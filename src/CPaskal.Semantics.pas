{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.Semantics - Semantic analysis pass

  Walks the master AST and enriches every node with resolved types, symbols,
  and module references. Validates the entire program: type checking, symbol
  resolution, control flow, forward declarations, and intrinsic argument
  validation. After this pass, every node carries everything codegen needs.
  If codegen ever needs to "figure something out," that is a bug here.

  Dependencies: CPaskal.Common, CPaskal.AST, StdApp.Base
===============================================================================}

unit CPaskal.Semantics;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Rtti,
  StdApp.Base,
  CPaskal.Common,
  CPaskal.AST;

const
  // Error codes for semantic analysis
  CP_ERR_SEM_001 = 'SEM001';  // Undeclared identifier
  CP_ERR_SEM_002 = 'SEM002';  // Duplicate declaration
  CP_ERR_SEM_003 = 'SEM003';  // Type mismatch
  CP_ERR_SEM_004 = 'SEM004';  // Wrong argument count
  CP_ERR_SEM_005 = 'SEM005';  // Break/continue outside loop
  CP_ERR_SEM_006 = 'SEM006';  // Return outside routine
  CP_ERR_SEM_007 = 'SEM007';  // Missing return in function
  CP_ERR_SEM_008 = 'SEM008';  // Visibility violation
  CP_ERR_SEM_009 = 'SEM009';  // Unqualified import access
  CP_ERR_SEM_010 = 'SEM010';  // Forward not resolved
  CP_ERR_SEM_011 = 'SEM011';  // Forward signature mismatch
  CP_ERR_SEM_012 = 'SEM012';  // Forward type used in non-pointer context
  CP_ERR_SEM_013 = 'SEM013';  // Invalid operation on type
  CP_ERR_SEM_014 = 'SEM014';  // Const expression required
  CP_ERR_SEM_015 = 'SEM015';  // Invalid intrinsic argument
  CP_ERR_SEM_016 = 'SEM016';  // Char literal length
  CP_ERR_SEM_017 = 'SEM017';  // Invalid array bounds
  CP_ERR_SEM_018 = 'SEM018';  // Duplicate field name
  CP_ERR_SEM_019 = 'SEM019';  // Duplicate choices value

type
  { TCPScopeKind }
  TCPScopeKind = (
    skModule,
    skRoutine,
    skBlock,
    skTest
  );

  { TCPScope }
  TCPScope = class(TBaseObject)
  protected
    FScopeKind: TCPScopeKind;
    FParent: TCPScope;
    FSymbols: TDictionary<string, TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Declare(const AName: string; const ANode: TCPASTNode;
      const ALocation: TSourceRange);
    function Lookup(const AName: string): TCPASTNode;
    function LookupLocal(const AName: string): TCPASTNode;
    property ScopeKind: TCPScopeKind read FScopeKind write FScopeKind;
    property Parent: TCPScope read FParent write FParent;
  end;

  { TCPSemantics }
  TCPSemantics = class(TBaseObject)
  protected
    FMasterAST: TCPMasterAST;
    FCurrentScope: TCPScope;
    FCurrentModule: TCPModuleNode;
    FModuleScopes: TObjectDictionary<string, TCPScope>;
    FPrimitiveTypes: TObjectDictionary<TCPTokenKind, TCPTypeDeclNode>;
    FLoopDepth: Integer;
    FCurrentRoutine: TCPRoutineDeclNode;

    // Primitive type initialization
    procedure InitPrimitiveTypes();
    function GetPrimitiveType(const AKind: TCPTokenKind): TCPTypeDeclNode;

    // Scope management
    function PushScope(const AKind: TCPScopeKind): TCPScope;
    procedure PopScope();

    // Module processing
    procedure DoAnalyzeModule(const AModule: TCPModuleNode);

    // Declaration analysis
    procedure DoAnalyzeDeclaration(const ANode: TCPASTNode);
    procedure DoAnalyzeConstDecl(const ANode: TCPConstDeclNode);
    procedure DoAnalyzeTypeDecl(const ANode: TCPTypeDeclNode);
    procedure DoAnalyzeVarDecl(const ANode: TCPVarDeclNode);
    procedure DoAnalyzeRoutineDecl(const ANode: TCPRoutineDeclNode);
    procedure DoAnalyzeForwardTypeDecl(const ANode: TCPForwardTypeDeclNode);
    procedure DoAnalyzeForwardRoutineDecl(const ANode: TCPForwardRoutineDeclNode);

    // Type definition analysis
    procedure DoAnalyzeTypeDef(const ANode: TCPASTNode);
    procedure DoAnalyzeRecordType(const ANode: TCPRecordTypeNode);
    procedure DoAnalyzeOverlayType(const ANode: TCPOverlayTypeNode);
    procedure DoAnalyzeArrayType(const ANode: TCPArrayTypeNode);
    procedure DoAnalyzePointerType(const ANode: TCPPointerTypeNode);
    procedure DoAnalyzeSetType(const ANode: TCPSetTypeNode);
    procedure DoAnalyzeChoicesType(const ANode: TCPChoicesTypeNode);
    procedure DoAnalyzeRoutineType(const ANode: TCPRoutineTypeNode);

    // Statement analysis
    procedure DoAnalyzeStatement(const ANode: TCPASTNode);
    procedure DoAnalyzeStatementSeq(const AList: TObjectList<TCPASTNode>);
    procedure DoAnalyzeAssign(const ANode: TCPAssignNode);
    procedure DoAnalyzeCallStmt(const ANode: TCPCallStmtNode);
    procedure DoAnalyzeIf(const ANode: TCPIfNode);
    procedure DoAnalyzeWhile(const ANode: TCPWhileNode);
    procedure DoAnalyzeFor(const ANode: TCPForNode);
    procedure DoAnalyzeRepeat(const ANode: TCPRepeatNode);
    procedure DoAnalyzeMatch(const ANode: TCPMatchNode);
    procedure DoAnalyzeReturn(const ANode: TCPReturnNode);
    procedure DoAnalyzeGuard(const ANode: TCPGuardNode);
    procedure DoAnalyzeThrow(const ANode: TCPThrowNode);
    procedure DoAnalyzePrint(const ANode: TCPPrintNode);
    procedure DoAnalyzeAssert(const ANode: TCPAssertStmtNode);
    procedure DoAnalyzeBreak(const ANode: TCPBreakNode);
    procedure DoAnalyzeContinue(const ANode: TCPContinueNode);
    procedure DoAnalyzeCreate(const ANode: TCPCreateNode);
    procedure DoAnalyzeDestroy(const ANode: TCPDestroyNode);
    procedure DoAnalyzeGetMem(const ANode: TCPGetMemNode);
    procedure DoAnalyzeFreeMem(const ANode: TCPFreeMemNode);
    procedure DoAnalyzeResizeMem(const ANode: TCPResizeMemNode);
    procedure DoAnalyzeSetLength(const ANode: TCPSetLengthNode);

    // Expression analysis
    procedure DoAnalyzeExpr(const ANode: TCPExprNode);
    procedure DoAnalyzeBinaryExpr(const ANode: TCPBinaryExprNode);
    procedure DoAnalyzeUnaryExpr(const ANode: TCPUnaryExprNode);
    procedure DoAnalyzeIdentifier(const ANode: TCPIdentifierNode);
    procedure DoAnalyzeDotAccess(const ANode: TCPDotAccessNode);
    procedure DoAnalyzeIndexAccess(const ANode: TCPIndexAccessNode);
    procedure DoAnalyzeDeref(const ANode: TCPDerefNode);
    procedure DoAnalyzeCallExpr(const ANode: TCPCallExprNode);
    procedure DoAnalyzeTypeCast(const ANode: TCPTypeCastExprNode);
    procedure DoAnalyzeIntrinsic(const ANode: TCPIntrinsicExprNode);
    procedure DoAnalyzeSetLiteral(const ANode: TCPSetLiteralExprNode);
    procedure DoAnalyzeRecordLiteral(const ANode: TCPRecordLiteralNode);
    procedure DoAnalyzeTypeRef(const ANode: TCPTypeRefNode);

    // Literal type assignment
    procedure DoResolveLiteralType(const ANode: TCPExprNode);

    // Type helpers
    function ResolveTypeExpr(const ANode: TCPASTNode): TCPASTNode;
    function IsAssignableFrom(const ATarget: TCPASTNode; const ASource: TCPASTNode): Boolean;
    function PromoteTypes(const ALeft: TCPASTNode; const ARight: TCPASTNode): TCPASTNode;
    function IsIntegerType(const AType: TCPASTNode): Boolean;
    function IsFloatType(const AType: TCPASTNode): Boolean;
    function IsNumericType(const AType: TCPASTNode): Boolean;
    function IsBooleanType(const AType: TCPASTNode): Boolean;
    function IsStringType(const AType: TCPASTNode): Boolean;
    function IsPointerType(const AType: TCPASTNode): Boolean;

    // Forward declaration validation
    procedure DoValidateForwards();

    // Return path validation
    function DoCheckReturnPaths(const AList: TObjectList<TCPASTNode>): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure Analyze(const AMasterAST: TCPMasterAST);
  end;



