// SPDX-License-Identifier: Apache-2.0

unit UnitBacktrace.IDE.Progress;

interface

uses System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.ComCtrls,
  Reverse.Domain, Reverse.Runner;

type
  TAnalysisProgressForm = class(TForm)
  private
    FStatus: TLabel;
    FProgress: TProgressBar;
    FDetails: TMemo;
    FCloseButton: TButton;
    FOpenButton: TButton;
    FRunning: Boolean;
    FGraphFile: string;
    FCancellation: IAnalysisCancellation;
    procedure CloseClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormClosed(Sender: TObject; var Action: TCloseAction);
    procedure UpdateProgress(const Stage: string; Completed, Total: Integer);
    procedure Finish(const ErrorText: string; Partial: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start(const Request: TAnalysisRequest; const OutputDir: string);
    class procedure StartAnalysis(const Request: TAnalysisRequest;
      const OutputDir: string); static;
  end;

implementation

uses System.SysUtils, System.IOUtils, Winapi.Windows, Winapi.ShellAPI,
  Vcl.Controls, Vcl.Dialogs, Reverse.Analysis, Reverse.Log, Reverse.Output;

type
  TIDEProgress = class(TInterfacedObject, IAnalysisProgress)
  private
    FForm: TAnalysisProgressForm;
    FLastStage: string;
    FLastTick: UInt64;
  public
    constructor Create(Form: TAnalysisProgressForm);
    procedure Report(const Stage: string; Completed, Total: Integer);
  end;

  TIDECancellation = class(TInterfacedObject, IAnalysisCancellation)
  private
    FRequested: Integer;
  public
    procedure RequestCancel;
    function IsCancellationRequested: Boolean;
  end;

var
  ActiveForm: TAnalysisProgressForm;

constructor TIDEProgress.Create(Form: TAnalysisProgressForm);
begin
  inherited Create;
  FForm := Form;
end;

procedure TIDECancellation.RequestCancel;
begin
  InterlockedExchange(FRequested, 1);
end;

function TIDECancellation.IsCancellationRequested: Boolean;
begin
  Result := InterlockedCompareExchange(FRequested, 0, 0) <> 0;
end;

procedure TIDEProgress.Report(const Stage: string; Completed, Total: Integer);
var
  StageCopy: string;
  CompletedCopy, TotalCopy: Integer;
  NowTick: UInt64;
begin
  NowTick := GetTickCount64;
  if (Stage = FLastStage) and (Completed < Total) and
    (NowTick - FLastTick < 250) then Exit;
  FLastStage := Stage;
  FLastTick := NowTick;
  StageCopy := Stage;
  CompletedCopy := Completed;
  TotalCopy := Total;
  TThread.Queue(nil,
    procedure
    begin
      if FForm <> nil then
        FForm.UpdateProgress(StageCopy, CompletedCopy, TotalCopy);
    end);
end;

constructor TAnalysisProgressForm.Create(AOwner: TComponent);
begin
  inherited;
  Caption := 'Delphi Unit Backtrace';
  Width := 620;
  Height := 330;
  Position := poScreenCenter;
  BorderStyle := bsSizeable;
  OnCloseQuery := FormCloseQuery;
  OnClose := FormClosed;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alTop;
  FStatus.AutoSize := False;
  FStatus.Height := 38;
  FStatus.Margins.SetBounds(12, 12, 12, 6);
  FStatus.AlignWithMargins := True;
  FStatus.Caption := 'Preparando análise...';

  FProgress := TProgressBar.Create(Self);
  FProgress.Parent := Self;
  FProgress.Align := alTop;
  FProgress.Height := 24;
  FProgress.Margins.SetBounds(12, 0, 12, 8);
  FProgress.AlignWithMargins := True;
  FProgress.Min := 0;
  FProgress.Max := 100;

  FDetails := TMemo.Create(Self);
  FDetails.Parent := Self;
  FDetails.Align := alClient;
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssVertical;
  FDetails.Margins.SetBounds(12, 0, 12, 8);
  FDetails.AlignWithMargins := True;

  FCloseButton := TButton.Create(Self);
  FCloseButton.Parent := Self;
  FCloseButton.Align := alBottom;
  FCloseButton.Height := 34;
  FCloseButton.Caption := 'Cancelar';
  FCloseButton.Enabled := True;
  FCloseButton.OnClick := CloseClick;

  FOpenButton := TButton.Create(Self);
  FOpenButton.Parent := Self;
  FOpenButton.Align := alBottom;
  FOpenButton.Height := 34;
  FOpenButton.Caption := 'Abrir gráfico';
  FOpenButton.Enabled := False;
  FOpenButton.OnClick := OpenClick;
end;

procedure TAnalysisProgressForm.CloseClick(Sender: TObject);
begin
  if FRunning then
  begin
    FCancellation.RequestCancel;
    FCloseButton.Enabled := False;
    FStatus.Caption := 'Cancelando análise...';
  end
  else
    Close;
end;

procedure TAnalysisProgressForm.OpenClick(Sender: TObject);
begin
  if TFile.Exists(FGraphFile) then
    ShellExecute(0, 'open', PChar(FGraphFile), nil,
      PChar(ExtractFilePath(FGraphFile)), SW_SHOWNORMAL);
end;

procedure TAnalysisProgressForm.FormCloseQuery(Sender: TObject;
  var CanClose: Boolean);
begin
  CanClose := not FRunning;
end;

procedure TAnalysisProgressForm.FormClosed(Sender: TObject;
  var Action: TCloseAction);
begin
  ActiveForm := nil;
  Action := caFree;
end;

procedure TAnalysisProgressForm.UpdateProgress(const Stage: string;
  Completed, Total: Integer);
begin
  FStatus.Caption := Stage;
  if Total > 0 then
  begin
    FProgress.Position := Trunc(Int64(Completed) * 100 / Total);
    FDetails.Lines.Add(Format('%s: %d/%d (%d%%)',
      [Stage, Completed, Total, FProgress.Position]));
  end
  else
    FDetails.Lines.Add(Stage);
end;

procedure TAnalysisProgressForm.Finish(const ErrorText: string;
  Partial: Boolean);
begin
  FRunning := False;
  FCancellation := nil;
  FCloseButton.Enabled := True;
  FCloseButton.Caption := 'Fechar';
  if ErrorText = 'CANCELLED' then
  begin
    FStatus.Caption := 'Análise cancelada.';
    FDetails.Lines.Add('A análise foi cancelada pelo usuário.');
    Exit;
  end;
  if ErrorText <> '' then
  begin
    FStatus.Caption := 'A análise falhou.';
    FDetails.Lines.Add(ErrorText);
    MessageDlg(ErrorText, mtError, [mbOK], 0);
    Exit;
  end;
  FProgress.Position := 100;
  FOpenButton.Enabled := True;
  if Partial then
    FStatus.Caption := 'Análise parcial concluída. Consulte analysis.log.'
  else
    FStatus.Caption := 'Análise concluída.';
  FDetails.Lines.Add('Resultado: ' + ExtractFilePath(FGraphFile));
  OpenClick(nil);
end;

procedure TAnalysisProgressForm.Start(const Request: TAnalysisRequest;
  const OutputDir: string);
var
  RequestCopy: TAnalysisRequest;
  OutputCopy: string;
begin
  RequestCopy := Request;
  FCancellation := TIDECancellation.Create;
  RequestCopy.Cancellation := FCancellation;
  OutputCopy := OutputDir;
  FGraphFile := TPath.Combine(OutputDir, 'graph.html');
  FRunning := True;
  Show;
  TThread.CreateAnonymousThread(
    procedure
    var
      Analysis: TAnalysisResult;
      Logger: ILogger;
      Progress: IAnalysisProgress;
      ErrorText: string;
      Partial: Boolean;
    begin
      ErrorText := '';
      Partial := False;
      try
        TDirectory.CreateDirectory(OutputCopy);
        Logger := TFileLogger.Create(TPath.Combine(OutputCopy, 'analysis.log'));
        if RequestCopy.TargetUnit = '' then
          Logger.Write('INFO', 'ide-start-project-map', RequestCopy.ProjectFile)
        else
          Logger.Write('INFO', 'ide-start', RequestCopy.ProjectFile + ' | ' +
            RequestCopy.TargetUnit);
        Progress := TIDEProgress.Create(Self);
        Analysis := TAnalysisRunner.Run(RequestCopy, Logger, Progress);
        try
          TOutputWriter.WriteFiles(Analysis, OutputCopy);
          Partial := TAnalysisRunner.IsPartial(Analysis);
        finally
          Analysis.Free;
        end;
      except
        on E: EAnalysisCancelled do ErrorText := 'CANCELLED';
        on E: Exception do ErrorText := E.ClassName + ': ' + E.Message;
      end;
      TThread.Queue(nil,
        procedure
        begin
          Finish(ErrorText, Partial);
        end);
    end).Start;
end;

class procedure TAnalysisProgressForm.StartAnalysis(
  const Request: TAnalysisRequest; const OutputDir: string);
begin
  if ActiveForm <> nil then
  begin
    ActiveForm.Show;
    ActiveForm.BringToFront;
    MessageDlg('Já existe uma análise em andamento ou aguardando revisão.',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  ActiveForm := TAnalysisProgressForm.Create(Application);
  ActiveForm.Start(Request, OutputDir);
end;

end.
