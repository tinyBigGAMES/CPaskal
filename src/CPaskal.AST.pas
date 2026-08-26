{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.AST - Abstract Syntax Tree node types

  Defines all AST node classes for the CPaskal compiler. Every syntactic
  construct in the BNF grammar has a corresponding node type. The master AST
  container (TCPMasterAST) holds all parsed modules as a flat list of
  TCPModuleNode children.

  Design rules:
    - Every source detail is preserved on nodes (modifiers, linkage, visibility)
    - Semantic pass enriches nodes with resolved types and symbol references
    - Codegen is a dumb walker: it reads node fields and emits C++23
    - No side-channel structures: everything lives on the tree

  Dependencies: CPaskal.Common, StdApp.Base
  Notes: Do NOT add System.TypInfo to uses -- tk* collision risk.
===============================================================================}

unit CPaskal.AST;

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  StdApp.Base,
  CPaskal.Common;

type

  // Forward declarations
  TCPASTNode = class;
  TCPDeclNode = class;
  TCPExprNode = class;
  TCPModuleNode = class;
  TCPDirectiveNode = class;
  TCPImportNode = class;
  TCPTestBlockNode = class;
  TCPConstDeclNode = class;
  TCPTypeDeclNode = class;
  TCPVarDeclNode = class;
  TCPRoutineDeclNode = class;
  TCPForwardTypeDeclNode = class;
  TCPForwardRoutineDeclNode = class;
  TCPParamDeclNode = class;
  TCPRecordTypeNode = class;
  TCPOverlayTypeNode = class;
  TCPAnonRecordNode = class;
  TCPAnonOverlayNode = class;
  TCPFieldDeclNode = class;
  TCPArrayTypeNode = class;
  TCPPointerTypeNode = class;
  TCPSetTypeNode = class;
  TCPChoicesTypeNode = class;
  TCPChoicesValueNode = class;
  TCPRoutineTypeNode = class;
  TCPTypeRefNode = class;
  TCPOverloadGroupNode = class;
  TCPAssignNode = class;
  TCPCallStmtNode = class;
  TCPIfNode = class;
  TCPWhileNode = class;
  TCPForNode = class;
  TCPRepeatNode = class;
  TCPBreakNode = class;
  TCPContinueNode = class;
  TCPMatchNode = class;
  TCPMatchArmNode = class;
  TCPMatchLabelNode = class;
  TCPReturnNode = class;
  TCPGuardNode = class;
  TCPThrowNode = class;
  TCPThrowCodeNode = class;
  TCPCppBlockNode = class;
  TCPCppExprNode = class;
  TCPCreateNode = class;
  TCPDestroyNode = class;
  TCPGetMemNode = class;
  TCPFreeMemNode = class;
  TCPResizeMemNode = class;
  TCPSetLengthNode = class;
  TCPPrintNode = class;
  TCPAssertStmtNode = class;
  TCPBinaryExprNode = class;
  TCPUnaryExprNode = class;
  TCPIntLiteralNode = class;
  TCPFloatLiteralNode = class;
  TCPStringLiteralNode = class;
  TCPWStringLiteralNode = class;
  TCPBoolLiteralNode = class;
  TCPNilLiteralNode = class;
  TCPIdentifierNode = class;
  TCPDotAccessNode = class;
  TCPIndexAccessNode = class;
  TCPDerefNode = class;
  TCPCallExprNode = class;
  TCPSetLiteralExprNode = class;
  TCPSetElementNode = class;
  TCPRecordLiteralNode = class;
  TCPFieldInitNode = class;
  TCPTypeCastExprNode = class;
  TCPIntrinsicExprNode = class;

  { TCPModuleKind }
  TCPModuleKind = (
    mkExe,
    mkDll,
    mkLib,
    mkUnit
  );

  { TCPLinkage }
  TCPLinkage = (
    lkDefault,          // no linkage spec given (defaults to C linkage)
    lkCLink,            // explicit clink
    lkCppLink           // explicit cpplink
  );

  { TCPParamMode }
  TCPParamMode = (
    pmConst,            // const (default per coding standards)
    pmVar,              // var (pass by reference, mutable)
    pmDefault           // no modifier specified in source
  );

  { TCPAssignOp }
  TCPAssignOp = (
    aoAssign,           // :=
    aoPlusAssign,       // +=
    aoMinusAssign,      // -=
    aoMulAssign,        // *=
    aoDivAssign         // /=
  );

  { TCPBinaryOp }
  TCPBinaryOp = (
    // Multiplicative (precedence 2)
    boMul,              // *
    boDiv,              // /
    boIntDiv,           // div
    boMod,              // mod
    boAnd,              // and
    boShl,              // shl
    boShr,              // shr
    // Additive (precedence 3)
    boAdd,              // +
    boSub,              // -
    boOr,               // or
    boXor,              // xor
    // Logical (disambiguated by semantics from bitwise boAnd/boOr)
    boLogicalAnd,       // and (when both operands are boolean)
    boLogicalOr,        // or  (when both operands are boolean)
    // Relational (precedence 4)
    boEq,               // =
    boNotEq,            // <>
    boLess,             // <
    boGreater,          // >
    boLessEq,           // <=
    boGreaterEq,        // >=
    boIn                // in
  );

  { TCPUnaryOp }
  TCPUnaryOp = (
    uoNot,              // not
    uoNegate,           // - (unary minus)
    uoPositive,         // + (unary plus)
    uoAddressOf         // address of
  );

  { TCPAssertKind }
  TCPAssertKind = (
    akAssert,           // assert(expr)
    akTrue,             // asserttrue(expr)
    akFalse,            // assertfalse(expr)
    akEq,               // asserteq(expected, actual)
    akEqF,              // asserteqf(expected, actual, epsilon)
    akNil,              // assertnil(expr)
    akNotNil,           // assertnotnil(expr)
    akFail              // assertfail("message")
  );

  { TCPIntrinsicKind }
  TCPIntrinsicKind = (
    ikLen,              // len(expr)
    ikSize,             // size(type_or_expr)
    ikUtf8,             // utf8(expr)
    ikCStr,             // cstr(expr)
    ikWStr,             // wstr(expr)
    ikParamCount,       // paramcount()
    ikParamStr,         // paramstr(expr)
    ikExcCode,          // exccode()
    ikExcMsg            // excmsg()
  );

  { TCPASTNode }
  TCPASTNode = class
  protected
    FLocation: TSourceRange;
  public
    constructor Create(); virtual;
    destructor Destroy(); override;
    property Location: TSourceRange read FLocation write FLocation;
  end;

  { TCPDeclNode }
  TCPDeclNode = class(TCPASTNode)
  protected
    FDeclName: string;
    FIsPublic: Boolean;
  public
    property DeclName: string read FDeclName write FDeclName;
    property IsPublic: Boolean read FIsPublic write FIsPublic;
  end;

  { TCPExprNode }
  TCPExprNode = class(TCPASTNode)
  protected
    FResolvedType: TCPASTNode;   // populated by semantic pass
  public
    property ResolvedType: TCPASTNode read FResolvedType write FResolvedType;
  end;

  { TCPModuleNode }
  TCPModuleNode = class(TCPASTNode)
  protected
    FModuleName: string;
    FModuleKind: TCPModuleKind;
    FSourceFile: string;
    FDirectives: TObjectList<TCPDirectiveNode>;
    FImports: TObjectList<TCPImportNode>;
    FDeclarations: TObjectList<TCPASTNode>;
    FInitBody: TObjectList<TCPASTNode>;
    FFinalBody: TObjectList<TCPASTNode>;
    FMainBody: TObjectList<TCPASTNode>;
    FTestBlocks: TObjectList<TCPTestBlockNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property ModuleName: string read FModuleName write FModuleName;
    property ModuleKind: TCPModuleKind read FModuleKind write FModuleKind;
    property SourceFile: string read FSourceFile write FSourceFile;
    property Directives: TObjectList<TCPDirectiveNode> read FDirectives;
    property Imports: TObjectList<TCPImportNode> read FImports;
    property Declarations: TObjectList<TCPASTNode> read FDeclarations;
    property InitBody: TObjectList<TCPASTNode> read FInitBody;
    property FinalBody: TObjectList<TCPASTNode> read FFinalBody;
    property MainBody: TObjectList<TCPASTNode> read FMainBody;
    property TestBlocks: TObjectList<TCPTestBlockNode> read FTestBlocks;
  end;

  { TCPDirectiveNode }
  TCPDirectiveNode = class(TCPASTNode)
  protected
    FDirectiveName: string;
    FDirectiveValue: string;
  public
    property DirectiveName: string read FDirectiveName write FDirectiveName;
    property DirectiveValue: string read FDirectiveValue write FDirectiveValue;
  end;

  { TCPImportNode }
  TCPImportNode = class(TCPASTNode)
  protected
    FModuleName: string;
    FResolvedModule: TCPModuleNode;  // populated by semantic pass
  public
    property ModuleName: string read FModuleName write FModuleName;
    property ResolvedModule: TCPModuleNode read FResolvedModule write FResolvedModule;
  end;

  { TCPTestBlockNode }
  TCPTestBlockNode = class(TCPASTNode)
  protected
    FTestName: string;
    FCppTestName: string;
    FLocals: TObjectList<TCPVarDeclNode>;
    FBody: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property TestName: string read FTestName write FTestName;
    property CppTestName: string read FCppTestName write FCppTestName;
    property Locals: TObjectList<TCPVarDeclNode> read FLocals;
    property Body: TObjectList<TCPASTNode> read FBody;
  end;

  { TCPConstDeclNode }
  TCPConstDeclNode = class(TCPDeclNode)
  protected
    FTypeExpr: TCPASTNode;       // nil if type is inferred
    FValueExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property TypeExpr: TCPASTNode read FTypeExpr write FTypeExpr;
    property ValueExpr: TCPASTNode read FValueExpr write FValueExpr;
  end;

  { TCPTypeDeclNode }
  TCPTypeDeclNode = class(TCPDeclNode)
  protected
    FTypeDef: TCPASTNode;        // record/overlay/array/pointer/set/choices/routine/typeref
    FPrimitiveKind: TCPTokenKind;  // tkChar, tkInt32, etc. for synthetic primitives; tkUnknown otherwise
    FCppTypeName: string;          // C++23 type name for primitives (e.g. 'int32_t', 'double')
  public
    destructor Destroy(); override;
    property TypeDef: TCPASTNode read FTypeDef write FTypeDef;
    property PrimitiveKind: TCPTokenKind read FPrimitiveKind write FPrimitiveKind;
    property CppTypeName: string read FCppTypeName write FCppTypeName;
  end;

  { TCPVarDeclNode }
  TCPVarDeclNode = class(TCPDeclNode)
  protected
    FTypeExpr: TCPASTNode;
    FInitExpr: TCPASTNode;       // nil if no initializer
    FIsExternal: Boolean;
    FExternalLib: string;
  public
    destructor Destroy(); override;
    property TypeExpr: TCPASTNode read FTypeExpr write FTypeExpr;
    property InitExpr: TCPASTNode read FInitExpr write FInitExpr;
    property IsExternal: Boolean read FIsExternal write FIsExternal;
    property ExternalLib: string read FExternalLib write FExternalLib;
  end;

  { TCPRoutineDeclNode }
  TCPRoutineDeclNode = class(TCPDeclNode)
  protected
    FLinkage: TCPLinkage;
    FParams: TObjectList<TCPParamDeclNode>;
    FReturnType: TCPASTNode;     // nil for procedures
    FIsExternal: Boolean;
    FExternalLib: string;
    FIsVariadic: Boolean;
    FLocalTypes: TObjectList<TCPTypeDeclNode>;
    FLocalConsts: TObjectList<TCPConstDeclNode>;
    FLocalVars: TObjectList<TCPVarDeclNode>;
    FBody: TObjectList<TCPASTNode>;  // nil for external routines
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Linkage: TCPLinkage read FLinkage write FLinkage;
    property Params: TObjectList<TCPParamDeclNode> read FParams;
    property ReturnType: TCPASTNode read FReturnType write FReturnType;
    property IsExternal: Boolean read FIsExternal write FIsExternal;
    property ExternalLib: string read FExternalLib write FExternalLib;
    property IsVariadic: Boolean read FIsVariadic write FIsVariadic;
    property LocalTypes: TObjectList<TCPTypeDeclNode> read FLocalTypes;
    property LocalConsts: TObjectList<TCPConstDeclNode> read FLocalConsts;
    property LocalVars: TObjectList<TCPVarDeclNode> read FLocalVars;
    property Body: TObjectList<TCPASTNode> read FBody;
  end;

  { TCPOverloadGroupNode }
  // Groups multiple routines with the same name but different signatures.
  // Non-owning: routines are owned by the module's declaration list.
  TCPOverloadGroupNode = class(TCPDeclNode)
  protected
    FOverloads: TList<TCPRoutineDeclNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Overloads: TList<TCPRoutineDeclNode> read FOverloads;
  end;

  { TCPForwardTypeDeclNode }
  // Forward type declaration: forward type TFoo;
  // Only valid in pointer-to contexts until full definition is seen
  TCPForwardTypeDeclNode = class(TCPDeclNode)
  protected
    FResolvedDecl: TCPASTNode;   // populated by semantic pass -- points to full type decl
  public
    property ResolvedDecl: TCPASTNode read FResolvedDecl write FResolvedDecl;
  end;

  { TCPForwardRoutineDeclNode }
  // Forward routine declaration: forward routine Foo(x: int32): int32;
  // Carries full signature so calls are valid immediately
  TCPForwardRoutineDeclNode = class(TCPDeclNode)
  protected
    FLinkage: TCPLinkage;
    FParams: TObjectList<TCPParamDeclNode>;
    FReturnType: TCPASTNode;
    FIsVariadic: Boolean;
    FResolvedDecl: TCPASTNode;   // populated by semantic pass -- points to full routine decl
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Linkage: TCPLinkage read FLinkage write FLinkage;
    property Params: TObjectList<TCPParamDeclNode> read FParams;
    property ReturnType: TCPASTNode read FReturnType write FReturnType;
    property IsVariadic: Boolean read FIsVariadic write FIsVariadic;
    property ResolvedDecl: TCPASTNode read FResolvedDecl write FResolvedDecl;
  end;

  { TCPParamDeclNode }
  TCPParamDeclNode = class(TCPASTNode)
  protected
    FParamName: string;
    FParamMode: TCPParamMode;
    FTypeExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property ParamName: string read FParamName write FParamName;
    property ParamMode: TCPParamMode read FParamMode write FParamMode;
    property TypeExpr: TCPASTNode read FTypeExpr write FTypeExpr;
  end;

  { TCPRecordTypeNode }
  TCPRecordTypeNode = class(TCPASTNode)
  protected
    FIsPacked: Boolean;
    FAlignment: Integer;         // 0 = default alignment
    FBaseType: TCPASTNode;       // nil = no inheritance
    FFields: TObjectList<TCPASTNode>;  // TCPFieldDeclNode or TCPAnonOverlayNode
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IsPacked: Boolean read FIsPacked write FIsPacked;
    property Alignment: Integer read FAlignment write FAlignment;
    property BaseType: TCPASTNode read FBaseType write FBaseType;
    property Fields: TObjectList<TCPASTNode> read FFields;
  end;

  { TCPOverlayTypeNode }
  TCPOverlayTypeNode = class(TCPASTNode)
  protected
    FFields: TObjectList<TCPASTNode>;  // TCPFieldDeclNode or TCPAnonRecordNode
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Fields: TObjectList<TCPASTNode> read FFields;
  end;

  { TCPAnonRecordNode }
  TCPAnonRecordNode = class(TCPASTNode)
  protected
    FIsPacked: Boolean;
    FFields: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IsPacked: Boolean read FIsPacked write FIsPacked;
    property Fields: TObjectList<TCPASTNode> read FFields;
  end;

  { TCPAnonOverlayNode }
  TCPAnonOverlayNode = class(TCPASTNode)
  protected
    FFields: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Fields: TObjectList<TCPASTNode> read FFields;
  end;

  { TCPFieldDeclNode }
  TCPFieldDeclNode = class(TCPASTNode)
  protected
    FFieldName: string;
    FTypeExpr: TCPASTNode;
    FBitWidth: Integer;          // 0 = no bit field
  public
    destructor Destroy(); override;
    property FieldName: string read FFieldName write FFieldName;
    property TypeExpr: TCPASTNode read FTypeExpr write FTypeExpr;
    property BitWidth: Integer read FBitWidth write FBitWidth;
  end;

  { TCPArrayTypeNode }
  TCPArrayTypeNode = class(TCPASTNode)
  protected
    FElementType: TCPASTNode;
    FIsDynamic: Boolean;         // true = no bounds specified
    FLowBound: Int64;
    FHighBound: Int64;
  public
    destructor Destroy(); override;
    property ElementType: TCPASTNode read FElementType write FElementType;
    property IsDynamic: Boolean read FIsDynamic write FIsDynamic;
    property LowBound: Int64 read FLowBound write FLowBound;
    property HighBound: Int64 read FHighBound write FHighBound;
  end;

  { TCPPointerTypeNode }
  TCPPointerTypeNode = class(TCPASTNode)
  protected
    FTargetType: TCPASTNode;     // nil = untyped pointer
    FIsConstTarget: Boolean;
  public
    destructor Destroy(); override;
    property TargetType: TCPASTNode read FTargetType write FTargetType;
    property IsConstTarget: Boolean read FIsConstTarget write FIsConstTarget;
  end;

  { TCPSetTypeNode }
  TCPSetTypeNode = class(TCPASTNode)
  protected
    FElementType: TCPASTNode;    // nil for bare "set"
    FIsRangeForm: Boolean;       // true = integer..integer form
    FRangeLow: Int64;
    FRangeHigh: Int64;
  public
    destructor Destroy(); override;
    property ElementType: TCPASTNode read FElementType write FElementType;
    property IsRangeForm: Boolean read FIsRangeForm write FIsRangeForm;
    property RangeLow: Int64 read FRangeLow write FRangeLow;
    property RangeHigh: Int64 read FRangeHigh write FRangeHigh;
  end;

  { TCPChoicesTypeNode }
  TCPChoicesTypeNode = class(TCPASTNode)
  protected
    FMembers: TObjectList<TCPChoicesValueNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Members: TObjectList<TCPChoicesValueNode> read FMembers;
  end;

  { TCPChoicesValueNode }
  TCPChoicesValueNode = class(TCPASTNode)
  protected
    FMemberName: string;
    FValueExpr: TCPASTNode;      // nil = auto-assigned
  public
    destructor Destroy(); override;
    property MemberName: string read FMemberName write FMemberName;
    property ValueExpr: TCPASTNode read FValueExpr write FValueExpr;
  end;

  { TCPRoutineTypeNode }
  TCPRoutineTypeNode = class(TCPASTNode)
  protected
    FLinkage: TCPLinkage;
    FParams: TObjectList<TCPParamDeclNode>;
    FReturnType: TCPASTNode;     // nil for procedure type
    FIsVariadic: Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Linkage: TCPLinkage read FLinkage write FLinkage;
    property Params: TObjectList<TCPParamDeclNode> read FParams;
    property ReturnType: TCPASTNode read FReturnType write FReturnType;
    property IsVariadic: Boolean read FIsVariadic write FIsVariadic;
  end;

  { TCPTypeRefNode }
  TCPTypeRefNode = class(TCPExprNode)
  protected
    FTokenKind: TCPTokenKind;    // tkInt32 etc. for primitives, tkIdentifier for user types
    FQualParts: TArray<string>;  // ['ModName', 'TypeName'] for qualified access
    FResolvedDecl: TCPASTNode;   // populated by semantic pass
    FCppTypeText: string;        // C++23 type string, set by parser/semantics
  public
    property TokenKind: TCPTokenKind read FTokenKind write FTokenKind;
    property QualParts: TArray<string> read FQualParts write FQualParts;
    property ResolvedDecl: TCPASTNode read FResolvedDecl write FResolvedDecl;
    property CppTypeText: string read FCppTypeText write FCppTypeText;
  end;

  { TCPAssignNode }
  TCPAssignNode = class(TCPASTNode)
  protected
    FTarget: TCPASTNode;         // designator (expression node)
    FOp: TCPAssignOp;
    FValueExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property Target: TCPASTNode read FTarget write FTarget;
    property Op: TCPAssignOp read FOp write FOp;
    property ValueExpr: TCPASTNode read FValueExpr write FValueExpr;
  end;

  { TCPCallStmtNode }
  TCPCallStmtNode = class(TCPASTNode)
  protected
    FCallExpr: TCPASTNode;       // typically a TCPCallExprNode
  public
    destructor Destroy(); override;
    property CallExpr: TCPASTNode read FCallExpr write FCallExpr;
  end;

  { TCPIfNode }
  TCPIfNode = class(TCPASTNode)
  protected
    FCondition: TCPASTNode;
    FThenBody: TObjectList<TCPASTNode>;
    FElseBody: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Condition: TCPASTNode read FCondition write FCondition;
    property ThenBody: TObjectList<TCPASTNode> read FThenBody;
    property ElseBody: TObjectList<TCPASTNode> read FElseBody;
  end;

  { TCPWhileNode }
  TCPWhileNode = class(TCPASTNode)
  protected
    FCondition: TCPASTNode;
    FBody: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Condition: TCPASTNode read FCondition write FCondition;
    property Body: TObjectList<TCPASTNode> read FBody;
  end;

  { TCPForNode }
  TCPForNode = class(TCPASTNode)
  protected
    FIteratorName: string;
    FStartExpr: TCPASTNode;
    FEndExpr: TCPASTNode;
    FIsDownTo: Boolean;
    FBody: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IteratorName: string read FIteratorName write FIteratorName;
    property StartExpr: TCPASTNode read FStartExpr write FStartExpr;
    property EndExpr: TCPASTNode read FEndExpr write FEndExpr;
    property IsDownTo: Boolean read FIsDownTo write FIsDownTo;
    property Body: TObjectList<TCPASTNode> read FBody;
  end;

  { TCPRepeatNode }
  TCPRepeatNode = class(TCPASTNode)
  protected
    FBody: TObjectList<TCPASTNode>;
    FCondition: TCPASTNode;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Body: TObjectList<TCPASTNode> read FBody;
    property Condition: TCPASTNode read FCondition write FCondition;
  end;

  { TCPBreakNode }
  TCPBreakNode = class(TCPASTNode);

  { TCPContinueNode }
  TCPContinueNode = class(TCPASTNode);

  { TCPMatchNode }
  TCPMatchNode = class(TCPASTNode)
  protected
    FExpr: TCPASTNode;
    FArms: TObjectList<TCPMatchArmNode>;
    FElseBody: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Expr: TCPASTNode read FExpr write FExpr;
    property Arms: TObjectList<TCPMatchArmNode> read FArms;
    property ElseBody: TObjectList<TCPASTNode> read FElseBody;
  end;

  { TCPMatchArmNode }
  TCPMatchArmNode = class(TCPASTNode)
  protected
    FLabels: TObjectList<TCPMatchLabelNode>;
    FBody: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Labels: TObjectList<TCPMatchLabelNode> read FLabels;
    property Body: TObjectList<TCPASTNode> read FBody;
  end;

  { TCPMatchLabelNode }
  TCPMatchLabelNode = class(TCPASTNode)
  protected
    FLowExpr: TCPASTNode;
    FHighExpr: TCPASTNode;       // nil = single value, not a range
  public
    destructor Destroy(); override;
    property LowExpr: TCPASTNode read FLowExpr write FLowExpr;
    property HighExpr: TCPASTNode read FHighExpr write FHighExpr;
  end;

  { TCPReturnNode }
  TCPReturnNode = class(TCPASTNode)
  protected
    FValueExpr: TCPASTNode;      // nil = void return
  public
    destructor Destroy(); override;
    property ValueExpr: TCPASTNode read FValueExpr write FValueExpr;
  end;

  { TCPGuardNode }
  TCPGuardNode = class(TCPASTNode)
  protected
    FGuardBody: TObjectList<TCPASTNode>;
    FExceptBody: TObjectList<TCPASTNode>;   // nil = no except clause
    FFinallyBody: TObjectList<TCPASTNode>;  // nil = no finally clause
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property GuardBody: TObjectList<TCPASTNode> read FGuardBody;
    property ExceptBody: TObjectList<TCPASTNode> read FExceptBody;
    property FinallyBody: TObjectList<TCPASTNode> read FFinallyBody;
  end;

  { TCPThrowNode }
  TCPThrowNode = class(TCPASTNode)
  protected
    FMessageExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property MessageExpr: TCPASTNode read FMessageExpr write FMessageExpr;
  end;

  { TCPThrowCodeNode }
  TCPThrowCodeNode = class(TCPASTNode)
  protected
    FCodeExpr: TCPASTNode;
    FMessageExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property CodeExpr: TCPASTNode read FCodeExpr write FCodeExpr;
    property MessageExpr: TCPASTNode read FMessageExpr write FMessageExpr;
  end;

  { TCPCppBlockNode }
  // cppstart header|source ... cppend -- injects raw C/C++ into output
  TCPCppBlockNode = class(TCPASTNode)
  protected
    FTarget: string;    // 'header' or 'source'
    FRawText: string;   // verbatim C/C++ text
  public
    property Target: string read FTarget write FTarget;
    property RawText: string read FRawText write FRawText;
  end;

  { TCPCppExprNode }
  // cpp(expr) -- injects raw C/C++ expression inline
  TCPCppExprNode = class(TCPExprNode)
  protected
    FArgExpr: TCPExprNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TCPExprNode read FArgExpr write FArgExpr;
  end;

  { TCPCreateNode }
  TCPCreateNode = class(TCPASTNode)
  protected
    FArgExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TCPASTNode read FArgExpr write FArgExpr;
  end;

  { TCPDestroyNode }
  TCPDestroyNode = class(TCPASTNode)
  protected
    FArgExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TCPASTNode read FArgExpr write FArgExpr;
  end;

  { TCPGetMemNode }
  TCPGetMemNode = class(TCPASTNode)
  protected
    FArgExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TCPASTNode read FArgExpr write FArgExpr;
  end;

  { TCPFreeMemNode }
  TCPFreeMemNode = class(TCPASTNode)
  protected
    FArgExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property ArgExpr: TCPASTNode read FArgExpr write FArgExpr;
  end;

  { TCPResizeMemNode }
  TCPResizeMemNode = class(TCPASTNode)
  protected
    FPtrExpr: TCPASTNode;
    FSizeExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property PtrExpr: TCPASTNode read FPtrExpr write FPtrExpr;
    property SizeExpr: TCPASTNode read FSizeExpr write FSizeExpr;
  end;

  { TCPSetLengthNode }
  TCPSetLengthNode = class(TCPASTNode)
  protected
    FTargetExpr: TCPASTNode;
    FLengthExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property TargetExpr: TCPASTNode read FTargetExpr write FTargetExpr;
    property LengthExpr: TCPASTNode read FLengthExpr write FLengthExpr;
  end;

  { TCPPrintNode }
  TCPPrintNode = class(TCPASTNode)
  protected
    FIsLn: Boolean;
    FArgs: TObjectList<TCPASTNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IsLn: Boolean read FIsLn write FIsLn;
    property Args: TObjectList<TCPASTNode> read FArgs;
  end;

  { TCPAssertStmtNode }
  TCPAssertStmtNode = class(TCPASTNode)
  protected
    FAssertKind: TCPAssertKind;
    FArgs: TObjectList<TCPASTNode>;  // 1-3 args depending on kind
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property AssertKind: TCPAssertKind read FAssertKind write FAssertKind;
    property Args: TObjectList<TCPASTNode> read FArgs;
  end;

  { TCPBinaryExprNode }
  TCPBinaryExprNode = class(TCPExprNode)
  protected
    FLeft: TCPASTNode;
    FOp: TCPBinaryOp;
    FRight: TCPASTNode;
  public
    destructor Destroy(); override;
    property Left: TCPASTNode read FLeft write FLeft;
    property Op: TCPBinaryOp read FOp write FOp;
    property Right: TCPASTNode read FRight write FRight;
  end;

  { TCPUnaryExprNode }
  TCPUnaryExprNode = class(TCPExprNode)
  protected
    FOp: TCPUnaryOp;
    FOperand: TCPASTNode;
  public
    destructor Destroy(); override;
    property Op: TCPUnaryOp read FOp write FOp;
    property Operand: TCPASTNode read FOperand write FOperand;
  end;

  { TCPIntLiteralNode }
  TCPIntLiteralNode = class(TCPExprNode)
  protected
    FIntValue: Int64;
  public
    property IntValue: Int64 read FIntValue write FIntValue;
  end;

  { TCPFloatLiteralNode }
  TCPFloatLiteralNode = class(TCPExprNode)
  protected
    FFloatValue: Double;
    FHasSuffix: Boolean;         // true if f/F suffix present (forces float32)
  public
    property FloatValue: Double read FFloatValue write FFloatValue;
    property HasSuffix: Boolean read FHasSuffix write FHasSuffix;
  end;

  { TCPStringLiteralNode }
  TCPStringLiteralNode = class(TCPExprNode)
  protected
    FStringValue: string;
  public
    property StringValue: string read FStringValue write FStringValue;
  end;

  { TCPWStringLiteralNode }
  TCPWStringLiteralNode = class(TCPExprNode)
  protected
    FStringValue: string;
  public
    property StringValue: string read FStringValue write FStringValue;
  end;

  { TCPBoolLiteralNode }
  TCPBoolLiteralNode = class(TCPExprNode)
  protected
    FBoolValue: Boolean;
  public
    property BoolValue: Boolean read FBoolValue write FBoolValue;
  end;

  { TCPNilLiteralNode }
  TCPNilLiteralNode = class(TCPExprNode);

  { TCPIdentifierNode }
  TCPIdentifierNode = class(TCPExprNode)
  protected
    FIdentName: string;
    FResolvedDecl: TCPASTNode;   // populated by semantic pass
  public
    property IdentName: string read FIdentName write FIdentName;
    property ResolvedDecl: TCPASTNode read FResolvedDecl write FResolvedDecl;
  end;

  { TCPDotAccessKind }
  TCPDotAccessKind = (
    dakField,           // record/struct field access: obj.field
    dakModule,          // module-qualified access: Module.Symbol
    dakChoices          // choices (enum) member: MyEnum.Value
  );

  { TCPDotAccessNode }
  TCPDotAccessNode = class(TCPExprNode)
  protected
    FBaseExpr: TCPASTNode;
    FMemberName: string;
    FResolvedDecl: TCPASTNode;   // populated by semantic pass
    FAccessKind: TCPDotAccessKind; // set by semantic pass
  public
    destructor Destroy(); override;
    property BaseExpr: TCPASTNode read FBaseExpr write FBaseExpr;
    property MemberName: string read FMemberName write FMemberName;
    property ResolvedDecl: TCPASTNode read FResolvedDecl write FResolvedDecl;
    property AccessKind: TCPDotAccessKind read FAccessKind write FAccessKind;
  end;

  { TCPIndexAccessNode }
  TCPIndexAccessNode = class(TCPExprNode)
  protected
    FBaseExpr: TCPASTNode;
    FIndexExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property BaseExpr: TCPASTNode read FBaseExpr write FBaseExpr;
    property IndexExpr: TCPASTNode read FIndexExpr write FIndexExpr;
  end;

  { TCPDerefNode }
  TCPDerefNode = class(TCPExprNode)
  protected
    FBaseExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property BaseExpr: TCPASTNode read FBaseExpr write FBaseExpr;
  end;

  { TCPCallExprNode }
  TCPCallExprNode = class(TCPExprNode)
  protected
    FCallee: TCPASTNode;
    FArgs: TObjectList<TCPASTNode>;
    FResolvedRoutine: TCPASTNode;  // populated by semantic pass
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Callee: TCPASTNode read FCallee write FCallee;
    property Args: TObjectList<TCPASTNode> read FArgs;
    property ResolvedRoutine: TCPASTNode read FResolvedRoutine write FResolvedRoutine;
  end;

  { TCPSetLiteralExprNode }
  TCPSetLiteralExprNode = class(TCPExprNode)
  protected
    FElements: TObjectList<TCPSetElementNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property Elements: TObjectList<TCPSetElementNode> read FElements;
  end;

  { TCPSetElementNode }
  TCPSetElementNode = class(TCPASTNode)
  protected
    FLowExpr: TCPASTNode;
    FHighExpr: TCPASTNode;       // nil = single element, not a range
  public
    destructor Destroy(); override;
    property LowExpr: TCPASTNode read FLowExpr write FLowExpr;
    property HighExpr: TCPASTNode read FHighExpr write FHighExpr;
  end;

  { TCPRecordLiteralNode }
  TCPRecordLiteralNode = class(TCPExprNode)
  protected
    FTypeName: string;
    FModuleName: string;
    FFieldInits: TObjectList<TCPFieldInitNode>;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property TypeName: string read FTypeName write FTypeName;
    property ModuleName: string read FModuleName write FModuleName;
    property FieldInits: TObjectList<TCPFieldInitNode> read FFieldInits;
  end;

  { TCPFieldInitNode }
  TCPFieldInitNode = class(TCPASTNode)
  protected
    FFieldName: string;
    FValueExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property FieldName: string read FFieldName write FFieldName;
    property ValueExpr: TCPASTNode read FValueExpr write FValueExpr;
  end;

  { TCPTypeCastExprNode }
  TCPTypeCastExprNode = class(TCPExprNode)
  protected
    FTargetType: TCPASTNode;
    FExpr: TCPASTNode;
  public
    destructor Destroy(); override;
    property TargetType: TCPASTNode read FTargetType write FTargetType;
    property Expr: TCPASTNode read FExpr write FExpr;
  end;

  { TCPIntrinsicExprNode }
  TCPIntrinsicExprNode = class(TCPExprNode)
  protected
    FIntrinsicKind: TCPIntrinsicKind;
    FArgs: TObjectList<TCPASTNode>;  // 0-1 args depending on intrinsic
  public
    constructor Create(); override;
    destructor Destroy(); override;
    property IntrinsicKind: TCPIntrinsicKind read FIntrinsicKind write FIntrinsicKind;
    property Args: TObjectList<TCPASTNode> read FArgs;
  end;

  { TCPMasterAST }
  TCPMasterAST = class(TBaseObject)
  protected
    FModules: TObjectList<TCPModuleNode>;
    FModuleMap: TDictionary<string, TCPModuleNode>;
    FPendingQueue: TQueue<string>;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Add a parsed module to the master tree
    procedure AddModule(const AModule: TCPModuleNode);

    // Check if a module has already been parsed
    function HasModule(const AModuleName: string): Boolean;

    // Retrieve a module by name
    function GetModule(const AModuleName: string): TCPModuleNode;

    // Work queue management for import processing
    procedure EnqueuePending(const AModuleName: string);
    function DequeuePending(): string;
    function HasPending(): Boolean;

    // Module count
    function ModuleCount(): Integer;

    // Indexed access to modules (source order)
    function GetModuleAt(const AIndex: Integer): TCPModuleNode;

    property Modules: TObjectList<TCPModuleNode> read FModules;
  end;

