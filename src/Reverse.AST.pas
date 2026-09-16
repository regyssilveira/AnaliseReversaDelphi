// SPDX-License-Identifier: Apache-2.0

unit Reverse.AST;

interface

uses Reverse.Domain, System.Generics.Collections, DelphiAST, DelphiAST.Classes,
  SimpleParser.Lexer;

type
  TAstUnitParser = class(TInterfacedObject, IUnitParser)
  private
    FSearchPaths: TArray<string>;
    FLogger: ILogger;
    FLastFallback: Boolean;
    FDefines: TArray<string>;
    FPlatform: string;
    procedure ConfigureDefines(const Lexer: TmwBasePasLex);
    procedure Collect(Node: TSyntaxNode; const Consumer, Section,
      FileName: string; Dependencies: TList<TDependency>);
    function ParseTokens(const FileName: string;
      Dependencies: TList<TDependency>): string;
  public
    constructor Create(const SearchPaths: TArray<string>;
      const Logger: ILogger = nil;
      const Defines: TArray<string> = nil;
      const Platform: string = ''); overload;
    function Parse(const FileName: string; Dependencies: TList<TDependency>): string;
    function LastParseWasFallback: Boolean;
  end;

implementation

uses System.SysUtils, System.IOUtils, System.Classes, DelphiAST.Consts,
  SimpleParser.Lexer.Types;

type
  TRelativeIncludeHandler = class(TInterfacedObject, IIncludeHandler)
  private
    FMainFileName: string;
    FSearchPaths: TArray<string>;
  public
    constructor Create(const MainFileName: string;
      const SearchPaths: TArray<string>);
    function GetIncludeFileContent(const ParentFileName, IncludeName: string;
      out Content: string; out FileName: string): Boolean;
  end;

constructor TRelativeIncludeHandler.Create(const MainFileName: string;
  const SearchPaths: TArray<string>);
begin
  inherited Create;
  FMainFileName := MainFileName;
  FSearchPaths := SearchPaths;
end;

function TRelativeIncludeHandler.GetIncludeFileContent(const ParentFileName,
  IncludeName: string; out Content, FileName: string): Boolean;
var
  BaseFile: string;
  Directory: string;
begin
  BaseFile := ParentFileName;
  if BaseFile = '' then BaseFile := FMainFileName;
  FileName := IncludeName;
  if not TPath.IsPathRooted(FileName) then
    FileName := TPath.GetFullPath(TPath.Combine(
      ExtractFilePath(BaseFile), FileName));
  Result := FileExists(FileName);
  if not Result then
    for Directory in FSearchPaths do
    begin
      FileName := TPath.GetFullPath(TPath.Combine(Directory, IncludeName));
      if FileExists(FileName) then
      begin
        Result := True;
        Break;
      end;
    end;
  if not Result then raise EIncludeError.Create('Include not found: ' + IncludeName);
  Content := TFile.ReadAllText(FileName);
end;

constructor TAstUnitParser.Create(const SearchPaths: TArray<string>;
  const Logger: ILogger; const Defines: TArray<string>;
  const Platform: string);
begin
  inherited Create;
  FSearchPaths := SearchPaths;
  FLogger := Logger;
  FDefines := Defines;
  FPlatform := Platform;
end;

procedure TAstUnitParser.ConfigureDefines(const Lexer: TmwBasePasLex);
var
  Symbol: string;
begin
  Lexer.InitDefinesDefinedByCompiler;
  Lexer.RemoveDefine('CONSOLE');
  if SameText(FPlatform, 'Win32') then
  begin
    Lexer.RemoveDefine('WIN64');
    Lexer.RemoveDefine('CPUX64');
    Lexer.RemoveDefine('CPU64BITS');
    Lexer.AddDefine('WIN32');
    Lexer.AddDefine('CPU386');
    Lexer.AddDefine('CPUX86');
    Lexer.AddDefine('CPU32BITS');
  end
  else if SameText(FPlatform, 'Win64') then
  begin
    Lexer.RemoveDefine('WIN32');
    Lexer.RemoveDefine('CPU386');
    Lexer.RemoveDefine('CPUX86');
    Lexer.RemoveDefine('CPU32BITS');
    Lexer.AddDefine('WIN64');
    Lexer.AddDefine('CPUX64');
    Lexer.AddDefine('CPU64BITS');
  end;
  for Symbol in FDefines do Lexer.AddDefine(Symbol);
