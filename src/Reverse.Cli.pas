// SPDX-License-Identifier: Apache-2.0

unit Reverse.Cli;

interface

uses Reverse.Analysis;

type
  TConsoleReport = class
  public
    class function DefaultOutputDirectory(const CurrentDirectory,
      ProjectFile, UnitName: string): string; static;
    class function SummaryLines(const Analysis: TAnalysisResult): TArray<string>; static;
  end;

implementation

uses System.SysUtils, System.IOUtils, System.RegularExpressions, System.Hash,
  System.Generics.Collections, Reverse.Domain;

function SafeFolderName(const Value: string): string;
begin
  Result := TRegEx.Replace(Trim(Value), '[^\p{L}\p{N}_.-]', '_');
  Result := Result.Trim(['.', ' ', '_']);
  if Result = '' then raise Exception.Create('Invalid output folder name');
  if SameText(Result, 'CON') or SameText(Result, 'PRN') or
    SameText(Result, 'AUX') or SameText(Result, 'NUL') or
    TRegEx.IsMatch(Result, '^(COM[1-9]|LPT[1-9])$', [roIgnoreCase]) then
    Result := '_' + Result;
end;

function CountLabel(const Count: Integer; const Singular, Plural: string): string;
begin
  if Count = 1 then Result := Singular else Result := Plural;
end;

class function TConsoleReport.DefaultOutputDirectory(const CurrentDirectory,
  ProjectFile, UnitName: string): string;
var
  ProjectKey: string;
begin
  ProjectKey := TPath.GetFullPath(ProjectFile).ToUpperInvariant;
  Result := TPath.Combine(CurrentDirectory, 'analysis-output');
  Result := TPath.Combine(Result, SafeFolderName(
    ChangeFileExt(ExtractFileName(ProjectFile), '')) + '-' +
    Copy(THashSHA2.GetHashString(ProjectKey), 1, 8));
  Result := TPath.Combine(Result, SafeFolderName(UnitName));
end;

class function TConsoleReport.SummaryLines(
  const Analysis: TAnalysisResult): TArray<string>;
var
  ToProgram: TDictionary<string, Boolean>;
  Consumers: TDictionary<string, Boolean>;
  ByConsumer: TObjectDictionary<string, TList<string>>;
  Queue: TQueue<string>;
  UsedFiles: TList<string>;
  Edge: TDependency;
  ConsumerFile, UsedFile, Status, Connected: string;
  DirectDeclarations: Integer;
  Partial: Boolean;
begin
  ToProgram := TDictionary<string, Boolean>.Create;
  Consumers := TDictionary<string, Boolean>.Create;
  ByConsumer := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  Queue := TQueue<string>.Create;
  try
    for Edge in Analysis.Reachable do
    begin
      ConsumerFile := Key(Edge.ConsumerPath);
      if not ByConsumer.TryGetValue(ConsumerFile, UsedFiles) then
      begin
        UsedFiles := TList<string>.Create;
        ByConsumer.Add(ConsumerFile, UsedFiles);
      end;
      UsedFiles.Add(Key(Edge.UsedPath));
    end;
    ConsumerFile := Key(Analysis.ProgramFile);
    ToProgram.Add(ConsumerFile, True);
    Queue.Enqueue(ConsumerFile);
    while Queue.Count > 0 do
    begin
      ConsumerFile := Queue.Dequeue;
      if not ByConsumer.TryGetValue(ConsumerFile, UsedFiles) then Continue;
      for UsedFile in UsedFiles do
        if not ToProgram.ContainsKey(UsedFile) then
        begin
          ToProgram.Add(UsedFile, True);
          Queue.Enqueue(UsedFile);
        end;
    end;
    DirectDeclarations := 0;
    for Edge in Analysis.Reachable do
      if SameText(Edge.UsedPath, Analysis.TargetFile) and
        ToProgram.ContainsKey(Key(Edge.ConsumerPath)) then
      begin
        Inc(DirectDeclarations);
        Consumers.AddOrSetValue(Key(Edge.ConsumerPath), True);
      end;
    Partial := (Analysis.FallbackCount > 0) or (Analysis.FailedCount > 0) or
      Analysis.PathEvaluationWasFallback or (Analysis.UnresolvedCount > 0) or
      (Analysis.AmbiguousCount > 0);
    if ToProgram.ContainsKey(Key(Analysis.TargetFile)) then Connected := 'sim'
    else Connected := 'nao';
    if Partial then Status := 'parcial' else Status := 'completa';
    Result := [Format('Resumo: %d %s ate o DPR | %d %s uses | %d %s',
      [Consumers.Count, CountLabel(Consumers.Count, 'consumidor direto', 'consumidores diretos'),
       DirectDeclarations, CountLabel(DirectDeclarations, 'declaracao', 'declaracoes'),
       Length(Analysis.Reachable), CountLabel(Length(Analysis.Reachable),
         'ligacao alcancavel', 'ligacoes alcancaveis')]),
      Format('Caminho ate o DPR: %s | Analise: %s',
        [Connected, Status])];
    if Partial then
    begin
      SetLength(Result, 3);
      Result[2] := Format('Confira analysis.log: %d nao resolvidas | %d ambiguas | %d falhas | %d fallbacks',
        [Analysis.UnresolvedCount, Analysis.AmbiguousCount,
         Analysis.FailedCount, Analysis.FallbackCount]);
      if Analysis.PathEvaluationWasFallback then
        Result[2] := Result[2] + ' | MSBuild fallback';
    end;
  finally
    Queue.Free;
    ByConsumer.Free;
    Consumers.Free;
    ToProgram.Free;
  end;
end;

end.
