unit FireFX_Field;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// D3D11とCPUで共通の火炎・粒子フィールドを定義し、CPUの代替描画を行う。

{$ALIGN 4}

interface

uses AviUtl2FilterTypes;

const
  FIRE_MAX_FIELDS = 480;
  FIRE_MAX_SIDE = 16384;
  FIRE_MAX_PIXELS = 33554432;
  FIRE_NO_CLIP = -1E8;

type
  TFirePixels = TArray<TPIXEL_RGBA>;
  TFireVector = record
    X, Y, Z, W: Single;
  end;
  TFireFieldKind = (fkFlame, fkSmoke, fkGlow, fkSpark, fkEmber);
  TFireField = record
    Bounds, Axis, Shape, Detail, Core, Middle, Outer, Clip: TFireVector;
  end;
  PFireScene = ^TFireScene;
  // 16バイト単位。Source/Shaders/FireFX.hlsl の定数バッファと同一の配置。
  TFireScene = record
    Info: TFireVector; // X=フィールド数、Y=予約、Z/W=描画サイズ
    Bounds, Haze, HazeParams, BackgroundX, BackgroundY: TFireVector;
    Fields: array[0..FIRE_MAX_FIELDS-1] of TFireField;
  end;

function Vector(X, Y, Z, W: Single): TFireVector; inline;
function RGBVector(Color: Cardinal; W: Single = 0): TFireVector; inline;
function Sat(Value: Single): Single; inline;
function Blend(A, B, T: Single): Single; inline;
function Smooth(A, B, Value: Single): Single; inline;
// 符号付きの格子座標と固定シードから、フレーム履歴に依存しない値を生成する。
function FireRandom(X, Y, Seed: Integer): Single;
function FireNoise(X, Y: Single; Seed: Integer): Single;

// 出力はSetImageDataへ渡すストレートαのRGBA。PixelsとScratchは呼出側が再利用する。
procedure RasterFire(const Scene: TFireScene; Width, Height: Integer;
  var Pixels, Scratch: TFirePixels);

implementation

uses System.Math;

function Vector(X, Y, Z, W: Single): TFireVector;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
  Result.W := W;
end;

function RGBVector(Color: Cardinal; W: Single): TFireVector;
begin
  Result := Vector((Color shr 16 and 255)/255, (Color shr 8 and 255)/255,
    (Color and 255)/255, W);
end;

function Sat(Value: Single): Single;
begin
  Result := EnsureRange(Value, 0.0, 1.0);
end;

function Blend(A, B, T: Single): Single;
begin
  Result := A + (B-A)*T;
end;

function Smooth(A, B, Value: Single): Single;
var
  T: Single;
begin
  T := Sat((Value-A)/(B-A));
  Result := T*T*(3-2*T);
end;

{$IFOPT Q+}{$DEFINE FIREFX_RESTORE_Q}{$ENDIF}
{$IFOPT R+}{$DEFINE FIREFX_RESTORE_R}{$ENDIF}
{$Q-}{$R-}
function FireRandom(X, Y, Seed: Integer): Single;
var
  Hash: Cardinal;
begin
  Hash := Cardinal(X)*$9E3779B1 xor Cardinal(Y)*$85EBCA77 xor Cardinal(Seed)*$C2B2AE3D;
  Hash := (Hash xor (Hash shr 16))*$7FEB352D;
  Hash := (Hash xor (Hash shr 15))*$846CA68B;
  Result := ((Hash xor (Hash shr 16)) shr 8)/16777216.0;
end;
{$IFDEF FIREFX_RESTORE_Q}{$Q+}{$UNDEF FIREFX_RESTORE_Q}{$ENDIF}
{$IFDEF FIREFX_RESTORE_R}{$R+}{$UNDEF FIREFX_RESTORE_R}{$ENDIF}

function FireNoise(X, Y: Single; Seed: Integer): Single;
var
  IX, IY: Integer;
  U, V: Single;
begin
  IX := Floor(X);
  IY := Floor(Y);
  U := X-IX;
  V := Y-IY;
  U := U*U*(3-2*U);
  V := V*V*(3-2*V);
  Result := Blend(Blend(FireRandom(IX, IY, Seed), FireRandom(IX+1, IY, Seed), U),
    Blend(FireRandom(IX, IY+1, Seed), FireRandom(IX+1, IY+1, Seed), U), V);
end;

