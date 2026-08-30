{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.Script - Script engine and interpreter

  Provides a CPaskal scripting engine that reuses the existing lexer, parser,
  and semantic pipeline via inheritance. Scripts use `module script <name>;`
  syntax and are interpreted via a tree-walking AST interpreter.

  Dependencies: StdApp.Base, CPaskal.Common, CPaskal.AST, CPaskal.Parser
===============================================================================}
unit CPaskal.Script;

interface

uses
  System.SysUtils,
  System.IOUtils,
  System.Rtti,
  System.Generics.Collections,
  StdApp.Utils,
  StdApp.Base,
  CPaskal.Common,
  CPaskal.AST,
  CPaskal.Parser,
  CPaskal.Semantics;

const
  CP_ERR_SCR_001 = 'SCR001';  // Script file not found
  CP_ERR_SCR_002 = 'SCR002';  // Invalid routine/data declaration
  CP_ERR_SCR_003 = 'SCR003';  // Registration not a routine/data node
  CP_ERR_SCR_004 = 'SCR004';  // Runtime error during execution

type
  // Class forwards
  TCPScriptInterpreter = class;

  { TCPScriptSignal }
  TCPScriptSignal = (
    ssNone,
    ssReturn,
    ssBreak,
    ssContinue
  );

  { TCPScriptValue }
  TCPScriptValue = TValue;

  { TCPScriptArgs }
  TCPScriptArgs = TArray<TCPScriptValue>;

  { TCPScriptRoutineFunc }
  TCPScriptRoutineFunc = reference to function(
    const AArgs: TCPScriptArgs;
    const AInterpreter: TCPScriptInterpreter;
    const AUserData: Pointer): TCPScriptValue;

  { TCPScriptPrintCallback }
  TCPScriptPrintCallback = reference to procedure(
    const AText: string; const ANewLine: Boolean; const AUserData: Pointer);

  { TCPScriptVarEntry }
  TCPScriptVarEntry = record
    Value: TCPScriptValue;
    IsConst: Boolean;
  end;

  { TCPScriptRecord }
  // Runtime representation of a CPaskal record value.
  // Fields stored by name; TypeName tracks the declared type for identity.
  TCPScriptRecord = class(TBaseObject)
  private
    FTypeName: string;
    FFields: TDictionary<string, TValue>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function GetField(const AName: string): TValue;
    procedure SetField(const AName: string; const AValue: TValue);
    function HasField(const AName: string): Boolean;
    function Clone(): TCPScriptRecord;
    property TypeName: string read FTypeName write FTypeName;
    property Fields: TDictionary<string, TValue> read FFields;
  end;

  { TCPScriptArray }
  // Runtime representation of a CPaskal array value.
  // Supports both static (fixed bounds) and dynamic (growable) arrays.
  TCPScriptArray = class(TBaseObject)
  private
    FElements: TList<TValue>;
    FLowBound: Int64;
    FIsDynamic: Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    function GetElement(const AIndex: Int64): TValue;
    procedure SetElement(const AIndex: Int64; const AValue: TValue);
    function GetCount(): Int64;
    procedure Resize(const ANewLength: Int64);
    function Clone(): TCPScriptArray;
    property Elements: TList<TValue> read FElements;
    property LowBound: Int64 read FLowBound write FLowBound;
    property IsDynamic: Boolean read FIsDynamic write FIsDynamic;
  end;

  { TCPScriptSet }
  // Runtime representation of a CPaskal set value.
  // Stores members as sorted Int64 for fast membership testing.
  TCPScriptSet = class(TBaseObject)
  private
    FMembers: TList<Int64>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Add(const AValue: Int64);
    procedure AddRange(const ALow: Int64; const AHigh: Int64);
    function Contains(const AValue: Int64): Boolean;
    function Clone(): TCPScriptSet;
    property Members: TList<Int64> read FMembers;
  end;

  { TCPScriptBuffer }
  // Runtime representation of a raw memory buffer for getmem/freemem/resizemem.
  TCPScriptBuffer = class(TBaseObject)
  private
    FData: TBytes;
    FSize: Int64;
  public
    constructor Create(); override;
    procedure Allocate(const ASize: Int64);
    procedure Resize(const ANewSize: Int64);
    property Data: TBytes read FData;
    property Size: Int64 read FSize;
  end;

  { TCPScriptScope }
  TCPScriptScope = class
  private
    FVars: TDictionary<string, TCPScriptVarEntry>;
    FParent: TCPScriptScope;
  public
    constructor Create(const AParent: TCPScriptScope);
    destructor Destroy(); override;
    property Vars: TDictionary<string, TCPScriptVarEntry> read FVars;
    property Parent: TCPScriptScope read FParent;
  end;

  { TCPScriptEnvironment }
  TCPScriptEnvironment = class(TBaseObject)
  private
    FCurrent: TCPScriptScope;
    FScopes: TObjectList<TCPScriptScope>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure PushScope();
    procedure PopScope();
    function DeclareVar(const AName: string; const AValue: TCPScriptValue;
      const AIsConst: Boolean = False): Boolean;
    function UpdateVar(const AName: string; const AValue: TCPScriptValue): Boolean;
    function TryGetVar(const AName: string; out AValue: TCPScriptValue): Boolean;
    property CurrentScope: TCPScriptScope read FCurrent;
  end;

  { TCPScriptParser }
  TCPScriptParser = class(TCPParser)
  protected
    function DoParseModuleKind(): TCPModuleKind; override;
  end;

  { TCPScriptInterpreter }
  TCPScriptInterpreter = class(TBaseObject)
  private
    FEnvironment: TCPScriptEnvironment;
    FSignal: TCPScriptSignal;
    FReturnValue: TCPScriptValue;
    FFuncs: TDictionary<TCPRoutineDeclNode, TCallback<TCPScriptRoutineFunc>>;
    FPrintCallback: TCallback<TCPScriptPrintCallback>;
    FCurrentExcCode: Int64;
    FCurrentExcMsg: string;

    // Core dispatch
    procedure ExecNode(const ANode: TCPASTNode);
    procedure ExecStmtList(const AList: TObjectList<TCPASTNode>);
    function EvalExpr(const ANode: TCPASTNode): TCPScriptValue;

    // Statement handlers
    procedure ExecConstDecl(const ANode: TCPConstDeclNode);
    procedure ExecVarDecl(const ANode: TCPVarDeclNode);
    procedure ExecRoutineDecl(const ANode: TCPRoutineDeclNode);
    procedure ExecAssign(const ANode: TCPAssignNode);
    procedure ExecCallStmt(const ANode: TCPCallStmtNode);
    procedure ExecIf(const ANode: TCPIfNode);
    procedure ExecWhile(const ANode: TCPWhileNode);
    procedure ExecFor(const ANode: TCPForNode);
    procedure ExecRepeat(const ANode: TCPRepeatNode);
    procedure ExecMatch(const ANode: TCPMatchNode);
    procedure ExecReturn(const ANode: TCPReturnNode);
    procedure ExecGuard(const ANode: TCPGuardNode);
    procedure ExecThrow(const ANode: TCPThrowNode);
    procedure ExecThrowCode(const ANode: TCPThrowCodeNode);
    procedure ExecPrint(const ANode: TCPPrintNode);
    procedure ExecAssertStmt(const ANode: TCPAssertStmtNode);
    procedure ExecSetLength(const ANode: TCPSetLengthNode);
    procedure ExecDirective(const ANode: TCPDirectiveNode);
    procedure ExecNew(const ANode: TCPNewNode);
    procedure ExecDispose(const ANode: TCPDisposeNode);
    procedure ExecGetMem(const ANode: TCPGetMemNode);
    procedure ExecFreeMem(const ANode: TCPFreeMemNode);
    procedure ExecResizeMem(const ANode: TCPResizeMemNode);

    // Expression evaluators
    function EvalBinaryExpr(const ANode: TCPBinaryExprNode): TCPScriptValue;
    function EvalUnaryExpr(const ANode: TCPUnaryExprNode): TCPScriptValue;
    function EvalCallExpr(const ANode: TCPCallExprNode): TCPScriptValue;
    function EvalIdentifier(const ANode: TCPIdentifierNode): TCPScriptValue;
    function EvalIntrinsic(const ANode: TCPIntrinsicExprNode): TCPScriptValue;
    function EvalTypeCast(const ANode: TCPTypeCastExprNode): TCPScriptValue;
    function EvalDotAccess(const ANode: TCPDotAccessNode): TCPScriptValue;
    function EvalIndexAccess(const ANode: TCPIndexAccessNode): TCPScriptValue;
    function EvalDeref(const ANode: TCPDerefNode): TCPScriptValue;
    function EvalSetLiteral(const ANode: TCPSetLiteralExprNode): TCPScriptValue;
    function EvalRecordLiteral(const ANode: TCPRecordLiteralNode): TCPScriptValue;

    // Helpers
    function DoApplyCompoundOp(const AOp: TCPAssignOp; const AOld: TCPScriptValue;
      const ANew: TCPScriptValue): TCPScriptValue;
    function ValueToStr(const AValue: TCPScriptValue): string;
    function ValueToBool(const AValue: TCPScriptValue): Boolean;
    function ValueToInt(const AValue: TCPScriptValue): Int64;
    function ValueToFloat(const AValue: TCPScriptValue): Double;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure RegisterBuiltin(const ANode: TCPRoutineDeclNode;
      const AFunc: TCPScriptRoutineFunc; const AUserData: Pointer = nil);
    function IsBuiltin(const ANode: TCPRoutineDeclNode): Boolean;

    procedure Execute(const AModule: TCPModuleNode);

    property Environment: TCPScriptEnvironment read FEnvironment;
    property Signal: TCPScriptSignal read FSignal;
    property ReturnValue: TCPScriptValue read FReturnValue;
    property PrintCallback: TCallback<TCPScriptPrintCallback> read FPrintCallback write FPrintCallback;
  end;

  { TCPScriptSemantics }
  TCPScriptSemantics = class(TCPSemantics)
  protected
    procedure DoAnalyzeModule(const AModule: TCPModuleNode); override;
  public
    procedure Analyze(const AMasterAST: TCPMasterAST); override;
  end;

  { TCPScriptEngine }
  TCPScriptEngine = class(TBaseObject)
  private
    FExtension: string;
    FParser: TCPScriptParser;
    FSemantics: TCPScriptSemantics;
    FInterpreter: TCPScriptInterpreter;
    FMasterAST: TCPMasterAST;
    FSyntheticDecls: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetExtension(const AExt: string);
    procedure SetPrintCallback(const ACallback: TCPScriptPrintCallback;
      const AUserData: Pointer = nil);
    procedure RegisterGlobalRoutine(const ADeclaration: string;
      const AFunc: TCPScriptRoutineFunc; const AUserData: Pointer = nil);
    procedure RegisterGlobalData(const ADeclaration: string);
    function ExecuteFile(const AFilename: string): Boolean;
    function ExecuteSource(const ASource: string;
      const AFilename: string): Boolean;
  end;

