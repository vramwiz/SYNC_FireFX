program FireFX_RenderTests;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 本番AUF2をロードし、AviUtl2のコールバック境界とD3D11の描画を検査する。

{$APPTYPE CONSOLE}
{$POINTERMATH ON}

uses
  Winapi.Windows, Winapi.D3D11, Winapi.D3DCommon, Winapi.D3DCompiler, Winapi.DXGI,
  Winapi.DXGIFormat, System.SysUtils, System.Math, System.Generics.Collections,
  System.Diagnostics, Vcl.Graphics, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  FireFX_Field in '..\Source\Common\FireFX_Field.pas',
  FireFX_Settings in '..\Source\Common\FireFX_Settings.pas';

type
  TRequiredVersion = function: Cardinal; cdecl;
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TUninitialize = procedure; cdecl;
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  PSelectOption = ^TFILTER_ITEM_SELECT_ITEM;
  TImageStats = record
    Alpha, Blue, Red: Int64;
    X: Double;
  end;

const
  W = 720;
  H = 520;
  VertexSource: AnsiString = 'float4 main(uint id:SV_VertexID):SV_Position {'+
    'float2 p=float2((id<<1)&2,id&2); return float4(p*float2(2,-2)+float2(-1,1),0,1); }';

var
  Table: PFILTER_PLUGIN_TABLE;
  Items: TDictionary<string, Pointer>;
  Scene: TSCENE_INFO;
  Obj: TOBJECT_INFO;
  Video: TFILTER_PROC_VIDEO;
  Edit: TEDIT_SECTION;
  ImageParam: TOBJECT_IMAGE_PARAM;
  Output: TFirePixels;
  SavedValue: UTF8String;
  Preset: PFILTER_ITEM_SELECT;
  Button: PFILTER_ITEM_BUTTON;
  ApplyTarget, FailureItem, OutputPath: string;
  CopyCalls, GPUCalls, CPUCalls, ShaderFieldCount, TimelineMode: Integer;
  Device: ID3D11Device;
  Context: ID3D11DeviceContext;
  VertexShader: ID3D11VertexShader;
  PixelShader: ID3D11PixelShader;
  DriverLabel: string;

procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then raise Exception.Create(Message);
end;

procedure CheckHR(Value: HRESULT; const Message: string);
begin
  Check(Succeeded(Value), Message+' (0x'+IntToHex(Cardinal(Value), 8)+')');
end;

procedure CheckShaderResource(Module: HMODULE);
var
  Info: HRSRC;
  Resource: Pointer;
  Code, Errors: ID3DBlob;
begin
  Info := FindResource(Module, PWideChar(101), RT_RCDATA);
  Check(Info <> 0, 'embedded HLSL resource');
  Resource := LockResource(LoadResource(Module, Info));
  Check(Resource <> nil, 'embedded HLSL bytes');
  if Failed(D3DCompile(Resource, SizeofResource(Module, Info), nil, nil,
    nil, 'psmain', 'ps_5_0', 0, 0, Code, Errors)) then
  begin
    if Errors <> nil then Writeln(string(AnsiString(PAnsiChar(Errors.GetBufferPointer))));
    raise Exception.Create('embedded shader did not compile');
  end;
end;

function ItemKind(Item: Pointer): string;
begin
  Result := PPWideChar(Item)^;
end;

function ChoiceItem(Selector: PFILTER_ITEM_SELECT; I: Integer): PSelectOption;
begin
  Result := PSelectOption(Selector.List);
  Inc(Result, I);
end;

function ItemNamed(const Name: string): Pointer;
begin
  Result := Items[Name];
end;

procedure SetTrack(Track: TFireTrack; Value: Double);
begin
  PFILTER_ITEM_TRACK(ItemNamed(FIRE_TRACKS[Track].Name)).Value := Value;
end;

function GetValue(Handle: OBJECT_HANDLE; Effect, Item: LPCWSTR): PAnsiChar; cdecl;
var
  P: Pointer;
  Kind: string;
  Color: PFILTER_ITEM_COLOR;
