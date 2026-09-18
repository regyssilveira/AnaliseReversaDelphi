// SPDX-License-Identifier: Apache-2.0

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
    [Test] procedure ClassifiesTerminalOrigins;
    [Test] procedure KeepsAllEdgesAfterRevisitingNode;
    [Test] procedure LimitsPathEnumerationWithoutDroppingGraphEdges;
    [Test] procedure KeepsSameNamedFilesSeparateWhenPathsAreKnown;
    [Test] procedure SkipsIdenticalEdgesButKeepsDifferentEvidence;
    [Test] procedure TraversesDependenciesFromProjectEntry;
  end;

  [TestFixture]
  TAstTests = class
  public
    [Test] procedure ExtractsRealUsesWithSectionAndLine;
    [Test] procedure ExtractsProgramUses;
    [Test] procedure ReadsUsesFromRelativeInclude;
    [Test] procedure ReadsIncludeFromConfiguredSearchPath;
    [Test] procedure FailsWhenIncludeIsMissing;
    [Test] procedure ExtractsUsesWhenAstCannotParseLaterSyntax;
    [Test] procedure RespectsProjectDefinesAndSelectedPlatform;
  end;

  [TestFixture]
  TLogTests = class
  public
    [Test] procedure PersistsDebugAndWarningsAfterClose;
    [Test] procedure FormatsProgressWithKnownAndUnknownTotals;
  end;

  [TestFixture]
  TConsoleTests = class
  public
    [Test] procedure SeparatesDefaultOutputByProjectAndUnit;
    [Test] procedure UsesDedicatedProjectMapOutputDirectory;
    [Test] procedure SummarizesOnlyDirectConsumersThatReachDpr;
    [Test] procedure SummarizesProjectMap;
  end;

  [TestFixture]
  TWorkflowTests = class
  public
    [Test] procedure DiscoversTargetByNameAndWritesEvidence;
    [Test] procedure WritesEachIdenticalOutputLineOnlyOnce;
    [Test] procedure ReportsProgressForParsingAndResolution;
    [Test] procedure ReportsMissingTarget;
    [Test] procedure UsesMainSourceDeclaredByProject;
    [Test] procedure DiscoversExplicitDprReferenceOutsideProjectFolder;
    [Test] procedure UsesRelativeLibrarySearchPath;
    [Test] procedure ResolvesLegacyNameToNamespacedUnit;
    [Test] procedure InfersDefaultPlatformFromProject;
    [Test] procedure RejectsUnsupportedConfiguration;
    [Test] procedure EvaluatesOnlySelectedConfigurationPaths;
    [Test] procedure MarksMsbuildFailureAsPartial;
    [Test] procedure FindsUnitRecursivelyInAdditionalSourceRoot;
    [Test] procedure UsesInjectedGlobalPathProvider;
    [Test] procedure ClassifiesDprProjectAndLibraryRoutes;
    [Test] procedure RetainsUnresolvedReferencesForVisualReview;
    [Test] procedure ProjectDefineChangesReverseRoutesBetweenConfigurations;
    [Test] procedure MapsAllDependenciesReachableFromDpr;
    [Test] procedure RunsAnalysisThroughReusableCore;
    [Test] procedure CancelsReusableCoreBeforeParsing;
  end;

implementation

uses Reverse.AST, Reverse.Scope, Reverse.Analysis, Reverse.Output, Reverse.Log,
  Reverse.Runner,
  Reverse.Cli,
  Reverse.Progress,
  Reverse.MSBuild,
  System.SysUtils, System.IOUtils, System.Classes, System.RegularExpressions,
  SimpleParser.Lexer.Types;

type
  TFixedPathProvider = class(TInterfacedObject, IGlobalSourcePathProvider)
  private
    FDirectory: string;
  public
    constructor Create(const Directory: string);
    function Paths(const Platform, ProjectRoot: string): TArray<string>;
  end;

  TProgressRecorder = class(TInterfacedObject, IAnalysisProgress)
  public
    Stages: TList<string>;
    CompletedValues: TList<Integer>;
    Totals: TList<Integer>;
    constructor Create;
    destructor Destroy; override;
    procedure Report(const Stage: string; Completed, Total: Integer);
  end;

  TCancelledAnalysis = class(TInterfacedObject, IAnalysisCancellation)
  public
    procedure RequestCancel;
    function IsCancellationRequested: Boolean;
  end;

constructor TProgressRecorder.Create;
begin
  inherited;
  Stages := TList<string>.Create;
  CompletedValues := TList<Integer>.Create;
  Totals := TList<Integer>.Create;
end;

procedure TWorkflowTests.RunsAnalysisThroughReusableCore;
var
  Request: TAnalysisRequest;
  Analysis: TAnalysisResult;
  Logger: ILogger;
begin
  Request := Default(TAnalysisRequest);
  Request.ProjectFile := TPath.GetFullPath(
    'tests\fixtures\Small\Small.dproj');
  Request.Platform := 'Win64';
  Request.UseGlobalSearchPaths := False;
  TDirectory.CreateDirectory(TPath.GetFullPath('bin\workflow-test'));
  Logger := TFileLogger.Create(TPath.GetFullPath(
    'bin\workflow-test\runner-analysis.log'));
  Analysis := TAnalysisRunner.Run(Request, Logger);
  try
    Assert.AreEqual(amProjectMap, Analysis.Mode);
    Assert.AreEqual(4, Analysis.DiscoveredCount);
    Assert.AreEqual('Win64', Analysis.Platform);
    Assert.AreEqual('Debug', Analysis.Config);
    Assert.AreEqual(NativeInt(5), Length(Analysis.Reachable));
    Assert.IsFalse(TAnalysisRunner.IsPartial(Analysis));
    Analysis.FailedCount := 1;
    Assert.IsTrue(TAnalysisRunner.IsPartial(Analysis));
  finally
    Analysis.Free;
  end;
end;

procedure TCancelledAnalysis.RequestCancel;
begin
end;

function TCancelledAnalysis.IsCancellationRequested: Boolean;
begin
  Result := True;
end;

procedure TWorkflowTests.CancelsReusableCoreBeforeParsing;
var
  Request: TAnalysisRequest;
  Logger: ILogger;
