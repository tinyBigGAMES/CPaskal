{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.Codegen - C++23 Code Generation

  Pure AST walker that emits C++23 source code. Reads enriched AST nodes
  (ResolvedType, ResolvedDecl, CppTypeText all populated by semantic pass).
  Never resolves, never looks up symbols, never calls back into lexer/parser/
  semantics. The AST is the single source of truth.

  Two classes:
    TCPCodeOutput  -- dual-buffer (header/source) text builder
    TCPCodegen     -- walks the master AST, emits via TCPCodeOutput

  Dependencies: CPaskal.Common, CPaskal.AST, StdApp.Base
===============================================================================}

unit CPaskal.Codegen;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  StdApp.Base,
  CPaskal.Common,
  CPaskal.AST;

type

  { TCPOutputTarget }
  TCPOutputTarget = (
    otHeader,
    otSource
  );

  { TCPCodeOutput }
  TCPCodeOutput = class(TBaseObject)
  protected
    FHeaderBuffer: TStringBuilder;
    FSourceBuffer: TStringBuilder;
    FIndentLevel: Integer;
    FExprResult: string;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Low-level emission
    procedure EmitLine(const AText: string; const ATarget: TCPOutputTarget = otSource);
    procedure Emit(const AText: string; const ATarget: TCPOutputTarget = otSource);
    procedure EmitRaw(const AText: string; const ATarget: TCPOutputTarget = otSource);
    procedure BlankLine(const ATarget: TCPOutputTarget = otSource);
    procedure IndentIn();
    procedure IndentOut();

    // Content access
    function GetHeaderContent(): string;
    function GetSourceContent(): string;
    procedure Clear();

    // Expression result
    property ExprResult: string read FExprResult write FExprResult;
  end;

  { TCPCodegen }
  TCPCodegen = class(TBaseObject)
  protected
    FOutput: TCPCodeOutput;
    FCurrentModule: TCPModuleNode;
    FGuardCounter: Integer;

    // Indentation helper
    function Indent(): string;

    // Top-level
    procedure EmitModule(const AModule: TCPModuleNode);
    procedure EmitModulePreamble(const AModule: TCPModuleNode);

    // Dispatch
    procedure EmitNode(const ANode: TCPASTNode);
    procedure EmitStmtList(const AList: TObjectList<TCPASTNode>);

    // Declarations
    procedure EmitConstDecl(const ANode: TCPConstDeclNode);
    procedure EmitTypeDecl(const ANode: TCPTypeDeclNode);
    procedure EmitVarDecl(const ANode: TCPVarDeclNode);
    procedure EmitRoutineDecl(const ANode: TCPRoutineDeclNode);

    // Type definitions
    procedure EmitRecordType(const AName: string; const ANode: TCPRecordTypeNode; const AIsPublic: Boolean);
    procedure EmitAnonFields(const AFields: TObjectList<TCPASTNode>; const ATarget: TCPOutputTarget);
    procedure EmitOverlayType(const AName: string; const ANode: TCPOverlayTypeNode; const AIsPublic: Boolean);
    procedure EmitChoicesType(const AName: string; const ANode: TCPChoicesTypeNode; const AIsPublic: Boolean);

    // Statements
    procedure EmitAssign(const ANode: TCPAssignNode);
    procedure EmitCallStmt(const ANode: TCPCallStmtNode);
    procedure EmitIf(const ANode: TCPIfNode);
    procedure EmitWhile(const ANode: TCPWhileNode);
    procedure EmitFor(const ANode: TCPForNode);
    procedure EmitRepeat(const ANode: TCPRepeatNode);
    procedure EmitMatch(const ANode: TCPMatchNode);
    procedure EmitReturn(const ANode: TCPReturnNode);
    procedure EmitGuard(const ANode: TCPGuardNode);
    procedure EmitThrow(const ANode: TCPThrowNode);
    procedure EmitThrowCode(const ANode: TCPThrowCodeNode);
    procedure EmitPrint(const ANode: TCPPrintNode);
    procedure EmitAssertStmt(const ANode: TCPAssertStmtNode);
    procedure EmitBreak();
    procedure EmitContinue();
    procedure EmitCppBlock(const ANode: TCPCppBlockNode);
    procedure EmitCppExpr(const ANode: TCPCppExprNode);

    // Memory
    procedure EmitCreate(const ANode: TCPCreateNode);
    procedure EmitDestroy(const ANode: TCPDestroyNode);
    procedure EmitGetMem(const ANode: TCPGetMemNode);
    procedure EmitFreeMem(const ANode: TCPFreeMemNode);
    procedure EmitResizeMem(const ANode: TCPResizeMemNode);
    procedure EmitSetLength(const ANode: TCPSetLengthNode);

    // Expressions (all set FOutput.ExprResult)
    procedure EmitExpr(const ANode: TCPASTNode);
    procedure EmitBinaryExpr(const ANode: TCPBinaryExprNode);
    procedure EmitUnaryExpr(const ANode: TCPUnaryExprNode);
    procedure EmitIntLiteral(const ANode: TCPIntLiteralNode);
    procedure EmitFloatLiteral(const ANode: TCPFloatLiteralNode);
    procedure EmitStringLiteral(const ANode: TCPStringLiteralNode);
    procedure EmitWStringLiteral(const ANode: TCPWStringLiteralNode);
    procedure EmitBoolLiteral(const ANode: TCPBoolLiteralNode);
    procedure EmitNilLiteral();
    procedure EmitIdentifier(const ANode: TCPIdentifierNode);
    procedure EmitDotAccess(const ANode: TCPDotAccessNode);
    procedure EmitIndexAccess(const ANode: TCPIndexAccessNode);
    procedure EmitDeref(const ANode: TCPDerefNode);
    procedure EmitCallExpr(const ANode: TCPCallExprNode);
    procedure EmitTypeCast(const ANode: TCPTypeCastExprNode);
    procedure EmitIntrinsic(const ANode: TCPIntrinsicExprNode);
    procedure EmitSetLiteral(const ANode: TCPSetLiteralExprNode);
    procedure EmitRecordLiteral(const ANode: TCPRecordLiteralNode);

    // Type emission
    function EmitTypeExpr(const ANode: TCPASTNode): string;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Generate(const AMasterAST: TCPMasterAST; const AOutputDir: string);
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils;

function cpEscapeCppString(const AValue: string): string; forward;

{ TCPCodeOutput }

constructor TCPCodeOutput.Create();
begin
  inherited;

  FHeaderBuffer := TStringBuilder.Create();
  FSourceBuffer := TStringBuilder.Create();
  FIndentLevel := 0;
  FExprResult := '';
end;

destructor TCPCodeOutput.Destroy();
begin
  FSourceBuffer.Free();
  FHeaderBuffer.Free();

  inherited;
end;

procedure TCPCodeOutput.EmitLine(const AText: string; const ATarget: TCPOutputTarget);
var
  LBuf: TStringBuilder;
  LIndent: string;
  I: Integer;
begin
  if ATarget = otHeader then
    LBuf := FHeaderBuffer
  else
    LBuf := FSourceBuffer;

  LIndent := '';
  for I := 1 to FIndentLevel do
    LIndent := LIndent + '  ';

  LBuf.AppendLine(LIndent + AText);
end;

procedure TCPCodeOutput.Emit(const AText: string; const ATarget: TCPOutputTarget);
var
  LBuf: TStringBuilder;
begin
  if ATarget = otHeader then
    LBuf := FHeaderBuffer
  else
    LBuf := FSourceBuffer;

  LBuf.Append(AText);
end;

procedure TCPCodeOutput.EmitRaw(const AText: string; const ATarget: TCPOutputTarget);
var
  LBuf: TStringBuilder;
begin
  if ATarget = otHeader then
    LBuf := FHeaderBuffer
  else
    LBuf := FSourceBuffer;

  LBuf.Append(AText);
end;

procedure TCPCodeOutput.BlankLine(const ATarget: TCPOutputTarget);
var
  LBuf: TStringBuilder;
begin
  if ATarget = otHeader then
    LBuf := FHeaderBuffer
  else
    LBuf := FSourceBuffer;

  LBuf.AppendLine('');
end;

procedure TCPCodeOutput.IndentIn();
begin
  Inc(FIndentLevel);
end;

procedure TCPCodeOutput.IndentOut();
begin
  if FIndentLevel > 0 then
    Dec(FIndentLevel);
end;

function TCPCodeOutput.GetHeaderContent(): string;
begin
  Result := FHeaderBuffer.ToString();
end;

function TCPCodeOutput.GetSourceContent(): string;
begin
  Result := FSourceBuffer.ToString();
