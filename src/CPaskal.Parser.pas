{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.Parser - Recursive descent + Pratt expression parser

  Parses a CPaskal token stream into AST nodes. Uses recursive descent for
  statements and declarations, and a Pratt (top-down operator precedence)
  parser for expressions. Produces TCPModuleNode instances that attach to the
  master AST.

  The parser never interrupts itself for imports. When it encounters an
  import clause, it enqueues pending module names on the master AST's work
  queue. The outer compile loop calls ParseModule for each pending file.

  Dependencies: CPaskal.Common, CPaskal.AST, CPaskal.Lexer, StdApp.Base
===============================================================================}

unit CPaskal.Parser;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Resources,
  CPaskal.Common,
  CPaskal.AST,
  CPaskal.Lexer;

const
  CP_ERR_PAR_001 = 'PAR001';  // Unexpected token
  CP_ERR_PAR_002 = 'PAR002';  // Expected token not found
  CP_ERR_PAR_003 = 'PAR003';  // Invalid module kind
  CP_ERR_PAR_004 = 'PAR004';  // Duplicate import
  CP_ERR_PAR_005 = 'PAR005';  // Invalid type definition
  CP_ERR_PAR_006 = 'PAR006';  // Invalid statement
  CP_ERR_PAR_007 = 'PAR007';  // Invalid expression
  CP_ERR_PAR_008 = 'PAR008';  // Expected identifier
  CP_ERR_PAR_009 = 'PAR009';  // Invalid directive
  CP_ERR_PAR_010 = 'PAR010';  // Invalid match arm
  CP_ERR_PAR_020 = 'PAR020';  // Conditional directive missing identifier
  CP_ERR_PAR_021 = 'PAR021';  // Unmatched @elseif/@else/@endif
  CP_ERR_PAR_022 = 'PAR022';  // Unterminated @ifdef/@ifndef block

type

  { TCPCondState }
  TCPCondState = record
    Active: Boolean;
    HadTrue: Boolean;
    HadElse: Boolean;
    ParentActive: Boolean;
  end;

  { TCPParser }
  TCPParser = class(TBaseObject)
  private
    FLexer: TCPLexer;
    FMasterAST: TCPMasterAST;

    // Conditional compilation
    FDefines: TDictionary<string, string>;
    FCondStack: TList<TCPCondState>;
    procedure DoProcessConditionals();
    procedure DoSkipFalseBranch();
    procedure DoSetupPredefinedDefines(const AModuleKind: TCPModuleKind);

    // Token helpers
    function Current(): TCPToken;
    function PeekAt(const AOffset: Int64): TCPToken;
    function Consume(): TCPToken;
    function Match(const AKind: TCPTokenKind): Boolean;
    function Expect(const AKind: TCPTokenKind): TCPToken;
    function Check(const AKind: TCPTokenKind): Boolean;
    procedure OptionalSemicolon();
    procedure ExpectBlockEnd(const AConstruct: string;
      const AStartLocation: TSourceRange);

    // Precedence
    function GetPrecedence(const AKind: TCPTokenKind): Integer;
    function IsRelOp(const AKind: TCPTokenKind): Boolean;
    function IsAddOp(const AKind: TCPTokenKind): Boolean;
    function IsMulOp(const AKind: TCPTokenKind): Boolean;
    function IsAssignOp(const AKind: TCPTokenKind): Boolean;
    function IsStatementStart(const AKind: TCPTokenKind): Boolean;
    function TokenToBinaryOp(const AKind: TCPTokenKind): TCPBinaryOp;
    function TokenToAssignOp(const AKind: TCPTokenKind): TCPAssignOp;

    // Module structure
    function DoParseModuleKind(): TCPModuleKind;
    procedure DoParseDirectives(const AModule: TCPModuleNode);
    procedure DoParseImportClause(const AModule: TCPModuleNode);
    procedure DoParseDeclarations(const AModule: TCPModuleNode);
    procedure DoParseInitializeBlock(const AModule: TCPModuleNode);
    procedure DoParseFinalizeBlock(const AModule: TCPModuleNode);
    procedure DoParseMainBody(const AModule: TCPModuleNode);
    procedure DoParseTestBlocks(const AModule: TCPModuleNode);

    // Declarations
    function DoParseConstDecl(const AIsPublic: Boolean): TCPConstDeclNode;
    function DoParseTypeDecl(const AIsPublic: Boolean): TCPTypeDeclNode;
    function DoParseVarDecl(const AIsPublic: Boolean): TCPVarDeclNode;
    function DoParseRoutineDecl(const AIsPublic: Boolean): TCPRoutineDeclNode;
    function DoParseForwardDecl(): TCPASTNode;
    procedure DoParseFormalParams(const ARoutine: TCPRoutineDeclNode);
    function DoParseParamDecl(): TCPParamDeclNode;
    procedure DoParseRoutineBody(const ARoutine: TCPRoutineDeclNode);

    // Type definitions
    function DoParseTypeDef(): TCPASTNode;
    function DoParseRecordType(): TCPRecordTypeNode;
    function DoParseOverlayType(): TCPOverlayTypeNode;
    function DoParseArrayType(): TCPArrayTypeNode;
    function DoParsePointerType(): TCPPointerTypeNode;
    function DoParseSetType(): TCPSetTypeNode;
    function DoParseChoicesType(): TCPChoicesTypeNode;
    function DoParseRoutineTypeDef(): TCPRoutineTypeNode;
    function DoParseTypeExpr(): TCPASTNode;
    function DoParseFieldDecl(): TCPFieldDeclNode;

    // Statements
    function DoParseStatementSeq(const ATerminators: array of TCPTokenKind): TObjectList<TCPASTNode>;
    function DoParseStatement(): TCPASTNode;
    function DoParseAssignOrCall(): TCPASTNode;
    function DoParseIfStmt(): TCPIfNode;
    function DoParseWhileStmt(): TCPWhileNode;
    function DoParseForStmt(): TCPForNode;
    function DoParseRepeatStmt(): TCPRepeatNode;
    function DoParseMatchStmt(): TCPMatchNode;
    function DoParseMatchArm(): TCPMatchArmNode;
    function DoParseReturnStmt(): TCPReturnNode;
    function DoParseGuardStmt(): TCPGuardNode;
    function DoParseThrowStmt(): TCPASTNode;
    function DoParseNewStmt(): TCPNewNode;
    function DoParseDisposeStmt(): TCPDisposeNode;
    function DoParseGetMemStmt(): TCPGetMemNode;
    function DoParseFreeMemStmt(): TCPFreeMemNode;
    function DoParseResizeMemStmt(): TCPResizeMemNode;
    function DoParseSetLengthStmt(): TCPSetLengthNode;
    function DoParsePrintStmt(): TCPPrintNode;
    function DoParseAssertStmt(): TCPAssertStmtNode;
    function DoParseCppBlock(): TCPCppBlockNode;
    function DoParseCppStmt(): TCPASTNode;
    function DoParseCppExpr(): TCPCppExprNode;

    // Expressions (Pratt parser)
    function DoParseExpression(): TCPASTNode;
    function DoParsePrecedence(const AMinPrec: Integer): TCPASTNode;
    function DoParsePrefix(): TCPASTNode;
    function DoParseDesignator(const ABase: TCPASTNode): TCPASTNode;
    function DoParseSetLiteral(): TCPSetLiteralExprNode;
    function DoParseIntrinsic(const AKind: TCPIntrinsicKind): TCPIntrinsicExprNode;
    function IsIntrinsicToken(const AKind: TCPTokenKind): Boolean;
    function TokenToIntrinsicKind(const AKind: TCPTokenKind): TCPIntrinsicKind;

  public
    constructor Create(); override;
    destructor Destroy(); override;

    function ParseModule(const AFilename: string; const AMasterAST: TCPMasterAST): TCPModuleNode;
    procedure SetErrors(const AErrors: TErrors); override;
    procedure SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer = nil); override;

    // Conditional compilation defines
    procedure SetDefine(const AName: string; const AValue: string);
    procedure Undefine(const AName: string);
    function IsDefined(const AName: string): Boolean;

    property Lexer: TCPLexer read FLexer;
    property MasterAST: TCPMasterAST read FMasterAST;
  end;

implementation

{ TCPParser }
constructor TCPParser.Create();
begin
  inherited;

  FLexer := TCPLexer.Create();
  FLexer.SetErrors(FErrors);
  FDefines := TDictionary<string, string>.Create();
  FCondStack := TList<TCPCondState>.Create();
end;

destructor TCPParser.Destroy();
begin
  FCondStack.Free();
  FDefines.Free();
  FLexer.Free();

  inherited;
end;

procedure TCPParser.SetErrors(const AErrors: TErrors);
begin
  inherited;

  FLexer.SetErrors(AErrors);
end;

procedure TCPParser.SetStatusCallback(const ACallback: TStatusCallback; const AUserData: Pointer);
begin
  inherited;

  FLexer.SetStatusCallback(ACallback, AUserData);
end;

// -- Token helpers ----------------------------------------------------------

function TCPParser.Current(): TCPToken;
begin
  Result := FLexer.CurrentToken();
end;

function TCPParser.PeekAt(const AOffset: Int64): TCPToken;
begin
  Result := FLexer.PeekAt(AOffset);
end;

function TCPParser.Consume(): TCPToken;
begin
  Result := FLexer.CurrentToken();
  FLexer.NextToken();
  DoProcessConditionals();
end;

function TCPParser.Match(const AKind: TCPTokenKind): Boolean;
begin
  Result := Current().Kind = AKind;
  if Result then
  begin
    FLexer.NextToken();
    DoProcessConditionals();
  end;
end;

function TCPParser.Expect(const AKind: TCPTokenKind): TCPToken;
begin
  Result := Current();
  if Result.Kind = AKind then
  begin
    FLexer.NextToken();
    DoProcessConditionals();
  end
  else
    FLexer.Expect(AKind);
end;

function TCPParser.Check(const AKind: TCPTokenKind): Boolean;
begin
  Result := Current().Kind = AKind;
end;

procedure TCPParser.OptionalSemicolon();
begin
  Match(tkSemicolon);
end;

