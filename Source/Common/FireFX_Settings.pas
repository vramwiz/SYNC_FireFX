unit FireFX_Settings;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// GUIの型、単位、範囲と、プリセットが設定する独立した値を定義する。

interface

type
  TFireGroup = (fgPreset, fgPower, fgShape, fgSources, fgProjection,
    fgIgnition, fgColors, fgWind, fgObstacle, fgSmoke, fgSparks, fgEmbers, fgHaze);
  TFirePreset = (fpCandle, fpStove, fpCampfire, fpTorch, fpFireplace, fpAlcohol,
    fpBurner, fpCharcoal, fpBlaze, fpIncense, fpSparkler, fpPillar);
  TFireLayout = (flSingle, flLine, flRing, flDoubleRing, flRectangle, flRandom);
  TFireIgnition = (fiInstant, fiSpark, fiSmall, fiSpread, fiEmber);
  TFireSpread = (fsTogether, fsForward, fsBoth, fsRandom);
  TFireObstacle = (foNone, foBox, foRound);
  TFireSmoke = (fmNone, fmBurning, fmExtinction, fmBoth);
  TFireColor = (fcCore, fcMiddle, fcOuter, fcSmoke, fcEmber);
  TFireTrack = (
    ftPower,
    ftHeight, ftWidth, ftDensity, ftTurbulence, ftFlicker, ftRise, ftSplit, ftDetail,
    ftCount, ftSourceWidth, ftSourceDepth, ftDiameter, ftInnerRatio, ftPositionJitter,
    ftHeightJitter, ftPowerJitter, ftPitch, ftRotation, ftPerspective, ftLean, ftRadiate,
    ftIgnitionStart, ftIgnitionJitter, ftFlameTransparency, ftGlow, ftGlowRadius, ftBlur,
    ftWindDirection, ftWindSpeed, ftGust, ftGustSpeed,
    ftObstacleX, ftObstacleY, ftObstacleZ, ftObstacleWidth, ftObstacleHeight,
    ftObstacleDepth, ftWrap, ftCurvature,
    ftSmokeAmount, ftSmokeWidth, ftSmokeRise, ftSmokeSpread, ftSmokeTransparency,
    ftSmokeLife, ftSparkAmount, ftSparkSize, ftSparkSpeed, ftSparkSpread, ftSparkLife,
    ftSparkGlow, ftEmberRadius, ftEmberStrength, ftEmberFlicker, ftEmberLife,
    ftHazeStrength, ftHazeRange, ftHazeSpeed);
  TFireTrackDefinition = record
    Name: PWideChar;
    Group: TFireGroup;
    Initial, Min, Max, Step: Double;
  end;
  TFireSettings = record
    V: array[TFireTrack] of Double;
    Colors: array[TFireColor] of Cardinal;
    Layout: TFireLayout;
    Ignition: TFireIgnition;
    Spread: TFireSpread;
    Obstacle: TFireObstacle;
    Smoke: TFireSmoke;
    Sparks, Embers, Haze: Boolean;
  end;