end;

procedure TCPCodeOutput.Clear();
begin
  FHeaderBuffer.Clear();
  FSourceBuffer.Clear();
  FIndentLevel := 0;
  FExprResult := '';
end;

{ TCPCodegen }

constructor TCPCodegen.Create();
begin
  inherited;

  FOutput := TCPCodeOutput.Create();
  FOutput.SetErrors(FErrors);
  FCurrentModule := nil;
  FGuardCounter := 0;
end;

destructor TCPCodegen.Destroy();
begin
  FOutput.Free();

  inherited;
end;

function TCPCodegen.Indent(): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to FOutput.FIndentLevel do
    Result := Result + '  ';
end;

procedure TCPCodegen.Generate(const AMasterAST: TCPMasterAST; const AOutputDir: string);
var
  I: Integer;
  LModule: TCPModuleNode;
  LHeaderPath: string;
  LSourcePath: string;
begin
  for I := 0 to AMasterAST.Modules.Count - 1 do
  begin
    LModule := AMasterAST.Modules[I];
    FOutput.Clear();
    FGuardCounter := 0;
    EmitModule(LModule);

    // Write files
    LHeaderPath := TPath.Combine(AOutputDir, LModule.ModuleName + '.h');
    LSourcePath := TPath.Combine(AOutputDir, LModule.ModuleName + '.cpp');

    TFile.WriteAllText(LHeaderPath, FOutput.GetHeaderContent(), TEncoding.UTF8);
    TFile.WriteAllText(LSourcePath, FOutput.GetSourceContent(), TEncoding.UTF8);
  end;
end;

procedure TCPCodegen.EmitModulePreamble(const AModule: TCPModuleNode);
var
  I: Integer;
begin
  // Header preamble
  FOutput.EmitLine('#pragma once', otHeader);
  FOutput.BlankLine(otHeader);
  FOutput.EmitLine('#include <cstdint>', otHeader);
  FOutput.EmitLine('#include <string>', otHeader);
  FOutput.EmitLine('#include <array>', otHeader);
  FOutput.EmitLine('#include <vector>', otHeader);
  FOutput.EmitLine('#include <print>', otHeader);
  FOutput.EmitLine('#include "runtime.h"', otHeader);
  FOutput.BlankLine(otHeader);

  // Import includes in header
  for I := 0 to AModule.Imports.Count - 1 do
    FOutput.EmitLine('#include "' + AModule.Imports[I].ModuleName + '.h"', otHeader);

  if AModule.Imports.Count > 0 then
    FOutput.BlankLine(otHeader);

  // Source preamble
  FOutput.EmitLine('#include "' + AModule.ModuleName + '.h"', otSource);
  FOutput.BlankLine(otSource);
end;

procedure TCPCodegen.EmitModule(const AModule: TCPModuleNode);
var
  I: Integer;
  LTest: TCPTestBlockNode;
  J: Integer;
begin
  FCurrentModule := AModule;
  EmitModulePreamble(AModule);

  // Declarations
  for I := 0 to AModule.Declarations.Count - 1 do
    EmitNode(AModule.Declarations[I]);

  // Init body
  if AModule.InitBody.Count > 0 then
  begin
    FOutput.BlankLine(otSource);
    FOutput.EmitLine('__attribute__((constructor)) static void __cpas_init_0() {', otSource);
    FOutput.IndentIn();
    EmitStmtList(AModule.InitBody);
    FOutput.IndentOut();
    FOutput.EmitLine('}', otSource);
  end;

  // Final body
  if AModule.FinalBody.Count > 0 then
  begin
    FOutput.BlankLine(otSource);
    FOutput.EmitLine('__attribute__((destructor)) static void __cpas_fini_0() {', otSource);
    FOutput.IndentIn();
    EmitStmtList(AModule.FinalBody);
    FOutput.IndentOut();
    FOutput.EmitLine('}', otSource);
  end;

  // Test blocks
  for I := 0 to AModule.TestBlocks.Count - 1 do
  begin
    LTest := AModule.TestBlocks[I];
    FOutput.BlankLine(otSource);
    FOutput.EmitLine('void __test_' + LTest.CppTestName + '() {', otSource);
    FOutput.IndentIn();

    // Local variables
    for J := 0 to LTest.Locals.Count - 1 do
      EmitVarDecl(LTest.Locals[J]);

    EmitStmtList(LTest.Body);
    FOutput.IndentOut();
    FOutput.EmitLine('}', otSource);
  end;

  // Main body (exe only)
  if AModule.ModuleKind = mkExe then
  begin
    FOutput.BlankLine(otSource);
    FOutput.EmitLine('int main(int argc, char** argv) {', otSource);
    FOutput.IndentIn();
    FOutput.EmitLine('rt_initconsole();', otSource);
    FOutput.EmitLine('rt_init_exceptions();', otSource);
    FOutput.EmitLine('rt_init_args(argc, argv);', otSource);

    // Register test blocks
    if AModule.TestBlocks.Count > 0 then
    begin
      FOutput.BlankLine(otSource);
      for I := 0 to AModule.TestBlocks.Count - 1 do
      begin
        LTest := AModule.TestBlocks[I];
        FOutput.EmitLine('rt_test_register("' + LTest.TestName +
          '", __test_' + LTest.CppTestName + ', __FILE__, __LINE__);', otSource);
      end;
    end;

    // Main body statements
    if AModule.MainBody.Count > 0 then
    begin
      FOutput.BlankLine(otSource);
      EmitStmtList(AModule.MainBody);
    end;

    // Return: if tests registered, return test result; else 0
    FOutput.BlankLine(otSource);
    if AModule.TestBlocks.Count > 0 then
      FOutput.EmitLine('return rt_test_run_all();', otSource)
    else
      FOutput.EmitLine('return 0;', otSource);

    FOutput.IndentOut();
    FOutput.EmitLine('}', otSource);
  end;
end;

// Dispatch

procedure TCPCodegen.EmitNode(const ANode: TCPASTNode);
begin
  if ANode = nil then
    Exit;

  if ANode is TCPConstDeclNode then
    EmitConstDecl(TCPConstDeclNode(ANode))
  else if ANode is TCPTypeDeclNode then
    EmitTypeDecl(TCPTypeDeclNode(ANode))
  else if ANode is TCPVarDeclNode then
    EmitVarDecl(TCPVarDeclNode(ANode))
  else if ANode is TCPRoutineDeclNode then
    EmitRoutineDecl(TCPRoutineDeclNode(ANode))
  else if ANode is TCPAssignNode then
    EmitAssign(TCPAssignNode(ANode))
  else if ANode is TCPCallStmtNode then
    EmitCallStmt(TCPCallStmtNode(ANode))
  else if ANode is TCPIfNode then
    EmitIf(TCPIfNode(ANode))
  else if ANode is TCPWhileNode then
    EmitWhile(TCPWhileNode(ANode))
  else if ANode is TCPForNode then
    EmitFor(TCPForNode(ANode))
  else if ANode is TCPRepeatNode then
    EmitRepeat(TCPRepeatNode(ANode))
  else if ANode is TCPMatchNode then
    EmitMatch(TCPMatchNode(ANode))
  else if ANode is TCPReturnNode then
    EmitReturn(TCPReturnNode(ANode))
  else if ANode is TCPGuardNode then
    EmitGuard(TCPGuardNode(ANode))
  else if ANode is TCPThrowNode then
    EmitThrow(TCPThrowNode(ANode))
  else if ANode is TCPThrowCodeNode then
    EmitThrowCode(TCPThrowCodeNode(ANode))
  else if ANode is TCPPrintNode then
    EmitPrint(TCPPrintNode(ANode))
  else if ANode is TCPAssertStmtNode then
    EmitAssertStmt(TCPAssertStmtNode(ANode))
  else if ANode is TCPBreakNode then
    EmitBreak()
  else if ANode is TCPContinueNode then
    EmitContinue()
  else if ANode is TCPCreateNode then
    EmitCreate(TCPCreateNode(ANode))
  else if ANode is TCPDestroyNode then
    EmitDestroy(TCPDestroyNode(ANode))
  else if ANode is TCPGetMemNode then
    EmitGetMem(TCPGetMemNode(ANode))
  else if ANode is TCPFreeMemNode then
    EmitFreeMem(TCPFreeMemNode(ANode))
  else if ANode is TCPResizeMemNode then
    EmitResizeMem(TCPResizeMemNode(ANode))
  else if ANode is TCPSetLengthNode then
    EmitSetLength(TCPSetLengthNode(ANode))
  else if ANode is TCPCppBlockNode then
    EmitCppBlock(TCPCppBlockNode(ANode));
  // Forward decls and other non-emitting nodes silently skipped