function MixColor(const A, B: TFireVector; Weight: Single): TFireVector; inline;
begin
  Result := Vector(Blend(A.X, B.X, Weight), Blend(A.Y, B.Y, Weight),
    Blend(A.Z, B.Z, Weight), 0);
end;

function FlameAt(const F: TFireField; U, V: Single; Seed: Integer): TFireVector;
var
  Edge, Layer, Grain, Radius, Heat, Rim, Body, Core, Fade, Amplitude: Single;
begin
  Result := Default(TFireVector);
  if (V < -0.13) or (V > 1.12) then Exit;
  Amplitude := F.Detail.X;
  U := U - F.Shape.Y*4*V*(1-V);
  // 芯から太くなり、上部では風と上昇する渦に引き伸ばされる。
  Radius := (0.20 + 0.83*Smooth(-0.06, 0.22, V)) *
    (1 - Smooth(0.25, 1.10, V));
  if Abs(U) > Radius + 0.6 + Amplitude*0.55 then Exit;
  Edge := FireNoise(V*4.3-F.Shape.W*0.37, F.Middle.W, Seed)-0.5;
  U := U - Edge*Amplitude*Smooth(0.04, 0.92, V)*0.97;
  if Abs(U) > Radius + 0.52 then Exit;
  Grain := FireNoise(U*2.6, V*(4+F.Detail.Y*8)-F.Shape.W, Seed+17)-0.5;
  Layer := FireNoise(U*6.5+Grain, V*12.5-F.Shape.W*1.61, Seed+29)-0.5;
  Radius := Radius + (Grain*0.21 + Layer*0.09)*Amplitude;
  Rim := Abs(U);
  if F.Detail.Z > 0 then
    Rim := Rim + F.Detail.Z*Smooth(0.34, 0.76, V)*
      (1-Smooth(0.06, 0.53, Rim))*Smooth(0.10, 0.49, Grain+0.35)*0.43;
  Body := 1-Smooth(Radius-(0.11+F.Detail.W*0.16), Radius+0.10+F.Detail.W*0.19, Rim);
  Core := 1-Smooth(0.03, Max(0.13, Radius*0.82), Rim);
  Fade := Smooth(-0.10, 0.025, V)*(1-Smooth(0.81+Grain*0.16, 1.10+Grain*0.18, V));
  Heat := Sat(Core*0.68 + F.Core.W*0.36 - V*0.36 +
    (Grain+Layer*0.43)*(0.33+F.Detail.Y*0.44));
  Result := MixColor(F.Outer, F.Middle, Sat(Body*0.78 + Heat*0.45));
  Result := MixColor(Result, F.Core, Smooth(0.29, 0.82, Heat));
  if F.Outer.X > F.Outer.Z then
    Result := MixColor(Result, Vector(0.32, 0.26, 0.94, 0),
      F.Outer.W*(1-Smooth(-0.04, 0.24, V))*(1-Core*0.42));
  Result.W := Sat(Body*Fade*F.Shape.Z*(0.67+Heat*0.41+Grain*0.21));
end;

function SmokeAt(const F: TFireField; U, V: Single; Seed: Integer): TFireVector;
var
  Width, Edge, Grain, Layer: Single;
begin
  Result := Default(TFireVector);
  if (V < -0.05) or (V > 1.02) then Exit;
  Width := 0.20 + V*F.Detail.Y;
  U := U - F.Shape.Y*4*V*(1-V);
  if Abs(U) > Width + 0.65 then Exit;
  Edge := FireNoise(V*4.6-F.Shape.W*0.52, 13.3, Seed)-0.5;
  U := U - Edge*F.Detail.X*Smooth(0.0, 0.7, V);
  Grain := FireNoise(U*3.2 + 7.0, V*6.6 - F.Shape.W, Seed+13);
  Layer := FireNoise(U*7.3 - Grain, V*13 - F.Shape.W*1.4, Seed+27);
  Width := Width*(0.72+Grain*0.48+Layer*0.18);
  Result := MixColor(F.Middle, F.Core, Grain);
  Result.W := (1-Smooth(0.01, Max(0.12, Width), Abs(U)))*
    Smooth(-0.04, 0.13, V)*(1-Smooth(0.36, 1.02, V))*
    F.Shape.Z*(0.20+0.60*Grain+0.20*Layer);
end;

function RadialAt(const F: TFireField; X, Y: Single; Kind: TFireFieldKind;
  Seed: Integer): TFireVector;
