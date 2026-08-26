{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.Lexer - Tokenizer with dynamic keyword registration

  Tokenizes CPaskal source into a rich token stream. Keywords, primitives,
  and their metadata (category, C++23 type mapping) are registered dynamically
  via AddKeyword. The parser navigates the token stream through the lexer's
  API -- it never receives the internal token list.

  Dependencies: CPaskal.Common, StdApp.Base, StdApp.Resources
===============================================================================}

unit CPaskal.Lexer;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Rtti,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  CPaskal.Common;

const

  { Lexer error codes }
  CP_ERR_LEX_001 = 'LEX001';  // Unterminated string literal
  CP_ERR_LEX_002 = 'LEX002';  // Unterminated block comment
  CP_ERR_LEX_003 = 'LEX003';  // Invalid character
  CP_ERR_LEX_004 = 'LEX004';  // Invalid hex literal
  CP_ERR_LEX_005 = 'LEX005';  // Invalid escape sequence
  CP_ERR_LEX_006 = 'LEX006';  // Invalid numeric literal
  CP_ERR_LEX_007 = 'LEX007';  // Unexpected end of file
  CP_ERR_LEX_008 = 'LEX008';  // Expected token
  CP_ERR_LEX_009 = 'LEX009';  // File not found
  CP_ERR_LEX_010 = 'LEX010';  // File read error

type

  { TCPLexer }
  TCPLexer = class(TBaseObject)
  private
    // Source state
    FSource: string;
    FFilename: string;
    FPos: UInt64;
    FLine: UInt64;
    FCol: UInt64;

    // Token storage and navigation
    FTokens: TList<TCPToken>;
    FTokenIndex: UInt64;

    // Registration dictionaries
    FKeywords: TDictionary<string, TCPTokenKind>;
    FCategories: TDictionary<TCPTokenKind, TCPTokenCategory>;
    FCppTypes: TDictionary<TCPTokenKind, string>;

    // Source traversal
    function CurrentChar(): Char;
    function PeekChar(): Char;
    function PeekCharAt(const AOffset: Int64): Char;
    procedure Advance();
    function IsAtSourceEnd(): Boolean;
    function MakeLocation(const AStartLine: UInt64; const AStartCol: UInt64): TSourceRange;

    // Trivia and comment scanning
    function DoCollectTrivia(): string;
    procedure DoScanLineComment(var ATrivia: string);
    procedure DoScanBlockComment(var ATrivia: string);

    // Token scanning
    function DoScanToken(const ATrivia: string): TCPToken;
    function DoScanIdentifier(): TCPToken;
    function DoScanNumber(): TCPToken;
    function DoScanStringLiteral(): TCPToken;
    function DoScanWStringLiteral(): TCPToken;
    function DoScanDirective(): TCPToken;
    function DoScanOperator(): TCPToken;
    procedure DoScanRawBlock();
    function DoProcessEscapeSeq(): Char;

    // Internal registration
    procedure RegisterKeywords();
    procedure RegisterPrimitives();
    procedure RegisterCategories();

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Tokenization
    function TokenizeString(const ASource: string; const AFilename: string): Boolean;
    function TokenizeFile(const AFilename: string): Boolean;

    // Keyword/type registration
    procedure AddKeyword(const AText: string; const AKind: TCPTokenKind;
      const ACategory: TCPTokenCategory); overload;
    procedure AddKeyword(const AText: string; const AKind: TCPTokenKind;
      const ACategory: TCPTokenCategory; const ACppType: string); overload;

    // Navigation API (used by parser)
    function CurrentToken(): TCPToken;
    function NextToken(): TCPToken;
    function PeekToken(): TCPToken;
    function PeekAt(const AOffset: Int64): TCPToken;
    function Match(const AKind: TCPTokenKind): Boolean;
    function Expect(const AKind: TCPTokenKind): TCPToken;
    function IsAtEnd(): Boolean;

    // Query helpers
    function IsDataType(const AKind: TCPTokenKind): Boolean;
    function IsOperator(const AKind: TCPTokenKind): Boolean;
    function GetCppType(const AKind: TCPTokenKind): string;
    function GetCategory(const AKind: TCPTokenKind): TCPTokenCategory;
    function TokenCount(): UInt64;

    // Properties
    property SourceText: string read FSource;

    // Source reconstruction
    function ToSource(): string;
  end;

implementation

{ TCPaskalLexer }

constructor TCPLexer.Create();
begin
  inherited;

  FTokens := TList<TCPToken>.Create();
  FKeywords := TDictionary<string, TCPTokenKind>.Create();
  FCategories := TDictionary<TCPTokenKind, TCPTokenCategory>.Create();
  FCppTypes := TDictionary<TCPTokenKind, string>.Create();

  FTokenIndex := 0;
  FPos := 1;
  FLine := 1;
  FCol := 1;

  RegisterKeywords();
  RegisterPrimitives();
  RegisterCategories();
end;

destructor TCPLexer.Destroy();
begin
  FCppTypes.Free();
  FCategories.Free();
  FKeywords.Free();
  FTokens.Free();

  inherited;
end;

// -- Registration -----------------------------------------------------------

procedure TCPLexer.AddKeyword(const AText: string; const AKind: TCPTokenKind;
  const ACategory: TCPTokenCategory);
begin
  FKeywords.AddOrSetValue(AText.ToLower(), AKind);
  FCategories.AddOrSetValue(AKind, ACategory);
end;

