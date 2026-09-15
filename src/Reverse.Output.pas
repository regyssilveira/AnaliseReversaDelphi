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

uses System.SysUtils, System.IOUtils, System.Classes, Reverse.Domain;

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
begin
  TDirectory.CreateDirectory(OutputDirectory);
  Report := TStringList.Create;
  Dot := TStringList.Create;
  try
    Report.Add('Target: ' + Result.TargetName + ' | ' + Result.TargetFile);
    Report.Add('Project entry: ' + Result.ProgramName);
    Report.Add(Format('Parsed: %d | AST fallback: %d | Failed: %d | Unresolved: %d | Ambiguous: %d | Reachable edges: %d',
      [Result.ParsedCount, Result.FallbackCount, Result.FailedCount, Result.UnresolvedCount,
       Result.AmbiguousCount, Length(Result.Reachable)]));
    if Result.PathEvaluationWasFallback then
      Report.Add('Project path evaluation: MSBuild fallback; verify configuration-specific paths in analysis.log');
    Report.Add('');
    Report.Add('Reverse paths:');
    for Path in Result.Paths do Report.Add(Path);
    Report.Add('');
    Report.Add('Evidence:');
    Dot.Add('digraph ReverseDependencies {');
    Dot.Add('  rankdir=LR;');
    for Edge in Result.Reachable do
    begin
      Report.Add(Edge.UsedName + ' -> ' + Edge.Consumer + ' | ' +
        Edge.Section + ' | ' + Edge.SourceFile + ':' + Edge.Line.ToString +
        ' | used file: ' + Edge.UsedPath);
      Dot.Add('  ' + DotQuote(Edge.UsedPath) + ' [label=' +
        DotQuote(Edge.UsedName) + '];');
      Dot.Add('  ' + DotQuote(Edge.ConsumerPath) + ' [label=' +
        DotQuote(Edge.Consumer) + '];');
      Dot.Add('  ' + DotQuote(Edge.UsedPath) + ' -> ' + DotQuote(Edge.ConsumerPath) +
        ' [label=' + DotQuote(Edge.Section + ':' + Edge.Line.ToString) + '];');
    end;
    Dot.Add('}');
    Report.SaveToFile(TPath.Combine(OutputDirectory, 'result.txt'), TEncoding.UTF8);
    Dot.SaveToFile(TPath.Combine(OutputDirectory, 'graph.dot'), TEncoding.UTF8);
  finally
    Dot.Free;
    Report.Free;
  end;
end;

end.