end;

procedure TCPCodegen.EmitStmtList(const AList: TObjectList<TCPASTNode>);
var
  I: Integer;
begin
  for I := 0 to AList.Count - 1 do
    EmitNode(AList[I]);
end;

// Declarations

procedure TCPCodegen.EmitConstDecl(const ANode: TCPConstDeclNode);
var
  LType: string;
  LValue: string;
begin
  if ANode.TypeExpr <> nil then
    LType := EmitTypeExpr(ANode.TypeExpr)
  else
    LType := EmitTypeExpr(TCPExprNode(ANode.ValueExpr).ResolvedType);

  EmitExpr(TCPExprNode(ANode.ValueExpr));
  LValue := FOutput.ExprResult;

  if ANode.IsPublic then
  begin
    // Public: inline constexpr in header
    FOutput.EmitLine('inline constexpr ' + LType + ' ' + ANode.DeclName +
      ' = ' + LValue + ';', otHeader);
  end
  else
  begin
    // Private: constexpr in source
    FOutput.EmitLine('constexpr ' + LType + ' ' + ANode.DeclName +
      ' = ' + LValue + ';', otSource);
  end;
end;

procedure TCPCodegen.EmitTypeDecl(const ANode: TCPTypeDeclNode);
begin
  if ANode.TypeDef = nil then
    Exit;

  if ANode.TypeDef is TCPRecordTypeNode then
    EmitRecordType(ANode.DeclName, TCPRecordTypeNode(ANode.TypeDef), ANode.IsPublic)
  else if ANode.TypeDef is TCPOverlayTypeNode then
    EmitOverlayType(ANode.DeclName, TCPOverlayTypeNode(ANode.TypeDef), ANode.IsPublic)
  else if ANode.TypeDef is TCPChoicesTypeNode then
    EmitChoicesType(ANode.DeclName, TCPChoicesTypeNode(ANode.TypeDef), ANode.IsPublic)
  else if ANode.TypeDef is TCPTypeRefNode then
  begin
    // Type alias: using Name = Original;
    if ANode.IsPublic then
      FOutput.EmitLine('using ' + ANode.DeclName + ' = ' +
        EmitTypeExpr(ANode.TypeDef) + ';', otHeader)
    else
      FOutput.EmitLine('using ' + ANode.DeclName + ' = ' +
        EmitTypeExpr(ANode.TypeDef) + ';', otSource);
  end
  else if ANode.TypeDef is TCPArrayTypeNode then
  begin
    if ANode.IsPublic then
      FOutput.EmitLine('using ' + ANode.DeclName + ' = ' +
        EmitTypeExpr(ANode.TypeDef) + ';', otHeader)
    else
      FOutput.EmitLine('using ' + ANode.DeclName + ' = ' +
        EmitTypeExpr(ANode.TypeDef) + ';', otSource);
  end
  else if ANode.TypeDef is TCPPointerTypeNode then
  begin
    if ANode.IsPublic then
      FOutput.EmitLine('using ' + ANode.DeclName + ' = ' +
        EmitTypeExpr(ANode.TypeDef) + ';', otHeader)
    else
      FOutput.EmitLine('using ' + ANode.DeclName + ' = ' +
        EmitTypeExpr(ANode.TypeDef) + ';', otSource);
  end
  else if ANode.TypeDef is TCPRoutineTypeNode then
  begin
    // Routine type: using Name = rettype(*)(params...);
    if ANode.IsPublic then
      FOutput.EmitLine('using ' + ANode.DeclName + ' = ' +
        EmitTypeExpr(ANode.TypeDef) + ';', otHeader)
    else
      FOutput.EmitLine('using ' + ANode.DeclName + ' = ' +
        EmitTypeExpr(ANode.TypeDef) + ';', otSource);
  end;
end;

procedure TCPCodegen.EmitVarDecl(const ANode: TCPVarDeclNode);
var
  LType: string;
  LInit: string;
begin
  LType := EmitTypeExpr(ANode.TypeExpr);

  if ANode.InitExpr <> nil then
  begin
    EmitExpr(TCPExprNode(ANode.InitExpr));
    LInit := ' = ' + FOutput.ExprResult;
  end
  else
    LInit := '';

  if ANode.IsExternal then
  begin
    // External variable: extern "C" type name;
    FOutput.EmitLine('extern "C" ' + LType + ' ' + ANode.DeclName + ';', otHeader);
  end
  else if ANode.IsPublic then
  begin
    // Public: extern in header, definition in source
    FOutput.EmitLine('extern ' + LType + ' ' + ANode.DeclName + ';', otHeader);
    FOutput.EmitLine(LType + ' ' + ANode.DeclName + LInit + ';', otSource);
  end
  else
  begin
    // Private or local: definition in source
    FOutput.EmitLine(LType + ' ' + ANode.DeclName + LInit + ';', otSource);
  end;
end;

procedure TCPCodegen.EmitRoutineDecl(const ANode: TCPRoutineDeclNode);
var
  LRetType: string;
  LSig: string;
  I: Integer;
  LParam: TCPParamDeclNode;
  LParamType: string;
begin
  // Determine return type
  if ANode.ReturnType <> nil then
    LRetType := EmitTypeExpr(ANode.ReturnType)
  else
    LRetType := 'void';

  // Build parameter list
  LSig := '';
  for I := 0 to ANode.Params.Count - 1 do
  begin
    LParam := ANode.Params[I];
    LParamType := EmitTypeExpr(LParam.TypeExpr);

    // Parameter passing
    if LParam.ParamMode = pmVar then
      LParamType := LParamType + '&'
    else if LParam.ParamMode = pmConst then
      LParamType := 'const ' + LParamType + '&';

    if I > 0 then
      LSig := LSig + ', ';
    LSig := LSig + LParamType + ' ' + LParam.ParamName;
  end;

  // Variadic: add hidden count param
  if ANode.IsVariadic then
  begin
    if LSig <> '' then
      LSig := LSig + ', ';
    LSig := LSig + 'int32_t __rt_vararg_count, ...';
  end;

  // External routine
  if ANode.IsExternal then
  begin
    if ANode.Linkage = lkCppLink then
      FOutput.EmitLine(LRetType + ' ' + ANode.DeclName + '(' + LSig + ');', otHeader)
    else
      FOutput.EmitLine('extern "C" ' + LRetType + ' ' + ANode.DeclName +
        '(' + LSig + ');', otHeader);
    Exit;
  end;

  // Public: prototype in header
  if ANode.IsPublic then
    FOutput.EmitLine(LRetType + ' ' + ANode.DeclName + '(' + LSig + ');', otHeader);

  // Function body in source
  FOutput.BlankLine(otSource);
  FOutput.EmitLine(LRetType + ' ' + ANode.DeclName + '(' + LSig + ') {', otSource);
  FOutput.IndentIn();

  // Local types
  for I := 0 to ANode.LocalTypes.Count - 1 do
    EmitTypeDecl(ANode.LocalTypes[I]);

  // Local constants
  for I := 0 to ANode.LocalConsts.Count - 1 do
    EmitConstDecl(ANode.LocalConsts[I]);

  // Local variables
  for I := 0 to ANode.LocalVars.Count - 1 do
    EmitVarDecl(ANode.LocalVars[I]);

  // Variadic setup
  if ANode.IsVariadic then
  begin
    FOutput.EmitLine('rt_varargs varargs;', otSource);
    FOutput.EmitLine('rt_varargs_start(varargs, __rt_vararg_count);', otSource);
  end;

  // Body statements
  EmitStmtList(ANode.Body);

  FOutput.IndentOut();
  FOutput.EmitLine('}', otSource);
end;

// Type definitions

procedure TCPCodegen.EmitRecordType(const AName: string; const ANode: TCPRecordTypeNode; const AIsPublic: Boolean);
var
  LTarget: TCPOutputTarget;
  I: Integer;
  LField: TCPFieldDeclNode;
  LFieldType: string;
  LBaseSpec: string;
