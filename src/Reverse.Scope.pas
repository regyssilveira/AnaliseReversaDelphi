// SPDX-License-Identifier: Apache-2.0

unit Reverse.Scope;

interface

uses System.Generics.Collections, Reverse.Domain;

type
  TProjectScope = class
  private
    FFiles: TList<string>;
    FSeen: TDictionary<string, Boolean>;
    FSearchDirectories: TList<string>;
    FNamespaceOrder: TList<string>;
    FLogger: ILogger;
    FGlobalPaths: IGlobalSourcePathProvider;
    FRoot: string;
    FProgramFile: string;
    FPlatform: string;
    FConfig: string;
    FPathEvaluator: IProjectPathEvaluator;
    FPathEvaluationWasFallback: Boolean;
    procedure ScanDirectory(const Directory: string; Recursive: Boolean);
    procedure ReadSearchPaths(const ProjectFile: string);
    procedure ReadProgramReferences;
    procedure ReadGlobalSearchPaths(const Platform: string);
  public
    constructor Create(const ProjectFile: string; const Logger: ILogger;
      const Platform: string = '';
      UseGlobalSearchPaths: Boolean = True; const Config: string = '';
      const PathEvaluator: IProjectPathEvaluator = nil;
      const AdditionalSourceRoots: TArray<string> = nil;
      const GlobalPaths: IGlobalSourcePathProvider = nil);
    destructor Destroy; override;
    property Files: TList<string> read FFiles;
    property ProgramFile: string read FProgramFile;
    property ProjectRoot: string read FRoot;
    property SearchDirectories: TList<string> read FSearchDirectories;
    property NamespaceOrder: TList<string> read FNamespaceOrder;
    property Platform: string read FPlatform;
    property Config: string read FConfig;
    property PathEvaluationWasFallback: Boolean read FPathEvaluationWasFallback;
  end;

implementation

uses System.SysUtils, System.IOUtils, System.RegularExpressions,
  Reverse.DelphiPaths;

constructor TProjectScope.Create(const ProjectFile: string; const Logger: ILogger;
  const Platform: string; UseGlobalSearchPaths: Boolean; const Config: string;
  const PathEvaluator: IProjectPathEvaluator;
  const AdditionalSourceRoots: TArray<string>;
  const GlobalPaths: IGlobalSourcePathProvider);
var
  ProjectText: string;
  MainMatch: TMatch;