begin
  Request := Default(TAnalysisRequest);
  Request.ProjectFile := TPath.GetFullPath(
    'tests\fixtures\Small\Small.dproj');
  Request.Platform := 'Win64';
  Request.UseGlobalSearchPaths := False;
  Request.Cancellation := TCancelledAnalysis.Create;
  TDirectory.CreateDirectory(TPath.GetFullPath('bin\workflow-test'));
  Logger := TFileLogger.Create(TPath.GetFullPath(
    'bin\workflow-test\cancel-analysis.log'));
  Assert.WillRaise(
    procedure
    var
      Analysis: TAnalysisResult;
    begin
      Analysis := TAnalysisRunner.Run(Request, Logger);
      Analysis.Free;
    end,
    EAnalysisCancelled);
end;

destructor TProgressRecorder.Destroy;
begin
  Totals.Free;
  CompletedValues.Free;
  Stages.Free;
  inherited;
end;

procedure TProgressRecorder.Report(const Stage: string; Completed, Total: Integer);
begin
  Stages.Add(Stage);
  CompletedValues.Add(Completed);
  Totals.Add(Total);
end;

constructor TFixedPathProvider.Create(const Directory: string);
begin
  inherited Create;
  FDirectory := Directory;
end;

function TFixedPathProvider.Paths(const Platform,
  ProjectRoot: string): TArray<string>;
begin
  Result := [FDirectory];
end;

procedure TGraphTests.Setup;
begin
  FGraph := TReverseGraph.Create;
end;

procedure TConsoleTests.SeparatesDefaultOutputByProjectAndUnit;
var
  Root, Output, OtherProject: string;