implementation

{ TCPASTNode }
constructor TCPASTNode.Create();
begin
  inherited;

  FLocation.Clear();
end;

destructor TCPASTNode.Destroy();
begin
  inherited;
end;

{ TCPModuleNode }
constructor TCPModuleNode.Create();
begin
  inherited;

  FModuleKind := mkExe;
  FDirectives := TObjectList<TCPDirectiveNode>.Create(True);
  FImports := TObjectList<TCPImportNode>.Create(True);
  FDeclarations := TObjectList<TCPASTNode>.Create(True);
  FInitBody := TObjectList<TCPASTNode>.Create(True);
  FFinalBody := TObjectList<TCPASTNode>.Create(True);
  FMainBody := TObjectList<TCPASTNode>.Create(True);
  FTestBlocks := TObjectList<TCPTestBlockNode>.Create(True);
end;

destructor TCPModuleNode.Destroy();
begin
  FTestBlocks.Free();
  FMainBody.Free();
  FFinalBody.Free();
  FInitBody.Free();
  FDeclarations.Free();
  FImports.Free();
  FDirectives.Free();

  inherited;
end;

{ TCPTestBlockNode }
constructor TCPTestBlockNode.Create();
begin
  inherited;

  FLocals := TObjectList<TCPVarDeclNode>.Create(True);
  FBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPTestBlockNode.Destroy();
