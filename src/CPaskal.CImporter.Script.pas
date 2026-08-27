(*==============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.CImporter.Script - CImport Script Interpreter

  Loads and executes .cis (CImport Script) files. The script format is a
  dead-simple imperative language that maps 1:1 to TCImporter method calls.
  No variables, no control flow, no expressions -- just validated command
  invocations with string, integer, boolean, and enum arguments.

  Grammar:
    script    = { statement }
    statement = IDENTIFIER "(" [ arg { "," arg } ] ")" ";"
    arg       = STRING | INTEGER | IDENTIFIER

  Dependencies: CPaskal.CImporter, CPaskal.Common, StdApp.Base
==============================================================================*)

unit CPaskal.CImporter.Script;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  CPaskal.Common,
  CPaskal.CImporter;

const
  { CP_ERR_CIS_001 }
  CP_ERR_CIS_001 = 'CIS001';

type
  { TCISTokenKind }
  TCISTokenKind = (
    tkCisIdentifier,
    tkCisString,
    tkCisInteger,
    tkCisLParen,
    tkCisRParen,
    tkCisComma,
    tkCisSemicolon,
    tkCisEOF
  );

  { TCISToken }
  TCISToken = record
    Kind: TCISTokenKind;
    Text: string;
    Line: UInt64;
    Col: UInt64;
  end;

  { TCISLexer }
  TCISLexer = class
  private
    FSource: string;
    FPos: Integer;
    FLine: UInt64;
    FCol: UInt64;
    FFilename: string;
    procedure SkipWhitespaceAndComments();
    function PeekChar(): Char;
    function ReadChar(): Char;
    function IsAtEnd(): Boolean;
  public
    constructor Create(const ASource: string; const AFilename: string);
    function NextToken(): TCISToken;
  end;

  { TCPCImportScript }
  TCPCImportScript = class(TBaseObject)
  private
    FImporter: TCImporter;
    FFilename: string;
    function ResolveTarget(const AToken: TCISToken): TCPTargetPlatform;
    function ResolveBindingMode(const AToken: TCISToken): TBindingMode;
    procedure ExpectArgCount(const ACommand: string; const AArgs: TList<TCISToken>;
      const AMin: Integer; const AMax: Integer; const ACommandToken: TCISToken);
    function ArgString(const AToken: TCISToken; const ACommand: string): string;
    function ArgInteger(const AToken: TCISToken; const ACommand: string): Integer;
    function ArgBoolean(const AToken: TCISToken; const ACommand: string): Boolean;
    procedure DispatchCommand(const ACommandToken: TCISToken;
      const AArgs: TList<TCISToken>);
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer = nil); override;
    procedure ShowHelp();
    function ExecuteFile(const AFilename: string): Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  StdApp.Console;

{ TCISLexer }

constructor TCISLexer.Create(const ASource: string; const AFilename: string);
begin
  FSource := ASource;
  FFilename := AFilename;
  FPos := 1;
  FLine := 1;
  FCol := 1;
end;

function TCISLexer.PeekChar(): Char;
begin
  if FPos <= Length(FSource) then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TCISLexer.ReadChar(): Char;
begin
  Result := FSource[FPos];
  Inc(FPos);
  if Result = #10 then
  begin
    Inc(FLine);
    FCol := 1;
  end
  else
    Inc(FCol);
end;

function TCISLexer.IsAtEnd(): Boolean;
begin
  Result := FPos > Length(FSource);
end;

procedure TCISLexer.SkipWhitespaceAndComments();
var
  LC: Char;