{ TCPParser.ExpectBlockEnd }
procedure TCPParser.ExpectBlockEnd(const AConstruct: string;
  const AStartLocation: TSourceRange);
begin
  if not Match(tkEnd) then
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_002,
      'Expected "end" to close "%s" started at line %d',
      [AConstruct, AStartLocation.StartLine]);
end;

// -- Precedence helpers -----------------------------------------------------

function TCPParser.GetPrecedence(const AKind: TCPTokenKind): Integer;
begin
  if IsRelOp(AKind) then
    Result := 1
  else if IsAddOp(AKind) then
    Result := 2
  else if IsMulOp(AKind) then
    Result := 3
  else
    Result := 0;
end;

function TCPParser.IsRelOp(const AKind: TCPTokenKind): Boolean;
begin
  Result := (AKind = tkEqual) or (AKind = tkNotEqual) or
            (AKind = tkLess) or (AKind = tkGreater) or
            (AKind = tkLessEqual) or (AKind = tkGreaterEqual) or
            (AKind = tkIn);
end;

function TCPParser.IsAddOp(const AKind: TCPTokenKind): Boolean;
begin
  Result := (AKind = tkPlus) or (AKind = tkMinus) or
            (AKind = tkOr) or (AKind = tkXor);
end;

function TCPParser.IsMulOp(const AKind: TCPTokenKind): Boolean;
begin
  Result := (AKind = tkStar) or (AKind = tkSlash) or
            (AKind = tkDiv) or (AKind = tkMod) or
            (AKind = tkAnd) or (AKind = tkShl) or (AKind = tkShr);
end;

function TCPParser.IsAssignOp(const AKind: TCPTokenKind): Boolean;
begin
  Result := (AKind = tkAssign) or (AKind = tkPlusAssign) or
            (AKind = tkMinusAssign) or (AKind = tkStarAssign) or
            (AKind = tkSlashAssign);
end;

{ TCPParser.IsStatementStart }
function TCPParser.IsStatementStart(const AKind: TCPTokenKind): Boolean;
begin
  Result :=
    (AKind = tkIf) or (AKind = tkWhile) or (AKind = tkFor) or
    (AKind = tkRepeat) or (AKind = tkMatch) or (AKind = tkReturn) or
    (AKind = tkGuard) or (AKind = tkThrow) or (AKind = tkThrowCode) or
    (AKind = tkBreak) or (AKind = tkContinue) or
    (AKind = tkNew) or (AKind = tkDispose) or
    (AKind = tkGetMem) or (AKind = tkFreeMem) or
    (AKind = tkResizeMem) or (AKind = tkSetLength) or
    (AKind = tkPrint) or (AKind = tkPrintLn) or
    (AKind = tkAssert) or (AKind = tkAssertTrue) or (AKind = tkAssertFalse) or
    (AKind = tkAssertEq) or (AKind = tkAssertEqF) or (AKind = tkAssertNil) or
    (AKind = tkAssertNotNil) or (AKind = tkAssertFail) or
    (AKind = tkCppStart) or (AKind = tkCpp) or
    (AKind = tkDirective) or (AKind = tkVar) or
    (AKind = tkIdentifier) or (AKind = tkVarArgs);
end;

function TCPParser.TokenToBinaryOp(const AKind: TCPTokenKind): TCPBinaryOp;
begin
  if AKind = tkPlus then Result := boAdd
  else if AKind = tkMinus then Result := boSub
  else if AKind = tkStar then Result := boMul
  else if AKind = tkSlash then Result := boDiv
  else if AKind = tkDiv then Result := boIntDiv
  else if AKind = tkMod then Result := boMod
  else if AKind = tkAnd then Result := boAnd
  else if AKind = tkOr then Result := boOr
  else if AKind = tkXor then Result := boXor
  else if AKind = tkShl then Result := boShl
  else if AKind = tkShr then Result := boShr
  else if AKind = tkEqual then Result := boEq
  else if AKind = tkNotEqual then Result := boNotEq
  else if AKind = tkLess then Result := boLess
  else if AKind = tkGreater then Result := boGreater
  else if AKind = tkLessEqual then Result := boLessEq
  else if AKind = tkGreaterEqual then Result := boGreaterEq
  else if AKind = tkIn then Result := boIn
  else
    Result := boAdd;  // should never reach here
end;

function TCPParser.TokenToAssignOp(const AKind: TCPTokenKind): TCPAssignOp;
begin
  if AKind = tkAssign then Result := aoAssign
  else if AKind = tkPlusAssign then Result := aoPlusAssign
  else if AKind = tkMinusAssign then Result := aoMinusAssign
  else if AKind = tkStarAssign then Result := aoMulAssign
  else if AKind = tkSlashAssign then Result := aoDivAssign
  else
    Result := aoAssign;  // should never reach here
end;

// -- Intrinsic helpers ------------------------------------------------------

function TCPParser.IsIntrinsicToken(const AKind: TCPTokenKind): Boolean;
begin
  Result := (AKind = tkLen) or (AKind = tkSize) or (AKind = tkUtf8) or
            (AKind = tkCStr) or (AKind = tkWStr) or
            (AKind = tkParamCount) or (AKind = tkParamStr) or
            (AKind = tkExcCode) or (AKind = tkExcMsg);
end;

function TCPParser.TokenToIntrinsicKind(const AKind: TCPTokenKind): TCPIntrinsicKind;
begin
  if AKind = tkLen then Result := ikLen
  else if AKind = tkSize then Result := ikSize
  else if AKind = tkUtf8 then Result := ikUtf8
  else if AKind = tkCStr then Result := ikCStr
  else if AKind = tkWStr then Result := ikWStr
  else if AKind = tkParamCount then Result := ikParamCount
  else if AKind = tkParamStr then Result := ikParamStr
  else if AKind = tkExcCode then Result := ikExcCode
  else if AKind = tkExcMsg then Result := ikExcMsg
  else
    Result := ikLen;  // should never reach here
end;

// -- Conditional compilation ------------------------------------------------

{ TCPParser.SetDefine }
procedure TCPParser.SetDefine(const AName: string; const AValue: string);
begin
  FDefines.AddOrSetValue(AName, AValue);
end;

{ TCPParser.Undefine }
procedure TCPParser.Undefine(const AName: string);
begin
  FDefines.Remove(AName);
end;

{ TCPParser.IsDefined }
function TCPParser.IsDefined(const AName: string): Boolean;
begin
  Result := FDefines.ContainsKey(AName);
end;

{ TCPParser.DoProcessConditionals }
procedure TCPParser.DoProcessConditionals();
var
  LTok: TCPToken;
  LDirName: string;
  LSymbol: string;
  LState: TCPCondState;
  LActive: Boolean;
begin
  while Current().Kind = tkDirective do
  begin
    LTok := Current();
    LDirName := LTok.TokenText;

    // @define SYMBOL
    if LDirName = 'define' then
    begin
      FLexer.NextToken(); // consume @define
      if Current().Kind = tkIdentifier then
      begin
        SetDefine(Current().TokenText, '1');
        FLexer.NextToken(); // consume symbol
      end
      else
        FErrors.Add(LTok.Location, esError, CP_ERR_PAR_020,
          '@define requires an identifier argument');
    end

    // @undef SYMBOL
    else if LDirName = 'undef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        Undefine(Current().TokenText);
        FLexer.NextToken();
      end
      else
        FErrors.Add(LTok.Location, esError, CP_ERR_PAR_020,
          '@undef requires an identifier argument');
    end

    // @ifdef SYMBOL
    else if LDirName = 'ifdef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        LSymbol := Current().TokenText;
        FLexer.NextToken();
      end
      else
      begin
        FErrors.Add(LTok.Location, esError, CP_ERR_PAR_020,
          '@ifdef requires an identifier argument');
        LSymbol := '';
      end;
      LActive := IsDefined(LSymbol);
      LState := Default(TCPCondState);
      LState.Active := LActive;
      LState.HadTrue := LActive;
      LState.HadElse := False;
      LState.ParentActive := True;
      FCondStack.Add(LState);
      if not LActive then
        DoSkipFalseBranch();
    end

    // @ifndef SYMBOL
    else if LDirName = 'ifndef' then
    begin
      FLexer.NextToken();
      if Current().Kind = tkIdentifier then
      begin
        LSymbol := Current().TokenText;
        FLexer.NextToken();
      end
      else
      begin
        FErrors.Add(LTok.Location, esError, CP_ERR_PAR_020,
          '@ifndef requires an identifier argument');
        LSymbol := '';
      end;
      LActive := not IsDefined(LSymbol);
      LState := Default(TCPCondState);
      LState.Active := LActive;
      LState.HadTrue := LActive;
      LState.HadElse := False;
      LState.ParentActive := True;
      FCondStack.Add(LState);
      if not LActive then
        DoSkipFalseBranch();
    end

    // @elseif SYMBOL
    else if LDirName = 'elseif' then
    begin
      if FCondStack.Count = 0 then
      begin
        FErrors.Add(LTok.Location, esError, CP_ERR_PAR_021,
          '@elseif without matching @ifdef');
        FLexer.NextToken();
      end
      else
      begin
        // We were in a true branch that just ended -- skip until @endif
        LState := FCondStack[FCondStack.Count - 1];
        LState.HadTrue := True;
        FCondStack[FCondStack.Count - 1] := LState;
        DoSkipFalseBranch();
      end;
    end

    // @else
    else if LDirName = 'else' then
    begin
      if FCondStack.Count = 0 then
      begin
        FErrors.Add(LTok.Location, esError, CP_ERR_PAR_021,
          '@else without matching @ifdef');
        FLexer.NextToken();
      end
      else
      begin
        // We were in a true branch that just ended -- skip until @endif
        LState := FCondStack[FCondStack.Count - 1];
        LState.HadTrue := True;
        LState.HadElse := True;
        FCondStack[FCondStack.Count - 1] := LState;
        DoSkipFalseBranch();
      end;
    end

    // @endif
    else if LDirName = 'endif' then
    begin
      if FCondStack.Count = 0 then
        FErrors.Add(LTok.Location, esError, CP_ERR_PAR_021,
          '@endif without matching @ifdef')
      else
        FCondStack.Delete(FCondStack.Count - 1);
      FLexer.NextToken();
    end

    // Not a conditional directive -- stop processing, let parser handle it
    else
      Break;
  end;