procedure TCPLexer.AddKeyword(const AText: string; const AKind: TCPTokenKind;
  const ACategory: TCPTokenCategory; const ACppType: string);
begin
  AddKeyword(AText, AKind, ACategory);
  FCppTypes.AddOrSetValue(AKind, ACppType);
end;

procedure TCPLexer.RegisterKeywords();
begin
  // BNF Section 2 - Reserved Words (except pointer, registered in primitives)
  AddKeyword('address',      tkAddress,      tcKeyword);
  AddKeyword('align',        tkAlign,        tcKeyword);
  AddKeyword('and',          tkAnd,          tcKeyword);
  AddKeyword('array',        tkArray,        tcKeyword);
  AddKeyword('assert',       tkAssert,       tcKeyword);
  AddKeyword('asserteq',     tkAssertEq,     tcKeyword);
  AddKeyword('asserteqf',    tkAssertEqF,    tcKeyword);
  AddKeyword('assertfalse',  tkAssertFalse,  tcKeyword);
  AddKeyword('assertfail',   tkAssertFail,   tcKeyword);
  AddKeyword('assertnil',    tkAssertNil,    tcKeyword);
  AddKeyword('assertnotnil', tkAssertNotNil, tcKeyword);
  AddKeyword('asserttrue',   tkAssertTrue,   tcKeyword);
  AddKeyword('begin',        tkBegin,        tcKeyword);
  AddKeyword('break',        tkBreak,        tcKeyword);
  AddKeyword('choices',      tkChoices,      tcKeyword);
  AddKeyword('clink',        tkCLink,        tcKeyword);
  AddKeyword('const',        tkConst,        tcKeyword);
  AddKeyword('continue',     tkContinue,     tcKeyword);
  AddKeyword('cpp',          tkCpp,          tcKeyword);
  AddKeyword('cppend',       tkCppEnd,       tcKeyword);
  AddKeyword('cpplink',      tkCppLink,      tcKeyword);
  AddKeyword('cppstart',     tkCppStart,     tcKeyword);
  AddKeyword('create',       tkCreate,       tcKeyword);
  AddKeyword('cstr',         tkCStr,         tcKeyword);
  AddKeyword('destroy',      tkDestroy,      tcKeyword);
  AddKeyword('div',          tkDiv,          tcKeyword);
  AddKeyword('do',           tkDo,           tcKeyword);
  AddKeyword('downto',       tkDownTo,       tcKeyword);
  AddKeyword('else',         tkElse,         tcKeyword);
  AddKeyword('end',          tkEnd,          tcKeyword);
  AddKeyword('except',       tkExcept,       tcKeyword);
  AddKeyword('exccode',      tkExcCode,      tcKeyword);
  AddKeyword('excmsg',       tkExcMsg,       tcKeyword);
  AddKeyword('external',     tkExternal,     tcKeyword);

  AddKeyword('false',        tkFalse,        tcKeyword);
  AddKeyword('finalize',     tkFinalize,     tcKeyword);
  AddKeyword('finally',      tkFinally,      tcKeyword);
  AddKeyword('for',          tkFor,          tcKeyword);
  AddKeyword('forward',      tkForward,      tcKeyword);
  AddKeyword('freemem',      tkFreeMem,      tcKeyword);
  AddKeyword('getmem',       tkGetMem,       tcKeyword);
  AddKeyword('guard',        tkGuard,        tcKeyword);
  AddKeyword('if',           tkIf,           tcKeyword);
  AddKeyword('import',       tkImport,       tcKeyword);
  AddKeyword('in',           tkIn,           tcKeyword);
  AddKeyword('initialize',   tkInitialize,   tcKeyword);
  AddKeyword('is',           tkIs,           tcKeyword);
  AddKeyword('len',          tkLen,          tcKeyword);
  AddKeyword('match',        tkMatch,        tcKeyword);
  AddKeyword('mod',          tkMod,          tcKeyword);
  AddKeyword('module',       tkModule,       tcKeyword);
  AddKeyword('nil',          tkNil,          tcKeyword);
  AddKeyword('not',          tkNot,          tcKeyword);
  AddKeyword('of',           tkOf,           tcKeyword);
  AddKeyword('or',           tkOr,           tcKeyword);
  AddKeyword('overlay',      tkOverlay,      tcKeyword);
  AddKeyword('packed',       tkPacked,       tcKeyword);
  AddKeyword('paramcount',   tkParamCount,   tcKeyword);
  AddKeyword('paramstr',     tkParamStr,     tcKeyword);
  AddKeyword('print',        tkPrint,        tcKeyword);
  AddKeyword('println',      tkPrintLn,      tcKeyword);
  AddKeyword('public',       tkPublic,       tcKeyword);
  AddKeyword('record',       tkRecord,       tcKeyword);
  AddKeyword('repeat',       tkRepeat,       tcKeyword);
  AddKeyword('resizemem',    tkResizeMem,    tcKeyword);
  AddKeyword('return',       tkReturn,       tcKeyword);
  AddKeyword('routine',      tkRoutine,      tcKeyword);
  AddKeyword('set',          tkSet,          tcKeyword);
  AddKeyword('setlength',    tkSetLength,    tcKeyword);
  AddKeyword('shl',          tkShl,          tcKeyword);
  AddKeyword('shr',          tkShr,          tcKeyword);
  AddKeyword('size',         tkSize,         tcKeyword);
  AddKeyword('test',         tkTest,         tcKeyword);
  AddKeyword('then',         tkThen,         tcKeyword);
  AddKeyword('throw',        tkThrow,        tcKeyword);
  AddKeyword('throwcode',    tkThrowCode,    tcKeyword);
  AddKeyword('to',           tkTo,           tcKeyword);
  AddKeyword('true',         tkTrue,         tcKeyword);
  AddKeyword('type',         tkType,         tcKeyword);
  AddKeyword('until',        tkUntil,        tcKeyword);
  AddKeyword('utf8',         tkUtf8,         tcKeyword);
  AddKeyword('var',          tkVar,          tcKeyword);
  AddKeyword('varargs',      tkVarArgs,      tcKeyword);
  AddKeyword('while',        tkWhile,        tcKeyword);
  AddKeyword('wstr',         tkWStr,         tcKeyword);
  AddKeyword('xor',          tkXor,          tcKeyword);