begin
  FBody.Free();
  FLocals.Free();

  inherited;
end;

{ TCPRoutineDeclNode }
constructor TCPRoutineDeclNode.Create();
begin
  inherited;

  FLinkage := lkDefault;
  FParams := TObjectList<TCPParamDeclNode>.Create(True);
  FLocalTypes := TObjectList<TCPTypeDeclNode>.Create(True);
  FLocalConsts := TObjectList<TCPConstDeclNode>.Create(True);
  FLocalVars := TObjectList<TCPVarDeclNode>.Create(True);
  FBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPRoutineDeclNode.Destroy();
begin
  if FReturnType <> nil then
    FReturnType.Free();
  FBody.Free();
  FLocalVars.Free();
  FLocalConsts.Free();
  FLocalTypes.Free();
  FParams.Free();

  inherited;
end;

{ TCPOverloadGroupNode }
constructor TCPOverloadGroupNode.Create();
begin
  inherited;

  FOverloads := TList<TCPRoutineDeclNode>.Create();
end;

destructor TCPOverloadGroupNode.Destroy();
begin
  FOverloads.Free();

  inherited;
end;

{ TCPForwardRoutineDeclNode }
constructor TCPForwardRoutineDeclNode.Create();
begin
  inherited;

  FParams := TObjectList<TCPParamDeclNode>.Create(True);