begin
  inherited Create;
  if not FileExists(ProjectFile) then
    raise Exception.Create('Project not found: ' + ProjectFile);
  FLogger := Logger;
  FPathEvaluator := PathEvaluator;
  FGlobalPaths := GlobalPaths;
  if (FGlobalPaths = nil) and UseGlobalSearchPaths then
    FGlobalPaths := TDelphiPathProvider.Create(Logger);
  FRoot := ExtractFilePath(ExpandFileName(ProjectFile));
  FProgramFile := ChangeFileExt(ExpandFileName(ProjectFile), '.dpr');
  ProjectText := TFile.ReadAllText(ProjectFile);
  FPlatform := Platform;
  if FPlatform = '' then
  begin
    var PlatformMatch := TRegEx.Match(ProjectText,
      '<Platform[^>]*>(Win32|Win64)</Platform>', [roIgnoreCase]);
    if PlatformMatch.Success then FPlatform := PlatformMatch.Groups[1].Value
    else FPlatform := 'Win64';
  end;
  if not SameText(FPlatform, 'Win32') and not SameText(FPlatform, 'Win64') then
    raise Exception.Create('Unsupported platform: ' + FPlatform);
  FConfig := Config;
  if FConfig = '' then
  begin
    var ConfigMatch := TRegEx.Match(ProjectText,
      '<Config[^>]*>(Debug|Release)</Config>', [roIgnoreCase]);
    if ConfigMatch.Success then FConfig := ConfigMatch.Groups[1].Value
    else FConfig := 'Debug';
  end;
  if not SameText(FConfig, 'Debug') and not SameText(FConfig, 'Release') then
    raise Exception.Create('Unsupported config: ' + FConfig);
  FLogger.Write('INFO', 'platform', FPlatform);
  FLogger.Write('INFO', 'config', FConfig);
  MainMatch := TRegEx.Match(ProjectText, '<MainSource>(.*?)</MainSource>',
    [roIgnoreCase, roSingleLine]);
  if MainMatch.Success then
    FProgramFile := TPath.GetFullPath(TPath.Combine(FRoot,
      MainMatch.Groups[1].Value.Replace('&amp;', '&')));
  if not FileExists(FProgramFile) then
    raise Exception.Create('DPR not found: ' + FProgramFile);
  FFiles := TList<string>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
  FNamespaceOrder := TList<string>.Create;
  FSearchDirectories := TList<string>.Create;
  FSearchDirectories.Add(FRoot);
  var NamespaceMatch := TRegEx.Match(ProjectText,
    '<DCC_Namespace>(.*?)</DCC_Namespace>', [roIgnoreCase, roSingleLine]);
  if NamespaceMatch.Success then
    for var NamespaceName in NamespaceMatch.Groups[1].Value.Split([';']) do
      if (NamespaceName <> '') and not NamespaceName.Contains('$(') then
        FNamespaceOrder.Add(Trim(NamespaceName));
  if FNamespaceOrder.Count = 0 then
  begin
    FNamespaceOrder.Add('System');
    FNamespaceOrder.Add('Winapi');
    FNamespaceOrder.Add('Vcl');
    FNamespaceOrder.Add('Data');
    FNamespaceOrder.Add('Xml');
  end;
  ScanDirectory(FRoot, True);
  ReadSearchPaths(ProjectFile);
  if UseGlobalSearchPaths then ReadGlobalSearchPaths(FPlatform);
  for var SourceRoot in AdditionalSourceRoots do
  begin
    var RootPath := TPath.GetFullPath(SourceRoot);
    if not DirectoryExists(RootPath) then
      raise Exception.Create('Source root not found: ' + RootPath);
    if not FSearchDirectories.Contains(RootPath) then
      FSearchDirectories.Add(RootPath);
    ScanDirectory(RootPath, True);
    FLogger.Write('INFO', 'source-root', RootPath);
  end;
  ReadProgramReferences;
  FFiles.Add(FProgramFile);
  FLogger.Write('INFO', 'scope', Format('%d source files discovered', [FFiles.Count]));
end;

procedure TProjectScope.ReadProgramReferences;
var
  Text, PathName: string;
  Match: TMatch;
begin
  Text := TFile.ReadAllText(FProgramFile);
  for Match in TRegEx.Matches(Text, 'in\s+''([^'']+)''', [roIgnoreCase]) do
  begin
    PathName := Match.Groups[1].Value;
    if not SameText(ExtractFileExt(PathName), '.pas') then Continue;
    if not TPath.IsPathRooted(PathName) then
      PathName := TPath.GetFullPath(TPath.Combine(
        ExtractFilePath(FProgramFile), PathName));
    if FileExists(PathName) and not FSeen.ContainsKey(LowerCase(PathName)) then
    begin
      FSeen.Add(LowerCase(PathName), True);
      FFiles.Add(PathName);
    end
    else if not FileExists(PathName) then
      FLogger.Write('WARN', 'program-reference-missing', PathName);
  end;
end;

destructor TProjectScope.Destroy;
begin
  FFiles.Free;
  FSeen.Free;
  FNamespaceOrder.Free;
  FSearchDirectories.Free;
  inherited;
end;

procedure TProjectScope.ScanDirectory(const Directory: string; Recursive: Boolean);
var
  FileName: string;
  SearchOption: TSearchOption;
begin
  if not DirectoryExists(Directory) then Exit;
  if Recursive then SearchOption := TSearchOption.soAllDirectories
  else SearchOption := TSearchOption.soTopDirectoryOnly;
  for FileName in TDirectory.GetFiles(Directory, '*.pas', SearchOption) do
    if not FSeen.ContainsKey(LowerCase(FileName)) then
    begin
      FSeen.Add(LowerCase(FileName), True);
      FFiles.Add(FileName);
    end;
