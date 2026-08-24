{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.Common - Shared types and definitions

  Central definitions shared across all compiler units: token categories,
  token kinds, and the TCPToken record. This unit defines the vocabulary of
  the lexer and the data contract that flows through the entire pipeline.

  Dependencies: StdApp.Base (TSourceRange)
  Notes: Do NOT add System.TypInfo to uses -- TTypeKind's tk* values collide.
===============================================================================}

unit CPaskal.Common;

interface

uses
  System.SysUtils,
  System.Rtti,
  StdApp.Base;

const
  CP_SRC_EXT = 'cpas';

type

  { TCPTokenCategory }
  TCPTokenCategory = (
    tcKeyword,        // language reserved words
    tcPrimitive,      // built-in type names (int32, string, etc.)
    tcOperator,       // operators (+, -, :=, etc.)
    tcDelimiter,      // structural punctuation (; , . ( ) etc.)
    tcLiteral,        // integer, float, string, wstring literals
    tcIdentifier,     // user-defined identifiers
    tcDirective,      // @name directives
    tcSpecial         // EOF, unknown
  );

  { TCPTokenKind }
  TCPTokenKind = (

    // -- Special tokens --
    tkEOF,
    tkUnknown,
    tkIdentifier,
    tkDirective,

    // -- Literals --
    tkIntLiteral,
    tkFloatLiteral,
    tkStringLiteral,
    tkWStringLiteral,

    // -- Keywords (BNF Section 2 - Reserved Words) --
    tkAddress,
    tkAlign,
    tkAnd,
    tkArray,
    tkAssert,
    tkAssertEq,
    tkAssertEqF,
    tkAssertFalse,
    tkAssertFail,
    tkAssertNil,
    tkAssertNotNil,
    tkAssertTrue,
    tkBegin,
    tkBreak,
    tkChoices,
    tkCLink,
    tkConst,
    tkContinue,
    tkCppLink,
    tkCreate,
    tkCStr,
    tkDestroy,
    tkDiv,
    tkDo,
    tkDownTo,
    tkElse,
    tkEnd,
    tkExcept,
    tkExcCode,
    tkExcMsg,
    tkExternal,
    tkFalse,
    tkFinalize,
    tkFinally,
    tkFor,
    tkForward,
    tkFreeMem,
    tkGetMem,
    tkGuard,

    tkIf,
    tkImport,
    tkIn,
    tkInitialize,
    tkIs,
    tkLen,
    tkMatch,
    tkMod,
    tkModule,
    tkNil,
    tkNot,
    tkOf,
    tkOr,
    tkOverlay,
    tkPacked,
    tkParamCount,
    tkParamStr,
    tkPointer,
    tkPrint,
    tkPrintLn,
    tkPublic,
    tkRecord,
    tkRepeat,
    tkResizeMem,
    tkReturn,
    tkRoutine,
    tkSet,
    tkSetLength,
    tkShl,
    tkShr,
    tkSize,
    tkTest,
    tkThen,
    tkThrow,
    tkThrowCode,
    tkTo,
    tkTrue,
    tkType,
    tkUntil,
    tkUtf8,
    tkVar,
    tkVarArgs,
    tkWhile,
    tkWStr,
    tkXor,

    // -- Primitive types (BNF Section 3 - Built-in Types) --
    // Registered as keywords with tcPrimitive category and C++23 mappings.
    // pointer is already listed above as a keyword; it is registered once
    // with tcPrimitive category so GetCppType works.
    tkInt8,
    tkInt16,
    tkInt32,
    tkInt64,
    tkUInt8,
    tkUInt16,
    tkUInt32,
    tkUInt64,
    tkFloat32,
    tkFloat64,
    tkBoolean,
    tkChar,
    tkWChar,
    tkString,
    tkWString,

    // -- Operators (BNF Section 4) --
    tkPlus,           // +
    tkMinus,          // -
    tkStar,           // *
    tkSlash,          // /
    tkEqual,          // =
    tkNotEqual,       // <>
    tkLess,           // <
    tkGreater,        // >
    tkLessEqual,      // <=
    tkGreaterEqual,   // >=
    tkAssign,         // :=
    tkPlusAssign,     // +=
    tkMinusAssign,    // -=
    tkStarAssign,     // *=
    tkSlashAssign,    // /=
    tkCaret,          // ^
    tkPipe,           // |
    tkAmpersand,      // &

    // -- Delimiters --
    tkColon,          // :
    tkSemicolon,      // ;
    tkComma,          // ,
    tkDot,            // .
    tkDotDot,         // ..
    tkEllipsis,       // ...
    tkLParen,         // (
    tkRParen,         // )
    tkLBracket,       // [
    tkRBracket        // ]
  );

  { TCPToken }
  TCPToken = record
    Kind: TCPTokenKind;
    TokenText: string;        // canonical text (lowercased for keywords)
    RawText: string;          // exactly as it appeared in source
    LeadingTrivia: string;    // whitespace and comments preceding this token
    Location: TSourceRange;   // file, line, column
    Category: TCPTokenCategory; // what family this token belongs to
    LiteralValue: TValue;     // parsed literal (Int64, UInt64, Double, or string)
    procedure Clear();
  end;

implementation

{ TCPToken }

procedure TCPToken.Clear();
begin
  Kind := tkUnknown;
  TokenText := '';
  RawText := '';
  LeadingTrivia := '';
  Location.Clear();
  Category := tcSpecial;
  LiteralValue := TValue.Empty;
end;

end.