implementation

// -- Composite value wrappers ------------------------------------------------

{ TCPScriptRecord }
constructor TCPScriptRecord.Create();
begin
  inherited;

  FTypeName := '';
  FFields := TDictionary<string, TValue>.Create();
end;

destructor TCPScriptRecord.Destroy();
begin
  FFields.Free();

  inherited;
end;

function TCPScriptRecord.GetField(const AName: string): TValue;
begin
  if not FFields.TryGetValue(AName, Result) then
    raise Exception.CreateFmt('Record field "%s" not found in %s', [AName, FTypeName]);
end;

procedure TCPScriptRecord.SetField(const AName: string; const AValue: TValue);
begin
  FFields.AddOrSetValue(AName, AValue);
end;

function TCPScriptRecord.HasField(const AName: string): Boolean;
begin
  Result := FFields.ContainsKey(AName);
end;

function TCPScriptRecord.Clone(): TCPScriptRecord;
var
  LPair: TPair<string, TValue>;
begin
  Result := TCPScriptRecord.Create();
  Result.FTypeName := FTypeName;
  for LPair in FFields do
    Result.FFields.Add(LPair.Key, LPair.Value);
end;

{ TCPScriptArray }
constructor TCPScriptArray.Create();
begin
  inherited;

  FElements := TList<TValue>.Create();
  FLowBound := 0;
  FIsDynamic := True;
end;

destructor TCPScriptArray.Destroy();
begin
  FElements.Free();

  inherited;
end;

function TCPScriptArray.GetElement(const AIndex: Int64): TValue;
var
  LActual: Int64;
begin
  LActual := AIndex - FLowBound;
  if (LActual < 0) or (LActual >= FElements.Count) then
    raise Exception.CreateFmt('Array index %d out of bounds [%d..%d]',
      [AIndex, FLowBound, FLowBound + FElements.Count - 1]);
  Result := FElements[LActual];
end;

procedure TCPScriptArray.SetElement(const AIndex: Int64; const AValue: TValue);
var
  LActual: Int64;
begin
  LActual := AIndex - FLowBound;
  if (LActual < 0) or (LActual >= FElements.Count) then
    raise Exception.CreateFmt('Array index %d out of bounds [%d..%d]',
      [AIndex, FLowBound, FLowBound + FElements.Count - 1]);
  FElements[LActual] := AValue;
end;

function TCPScriptArray.GetCount(): Int64;
begin
  Result := FElements.Count;
end;

procedure TCPScriptArray.Resize(const ANewLength: Int64);
begin
  while FElements.Count < ANewLength do
    FElements.Add(TValue.Empty);
  while FElements.Count > ANewLength do
    FElements.Delete(FElements.Count - 1);
end;

function TCPScriptArray.Clone(): TCPScriptArray;
var
  LI: Integer;
begin
  Result := TCPScriptArray.Create();
  Result.FLowBound := FLowBound;
  Result.FIsDynamic := FIsDynamic;
  for LI := 0 to FElements.Count - 1 do
    Result.FElements.Add(FElements[LI]);
end;

{ TCPScriptSet }
constructor TCPScriptSet.Create();
begin
  inherited;

  FMembers := TList<Int64>.Create();
end;

destructor TCPScriptSet.Destroy();
begin
  FMembers.Free();

  inherited;
end;

procedure TCPScriptSet.Add(const AValue: Int64);
begin
  if not FMembers.Contains(AValue) then
    FMembers.Add(AValue);
end;

procedure TCPScriptSet.AddRange(const ALow: Int64; const AHigh: Int64);
var
  LI: Int64;
begin
  for LI := ALow to AHigh do
    Add(LI);
end;

function TCPScriptSet.Contains(const AValue: Int64): Boolean;
begin
  Result := FMembers.Contains(AValue);
end;

function TCPScriptSet.Clone(): TCPScriptSet;
var
  LI: Integer;
begin
  Result := TCPScriptSet.Create();
  for LI := 0 to FMembers.Count - 1 do
    Result.FMembers.Add(FMembers[LI]);
end;

{ TCPScriptBuffer }
constructor TCPScriptBuffer.Create();
begin
  inherited Create();

  FSize := 0;
  SetLength(FData, 0);
end;

procedure TCPScriptBuffer.Allocate(const ASize: Int64);
begin
  FSize := ASize;
  SetLength(FData, ASize);
  if ASize > 0 then
    FillChar(FData[0], ASize, 0);
end;

procedure TCPScriptBuffer.Resize(const ANewSize: Int64);
begin
  FSize := ANewSize;
  SetLength(FData, ANewSize);
end;

{ TCPScriptScope }
constructor TCPScriptScope.Create(const AParent: TCPScriptScope);
begin
  inherited Create();

  FVars := TDictionary<string, TCPScriptVarEntry>.Create();
  FParent := AParent;
end;

destructor TCPScriptScope.Destroy();
var
  LEntry: TCPScriptVarEntry;
begin
  // Free any TObject values stored in TValue (composite wrappers)
  for LEntry in FVars.Values do
  begin
    if LEntry.Value.IsObject and (LEntry.Value.AsObject <> nil) and
       not (LEntry.Value.AsObject is TCPASTNode) then
      LEntry.Value.AsObject.Free();
  end;
  FVars.Free();

  inherited;
end;

{ TCPScriptEnvironment }
constructor TCPScriptEnvironment.Create();
begin
  inherited;

  FScopes := TObjectList<TCPScriptScope>.Create(True);
  FCurrent := TCPScriptScope.Create(nil);
  FScopes.Add(FCurrent);
end;

destructor TCPScriptEnvironment.Destroy();
begin
  FScopes.Free();

  inherited;
end;

procedure TCPScriptEnvironment.PushScope();
begin
  FCurrent := TCPScriptScope.Create(FCurrent);
  FScopes.Add(FCurrent);
end;

procedure TCPScriptEnvironment.PopScope();
begin
  if FCurrent.Parent = nil then
    Exit;
  FCurrent := FCurrent.Parent;
end;

function TCPScriptEnvironment.DeclareVar(const AName: string;
  const AValue: TCPScriptValue; const AIsConst: Boolean): Boolean;
var
  LEntry: TCPScriptVarEntry;
begin
  if FCurrent.Vars.ContainsKey(AName) then
    Exit(False);

  LEntry.Value := AValue;
  LEntry.IsConst := AIsConst;
  FCurrent.Vars.Add(AName, LEntry);
  Result := True;
end;

function TCPScriptEnvironment.UpdateVar(const AName: string;
  const AValue: TCPScriptValue): Boolean;
var
  LScope: TCPScriptScope;
  LEntry: TCPScriptVarEntry;
begin
  LScope := FCurrent;
  while LScope <> nil do
  begin
    if LScope.Vars.TryGetValue(AName, LEntry) then
    begin
      if LEntry.IsConst then
        Exit(False);
      // Free old composite wrapper if being replaced
      if LEntry.Value.IsObject and (LEntry.Value.AsObject <> nil) and
         not (LEntry.Value.AsObject is TCPASTNode) then
      begin
        if not AValue.IsObject or (LEntry.Value.AsObject <> AValue.AsObject) then
          LEntry.Value.AsObject.Free();
      end;
      LEntry.Value := AValue;
      LScope.Vars.AddOrSetValue(AName, LEntry);
      Result := True;
      Exit;
    end;
    LScope := LScope.Parent;
  end;
  Result := False;
end;

function TCPScriptEnvironment.TryGetVar(const AName: string;
  out AValue: TCPScriptValue): Boolean;
var
  LScope: TCPScriptScope;
  LEntry: TCPScriptVarEntry;
begin
  LScope := FCurrent;
  while LScope <> nil do
  begin
    if LScope.Vars.TryGetValue(AName, LEntry) then
    begin
      AValue := LEntry.Value;
      Result := True;
      Exit;
    end;
    LScope := LScope.Parent;
  end;
  Result := False;
end;

{ TCPScriptParser }
function TCPScriptParser.DoParseModuleKind(): TCPModuleKind;
var
  LText: string;
begin
  if Current().Kind = tkIdentifier then
  begin
    LText := Current().TokenText;
    if LText = 'script' then
    begin
      Consume();
      Result := mkExe;
      Exit;
    end;
  end;

  Result := inherited;
end;

{ TCPScriptInterpreter }
constructor TCPScriptInterpreter.Create();
begin
  inherited;

  FEnvironment := TCPScriptEnvironment.Create();
  FFuncs := TDictionary<TCPRoutineDeclNode, TCallback<TCPScriptRoutineFunc>>.Create();
  FSignal := ssNone;
end;

destructor TCPScriptInterpreter.Destroy();
begin
  FFuncs.Free();
  FEnvironment.Free();

  inherited;
