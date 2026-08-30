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
  CPaskal.AST in '..\..\src\CPaskal.AST.pas',
  CPaskal.CImporter in '..\..\src\CPaskal.CImporter.pas',
  CPaskal.CImporter.Script in '..\..\src\CPaskal.CImporter.Script.pas',
  CPaskal.CLI in '..\..\src\CPaskal.CLI.pas',
  CPaskal.Codegen in '..\..\src\CPaskal.Codegen.pas',
  CPaskal.Common in '..\..\src\CPaskal.Common.pas',
  CPaskal.Compiler in '..\..\src\CPaskal.Compiler.pas',
  CPaskal.Debug.Client in '..\..\src\CPaskal.Debug.Client.pas',
  CPaskal.Debug.DAP in '..\..\src\CPaskal.Debug.DAP.pas',
  CPaskal.Debug.PDB in '..\..\src\CPaskal.Debug.PDB.pas',
  CPaskal.Debug.REPL in '..\..\src\CPaskal.Debug.REPL.pas',
  CPaskal.Debug.Runtime in '..\..\src\CPaskal.Debug.Runtime.pas',
  CPaskal.Debug.Server in '..\..\src\CPaskal.Debug.Server.pas',
  CPaskal.Debug.Target in '..\..\src\CPaskal.Debug.Target.pas',
  CPaskal.Lexer in '..\..\src\CPaskal.Lexer.pas',
  CPaskal.LSP in '..\..\src\CPaskal.LSP.pas',
  CPaskal.Parser in '..\..\src\CPaskal.Parser.pas',
  CPaskal.Script in '..\..\src\CPaskal.Script.pas',
  CPaskal.Semantics in '..\..\src\CPaskal.Semantics.pas',
  CPaskal.ZigBuild in '..\..\src\CPaskal.ZigBuild.pas',
  CPaskal.ZigBuild.Targets in '..\..\src\CPaskal.ZigBuild.Targets.pas',
  StdApp.Resources in '..\..\src\StdApp.Resources.pas';

begin
  RunCLI();
end.