end;

function TAstUnitParser.LastParseWasFallback: Boolean;
begin
  Result := FLastFallback;
end;

function TAstUnitParser.ParseTokens(const FileName: string;
  Dependencies: TList<TDependency>): string;
var
  Lexer: TmwPasLex;
  Section, NamePart, DeclaredPath: string;
  FirstLine: Integer;
  FirstFile: string;
  Edge: TDependency;

  procedure AddUsedUnit;
  begin
    if NamePart = '' then Exit;
    Edge.Consumer := Result;
    Edge.ConsumerPath := FileName;
    Edge.UsedName := NamePart;
    Edge.UsedPath := '';
    Edge.DeclaredPath := DeclaredPath;
    Edge.SourceFile := FirstFile;
    Edge.Section := Section;
    Edge.Line := FirstLine;
    Dependencies.Add(Edge);
    NamePart := '';
    DeclaredPath := '';
  end;

  procedure Advance;
  begin
    Lexer.NextNoJunk;
  end;

begin
  Result := ChangeFileExt(ExtractFileName(FileName), '');
  if SameText(ExtractFileExt(FileName), '.dpr') then Section := 'program'
  else Section := 'interface';
  Lexer := TmwPasLex.Create;
  try
    Lexer.IncludeHandler := TRelativeIncludeHandler.Create(FileName, FSearchPaths);
    ConfigureDefines(Lexer);
    Lexer.Origin := TFile.ReadAllText(FileName);
    while Lexer.TokenID <> ptNull do
    begin
      if Lexer.TokenID in [ptUnit, ptProgram] then
      begin
        Advance;
        Result := '';
        while (Lexer.TokenID <> ptSemiColon) and (Lexer.TokenID <> ptNull) do
        begin
          Result := Result + Lexer.Token;
          Advance;
        end;
      end
      else if Lexer.TokenID = ptInterface then Section := 'interface'
      else if Lexer.TokenID = ptImplementation then Section := 'implementation'
      else if Lexer.TokenID = ptUses then
      begin
        NamePart := '';
        DeclaredPath := '';
        FirstLine := 0;
        FirstFile := FileName;
        Advance;
        while (Lexer.TokenID <> ptSemiColon) and (Lexer.TokenID <> ptNull) do
        begin
          if Lexer.TokenID = ptComma then AddUsedUnit
          else if Lexer.TokenID = ptIn then
          begin
            Advance;
            DeclaredPath := Lexer.Token.Trim(['''']);
          end
          else
          begin
            if FirstLine = 0 then
            begin
              FirstLine := Lexer.PosXY.Y;
              if Lexer.FileName <> '' then FirstFile := Lexer.FileName;
            end;
            NamePart := NamePart + Lexer.Token;
          end;
          Advance;
        end;
        AddUsedUnit;
      end;
      Advance;
    end;
  finally
    Lexer.Free;
  end;
end;

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
        Edge.ConsumerPath := FileName;
        Edge.UsedName := Child.GetAttribute(anName);
        Edge.DeclaredPath := Child.GetAttribute(anPath);
        Edge.UsedPath := '';
        Edge.SourceFile := Child.FileName;
        if Edge.SourceFile = '' then Edge.SourceFile := FileName;
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
  Builder: TPasSyntaxTreeBuilder;
  Stream: TStringStream;
begin
  FLastFallback := False;
  try
    Stream := TStringStream.Create;
    try
      Stream.LoadFromFile(FileName);
      Builder := TPasSyntaxTreeBuilder.Create;
      try
        ConfigureDefines(Builder.Lexer.Lexer);
        Builder.IncludeHandler := TRelativeIncludeHandler.Create(FileName, FSearchPaths);
        Root := Builder.Run(Stream);
      finally
        Builder.Free;
      end;
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
    begin
      Dependencies.Clear;
      FLastFallback := True;
      if FLogger <> nil then FLogger.Write('WARN', 'ast-fallback',
        FileName + ' | ' + E.Message);
      Result := ParseTokens(FileName, Dependencies);
      Exit;
    end;
  end;
  try
    Result := Root.GetAttribute(anName);
    if Result = '' then Result := ChangeFileExt(ExtractFileName(FileName), '');
    Collect(Root, Result, 'program', FileName, Dependencies);
  finally
    Root.Free;
  end;
end;

end.