implementation

{ TCPScope }
constructor TCPScope.Create();
begin
  inherited;

  FSymbols := TDictionary<string, TCPASTNode>.Create();
end;

destructor TCPScope.Destroy();
begin
  FSymbols.Free();

  inherited;
end;

procedure TCPScope.Declare(const AName: string; const ANode: TCPASTNode;
  const ALocation: TSourceRange);
begin
  if FSymbols.ContainsKey(AName) then
  begin
    FErrors.Add(ALocation, esError, CP_ERR_SEM_002,
      'Duplicate declaration: %s', [AName]);
    Exit;
  end;
  FSymbols.Add(AName, ANode);
end;

function TCPScope.Lookup(const AName: string): TCPASTNode;
var
  LScope: TCPScope;
begin
  Result := nil;
  LScope := Self;
  while LScope <> nil do
  begin
    if LScope.FSymbols.TryGetValue(AName, Result) then
      Exit;
    LScope := LScope.FParent;
  end;
end;

function TCPScope.LookupLocal(const AName: string): TCPASTNode;
begin
  if not FSymbols.TryGetValue(AName, Result) then
    Result := nil;
end;

{ TCPSemantics }
constructor TCPSemantics.Create();
begin
  inherited;

  FModuleScopes := TObjectDictionary<string, TCPScope>.Create([doOwnsValues]);
  FPrimitiveTypes := TObjectDictionary<TCPTokenKind, TCPTypeDeclNode>.Create([doOwnsValues]);
  FLoopDepth := 0;
  InitPrimitiveTypes();
end;

destructor TCPSemantics.Destroy();
begin
  FPrimitiveTypes.Free();
  FModuleScopes.Free();

  inherited;
end;

procedure TCPSemantics.InitPrimitiveTypes();

  procedure LRegister(const AKind: TCPTokenKind; const AName: string);
  var
    LNode: TCPTypeDeclNode;
  begin
    LNode := TCPTypeDeclNode.Create();
    LNode.DeclName := AName;
    FPrimitiveTypes.Add(AKind, LNode);
  end;

begin
  LRegister(tkInt8, 'int8');
  LRegister(tkInt16, 'int16');
  LRegister(tkInt32, 'int32');
  LRegister(tkInt64, 'int64');
  LRegister(tkUInt8, 'uint8');
  LRegister(tkUInt16, 'uint16');
  LRegister(tkUInt32, 'uint32');
  LRegister(tkUInt64, 'uint64');
  LRegister(tkFloat32, 'float32');
  LRegister(tkFloat64, 'float64');
  LRegister(tkBoolean, 'boolean');
  LRegister(tkChar, 'char');
  LRegister(tkWChar, 'wchar');
  LRegister(tkString, 'string');
  LRegister(tkWString, 'wstring');
  LRegister(tkPointer, 'pointer');
end;

function TCPSemantics.GetPrimitiveType(const AKind: TCPTokenKind): TCPTypeDeclNode;
begin
  if not FPrimitiveTypes.TryGetValue(AKind, Result) then
    Result := nil;
end;

function TCPSemantics.PushScope(const AKind: TCPScopeKind): TCPScope;
begin
  Result := TCPScope.Create();
  Result.SetErrors(FErrors);
  Result.ScopeKind := AKind;
  Result.Parent := FCurrentScope;
  FCurrentScope := Result;
end;

procedure TCPSemantics.PopScope();
var
  LOld: TCPScope;
begin
  LOld := FCurrentScope;
  FCurrentScope := FCurrentScope.Parent;
  // Module scopes are owned by FModuleScopes, don't free them here
  if LOld.ScopeKind <> skModule then
    LOld.Free();
end;

procedure TCPSemantics.Analyze(const AMasterAST: TCPMasterAST);
var
  I: Integer;
begin
  FMasterAST := AMasterAST;

  // Process all modules in order (import-dependency order)
  for I := 0 to FMasterAST.ModuleCount() - 1 do
    DoAnalyzeModule(FMasterAST.GetModuleAt(I));
end;

procedure TCPSemantics.DoAnalyzeModule(const AModule: TCPModuleNode);
var
  LScope: TCPScope;
  I: Integer;
begin
  FCurrentModule := AModule;

  // Create module scope
  LScope := PushScope(skModule);
  FModuleScopes.Add(AModule.ModuleName, LScope);

  // Resolve import nodes to their module nodes in the master AST
  for I := 0 to AModule.Imports.Count - 1 do
  begin
    AModule.Imports[I].ResolvedModule := FMasterAST.GetModule(
      AModule.Imports[I].ModuleName);
    if AModule.Imports[I].ResolvedModule = nil then
      FErrors.Add(AModule.Imports[I].Location, esError, CP_ERR_SEM_001,
        'Imported module not found: %s', [AModule.Imports[I].ModuleName]);
  end;

  // Walk declarations in order (declare-before-use)
  for I := 0 to AModule.Declarations.Count - 1 do
    DoAnalyzeDeclaration(AModule.Declarations[I]);

  // Validate all forward declarations resolved
  DoValidateForwards();

  // Analyze bodies
  DoAnalyzeStatementSeq(AModule.InitBody);
  DoAnalyzeStatementSeq(AModule.FinalBody);
  DoAnalyzeStatementSeq(AModule.MainBody);

  // Analyze test blocks
  for I := 0 to AModule.TestBlocks.Count - 1 do
  begin
    PushScope(skTest);
    // Register test block local vars
    DoAnalyzeStatementSeq(AModule.TestBlocks[I].Body);
    PopScope();
  end;

  // Pop module scope (stays in FModuleScopes)
  FCurrentScope := FCurrentScope.Parent;
end;

procedure TCPSemantics.DoAnalyzeDeclaration(const ANode: TCPASTNode);
begin
  if ANode is TCPConstDeclNode then
    DoAnalyzeConstDecl(TCPConstDeclNode(ANode))
  else if ANode is TCPTypeDeclNode then
    DoAnalyzeTypeDecl(TCPTypeDeclNode(ANode))
  else if ANode is TCPVarDeclNode then
    DoAnalyzeVarDecl(TCPVarDeclNode(ANode))
  else if ANode is TCPRoutineDeclNode then
    DoAnalyzeRoutineDecl(TCPRoutineDeclNode(ANode))
  else if ANode is TCPForwardTypeDeclNode then
    DoAnalyzeForwardTypeDecl(TCPForwardTypeDeclNode(ANode))
  else if ANode is TCPForwardRoutineDeclNode then
    DoAnalyzeForwardRoutineDecl(TCPForwardRoutineDeclNode(ANode))
  else if ANode is TCPDirectiveNode then
    // Directives don't need semantic analysis
  else
    FErrors.Add(ANode.Location, esError, CP_ERR_SEM_013,
      'Unexpected declaration node type');