end;

{ TCPParser.DoSkipFalseBranch }
procedure TCPParser.DoSkipFalseBranch();
var
  LDepth: Integer;
  LDirName: string;
  LState: TCPCondState;
  LSymbol: string;
begin
  // Skip tokens until we find a matching @else/@elseif/@endif at depth 0
  LDepth := 0;
  while Current().Kind <> tkEOF do
  begin
    if Current().Kind = tkDirective then
    begin
      LDirName := Current().TokenText;

      // Nested @ifdef/@ifndef increase depth
      if (LDirName = 'ifdef') or (LDirName = 'ifndef') then
      begin
        Inc(LDepth);
        FLexer.NextToken();
        // Skip the symbol argument too
        if Current().Kind = tkIdentifier then
          FLexer.NextToken();
        Continue;
      end;

      // @endif at our level means the conditional block is done
      if LDirName = 'endif' then
      begin
        if LDepth > 0 then
        begin
          Dec(LDepth);
          FLexer.NextToken();
          Continue;
        end;
        // Our @endif -- pop the stack and advance past it
        if FCondStack.Count > 0 then
          FCondStack.Delete(FCondStack.Count - 1);
        FLexer.NextToken();
        Exit;
      end;

      // @else at our level -- check if we should start emitting
      if (LDirName = 'else') and (LDepth = 0) then
      begin
        if FCondStack.Count > 0 then
        begin
          LState := FCondStack[FCondStack.Count - 1];
          if not LState.HadTrue then
          begin
            // This @else branch is active
            LState.Active := True;
            LState.HadTrue := True;
            LState.HadElse := True;
            FCondStack[FCondStack.Count - 1] := LState;
            FLexer.NextToken();
            Exit;
          end;
        end;
        FLexer.NextToken();
        Continue;
      end;

      // @elseif at our level -- evaluate the condition
      if (LDirName = 'elseif') and (LDepth = 0) then
      begin
        FLexer.NextToken(); // consume @elseif
        LSymbol := '';
        if Current().Kind = tkIdentifier then
        begin
          LSymbol := Current().TokenText;
          FLexer.NextToken();
        end;
        if FCondStack.Count > 0 then
        begin
          LState := FCondStack[FCondStack.Count - 1];
          if (not LState.HadTrue) and IsDefined(LSymbol) then
          begin
            // This @elseif branch is active
            LState.Active := True;
            LState.HadTrue := True;
            FCondStack[FCondStack.Count - 1] := LState;
            Exit;
          end;
        end;
        Continue;
      end;
    end;

    // Non-conditional token in false branch -- skip it
    FLexer.NextToken();
  end;

  // Reached EOF without @endif
  if FCondStack.Count > 0 then
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_022,
      'Unterminated @ifdef/@ifndef block');
end;

{ TCPParser.DoSetupPredefinedDefines }
procedure TCPParser.DoSetupPredefinedDefines(const AModuleKind: TCPModuleKind);
begin
  // Always defined
  SetDefine('CPASKAL', '1');
  SetDefine('CPUX64', '1');

  // Module kind
  Undefine('BUILD_EXE');
  Undefine('BUILD_DLL');
  Undefine('BUILD_LIB');
  if AModuleKind = mkExe then
    SetDefine('BUILD_EXE', '1')
  else if AModuleKind = mkDll then
    SetDefine('BUILD_DLL', '1')
  else if AModuleKind = mkLib then
    SetDefine('BUILD_LIB', '1');

  // App type -- always console for now
  SetDefine('APPTYPE_CONSOLE', '1');
end;

// -- Module structure -------------------------------------------------------

function TCPParser.ParseModule(const AFilename: string; const AMasterAST: TCPMasterAST): TCPModuleNode;
var
  LModule: TCPModuleNode;
  LNormalized: string;
begin
  Result := nil;
  FMasterAST := AMasterAST;

  // Normalize filename with .cpas extension
  LNormalized := TPath.ChangeExtension(AFilename, CP_SRC_EXT);

  // Tokenize the source file
  if not FLexer.TokenizeFile(LNormalized) then
    Exit;

  // Prime conditional processing for the first token position
  DoProcessConditionals();

  // Create module node -- try/finally ensures cleanup on any failure path
  LModule := TCPModuleNode.Create();
  try
    LModule.Location := Current().Location;
    LModule.SourceFile := LNormalized;

    // module ModuleKind name;
    Expect(tkModule);
    LModule.ModuleKind := DoParseModuleKind();

    // Set up predefined defines now that module kind is known
    DoSetupPredefinedDefines(LModule.ModuleKind);

    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
        'Expected module name identifier');
      Exit;
    end;
    LModule.ModuleName := Consume().TokenText;

    // Expect semicolon but advance without DoProcessConditionals so that
    // any @ifdef block in the directive section is left for DoParseDirectives
    if Current().Kind = tkSemicolon then
      FLexer.NextToken()
    else
      FLexer.Expect(tkSemicolon);

    // Directives, imports, declarations
    DoParseDirectives(LModule);
    DoParseImportClause(LModule);
    DoParseDeclarations(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Optional initialize/finalize blocks
    DoParseInitializeBlock(LModule);
    DoParseFinalizeBlock(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Main body: begin...end.
    DoParseMainBody(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Test blocks after end.
    DoParseTestBlocks(LModule);

    if FErrors.HasErrors() then
      Exit;

    // Success -- transfer ownership to caller
    Result := LModule;
    LModule := nil;
  finally
    LModule.Free();
  end;
end;

function TCPParser.DoParseModuleKind(): TCPModuleKind;
var
  LText: string;
begin
  // Module kind is a contextual keyword -- exe, dll, lib, unit are identifiers
  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_003,
      'Expected module kind (exe, dll, lib, unit)');
    Result := mkExe;
    Exit;
  end;

  LText := Current().TokenText;
  if LText = 'exe' then
    Result := mkExe
  else if LText = 'dll' then
    Result := mkDll
  else if LText = 'lib' then
    Result := mkLib
  else if LText = 'unit' then
    Result := mkUnit
  else
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_003,
      'Invalid module kind: %s (expected exe, dll, lib, unit)', [LText]);
    Result := mkExe;
  end;
  Consume();
end;

procedure TCPParser.DoParseDirectives(const AModule: TCPModuleNode);
var
  LDirective: TCPDirectiveNode;
  LName: string;
begin
  // Directives start with @ (tkDirective)
  while Current().Kind = tkDirective do
  begin
    LName := Current().TokenText;

    // Conditional compilation directives are handled by DoProcessConditionals,
    // which manages the condition stack and skips inactive branches.
    if LName.StartsWith('define') or LName.StartsWith('undef') or
       LName.StartsWith('ifdef') or LName.StartsWith('ifndef') or
       LName.StartsWith('elseif') or
       (LName = 'else') or (LName = 'endif') then
    begin
      DoProcessConditionals();
      Continue;
    end;

    // Content directive (copydll, librarypath, target, etc.)
    LDirective := TCPDirectiveNode.Create();
    LDirective.Location := Current().Location;
    LDirective.DirectiveName := LName;
    Consume();

    // Directive value: string, integer, float, or identifier
    if (Current().Kind = tkStringLiteral) or
       (Current().Kind = tkIntLiteral) or
       (Current().Kind = tkFloatLiteral) or
       (Current().Kind = tkIdentifier) then
    begin
      LDirective.DirectiveValue := Current().TokenText;
      Consume();

      // Second value for @message: severity followed by text
      if (LDirective.DirectiveName = 'message') and
         (Current().Kind = tkStringLiteral) then
      begin
        LDirective.DirectiveValue2 := Current().TokenText;
        Consume();
      end;
    end;

    Expect(tkSemicolon);
    AModule.Directives.Add(LDirective);
  end;
end;

procedure TCPParser.DoParseImportClause(const AModule: TCPModuleNode);
var
  LImport: TCPImportNode;
  LName: string;
begin
  if not Match(tkImport) then
    Exit;

  // import name1, name2, name3;
  repeat
    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
        'Expected module name in import clause');
      Exit;
    end;

    LName := Current().TokenText;

    LImport := TCPImportNode.Create();
    LImport.Location := Current().Location;
    LImport.ModuleName := LName;
    AModule.Imports.Add(LImport);

    // Enqueue for parsing if not already on the master AST
    if Assigned(FMasterAST) and not FMasterAST.HasModule(LName) then
      FMasterAST.EnqueuePending(LName);

    Consume();
  until not Match(tkComma);

  Expect(tkSemicolon);
end;

procedure TCPParser.DoParseDeclarations(const AModule: TCPModuleNode);
var
  LIsPublic: Boolean;
begin
  // Parse declarations until we hit initialize, finalize, begin, or EOF
  while not (Check(tkInitialize) or Check(tkFinalize) or Check(tkBegin) or
             Check(tkEnd) or Check(tkEOF)) do
  begin
    // Check for public modifier
    LIsPublic := Match(tkPublic);

    if Check(tkConst) then
    begin
      Consume();
      // Parse multiple const declarations in the section
      // Note: public followed by a section keyword (const/type/var/routine)
      // starts a new section -- don't consume it here
      while (Current().Kind = tkIdentifier) or
            ((Current().Kind = tkPublic) and (PeekAt(1).Kind = tkIdentifier)) do
      begin
        if Current().Kind = tkPublic then
        begin
          Consume();
          AModule.Declarations.Add(DoParseConstDecl(True));
        end
        else
          AModule.Declarations.Add(DoParseConstDecl(LIsPublic));
      end;
    end
    else if Check(tkType) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) or
            ((Current().Kind = tkPublic) and (PeekAt(1).Kind = tkIdentifier)) do
      begin
        if Current().Kind = tkPublic then
        begin
          Consume();
          AModule.Declarations.Add(DoParseTypeDecl(True));
        end
        else
          AModule.Declarations.Add(DoParseTypeDecl(LIsPublic));
      end;
    end
    else if Check(tkVar) then
    begin
      Consume();
      while (Current().Kind = tkIdentifier) or
            ((Current().Kind = tkPublic) and (PeekAt(1).Kind = tkIdentifier)) do
      begin
        if Current().Kind = tkPublic then
        begin
          Consume();
          AModule.Declarations.Add(DoParseVarDecl(True));
        end
        else
          AModule.Declarations.Add(DoParseVarDecl(LIsPublic));
      end;
    end
    else if Check(tkRoutine) then
    begin
      AModule.Declarations.Add(DoParseRoutineDecl(LIsPublic));
    end
    else if Check(tkForward) then
    begin
      AModule.Declarations.Add(DoParseForwardDecl());
    end
    else if Check(tkCppStart) then
    begin
      AModule.Declarations.Add(DoParseCppBlock());
    end
    else if Current().Kind = tkDirective then
    begin
      // Statement-level directives within declarations
      DoParseDirectives(AModule);
    end
    else
    begin
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_001,
        'Unexpected token in declarations: %s', [Current().TokenText]);
      Consume();  // skip to avoid infinite loop
    end;

    // Bail on error -- everything after is unreliable
    if FErrors.HasErrors() then
      Break;
  end;