begin
  if AIsPublic then
    LTarget := otHeader
  else
    LTarget := otSource;

  // Record inheritance: emit struct TDerived : TBase {
  if ANode.BaseType <> nil then
    LBaseSpec := ' : ' + EmitTypeExpr(ANode.BaseType)
  else
    LBaseSpec := '';

  if ANode.IsPacked then
    FOutput.EmitLine('#pragma pack(push, 1)', LTarget);

  if ANode.Alignment > 0 then
    FOutput.EmitLine('struct alignas(' + IntToStr(ANode.Alignment) + ') ' + AName + LBaseSpec + ' {', LTarget)
  else
    FOutput.EmitLine('struct ' + AName + LBaseSpec + ' {', LTarget);

  FOutput.IndentIn();
  for I := 0 to ANode.Fields.Count - 1 do
  begin
    if ANode.Fields[I] is TCPFieldDeclNode then
    begin
      LField := TCPFieldDeclNode(ANode.Fields[I]);
      LFieldType := EmitTypeExpr(LField.TypeExpr);
      if LField.BitWidth > 0 then
        FOutput.EmitLine(LFieldType + ' ' + LField.FieldName +
          ' : ' + IntToStr(LField.BitWidth) + ';', LTarget)
      else
        FOutput.EmitLine(LFieldType + ' ' + LField.FieldName + ';', LTarget);
    end
    else if ANode.Fields[I] is TCPAnonRecordNode then
    begin
      FOutput.EmitLine('struct {', LTarget);
      FOutput.IndentIn();
      EmitAnonFields(TCPAnonRecordNode(ANode.Fields[I]).Fields, LTarget);
      FOutput.IndentOut();
      FOutput.EmitLine('};', LTarget);
    end
    else if ANode.Fields[I] is TCPAnonOverlayNode then
    begin
      FOutput.EmitLine('union {', LTarget);
      FOutput.IndentIn();
      EmitAnonFields(TCPAnonOverlayNode(ANode.Fields[I]).Fields, LTarget);
      FOutput.IndentOut();
      FOutput.EmitLine('};', LTarget);
    end;
  end;
  FOutput.IndentOut();
  FOutput.EmitLine('};', LTarget);

  if ANode.IsPacked then
    FOutput.EmitLine('#pragma pack(pop)', LTarget);

  FOutput.BlankLine(LTarget);
end;

procedure TCPCodegen.EmitOverlayType(const AName: string; const ANode: TCPOverlayTypeNode; const AIsPublic: Boolean);
var
  LTarget: TCPOutputTarget;
  I: Integer;
  LField: TCPFieldDeclNode;
begin
  if AIsPublic then
    LTarget := otHeader
  else
    LTarget := otSource;

  FOutput.EmitLine('union ' + AName + ' {', LTarget);
  FOutput.IndentIn();
  for I := 0 to ANode.Fields.Count - 1 do
  begin
    if ANode.Fields[I] is TCPFieldDeclNode then
    begin
      LField := TCPFieldDeclNode(ANode.Fields[I]);
      FOutput.EmitLine(EmitTypeExpr(LField.TypeExpr) + ' ' + LField.FieldName + ';', LTarget);
    end;
  end;
  FOutput.IndentOut();
  FOutput.EmitLine('};', LTarget);
  FOutput.BlankLine(LTarget);
end;

procedure TCPCodegen.EmitChoicesType(const AName: string; const ANode: TCPChoicesTypeNode; const AIsPublic: Boolean);
var
  LTarget: TCPOutputTarget;
  I: Integer;
  LMember: TCPChoicesValueNode;
  LLine: string;
begin
  if AIsPublic then
    LTarget := otHeader
  else
    LTarget := otSource;

  FOutput.EmitLine('enum ' + AName + ' {', LTarget);
  FOutput.IndentIn();
  for I := 0 to ANode.Members.Count - 1 do
  begin
    LMember := ANode.Members[I];
    LLine := LMember.MemberName;
    if LMember.ValueExpr <> nil then
    begin
      EmitExpr(TCPExprNode(LMember.ValueExpr));
      LLine := LLine + ' = ' + FOutput.ExprResult;
    end;
    if I < ANode.Members.Count - 1 then
      LLine := LLine + ',';
    FOutput.EmitLine(LLine, LTarget);
  end;
  FOutput.IndentOut();
  FOutput.EmitLine('};', LTarget);
  FOutput.BlankLine(LTarget);
end;

// Statements

procedure TCPCodegen.EmitAssign(const ANode: TCPAssignNode);
var
  LTarget: string;
  LValue: string;
  LOp: string;
begin
  EmitExpr(TCPExprNode(ANode.Target));
  LTarget := FOutput.ExprResult;

  EmitExpr(TCPExprNode(ANode.ValueExpr));
  LValue := FOutput.ExprResult;

  case ANode.Op of
    aoAssign:      LOp := ' = ';
    aoPlusAssign:  LOp := ' += ';
    aoMinusAssign: LOp := ' -= ';
    aoMulAssign:   LOp := ' *= ';
    aoDivAssign:   LOp := ' /= ';
  end;

  FOutput.EmitLine(LTarget + LOp + LValue + ';', otSource);
end;

procedure TCPCodegen.EmitCallStmt(const ANode: TCPCallStmtNode);
begin
  EmitExpr(TCPExprNode(ANode.CallExpr));
  FOutput.EmitLine(FOutput.ExprResult + ';', otSource);
end;

procedure TCPCodegen.EmitIf(const ANode: TCPIfNode);
begin
  EmitExpr(TCPExprNode(ANode.Condition));
  FOutput.EmitLine('if (' + FOutput.ExprResult + ') {', otSource);
  FOutput.IndentIn();
  EmitStmtList(ANode.ThenBody);
  FOutput.IndentOut();

  if ANode.ElseBody.Count > 0 then
  begin
    // Check if else body is a single if node (else if chain)
    if (ANode.ElseBody.Count = 1) and (ANode.ElseBody[0] is TCPIfNode) then
    begin
      FOutput.Emit(Indent() + '} else ', otSource);
      // Emit the nested if without extra indent
      EmitExpr(TCPExprNode(TCPIfNode(ANode.ElseBody[0]).Condition));
      FOutput.EmitRaw('if (' + FOutput.ExprResult + ') {' + sLineBreak, otSource);
      FOutput.IndentIn();
      EmitStmtList(TCPIfNode(ANode.ElseBody[0]).ThenBody);
      FOutput.IndentOut();
      if TCPIfNode(ANode.ElseBody[0]).ElseBody.Count > 0 then
      begin
        FOutput.EmitLine('} else {', otSource);
        FOutput.IndentIn();
        EmitStmtList(TCPIfNode(ANode.ElseBody[0]).ElseBody);
        FOutput.IndentOut();
      end;
      FOutput.EmitLine('}', otSource);
    end
    else
    begin
      FOutput.EmitLine('} else {', otSource);
      FOutput.IndentIn();
      EmitStmtList(ANode.ElseBody);
      FOutput.IndentOut();
      FOutput.EmitLine('}', otSource);
    end;
  end
  else
    FOutput.EmitLine('}', otSource);
end;

procedure TCPCodegen.EmitWhile(const ANode: TCPWhileNode);
begin
  EmitExpr(TCPExprNode(ANode.Condition));
  FOutput.EmitLine('while (' + FOutput.ExprResult + ') {', otSource);
  FOutput.IndentIn();
  EmitStmtList(ANode.Body);
  FOutput.IndentOut();
  FOutput.EmitLine('}', otSource);
end;

procedure TCPCodegen.EmitFor(const ANode: TCPForNode);
var
  LStart: string;
  LEnd: string;
  LCmp: string;
  LStep: string;
begin
  EmitExpr(TCPExprNode(ANode.StartExpr));
  LStart := FOutput.ExprResult;

  EmitExpr(TCPExprNode(ANode.EndExpr));
  LEnd := FOutput.ExprResult;

  if ANode.IsDownTo then
  begin
    LCmp := ' >= ';
    LStep := '--';
  end
  else
  begin
    LCmp := ' <= ';
    LStep := '++';
  end;

  FOutput.EmitLine('for (auto ' + ANode.IteratorName + ' = ' + LStart +
    '; ' + ANode.IteratorName + LCmp + LEnd +
    '; ' + LStep + ANode.IteratorName + ') {', otSource);
  FOutput.IndentIn();
  EmitStmtList(ANode.Body);
  FOutput.IndentOut();
  FOutput.EmitLine('}', otSource);
end;

procedure TCPCodegen.EmitRepeat(const ANode: TCPRepeatNode);
begin
  FOutput.EmitLine('do {', otSource);
  FOutput.IndentIn();
  EmitStmtList(ANode.Body);
  FOutput.IndentOut();
  EmitExpr(TCPExprNode(ANode.Condition));
  FOutput.EmitLine('} while (!(' + FOutput.ExprResult + '));', otSource);
end;

procedure TCPCodegen.EmitMatch(const ANode: TCPMatchNode);
var
  I: Integer;
  J: Integer;
  LArm: TCPMatchArmNode;
  LLabel: TCPMatchLabelNode;
  LFirst: Boolean;
  LCond: string;