end;

procedure TCPScriptInterpreter.RegisterBuiltin(const ANode: TCPRoutineDeclNode;
  const AFunc: TCPScriptRoutineFunc; const AUserData: Pointer);
var
  LCB: TCallback<TCPScriptRoutineFunc>;
begin
  LCB.Callback := AFunc;
  LCB.UserData := AUserData;
  FFuncs.AddOrSetValue(ANode, LCB);
end;

function TCPScriptInterpreter.IsBuiltin(const ANode: TCPRoutineDeclNode): Boolean;
begin
  Result := FFuncs.ContainsKey(ANode);
end;

procedure TCPScriptInterpreter.Execute(const AModule: TCPModuleNode);
var
  LDecl: TCPASTNode;
begin
  FSignal := ssNone;
  FReturnValue := TCPScriptValue.Empty;

  // Process declarations (registers routines and consts/vars in scope)
  for LDecl in AModule.Declarations do
    ExecNode(LDecl);

  // Execute init body if present
  if AModule.InitBody.Count > 0 then
    ExecStmtList(AModule.InitBody);

  // Execute main body
  if AModule.HasMainBody then
    ExecStmtList(AModule.MainBody);
end;

// -- Core dispatch --------------------------------------------------------

procedure TCPScriptInterpreter.ExecNode(const ANode: TCPASTNode);
begin
  if ANode = nil then
    Exit;
  if FSignal <> ssNone then
    Exit;

  if ANode is TCPConstDeclNode then
    ExecConstDecl(TCPConstDeclNode(ANode))
  else if ANode is TCPVarDeclNode then
    ExecVarDecl(TCPVarDeclNode(ANode))
  else if ANode is TCPRoutineDeclNode then
    ExecRoutineDecl(TCPRoutineDeclNode(ANode))
  else if ANode is TCPAssignNode then
    ExecAssign(TCPAssignNode(ANode))
  else if ANode is TCPCallStmtNode then
    ExecCallStmt(TCPCallStmtNode(ANode))
  else if ANode is TCPIfNode then
    ExecIf(TCPIfNode(ANode))
  else if ANode is TCPWhileNode then
    ExecWhile(TCPWhileNode(ANode))
  else if ANode is TCPForNode then
    ExecFor(TCPForNode(ANode))
  else if ANode is TCPRepeatNode then
    ExecRepeat(TCPRepeatNode(ANode))
  else if ANode is TCPMatchNode then
    ExecMatch(TCPMatchNode(ANode))
  else if ANode is TCPReturnNode then
    ExecReturn(TCPReturnNode(ANode))
  else if ANode is TCPBreakNode then
    FSignal := ssBreak
  else if ANode is TCPContinueNode then
    FSignal := ssContinue
  else if ANode is TCPGuardNode then
    ExecGuard(TCPGuardNode(ANode))
  else if ANode is TCPThrowNode then
    ExecThrow(TCPThrowNode(ANode))
  else if ANode is TCPThrowCodeNode then
    ExecThrowCode(TCPThrowCodeNode(ANode))
  else if ANode is TCPPrintNode then
    ExecPrint(TCPPrintNode(ANode))
  else if ANode is TCPAssertStmtNode then
    ExecAssertStmt(TCPAssertStmtNode(ANode))
  else if ANode is TCPSetLengthNode then
    ExecSetLength(TCPSetLengthNode(ANode))
  else if ANode is TCPDirectiveNode then
    ExecDirective(TCPDirectiveNode(ANode))
  else if ANode is TCPNewNode then
    ExecNew(TCPNewNode(ANode))
  else if ANode is TCPDisposeNode then
    ExecDispose(TCPDisposeNode(ANode))
  else if ANode is TCPGetMemNode then
    ExecGetMem(TCPGetMemNode(ANode))
  else if ANode is TCPFreeMemNode then
    ExecFreeMem(TCPFreeMemNode(ANode))
  else if ANode is TCPResizeMemNode then
    ExecResizeMem(TCPResizeMemNode(ANode))
  else if ANode is TCPCppBlockNode then
    raise Exception.Create('C++ blocks are not supported in script mode')
  else if ANode is TCPTypeDeclNode then
    // Type declarations are no-ops at runtime
  else if ANode is TCPForwardTypeDeclNode then
    // Forward type declarations are no-ops at runtime
  else if ANode is TCPForwardRoutineDeclNode then
    // Forward routine declarations are no-ops at runtime
  ;
end;

procedure TCPScriptInterpreter.ExecStmtList(const AList: TObjectList<TCPASTNode>);
var
  LNode: TCPASTNode;
begin
  for LNode in AList do
  begin
    if FSignal <> ssNone then
      Exit;
    ExecNode(LNode);
  end;
end;

function TCPScriptInterpreter.EvalExpr(const ANode: TCPASTNode): TCPScriptValue;
begin
  Result := TCPScriptValue.Empty;
  if ANode = nil then
    Exit;

  if ANode is TCPIntLiteralNode then
    Result := TCPScriptValue.From<Int64>(TCPIntLiteralNode(ANode).IntValue)
  else if ANode is TCPFloatLiteralNode then
    Result := TCPScriptValue.From<Double>(TCPFloatLiteralNode(ANode).FloatValue)
  else if ANode is TCPStringLiteralNode then
    Result := TCPScriptValue.From<string>(TCPStringLiteralNode(ANode).StringValue)
  else if ANode is TCPWStringLiteralNode then
    Result := TCPScriptValue.From<string>(TCPWStringLiteralNode(ANode).StringValue)
  else if ANode is TCPBoolLiteralNode then
    Result := TCPScriptValue.From<Boolean>(TCPBoolLiteralNode(ANode).BoolValue)
  else if ANode is TCPNilLiteralNode then
    Result := TCPScriptValue.Empty
  else if ANode is TCPBinaryExprNode then
    Result := EvalBinaryExpr(TCPBinaryExprNode(ANode))
  else if ANode is TCPUnaryExprNode then
    Result := EvalUnaryExpr(TCPUnaryExprNode(ANode))
  else if ANode is TCPIdentifierNode then
    Result := EvalIdentifier(TCPIdentifierNode(ANode))
  else if ANode is TCPCallExprNode then
    Result := EvalCallExpr(TCPCallExprNode(ANode))
  else if ANode is TCPIntrinsicExprNode then
    Result := EvalIntrinsic(TCPIntrinsicExprNode(ANode))
  else if ANode is TCPTypeCastExprNode then
    Result := EvalTypeCast(TCPTypeCastExprNode(ANode))
  else if ANode is TCPDotAccessNode then
    Result := EvalDotAccess(TCPDotAccessNode(ANode))
  else if ANode is TCPIndexAccessNode then
    Result := EvalIndexAccess(TCPIndexAccessNode(ANode))
  else if ANode is TCPDerefNode then
    Result := EvalDeref(TCPDerefNode(ANode))
  else if ANode is TCPSetLiteralExprNode then
    Result := EvalSetLiteral(TCPSetLiteralExprNode(ANode))
  else if ANode is TCPRecordLiteralNode then
    Result := EvalRecordLiteral(TCPRecordLiteralNode(ANode))
  else if ANode is TCPCppExprNode then
    raise Exception.Create('C++ expressions are not supported in script mode');
end;

// -- Statement handlers ---------------------------------------------------

procedure TCPScriptInterpreter.ExecConstDecl(const ANode: TCPConstDeclNode);
var
  LValue: TCPScriptValue;
begin
  LValue := EvalExpr(ANode.ValueExpr);
  FEnvironment.DeclareVar(ANode.DeclName, LValue, True);
end;

procedure TCPScriptInterpreter.ExecVarDecl(const ANode: TCPVarDeclNode);
var
  LValue: TCPScriptValue;
  LTypeNode: TCPASTNode;
  LTypeDef: TCPASTNode;
  LRec: TCPScriptRecord;
  LArr: TCPScriptArray;
  LSet: TCPScriptSet;
  LFieldNode: TCPASTNode;
begin
  if ANode.InitExpr <> nil then
    LValue := EvalExpr(ANode.InitExpr)
  else
  begin
    // Default-initialize based on type
    LValue := TCPScriptValue.Empty;
    LTypeNode := ANode.TypeExpr;

    // Follow TCPTypeRefNode -> ResolvedDecl -> TCPTypeDeclNode -> TypeDef
    if (LTypeNode <> nil) and (LTypeNode is TCPTypeRefNode) and
       (TCPTypeRefNode(LTypeNode).ResolvedDecl <> nil) then
      LTypeNode := TCPTypeRefNode(LTypeNode).ResolvedDecl;

    // Follow TCPTypeDeclNode -> TypeDef
    if (LTypeNode <> nil) and (LTypeNode is TCPTypeDeclNode) then
      LTypeDef := TCPTypeDeclNode(LTypeNode).TypeDef
    else
      LTypeDef := LTypeNode;

    if LTypeDef is TCPArrayTypeNode then
    begin
      LArr := TCPScriptArray.Create();
      LValue := TCPScriptValue.From<TObject>(LArr);
    end
    else if LTypeDef is TCPRecordTypeNode then
    begin
      LRec := TCPScriptRecord.Create();
      if (LTypeNode <> nil) and (LTypeNode is TCPTypeDeclNode) then
        LRec.TypeName := TCPTypeDeclNode(LTypeNode).DeclName;
      for LFieldNode in TCPRecordTypeNode(LTypeDef).Fields do
      begin
        if LFieldNode is TCPFieldDeclNode then
          LRec.SetField(TCPFieldDeclNode(LFieldNode).FieldName, TCPScriptValue.Empty);
      end;
      LValue := TCPScriptValue.From<TObject>(LRec);
    end
    else if LTypeDef is TCPSetTypeNode then
    begin
      LSet := TCPScriptSet.Create();
      LValue := TCPScriptValue.From<TObject>(LSet);
    end;
  end;
  FEnvironment.DeclareVar(ANode.DeclName, LValue, False);