var
  Radius, Falloff, Flecks: Single;
begin
  X := X/F.Axis.Z;
  Y := Y/F.Axis.W;
  Radius := X*X+Y*Y;
  Result := Default(TFireVector);
  if Radius >= 1 then Exit;
  Falloff := 1-Radius;
  Result := MixColor(F.Outer, F.Core, Falloff*Falloff);
  Result.W := F.Shape.Z*Falloff*Falloff*Falloff;
  if Kind = fkEmber then
  begin
    Flecks := FireNoise(X*3.1, Y*3.5-F.Shape.W, Seed);
    Result := MixColor(F.Outer, F.Core, Smooth(0.37, 0.83, Flecks));
    Result.W := F.Shape.Z*Falloff*Falloff*Smooth(0.28, 0.86, Flecks);
  end;
end;

function FieldAt(const F: TFireField; Kind: TFireFieldKind; Seed: Integer;
  X, Y, InvLength, InvWidth: Single): TFireVector;
var
  DX, DY, U, V, Distance, Halo, Core: Single;
begin
  DX := X-F.Axis.X;
  DY := Y-F.Axis.Y;
  if Kind in [fkGlow, fkEmber] then
    Exit(RadialAt(F, DX, DY, Kind, Seed));
  V := (DX*F.Axis.Z + DY*F.Axis.W)*InvLength*InvLength;
  U := (DX*(-F.Axis.W) + DY*F.Axis.Z)*InvLength*InvWidth;
  case Kind of
    fkFlame: Result := FlameAt(F, U, V, Seed);
    fkSmoke: Result := SmokeAt(F, U, V, Seed);
  else
    Distance := Sqr(U) + Sqr((V-0.5)*2.0);
    Core := 1-Smooth(0.01, 0.23, Distance);
    Halo := (1-Smooth(0.04, 1.0, Distance))*F.Detail.X*0.58;
    Result := MixColor(F.Outer, F.Core, Core);
    Result.W := F.Shape.Z*Sat(Core+Halo);
  end;
  if F.Clip.Z > FIRE_NO_CLIP then
    Result.W := Result.W*Smooth(F.Clip.Z, F.Clip.Z+F.Clip.W, Y);
end;

procedure OverPixel(var Pixel: TPIXEL_RGBA; const Src: TFireVector);
var
  Alpha, Under, Weight: Single;
begin
  if Src.W < 0.002 then Exit;
  Under := Pixel.A*(1-Src.W)/255;
  Alpha := Src.W+Under;
  Weight := Src.W/Alpha;
  Pixel.R := Round(Blend(Pixel.R, Src.X*255, Weight));
  Pixel.G := Round(Blend(Pixel.G, Src.Y*255, Weight));
  Pixel.B := Round(Blend(Pixel.B, Src.Z*255, Weight));
  Pixel.A := Round(Alpha*255);
end;

procedure RasterFields(const Scene: TFireScene; Width, Height, Step, First, Last: Integer;
  var Pixels: TFirePixels);
var
  I, X, Y, Left, Top, Right, Bottom, Seed: Integer;
  F: ^TFireField;
  Src: TFireVector;
  Pixel: PPIXEL_RGBA;
  Kind: TFireFieldKind;
  InvLength, InvWidth: Single;
begin
  for I := First to Last do
  begin
    F := @Scene.Fields[I];
    Left := Max(0, Floor(F^.Bounds.X/Step));
    Top := Max(0, Floor(F^.Bounds.Y/Step));
    Right := Min(Width-1, Ceil(F^.Bounds.Z/Step));
    Bottom := Min(Height-1, Ceil(F^.Bounds.W/Step));
    Kind := TFireFieldKind(Trunc(F^.Clip.X));
    Seed := Trunc(F^.Clip.Y);
    InvLength := 1/Sqrt(Sqr(F^.Axis.Z)+Sqr(F^.Axis.W));
    InvWidth := 1/F^.Shape.X;
    for Y := Top to Bottom do
    begin
      Pixel := @Pixels[Y*Width+Left];
      for X := Left to Right do
      begin
        Src := FieldAt(F^, Kind, Seed, (X+0.5)*Step, (Y+0.5)*Step, InvLength, InvWidth);
        OverPixel(Pixel^, Src);
        Inc(Pixel);
      end;
    end;
  end;
end;

procedure ExpandFields(const Scratch: TFirePixels; ScratchWidth, ScratchHeight, Step,
  Width, Height: Integer; const Bounds: TFireVector; var Pixels: TFirePixels);
