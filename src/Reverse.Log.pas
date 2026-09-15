// SPDX-License-Identifier: Apache-2.0

unit Reverse.Log;

interface

uses Reverse.Domain, System.Classes;

type
  TFileLogger = class(TInterfacedObject, ILogger)
  private
    FWriter: TStreamWriter;
    FPendingCount: Integer;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    procedure Write(const Level, Event, Detail: string);
  end;

implementation

uses System.SysUtils;

constructor TFileLogger.Create(const FileName: string);
begin
  inherited Create;
  FWriter := TStreamWriter.Create(FileName, False, TEncoding.UTF8);
end;

destructor TFileLogger.Destroy;
begin
  FWriter.Free;
  inherited;
end;

procedure TFileLogger.Write(const Level, Event, Detail: string);
begin
  FWriter.WriteLine(FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now) +
    ' [' + Level + '] ' + Event + ' | ' + Detail);
  Inc(FPendingCount);
  if (FPendingCount >= 200) or not SameText(Level, 'DEBUG') then
  begin
    FWriter.Flush;
    FPendingCount := 0;
  end;
end;

end.