end;

procedure TCPScriptInterpreter.ExecRoutineDecl(const ANode: TCPRoutineDeclNode);
begin
  // Register routine name in scope so it can be looked up by calls.
  // The TCPRoutineDeclNode itself carries the body -- no separate storage needed.
  FEnvironment.DeclareVar(ANode.DeclName, TCPScriptValue.From<TObject>(ANode), False);
end;

procedure TCPScriptInterpreter.ExecAssign(const ANode: TCPAssignNode);
var
  LName: string;
  LNewValue: TCPScriptValue;
  LOldValue: TCPScriptValue;
  LTarget: TCPASTNode;
  LBaseValue: TCPScriptValue;
  LRec: TCPScriptRecord;
  LArr: TCPScriptArray;
  LIdx: Int64;
  LFieldName: string;
begin
  LNewValue := EvalExpr(ANode.ValueExpr);
  LTarget := ANode.Target;

  // Simple identifier assignment
  if LTarget is TCPIdentifierNode then
  begin
    LName := TCPIdentifierNode(LTarget).IdentName;

    if ANode.Op = aoAssign then
    begin
      FEnvironment.UpdateVar(LName, LNewValue);
    end
    else
    begin
      // Compound assignment -- read old value, apply op, write back
      if FEnvironment.TryGetVar(LName, LOldValue) then
      begin
        LNewValue := DoApplyCompoundOp(ANode.Op, LOldValue, LNewValue);
        FEnvironment.UpdateVar(LName, LNewValue);
      end;
    end;
  end
  else if LTarget is TCPDotAccessNode then
  begin
    // Record field assignment: rec.field := value
    LBaseValue := EvalExpr(TCPDotAccessNode(LTarget).BaseExpr);
    if LBaseValue.IsObject and (LBaseValue.AsObject is TCPScriptRecord) then
    begin
      LRec := TCPScriptRecord(LBaseValue.AsObject);
      LFieldName := TCPDotAccessNode(LTarget).MemberName;
      if ANode.Op <> aoAssign then
      begin
        LOldValue := LRec.GetField(LFieldName);
        LNewValue := DoApplyCompoundOp(ANode.Op, LOldValue, LNewValue);
      end;
      LRec.SetField(LFieldName, LNewValue);
    end
    else
      raise Exception.Create('Cannot assign to field of non-record value');
  end
  else if LTarget is TCPIndexAccessNode then
  begin
    // Array/string index assignment: arr[i] := value
    LBaseValue := EvalExpr(TCPIndexAccessNode(LTarget).BaseExpr);
    LIdx := ValueToInt(EvalExpr(TCPIndexAccessNode(LTarget).IndexExpr));
    if LBaseValue.IsObject and (LBaseValue.AsObject is TCPScriptArray) then
    begin
      LArr := TCPScriptArray(LBaseValue.AsObject);
      if ANode.Op <> aoAssign then
      begin
        LOldValue := LArr.GetElement(LIdx);
        LNewValue := DoApplyCompoundOp(ANode.Op, LOldValue, LNewValue);
      end;
      LArr.SetElement(LIdx, LNewValue);
    end
    else
      raise Exception.Create('Cannot index-assign to non-array value');
  end
  else if LTarget is TCPDerefNode then
  begin
    // Pointer dereference assignment: p^ := value
    // In the interpreter, deref is identity -- the pointer IS the object
    // So we need to get the variable name from the base expression and update it
    if TCPDerefNode(LTarget).BaseExpr is TCPIdentifierNode then
    begin
      LName := TCPIdentifierNode(TCPDerefNode(LTarget).BaseExpr).IdentName;
      if ANode.Op <> aoAssign then
      begin
        if FEnvironment.TryGetVar(LName, LOldValue) then
          LNewValue := DoApplyCompoundOp(ANode.Op, LOldValue, LNewValue);
      end;
      FEnvironment.UpdateVar(LName, LNewValue);
    end
    else
      raise Exception.Create('Cannot assign through complex dereference expression');
  end;
end;

procedure TCPScriptInterpreter.ExecCallStmt(const ANode: TCPCallStmtNode);
begin
  // Evaluate the call expression and discard the result
  EvalExpr(ANode.CallExpr);
end;

procedure TCPScriptInterpreter.ExecIf(const ANode: TCPIfNode);
begin
  if ValueToBool(EvalExpr(ANode.Condition)) then
    ExecStmtList(ANode.ThenBody)
  else if ANode.ElseBody.Count > 0 then
    ExecStmtList(ANode.ElseBody);
end;

procedure TCPScriptInterpreter.ExecWhile(const ANode: TCPWhileNode);
begin
  while ValueToBool(EvalExpr(ANode.Condition)) do
  begin
    ExecStmtList(ANode.Body);
    if FSignal = ssBreak then
    begin
      FSignal := ssNone;
      Break;
    end;
    if FSignal = ssContinue then
      FSignal := ssNone;
    if FSignal = ssReturn then
      Exit;
  end;
end;

procedure TCPScriptInterpreter.ExecFor(const ANode: TCPForNode);
var
  LStart: Int64;
  LEnd: Int64;
  LI: Int64;
begin
  LStart := ValueToInt(EvalExpr(ANode.StartExpr));
  LEnd := ValueToInt(EvalExpr(ANode.EndExpr));

  // Declare iterator variable in a new scope
  FEnvironment.PushScope();
  try
    FEnvironment.DeclareVar(ANode.IteratorName, TCPScriptValue.From<Int64>(LStart), False);

    if ANode.IsDownTo then
    begin
      LI := LStart;
      while LI >= LEnd do
      begin
        FEnvironment.UpdateVar(ANode.IteratorName, TCPScriptValue.From<Int64>(LI));
        ExecStmtList(ANode.Body);
        if FSignal = ssBreak then
        begin
          FSignal := ssNone;
          Break;
        end;
        if FSignal = ssContinue then
          FSignal := ssNone;
        if FSignal = ssReturn then
          Exit;
        Dec(LI);
      end;
    end
    else
    begin
      LI := LStart;
      while LI <= LEnd do
      begin
        FEnvironment.UpdateVar(ANode.IteratorName, TCPScriptValue.From<Int64>(LI));
        ExecStmtList(ANode.Body);
        if FSignal = ssBreak then
        begin
          FSignal := ssNone;
          Break;
        end;
        if FSignal = ssContinue then
          FSignal := ssNone;
        if FSignal = ssReturn then
          Exit;
        Inc(LI);
      end;
    end;
  finally
    FEnvironment.PopScope();
  end;
end;

procedure TCPScriptInterpreter.ExecRepeat(const ANode: TCPRepeatNode);
begin
  repeat
    ExecStmtList(ANode.Body);
    if FSignal = ssBreak then
    begin
      FSignal := ssNone;
      Break;
    end;
    if FSignal = ssContinue then
      FSignal := ssNone;
    if FSignal = ssReturn then
      Exit;
  until ValueToBool(EvalExpr(ANode.Condition));
end;

procedure TCPScriptInterpreter.ExecMatch(const ANode: TCPMatchNode);
var
  LExprValue: TCPScriptValue;
  LArm: TCPMatchArmNode;
  LLabel: TCPMatchLabelNode;
  LLow: TCPScriptValue;
  LHigh: TCPScriptValue;
  LMatched: Boolean;
begin
  LExprValue := EvalExpr(ANode.Expr);

  for LArm in ANode.Arms do
  begin
    LMatched := False;
    for LLabel in LArm.Labels do
    begin
      LLow := EvalExpr(LLabel.LowExpr);
      if LLabel.HighExpr <> nil then
      begin
        // Range label: check if value is within range
        LHigh := EvalExpr(LLabel.HighExpr);
        if (ValueToInt(LExprValue) >= ValueToInt(LLow)) and
           (ValueToInt(LExprValue) <= ValueToInt(LHigh)) then
        begin
          LMatched := True;
          Break;
        end;
      end
      else
      begin
        // Single value label
        if LExprValue.IsType<Int64>() and LLow.IsType<Int64>() then
          LMatched := LExprValue.AsInt64 = LLow.AsInt64
        else if LExprValue.IsType<string>() and LLow.IsType<string>() then
          LMatched := LExprValue.AsString = LLow.AsString
        else if LExprValue.IsType<Boolean>() and LLow.IsType<Boolean>() then
          LMatched := LExprValue.IsType<Boolean>() = LLow.IsType<Boolean>()
        else
          LMatched := ValueToFloat(LExprValue) = ValueToFloat(LLow);

        if LMatched then
          Break;
      end;
    end;

    if LMatched then
    begin
      ExecStmtList(LArm.Body);
      Exit;
    end;
  end;

  // No arm matched -- execute else body if present
  if ANode.ElseBody.Count > 0 then
    ExecStmtList(ANode.ElseBody);
end;

procedure TCPScriptInterpreter.ExecReturn(const ANode: TCPReturnNode);
begin
  if ANode.ValueExpr <> nil then
    FReturnValue := EvalExpr(ANode.ValueExpr)
  else
    FReturnValue := TCPScriptValue.Empty;
  FSignal := ssReturn;
end;

procedure TCPScriptInterpreter.ExecGuard(const ANode: TCPGuardNode);
var
  LSavedExcCode: Int64;
  LSavedExcMsg: string;
  LBracketEnd: Integer;
  LCodeStr: string;
  LCode: Int64;