begin
  Result := nil;
  if not Items.TryGetValue(Item, P) then Exit;
  Kind := ItemKind(P);
  if Kind = 'track' then
    SavedValue := UTF8String(FloatToStr(PFILTER_ITEM_TRACK(P).Value, TFormatSettings.Invariant))
  else if Kind = 'select' then
    SavedValue := UTF8String(string(ChoiceItem(P, PFILTER_ITEM_SELECT(P).Value).Name))
  else if Kind = 'check' then
    SavedValue := UTF8String(IntToStr(PFILTER_ITEM_CHECK(P).Value))
  else if Kind = 'color' then
  begin
    Color := P;
    SavedValue := UTF8String(IntToHex(Color.R, 2)+IntToHex(Color.G, 2)+IntToHex(Color.B, 2));
  end
  else Exit;
  Result := PAnsiChar(SavedValue);
end;

function SetValue(Handle: OBJECT_HANDLE; Effect, Item: LPCWSTR; Value: PAnsiChar): Boolean; cdecl;
var
  P: Pointer;
  Kind, ValueText: string;
  I, Color: Integer;
begin
  Result := False;
  if (string(Effect) <> ApplyTarget) or (string(Item) = FailureItem) or
    not Items.TryGetValue(Item, P) then Exit;
  Kind := ItemKind(P);
  ValueText := string(UTF8String(Value));
  if Kind = 'track' then
    PFILTER_ITEM_TRACK(P).Value := StrToFloat(ValueText, TFormatSettings.Invariant)
  else if Kind = 'select' then
  begin
    I := 0;
    while ChoiceItem(P, I).Name <> nil do
    begin
      if ValueText = string(ChoiceItem(P, I).Name) then
      begin
        PFILTER_ITEM_SELECT(P).Value := ChoiceItem(P, I).Value;
        Exit(True);
      end;
      Inc(I);
    end;
    Exit;
  end
  else if Kind = 'check' then
    PFILTER_ITEM_CHECK(P).Value := StrToInt(ValueText)
  else if Kind = 'color' then
  begin
    Color := StrToInt('$'+ValueText);
    PFILTER_ITEM_COLOR(P).R := Byte(Color shr 16);
    PFILTER_ITEM_COLOR(P).G := Byte(Color shr 8 and 255);
    PFILTER_ITEM_COLOR(P).B := Byte(Color and 255);
  end
  else Exit;
  Result := True;
end;

procedure Apply(Index: Integer);
begin
  Preset.Value := Index;
  Button.Callback2(@Edit, @Obj, PWideChar(ApplyTarget), Button.Name);
end;

function FindObject(Layer, Frame: Integer): OBJECT_HANDLE; cdecl;
begin
  Result := nil;
  if (Layer = Obj.Layer) and (Frame >= Obj.FrameS) and (Frame <= Obj.FrameE) then Result := @Obj;
end;

function ReadPower(Handle: OBJECT_HANDLE; Effect, Item: LPCWSTR; Frame: Double;
  Value: PDouble): Boolean; cdecl;
begin
  Result := (Handle = @Obj) and (string(Effect) = FIRE_EFFECT_NAME) and (string(Item) = '火力');
  if not Result then Exit;
  Frame := Frame-Obj.FrameS;
  case TimelineMode of
    1: Value^ := EnsureRange((Frame-30)*(-100/30), 0, 100);
    2: Value^ := EnsureRange(0.75-Frame*0.04, 0, 150);
    3: Result := False;
  else
    Value^ := PFILTER_ITEM_TRACK(ItemNamed('火力')).Value;
  end;
end;

procedure SetImage(Buffer: PPIXEL_RGBA; Width, Height: Integer); cdecl;
begin
  Check((Width = Scene.Width) and (Height = Scene.Height), 'scene-sized output');
  if Buffer <> nil then
  begin
    Inc(CPUCalls);
    SetLength(Output, Width*Height);
    Move(Buffer^, Output[0], Width*Height*SizeOf(TPIXEL_RGBA));
  end;
end;

function OutputTransform(Handle: OBJECT_HANDLE; Offset: Double; P: POBJECT_IMAGE_PARAM;
  ParamSize: Integer): Boolean; cdecl;
begin
  Result := ParamSize = SizeOf(P^);
  if Result then
  begin
    P^ := Default(TOBJECT_IMAGE_PARAM);
    P^.SX := 1;
    P^.SY := 1;
    P^.SZ := 1;
    P^.Alpha := 1;
  end;