begin
  EmitExpr(TCPExprNode(ANode.Expr));
  FOutput.EmitLine('{', otSource);
  FOutput.IndentIn();
  FOutput.EmitLine('auto __match = ' + FOutput.ExprResult + ';', otSource);

  for I := 0 to ANode.Arms.Count - 1 do
  begin
    LArm := ANode.Arms[I];

    // Build condition from labels
    LCond := '';
    LFirst := True;
    for J := 0 to LArm.Labels.Count - 1 do
    begin
      LLabel := LArm.Labels[J];
      if not LFirst then
        LCond := LCond + ' || ';
      LFirst := False;

      if LLabel.HighExpr <> nil then
      begin
        // Range label: low..high
        EmitExpr(TCPExprNode(LLabel.LowExpr));
        LCond := LCond + '(__match >= ' + FOutput.ExprResult;
        EmitExpr(TCPExprNode(LLabel.HighExpr));
        LCond := LCond + ' && __match <= ' + FOutput.ExprResult + ')';
      end
      else
      begin
        // Single value
        EmitExpr(TCPExprNode(LLabel.LowExpr));
        LCond := LCond + '__match == ' + FOutput.ExprResult;
      end;
    end;

    if I = 0 then
      FOutput.EmitLine('if (' + LCond + ') {', otSource)
    else
      FOutput.EmitLine('} else if (' + LCond + ') {', otSource);

    FOutput.IndentIn();
    EmitStmtList(LArm.Body);
    FOutput.IndentOut();
  end;

  // Else branch
  if ANode.ElseBody.Count > 0 then
  begin
    FOutput.EmitLine('} else {', otSource);
    FOutput.IndentIn();
    EmitStmtList(ANode.ElseBody);
    FOutput.IndentOut();
  end;

  FOutput.EmitLine('}', otSource);
  FOutput.IndentOut();
  FOutput.EmitLine('}', otSource);
end;

procedure TCPCodegen.EmitReturn(const ANode: TCPReturnNode);
begin
  if ANode.ValueExpr <> nil then
  begin
    EmitExpr(TCPExprNode(ANode.ValueExpr));
    FOutput.EmitLine('return ' + FOutput.ExprResult + ';', otSource);
  end
  else
    FOutput.EmitLine('return;', otSource);
end;

procedure TCPCodegen.EmitGuard(const ANode: TCPGuardNode);
var
  LVarName: string;
begin
  Inc(FGuardCounter);
  LVarName := '__guard_result_' + IntToStr(FGuardCounter);

  FOutput.EmitLine('{', otSource);
  FOutput.IndentIn();
  FOutput.EmitLine('int32_t ' + LVarName + ' = rt_guard([&]() {', otSource);
  FOutput.IndentIn();
  EmitStmtList(ANode.GuardBody);
  FOutput.IndentOut();
  FOutput.EmitLine('});', otSource);

  // Except block
  if ANode.ExceptBody.Count > 0 then
  begin
    FOutput.EmitLine('if (' + LVarName + ' != RT_EXC_NONE) {', otSource);
    FOutput.IndentIn();
    EmitStmtList(ANode.ExceptBody);
    FOutput.IndentOut();
    FOutput.EmitLine('}', otSource);
  end;

  // Finally block
  if ANode.FinallyBody.Count > 0 then
    EmitStmtList(ANode.FinallyBody);

  FOutput.IndentOut();
  FOutput.EmitLine('}', otSource);
end;

procedure TCPCodegen.EmitThrow(const ANode: TCPThrowNode);
begin
  EmitExpr(TCPExprNode(ANode.MessageExpr));
  FOutput.EmitLine('rt_throw(1, ' + FOutput.ExprResult + ');', otSource);
end;

procedure TCPCodegen.EmitThrowCode(const ANode: TCPThrowCodeNode);
var
  LCode: string;
begin
  EmitExpr(TCPExprNode(ANode.CodeExpr));
  LCode := FOutput.ExprResult;

  EmitExpr(TCPExprNode(ANode.MessageExpr));
  FOutput.EmitLine('rt_throw(' + LCode + ', ' + FOutput.ExprResult + ');', otSource);
end;

procedure TCPCodegen.EmitPrint(const ANode: TCPPrintNode);
var
  LFmtExpr: string;
  LArgs: string;
  LArgExpr: string;
  I: Integer;
begin
  // First arg is the format string, remaining args are format arguments
  if ANode.Args.Count = 0 then
  begin
    if ANode.IsLn then
      FOutput.EmitLine('std::println("");', otSource)
    else
      FOutput.EmitLine('std::print("");', otSource);
    Exit;
  end;

  // Emit format string (first argument)
  EmitExpr(TCPExprNode(ANode.Args[0]));
  LFmtExpr := FOutput.ExprResult;

  // Emit remaining arguments
  LArgs := '';
  for I := 1 to ANode.Args.Count - 1 do
  begin
    EmitExpr(TCPExprNode(ANode.Args[I]));
    LArgExpr := FOutput.ExprResult;

    // Bit-field members cannot bind to forwarding references (std::println
    // takes Args&&...). Wrap in static_cast to produce a prvalue.
    if (ANode.Args[I] is TCPDotAccessNode) and
       (TCPDotAccessNode(ANode.Args[I]).AccessKind = dakField) and
       (TCPDotAccessNode(ANode.Args[I]).ResolvedDecl is TCPFieldDeclNode) and
       (TCPFieldDeclNode(TCPDotAccessNode(ANode.Args[I]).ResolvedDecl).BitWidth > 0) then
      LArgExpr := 'static_cast<' + EmitTypeExpr(TCPExprNode(ANode.Args[I]).ResolvedType) + '>(' + LArgExpr + ')';

    if LArgs <> '' then
      LArgs := LArgs + ', ';
    LArgs := LArgs + LArgExpr;
  end;

  if ANode.IsLn then
    FOutput.EmitLine('std::println(' + LFmtExpr +
      IfThen(LArgs <> '', ', ' + LArgs, '') + ');', otSource)
  else
    FOutput.EmitLine('std::print(' + LFmtExpr +
      IfThen(LArgs <> '', ', ' + LArgs, '') + ');', otSource);
end;

procedure TCPCodegen.EmitAssertStmt(const ANode: TCPAssertStmtNode);
var
  LArg0: string;
  LArg1: string;
  LArg2: string;
begin
  case ANode.AssertKind of
    akAssert:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.EmitLine('rt_test_assert_impl(' + FOutput.ExprResult +
        ', __FILE__, __LINE__);', otSource);
    end;
    akTrue:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.EmitLine('rt_test_assert_true_impl(' + FOutput.ExprResult +
        ', __FILE__, __LINE__);', otSource);
    end;
    akFalse:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.EmitLine('rt_test_assert_false_impl(' + FOutput.ExprResult +
        ', __FILE__, __LINE__);', otSource);
    end;
    akEq:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      LArg0 := FOutput.ExprResult;
      EmitExpr(TCPExprNode(ANode.Args[1]));
      LArg1 := FOutput.ExprResult;

      // Cast expected to match actual's type for C++ template deduction
      if (TCPExprNode(ANode.Args[0]).ResolvedType <> nil) and
         (TCPExprNode(ANode.Args[1]).ResolvedType <> nil) and
         (TCPExprNode(ANode.Args[0]).ResolvedType <> TCPExprNode(ANode.Args[1]).ResolvedType) then
        LArg0 := 'static_cast<' + EmitTypeExpr(TCPExprNode(ANode.Args[1]).ResolvedType) + '>(' + LArg0 + ')';

      FOutput.EmitLine('rt_test_assert_cmp(' + LArg0 + ', ' + LArg1 +
        ', RT_CMP_EQ, nullptr, __FILE__, __LINE__);', otSource);
    end;
    akEqF:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      LArg0 := FOutput.ExprResult;
      EmitExpr(TCPExprNode(ANode.Args[1]));
      LArg1 := FOutput.ExprResult;
      EmitExpr(TCPExprNode(ANode.Args[2]));
      LArg2 := FOutput.ExprResult;
      FOutput.EmitLine('rt_test_assert_cmp_float_tol(' + LArg0 + ', ' + LArg1 +
        ', ' + LArg2 + ', RT_CMP_EQ, nullptr, __FILE__, __LINE__);', otSource);
    end;
    akNil:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.EmitLine('rt_test_assert_nil_impl(' + FOutput.ExprResult +
        ', __FILE__, __LINE__);', otSource);
    end;
    akNotNil:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.EmitLine('rt_test_assert_not_nil_impl(' + FOutput.ExprResult +
        ', __FILE__, __LINE__);', otSource);
    end;
    akFail:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.EmitLine('rt_test_fail_impl(' + FOutput.ExprResult +
        ', __FILE__, __LINE__);', otSource);
    end;
  end;
