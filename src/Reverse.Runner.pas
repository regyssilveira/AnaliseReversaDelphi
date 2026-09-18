// SPDX-License-Identifier: Apache-2.0

unit Reverse.Runner;

interface

uses Reverse.Domain, Reverse.Analysis;

type
  TAnalysisRequest = record
    ProjectFile: string;
    TargetUnit: string;
    Platform: string;
    Config: string;
    SourceRoots: TArray<string>;
    UseGlobalSearchPaths: Boolean;
    Cancellation: IAnalysisCancellation;
  end;

  TAnalysisRunner = class
  public
    class function Run(const Request: TAnalysisRequest;
      const Logger: ILogger; const Progress: IAnalysisProgress = nil):
      TAnalysisResult; static;
    class function IsPartial(const Analysis: TAnalysisResult): Boolean; static;
  end;

implementation

uses Reverse.Scope, Reverse.MSBuild, Reverse.AST;

class function TAnalysisRunner.Run(const Request: TAnalysisRequest;
  const Logger: ILogger; const Progress: IAnalysisProgress): TAnalysisResult;
var
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
begin
  Scope := TProjectScope.Create(Request.ProjectFile, Logger,
    Request.Platform, Request.UseGlobalSearchPaths, Request.Config,
    TMSBuildPathEvaluator.Create(Logger), Request.SourceRoots);
  try
    Analyzer := TAnalyzer.Create(TAstUnitParser.Create(
      Scope.SearchDirectories.ToArray, Logger, Scope.Defines.ToArray,
      Scope.Platform), Logger, Progress, Request.Cancellation);
    try
      Result := Analyzer.Run(Scope, Request.TargetUnit);
      Result.DiscoveredCount := Scope.Files.Count;
      Result.Platform := Scope.Platform;
      Result.Config := Scope.Config;
    finally
      Analyzer.Free;
    end;
  finally
    Scope.Free;
  end;
end;

class function TAnalysisRunner.IsPartial(
  const Analysis: TAnalysisResult): Boolean;
begin
  Result := (Analysis.FallbackCount > 0) or
    (Analysis.FailedCount > 0) or Analysis.PathEvaluationWasFallback or
    (Analysis.UnresolvedCount > 0) or (Analysis.AmbiguousCount > 0);
end;

end.
