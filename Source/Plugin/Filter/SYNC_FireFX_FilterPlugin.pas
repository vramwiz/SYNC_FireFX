unit SYNC_FireFX_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// メディアオブジェクトを登録し、タイムラインと描画資源を結び付ける。

interface

uses AviUtl2FilterTypes;

const
  FIREFX_REQUIRED_VERSION = 2011600;

// DLL所有の登録テーブルを返す。呼出側で解放しない。
function GetFireFXFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses System.SysUtils, System.Math, System.SyncObjs, Winapi.Windows, PluginFilterTable,
  FireFX_Settings, FireFX_Parameters, FireFX_Field, FireFX_Scene, FireFX_GPU;

type
  TFireSession = class
  private
    FLock: TCriticalSection;
    FScene: TFireScene;
    FPixels, FScratch: TFirePixels;
  public
    constructor Create;
    destructor Destroy; override;
    // ホストの画像と編集APIをコールバックの間だけ借用する。
    function Render(Video: PFILTER_PROC_VIDEO): Byte;
  end;

var
  TableInitialized: Boolean;

function ReadActivity(Video: PFILTER_PROC_VIDEO; const S: TFireSettings): TFireActivity;
var
  Edit: PEDIT_SECTION;
  Info: POBJECT_INFO;
  Obj: OBJECT_HANDLE;
  Frame, Fps, Power, Prev, Next, Age, Duration: Double;
  SmokeEnabled, EmberEnabled, WantSmoke, WantEmbers: Boolean;

  function ReadPower(AtFrame: Double; out Value: Double): Boolean;
  begin
    Result := Edit^.GetObjectTrackValue(Obj, FIRE_EFFECT_NAME, FIRE_TRACKS[ftPower].Name,
      EnsureRange(AtFrame, Double(Info^.FrameS), Double(Info^.FrameE)), @Value);
    if Result then Value := ClampFireTrack(ftPower, Value);
  end;

  function PriorCrossing(Threshold, Seconds: Double; out SecondsAgo: Double): Boolean;
  var
    I, Search: Integer;
    Tested, Later, Earlier, SampleFrame, Sample: Double;
  begin
    Result := False;
    Seconds := Min(Seconds, (Frame-Info^.FrameS)/Fps);
    if Seconds <= 0 then Exit;
    Later := Frame;
    for I := 1 to 24 do
    begin
      Tested := Frame-Sqr(I/24)*Seconds*Fps;
      if not ReadPower(Tested, Sample) then Exit;
      if Sample >= Threshold then
      begin
        Earlier := Tested;
        for Search := 1 to 8 do
        begin
          SampleFrame := (Earlier+Later)*0.5;
          if not ReadPower(SampleFrame, Sample) then Break;
          if Sample >= Threshold then Earlier := SampleFrame else Later := SampleFrame;
        end;
        SecondsAgo := (Frame-(Earlier+Later)*0.5)/Fps;
        Exit(True);
      end;
      Later := Tested;
    end;
  end;