begin
  Root := TPath.GetFullPath('bin\console-output-test');
  Output := TConsoleReport.DefaultOutputDirectory(Root,
    'D:\Projects\Small.dproj', 'Target');
  Assert.IsTrue(TRegEx.IsMatch(Output,
    'analysis-output\\Small-[0-9a-fA-F]{8}\\Target$'));
  OtherProject := TConsoleReport.DefaultOutputDirectory(Root,
    'D:\Elsewhere\Small.dproj', 'Target');
  Assert.AreNotEqual(Output, OtherProject);
  Output := TConsoleReport.DefaultOutputDirectory(Root,
    'D:\Projects\Small.dproj', '..\Other/Target');
  Assert.IsTrue(TRegEx.IsMatch(Output,
    'analysis-output\\Small-[0-9a-fA-F]{8}\\[^\\]+$'));
  Assert.IsFalse(Output.Contains('..\'));
end;

procedure TConsoleTests.UsesDedicatedProjectMapOutputDirectory;
var
  Output: string;
begin
  Output := TConsoleReport.DefaultProjectMapOutputDirectory(
    TPath.GetFullPath('bin\console-output-test'),
    'D:\Projects\Small.dproj');
  Assert.IsTrue(TRegEx.IsMatch(Output,
    'analysis-output\\Small-[0-9a-fA-F]{8}\\project-map$'));
end;

procedure TConsoleTests.SummarizesOnlyDirectConsumersThatReachDpr;
var
  Analysis: TAnalysisResult;
  Edges: TArray<TDependency>;
  Lines: TArray<string>;
  procedure AddEdge(const Index: Integer; const Used, Consumer: string);
  begin
    Edges[Index].UsedPath := Used;
    Edges[Index].ConsumerPath := Consumer;
  end;
begin
  Analysis := TAnalysisResult.Create;
  try
    Analysis.TargetFile := 'C:\Target.pas';
    Analysis.ProgramFile := 'C:\App.dpr';
    SetLength(Edges, 5);
    AddEdge(0, 'C:\Target.pas', 'C:\A.pas');
    AddEdge(1, 'C:\Target.pas', 'C:\B.pas');
    AddEdge(2, 'C:\A.pas', 'C:\App.dpr');
    AddEdge(3, 'C:\B.pas', 'C:\App.dpr');
    AddEdge(4, 'C:\Target.pas', 'C:\Orphan.pas');
    Analysis.Reachable := Edges;
    Analysis.UnresolvedCount := 1;
    Lines := TConsoleReport.SummaryLines(Analysis);
    Assert.AreEqual(NativeInt(4), Length(Lines));
    Assert.IsTrue(Lines[0].Contains('2 consumidores diretos'));
    Assert.IsTrue(Lines[0].Contains('2 declaracoes uses'));
    Assert.IsTrue(Lines[1].Contains('Caminho ate o DPR: sim'));
    Assert.IsTrue(Lines[2].Contains('Rotas:'));
    Assert.IsTrue(Lines[3].Contains('1 nao resolvidas'));
  finally
    Analysis.Free;
  end;
end;

procedure TConsoleTests.SummarizesProjectMap;
var
  Analysis: TAnalysisResult;
  Edges: TArray<TDependency>;
  Lines: TArray<string>;
begin
  Analysis := TAnalysisResult.Create;
  try
    Analysis.Mode := amProjectMap;
    Analysis.ProgramFile := 'C:\Project\App.dpr';
    SetLength(Edges, 2);
    Edges[0].ConsumerPath := Analysis.ProgramFile;
    Edges[0].UsedPath := 'C:\Project\Feature\A.pas';
    Edges[1].ConsumerPath := Edges[0].UsedPath;
    Edges[1].UsedPath := 'C:\Library\B.pas';
    Analysis.Reachable := Edges;
    Lines := TConsoleReport.SummaryLines(Analysis);
    Assert.AreEqual(NativeInt(2), Length(Lines));
    Assert.IsTrue(Lines[0].Contains('3 arquivos alcancaveis'));
    Assert.IsTrue(Lines[0].Contains('3 pastas'));
    Assert.IsTrue(Lines[0].Contains('2 relacoes'));
    Assert.IsTrue(Lines[1].Contains('Dependencias diretas do DPR: 1'));
  finally
    Analysis.Free;
  end;
end;

procedure TLogTests.PersistsDebugAndWarningsAfterClose;
var
  FileName, Content: string;
  Logger: ILogger;
begin
  TDirectory.CreateDirectory('bin\log-test');
  FileName := TPath.GetFullPath('bin\log-test\analysis.log');
  Logger := TFileLogger.Create(FileName);
  Logger.Write('DEBUG', 'dependency', 'A uses B');
  Logger.Write('WARN', 'unresolved-reference', 'B');
  Logger := nil;
  Content := TFile.ReadAllText(FileName);
  Assert.IsTrue(Content.Contains('[DEBUG] dependency | A uses B'));
  Assert.IsTrue(Content.Contains('[WARN] unresolved-reference | B'));
end;

procedure TLogTests.FormatsProgressWithKnownAndUnknownTotals;
begin
  Assert.AreEqual('Analisando arquivos: [######------------------]  25% 5/20',
    TConsoleProgress.FormatLine('Analisando arquivos', 5, 20));
  Assert.AreEqual('Analisando arquivos: [------------------------]   0% 0/20',
    TConsoleProgress.FormatLine('Analisando arquivos', -5, 20));
  Assert.AreEqual('Analisando arquivos: [########################] 100% 20/20',
    TConsoleProgress.FormatLine('Analisando arquivos', 25, 20));
  Assert.AreEqual('Montando grafo reverso...',
    TConsoleProgress.FormatLine('Montando grafo reverso', 0, 0));
  Assert.AreEqual(#13 + 'Novo' + '   ',
    TConsoleProgress.RewriteLine('Novo', 7));
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
  Assert.IsTrue(LowerCase(Paths[0]).Contains('target -> a -> root'));
  Assert.IsTrue(LowerCase(Paths[1]).Contains('target -> b -> root'));
end;

procedure TGraphTests.StopsAtCycle;
var
  Paths: TArray<string>;
  Routes: TArray<TRoutePath>;
  Origins: TDictionary<string, TSourceOrigin>;
begin
  AddEdge('Target', 'A');
  AddEdge('A', 'B');
  AddEdge('B', 'A');
  Paths := FGraph.Paths('Target', 'Root');
  Assert.AreEqual(NativeInt(1), Length(Paths));
  Assert.IsTrue(Paths[0].Contains('[CYCLE]'));
  Origins := TDictionary<string, TSourceOrigin>.Create;
  try
    Routes := FGraph.ClassifiedPaths('Target', 'Root', Origins);
    Assert.AreEqual(NativeInt(1), Length(Routes));
    Assert.AreEqual(rdCycle, Routes[0].Destination);
  finally
    Origins.Free;
  end;
end;

procedure TGraphTests.ReportsOrphanBranch;
begin
  AddEdge('Target', 'Orphan');
  Assert.IsTrue(FGraph.Paths('Target', 'Root')[0].Contains('[NO CONSUMER]'));
end;

procedure TGraphTests.ClassifiesTerminalOrigins;
var
  Origins: TDictionary<string, TSourceOrigin>;
  Routes: TArray<TRoutePath>;
begin
  AddEdge('Target', 'ProjectOnly');
  AddEdge('Target', 'LibraryOnly');
  AddEdge('Target', 'UnknownOnly');
  Origins := TDictionary<string, TSourceOrigin>.Create;
  try
    Origins.Add(Key('Target'), soProjectSearchPath);
    Origins.Add(Key('ProjectOnly'), soProject);
    Origins.Add(Key('LibraryOnly'), soProjectSearchPath);
    Routes := FGraph.ClassifiedPaths('Target', 'Root', Origins);
    Assert.AreEqual(NativeInt(3), Length(Routes));
    Assert.AreEqual(rdProjectFile, Routes[0].Destination);
    Assert.AreEqual(rdLibraryRoot, Routes[1].Destination);
    Assert.AreEqual(rdNoConsumer, Routes[2].Destination);
  finally
    Origins.Free;
  end;
end;

procedure TGraphTests.KeepsAllEdgesAfterRevisitingNode;
begin
  AddEdge('Target', 'A');
  AddEdge('Target', 'B');
  AddEdge('A', 'C');
  AddEdge('B', 'C');
  Assert.AreEqual(NativeInt(4), Length(FGraph.Reachable('Target')));
end;

procedure TGraphTests.SkipsIdenticalEdgesButKeepsDifferentEvidence;
var
  Edge: TDependency;
begin
  Edge := Default(TDependency);
  Edge.UsedName := 'Target';
  Edge.Consumer := 'A';
  Edge.SourceFile := 'A.pas';
  Edge.Section := 'interface';
  Edge.Line := 3;
  FGraph.Add(Edge);
  FGraph.Add(Edge);
  Assert.AreEqual(NativeInt(1), Length(FGraph.Reachable('Target')));
  Edge.Line := 4;
  FGraph.Add(Edge);
  Assert.AreEqual(NativeInt(2), Length(FGraph.Reachable('Target')));
end;

procedure TGraphTests.LimitsPathEnumerationWithoutDroppingGraphEdges;
var
  I: Integer;
  PreviousA, PreviousB, CurrentA, CurrentB: string;
  Paths: TArray<string>;
  Routes: TArray<TRoutePath>;
  Origins: TDictionary<string, TSourceOrigin>;
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
  Origins := TDictionary<string, TSourceOrigin>.Create;
  try
    Routes := FGraph.ClassifiedPaths('Target', 'Root', Origins, 10);
    Assert.AreEqual(NativeInt(11), Length(Routes));
    Assert.IsTrue(Routes[10].IsLimitMarker);
  finally
    Origins.Free;
  end;
  Assert.IsTrue(Length(FGraph.Reachable('Target')) > 20);
end;

procedure TGraphTests.KeepsSameNamedFilesSeparateWhenPathsAreKnown;
var
  Edge: TDependency;
begin
  Edge.UsedName := 'Target';
  Edge.UsedPath := 'C:\LibraryOne\Target.pas';
  Edge.Consumer := 'ConsumerOne';
  Edge.ConsumerPath := 'C:\Project\ConsumerOne.pas';
  Edge.SourceFile := 'C:\Project\ConsumerOne.pas';
  FGraph.Add(Edge);
  Edge.UsedPath := 'C:\LibraryTwo\Target.pas';
  Edge.Consumer := 'ConsumerTwo';
  Edge.ConsumerPath := 'C:\Project\ConsumerTwo.pas';
  Edge.SourceFile := 'C:\Project\ConsumerTwo.pas';
  FGraph.Add(Edge);
  Assert.AreEqual(NativeInt(1), Length(FGraph.Reachable(
    'C:\LibraryOne\Target.pas')));
  Assert.AreEqual('ConsumerOne', FGraph.Reachable(
    'C:\LibraryOne\Target.pas')[0].Consumer);
end;

procedure TGraphTests.TraversesDependenciesFromProjectEntry;
var
  Edge: TDependency;
  Dependencies: TArray<TDependency>;
begin
  Edge := Default(TDependency);
  Edge.Consumer := 'App';
  Edge.ConsumerPath := 'C:\Project\App.dpr';
  Edge.SourceFile := Edge.ConsumerPath;
  Edge.UsedName := 'A';
  Edge.UsedPath := 'C:\Project\A.pas';
  Edge.Section := 'program';
  Edge.Line := 3;
  FGraph.Add(Edge);
  Edge.Consumer := 'A';
  Edge.ConsumerPath := 'C:\Project\A.pas';
  Edge.SourceFile := Edge.ConsumerPath;
  Edge.UsedName := 'B';
  Edge.UsedPath := 'C:\Project\B.pas';
  Edge.Section := 'interface';
  FGraph.Add(Edge);
  Edge.Consumer := 'Detached';
  Edge.ConsumerPath := 'C:\Project\Detached.pas';
  Edge.SourceFile := Edge.ConsumerPath;
  Edge.UsedName := 'Unused';
  Edge.UsedPath := 'C:\Project\Unused.pas';
  FGraph.Add(Edge);
  Dependencies := FGraph.DependenciesReachable('C:\Project\App.dpr');
  Assert.AreEqual(NativeInt(2), Length(Dependencies));
  Assert.AreEqual('A', Dependencies[0].UsedName);
  Assert.AreEqual('B', Dependencies[1].UsedName);
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

procedure TAstTests.ReadsUsesFromRelativeInclude;
var
  Parser: IUnitParser;
  Edges: TList<TDependency>;
begin
  Parser := TAstUnitParser.Create;
  Edges := TList<TDependency>.Create;
  try
    Assert.AreEqual('IncludedConsumer', Parser.Parse(TPath.GetFullPath(
      'tests\fixtures\Includes\IncludedConsumer.pas'), Edges));
    Assert.AreEqual(NativeInt(1), Edges.Count);
    Assert.AreEqual('Target', Edges[0].UsedName);
    Assert.IsTrue(SameText(ExtractFileName(Edges[0].ConsumerPath),
      'IncludedConsumer.pas'));
    Assert.IsTrue(SameText(ExtractFileName(Edges[0].SourceFile),
      'IncludedUses.inc'));
  finally
    Edges.Free;
  end;
end;

procedure TAstTests.ReadsIncludeFromConfiguredSearchPath;
var
  Parser: IUnitParser;
  Edges: TList<TDependency>;
begin
  Parser := TAstUnitParser.Create([TPath.GetFullPath(
    'tests\fixtures\Includes\Common')]);
  Edges := TList<TDependency>.Create;
  try
    Parser.Parse(TPath.GetFullPath(
      'tests\fixtures\Includes\ConsumerWithSearchPath.pas'), Edges);
    Assert.AreEqual(NativeInt(1), Edges.Count);
  finally
    Edges.Free;
  end;
end;

procedure TAstTests.FailsWhenIncludeIsMissing;
var
  Parser: IUnitParser;
  Edges: TList<TDependency>;
begin
  Parser := TAstUnitParser.Create;
  Edges := TList<TDependency>.Create;
  try
    Assert.WillRaise(procedure begin Parser.Parse(TPath.GetFullPath(
      'tests\fixtures\Includes\ConsumerWithMissingInclude.pas'), Edges) end,
      EIncludeError);
  finally
    Edges.Free;
  end;
end;

procedure TAstTests.ExtractsUsesWhenAstCannotParseLaterSyntax;
var
  Parser: IUnitParser;
  Edges: TList<TDependency>;
begin
  Parser := TAstUnitParser.Create;
  Edges := TList<TDependency>.Create;
  try
    Assert.AreEqual('UnsupportedSyntax', Parser.Parse(TPath.GetFullPath(
      'tests\fixtures\Fallback\UnsupportedSyntax.pas'), Edges));
    Assert.IsTrue(Parser.LastParseWasFallback);
    Assert.AreEqual(NativeInt(2), Edges.Count);
    Assert.AreEqual('Target', Edges[0].UsedName);
    Assert.AreEqual('Another.Unit', Edges[1].UsedName);
  finally
    Edges.Free;
  end;
end;

procedure TAstTests.RespectsProjectDefinesAndSelectedPlatform;
var
  Source: string;
  Parser: IUnitParser;
  Edges: TList<TDependency>;
begin
  Source := TPath.GetFullPath('bin\conditional-parser-test\Conditional.pas');
  TDirectory.CreateDirectory(ExtractFilePath(Source));
  TFile.WriteAllText(Source, 'unit Conditional; interface' + sLineBreak +
    '{$IFDEF FEATURE_X} uses FeatureUnit; {$ENDIF}' + sLineBreak +
    '{$IFDEF WIN32} uses Win32Unit; {$ENDIF}' + sLineBreak +
    '{$IFDEF WIN64} uses Win64Unit; {$ENDIF}' + sLineBreak +
    'implementation end.');
  Edges := TList<TDependency>.Create;
  try
    Parser := TAstUnitParser.Create([], nil, ['FEATURE_X'], 'Win32');
    Parser.Parse(Source, Edges);
    Assert.AreEqual(NativeInt(2), Edges.Count);
    Assert.AreEqual('FeatureUnit', Edges[0].UsedName);
    Assert.AreEqual('Win32Unit', Edges[1].UsedName);
    Edges.Clear;
    Parser := TAstUnitParser.Create([], nil, [], 'Win64');
    Parser.Parse(Source, Edges);
    Assert.AreEqual(NativeInt(1), Edges.Count);
    Assert.AreEqual('Win64Unit', Edges[0].UsedName);
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
    'tests\fixtures\Small\Small.dproj'), Logger, 'Win64', False);
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
        .Contains('[label="Target"]'));
      Assert.IsTrue(TFile.ReadAllText(TPath.Combine(OutputDir, 'graph.html'))
        .Contains('Mostrar somente caminhos at' + #$00E9 + ' o DPR'));
      Assert.IsTrue(TFile.ReadAllText(TPath.Combine(OutputDir, 'graph.html'))
        .Contains('section:"interface"'));
      Assert.IsTrue(TFile.ReadAllText(TPath.Combine(OutputDir, 'graph.html'))
        .Contains('Ver liga' + #$00E7 + #$00F5 + 'es da unit selecionada'));
      Assert.IsTrue(TFile.ReadAllText(TPath.Combine(OutputDir, 'graph.html'))
        .Contains('Isolar cadeia destacada'));
      Assert.AreEqual(Scope.ProjectRoot, Analysis.ProjectRoot);
      Assert.IsTrue(TFile.ReadAllText(TPath.Combine(OutputDir, 'graph.html'))
        .Contains('projectRoot='));
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.MapsAllDependenciesReachableFromDpr;
var
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  Logger := TFileLogger.Create(TPath.GetFullPath(
    'bin\workflow-test\project-map-analysis.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\Small\Small.dproj'), Logger, 'Win64', False);
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create, Logger);
  try
    Analysis := Analyzer.Run(Scope, '');
    try
      Assert.AreEqual(amProjectMap, Analysis.Mode);
      Assert.AreEqual(Analysis.ProgramName, Analysis.TargetName);
      Assert.AreEqual(Analysis.ProgramFile, Analysis.TargetFile);
      Assert.AreEqual(NativeInt(5), Length(Analysis.Reachable));
      Assert.AreEqual(NativeInt(0), Length(Analysis.Routes));
      Assert.AreEqual(NativeInt(0), Length(Analysis.Paths));
      TOutputWriter.WriteFiles(Analysis, TPath.GetFullPath(
        'bin\project-map-output'));
      Assert.IsTrue(TFile.ReadAllText(TPath.GetFullPath(
        'bin\project-map-output\result.txt')).Contains(
        'Dependencies reachable from the project entry'));
      Assert.IsTrue(TFile.ReadAllText(TPath.GetFullPath(
        'bin\project-map-output\graph.dot')).Contains(
        'Small.dpr" -> "'));
      Assert.IsTrue(TFile.ReadAllText(TPath.GetFullPath(
        'bin\project-map-output\graph.html')).Contains(
        'Mapa de depend' + #$00EA + 'ncias do projeto'));
      Assert.IsTrue(TFile.ReadAllText(TPath.GetFullPath(
        'bin\project-map-output\graph.html')).Contains(
        '>Pastas (vis' + #$00E3 + 'o geral)</button>'));
      Assert.IsTrue(TFile.ReadAllText(TPath.GetFullPath(
        'bin\project-map-output\graph.html')).Contains(
        '>Units</button>'));
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.WritesEachIdenticalOutputLineOnlyOnce;
var
  Analysis: TAnalysisResult;
  Edge: TDependency;
  Dot, Report, Html: TStringList;
  I, NodeCount, LinkCount, PathCount, EvidenceCount: Integer;
  OutputDir: string;
begin
  Analysis := TAnalysisResult.Create;
  Dot := TStringList.Create;
  Report := TStringList.Create;
  Html := TStringList.Create;
  try
    Analysis.TargetName := 'Target';
    Analysis.TargetFile := 'Target.pas';
    Analysis.ProgramName := 'App';
    Analysis.ProgramFile := 'App.dpr';
    Analysis.Paths := ['Target -> A -> App [DPR]',
      'Target -> A -> App [DPR]'];
    Edge := Default(TDependency);
    Edge.UsedName := 'Target';
    Edge.UsedPath := 'Target.pas';
    Edge.Consumer := 'A';
    Edge.ConsumerPath := 'A.pas';
    Edge.SourceFile := 'A.pas';
    Edge.Section := 'interface';
    Edge.Line := 3;
    Analysis.Reachable := [Edge, Edge];
    OutputDir := TPath.GetFullPath('bin\dedup-output-test');
    TOutputWriter.WriteFiles(Analysis, OutputDir);
    Dot.LoadFromFile(TPath.Combine(OutputDir, 'graph.dot'));
    Report.LoadFromFile(TPath.Combine(OutputDir, 'result.txt'));
    Html.LoadFromFile(TPath.Combine(OutputDir, 'graph.html'));
    NodeCount := 0;
    LinkCount := 0;
    PathCount := 0;
    EvidenceCount := 0;
    for I := 0 to Dot.Count - 1 do
    begin
      if Dot[I] = '  "Target.pas" [label="Target"];' then Inc(NodeCount);
      if Dot[I] = '  "Target.pas" -> "A.pas" [label="interface:3"];' then
        Inc(LinkCount);
    end;
    for I := 0 to Report.Count - 1 do
    begin
      if Report[I] = 'Target -> A -> App [DPR]' then Inc(PathCount);
      if Report[I].StartsWith('Target -> A | interface |') then
        Inc(EvidenceCount);
    end;
    Assert.AreEqual(1, NodeCount);
    Assert.AreEqual(1, LinkCount);
    Assert.AreEqual(1, PathCount);
    Assert.AreEqual(1, EvidenceCount);
    Assert.AreEqual(Html.Text.IndexOf('{from:'), Html.Text.LastIndexOf('{from:'));
  finally
    Html.Free;
    Report.Free;
    Dot.Free;
    Analysis.Free;
  end;
end;

procedure TWorkflowTests.ReportsProgressForParsingAndResolution;
var
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
  Progress: IAnalysisProgress;
  Recorder: TProgressRecorder;
  I: Integer;
  FoundParsing, FoundResolution, FoundGraph: Boolean;
begin
  Logger := TFileLogger.Create(TPath.GetFullPath('bin\progress-test.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\Small\Small.dproj'), Logger, 'Win64', False);
  Recorder := TProgressRecorder.Create;
  Progress := Recorder;
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create, Logger, Progress);
  try
    Analysis := Analyzer.Run(Scope, 'Target');
    try
      FoundParsing := False;
      FoundResolution := False;
      FoundGraph := False;
      for I := 0 to Recorder.Stages.Count - 1 do
      begin
        Assert.IsTrue(Recorder.CompletedValues[I] <= Recorder.Totals[I]);
        if (Recorder.Stages[I] = 'Analisando arquivos') and
          (Recorder.CompletedValues[I] = Scope.Files.Count) then
          FoundParsing := True;
        if (Recorder.Stages[I] = 'Resolvendo dependencias') and
          (Recorder.CompletedValues[I] = Recorder.Totals[I]) and
          (Recorder.Totals[I] > 0) then FoundResolution := True;
        if (Recorder.Stages[I] = 'Montando grafo reverso') and
          (Recorder.CompletedValues[I] = 1) then FoundGraph := True;
      end;
      Assert.IsTrue(FoundParsing);
      Assert.IsTrue(FoundResolution);
      Assert.IsTrue(FoundGraph);
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
    'tests\fixtures\Small\Small.dproj'), Logger, 'Win64', False);
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
    'tests\fixtures\Small\Small.dproj'), Logger, 'Win64', False);
  try
    Assert.IsTrue(SameText(ExtractFileName(Scope.ProgramFile), 'Small.dpr'));
    Assert.AreEqual(NativeInt(4), Scope.Files.Count);
  finally
    Scope.Free;
  end;
end;

procedure TWorkflowTests.DiscoversExplicitDprReferenceOutsideProjectFolder;
var
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  TDirectory.CreateDirectory('bin\external-test');
  Logger := TFileLogger.Create(TPath.GetFullPath('bin\external-test\analysis.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\External\Project\ExternalProject.dproj'), Logger,
    'Win64', False);
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create, Logger);
  try
    Assert.IsTrue(SameText(ExtractFileName(Scope.ProgramFile), 'ActualProgram.dpr'));
    Assert.AreEqual(NativeInt(2), Scope.Files.Count);
    Assert.AreEqual(soProjectReference, Scope.OriginOf(TPath.GetFullPath(
      'tests\fixtures\External\Library\ExternalTarget.pas')));
    Analysis := Analyzer.Run(Scope, 'ExternalTarget');
    try
      Assert.AreEqual(NativeInt(1), Length(Analysis.Reachable));
      Assert.IsTrue(Analysis.Paths[0].Contains('[DPR]'));
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.UsesRelativeLibrarySearchPath;
var
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  TDirectory.CreateDirectory('bin\relative-path-test');
  Logger := TFileLogger.Create(TPath.GetFullPath('bin\relative-path-test\analysis.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\SearchPaths\Project\SearchPaths.dproj'), Logger,
    'Win64', False);
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create(
    Scope.SearchDirectories.ToArray), Logger);
  try
    Assert.AreEqual(soProjectSearchPath, Scope.OriginOf(TPath.GetFullPath(
      'tests\fixtures\SearchPaths\Library\Target.pas')));
    Assert.AreEqual(soProject, Scope.OriginOf(TPath.GetFullPath(
      'tests\fixtures\SearchPaths\Project\Consumer.pas')));
    Assert.AreEqual(soProjectReference, Scope.OriginOf(Scope.ProgramFile));
    Analysis := Analyzer.Run(Scope, 'Target');
    try
      Assert.AreEqual(NativeInt(2), Length(Analysis.Reachable));
      Assert.IsTrue(Analysis.Paths[0].Contains('[DPR]'));
      Assert.AreEqual(0, Analysis.UnresolvedCount);
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.ResolvesLegacyNameToNamespacedUnit;
var
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  TDirectory.CreateDirectory('bin\alias-test');
  Logger := TFileLogger.Create(TPath.GetFullPath('bin\alias-test\analysis.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\Alias\Alias.dproj'), Logger, 'Win64', False);
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create, Logger);
  try
    Analysis := Analyzer.Run(Scope, 'System.Classes');
    try
      Assert.AreEqual(NativeInt(2), Length(Analysis.Reachable));
      Assert.AreEqual(0, Analysis.UnresolvedCount);
      Assert.IsTrue(Analysis.Paths[0].Contains('[DPR]'));
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.InfersDefaultPlatformFromProject;
var
  Logger: ILogger;
  Scope: TProjectScope;
