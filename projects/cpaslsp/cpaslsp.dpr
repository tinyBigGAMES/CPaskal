{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
===============================================================================}

program cpaslsp;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  UCPasLSP in 'UCPasLSP.pas',
  CPaskal.LSP in '..\..\src\CPaskal.LSP.pas';

begin
  RunLSP();
end.
