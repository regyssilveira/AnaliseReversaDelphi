unit Reverse.Scope;

interface

uses System.Generics.Collections, Reverse.Domain;

type
  TProjectScope = class
  private
    FFiles: TList<string>;
    FSeen: TDictionary<string, Boolean>;
    FLogger: ILogger;
    FRoot: string;
    FProgramFile: string;
    procedure ScanDirectory(const Directory: string);
    procedure ReadSearchPaths(const ProjectFile: string);
  public
    constructor Create(const ProjectFile: string; const Logger: ILogger);
    destructor Destroy; override;
    property Files: TList<string> read FFiles;
    property ProgramFile: string read FProgramFile;
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Classes, System.RegularExpressions;

constructor TProjectScope.Create(const ProjectFile: string; const Logger: ILogger);
var
  ProjectText: string;
  MainMatch: TMatch;
begin
  inherited Create;
  if not FileExists(ProjectFile) then
    raise Exception.Create('Project not found: ' + ProjectFile);
  FLogger := Logger;
  FRoot := ExtractFilePath(ExpandFileName(ProjectFile));
  FProgramFile := ChangeFileExt(ExpandFileName(ProjectFile), '.dpr');
  ProjectText := TFile.ReadAllText(ProjectFile);
  MainMatch := TRegEx.Match(ProjectText, '<MainSource>(.*?)</MainSource>',
    [roIgnoreCase, roSingleLine]);
  if MainMatch.Success then
    FProgramFile := TPath.GetFullPath(TPath.Combine(FRoot,
      MainMatch.Groups[1].Value.Replace('&amp;', '&')));
  if not FileExists(FProgramFile) then
    raise Exception.Create('DPR not found: ' + FProgramFile);
  FFiles := TList<string>.Create;
  FSeen := TDictionary<string, Boolean>.Create;
  ScanDirectory(FRoot);
  ReadSearchPaths(ProjectFile);
  FFiles.Add(FProgramFile);
  FLogger.Write('INFO', 'scope', Format('%d source files discovered', [FFiles.Count]));
end;

destructor TProjectScope.Destroy;
begin
  FFiles.Free;
  FSeen.Free;
  inherited;
end;

procedure TProjectScope.ScanDirectory(const Directory: string);
var
  FileName: string;
begin
  if not DirectoryExists(Directory) then Exit;
  for FileName in TDirectory.GetFiles(Directory, '*.pas', TSearchOption.soAllDirectories) do
    if not FSeen.ContainsKey(LowerCase(FileName)) then
    begin
      FSeen.Add(LowerCase(FileName), True);
      FFiles.Add(FileName);
    end;
end;

procedure TProjectScope.ReadSearchPaths(const ProjectFile: string);
var
  Text, Raw, Item, PathName: string;
  Match: TMatch;
begin
  Text := TFile.ReadAllText(ProjectFile);
  for Match in TRegEx.Matches(Text, '<DCC_UnitSearchPath>(.*?)</DCC_UnitSearchPath>',
    [roIgnoreCase, roSingleLine]) do
  begin
    Raw := Match.Groups[1].Value.Replace('&amp;', '&');
    for Item in Raw.Split([';']) do
    begin
      PathName := Trim(Item);
      if PathName = '' then Continue;
      if PathName.Contains('$(') then
      begin
        FLogger.Write('WARN', 'unresolved-macro', PathName);
        Continue;
      end;
      if not TPath.IsPathRooted(PathName) then
        PathName := TPath.GetFullPath(TPath.Combine(FRoot, PathName));
      if DirectoryExists(PathName) then ScanDirectory(PathName)
      else FLogger.Write('WARN', 'search-path-missing', PathName);
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

end.