end;

procedure TCPLexer.RegisterPrimitives();
begin
  // BNF Section 3 - Built-in Types with C++23 mappings
  AddKeyword('int8',     tkInt8,     tcPrimitive, 'int8_t');
  AddKeyword('int16',    tkInt16,    tcPrimitive, 'int16_t');
  AddKeyword('int32',    tkInt32,    tcPrimitive, 'int32_t');
  AddKeyword('int64',    tkInt64,    tcPrimitive, 'int64_t');
  AddKeyword('uint8',    tkUInt8,    tcPrimitive, 'uint8_t');
  AddKeyword('uint16',   tkUInt16,   tcPrimitive, 'uint16_t');
  AddKeyword('uint32',   tkUInt32,   tcPrimitive, 'uint32_t');
  AddKeyword('uint64',   tkUInt64,   tcPrimitive, 'uint64_t');
  AddKeyword('float32',  tkFloat32,  tcPrimitive, 'float');
  AddKeyword('float64',  tkFloat64,  tcPrimitive, 'double');
  AddKeyword('boolean',  tkBoolean,  tcPrimitive, 'bool');
  AddKeyword('char',     tkChar,     tcPrimitive, 'char');
  AddKeyword('wchar',    tkWChar,    tcPrimitive, 'char16_t');
  AddKeyword('string',   tkString,   tcPrimitive, 'std::string');
  AddKeyword('wstring',  tkWString,  tcPrimitive, 'std::wstring');
  AddKeyword('pointer',  tkPointer,  tcPrimitive, 'void*');
end;

procedure TCPLexer.RegisterCategories();
begin
  // Register categories for non-keyword token kinds (operators, delimiters, etc.)
  // Keywords and primitives are already registered via AddKeyword.

  // Operators
  FCategories.AddOrSetValue(tkPlus,         tcOperator);
  FCategories.AddOrSetValue(tkMinus,        tcOperator);
  FCategories.AddOrSetValue(tkStar,         tcOperator);
  FCategories.AddOrSetValue(tkSlash,        tcOperator);
  FCategories.AddOrSetValue(tkEqual,        tcOperator);
  FCategories.AddOrSetValue(tkNotEqual,     tcOperator);
  FCategories.AddOrSetValue(tkLess,         tcOperator);
  FCategories.AddOrSetValue(tkGreater,      tcOperator);
  FCategories.AddOrSetValue(tkLessEqual,    tcOperator);
  FCategories.AddOrSetValue(tkGreaterEqual, tcOperator);
  FCategories.AddOrSetValue(tkAssign,       tcOperator);
  FCategories.AddOrSetValue(tkPlusAssign,   tcOperator);
  FCategories.AddOrSetValue(tkMinusAssign,  tcOperator);
  FCategories.AddOrSetValue(tkStarAssign,   tcOperator);
  FCategories.AddOrSetValue(tkSlashAssign,  tcOperator);
  FCategories.AddOrSetValue(tkCaret,        tcOperator);
  FCategories.AddOrSetValue(tkPipe,         tcOperator);
  FCategories.AddOrSetValue(tkAmpersand,    tcOperator);

  // Delimiters
  FCategories.AddOrSetValue(tkColon,        tcDelimiter);
  FCategories.AddOrSetValue(tkSemicolon,    tcDelimiter);
  FCategories.AddOrSetValue(tkComma,        tcDelimiter);
  FCategories.AddOrSetValue(tkDot,          tcDelimiter);
  FCategories.AddOrSetValue(tkDotDot,       tcDelimiter);
  FCategories.AddOrSetValue(tkEllipsis,     tcDelimiter);
  FCategories.AddOrSetValue(tkLParen,       tcDelimiter);
  FCategories.AddOrSetValue(tkRParen,       tcDelimiter);
  FCategories.AddOrSetValue(tkLBracket,     tcDelimiter);
  FCategories.AddOrSetValue(tkRBracket,     tcDelimiter);

  // Literals
  FCategories.AddOrSetValue(tkIntLiteral,     tcLiteral);
  FCategories.AddOrSetValue(tkFloatLiteral,   tcLiteral);
  FCategories.AddOrSetValue(tkStringLiteral,  tcLiteral);
  FCategories.AddOrSetValue(tkWStringLiteral, tcLiteral);

  // Special
  FCategories.AddOrSetValue(tkIdentifier, tcIdentifier);
  FCategories.AddOrSetValue(tkDirective,  tcDirective);
  FCategories.AddOrSetValue(tkEOF,        tcSpecial);
  FCategories.AddOrSetValue(tkUnknown,    tcSpecial);
end;

// -- Source traversal -------------------------------------------------------

