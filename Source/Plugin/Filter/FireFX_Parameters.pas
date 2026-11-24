unit FireFX_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// GUI項目を登録し、ホストの現在値を描画用の設定に読み出す。

interface

uses FireFX_Settings;

// DLLが所有する設定項目を登録する。描画からは項目を書き換えない。
procedure RegisterFireParameters;
function ReadFireSettings: TFireSettings;

implementation

uses System.SysUtils, System.Math, Winapi.Windows, AviUtl2FilterTypes, PluginFilterTable;

type
  TSelector = (selPreset, selLayout, selIgnition, selSpread, selObstacle, selSmoke);
  TToggle = (togSparks, togEmbers, togHaze);
  TItemChange = record
    Name: PWideChar;
    Value, Previous: UTF8String;
    HasPrevious: Boolean;
  end;

const
  SELECT_NAMES: array[TSelector] of PWideChar =
    ('プリセット選択', '配置方式', '点火方式', '点火方向', '干渉形状', '煙の発生方式');
  SELECT_GROUPS: array[TSelector] of TFireGroup =
    (fgPreset, fgSources, fgIgnition, fgIgnition, fgObstacle, fgSmoke);
  TOGGLE_NAMES: array[TToggle] of PWideChar = ('火の粉を有効にする', '赤熱を有効にする', '陽炎を有効にする');
  TOGGLE_GROUPS: array[TToggle] of TFireGroup = (fgSparks, fgEmbers, fgHaze);
  COLOR_GROUPS: array[TFireColor] of TFireGroup =
    (fgColors, fgColors, fgColors, fgSmoke, fgEmbers);

var
  Tracks: array[TFireTrack] of TFILTER_ITEM_TRACK;
  Selectors: array[TSelector] of TFILTER_ITEM_SELECT;
  Options: array[TSelector, 0..Ord(High(TFirePreset))+1] of TFILTER_ITEM_SELECT_ITEM;
  OptionCounts: array[TSelector] of Integer;
  Toggles: array[TToggle] of TFILTER_ITEM_CHECK;
  Colors: array[TFireColor] of TFILTER_ITEM_COLOR;
  Groups, GroupEnds: array[TFireGroup] of TFILTER_ITEM_GROUP;
  ApplyButton: TFILTER_ITEM_BUTTON;

function SelectorValue(const S: TFireSettings; Selector: TSelector): Integer;
begin
  case Selector of
    selLayout: Result := Ord(S.Layout);
    selIgnition: Result := Ord(S.Ignition);
    selSpread: Result := Ord(S.Spread);
    selObstacle: Result := Ord(S.Obstacle);
    selSmoke: Result := Ord(S.Smoke);
  else
    Result := Ord(fpCandle);
  end;
end;

function ToggleValue(const S: TFireSettings; Toggle: TToggle): Boolean;
begin
  case Toggle of
    togSparks: Result := S.Sparks;
    togEmbers: Result := S.Embers;
  else
    Result := S.Haze;
  end;
end;

function ReadSelector(Selector: TSelector): Integer;
begin
  Result := EnsureRange(Selectors[Selector].Value, 0, OptionCounts[Selector]-1);
end;

function SelectedPreset(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect: PWideChar): TFirePreset;
var
  Value: PAnsiChar;
  Name: UTF8String;
  Preset: TFirePreset;
begin
  if Assigned(Edit^.GetObjectItemValue) then
  begin
    Value := Edit^.GetObjectItemValue(Obj, Effect, SELECT_NAMES[selPreset]);
    if Value <> nil then
    begin
      Name := UTF8String(Value);
      for Preset := Low(TFirePreset) to High(TFirePreset) do
        if Name = UTF8String(string(FIRE_PRESET_NAMES[Preset])) then
          Exit(Preset);
    end;
  end;
  Result := TFirePreset(ReadSelector(selPreset));
end;

procedure ApplyPreset(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect, Item: PWideChar); cdecl;
var
  S: TFireSettings;
  Track: TFireTrack;
  Selector: TSelector;
  Color: TFireColor;
  Toggle: TToggle;
  Changes: array[0..Ord(High(TFireTrack))+Ord(High(TSelector))+
    Ord(High(TFireColor))+Ord(High(TToggle))+3] of TItemChange;
  Count, I, J: Integer;

  procedure AddChange(Name: PWideChar; const Value: UTF8String);
  var
    Previous: PAnsiChar;
  begin
    Changes[Count].Name := Name;
    Changes[Count].Value := Value;
    Changes[Count].HasPrevious := False;
    if Assigned(Edit^.GetObjectItemValue) then
    begin
      Previous := Edit^.GetObjectItemValue(Obj, Effect, Name);
      if Previous <> nil then
      begin
        Changes[Count].Previous := UTF8String(Previous);
        Changes[Count].HasPrevious := True;
      end;
    end;
    Inc(Count);
  end;

