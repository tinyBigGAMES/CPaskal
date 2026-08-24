{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
===============================================================================}

program cpas;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  UCPAS in 'UCPAS.pas',
  CPaskal.CLI in '..\..\src\CPaskal.CLI.pas';

begin
  RunCLI();
end.
