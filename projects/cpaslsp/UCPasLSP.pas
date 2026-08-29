{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
===============================================================================}

unit UCPasLSP;

interface

procedure RunLSP();

implementation

uses
  System.SysUtils,
  StdApp.Console,
  StdApp.Utils,
  CPaskal.LSP;

procedure RunLSP();
var
  LServer: TCPLSPServer;
begin
  try
    LServer := TCPLSPServer.Create();
    try
      ExitCode := LServer.Run();
    finally
      LServer.Free();
    end;
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: %s', [E.Message]);
    end;
  end;
end;

end.