begin
  // Save outer exception context
  LSavedExcCode := FCurrentExcCode;
  LSavedExcMsg := FCurrentExcMsg;
  try
    ExecStmtList(ANode.GuardBody);
  except
    on E: Exception do
    begin
      // Parse exception code from ThrowCode format: [code] message
      FCurrentExcCode := 0;
      FCurrentExcMsg := E.Message;
      if (Length(E.Message) > 2) and (E.Message[1] = '[') then
      begin
        LBracketEnd := Pos(']', E.Message);
        if LBracketEnd > 2 then
        begin
          LCodeStr := Copy(E.Message, 2, LBracketEnd - 2);
          if TryStrToInt64(LCodeStr, LCode) then
          begin
            FCurrentExcCode := LCode;
            FCurrentExcMsg := Trim(Copy(E.Message, LBracketEnd + 1, MaxInt));
          end;
        end;
      end;
      if ANode.ExceptBody <> nil then
        ExecStmtList(ANode.ExceptBody);
    end;
  end;
  // Restore outer exception context
  FCurrentExcCode := LSavedExcCode;
  FCurrentExcMsg := LSavedExcMsg;
  if ANode.FinallyBody <> nil then
    ExecStmtList(ANode.FinallyBody);
end;

procedure TCPScriptInterpreter.ExecThrow(const ANode: TCPThrowNode);
var
  LMsg: string;
begin
  LMsg := ValueToStr(EvalExpr(ANode.MessageExpr));
  raise Exception.Create(LMsg);
end;

procedure TCPScriptInterpreter.ExecPrint(const ANode: TCPPrintNode);
var
  LText: string;
  LFmt: string;
  LArgIdx: Integer;
  I: Integer;
begin
  if ANode.Args.Count = 0 then
    LText := ''
  else if ANode.Args.Count = 1 then
    // Single arg: print directly, no format substitution
    LText := ValueToStr(EvalExpr(ANode.Args[0]))
  else
  begin
    // First arg is format string, remaining args replace {} placeholders
    LFmt := ValueToStr(EvalExpr(ANode.Args[0]));
    LText := '';
    LArgIdx := 1;
    I := 1;
    while I <= Length(LFmt) do
    begin
      if (I < Length(LFmt)) and (LFmt[I] = '{') and (LFmt[I + 1] = '}') then
      begin
        if LArgIdx < ANode.Args.Count then
        begin
          LText := LText + ValueToStr(EvalExpr(ANode.Args[LArgIdx]));
          Inc(LArgIdx);
        end
        else
          LText := LText + '{}';
        Inc(I, 2);
      end
      else
      begin
        LText := LText + LFmt[I];
        Inc(I);
      end;
    end;
  end;

  if FPrintCallback.IsAssigned() then
    FPrintCallback.Callback(LText, ANode.IsLn, FPrintCallback.UserData)
  else
  begin
    if ANode.IsLn then
      WriteLn(LText)
    else
      Write(LText);
  end;
end;

procedure TCPScriptInterpreter.ExecThrowCode(const ANode: TCPThrowCodeNode);
var
  LCode: Int64;
  LMsg: string;
begin
  LCode := ValueToInt(EvalExpr(ANode.CodeExpr));
  LMsg := ValueToStr(EvalExpr(ANode.MessageExpr));
  raise Exception.CreateFmt('[%d] %s', [LCode, LMsg]);
end;

procedure TCPScriptInterpreter.ExecAssertStmt(const ANode: TCPAssertStmtNode);
var
  LArg0: TCPScriptValue;
  LArg1: TCPScriptValue;
  LArg2: TCPScriptValue;
  LPassed: Boolean;
  LMsg: string;
begin
  LPassed := False;
  LMsg := '';

  case ANode.AssertKind of
    akAssert:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := ValueToBool(LArg0);
      if not LPassed then
        LMsg := 'Assertion failed';
    end;
    akTrue:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := ValueToBool(LArg0);
      if not LPassed then
        LMsg := 'Expected true, got false';
    end;
    akFalse:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := not ValueToBool(LArg0);
      if not LPassed then
        LMsg := 'Expected false, got true';
    end;
    akEq:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LArg1 := EvalExpr(ANode.Args[1]);
      LPassed := (ValueToStr(LArg0) = ValueToStr(LArg1));
      if not LPassed then
        LMsg := Format('Expected %s, got %s', [ValueToStr(LArg0), ValueToStr(LArg1)]);
    end;
    akEqF:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LArg1 := EvalExpr(ANode.Args[1]);
      LArg2 := EvalExpr(ANode.Args[2]);
      LPassed := Abs(ValueToFloat(LArg0) - ValueToFloat(LArg1)) <= ValueToFloat(LArg2);
      if not LPassed then
        LMsg := Format('Expected %s within %s of %s',
          [ValueToStr(LArg0), ValueToStr(LArg2), ValueToStr(LArg1)]);
    end;
    akNil:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := LArg0.IsEmpty;
      if not LPassed then
        LMsg := Format('Expected nil, got %s', [ValueToStr(LArg0)]);
    end;
    akNotNil:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := not LArg0.IsEmpty;
      if not LPassed then
        LMsg := 'Expected non-nil, got nil';
    end;
    akFail:
    begin
      LArg0 := EvalExpr(ANode.Args[0]);
      LPassed := False;
      LMsg := ValueToStr(LArg0);
    end;
  end;

  if not LPassed then
    raise Exception.Create('Assertion failed: ' + LMsg);
end;

procedure TCPScriptInterpreter.ExecSetLength(const ANode: TCPSetLengthNode);
var
  LTarget: TCPScriptValue;
  LLength: Int64;
  LArr: TCPScriptArray;
begin
  LTarget := EvalExpr(ANode.TargetExpr);
  LLength := ValueToInt(EvalExpr(ANode.LengthExpr));
  if LTarget.IsObject and (LTarget.AsObject is TCPScriptArray) then
  begin
    LArr := TCPScriptArray(LTarget.AsObject);
    LArr.Resize(LLength);
  end
  else
    raise Exception.Create('setlength target must be an array');
end;

procedure TCPScriptInterpreter.ExecDirective(const ANode: TCPDirectiveNode);
begin
  // Statement-level directives: @breakpoint and @message
  // @message is handled at parse time (compiler message). No runtime action.
  // @breakpoint has no effect in the interpreter.
end;

procedure TCPScriptInterpreter.ExecNew(const ANode: TCPNewNode);
var
  LRec: TCPScriptRecord;
  LTypeDecl: TCPASTNode;
  LTypeDef: TCPASTNode;
  LPointerType: TCPPointerTypeNode;
  LTargetTypeDecl: TCPTypeDeclNode;
  LRecordType: TCPRecordTypeNode;
  LFieldNode: TCPASTNode;
  LName: string;
begin
  // new(p) -- allocate a default-initialized record for the pointer's target type
  // The argument is an identifier (the pointer variable)
  if not (ANode.ArgExpr is TCPIdentifierNode) then
    raise Exception.Create('new() argument must be an identifier');

  LName := TCPIdentifierNode(ANode.ArgExpr).IdentName;

  // Resolve the pointer's target type from the enriched AST
  LRec := TCPScriptRecord.Create();
  LRec.TypeName := 'heap';

  // Try to resolve the pointed-to type and default-initialize fields
  LTypeDecl := TCPExprNode(ANode.ArgExpr).ResolvedType;
  if LTypeDecl <> nil then
  begin
    // Follow type declaration chain to get the pointer's target type
    if (LTypeDecl is TCPTypeDeclNode) and
       (TCPTypeDeclNode(LTypeDecl).TypeDef is TCPPointerTypeNode) then
    begin
      LPointerType := TCPPointerTypeNode(TCPTypeDeclNode(LTypeDecl).TypeDef);
      if (LPointerType.TargetType <> nil) and
         (LPointerType.TargetType is TCPTypeDeclNode) then
      begin
        LTargetTypeDecl := TCPTypeDeclNode(LPointerType.TargetType);
        LRec.TypeName := LTargetTypeDecl.DeclName;
        LTypeDef := LTargetTypeDecl.TypeDef;
        if LTypeDef is TCPRecordTypeNode then
        begin
          LRecordType := TCPRecordTypeNode(LTypeDef);
          for LFieldNode in LRecordType.Fields do
          begin
            if LFieldNode is TCPFieldDeclNode then
              LRec.SetField(TCPFieldDeclNode(LFieldNode).FieldName, TCPScriptValue.Empty);
          end;
        end;
      end;
    end;
  end;

  FEnvironment.UpdateVar(LName, TCPScriptValue.From<TObject>(LRec));
end;

procedure TCPScriptInterpreter.ExecDispose(const ANode: TCPDisposeNode);
var
  LName: string;
begin
  if not (ANode.ArgExpr is TCPIdentifierNode) then
    raise Exception.Create('dispose() argument must be an identifier');

  LName := TCPIdentifierNode(ANode.ArgExpr).IdentName;
  // UpdateVar frees the old composite wrapper when replacing with Empty
  FEnvironment.UpdateVar(LName, TCPScriptValue.Empty);
end;

procedure TCPScriptInterpreter.ExecGetMem(const ANode: TCPGetMemNode);
var
  LName: string;
  LBuf: TCPScriptBuffer;
begin
  if not (ANode.ArgExpr is TCPIdentifierNode) then
    raise Exception.Create('getmem() argument must be an identifier');

  LName := TCPIdentifierNode(ANode.ArgExpr).IdentName;

  // Allocate a buffer -- size comes from the type info
  LBuf := TCPScriptBuffer.Create();
  LBuf.Allocate(1); // Default 1 byte; real size determined by type
  FEnvironment.UpdateVar(LName, TCPScriptValue.From<TObject>(LBuf));
end;

procedure TCPScriptInterpreter.ExecFreeMem(const ANode: TCPFreeMemNode);
var
  LName: string;
begin
  if not (ANode.ArgExpr is TCPIdentifierNode) then
    raise Exception.Create('freemem() argument must be an identifier');

  LName := TCPIdentifierNode(ANode.ArgExpr).IdentName;
  // UpdateVar frees the old composite wrapper when replacing with Empty
  FEnvironment.UpdateVar(LName, TCPScriptValue.Empty);
