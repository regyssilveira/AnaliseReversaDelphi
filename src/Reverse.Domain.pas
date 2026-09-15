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

  IUnitParser = interface
    ['{641C73C6-AD76-4E05-9AC7-D0FDD275508C}']
    function Parse(const FileName: string; Dependencies: TList<TDependency>): string;
    function LastParseWasFallback: Boolean;
  end;

  ILogger = interface
    ['{C5AF8A52-C551-445B-BC5B-4FEAE9C03D08}']
    procedure Write(const Level, Event, Detail: string);
  end;

function Key(const Name: string): string;

implementation

function Key(const Name: string): string;
begin
  Result := LowerCase(Trim(Name));
  if Result.Contains('\') or Result.Contains('/') or
    (ExtractFileDrive(Result) <> '') then Exit;
  if SameText(ExtractFileExt(Result), '.pas') then
    Result := ChangeFileExt(Result, '');
end;

end.