begin
  TDirectory.CreateDirectory('bin\platform-test');
  Logger := TFileLogger.Create(TPath.GetFullPath('bin\platform-test\analysis.log'));
  Scope := TProjectScope.Create(TPath.GetFullPath(
    'tests\fixtures\Small\Small.dproj'), Logger, '', False);
  try
    Assert.AreEqual('Win32', Scope.Platform);
  finally
    Scope.Free;
  end;
end;

procedure TWorkflowTests.RejectsUnsupportedConfiguration;
var
  Logger: ILogger;
begin
  Logger := TFileLogger.Create(TPath.GetFullPath('bin\invalid-config-test.log'));
  Assert.WillRaise(procedure begin
    TProjectScope.Create(TPath.GetFullPath(
      'tests\fixtures\Small\Small.dproj'), Logger, 'Win64', False,
      'Debug" /p:Unexpected=true');
  end, Exception);
end;

procedure TWorkflowTests.EvaluatesOnlySelectedConfigurationPaths;
var
  Root, ProjectFile: string;
  Logger: ILogger;
  Scope: TProjectScope;
begin
  Root := TPath.GetFullPath('bin\msbuild-config-test');
  TDirectory.CreateDirectory(Root);
  TDirectory.CreateDirectory(TPath.Combine(Root, 'Debug64'));
  TDirectory.CreateDirectory(TPath.Combine(Root, 'Release32'));
  ProjectFile := TPath.Combine(Root, 'Config.dproj');
  TFile.WriteAllText(TPath.Combine(Root, 'Config.dpr'),
    'program Config; begin end.');
  TFile.WriteAllText(ProjectFile,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>Config.dpr</MainSource></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Config)''==''Debug'' And ''$(Platform)''==''Win64''">' +
    '<DCC_UnitSearchPath>Debug64</DCC_UnitSearchPath><DCC_Define>FEATURE_DEBUG</DCC_Define></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Config)''==''Release'' And ''$(Platform)''==''Win32''">' +
    '<DCC_UnitSearchPath>Release32</DCC_UnitSearchPath></PropertyGroup>' +
    '</Project>');
  Logger := TFileLogger.Create(TPath.Combine(Root, 'analysis.log'));
  Scope := TProjectScope.Create(ProjectFile, Logger, 'Win64', False, 'Debug',
    TMSBuildPathEvaluator.Create(Logger));
  try
    Assert.AreEqual('Debug', Scope.Config);
    Assert.IsTrue(Scope.SearchDirectories.Contains(TPath.Combine(Root,
      'Debug64')));
    Assert.IsFalse(Scope.SearchDirectories.Contains(TPath.Combine(Root,
      'Release32')));
    Assert.IsTrue(Scope.Defines.Contains('FEATURE_DEBUG'));
  finally
    Scope.Free;
  end;