end;

procedure TCPSemantics.DoAnalyzeConstDecl(const ANode: TCPConstDeclNode);
begin
  // Register in current scope
  FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Analyze the value expression
  if ANode.ValueExpr <> nil then
  begin
    DoAnalyzeExpr(TCPExprNode(ANode.ValueExpr));
    // Type annotation present -- resolve and check compatibility
    if ANode.TypeExpr <> nil then
    begin
      ANode.TypeExpr := ResolveTypeExpr(ANode.TypeExpr);
      if not IsAssignableFrom(ANode.TypeExpr, TCPExprNode(ANode.ValueExpr).ResolvedType) then
        FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
          'Const value type does not match declared type for: %s', [ANode.DeclName]);
    end;
  end;
end;

procedure TCPSemantics.DoAnalyzeTypeDecl(const ANode: TCPTypeDeclNode);
var
  LForward: TCPASTNode;
begin
  // Check if this resolves a forward declaration
  LForward := FCurrentScope.LookupLocal(ANode.DeclName);
  if LForward <> nil then
  begin
    if LForward is TCPForwardTypeDeclNode then
    begin
      // Link forward to full declaration
      TCPForwardTypeDeclNode(LForward).ResolvedDecl := ANode;
      // Update scope entry to point to full declaration
      FCurrentScope.FSymbols[ANode.DeclName] := ANode;
    end
    else
    begin
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_002,
        'Duplicate declaration: %s', [ANode.DeclName]);
      Exit;
    end;
  end
  else
    FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Analyze the type definition
  if ANode.TypeDef <> nil then
    DoAnalyzeTypeDef(ANode.TypeDef);
end;

procedure TCPSemantics.DoAnalyzeVarDecl(const ANode: TCPVarDeclNode);
begin
  FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Resolve the type expression
  if ANode.TypeExpr <> nil then
    ANode.TypeExpr := ResolveTypeExpr(ANode.TypeExpr);

  // Analyze initializer if present
  if ANode.InitExpr <> nil then
  begin
    DoAnalyzeExpr(TCPExprNode(ANode.InitExpr));
    if (ANode.TypeExpr <> nil) and (TCPExprNode(ANode.InitExpr).ResolvedType <> nil) then
    begin
      if not IsAssignableFrom(ANode.TypeExpr, TCPExprNode(ANode.InitExpr).ResolvedType) then
        FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
          'Initializer type does not match declared type for: %s', [ANode.DeclName]);
    end;
  end;
end;

procedure TCPSemantics.DoAnalyzeRoutineDecl(const ANode: TCPRoutineDeclNode);
var
  LForward: TCPASTNode;
  LScope: TCPScope;
  I: Integer;
  LPrevRoutine: TCPRoutineDeclNode;
begin
  // Check if this resolves a forward declaration
  LForward := FCurrentScope.LookupLocal(ANode.DeclName);
  if LForward <> nil then
  begin
    if LForward is TCPForwardRoutineDeclNode then
    begin
      // TODO: Verify signatures match
      TCPForwardRoutineDeclNode(LForward).ResolvedDecl := ANode;
      FCurrentScope.FSymbols[ANode.DeclName] := ANode;
    end
    else
    begin
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_002,
        'Duplicate declaration: %s', [ANode.DeclName]);
      Exit;
    end;
  end
  else
    FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Resolve return type
  if ANode.ReturnType <> nil then
    ANode.ReturnType := ResolveTypeExpr(ANode.ReturnType);

  // Resolve parameter types
  for I := 0 to ANode.Params.Count - 1 do
  begin
    if ANode.Params[I].TypeExpr <> nil then
      ANode.Params[I].TypeExpr := ResolveTypeExpr(ANode.Params[I].TypeExpr);
  end;

  // External routines have no body to analyze
  if ANode.IsExternal then
    Exit;

  // Push routine scope
  LScope := PushScope(skRoutine);
  LPrevRoutine := FCurrentRoutine;
  FCurrentRoutine := ANode;

  // Register parameters in routine scope
  for I := 0 to ANode.Params.Count - 1 do
    LScope.Declare(ANode.Params[I].ParamName, ANode.Params[I],
      ANode.Params[I].Location);

  // Register local types
  for I := 0 to ANode.LocalTypes.Count - 1 do
    DoAnalyzeTypeDecl(ANode.LocalTypes[I]);

  // Register local consts
  for I := 0 to ANode.LocalConsts.Count - 1 do
    DoAnalyzeConstDecl(ANode.LocalConsts[I]);

  // Register local vars
  for I := 0 to ANode.LocalVars.Count - 1 do
    DoAnalyzeVarDecl(ANode.LocalVars[I]);

  // Analyze body
  DoAnalyzeStatementSeq(ANode.Body);

  // Check return paths for functions
  if ANode.ReturnType <> nil then
  begin
    if not DoCheckReturnPaths(ANode.Body) then
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_007,
        'Not all code paths return a value in function: %s', [ANode.DeclName]);
  end;

  FCurrentRoutine := LPrevRoutine;
  PopScope();
end;

procedure TCPSemantics.DoAnalyzeForwardTypeDecl(const ANode: TCPForwardTypeDeclNode);
begin
  FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);
end;

procedure TCPSemantics.DoAnalyzeForwardRoutineDecl(const ANode: TCPForwardRoutineDeclNode);
var
  I: Integer;
begin
  FCurrentScope.Declare(ANode.DeclName, ANode, ANode.Location);

  // Resolve parameter types
  for I := 0 to ANode.Params.Count - 1 do
  begin
    if ANode.Params[I].TypeExpr <> nil then
      ANode.Params[I].TypeExpr := ResolveTypeExpr(ANode.Params[I].TypeExpr);
  end;

  // Resolve return type
  if ANode.ReturnType <> nil then
    ANode.ReturnType := ResolveTypeExpr(ANode.ReturnType);
end;

procedure TCPSemantics.DoValidateForwards();
var
  LPair: TPair<string, TCPASTNode>;
begin
  for LPair in FCurrentScope.FSymbols do
  begin
    if (LPair.Value is TCPForwardTypeDeclNode) and
       (TCPForwardTypeDeclNode(LPair.Value).ResolvedDecl = nil) then
      FErrors.Add(LPair.Value.Location, esError, CP_ERR_SEM_010,
        'Forward type never defined: %s', [LPair.Key]);

    if (LPair.Value is TCPForwardRoutineDeclNode) and
       (TCPForwardRoutineDeclNode(LPair.Value).ResolvedDecl = nil) then
      FErrors.Add(LPair.Value.Location, esError, CP_ERR_SEM_010,
        'Forward routine never defined: %s', [LPair.Key]);
  end;
end;

// Type definition analysis
procedure TCPSemantics.DoAnalyzeTypeDef(const ANode: TCPASTNode);
begin
  if ANode is TCPRecordTypeNode then
    DoAnalyzeRecordType(TCPRecordTypeNode(ANode))
  else if ANode is TCPOverlayTypeNode then
    DoAnalyzeOverlayType(TCPOverlayTypeNode(ANode))
  else if ANode is TCPArrayTypeNode then
    DoAnalyzeArrayType(TCPArrayTypeNode(ANode))
  else if ANode is TCPPointerTypeNode then
    DoAnalyzePointerType(TCPPointerTypeNode(ANode))
  else if ANode is TCPSetTypeNode then
    DoAnalyzeSetType(TCPSetTypeNode(ANode))
  else if ANode is TCPChoicesTypeNode then
    DoAnalyzeChoicesType(TCPChoicesTypeNode(ANode))
  else if ANode is TCPRoutineTypeNode then
    DoAnalyzeRoutineType(TCPRoutineTypeNode(ANode));
end;

procedure TCPSemantics.DoAnalyzeRecordType(const ANode: TCPRecordTypeNode);
var
  I: Integer;
  LField: TCPFieldDeclNode;
  LNames: TDictionary<string, Boolean>;
