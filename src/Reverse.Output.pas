// SPDX-License-Identifier: Apache-2.0

unit Reverse.Output;

interface

uses Reverse.Analysis;

type
  TOutputWriter = class
  public
    class procedure WriteFiles(const Result: TAnalysisResult;
      const OutputDirectory: string);
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Classes,
  System.Generics.Collections, Reverse.Domain,
  Reverse.Visual;

function DotQuote(const Value: string): string;
begin
  Result := '"' + Value.Replace('\', '\\').Replace('"', '\"') + '"';
end;

class procedure TOutputWriter.WriteFiles(const Result: TAnalysisResult;
  const OutputDirectory: string);
var
  Report, Dot: TStringList;
  Edge: TDependency;
  Path: string;
  SeenPaths, SeenEvidence, SeenDot: TDictionary<string, Boolean>;
  Evidence, DotLine: string;
begin
  TDirectory.CreateDirectory(OutputDirectory);
  Report := TStringList.Create;
  Dot := TStringList.Create;
  SeenPaths := TDictionary<string, Boolean>.Create;
  SeenEvidence := TDictionary<string, Boolean>.Create;
  SeenDot := TDictionary<string, Boolean>.Create;
  try
    Report.Add('Target: ' + Result.TargetName + ' | ' + Result.TargetFile);
    Report.Add('Project entry: ' + Result.ProgramName);
    Report.Add(Format('Parsed: %d | AST fallback: %d | Failed: %d | Unresolved: %d | Ambiguous: %d | Reachable edges: %d',
      [Result.ParsedCount, Result.FallbackCount, Result.FailedCount, Result.UnresolvedCount,
       Result.AmbiguousCount, Length(Result.Reachable)]));
    Report.Add(Format('Routes: DPR %d | Project %d | Library %d | No consumer %d | Cycles %d',
      [Result.RouteCount(rdDpr), Result.RouteCount(rdProjectFile),
       Result.RouteCount(rdLibraryRoot), Result.RouteCount(rdNoConsumer),
       Result.RouteCount(rdCycle)]));
    if Result.PathEvaluationWasFallback then
      Report.Add('Project path evaluation: MSBuild fallback; verify configuration-specific paths in analysis.log');
    Report.Add('');
    Report.Add('Reverse paths:');
    for Path in Result.Paths do
      if not SeenPaths.ContainsKey(Path) then
      begin
        SeenPaths.Add(Path, True);
        Report.Add(Path);
      end;
    Report.Add('');
    Report.Add('Evidence:');
    Dot.Add('digraph UnitBacktrace {');
    Dot.Add('  rankdir=LR;');
    for Edge in Result.Reachable do
    begin
      Evidence := Edge.UsedName + ' -> ' + Edge.Consumer + ' | ' +
        Edge.Section + ' | ' + Edge.SourceFile + ':' + Edge.Line.ToString +
        ' | used file: ' + Edge.UsedPath;
      if not SeenEvidence.ContainsKey(Evidence) then
      begin
        SeenEvidence.Add(Evidence, True);
        Report.Add(Evidence);
      end;
      DotLine := '  ' + DotQuote(Edge.UsedPath) + ' [label=' +
        DotQuote(Edge.UsedName) + '];';
      if not SeenDot.ContainsKey(DotLine) then
      begin
        SeenDot.Add(DotLine, True);
        Dot.Add(DotLine);
      end;
      DotLine := '  ' + DotQuote(Edge.ConsumerPath) + ' [label=' +
        DotQuote(Edge.Consumer) + '];';
      if not SeenDot.ContainsKey(DotLine) then
      begin
        SeenDot.Add(DotLine, True);
        Dot.Add(DotLine);
      end;
      DotLine := '  ' + DotQuote(Edge.UsedPath) + ' -> ' +
        DotQuote(Edge.ConsumerPath) + ' [label=' +
        DotQuote(Edge.Section + ':' + Edge.Line.ToString) + '];';
      if not SeenDot.ContainsKey(DotLine) then
      begin
        SeenDot.Add(DotLine, True);
        Dot.Add(DotLine);
      end;
    end;
    Dot.Add('}');
    Report.SaveToFile(TPath.Combine(OutputDirectory, 'result.txt'), TEncoding.UTF8);
    Dot.SaveToFile(TPath.Combine(OutputDirectory, 'graph.dot'), TEncoding.UTF8);
    TVisualWriter.WriteHtml(Result,
      TPath.Combine(OutputDirectory, 'graph.html'));
  finally
    SeenDot.Free;
    SeenEvidence.Free;
    SeenPaths.Free;
    Dot.Free;
    Report.Free;
  end;
end;

end.
