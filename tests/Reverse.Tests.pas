unit Reverse.Tests;

interface

uses DUnitX.TestFramework, Reverse.Graph, Reverse.Domain,
  System.Generics.Collections;

type
  [TestFixture]
  TGraphTests = class
  private
    FGraph: TReverseGraph;
    procedure AddEdge(const Used, Consumer: string);
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure PreservesConvergingPaths;
    [Test] procedure StopsAtCycle;
    [Test] procedure ReportsOrphanBranch;
    [Test] procedure KeepsAllEdgesAfterRevisitingNode;
    [Test] procedure LimitsPathEnumerationWithoutDroppingGraphEdges;
  end;

  [TestFixture]
  TAstTests = class
  public
    [Test] procedure ExtractsRealUsesWithSectionAndLine;
    [Test] procedure ExtractsProgramUses;
  end;

  [TestFixture]
  TWorkflowTests = class
  public
    [Test] procedure DiscoversTargetByNameAndWritesEvidence;
    [Test] procedure ReportsMissingTarget;
    [Test] procedure UsesMainSourceDeclaredByProject;
  end;

implementation

uses Reverse.AST, Reverse.Scope, Reverse.Analysis, Reverse.Output, Reverse.Log,
  System.SysUtils, System.IOUtils;

procedure TGraphTests.Setup;
begin
  FGraph := TReverseGraph.Create;
end;

procedure TGraphTests.TearDown;
begin
  FGraph.Free;
end;

procedure TGraphTests.AddEdge(const Used, Consumer: string);
var
  Edge: TDependency;
begin
  Edge.UsedName := Used;
  Edge.Consumer := Consumer;
  Edge.SourceFile := 'fixture.pas';
  Edge.Section := 'interface';
  Edge.Line := 1;
  FGraph.Add(Edge);
end;

procedure TGraphTests.PreservesConvergingPaths;
var
  Paths: TArray<string>;
begin
  AddEdge('Target', 'A');
  AddEdge('Target', 'B');
  AddEdge('A', 'Root');
  AddEdge('B', 'Root');
  Paths := FGraph.Paths('Target', 'Root');
  Assert.AreEqual(NativeInt(2), Length(Paths));
  Assert.IsTrue(Paths[0].Contains('target -> a -> root'));
  Assert.IsTrue(Paths[1].Contains('target -> b -> root'));
end;

procedure TGraphTests.StopsAtCycle;
var
  Paths: TArray<string>;
begin
  AddEdge('Target', 'A');
  AddEdge('A', 'B');
  AddEdge('B', 'A');
  Paths := FGraph.Paths('Target', 'Root');
  Assert.AreEqual(NativeInt(1), Length(Paths));
  Assert.IsTrue(Paths[0].Contains('[CYCLE]'));
end;

procedure TGraphTests.ReportsOrphanBranch;
begin
  AddEdge('Target', 'Orphan');
  Assert.IsTrue(FGraph.Paths('Target', 'Root')[0].Contains('[NO CONSUMER]'));
end;

procedure TGraphTests.KeepsAllEdgesAfterRevisitingNode;
begin
  AddEdge('Target', 'A');
  AddEdge('Target', 'B');
  AddEdge('A', 'C');
  AddEdge('B', 'C');
  Assert.AreEqual(NativeInt(4), Length(FGraph.Reachable('Target')));
end;

procedure TGraphTests.LimitsPathEnumerationWithoutDroppingGraphEdges;
var
  I: Integer;
  PreviousA, PreviousB, CurrentA, CurrentB: string;
  Paths: TArray<string>;
begin
  PreviousA := 'Target';
  PreviousB := 'Target';
  for I := 1 to 8 do
  begin
    CurrentA := 'A' + I.ToString;
    CurrentB := 'B' + I.ToString;
    AddEdge(PreviousA, CurrentA);
    AddEdge(PreviousA, CurrentB);
    if I > 1 then
    begin
      AddEdge(PreviousB, CurrentA);
      AddEdge(PreviousB, CurrentB);
    end;
    PreviousA := CurrentA;
    PreviousB := CurrentB;
  end;
  AddEdge(PreviousA, 'Root');
  AddEdge(PreviousB, 'Root');
  Paths := FGraph.Paths('Target', 'Root', 10);
  Assert.AreEqual(NativeInt(11), Length(Paths));
  Assert.IsTrue(Paths[10].Contains('LIMITED'));
  Assert.IsTrue(Length(FGraph.Reachable('Target')) > 20);