end;

procedure TCPParser.DoParseInitializeBlock(const AModule: TCPModuleNode);
var
  LBody: TObjectList<TCPASTNode>;
begin
  if not Match(tkInitialize) then
    Exit;

  LBody := DoParseStatementSeq([tkEnd]);
  AModule.InitBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  Expect(tkEnd);
  Expect(tkSemicolon);
end;

procedure TCPParser.DoParseFinalizeBlock(const AModule: TCPModuleNode);
var
  LBody: TObjectList<TCPASTNode>;
begin
  if not Match(tkFinalize) then
    Exit;

  LBody := DoParseStatementSeq([tkEnd]);
  AModule.FinalBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  Expect(tkEnd);
  Expect(tkSemicolon);
end;

procedure TCPParser.DoParseMainBody(const AModule: TCPModuleNode);
var
  LBody: TObjectList<TCPASTNode>;
begin
  // Unit modules have no begin block -- just end.
  if not Check(tkBegin) then
  begin
    Expect(tkEnd);
    Expect(tkDot);
    Exit;
  end;

  AModule.HasMainBody := True;
  Consume(); // consume 'begin'

  LBody := DoParseStatementSeq([tkEnd]);
  AModule.MainBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  Expect(tkEnd);
  Expect(tkDot);
end;

procedure TCPParser.DoParseTestBlocks(const AModule: TCPModuleNode);
var
  LTest: TCPTestBlockNode;
  LBody: TObjectList<TCPASTNode>;
begin
  while Check(tkTest) do
  begin
    LTest := TCPTestBlockNode.Create();
    LTest.Location := Current().Location;
    Consume();

    // test "name"
    if Current().Kind <> tkStringLiteral then
    begin
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_002,
        'Expected string literal for test name');
      LTest.Free();
      Exit;
    end;
    LTest.TestName := Current().LiteralValue.AsString();
    Consume();

    // Optional var section
    if Match(tkVar) then
    begin
      while Current().Kind = tkIdentifier do
        LTest.Locals.Add(DoParseVarDecl(False));
    end;

    // begin...end;
    Expect(tkBegin);
    LBody := DoParseStatementSeq([tkEnd]);
    LTest.Body.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();
    Expect(tkEnd);
    Expect(tkSemicolon);

    AModule.TestBlocks.Add(LTest);
  end;
end;

// -- Declarations -----------------------------------------------------------

function TCPParser.DoParseConstDecl(const AIsPublic: Boolean): TCPConstDeclNode;
begin
  Result := TCPConstDeclNode.Create();
  Result.Location := Current().Location;
  Result.IsPublic := AIsPublic;

  // name [: type] = value;
  Result.DeclName := Current().TokenText;
  Consume();

  // Optional type annotation
  if Match(tkColon) then
    Result.TypeExpr := DoParseTypeExpr();

  Expect(tkEqual);
  Result.ValueExpr := DoParseExpression();
  Expect(tkSemicolon);
end;

function TCPParser.DoParseTypeDecl(const AIsPublic: Boolean): TCPTypeDeclNode;
begin
  Result := TCPTypeDeclNode.Create();
  Result.Location := Current().Location;
  Result.IsPublic := AIsPublic;

  // name = typedef;
  Result.DeclName := Current().TokenText;
  Consume();

  Expect(tkEqual);
  Result.TypeDef := DoParseTypeDef();
  Expect(tkSemicolon);
end;

function TCPParser.DoParseVarDecl(const AIsPublic: Boolean): TCPVarDeclNode;
begin
  Result := TCPVarDeclNode.Create();
  Result.Location := Current().Location;
  Result.IsPublic := AIsPublic;

  // name: type [= value]; [external lib;]
  Result.DeclName := Current().TokenText;
  Consume();

  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();

  // Optional initializer
  if Match(tkEqual) then
    Result.InitExpr := DoParseExpression();

  Expect(tkSemicolon);

  // Optional external clause
  if Match(tkExternal) then
  begin
    Result.IsExternal := True;
    // Optional library: string literal or identifier (but not "name" followed by string)
    if Current().Kind = tkStringLiteral then
    begin
      Result.ExternalLib := Current().TokenText;
      Consume();
    end
    else if (Current().Kind = tkIdentifier) and
            not ((Current().TokenText = 'name') and (PeekAt(1).Kind = tkStringLiteral)) then
    begin
      Result.ExternalLib := Current().TokenText;
      Consume();
    end;
    // Optional name clause: name "symbol"
    if (Current().Kind = tkIdentifier) and (Current().TokenText = 'name') then
    begin
      Consume();
      if Current().Kind = tkStringLiteral then
      begin
        Result.ExternalName := Current().TokenText;
        Consume();
      end
      else
        FErrors.Add(Current().Location, esError, CP_ERR_PAR_002,
          'Expected string literal after "name"');
    end;
    Expect(tkSemicolon);
  end;
end;

function TCPParser.DoParseRoutineDecl(const AIsPublic: Boolean): TCPRoutineDeclNode;
begin
  Result := TCPRoutineDeclNode.Create();
  Result.Location := Current().Location;
  Result.IsPublic := AIsPublic;

  // routine [linkage] name(params) [: returntype];
  Expect(tkRoutine);

  // Optional linkage spec
  if Check(tkCLink) then
  begin
    Result.Linkage := lkCLink;
    Consume();
  end
  else if Check(tkCppLink) then
  begin
    Result.Linkage := lkCppLink;
    Consume();
  end;

  // Routine name
  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
      'Expected routine name');
    Result.Free();
    Result := nil;
    Exit;
  end;
  Result.DeclName := Current().TokenText;
  Consume();

  // Optional formal parameters
  if Check(tkLParen) then
    DoParseFormalParams(Result);

  // Optional return type
  if Match(tkColon) then
    Result.ReturnType := DoParseTypeExpr();

  Expect(tkSemicolon);

  // External clause or body
  if Match(tkExternal) then
  begin
    Result.IsExternal := True;
    // Optional library: string literal or identifier (but not "name" followed by string)
    if Current().Kind = tkStringLiteral then
    begin
      Result.ExternalLib := Current().TokenText;
      Consume();
    end
    else if (Current().Kind = tkIdentifier) and
            not ((Current().TokenText = 'name') and (PeekAt(1).Kind = tkStringLiteral)) then
    begin
      Result.ExternalLib := Current().TokenText;
      Consume();
    end;
    // Optional name clause: name "symbol"
    if (Current().Kind = tkIdentifier) and (Current().TokenText = 'name') then
    begin
      Consume();
      if Current().Kind = tkStringLiteral then
      begin
        Result.ExternalName := Current().TokenText;
        Consume();
      end
      else
        FErrors.Add(Current().Location, esError, CP_ERR_PAR_002,
          'Expected string literal after "name"');
    end;
    Expect(tkSemicolon);
  end
  else
    DoParseRoutineBody(Result);
end;

function TCPParser.DoParseForwardDecl(): TCPASTNode;
var
  LForwardType: TCPForwardTypeDeclNode;
  LForwardRoutine: TCPForwardRoutineDeclNode;
begin
  Result := nil;
  Expect(tkForward);

  if Check(tkType) then
  begin
    // forward type TFoo;
    Consume();
    LForwardType := TCPForwardTypeDeclNode.Create();
    LForwardType.Location := Current().Location;

    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
        'Expected type name after forward type');
      LForwardType.Free();
      Exit;
    end;
    LForwardType.DeclName := Current().TokenText;
    Consume();
    Expect(tkSemicolon);
    Result := LForwardType;
  end
  else if Check(tkRoutine) then
  begin
    // forward routine Foo(params): ReturnType;
    Consume();
    LForwardRoutine := TCPForwardRoutineDeclNode.Create();
    LForwardRoutine.Location := Current().Location;

    // Optional linkage spec
    if Check(tkCLink) then
    begin
      LForwardRoutine.Linkage := lkCLink;
      Consume();
    end
    else if Check(tkCppLink) then
    begin
      LForwardRoutine.Linkage := lkCppLink;
      Consume();
    end;

    // Routine name
    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
        'Expected routine name after forward routine');
      LForwardRoutine.Free();
      Exit;
    end;
    LForwardRoutine.DeclName := Current().TokenText;
    Consume();

    // Optional formal parameters
    if Check(tkLParen) then
    begin
      Expect(tkLParen);

      if not Check(tkRParen) then
      begin
        // Lone ellipsis
        if Check(tkEllipsis) then
        begin
          LForwardRoutine.IsVariadic := True;
          Consume();
        end
        else
        begin
          LForwardRoutine.Params.Add(DoParseParamDecl());
          while Match(tkSemicolon) do
          begin
            if Check(tkEllipsis) then
            begin
              LForwardRoutine.IsVariadic := True;
              Consume();
              Break;
            end;
            LForwardRoutine.Params.Add(DoParseParamDecl());
          end;
        end;
      end;

      Expect(tkRParen);
    end;

    // Optional return type
    if Match(tkColon) then
      LForwardRoutine.ReturnType := DoParseTypeExpr();

    Expect(tkSemicolon);
    Result := LForwardRoutine;
  end
  else
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_001,
      'Expected "type" or "routine" after "forward"');
  end;
end;