end;

procedure TCPCodegen.EmitBreak();
begin
  FOutput.EmitLine('break;', otSource);
end;

procedure TCPCodegen.EmitContinue();
begin
  FOutput.EmitLine('continue;', otSource);
end;

{ TCPCodegen.EmitCppBlock }
procedure TCPCodegen.EmitCppBlock(const ANode: TCPCppBlockNode);
var
  LTarget: TCPOutputTarget;
begin
  if ANode.Target = 'header' then
    LTarget := otHeader
  else
    LTarget := otSource;

  FOutput.EmitRaw(ANode.RawText + sLineBreak, LTarget);
end;

{ TCPCodegen.EmitCppExpr }
procedure TCPCodegen.EmitCppExpr(const ANode: TCPCppExprNode);
begin
  // The argument is a string literal -- use its raw value as C++ expression
  if ANode.ArgExpr is TCPStringLiteralNode then
    FOutput.ExprResult := TCPStringLiteralNode(ANode.ArgExpr).StringValue
  else
  begin
    // Fallback: emit as expression (shouldn't happen in practice)
    EmitExpr(ANode.ArgExpr);
  end;
end;

// Memory statements

procedure TCPCodegen.EmitCreate(const ANode: TCPCreateNode);
begin
  EmitExpr(TCPExprNode(ANode.ArgExpr));
  FOutput.EmitLine('rt_create(' + FOutput.ExprResult + ');', otSource);
end;

procedure TCPCodegen.EmitDestroy(const ANode: TCPDestroyNode);
begin
  EmitExpr(TCPExprNode(ANode.ArgExpr));
  FOutput.EmitLine('rt_destroy(' + FOutput.ExprResult + ');', otSource);
end;

procedure TCPCodegen.EmitGetMem(const ANode: TCPGetMemNode);
var
  LPtr: string;
  LPtrCppType: string;
  LTargetType: string;
  LResolved: TCPASTNode;
  LPointerNode: TCPPointerTypeNode;
begin
  EmitExpr(TCPExprNode(ANode.ArgExpr));
  LPtr := FOutput.ExprResult;

  // getmem(ptr) -> ptr = static_cast<T*>(rt_getmem(sizeof(T)))
  // ResolvedType may be TCPTypeDeclNode(TypeDef=PointerTypeNode) or
  // TCPPointerTypeNode directly, or TCPTypeRefNode -> ResolvedDecl -> TypeDeclNode
  LPtrCppType := '';
  LTargetType := '';
  LPointerNode := nil;
  LResolved := TCPExprNode(ANode.ArgExpr).ResolvedType;

  // Follow TCPTypeRefNode -> ResolvedDecl
  if (LResolved <> nil) and (LResolved is TCPTypeRefNode) and
     (TCPTypeRefNode(LResolved).ResolvedDecl <> nil) then
    LResolved := TCPTypeRefNode(LResolved).ResolvedDecl;

  // Follow TCPTypeDeclNode -> TypeDef
  if (LResolved <> nil) and (LResolved is TCPTypeDeclNode) and
     (TCPTypeDeclNode(LResolved).TypeDef is TCPPointerTypeNode) then
    LPointerNode := TCPPointerTypeNode(TCPTypeDeclNode(LResolved).TypeDef)
  else if (LResolved <> nil) and (LResolved is TCPPointerTypeNode) then
    LPointerNode := TCPPointerTypeNode(LResolved);

  if (LPointerNode <> nil) and (LPointerNode.TargetType <> nil) then
  begin
    LTargetType := EmitTypeExpr(LPointerNode.TargetType);
    LPtrCppType := LTargetType + '*';
  end;

  if LPtrCppType <> '' then
    FOutput.EmitLine(LPtr + ' = static_cast<' + LPtrCppType + '>(rt_getmem(sizeof(' + LTargetType + ')));', otSource)
  else
    FOutput.EmitLine(LPtr + ' = rt_getmem(1);', otSource);
end;

procedure TCPCodegen.EmitFreeMem(const ANode: TCPFreeMemNode);
begin
  EmitExpr(TCPExprNode(ANode.ArgExpr));
  FOutput.EmitLine('rt_freemem(' + FOutput.ExprResult + ');', otSource);
end;

procedure TCPCodegen.EmitResizeMem(const ANode: TCPResizeMemNode);
var
  LPtr: string;
  LSize: string;
  LPtrType: string;
  LResolved: TCPASTNode;
  LPointerNode: TCPPointerTypeNode;
begin
  EmitExpr(TCPExprNode(ANode.PtrExpr));
  LPtr := FOutput.ExprResult;

  EmitExpr(TCPExprNode(ANode.SizeExpr));
  LSize := FOutput.ExprResult;

  // resizemem(ptr, size) -> ptr = static_cast<T*>(rt_resizemem(ptr, size))
  LPtrType := '';
  LPointerNode := nil;
  LResolved := TCPExprNode(ANode.PtrExpr).ResolvedType;

  // Follow TCPTypeRefNode -> ResolvedDecl
  if (LResolved <> nil) and (LResolved is TCPTypeRefNode) and
     (TCPTypeRefNode(LResolved).ResolvedDecl <> nil) then
    LResolved := TCPTypeRefNode(LResolved).ResolvedDecl;

  // Follow TCPTypeDeclNode -> TypeDef
  if (LResolved <> nil) and (LResolved is TCPTypeDeclNode) and
     (TCPTypeDeclNode(LResolved).TypeDef is TCPPointerTypeNode) then
    LPointerNode := TCPPointerTypeNode(TCPTypeDeclNode(LResolved).TypeDef)
  else if (LResolved <> nil) and (LResolved is TCPPointerTypeNode) then
    LPointerNode := TCPPointerTypeNode(LResolved);

  if (LPointerNode <> nil) and (LPointerNode.TargetType <> nil) then
    LPtrType := EmitTypeExpr(LPointerNode.TargetType) + '*';

  if LPtrType <> '' then
    FOutput.EmitLine(LPtr + ' = static_cast<' + LPtrType + '>(rt_resizemem(' + LPtr + ', ' + LSize + '));', otSource)
  else
    FOutput.EmitLine(LPtr + ' = rt_resizemem(' + LPtr + ', ' + LSize + ');', otSource);
end;

procedure TCPCodegen.EmitSetLength(const ANode: TCPSetLengthNode);
var
  LTarget: string;
  LLen: string;
  LPtrType: string;
  LResolved: TCPASTNode;
  LPointerNode: TCPPointerTypeNode;
begin
  EmitExpr(TCPExprNode(ANode.TargetExpr));
  LTarget := FOutput.ExprResult;

  EmitExpr(TCPExprNode(ANode.LengthExpr));
  LLen := FOutput.ExprResult;

  // Check if target is a pointer type -- use rt_resizemem instead of .resize()
  LPtrType := '';
  LPointerNode := nil;
  LResolved := TCPExprNode(ANode.TargetExpr).ResolvedType;

  // Follow TCPTypeRefNode -> ResolvedDecl
  if (LResolved <> nil) and (LResolved is TCPTypeRefNode) and
     (TCPTypeRefNode(LResolved).ResolvedDecl <> nil) then
    LResolved := TCPTypeRefNode(LResolved).ResolvedDecl;

  // Follow TCPTypeDeclNode -> TypeDef
  if (LResolved <> nil) and (LResolved is TCPTypeDeclNode) and
     (TCPTypeDeclNode(LResolved).TypeDef is TCPPointerTypeNode) then
    LPointerNode := TCPPointerTypeNode(TCPTypeDeclNode(LResolved).TypeDef)
  else if (LResolved <> nil) and (LResolved is TCPPointerTypeNode) then
    LPointerNode := TCPPointerTypeNode(LResolved);

  if (LPointerNode <> nil) and (LPointerNode.TargetType <> nil) then
    LPtrType := EmitTypeExpr(LPointerNode.TargetType) + '*';

  if LPtrType <> '' then
    FOutput.EmitLine(LTarget + ' = static_cast<' + LPtrType + '>(rt_resizemem(' + LTarget + ', ' + LLen + '));', otSource)
  else
    FOutput.EmitLine(LTarget + '.resize(' + LLen + ');', otSource);
end;

// Expression dispatch