end;

procedure TCPScriptInterpreter.ExecResizeMem(const ANode: TCPResizeMemNode);
var
  LPtrValue: TCPScriptValue;
  LNewSize: Int64;
  LBuf: TCPScriptBuffer;
begin
  LPtrValue := EvalExpr(ANode.PtrExpr);
  LNewSize := ValueToInt(EvalExpr(ANode.SizeExpr));

  if LPtrValue.IsObject and (LPtrValue.AsObject is TCPScriptBuffer) then
  begin
    LBuf := TCPScriptBuffer(LPtrValue.AsObject);
    LBuf.Resize(LNewSize);
  end
  else
    raise Exception.Create('resizemem target must be a memory buffer');
end;

function TCPScriptInterpreter.DoApplyCompoundOp(const AOp: TCPAssignOp;
  const AOld: TCPScriptValue; const ANew: TCPScriptValue): TCPScriptValue;
begin
  if AOp = aoPlusAssign then
  begin
    if AOld.IsType<Int64>() and ANew.IsType<Int64>() then
      Result := TCPScriptValue.From<Int64>(AOld.AsInt64 + ANew.AsInt64)
    else
      Result := TCPScriptValue.From<Double>(ValueToFloat(AOld) + ValueToFloat(ANew));
  end
  else if AOp = aoMinusAssign then
  begin
    if AOld.IsType<Int64>() and ANew.IsType<Int64>() then
      Result := TCPScriptValue.From<Int64>(AOld.AsInt64 - ANew.AsInt64)
    else
      Result := TCPScriptValue.From<Double>(ValueToFloat(AOld) - ValueToFloat(ANew));
  end
  else if AOp = aoMulAssign then
  begin
    if AOld.IsType<Int64>() and ANew.IsType<Int64>() then
      Result := TCPScriptValue.From<Int64>(AOld.AsInt64 * ANew.AsInt64)
    else
      Result := TCPScriptValue.From<Double>(ValueToFloat(AOld) * ValueToFloat(ANew));
  end
  else if AOp = aoDivAssign then
    Result := TCPScriptValue.From<Double>(ValueToFloat(AOld) / ValueToFloat(ANew))
  else
    Result := ANew;
end;

// -- Expression evaluators ------------------------------------------------

function TCPScriptInterpreter.EvalBinaryExpr(const ANode: TCPBinaryExprNode): TCPScriptValue;
var
  LLeft: TCPScriptValue;
  LRight: TCPScriptValue;
  LLI: Int64;
  LRI: Int64;
  LLF: Double;
  LRF: Double;
  LBothInt: Boolean;
begin
  LLeft := EvalExpr(ANode.Left);
  LRight := EvalExpr(ANode.Right);

  // String concatenation
  if (ANode.Op = boAdd) and (LLeft.IsType<string>() or LRight.IsType<string>()) then
    Exit(TCPScriptValue.From<string>(ValueToStr(LLeft) + ValueToStr(LRight)));

  // String comparison
  if LLeft.IsType<string>() and LRight.IsType<string>() then
  begin
    case ANode.Op of
      boEq:        Exit(TCPScriptValue.From<Boolean>(LLeft.AsString = LRight.AsString));
      boNotEq:     Exit(TCPScriptValue.From<Boolean>(LLeft.AsString <> LRight.AsString));
      boLess:      Exit(TCPScriptValue.From<Boolean>(LLeft.AsString < LRight.AsString));
      boGreater:   Exit(TCPScriptValue.From<Boolean>(LLeft.AsString > LRight.AsString));
      boLessEq:    Exit(TCPScriptValue.From<Boolean>(LLeft.AsString <= LRight.AsString));
      boGreaterEq: Exit(TCPScriptValue.From<Boolean>(LLeft.AsString >= LRight.AsString));
    end;
  end;

  // Boolean operations
  if LLeft.IsType<Boolean>() and LRight.IsType<Boolean>() then
  begin
    case ANode.Op of
      boLogicalAnd, boAnd: Exit(TCPScriptValue.From<Boolean>(LLeft.AsBoolean and LRight.AsBoolean));
      boLogicalOr, boOr:   Exit(TCPScriptValue.From<Boolean>(LLeft.AsBoolean or LRight.AsBoolean));
      boXor:               Exit(TCPScriptValue.From<Boolean>(LLeft.AsBoolean xor LRight.AsBoolean));
      boEq:                Exit(TCPScriptValue.From<Boolean>(LLeft.AsBoolean = LRight.AsBoolean));
      boNotEq:             Exit(TCPScriptValue.From<Boolean>(LLeft.AsBoolean <> LRight.AsBoolean));
    end;
  end;

  // Numeric operations
  LBothInt := LLeft.IsType<Int64>() and LRight.IsType<Int64>();

  if LBothInt then
  begin
    LLI := LLeft.AsInt64;
    LRI := LRight.AsInt64;
    case ANode.Op of
      boAdd:      Exit(TCPScriptValue.From<Int64>(LLI + LRI));
      boSub:      Exit(TCPScriptValue.From<Int64>(LLI - LRI));
      boMul:      Exit(TCPScriptValue.From<Int64>(LLI * LRI));
      boIntDiv:   Exit(TCPScriptValue.From<Int64>(LLI div LRI));
      boMod:      Exit(TCPScriptValue.From<Int64>(LLI mod LRI));
      boDiv:      Exit(TCPScriptValue.From<Double>(LLI / LRI));
      boAnd:      Exit(TCPScriptValue.From<Int64>(LLI and LRI));
      boOr:       Exit(TCPScriptValue.From<Int64>(LLI or LRI));
      boXor:      Exit(TCPScriptValue.From<Int64>(LLI xor LRI));
      boShl:      Exit(TCPScriptValue.From<Int64>(LLI shl LRI));
      boShr:      Exit(TCPScriptValue.From<Int64>(LLI shr LRI));
      boEq:       Exit(TCPScriptValue.From<Boolean>(LLI = LRI));
      boNotEq:    Exit(TCPScriptValue.From<Boolean>(LLI <> LRI));
      boLess:     Exit(TCPScriptValue.From<Boolean>(LLI < LRI));
      boGreater:  Exit(TCPScriptValue.From<Boolean>(LLI > LRI));
      boLessEq:   Exit(TCPScriptValue.From<Boolean>(LLI <= LRI));
      boGreaterEq:Exit(TCPScriptValue.From<Boolean>(LLI >= LRI));
    end;
  end
  else
  begin
    // Float arithmetic
    LLF := ValueToFloat(LLeft);
    LRF := ValueToFloat(LRight);
    case ANode.Op of
      boAdd:      Exit(TCPScriptValue.From<Double>(LLF + LRF));
      boSub:      Exit(TCPScriptValue.From<Double>(LLF - LRF));
      boMul:      Exit(TCPScriptValue.From<Double>(LLF * LRF));
      boDiv:      Exit(TCPScriptValue.From<Double>(LLF / LRF));
      boEq:       Exit(TCPScriptValue.From<Boolean>(LLF = LRF));
      boNotEq:    Exit(TCPScriptValue.From<Boolean>(LLF <> LRF));
      boLess:     Exit(TCPScriptValue.From<Boolean>(LLF < LRF));
      boGreater:  Exit(TCPScriptValue.From<Boolean>(LLF > LRF));
      boLessEq:   Exit(TCPScriptValue.From<Boolean>(LLF <= LRF));
      boGreaterEq:Exit(TCPScriptValue.From<Boolean>(LLF >= LRF));
    end;
  end;

  // Set membership: value in set
  if (ANode.Op = boIn) and LRight.IsObject and (LRight.AsObject is TCPScriptSet) then
    Exit(TCPScriptValue.From<Boolean>(
      TCPScriptSet(LRight.AsObject).Contains(ValueToInt(LLeft))));

  Result := TCPScriptValue.Empty;
end;

function TCPScriptInterpreter.EvalUnaryExpr(const ANode: TCPUnaryExprNode): TCPScriptValue;
var
  LValue: TCPScriptValue;
begin
  LValue := EvalExpr(ANode.Operand);
  case ANode.Op of
    uoNegate:
      begin
        if LValue.IsType<Int64>() then
          Result := TCPScriptValue.From<Int64>(-LValue.AsInt64)
        else
          Result := TCPScriptValue.From<Double>(-ValueToFloat(LValue));
      end;
    uoPositive:
      Result := LValue;
    uoNot:
      begin
        if LValue.IsType<Boolean>() then
          Result := TCPScriptValue.From<Boolean>(not LValue.AsBoolean)
        else if LValue.IsType<Int64>() then
          Result := TCPScriptValue.From<Int64>(not LValue.AsInt64)
        else
          Result := TCPScriptValue.From<Boolean>(not ValueToBool(LValue));
      end;
  else
    Result := TCPScriptValue.Empty;
  end;
end;

function TCPScriptInterpreter.EvalCallExpr(const ANode: TCPCallExprNode): TCPScriptValue;
var
  LRoutine: TCPRoutineDeclNode;
  LArgs: TArray<TCPScriptValue>;
  LBuiltinFunc: TCallback<TCPScriptRoutineFunc>;
  LI: Integer;
  LParam: TCPParamDeclNode;