end;

procedure TWorkflowTests.RetainsUnresolvedReferencesForVisualReview;
var
  Root, ProjectFile: string;
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  Root := TPath.GetFullPath('bin\uncertain-reference-test');
  TDirectory.CreateDirectory(Root);
  ProjectFile := TPath.Combine(Root, 'Uncertain.dproj');
  TFile.WriteAllText(ProjectFile,
    '<Project><PropertyGroup><MainSource>Uncertain.dpr</MainSource></PropertyGroup></Project>');
  TFile.WriteAllText(TPath.Combine(Root, 'Uncertain.dpr'),
    'program Uncertain; uses Consumer in ''Consumer.pas''; begin end.');
  TFile.WriteAllText(TPath.Combine(Root, 'Target.pas'),
    'unit Target; interface implementation end.');
  TFile.WriteAllText(TPath.Combine(Root, 'Consumer.pas'),
    'unit Consumer; interface uses Target, MissingUnit; implementation end.');
  Logger := TFileLogger.Create(TPath.Combine(Root, 'analysis.log'));
  Scope := TProjectScope.Create(ProjectFile, Logger, 'Win64', False);
  try
    Analyzer := TAnalyzer.Create(TAstUnitParser.Create, Logger);
    try
      Analysis := Analyzer.Run(Scope, 'Target');
      try
        Assert.AreEqual(1, Analysis.UnresolvedCount);
        Assert.AreEqual(NativeInt(1), Length(Analysis.Uncertain));
        Assert.AreEqual('MissingUnit', Analysis.Uncertain[0].Dependency.UsedName);
        Assert.AreEqual('unresolved-reference', Analysis.Uncertain[0].Reason);
        Assert.IsTrue(Length(Analysis.Reachable) > 0);
      finally
        Analysis.Free;
      end;
    finally
      Analyzer.Free;
    end;
  finally
    Scope.Free;
  end;
