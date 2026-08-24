{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
===============================================================================}

unit UCPAS;

{$I StdApp.Defines.inc}

interface

procedure RunCLI();

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Console,
  CPaskal.CLI;

procedure RunCLI();
var
  LCLI: TCPCLI;
begin
 try
    ExitCode := 0;
    LCLI := TCPCLI.Create();
    try
      LCLI.Execute();
    finally
      LCLI.Free();
    end;
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: ' + E.Message + COLOR_RESET);
    end;
  end;
end;

end.
