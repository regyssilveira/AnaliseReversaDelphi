// SPDX-License-Identifier: Apache-2.0

unit Reverse.Progress;

interface

uses Reverse.Domain;

type
  TConsoleProgress = class(TInterfacedObject, IAnalysisProgress)
  private
    FStage: string;
    FLastTick: UInt64;
    FInteractive: Boolean;
    FActiveLine: Boolean;
    FLastWidth: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    class function FormatLine(const Stage: string; Completed, Total: Integer): string; static;
    class function RewriteLine(const Line: string; PreviousWidth: Integer): string; static;
    procedure Report(const Stage: string; Completed, Total: Integer);
  end;

implementation

uses System.SysUtils, System.Math, Winapi.Windows;

constructor TConsoleProgress.Create;
var
  Mode: DWORD;
begin
  inherited Create;
  FInteractive := GetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), Mode);
end;

destructor TConsoleProgress.Destroy;
begin
  if FActiveLine then Writeln;
  inherited;
end;

procedure TConsoleProgress.Report(const Stage: string; Completed, Total: Integer);
var
  NowTick: UInt64;
  Line: string;
  IsComplete: Boolean;
begin
  NowTick := GetTickCount64;
  if (Stage = FStage) and (Completed <> Total) and
    (NowTick - FLastTick < 500) then Exit;
  if FInteractive and FActiveLine and (Stage <> FStage) then
  begin
    Writeln;
    FActiveLine := False;
    FLastWidth := 0;
  end;
  FStage := Stage;
  FLastTick := NowTick;
  Line := FormatLine(Stage, Completed, Total);
  IsComplete := (Total > 0) and (Completed >= Total);
  if not FInteractive then
  begin
    Writeln(Line);
    Exit;
  end;
  if FActiveLine then Write(RewriteLine(Line, FLastWidth))
  else Write(Line);
  FLastWidth := Length(Line);
  FActiveLine := True;
  if IsComplete then
  begin
    Writeln;
    FActiveLine := False;
    FLastWidth := 0;
  end;
end;

class function TConsoleProgress.RewriteLine(const Line: string;
  PreviousWidth: Integer): string;
begin
  Result := #13 + Line;
  if PreviousWidth > Length(Line) then
    Result := Result + StringOfChar(' ', PreviousWidth - Length(Line));
end;

class function TConsoleProgress.FormatLine(const Stage: string;
  Completed, Total: Integer): string;
const
  BarWidth = 24;
var
  SafeCompleted, Percent, Filled: Integer;
begin
  if Total > 0 then
  begin
    SafeCompleted := EnsureRange(Completed, 0, Total);
    Percent := Trunc(Int64(SafeCompleted) * 100 / Total);
    Filled := Trunc(Int64(SafeCompleted) * BarWidth / Total);
    Result := Format('%s: [%s%s] %3d%% %d/%d',
      [Stage, StringOfChar('#', Filled), StringOfChar('-', BarWidth - Filled),
       Percent, SafeCompleted, Total]);
  end
  else Result := Stage + '...';
end;

end.