end;

procedure TWorkflowTests.ProjectDefineChangesReverseRoutesBetweenConfigurations;
var
  Root, ProjectFile, Config: string;
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  Root := TPath.GetFullPath('bin\conditional-workflow-test');
  TDirectory.CreateDirectory(Root);
  ProjectFile := TPath.Combine(Root, 'Conditional.dproj');
  TFile.WriteAllText(ProjectFile,
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '<PropertyGroup><MainSource>Conditional.dpr</MainSource></PropertyGroup>' +
    '<PropertyGroup Condition="''$(Config)''==''Debug''"><DCC_Define>FEATURE_X</DCC_Define></PropertyGroup>' +
    '</Project>');
  TFile.WriteAllText(TPath.Combine(Root, 'Conditional.dpr'),
    'program Conditional; uses Consumer in ''Consumer.pas''; begin end.');
  TFile.WriteAllText(TPath.Combine(Root, 'Target.pas'),
    'unit Target; interface implementation end.');
  TFile.WriteAllText(TPath.Combine(Root, 'Consumer.pas'),
    'unit Consumer; interface {$IFDEF FEATURE_X} uses Target; {$ENDIF} implementation end.');
  Logger := TFileLogger.Create(TPath.Combine(Root, 'analysis.log'));
  for Config in ['Debug', 'Release'] do
  begin
    Scope := TProjectScope.Create(ProjectFile, Logger, 'Win64', False,
      Config, TMSBuildPathEvaluator.Create(Logger));
    try
      Analyzer := TAnalyzer.Create(TAstUnitParser.Create(
        Scope.SearchDirectories.ToArray, Logger, Scope.Defines.ToArray,
        Scope.Platform), Logger);
      try
        Analysis := Analyzer.Run(Scope, 'Target');
        try
          Assert.IsFalse(Scope.PathEvaluationWasFallback);
          if Config = 'Debug' then
            Assert.AreEqual(NativeInt(2), Length(Analysis.Reachable))
          else Assert.AreEqual(NativeInt(0), Length(Analysis.Reachable));
        finally
          Analysis.Free;
        end;
      finally
        Analyzer.Free;
      end;
    finally
      Scope.Free;
    end;
  end;