begin
  Result := Default(TFireActivity);
  Power := S.V[ftPower];
  SmokeEnabled := (S.Smoke in [fmExtinction, fmBoth]) and
    (S.V[ftSmokeAmount] > 0) and (S.V[ftSmokeLife] > 0);
  EmberEnabled := S.Embers and (S.V[ftEmberStrength] > 0) and (S.V[ftEmberLife] > 0);
  WantSmoke := SmokeEnabled and (Power < 1);
  WantEmbers := EmberEnabled and (Power < 1);
  if (Power >= 1) or ((Power = 0) and not WantSmoke and not WantEmbers) then Exit;
  if not WantSmoke and not WantEmbers and (S.Ignition in [fiInstant, fiSpread]) then Exit;
  Edit := Video^.Edit;
  Info := Video^.Object_;
  if (Edit = nil) or (Video^.Scene^.Rate <= 0) or (Video^.Scene^.Scale <= 0) or
    (Info^.FrameE < Info^.FrameS) or not Assigned(Edit^.FindObject) or
    not Assigned(Edit^.GetObjectTrackValue) then Exit;
  Fps := Video^.Scene^.Rate/Video^.Scene^.Scale;
  Frame := EnsureRange(Double(Info^.FrameS)+Info^.Frame, Double(Info^.FrameS), Double(Info^.FrameE));
  Obj := Edit^.FindObject(Info^.Layer, Floor(Frame));
  if Obj = nil then Exit;
  Prev := Power;
  Next := Power;
  if Frame > Info^.FrameS then
    if not ReadPower(Frame-0.5, Prev) then Exit;
  if Frame < Info^.FrameE then
    if not ReadPower(Frame+0.5, Next) then Exit;
  Result.SparkAllowed := True;
  Result.Falling := (Next < Power-0.001) or (Prev > Power+0.001);
  if (Next > Power+0.001) and (Prev <= Power+0.001) then Exit;
  Duration := 0.85;
  if WantSmoke then Duration := Max(Duration, S.V[ftSmokeLife]);
  if WantEmbers then Duration := Max(Duration, S.V[ftEmberLife]);
  if PriorCrossing(1, Duration, Age) then
  begin
    Result.Falling := True;
    if WantSmoke then
    begin
      Result.SmokeAge := Age;
      Result.SmokeResidual := System.Math.Power(1-Sat(Age/S.V[ftSmokeLife]), 1.45);
    end;
    if WantEmbers then
      Result.EmberResidual := 0.56*Sqr(1-Sat(Age/S.V[ftEmberLife]));
  end;
end;

constructor TFireSession.Create;
begin
  inherited;
  FLock := TCriticalSection.Create;
end;

destructor TFireSession.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TFireSession.Render(Video: PFILTER_PROC_VIDEO): Byte;
var
  W, H: Integer;
  Time: Double;
  Settings: TFireSettings;
  Activity: TFireActivity;
  Rendered: Boolean;
begin
  Result := 0;
  if (Video^.Scene = nil) or not Assigned(Video^.SetImageData) then Exit;
  W := Video^.Scene^.Width;
  H := Video^.Scene^.Height;
  if (W <= 0) or (H <= 0) or (W > FIRE_MAX_SIDE) or (H > FIRE_MAX_SIDE) or
    (Int64(W)*H > FIRE_MAX_PIXELS) then Exit;
  Time := Video^.Object_^.Time;
  if IsNan(Time) or IsInfinite(Time) then Exit;
  Settings := ReadFireSettings;
  Activity := ReadActivity(Video, Settings);
  FLock.Acquire;
  try
    BuildFireScene(Settings, Activity, W, H, EnsureRange(Time, 0.0, 864000.0), FScene);
    try
      Rendered := RenderFireGPU(Video, FScene);
    except
      on E: Exception do
      begin
        OutputDebugString(PWideChar('SYNC_FireFX GPU: ' + E.Message));
        Rendered := False;
      end;
    end;
    if not Rendered then
    begin
      RasterFire(FScene, W, H, FPixels, FScratch);
      Video^.SetImageData(@FPixels[0], W, H);
    end;
    Result := 1;
  finally
    FLock.Release;
  end;
end;

function ProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 0;
  if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
  try
    Result := TFireSession(Video^.UserData).Render(Video);
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_FireFX render: ' + E.Message));
  end;
end;

function CreateEffect(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TFireSession.Create;
  except
    // 失敗時はホストへnilを返す。
  end;
end;

procedure DestroyEffect(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TFireSession(UserData).Free;
  except
    // Delphi例外をホストに伝播させない。
  end;
end;

function GetFireFXFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not TableInitialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
      FIRE_EFFECT_NAME, 'SYNC', '火演出 / SYNC_FireFX v1.0.0', ProcVideo, nil);
    RegisterFireParameters;
    GetPluginTable^.Func_Create := CreateEffect;
    GetPluginTable^.Func_Destroy := DestroyEffect;
    TableInitialized := True;
  end;
  Result := GetPluginTable;
end;

end.