procedure TCPCodegen.EmitExpr(const ANode: TCPASTNode);
begin
  if ANode = nil then
  begin
    FOutput.ExprResult := '';
    Exit;
  end;

  if ANode is TCPBinaryExprNode then
    EmitBinaryExpr(TCPBinaryExprNode(ANode))
  else if ANode is TCPUnaryExprNode then
    EmitUnaryExpr(TCPUnaryExprNode(ANode))
  else if ANode is TCPIntLiteralNode then
    EmitIntLiteral(TCPIntLiteralNode(ANode))
  else if ANode is TCPFloatLiteralNode then
    EmitFloatLiteral(TCPFloatLiteralNode(ANode))
  else if ANode is TCPStringLiteralNode then
    EmitStringLiteral(TCPStringLiteralNode(ANode))
  else if ANode is TCPWStringLiteralNode then
    EmitWStringLiteral(TCPWStringLiteralNode(ANode))
  else if ANode is TCPBoolLiteralNode then
    EmitBoolLiteral(TCPBoolLiteralNode(ANode))
  else if ANode is TCPNilLiteralNode then
    EmitNilLiteral()
  else if ANode is TCPIdentifierNode then
    EmitIdentifier(TCPIdentifierNode(ANode))
  else if ANode is TCPDotAccessNode then
    EmitDotAccess(TCPDotAccessNode(ANode))
  else if ANode is TCPIndexAccessNode then
    EmitIndexAccess(TCPIndexAccessNode(ANode))
  else if ANode is TCPDerefNode then
    EmitDeref(TCPDerefNode(ANode))
  else if ANode is TCPCallExprNode then
    EmitCallExpr(TCPCallExprNode(ANode))
  else if ANode is TCPTypeCastExprNode then
    EmitTypeCast(TCPTypeCastExprNode(ANode))
  else if ANode is TCPIntrinsicExprNode then
    EmitIntrinsic(TCPIntrinsicExprNode(ANode))
  else if ANode is TCPSetLiteralExprNode then
    EmitSetLiteral(TCPSetLiteralExprNode(ANode))
  else if ANode is TCPRecordLiteralNode then
    EmitRecordLiteral(TCPRecordLiteralNode(ANode))
  else if ANode is TCPCppExprNode then
    EmitCppExpr(TCPCppExprNode(ANode))
  else
    FOutput.ExprResult := '/* unknown expr */';
end;

// Expression emitters

procedure TCPCodegen.EmitBinaryExpr(const ANode: TCPBinaryExprNode);
var
  LLeft: string;
  LRight: string;
  LOp: string;
begin
  EmitExpr(ANode.Left);
  LLeft := FOutput.ExprResult;

  EmitExpr(ANode.Right);
  LRight := FOutput.ExprResult;

  case ANode.Op of
    boAdd:        LOp := ' + ';
    boSub:        LOp := ' - ';
    boMul:        LOp := ' * ';
    boDiv:        LOp := ' / ';
    boIntDiv:     LOp := ' / ';
    boMod:        LOp := ' % ';
    boAnd:        LOp := ' & ';
    boOr:         LOp := ' | ';
    boXor:        LOp := ' ^ ';
    boLogicalAnd: LOp := ' && ';
    boLogicalOr:  LOp := ' || ';
    boShl:        LOp := ' << ';
    boShr:        LOp := ' >> ';
    boEq:         LOp := ' == ';
    boNotEq:      LOp := ' != ';
    boLess:       LOp := ' < ';
    boGreater:    LOp := ' > ';
    boLessEq:     LOp := ' <= ';
    boGreaterEq:  LOp := ' >= ';
    boIn:
    begin
      FOutput.ExprResult := 'rt_contains(' + LRight + ', ' + LLeft + ')';
      Exit;
    end;
  end;

  FOutput.ExprResult := '(' + LLeft + LOp + LRight + ')';
end;

procedure TCPCodegen.EmitUnaryExpr(const ANode: TCPUnaryExprNode);
begin
  EmitExpr(ANode.Operand);

  case ANode.Op of
    uoNot:       FOutput.ExprResult := '!' + FOutput.ExprResult;
    uoNegate:    FOutput.ExprResult := '-' + FOutput.ExprResult;
    uoPositive:  ; // no-op, ExprResult unchanged
    uoAddressOf: FOutput.ExprResult := '&' + FOutput.ExprResult;
  end;
end;

procedure TCPCodegen.EmitIntLiteral(const ANode: TCPIntLiteralNode);
begin
  FOutput.ExprResult := IntToStr(ANode.IntValue);
end;

procedure TCPCodegen.EmitFloatLiteral(const ANode: TCPFloatLiteralNode);
begin
  FOutput.ExprResult := FloatToStr(ANode.FloatValue);
  // Ensure decimal point
  if not FOutput.ExprResult.Contains('.') then
    FOutput.ExprResult := FOutput.ExprResult + '.0';
  if ANode.HasSuffix then
    FOutput.ExprResult := FOutput.ExprResult + 'f';
end;

procedure TCPCodegen.EmitStringLiteral(const ANode: TCPStringLiteralNode);
begin
  // Char coercion: single-char string assigned to char emits 'x' not "x"
  if (ANode.ResolvedType <> nil) and
     (ANode.ResolvedType is TCPTypeDeclNode) and
     (TCPTypeDeclNode(ANode.ResolvedType).PrimitiveKind = tkChar) then
    FOutput.ExprResult := '''' + cpEscapeCppString(ANode.StringValue) + ''''
  else
    FOutput.ExprResult := '"' + cpEscapeCppString(ANode.StringValue) + '"';
end;