begin
  if (Edit = nil) or (Obj = nil) or (Effect = nil) or
    not Assigned(Edit^.SetObjectItemValue) then Exit;
  try
    S := FirePreset(SelectedPreset(Edit, Obj, Effect));
    Count := 0;
    for Track := Low(TFireTrack) to High(TFireTrack) do
      AddChange(FIRE_TRACKS[Track].Name,
        UTF8String(FloatToStr(S.V[Track], TFormatSettings.Invariant)));
    for Selector := Succ(selPreset) to High(TSelector) do
      AddChange(SELECT_NAMES[Selector],
        UTF8String(string(Options[Selector, SelectorValue(S, Selector)].Name)));
    for Toggle := Low(TToggle) to High(TToggle) do
      AddChange(TOGGLE_NAMES[Toggle], UTF8String(IntToStr(Ord(ToggleValue(S, Toggle)))));
    for Color := Low(TFireColor) to High(TFireColor) do
      AddChange(FIRE_COLOR_NAMES[Color], UTF8String(IntToHex(S.Colors[Color], 6)));
    for I := 0 to Count-1 do
      if not Edit^.SetObjectItemValue(Obj, Effect, Changes[I].Name, PAnsiChar(Changes[I].Value)) then
      begin
        for J := I-1 downto 0 do
          if Changes[J].HasPrevious then
            Edit^.SetObjectItemValue(Obj, Effect, Changes[J].Name, PAnsiChar(Changes[J].Previous));
        raise EInvalidOp.CreateFmt('Could not apply preset item: %s', [string(Changes[I].Name)]);
      end;
  except
    on E: Exception do OutputDebugString(PWideChar('SYNC_FireFX preset: ' + E.Message));
  end;
end;

procedure SetOptions(Selector: TSelector; const Names: array of PWideChar);
var
  I: Integer;
begin
  OptionCounts[Selector] := Length(Names);
  for I := 0 to High(Names) do
  begin
    Options[Selector, I].Name := Names[I];
    Options[Selector, I].Value := I;
  end;
  Options[Selector, Length(Names)].Name := nil;
end;

procedure RegisterFireParameters;
var
  S: TFireSettings;
  Group: TFireGroup;
  Track: TFireTrack;
  Selector: TSelector;
  Color: TFireColor;
  Toggle: TToggle;
  RGB: Cardinal;
begin
  S := FirePreset(fpCandle);
  SetOptions(selPreset, FIRE_PRESET_NAMES);
  SetOptions(selLayout, FIRE_LAYOUT_NAMES);
  SetOptions(selIgnition, FIRE_IGNITION_NAMES);
  SetOptions(selSpread, FIRE_SPREAD_NAMES);
  SetOptions(selObstacle, FIRE_OBSTACLE_NAMES);
  SetOptions(selSmoke, FIRE_SMOKE_NAMES);
  for Group := Low(TFireGroup) to High(TFireGroup) do
  begin
    AddGroup(Groups[Group], FIRE_GROUP_NAMES[Group], Ord(Group in [fgPreset, fgPower]));
    for Selector := Low(TSelector) to High(TSelector) do
      if SELECT_GROUPS[Selector] = Group then
        AddSelect(Selectors[Selector], SELECT_NAMES[Selector],
          SelectorValue(S, Selector), @Options[Selector, 0]);
    if Group = fgPreset then AddButton(ApplyButton, '設定', ApplyPreset);
    for Toggle := Low(TToggle) to High(TToggle) do
      if TOGGLE_GROUPS[Toggle] = Group then
        AddCheck(Toggles[Toggle], TOGGLE_NAMES[Toggle], Ord(ToggleValue(S, Toggle)));
    for Track := Low(TFireTrack) to High(TFireTrack) do
      if FIRE_TRACKS[Track].Group = Group then
        AddTrack(Tracks[Track], FIRE_TRACKS[Track].Name, S.V[Track],
          FIRE_TRACKS[Track].Min, FIRE_TRACKS[Track].Max, FIRE_TRACKS[Track].Step);
    for Color := Low(TFireColor) to High(TFireColor) do
      if COLOR_GROUPS[Color] = Group then
      begin
        RGB := S.Colors[Color];
        AddColor(Colors[Color], FIRE_COLOR_NAMES[Color],
          Byte(RGB and 255), Byte((RGB shr 8) and 255), Byte(RGB shr 16));
      end;
    AddGroup(GroupEnds[Group], '', 0);
  end;
end;

function ReadFireSettings: TFireSettings;
var
  Track: TFireTrack;
  Color: TFireColor;
begin
  for Track := Low(TFireTrack) to High(TFireTrack) do
    Result.V[Track] := ClampFireTrack(Track, Tracks[Track].Value);
  for Color := Low(TFireColor) to High(TFireColor) do
    Result.Colors[Color] := (Cardinal(Colors[Color].R) shl 16) or
      (Cardinal(Colors[Color].G) shl 8) or Colors[Color].B;
  Result.Layout := TFireLayout(ReadSelector(selLayout));
  Result.Ignition := TFireIgnition(ReadSelector(selIgnition));
  Result.Spread := TFireSpread(ReadSelector(selSpread));
  Result.Obstacle := TFireObstacle(ReadSelector(selObstacle));
  Result.Smoke := TFireSmoke(ReadSelector(selSmoke));
  Result.Sparks := Toggles[togSparks].Value <> 0;
  Result.Embers := Toggles[togEmbers].Value <> 0;
  Result.Haze := Toggles[togHaze].Value <> 0;
end;

end.