function TCPLexer.CurrentChar(): Char;
begin
  if FPos <= Length(FSource) then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TCPLexer.PeekChar(): Char;
begin
  Result := PeekCharAt(1);
end;

function TCPLexer.PeekCharAt(const AOffset: Int64): Char;
var
  LIdx: UInt64;
begin
  if AOffset >= 0 then
    LIdx := FPos + UInt64(AOffset)
  else
  begin
    if UInt64(-AOffset) > FPos then
    begin
      Result := #0;
      Exit;
    end;
    LIdx := FPos - UInt64(-AOffset);
  end;
  if (LIdx >= 1) and (LIdx <= UInt64(Length(FSource))) then
    Result := FSource[LIdx]
  else
    Result := #0;
end;

procedure TCPLexer.Advance();
var
  LCh: Char;
begin
  if FPos > Length(FSource) then
    Exit;
  LCh := FSource[FPos];
  Inc(FPos);
  if LCh = #10 then
  begin
    Inc(FLine);
    FCol := 1;
  end
  else if LCh <> #13 then
    Inc(FCol);
end;

function TCPLexer.IsAtSourceEnd(): Boolean;
begin
  Result := FPos > Length(FSource);
end;

function TCPLexer.MakeLocation(const AStartLine: UInt64;
  const AStartCol: UInt64): TSourceRange;
begin
  Result.Clear();
  Result.Filename := FFilename;
  Result.StartLine := AStartLine;
  Result.StartColumn := AStartCol;
end;

// -- Trivia and comment scanning --------------------------------------------

function TCPLexer.DoCollectTrivia(): string;
begin
  Result := '';
  while not IsAtSourceEnd() do
  begin
    if CharInSet(CurrentChar(), [' ', #9, #13, #10]) then
    begin
      Result := Result + CurrentChar();
      Advance();
    end
    else if (CurrentChar() = '/') and (PeekChar() = '/') then
      DoScanLineComment(Result)
    else if (CurrentChar() = '/') and (PeekChar() = '*') then
      DoScanBlockComment(Result)
    else
      Break;
  end;
end;

procedure TCPLexer.DoScanLineComment(var ATrivia: string);
begin
  // Consume // and everything until end of line
  while not IsAtSourceEnd() and (CurrentChar() <> #10) do
  begin
    ATrivia := ATrivia + CurrentChar();
    Advance();
  end;
  // Consume the newline as part of the comment trivia
  if not IsAtSourceEnd() then
  begin
    ATrivia := ATrivia + CurrentChar();
    Advance();
  end;
end;

procedure TCPLexer.DoScanBlockComment(var ATrivia: string);
var
  LDepth: Integer;
  LStartLine: UInt64;
  LStartCol: UInt64;
begin
  LStartLine := FLine;
  LStartCol := FCol;
  LDepth := 1;

  // Consume /*
  ATrivia := ATrivia + CurrentChar();
  Advance();
  ATrivia := ATrivia + CurrentChar();
  Advance();

  while not IsAtSourceEnd() and (LDepth > 0) do
  begin
    if (CurrentChar() = '/') and (PeekChar() = '*') then
    begin
      Inc(LDepth);
      ATrivia := ATrivia + CurrentChar();
      Advance();
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end
    else if (CurrentChar() = '*') and (PeekChar() = '/') then
    begin
      Dec(LDepth);
      ATrivia := ATrivia + CurrentChar();
      Advance();
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end
    else
    begin
      ATrivia := ATrivia + CurrentChar();
      Advance();
    end;
  end;

  if LDepth > 0 then
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, CP_ERR_LEX_002,
      RSLexUnterminatedComment);
end;

// -- Escape sequence processing ---------------------------------------------

function TCPLexer.DoProcessEscapeSeq(): Char;
var
  LHexStr: string;
  LHexVal: Integer;
begin
  // Current position is on the character after '\'
  Result := #0;

  if IsAtSourceEnd() then
  begin
    FErrors.Add(FFilename, FLine, FCol, esError, CP_ERR_LEX_005,
      RSLexInvalidEscape, ['EOF']);
    Exit;
  end;

  if CurrentChar() = 'n' then
  begin
    Result := #10;
    Advance();
  end
  else if CurrentChar() = 't' then
  begin
    Result := #9;
    Advance();
  end
  else if CurrentChar() = 'r' then
  begin
    Result := #13;
    Advance();
  end
  else if CurrentChar() = '0' then
  begin
    Result := #0;
    Advance();
  end
  else if CurrentChar() = '\' then
  begin
    Result := '\';
    Advance();
  end
  else if CurrentChar() = '''' then
  begin
    Result := '''';
    Advance();
  end
  else if CurrentChar() = '"' then
  begin
    Result := '"';
    Advance();
  end
  else if CurrentChar() = 'x' then
  begin
    // \xHH - two hex digits required
    Advance(); // skip 'x'
    if IsAtSourceEnd() or not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, FLine, FCol, esError, CP_ERR_LEX_005,
        RSLexInvalidEscape, ['x']);
      Exit;
    end;
    LHexStr := CurrentChar();
    Advance();
    if IsAtSourceEnd() or not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, FLine, FCol, esError, CP_ERR_LEX_005,
        RSLexInvalidEscape, ['x' + LHexStr]);
      Exit;
    end;
    LHexStr := LHexStr + CurrentChar();
    Advance();
    if TryStrToInt('$' + LHexStr, LHexVal) then
      Result := Char(LHexVal)
    else
      FErrors.Add(FFilename, FLine, FCol, esError, CP_ERR_LEX_005,
        RSLexInvalidEscape, ['x' + LHexStr]);
  end
  else
  begin
    FErrors.Add(FFilename, FLine, FCol, esError, CP_ERR_LEX_005,
      RSLexInvalidEscape, [CurrentChar()]);
    Advance();
  end;
