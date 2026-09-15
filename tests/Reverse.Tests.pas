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
    [Test] procedure KeepsAllEdgesAfterRevisitingNode;
    [Test] procedure LimitsPathEnumerationWithoutDroppingGraphEdges;
    [Test] procedure KeepsSameNamedFilesSeparateWhenPathsAreKnown;
    [Test] procedure SkipsIdenticalEdgesButKeepsDifferentEvidence;
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
  end;

  [TestFixture]
  TLogTests = class
  public
    [Test] procedure PersistsDebugAndWarningsAfterClose;
    [Test] procedure FormatsProgressWithKnownAndUnknownTotals;
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
  end;

implementation

uses Reverse.AST, Reverse.Scope, Reverse.Analysis, Reverse.Output, Reverse.Log,
  Reverse.Progress,
  Reverse.MSBuild,
  System.SysUtils, System.IOUtils, System.Classes, SimpleParser.Lexer.Types;

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

constructor TProgressRecorder.Create;
begin
  inherited;
  Stages := TList<string>.Create;
  CompletedValues := TList<Integer>.Create;
  Totals := TList<Integer>.Create;
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
  Assert.AreEqual('Analisando arquivos: 5/20 (25%)',
    TConsoleProgress.FormatLine('Analisando arquivos', 5, 20));
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
    '<DCC_UnitSearchPath>Debug64</DCC_UnitSearchPath></PropertyGroup>' +
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
  finally
    Scope.Free;
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

initialization
  TDUnitX.RegisterTestFixture(TGraphTests);
  TDUnitX.RegisterTestFixture(TAstTests);
  TDUnitX.RegisterTestFixture(TLogTests);
  TDUnitX.RegisterTestFixture(TWorkflowTests);

end.