begin
  // Resolve base type if present
  if ANode.BaseType <> nil then
    ANode.BaseType := ResolveTypeExpr(ANode.BaseType);

  // Check for duplicate field names and resolve field types
  LNames := TDictionary<string, Boolean>.Create();
  try
    for I := 0 to ANode.Fields.Count - 1 do
    begin
      if ANode.Fields[I] is TCPFieldDeclNode then
      begin
        LField := TCPFieldDeclNode(ANode.Fields[I]);
        if LNames.ContainsKey(LField.FieldName) then
          FErrors.Add(LField.Location, esError, CP_ERR_SEM_018,
            'Duplicate field name: %s', [LField.FieldName])
        else
          LNames.Add(LField.FieldName, True);

        if LField.TypeExpr <> nil then
          LField.TypeExpr := ResolveTypeExpr(LField.TypeExpr);
      end
      else if ANode.Fields[I] is TCPAnonOverlayNode then
        DoAnalyzeTypeDef(ANode.Fields[I]);
    end;
  finally
    LNames.Free();
  end;
end;

procedure TCPSemantics.DoAnalyzeOverlayType(const ANode: TCPOverlayTypeNode);
var
  I: Integer;
  LField: TCPFieldDeclNode;
  LNames: TDictionary<string, Boolean>;
begin
  LNames := TDictionary<string, Boolean>.Create();
  try
    for I := 0 to ANode.Fields.Count - 1 do
    begin
      if ANode.Fields[I] is TCPFieldDeclNode then
      begin
        LField := TCPFieldDeclNode(ANode.Fields[I]);
        if LNames.ContainsKey(LField.FieldName) then
          FErrors.Add(LField.Location, esError, CP_ERR_SEM_018,
            'Duplicate field name: %s', [LField.FieldName])
        else
          LNames.Add(LField.FieldName, True);

        if LField.TypeExpr <> nil then
          LField.TypeExpr := ResolveTypeExpr(LField.TypeExpr);
      end;
    end;
  finally
    LNames.Free();
  end;
end;

procedure TCPSemantics.DoAnalyzeArrayType(const ANode: TCPArrayTypeNode);
begin
  if ANode.ElementType <> nil then
    ANode.ElementType := ResolveTypeExpr(ANode.ElementType);
end;

procedure TCPSemantics.DoAnalyzePointerType(const ANode: TCPPointerTypeNode);
begin
  // Pointer target can reference a forward-declared type
  if ANode.TargetType <> nil then
    ANode.TargetType := ResolveTypeExpr(ANode.TargetType);
end;

procedure TCPSemantics.DoAnalyzeSetType(const ANode: TCPSetTypeNode);
begin
  if ANode.ElementType <> nil then
    ANode.ElementType := ResolveTypeExpr(ANode.ElementType);
end;

procedure TCPSemantics.DoAnalyzeChoicesType(const ANode: TCPChoicesTypeNode);
var
  I: Integer;
  LVal: TCPChoicesValueNode;
begin
  for I := 0 to ANode.Members.Count - 1 do
  begin
    LVal := TCPChoicesValueNode(ANode.Members[I]);
    // Analyze explicit value expression if present
    if LVal.ValueExpr <> nil then
      DoAnalyzeExpr(TCPExprNode(LVal.ValueExpr));
  end;
end;

procedure TCPSemantics.DoAnalyzeRoutineType(const ANode: TCPRoutineTypeNode);
var
  I: Integer;
begin
  for I := 0 to ANode.Params.Count - 1 do
  begin
    if ANode.Params[I].TypeExpr <> nil then
      ANode.Params[I].TypeExpr := ResolveTypeExpr(ANode.Params[I].TypeExpr);
  end;

  if ANode.ReturnType <> nil then
    ANode.ReturnType := ResolveTypeExpr(ANode.ReturnType);
end;

// Statement analysis
procedure TCPSemantics.DoAnalyzeStatementSeq(const AList: TObjectList<TCPASTNode>);
var
  I: Integer;
begin
  if AList = nil then
    Exit;
  for I := 0 to AList.Count - 1 do
    DoAnalyzeStatement(AList[I]);
end;

procedure TCPSemantics.DoAnalyzeStatement(const ANode: TCPASTNode);
begin
  if ANode is TCPAssignNode then
    DoAnalyzeAssign(TCPAssignNode(ANode))
  else if ANode is TCPCallStmtNode then
    DoAnalyzeCallStmt(TCPCallStmtNode(ANode))
  else if ANode is TCPIfNode then
    DoAnalyzeIf(TCPIfNode(ANode))
  else if ANode is TCPWhileNode then
    DoAnalyzeWhile(TCPWhileNode(ANode))
  else if ANode is TCPForNode then
    DoAnalyzeFor(TCPForNode(ANode))
  else if ANode is TCPRepeatNode then
    DoAnalyzeRepeat(TCPRepeatNode(ANode))
  else if ANode is TCPMatchNode then
    DoAnalyzeMatch(TCPMatchNode(ANode))
  else if ANode is TCPReturnNode then
    DoAnalyzeReturn(TCPReturnNode(ANode))
  else if ANode is TCPGuardNode then
    DoAnalyzeGuard(TCPGuardNode(ANode))
  else if ANode is TCPThrowNode then
    DoAnalyzeThrow(TCPThrowNode(ANode))
  else if ANode is TCPPrintNode then
    DoAnalyzePrint(TCPPrintNode(ANode))
  else if ANode is TCPAssertStmtNode then
    DoAnalyzeAssert(TCPAssertStmtNode(ANode))
  else if ANode is TCPBreakNode then
    DoAnalyzeBreak(TCPBreakNode(ANode))
  else if ANode is TCPContinueNode then
    DoAnalyzeContinue(TCPContinueNode(ANode))
  else if ANode is TCPCreateNode then
    DoAnalyzeCreate(TCPCreateNode(ANode))
  else if ANode is TCPDestroyNode then
    DoAnalyzeDestroy(TCPDestroyNode(ANode))
  else if ANode is TCPGetMemNode then
    DoAnalyzeGetMem(TCPGetMemNode(ANode))
  else if ANode is TCPFreeMemNode then
    DoAnalyzeFreeMem(TCPFreeMemNode(ANode))
  else if ANode is TCPResizeMemNode then
    DoAnalyzeResizeMem(TCPResizeMemNode(ANode))
  else if ANode is TCPSetLengthNode then
    DoAnalyzeSetLength(TCPSetLengthNode(ANode))
  else if ANode is TCPThrowCodeNode then
    // ThrowCode has code + message expressions
    DoAnalyzeThrow(nil)  // handled inline
  else if ANode is TCPDirectiveNode then
    // Directives in statement position -- no analysis needed
  ;
end;

procedure TCPSemantics.DoAnalyzeAssign(const ANode: TCPAssignNode);
begin
  DoAnalyzeExpr(TCPExprNode(ANode.Target));
  DoAnalyzeExpr(TCPExprNode(ANode.ValueExpr));

  // Type check: value must be assignable to target
  if (TCPExprNode(ANode.Target).ResolvedType <> nil) and
     (TCPExprNode(ANode.ValueExpr).ResolvedType <> nil) then
  begin
    if not IsAssignableFrom(TCPExprNode(ANode.Target).ResolvedType,
                            TCPExprNode(ANode.ValueExpr).ResolvedType) then
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
        'Cannot assign: type mismatch');
  end;
end;

procedure TCPSemantics.DoAnalyzeCallStmt(const ANode: TCPCallStmtNode);
begin
  // The call expression handles all resolution
  if ANode.CallExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.CallExpr));
end;

