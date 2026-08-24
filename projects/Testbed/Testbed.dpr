{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
===============================================================================}

program Testbed;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  CPaskal.Common in '..\..\src\CPaskal.Common.pas',
  CPaskal.Lexer in '..\..\src\CPaskal.Lexer.pas',
  UTestbed in 'UTestbed.pas',
  UTestCase.Lexer in 'UTestCase.Lexer.pas',
  CPaskal.ZigBuild in '..\..\src\CPaskal.ZigBuild.pas',
  CPaskal.ZigBuild.Targets in '..\..\src\CPaskal.ZigBuild.Targets.pas',
  StdApp.Resources in '..\..\src\StdApp.Resources.pas',
  CPaskal.AST in '..\..\src\CPaskal.AST.pas',
  CPaskal.Parser in '..\..\src\CPaskal.Parser.pas';

begin
  RunTestbed();
end.
