unit Reverse.AST;

interface

uses Reverse.Domain, System.Generics.Collections, DelphiAST, DelphiAST.Classes;

type
  TAstUnitParser = class(TInterfacedObject, IUnitParser)
  private
    procedure Collect(Node: TSyntaxNode; const Consumer, Section,
      FileName: string; Dependencies: TList<TDependency>);
  public
    function Parse(const FileName: string; Dependencies: TList<TDependency>): string;
  end;

implementation

uses System.SysUtils, DelphiAST.Consts;

procedure TAstUnitParser.Collect(Node: TSyntaxNode; const Consumer,
  Section, FileName: string; Dependencies: TList<TDependency>);
var
  Child: TSyntaxNode;
  NextSection: string;
  Edge: TDependency;
begin
  NextSection := Section;
  if Node.Typ = ntInterface then NextSection := 'interface';
  if Node.Typ = ntImplementation then NextSection := 'implementation';
  if Node.Typ = ntUses then
  begin
    for Child in Node.ChildNodes do
      if Child.Typ = ntUnit then
      begin
        Edge.Consumer := Consumer;
        Edge.UsedName := Child.GetAttribute(anName);
        Edge.SourceFile := FileName;
        Edge.Section := NextSection;
        Edge.Line := Child.Line;
        if Edge.UsedName <> '' then Dependencies.Add(Edge);
      end;
    Exit;
  end;
  for Child in Node.ChildNodes do
    Collect(Child, Consumer, NextSection, FileName, Dependencies);
end;

function TAstUnitParser.Parse(const FileName: string;
  Dependencies: TList<TDependency>): string;
var
  Root: TSyntaxNode;
begin
  Root := TPasSyntaxTreeBuilder.Run(FileName, False);
  try
    Result := Root.GetAttribute(anName);
    if Result = '' then Result := ChangeFileExt(ExtractFileName(FileName), '');
    Collect(Root, Result, 'program', FileName, Dependencies);
  finally
    Root.Free;
  end;
end;

end.
