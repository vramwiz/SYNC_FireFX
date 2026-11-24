unit FireFX_Scene;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 設置面、火力、風と時刻から奥行順の描画フィールドを作る。

interface

uses FireFX_Settings, FireFX_Field;

type
  TFireActivity = record
    Falling, SparkAllowed: Boolean;
    SmokeResidual, SmokeAge, EmberResidual: Single;
  end;

// Activityはタイムラインの読み取り結果。Sceneは呼出側が描画間で再利用する。
procedure BuildFireScene(const S: TFireSettings; const Activity: TFireActivity;
  Width, Height: Integer; Time: Single; var Scene: TFireScene);

implementation

uses System.Math;

type
  TSource = record
    X, Z, Height, Strength, Lit: Single;
    Index: Integer;
    Projected: TFireVector;
  end;

procedure BuildFireScene(const S: TFireSettings; const Activity: TFireActivity;
  Width, Height: Integer; Time: Single; var Scene: TFireScene);
var
  Sources: array[0..FIRE_MAX_SOURCES-1] of TSource;
  Source, Moving: TSource;
  Count, FieldCount, I, J, StartIndex: Integer;
  OriginX, OriginY, PitchSin, PitchCos, ViewDepth, RotSin, RotCos: Single;
  Power, Load, WindX, WindZ, FlickerTime, FlowTime, FireOpacity: Single;
  IgniteDistance, IgniteOrigin, IgniteMin, IgniteMax: Single;
  CoreColor, MiddleColor, OuterColor: TFireVector;

  function Project(X, H, Z: Single): TFireVector;
  var
    Depth, Ratio: Single;
  begin
    Depth := Z*PitchCos;
    Ratio := 1/EnsureRange(1-Depth*ViewDepth, 0.42, 2.4);
    Result := Vector(OriginX+X*Ratio, OriginY+(Z*PitchSin-H)*Ratio, Depth, Ratio);
  end;

  procedure InsertField(const F: TFireField);
  begin
    if (FieldCount >= FIRE_MAX_FIELDS) or (F.Shape.Z <= 0.002) or
      (F.Bounds.Z <= 0) or (F.Bounds.W <= 0) or
      (F.Bounds.X >= Width) or (F.Bounds.Y >= Height) then Exit;
    Scene.Fields[FieldCount] := F;
    Scene.Bounds.X := Min(Scene.Bounds.X, F.Bounds.X);
    Scene.Bounds.Y := Min(Scene.Bounds.Y, F.Bounds.Y);
    Scene.Bounds.Z := Max(Scene.Bounds.Z, F.Bounds.Z);
    Scene.Bounds.W := Max(Scene.Bounds.W, F.Bounds.W);
    Inc(FieldCount);
  end;

  function Ribbon(Kind: TFireFieldKind; const A, B: TFireVector; Radius, Bend,
    Alpha, Phase, Turbulence, Expansion: Single; Seed: Integer): TFireField;
  var
    Pad, MarginX, MarginY, Length: Single;
  begin
    Result := Default(TFireField);
    Radius := Max(0.45, Radius);
    Result.Axis := Vector(A.X, A.Y, B.X-A.X, B.Y-A.Y);
    Result.Shape := Vector(Radius, Bend, Alpha, Phase);
    Result.Detail := Vector(Turbulence, Expansion, 0, 0);
    Result.Clip := Vector(Ord(Kind), Seed, FIRE_NO_CLIP, 1);
    Length := Sqrt(Sqr(Result.Axis.Z)+Sqr(Result.Axis.W));
    if Length < 0.3 then
    begin
      Result.Shape.Z := 0;
      Exit;
    end;
    Pad := Radius*(Max(1.25, 0.90+Expansion)+Abs(Bend)+Turbulence*0.75);
    MarginX := Pad*Abs(Result.Axis.W)/Length+Abs(Result.Axis.Z)*0.14+1;
    MarginY := Pad*Abs(Result.Axis.Z)/Length+Abs(Result.Axis.W)*0.14+1;
    Result.Bounds := Vector(Min(A.X,B.X)-MarginX, Min(A.Y,B.Y)-MarginY,
      Max(A.X,B.X)+MarginX, Max(A.Y,B.Y)+MarginY);
  end;

  procedure Radial(Kind: TFireFieldKind; const Center, InsideColor, OutsideColor: TFireVector;
    RadiusX, RadiusY, Alpha: Single; Seed: Integer);
  var
    F: TFireField;
  begin
    if (RadiusX <= 0.1) or (RadiusY <= 0.1) then Exit;
    F := Default(TFireField);
    F.Axis := Vector(Center.X, Center.Y, RadiusX, RadiusY);
    F.Bounds := Vector(Center.X-RadiusX, Center.Y-RadiusY,
      Center.X+RadiusX, Center.Y+RadiusY);
    F.Shape := Vector(1, 0, Sat(Alpha), FlickerTime*0.37);
    F.Clip := Vector(Ord(Kind), Seed, FIRE_NO_CLIP, 1);
    F.Core := InsideColor;
    F.Outer := OutsideColor;
    InsertField(F);
  end;

  function StartDelay(Index: Integer): Single;
  var
    D: Integer;
    Rank, Turn, AxisPosition, Span: Single;
  begin
    if (Index = StartIndex) or (S.Spread = fsTogether) then Exit(0);
    D := (Index-StartIndex+Count) mod Count;
    case S.Spread of
      fsForward:
        if S.Layout in [flRing, flDoubleRing] then
          Rank := D/(Count-1)
        else
        begin
          Span := IgniteMax-IgniteMin;
          AxisPosition := Sources[Index].X*RotCos+Sources[Index].Z*RotSin-IgniteOrigin;
          if AxisPosition < -0.001 then AxisPosition := AxisPosition+Span+0.001;
          Rank := AxisPosition/Max(0.001, Span);
        end;
      fsBoth:
        if S.Layout in [flRing, flDoubleRing] then
          Rank := Min(D, Count-D)/Max(1, Count div 2)
        else
          Rank := Sqrt(Sqr(Sources[Index].X-Source.X)+Sqr(Sources[Index].Z-Source.Z))/
            Max(0.001, IgniteDistance);
    else
      Rank := FireRandom(Index, 52, 269);
    end;
    if (S.Layout = flDoubleRing) and (S.Spread in [fsForward, fsBoth]) then
    begin
      Turn := (ArcTan2(Sources[Index].Z, Sources[Index].X)-ArcTan2(Source.Z, Source.X))/(2*Pi);
      Turn := Turn-Floor(Turn);
      if S.Spread = fsBoth then Turn := 2*Min(Turn, 1-Turn);
      Rank := Turn;
    end;
    Result := EnsureRange(Rank*0.93 + (FireRandom(Index, 55, 269)-0.5)*
      S.V[ftIgnitionJitter]*0.004, 0.012, 0.985);
  end;

  function LitLevel(Index: Integer): Single;
  var
    Delay: Single;
  begin
    if Power >= 2 then Exit(1);
    if Power < 1 then
    begin
      if (Power > 0) and not Activity.Falling and (S.Ignition = fiSmall) and (Index = StartIndex) then
        Exit(0.23*Smooth(0.17, 1, Power));
      Exit(0);
    end;
    Delay := StartDelay(Index);
    if Power-1 < Delay then Exit(0);
    if S.Ignition = fiInstant then Exit(1);
    Result := 0.33+0.67*Smooth(Delay, Min(1.0, Delay+0.18), Power-1);
  end;

  function MakeSource(Index: Integer): TSource;
  var
    X, Z, A, R, Jitter: Single;
    RingCount, InnerCount, Columns, Rows: Integer;
  begin
    X := 0;
    Z := 0;
    if Count > 1 then
      case S.Layout of
        flLine:
          X := S.V[ftSourceWidth]*(Index/(Count-1)-0.5);
        flRing, flDoubleRing:
          begin
            R := S.V[ftDiameter]*0.5;
            RingCount := Count;
            if S.Layout = flDoubleRing then RingCount := Max(1, Round(Count*0.62));
            A := 2*Pi*Index/RingCount;
            if Index >= RingCount then
            begin
              InnerCount := Count-RingCount;
              R := R*S.V[ftInnerRatio]*0.01;
              A := 2*Pi*(Index-RingCount+0.5)/InnerCount;
            end;
            X := Cos(A)*R;
            Z := Sin(A)*R;
          end;
        flRectangle:
          begin
            Columns := EnsureRange(Round(Sqrt(Count*Max(1.0,S.V[ftSourceWidth])/
              Max(1.0,S.V[ftSourceDepth]))), 2, Count);
            Rows := (Count+Columns-1) div Columns;
            // 行ごとの個数は右端の余りを含め、各行を中央揃えにする。
            Jitter := Min(Columns, Count-(Index div Columns)*Columns);
            if Jitter > 1 then X := ((Index mod Columns)/(Jitter-1)-0.5)*S.V[ftSourceWidth];
            if Rows > 1 then Z := ((Index div Columns)/(Rows-1)-0.5)*S.V[ftSourceDepth];
          end;
        flRandom:
          begin
            X := (FireRandom(Index, 2, 403)-0.5)*S.V[ftSourceWidth];
            Z := (FireRandom(Index, 3, 403)-0.5)*S.V[ftSourceDepth];
          end;
      end;
    if S.Layout <> flSingle then
    begin
      Jitter := S.V[ftPositionJitter]*0.01*
        Max(S.V[ftWidth], Max(S.V[ftSourceWidth], S.V[ftDiameter])/Sqrt(Count))*0.45;
      X := X+(FireRandom(Index, 9, 403)-0.5)*Jitter;
      Z := Z+(FireRandom(Index, 10, 403)-0.5)*Jitter;
    end;
    Result.X := X*RotCos-Z*RotSin;
    Result.Z := X*RotSin+Z*RotCos;
    Result.Lit := 0;
    Result.Index := Index;
    Result.Projected := Project(Result.X, 0, Result.Z);
    Result.Height := 1+(FireRandom(Index, 12, 403)*2-1)*S.V[ftHeightJitter]*0.007;
    Result.Strength := 1+(FireRandom(Index, 13, 403)*2-1)*S.V[ftPowerJitter]*0.0065;
  end;

  procedure AddFlame(const A, B: TFireVector; Radius, Bend, Alpha, Heat, Turbulence,
    ClipY: Single; Seed: Integer);
  var
    F: TFireField;
  begin
    F := Ribbon(fkFlame, A, B, Radius, Bend, Alpha, FlowTime, Turbulence, 0, Seed);
    F.Detail.Y := S.V[ftDetail]*0.01;
    F.Detail.Z := S.V[ftSplit]*0.01;
    F.Detail.W := S.V[ftBlur]*0.01;
    F.Core := CoreColor;
    F.Core.W := Heat;
    F.Middle := MiddleColor;
    F.Middle.W := FlickerTime;
    F.Outer := OuterColor;
    F.Outer.W := 0.56*(1-Sat(S.V[ftTurbulence]*0.006));
    F.Clip.Z := ClipY;
    F.Clip.W := Max(0.65, Radius*0.15);
    InsertField(F);
  end;

  function ObstacleSurface(X, Z: Single; out Surface: Single): Boolean;
  var
    U, V, R: Single;
  begin
    U := (X-S.V[ftObstacleX])*2/S.V[ftObstacleWidth];
    V := (Z-S.V[ftObstacleZ])*2/S.V[ftObstacleDepth];
    Surface := -S.V[ftObstacleY]-S.V[ftObstacleHeight]*0.5;
    if S.Obstacle = foBox then Exit((Abs(U) <= 1) and (Abs(V) <= 1));
    R := U*U+V*V;
    Result := R <= 1;
    if Result then Surface := Surface + (1-Sqrt(1-R))*S.V[ftObstacleHeight]*S.V[ftCurvature]*0.01;
  end;

  procedure DrawFlame(const Src: TSource);
  var
    A, B, Contact, Edge, Tip: TFireVector;
    L, Radius, Bend, Alpha, Heat, Strength, Turbulence, Phase, Drift, Radial, DX, DZ,
      H, X, Z, Surface, ClipY, EdgeX, EdgeSurface, Direction, WrapStrength, HalfWidth,
      SideRise, Travel, Lower, Upper, Mid: Single;
    J: Integer;

    function IsObstructed(H: Single; out X, Z, Surface: Single): Boolean;
    begin
      X := Src.X+DX*(H/L);
      Z := Src.Z+DZ*(H/L);
      Result := ObstacleSurface(X, Z, Surface) and (H >= Surface) and
        (H <= Surface+S.V[ftObstacleHeight]);
    end;

  begin
    if (Src.Lit <= 0) or (S.V[ftHeight] <= 0) or (S.V[ftWidth] <= 0) or
      (S.V[ftDensity] <= 0) or (FireOpacity <= 0) then Exit;
    Phase := FireNoise(FlickerTime*1.7, Src.Index*1.71, 710)-0.5;
    Strength := Src.Lit*Src.Strength;
    if Abs(WindX)+Abs(WindZ) > 120 then
      Strength := Strength*(1-0.86*Smooth(120, 325, Abs(WindX)+Abs(WindZ))*
        Smooth(0.37, 0.79, FireNoise(FlickerTime*1.15, Src.Index*1.46, 867)));
    if Strength < 0.025 then Exit;
    Turbulence := S.V[ftTurbulence]*0.01*(0.85+Power/510+0.65*(1-Src.Lit))+
      Min(0.33, (Abs(WindX)+Abs(WindZ))*0.001);
    L := S.V[ftHeight]*(0.10+0.90*Load)*Src.Height*(0.39+0.61*Sqrt(Src.Lit))*
      (1+Phase*(0.10+0.28*Turbulence));
    Radius := S.V[ftWidth]*0.50*(0.23+0.77*Sqrt(Load))*Sqrt(Src.Lit)*Src.Projected.W;
    Alpha := Sat(S.V[ftDensity]*0.011*(0.31+Load*0.66)*Strength)*FireOpacity;
    Heat := Sat(0.22+0.67*Load+Phase*Turbulence*0.2);
    Bend := (FireNoise(FlickerTime*1.23, Src.Index*1.9, 988)-0.5)*Turbulence*0.9;
    Drift := L*0.21*Phase*Turbulence;
    Radial := Max(0.001, Sqrt(Sqr(Src.X)+Sqr(Src.Z)));
    DX := L*(Tan(DegToRad(S.V[ftLean])) + Tan(DegToRad(S.V[ftRadiate]))*Src.X/Radial +
      WindX*0.005) + Drift;
    DZ := L*(Tan(DegToRad(S.V[ftRadiate]))*Src.Z/Radial + WindZ*0.005);
    A := Src.Projected;
    B := Project(Src.X+DX, L, Src.Z+DZ);
    if S.Obstacle <> foNone then
      for J := 0 to 24 do
      begin
        H := L*J/24;
        if not IsObstructed(H, X, Z, Surface) then Continue;
        Lower := Max(0.0, L*(J-1)/24);
        Upper := H;
        for var Step := 1 to 7 do
        begin
          Mid := (Lower+Upper)*0.5;
          if IsObstructed(Mid, X, Z, Surface) then Upper := Mid else Lower := Mid;
        end;
        H := Upper;
        IsObstructed(H, X, Z, Surface);
        Contact := Project(X, Surface-0.6, Z);
        ClipY := Contact.Y;
        AddFlame(A, Contact, Radius, Bend, Alpha, Heat, Turbulence, ClipY, Src.Index+70);
        WrapStrength := S.V[ftWrap]*0.01;
        if WrapStrength > 0 then
        begin
          Direction := 1;
          if X-S.V[ftObstacleX]+DX*0.13 < 0 then Direction := -1;
          HalfWidth := S.V[ftObstacleWidth]*0.5;
          if S.Obstacle = foRound then
            HalfWidth := HalfWidth*Sqrt(Max(0.0, 1-Sqr((Z-S.V[ftObstacleZ])*2/S.V[ftObstacleDepth])));
          EdgeX := S.V[ftObstacleX]+Direction*HalfWidth;
          if Abs(EdgeX-X) > 0.1 then
          begin
            // 余った炎の長さを底面方向に配分し、縁に届いた分が上へ折り返す。
            Travel := (L-H)*WrapStrength*1.5;
            SideRise := Max(0.0, (Travel-Abs(EdgeX-X))*0.66);
            EdgeX := X+Direction*Min(Abs(EdgeX-X)+1, Travel);
            ObstacleSurface(EdgeX-Direction*1.1, Z, EdgeSurface);
            Edge := Project(EdgeX, EdgeSurface-1.4, Z);
            Contact.Y := Contact.Y+Radius*0.23;
            AddFlame(Contact, Edge, Radius*0.50, -Direction*0.19,
              Alpha*Sat(WrapStrength*0.74), Heat, Turbulence,
              Min(Contact.Y, Edge.Y)-Radius*0.27, Src.Index+197);
            if SideRise > 0.5 then
            begin
              Tip := Project(EdgeX+Direction*(SideRise*0.37+2), EdgeSurface+SideRise, Z);
              AddFlame(Edge, Tip, Radius*0.56, Direction*0.44, Alpha*Sat(WrapStrength),
                Heat, Turbulence, FIRE_NO_CLIP, Src.Index+289);
            end;
          end;
        end;
        Exit;
      end;
    AddFlame(A, B, Radius, Bend, Alpha, Heat, Turbulence, FIRE_NO_CLIP, Src.Index+70);
  end;

  procedure DrawSmoke(const Src: TSource; Strength, Life, Offset, WidthFactor: Single);
  var
    A, B: TFireVector;
    F: TFireField;
    Lift, Drift, Radius, Expand: Single;
  begin
    if (Strength <= 0.004) or (Life <= 0) then Exit;
    Lift := Life*S.V[ftSmokeRise]*(0.72+FireRandom(Src.Index, 8, 313)*0.35);
    if Lift <= 0.5 then Exit;
    Drift := Time*S.V[ftWindSpeed]*0.004;
    A := Project(Src.X+Offset*WindX*0.28, Offset*S.V[ftSmokeRise], Src.Z+Offset*WindZ*0.28);
    B := Project(Src.X+(Life+Offset)*WindX*0.28 + (FireNoise(Time*0.42, Src.Index, 578)-0.5)*
      S.V[ftSmokeWidth]*0.89, Lift+Offset*S.V[ftSmokeRise], Src.Z+(Life+Offset)*WindZ*0.28);
    Radius := (S.V[ftSmokeWidth]*(0.82+Offset*0.4)*WidthFactor)*Src.Projected.W;
    if Radius <= 0.1 then Exit;
    Expand := 0.33+S.V[ftSmokeSpread]*0.012;
    F := Ribbon(fkSmoke, A, B, Radius,
      (FireNoise(Time*0.39, Src.Index, 601)-0.5)*0.73, Sat(Strength),
      Time*S.V[ftSmokeRise]*0.012+Drift, 0.7, Expand, Src.Index+413);
    F.Core := RGBVector(S.Colors[fcSmoke]);
    F.Middle := Vector(F.Core.X*0.63, F.Core.Y*0.65, F.Core.Z*0.68, 0);
    InsertField(F);
  end;

  procedure DrawSparks;
  var
    A, B: TFireVector;
    F: TFireField;
    Birth, K, N, Step, SourceIndex: Integer;
    Rate, Life, Age, Phase, Alpha, DX, DZ, Rise, Radius, Bright, Burst, Angle, Speed: Single;
  begin
    Life := S.V[ftSparkLife];
    Rate := S.V[ftSparkAmount]*0.49*S.V[ftSparkSpeed]*0.008*Sqrt(Load);
    Radius := S.V[ftSparkSize];
    if not S.Sparks or (Power < 1) or (Life <= 0) or (Rate <= 0.05) or (Radius <= 0) then Exit;
    Rate := Min(Rate, 60/Life);
    Birth := Floor(Time*Rate);
    N := Min(64, Ceil(Life*Rate*1.14)+1);
    Burst := Smooth(70, 130, S.V[ftSparkAmount])*Smooth(47, 145, S.V[ftSparkSpread]);
    for Step := N-1 downto 0 do
    begin
      K := Birth-Step;
      Age := Time-(K+FireRandom(K, 1, 380)*0.9)/Rate;
      Phase := Age/(Life*(0.61+FireRandom(K, 4, 380)*0.52));
      if (Phase < 0) or (Phase >= 1) then Continue;
      SourceIndex := Min(Count-1, Trunc(Count*FireRandom(K, 2, 380)));
      if Sources[SourceIndex].Lit <= 0 then Continue;
      Alpha := (1-Phase)*Sqrt(Sources[SourceIndex].Lit);
      Bright := S.V[ftSparkGlow]*0.01;
      DX := (FireRandom(K, 5, 380)*2-1)*S.V[ftSparkSpread];
      DZ := (FireRandom(K, 6, 380)*2-1)*S.V[ftSparkSpread]*0.6 + WindZ*Life*0.23;
      Rise := (0.25+FireRandom(K, 7, 380)*0.98)*S.V[ftSparkSpeed]*Life*0.92;
      if Burst > 0 then
      begin
        Angle := 2*Pi*FireRandom(K, 9, 380);
        Speed := S.V[ftSparkSpread]*(0.27+FireRandom(K, 10, 380)*0.75);
        DX := Blend(DX, Cos(Angle)*Speed, Burst);
        Rise := Blend(Rise, (Sin(Angle)+0.14)*Speed, Burst);
      end;
      DX := DX+WindX*Life*0.23;
      A := Project(Sources[SourceIndex].X+DX*Phase, Rise*Phase*(1-Phase*0.29),
        Sources[SourceIndex].Z+DZ*Phase);
      B := Vector(A.X+DX*0.045*A.W, A.Y-(Rise*(0.09-Phase*0.029)+1.0)*A.W, 0, A.W);
      F := Ribbon(fkSpark, A, B, (Radius*(0.47+FireRandom(K, 8, 380)*0.82)+0.5)*A.W,
        0, Sat(Alpha), 0, Bright, 0, K mod 100003);
      F.Core := RGBVector($FFF4C4);
      F.Outer := RGBVector($FF5612);
      InsertField(F);
    end;
  end;

  procedure DrawIgnition(const Src: TSource);
  var
    A, B: TFireVector;
    F: TFireField;
    K, Spark: Integer;
    Pulse, Age: Single;
  begin
    if (Power <= 0) or (Power >= 1) or Activity.Falling then Exit;
    if S.Ignition = fiEmber then
    begin
      Radial(fkEmber, Src.Projected, RGBVector($FFCE67), RGBVector(S.Colors[fcEmber]),
        S.V[ftEmberRadius]*Src.Projected.W, S.V[ftEmberRadius]*Src.Projected.W*0.6,
        Power*0.72, 926);
      Exit;
    end;
    if (S.Ignition <> fiSpark) or not Activity.SparkAllowed then Exit;
    K := Floor(Time*7.1);
    Age := Time*7.1-K;
    if Age > 0.34 then Exit;
    Pulse := Smooth(0, 0.23, Power)*(1-Smooth(0.06, 0.34, Age));
    for Spark := 0 to 4 do
    begin
      A := Src.Projected;
      B := Vector(A.X + (FireRandom(K, Spark, 820)-0.5)*(13+Age*59)*A.W,
        A.Y-(6+FireRandom(K, Spark, 872)*(8+Age*48))*A.W, 0, A.W);
      if Spark = 0 then
        Radial(fkGlow, A, RGBVector($B8DEFF), RGBVector($554BFF),
          12*A.W, 11*A.W, Pulse*0.42, K mod 100003);
      F := Ribbon(fkSpark, A, B, 1.2*A.W, 0, Pulse, 0, 1, 0, Spark);
      F.Core := RGBVector($F0FAFF);
      F.Outer := RGBVector($7F9CFF);
      InsertField(F);
    end;
  end;