procedure TCPCodegen.EmitWStringLiteral(const ANode: TCPWStringLiteralNode);
begin
  // WChar coercion: single-char wstring assigned to wchar emits u'x' not L"x"
  if (ANode.ResolvedType <> nil) and
     (ANode.ResolvedType is TCPTypeDeclNode) and
     (TCPTypeDeclNode(ANode.ResolvedType).PrimitiveKind = tkWChar) then
    FOutput.ExprResult := 'u''' + cpEscapeCppString(ANode.StringValue) + ''''
  else
    FOutput.ExprResult := 'L"' + cpEscapeCppString(ANode.StringValue) + '"';
end;

procedure TCPCodegen.EmitBoolLiteral(const ANode: TCPBoolLiteralNode);
begin
  if ANode.BoolValue then
    FOutput.ExprResult := 'true'
  else
    FOutput.ExprResult := 'false';
end;

procedure TCPCodegen.EmitNilLiteral();
begin
  FOutput.ExprResult := 'nullptr';
end;

procedure TCPCodegen.EmitIdentifier(const ANode: TCPIdentifierNode);
begin
  FOutput.ExprResult := ANode.IdentName;
end;

procedure TCPCodegen.EmitDotAccess(const ANode: TCPDotAccessNode);
begin
  case ANode.AccessKind of
    dakModule:
      // Module-qualified: just emit the member name (include handles visibility)
      FOutput.ExprResult := ANode.MemberName;
    dakChoices:
    begin
      // Choices member: TypeName::MemberName (but C enum, not enum class, so just MemberName)
      FOutput.ExprResult := ANode.MemberName;
    end;
    dakField:
    begin
      // Record field: base.member
      EmitExpr(TCPExprNode(ANode.BaseExpr));
      FOutput.ExprResult := FOutput.ExprResult + '.' + ANode.MemberName;
    end;
  else
    // Default to field access
    EmitExpr(TCPExprNode(ANode.BaseExpr));
    FOutput.ExprResult := FOutput.ExprResult + '.' + ANode.MemberName;
  end;
end;

procedure TCPCodegen.EmitIndexAccess(const ANode: TCPIndexAccessNode);
var
  LBase: string;
begin
  EmitExpr(TCPExprNode(ANode.BaseExpr));
  LBase := FOutput.ExprResult;

  EmitExpr(TCPExprNode(ANode.IndexExpr));
  FOutput.ExprResult := LBase + '[' + FOutput.ExprResult + ']';
end;

procedure TCPCodegen.EmitDeref(const ANode: TCPDerefNode);
begin
  EmitExpr(TCPExprNode(ANode.BaseExpr));
  FOutput.ExprResult := '(*' + FOutput.ExprResult + ')';
end;

procedure TCPCodegen.EmitCallExpr(const ANode: TCPCallExprNode);
var
  LCallee: string;
  LArgs: string;
  I: Integer;
begin
  EmitExpr(TCPExprNode(ANode.Callee));
  LCallee := FOutput.ExprResult;

  LArgs := '';
  for I := 0 to ANode.Args.Count - 1 do
  begin
    EmitExpr(TCPExprNode(ANode.Args[I]));
    if I > 0 then
      LArgs := LArgs + ', ';
    LArgs := LArgs + FOutput.ExprResult;
  end;

  FOutput.ExprResult := LCallee + '(' + LArgs + ')';
end;

procedure TCPCodegen.EmitTypeCast(const ANode: TCPTypeCastExprNode);
var
  LType: string;
begin
  LType := EmitTypeExpr(ANode.TargetType);
  EmitExpr(TCPExprNode(ANode.Expr));
  FOutput.ExprResult := 'static_cast<' + LType + '>(' + FOutput.ExprResult + ')';
end;

procedure TCPCodegen.EmitIntrinsic(const ANode: TCPIntrinsicExprNode);
begin
  case ANode.IntrinsicKind of
    ikLen:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.ExprResult := 'rt_len(' + FOutput.ExprResult + ')';
    end;
    ikSize:
    begin
      if ANode.Args[0] is TCPTypeRefNode then
        FOutput.ExprResult := 'sizeof(' + EmitTypeExpr(ANode.Args[0]) + ')'
      else
      begin
        EmitExpr(TCPExprNode(ANode.Args[0]));
        FOutput.ExprResult := 'sizeof(' + FOutput.ExprResult + ')';
      end;
    end;
    ikUtf8:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.ExprResult := 'rt_utf8(' + FOutput.ExprResult + ')';
    end;
    ikCStr:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.ExprResult := 'const_cast<char*>(' + FOutput.ExprResult + '.c_str())';
    end;
    ikWStr:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.ExprResult := 'rt_wstr(' + FOutput.ExprResult + ')';
    end;
    ikParamCount:
      FOutput.ExprResult := 'rt_paramcount()';
    ikParamStr:
    begin
      EmitExpr(TCPExprNode(ANode.Args[0]));
      FOutput.ExprResult := 'rt_paramstr(' + FOutput.ExprResult + ')';
    end;
    ikExcCode:
      FOutput.ExprResult := 'rt_exc_code()';
    ikExcMsg:
      FOutput.ExprResult := 'rt_exc_msg()';
  end;
end;

procedure TCPCodegen.EmitSetLiteral(const ANode: TCPSetLiteralExprNode);
var
  I: Integer;
  LElem: TCPSetElementNode;
  LParts: string;
begin
  if ANode.Elements.Count = 0 then
  begin
    FOutput.ExprResult := 'RtSet()';
    Exit;
  end;

  LParts := '';
  for I := 0 to ANode.Elements.Count - 1 do
  begin
    LElem := ANode.Elements[I];
    if LParts <> '' then
      LParts := LParts + ' + ';

    if LElem.HighExpr <> nil then
    begin
      // Range element
      EmitExpr(TCPExprNode(LElem.LowExpr));
      LParts := LParts + 'rt_range(' + FOutput.ExprResult;
      EmitExpr(TCPExprNode(LElem.HighExpr));
      LParts := LParts + ', ' + FOutput.ExprResult + ')';
    end
    else
    begin
      // Single element
      EmitExpr(TCPExprNode(LElem.LowExpr));
      LParts := LParts + 'rt_elem(' + FOutput.ExprResult + ')';
    end;
  end;

  FOutput.ExprResult := LParts;
end;

procedure TCPCodegen.EmitRecordLiteral(const ANode: TCPRecordLiteralNode);
var
  I: Integer;
  LInit: TCPFieldInitNode;
  LParts: string;
begin
  LParts := '';
  for I := 0 to ANode.FieldInits.Count - 1 do
  begin
    LInit := ANode.FieldInits[I];
    if LInit.ValueExpr <> nil then
    begin
      EmitExpr(TCPExprNode(LInit.ValueExpr));
      if LParts <> '' then
        LParts := LParts + ', ';
      LParts := LParts + '.' + LInit.FieldName + ' = ' + FOutput.ExprResult;
    end;
  end;

  FOutput.ExprResult := ANode.TypeName + '{' + LParts + '}';
end;

// Type expression emission

function TCPCodegen.EmitTypeExpr(const ANode: TCPASTNode): string;
var
  LArr: TCPArrayTypeNode;
  LPtr: TCPPointerTypeNode;
  LRtn: TCPRoutineTypeNode;
  I: Integer;
  LParams: string;
  LRetType: string;
begin
  if ANode = nil then
  begin
    Result := 'void';
    Exit;
  end;

  if ANode is TCPTypeRefNode then
  begin
    // Primitive types have CppTypeText set by the parser
    if TCPTypeRefNode(ANode).CppTypeText <> '' then
      Result := TCPTypeRefNode(ANode).CppTypeText
    // User-defined types: follow ResolvedDecl to the type declaration
    else if TCPTypeRefNode(ANode).ResolvedDecl is TCPTypeDeclNode then
      Result := TCPTypeDeclNode(TCPTypeRefNode(ANode).ResolvedDecl).DeclName
    else
      Result := 'auto'; // fallback
  end
  else if ANode is TCPArrayTypeNode then
  begin
    LArr := TCPArrayTypeNode(ANode);
    if LArr.IsDynamic then
      Result := 'std::vector<' + EmitTypeExpr(LArr.ElementType) + '>'
    else
      Result := 'std::array<' + EmitTypeExpr(LArr.ElementType) + ', ' +
        IntToStr(LArr.HighBound - LArr.LowBound + 1) + '>';
  end
  else if ANode is TCPPointerTypeNode then
  begin
    LPtr := TCPPointerTypeNode(ANode);
    if LPtr.TargetType = nil then
      Result := 'void*'
    else
      Result := EmitTypeExpr(LPtr.TargetType) + '*';
  end
  else if ANode is TCPSetTypeNode then
  begin
    Result := 'RtSet';
  end
  else if ANode is TCPRoutineTypeNode then
  begin
    LRtn := TCPRoutineTypeNode(ANode);
    if LRtn.ReturnType <> nil then
      LRetType := EmitTypeExpr(LRtn.ReturnType)
    else
      LRetType := 'void';

    LParams := '';
    for I := 0 to LRtn.Params.Count - 1 do
    begin
      if I > 0 then
        LParams := LParams + ', ';
      LParams := LParams + EmitTypeExpr(LRtn.Params[I].TypeExpr);
    end;

    Result := LRetType + '(*)(' + LParams + ')';
  end
  else if ANode is TCPTypeDeclNode then
  begin
    if TCPTypeDeclNode(ANode).CppTypeName <> '' then
      Result := TCPTypeDeclNode(ANode).CppTypeName
    else
      Result := TCPTypeDeclNode(ANode).DeclName;
  end
  else
    Result := 'auto'; // fallback for unknown types
end;

// Helper: escape a string for C++ string literal
function cpEscapeCppString(const AValue: string): string;
var
  I: Integer;
  LCh: Char;
begin
  Result := '';
  for I := 1 to Length(AValue) do
  begin
    LCh := AValue[I];
    if LCh = '\' then
      Result := Result + '\\'
    else if LCh = '"' then
      Result := Result + '\"'
    else if LCh = #10 then
      Result := Result + '\n'
    else if LCh = #13 then
      Result := Result + '\r'
    else if LCh = #9 then
      Result := Result + '\t'
    else if LCh = #0 then
      Result := Result + '\0'
    else
      Result := Result + LCh;
  end;
end;

// Helper: emit anonymous struct/union fields
procedure TCPCodegen.EmitAnonFields(const AFields: TObjectList<TCPASTNode>; const ATarget: TCPOutputTarget);
var
  I: Integer;
  LField: TCPFieldDeclNode;
begin
  for I := 0 to AFields.Count - 1 do
  begin
    if AFields[I] is TCPFieldDeclNode then
    begin
      LField := TCPFieldDeclNode(AFields[I]);
      if LField.BitWidth > 0 then
        FOutput.EmitLine(EmitTypeExpr(LField.TypeExpr) + ' ' + LField.FieldName +
          ' : ' + IntToStr(LField.BitWidth) + ';', ATarget)
      else
        FOutput.EmitLine(EmitTypeExpr(LField.TypeExpr) + ' ' + LField.FieldName + ';', ATarget);
    end
    else if AFields[I] is TCPAnonRecordNode then
    begin
      FOutput.EmitLine('struct {', ATarget);
      FOutput.IndentIn();
      EmitAnonFields(TCPAnonRecordNode(AFields[I]).Fields, ATarget);
      FOutput.IndentOut();
      FOutput.EmitLine('};', ATarget);
    end
    else if AFields[I] is TCPAnonOverlayNode then
    begin
      FOutput.EmitLine('union {', ATarget);
      FOutput.IndentIn();
      EmitAnonFields(TCPAnonOverlayNode(AFields[I]).Fields, ATarget);
      FOutput.IndentOut();
      FOutput.EmitLine('};', ATarget);
    end;
  end;
end;

end.