end;

function CopyBackground(Dest, Src: LPCWSTR): Boolean; cdecl;
begin
  Inc(CopyCalls);
  Result := (string(Src) = 'framebuffer') and (string(Dest) = 'resource:SYNC_FireFX.Background');
end;

function BackgroundSize(Name: LPCWSTR; Width, Height: PInteger): Boolean; cdecl;
begin
  Width^ := Scene.Width;
  Height^ := Scene.Height;
  Result := True;
end;

procedure StartGPU;
var
  Level: D3D_FEATURE_LEVEL;
  VsCode, Errors: ID3DBlob;
begin
  DriverLabel := 'hardware';
  if Failed(D3D11CreateDevice(nil, D3D_DRIVER_TYPE_HARDWARE, 0, 0,
    nil, 0, D3D11_SDK_VERSION, Device, Level, Context)) then
  begin
    DriverLabel := 'WARP';
    CheckHR(D3D11CreateDevice(nil, D3D_DRIVER_TYPE_WARP, 0, 0,
      nil, 0, D3D11_SDK_VERSION, Device, Level, Context), 'D3D11 device');
  end;
  CheckHR(D3DCompile(PAnsiChar(VertexSource), Length(VertexSource), nil, nil,
    nil, 'main', 'vs_5_0', 0, 0, VsCode, Errors), 'vertex shader compile');
  CheckHR(Device.CreateVertexShader(VsCode.GetBufferPointer, VsCode.GetBufferSize,
    nil, @VertexShader), 'vertex shader create');
end;

function ExecShader(Code: PByte; CodeSize: Integer; Target: LPCWSTR; Resources: PPWideChar;
  ResourceCount: Integer; Constants: Pointer; ConstantSize: Integer;
  BlendState, SamplerState: Pointer): Boolean; cdecl;
var
  TargetTexture, Staging, Background: ID3D11Texture2D;
  TargetView: ID3D11RenderTargetView;
  BackgroundView: ID3D11ShaderResourceView;
  Buffer: ID3D11Buffer;
  Desc: D3D11_TEXTURE2D_DESC;
  BufferDesc: D3D11_BUFFER_DESC;
  Data: D3D11_SUBRESOURCE_DATA;
  Viewport: D3D11_VIEWPORT;
  Mapped: D3D11_MAPPED_SUBRESOURCE;
  Pattern: TFirePixels;
  X, Y: Integer;
  Shade: Byte;