end;

procedure TAstTests.ExtractsRealUsesWithSectionAndLine;
var
  Parser: IUnitParser;
  Edges: TList<TDependency>;
  FileName: string;
begin
  FileName := TPath.GetFullPath('tests\fixtures\Small\B.pas');
  Parser := TAstUnitParser.Create;
  Edges := TList<TDependency>.Create;
  try
    Assert.AreEqual('B', Parser.Parse(FileName, Edges));
    Assert.AreEqual(NativeInt(2), Edges.Count);
    Assert.AreEqual('A', Edges[0].UsedName);
    Assert.AreEqual('Target', Edges[1].UsedName);
    Assert.AreEqual('interface', Edges[0].Section);
    Assert.AreEqual(3, Edges[0].Line);
  finally
    Edges.Free;
  end;
end;

procedure TAstTests.ExtractsProgramUses;
var
  Parser: IUnitParser;
  Edges: TList<TDependency>;
begin
  Parser := TAstUnitParser.Create;
  Edges := TList<TDependency>.Create;
  try
    Assert.AreEqual('Small', Parser.Parse(
      TPath.GetFullPath('tests\fixtures\Small\Small.dpr'), Edges));
    Assert.AreEqual(NativeInt(2), Edges.Count);
    Assert.AreEqual('program', Edges[0].Section);
  finally
    Edges.Free;
  end;
end;

procedure TWorkflowTests.DiscoversTargetByNameAndWritesEvidence;
var
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
  OutputDir: string;
begin
  OutputDir := TPath.GetFullPath('bin\workflow-test');
  TDirectory.CreateDirectory(OutputDir);
  Logger := TFileLogger.Create(TPath.Combine(OutputDir, 'analysis.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\Small\Small.dproj'), Logger);
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create, Logger);
  try
    Analysis := Analyzer.Run(Scope, 'target');
    try
      Assert.AreEqual('Target', Analysis.TargetName);
      Assert.AreEqual(NativeInt(5), Length(Analysis.Reachable));
      Assert.AreEqual(NativeInt(3), Length(Analysis.Paths));
      TOutputWriter.WriteFiles(Analysis, OutputDir);
      Assert.IsTrue(TFile.ReadAllText(TPath.Combine(OutputDir, 'result.txt'))
        .Contains('Target -> A | interface'));
      Assert.IsTrue(TFile.ReadAllText(TPath.Combine(OutputDir, 'graph.dot'))
        .Contains('"Target" -> "A"'));
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.ReportsMissingTarget;
var
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
begin
  TDirectory.CreateDirectory('bin\missing-test');
  Logger := TFileLogger.Create(TPath.GetFullPath('bin\missing-test\analysis.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\Small\Small.dproj'), Logger);
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create, Logger);
  try
    Assert.WillRaise(procedure begin Analyzer.Run(Scope, 'DoesNotExist') end,
      Exception);
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.UsesMainSourceDeclaredByProject;
var
  Logger: ILogger;
  Scope: TProjectScope;
begin
  TDirectory.CreateDirectory('bin\scope-test');
  Logger := TFileLogger.Create(TPath.GetFullPath('bin\scope-test\analysis.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\Small\Small.dproj'), Logger);
  try
    Assert.IsTrue(SameText(ExtractFileName(Scope.ProgramFile), 'Small.dpr'));
    Assert.AreEqual(NativeInt(4), Scope.Files.Count);
  finally
    Scope.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TGraphTests);
  TDUnitX.RegisterTestFixture(TAstTests);
  TDUnitX.RegisterTestFixture(TWorkflowTests);

end.