procedure TCPParser.DoParseFormalParams(const ARoutine: TCPRoutineDeclNode);
begin
  Expect(tkLParen);

  // Empty params
  if Check(tkRParen) then
  begin
    Consume();
    Exit;
  end;

  // Lone ellipsis: routine foo(...);
  if Check(tkEllipsis) then
  begin
    ARoutine.IsVariadic := True;
    Consume();
    Expect(tkRParen);
    Exit;
  end;

  // Parse parameter declarations
  ARoutine.Params.Add(DoParseParamDecl());
  while Match(tkSemicolon) do
  begin
    // Check for trailing ellipsis: routine foo(a: int32; ...);
    if Check(tkEllipsis) then
    begin
      ARoutine.IsVariadic := True;
      Consume();
      Break;
    end;
    ARoutine.Params.Add(DoParseParamDecl());
  end;

  Expect(tkRParen);
end;

function TCPParser.DoParseParamDecl(): TCPParamDeclNode;
begin
  Result := TCPParamDeclNode.Create();
  Result.Location := Current().Location;

  // [var | const] name: type
  if Match(tkVar) then
    Result.ParamMode := pmVar
  else if Match(tkConst) then
    Result.ParamMode := pmConst
  else
    Result.ParamMode := pmDefault;

  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
      'Expected parameter name');
    Result.Free();
    Result := nil;
    Exit;
  end;
  Result.ParamName := Current().TokenText;
  Consume();

  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();
end;

procedure TCPParser.DoParseRoutineBody(const ARoutine: TCPRoutineDeclNode);
var
  LBody: TObjectList<TCPASTNode>;
begin
  // Optional local type/const/var sections
  if Match(tkType) then
  begin
    while Current().Kind = tkIdentifier do
      ARoutine.LocalTypes.Add(DoParseTypeDecl(False));
  end;

  if Match(tkConst) then
  begin
    while Current().Kind = tkIdentifier do
      ARoutine.LocalConsts.Add(DoParseConstDecl(False));
  end;

  if Match(tkVar) then
  begin
    while Current().Kind = tkIdentifier do
      ARoutine.LocalVars.Add(DoParseVarDecl(False));
  end;

  // begin...end;
  Expect(tkBegin);
  LBody := DoParseStatementSeq([tkEnd]);
  ARoutine.Body.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();
  Expect(tkEnd);
  Expect(tkSemicolon);
end;

// -- Type definitions -------------------------------------------------------

function TCPParser.DoParseTypeDef(): TCPASTNode;
begin
  if Check(tkRecord) then
    Result := DoParseRecordType()
  else if Check(tkOverlay) then
    Result := DoParseOverlayType()
  else if Check(tkArray) then
    Result := DoParseArrayType()
  else if Check(tkPointer) then
    Result := DoParsePointerType()
  else if Check(tkSet) then
    Result := DoParseSetType()
  else if Check(tkChoices) then
    Result := DoParseChoicesType()
  else if Check(tkRoutine) then
    Result := DoParseRoutineTypeDef()
  else
    Result := DoParseTypeExpr();
end;

function TCPParser.DoParseRecordType(): TCPRecordTypeNode;
var
  LAnon: TCPAnonOverlayNode;
begin
  Result := TCPRecordTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'record'

  // Optional packed
  if Match(tkPacked) then
    Result.IsPacked := True;

  // Optional align(n)
  if Match(tkAlign) then
  begin
    Expect(tkLParen);
    if Current().Kind = tkIntLiteral then
    begin
      Result.Alignment := StrToIntDef(Current().TokenText, 0);
      Consume();
    end;
    Expect(tkRParen);
  end;

  // Optional base type: record(BaseType)
  if Match(tkLParen) then
  begin
    Result.BaseType := DoParseTypeExpr();
    Expect(tkRParen);
  end;

  // Fields and anonymous overlays until 'end'
  while not (Check(tkEnd) or Check(tkEOF)) do
  begin
    if Check(tkOverlay) then
    begin
      LAnon := TCPAnonOverlayNode.Create();
      LAnon.Location := Current().Location;
      Consume();  // consume 'overlay'
      while not (Check(tkEnd) or Check(tkEOF)) do
      begin
        if Check(tkRecord) then
        begin
          // Nested anonymous record inside anonymous overlay
          LAnon.Fields.Add(DoParseRecordType());
          Expect(tkSemicolon);
        end
        else
          LAnon.Fields.Add(DoParseFieldDecl());

        if FErrors.HasErrors() then
          Break;
      end;
      Expect(tkEnd);
      Expect(tkSemicolon);
      Result.Fields.Add(LAnon);
    end
    else
      Result.Fields.Add(DoParseFieldDecl());

    if FErrors.HasErrors() then
      Break;
  end;

  Expect(tkEnd);
end;

function TCPParser.DoParseOverlayType(): TCPOverlayTypeNode;
var
  LAnon: TCPAnonRecordNode;
begin
  Result := TCPOverlayTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'overlay'

  while not (Check(tkEnd) or Check(tkEOF)) do
  begin
    if Check(tkRecord) then
    begin
      LAnon := TCPAnonRecordNode.Create();
      LAnon.Location := Current().Location;
      Consume();  // consume 'record'
      if Match(tkPacked) then
        LAnon.IsPacked := True;
      while not (Check(tkEnd) or Check(tkEOF)) do
      begin
        LAnon.Fields.Add(DoParseFieldDecl());
        if FErrors.HasErrors() then
          Break;
      end;
      Expect(tkEnd);
      Expect(tkSemicolon);
      Result.Fields.Add(LAnon);
    end
    else
      Result.Fields.Add(DoParseFieldDecl());

    if FErrors.HasErrors() then
      Break;
  end;

  Expect(tkEnd);
end;

function TCPParser.DoParseFieldDecl(): TCPFieldDeclNode;
begin
  Result := TCPFieldDeclNode.Create();
  Result.Location := Current().Location;

  // name: type [: bitwidth];
  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
      'Expected field name');
    Result.Free();
    Result := nil;
    Exit;
  end;
  Result.FieldName := Current().TokenText;
  Consume();

  Expect(tkColon);
  Result.TypeExpr := DoParseTypeExpr();

  // Optional bit width
  if Match(tkColon) then
  begin
    if Current().Kind = tkIntLiteral then
    begin
      Result.BitWidth := StrToIntDef(Current().TokenText, 0);
      Consume();
    end;
  end;

  Expect(tkSemicolon);
end;

function TCPParser.DoParseArrayType(): TCPArrayTypeNode;
begin
  Result := TCPArrayTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'array'

  // Optional bounds: [low..high]
  if Match(tkLBracket) then
  begin
    if Check(tkRBracket) then
    begin
      // Dynamic array: array[] of type
      Result.IsDynamic := True;
    end
    else
    begin
      // Static array: array[low..high] of type
      Result.IsDynamic := False;
      if Current().Kind = tkIntLiteral then
      begin
        Result.LowBound := StrToInt64Def(Current().TokenText, 0);
        Consume();
      end;
      Expect(tkDotDot);
      if Current().Kind = tkIntLiteral then
      begin
        Result.HighBound := StrToInt64Def(Current().TokenText, 0);
        Consume();
      end;
    end;
    Expect(tkRBracket);
  end
  else
    Result.IsDynamic := True;  // array of type (no brackets)

  Expect(tkOf);
  Result.ElementType := DoParseTypeExpr();
end;

function TCPParser.DoParsePointerType(): TCPPointerTypeNode;
begin
  Result := TCPPointerTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'pointer'

  // Optional: pointer to [const] type
  if Current().Kind = tkTo then
  begin
    Consume();
    if Match(tkConst) then
      Result.IsConstTarget := True;
    Result.TargetType := DoParseTypeExpr();
  end;
end;

function TCPParser.DoParseSetType(): TCPSetTypeNode;
begin
  Result := TCPSetTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'set'

  // Optional: set of (range | type)
  if Match(tkOf) then
  begin
    // Check if it's integer..integer range form
    if (Current().Kind = tkIntLiteral) and (PeekAt(1).Kind = tkDotDot) then
    begin
      Result.IsRangeForm := True;
      Result.RangeLow := StrToInt64Def(Current().TokenText, 0);
      Consume();
      Expect(tkDotDot);
      Result.RangeHigh := StrToInt64Def(Current().TokenText, 0);
      Consume();
    end
    else
      Result.ElementType := DoParseTypeExpr();
  end;
end;

function TCPParser.DoParseChoicesType(): TCPChoicesTypeNode;
var
  LValue: TCPChoicesValueNode;
begin
  Result := TCPChoicesTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'choices'

  Expect(tkLParen);

  repeat
    LValue := TCPChoicesValueNode.Create();
    LValue.Location := Current().Location;

    if Current().Kind <> tkIdentifier then
    begin
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
        'Expected choices member name');
      LValue.Free();
      Break;
    end;
    LValue.MemberName := Current().TokenText;
    Consume();

    // Optional explicit value: = expr
    if Match(tkEqual) then
      LValue.ValueExpr := DoParseExpression();

    Result.Members.Add(LValue);
  until not Match(tkComma);

  Expect(tkRParen);
end;

function TCPParser.DoParseRoutineTypeDef(): TCPRoutineTypeNode;
begin
  Result := TCPRoutineTypeNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'routine'

  // Optional linkage
  if Check(tkCLink) then
  begin
    Result.Linkage := lkCLink;
    Consume();
  end
  else if Check(tkCppLink) then
  begin
    Result.Linkage := lkCppLink;
    Consume();
  end;

  // Parameters
  Expect(tkLParen);
  if not Check(tkRParen) then
  begin
    // Check for lone ellipsis
    if Check(tkEllipsis) then
    begin
      Result.IsVariadic := True;
      Consume();
    end
    else
    begin
      Result.Params.Add(DoParseParamDecl());
      while Match(tkSemicolon) do
      begin
        if Check(tkEllipsis) then
        begin
          Result.IsVariadic := True;
          Consume();
          Break;
        end;
        Result.Params.Add(DoParseParamDecl());
      end;
    end;
  end;
  Expect(tkRParen);

  // Optional return type
  if Match(tkColon) then
    Result.ReturnType := DoParseTypeExpr();
end;