const
  FIRE_EFFECT_NAME = '火演出';
  FIRE_MAX_SOURCES = 100;
  FIRE_GROUP_NAMES: array[TFireGroup] of PWideChar = ('プリセット', '燃焼',
    '炎形状', '火元配置', '疑似立体', '点火・消火', '色彩・発光', '風', '物体干渉',
    '煙', '火の粉・火花', '赤熱・残り火', '陽炎');
  FIRE_PRESET_NAMES: array[TFirePreset] of PWideChar = ('ろうそく', 'ガスコンロ',
    '焚き火', 'たいまつ', '暖炉', 'アルコールランプ', 'ガスバーナー',
    '炭火', '火災', '線香', '線香花火', '火柱');
  FIRE_LAYOUT_NAMES: array[TFireLayout] of PWideChar = ('単点', '直線', '円形',
    '二重円', '矩形', 'ランダム');
  FIRE_IGNITION_NAMES: array[TFireIgnition] of PWideChar = ('即時', '火花',
    '小炎', '燃え広がり', '赤熱');
  FIRE_SPREAD_NAMES: array[TFireSpread] of PWideChar = ('同時', '一方向', '両方向', 'ランダム');
  FIRE_OBSTACLE_NAMES: array[TFireObstacle] of PWideChar = ('なし', '四角', '丸');
  FIRE_SMOKE_NAMES: array[TFireSmoke] of PWideChar = ('なし', '燃焼中', '消火時', '燃焼中・消火時');
  FIRE_COLOR_NAMES: array[TFireColor] of PWideChar = ('炎の中心色', '炎の中間色',
    '炎の外側の色', '煙の色', '赤熱色');

  FIRE_TRACKS: array[TFireTrack] of TFireTrackDefinition = (
    (Name:'火力'; Group:fgPower; Initial:100; Min:0; Max:150; Step:0.01),
    (Name:'炎の高さ'; Group:fgShape; Initial:92; Min:0; Max:4096; Step:0.1),
    (Name:'炎の幅'; Group:fgShape; Initial:31; Min:0; Max:2048; Step:0.1),
    (Name:'炎の密度'; Group:fgShape; Initial:84; Min:0; Max:150; Step:0.1),
    (Name:'炎の揺らぎ'; Group:fgShape; Initial:16; Min:0; Max:150; Step:0.1),
    (Name:'揺らぎ速度'; Group:fgShape; Initial:90; Min:0; Max:300; Step:0.1),
    (Name:'炎の上昇速度'; Group:fgShape; Initial:86; Min:0; Max:300; Step:0.1),
    (Name:'炎の分裂・合流'; Group:fgShape; Initial:12; Min:0; Max:100; Step:0.1),
    (Name:'炎の内部構造'; Group:fgShape; Initial:34; Min:0; Max:100; Step:0.1),
    (Name:'火元数'; Group:fgSources; Initial:1; Min:1; Max:FIRE_MAX_SOURCES; Step:1),
    (Name:'配置幅'; Group:fgSources; Initial:140; Min:0; Max:8192; Step:0.1),
    (Name:'配置奥行'; Group:fgSources; Initial:90; Min:0; Max:8192; Step:0.1),
    (Name:'円の直径'; Group:fgSources; Initial:132; Min:0; Max:8192; Step:0.1),
    (Name:'内円の直径比'; Group:fgSources; Initial:56; Min:0; Max:100; Step:0.1),
    (Name:'火元の位置のばらつき'; Group:fgSources; Initial:0; Min:0; Max:100; Step:0.1),
    (Name:'炎の高さのばらつき'; Group:fgSources; Initial:8; Min:0; Max:100; Step:0.1),
    (Name:'炎の強さのばらつき'; Group:fgSources; Initial:5; Min:0; Max:100; Step:0.1),
    (Name:'傾斜角度'; Group:fgProjection; Initial:21; Min:-89; Max:89; Step:0.1),
    (Name:'回転角度'; Group:fgProjection; Initial:0; Min:-360; Max:360; Step:0.1),
    (Name:'遠近感'; Group:fgProjection; Initial:18; Min:0; Max:100; Step:0.1),
    (Name:'炎の傾き'; Group:fgProjection; Initial:0; Min:-75; Max:75; Step:0.1),
    (Name:'炎の放射方向'; Group:fgProjection; Initial:0; Min:-75; Max:75; Step:0.1),
    (Name:'点火開始位置'; Group:fgIgnition; Initial:0; Min:0; Max:100; Step:0.1),
    (Name:'点火のばらつき'; Group:fgIgnition; Initial:8; Min:0; Max:100; Step:0.1),
    (Name:'炎の透明度'; Group:fgColors; Initial:5; Min:0; Max:100; Step:0.1),
    (Name:'発光強度'; Group:fgColors; Initial:33; Min:0; Max:150; Step:0.1),
    (Name:'発光範囲'; Group:fgColors; Initial:31; Min:0; Max:2048; Step:0.1),
    (Name:'ぼかし'; Group:fgColors; Initial:17; Min:0; Max:100; Step:0.1),
    (Name:'風向'; Group:fgWind; Initial:0; Min:-360; Max:360; Step:0.1),
    (Name:'風速'; Group:fgWind; Initial:0; Min:0; Max:300; Step:0.1),
    (Name:'風の揺らぎ'; Group:fgWind; Initial:30; Min:0; Max:100; Step:0.1),
    (Name:'風の変化速度'; Group:fgWind; Initial:80; Min:0; Max:300; Step:0.1),
    (Name:'干渉物体の相対X'; Group:fgObstacle; Initial:0; Min:-8192; Max:8192; Step:0.1),
    (Name:'干渉物体の相対Y'; Group:fgObstacle; Initial:-36; Min:-8192; Max:8192; Step:0.1),
    (Name:'干渉物体の相対Z'; Group:fgObstacle; Initial:0; Min:-8192; Max:8192; Step:0.1),
    (Name:'干渉物体の幅'; Group:fgObstacle; Initial:180; Min:1; Max:8192; Step:0.1),
    (Name:'干渉物体の高さ'; Group:fgObstacle; Initial:16; Min:1; Max:8192; Step:0.1),
    (Name:'干渉物体の奥行'; Group:fgObstacle; Initial:180; Min:1; Max:8192; Step:0.1),
    (Name:'炎の回り込み'; Group:fgObstacle; Initial:60; Min:0; Max:150; Step:0.1),
    (Name:'底面の曲率'; Group:fgObstacle; Initial:20; Min:0; Max:100; Step:0.1),
    (Name:'煙の発生量'; Group:fgSmoke; Initial:36; Min:0; Max:150; Step:0.1),
    (Name:'煙の太さ'; Group:fgSmoke; Initial:13; Min:0; Max:2048; Step:0.1),
    (Name:'煙の上昇速度'; Group:fgSmoke; Initial:57; Min:0; Max:1024; Step:0.1),
    (Name:'煙の拡散率'; Group:fgSmoke; Initial:38; Min:0; Max:150; Step:0.1),
    (Name:'煙の透明度'; Group:fgSmoke; Initial:38; Min:0; Max:100; Step:0.1),
    (Name:'煙の残存時間'; Group:fgSmoke; Initial:2.4; Min:0; Max:15; Step:0.01),
    (Name:'火の粉の発生量'; Group:fgSparks; Initial:30; Min:0; Max:150; Step:0.1),
    (Name:'火の粉の大きさ'; Group:fgSparks; Initial:2; Min:0; Max:128; Step:0.1),
    (Name:'火の粉の発生速度'; Group:fgSparks; Initial:83; Min:0; Max:300; Step:0.1),
    (Name:'火の粉の飛散範囲'; Group:fgSparks; Initial:62; Min:0; Max:2048; Step:0.1),
    (Name:'火の粉の寿命'; Group:fgSparks; Initial:0.9; Min:0; Max:10; Step:0.01),
    (Name:'火の粉の発光強度'; Group:fgSparks; Initial:70; Min:0; Max:150; Step:0.1),
    (Name:'赤熱範囲'; Group:fgEmbers; Initial:12; Min:0; Max:2048; Step:0.1),
    (Name:'赤熱の強さ'; Group:fgEmbers; Initial:52; Min:0; Max:150; Step:0.1),
    (Name:'赤熱の明滅'; Group:fgEmbers; Initial:41; Min:0; Max:100; Step:0.1),
    (Name:'赤熱の残存時間'; Group:fgEmbers; Initial:2.7; Min:0; Max:15; Step:0.01),
    (Name:'陽炎の揺らぎの強さ'; Group:fgHaze; Initial:24; Min:0; Max:150; Step:0.1),
    (Name:'陽炎の揺らぎ範囲'; Group:fgHaze; Initial:110; Min:0; Max:2048; Step:0.1),
    (Name:'陽炎の揺らぎ速度'; Group:fgHaze; Initial:85; Min:0; Max:300; Step:0.1));