end;

procedure TWorkflowTests.MarksMsbuildFailureAsPartial;
var
  Root, ProjectFile: string;
  Logger: ILogger;
  Scope: TProjectScope;
begin
  Root := TPath.GetFullPath('bin\msbuild-fallback-test');
  TDirectory.CreateDirectory(Root);
  ProjectFile := TPath.Combine(Root, 'Fallback.dproj');
  TFile.WriteAllText(TPath.Combine(Root, 'Fallback.dpr'),
    'program Fallback; begin end.');
  TFile.WriteAllText(ProjectFile,
    '<Project><PropertyGroup><MainSource>Fallback.dpr</MainSource>' +
    '<DCC_UnitSearchPath>.</DCC_UnitSearchPath></PropertyGroup></Project>');
  Logger := TFileLogger.Create(TPath.Combine(Root, 'analysis.log'));
  Scope := TProjectScope.Create(ProjectFile, Logger, 'Win64', False, 'Debug',
    TMSBuildPathEvaluator.Create(Logger));
  try
    Assert.IsTrue(Scope.PathEvaluationWasFallback);
    Assert.IsTrue(Scope.SearchDirectories.Contains(Root));
  finally
    Scope.Free;
  end;
end;

procedure TWorkflowTests.FindsUnitRecursivelyInAdditionalSourceRoot;
var
  Root, ProjectRoot, LibraryRoot, ProjectFile: string;
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  Root := TPath.GetFullPath('bin\additional-root-test');
  ProjectRoot := TPath.Combine(Root, 'Project');
  LibraryRoot := TPath.Combine(Root, 'Library');
  TDirectory.CreateDirectory(ProjectRoot);
  TDirectory.CreateDirectory(TPath.Combine(LibraryRoot, 'Nested'));
  TFile.WriteAllText(TPath.Combine(LibraryRoot, 'Nested\ExternalTarget.pas'),
    'unit ExternalTarget; interface implementation end.');
  TFile.WriteAllText(TPath.Combine(ProjectRoot, 'Consumer.pas'),
    'unit Consumer; interface uses ExternalTarget; implementation end.');
  TFile.WriteAllText(TPath.Combine(ProjectRoot, 'Additional.dpr'),
    'program Additional; uses Consumer; begin end.');
  ProjectFile := TPath.Combine(ProjectRoot, 'Additional.dproj');
  TFile.WriteAllText(ProjectFile,
    '<Project><PropertyGroup><MainSource>Additional.dpr</MainSource>' +
    '</PropertyGroup></Project>');
  Logger := TFileLogger.Create(TPath.Combine(Root, 'analysis.log'));
  Scope := TProjectScope.Create(ProjectFile, Logger, 'Win64', False, '', nil,
    [LibraryRoot]);
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create(
    Scope.SearchDirectories.ToArray, Logger), Logger);
  try
    Assert.AreEqual(soAdditionalRoot, Scope.OriginOf(TPath.Combine(
      LibraryRoot, 'Nested\ExternalTarget.pas')));
    Analysis := Analyzer.Run(Scope, 'ExternalTarget');
    try
      Assert.AreEqual(NativeInt(3), Scope.Files.Count);
      Assert.AreEqual(NativeInt(2), Length(Analysis.Reachable));
      Assert.IsTrue(Analysis.Paths[0].Contains('[DPR]'));
      Assert.AreEqual(0, Analysis.UnresolvedCount);
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.UsesInjectedGlobalPathProvider;
var
  Root, ProjectRoot, LibraryRoot, ProjectFile: string;
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  Root := TPath.GetFullPath('bin\global-path-provider-test');
  ProjectRoot := TPath.Combine(Root, 'Project');
  LibraryRoot := TPath.Combine(Root, 'Library');
  TDirectory.CreateDirectory(ProjectRoot);
  TDirectory.CreateDirectory(LibraryRoot);
  TFile.WriteAllText(TPath.Combine(LibraryRoot, 'InjectedTarget.pas'),
    'unit InjectedTarget; interface implementation end.');
  TFile.WriteAllText(TPath.Combine(ProjectRoot, 'Injected.dpr'),
    'program Injected; uses InjectedTarget; begin end.');
  ProjectFile := TPath.Combine(ProjectRoot, 'Injected.dproj');
  TFile.WriteAllText(ProjectFile,
    '<Project><PropertyGroup><MainSource>Injected.dpr</MainSource>' +
    '</PropertyGroup></Project>');
  Logger := TFileLogger.Create(TPath.Combine(Root, 'analysis.log'));
  Scope := TProjectScope.Create(ProjectFile, Logger, 'Win64', True, '', nil,
    nil, TFixedPathProvider.Create(LibraryRoot));
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create(
    Scope.SearchDirectories.ToArray, Logger), Logger);
  try
    Assert.AreEqual(soGlobalSearchPath, Scope.OriginOf(TPath.Combine(
      LibraryRoot, 'InjectedTarget.pas')));
    Analysis := Analyzer.Run(Scope, 'InjectedTarget');
    try
      Assert.AreEqual(NativeInt(2), Scope.Files.Count);
      Assert.AreEqual(NativeInt(1), Length(Analysis.Reachable));
      Assert.AreEqual(0, Analysis.UnresolvedCount);
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

