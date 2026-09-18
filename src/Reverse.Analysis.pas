// SPDX-License-Identifier: Apache-2.0

unit Reverse.Analysis;

interface

uses Reverse.Domain, Reverse.Scope, Reverse.Graph,
  System.Generics.Collections;

type
  TAnalysisResult = class
  public
    Mode: TAnalysisMode;
    TargetName: string;
    TargetFile: string;
    ProgramName: string;
    ProgramFile: string;
    ProjectRoot: string;
    Graph: TReverseGraph;
    Reachable: TArray<TDependency>;
    Paths: TArray<string>;
    Routes: TArray<TRoutePath>;
    SourceOrigins: TDictionary<string, TSourceOrigin>;
    Uncertain: TArray<TUncertainReference>;
    ParsedCount: Integer;
    FailedCount: Integer;
    FallbackCount: Integer;
    PathEvaluationWasFallback: Boolean;
    UnresolvedCount: Integer;
    AmbiguousCount: Integer;
    function RouteCount(const Destination: TRouteDestination): Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TAnalyzer = class
  private
    FParser: IUnitParser;
    FLogger: ILogger;
    FProgress: IAnalysisProgress;
  public
    constructor Create(const Parser: IUnitParser; const Logger: ILogger;
      const Progress: IAnalysisProgress = nil);
    function Run(const Scope: TProjectScope; const Target: string): TAnalysisResult;
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Diagnostics;

constructor TAnalysisResult.Create;
begin
  inherited;
  Mode := amUnitBacktrace;
  Graph := TReverseGraph.Create;
  SourceOrigins := TDictionary<string, TSourceOrigin>.Create;
end;

destructor TAnalysisResult.Destroy;
begin
  SourceOrigins.Free;
  Graph.Free;
  inherited;
end;

constructor TAnalyzer.Create(const Parser: IUnitParser; const Logger: ILogger;
  const Progress: IAnalysisProgress);
begin
  inherited Create;
  FParser := Parser;
  FLogger := Logger;
  FProgress := Progress;
end;

function TAnalyzer.Run(const Scope: TProjectScope; const Target: string): TAnalysisResult;
var
  FileName, Name: string;
  Edges, Pending: TList<TDependency>;
  Edge: TDependency;
  Count: Integer;
  Processed: Integer;
  Known: TObjectDictionary<string, TList<string>>;
  Aliases: TObjectDictionary<string, TList<string>>;
  Candidates: TList<string>;
  AliasNames: TList<string>;
  DeclaredFile, AliasKey, FullName: string;
  I: Integer;
  DotPos: Integer;
  Stopwatch: TStopwatch;
  NamespaceName, ChosenAlias: string;
  GraphStage: string;
  Uncertain: TList<TUncertainReference>;
  Warning: TUncertainReference;
  procedure AddOrigin(const SourceFile: string);
  begin
    if (SourceFile <> '') and not Result.SourceOrigins.ContainsKey(Key(SourceFile)) then
      Result.SourceOrigins.Add(Key(SourceFile), Scope.OriginOf(SourceFile));
  end;
  procedure MarkUncertain(const Reason: string);
  begin
    Warning.Dependency := Edge;
    Warning.Reason := Reason;
    Uncertain.Add(Warning);
  end;