begin
  Result := False;
  try
    Inc(GPUCalls);
    Check((CodeSize > 4) and (PCardinal(Code)^ = $43425844), 'embedded D3D shader bytecode');
    Check(ConstantSize = SizeOf(TFireScene), 'constant buffer size');
    ShaderFieldCount := Trunc(PFireScene(Constants).Info.X);
    if PixelShader = nil then
      CheckHR(Device.CreatePixelShader(Code, CodeSize, nil, PixelShader), 'pixel shader create');
    Desc := Default(D3D11_TEXTURE2D_DESC);
    Desc.Width := Scene.Width;
    Desc.Height := Scene.Height;
    Desc.MipLevels := 1;
    Desc.ArraySize := 1;
    Desc.Format := DXGI_FORMAT_R8G8B8A8_UNORM;
    Desc.SampleDesc.Count := 1;
    Desc.Usage := D3D11_USAGE_DEFAULT;
    Desc.BindFlags := D3D11_BIND_RENDER_TARGET;
    CheckHR(Device.CreateTexture2D(Desc, nil, TargetTexture), 'shader output texture');
    CheckHR(Device.CreateRenderTargetView(TargetTexture, nil, TargetView), 'shader output view');
    if ResourceCount > 0 then
    begin
      Check((ResourceCount = 1) and (string(Resources^) = 'resource:SYNC_FireFX.Background'),
        'framebuffer texture binding');
      SetLength(Pattern, Scene.Width*Scene.Height);
      for Y := 0 to Scene.Height-1 do
        for X := 0 to Scene.Width-1 do
        begin
          Shade := 25+((X div 5 + Y div 5) and 1)*190;
          Pattern[Y*Scene.Width+X].R := Shade;
          Pattern[Y*Scene.Width+X].G := Shade;
          Pattern[Y*Scene.Width+X].B := Shade;
          Pattern[Y*Scene.Width+X].A := 255;
        end;
      Desc.BindFlags := D3D11_BIND_SHADER_RESOURCE;
      Data := Default(D3D11_SUBRESOURCE_DATA);
      Data.pSysMem := @Pattern[0];
      Data.SysMemPitch := Scene.Width*SizeOf(TPIXEL_RGBA);
      CheckHR(Device.CreateTexture2D(Desc, @Data, Background), 'background texture');
      CheckHR(Device.CreateShaderResourceView(Background, nil, BackgroundView), 'background view');
    end;
    Desc.Usage := D3D11_USAGE_STAGING;
    Desc.BindFlags := 0;
    Desc.CPUAccessFlags := D3D11_CPU_ACCESS_READ;
    CheckHR(Device.CreateTexture2D(Desc, nil, Staging), 'readback texture');
    BufferDesc := Default(D3D11_BUFFER_DESC);
    BufferDesc.ByteWidth := ConstantSize;
    BufferDesc.Usage := D3D11_USAGE_IMMUTABLE;
    BufferDesc.BindFlags := D3D11_BIND_CONSTANT_BUFFER;
    Data := Default(D3D11_SUBRESOURCE_DATA);
    Data.pSysMem := Constants;
    CheckHR(Device.CreateBuffer(BufferDesc, @Data, Buffer), 'shader constants');
    Viewport := Default(D3D11_VIEWPORT);
    Viewport.Width := Scene.Width;
    Viewport.Height := Scene.Height;
    Viewport.MaxDepth := 1;
    Context.RSSetViewports(1, @Viewport);
    Context.IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    Context.OMSetRenderTargets(1, TargetView, nil);
    Context.VSSetShader(VertexShader, nil, 0);
    Context.PSSetShader(PixelShader, nil, 0);
    Context.PSSetConstantBuffers(0, 1, Buffer);
    Context.PSSetShaderResources(0, 1, BackgroundView);
    Context.Draw(3, 0);
    Context.OMSetRenderTargets(0, TargetView, nil);
    Context.CopyResource(Staging, TargetTexture);
    CheckHR(Context.Map(Staging, 0, D3D11_MAP_READ, 0, Mapped), 'shader readback map');
    try
      SetLength(Output, Scene.Width*Scene.Height);
      for Y := 0 to Scene.Height-1 do
        Move((PByte(Mapped.pData)+Y*Integer(Mapped.RowPitch))^,
          Output[Y*Scene.Width], Scene.Width*SizeOf(TPIXEL_RGBA));
    finally
      Context.Unmap(Staging, 0);
    end;
    Result := True;
  except
    on E: Exception do Writeln('D3D callback: ', E.Message);
  end;
end;

function Render(Frame: Integer; Power: Double): TImageStats;
var
  I: Integer;
  Pixel: TPIXEL_RGBA;
  SavedParam: TOBJECT_IMAGE_PARAM;
begin
  Result := Default(TImageStats);
  Obj.Frame := Frame;
  Obj.Time := Frame/Scene.Rate;
  SetTrack(ftPower, Power);
  SavedParam := ImageParam;
  Check(Table.Func_Proc_Video(@Video) <> 0, 'render callback');
  Check(CompareMem(@SavedParam, @ImageParam, SizeOf(ImageParam)), 'host placement parameters preserved');
  for I := 0 to High(Output) do
  begin
    Pixel := Output[I];
    Inc(Result.Alpha, Pixel.A);
    Inc(Result.Blue, Pixel.B*Pixel.A);
    Inc(Result.Red, Pixel.R*Pixel.A);
    Result.X := Result.X+(I mod Scene.Width)*Pixel.A;
  end;
  if Result.Alpha > 0 then Result.X := Result.X/Result.Alpha;
end;

procedure Preview(const FileName: string; GPU: Boolean);
var
  Bitmap: TBitmap;
  PNG: TPngImage;
  Row: PByte;
  X, Y, I: Integer;
  P: TPIXEL_RGBA;