end;

destructor TCPForwardRoutineDeclNode.Destroy();
begin
  if FReturnType <> nil then
    FReturnType.Free();
  FParams.Free();

  inherited;
end;

{ TCPRecordTypeNode }
constructor TCPRecordTypeNode.Create();
begin
  inherited;

  FFields := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPRecordTypeNode.Destroy();
begin
  if FBaseType <> nil then
    FBaseType.Free();
  FFields.Free();

  inherited;
end;

{ TCPOverlayTypeNode }
constructor TCPOverlayTypeNode.Create();
begin
  inherited;

  FFields := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPOverlayTypeNode.Destroy();
begin
  FFields.Free();

  inherited;
end;

{ TCPAnonRecordNode }
constructor TCPAnonRecordNode.Create();
begin
  inherited;

  FFields := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPAnonRecordNode.Destroy();
begin
  FFields.Free();

  inherited;
end;

{ TCPAnonOverlayNode }
constructor TCPAnonOverlayNode.Create();
begin
  inherited;

  FFields := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPAnonOverlayNode.Destroy();
begin
  FFields.Free();

  inherited;
end;

{ TCPChoicesTypeNode }
constructor TCPChoicesTypeNode.Create();
begin
  inherited;

  FMembers := TObjectList<TCPChoicesValueNode>.Create(True);