begin
  Stopwatch := TStopwatch.StartNew;
  Result := TAnalysisResult.Create;
  Result.ProgramFile := Scope.ProgramFile;
  Result.ProjectRoot := Scope.ProjectRoot;
  Result.PathEvaluationWasFallback := Scope.PathEvaluationWasFallback;
  Edges := TList<TDependency>.Create;
  Pending := TList<TDependency>.Create;
  Uncertain := TList<TUncertainReference>.Create;
  Known := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  Aliases := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  try
    try
    Count := 0;
    Processed := 0;
    if FProgress <> nil then FProgress.Report('Analisando arquivos', 0, Scope.Files.Count);
    for FileName in Scope.Files do
    begin
      Edges.Clear;
      try
        Name := FParser.Parse(FileName, Edges);
        Inc(Result.ParsedCount);
        if FParser.LastParseWasFallback then Inc(Result.FallbackCount);
        if not Known.TryGetValue(Key(Name), Candidates) then
        begin
          Candidates := TList<string>.Create;
          Known.Add(Key(Name), Candidates);
        end;
        Candidates.Add(FileName);
        DotPos := Name.LastIndexOf('.');
        if DotPos >= 0 then
        begin
          AliasKey := Key(Name.Substring(DotPos + 1));
          if not Aliases.TryGetValue(AliasKey, AliasNames) then
          begin
            AliasNames := TList<string>.Create;
            Aliases.Add(AliasKey, AliasNames);
          end;
          if not AliasNames.Contains(Name) then AliasNames.Add(Name);
        end;
        if SameText(FileName, Scope.ProgramFile) then
          Result.ProgramName := Name;
        if (Target <> '') and (Key(Name) = Key(Target)) then
        begin
          Inc(Count);
          Result.TargetName := Name;
          Result.TargetFile := FileName;
          FLogger.Write('INFO', 'target-candidate', Name + ' | ' + FileName);
        end;
        for Edge in Edges do
        begin
          Pending.Add(Edge);
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
      Inc(Processed);
      if FProgress <> nil then
        FProgress.Report('Analisando arquivos', Processed, Scope.Files.Count);
    end;
    if Result.ProgramName = '' then
      raise Exception.Create('Project entry could not be parsed: ' + Scope.ProgramFile);
    if Target = '' then
    begin
      Result.Mode := amProjectMap;
      Result.TargetName := Result.ProgramName;
      Result.TargetFile := Result.ProgramFile;
    end
    else
    begin
      if Count = 0 then raise Exception.Create('Unit not found: ' + Target);
      if Count > 1 then raise Exception.Create('Ambiguous unit: ' + Target +
        ' (' + Count.ToString + ' candidates; see log)');
    end;
    if FProgress <> nil then FProgress.Report('Resolvendo dependencias', 0, Pending.Count);
    for I := 0 to Pending.Count - 1 do
    begin
      Edge := Pending[I];
      if FProgress <> nil then
        FProgress.Report('Resolvendo dependencias', I, Pending.Count);
      if Edge.DeclaredPath <> '' then
      begin
        DeclaredFile := Edge.DeclaredPath;
        if not TPath.IsPathRooted(DeclaredFile) then
          DeclaredFile := TPath.GetFullPath(TPath.Combine(
            ExtractFilePath(Edge.ConsumerPath), DeclaredFile));
        if not FileExists(DeclaredFile) then
        begin
          Inc(Result.UnresolvedCount);
          FLogger.Write('WARN', 'declared-path-missing', Edge.UsedName +
            ' | ' + DeclaredFile);
          MarkUncertain('declared-path-missing');
          Continue;
        end;
        Edge.UsedPath := DeclaredFile;
      end
      else if Known.TryGetValue(Key(Edge.UsedName), Candidates) then
      begin
        if Candidates.Count > 1 then
        begin
          Inc(Result.AmbiguousCount);
          FLogger.Write('WARN', 'ambiguous-reference', Edge.SourceFile + ':' +
            Edge.Line.ToString + ' | ' + Edge.UsedName + ' | ' +
            String.Join('; ', Candidates.ToArray));
          MarkUncertain('ambiguous-reference');
          Continue;
        end;
        Edge.UsedPath := Candidates[0];
      end
      else if Aliases.TryGetValue(Key(Edge.UsedName), AliasNames) then
      begin
        ChosenAlias := '';
        if Edge.Consumer.StartsWith('FMX.', True) then
          for FullName in AliasNames do
            if SameText(FullName, 'FMX.' + Edge.UsedName) then
            begin
              ChosenAlias := FullName;
              Break;
            end;
        if ChosenAlias = '' then
          for NamespaceName in Scope.NamespaceOrder do
          begin
            for FullName in AliasNames do
              if SameText(FullName, NamespaceName + '.' + Edge.UsedName) then
              begin
                ChosenAlias := FullName;
                Break;
              end;
            if ChosenAlias <> '' then Break;
          end;
        if (ChosenAlias = '') and (AliasNames.Count = 1) then
          ChosenAlias := AliasNames[0];
        if ChosenAlias = '' then
        begin
          Inc(Result.AmbiguousCount);
          FLogger.Write('WARN', 'ambiguous-namespace', Edge.SourceFile + ':' +
            Edge.Line.ToString + ' | ' + Edge.UsedName + ' | ' +
            String.Join('; ', AliasNames.ToArray));
          MarkUncertain('ambiguous-namespace');
          Continue;
        end;
        FullName := ChosenAlias;
        Candidates := Known[Key(FullName)];
        if Candidates.Count > 1 then
        begin
          Inc(Result.AmbiguousCount);
          FLogger.Write('WARN', 'ambiguous-namespace-file', FullName);
          MarkUncertain('ambiguous-namespace-file');
          Continue;
        end;
        Edge.UsedPath := Candidates[0];
        FLogger.Write('DEBUG', 'namespace-alias', Edge.UsedName +
          ' -> ' + FullName);
      end
      else
      begin
        Inc(Result.UnresolvedCount);
        FLogger.Write('WARN', 'unresolved-reference', Edge.SourceFile + ':' +
          Edge.Line.ToString + ' | ' + Edge.UsedName);
        MarkUncertain('unresolved-reference');
        Continue;
      end;
      Result.Graph.Add(Edge);
      FLogger.Write('DEBUG', 'resolved-reference', Edge.UsedName + ' | ' +
        Edge.UsedPath + ' -> ' + Edge.ConsumerPath);
    end;
    if FProgress <> nil then FProgress.Report('Resolvendo dependencias', Pending.Count, Pending.Count);
    if Result.Mode = amProjectMap then GraphStage := 'Montando mapa do projeto'
    else GraphStage := 'Montando grafo reverso';
    if FProgress <> nil then FProgress.Report(GraphStage, 0, 0);
    if Result.Mode = amProjectMap then
      Result.Reachable := Result.Graph.DependenciesReachable(Result.ProgramFile)
    else
      Result.Reachable := Result.Graph.Reachable(Result.TargetFile);
    AddOrigin(Result.TargetFile);
    AddOrigin(Result.ProgramFile);
    for Edge in Result.Reachable do
    begin
      AddOrigin(Edge.UsedPath);
      AddOrigin(Edge.ConsumerPath);
    end;
    Result.Uncertain := Uncertain.ToArray;
    if Result.Mode = amUnitBacktrace then
    begin
      Result.Routes := Result.Graph.ClassifiedPaths(Result.TargetFile,
        Scope.ProgramFile, Result.SourceOrigins);
      SetLength(Result.Paths, Length(Result.Routes));
      for I := 0 to High(Result.Routes) do
        Result.Paths[I] := Result.Routes[I].Text;
    end;
    if FProgress <> nil then FProgress.Report(GraphStage, 1, 1);
    FLogger.Write('INFO', 'complete', Format('%d parsed; %d fallback; %d failed; %d unresolved; %d ambiguous; %d reachable edges; %d ms',
      [Result.ParsedCount, Result.FallbackCount, Result.FailedCount, Result.UnresolvedCount,
       Result.AmbiguousCount, Length(Result.Reachable), Stopwatch.ElapsedMilliseconds]));
    except
      Result.Free;
      raise;
    end;
  finally
    Aliases.Free;
    Known.Free;
    Pending.Free;
    Uncertain.Free;
    Edges.Free;
  end;
end;

function TAnalysisResult.RouteCount(
  const Destination: TRouteDestination): Integer;
var
  Route: TRoutePath;
begin
  Result := 0;
  for Route in Routes do
    if not Route.IsLimitMarker and (Route.Destination = Destination) then
      Inc(Result);
end;

end.