procedure TWorkflowTests.ClassifiesDprProjectAndLibraryRoutes;
var
  Root, ProjectRoot, LibraryRoot, ProjectFile: string;
  Logger: ILogger;
  Scope: TProjectScope;
  Analyzer: TAnalyzer;
  Analysis: TAnalysisResult;
begin
  Root := TPath.GetFullPath('bin\route-classification-test');
  ProjectRoot := TPath.Combine(Root, 'Project');
  LibraryRoot := TPath.Combine(Root, 'Library');
  TDirectory.CreateDirectory(ProjectRoot);
  TDirectory.CreateDirectory(LibraryRoot);
  TFile.WriteAllText(TPath.Combine(LibraryRoot, 'Target.pas'),
    'unit Target; interface implementation end.');
  TFile.WriteAllText(TPath.Combine(LibraryRoot, 'LibraryConsumer.pas'),
    'unit LibraryConsumer; interface uses Target; implementation end.');
  TFile.WriteAllText(TPath.Combine(LibraryRoot, 'LibraryRoot.pas'),
    'unit LibraryRoot; interface uses LibraryConsumer; implementation end.');
  TFile.WriteAllText(TPath.Combine(ProjectRoot, 'ProjectConsumer.pas'),
    'unit ProjectConsumer; interface uses Target; implementation end.');
  TFile.WriteAllText(TPath.Combine(ProjectRoot, 'ProjectOnly.pas'),
    'unit ProjectOnly; interface uses Target; implementation end.');
  TFile.WriteAllText(TPath.Combine(ProjectRoot, 'Detached.dpr'),
    'program Detached; uses ProjectConsumer; begin end.');
  ProjectFile := TPath.Combine(ProjectRoot, 'Detached.dproj');
  TFile.WriteAllText(ProjectFile,
    '<Project><PropertyGroup><MainSource>Detached.dpr</MainSource>' +
    '<DCC_UnitSearchPath>..\Library</DCC_UnitSearchPath></PropertyGroup></Project>');
  Logger := TFileLogger.Create(TPath.Combine(Root, 'analysis.log'));
  Scope := TProjectScope.Create(ProjectFile, Logger, 'Win64', False);
  Analyzer := TAnalyzer.Create(TAstUnitParser.Create(
    Scope.SearchDirectories.ToArray), Logger);
  try
    Analysis := Analyzer.Run(Scope, 'Target');
    try
      Assert.AreEqual(1, Analysis.RouteCount(rdDpr));
      Assert.AreEqual(1, Analysis.RouteCount(rdProjectFile));
      Assert.AreEqual(1, Analysis.RouteCount(rdLibraryRoot));
      Assert.AreEqual(0, Analysis.RouteCount(rdNoConsumer));
      Assert.AreEqual(soProjectSearchPath,
        Analysis.SourceOrigins[Key(TPath.Combine(LibraryRoot, 'Target.pas'))]);
    finally
      Analysis.Free;
    end;
  finally
    Analyzer.Free;
    Scope.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TGraphTests);
  TDUnitX.RegisterTestFixture(TAstTests);
  TDUnitX.RegisterTestFixture(TLogTests);
  TDUnitX.RegisterTestFixture(TConsoleTests);
  TDUnitX.RegisterTestFixture(TWorkflowTests);

end.
