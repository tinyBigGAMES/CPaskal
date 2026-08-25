{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  UTestbed - Test harness entry point

  Wires up all test case classes into the console menu system and provides
  the RunTestbed entry point called from the .dpr.

  Dependencies: StdApp.Console.Menu, UTestCase.Lexer
===============================================================================}

unit UTestbed;

interface

procedure RunTestbed();

implementation

uses
  System.SysUtils,
  System.IOUtils,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Console,
  StdApp.Console.Menu,
  CPaskal.Common,
  CPaskal.Compiler,
  CPaskal.ZigBuild,
  UTestCase.Lexer;

procedure RegisterMenuItems(const AMenu: TConsoleMenu);
begin
  AMenu.SetCategory('Lexer');
  AMenu.AddTestCase(TCPLexerTests);
  AMenu.ClearCategory();
end;

procedure Menu();
var
  LMenu: TConsoleMenu;
begin
  LMenu := TConsoleMenu.Create();
  try
    LMenu.Title('CPaskal Testbed');
    RegisterMenuItems(LMenu);
    LMenu.Run();
  finally
    LMenu.Free();
  end;
end;

procedure Test01();
var
  LCompiler: TCPCompiler;
  LSourceFile: string;
  LOutputPath: string;
begin
  LCompiler := TCPCompiler.Create();
  try
    LCompiler.SetStatusCallback(
      procedure(const AText: string; const AUserData: Pointer)
      begin
        TConsole.PrintLn(AText);
      end, nil);

    LCompiler.SetOutputCallback(
      procedure(const ALine: string; const AUserData: Pointer)
      begin
        TConsole.Print(ALine);
      end, nil);

    LSourceFile := TUtils.ResolvePath('$P:res\tests\bnf_compliance');
    LOutputPath := TUtils.ResolvePath('$P:output');

    TConsole.PrintLn('Source: %s', [LSourceFile]);
    TConsole.PrintLn('Output: %s', [LOutputPath]);
    TConsole.PrintLn('');

    LCompiler.Compile(LSourceFile, LOutputPath, True);

    LCompiler.PrintErrors();

    if LCompiler.GetErrors().HasErrors() then
      TConsole.PrintLn(COLOR_RED + 'FAILED.')
    else
      TConsole.PrintLn(COLOR_GREEN + 'OK.');
  finally
    LCompiler.Free();
  end;

  TConsole.Pause();
end;

procedure RunTestbed();
begin
  try
    Test01();
    //Menu();
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + 'EXCEPTION: %s', [E.Message]);

      if TUtils.RunFromIDE() then
        TConsole.Pause();
    end;
  end;
end;

end.
