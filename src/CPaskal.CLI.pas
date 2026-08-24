{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.CLI - Command-line front-end

  Parses command-line arguments, configures the compiler, runs the full
  pipeline. Single entry point: TCPCLI.Execute().

  Dependencies: CPaskal.Compiler, CPaskal.ZigBuild, StdApp.Console
===============================================================================}

unit CPaskal.CLI;

interface

uses
  System.IOUtils,
  StdApp.Console,
  CPaskal.Compiler;

const
  { CP_VERSION }
  CP_VERSION = '0.1.0';

type

  { TCPCLI }
  TCPCLI = class
  private
    FCompiler: TCPCompiler;
    FSourceFile: string;
    FAutoRun: Boolean;
    FTarget: string;
    FOutputPath: string;
    FSubsystem: string;
    FOptLevel: string;
    procedure ShowBanner();
    procedure ShowHelp();
    procedure ShowErrors();
    procedure SetupCallbacks();
    function ParseArgs(): Boolean;
    procedure DoCompile();
  public
    constructor Create();
    destructor Destroy(); override;
    procedure Execute();
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  StdApp.Base,
  StdApp.Utils,
  CPaskal.Common,
  CPaskal.ZigBuild;

{ TCPCLI }

constructor TCPCLI.Create();
begin
  inherited Create();

  FCompiler := TCPCompiler.Create();
  FSourceFile := '';
  FAutoRun := False;
  FTarget := '';
  FOutputPath := '';
  FSubsystem := '';
  FOptLevel := '';
end;

destructor TCPCLI.Destroy();
begin
  FreeAndNil(FCompiler);

  inherited Destroy();
end;

procedure TCPCLI.ShowBanner();
var
  LVerInfo: TVersionInfo;
begin
  LVerInfo := Default(TVersionInfo);

  (*
  LVerInfo.ProductName := 'CPaskal™ CLI';
  LVerInfo.VersionString := CP_VERSION;
  LVerInfo.Copyright := 'Copyright © 2026-present tinyBigGAMES™ LLC';
  LVerInfo.URL := 'https://cpaskal.org';
  *)

  TUtils.GetVersionInfo(LVerInfo);

  TConsole.PrintLn(COLOR_WHITE + COLOR_BOLD +
    Format('%s v%s', [LVerInfo.ProductName, LVerInfo.VersionString]));
  TConsole.PrintLn(COLOR_WHITE +
    Format('%s, All Rights Reserved.', [LVerInfo.Copyright]));
  TConsole.PrintLn(COLOR_YELLOW + LVerInfo.URL);

  TConsole.PrintLn('');
end;

procedure TCPCLI.ShowHelp();
var
  LExeName: string;
begin
  LExeName := TPath.GetFileNameWithoutExtension(ParamStr(0));

  TConsole.PrintLn(COLOR_BOLD + 'USAGE:');
  TConsole.PrintLn('  ' + LExeName + ' ' + COLOR_CYAN +
    '<source>' + COLOR_RESET + ' [OPTIONS]');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'REQUIRED:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '<source>' + COLOR_RESET +
    '                  CPaskal source file (.cpas)');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'OPTIONS:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-r, --run              ' + COLOR_RESET +
    '  Run the compiled executable after building');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-t, --target    <target>' + COLOR_RESET +
    '  Set compilation target (e.g. x86_64-windows-gnu)');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-o, --output    <path>  ' + COLOR_RESET +
    '  Set output directory');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-sub, --subsystem <type>' + COLOR_RESET +
    '  Set subsystem: console (default), gui');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-opt, --optimize <level>' + COLOR_RESET +
    '  Set optimize level: debug (default), release-safe,');
  TConsole.PrintLn('  ' + COLOR_CYAN + '                        ' + COLOR_RESET +
    '  release-fast, release-small');
  TConsole.PrintLn('  ' + COLOR_CYAN + '-h, --help             ' + COLOR_RESET +
    '  Display this help message');
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'EXAMPLES:');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -r');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -r -t x86_64-linux-gnu');
  TConsole.PrintLn('  ' + COLOR_CYAN +
    LExeName + ' hello -r -opt release-fast');
  TConsole.PrintLn('');
end;

procedure TCPCLI.ShowErrors();
begin
  FCompiler.PrintErrors();
end;

procedure TCPCLI.SetupCallbacks();
begin
  FCompiler.SetOutputCallback(
    procedure(const ALine: string; const AUserData: Pointer)
    begin
      TConsole.Print(ALine);
    end, nil);

  FCompiler.SetStatusCallback(
    procedure(const AText: string; const AUserData: Pointer)
    begin
      TConsole.PrintLn(AText);
    end, nil);
end;

function TCPCLI.ParseArgs(): Boolean;
var
  LI: Integer;
  LFlag: string;