end;

destructor TCPChoicesTypeNode.Destroy();
begin
  FMembers.Free();

  inherited;
end;

{ TCPRoutineTypeNode }
constructor TCPRoutineTypeNode.Create();
begin
  inherited;

  FLinkage := lkDefault;
  FParams := TObjectList<TCPParamDeclNode>.Create(True);
end;

destructor TCPRoutineTypeNode.Destroy();
begin
  if FReturnType <> nil then
    FReturnType.Free();
  FParams.Free();

  inherited;
end;

{ TCPIfNode }
constructor TCPIfNode.Create();
begin
  inherited;

  FThenBody := TObjectList<TCPASTNode>.Create(True);
  FElseBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPIfNode.Destroy();
begin
  FCondition.Free();
  FElseBody.Free();
  FThenBody.Free();

  inherited;
end;

{ TCPWhileNode }
constructor TCPWhileNode.Create();
begin
  inherited;

  FBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPWhileNode.Destroy();
begin
  FCondition.Free();
  FBody.Free();

  inherited;
end;

{ TCPForNode }
constructor TCPForNode.Create();
begin
  inherited;

  FBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPForNode.Destroy();
begin
  FStartExpr.Free();
  FEndExpr.Free();
  FBody.Free();

  inherited;
end;

{ TCPRepeatNode }
constructor TCPRepeatNode.Create();
begin
  inherited;

  FBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPRepeatNode.Destroy();