begin
  Bitmap := TBitmap.Create;
  PNG := TPngImage.Create;
  try
    Bitmap.PixelFormat := pf24bit;
    Bitmap.SetSize(Scene.Width, Scene.Height);
    for Y := 0 to Scene.Height-1 do
    begin
      Row := Bitmap.ScanLine[Y];
      for X := 0 to Scene.Width-1 do
      begin
        I := Y*Scene.Width+X;
        P := Output[I];
        if GPU then
        begin
          Row[X*3] := P.B;
          Row[X*3+1] := P.G;
          Row[X*3+2] := P.R;
        end
        else
        begin
          Row[X*3] := P.B*P.A div 255;
          Row[X*3+1] := P.G*P.A div 255;
          Row[X*3+2] := P.R*P.A div 255;
        end;
      end;
    end;
    PNG.Assign(Bitmap);
    PNG.SaveToFile(IncludeTrailingPathDelimiter(OutputPath)+FileName+'.png');
  finally
    PNG.Free;
    Bitmap.Free;
  end;
end;

procedure TestCPU;
var
  Base, Other: TImageStats;
  Image: TFirePixels;
  I, J: Integer;
  PresetAlpha: array[TFirePreset] of Int64;
  PresetValue: TFirePreset;
begin
  Base := Render(17, 100);
  Check((Base.Alpha > 100000) and (Base.Red > Base.Blue) and (Output[0].A = 0), 'initial candle');
  Image := Copy(Output);
  Check(Render(32, 100).Alpha <> Base.Alpha, 'time-varying flame');
  Render(17, 100);
  Check(CompareMem(@Image[0], @Output[0], Length(Image)*4), 'seek determinism');
  Check(Render(0, 0).Alpha = 0, 'fully extinguished initial frame');
  Other := Render(0, 1);
  PFILTER_ITEM_SELECT(ItemNamed('点火方式')).Value := Ord(fiInstant);
  Check(Render(0, 1).Alpha > Other.Alpha, 'instant ignition skips the local flame ramp');
  Apply(Ord(fpCandle));
  Preset.Value := Ord(fpStove);
  Check(Render(17, 100).Alpha = Base.Alpha, 'selector alone preserves settings');
  FailureItem := '発光強度';
  Apply(Ord(fpStove));
  FailureItem := '';
  Check(PFILTER_ITEM_SELECT(ItemNamed('配置方式')).Value = Ord(flSingle), 'preset rollback');
  Apply(Ord(fpStove));
  Other := Render(0, 100);
  Check((Other.Blue > Other.Red) and (Abs(Other.X-(Scene.Width-1)*0.5) < 10),
    'blue ring centered in the generated image');

  Scene.Height := H*2;
  for PresetValue := Low(TFirePreset) to High(TFirePreset) do
  begin
    Apply(Ord(PresetValue));
    Base := Render(25, 100);
    Check(Base.Alpha > 1000, 'active preset '+IntToStr(Ord(PresetValue)));
    PresetAlpha[PresetValue] := Base.Alpha;
    Preview(Format('preset-%.2d', [Ord(PresetValue)]), False);
  end;
  Scene.Height := H;
  for I := 0 to Ord(High(TFirePreset)) do
    for J := I+1 to Ord(High(TFirePreset)) do
      Check(PresetAlpha[TFirePreset(I)] <> PresetAlpha[TFirePreset(J)], 'distinct preset images');

  Apply(Ord(fpStove));
  Check(Render(0, 0.74).Alpha > 0, 'ignition spark burst');
  Base := Render(0, 1);
  Other := Render(0, 1.55);
  Check((Base.Alpha > 0) and (Other.Alpha > Base.Alpha) and
    (Render(0, 2).Alpha > Other.Alpha), 'ordered stove ignition');
  TimelineMode := 2;
  Check(Render(0, 0.75).Alpha = 0, 'no ignition sparks while cooling through the ignition range');
  TimelineMode := 3;
  Check(Render(0, 0.75).Alpha = 0, 'unknown track direction suppresses ignition sparks');
  TimelineMode := 1;
  Check(Render(30, 0).Alpha = 0, 'completely extinguished stove');
  Apply(Ord(fpCandle));
  Check(Render(36, 0).Alpha > 1000, 'extinction smoke after power reaches zero');
  Image := Copy(Output);
  Preview('extinction-smoke', False);
  Check(Render(140, 0).Alpha = 0, 'expired smoke');
  Render(36, 0);
  Check(CompareMem(@Image[0], @Output[0], Length(Image)*4), 'smoke seek determinism');
  Apply(Ord(fpCharcoal));
  Check(Render(60, 0).Alpha > 0, 'remaining embers');
  Check(Render(370, 0).Alpha = 0, 'expired embers');
  TimelineMode := 0;

  Apply(Ord(fpStove));
  Base := Render(25, 100);
  PFILTER_ITEM_SELECT(ItemNamed('干渉形状')).Value := Ord(foRound);
  SetTrack(ftObstacleY, -21);
  SetTrack(ftObstacleWidth, 168);
  SetTrack(ftObstacleDepth, 172);
  SetTrack(ftWrap, 0);
  Check(Render(25, 100).Alpha < Base.Alpha, 'obstacle collision');
  Base := Render(25, 100);
  SetTrack(ftWrap, 120);
  Check(Render(25, 100).Alpha > Base.Alpha, 'obstacle deflection');
  Preview('stove-obstacle', False);
  Writeln('CPU: defaults, 12 presets, controls, seek, ignition, smoke, embers, collision passed');
