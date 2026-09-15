// SPDX-License-Identifier: Apache-2.0

unit Reverse.DelphiPaths;

interface

uses Reverse.Domain;

type
  TDelphiPathProvider = class(TInterfacedObject, IGlobalSourcePathProvider)
  private
    FLogger: ILogger;
  public
    constructor Create(const Logger: ILogger);
    function Paths(const Platform, ProjectRoot: string): TArray<string>;
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Classes,
  System.Generics.Collections, System.RegularExpressions, System.Win.Registry,
  Winapi.Windows;

constructor TDelphiPathProvider.Create(const Logger: ILogger);
begin
  inherited Create;
  FLogger := Logger;
end;

function TDelphiPathProvider.Paths(const Platform,
  ProjectRoot: string): TArray<string>;
var
  Registry: TRegistry;
  Names: TStringList;
  Variables: TDictionary<string, string>;
  Directories: TList<string>;
  Raw, BrowseRaw, BdsRoot, Name: string;
  Match: TMatch;
  function ExpandVariables(const Source: string): string;
  var
    VariableMatch: TMatch;
    VariableName, Value: string;
    I: Integer;
  begin
    Result := Source;
    for I := 1 to 8 do
    begin
      VariableMatch := TRegEx.Match(Result, '\$\(([^)]+)\)');
      if not VariableMatch.Success then Break;
      VariableName := LowerCase(VariableMatch.Groups[1].Value);
      if (VariableName = 'dcc_unitsearchpath') or
        (VariableName = 'dcc_includepath') then Value := ''
      else if VariableName = 'platform' then Value := Platform
      else if not Variables.TryGetValue(VariableName, Value) then
        Value := GetEnvironmentVariable(VariableMatch.Groups[1].Value);
      if (Value = '') and (VariableName <> 'dcc_unitsearchpath') and
        (VariableName <> 'dcc_includepath') then
      begin
        FLogger.Write('WARN', 'unresolved-path-variable', Source);
        Exit('');
      end;
      Result := Result.Replace(VariableMatch.Value, Value);
    end;
    if Result.Contains('$(') then
    begin
      FLogger.Write('WARN', 'recursive-path-variable', Source);
      Result := '';
    end;
  end;
  procedure AddDirectories(const Values: string);
  var
    Item, PathName: string;
  begin
    for Item in Values.Split([';']) do
    begin
      PathName := Trim(ExpandVariables(Item));
      if PathName = '' then Continue;
      if not TPath.IsPathRooted(PathName) then
        PathName := TPath.GetFullPath(TPath.Combine(ProjectRoot, PathName));
      if DirectoryExists(PathName) and not Directories.Contains(PathName) then
        Directories.Add(PathName);
    end;
  end;
begin
  Registry := TRegistry.Create(KEY_READ or KEY_WOW64_32KEY);
  Names := TStringList.Create;
  Variables := TDictionary<string, string>.Create;
  Directories := TList<string>.Create;
  try
    Registry.RootKey := HKEY_LOCAL_MACHINE;
    if Registry.OpenKeyReadOnly('SOFTWARE\Embarcadero\BDS\37.0') then
    begin
      BdsRoot := Registry.ReadString('RootDir');
      Variables.AddOrSetValue('bds', BdsRoot);
      Variables.AddOrSetValue('bdslib', TPath.Combine(BdsRoot, 'lib'));
      Registry.CloseKey;
    end;
    Registry.RootKey := HKEY_CURRENT_USER;
    if not Variables.ContainsKey('bds') and
      Registry.OpenKeyReadOnly('Software\Embarcadero\BDS\37.0') then
    begin
      BdsRoot := Registry.ReadString('RootDir');
      Variables.AddOrSetValue('bds', BdsRoot);
      Variables.AddOrSetValue('bdslib', TPath.Combine(BdsRoot, 'lib'));
      Registry.CloseKey;
    end;
    if Registry.OpenKeyReadOnly('Software\Embarcadero\BDS\37.0\Environment Variables') then
    begin
      Registry.GetValueNames(Names);
      for Name in Names do
        if Registry.GetDataType(Name) in [rdString, rdExpandString] then
          Variables.AddOrSetValue(LowerCase(Name), Registry.ReadString(Name));
      Registry.CloseKey;
    end;
    if not Registry.OpenKeyReadOnly('Software\Embarcadero\BDS\37.0\Library\' + Platform) then
    begin
      FLogger.Write('WARN', 'global-search-path-unavailable', Platform);
      Exit(nil);
    end;
    Raw := Registry.ReadString('Search Path');
    BrowseRaw := '';
    if Registry.ValueExists('Browsing Path') then
      BrowseRaw := Registry.ReadString('Browsing Path');
    Registry.CloseKey;
    if not Variables.ContainsKey('dxvcl') then
    begin
      Match := TRegEx.Match(Raw,
        '([A-Za-z]:\\[^;]*?\\DevExpress)\\Library\\', [roIgnoreCase]);
      if Match.Success then
      begin
        Variables.Add('dxvcl', Match.Groups[1].Value);
        FLogger.Write('INFO', 'inferred-path-variable',
          'DXVCL | ' + Match.Groups[1].Value);
      end;
    end;
    FLogger.Write('INFO', 'global-search-path', Platform + ' | ' +
      Length(Raw.Split([';'])).ToString + ' entries');
    AddDirectories(Raw);
    FLogger.Write('INFO', 'global-browsing-path',
      Length(BrowseRaw.Split([';'])).ToString + ' entries');
    AddDirectories(BrowseRaw);
    Result := Directories.ToArray;
  finally
    Directories.Free;
    Variables.Free;
    Names.Free;
    Registry.Free;
  end;
end;

end.