procedure TCPSemantics.DoAnalyzeIf(const ANode: TCPIfNode);
begin
  // Condition must be boolean
  DoAnalyzeExpr(TCPExprNode(ANode.Condition));
  if (TCPExprNode(ANode.Condition).ResolvedType <> nil) and
     (not IsBooleanType(TCPExprNode(ANode.Condition).ResolvedType)) then
    FErrors.Add(ANode.Condition.Location, esError, CP_ERR_SEM_003,
      'If condition must be boolean');

  DoAnalyzeStatementSeq(ANode.ThenBody);

  // ElseBody contains either the else statements or a nested TCPIfNode
  // for elsif chains (parser flattens elsif into nested if/else)
  DoAnalyzeStatementSeq(ANode.ElseBody);
end;

procedure TCPSemantics.DoAnalyzeWhile(const ANode: TCPWhileNode);
begin
  DoAnalyzeExpr(TCPExprNode(ANode.Condition));
  if (TCPExprNode(ANode.Condition).ResolvedType <> nil) and
     (not IsBooleanType(TCPExprNode(ANode.Condition).ResolvedType)) then
    FErrors.Add(ANode.Condition.Location, esError, CP_ERR_SEM_003,
      'While condition must be boolean');

  Inc(FLoopDepth);
  DoAnalyzeStatementSeq(ANode.Body);
  Dec(FLoopDepth);
end;

procedure TCPSemantics.DoAnalyzeFor(const ANode: TCPForNode);
begin
  // Analyze start and end expressions
  DoAnalyzeExpr(TCPExprNode(ANode.StartExpr));
  DoAnalyzeExpr(TCPExprNode(ANode.EndExpr));

  // Push block scope for iterator variable
  PushScope(skBlock);

  Inc(FLoopDepth);
  DoAnalyzeStatementSeq(ANode.Body);
  Dec(FLoopDepth);

  PopScope();
end;

procedure TCPSemantics.DoAnalyzeRepeat(const ANode: TCPRepeatNode);
begin
  Inc(FLoopDepth);
  DoAnalyzeStatementSeq(ANode.Body);
  Dec(FLoopDepth);

  DoAnalyzeExpr(TCPExprNode(ANode.Condition));
  if (TCPExprNode(ANode.Condition).ResolvedType <> nil) and
     (not IsBooleanType(TCPExprNode(ANode.Condition).ResolvedType)) then
    FErrors.Add(ANode.Condition.Location, esError, CP_ERR_SEM_003,
      'Repeat condition must be boolean');
end;

procedure TCPSemantics.DoAnalyzeMatch(const ANode: TCPMatchNode);
var
  I: Integer;
  LArm: TCPMatchArmNode;
begin
  DoAnalyzeExpr(TCPExprNode(ANode.Expr));

  for I := 0 to ANode.Arms.Count - 1 do
  begin
    LArm := TCPMatchArmNode(ANode.Arms[I]);
    DoAnalyzeStatementSeq(LArm.Body);
  end;

  // Analyze else body if present
  DoAnalyzeStatementSeq(ANode.ElseBody);
end;

procedure TCPSemantics.DoAnalyzeReturn(const ANode: TCPReturnNode);
begin
  if FCurrentRoutine = nil then
  begin
    FErrors.Add(ANode.Location, esError, CP_ERR_SEM_006,
      'Return statement outside of a routine');
    Exit;
  end;

  if ANode.ValueExpr <> nil then
  begin
    DoAnalyzeExpr(TCPExprNode(ANode.ValueExpr));
    // Check return type matches
    if (FCurrentRoutine.ReturnType <> nil) and
       (TCPExprNode(ANode.ValueExpr).ResolvedType <> nil) then
    begin
      if not IsAssignableFrom(FCurrentRoutine.ReturnType,
                              TCPExprNode(ANode.ValueExpr).ResolvedType) then
        FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
          'Return value type does not match function return type');
    end;
  end
  else if FCurrentRoutine.ReturnType <> nil then
    FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
      'Function requires a return value');
end;

procedure TCPSemantics.DoAnalyzeGuard(const ANode: TCPGuardNode);
begin
  DoAnalyzeStatementSeq(ANode.GuardBody);
  DoAnalyzeStatementSeq(ANode.ExceptBody);
  DoAnalyzeStatementSeq(ANode.FinallyBody);
end;

procedure TCPSemantics.DoAnalyzeThrow(const ANode: TCPThrowNode);
begin
  if ANode = nil then
    Exit;
  if ANode.MessageExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.MessageExpr));
end;

procedure TCPSemantics.DoAnalyzePrint(const ANode: TCPPrintNode);
var
  I: Integer;
begin
  // All print arguments (first is format string, rest are values)
  for I := 0 to ANode.Args.Count - 1 do
    DoAnalyzeExpr(TCPExprNode(ANode.Args[I]));
end;

procedure TCPSemantics.DoAnalyzeAssert(const ANode: TCPAssertStmtNode);
var
  I: Integer;
begin
  // Analyze all assert arguments
  for I := 0 to ANode.Args.Count - 1 do
    DoAnalyzeExpr(TCPExprNode(ANode.Args[I]));
end;

procedure TCPSemantics.DoAnalyzeBreak(const ANode: TCPBreakNode);
begin
  if FLoopDepth = 0 then
    FErrors.Add(ANode.Location, esError, CP_ERR_SEM_005,
      'Break statement outside of a loop');
end;

procedure TCPSemantics.DoAnalyzeContinue(const ANode: TCPContinueNode);
begin
  if FLoopDepth = 0 then
    FErrors.Add(ANode.Location, esError, CP_ERR_SEM_005,
      'Continue statement outside of a loop');
end;

procedure TCPSemantics.DoAnalyzeCreate(const ANode: TCPCreateNode);
begin
  if ANode.ArgExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.ArgExpr));
end;

procedure TCPSemantics.DoAnalyzeDestroy(const ANode: TCPDestroyNode);
begin
  if ANode.ArgExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.ArgExpr));
end;

procedure TCPSemantics.DoAnalyzeGetMem(const ANode: TCPGetMemNode);
begin
  if ANode.ArgExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.ArgExpr));
end;

procedure TCPSemantics.DoAnalyzeFreeMem(const ANode: TCPFreeMemNode);
begin
  if ANode.ArgExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.ArgExpr));
end;

procedure TCPSemantics.DoAnalyzeResizeMem(const ANode: TCPResizeMemNode);
begin
  if ANode.PtrExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.PtrExpr));
  if ANode.SizeExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.SizeExpr));
end;

procedure TCPSemantics.DoAnalyzeSetLength(const ANode: TCPSetLengthNode);
begin
  if ANode.TargetExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.TargetExpr));
  if ANode.LengthExpr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.LengthExpr));
end;

// Expression analysis
procedure TCPSemantics.DoAnalyzeExpr(const ANode: TCPExprNode);
begin
  if ANode = nil then
    Exit;

  if ANode is TCPBinaryExprNode then
    DoAnalyzeBinaryExpr(TCPBinaryExprNode(ANode))
  else if ANode is TCPUnaryExprNode then
    DoAnalyzeUnaryExpr(TCPUnaryExprNode(ANode))
  else if ANode is TCPIdentifierNode then
    DoAnalyzeIdentifier(TCPIdentifierNode(ANode))
  else if ANode is TCPDotAccessNode then
    DoAnalyzeDotAccess(TCPDotAccessNode(ANode))
  else if ANode is TCPIndexAccessNode then
    DoAnalyzeIndexAccess(TCPIndexAccessNode(ANode))
  else if ANode is TCPDerefNode then
    DoAnalyzeDeref(TCPDerefNode(ANode))
  else if ANode is TCPCallExprNode then
    DoAnalyzeCallExpr(TCPCallExprNode(ANode))
  else if ANode is TCPTypeCastExprNode then
    DoAnalyzeTypeCast(TCPTypeCastExprNode(ANode))
  else if ANode is TCPIntrinsicExprNode then
    DoAnalyzeIntrinsic(TCPIntrinsicExprNode(ANode))
  else if ANode is TCPSetLiteralExprNode then
    DoAnalyzeSetLiteral(TCPSetLiteralExprNode(ANode))
  else if ANode is TCPRecordLiteralNode then
    DoAnalyzeRecordLiteral(TCPRecordLiteralNode(ANode))
  else if ANode is TCPTypeRefNode then
    DoAnalyzeTypeRef(TCPTypeRefNode(ANode))
  else if (ANode is TCPIntLiteralNode) or (ANode is TCPFloatLiteralNode) or
          (ANode is TCPStringLiteralNode) or (ANode is TCPWStringLiteralNode) or
          (ANode is TCPBoolLiteralNode) or (ANode is TCPNilLiteralNode) then
    DoResolveLiteralType(ANode);