begin
  Result := TCPScriptValue.Empty;

  // Resolve the routine from the semantic pass
  if not (ANode.ResolvedRoutine is TCPRoutineDeclNode) then
    Exit;

  LRoutine := TCPRoutineDeclNode(ANode.ResolvedRoutine);

  // Evaluate arguments
  SetLength(LArgs, ANode.Args.Count);
  for LI := 0 to ANode.Args.Count - 1 do
    LArgs[LI] := EvalExpr(ANode.Args[LI]);

  // Check if this is a builtin
  if FFuncs.TryGetValue(LRoutine, LBuiltinFunc) then
    Exit(LBuiltinFunc.Callback(LArgs, Self, LBuiltinFunc.UserData));

  // User-defined routine -- execute body in a new scope
  FEnvironment.PushScope();
  try
    // Bind parameters
    for LI := 0 to LRoutine.Params.Count - 1 do
    begin
      LParam := LRoutine.Params[LI];
      if LI < Length(LArgs) then
        FEnvironment.DeclareVar(LParam.ParamName, LArgs[LI], False)
      else
        FEnvironment.DeclareVar(LParam.ParamName, TCPScriptValue.Empty, False);
    end;

    // Declare local consts
    for LI := 0 to LRoutine.LocalConsts.Count - 1 do
      ExecConstDecl(LRoutine.LocalConsts[LI]);

    // Declare local vars
    for LI := 0 to LRoutine.LocalVars.Count - 1 do
      ExecVarDecl(LRoutine.LocalVars[LI]);

    // Execute body
    ExecStmtList(LRoutine.Body);

    // Capture return value
    if FSignal = ssReturn then
    begin
      FSignal := ssNone;
      Result := FReturnValue;
      FReturnValue := TCPScriptValue.Empty;
    end;
  finally
    FEnvironment.PopScope();
  end;
end;

function TCPScriptInterpreter.EvalIdentifier(const ANode: TCPIdentifierNode): TCPScriptValue;
begin
  if not FEnvironment.TryGetVar(ANode.IdentName, Result) then
    Result := TCPScriptValue.Empty;
end;

function TCPScriptInterpreter.EvalIntrinsic(const ANode: TCPIntrinsicExprNode): TCPScriptValue;
var
  LArg: TCPScriptValue;
begin
  Result := TCPScriptValue.Empty;

  case ANode.IntrinsicKind of
    ikLen:
    begin
      if ANode.Args.Count > 0 then
      begin
        LArg := EvalExpr(ANode.Args[0]);
        if LArg.IsType<string>() then
          Result := TCPScriptValue.From<Int64>(Length(LArg.AsString))
        else if LArg.IsObject and (LArg.AsObject is TCPScriptArray) then
          Result := TCPScriptValue.From<Int64>(TCPScriptArray(LArg.AsObject).GetCount());
      end;
    end;
    ikSize:
    begin
      // size() returns compile-time size -- in interpreter, return a reasonable default
      // based on the resolved type
      Result := TCPScriptValue.From<Int64>(0);
    end;
    ikExcCode:
      Result := TCPScriptValue.From<Int64>(FCurrentExcCode);
    ikExcMsg:
      Result := TCPScriptValue.From<string>(FCurrentExcMsg);
    ikUtf8, ikCStr, ikWStr:
    begin
      // String conversion intrinsics -- in the interpreter, strings are all Delphi strings
      // so these are pass-through
      if ANode.Args.Count > 0 then
        Result := EvalExpr(ANode.Args[0]);
    end;
    ikParamCount:
      Result := TCPScriptValue.From<Int64>(ParamCount());
    ikParamStr:
    begin
      if ANode.Args.Count > 0 then
      begin
        LArg := EvalExpr(ANode.Args[0]);
        Result := TCPScriptValue.From<string>(ParamStr(ValueToInt(LArg)));
      end;
    end;
  end;
end;

function TCPScriptInterpreter.EvalTypeCast(const ANode: TCPTypeCastExprNode): TCPScriptValue;
var
  LValue: TCPScriptValue;
  LTargetType: TCPTypeDeclNode;
begin
  LValue := EvalExpr(ANode.Expr);
  Result := LValue;

  // Resolve target type
  if not (ANode.TargetType is TCPTypeDeclNode) then
    Exit;

  LTargetType := TCPTypeDeclNode(ANode.TargetType);

  case LTargetType.PrimitiveKind of
    tkInt8, tkInt16, tkInt32, tkInt64:
      Result := TCPScriptValue.From<Int64>(ValueToInt(LValue));
    tkUInt8, tkUInt16, tkUInt32, tkUInt64:
      Result := TCPScriptValue.From<Int64>(ValueToInt(LValue));
    tkFloat32, tkFloat64:
      Result := TCPScriptValue.From<Double>(ValueToFloat(LValue));
    tkBoolean:
      Result := TCPScriptValue.From<Boolean>(ValueToBool(LValue));
    tkString:
      Result := TCPScriptValue.From<string>(ValueToStr(LValue));
  end;
end;

function TCPScriptInterpreter.EvalDotAccess(const ANode: TCPDotAccessNode): TCPScriptValue;
var
  LBaseValue: TCPScriptValue;
  LRec: TCPScriptRecord;
  LTypeDecl: TCPTypeDeclNode;
  LChoicesType: TCPChoicesTypeNode;
  LMember: TCPChoicesValueNode;
  LI: Integer;
begin
  Result := TCPScriptValue.Empty;

  case ANode.AccessKind of
    dakField:
    begin
      // Record field access: base.member
      LBaseValue := EvalExpr(ANode.BaseExpr);
      if LBaseValue.IsObject and (LBaseValue.AsObject is TCPScriptRecord) then
      begin
        LRec := TCPScriptRecord(LBaseValue.AsObject);
        Result := LRec.GetField(ANode.MemberName);
      end
      else
        raise Exception.CreateFmt('Cannot access field "%s" on non-record value',
          [ANode.MemberName]);
    end;
    dakModule:
    begin
      // Module-qualified access: Module.Symbol
      // The symbol should resolve to a constant or variable in the imported module
      // For the interpreter, the semantic pass resolved this -- look up by member name
      if (ANode.ResolvedDecl <> nil) and (ANode.ResolvedDecl is TCPConstDeclNode) then
        Result := EvalExpr(TCPConstDeclNode(ANode.ResolvedDecl).ValueExpr)
      else if (ANode.ResolvedDecl <> nil) and (ANode.ResolvedDecl is TCPVarDeclNode) then
      begin
        if not FEnvironment.TryGetVar(ANode.MemberName, Result) then
          Result := TCPScriptValue.Empty;
      end
      else
        raise Exception.CreateFmt('Cannot resolve module member "%s"', [ANode.MemberName]);
    end;
    dakChoices:
    begin
      // Choices (enum) member: MyEnum.Value -- resolve to ordinal
      if (ANode.ResolvedType <> nil) and (ANode.ResolvedType is TCPTypeDeclNode) then
      begin
        LTypeDecl := TCPTypeDeclNode(ANode.ResolvedType);
        if LTypeDecl.TypeDef is TCPChoicesTypeNode then
        begin
          LChoicesType := TCPChoicesTypeNode(LTypeDecl.TypeDef);
          for LI := 0 to LChoicesType.Members.Count - 1 do
          begin
            LMember := LChoicesType.Members[LI];
            if LMember.MemberName = ANode.MemberName then
            begin
              // If member has an explicit value, evaluate it; otherwise use ordinal index
              if LMember.ValueExpr <> nil then
                Result := EvalExpr(LMember.ValueExpr)
              else
                Result := TCPScriptValue.From<Int64>(LI);
              Exit;
            end;
          end;
          raise Exception.CreateFmt('Choices member "%s" not found', [ANode.MemberName]);
        end;
      end;
    end;
  end;
end;

function TCPScriptInterpreter.EvalIndexAccess(const ANode: TCPIndexAccessNode): TCPScriptValue;
var
  LBaseValue: TCPScriptValue;
  LIndex: Int64;
  LArr: TCPScriptArray;
  LStr: string;
begin
  LBaseValue := EvalExpr(ANode.BaseExpr);
  LIndex := ValueToInt(EvalExpr(ANode.IndexExpr));

  if LBaseValue.IsObject and (LBaseValue.AsObject is TCPScriptArray) then
  begin
    LArr := TCPScriptArray(LBaseValue.AsObject);
    Result := LArr.GetElement(LIndex);
  end
  else if LBaseValue.IsType<string>() then
  begin
    // String character access (1-based in CPaskal)
    LStr := LBaseValue.AsString;
    if (LIndex >= 1) and (LIndex <= Length(LStr)) then
      Result := TCPScriptValue.From<string>(LStr[LIndex])
    else
      raise Exception.CreateFmt('String index %d out of bounds [1..%d]',
        [LIndex, Length(LStr)]);
  end
  else
    raise Exception.Create('Cannot index into non-array/non-string value');
end;

function TCPScriptInterpreter.EvalDeref(const ANode: TCPDerefNode): TCPScriptValue;
begin
  // In the interpreter, a pointer is just a TValue holding a TObject reference.
  // Dereferencing returns the same TValue -- the object IS the pointed-to value.
  Result := EvalExpr(ANode.BaseExpr);
  if Result.IsEmpty then
    raise Exception.Create('Nil pointer dereference');
end;

function TCPScriptInterpreter.EvalSetLiteral(const ANode: TCPSetLiteralExprNode): TCPScriptValue;
var
  LSet: TCPScriptSet;
  LElem: TCPSetElementNode;
  LLow: Int64;
  LHigh: Int64;
begin
  LSet := TCPScriptSet.Create();
  for LElem in ANode.Elements do
  begin
    LLow := ValueToInt(EvalExpr(LElem.LowExpr));
    if LElem.HighExpr <> nil then
    begin
      LHigh := ValueToInt(EvalExpr(LElem.HighExpr));
      LSet.AddRange(LLow, LHigh);
    end
    else
      LSet.Add(LLow);
  end;
  Result := TCPScriptValue.From<TObject>(LSet);
end;

function TCPScriptInterpreter.EvalRecordLiteral(const ANode: TCPRecordLiteralNode): TCPScriptValue;
var
  LRec: TCPScriptRecord;
  LFieldInit: TCPFieldInitNode;