begin
  FCondition.Free();
  FBody.Free();

  inherited;
end;

{ TCPMatchNode }
constructor TCPMatchNode.Create();
begin
  inherited;

  FArms := TObjectList<TCPMatchArmNode>.Create(True);
  FElseBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPMatchNode.Destroy();
begin
  FExpr.Free();
  FElseBody.Free();
  FArms.Free();

  inherited;
end;

{ TCPMatchArmNode }
constructor TCPMatchArmNode.Create();
begin
  inherited;

  FLabels := TObjectList<TCPMatchLabelNode>.Create(True);
  FBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPMatchArmNode.Destroy();
begin
  FBody.Free();
  FLabels.Free();

  inherited;
end;

{ TCPGuardNode }
constructor TCPGuardNode.Create();
begin
  inherited;

  FGuardBody := TObjectList<TCPASTNode>.Create(True);
  FExceptBody := TObjectList<TCPASTNode>.Create(True);
  FFinallyBody := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPGuardNode.Destroy();
begin
  FFinallyBody.Free();
  FExceptBody.Free();
  FGuardBody.Free();

  inherited;
end;

{ TCPPrintNode }
constructor TCPPrintNode.Create();
begin
  inherited;

  FArgs := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPPrintNode.Destroy();
begin
  FArgs.Free();
  inherited;
