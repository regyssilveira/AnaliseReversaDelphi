// SPDX-License-Identifier: Apache-2.0

unit Reverse.Progress;

interface

uses Reverse.Domain;

type
  TConsoleProgress = class(TInterfacedObject, IAnalysisProgress)
  private
    FStage: string;
    FLastTick: UInt64;
  public
    class function FormatLine(const Stage: string; Completed, Total: Integer): string; static;
    procedure Report(const Stage: string; Completed, Total: Integer);
  end;

implementation

uses System.SysUtils, Winapi.Windows;

procedure TConsoleProgress.Report(const Stage: string; Completed, Total: Integer);
var
  NowTick: UInt64;
begin
  NowTick := GetTickCount64;
  if (Stage = FStage) and (Completed <> Total) and
    (NowTick - FLastTick < 500) then Exit;
  FStage := Stage;
  FLastTick := NowTick;
  Writeln(FormatLine(Stage, Completed, Total));
end;

class function TConsoleProgress.FormatLine(const Stage: string;
  Completed, Total: Integer): string;
begin
  if Total > 0 then
    Result := Format('%s: %d/%d (%d%%)',
      [Stage, Completed, Total, Trunc(Int64(Completed) * 100 / Total)])
  else Result := Stage + '...';
end;

end.