var
  Angle, Gust, Smoke, SmokeLife, Glow, Ember, WidthSpan, SourceAxis: Single;
  SmokeStride, GlowStride, EmberStride: Integer;
  Center: TFireVector;
begin
  Scene.Info := Vector(0, 0, Width, Height);
  Scene.Bounds := Vector(Width, Height, 0, 0);
  Scene.Haze := Default(TFireVector);
  Scene.HazeParams := Default(TFireVector);
  FieldCount := 0;
  OriginX := Width*0.5;
  OriginY := Height*0.5;
  Power := S.V[ftPower];
  Load := 0.04 + 0.96*Power/100;
  Count := Round(S.V[ftCount]);
  if S.Layout = flSingle then Count := 1;
  PitchSin := Sin(DegToRad(S.V[ftPitch]));
  PitchCos := Cos(DegToRad(S.V[ftPitch]));
  RotSin := Sin(DegToRad(S.V[ftRotation]));
  RotCos := Cos(DegToRad(S.V[ftRotation]));
  ViewDepth := S.V[ftPerspective]*0.01/Max(420.0, Max(S.V[ftDiameter], S.V[ftSourceDepth])*0.9);
  Angle := DegToRad(S.V[ftWindDirection]);
  Gust := S.V[ftWindSpeed];
  if (Gust > 0) and (S.V[ftGust] > 0) then
  begin
    Gust := Gust*(1+(FireNoise(Time*S.V[ftGustSpeed]*0.01, 14, 605)*2-1)*S.V[ftGust]*0.007);
    Angle := Angle+(FireNoise(Time*S.V[ftGustSpeed]*0.006, 17, 605)-0.5)*S.V[ftGust]*0.009;
  end;
  WindX := Cos(Angle)*Gust;
  WindZ := Sin(Angle)*Gust;
  FlowTime := Time*S.V[ftRise]*0.01*(0.42+0.61*Load);
  FlickerTime := Time*S.V[ftFlicker]*0.01;
  FireOpacity := 1-S.V[ftFlameTransparency]*0.01;
  CoreColor := RGBVector(S.Colors[fcCore]);
  MiddleColor := RGBVector(S.Colors[fcMiddle]);
  OuterColor := RGBVector(S.Colors[fcOuter]);
  StartIndex := Min(Count-1, Floor(S.V[ftIgnitionStart]*Count*0.01));
  for I := 0 to Count-1 do
    Sources[I] := MakeSource(I);
  Source := Sources[StartIndex];
  IgniteDistance := 0;
  IgniteOrigin := Source.X*RotCos+Source.Z*RotSin;
  IgniteMin := IgniteOrigin;
  IgniteMax := IgniteOrigin;
  if (Power >= 1) and (Power < 2) and not (S.Layout in [flRing, flDoubleRing]) then
    for I := 0 to Count-1 do
    begin
      SourceAxis := Sources[I].X*RotCos+Sources[I].Z*RotSin;
      IgniteMin := Min(IgniteMin, SourceAxis);
      IgniteMax := Max(IgniteMax, SourceAxis);
      IgniteDistance := Max(IgniteDistance, Sqrt(Sqr(Sources[I].X-Source.X)+
        Sqr(Sources[I].Z-Source.Z)));
    end;
  for I := 0 to Count-1 do
    Sources[I].Lit := LitLevel(I);
  for I := 1 to Count-1 do
  begin
    Moving := Sources[I];
    J := I;
    // 挿入ソートで等しい奥行の順序を保つ。
    while (J > 0) and (Sources[J-1].Projected.Z > Moving.Projected.Z) do
    begin
      Sources[J] := Sources[J-1];
      Dec(J);
    end;
    Sources[J] := Moving;
  end;

  if (S.Smoke <> fmNone) and (S.V[ftSmokeAmount] > 0) and (S.V[ftSmokeWidth] > 0) then
  begin
    Smoke := S.V[ftSmokeAmount]*0.01*(1-S.V[ftSmokeTransparency]*0.01);
    SmokeLife := S.V[ftSmokeLife];
    SmokeStride := (Count+11) div 12;
    for I := 0 to Count-1 do
      if (Sources[I].Index mod SmokeStride) = 0 then
      begin
        if (S.Smoke in [fmBurning, fmBoth]) and (Power >= 1) then
          DrawSmoke(Sources[I], Smoke*Min(1.2, 0.18+Load*0.78)*Sources[I].Lit,
            SmokeLife, 0, 1);
        if (S.Smoke in [fmExtinction, fmBoth]) and (Activity.SmokeResidual > 0) then
          DrawSmoke(Sources[I], Smoke*Activity.SmokeResidual,
            Max(0.0, SmokeLife-Activity.SmokeAge), Activity.SmokeAge*0.92, 0.57);
      end;
  end;
  if S.Embers and (S.V[ftEmberStrength] > 0) and (S.V[ftEmberRadius] > 0) then
  begin
    EmberStride := (Count+63) div 64;
    for I := 0 to Count-1 do
      if (Sources[I].Index mod EmberStride) = 0 then
      begin
        Ember := Max(0.76*Load*Sources[I].Lit, Activity.EmberResidual)*S.V[ftEmberStrength]*0.01;
        Ember := Ember*(1 + (FireNoise(FlickerTime*0.65, Sources[I].Index, 204)-0.5)*
          S.V[ftEmberFlicker]*0.017);
        Radial(fkEmber, Sources[I].Projected, RGBVector($FFAE52), RGBVector(S.Colors[fcEmber]),
          S.V[ftEmberRadius]*Sources[I].Projected.W, S.V[ftEmberRadius]*Sources[I].Projected.W*0.58,
          Ember, Sources[I].Index+518);
      end;
  end;
  if (S.V[ftGlow] > 0) and (S.V[ftGlowRadius] > 0) and
    (FireOpacity > 0) and (S.V[ftDensity] > 0) and (S.V[ftHeight] > 0) and (S.V[ftWidth] > 0) then
  begin
    GlowStride := (Count+23) div 24;
    for I := 0 to Count-1 do
      if ((Sources[I].Index mod GlowStride) = 0) or (Sources[I].Index = StartIndex) then
      begin
        Glow := S.V[ftGlowRadius]*Sources[I].Projected.W;
        Center := Sources[I].Projected;
        Center.Y := Center.Y-S.V[ftHeight]*Sources[I].Projected.W*(0.09+0.14*Load)*Sources[I].Lit;
        Radial(fkGlow, Center, MiddleColor, OuterColor, Glow, Glow*1.24,
          S.V[ftGlow]*0.0029*Load*FireOpacity*Sources[I].Lit, Sources[I].Index+698);
      end;
  end;
  for I := 0 to Count-1 do DrawFlame(Sources[I]);
  DrawSparks;
  DrawIgnition(Source);
  if S.Haze and (S.V[ftHazeStrength] > 0) and (S.V[ftHazeRange] > 0) and (Power >= 1) then
  begin
    WidthSpan := S.V[ftWidth];
    if Count > 1 then
      if S.Layout in [flRing, flDoubleRing] then WidthSpan := S.V[ftDiameter]
      else WidthSpan := S.V[ftSourceWidth];
    Scene.Haze := Vector(OriginX+WindX*0.11, OriginY-(S.V[ftHazeRange]*0.43+
      S.V[ftHeight]*0.31*Load), WidthSpan*0.45+S.V[ftHazeRange]*0.44,
      S.V[ftHazeRange]*0.83);
    Scene.HazeParams := Vector(0, S.V[ftHazeStrength]*0.038*Min(1.45, Load),
      Time*S.V[ftHazeSpeed]*0.01, 0);
  end;
  Scene.Info.X := FieldCount;
end;

end.