end;

procedure TCPSemantics.DoResolveLiteralType(const ANode: TCPExprNode);
begin
  if ANode is TCPIntLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkInt32)
  else if ANode is TCPFloatLiteralNode then
  begin
    if TCPFloatLiteralNode(ANode).HasSuffix then
      ANode.ResolvedType := GetPrimitiveType(tkFloat32)
    else
      ANode.ResolvedType := GetPrimitiveType(tkFloat64);
  end
  else if ANode is TCPStringLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkString)
  else if ANode is TCPWStringLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkWString)
  else if ANode is TCPBoolLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkBoolean)
  else if ANode is TCPNilLiteralNode then
    ANode.ResolvedType := GetPrimitiveType(tkPointer);
end;

procedure TCPSemantics.DoAnalyzeBinaryExpr(const ANode: TCPBinaryExprNode);
var
  LLeft: TCPASTNode;
  LRight: TCPASTNode;
begin
  DoAnalyzeExpr(TCPExprNode(ANode.Left));
  DoAnalyzeExpr(TCPExprNode(ANode.Right));

  LLeft := TCPExprNode(ANode.Left).ResolvedType;
  LRight := TCPExprNode(ANode.Right).ResolvedType;

  if (LLeft = nil) or (LRight = nil) then
    Exit;

  // Comparison operators always produce boolean
  case ANode.Op of
    boEq, boNotEq, boLess, boGreater, boLessEq, boGreaterEq:
      ANode.ResolvedType := GetPrimitiveType(tkBoolean);
    boAnd, boOr, boXor:
    begin
      if (not IsBooleanType(LLeft)) or (not IsBooleanType(LRight)) then
        FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
          'Boolean operator requires boolean operands');
      ANode.ResolvedType := GetPrimitiveType(tkBoolean);

      // Disambiguate for codegen: boolean and/or -> logical (&&/||)
      if IsBooleanType(LLeft) and IsBooleanType(LRight) then
      begin
        if ANode.Op = boAnd then
          ANode.Op := boLogicalAnd
        else if ANode.Op = boOr then
          ANode.Op := boLogicalOr;
      end;
    end;
    boIn:
      ANode.ResolvedType := GetPrimitiveType(tkBoolean);
  else
    // Arithmetic: promote types
    ANode.ResolvedType := PromoteTypes(LLeft, LRight);
    if ANode.ResolvedType = nil then
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
        'Incompatible types for binary operator');
  end;
end;

procedure TCPSemantics.DoAnalyzeUnaryExpr(const ANode: TCPUnaryExprNode);
begin
  DoAnalyzeExpr(TCPExprNode(ANode.Operand));

  if TCPExprNode(ANode.Operand).ResolvedType = nil then
    Exit;

  if ANode.Op = uoNot then
  begin
    if not IsBooleanType(TCPExprNode(ANode.Operand).ResolvedType) then
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
        'Not operator requires boolean operand');
    ANode.ResolvedType := GetPrimitiveType(tkBoolean);
  end
  else
    // Unary minus/plus: same type as operand
    ANode.ResolvedType := TCPExprNode(ANode.Operand).ResolvedType;
end;

procedure TCPSemantics.DoAnalyzeIdentifier(const ANode: TCPIdentifierNode);
var
  LDecl: TCPASTNode;
begin
  LDecl := FCurrentScope.Lookup(ANode.IdentName);

  // Check if it's an imported module name (would need dot access)
  if LDecl = nil then
  begin
    // Check if it matches any import name -- that's an unqualified access error
    if FCurrentModule <> nil then
    begin
      // Check imports for name match
    end;
    FErrors.Add(ANode.Location, esError, CP_ERR_SEM_001,
      'Undeclared identifier: %s', [ANode.IdentName]);
    Exit;
  end;

  ANode.ResolvedDecl := LDecl;

  // Resolve type based on what the identifier refers to
  if LDecl is TCPVarDeclNode then
    ANode.ResolvedType := TCPVarDeclNode(LDecl).TypeExpr
  else if LDecl is TCPConstDeclNode then
  begin
    if TCPConstDeclNode(LDecl).TypeExpr <> nil then
      ANode.ResolvedType := TCPConstDeclNode(LDecl).TypeExpr
    else if TCPConstDeclNode(LDecl).ValueExpr <> nil then
      ANode.ResolvedType := TCPExprNode(TCPConstDeclNode(LDecl).ValueExpr).ResolvedType;
  end
  else if LDecl is TCPParamDeclNode then
    ANode.ResolvedType := TCPParamDeclNode(LDecl).TypeExpr
  else if LDecl is TCPRoutineDeclNode then
    // Identifier refers to a routine -- type is the routine itself
    ANode.ResolvedType := LDecl
  else if LDecl is TCPForwardRoutineDeclNode then
    ANode.ResolvedType := LDecl
  else if LDecl is TCPTypeDeclNode then
    ANode.ResolvedType := LDecl;
end;

procedure TCPSemantics.DoAnalyzeDotAccess(const ANode: TCPDotAccessNode);
var
  LLeft: TCPExprNode;
  LModuleScope: TCPScope;
  LDecl: TCPASTNode;
  LRecordType: TCPRecordTypeNode;
  LField: TCPFieldDeclNode;
  I: Integer;
begin
  LLeft := TCPExprNode(ANode.BaseExpr);
  DoAnalyzeExpr(LLeft);

  // Check if left side is a module name (cross-module qualified access)
  if (LLeft is TCPIdentifierNode) and (TCPIdentifierNode(LLeft).ResolvedDecl = nil) then
  begin
    // It might be a module name -- check imports
    if FModuleScopes.TryGetValue(TCPIdentifierNode(LLeft).IdentName, LModuleScope) then
    begin
      // Verify it's actually imported
      LDecl := LModuleScope.LookupLocal(ANode.MemberName);
      if LDecl = nil then
      begin
        FErrors.Add(ANode.Location, esError, CP_ERR_SEM_001,
          'Symbol not found in module %s: %s',
          [TCPIdentifierNode(LLeft).IdentName, ANode.MemberName]);
        Exit;
      end;

      // Check visibility
      if (LDecl is TCPDeclNode) and (not TCPDeclNode(LDecl).IsPublic) then
      begin
        FErrors.Add(ANode.Location, esError, CP_ERR_SEM_008,
          'Symbol %s.%s is not public',
          [TCPIdentifierNode(LLeft).IdentName, ANode.MemberName]);
        Exit;
      end;

      ANode.ResolvedDecl := LDecl;
      ANode.AccessKind := dakModule;
      // Resolve type of the accessed symbol
      if LDecl is TCPVarDeclNode then
        ANode.ResolvedType := TCPVarDeclNode(LDecl).TypeExpr
      else if LDecl is TCPConstDeclNode then
        ANode.ResolvedType := TCPConstDeclNode(LDecl).TypeExpr
      else if LDecl is TCPRoutineDeclNode then
        ANode.ResolvedType := LDecl
      else if LDecl is TCPTypeDeclNode then
        ANode.ResolvedType := LDecl;
      Exit;
    end;
  end;

  // Left side is a record -- resolve field access
  if LLeft.ResolvedType is TCPTypeDeclNode then
  begin
    if TCPTypeDeclNode(LLeft.ResolvedType).TypeDef is TCPRecordTypeNode then
    begin
      LRecordType := TCPRecordTypeNode(TCPTypeDeclNode(LLeft.ResolvedType).TypeDef);
      for I := 0 to LRecordType.Fields.Count - 1 do
      begin
        if LRecordType.Fields[I] is TCPFieldDeclNode then
        begin
          LField := TCPFieldDeclNode(LRecordType.Fields[I]);
          if LField.FieldName = ANode.MemberName then
          begin
            ANode.ResolvedDecl := LField;
            ANode.ResolvedType := LField.TypeExpr;
            ANode.AccessKind := dakField;
            Exit;
          end;
        end;
      end;
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_001,
        'Field not found: %s', [ANode.MemberName]);
    end
    else if TCPTypeDeclNode(LLeft.ResolvedType).TypeDef is TCPChoicesTypeNode then
    begin
      // Choices member access: MyEnum.Value
      ANode.AccessKind := dakChoices;
      ANode.ResolvedType := LLeft.ResolvedType;
    end;
  end;