end;

procedure TestGPU;
var
  CPU, GPU: TImageStats;
  Before, I, Undistorted, Shifted: Integer;
  Timer: TStopwatch;
begin
  StartGPU;
  Apply(Ord(fpStove));
  CPU := Render(19, 100);
  Before := CPUCalls;
  Video.ExecPixelshaderData := ExecShader;
  GPU := Render(19, 100);
  Check((CPUCalls = Before) and (GPUCalls = 1) and (ShaderFieldCount >= 24),
    Format('active GPU render path (CPU delta %d, GPU %d, fields %d)',
      [CPUCalls-Before, GPUCalls, ShaderFieldCount]));
  Check(Abs(CPU.Alpha-GPU.Alpha) < CPU.Alpha*0.018, 'CPU/GPU alpha matches');
  Preview('stove-gpu', True);
  Apply(Ord(fpCandle));
  SetTrack(ftDensity, 0);
  Video.CopyImageResource := CopyBackground;
  Video.GetImageResourceSize := BackgroundSize;
  Video.GetOutputImageParam := OutputTransform;
  Check((Render(19, 100).Alpha = 0) and (CopyCalls = 0), 'disabled haze bypasses the framebuffer');
  PFILTER_ITEM_CHECK(ItemNamed('陽炎を有効にする')).Value := 1;
  SetTrack(ftHazeStrength, 135);
  Check((Render(19, 100).Alpha > 10000) and (CopyCalls = 1), 'haze with real texture samples');
  Shifted := 0;
  for I := 0 to High(Output) do
  begin
    Undistorted := 25+((I mod Scene.Width div 5 + I div Scene.Width div 5) and 1)*190;
    if (Output[I].A > 60) and
      (Abs(Output[I].R-Undistorted*Output[I].A/255) > 5) then Inc(Shifted);
  end;
  Check(Shifted > 100, 'haze displaces the checkerboard samples');
  Preview('haze-gpu', True);
  Check(CPUCalls = Before, 'GPU test frames did not fall back');
  Writeln('GPU (', DriverLabel, '): shader, CPU parity, framebuffer haze passed');

  if ParamStr(3) = '--benchmark' then
  begin
    Scene.Width := 1920;
    Scene.Height := 1080;
    Apply(Ord(fpBlaze));
    Video.ExecPixelshaderData := nil;
    Timer := TStopwatch.StartNew;
    for I := 1 to 10 do
    begin
      Obj.Time := I/30;
      Check(Table.Func_Proc_Video(@Video) <> 0, 'CPU benchmark');
    end;
    Writeln(Format('CPU blaze 1080p: %.1f ms/frame', [Timer.Elapsed.TotalMilliseconds/10]));
    Video.ExecPixelshaderData := ExecShader;
    Timer := TStopwatch.StartNew;
    for I := 1 to 10 do
    begin
      Obj.Time := I/30;
      Check(Table.Func_Proc_Video(@Video) <> 0, 'GPU benchmark');
    end;
    Writeln(Format('GPU blaze 1080p including readback: %.1f ms/frame', [Timer.Elapsed.TotalMilliseconds/10]));
  end;