end;

// -- Token scanning ---------------------------------------------------------

function TCPLexer.DoScanIdentifier(): TCPToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LText: string;
  LLower: string;
  LKind: TCPTokenKind;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  while not IsAtSourceEnd() and
    CharInSet(CurrentChar(), ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Advance();

  LText := FSource.Substring(LStart - 1, FPos - LStart);
  LLower := LText.ToLower();

  if FKeywords.TryGetValue(LLower, LKind) then
  begin
    Result.Kind := LKind;
    Result.TokenText := LLower;
    Result.Category := FCategories[LKind];
  end
  else
  begin
    Result.Kind := tkIdentifier;
    Result.TokenText := LText;
    Result.Category := tcIdentifier;
  end;

  Result.RawText := LText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

function TCPLexer.DoScanNumber(): TCPToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LText: string;
  LParseText: string;
  LFloatVal: Double;
  LUIntVal: UInt64;
  LIsFloat: Boolean;
  LIsHex: Boolean;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;
  LIsFloat := False;
  LIsHex := False;

  // Check for hex: 0x or 0X
  if (CurrentChar() = '0') and CharInSet(PeekChar(), ['x', 'X']) then
  begin
    LIsHex := True;
    Advance(); // 0
    Advance(); // x
    if IsAtSourceEnd() or
      not CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) then
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, CP_ERR_LEX_004,
        RSLexInvalidHexLiteral);
      LText := FSource.Substring(LStart - 1, FPos - LStart);
      Result.Kind := tkUnknown;
      Result.TokenText := LText;
      Result.RawText := LText;
      Result.Location := MakeLocation(LStartLine, LStartCol);
      Result.Category := tcSpecial;
      Exit;
    end;
    while not IsAtSourceEnd() and
      CharInSet(CurrentChar(), ['0'..'9', 'A'..'F', 'a'..'f']) do
      Advance();
  end
  else
  begin
    // Decimal digits
    while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
      Advance();

    // Check for decimal point (not '..' range operator)
    if not IsAtSourceEnd() and (CurrentChar() = '.') and (PeekChar() <> '.') then
    begin
      LIsFloat := True;
      Advance();
      while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
        Advance();
    end;

    // Check for exponent
    if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['e', 'E']) then
    begin
      LIsFloat := True;
      Advance();
      if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['+', '-']) then
        Advance();
      while not IsAtSourceEnd() and CharInSet(CurrentChar(), ['0'..'9']) do
        Advance();
    end;

    // Check for f/F suffix (always makes it float)
    if not IsAtSourceEnd() and CharInSet(CurrentChar(), ['f', 'F']) then
    begin
      LIsFloat := True;
      Advance();
    end;
  end;

  LText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := LText;
  Result.Location := MakeLocation(LStartLine, LStartCol);

  if LIsFloat then
  begin
    Result.Kind := tkFloatLiteral;
    Result.Category := tcLiteral;
    Result.TokenText := LText;
    // Strip f/F suffix for parsing
    LParseText := LText;
    if LParseText.EndsWith('f', True) then
      LParseText := LParseText.Substring(0, LParseText.Length - 1);
    if TryStrToFloat(LParseText, LFloatVal, TFormatSettings.Invariant) then
      Result.LiteralValue := TValue.From<Double>(LFloatVal)
    else
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, CP_ERR_LEX_006,
        RSLexInvalidNumber);
      Exit;
    end;
  end
  else
  begin
    Result.Kind := tkIntLiteral;
    Result.Category := tcLiteral;
    Result.TokenText := LText;
    if LIsHex then
      LParseText := '$' + LText.Substring(2)
    else
      LParseText := LText;
    if TryStrToUInt64(LParseText, LUIntVal) then
      Result.LiteralValue := TValue.From<UInt64>(LUIntVal)
    else
    begin
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, CP_ERR_LEX_006,
        RSLexInvalidNumber);
      Exit;
    end;
  end;
end;