end;

procedure TCPSemantics.DoAnalyzeIndexAccess(const ANode: TCPIndexAccessNode);
begin
  DoAnalyzeExpr(TCPExprNode(ANode.BaseExpr));
  DoAnalyzeExpr(TCPExprNode(ANode.IndexExpr));

  // Index must be integer
  if (TCPExprNode(ANode.IndexExpr).ResolvedType <> nil) and
     (not IsIntegerType(TCPExprNode(ANode.IndexExpr).ResolvedType)) then
    FErrors.Add(ANode.IndexExpr.Location, esError, CP_ERR_SEM_003,
      'Array index must be an integer type');

  // Result type is the array element type
  if TCPExprNode(ANode.BaseExpr).ResolvedType is TCPTypeDeclNode then
  begin
    if TCPTypeDeclNode(TCPExprNode(ANode.BaseExpr).ResolvedType).TypeDef is TCPArrayTypeNode then
      ANode.ResolvedType := TCPArrayTypeNode(
        TCPTypeDeclNode(TCPExprNode(ANode.BaseExpr).ResolvedType).TypeDef).ElementType;
  end;
end;

procedure TCPSemantics.DoAnalyzeDeref(const ANode: TCPDerefNode);
begin
  DoAnalyzeExpr(TCPExprNode(ANode.BaseExpr));

  if TCPExprNode(ANode.BaseExpr).ResolvedType = nil then
    Exit;

  if not IsPointerType(TCPExprNode(ANode.BaseExpr).ResolvedType) then
    FErrors.Add(ANode.Location, esError, CP_ERR_SEM_013,
      'Dereference requires a pointer type');

  // Result type is the pointer's target type
  if TCPExprNode(ANode.BaseExpr).ResolvedType is TCPTypeDeclNode then
  begin
    if TCPTypeDeclNode(TCPExprNode(ANode.BaseExpr).ResolvedType).TypeDef is TCPPointerTypeNode then
      ANode.ResolvedType := TCPPointerTypeNode(
        TCPTypeDeclNode(TCPExprNode(ANode.BaseExpr).ResolvedType).TypeDef).TargetType;
  end;
end;

procedure TCPSemantics.DoAnalyzeCallExpr(const ANode: TCPCallExprNode);
var
  LRoutine: TCPRoutineDeclNode;
  LForwardRoutine: TCPForwardRoutineDeclNode;
  I: Integer;
begin
  DoAnalyzeExpr(TCPExprNode(ANode.Callee));

  // Analyze arguments
  for I := 0 to ANode.Args.Count - 1 do
    DoAnalyzeExpr(TCPExprNode(ANode.Args[I]));

  // Resolve the call target
  if TCPExprNode(ANode.Callee).ResolvedType is TCPRoutineDeclNode then
  begin
    LRoutine := TCPRoutineDeclNode(TCPExprNode(ANode.Callee).ResolvedType);
    ANode.ResolvedRoutine := LRoutine;
    ANode.ResolvedType := LRoutine.ReturnType;

    // Check argument count (account for variadic)
    if not LRoutine.IsVariadic then
    begin
      if ANode.Args.Count <> LRoutine.Params.Count then
        FErrors.Add(ANode.Location, esError, CP_ERR_SEM_004,
          'Expected %d arguments, got %d', [LRoutine.Params.Count, ANode.Args.Count]);
    end
    else
    begin
      if ANode.Args.Count < LRoutine.Params.Count then
        FErrors.Add(ANode.Location, esError, CP_ERR_SEM_004,
          'Expected at least %d arguments, got %d', [LRoutine.Params.Count, ANode.Args.Count]);
    end;
  end
  else if TCPExprNode(ANode.Callee).ResolvedType is TCPForwardRoutineDeclNode then
  begin
    LForwardRoutine := TCPForwardRoutineDeclNode(TCPExprNode(ANode.Callee).ResolvedType);
    ANode.ResolvedRoutine := LForwardRoutine;
    ANode.ResolvedType := LForwardRoutine.ReturnType;
  end;
end;

procedure TCPSemantics.DoAnalyzeTypeCast(const ANode: TCPTypeCastExprNode);
begin
  if ANode.TargetType <> nil then
    ANode.TargetType := ResolveTypeExpr(ANode.TargetType);
  if ANode.Expr <> nil then
    DoAnalyzeExpr(TCPExprNode(ANode.Expr));
  ANode.ResolvedType := ANode.TargetType;
end;

procedure TCPSemantics.DoAnalyzeIntrinsic(const ANode: TCPIntrinsicExprNode);
var
  I: Integer;
begin
  // Analyze all arguments
  for I := 0 to ANode.Args.Count - 1 do
    DoAnalyzeExpr(TCPExprNode(ANode.Args[I]));

  // Resolve result type based on intrinsic kind
  case ANode.IntrinsicKind of
    ikLen:
      ANode.ResolvedType := GetPrimitiveType(tkInt32);
    ikSize:
      ANode.ResolvedType := GetPrimitiveType(tkInt64);
    ikParamCount:
      ANode.ResolvedType := GetPrimitiveType(tkInt32);
    ikParamStr:
      ANode.ResolvedType := GetPrimitiveType(tkString);
    ikExcCode:
      ANode.ResolvedType := GetPrimitiveType(tkInt32);
    ikExcMsg:
      ANode.ResolvedType := GetPrimitiveType(tkString);
    ikUtf8:
      ANode.ResolvedType := GetPrimitiveType(tkString);
    ikWStr:
      ANode.ResolvedType := GetPrimitiveType(tkWString);
    ikCStr:
      ANode.ResolvedType := GetPrimitiveType(tkPointer);
  end;
end;

procedure TCPSemantics.DoAnalyzeSetLiteral(const ANode: TCPSetLiteralExprNode);
var
  I: Integer;
begin
  for I := 0 to ANode.Elements.Count - 1 do
  begin
    if TCPSetElementNode(ANode.Elements[I]).LowExpr <> nil then
      DoAnalyzeExpr(TCPExprNode(TCPSetElementNode(ANode.Elements[I]).LowExpr));
    if TCPSetElementNode(ANode.Elements[I]).HighExpr <> nil then
      DoAnalyzeExpr(TCPExprNode(TCPSetElementNode(ANode.Elements[I]).HighExpr));
  end;
end;

procedure TCPSemantics.DoAnalyzeRecordLiteral(const ANode: TCPRecordLiteralNode);
var
  I: Integer;
  LDecl: TCPASTNode;
begin
  // Resolve the type by name
  if ANode.TypeName <> '' then
  begin
    LDecl := FCurrentScope.Lookup(ANode.TypeName);
    if LDecl <> nil then
      ANode.ResolvedType := LDecl
    else
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_001,
        'Undeclared type: %s', [ANode.TypeName]);
  end;

  for I := 0 to ANode.FieldInits.Count - 1 do
  begin
    if ANode.FieldInits[I].ValueExpr <> nil then
      DoAnalyzeExpr(TCPExprNode(ANode.FieldInits[I].ValueExpr));
  end;
