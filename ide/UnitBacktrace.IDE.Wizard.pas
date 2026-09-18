// SPDX-License-Identifier: Apache-2.0

unit UnitBacktrace.IDE.Wizard;

interface

uses ToolsAPI;

type
  TProjectMapWizard = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  public
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    function GetMenuText: string;
    procedure Execute;
  end;

  TCurrentUnitWizard = class(TNotifierObject, IOTAWizard, IOTAMenuWizard)
  public
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    function GetMenuText: string;
    procedure Execute;
  end;

procedure Register;

implementation

uses System.SysUtils, System.IOUtils, Vcl.Dialogs, Reverse.Runner,
  Reverse.Cli, UnitBacktrace.IDE.Progress;

function ActiveProjectFile: string;
var
  Services: IOTAModuleServices;
  Project: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then Exit;
  Project := Services.GetActiveProject;
  if Project <> nil then Result := Project.FileName;
end;

function CurrentUnitName: string;
var
  Services: IOTAModuleServices;
  Module: IOTAModule;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then Exit;
  Module := Services.CurrentModule;
  if (Module <> nil) and SameText(ExtractFileExt(Module.FileName), '.pas') then
    Result := ChangeFileExt(ExtractFileName(Module.FileName), '');
end;

procedure Analyze(const TargetUnit: string);
var
  Request: TAnalysisRequest;
  ProjectFile, OutputRoot, OutputDir: string;
begin
  ProjectFile := ActiveProjectFile;
  if (ProjectFile = '') or not SameText(ExtractFileExt(ProjectFile), '.dproj') then
    raise Exception.Create('Nenhum projeto Delphi ativo foi encontrado.');
  if (TargetUnit <> '') and not SameText(ExtractFileExt(
    (BorlandIDEServices as IOTAModuleServices).CurrentModule.FileName), '.pas') then
    raise Exception.Create('Abra uma unit .pas antes de executar o backtrace.');

  OutputRoot := ExcludeTrailingPathDelimiter(ExtractFilePath(ProjectFile));
  if TargetUnit = '' then
    OutputDir := TConsoleReport.DefaultProjectMapOutputDirectory(
      OutputRoot, ProjectFile)
  else
    OutputDir := TConsoleReport.DefaultOutputDirectory(
      OutputRoot, ProjectFile, TargetUnit);
  Request := Default(TAnalysisRequest);
  Request.ProjectFile := ProjectFile;
  Request.TargetUnit := TargetUnit;
  Request.UseGlobalSearchPaths := True;
  TAnalysisProgressForm.StartAnalysis(Request, OutputDir);
end;

procedure ExecuteSafely(const TargetUnit: string);
begin
  try
    Analyze(TargetUnit);
  except
    on E: Exception do
      MessageDlg('Delphi Unit Backtrace' + sLineBreak + sLineBreak + E.Message,
        mtError, [mbOK], 0);
  end;
end;

procedure Register;
begin
  RegisterPackageWizard(TProjectMapWizard.Create);
  RegisterPackageWizard(TCurrentUnitWizard.Create);
end;

procedure TProjectMapWizard.Execute;
begin
  ExecuteSafely('');
end;

function TProjectMapWizard.GetIDString: string;
begin
  Result := 'DelphiUnitBacktrace.ProjectMap';
end;

function TProjectMapWizard.GetMenuText: string;
begin
  Result := 'Delphi Unit Backtrace - Mapear projeto atual';
end;

function TProjectMapWizard.GetName: string;
begin
  Result := 'Mapa de dependências do projeto';
end;

function TProjectMapWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TCurrentUnitWizard.Execute;
var
  UnitName: string;
begin
  UnitName := CurrentUnitName;
  if UnitName = '' then
    MessageDlg('Abra uma unit .pas antes de executar o backtrace.',
      mtInformation, [mbOK], 0)
  else
    ExecuteSafely(UnitName);
end;

function TCurrentUnitWizard.GetIDString: string;
begin
  Result := 'DelphiUnitBacktrace.CurrentUnit';
end;

function TCurrentUnitWizard.GetMenuText: string;
begin
  Result := 'Delphi Unit Backtrace - Analisar unit atual';
end;

function TCurrentUnitWizard.GetName: string;
begin
  Result := 'Backtrace da unit atual';
end;

function TCurrentUnitWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

end.
