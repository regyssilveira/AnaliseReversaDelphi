// SPDX-License-Identifier: Apache-2.0

program UnitBacktrace;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Reverse.Domain in 'src\Reverse.Domain.pas',
  Reverse.AST in 'src\Reverse.AST.pas',
  Reverse.Graph in 'src\Reverse.Graph.pas',
  Reverse.Scope in 'src\Reverse.Scope.pas',
  Reverse.MSBuild in 'src\Reverse.MSBuild.pas',
  Reverse.DelphiPaths in 'src\Reverse.DelphiPaths.pas',
  Reverse.Log in 'src\Reverse.Log.pas',
  Reverse.Progress in 'src\Reverse.Progress.pas',
  Reverse.Runner in 'src\Reverse.Runner.pas',
  Reverse.Analysis in 'src\Reverse.Analysis.pas',
  Reverse.Visual in 'src\Reverse.Visual.pas',
  Reverse.ProjectMapVisual in 'src\Reverse.ProjectMapVisual.pas',
  Reverse.Cli in 'src\Reverse.Cli.pas',
  Reverse.Output in 'src\Reverse.Output.pas';

function OptionValue(const Option: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to ParamCount - 1 do
    if SameText(ParamStr(I), Option) then Exit(ParamStr(I + 1));
end;

function OptionValues(const Option: string): TArray<string>;
var
  Values: TList<string>;
  I: Integer;
begin
  Values := TList<string>.Create;
  try
    for I := 1 to ParamCount - 1 do
      if SameText(ParamStr(I), Option) then
        Values.Add(ParamStr(I + 1));
    Result := Values.ToArray;
  finally
    Values.Free;
  end;
end;

var
  ProjectFile, Target, OutputDir: string;
  Logger: ILogger;
  Analysis: TAnalysisResult;
  Request: TAnalysisRequest;
  I: Integer;
  UseGlobalSearchPaths: Boolean;
begin
  try
    ProjectFile := OptionValue('--project');
    Target := OptionValue('--unit');
    if ProjectFile = '' then
    begin
      Writeln('Usage: UnitBacktrace --project FILE.dproj [--unit UnitName] [--platform Win32|Win64] [--config Debug|Release] [--source-root DIR ...] [--output DIR] [--no-global-path]');
      Writeln('Without --unit, generates the complete dependency map from the DPR.');
      ExitCode := 2;
      Exit;
    end;
    OutputDir := OptionValue('--output');
    if OutputDir = '' then
      if Target = '' then
        OutputDir := TConsoleReport.DefaultProjectMapOutputDirectory(
          GetCurrentDir, ProjectFile)
      else
        OutputDir := TConsoleReport.DefaultOutputDirectory(GetCurrentDir,
          ProjectFile, Target);
    TDirectory.CreateDirectory(OutputDir);
    Logger := TFileLogger.Create(TPath.Combine(OutputDir, 'analysis.log'));
    if Target = '' then
      Logger.Write('INFO', 'start-project-map', ProjectFile)
    else Logger.Write('INFO', 'start', ProjectFile + ' | ' + Target);
    Writeln('Preparando projeto e descobrindo arquivos...');
    UseGlobalSearchPaths := True;
    for I := 1 to ParamCount do
      if SameText(ParamStr(I), '--no-global-path') then
        UseGlobalSearchPaths := False;
    Request.ProjectFile := ProjectFile;
    Request.TargetUnit := Target;
    Request.Platform := OptionValue('--platform');
    Request.Config := OptionValue('--config');
    Request.SourceRoots := OptionValues('--source-root');
    Request.UseGlobalSearchPaths := UseGlobalSearchPaths;
    Analysis := TAnalysisRunner.Run(Request, Logger, TConsoleProgress.Create);
    try
      Writeln(Format('Arquivos descobertos: %d | %s | %s',
        [Analysis.DiscoveredCount, Analysis.Platform, Analysis.Config]));
      Writeln('Gravando resultado e log...');
      TOutputWriter.WriteFiles(Analysis, OutputDir);
      for var SummaryLine in TConsoleReport.SummaryLines(Analysis) do
        Writeln(SummaryLine);
      Writeln('Concluido: ' + OutputDir);
      Writeln('Abra no navegador: ' + TPath.Combine(OutputDir, 'graph.html'));
      if TAnalysisRunner.IsPartial(Analysis) then ExitCode := 3;
    finally
      Analysis.Free;
    end;
  except
    on E: Exception do
    begin
      if Logger <> nil then Logger.Write('ERROR', 'fatal', E.Message);
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
