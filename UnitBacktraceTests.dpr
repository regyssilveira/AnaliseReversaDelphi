// SPDX-License-Identifier: Apache-2.0

program UnitBacktraceTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  Reverse.Domain in 'src\Reverse.Domain.pas',
  Reverse.AST in 'src\Reverse.AST.pas',
  Reverse.Graph in 'src\Reverse.Graph.pas',
  Reverse.Scope in 'src\Reverse.Scope.pas',
  Reverse.Log in 'src\Reverse.Log.pas',
  Reverse.Analysis in 'src\Reverse.Analysis.pas',
  Reverse.Output in 'src\Reverse.Output.pas',
  Reverse.Tests in 'tests\Reverse.Tests.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
begin
  try
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := True;
    Runner.AddLogger(TDUnitXConsoleLogger.Create(False));
    Results := Runner.Execute;
    if not Results.AllPassed then ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