end;

procedure TCPSemantics.DoAnalyzeTypeRef(const ANode: TCPTypeRefNode);
begin
  ANode.ResolvedDecl := ResolveTypeExpr(ANode);
  ANode.ResolvedType := ANode.ResolvedDecl;

  // Set CppTypeText for user-defined types (primitives already set by parser)
  if (ANode.CppTypeText = '') and (ANode.ResolvedDecl is TCPTypeDeclNode) then
    ANode.CppTypeText := TCPTypeDeclNode(ANode.ResolvedDecl).DeclName;
end;

// Type resolution and helpers
function TCPSemantics.ResolveTypeExpr(const ANode: TCPASTNode): TCPASTNode;
var
  LDecl: TCPASTNode;
  LRef: TCPTypeRefNode;
  LName: string;
  LModuleScope: TCPScope;
begin
  Result := ANode;

  if ANode is TCPTypeRefNode then
  begin
    LRef := TCPTypeRefNode(ANode);

    // Check if it's a primitive type by token kind
    if LRef.TokenKind <> tkIdentifier then
    begin
      if FPrimitiveTypes.TryGetValue(LRef.TokenKind, TCPTypeDeclNode(Result)) then
        Exit;
    end;

    // Qualified access: ModuleName.TypeName
    if Length(LRef.QualParts) = 2 then
    begin
      if FModuleScopes.TryGetValue(LRef.QualParts[0], LModuleScope) then
      begin
        LDecl := LModuleScope.LookupLocal(LRef.QualParts[1]);
        if LDecl = nil then
        begin
          FErrors.Add(ANode.Location, esError, CP_ERR_SEM_001,
            'Type not found in module %s: %s', [LRef.QualParts[0], LRef.QualParts[1]]);
          Exit;
        end;
        if (LDecl is TCPDeclNode) and (not TCPDeclNode(LDecl).IsPublic) then
        begin
          FErrors.Add(ANode.Location, esError, CP_ERR_SEM_008,
            'Type %s.%s is not public', [LRef.QualParts[0], LRef.QualParts[1]]);
          Exit;
        end;
        Result := LDecl;
        Exit;
      end;
    end;

    // Unqualified: single name lookup
    if Length(LRef.QualParts) = 1 then
      LName := LRef.QualParts[0]
    else
      LName := '';

    if LName = '' then
      Exit;

    LDecl := FCurrentScope.Lookup(LName);
    if LDecl = nil then
    begin
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_001,
        'Undeclared type: %s', [LName]);
      Exit;
    end;

    if (LDecl is TCPTypeDeclNode) or (LDecl is TCPForwardTypeDeclNode) then
      Result := LDecl
    else
      FErrors.Add(ANode.Location, esError, CP_ERR_SEM_003,
        '%s is not a type', [LName]);
  end;
end;

function TCPSemantics.IsAssignableFrom(const ATarget: TCPASTNode;
  const ASource: TCPASTNode): Boolean;
begin
  Result := False;
  if (ATarget = nil) or (ASource = nil) then
    Exit;

  // Same type
  if ATarget = ASource then
  begin
    Result := True;
    Exit;
  end;

  // Nil assignable to any pointer
  if IsPointerType(ATarget) and (ASource = GetPrimitiveType(tkPointer)) then
  begin
    Result := True;
    Exit;
  end;

  // Numeric promotion: int -> float
  if IsFloatType(ATarget) and IsIntegerType(ASource) then
  begin
    Result := True;
    Exit;
  end;

  // Smaller int -> larger int
  if IsIntegerType(ATarget) and IsIntegerType(ASource) then
  begin
    Result := True;
    Exit;
  end;

  // float32 -> float64
  if IsFloatType(ATarget) and IsFloatType(ASource) then
  begin
    Result := True;
    Exit;
  end;
end;

function TCPSemantics.PromoteTypes(const ALeft: TCPASTNode;
  const ARight: TCPASTNode): TCPASTNode;
begin
  Result := nil;
  if (ALeft = nil) or (ARight = nil) then
    Exit;

  // Same type
  if ALeft = ARight then
  begin
    Result := ALeft;
    Exit;
  end;

  // Float + int -> float
  if IsFloatType(ALeft) and IsIntegerType(ARight) then
  begin
    Result := ALeft;
    Exit;
  end;
  if IsIntegerType(ALeft) and IsFloatType(ARight) then
  begin
    Result := ARight;
    Exit;
  end;

  // float32 + float64 -> float64
  if IsFloatType(ALeft) and IsFloatType(ARight) then
  begin
    Result := GetPrimitiveType(tkFloat64);
    Exit;
  end;

  // int + int -> larger int (simplified: promote to int64)
  if IsIntegerType(ALeft) and IsIntegerType(ARight) then
  begin
    Result := GetPrimitiveType(tkInt64);
    Exit;
  end;

  // String + string
  if IsStringType(ALeft) and IsStringType(ARight) then
  begin
    if ALeft = ARight then
      Result := ALeft
    else
      Result := GetPrimitiveType(tkString);
    Exit;
  end;
end;

function TCPSemantics.IsIntegerType(const AType: TCPASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkInt8)) or
            (AType = GetPrimitiveType(tkInt16)) or
            (AType = GetPrimitiveType(tkInt32)) or
            (AType = GetPrimitiveType(tkInt64)) or
            (AType = GetPrimitiveType(tkUInt8)) or
            (AType = GetPrimitiveType(tkUInt16)) or
            (AType = GetPrimitiveType(tkUInt32)) or
            (AType = GetPrimitiveType(tkUInt64));
end;

function TCPSemantics.IsFloatType(const AType: TCPASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkFloat32)) or
            (AType = GetPrimitiveType(tkFloat64));
end;

function TCPSemantics.IsNumericType(const AType: TCPASTNode): Boolean;
begin
  Result := IsIntegerType(AType) or IsFloatType(AType);
end;

function TCPSemantics.IsBooleanType(const AType: TCPASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkBoolean));
end;

function TCPSemantics.IsStringType(const AType: TCPASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkString)) or
            (AType = GetPrimitiveType(tkWString));
end;

function TCPSemantics.IsPointerType(const AType: TCPASTNode): Boolean;
begin
  Result := (AType = GetPrimitiveType(tkPointer));
  // Also check for typed pointers (pointer to T)
  if (not Result) and (AType is TCPTypeDeclNode) then
    Result := TCPTypeDeclNode(AType).TypeDef is TCPPointerTypeNode;
end;

function TCPSemantics.DoCheckReturnPaths(const AList: TObjectList<TCPASTNode>): Boolean;
var
  I: Integer;
  LNode: TCPASTNode;
  LIf: TCPIfNode;
begin
  Result := False;
  if (AList = nil) or (AList.Count = 0) then
    Exit;

  // Check last statement
  LNode := AList[AList.Count - 1];

  if LNode is TCPReturnNode then
  begin
    Result := True;
    Exit;
  end;

  // If/else: all branches must return
  // (elsif is flattened into nested if/else by parser)
  if LNode is TCPIfNode then
  begin
    LIf := TCPIfNode(LNode);
    // Must have an else branch
    if (LIf.ElseBody = nil) or (LIf.ElseBody.Count = 0) then
      Exit;

    // Then branch must return
    if not DoCheckReturnPaths(LIf.ThenBody) then
      Exit;

    // Else branch must return (may contain nested if for elsif chains)
    Result := DoCheckReturnPaths(LIf.ElseBody);
    Exit;
  end;

  // Match with else arm: all arms must return
  if LNode is TCPMatchNode then
  begin
    // Simplified: check if all arms return
    Result := True;
    for I := 0 to TCPMatchNode(LNode).Arms.Count - 1 do
    begin
      if not DoCheckReturnPaths(TCPMatchArmNode(TCPMatchNode(LNode).Arms[I]).Body) then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;
end;

end.