begin
  Result := True;

  if ParamCount() = 0 then
  begin
    ShowHelp();
    Result := False;
    Exit;
  end;

  LI := 1;
  while LI <= ParamCount() do
  begin
    LFlag := ParamStr(LI).Trim();

    if (LFlag = '-h') or (LFlag = '--help') then
    begin
      ShowHelp();
      Result := False;
      Exit;
    end
    else if (LFlag = '-r') or (LFlag = '--run') then
    begin
      FAutoRun := True;
    end
    else if (LFlag = '-t') or (LFlag = '--target') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires a target argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FTarget := ParamStr(LI).Trim();
    end
    else if (LFlag = '-o') or (LFlag = '--output') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires a path argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FOutputPath := ParamStr(LI).Trim();
    end
    else if (LFlag = '-sub') or (LFlag = '--subsystem') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires a subsystem argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FSubsystem := ParamStr(LI).Trim();
    end
    else if (LFlag = '-opt') or (LFlag = '--optimize') then
    begin
      Inc(LI);
      if LI > ParamCount() then
      begin
        TConsole.PrintLn(COLOR_RED + 'Error: ' + LFlag +
          ' requires an optimize level argument');
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
      FOptLevel := ParamStr(LI).Trim();
    end
    else if LFlag.StartsWith('-') then
    begin
      TConsole.PrintLn(COLOR_RED + 'Error: Unknown flag: ' +
        COLOR_YELLOW + LFlag);
      TConsole.PrintLn('');
      TConsole.PrintLn('Run ' + COLOR_CYAN +
        TPath.GetFileNameWithoutExtension(ParamStr(0)) + ' -h' +
        COLOR_RESET + ' to see available options');
      TConsole.PrintLn('');
      ExitCode := 2;
      Result := False;
      Exit;
    end
    else
    begin
      // Positional argument: source file
      if FSourceFile = '' then
        FSourceFile := LFlag
      else
      begin
        TConsole.PrintLn(COLOR_RED +
          'Error: Unexpected argument: ' + COLOR_YELLOW + LFlag);
        TConsole.PrintLn('');
        ExitCode := 2;
        Result := False;
        Exit;
      end;
    end;

    Inc(LI);
  end;

  // Validate: source file is required
  if FSourceFile = '' then
  begin
    TConsole.PrintLn(COLOR_RED +
      'Error: Source file is required');
    TConsole.PrintLn('');
    TConsole.PrintLn('Run ' + COLOR_CYAN +
      TPath.GetFileNameWithoutExtension(ParamStr(0)) + ' -h' +
      COLOR_RESET + ' to see available options');
    TConsole.PrintLn('');
    ExitCode := 2;
    Result := False;
    Exit;
  end;

  // Normalize source file extension
  FSourceFile := TPath.ChangeExtension(FSourceFile, CP_SRC_EXT);

  // Validate: source file must exist
  if not TFile.Exists(FSourceFile) then
  begin
    TConsole.PrintLn(COLOR_RED +
      'Error: Source file not found: ' + COLOR_YELLOW + FSourceFile);
    TConsole.PrintLn('');
    ExitCode := 2;
    Result := False;
    Exit;
  end;
end;

procedure TCPCLI.DoCompile();
var
  LOutputPath: string;
begin
  SetupCallbacks();

  // Configure target
  if FTarget <> '' then
    FCompiler.SetTarget(FTarget);

  // Configure subsystem
  if FSubsystem <> '' then
  begin
    if SameText(FSubsystem, 'gui') then
      FCompiler.SetSubsystem(stGUI)
    else
      FCompiler.SetSubsystem(stConsole);
  end;

  // Configure optimize level
  if FOptLevel <> '' then
  begin
    if SameText(FOptLevel, 'release-safe') then
      FCompiler.SetOptimizeLevel(olReleaseSafe)
    else if SameText(FOptLevel, 'release-fast') then
      FCompiler.SetOptimizeLevel(olReleaseFast)
    else if SameText(FOptLevel, 'release-small') then
      FCompiler.SetOptimizeLevel(olReleaseSmall)
    else
      FCompiler.SetOptimizeLevel(olDebug);
  end;

  // Determine output path
  if FOutputPath <> '' then
    LOutputPath := TUtils.ResolvePath(FOutputPath)
  else
    LOutputPath := TUtils.ResolvePath('$P:output');

  // Compile
  FCompiler.Compile(FSourceFile, LOutputPath, FAutoRun);

  // Display errors
  ShowErrors();

  if FCompiler.GetErrors().HasErrors() then
  begin
    TConsole.PrintLn(COLOR_RED + 'Failed.');
    ExitCode := 1;
  end
  else
    ExitCode := FCompiler.GetLastExitCode();
end;

procedure TCPCLI.Execute();
begin
  ShowBanner();

  if not ParseArgs() then
    Exit;

  try
    DoCompile();
  except
    on E: Exception do
    begin
      TConsole.PrintLn('');
      TConsole.PrintLn(COLOR_RED + COLOR_BOLD + 'Fatal Error: ' +
        E.Message + COLOR_RESET);
      TConsole.PrintLn('');
      ExitCode := 1;
    end;
  end;
end;

end.