function TCPParser.DoParseTypeExpr(): TCPASTNode;
var
  LRef: TCPTypeRefNode;
  LParts: TList<string>;
begin
  // Inline type expressions: pointer, array, set, or named type reference
  // Bare 'pointer' is a primitive (void*); 'pointer to T' is a typed pointer
  if Check(tkPointer) and (PeekAt(1).Kind = tkTo) then
  begin
    Result := DoParsePointerType();
    Exit;
  end;

  if Check(tkArray) then
  begin
    Result := DoParseArrayType();
    Exit;
  end;

  if Check(tkSet) then
  begin
    Result := DoParseSetType();
    Exit;
  end;

  // Primitive type keyword or qualified identifier
  LRef := TCPTypeRefNode.Create();
  LRef.Location := Current().Location;

  if FLexer.IsDataType(Current().Kind) then
  begin
    // Primitive type: int32, float64, string, etc.
    LRef.TokenKind := Current().Kind;
    LRef.CppTypeText := FLexer.GetCppType(Current().Kind);
    LRef.QualParts := [Current().TokenText];
    Consume();
  end
  else if Current().Kind = tkIdentifier then
  begin
    // User type, possibly qualified: ModName.TypeName
    LRef.TokenKind := tkIdentifier;
    LParts := TList<string>.Create();
    try
      LParts.Add(Current().TokenText);
      Consume();
      while Match(tkDot) do
      begin
        if Current().Kind <> tkIdentifier then
        begin
          FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
            'Expected identifier after "."');
          Break;
        end;
        LParts.Add(Current().TokenText);
        Consume();
      end;
      LRef.QualParts := LParts.ToArray();
    finally
      LParts.Free();
    end;
  end
  else
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_005,
      'Expected type expression, got: %s', [Current().TokenText]);
    LRef.Free();
    Result := nil;
    Exit;
  end;

  Result := LRef;
end;

// -- Statements -------------------------------------------------------------

function TCPParser.DoParseStatementSeq(const ATerminators: array of TCPTokenKind): TObjectList<TCPASTNode>;
var
  LStmt: TCPASTNode;
  LKind: TCPTokenKind;
  LIsTerminator: Boolean;
begin
  Result := TObjectList<TCPASTNode>.Create(True);

  while not Check(tkEOF) do
  begin
    // Check if current token is a terminator
    LIsTerminator := False;
    for LKind in ATerminators do
    begin
      if Check(LKind) then
      begin
        LIsTerminator := True;
        Break;
      end;
    end;
    if LIsTerminator then
      Break;

    // Skip lone semicolons
    if Match(tkSemicolon) then
      Continue;

    LStmt := DoParseStatement();
    if Assigned(LStmt) then
      Result.Add(LStmt);

    // Bail on error -- everything after is unreliable
    if FErrors.HasErrors() then
      Break;
  end;
end;

function TCPParser.DoParseStatement(): TCPASTNode;
begin
  Result := nil;

  if Check(tkIf) then
    Result := DoParseIfStmt()
  else if Check(tkWhile) then
    Result := DoParseWhileStmt()
  else if Check(tkFor) then
    Result := DoParseForStmt()
  else if Check(tkRepeat) then
    Result := DoParseRepeatStmt()
  else if Check(tkMatch) then
    Result := DoParseMatchStmt()
  else if Check(tkReturn) then
    Result := DoParseReturnStmt()
  else if Check(tkGuard) then
    Result := DoParseGuardStmt()
  else if Check(tkThrow) or Check(tkThrowCode) then
    Result := DoParseThrowStmt()
  else if Check(tkBreak) then
  begin
    Result := TCPBreakNode.Create();
    Result.Location := Current().Location;
    Consume();
    OptionalSemicolon();
  end
  else if Check(tkContinue) then
  begin
    Result := TCPContinueNode.Create();
    Result.Location := Current().Location;
    Consume();
    OptionalSemicolon();
  end
  else if Check(tkNew) then
    Result := DoParseNewStmt()
  else if Check(tkDispose) then
    Result := DoParseDisposeStmt()
  else if Check(tkGetMem) then
    Result := DoParseGetMemStmt()
  else if Check(tkFreeMem) then
    Result := DoParseFreeMemStmt()
  else if Check(tkResizeMem) then
    Result := DoParseResizeMemStmt()
  else if Check(tkSetLength) then
    Result := DoParseSetLengthStmt()
  else if Check(tkPrint) or Check(tkPrintLn) then
    Result := DoParsePrintStmt()
  else if Check(tkAssert) or Check(tkAssertTrue) or Check(tkAssertFalse) or
          Check(tkAssertEq) or Check(tkAssertEqF) or Check(tkAssertNil) or
          Check(tkAssertNotNil) or Check(tkAssertFail) then
    Result := DoParseAssertStmt()
  else if Check(tkCppStart) then
    Result := DoParseCppBlock()
  else if Check(tkCpp) then
    Result := DoParseCppStmt()
  else if Check(tkDirective) then
  begin
    // Statement-level directive (@breakpoint, @message)
    Result := TCPDirectiveNode.Create();
    Result.Location := Current().Location;
    TCPDirectiveNode(Result).DirectiveName := Current().TokenText;
    Consume();
    if (Current().Kind = tkIdentifier) or (Current().Kind = tkStringLiteral) then
    begin
      TCPDirectiveNode(Result).DirectiveValue := Current().TokenText;
      Consume();
      // @message has severity + string, consume the string too
      if Current().Kind = tkStringLiteral then
      begin
        TCPDirectiveNode(Result).DirectiveValue :=
          TCPDirectiveNode(Result).DirectiveValue + ' ' + Current().TokenText;
        Consume();
      end;
    end;
    OptionalSemicolon();
  end
  else if Check(tkVar) then
  begin
    // Inline var declaration in statement position
    Consume(); // consume 'var'
    Result := DoParseVarDecl(False);
  end
  else if Check(tkIdentifier) or Check(tkVarArgs) then
    Result := DoParseAssignOrCall()
  else
  begin
    if Check(tkDot) then
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_006,
        'Unexpected end of module -- likely a missing "end" for an if, while, for, match, or guard block')
    else
      FErrors.Add(Current().Location, esError, CP_ERR_PAR_006,
        'Unexpected token in statement: %s', [Current().TokenText]);
    Consume();
  end;
end;

function TCPParser.DoParseAssignOrCall(): TCPASTNode;
var
  LLeft: TCPASTNode;
  LAssign: TCPAssignNode;
  LCallStmt: TCPCallStmtNode;
begin
  // Parse the left side as an expression (designator chain)
  LLeft := DoParseExpression();

  // Check for assignment operator
  if IsAssignOp(Current().Kind) then
  begin
    LAssign := TCPAssignNode.Create();
    LAssign.Location := LLeft.Location;
    LAssign.Target := LLeft;
    LAssign.Op := TokenToAssignOp(Current().Kind);
    Consume();
    LAssign.ValueExpr := DoParseExpression();
    OptionalSemicolon();
    Result := LAssign;
  end
  else
  begin
    // Treat as call statement
    LCallStmt := TCPCallStmtNode.Create();
    LCallStmt.Location := LLeft.Location;
    LCallStmt.CallExpr := LLeft;
    OptionalSemicolon();
    Result := LCallStmt;
  end;
end;

function TCPParser.DoParseIfStmt(): TCPIfNode;
var
  LBody: TObjectList<TCPASTNode>;
begin
  Result := TCPIfNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'if'

  Result.Condition := DoParseExpression();
  Expect(tkThen);

  LBody := DoParseStatementSeq([tkElse, tkEnd]);
  Result.ThenBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  if Match(tkElse) then
  begin
    LBody := DoParseStatementSeq([tkEnd]);
    Result.ElseBody.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();
  end;

  ExpectBlockEnd('if', Result.Location);
  OptionalSemicolon();
end;

function TCPParser.DoParseWhileStmt(): TCPWhileNode;
var
  LBody: TObjectList<TCPASTNode>;
begin
  Result := TCPWhileNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'while'

  Result.Condition := DoParseExpression();
  Expect(tkDo);

  LBody := DoParseStatementSeq([tkEnd]);
  Result.Body.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  ExpectBlockEnd('while', Result.Location);
  OptionalSemicolon();
end;

function TCPParser.DoParseForStmt(): TCPForNode;
var
  LBody: TObjectList<TCPASTNode>;
begin
  Result := TCPForNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'for'

  if Current().Kind <> tkIdentifier then
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
      'Expected iterator variable name');
    Result.Free();
    Result := nil;
    Exit;
  end;
  Result.IteratorName := Current().TokenText;
  Consume();

  Expect(tkAssign);
  Result.StartExpr := DoParseExpression();

  if Match(tkDownTo) then
    Result.IsDownTo := True
  else
    Expect(tkTo);

  Result.EndExpr := DoParseExpression();
  Expect(tkDo);

  LBody := DoParseStatementSeq([tkEnd]);
  Result.Body.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  ExpectBlockEnd('for', Result.Location);
  OptionalSemicolon();
end;

function TCPParser.DoParseRepeatStmt(): TCPRepeatNode;
var
  LBody: TObjectList<TCPASTNode>;
begin
  Result := TCPRepeatNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'repeat'

  LBody := DoParseStatementSeq([tkUntil]);
  Result.Body.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  Expect(tkUntil);
  Result.Condition := DoParseExpression();
  OptionalSemicolon();
end;

function TCPParser.DoParseMatchStmt(): TCPMatchNode;
var
  LBody: TObjectList<TCPASTNode>;
begin
  Result := TCPMatchNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'match'

  Result.Expr := DoParseExpression();
  Expect(tkOf);

  // Parse match arms until else or end
  while not (Check(tkElse) or Check(tkEnd) or Check(tkEOF)) do
    Result.Arms.Add(DoParseMatchArm());

  if Match(tkElse) then
  begin
    LBody := DoParseStatementSeq([tkEnd]);
    Result.ElseBody.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();
  end;

  ExpectBlockEnd('match', Result.Location);
  OptionalSemicolon();
end;

function TCPParser.DoParseMatchArm(): TCPMatchArmNode;
var
  LLabel: TCPMatchLabelNode;
  LStmt: TCPASTNode;