end;

{ TCPAssertStmtNode }
constructor TCPAssertStmtNode.Create();
begin
  inherited;

  FArgs := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPAssertStmtNode.Destroy();
begin
  FArgs.Free();

  inherited;
end;

{ TCPCallExprNode }
constructor TCPCallExprNode.Create();
begin
  inherited;

  FArgs := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPCallExprNode.Destroy();
begin
  FCallee.Free();
  FArgs.Free();

  inherited;
end;

{ TCPSetLiteralExprNode }
constructor TCPSetLiteralExprNode.Create();
begin
  inherited;

  FElements := TObjectList<TCPSetElementNode>.Create(True);
end;

destructor TCPSetLiteralExprNode.Destroy();
begin
  FElements.Free();

  inherited;
end;

{ TCPRecordLiteralNode }
constructor TCPRecordLiteralNode.Create();
begin
  inherited;

  FFieldInits := TObjectList<TCPFieldInitNode>.Create(True);
end;

destructor TCPRecordLiteralNode.Destroy();
begin
  FFieldInits.Free();

  inherited;
end;

{ TCPIntrinsicExprNode }
constructor TCPIntrinsicExprNode.Create();
begin
  inherited;

  FArgs := TObjectList<TCPASTNode>.Create(True);
end;

destructor TCPIntrinsicExprNode.Destroy();
begin
  FArgs.Free();

  inherited;