// すべてのGUI項目を初期化し、指定した一括設定の値を返す。
function FirePreset(Preset: TFirePreset): TFireSettings;
// 異常な値や範囲外の値を除き、GUIの既定値と範囲を適用する。
function ClampFireTrack(Track: TFireTrack; Value: Double): Double;

implementation

uses System.Math;

function ClampFireTrack(Track: TFireTrack; Value: Double): Double;
begin
  if IsNan(Value) then
    Exit(FIRE_TRACKS[Track].Initial);
  Result := EnsureRange(Value, FIRE_TRACKS[Track].Min, FIRE_TRACKS[Track].Max);
end;

function FirePreset(Preset: TFirePreset): TFireSettings;
var
  Track: TFireTrack;

  procedure Flame(Height, Width, Density, Turbulence, Flicker, Rise, Split, Detail: Double);
  begin
    Result.V[ftHeight] := Height;
    Result.V[ftWidth] := Width;
    Result.V[ftDensity] := Density;
    Result.V[ftTurbulence] := Turbulence;
    Result.V[ftFlicker] := Flicker;
    Result.V[ftRise] := Rise;
    Result.V[ftSplit] := Split;
    Result.V[ftDetail] := Detail;
  end;

  procedure Palette(Core, Middle, Outer: Cardinal);
  begin
    Result.Colors[fcCore] := Core;
    Result.Colors[fcMiddle] := Middle;
    Result.Colors[fcOuter] := Outer;
  end;

  procedure Sources(Layout: TFireLayout; Count: Integer; Width, Depth, Position,
    Height, Power: Double);
  begin
    Result.Layout := Layout;
    Result.V[ftCount] := Count;
    Result.V[ftSourceWidth] := Width;
    Result.V[ftSourceDepth] := Depth;
    Result.V[ftPositionJitter] := Position;
    Result.V[ftHeightJitter] := Height;
    Result.V[ftPowerJitter] := Power;
  end;

  procedure Smoke(Mode: TFireSmoke; Color: Cardinal; Amount, Width, Rise,
    Spread, Transparency, Life: Double);
  begin
    Result.Smoke := Mode;
    Result.Colors[fcSmoke] := Color;
    Result.V[ftSmokeAmount] := Amount;
    Result.V[ftSmokeWidth] := Width;
    Result.V[ftSmokeRise] := Rise;
    Result.V[ftSmokeSpread] := Spread;
    Result.V[ftSmokeTransparency] := Transparency;
    Result.V[ftSmokeLife] := Life;
  end;

  procedure Sparks(Amount, Size, Speed, Spread, Life, Glow: Double);
  begin
    Result.Sparks := True;
    Result.V[ftSparkAmount] := Amount;
    Result.V[ftSparkSize] := Size;
    Result.V[ftSparkSpeed] := Speed;
    Result.V[ftSparkSpread] := Spread;
    Result.V[ftSparkLife] := Life;
    Result.V[ftSparkGlow] := Glow;
  end;

  procedure Embers(Radius, Strength, Flicker, Life: Double);
  begin
    Result.Embers := True;
    Result.V[ftEmberRadius] := Radius;
    Result.V[ftEmberStrength] := Strength;
    Result.V[ftEmberFlicker] := Flicker;
    Result.V[ftEmberLife] := Life;
  end;