begin
  Result := TCPMatchArmNode.Create();
  Result.Location := Current().Location;

  // label1, label2, ...: body
  repeat
    LLabel := TCPMatchLabelNode.Create();
    LLabel.Location := Current().Location;
    LLabel.LowExpr := DoParseExpression();

    // Check for range: expr..expr
    if Match(tkDotDot) then
      LLabel.HighExpr := DoParseExpression();

    Result.Labels.Add(LLabel);
  until not Match(tkComma);

  Expect(tkColon);

  // Parse body statements until we leave this arm's scope.
  // We're in match state -- each iteration checks: is this a statement,
  // or the start of the next arm / else / end?
  while not (Check(tkEnd) or Check(tkElse) or Check(tkEOF)) do
  begin
    // Skip lone semicolons
    if Match(tkSemicolon) then
      Continue;

    // If the current token is not a valid statement start, this arm is done.
    // The match loop in DoParseMatchStmt will pick it up as a new label.
    if not IsStatementStart(Current().Kind) then
      Break;

    LStmt := DoParseStatement();
    if Assigned(LStmt) then
      Result.Body.Add(LStmt);

    if FErrors.HasErrors() then
      Break;
  end;
end;

function TCPParser.DoParseReturnStmt(): TCPReturnNode;
begin
  Result := TCPReturnNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'return'

  // Optional return value -- return is followed by expression unless
  // we see a statement terminator
  if not (Check(tkSemicolon) or Check(tkEnd) or Check(tkElse) or
          Check(tkFinally) or Check(tkExcept) or Check(tkUntil) or Check(tkEOF)) then
    Result.ValueExpr := DoParseExpression();

  OptionalSemicolon();
end;

function TCPParser.DoParseGuardStmt(): TCPGuardNode;
var
  LBody: TObjectList<TCPASTNode>;
begin
  Result := TCPGuardNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume 'guard'

  // Guard body
  LBody := DoParseStatementSeq([tkExcept, tkFinally]);
  Result.GuardBody.AddRange(LBody.ToArray());
  LBody.OwnsObjects := False;
  LBody.Free();

  if Match(tkExcept) then
  begin
    LBody := DoParseStatementSeq([tkFinally, tkEnd]);
    Result.ExceptBody.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();

    // Optional finally after except
    if Match(tkFinally) then
    begin
      LBody := DoParseStatementSeq([tkEnd]);
      Result.FinallyBody.AddRange(LBody.ToArray());
      LBody.OwnsObjects := False;
      LBody.Free();
    end;
  end
  else if Match(tkFinally) then
  begin
    LBody := DoParseStatementSeq([tkEnd]);
    Result.FinallyBody.AddRange(LBody.ToArray());
    LBody.OwnsObjects := False;
    LBody.Free();
  end;

  ExpectBlockEnd('guard', Result.Location);
  OptionalSemicolon();
end;

function TCPParser.DoParseThrowStmt(): TCPASTNode;
var
  LThrow: TCPThrowNode;
  LThrowCode: TCPThrowCodeNode;
begin
  if Check(tkThrowCode) then
  begin
    LThrowCode := TCPThrowCodeNode.Create();
    LThrowCode.Location := Current().Location;
    Consume();
    Expect(tkLParen);
    LThrowCode.CodeExpr := DoParseExpression();
    Expect(tkComma);
    LThrowCode.MessageExpr := DoParseExpression();
    Expect(tkRParen);
    OptionalSemicolon();
    Result := LThrowCode;
  end
  else
  begin
    LThrow := TCPThrowNode.Create();
    LThrow.Location := Current().Location;
    Consume();
    Expect(tkLParen);
    LThrow.MessageExpr := DoParseExpression();
    Expect(tkRParen);
    OptionalSemicolon();
    Result := LThrow;
  end;
end;

function TCPParser.DoParseNewStmt(): TCPNewNode;
begin
  Result := TCPNewNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.ArgExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TCPParser.DoParseDisposeStmt(): TCPDisposeNode;
begin
  Result := TCPDisposeNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.ArgExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TCPParser.DoParseGetMemStmt(): TCPGetMemNode;
begin
  Result := TCPGetMemNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.ArgExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TCPParser.DoParseFreeMemStmt(): TCPFreeMemNode;
begin
  Result := TCPFreeMemNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.ArgExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TCPParser.DoParseResizeMemStmt(): TCPResizeMemNode;
begin
  Result := TCPResizeMemNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.PtrExpr := DoParseExpression();
  Expect(tkComma);
  Result.SizeExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TCPParser.DoParseSetLengthStmt(): TCPSetLengthNode;
begin
  Result := TCPSetLengthNode.Create();
  Result.Location := Current().Location;
  Consume();
  Expect(tkLParen);
  Result.TargetExpr := DoParseExpression();
  Expect(tkComma);
  Result.LengthExpr := DoParseExpression();
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TCPParser.DoParsePrintStmt(): TCPPrintNode;
begin
  Result := TCPPrintNode.Create();
  Result.Location := Current().Location;
  Result.IsLn := Check(tkPrintLn);
  Consume();

  Expect(tkLParen);
  if not Check(tkRParen) then
  begin
    Result.Args.Add(DoParseExpression());
    while Match(tkComma) do
      Result.Args.Add(DoParseExpression());
  end;
  Expect(tkRParen);
  OptionalSemicolon();
end;

function TCPParser.DoParseAssertStmt(): TCPAssertStmtNode;
var
  LKind: TCPTokenKind;
begin
  Result := TCPAssertStmtNode.Create();
  Result.Location := Current().Location;

  LKind := Current().Kind;
  if LKind = tkAssert then Result.AssertKind := akAssert
  else if LKind = tkAssertTrue then Result.AssertKind := akTrue
  else if LKind = tkAssertFalse then Result.AssertKind := akFalse
  else if LKind = tkAssertEq then Result.AssertKind := akEq
  else if LKind = tkAssertEqF then Result.AssertKind := akEqF
  else if LKind = tkAssertNil then Result.AssertKind := akNil
  else if LKind = tkAssertNotNil then Result.AssertKind := akNotNil
  else if LKind = tkAssertFail then Result.AssertKind := akFail;

  Consume();
  Expect(tkLParen);

  // All asserts have at least one argument
  Result.Args.Add(DoParseExpression());

  // asserteq has 2 args, asserteqf has 3
  if Match(tkComma) then
  begin
    Result.Args.Add(DoParseExpression());
    if Match(tkComma) then
      Result.Args.Add(DoParseExpression());
  end;

  Expect(tkRParen);
  OptionalSemicolon();
end;

{ TCPParser.DoParseCppBlock }
function TCPParser.DoParseCppBlock(): TCPCppBlockNode;
var
  LRaw: string;
  LTarget: string;
  LText: string;
  LSplitPos: Integer;
