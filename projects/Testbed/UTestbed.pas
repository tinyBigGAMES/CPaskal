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
  StdApp.Utils,
  StdApp.Console,
  StdApp.Console.Menu,
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

procedure RunTestbed();
begin
  try
    Menu();
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