function TCPLexer.DoScanStringLiteral(): TCPToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LContent: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume opening "

  LContent := '';
  while not IsAtSourceEnd() and (CurrentChar() <> '"') and (CurrentChar() <> #10) do
  begin
    if CurrentChar() = '\' then
    begin
      Advance(); // skip backslash
      LContent := LContent + DoProcessEscapeSeq();
    end
    else
    begin
      LContent := LContent + CurrentChar();
      Advance();
    end;
  end;

  if IsAtSourceEnd() or (CurrentChar() = #10) then
  begin
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, CP_ERR_LEX_001,
      RSLexUnterminatedString);
    Result.Kind := tkUnknown;
    Result.Category := tcSpecial;
    Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
    Result.RawText := Result.TokenText;
    Result.Location := MakeLocation(LStartLine, LStartCol);
    Exit;
  end;

  Advance(); // consume closing "

  Result.Kind := tkStringLiteral;
  Result.Category := tcLiteral;
  Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := Result.TokenText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
  Result.LiteralValue := TValue.From<string>(LContent);
end;

function TCPLexer.DoScanWStringLiteral(): TCPToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LContent: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume 'w'
  Advance(); // consume opening "

  LContent := '';
  while not IsAtSourceEnd() and (CurrentChar() <> '"') and (CurrentChar() <> #10) do
  begin
    if CurrentChar() = '\' then
    begin
      Advance();
      LContent := LContent + DoProcessEscapeSeq();
    end
    else
    begin
      LContent := LContent + CurrentChar();
      Advance();
    end;
  end;

  if IsAtSourceEnd() or (CurrentChar() = #10) then
  begin
    FErrors.Add(FFilename, LStartLine, LStartCol, esError, CP_ERR_LEX_001,
      RSLexUnterminatedString);
    Result.Kind := tkUnknown;
    Result.Category := tcSpecial;
    Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
    Result.RawText := Result.TokenText;
    Result.Location := MakeLocation(LStartLine, LStartCol);
    Exit;
  end;

  Advance(); // consume closing "

  Result.Kind := tkWStringLiteral;
  Result.Category := tcLiteral;
  Result.TokenText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.RawText := Result.TokenText;
  Result.Location := MakeLocation(LStartLine, LStartCol);
  Result.LiteralValue := TValue.From<string>(LContent);
end;

function TCPLexer.DoScanDirective(): TCPToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LStart: UInt64;
  LName: string;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LStart := FPos;

  Advance(); // consume '@'

  // Scan the directive identifier
  LName := '';
  while not IsAtSourceEnd() and
    CharInSet(CurrentChar(), ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    LName := LName + CurrentChar();
    Advance();
  end;

  Result.Kind := tkDirective;
  Result.Category := tcDirective;
  Result.TokenText := LName.ToLower();
  Result.RawText := FSource.Substring(LStart - 1, FPos - LStart);
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

function TCPLexer.DoScanOperator(): TCPToken;
var
  LStartLine: UInt64;
  LStartCol: UInt64;
  LCh: Char;
  LNext: Char;
begin
  Result.Clear();
  LStartLine := FLine;
  LStartCol := FCol;
  LCh := CurrentChar();
  LNext := PeekChar();

  // Multi-character operators first
  if (LCh = ':') and (LNext = '=') then
  begin
    Result.Kind := tkAssign;
    Result.TokenText := ':=';
    Advance(); Advance();
  end
  else if (LCh = '+') and (LNext = '=') then
  begin
    Result.Kind := tkPlusAssign;
    Result.TokenText := '+=';
    Advance(); Advance();
  end
  else if (LCh = '-') and (LNext = '=') then
  begin
    Result.Kind := tkMinusAssign;
    Result.TokenText := '-=';
    Advance(); Advance();
  end
  else if (LCh = '*') and (LNext = '=') then
  begin
    Result.Kind := tkStarAssign;
    Result.TokenText := '*=';
    Advance(); Advance();
  end
  else if (LCh = '/') and (LNext = '=') then
  begin
    Result.Kind := tkSlashAssign;
    Result.TokenText := '/=';
    Advance(); Advance();
  end
  else if (LCh = '<') and (LNext = '>') then
  begin
    Result.Kind := tkNotEqual;
    Result.TokenText := '<>';
    Advance(); Advance();
  end
  else if (LCh = '<') and (LNext = '=') then
  begin
    Result.Kind := tkLessEqual;
    Result.TokenText := '<=';
    Advance(); Advance();
  end
  else if (LCh = '>') and (LNext = '=') then
  begin
    Result.Kind := tkGreaterEqual;
    Result.TokenText := '>=';
    Advance(); Advance();
  end
  // ... (triple dot) must be checked before .. (double dot)
  else if (LCh = '.') and (LNext = '.') and (PeekCharAt(2) = '.') then
  begin
    Result.Kind := tkEllipsis;
    Result.TokenText := '...';
    Advance(); Advance(); Advance();
  end
  else if (LCh = '.') and (LNext = '.') then
  begin
    Result.Kind := tkDotDot;
    Result.TokenText := '..';
    Advance(); Advance();
  end

  // Single-character operators and delimiters
  else
  begin
    Advance();
    if LCh = '+' then
    begin
      Result.Kind := tkPlus;
      Result.TokenText := '+';
    end
    else if LCh = '-' then
    begin
      Result.Kind := tkMinus;
      Result.TokenText := '-';
    end
    else if LCh = '*' then
    begin
      Result.Kind := tkStar;
      Result.TokenText := '*';
    end
    else if LCh = '/' then
    begin
      Result.Kind := tkSlash;
      Result.TokenText := '/';
    end
    else if LCh = '=' then
    begin
      Result.Kind := tkEqual;
      Result.TokenText := '=';
    end
    else if LCh = '<' then
    begin
      Result.Kind := tkLess;
      Result.TokenText := '<';
    end
    else if LCh = '>' then
    begin
      Result.Kind := tkGreater;
      Result.TokenText := '>';
    end
    else if LCh = '^' then
    begin
      Result.Kind := tkCaret;
      Result.TokenText := '^';
    end
    else if LCh = '|' then
    begin
      Result.Kind := tkPipe;
      Result.TokenText := '|';
    end
    else if LCh = '&' then
    begin
      Result.Kind := tkAmpersand;
      Result.TokenText := '&';
    end
    else if LCh = ':' then
    begin
      Result.Kind := tkColon;
      Result.TokenText := ':';
    end
    else if LCh = ';' then
    begin
      Result.Kind := tkSemicolon;
      Result.TokenText := ';';
    end
    else if LCh = ',' then
    begin
      Result.Kind := tkComma;
      Result.TokenText := ',';
    end
    else if LCh = '.' then
    begin
      Result.Kind := tkDot;
      Result.TokenText := '.';
    end
    else if LCh = '(' then
    begin
      Result.Kind := tkLParen;
      Result.TokenText := '(';
    end
    else if LCh = ')' then
    begin
      Result.Kind := tkRParen;
      Result.TokenText := ')';
    end
    else if LCh = '[' then
    begin
      Result.Kind := tkLBracket;
      Result.TokenText := '[';
    end
    else if LCh = ']' then
    begin
      Result.Kind := tkRBracket;
      Result.TokenText := ']';
    end
    else
    begin
      Result.Kind := tkUnknown;
      Result.TokenText := LCh;
      FErrors.Add(FFilename, LStartLine, LStartCol, esError, CP_ERR_LEX_003,
        RSLexInvalidCharacter, [LCh]);
    end;
  end;

  Result.RawText := Result.TokenText;
  Result.Category := FCategories[Result.Kind];
  Result.Location := MakeLocation(LStartLine, LStartCol);
end;

{ TCPLexer.DoScanRawBlock }
procedure TCPLexer.DoScanRawBlock();
var
  LRawBuf: string;
  LRawStartLine: UInt64;
  LRawStartCol: UInt64;
  LEndWord: string;
  LEndLen: UInt64;
  LFoundEnd: Boolean;
  LI: UInt64;
  LAfterEnd: Char;
  LEndKwLine: UInt64;
  LEndKwCol: UInt64;
  LToken: TCPToken;
begin
  LEndWord := 'cppend';
  LEndLen := Length(LEndWord);

  // Skip whitespace before raw content
  while not IsAtSourceEnd() and CharInSet(CurrentChar(), [' ', #9, #13, #10]) do
  begin
    if CurrentChar() = #10 then
    begin
      Inc(FLine);
      FCol := 1;
    end
    else
      Inc(FCol);
    Inc(FPos);
  end;

  LRawBuf := '';
  LRawStartLine := FLine;
  LRawStartCol := FCol;

  while not IsAtSourceEnd() do
  begin
    // Check if current position starts with the end keyword
    LFoundEnd := True;
    for LI := 0 to LEndLen - 1 do
    begin
      if (FPos + LI > Length(FSource)) or
         (FSource[FPos + LI] <> LEndWord[LI + 1]) then
      begin
        LFoundEnd := False;
        Break;
      end;
    end;

    // Verify end keyword is a standalone word
    if LFoundEnd then
    begin
      if (FPos + LEndLen) <= Length(FSource) then
        LAfterEnd := FSource[FPos + LEndLen]
      else
        LAfterEnd := ' ';

      if not CharInSet(LAfterEnd, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      begin
        // Emit the raw block token with trimmed text
        LToken.Clear();
        LToken.Kind := tkRawBlock;
        LToken.TokenText := LRawBuf.TrimRight();
        LToken.RawText := LRawBuf;
        LToken.LeadingTrivia := '';
        LToken.Location := MakeLocation(LRawStartLine, LRawStartCol);
        LToken.Category := tcLiteral;
        FTokens.Add(LToken);

        // Emit the cppend keyword token
        LEndKwLine := FLine;
        LEndKwCol := FCol;
        for LI := 1 to LEndLen do
          Advance();

        LToken.Clear();
        LToken.Kind := tkCppEnd;
        LToken.TokenText := LEndWord;
        LToken.RawText := LEndWord;
        LToken.LeadingTrivia := '';
        LToken.Location := MakeLocation(LEndKwLine, LEndKwCol);
        LToken.Category := tcKeyword;
        FTokens.Add(LToken);
        Exit;
      end;
    end;

    // Accumulate raw character
    LRawBuf := LRawBuf + CurrentChar();
    Advance();
  end;

  // Reached end of source without finding cppend
  FErrors.Add(FFilename, LRawStartLine, LRawStartCol, esError,
    CP_ERR_LEX_003, 'Unterminated cppstart block, expected ''cppend''', []);
end;

function TCPLexer.DoScanToken(const ATrivia: string): TCPToken;
var
  LCh: Char;
begin
  LCh := CurrentChar();

  // Identifier or keyword (check for w"..." wstring first)
  if CharInSet(LCh, ['A'..'Z', 'a'..'z', '_']) then
  begin
    if (LCh = 'w') and (PeekChar() = '"') then
      Result := DoScanWStringLiteral()
    else
      Result := DoScanIdentifier();
  end
  // Numeric literal
  else if CharInSet(LCh, ['0'..'9']) then
    Result := DoScanNumber()
  // String literal
  else if LCh = '"' then
    Result := DoScanStringLiteral()
  // Directive
  else if LCh = '@' then
    Result := DoScanDirective()
  // Operator or delimiter
  else
    Result := DoScanOperator();

  Result.LeadingTrivia := ATrivia;
end;

// -- Tokenization -----------------------------------------------------------

function TCPLexer.TokenizeFile(const AFilename: string): Boolean;
var
  LSource: string;
  LFilename: string;
begin
  Result := False;

  LFilename := TPath.ChangeExtension(TUtils.ResolvePath(AFilename), CP_SRC_EXT);

  if not TFile.Exists(LFilename) then
  begin
    FErrors.Add(esFatal, CP_ERR_LEX_009, RSFatalFileNotFound, [LFilename]);
    Exit;
  end;

  try
    LSource := TFile.ReadAllText(LFilename);
  except
    on E: Exception do
    begin
      FErrors.Add(esFatal, CP_ERR_LEX_010, RSFatalFileReadError, [LFilename, E.Message]);
      Exit;
    end;
  end;

  Result := TokenizeString(LSource, LFilename);
end;

function TCPLexer.TokenizeString(const ASource: string;
  const AFilename: string): Boolean;
var
  LTrivia: string;
  LToken: TCPToken;
begin
  // Reset state
  FSource := ASource;
  FFilename := AFilename;
  FPos := 1;
  FLine := 1;
  FCol := 1;
  FTokenIndex := 0;
  FTokens.Clear();

  while not IsAtSourceEnd() do
  begin
    LTrivia := DoCollectTrivia();
    if IsAtSourceEnd() then
    begin
      // Trailing trivia goes on the EOF token
      LToken.Clear();
      LToken.Kind := tkEOF;
      LToken.TokenText := '';
      LToken.RawText := '';
      LToken.LeadingTrivia := LTrivia;
      LToken.Location := MakeLocation(FLine, FCol);
      LToken.Category := tcSpecial;
      FTokens.Add(LToken);
      Result := not FErrors.HasErrors();
      Exit;
    end;
    LToken := DoScanToken(LTrivia);
    FTokens.Add(LToken);

    // Raw block capture: when cppstart is encountered, collect verbatim
    // text until cppend appears as a standalone word
    if LToken.Kind = tkCppStart then
      DoScanRawBlock();
  end;

  // Ensure EOF token always present
  LToken.Clear();
  LToken.Kind := tkEOF;
  LToken.TokenText := '';
  LToken.RawText := '';
  LToken.LeadingTrivia := '';
  LToken.Location := MakeLocation(FLine, FCol);
  LToken.Category := tcSpecial;
  FTokens.Add(LToken);

  Result := not FErrors.HasErrors();
end;

function TCPLexer.CurrentToken(): TCPToken;
begin
  if FTokenIndex < FTokens.Count then
    Result := FTokens[FTokenIndex]
  else
  begin
    Result.Clear();
    Result.Kind := tkEOF;
    Result.Category := tcSpecial;
  end;
end;

function TCPLexer.NextToken(): TCPToken;
begin
  if FTokenIndex < FTokens.Count - 1 then
    Inc(FTokenIndex);
  Result := CurrentToken();
end;

function TCPLexer.PeekToken(): TCPToken;
begin
  Result := PeekAt(1);
end;

function TCPLexer.PeekAt(const AOffset: Int64): TCPToken;
var
  LIdx: UInt64;
begin
  if AOffset >= 0 then
    LIdx := FTokenIndex + UInt64(AOffset)
  else
  begin
    if UInt64(-AOffset) > FTokenIndex then
    begin
      Result.Clear();
      Result.Kind := tkEOF;
      Result.Category := tcSpecial;
      Exit;
    end;
    LIdx := FTokenIndex - UInt64(-AOffset);
  end;
  if LIdx < UInt64(FTokens.Count) then
    Result := FTokens[LIdx]
  else
  begin
    Result.Clear();
    Result.Kind := tkEOF;
    Result.Category := tcSpecial;
  end;
end;

function TCPLexer.Match(const AKind: TCPTokenKind): Boolean;
begin
  Result := CurrentToken().Kind = AKind;
  if Result then
    NextToken();
end;

function TCPLexer.Expect(const AKind: TCPTokenKind): TCPToken;
var
  LExpected: string;
  LPair: TPair<string, TCPTokenKind>;
begin
  Result := CurrentToken();
  if Result.Kind <> AKind then
  begin
    // Build a readable description of the expected token
    LExpected := '';
    for LPair in FKeywords do
    begin
      if LPair.Value = AKind then
      begin
        LExpected := '''' + LPair.Key + '''';
        Break;
      end;
    end;
    if LExpected = '' then
      LExpected := 'token';
    FErrors.Add(Result.Location, esError, CP_ERR_LEX_008,
      RSLexExpected, [LExpected, Result.RawText]);
  end
  else
    NextToken();
end;

function TCPLexer.IsAtEnd(): Boolean;
begin
  Result := CurrentToken().Kind = tkEOF;
end;

function TCPLexer.IsDataType(const AKind: TCPTokenKind): Boolean;
var
  LCategory: TCPTokenCategory;
begin
  Result := FCategories.TryGetValue(AKind, LCategory) and
    (LCategory = tcPrimitive);
end;

function TCPLexer.IsOperator(const AKind: TCPTokenKind): Boolean;
var
  LCategory: TCPTokenCategory;
begin
  Result := FCategories.TryGetValue(AKind, LCategory) and
    (LCategory = tcOperator);
end;

function TCPLexer.GetCppType(const AKind: TCPTokenKind): string;
begin
  if not FCppTypes.TryGetValue(AKind, Result) then
    Result := '';
end;

function TCPLexer.GetCategory(const AKind: TCPTokenKind): TCPTokenCategory;
begin
  if not FCategories.TryGetValue(AKind, Result) then
    Result := tcSpecial;
end;

function TCPLexer.TokenCount(): UInt64;
begin
  Result := FTokens.Count;
end;

function TCPLexer.ToSource(): string;
var
  LBuilder: TStringBuilder;
  LIdx: Int64;
begin
  LBuilder := TStringBuilder.Create();
  try
    for LIdx := 0 to FTokens.Count - 1 do
    begin
      LBuilder.Append(FTokens[LIdx].LeadingTrivia);
      LBuilder.Append(FTokens[LIdx].RawText);
    end;
    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

end.