begin
  LRec := TCPScriptRecord.Create();
  LRec.TypeName := ANode.TypeName;
  for LFieldInit in ANode.FieldInits do
    LRec.SetField(LFieldInit.FieldName, EvalExpr(LFieldInit.ValueExpr));
  Result := TCPScriptValue.From<TObject>(LRec);
end;

// -- Helpers --------------------------------------------------------------

function TCPScriptInterpreter.ValueToStr(const AValue: TCPScriptValue): string;
begin
  if AValue.IsEmpty then
    Result := 'nil'
  else if AValue.IsType<string>() then
    Result := AValue.AsString
  else if AValue.IsType<Int64>() then
    Result := IntToStr(AValue.AsInt64)
  else if AValue.IsType<Double>() then
    Result := FloatToStr(AValue.AsType<Double>())
  else if AValue.IsType<Boolean>() then
  begin
    if AValue.AsBoolean then
      Result := 'true'
    else
      Result := 'false';
  end
  else
    Result := AValue.ToString();
end;

function TCPScriptInterpreter.ValueToBool(const AValue: TCPScriptValue): Boolean;
begin
  if AValue.IsEmpty then
    Result := False
  else if AValue.IsType<Boolean>() then
    Result := AValue.AsBoolean
  else if AValue.IsType<Int64>() then
    Result := AValue.AsInt64 <> 0
  else if AValue.IsType<Double>() then
    Result := AValue.AsType<Double>() <> 0.0
  else if AValue.IsType<string>() then
    Result := AValue.AsString <> ''
  else
    Result := True;
end;

function TCPScriptInterpreter.ValueToInt(const AValue: TCPScriptValue): Int64;
begin
  if AValue.IsEmpty then
    Result := 0
  else if AValue.IsType<Int64>() then
    Result := AValue.AsInt64
  else if AValue.IsType<Double>() then
    Result := Round(AValue.AsType<Double>())
  else if AValue.IsType<Boolean>() then
  begin
    if AValue.AsBoolean then
      Result := 1
    else
      Result := 0;
  end
  else
    Result := 0;
end;

function TCPScriptInterpreter.ValueToFloat(const AValue: TCPScriptValue): Double;
begin
  if AValue.IsEmpty then
    Result := 0.0
  else if AValue.IsType<Double>() then
    Result := AValue.AsType<Double>()
  else if AValue.IsType<Int64>() then
    Result := AValue.AsInt64
  else if AValue.IsType<Boolean>() then
  begin
    if AValue.AsBoolean then
      Result := 1.0
    else
      Result := 0.0;
  end
  else
    Result := 0.0;
end;

// -- TCPScriptSemantics ---------------------------------------------------

{ TCPScriptSemantics }
procedure TCPScriptSemantics.Analyze(const AMasterAST: TCPMasterAST);
begin
  FMasterAST := AMasterAST;

  // Scripts are single-module -- skip topological sort, analyze directly
  if FMasterAST.ModuleCount() > 0 then
    DoAnalyzeModule(FMasterAST.GetModuleAt(0));
end;

procedure TCPScriptSemantics.DoAnalyzeModule(const AModule: TCPModuleNode);
begin
  // Scripts use mkExe internally, so inherited validation passes.
  // Imports list is empty for scripts, so import resolution is a no-op.
  inherited;
end;

// -- TCPScriptEngine ------------------------------------------------------

{ TCPScriptEngine }
constructor TCPScriptEngine.Create();
begin
  inherited;

  FExtension := '.cps';
  FParser := TCPScriptParser.Create();
  FParser.SetErrors(FErrors);
  FSemantics := TCPScriptSemantics.Create();
  FSemantics.SetErrors(FErrors);
  FInterpreter := TCPScriptInterpreter.Create();
  FInterpreter.SetErrors(FErrors);
  FMasterAST := TCPMasterAST.Create();
  FSyntheticDecls := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPScriptEngine.Destroy();
begin
  FSyntheticDecls.Free();
  FMasterAST.Free();
  FInterpreter.Free();
  FSemantics.Free();
  FParser.Free();

  inherited;
end;

procedure TCPScriptEngine.SetExtension(const AExt: string);
begin
  FExtension := AExt;
end;

procedure TCPScriptEngine.SetPrintCallback(const ACallback: TCPScriptPrintCallback;
  const AUserData: Pointer);
var
  LCB: TCallback<TCPScriptPrintCallback>;
begin
  LCB.Callback := ACallback;
  LCB.UserData := AUserData;
  FInterpreter.PrintCallback := LCB;
end;

procedure TCPScriptEngine.RegisterGlobalRoutine(const ADeclaration: string;
  const AFunc: TCPScriptRoutineFunc; const AUserData: Pointer);
var
  LSource: string;
  LParser: TCPScriptParser;
  LTempAST: TCPMasterAST;
  LModule: TCPModuleNode;
  LDecl: TCPRoutineDeclNode;
begin
  // Wrap the declaration in a minimal module so the parser can handle it
  LSource := Format('''
    module script _synthetic;
    %s;
    begin
    end;
    begin
    end.
    ''',
    [ADeclaration]
  );

  LModule := nil;
  LParser := TCPScriptParser.Create();
  try
    LTempAST := TCPMasterAST.Create();
    try
      LModule := LParser.ParseModuleFromString(LSource, '_synthetic.cps', LTempAST);
      if (LModule = nil) or LParser.GetErrors().HasErrors() then
      begin
        FErrors.Add(esError, CP_ERR_SCR_002,
          'Invalid routine declaration: %s', [ADeclaration]);
        Exit;
      end;

      // Extract the routine node from the parsed module
      if (LModule.Declarations.Count = 0) or
        not (LModule.Declarations[0] is TCPRoutineDeclNode) then
      begin
        FErrors.Add(esError, CP_ERR_SCR_002,
          'Invalid routine declaration: %s', [ADeclaration]);
        Exit;
      end;

      LDecl := TCPRoutineDeclNode(LModule.Declarations.Extract(LModule.Declarations[0]));
      LDecl.IsExternal := True;
      LDecl.IsPublic := True;
      LDecl.Body.Clear();
      FSyntheticDecls.Add(LDecl);
      FInterpreter.RegisterBuiltin(LDecl, AFunc, AUserData);
    finally
      LModule.Free();
      LTempAST.Free();
    end;
  finally
    LParser.Free();
  end;
end;

{ TCPScriptEngine.RegisterGlobalData }
procedure TCPScriptEngine.RegisterGlobalData(const ADeclaration: string);
var
  LSource: string;
  LParser: TCPScriptParser;
  LTempAST: TCPMasterAST;
  LModule: TCPModuleNode;
  LDecl: TCPASTNode;
  I: Integer;
begin
  // Wrap the declaration in a minimal module so the parser can handle it
  LSource := Format('''
    module script _synthetic;
    %s
    begin
    end.
    ''',
    [ADeclaration]
  );

  LModule := nil;
  LParser := TCPScriptParser.Create();
  try
    LTempAST := TCPMasterAST.Create();
    try
      LModule := LParser.ParseModuleFromString(LSource, '_synthetic.cps', LTempAST);
      if (LModule = nil) or LParser.GetErrors().HasErrors() then
      begin
        FErrors.Add(esError, CP_ERR_SCR_003,
          'Invalid data declaration: %s', [ADeclaration]);
        Exit;
      end;

      // Extract all declarations from the parsed module
      for I := LModule.Declarations.Count - 1 downto 0 do
      begin
        LDecl := LModule.Declarations.Extract(LModule.Declarations[I]);
        FSyntheticDecls.Insert(0, LDecl);
      end;
    finally
      LModule.Free();
      LTempAST.Free();
    end;
  finally
    LParser.Free();
  end;
end;

function TCPScriptEngine.ExecuteFile(const AFilename: string): Boolean;
var
  LResolved: string;
  LSource: string;
begin
  LResolved := TUtils.ResolvePath(TPath.ChangeExtension(AFilename, FExtension));

  if not TFile.Exists(LResolved) then
  begin
    FErrors.Add(esError, CP_ERR_SCR_001,
      'Script file not found: %s', [LResolved]);
    Result := False;
    Exit;
  end;

  LSource := TFile.ReadAllText(LResolved, TEncoding.UTF8);
  Result := ExecuteSource(LSource, LResolved);
end;

function TCPScriptEngine.ExecuteSource(const ASource: string;
  const AFilename: string): Boolean;
var
  LModule: TCPModuleNode;
  I: Integer;
begin
  // Bail if registration errors exist
  if FErrors.HasErrors() then
  begin
    Result := False;
    Exit;
  end;

  // Clear previous execution state
  FErrors.Clear();
  FMasterAST.Free();
  FMasterAST := TCPMasterAST.Create();

  // Parse
  LModule := FParser.ParseModuleFromString(ASource, AFilename, FMasterAST);
  if (LModule = nil) or FErrors.HasErrors() then
  begin
    Result := False;
    Exit;
  end;

  // Inject synthetic builtin declarations at the front so semantics sees them
  for I := FSyntheticDecls.Count - 1 downto 0 do
    LModule.Declarations.Insert(0, FSyntheticDecls[I]);

  // Add module to master AST
  FMasterAST.AddModule(LModule);

  // Semantic analysis
  FSemantics.Analyze(FMasterAST);
  if FErrors.HasErrors() then
  begin
    // Remove synthetic decls so they are not freed with the module
    for I := 0 to FSyntheticDecls.Count - 1 do
      LModule.Declarations.Extract(FSyntheticDecls[I]);
    Result := False;
    Exit;
  end;

  // Execute
  try
    FInterpreter.Execute(LModule);
  except
    on E: Exception do
      FErrors.Add(esError, CP_ERR_SCR_004, '%s', [E.Message]);
  end;

  // Remove synthetic decls so they are not freed with the module
  for I := 0 to FSyntheticDecls.Count - 1 do
    LModule.Declarations.Extract(FSyntheticDecls[I]);

  Result := not FErrors.HasErrors();
end;

end.