begin
  Result := TCPCppBlockNode.Create();
  Result.Location := Current().Location;
  Consume(); // consume tkCppStart

  // The raw block token contains "target\ntext" -- first word is header|source
  if Current().Kind <> tkRawBlock then
  begin
    FErrors.Add(Current().Location, esError, CP_ERR_PAR_001,
      'Expected raw block content after cppstart', []);
    Exit;
  end;

  LRaw := Current().TokenText;
  Consume(); // consume tkRawBlock

  // Split target from text at first whitespace/newline
  LSplitPos := 0;
  while LSplitPos < Length(LRaw) do
  begin
    Inc(LSplitPos);
    if CharInSet(LRaw[LSplitPos], [' ', #9, #10, #13]) then
      Break;
  end;

  if LSplitPos <= Length(LRaw) then
  begin
    LTarget := LRaw.Substring(0, LSplitPos - 1).Trim();
    LText := LRaw.Substring(LSplitPos).Trim();
  end
  else
  begin
    LTarget := LRaw.Trim();
    LText := '';
  end;

  Result.Target := LTarget;
  Result.RawText := LText;

  Expect(tkCppEnd);
end;

{ TCPParser.DoParseCppStmt }
function TCPParser.DoParseCppStmt(): TCPASTNode;
var
  LExpr: TCPCppExprNode;
begin
  // cpp("...") as a statement -- parse as expression, wrap in call stmt
  LExpr := DoParseCppExpr();
  Result := TCPCallStmtNode.Create();
  Result.Location := LExpr.Location;
  TCPCallStmtNode(Result).CallExpr := LExpr;
  OptionalSemicolon();
end;

{ TCPParser.DoParseCppExpr }
function TCPParser.DoParseCppExpr(): TCPCppExprNode;
begin
  Result := TCPCppExprNode.Create();
  Result.Location := Current().Location;
  Consume(); // consume tkCpp

  Expect(tkLParen);
  Result.ArgExpr := TCPExprNode(DoParseExpression());
  Expect(tkRParen);
end;

// -- Expressions (Pratt parser) ---------------------------------------------

function TCPParser.DoParseExpression(): TCPASTNode;
begin
  Result := DoParsePrecedence(1);
end;

function TCPParser.DoParsePrecedence(const AMinPrec: Integer): TCPASTNode;
var
  LLeft: TCPASTNode;
  LBinary: TCPBinaryExprNode;
  LPrec: Integer;
begin
  LLeft := DoParsePrefix();

  while True do
  begin
    LPrec := GetPrecedence(Current().Kind);
    if (LPrec = 0) or (LPrec < AMinPrec) then
      Break;

    LBinary := TCPBinaryExprNode.Create();
    LBinary.Location := Current().Location;
    LBinary.Left := LLeft;
    LBinary.Op := TokenToBinaryOp(Current().Kind);
    Consume();
    // Right-associativity not needed for CPaskal ops, so use AMinPrec = LPrec + 1
    LBinary.Right := DoParsePrecedence(LPrec + 1);
    LLeft := LBinary;
  end;

  Result := LLeft;
end;

function TCPParser.DoParsePrefix(): TCPASTNode;
var
  LUnary: TCPUnaryExprNode;
  LLit: TCPIntLiteralNode;
  LFLit: TCPFloatLiteralNode;
  LSLit: TCPStringLiteralNode;
  LWSLit: TCPWStringLiteralNode;
  LBLit: TCPBoolLiteralNode;
  LIdent: TCPIdentifierNode;
begin
  // Unary operators
  if Check(tkNot) then
  begin
    LUnary := TCPUnaryExprNode.Create();
    LUnary.Location := Current().Location;
    LUnary.Op := uoNot;
    Consume();
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  if Check(tkMinus) then
  begin
    LUnary := TCPUnaryExprNode.Create();
    LUnary.Location := Current().Location;
    LUnary.Op := uoNegate;
    Consume();
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  if Check(tkPlus) then
  begin
    LUnary := TCPUnaryExprNode.Create();
    LUnary.Location := Current().Location;
    LUnary.Op := uoPositive;
    Consume();
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  // address of expr
  if Check(tkAddress) then
  begin
    LUnary := TCPUnaryExprNode.Create();
    LUnary.Location := Current().Location;
    LUnary.Op := uoAddressOf;
    Consume();
    Expect(tkOf);
    LUnary.Operand := DoParsePrefix();
    Result := LUnary;
    Exit;
  end;

  // Literals
  if Check(tkIntLiteral) then
  begin
    LLit := TCPIntLiteralNode.Create();
    LLit.Location := Current().Location;
    if Current().LiteralValue.IsType<UInt64>() then
      LLit.IntValue := Int64(Current().LiteralValue.AsUInt64())
    else if Current().LiteralValue.IsType<Int64>() then
      LLit.IntValue := Current().LiteralValue.AsInt64()
    else
      LLit.IntValue := StrToInt64Def(Current().TokenText, 0);
    Consume();
    Result := LLit;
    Exit;
  end;

  if Check(tkFloatLiteral) then
  begin
    LFLit := TCPFloatLiteralNode.Create();
    LFLit.Location := Current().Location;
    if Current().LiteralValue.IsType<Double>() then
      LFLit.FloatValue := Current().LiteralValue.AsType<Double>()
    else
      LFLit.FloatValue := StrToFloatDef(Current().TokenText, 0.0);
    LFLit.HasSuffix := Current().TokenText.EndsWith('f', True) or
                        Current().TokenText.EndsWith('F', True);
    Consume();
    Result := LFLit;
    Exit;
  end;

  if Check(tkStringLiteral) then
  begin
    LSLit := TCPStringLiteralNode.Create();
    LSLit.Location := Current().Location;
    if Current().LiteralValue.IsType<string>() then
      LSLit.StringValue := Current().LiteralValue.AsString()
    else
      LSLit.StringValue := Current().TokenText;
    Consume();
    Result := LSLit;
    Exit;
  end;

  if Check(tkWStringLiteral) then
  begin
    LWSLit := TCPWStringLiteralNode.Create();
    LWSLit.Location := Current().Location;
    if Current().LiteralValue.IsType<string>() then
      LWSLit.StringValue := Current().LiteralValue.AsString()
    else
      LWSLit.StringValue := Current().TokenText;
    Consume();
    Result := LWSLit;
    Exit;
  end;

  if Check(tkTrue) or Check(tkFalse) then
  begin
    LBLit := TCPBoolLiteralNode.Create();
    LBLit.Location := Current().Location;
    LBLit.BoolValue := Check(tkTrue);
    Consume();
    Result := LBLit;
    Exit;
  end;

  if Check(tkNil) then
  begin
    Result := TCPNilLiteralNode.Create();
    Result.Location := Current().Location;
    Consume();
    Exit;
  end;

  // Parenthesized expression
  if Check(tkLParen) then
  begin
    Consume();
    Result := DoParseExpression();
    Expect(tkRParen);
    // Continue with designator chain (selectors after parens)
    Result := DoParseDesignator(Result);
    Exit;
  end;

  // Set literal [...]
  if Check(tkLBracket) then
  begin
    Result := DoParseSetLiteral();
    Exit;
  end;

  // cpp() inline expression
  if Check(tkCpp) then
  begin
    Result := DoParseCppExpr();
    Exit;
  end;

  // Intrinsics
  if IsIntrinsicToken(Current().Kind) then
  begin
    Result := DoParseIntrinsic(TokenToIntrinsicKind(Current().Kind));
    Exit;
  end;

  // Identifier -- start of designator chain, possibly type cast or record literal
  if Check(tkIdentifier) or Check(tkVarArgs) then
  begin
    LIdent := TCPIdentifierNode.Create();
    LIdent.Location := Current().Location;
    LIdent.IdentName := Current().TokenText;
    Consume();
    Result := DoParseDesignator(LIdent);
    Exit;
  end;

  // Primitive type as expression (for type casts like int32(x))
  if FLexer.IsDataType(Current().Kind) then
  begin
    Result := DoParseTypeExpr();
    // If followed by (, it's a type cast
    if Check(tkLParen) then
      Result := DoParseDesignator(Result);
    Exit;
  end;

  // Nothing matched
  FErrors.Add(Current().Location, esError, CP_ERR_PAR_007,
    'Expected expression, got: %s', [Current().TokenText]);
  Result := nil;
end;

function TCPParser.DoParseDesignator(const ABase: TCPASTNode): TCPASTNode;
var
  LResult: TCPASTNode;
  LDot: TCPDotAccessNode;
  LIndex: TCPIndexAccessNode;
  LDeref: TCPDerefNode;
  LCall: TCPCallExprNode;
  LCast: TCPTypeCastExprNode;
  LRecLit: TCPRecordLiteralNode;
  LFieldInit: TCPFieldInitNode;
begin
  LResult := ABase;

  while True do
  begin
    // .member
    if Check(tkDot) then
    begin
      Consume();
      LDot := TCPDotAccessNode.Create();
      LDot.Location := Current().Location;
      LDot.BaseExpr := LResult;
      if Current().Kind <> tkIdentifier then
      begin
        FErrors.Add(Current().Location, esError, CP_ERR_PAR_008,
          'Expected member name after "."');
        LDot.BaseExpr := nil;  // detach before free to prevent double-free of LResult
        LDot.Free();
        Break;
      end;
      LDot.MemberName := Current().TokenText;
      Consume();
      LResult := LDot;
    end
    // [index]
    else if Check(tkLBracket) then
    begin
      Consume();
      LIndex := TCPIndexAccessNode.Create();
      LIndex.Location := LResult.Location;
      LIndex.BaseExpr := LResult;
      LIndex.IndexExpr := DoParseExpression();
      Expect(tkRBracket);
      LResult := LIndex;
    end
    // ^ dereference
    else if Check(tkCaret) then
    begin
      LDeref := TCPDerefNode.Create();
      LDeref.Location := Current().Location;
      LDeref.BaseExpr := LResult;
      Consume();
      LResult := LDeref;
    end
    // (args) -- call, type cast, or record literal
    else if Check(tkLParen) then
    begin
      // Check for record literal: ident(fieldname: expr, ...)
      // Record literal is when base is an identifier or module-qualified dot access
      // and first arg is ident followed by colon
      if ((LResult is TCPIdentifierNode) or
          ((LResult is TCPDotAccessNode) and (TCPDotAccessNode(LResult).BaseExpr is TCPIdentifierNode))) and
         (PeekAt(1).Kind = tkIdentifier) and (PeekAt(2).Kind = tkColon) then
      begin
        LRecLit := TCPRecordLiteralNode.Create();
        LRecLit.Location := LResult.Location;
        if LResult is TCPDotAccessNode then
        begin
          // Module-qualified: probeunit.TPoint(x: 10, y: 20)
          LRecLit.ModuleName := TCPIdentifierNode(TCPDotAccessNode(LResult).BaseExpr).IdentName;
          LRecLit.TypeName := TCPDotAccessNode(LResult).MemberName;
        end
        else
          LRecLit.TypeName := TCPIdentifierNode(LResult).IdentName;
        LResult.Free();
        Consume();  // consume (

        repeat
          LFieldInit := TCPFieldInitNode.Create();
          LFieldInit.Location := Current().Location;
          LFieldInit.FieldName := Current().TokenText;
          Consume();  // consume field name
          Expect(tkColon);
          LFieldInit.ValueExpr := DoParseExpression();
          LRecLit.FieldInits.Add(LFieldInit);
        until not Match(tkComma);

        Expect(tkRParen);
        LResult := LRecLit;
      end
      // Check for type cast: primitive_type(expr)
      else if LResult is TCPTypeRefNode then
      begin
        LCast := TCPTypeCastExprNode.Create();
        LCast.Location := LResult.Location;
        LCast.TargetType := LResult;
        Consume();  // consume (
        LCast.Expr := DoParseExpression();
        Expect(tkRParen);
        LResult := LCast;
      end
      // Regular function call
      else
      begin
        LCall := TCPCallExprNode.Create();
        LCall.Location := LResult.Location;
        LCall.Callee := LResult;
        Consume();  // consume (
        if not Check(tkRParen) then
        begin
          LCall.Args.Add(DoParseExpression());
          while Match(tkComma) do
            LCall.Args.Add(DoParseExpression());
        end;
        Expect(tkRParen);
        LResult := LCall;
      end;
    end
    else
      Break;
  end;

  Result := LResult;
end;

function TCPParser.DoParseSetLiteral(): TCPSetLiteralExprNode;
var
  LElement: TCPSetElementNode;
begin
  Result := TCPSetLiteralExprNode.Create();
  Result.Location := Current().Location;
  Consume();  // consume [

  if not Check(tkRBracket) then
  begin
    repeat
      LElement := TCPSetElementNode.Create();
      LElement.Location := Current().Location;
      LElement.LowExpr := DoParseExpression();

      // Range: expr..expr
      if Match(tkDotDot) then
        LElement.HighExpr := DoParseExpression();

      Result.Elements.Add(LElement);
    until not Match(tkComma);
  end;

  Expect(tkRBracket);
end;

function TCPParser.DoParseIntrinsic(const AKind: TCPIntrinsicKind): TCPIntrinsicExprNode;
begin
  Result := TCPIntrinsicExprNode.Create();
  Result.Location := Current().Location;
  Result.IntrinsicKind := AKind;
  Consume();  // consume intrinsic keyword

  Expect(tkLParen);

  // paramcount() and exccode() and excmsg() have no args
  if not Check(tkRParen) then
  begin
    Result.Args.Add(DoParseExpression());
    // size() can take a type expression too, but it's parsed as expression
  end;

  Expect(tkRParen);
end;

end.