end;

{ TCPConstDeclNode }
destructor TCPConstDeclNode.Destroy();
begin
  if FTypeExpr <> nil then
    FTypeExpr.Free();
  FValueExpr.Free();

  inherited;
end;

{ TCPTypeDeclNode }
destructor TCPTypeDeclNode.Destroy();
begin
  FTypeDef.Free();

  inherited;
end;

{ TCPVarDeclNode }
destructor TCPVarDeclNode.Destroy();
begin
  if FTypeExpr <> nil then
    FTypeExpr.Free();
  FInitExpr.Free();

  inherited;
end;

{ TCPParamDeclNode }
destructor TCPParamDeclNode.Destroy();
begin
  if FTypeExpr <> nil then
    FTypeExpr.Free();

  inherited;
end;

{ TCPFieldDeclNode }
destructor TCPFieldDeclNode.Destroy();
begin
  if FTypeExpr <> nil then
    FTypeExpr.Free();

  inherited;
end;

{ TCPArrayTypeNode }
destructor TCPArrayTypeNode.Destroy();
begin
  if FElementType <> nil then
    FElementType.Free();

  inherited;
end;

{ TCPPointerTypeNode }
destructor TCPPointerTypeNode.Destroy();
begin
  if FTargetType <> nil then
    FTargetType.Free();

  inherited;
end;

{ TCPSetTypeNode }
destructor TCPSetTypeNode.Destroy();
begin
  if FElementType <> nil then
    FElementType.Free();

  inherited;
end;

{ TCPChoicesValueNode }
destructor TCPChoicesValueNode.Destroy();
begin
  FValueExpr.Free();

  inherited;
end;

{ TCPAssignNode }
destructor TCPAssignNode.Destroy();
begin
  FTarget.Free();
  FValueExpr.Free();

  inherited;
end;

{ TCPCallStmtNode }
destructor TCPCallStmtNode.Destroy();
begin
  FCallExpr.Free();

  inherited;
end;

{ TCPMatchLabelNode }
destructor TCPMatchLabelNode.Destroy();
begin
  FLowExpr.Free();
  FHighExpr.Free();

  inherited;
end;

{ TCPReturnNode }
destructor TCPReturnNode.Destroy();
begin
  FValueExpr.Free();

  inherited;
end;

{ TCPThrowNode }
destructor TCPThrowNode.Destroy();
begin
  FMessageExpr.Free();

  inherited;
end;

{ TCPThrowCodeNode }
destructor TCPThrowCodeNode.Destroy();
begin
  FCodeExpr.Free();
  FMessageExpr.Free();

  inherited;
end;

{ TCPCppExprNode }
destructor TCPCppExprNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TCPCreateNode }
destructor TCPCreateNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TCPDestroyNode }
destructor TCPDestroyNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TCPGetMemNode }
destructor TCPGetMemNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TCPFreeMemNode }
destructor TCPFreeMemNode.Destroy();
begin
  FArgExpr.Free();

  inherited;
end;

{ TCPResizeMemNode }
destructor TCPResizeMemNode.Destroy();
begin
  FPtrExpr.Free();
  FSizeExpr.Free();

  inherited;
end;

{ TCPSetLengthNode }
destructor TCPSetLengthNode.Destroy();
begin
  FTargetExpr.Free();
  FLengthExpr.Free();

  inherited;
end;

{ TCPBinaryExprNode }
destructor TCPBinaryExprNode.Destroy();
begin
  FLeft.Free();
  FRight.Free();

  inherited;
end;

{ TCPUnaryExprNode }
destructor TCPUnaryExprNode.Destroy();
begin
  FOperand.Free();

  inherited;
end;

{ TCPDotAccessNode }
destructor TCPDotAccessNode.Destroy();
begin
  FBaseExpr.Free();

  inherited;
end;

{ TCPIndexAccessNode }
destructor TCPIndexAccessNode.Destroy();
begin
  FBaseExpr.Free();
  FIndexExpr.Free();

  inherited;
end;

{ TCPDerefNode }
destructor TCPDerefNode.Destroy();
begin
  FBaseExpr.Free();

  inherited;
end;

{ TCPSetElementNode }
destructor TCPSetElementNode.Destroy();
begin
  FLowExpr.Free();
  FHighExpr.Free();

  inherited;
end;

{ TCPFieldInitNode }
destructor TCPFieldInitNode.Destroy();
begin
  FValueExpr.Free();

  inherited;
end;

{ TCPTypeCastExprNode }
destructor TCPTypeCastExprNode.Destroy();
begin
  if FTargetType <> nil then
    FTargetType.Free();
  FExpr.Free();

  inherited;
end;
{ TCPMasterAST }
constructor TCPMasterAST.Create();
begin
  inherited;

  FModules := TObjectList<TCPModuleNode>.Create(True);
  FModuleMap := TDictionary<string, TCPModuleNode>.Create();
  FPendingQueue := TQueue<string>.Create();
end;

destructor TCPMasterAST.Destroy();
begin
  FPendingQueue.Free();
  FModuleMap.Free();
  FModules.Free();

  inherited;
end;

procedure TCPMasterAST.AddModule(const AModule: TCPModuleNode);
begin
  FModules.Add(AModule);
  FModuleMap.AddOrSetValue(AModule.ModuleName, AModule);
end;

function TCPMasterAST.HasModule(const AModuleName: string): Boolean;
begin
  Result := FModuleMap.ContainsKey(AModuleName);
end;

function TCPMasterAST.GetModule(const AModuleName: string): TCPModuleNode;
begin
  if not FModuleMap.TryGetValue(AModuleName, Result) then
    Result := nil;
end;

procedure TCPMasterAST.EnqueuePending(const AModuleName: string);
begin
  FPendingQueue.Enqueue(AModuleName);
end;

function TCPMasterAST.DequeuePending(): string;
begin
  Result := FPendingQueue.Dequeue();
end;

function TCPMasterAST.HasPending(): Boolean;
begin
  Result := FPendingQueue.Count > 0;
end;

function TCPMasterAST.ModuleCount(): Integer;
begin
  Result := FModules.Count;
end;

function TCPMasterAST.GetModuleAt(const AIndex: Integer): TCPModuleNode;
begin
  Result := FModules[AIndex];
end;

end.