end;

procedure TProjectScope.ReadSearchPaths(const ProjectFile: string);
var
  Text, Raw, Item, PathName, PathKind: string;
  Match: TMatch;
  Evaluated: Boolean;
  UnitPaths, IncludePaths: TArray<string>;
  procedure AddPath(const Value, Kind: string);
  begin
    PathName := Trim(Value);
    if PathName = '' then Exit;
    if PathName.Contains('$(') then
    begin
      FLogger.Write('WARN', 'unresolved-macro', PathName);
      Exit;
    end;
    if not TPath.IsPathRooted(PathName) then
      PathName := TPath.GetFullPath(TPath.Combine(FRoot, PathName));
    if DirectoryExists(PathName) then
    begin
      if not FSearchDirectories.Contains(PathName) then
        FSearchDirectories.Add(PathName);
      if SameText(Kind, 'UnitSearchPath') then
        ScanDirectory(PathName, False);
    end
    else FLogger.Write('WARN', 'search-path-missing', PathName);
  end;
begin
  Text := TFile.ReadAllText(ProjectFile);
  Evaluated := False;
  if FPathEvaluator <> nil then
    try
      UnitPaths := FPathEvaluator.Evaluate(ProjectFile, FConfig, FPlatform,
        'DCC_UnitSearchPath');
      IncludePaths := FPathEvaluator.Evaluate(ProjectFile, FConfig, FPlatform,
        'DCC_IncludePath');
      for Raw in UnitPaths do
        for Item in Raw.Split([';']) do AddPath(Item, 'UnitSearchPath');
      for Raw in IncludePaths do
        for Item in Raw.Split([';']) do AddPath(Item, 'IncludePath');
      Evaluated := True;
    except
      on E: Exception do
        FLogger.Write('WARN', 'msbuild-fallback', E.Message);
    end;
  if not Evaluated then
  begin
    FPathEvaluationWasFallback := FPathEvaluator <> nil;
    for Match in TRegEx.Matches(Text,
      '<DCC_(UnitSearchPath|IncludePath)>(.*?)</DCC_\1>',
      [roIgnoreCase, roSingleLine]) do
  begin
    PathKind := Match.Groups[1].Value;
    Raw := Match.Groups[2].Value.Replace('&amp;', '&');
    for Item in Raw.Split([';']) do AddPath(Item, PathKind);
  end;
  end;
  for Match in TRegEx.Matches(Text, '<DCCReference\s+Include="(.*?)"',
    [roIgnoreCase, roSingleLine]) do
  begin
    PathName := Match.Groups[1].Value.Replace('&amp;', '&');
    if not SameText(ExtractFileExt(PathName), '.pas') then Continue;
    if PathName.Contains('$(') then
    begin
      FLogger.Write('WARN', 'reference-macro', PathName);
      Continue;
    end;
    if not TPath.IsPathRooted(PathName) then
      PathName := TPath.GetFullPath(TPath.Combine(FRoot, PathName));
    if FileExists(PathName) and not FSeen.ContainsKey(LowerCase(PathName)) then
    begin
      FSeen.Add(LowerCase(PathName), True);
      FFiles.Add(PathName);
    end;
  end;
end;

procedure TProjectScope.ReadGlobalSearchPaths(const Platform: string);
var
  PathName: string;
begin
  if FGlobalPaths = nil then Exit;
  for PathName in FGlobalPaths.Paths(Platform, FRoot) do
  begin
    if not DirectoryExists(PathName) then
    begin
      FLogger.Write('WARN', 'global-search-path-missing', PathName);
      Continue;
    end;
    if not FSearchDirectories.Contains(PathName) then
      FSearchDirectories.Add(PathName);
    ScanDirectory(PathName, False);
  end;
end;

end.
