unit FireFX_GPU;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 一体化したピクセルシェーダーをAviUtl2のD3D11 APIで実行する。

interface

uses AviUtl2FilterTypes, FireFX_Field;

// 成功時は現在のオブジェクト画像をGPU上で更新する。
// ホストから借りるリソースはフィルター処理内だけで使用する。
function RenderFireGPU(Video: PFILTER_PROC_VIDEO; var Scene: TFireScene): Boolean;

implementation

uses Winapi.Windows, System.SysUtils, System.SyncObjs, System.Math;

const
  SHADER_RESOURCE_ID = 101;
  BACKGROUND_RESOURCE = 'resource:SYNC_FireFX.Background';
  D3DCOMPILE_OPTIMIZATION_LEVEL3 = 1 shl 15;
  LOAD_LIBRARY_SEARCH_SYSTEM32 = $00000800;
  OBJECT_FLAG_CAMERA_TARGET = 4;

type
  ID3DBlob = interface(IUnknown)
    ['{8BA5FB08-5195-40E2-AC58-0D989C3A0102}']
    function GetBufferPointer: Pointer; stdcall;
    function GetBufferSize: NativeUInt; stdcall;
  end;
  TD3DCompile = function(Src: Pointer; SrcSize: NativeUInt; SourceName: PAnsiChar;
    Defines, Include: Pointer; Entry, Target: PAnsiChar; Flags1, Flags2: Cardinal;
    out Code, Errors: ID3DBlob): HRESULT; stdcall;

var
  ShaderLock: TLightweightMREW;
  CompiledShader: TBytes;
  CompilationTried: Boolean;

function CompileShader: TBytes;
var
  Resource: HRSRC;
  Handle: HGLOBAL;
  Source: Pointer;
  Size: Cardinal;
  CompilerModule: HMODULE;
  Compile: TD3DCompile;
  Code, Errors: ID3DBlob;
begin
  Result := nil;
  Resource := FindResource(HInstance, PWideChar(SHADER_RESOURCE_ID), RT_RCDATA);
  if Resource = 0 then Exit;
  Size := SizeofResource(HInstance, Resource);
  Handle := LoadResource(HInstance, Resource);
  Source := LockResource(Handle);
  if (Source = nil) or (Size = 0) then Exit;
  CompilerModule := LoadLibraryEx('d3dcompiler_47.dll', 0, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if CompilerModule = 0 then Exit;
  try
    Compile := TD3DCompile(GetProcAddress(CompilerModule, 'D3DCompile'));
    if not Assigned(Compile) then Exit;
    if Failed(Compile(Source, Size, 'SYNC_FireFX', nil, nil, 'psmain', 'ps_5_0',
      D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, Code, Errors)) then
    begin
      if Assigned(Errors) then OutputDebugStringA(PAnsiChar(Errors.GetBufferPointer));
      Exit;
    end;
    SetLength(Result, Code.GetBufferSize);
    Move(Code.GetBufferPointer^, Result[0], Length(Result));
  finally
    Code := nil;
    Errors := nil;
    FreeLibrary(CompilerModule);
  end;
end;

function ShaderBytes: TBytes;
begin
  ShaderLock.BeginRead;
  try
    if CompilationTried then Exit(CompiledShader);
  finally
    ShaderLock.EndRead;
  end;
  ShaderLock.BeginWrite;
  try
    if not CompilationTried then
    begin
      CompiledShader := CompileShader;
      CompilationTried := True;
    end;
    Result := CompiledShader;
  finally
    ShaderLock.EndWrite;
  end;
end;

function PrepareBackground(Video: PFILTER_PROC_VIDEO; var Scene: TFireScene): Boolean;
var
  P: TOBJECT_IMAGE_PARAM;
  W, H: Integer;
  Angle, AX, AY, BX, BY: Single;
begin
  Result := False;
  if (Scene.HazeParams.Y <= 0) or
    ((Video^.Object_^.Flag and OBJECT_FLAG_CAMERA_TARGET) <> 0) or
    not Assigned(Video^.CopyImageResource) or not Assigned(Video^.GetOutputImageParam) or
    not Assigned(Video^.GetImageResourceSize) then Exit;
  if not Video^.GetOutputImageParam(nil, 0, @P, SizeOf(P)) then Exit;
  if (Abs(P.RX) > 0.01) or (Abs(P.RY) > 0.01) or (Abs(P.CX) > 0.01) or
    (Abs(P.CY) > 0.01) or (P.SX <= 0) or (P.SY <= 0) then Exit;
  if not Video^.CopyImageResource(BACKGROUND_RESOURCE, 'framebuffer') then Exit;
  if not Video^.GetImageResourceSize(BACKGROUND_RESOURCE, @W, @H) or (W < 2) or (H < 2) then Exit;
  Angle := DegToRad(P.RZ);
  AX := Cos(Angle)*P.SX;
  AY := -Sin(Angle)*P.SY;
  BX := Sin(Angle)*P.SX;
  BY := Cos(Angle)*P.SY;
  Scene.BackgroundX := Vector(AX, AY,
    W*0.5+P.X-AX*Scene.Info.Z*0.5-AY*Scene.Info.W*0.5, W);
  Scene.BackgroundY := Vector(BX, BY,
    H*0.5+P.Y-BX*Scene.Info.Z*0.5-BY*Scene.Info.W*0.5, H);
  Scene.HazeParams.X := 1;
  Result := True;
end;

function RenderFireGPU(Video: PFILTER_PROC_VIDEO; var Scene: TFireScene): Boolean;
var
  Code: TBytes;
  Resources: PPWideChar;
  Background: PWideChar;
  ResourceCount: Integer;
begin
  Result := False;
  if not Assigned(Video^.ExecPixelshaderData) then Exit;
  Code := ShaderBytes;
  if Length(Code) = 0 then Exit;
  Scene.HazeParams.X := 0;
  ResourceCount := 0;
  Resources := nil;
  if PrepareBackground(Video, Scene) then
  begin
    Background := BACKGROUND_RESOURCE;
    ResourceCount := 1;
    Resources := @Background;
  end;
  Video^.SetImageData(nil, Trunc(Scene.Info.Z), Trunc(Scene.Info.W));
  Result := Video^.ExecPixelshaderData(@Code[0], Length(Code), nil, Resources,
    ResourceCount, @Scene, SizeOf(Scene), nil, nil);
end;

end.
