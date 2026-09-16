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
  Reverse.Analysis in 'src\Reverse.Analysis.pas',
  Reverse.Visual in 'src\Reverse.Visual.pas',
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
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
  I: Integer;
  UseGlobalSearchPaths: Boolean;
begin
  try
    ProjectFile := OptionValue('--project');
    Target := OptionValue('--unit');
    if (ProjectFile = '') or (Target = '') then
    begin
      Writeln('Usage: UnitBacktrace --project FILE.dproj --unit UnitName [--platform Win32|Win64] [--config Debug|Release] [--source-root DIR ...] [--output DIR] [--no-global-path]');
      ExitCode := 2;
      Exit;
    end;
    OutputDir := OptionValue('--output');
    if OutputDir = '' then OutputDir := TPath.Combine(GetCurrentDir, 'analysis-output');
    TDirectory.CreateDirectory(OutputDir);
    Logger := TFileLogger.Create(TPath.Combine(OutputDir, 'analysis.log'));
    Logger.Write('INFO', 'start', ProjectFile + ' | ' + Target);
    Writeln('Preparando projeto e descobrindo arquivos...');
    UseGlobalSearchPaths := True;
    for I := 1 to ParamCount do
      if SameText(ParamStr(I), '--no-global-path') then
        UseGlobalSearchPaths := False;
    Scope := TProjectScope.Create(ProjectFile, Logger,
      OptionValue('--platform'),
      UseGlobalSearchPaths, OptionValue('--config'),
      TMSBuildPathEvaluator.Create(Logger), OptionValues('--source-root'));
    try
      Writeln(Format('Arquivos descobertos: %d | %s | %s',
        [Scope.Files.Count, Scope.Platform, Scope.Config]));
      Analyzer := TAnalyzer.Create(TAstUnitParser.Create(
        Scope.SearchDirectories.ToArray, Logger, Scope.Defines.ToArray,
        Scope.Platform), Logger, TConsoleProgress.Create);
      try
        Analysis := Analyzer.Run(Scope, Target);
        try
          Writeln('Gravando resultado e log...');
          TOutputWriter.WriteFiles(Analysis, OutputDir);
          Writeln('Concluido: ' + OutputDir);
          Writeln('Abra no navegador: ' + TPath.Combine(OutputDir, 'graph.html'));
          if (Analysis.FallbackCount > 0) or (Analysis.FailedCount > 0) or
            Analysis.PathEvaluationWasFallback or
            (Analysis.UnresolvedCount > 0) or
            (Analysis.AmbiguousCount > 0) then ExitCode := 3;
        finally
          Analysis.Free;
        end;
      finally
        Analyzer.Free;
      end;
    finally
      Scope.Free;
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