var
  X, Y, Left, Top, Right, Bottom, X0, X1, Y0, Y1: Integer;
  U, V, TX, TY, A, B, C, D, Alpha: Single;
  P0, P1, P2, P3: PPIXEL_RGBA;
  Pixel: PPIXEL_RGBA;
begin
  Left := Max(0, Floor(Bounds.X)-Step);
  Top := Max(0, Floor(Bounds.Y)-Step);
  Right := Min(Width-1, Ceil(Bounds.Z)+Step);
  Bottom := Min(Height-1, Ceil(Bounds.W)+Step);
  for Y := Top to Bottom do
  begin
    V := EnsureRange((Y+0.5)/Step-0.5, 0.0, ScratchHeight-1.0);
    Y0 := Trunc(V);
    Y1 := Min(Y0+1, ScratchHeight-1);
    TY := V-Y0;
    Pixel := @Pixels[Y*Width+Left];
    for X := Left to Right do
    begin
      U := EnsureRange((X+0.5)/Step-0.5, 0.0, ScratchWidth-1.0);
      X0 := Trunc(U);
      X1 := Min(X0+1, ScratchWidth-1);
      TX := U-X0;
      P0 := @Scratch[Y0*ScratchWidth+X0];
      P1 := @Scratch[Y0*ScratchWidth+X1];
      P2 := @Scratch[Y1*ScratchWidth+X0];
      P3 := @Scratch[Y1*ScratchWidth+X1];
      A := (1-TX)*(1-TY)*P0^.A;
      B := TX*(1-TY)*P1^.A;
      C := (1-TX)*TY*P2^.A;
      D := TX*TY*P3^.A;
      Alpha := A+B+C+D;
      if Alpha >= 0.5 then
      begin
        Pixel^.R := Round((A*P0^.R+B*P1^.R+C*P2^.R+D*P3^.R)/Alpha);
        Pixel^.G := Round((A*P0^.G+B*P1^.G+C*P2^.G+D*P3^.G)/Alpha);
        Pixel^.B := Round((A*P0^.B+B*P1^.B+C*P2^.B+D*P3^.B)/Alpha);
        Pixel^.A := Round(Alpha);
      end;
      Inc(Pixel);
    end;
  end;
end;

procedure RasterFire(const Scene: TFireScene; Width, Height: Integer;
  var Pixels, Scratch: TFirePixels);
const
  SAMPLE_BUDGET = 800000;
var
  I, Count, Step, FirstSpark, ScratchWidth, ScratchHeight: Integer;
  Work: Double;
  Bounds: TFireVector;
begin
  SetLength(Pixels, Width*Height);
  FillChar(Pixels[0], Length(Pixels)*SizeOf(TPIXEL_RGBA), 0);
  Count := Trunc(Scene.Info.X);
  if Count = 0 then Exit;
  Work := 0;
  FirstSpark := Count;
  for I := 0 to Count-1 do
  begin
    if Trunc(Scene.Fields[I].Clip.X) = Ord(fkSpark) then
    begin
      FirstSpark := I;
      Break;
    end;
    Bounds := Scene.Fields[I].Bounds;
    Work := Work+(Min(Width, Bounds.Z)-Max(0, Bounds.X))*
      (Min(Height, Bounds.W)-Max(0, Bounds.Y));
  end;
  // CPUに切り替わった場合、重い炎と煙の評価を減らして火の粉は個別に原寸で描く。
  Step := EnsureRange(Ceil(Sqrt(Work/SAMPLE_BUDGET)), 1, 5);
  if Step = 1 then
    RasterFields(Scene, Width, Height, 1, 0, Count-1, Pixels)
  else
  begin
    ScratchWidth := (Width+Step-1) div Step;
    ScratchHeight := (Height+Step-1) div Step;
    SetLength(Scratch, ScratchWidth*ScratchHeight);
    FillChar(Scratch[0], Length(Scratch)*SizeOf(TPIXEL_RGBA), 0);
    RasterFields(Scene, ScratchWidth, ScratchHeight, Step, 0, FirstSpark-1, Scratch);
    ExpandFields(Scratch, ScratchWidth, ScratchHeight, Step, Width, Height, Scene.Bounds, Pixels);
    RasterFields(Scene, Width, Height, 1, FirstSpark, Count-1, Pixels);
  end;
end;

end.
