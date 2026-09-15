unit Reverse.Analysis;

interface

uses Reverse.Domain, Reverse.Scope, Reverse.Graph,
  System.Generics.Collections;

type
  TAnalysisResult = class
  public
    TargetName: string;
    TargetFile: string;
    ProgramName: string;
    Graph: TReverseGraph;
    Reachable: TArray<TDependency>;
    Paths: TArray<string>;
    ParsedCount: Integer;
    FailedCount: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TAnalyzer = class
  private
    FParser: IUnitParser;
    FLogger: ILogger;
  public
    constructor Create(const Parser: IUnitParser; const Logger: ILogger);
    function Run(const Scope: TProjectScope; const Target: string): TAnalysisResult;
  end;

implementation

uses System.SysUtils;

constructor TAnalysisResult.Create;
begin
  inherited;
  Graph := TReverseGraph.Create;
end;

destructor TAnalysisResult.Destroy;
begin
  Graph.Free;
  inherited;
end;

constructor TAnalyzer.Create(const Parser: IUnitParser; const Logger: ILogger);
begin
  inherited Create;
  FParser := Parser;
  FLogger := Logger;
end;

function TAnalyzer.Run(const Scope: TProjectScope; const Target: string): TAnalysisResult;
var
  FileName, Name: string;
  Edges: TList<TDependency>;
  Edge: TDependency;
  Count: Integer;
begin
  Result := TAnalysisResult.Create;
  Edges := TList<TDependency>.Create;
  try
    try
    Count := 0;
    for FileName in Scope.Files do
    begin
      Edges.Clear;
      try
        Name := FParser.Parse(FileName, Edges);
        Inc(Result.ParsedCount);
        if SameText(FileName, Scope.ProgramFile) then
          Result.ProgramName := Name;
        if Key(Name) = Key(Target) then
        begin
          Inc(Count);
          Result.TargetName := Name;
          Result.TargetFile := FileName;
          FLogger.Write('INFO', 'target-candidate', Name + ' | ' + FileName);
        end;
        for Edge in Edges do
        begin
          Result.Graph.Add(Edge);
          FLogger.Write('DEBUG', 'dependency', Edge.SourceFile + ':' +
            Edge.Line.ToString + ' | ' + Edge.Consumer + ' uses ' + Edge.UsedName);
        end;
      except
        on E: Exception do
        begin
          Inc(Result.FailedCount);
          FLogger.Write('WARN', 'parse-failed', FileName + ' | ' + E.Message);
        end;
      end;
    end;
    if Count = 0 then raise Exception.Create('Unit not found: ' + Target);
    if Count > 1 then raise Exception.Create('Ambiguous unit: ' + Target +
      ' (' + Count.ToString + ' candidates; see log)');
    Result.Reachable := Result.Graph.Reachable(Result.TargetName);
    Result.Paths := Result.Graph.Paths(Result.TargetName, Result.ProgramName);
    FLogger.Write('INFO', 'complete', Format('%d parsed; %d failed; %d reachable edges',
      [Result.ParsedCount, Result.FailedCount, Length(Result.Reachable)]));
    except
      Result.Free;
      raise;
    end;
  finally
    Edges.Free;
  end;
end;

end.