end;

procedure Run;
var
  Module: HMODULE;
  Required: TRequiredVersion;
  Initialize: TInitialize;
  Uninitialize: TUninitialize;
  GetTable: TGetTable;
  P: Pointer;
  Name, Kind: string;
  I, Groups: Integer;
begin
  OutputPath := ParamStr(2);
  Module := LoadLibrary(PWideChar(ParamStr(1)));
  Check(Module <> 0, 'load production AUF2');
  try
    CheckShaderResource(Module);
    Required := TRequiredVersion(GetProcAddress(Module, 'RequiredVersion'));
    Initialize := TInitialize(GetProcAddress(Module, 'InitializePlugin'));
    Uninitialize := TUninitialize(GetProcAddress(Module, 'UninitializePlugin'));
    GetTable := TGetTable(GetProcAddress(Module, 'GetFilterPluginTable'));
    Check(Assigned(Required) and Assigned(Initialize) and Assigned(Uninitialize) and Assigned(GetTable),
      'four SDK exports');
    Check((Required() = 2011600) and (Initialize(2011500) = 0) and (Initialize(Required()) <> 0),
      'version gate');
    Table := GetTable;
    Check((Table <> nil) and (string(Table.Name) = FIRE_EFFECT_NAME) and (string(Table.Label_) = 'SYNC') and
      (Table.Flag = FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA) and
      not Assigned(Table.Func_Proc_Audio), 'standalone media object registration');
    Items := TDictionary<string, Pointer>.Create;
    try
      Groups := 0;
      for I := 0 to 127 do
      begin
        P := PPointer(Table.Items)[I];
        if P = nil then Break;
        Kind := ItemKind(P);
        Name := PFILTER_ITEM_TRACK(P).Name;
        if Kind = 'group' then
        begin
          Check(Name <> '基本設定', 'base placement group is absent');
          if Name <> '' then Inc(Groups);
        end
        else Items.Add(Name, P);
      end;
      Check((I < 128) and (Groups = 13), '13 closed groups and terminator');
      Check(not (Items.ContainsKey('X') or Items.ContainsKey('Y') or Items.ContainsKey('Z') or
        Items.ContainsKey('拡大率') or Items.ContainsKey('透明度')), 'base placement items are absent');
      Preset := ItemNamed('プリセット選択');
      Button := ItemNamed('設定');
      Check((Preset.Value = 0) and (ChoiceItem(Preset, 12).Name = nil), '12 preset choices');
      Check(PFILTER_ITEM_TRACK(ItemNamed('火力')).Step = 0.01, 'power step');
      Check(Table.Func_Proc_Video(nil) = 0, 'invalid callback rejected');
      Scene.Width := W;
      Scene.Height := H;
      Scene.Rate := 30;
      Scene.Scale := 1;
      Obj.Layer := 3;
      Obj.FrameS := 19;
      Obj.FrameE := 519;
      Edit.FindObject := FindObject;
      Edit.GetObjectTrackValue := ReadPower;
      Edit.GetObjectItemValue := GetValue;
      Edit.SetObjectItemValue := SetValue;
      Video.Scene := @Scene;
      Video.Object_ := @Obj;
      Video.Edit := @Edit;
      Video.Param := @ImageParam;
      ImageParam.X := 108;
      ImageParam.Y := 65;
      ImageParam.Z := 13;
      ImageParam.SX := 0.81;
      ImageParam.SY := 0.81;
      ImageParam.Alpha := 0.86;
      Video.SetImageData := SetImage;
      Video.UserData := Table.Func_Create(1);
      Check(Video.UserData <> nil, 'effect userdata');
      ApplyTarget := FIRE_EFFECT_NAME+':0';
      try
        TestCPU;
        TestGPU;
      finally
        Table.Func_Destroy(1, Video.UserData);
      end;
    finally
      Items.Free;
      Uninitialize;
    end;
  finally
    FreeLibrary(Module);
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
