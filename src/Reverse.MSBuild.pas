// SPDX-License-Identifier: Apache-2.0

unit Reverse.MSBuild;

interface

uses Reverse.Domain;

type
  TMSBuildPathEvaluator = class(TInterfacedObject, IProjectPathEvaluator)
  private
    FLogger: ILogger;
    function FindBdsRoot: string;
  public
    constructor Create(const Logger: ILogger);
    function Evaluate(const ProjectFile, Config, Platform,
      PropertyName: string): TArray<string>;
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Win.Registry, Winapi.Windows;

function XmlValue(const Value: string): string;
begin
  Result := Value.Replace('&', '&amp;').Replace('"', '&quot;')
    .Replace('<', '&lt;').Replace('>', '&gt;');
end;

constructor TMSBuildPathEvaluator.Create(const Logger: ILogger);
begin
  inherited Create;
  FLogger := Logger;
end;

function TMSBuildPathEvaluator.FindBdsRoot: string;
var
  Registry: TRegistry;
begin
  Result := GetEnvironmentVariable('BDS');
  if Result <> '' then Exit;
  Registry := TRegistry.Create(KEY_READ or KEY_WOW64_32KEY);
  try
    Registry.RootKey := HKEY_LOCAL_MACHINE;
    if Registry.OpenKeyReadOnly('SOFTWARE\Embarcadero\BDS\37.0') then
    begin
      Result := Registry.ReadString('RootDir');
      Registry.CloseKey;
    end;
    if Result = '' then
    begin
      Registry.RootKey := HKEY_CURRENT_USER;
      if Registry.OpenKeyReadOnly('Software\Embarcadero\BDS\37.0') then
      begin
        Result := Registry.ReadString('RootDir');
        Registry.CloseKey;
      end;
    end;
  finally
    Registry.Free;
  end;
end;

function TMSBuildPathEvaluator.Evaluate(const ProjectFile, Config,
  Platform, PropertyName: string): TArray<string>;
var
  BuildExe, BdsRoot, ProbeFile, PathFile, BuildLog, Xml, CommandLine: string;
  Startup: TStartupInfo;
  ProcessInfo: TProcessInformation;
  WaitResult, ExitStatus: DWORD;
begin
  if not SameText(PropertyName, 'DCC_UnitSearchPath') and
    not SameText(PropertyName, 'DCC_IncludePath') and
    not SameText(PropertyName, 'DCC_Define') then
    raise Exception.Create('Unsupported MSBuild property: ' + PropertyName);
  BuildExe := TPath.Combine(GetEnvironmentVariable('WINDIR'),
    'Microsoft.NET\Framework\v4.0.30319\MSBuild.exe');
  BdsRoot := FindBdsRoot;
  if not FileExists(BuildExe) or (BdsRoot = '') then
    raise Exception.Create('MSBuild or Delphi 13 installation not found');
  ProbeFile := TPath.GetTempFileName;
  PathFile := ProbeFile + '.paths';
  BuildLog := ProbeFile + '.msbuild.log';
  try
    Xml := '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
      '<Import Project="' + XmlValue(ExpandFileName(ProjectFile)) + '" />' +
      '<Target Name="DumpPaths"><WriteLinesToFile File="' +
      XmlValue(PathFile) + '" Lines="$(' + PropertyName +
      ')" Overwrite="true" /></Target></Project>';
    TFile.WriteAllText(ProbeFile, Xml, TEncoding.UTF8);
    CommandLine := '"' + BuildExe + '" "' + ProbeFile +
      '" /nologo /v:quiet /t:DumpPaths "/p:Config=' + Config +
      '" "/p:Platform=' + Platform + '" "/p:BDS=' + BdsRoot +
      '" "/flp:logfile=' + BuildLog + ';verbosity=errors"';
    FillChar(Startup, SizeOf(Startup), 0);
    Startup.cb := SizeOf(Startup);
    Startup.dwFlags := STARTF_USESHOWWINDOW;
    Startup.wShowWindow := SW_HIDE;
    FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
    UniqueString(CommandLine);
    if not CreateProcess(PChar(BuildExe), PChar(CommandLine), nil, nil,
      False, CREATE_NO_WINDOW, nil, nil, Startup, ProcessInfo) then
      raise Exception.Create('Could not start MSBuild');
    try
      WaitResult := WaitForSingleObject(ProcessInfo.hProcess, 30000);
      if WaitResult <> WAIT_OBJECT_0 then
      begin
        TerminateProcess(ProcessInfo.hProcess, 1);
        raise Exception.Create('MSBuild evaluation timed out');
      end;
      if not GetExitCodeProcess(ProcessInfo.hProcess, ExitStatus) or
        (ExitStatus <> 0) then
      begin
        if FileExists(BuildLog) then
          raise Exception.Create('MSBuild evaluation failed: ' +
            Copy(TFile.ReadAllText(BuildLog), 1, 1024));
        raise Exception.Create('MSBuild evaluation failed (exit ' +
          ExitStatus.ToString + ')');
      end;
    finally
      CloseHandle(ProcessInfo.hThread);
      CloseHandle(ProcessInfo.hProcess);
    end;
    if FileExists(PathFile) then Result := TFile.ReadAllLines(PathFile)
    else Result := [];
    if FLogger <> nil then FLogger.Write('INFO', 'msbuild-evaluated',
      PropertyName + ' | ' + Length(Result).ToString + ' entries');
  finally
    if FileExists(PathFile) then TFile.Delete(PathFile);
    if FileExists(BuildLog) then TFile.Delete(BuildLog);
    if FileExists(ProbeFile) then TFile.Delete(ProbeFile);
  end;
end;

end.