begin
  Result := Default(TFireSettings);
  for Track := Low(TFireTrack) to High(TFireTrack) do
    Result.V[Track] := FIRE_TRACKS[Track].Initial;
  Result.Ignition := fiSmall;
  Result.Smoke := fmExtinction;
  Result.Colors[fcSmoke] := $D9D8D4;
  Result.Colors[fcEmber] := $FF4E0B;
  Palette($FFFBD4, $FFC340, $ED4B0E);

  case Preset of
    fpStove:
      begin
        Flame(38, 12, 74, 9, 118, 125, 6, 49);
        Sources(flRing, 24, 132, 132, 0, 11, 10);
        Palette($D0F8FF, $498FFF, $2423F6);
        Result.Ignition := fiSpark;
        Result.Spread := fsBoth;
        Result.Smoke := fmNone;
        Result.V[ftRadiate] := 28;
        Result.V[ftPitch] := 32;
        Result.V[ftGlow] := 21;
        Result.V[ftGlowRadius] := 15;
      end;
    fpCampfire, fpFireplace:
      begin
        Flame(169, 74, 110, 72, 111, 128, 73, 70);
        Sources(flRandom, 11, 162, 89, 40, 44, 32);
        Palette($FFF6B3, $FF9C27, $DC2F08);
        Result.Ignition := fiSpread;
        Result.Spread := fsBoth;
        Result.V[ftGlow] := 52;
        Result.V[ftGlowRadius] := 75;
        Smoke(fmBoth, $777572, 37, 49, 95, 56, 68, 3.7);
        Sparks(40, 2.2, 112, 117, 1.3, 76);
        Embers(20, 56, 51, 5);
        if Preset = fpFireplace then
        begin
          Flame(143, 66, 104, 49, 95, 114, 52, 61);
          Sources(flRectangle, 12, 194, 66, 24, 37, 24);
          Result.V[ftSmokeAmount] := 18;
          Result.V[ftSparkAmount] := 19;
          Result.V[ftEmberLife] := 6;
        end;
      end;
    fpTorch:
      begin
        Flame(126, 49, 99, 83, 134, 140, 63, 63);
        Sources(flRandom, 4, 28, 24, 28, 31, 23);
        Palette($FFF2B8, $FFAA23, $DF3908);
        Smoke(fmBoth, $5F5B57, 24, 35, 90, 55, 70, 3.1);
        Sparks(14, 1.8, 98, 68, 0.8, 64);
      end;
    fpAlcohol:
      begin
        Flame(62, 42, 49, 18, 77, 83, 21, 40);
        Palette($E4FFFF, $5AB5FC, $594BF3);
        Result.Smoke := fmNone;
        Result.V[ftFlameTransparency] := 19;
        Result.V[ftGlow] := 17;
      end;
    fpBurner:
      begin
        Flame(104, 24, 103, 18, 170, 238, 22, 65);
        Palette($E7FFFF, $42CFFF, $2545FA);
        Result.Ignition := fiSpark;
        Result.Smoke := fmNone;
        Result.V[ftLean] := 42;
        Result.V[ftGlow] := 27;
        Result.V[ftGlowRadius] := 25;
      end;
    fpCharcoal:
      begin
        Flame(12, 19, 15, 66, 86, 68, 56, 50);
        Sources(flRandom, 22, 177, 112, 55, 60, 52);
        Palette($FFCD69, $FF5D12, $AD2107);
        Result.Ignition := fiEmber;
        Result.Spread := fsRandom;
        Smoke(fmBoth, $908B82, 14, 31, 48, 60, 72, 3.7);
        Embers(16, 105, 67, 8);
        Result.V[ftGlow] := 17;
      end;
    fpBlaze:
      begin
        Flame(325, 134, 127, 105, 116, 174, 90, 87);
        Sources(flRandom, 22, 410, 139, 69, 68, 37);
        Palette($FFF5B5, $FF8C24, $C8260E);
        Result.Ignition := fiSpread;
        Result.Spread := fsForward;
        Smoke(fmBoth, $24252A, 124, 118, 129, 80, 37, 6);
        Sparks(79, 2.7, 140, 235, 2.1, 87);
        Embers(33, 83, 58, 7);
        Result.V[ftGlow] := 84;
        Result.V[ftGlowRadius] := 147;
      end;
    fpIncense:
      begin
        Flame(0, 0, 0, 15, 37, 62, 0, 33);
        Result.Ignition := fiEmber;
        Smoke(fmBurning, $B5B9C3, 57, 6, 56, 65, 42, 4.2);
        Embers(3.2, 76, 48, 3);
        Result.V[ftGlow] := 0;
      end;
    fpSparkler:
      begin
        Flame(7, 8, 49, 39, 163, 101, 43, 62);
        Palette($FFFFEF, $FFB442, $F2510F);
        Result.Ignition := fiEmber;
        Sparks(144, 1.35, 208, 142, 0.57, 107);
        Embers(4.8, 130, 73, 0.8);
        Result.V[ftGlow] := 18;
      end;
    fpPillar:
      begin
        Flame(352, 79, 117, 65, 99, 212, 49, 79);
        Sources(flDoubleRing, 13, 70, 70, 21, 24, 20);
        Palette($FFF9C5, $FFB126, $E5390A);
        Result.Ignition := fiSpread;
        Result.Spread := fsBoth;
        Result.V[ftDiameter] := 61;
        Result.V[ftRadiate] := -9;
        Result.V[ftGlow] := 66;
        Result.V[ftGlowRadius] := 82;
        Smoke(fmBoth, $665F5D, 29, 67, 121, 76, 72, 3.5);
        Sparks(30, 2.9, 142, 107, 1.5, 77);
      end;
  end;
end;

end.