begin
  while not IsAtEnd() do
  begin
    LC := PeekChar();

    // Whitespace
    if CharInSet(LC, [' ', #9, #13, #10]) then
    begin
      ReadChar();
      Continue;
    end;

    // Line comment: //
    if (LC = '/') and (FPos + 1 <= Length(FSource)) and (FSource[FPos + 1] = '/') then
    begin
      ReadChar(); // skip first /
      ReadChar(); // skip second /
      while (not IsAtEnd()) and (PeekChar() <> #10) do
        ReadChar();
      Continue;
    end;

    // Block comment: /* */
    if (LC = '/') and (FPos + 1 <= Length(FSource)) and (FSource[FPos + 1] = '*') then
    begin
      ReadChar(); // skip /
      ReadChar(); // skip *
      while not IsAtEnd() do
      begin
        if (PeekChar() = '*') and (FPos + 1 <= Length(FSource)) and (FSource[FPos + 1] = '/') then
        begin
          ReadChar(); // skip *
          ReadChar(); // skip /
          Break;
        end;
        ReadChar();
      end;
      Continue;
    end;

    // Not whitespace or comment
    Break;
  end;
end;

function TCISLexer.NextToken(): TCISToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LText: string;
  LC: Char;
begin
  SkipWhitespaceAndComments();

  Result.Line := FLine;
  Result.Col := FCol;

  if IsAtEnd() then
  begin
    Result.Kind := tkCisEOF;
    Result.Text := '';
    Exit;
  end;

  LC := PeekChar();

  // Single-char delimiters
  if LC = '(' then
  begin
    Result.Kind := tkCisLParen;
    Result.Text := '(';
    ReadChar();
    Exit;
  end;

  if LC = ')' then
  begin
    Result.Kind := tkCisRParen;
    Result.Text := ')';
    ReadChar();
    Exit;
  end;

  if LC = ',' then
  begin
    Result.Kind := tkCisComma;
    Result.Text := ',';
    ReadChar();
    Exit;
  end;

  if LC = ';' then
  begin
    Result.Kind := tkCisSemicolon;
    Result.Text := ';';
    ReadChar();
    Exit;
  end;

  // String literal (double-quoted)
  if LC = '"' then
  begin
    LStartLine := FLine;
    LStartCol := FCol;
    Result.Line := LStartLine;
    Result.Col := LStartCol;
    ReadChar(); // skip opening quote
    LText := '';
    while not IsAtEnd() do
    begin
      LC := PeekChar();
      if LC = '"' then
      begin
        ReadChar(); // skip quote
        // Check for escaped quote ("")
        if (not IsAtEnd()) and (PeekChar() = '"') then
        begin
          LText := LText + '"';
          ReadChar(); // skip second quote
        end
        else
          Break; // end of string
      end
      else
        LText := LText + ReadChar();
    end;
    Result.Kind := tkCisString;
    Result.Text := LText;
    Exit;
  end;

  // Integer literal (optional leading minus, then digits)
  if CharInSet(LC, ['0'..'9']) or
     ((LC = '-') and (FPos + 1 <= Length(FSource)) and CharInSet(FSource[FPos + 1], ['0'..'9'])) then
  begin
    LText := '';
    if LC = '-' then
      LText := LText + ReadChar();
    while (not IsAtEnd()) and CharInSet(PeekChar(), ['0'..'9']) do
      LText := LText + ReadChar();
    Result.Kind := tkCisInteger;
    Result.Text := LText;
    Exit;
  end;

  // Identifier
  if CharInSet(LC, ['A'..'Z', 'a'..'z', '_']) then
  begin
    LText := '';
    while (not IsAtEnd()) and CharInSet(PeekChar(), ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
      LText := LText + ReadChar();
    Result.Kind := tkCisIdentifier;
    Result.Text := LText;
    Exit;
  end;

  // Unknown character -- consume it and produce an identifier token that will
  // cause a downstream error
  Result.Kind := tkCisIdentifier;
  Result.Text := ReadChar();
end;

{ TCPCImportScript }

constructor TCPCImportScript.Create();
begin
  inherited Create();

  FImporter := TCImporter.Create();
  FFilename := '';
end;

destructor TCPCImportScript.Destroy();
begin
  FreeAndNil(FImporter);

  inherited Destroy();
end;

procedure TCPCImportScript.SetStatusCallback(const ACallback: TStatusCallback;
  const AUserData: Pointer);
begin
  inherited SetStatusCallback(ACallback, AUserData);

  FImporter.SetStatusCallback(ACallback, AUserData);
end;

procedure TCPCImportScript.ShowHelp();
begin
  TConsole.PrintLn(COLOR_BOLD + 'USAGE:');
  TConsole.PrintLn('  cpas ' + COLOR_CYAN + 'cimport <script.cis>' + COLOR_RESET);
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + 'SCRIPT COMMANDS:');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Configuration:');
  TConsole.PrintLn(COLOR_CYAN + '    SetHeader' + COLOR_RESET +
    '("filename");                         C header file to import');
  TConsole.PrintLn(COLOR_CYAN + '    SetModuleName' + COLOR_RESET +
    '("name");                          Output module name');
  TConsole.PrintLn(COLOR_CYAN + '    SetDllName' + COLOR_RESET +
    '("name");                             DLL name');
  TConsole.PrintLn(COLOR_CYAN + '    SetTargetDllName' + COLOR_RESET +
    '(target, "name");               DLL name for specific target');
  TConsole.PrintLn(COLOR_CYAN + '    SetDllPath' + COLOR_RESET +
    '("path");                             Path to DLL for preprocessing');
  TConsole.PrintLn(COLOR_CYAN + '    SetOutputPath' + COLOR_RESET +
    '("path");                          Output directory');
  TConsole.PrintLn(COLOR_CYAN + '    SetBindingMode' + COLOR_RESET +
    '(mode);                           Binding mode');
  TConsole.PrintLn(COLOR_CYAN + '    SetSavePreprocessed' + COLOR_RESET +
    '(bool);                      Save preprocessor output');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Paths & Filtering:');
  TConsole.PrintLn(COLOR_CYAN + '    AddIncludePath' + COLOR_RESET +
    '("path" [, "module"]);             C include search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddSourcePath' + COLOR_RESET +
    '("path");                           C source search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddExcludedType' + COLOR_RESET +
    '("name");                         Skip a C type');
  TConsole.PrintLn(COLOR_CYAN + '    AddExcludedFunction' + COLOR_RESET +
    '("name");                     Skip a C function');
  TConsole.PrintLn(COLOR_CYAN + '    AddFunctionRename' + COLOR_RESET +
    '("original", "newname");        Rename an imported function');
  TConsole.PrintLn(COLOR_CYAN + '    AddUsesUnit' + COLOR_RESET +
    '("unit");                             Add a uses dependency');
  TConsole.PrintLn(COLOR_CYAN + '    AddDefine' + COLOR_RESET +
    '("name" [, "value"]);                   Preprocessor #define');
  TConsole.PrintLn(COLOR_CYAN + '    AddUndefine' + COLOR_RESET +
    '("name");                             Preprocessor #undef');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Text Manipulation:');
  TConsole.PrintLn(COLOR_CYAN + '    InsertTextAfter' + COLOR_RESET +
    '("target", "text" [, occurrence]);');
  TConsole.PrintLn(COLOR_CYAN + '    InsertTextBefore' + COLOR_RESET +
    '("target", "text" [, occurrence]);');
  TConsole.PrintLn(COLOR_CYAN + '    InsertFileAfter' + COLOR_RESET +
    '("target", "file" [, occurrence]);');
  TConsole.PrintLn(COLOR_CYAN + '    InsertFileBefore' + COLOR_RESET +
    '("target", "file" [, occurrence]);');
  TConsole.PrintLn(COLOR_CYAN + '    ReplaceText' + COLOR_RESET +
    '("old", "new" [, occurrence]);');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Linking:');
  TConsole.PrintLn(COLOR_CYAN + '    AddCopyDll' + COLOR_RESET +
    '(target, "path");                     Copy DLL to output');
  TConsole.PrintLn(COLOR_CYAN + '    AddLinkLibrary' + COLOR_RESET +
    '(target, "path");                Library search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddDllNameMap' + COLOR_RESET +
    '("path", "dllname", "dllpath");    DLL name mapping');
  TConsole.PrintLn(COLOR_CYAN + '    AddDepDll' + COLOR_RESET +
    '("dllname", "dllpath");                Dependency DLL');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Execution:');
  TConsole.PrintLn(COLOR_CYAN + '    Process' + COLOR_RESET +
    '();                                      Run the import');
  TConsole.PrintLn(COLOR_CYAN + '    Clear' + COLOR_RESET +
    '();                                        Reset all settings');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + 'ENUM VALUES:');
  TConsole.PrintLn('  target:  ' + COLOR_CYAN +
    'x86_64_windows' + COLOR_RESET + ', ' + COLOR_CYAN +
    'x86_64_linux' + COLOR_RESET);
  TConsole.PrintLn('  mode:    ' + COLOR_CYAN +
    'dynamic' + COLOR_RESET);
  TConsole.PrintLn('  bool:    ' + COLOR_CYAN +
    'True' + COLOR_RESET + ', ' + COLOR_CYAN + 'False' + COLOR_RESET);
  TConsole.PrintLn('');
end;

function TCPCImportScript.ResolveTarget(const AToken: TCISToken): TCPTargetPlatform;
var
  LText: string;
begin
  LText := AToken.Text.ToLower();
  if LText = 'x86_64_windows' then
    Result := tpX86_64_Windows
  else if LText = 'x86_64_linux' then
    Result := tpX86_64_Linux
  else
  begin
    FErrors.Add(FFilename, AToken.Line, AToken.Col, esError, CP_ERR_CIS_001,
      Format('Unknown target platform: %s', [AToken.Text]));
    Result := tpX86_64_Windows;
  end;
end;

function TCPCImportScript.ResolveBindingMode(const AToken: TCISToken): TBindingMode;
var
  LText: string;
begin
  LText := AToken.Text.ToLower();
  if LText = 'dynamic' then
    Result := bmDynamic
  else
  begin
    FErrors.Add(FFilename, AToken.Line, AToken.Col, esError, CP_ERR_CIS_001,
      Format('Unknown binding mode: %s', [AToken.Text]));
    Result := bmDynamic;
  end;
end;

procedure TCPCImportScript.ExpectArgCount(const ACommand: string;
  const AArgs: TList<TCISToken>; const AMin: Integer; const AMax: Integer;
  const ACommandToken: TCISToken);
begin
  if (AArgs.Count < AMin) or (AArgs.Count > AMax) then
  begin
    if AMin = AMax then
      FErrors.Add(FFilename, ACommandToken.Line, ACommandToken.Col, esError,
        CP_ERR_CIS_001, Format('%s expects %d argument(s), got %d',
          [ACommand, AMin, AArgs.Count]))
    else
      FErrors.Add(FFilename, ACommandToken.Line, ACommandToken.Col, esError,
        CP_ERR_CIS_001, Format('%s expects %d to %d arguments, got %d',
          [ACommand, AMin, AMax, AArgs.Count]));
  end;
end;

function TCPCImportScript.ArgString(const AToken: TCISToken;
  const ACommand: string): string;
begin
  if AToken.Kind <> tkCisString then
    FErrors.Add(FFilename, AToken.Line, AToken.Col, esError, CP_ERR_CIS_001,
      Format('%s: expected string argument, got ''%s''', [ACommand, AToken.Text]));
  Result := AToken.Text;
end;

function TCPCImportScript.ArgInteger(const AToken: TCISToken;
  const ACommand: string): Integer;
begin
  if AToken.Kind <> tkCisInteger then
  begin
    FErrors.Add(FFilename, AToken.Line, AToken.Col, esError, CP_ERR_CIS_001,
      Format('%s: expected integer argument, got ''%s''', [ACommand, AToken.Text]));
    Result := 0;
    Exit;
  end;
  Result := StrToIntDef(AToken.Text, 0);
end;

function TCPCImportScript.ArgBoolean(const AToken: TCISToken;
  const ACommand: string): Boolean;
var
  LText: string;
begin
  LText := AToken.Text.ToLower();
  if LText = 'true' then
    Result := True
  else if LText = 'false' then
    Result := False
  else
  begin
    FErrors.Add(FFilename, AToken.Line, AToken.Col, esError, CP_ERR_CIS_001,
      Format('%s: expected True or False, got ''%s''', [ACommand, AToken.Text]));
    Result := False;
  end;
end;

procedure TCPCImportScript.DispatchCommand(const ACommandToken: TCISToken;
  const AArgs: TList<TCISToken>);
var
  LCmd: string;
  LResult: Boolean;
begin
  LCmd := ACommandToken.Text.ToLower();

  // -- No-arg commands --
  if LCmd = 'process' then
  begin
    ExpectArgCount('Process', AArgs, 0, 0, ACommandToken);
    if FErrors.HasErrors() then Exit;
    LResult := FImporter.Process();
    if not LResult then
      FErrors.Add(FFilename, ACommandToken.Line, ACommandToken.Col, esError,
        CP_ERR_CIS_001, Format('Process failed: %s', [FImporter.GetLastError()]));
  end
  else if LCmd = 'clear' then
  begin
    ExpectArgCount('Clear', AArgs, 0, 0, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.Clear();
  end

  // -- Single string commands --
  else if LCmd = 'setmodulename' then
  begin
    ExpectArgCount('SetModuleName', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.SetModuleName(ArgString(AArgs[0], 'SetModuleName'));
  end
  else if LCmd = 'setdllname' then
  begin
    ExpectArgCount('SetDllName', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.SetDllName(ArgString(AArgs[0], 'SetDllName'));
  end
  else if LCmd = 'settargetdllname' then
  begin
    ExpectArgCount('SetTargetDllName', AArgs, 2, 2, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.SetDllName(
      ResolveTarget(AArgs[0]),
      ArgString(AArgs[1], 'SetTargetDllName'));
  end
  else if LCmd = 'setdllpath' then
  begin
    ExpectArgCount('SetDllPath', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.SetDllPath(ArgString(AArgs[0], 'SetDllPath'));
  end
  else if LCmd = 'setoutputpath' then
  begin
    ExpectArgCount('SetOutputPath', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.SetOutputPath(ArgString(AArgs[0], 'SetOutputPath'));
  end
  else if LCmd = 'setheader' then
  begin
    ExpectArgCount('SetHeader', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.SetHeader(ArgString(AArgs[0], 'SetHeader'));
  end
  else if LCmd = 'addsourcepath' then
  begin
    ExpectArgCount('AddSourcePath', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddSourcePath(ArgString(AArgs[0], 'AddSourcePath'));
  end
  else if LCmd = 'addexcludedtype' then
  begin
    ExpectArgCount('AddExcludedType', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddExcludedType(ArgString(AArgs[0], 'AddExcludedType'));
  end
  else if LCmd = 'addexcludedfunction' then
  begin
    ExpectArgCount('AddExcludedFunction', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddExcludedFunction(ArgString(AArgs[0], 'AddExcludedFunction'));
  end
  else if LCmd = 'addusesunit' then
  begin
    ExpectArgCount('AddUsesUnit', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddUsesUnit(ArgString(AArgs[0], 'AddUsesUnit'));
  end
  else if LCmd = 'addundefine' then
  begin
    ExpectArgCount('AddUndefine', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddUndefine(ArgString(AArgs[0], 'AddUndefine'));
  end

  // -- Boolean command --
  else if LCmd = 'setsavepreprocessed' then
  begin
    ExpectArgCount('SetSavePreprocessed', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.SetSavePreprocessed(ArgBoolean(AArgs[0], 'SetSavePreprocessed'));
  end

  // -- Binding mode command --
  else if LCmd = 'setbindingmode' then
  begin
    ExpectArgCount('SetBindingMode', AArgs, 1, 1, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.SetBindingMode(ResolveBindingMode(AArgs[0]));
  end

  // -- Optional second string arg --
  else if LCmd = 'addincludepath' then
  begin
    ExpectArgCount('AddIncludePath', AArgs, 1, 2, ACommandToken);
    if FErrors.HasErrors() then Exit;
    if AArgs.Count = 2 then
      FImporter.AddIncludePath(
        ArgString(AArgs[0], 'AddIncludePath'),
        ArgString(AArgs[1], 'AddIncludePath'))
    else
      FImporter.AddIncludePath(ArgString(AArgs[0], 'AddIncludePath'));
  end
  else if LCmd = 'adddefine' then
  begin
    ExpectArgCount('AddDefine', AArgs, 1, 2, ACommandToken);
    if FErrors.HasErrors() then Exit;
    if AArgs.Count = 2 then
      FImporter.AddDefine(
        ArgString(AArgs[0], 'AddDefine'),
        ArgString(AArgs[1], 'AddDefine'))
    else
      FImporter.AddDefine(ArgString(AArgs[0], 'AddDefine'));
  end

  // -- Two string commands --
  else if LCmd = 'addfunctionrename' then
  begin
    ExpectArgCount('AddFunctionRename', AArgs, 2, 2, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddFunctionRename(
      ArgString(AArgs[0], 'AddFunctionRename'),
      ArgString(AArgs[1], 'AddFunctionRename'));
  end
  else if LCmd = 'adddepdll' then
  begin
    ExpectArgCount('AddDepDll', AArgs, 2, 2, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddDepDll(
      ArgString(AArgs[0], 'AddDepDll'),
      ArgString(AArgs[1], 'AddDepDll'));
  end

  // -- Three string commands --
  else if LCmd = 'adddllnamemap' then
  begin
    ExpectArgCount('AddDllNameMap', AArgs, 3, 3, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddDllNameMap(
      ArgString(AArgs[0], 'AddDllNameMap'),
      ArgString(AArgs[1], 'AddDllNameMap'),
      ArgString(AArgs[2], 'AddDllNameMap'));
  end

  // -- Enum + string commands --
  else if LCmd = 'addcopydll' then
  begin
    ExpectArgCount('AddCopyDll', AArgs, 2, 2, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddCopyDll(
      ResolveTarget(AArgs[0]),
      ArgString(AArgs[1], 'AddCopyDll'));
  end
  else if LCmd = 'addlinklibrary' then
  begin
    ExpectArgCount('AddLinkLibrary', AArgs, 2, 2, ACommandToken);
    if FErrors.HasErrors() then Exit;
    FImporter.AddLinkLibrary(
      ResolveTarget(AArgs[0]),
      ArgString(AArgs[1], 'AddLinkLibrary'));
  end

  // -- String, String, optional Integer commands --
  else if LCmd = 'inserttextafter' then
  begin
    ExpectArgCount('InsertTextAfter', AArgs, 2, 3, ACommandToken);
    if FErrors.HasErrors() then Exit;
    if AArgs.Count = 3 then
      FImporter.InsertTextAfter(
        ArgString(AArgs[0], 'InsertTextAfter'),
        ArgString(AArgs[1], 'InsertTextAfter'),
        ArgInteger(AArgs[2], 'InsertTextAfter'))
    else
      FImporter.InsertTextAfter(
        ArgString(AArgs[0], 'InsertTextAfter'),
        ArgString(AArgs[1], 'InsertTextAfter'));
  end
  else if LCmd = 'insertfileafter' then
  begin
    ExpectArgCount('InsertFileAfter', AArgs, 2, 3, ACommandToken);
    if FErrors.HasErrors() then Exit;
    if AArgs.Count = 3 then
      FImporter.InsertFileAfter(
        ArgString(AArgs[0], 'InsertFileAfter'),
        ArgString(AArgs[1], 'InsertFileAfter'),
        ArgInteger(AArgs[2], 'InsertFileAfter'))
    else
      FImporter.InsertFileAfter(
        ArgString(AArgs[0], 'InsertFileAfter'),
        ArgString(AArgs[1], 'InsertFileAfter'));
  end
  else if LCmd = 'inserttextbefore' then
  begin
    ExpectArgCount('InsertTextBefore', AArgs, 2, 3, ACommandToken);
    if FErrors.HasErrors() then Exit;
    if AArgs.Count = 3 then
      FImporter.InsertTextBefore(
        ArgString(AArgs[0], 'InsertTextBefore'),
        ArgString(AArgs[1], 'InsertTextBefore'),
        ArgInteger(AArgs[2], 'InsertTextBefore'))
    else
      FImporter.InsertTextBefore(
        ArgString(AArgs[0], 'InsertTextBefore'),
        ArgString(AArgs[1], 'InsertTextBefore'));
  end
  else if LCmd = 'insertfilebefore' then
  begin
    ExpectArgCount('InsertFileBefore', AArgs, 2, 3, ACommandToken);
    if FErrors.HasErrors() then Exit;
    if AArgs.Count = 3 then
      FImporter.InsertFileBefore(
        ArgString(AArgs[0], 'InsertFileBefore'),
        ArgString(AArgs[1], 'InsertFileBefore'),
        ArgInteger(AArgs[2], 'InsertFileBefore'))
    else
      FImporter.InsertFileBefore(
        ArgString(AArgs[0], 'InsertFileBefore'),
        ArgString(AArgs[1], 'InsertFileBefore'));
  end
  else if LCmd = 'replacetext' then
  begin
    ExpectArgCount('ReplaceText', AArgs, 2, 3, ACommandToken);
    if FErrors.HasErrors() then Exit;
    if AArgs.Count = 3 then
      FImporter.ReplaceText(
        ArgString(AArgs[0], 'ReplaceText'),
        ArgString(AArgs[1], 'ReplaceText'),
        ArgInteger(AArgs[2], 'ReplaceText'))
    else
      FImporter.ReplaceText(
        ArgString(AArgs[0], 'ReplaceText'),
        ArgString(AArgs[1], 'ReplaceText'));
  end

  // -- Unknown command --
  else
  begin
    FErrors.Add(FFilename, ACommandToken.Line, ACommandToken.Col, esError,
      CP_ERR_CIS_001, Format('Unknown command: %s', [ACommandToken.Text]));
  end;
end;

function TCPCImportScript.ExecuteFile(const AFilename: string): Boolean;
var
  LSource: string;
  LLexer: TCISLexer;
  LToken: TCISToken;
  LCommandToken: TCISToken;
  LArgs: TList<TCISToken>;
  LArgToken: TCISToken;
begin
  FFilename := AFilename;

  // Read the script file
  if not TFile.Exists(AFilename) then
  begin
    FErrors.Add(AFilename, 1, 1, esError, CP_ERR_CIS_001,
      Format('Script file not found: %s', [AFilename]));
    Result := False;
    Exit;
  end;

  try
    LSource := TFile.ReadAllText(AFilename, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      FErrors.Add(AFilename, 1, 1, esError, CP_ERR_CIS_001,
        Format('Failed to read script file: %s', [E.Message]));
      Result := False;
      Exit;
    end;
  end;

  LLexer := TCISLexer.Create(LSource, AFilename);
  try
    LArgs := TList<TCISToken>.Create();
    try
      while True do
      begin
        // Read command name
        LToken := LLexer.NextToken();
        if LToken.Kind = tkCisEOF then
          Break;

        // Expect identifier (command name)
        if LToken.Kind <> tkCisIdentifier then
        begin
          FErrors.Add(FFilename, LToken.Line, LToken.Col, esError,
            CP_ERR_CIS_001, Format('Expected command name, got ''%s''', [LToken.Text]));
          Break;
        end;
        LCommandToken := LToken;

        // Expect '('
        LToken := LLexer.NextToken();
        if LToken.Kind <> tkCisLParen then
        begin
          FErrors.Add(FFilename, LToken.Line, LToken.Col, esError,
            CP_ERR_CIS_001, Format('Expected ''('', got ''%s''', [LToken.Text]));
          Break;
        end;

        // Collect args until ')'
        LArgs.Clear();
        LToken := LLexer.NextToken();
        if LToken.Kind <> tkCisRParen then
        begin
          // First arg
          if not (LToken.Kind in [tkCisIdentifier, tkCisString, tkCisInteger]) then
          begin
            FErrors.Add(FFilename, LToken.Line, LToken.Col, esError,
              CP_ERR_CIS_001, Format('Expected argument, got ''%s''', [LToken.Text]));
            Break;
          end;
          LArgs.Add(LToken);

          // Additional args separated by commas
          while True do
          begin
            LToken := LLexer.NextToken();
            if LToken.Kind = tkCisRParen then
              Break;
            if LToken.Kind <> tkCisComma then
            begin
              FErrors.Add(FFilename, LToken.Line, LToken.Col, esError,
                CP_ERR_CIS_001, Format('Expected '','' or '')'', got ''%s''', [LToken.Text]));
              Break;
            end;

            // Read next arg after comma
            LArgToken := LLexer.NextToken();
            if not (LArgToken.Kind in [tkCisIdentifier, tkCisString, tkCisInteger]) then
            begin
              FErrors.Add(FFilename, LArgToken.Line, LArgToken.Col, esError,
                CP_ERR_CIS_001, Format('Expected argument after '','', got ''%s''', [LArgToken.Text]));
              Break;
            end;
            LArgs.Add(LArgToken);
          end;

          if FErrors.HasErrors() then
            Break;
        end;

        // Expect ';'
        LToken := LLexer.NextToken();
        if LToken.Kind <> tkCisSemicolon then
        begin
          FErrors.Add(FFilename, LToken.Line, LToken.Col, esError,
            CP_ERR_CIS_001, Format('Expected '';'', got ''%s''', [LToken.Text]));
          Break;
        end;

        // Dispatch the validated command
        DispatchCommand(LCommandToken, LArgs);

        // Bail on errors
        if FErrors.HasErrors() then
          Break;
      end;
    finally
      LArgs.Free();
    end;
  finally
    LLexer.Free();
  end;

  Result := not FErrors.HasErrors();
end;

end.
