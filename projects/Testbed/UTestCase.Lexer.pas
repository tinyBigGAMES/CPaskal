{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  UTestCase.Lexer - Lexer test cases

  Tests for TCPLexer: keyword recognition, operators, literals, comments,
  trivia preservation, source reconstruction, and file tokenization.

  Dependencies: StdApp.TestCase, CPaskal.Common, CPaskal.Lexer
===============================================================================}

unit UTestCase.Lexer;

interface

uses
  StdApp.TestCase;

type

  { TCPLexerTests }
  TCPLexerTests = class(TTestCase)
  protected
    procedure Run(); override;
  public
    constructor Create(); override;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Rtti,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Console,
  CPaskal.Common,
  CPaskal.Lexer;

{ TCPLexerTests }

constructor TCPLexerTests.Create();
begin
  inherited;
  Title := 'Lexer';

  // -- Keywords --
  RegisterTest('keywords', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('begin end if then else while do for', 'test');
      Check(LLexer.CurrentToken().Kind = tkBegin, 'begin');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkEnd, 'end');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkIf, 'if');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkThen, 'then');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkElse, 'else');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkWhile, 'while');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkDo, 'do');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkFor, 'for');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkEOF, 'EOF after keywords');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Primitive types --
  RegisterTest('primitives', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('int32 float64 boolean string wstring pointer', 'test');
      Check(LLexer.CurrentToken().Kind = tkInt32, 'int32');
      Check(LLexer.CurrentToken().Category = tcPrimitive, 'int32 is primitive');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkFloat64, 'float64');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkBoolean, 'boolean');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkString, 'string');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkWString, 'wstring');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkPointer, 'pointer');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- C++ type mappings --
  RegisterTest('cpp_types', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      Check(LLexer.GetCppType(tkInt32) = 'int32_t', 'int32 -> int32_t');
      Check(LLexer.GetCppType(tkFloat64) = 'double', 'float64 -> double');
      Check(LLexer.GetCppType(tkBoolean) = 'bool', 'boolean -> bool');
      Check(LLexer.GetCppType(tkString) = 'std::string', 'string -> std::string');
      Check(LLexer.GetCppType(tkWString) = 'std::wstring', 'wstring -> std::wstring');
      Check(LLexer.GetCppType(tkPointer) = 'void*', 'pointer -> void*');
      Check(LLexer.GetCppType(tkChar) = 'char', 'char -> char');
      Check(LLexer.GetCppType(tkWChar) = 'char16_t', 'wchar -> char16_t');
      Check(LLexer.GetCppType(tkBegin) = '', 'begin has no cpp type');
    finally
      LLexer.Free();
    end;
  end);

  // -- Operators --
  RegisterTest('operators', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString(':= += -= *= /= = <> < > <= >=', 'test');
      Check(LLexer.CurrentToken().Kind = tkAssign, ':=');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkPlusAssign, '+=');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkMinusAssign, '-=');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkStarAssign, '*=');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkSlashAssign, '/=');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkEqual, '=');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkNotEqual, '<>');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkLess, '<');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkGreater, '>');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkLessEqual, '<=');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkGreaterEqual, '>=');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Delimiters and dot variants --
  RegisterTest('delimiters', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString(': ; , . .. ... ( ) [ ]', 'test');
      Check(LLexer.CurrentToken().Kind = tkColon, ':');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkSemicolon, ';');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkComma, ',');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkDot, '.');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkDotDot, '..');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkEllipsis, '...');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkLParen, '(');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkRParen, ')');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkLBracket, '[');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().Kind = tkRBracket, ']');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Integer literals --
  RegisterTest('int_literals', procedure
  var
    LLexer: TCPLexer;
    LToken: TCPToken;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('42 0 0xFF 0x1A', 'test');
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkIntLiteral, '42 is int literal');
      Check(LToken.LiteralValue.AsUInt64 = 42, '42 value');
      LLexer.NextToken();
      LToken := LLexer.CurrentToken();
      Check(LToken.LiteralValue.AsUInt64 = 0, '0 value');
      LLexer.NextToken();
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkIntLiteral, '0xFF is int literal');
      Check(LToken.LiteralValue.AsUInt64 = 255, '0xFF = 255');
      LLexer.NextToken();
      LToken := LLexer.CurrentToken();
      Check(LToken.LiteralValue.AsUInt64 = 26, '0x1A = 26');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Float literals --
  RegisterTest('float_literals', procedure
  var
    LLexer: TCPLexer;
    LToken: TCPToken;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('3.14 1.0e10 2.5f', 'test');
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkFloatLiteral, '3.14 is float literal');
      Check(Abs(LToken.LiteralValue.AsExtended - 3.14) < 0.001, '3.14 value');
      LLexer.NextToken();
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkFloatLiteral, '1.0e10 is float literal');
      LLexer.NextToken();
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkFloatLiteral, '2.5f is float literal');
      Check(LToken.RawText = '2.5f', '2.5f raw text preserved');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- String literals --
  RegisterTest('string_literals', procedure
  var
    LLexer: TCPLexer;
    LToken: TCPToken;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('"hello" "line\nbreak" "\x41"', 'test');
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkStringLiteral, 'hello is string literal');
      Check(LToken.LiteralValue.AsString = 'hello', 'hello value');
      LLexer.NextToken();
      LToken := LLexer.CurrentToken();
      Check(LToken.LiteralValue.AsString = 'line' + #10 + 'break', 'escape \n');
      LLexer.NextToken();
      LToken := LLexer.CurrentToken();
      Check(LToken.LiteralValue.AsString = 'A', '\x41 = A');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Wide string literals --
  RegisterTest('wstring_literals', procedure
  var
    LLexer: TCPLexer;
    LToken: TCPToken;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('w"wide string"', 'test');
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkWStringLiteral, 'w"..." is wstring literal');
      Check(LToken.LiteralValue.AsString = 'wide string', 'wstring value');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Comments as trivia --
  RegisterTest('comments', procedure
  var
    LLexer: TCPLexer;
    LToken: TCPToken;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('// line comment' + #10 + 'begin /* block */ end', 'test');
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkBegin, 'begin after line comment');
      Check(LToken.LeadingTrivia.Contains('// line comment'), 'line comment in trivia');
      LLexer.NextToken();
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkEnd, 'end after block comment');
      Check(LToken.LeadingTrivia.Contains('/* block */'), 'block comment in trivia');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Nested block comments --
  RegisterTest('nested_comments', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('/* outer /* inner */ still outer */ begin', 'test');
      Check(LLexer.CurrentToken().Kind = tkBegin, 'begin after nested comment');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Directives --
  RegisterTest('directives', procedure
  var
    LLexer: TCPLexer;
    LToken: TCPToken;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('@target @unittestmode @define', 'test');
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkDirective, '@ produces directive');
      Check(LToken.TokenText = 'target', 'directive name = target');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().TokenText = 'unittestmode', 'unittestmode');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().TokenText = 'define', 'define');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Identifiers --
  RegisterTest('identifiers', procedure
  var
    LLexer: TCPLexer;
    LToken: TCPToken;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeString('myVar _private count2', 'test');
      LToken := LLexer.CurrentToken();
      Check(LToken.Kind = tkIdentifier, 'myVar is identifier');
      Check(LToken.TokenText = 'myVar', 'case preserved');
      Check(LToken.Category = tcIdentifier, 'category is identifier');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().TokenText = '_private', '_private');
      LLexer.NextToken();
      Check(LLexer.CurrentToken().TokenText = 'count2', 'count2');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Source reconstruction --
  RegisterTest('to_source', procedure
  var
    LLexer: TCPLexer;
    LSource: string;
  begin
    LLexer := TCPLexer.Create();
    try
      LSource := 'module exe hello;' + #13#10 +
                 '// a comment' + #13#10 +
                 'begin' + #13#10 +
                 '  println("hello");' + #13#10 +
                 'end.';
      LLexer.TokenizeString(LSource, 'test');
      Check(LLexer.ToSource() = LSource, 'ToSource reproduces original');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- Category queries --
  RegisterTest('categories', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      Check(LLexer.IsDataType(tkInt32), 'int32 is data type');
      Check(LLexer.IsDataType(tkString), 'string is data type');
      Check(LLexer.IsDataType(tkPointer), 'pointer is data type');
      Check(not LLexer.IsDataType(tkBegin), 'begin is not data type');
      Check(LLexer.IsOperator(tkPlus), '+ is operator');
      Check(LLexer.IsOperator(tkAssign), ':= is operator');
      Check(not LLexer.IsOperator(tkSemicolon), '; is not operator');
      Check(LLexer.GetCategory(tkLParen) = tcDelimiter, '( is delimiter');
      Check(LLexer.GetCategory(tkIntLiteral) = tcLiteral, 'int literal category');
      Check(LLexer.GetCategory(tkDirective) = tcDirective, 'directive category');
    finally
      LLexer.Free();
    end;
  end);

  // -- File tokenization --
  RegisterTest('tokenize_file', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      Check(LLexer.TokenizeFile('$P:res\tests\testbed\hello'), 'tokenize hello.cpas');
      Check(LLexer.TokenCount() > 0, 'tokens produced');
      Check(LLexer.CurrentToken().Kind = tkModule, 'first token is module');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

  // -- File source reconstruction --
  RegisterTest('file_to_source', procedure
  var
    LLexer: TCPLexer;
  begin
    LLexer := TCPLexer.Create();
    try
      LLexer.TokenizeFile('$P:res\tests\testbed\hello');
      Check(LLexer.ToSource() = LLexer.SourceText, 'file ToSource matches original');
      Check(not LLexer.GetErrors().HasErrors(), 'no errors');
      FlushErrors(LLexer.GetErrors());
    finally
      LLexer.Free();
    end;
  end);

end;

procedure TCPLexerTests.Run();
begin
  inherited;
end;

end.
