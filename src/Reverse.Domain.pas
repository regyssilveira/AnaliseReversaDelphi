// SPDX-License-Identifier: Apache-2.0

unit Reverse.Domain;

interface

uses System.SysUtils, System.Generics.Collections;

type
  TDependency = record
    Consumer: string;
    ConsumerPath: string;
    UsedName: string;
    UsedPath: string;
    DeclaredPath: string;
    SourceFile: string;
    Section: string;
    Line: Integer;
  end;

  TUnitFile = record
    Name: string;
    Path: string;
  end;

  TUncertainReference = record
    Dependency: TDependency;
    Reason: string;
  end;

  IUnitParser = interface
    ['{641C73C6-AD76-4E05-9AC7-D0FDD275508C}']
    function Parse(const FileName: string; Dependencies: TList<TDependency>): string;
    function LastParseWasFallback: Boolean;
  end;

  ILogger = interface
    ['{C5AF8A52-C551-445B-BC5B-4FEAE9C03D08}']
    procedure Write(const Level, Event, Detail: string);
  end;

  IAnalysisProgress = interface
    ['{209E72D8-5722-4C91-A52E-778512A86612}']
    procedure Report(const Stage: string; Completed, Total: Integer);
  end;

  IProjectPathEvaluator = interface
    ['{6A18A89C-454A-484E-8971-59E4B3C9927A}']
    function Evaluate(const ProjectFile, Config, Platform,
      PropertyName: string): TArray<string>;
  end;

  IGlobalSourcePathProvider = interface
    ['{A04CB2BD-9D53-45D6-8CE0-A965A12478C4}']
    function Paths(const Platform, ProjectRoot: string): TArray<string>;
  end;

function Key(const Name: string): string;
function DependencyIdentity(const Edge: TDependency): string;

implementation

function Key(const Name: string): string;
begin
  Result := LowerCase(Trim(Name));
  if Result.Contains('\') or Result.Contains('/') or
    (ExtractFileDrive(Result) <> '') then Exit;
  if SameText(ExtractFileExt(Result), '.pas') then
    Result := ChangeFileExt(Result, '');
end;

function DependencyIdentity(const Edge: TDependency): string;
begin
  Result := Edge.UsedName + #0 + Edge.UsedPath + #0 +
    Edge.Consumer + #0 + Edge.ConsumerPath + #0 +
    Edge.DeclaredPath + #0 + Edge.SourceFile + #0 +
    Edge.Section + #0 + Edge.Line.ToString;
end;

end.
