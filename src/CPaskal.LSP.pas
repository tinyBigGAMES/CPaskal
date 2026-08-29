{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.LSP - Language Server Protocol Implementation

  Implements the full LSP server over JSON-RPC 2.0 (stdin/stdout).
  Three layers:
    TCPLSPDocument  - Holds source, runs compiler pipeline, queries enriched AST
    TCPLSPService   - Pure logic, no JSON. Answers every LSP query
    TCPLSPServer    - JSON-RPC framing and dispatch loop

  All LSP queries read directly from the semantically enriched AST.
  No parallel symbol table is maintained.

  Dependencies: StdApp.Base, CPaskal.Common, CPaskal.Lexer, CPaskal.Parser,
                CPaskal.AST, CPaskal.Semantics
===============================================================================}

unit CPaskal.LSP;

interface

uses
  WinApi.Windows,
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  System.IOUtils,
  System.Math,
  System.StrUtils,
  System.Rtti,
  StdApp.Base,
  CPaskal.Common,
  CPaskal.Lexer,
  CPaskal.Parser,
  CPaskal.AST,
  CPaskal.Semantics;

type

  //===========================================================================
  // Forward declarations
  //===========================================================================

  TCPLSPDocument = class;
  TCPLSPService  = class;
  TCPLSPServer   = class;

  //===========================================================================
  // LSP Protocol Record Types
  //===========================================================================

  { TCPLSPPosition }
  TCPLSPPosition = record
    Line: Integer;
    Character: Integer;
    procedure Clear();
    function ToJSON(): TJSONObject;
    class function FromJSON(const AObj: TJSONObject): TCPLSPPosition; static;
  end;

  { TCPLSPRange }
  TCPLSPRange = record
    StartPos: TCPLSPPosition;
    EndPos: TCPLSPPosition;
    procedure Clear();
    function ToJSON(): TJSONObject;
    class function FromJSON(const AObj: TJSONObject): TCPLSPRange; static;
    class function FromSourceRange(const ARange: TSourceRange): TCPLSPRange; static;
  end;

  { TCPLSPLocation }
  TCPLSPLocation = record
    Uri: string;
    Range: TCPLSPRange;
    function IsEmpty(): Boolean;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPDiagnosticRelated }
  TCPLSPDiagnosticRelated = record
    Location: TCPLSPLocation;
    Message: string;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPDiagnostic }
  TCPLSPDiagnostic = record
    Range: TCPLSPRange;
    Severity: Integer;
    Code: string;
    Source: string;
    Message: string;
    Related: TArray<TCPLSPDiagnosticRelated>;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPCompletionItem }
  TCPLSPCompletionItem = record
    LabelText: string;
    Kind: Integer;
    Detail: string;
    Documentation: string;
    InsertText: string;
    InsertTextFormat: Integer;
    SortText: string;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPParameterInfo }
  TCPLSPParameterInfo = record
    LabelText: string;
    Documentation: string;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPSignatureInfo }
  TCPLSPSignatureInfo = record
    LabelText: string;
    Documentation: string;
    Parameters: TArray<TCPLSPParameterInfo>;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPSignatureHelp }
  TCPLSPSignatureHelp = record
    Signatures: TArray<TCPLSPSignatureInfo>;
    ActiveSignature: Integer;
    ActiveParameter: Integer;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPHover }
  TCPLSPHover = record
    Contents: string;
    Range: TCPLSPRange;
    HasRange: Boolean;
    function IsEmpty(): Boolean;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPDocumentSymbol }
  TCPLSPDocumentSymbol = record
    SymbolName: string;
    Detail: string;
    Kind: Integer;
    Range: TCPLSPRange;
    SelectionRange: TCPLSPRange;
    Children: TArray<TCPLSPDocumentSymbol>;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPFoldingRange }
  TCPLSPFoldingRange = record
    StartLine: Integer;
    EndLine: Integer;
    Kind: string;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPInlayHint }
  TCPLSPInlayHint = record
    Position: TCPLSPPosition;
    LabelText: string;
    Kind: Integer;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPTextEdit }
  TCPLSPTextEdit = record
    Range: TCPLSPRange;
    NewText: string;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPWorkspaceEdit }
  TCPLSPWorkspaceEdit = record
    Uri: string;
    Edits: TArray<TCPLSPTextEdit>;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPSymbolInformation }
  TCPLSPSymbolInformation = record
    SymbolName: string;
    Kind: Integer;
    Uri: string;
    Range: TCPLSPRange;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPCallHierarchyItem }
  TCPLSPCallHierarchyItem = record
    ItemName: string;
    Kind: Integer;
    Uri: string;
    Range: TCPLSPRange;
    SelectionRange: TCPLSPRange;
    function ToJSON(): TJSONObject;
  end;

  { TCPLSPCallHierarchyCall }
  TCPLSPCallHierarchyCall = record
    Item: TCPLSPCallHierarchyItem;
    FromRanges: TArray<TCPLSPRange>;
    function ToJSON(const ADirection: string): TJSONObject;
  end;

  { TCPLSPDocument }
  TCPLSPDocument = class(TBaseObject)
  private
    FUri: string;
    FContent: string;
    FVersion: Integer;
    FLines: TStringList;
    FMasterAST: TCPMasterAST;
    FParser: TCPParser;
    FSemantics: TCPSemantics;

    procedure UpdateLines();

  public
    constructor Create(); override;
    destructor Destroy(); override;

    function GetUri(): string;
    procedure SetUri(const AValue: string);
    function GetContent(): string;
    procedure SetContent(const AValue: string);
    function GetVersion(): Integer;
    procedure SetVersion(const AValue: Integer);

    procedure Parse();

    function GetMasterAST(): TCPMasterAST;
    function GetModule(): TCPModuleNode;
    function GetTokens(): TList<TCPToken>;

    function OffsetToPosition(const AOffset: Integer): TCPLSPPosition;
    function PositionToOffset(const APosition: TCPLSPPosition): Integer;
    function GetLineCount(): Integer;
    function GetLine(const AIndex: Integer): string;

    function FindNodeAtPosition(const APosition: TCPLSPPosition): TCPASTNode;
    function FindCallAtPosition(const APosition: TCPLSPPosition): TCPCallExprNode;
  end;

  { TCPLSPService }
  TCPLSPService = class(TBaseObject)
  private
    FDocuments: TObjectDictionary<string, TCPLSPDocument>;
    FLexer: TCPLexer;  // keyword registry for completions

    function GetDocument(const AUri: string): TCPLSPDocument;

    function TypeRefToString(const ANode: TCPASTNode): string;
    function BuildSignatureString(const ARoutine: TCPRoutineDeclNode): string;
    function BuildSnippetInsertText(const AName: string;
      const ARoutine: TCPRoutineDeclNode): string;
    function DeclToCompletionKind(const ANode: TCPASTNode): Integer;
    function DeclToSymbolKind(const ANode: TCPASTNode): Integer;

    function GetKeywordCompletions(): TArray<TCPLSPCompletionItem>;
    function GetBuiltinTypeCompletions(): TArray<TCPLSPCompletionItem>;

    procedure WalkASTForReferences(const ANode: TCPASTNode;
      const ATarget: TCPASTNode; const AUri: string;
      var ALocations: TArray<TCPLSPLocation>);
    procedure WalkChildren(const ANode: TCPASTNode;
      const ATarget: TCPASTNode; const AUri: string;
      var ALocations: TArray<TCPLSPLocation>);
    procedure WalkListForReferences(const AList: TObjectList<TCPASTNode>;
      const ATarget: TCPASTNode; const AUri: string;
      var ALocations: TArray<TCPLSPLocation>);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure OpenDocument(const AUri: string; const AContent: string);
    procedure UpdateDocument(const AUri: string; const AContent: string;
      const AVersion: Integer);
    procedure CloseDocument(const AUri: string);
    function HasDocument(const AUri: string): Boolean;

    function GetDiagnostics(const AUri: string): TArray<TCPLSPDiagnostic>;
    function GetCompletions(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TArray<TCPLSPCompletionItem>;
    function GetHover(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TCPLSPHover;
    function GetDefinition(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TCPLSPLocation;
    function GetTypeDefinition(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TCPLSPLocation;
    function GetReferences(const AUri: string; const ALine: Integer;
      const ACharacter: Integer;
      const AIncludeDeclaration: Boolean): TArray<TCPLSPLocation>;
    function GetDocumentSymbols(
      const AUri: string): TArray<TCPLSPDocumentSymbol>;
    function GetSignatureHelp(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TCPLSPSignatureHelp;
    function GetFoldingRanges(
      const AUri: string): TArray<TCPLSPFoldingRange>;
    function GetSemanticTokens(const AUri: string): TArray<Integer>;
    function GetInlayHints(const AUri: string; const AStartLine: Integer;
      const AStartChar: Integer; const AEndLine: Integer;
      const AEndChar: Integer): TArray<TCPLSPInlayHint>;
    function GetRenameEdits(const AUri: string; const ALine: Integer;
      const ACharacter: Integer;
      const ANewName: string): TCPLSPWorkspaceEdit;
    function GetWorkspaceSymbols(const AQuery: string;
      const AUri: string): TArray<TCPLSPSymbolInformation>;
    function PrepareCallHierarchy(const AUri: string; const ALine: Integer;
      const ACharacter: Integer): TArray<TCPLSPCallHierarchyItem>;
    function GetIncomingCalls(const AUri: string;
      const AName: string): TArray<TCPLSPCallHierarchyCall>;
    function GetOutgoingCalls(const AUri: string;
      const AName: string): TArray<TCPLSPCallHierarchyCall>;
    function GetDocumentFormatting(const AUri: string; const ATabSize: Integer;
      const AInsertSpaces: Boolean): TArray<TCPLSPTextEdit>;

    class function FilePathToUri(const APath: string): string; static;
    class function UriToFilePath(const AUri: string): string; static;
    class function ErrorSeverityToLSPSeverity(
      const ASeverity: TErrorSeverity): Integer; static;
  end;

  { TCPLSPServer }
  TCPLSPServer = class(TBaseObject)
  private
    FService: TCPLSPService;
    FInitialized: Boolean;
    FShutdownRequested: Boolean;
    FRunning: Boolean;
    FExitCode: Word;
    FLogEnabled: Boolean;
    FInputStream: TStream;
    FOutputStream: TStream;
    FOwnsStreams: Boolean;

    procedure Log(const AMsg: string);

    function ReadMessage(): TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    procedure SendResponse(const AId: TJSONValue; const AResult: TJSONValue);
    procedure SendError(const AId: TJSONValue; const ACode: Integer;
      const AMessage: string);
    procedure SendNotification(const AMethod: string;
      const AParams: TJSONValue);

    procedure DispatchMessage(const AMessage: TJSONObject);
    procedure PublishDiagnostics(const AUri: string);

    procedure HandleInitialize(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleShutdown(const AId: TJSONValue);
    procedure HandleTextDocumentCompletion(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentHover(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentDefinition(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentTypeDefinition(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentReferences(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentDocumentSymbol(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentSignatureHelp(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentFoldingRange(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentSemanticTokensFull(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentFormatting(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentCodeAction(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentInlayHint(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentRename(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleWorkspaceSymbol(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleTextDocumentPrepareCallHierarchy(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleCallHierarchyIncomingCalls(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleCallHierarchyOutgoingCalls(const AId: TJSONValue;
      const AParams: TJSONObject);
    procedure HandleInitialized(const AParams: TJSONObject);
    procedure HandleExit();
    procedure HandleTextDocumentDidOpen(const AParams: TJSONObject);
    procedure HandleTextDocumentDidChange(const AParams: TJSONObject);
    procedure HandleTextDocumentDidClose(const AParams: TJSONObject);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    function Run(): Word;
    procedure SetStreams(const AInput: TStream; const AOutput: TStream);
    function GetService(): TCPLSPService;
    property LogEnabled: Boolean read FLogEnabled write FLogEnabled;
  end;

implementation

{ TCPLSPPosition }
procedure TCPLSPPosition.Clear();
begin
  Line := 0;
  Character := 0;
end;

function TCPLSPPosition.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('line', TJSONNumber.Create(Line));
  Result.AddPair('character', TJSONNumber.Create(Character));
end;

class function TCPLSPPosition.FromJSON(
  const AObj: TJSONObject): TCPLSPPosition;
begin
  Result.Line := AObj.GetValue<Integer>('line', 0);
  Result.Character := AObj.GetValue<Integer>('character', 0);
end;

{ TCPLSPRange }
procedure TCPLSPRange.Clear();
begin
  StartPos.Clear();
  EndPos.Clear();
end;

function TCPLSPRange.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('start', StartPos.ToJSON());
  Result.AddPair('end', EndPos.ToJSON());
end;

class function TCPLSPRange.FromJSON(
  const AObj: TJSONObject): TCPLSPRange;
var
  LStart: TJSONObject;
  LEnd: TJSONObject;
begin
  Result.Clear();
  LStart := AObj.GetValue<TJSONObject>('start', nil);
  if LStart <> nil then
    Result.StartPos := TCPLSPPosition.FromJSON(LStart);
  LEnd := AObj.GetValue<TJSONObject>('end', nil);
  if LEnd <> nil then
    Result.EndPos := TCPLSPPosition.FromJSON(LEnd);
end;

class function TCPLSPRange.FromSourceRange(
  const ARange: TSourceRange): TCPLSPRange;
begin
  // LSP is 0-based; CPaskal source ranges are 1-based
  Result.StartPos.Line := Max(0, Integer(ARange.StartLine) - 1);
  Result.StartPos.Character := Max(0, Integer(ARange.StartColumn) - 1);
  Result.EndPos.Line := Max(0, Integer(ARange.EndLine) - 1);
  Result.EndPos.Character := Max(0, Integer(ARange.EndColumn) - 1);
end;

{ TCPLSPLocation }
function TCPLSPLocation.IsEmpty(): Boolean;
begin
  Result := Uri = '';
end;

function TCPLSPLocation.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('uri', Uri);
  Result.AddPair('range', Range.ToJSON());
end;

{ TCPLSPDiagnosticRelated }
function TCPLSPDiagnosticRelated.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('location', Location.ToJSON());
  Result.AddPair('message', Message);
end;

{ TCPLSPDiagnostic }
function TCPLSPDiagnostic.ToJSON(): TJSONObject;
var
  LRelatedArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair('range', Range.ToJSON());
  Result.AddPair('severity', TJSONNumber.Create(Severity));
  if Code <> '' then
    Result.AddPair('code', Code);
  if Source <> '' then
    Result.AddPair('source', Source);
  Result.AddPair('message', Message);
  if Length(Related) > 0 then
  begin
    LRelatedArray := TJSONArray.Create();
    for LI := 0 to High(Related) do
      LRelatedArray.AddElement(Related[LI].ToJSON());
    Result.AddPair('relatedInformation', LRelatedArray);
  end;
end;

{ TCPLSPCompletionItem }
function TCPLSPCompletionItem.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('label', LabelText);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
  if Detail <> '' then
    Result.AddPair('detail', Detail);
  if Documentation <> '' then
    Result.AddPair('documentation', Documentation);
  if InsertText <> '' then
    Result.AddPair('insertText', InsertText);
  if InsertTextFormat <> 0 then
    Result.AddPair('insertTextFormat', TJSONNumber.Create(InsertTextFormat));
  if SortText <> '' then
    Result.AddPair('sortText', SortText);
end;

{ TCPLSPParameterInfo }
function TCPLSPParameterInfo.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('label', LabelText);
  if Documentation <> '' then
    Result.AddPair('documentation', Documentation);
end;

{ TCPLSPSignatureInfo }
function TCPLSPSignatureInfo.ToJSON(): TJSONObject;
var
  LParamsArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair('label', LabelText);
  if Documentation <> '' then
    Result.AddPair('documentation', Documentation);
  if Length(Parameters) > 0 then
  begin
    LParamsArray := TJSONArray.Create();
    for LI := 0 to High(Parameters) do
      LParamsArray.AddElement(Parameters[LI].ToJSON());
    Result.AddPair('parameters', LParamsArray);
  end;
end;

{ TCPLSPSignatureHelp }
function TCPLSPSignatureHelp.ToJSON(): TJSONObject;
var
  LSigsArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  LSigsArray := TJSONArray.Create();
  for LI := 0 to High(Signatures) do
    LSigsArray.AddElement(Signatures[LI].ToJSON());
  Result.AddPair('signatures', LSigsArray);
  Result.AddPair('activeSignature', TJSONNumber.Create(ActiveSignature));
  Result.AddPair('activeParameter', TJSONNumber.Create(ActiveParameter));
end;

{ TCPLSPHover }
function TCPLSPHover.IsEmpty(): Boolean;
begin
  Result := Contents = '';
end;

function TCPLSPHover.ToJSON(): TJSONObject;
var
  LContents: TJSONObject;
begin
  Result := TJSONObject.Create();
  LContents := TJSONObject.Create();
  LContents.AddPair('kind', 'markdown');
  LContents.AddPair('value', Contents);
  Result.AddPair('contents', LContents);
  if HasRange then
    Result.AddPair('range', Range.ToJSON());
end;

{ TCPLSPDocumentSymbol }
function TCPLSPDocumentSymbol.ToJSON(): TJSONObject;
var
  LChildArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair('name', SymbolName);
  if Detail <> '' then
    Result.AddPair('detail', Detail);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
  Result.AddPair('range', Range.ToJSON());
  Result.AddPair('selectionRange', SelectionRange.ToJSON());
  if Length(Children) > 0 then
  begin
    LChildArray := TJSONArray.Create();
    for LI := 0 to High(Children) do
      LChildArray.AddElement(Children[LI].ToJSON());
    Result.AddPair('children', LChildArray);
  end;
end;

{ TCPLSPFoldingRange }
function TCPLSPFoldingRange.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('startLine', TJSONNumber.Create(StartLine));
  Result.AddPair('endLine', TJSONNumber.Create(EndLine));
  if Kind <> '' then
    Result.AddPair('kind', Kind);
end;

{ TCPLSPInlayHint }
function TCPLSPInlayHint.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('position', Position.ToJSON());
  Result.AddPair('label', LabelText);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
end;

{ TCPLSPTextEdit }
function TCPLSPTextEdit.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('range', Range.ToJSON());
  Result.AddPair('newText', NewText);
end;

{ TCPLSPWorkspaceEdit }
function TCPLSPWorkspaceEdit.ToJSON(): TJSONObject;
var
  LEditsArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair('uri', Uri);
  LEditsArray := TJSONArray.Create();
  for LI := 0 to High(Edits) do
    LEditsArray.AddElement(Edits[LI].ToJSON());
  Result.AddPair('edits', LEditsArray);
end;

{ TCPLSPSymbolInformation }
function TCPLSPSymbolInformation.ToJSON(): TJSONObject;
var
  LLocation: TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('name', SymbolName);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
  LLocation := TJSONObject.Create();
  LLocation.AddPair('uri', Uri);
  LLocation.AddPair('range', Range.ToJSON());
  Result.AddPair('location', LLocation);
end;

{ TCPLSPCallHierarchyItem }
function TCPLSPCallHierarchyItem.ToJSON(): TJSONObject;
begin
  Result := TJSONObject.Create();
  Result.AddPair('name', ItemName);
  Result.AddPair('kind', TJSONNumber.Create(Kind));
  Result.AddPair('uri', Uri);
  Result.AddPair('range', Range.ToJSON());
  Result.AddPair('selectionRange', SelectionRange.ToJSON());
end;

{ TCPLSPCallHierarchyCall }
function TCPLSPCallHierarchyCall.ToJSON(
  const ADirection: string): TJSONObject;
var
  LRangesArray: TJSONArray;
  LI: Integer;
begin
  Result := TJSONObject.Create();
  Result.AddPair(ADirection, Item.ToJSON());
  LRangesArray := TJSONArray.Create();
  for LI := 0 to High(FromRanges) do
    LRangesArray.AddElement(FromRanges[LI].ToJSON());
  Result.AddPair('fromRanges', LRangesArray);
end;

{ TCPLSPDocument }
constructor TCPLSPDocument.Create();
begin
  inherited Create();

  FUri := '';
  FContent := '';
  FVersion := 0;
  FLines := TStringList.Create();
  FMasterAST := nil;
  FParser := nil;
  FSemantics := nil;
end;

destructor TCPLSPDocument.Destroy();
begin
  FreeAndNil(FSemantics);
  FreeAndNil(FMasterAST);
  FreeAndNil(FParser);
  FreeAndNil(FLines);

  inherited Destroy();
end;

procedure TCPLSPDocument.UpdateLines();
begin
  FLines.Clear();
  FLines.Text := FContent;
end;

function TCPLSPDocument.GetUri(): string;
begin
  Result := FUri;
end;

procedure TCPLSPDocument.SetUri(const AValue: string);
begin
  FUri := AValue;
end;

function TCPLSPDocument.GetContent(): string;
begin
  Result := FContent;
end;

procedure TCPLSPDocument.SetContent(const AValue: string);
begin
  FContent := AValue;
end;

function TCPLSPDocument.GetVersion(): Integer;
begin
  Result := FVersion;
end;

procedure TCPLSPDocument.SetVersion(const AValue: Integer);
begin
  FVersion := AValue;
end;

procedure TCPLSPDocument.Parse();
var
  LModule: TCPModuleNode;
begin
  // Free previous results
  FreeAndNil(FSemantics);
  FreeAndNil(FMasterAST);
  FreeAndNil(FParser);

  FErrors.Clear();
  FErrors.SetMaxErrors(100);

  FMasterAST := TCPMasterAST.Create();

  // Parse phase
  FParser := TCPParser.Create();
  FParser.SetErrors(FErrors);

  LModule := FParser.ParseModuleFromString(FContent, FUri, FMasterAST);
  if LModule <> nil then
  begin
    FMasterAST.AddModule(LModule);

    // Semantic phase (only when parse succeeded without errors)
    if not FErrors.HasErrors() then
    begin
      FSemantics := TCPSemantics.Create();
      FSemantics.SetErrors(FErrors);
      FErrors.RaiseOnError := True;
      try
        FSemantics.Analyze(FMasterAST);
      except
        on EStdAppException do; // errors collected, continue
      end;
      FErrors.RaiseOnError := False;
    end;
  end;

  UpdateLines();
end;

function TCPLSPDocument.GetMasterAST(): TCPMasterAST;
begin
  Result := FMasterAST;
end;

function TCPLSPDocument.GetModule(): TCPModuleNode;
begin
  if (FMasterAST <> nil) and (FMasterAST.ModuleCount() > 0) then
    Result := FMasterAST.GetModuleAt(0)
  else
    Result := nil;
end;

function TCPLSPDocument.GetTokens(): TList<TCPToken>;
begin
  if (FParser <> nil) and (FParser.Lexer <> nil) then
    Result := FParser.Lexer.GetTokens()
  else
    Result := nil;
end;

function TCPLSPDocument.OffsetToPosition(
  const AOffset: Integer): TCPLSPPosition;
var
  LLine: Integer;
  LPos: Integer;
  LLineLen: Integer;
begin
  Result.Clear();
  LPos := 0;
  LLine := 0;

  while LLine < FLines.Count do
  begin
    LLineLen := Length(FLines[LLine]) + 1;
    if LPos + LLineLen > AOffset then
    begin
      Result.Line := LLine;
      Result.Character := AOffset - LPos;
      Exit;
    end;
    LPos := LPos + LLineLen;
    Inc(LLine);
  end;

  if FLines.Count > 0 then
  begin
    Result.Line := FLines.Count - 1;
    Result.Character := Length(FLines[FLines.Count - 1]);
  end;
end;

function TCPLSPDocument.PositionToOffset(
  const APosition: TCPLSPPosition): Integer;
var
  LLine: Integer;
  LI: Integer;
begin
  LLine := 0;
  LI := 1;

  while LI <= Length(FContent) do
  begin
    if LLine = APosition.Line then
    begin
      Result := LI - 1 + APosition.Character;
      Exit;
    end;
    if FContent[LI] = #13 then
    begin
      Inc(LLine);
      Inc(LI);
      if (LI <= Length(FContent)) and (FContent[LI] = #10) then
        Inc(LI);
    end
    else if FContent[LI] = #10 then
    begin
      Inc(LLine);
      Inc(LI);
    end
    else
      Inc(LI);
  end;

  if LLine = APosition.Line then
    Result := Length(FContent) + APosition.Character
  else
    Result := Length(FContent);
end;

function TCPLSPDocument.GetLineCount(): Integer;
begin
  Result := FLines.Count;
end;

function TCPLSPDocument.GetLine(const AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FLines.Count) then
    Result := FLines[AIndex]
  else
    Result := '';
end;

function TCPLSPDocument.FindNodeAtPosition(
  const APosition: TCPLSPPosition): TCPASTNode;

  function ContainsPos(const ARange: TSourceRange): Boolean;
  var
    LLine: UInt64;
    LChar: UInt64;
  begin
    LLine := UInt64(APosition.Line + 1);
    LChar := UInt64(APosition.Character + 1);
    if (LLine < ARange.StartLine) or (LLine > ARange.EndLine) then
      Exit(False);
    if ARange.StartLine = ARange.EndLine then
      Exit((LChar >= ARange.StartColumn) and (LChar <= ARange.EndColumn));
    if LLine = ARange.StartLine then
      Result := LChar >= ARange.StartColumn
    else if LLine = ARange.EndLine then
      Result := LChar <= ARange.EndColumn
    else
      Result := True;
  end;

  function SearchInList(const AList: TObjectList<TCPASTNode>): TCPASTNode; forward;

  function SearchNode(const ANode: TCPASTNode): TCPASTNode;
  var
    LFound: TCPASTNode;
    LI: Integer;
  begin
    Result := nil;
    if ANode = nil then Exit;
    if ANode.Location.IsEmpty() then Exit;
    if not ContainsPos(ANode.Location) then Exit;

    // Try children first -- deepest match wins
    if ANode is TCPModuleNode then
    begin
      LFound := SearchInList(TCPModuleNode(ANode).Declarations);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPModuleNode(ANode).InitBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPModuleNode(ANode).FinalBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPModuleNode(ANode).MainBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPRoutineDeclNode then
    begin
      for LI := 0 to TCPRoutineDeclNode(ANode).Params.Count - 1 do
      begin
        LFound := SearchNode(TCPRoutineDeclNode(ANode).Params[LI]);
        if LFound <> nil then Exit(LFound);
      end;
      LFound := SearchNode(TCPRoutineDeclNode(ANode).ReturnType);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPRoutineDeclNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPVarDeclNode then
    begin
      LFound := SearchNode(TCPVarDeclNode(ANode).TypeExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPVarDeclNode(ANode).InitExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPConstDeclNode then
    begin
      LFound := SearchNode(TCPConstDeclNode(ANode).TypeExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPConstDeclNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPTypeDeclNode then
    begin
      LFound := SearchNode(TCPTypeDeclNode(ANode).TypeDef);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPBinaryExprNode then
    begin
      LFound := SearchNode(TCPBinaryExprNode(ANode).Left);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPBinaryExprNode(ANode).Right);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPUnaryExprNode then
    begin
      LFound := SearchNode(TCPUnaryExprNode(ANode).Operand);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPCallExprNode then
    begin
      LFound := SearchNode(TCPCallExprNode(ANode).Callee);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPCallExprNode(ANode).Args);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPCallStmtNode then
    begin
      LFound := SearchNode(TCPCallStmtNode(ANode).CallExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPDotAccessNode then
    begin
      LFound := SearchNode(TCPDotAccessNode(ANode).BaseExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPIndexAccessNode then
    begin
      LFound := SearchNode(TCPIndexAccessNode(ANode).BaseExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPIndexAccessNode(ANode).IndexExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPDerefNode then
    begin
      LFound := SearchNode(TCPDerefNode(ANode).BaseExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPAssignNode then
    begin
      LFound := SearchNode(TCPAssignNode(ANode).Target);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPAssignNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPIfNode then
    begin
      LFound := SearchNode(TCPIfNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPIfNode(ANode).ThenBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPIfNode(ANode).ElseBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPWhileNode then
    begin
      LFound := SearchNode(TCPWhileNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPWhileNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPForNode then
    begin
      LFound := SearchNode(TCPForNode(ANode).StartExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPForNode(ANode).EndExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPForNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPRepeatNode then
    begin
      LFound := SearchInList(TCPRepeatNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPRepeatNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPReturnNode then
    begin
      LFound := SearchNode(TCPReturnNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPGuardNode then
    begin
      LFound := SearchInList(TCPGuardNode(ANode).GuardBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPGuardNode(ANode).ExceptBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPGuardNode(ANode).FinallyBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPMatchNode then
    begin
      LFound := SearchNode(TCPMatchNode(ANode).Expr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPTypeCastExprNode then
    begin
      LFound := SearchNode(TCPTypeCastExprNode(ANode).Expr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPRecordTypeNode then
    begin
      LFound := SearchInList(TCPRecordTypeNode(ANode).Fields);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPPrintNode then
    begin
      LFound := SearchInList(TCPPrintNode(ANode).Args);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPTestBlockNode then
    begin
      LFound := SearchInList(TCPTestBlockNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end;

    // No child matched -- this node is the deepest match
    Result := ANode;
  end;

  function SearchInList(const AList: TObjectList<TCPASTNode>): TCPASTNode;
  var
    LI: Integer;
    LFound: TCPASTNode;
  begin
    Result := nil;
    if AList = nil then Exit;
    for LI := 0 to AList.Count - 1 do
    begin
      LFound := SearchNode(AList[LI]);
      if LFound <> nil then
        Exit(LFound);
    end;
  end;

var
  LModule: TCPModuleNode;
begin
  Result := nil;
  LModule := GetModule();
  if LModule <> nil then
    Result := SearchNode(LModule);
end;

function TCPLSPDocument.FindCallAtPosition(
  const APosition: TCPLSPPosition): TCPCallExprNode;

  function ContainsPos(const ARange: TSourceRange): Boolean;
  var
    LLine: UInt64;
    LChar: UInt64;
  begin
    LLine := UInt64(APosition.Line + 1);
    LChar := UInt64(APosition.Character + 1);
    if (LLine < ARange.StartLine) or (LLine > ARange.EndLine) then
      Exit(False);
    if ARange.StartLine = ARange.EndLine then
      Exit((LChar >= ARange.StartColumn) and (LChar <= ARange.EndColumn));
    if LLine = ARange.StartLine then
      Result := LChar >= ARange.StartColumn
    else if LLine = ARange.EndLine then
      Result := LChar <= ARange.EndColumn
    else
      Result := True;
  end;

  function SearchInList(const AList: TObjectList<TCPASTNode>): TCPCallExprNode; forward;

  function SearchNode(const ANode: TCPASTNode): TCPCallExprNode;
  var
    LFound: TCPCallExprNode;
  begin
    Result := nil;
    if ANode = nil then Exit;
    if ANode.Location.IsEmpty() then Exit;
    if not ContainsPos(ANode.Location) then Exit;

    // If this IS a call expression, return it (don't descend into args)
    if ANode is TCPCallExprNode then
      Exit(TCPCallExprNode(ANode));

    // Try children -- looking for a call
    if ANode is TCPModuleNode then
    begin
      LFound := SearchInList(TCPModuleNode(ANode).Declarations);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPModuleNode(ANode).InitBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPModuleNode(ANode).FinalBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPModuleNode(ANode).MainBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPRoutineDeclNode then
    begin
      LFound := SearchInList(TCPRoutineDeclNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPCallStmtNode then
    begin
      LFound := SearchNode(TCPCallStmtNode(ANode).CallExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPAssignNode then
    begin
      LFound := SearchNode(TCPAssignNode(ANode).Target);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPAssignNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPBinaryExprNode then
    begin
      LFound := SearchNode(TCPBinaryExprNode(ANode).Left);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPBinaryExprNode(ANode).Right);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPUnaryExprNode then
    begin
      LFound := SearchNode(TCPUnaryExprNode(ANode).Operand);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPIfNode then
    begin
      LFound := SearchNode(TCPIfNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPIfNode(ANode).ThenBody);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPIfNode(ANode).ElseBody);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPWhileNode then
    begin
      LFound := SearchNode(TCPWhileNode(ANode).Condition);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPWhileNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPForNode then
    begin
      LFound := SearchNode(TCPForNode(ANode).StartExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchNode(TCPForNode(ANode).EndExpr);
      if LFound <> nil then Exit(LFound);
      LFound := SearchInList(TCPForNode(ANode).Body);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPReturnNode then
    begin
      LFound := SearchNode(TCPReturnNode(ANode).ValueExpr);
      if LFound <> nil then Exit(LFound);
    end
    else if ANode is TCPVarDeclNode then
    begin
      LFound := SearchNode(TCPVarDeclNode(ANode).InitExpr);
      if LFound <> nil then Exit(LFound);
    end;
  end;

  function SearchInList(const AList: TObjectList<TCPASTNode>): TCPCallExprNode;
  var
    LI: Integer;
    LFound: TCPCallExprNode;
  begin
    Result := nil;
    if AList = nil then Exit;
    for LI := 0 to AList.Count - 1 do
    begin
      LFound := SearchNode(AList[LI]);
      if LFound <> nil then
        Exit(LFound);
    end;
  end;

var
  LModule: TCPModuleNode;
begin
  Result := nil;
  LModule := GetModule();
  if LModule <> nil then
    Result := SearchNode(LModule);
end;

{ TCPLSPService }
constructor TCPLSPService.Create();
begin
  inherited Create();

  FDocuments := TObjectDictionary<string, TCPLSPDocument>.Create([doOwnsValues]);
  FLexer := TCPLexer.Create();
end;

destructor TCPLSPService.Destroy();
begin
  FreeAndNil(FLexer);
  FreeAndNil(FDocuments);

  inherited Destroy();
end;

function TCPLSPService.GetDocument(
  const AUri: string): TCPLSPDocument;
begin
  if not FDocuments.TryGetValue(AUri, Result) then
    Result := nil;
end;

procedure TCPLSPService.OpenDocument(const AUri: string;
  const AContent: string);
var
  LDoc: TCPLSPDocument;
begin
  LDoc := TCPLSPDocument.Create();
  LDoc.SetUri(AUri);
  LDoc.SetContent(AContent);
  LDoc.SetVersion(1);
  LDoc.Parse();
  FDocuments.AddOrSetValue(AUri, LDoc);
end;

procedure TCPLSPService.UpdateDocument(const AUri: string;
  const AContent: string; const AVersion: Integer);
var
  LDoc: TCPLSPDocument;
begin
  LDoc := GetDocument(AUri);
  if LDoc = nil then
  begin
    OpenDocument(AUri, AContent);
    Exit;
  end;
  LDoc.SetContent(AContent);
  LDoc.SetVersion(AVersion);
  LDoc.Parse();
end;

procedure TCPLSPService.CloseDocument(const AUri: string);
begin
  FDocuments.Remove(AUri);
end;

function TCPLSPService.HasDocument(const AUri: string): Boolean;
begin
  Result := FDocuments.ContainsKey(AUri);
end;

function TCPLSPService.TypeRefToString(const ANode: TCPASTNode): string;
begin
  Result := '';
  if ANode = nil then Exit;

  if ANode is TCPTypeDeclNode then
    Result := TCPTypeDeclNode(ANode).DeclName
  else if ANode is TCPTypeRefNode then
  begin
    if TCPTypeRefNode(ANode).TokenKind <> tkIdentifier then
      Result := TCPTypeRefNode(ANode).CppTypeText  // primitive
    else if Length(TCPTypeRefNode(ANode).QualParts) > 0 then
      Result := String.Join('.', TCPTypeRefNode(ANode).QualParts)
    else
      Result := '?';
  end
  else if ANode is TCPArrayTypeNode then
    Result := 'array of ' + TypeRefToString(TCPArrayTypeNode(ANode).ElementType)
  else if ANode is TCPPointerTypeNode then
    Result := 'pointer to ' + TypeRefToString(TCPPointerTypeNode(ANode).TargetType)
  else if ANode is TCPSetTypeNode then
    Result := 'set of ' + TypeRefToString(TCPSetTypeNode(ANode).ElementType)
  else if ANode is TCPRecordTypeNode then
    Result := 'record'
  else if ANode is TCPChoicesTypeNode then
    Result := 'choices'
  else if ANode is TCPRoutineTypeNode then
    Result := 'routine type';
end;

function TCPLSPService.BuildSignatureString(
  const ARoutine: TCPRoutineDeclNode): string;
var
  LI: Integer;
  LParam: TCPParamDeclNode;
  LParts: TStringBuilder;
begin
  Result := '';
  if ARoutine = nil then Exit;

  LParts := TStringBuilder.Create();
  try
    for LI := 0 to ARoutine.Params.Count - 1 do
    begin
      LParam := ARoutine.Params[LI];
      if LI > 0 then LParts.Append('; ');
      case LParam.ParamMode of
        pmVar: LParts.Append('var ');
        pmConst: LParts.Append('const ');
      end;
      LParts.Append(LParam.ParamName);
      if LParam.TypeExpr <> nil then
        LParts.Append(': ' + TypeRefToString(LParam.TypeExpr));
    end;

    if ARoutine.ReturnType <> nil then
      Result := '(' + LParts.ToString() + '): ' + TypeRefToString(ARoutine.ReturnType)
    else
      Result := '(' + LParts.ToString() + ')';
  finally
    LParts.Free();
  end;
end;

function TCPLSPService.BuildSnippetInsertText(const AName: string;
  const ARoutine: TCPRoutineDeclNode): string;
var
  LI: Integer;
  LParam: TCPParamDeclNode;
  LParts: TStringBuilder;
begin
  Result := AName;
  if (ARoutine = nil) or (ARoutine.Params.Count = 0) then Exit;

  LParts := TStringBuilder.Create();
  try
    for LI := 0 to ARoutine.Params.Count - 1 do
    begin
      LParam := ARoutine.Params[LI];
      if LI > 0 then LParts.Append(', ');
      LParts.AppendFormat('${%d:%s}', [LI + 1, LParam.ParamName]);
    end;
    Result := AName + '(' + LParts.ToString() + ')';
  finally
    LParts.Free();
  end;
end;

function TCPLSPService.DeclToCompletionKind(const ANode: TCPASTNode): Integer;
begin
  if ANode is TCPRoutineDeclNode then Result := 3       // Function
  else if ANode is TCPOverloadGroupNode then Result := 3
  else if ANode is TCPTypeDeclNode then Result := 7     // Class
  else if ANode is TCPVarDeclNode then Result := 6      // Variable
  else if ANode is TCPConstDeclNode then Result := 21   // Constant
  else if ANode is TCPParamDeclNode then Result := 6    // Variable
  else if ANode is TCPFieldDeclNode then Result := 5    // Field
  else if ANode is TCPChoicesValueNode then Result := 20 // EnumMember
  else Result := 1;
end;

function TCPLSPService.DeclToSymbolKind(const ANode: TCPASTNode): Integer;
begin
  if ANode is TCPRoutineDeclNode then Result := 12       // Function
  else if ANode is TCPOverloadGroupNode then Result := 12
  else if ANode is TCPTypeDeclNode then
  begin
    if TCPTypeDeclNode(ANode).TypeDef is TCPRecordTypeNode then
      Result := 23   // Struct
    else if TCPTypeDeclNode(ANode).TypeDef is TCPChoicesTypeNode then
      Result := 10   // Enum
    else
      Result := 5;   // Class
  end
  else if ANode is TCPVarDeclNode then Result := 13      // Variable
  else if ANode is TCPConstDeclNode then Result := 14    // Constant
  else if ANode is TCPFieldDeclNode then Result := 8     // Field
  else Result := 1;
end;

class function TCPLSPService.ErrorSeverityToLSPSeverity(
  const ASeverity: TErrorSeverity): Integer;
begin
  case ASeverity of
    esHint:    Result := 4;
    esWarning: Result := 2;
    esError:   Result := 1;
    esFatal:   Result := 1;
  else
    Result := 1;
  end;
end;

class function TCPLSPService.FilePathToUri(const APath: string): string;
var
  LNormalized: string;
begin
  LNormalized := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Result := 'file:///' + LNormalized;
end;

class function TCPLSPService.UriToFilePath(const AUri: string): string;
begin
  Result := AUri;
  if Result.StartsWith('file:///') then
    Result := Copy(Result, 9, MaxInt);
  Result := StringReplace(Result, '/', PathDelim, [rfReplaceAll]);
end;

function TCPLSPService.GetKeywordCompletions(): TArray<TCPLSPCompletionItem>;
var
  LWords: TArray<string>;
  LI: Integer;
  LItem: TCPLSPCompletionItem;
begin
  LWords := FLexer.GetRegisteredWords(tcKeyword);
  SetLength(Result, Length(LWords));
  for LI := 0 to High(LWords) do
  begin
    LItem.LabelText := LWords[LI];
    LItem.Kind := 14;  // Keyword
    LItem.Detail := 'keyword';
    LItem.Documentation := '';
    LItem.InsertText := LWords[LI];
    LItem.InsertTextFormat := 1;
    LItem.SortText := '9' + LWords[LI];
    Result[LI] := LItem;
  end;
end;

function TCPLSPService.GetBuiltinTypeCompletions(): TArray<TCPLSPCompletionItem>;
var
  LWords: TArray<string>;
  LI: Integer;
  LItem: TCPLSPCompletionItem;
begin
  LWords := FLexer.GetRegisteredWords(tcPrimitive);
  SetLength(Result, Length(LWords));
  for LI := 0 to High(LWords) do
  begin
    LItem.LabelText := LWords[LI];
    LItem.Kind := 7;   // Class (type)
    LItem.Detail := 'built-in type';
    LItem.Documentation := '';
    LItem.InsertText := LWords[LI];
    LItem.InsertTextFormat := 1;
    LItem.SortText := '8' + LWords[LI];
    Result[LI] := LItem;
  end;
end;

function TCPLSPService.GetDiagnostics(
  const AUri: string): TArray<TCPLSPDiagnostic>;
var
  LDoc: TCPLSPDocument;
  LItems: TList<TError>;
  LI: Integer;
  LJ: Integer;
  LError: TError;
  LDiag: TCPLSPDiagnostic;
  LRelated: TCPLSPDiagnosticRelated;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  if LDoc.GetErrors() = nil then Exit;

  LItems := LDoc.GetErrors().GetItems();
  SetLength(Result, LItems.Count);
  for LI := 0 to LItems.Count - 1 do
  begin
    LError := LItems[LI];
    LDiag.Range := TCPLSPRange.FromSourceRange(LError.Range);
    LDiag.Severity := ErrorSeverityToLSPSeverity(LError.Severity);
    LDiag.Code := LError.Code;
    LDiag.Source := 'cpaskal';
    LDiag.Message := LError.Message;
    SetLength(LDiag.Related, Length(LError.Related));
    for LJ := 0 to High(LError.Related) do
    begin
      LRelated.Location.Uri := AUri;
      LRelated.Location.Range := TCPLSPRange.FromSourceRange(
        LError.Related[LJ].Range);
      LRelated.Message := LError.Related[LJ].Msg;
      LDiag.Related[LJ] := LRelated;
    end;
    Result[LI] := LDiag;
  end;
end;

function TCPLSPService.GetHover(const AUri: string; const ALine: Integer;
  const ACharacter: Integer): TCPLSPHover;
var
  LDoc: TCPLSPDocument;
  LPosition: TCPLSPPosition;
  LNode: TCPASTNode;
  LDecl: TCPASTNode;
  LContent: string;
begin
  Result.Contents := '';
  Result.HasRange := False;

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  // Resolve the declaration this node points to
  LDecl := nil;
  if LNode is TCPIdentifierNode then
    LDecl := TCPIdentifierNode(LNode).ResolvedDecl
  else if LNode is TCPDotAccessNode then
    LDecl := TCPDotAccessNode(LNode).ResolvedDecl
  else if (LNode is TCPDeclNode) or (LNode is TCPFieldDeclNode) or
          (LNode is TCPParamDeclNode) or (LNode is TCPChoicesValueNode) then
    LDecl := LNode;

  if LDecl <> nil then
  begin
    if LDecl is TCPRoutineDeclNode then
    begin
      LContent := '```cpaskal' + #10;
      LContent := LContent + 'routine ' + TCPRoutineDeclNode(LDecl).DeclName;
      LContent := LContent + BuildSignatureString(TCPRoutineDeclNode(LDecl));
      LContent := LContent + #10 + '```';
    end
    else if LDecl is TCPOverloadGroupNode then
    begin
      LContent := '```cpaskal' + #10;
      LContent := LContent + 'routine ' + TCPOverloadGroupNode(LDecl).DeclName;
      LContent := LContent + ' (overloaded, ' +
        IntToStr(TCPOverloadGroupNode(LDecl).Overloads.Count) + ' variants)';
      LContent := LContent + #10 + '```';
    end
    else if LDecl is TCPTypeDeclNode then
      LContent := '**type** `' + TCPTypeDeclNode(LDecl).DeclName + '`'
    else if LDecl is TCPVarDeclNode then
    begin
      LContent := '**var** `' + TCPVarDeclNode(LDecl).DeclName + '`';
      if TCPVarDeclNode(LDecl).TypeExpr <> nil then
        LContent := LContent + ': `' + TypeRefToString(TCPVarDeclNode(LDecl).TypeExpr) + '`';
    end
    else if LDecl is TCPConstDeclNode then
      LContent := '**const** `' + TCPConstDeclNode(LDecl).DeclName + '`'
    else if LDecl is TCPParamDeclNode then
    begin
      LContent := '**param** `' + TCPParamDeclNode(LDecl).ParamName + '`';
      if TCPParamDeclNode(LDecl).TypeExpr <> nil then
        LContent := LContent + ': `' + TypeRefToString(TCPParamDeclNode(LDecl).TypeExpr) + '`';
    end
    else if LDecl is TCPFieldDeclNode then
    begin
      LContent := '**field** `' + TCPFieldDeclNode(LDecl).FieldName + '`';
      if TCPFieldDeclNode(LDecl).TypeExpr <> nil then
        LContent := LContent + ': `' + TypeRefToString(TCPFieldDeclNode(LDecl).TypeExpr) + '`';
    end
    else if LDecl is TCPChoicesValueNode then
      LContent := '**choices value** `' + TCPChoicesValueNode(LDecl).MemberName + '`'
    else if LDecl is TCPDeclNode then
      LContent := '`' + TCPDeclNode(LDecl).DeclName + '`'
    else
      LContent := '';

    if LContent <> '' then
    begin
      Result.Contents := LContent;
      Result.Range := TCPLSPRange.FromSourceRange(LNode.Location);
      Result.HasRange := True;
      Exit;
    end;
  end;

  // Fallback: show resolved type for expressions
  if (LNode is TCPExprNode) and (TCPExprNode(LNode).ResolvedType <> nil) then
  begin
    Result.Contents := '`' + TypeRefToString(TCPExprNode(LNode).ResolvedType) + '`';
    Result.Range := TCPLSPRange.FromSourceRange(LNode.Location);
    Result.HasRange := True;
    Exit;
  end;

  // Literal fallbacks
  if LNode is TCPIntLiteralNode then
    Result.Contents := '**integer** `' + IntToStr(TCPIntLiteralNode(LNode).IntValue) + '`'
  else if LNode is TCPFloatLiteralNode then
    Result.Contents := '**float** `' + FloatToStr(TCPFloatLiteralNode(LNode).FloatValue) + '`'
  else if LNode is TCPStringLiteralNode then
    Result.Contents := '**string**'
  else if LNode is TCPBoolLiteralNode then
  begin
    if TCPBoolLiteralNode(LNode).BoolValue then
      Result.Contents := '**boolean** `true`'
    else
      Result.Contents := '**boolean** `false`';
  end
  else if LNode is TCPNilLiteralNode then
    Result.Contents := '**nil**';
end;

function TCPLSPService.GetDefinition(const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TCPLSPLocation;
var
  LDoc: TCPLSPDocument;
  LPosition: TCPLSPPosition;
  LNode: TCPASTNode;
  LDecl: TCPASTNode;
begin
  Result.Uri := '';
  Result.Range.Clear();

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  LDecl := nil;
  if LNode is TCPIdentifierNode then
    LDecl := TCPIdentifierNode(LNode).ResolvedDecl
  else if LNode is TCPDotAccessNode then
    LDecl := TCPDotAccessNode(LNode).ResolvedDecl
  else if LNode is TCPCallExprNode then
    LDecl := TCPCallExprNode(LNode).ResolvedRoutine;

  if (LDecl <> nil) and (not LDecl.Location.IsEmpty()) then
  begin
    Result.Uri := AUri;
    Result.Range := TCPLSPRange.FromSourceRange(LDecl.Location);
  end;
end;

function TCPLSPService.GetTypeDefinition(const AUri: string;
  const ALine: Integer; const ACharacter: Integer): TCPLSPLocation;
var
  LDoc: TCPLSPDocument;
  LPosition: TCPLSPPosition;
  LNode: TCPASTNode;
  LType: TCPASTNode;
begin
  Result.Uri := '';
  Result.Range.Clear();

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  LType := nil;
  if LNode is TCPExprNode then
    LType := TCPExprNode(LNode).ResolvedType;

  if (LType <> nil) and (not LType.Location.IsEmpty()) then
  begin
    Result.Uri := AUri;
    Result.Range := TCPLSPRange.FromSourceRange(LType.Location);
  end;
end;

function TCPLSPService.GetCompletions(const AUri: string;
  const ALine: Integer;
  const ACharacter: Integer): TArray<TCPLSPCompletionItem>;
var
  LDoc: TCPLSPDocument;
  LModule: TCPModuleNode;
  LI: Integer;
  LDecl: TCPASTNode;
  LItem: TCPLSPCompletionItem;
  LKeywords: TArray<TCPLSPCompletionItem>;
  LBuiltins: TArray<TCPLSPCompletionItem>;
begin
  SetLength(Result, 0);

  LDoc := GetDocument(AUri);
  LModule := nil;
  if LDoc <> nil then
    LModule := LDoc.GetModule();

  // Walk module declarations for completion items
  if LModule <> nil then
  begin
    for LI := 0 to LModule.Declarations.Count - 1 do
    begin
      LDecl := LModule.Declarations[LI];
      if not (LDecl is TCPDeclNode) then Continue;
      if TCPDeclNode(LDecl).DeclName = '' then Continue;

      LItem.LabelText := TCPDeclNode(LDecl).DeclName;
      LItem.Kind := DeclToCompletionKind(LDecl);
      LItem.SortText := '1' + TCPDeclNode(LDecl).DeclName;
      LItem.InsertTextFormat := 1;
      LItem.Documentation := '';
      LItem.Detail := '';

      if LDecl is TCPRoutineDeclNode then
      begin
        LItem.InsertText := BuildSnippetInsertText(
          TCPDeclNode(LDecl).DeclName, TCPRoutineDeclNode(LDecl));
        LItem.InsertTextFormat := 2;
        LItem.Detail := BuildSignatureString(TCPRoutineDeclNode(LDecl));
      end
      else if LDecl is TCPVarDeclNode then
      begin
        LItem.InsertText := TCPDeclNode(LDecl).DeclName;
        if TCPVarDeclNode(LDecl).TypeExpr <> nil then
          LItem.Detail := TypeRefToString(TCPVarDeclNode(LDecl).TypeExpr);
      end
      else
        LItem.InsertText := TCPDeclNode(LDecl).DeclName;

      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LItem;
    end;
  end;

  // Always include keywords and builtin types
  LKeywords := GetKeywordCompletions();
  for LI := 0 to High(LKeywords) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LKeywords[LI];
  end;

  LBuiltins := GetBuiltinTypeCompletions();
  for LI := 0 to High(LBuiltins) do
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LBuiltins[LI];
  end;
end;

procedure TCPLSPService.WalkASTForReferences(const ANode: TCPASTNode;
  const ATarget: TCPASTNode; const AUri: string;
  var ALocations: TArray<TCPLSPLocation>);
var
  LLocation: TCPLSPLocation;
begin
  if ANode = nil then Exit;

  // Check if this node references the target
  if (ANode is TCPIdentifierNode) and
     (TCPIdentifierNode(ANode).ResolvedDecl = ATarget) then
  begin
    LLocation.Uri := AUri;
    LLocation.Range := TCPLSPRange.FromSourceRange(ANode.Location);
    SetLength(ALocations, Length(ALocations) + 1);
    ALocations[High(ALocations)] := LLocation;
  end
  else if (ANode is TCPDotAccessNode) and
          (TCPDotAccessNode(ANode).ResolvedDecl = ATarget) then
  begin
    LLocation.Uri := AUri;
    LLocation.Range := TCPLSPRange.FromSourceRange(ANode.Location);
    SetLength(ALocations, Length(ALocations) + 1);
    ALocations[High(ALocations)] := LLocation;
  end;

  // Recurse into children
  WalkChildren(ANode, ATarget, AUri, ALocations);
end;

procedure TCPLSPService.WalkChildren(const ANode: TCPASTNode;
  const ATarget: TCPASTNode; const AUri: string;
  var ALocations: TArray<TCPLSPLocation>);
var
  LI: Integer;
begin
  if ANode is TCPModuleNode then
  begin
    WalkListForReferences(TCPModuleNode(ANode).Declarations, ATarget, AUri, ALocations);
    WalkListForReferences(TCPModuleNode(ANode).InitBody, ATarget, AUri, ALocations);
    WalkListForReferences(TCPModuleNode(ANode).FinalBody, ATarget, AUri, ALocations);
    WalkListForReferences(TCPModuleNode(ANode).MainBody, ATarget, AUri, ALocations);
  end
  else if ANode is TCPRoutineDeclNode then
  begin
    for LI := 0 to TCPRoutineDeclNode(ANode).Params.Count - 1 do
      WalkASTForReferences(TCPRoutineDeclNode(ANode).Params[LI], ATarget, AUri, ALocations);
    WalkASTForReferences(TCPRoutineDeclNode(ANode).ReturnType, ATarget, AUri, ALocations);
    WalkListForReferences(TCPRoutineDeclNode(ANode).Body, ATarget, AUri, ALocations);
  end
  else if ANode is TCPBinaryExprNode then
  begin
    WalkASTForReferences(TCPBinaryExprNode(ANode).Left, ATarget, AUri, ALocations);
    WalkASTForReferences(TCPBinaryExprNode(ANode).Right, ATarget, AUri, ALocations);
  end
  else if ANode is TCPUnaryExprNode then
    WalkASTForReferences(TCPUnaryExprNode(ANode).Operand, ATarget, AUri, ALocations)
  else if ANode is TCPCallExprNode then
  begin
    WalkASTForReferences(TCPCallExprNode(ANode).Callee, ATarget, AUri, ALocations);
    WalkListForReferences(TCPCallExprNode(ANode).Args, ATarget, AUri, ALocations);
  end
  else if ANode is TCPCallStmtNode then
    WalkASTForReferences(TCPCallStmtNode(ANode).CallExpr, ATarget, AUri, ALocations)
  else if ANode is TCPDotAccessNode then
    WalkASTForReferences(TCPDotAccessNode(ANode).BaseExpr, ATarget, AUri, ALocations)
  else if ANode is TCPIndexAccessNode then
  begin
    WalkASTForReferences(TCPIndexAccessNode(ANode).BaseExpr, ATarget, AUri, ALocations);
    WalkASTForReferences(TCPIndexAccessNode(ANode).IndexExpr, ATarget, AUri, ALocations);
  end
  else if ANode is TCPAssignNode then
  begin
    WalkASTForReferences(TCPAssignNode(ANode).Target, ATarget, AUri, ALocations);
    WalkASTForReferences(TCPAssignNode(ANode).ValueExpr, ATarget, AUri, ALocations);
  end
  else if ANode is TCPIfNode then
  begin
    WalkASTForReferences(TCPIfNode(ANode).Condition, ATarget, AUri, ALocations);
    WalkListForReferences(TCPIfNode(ANode).ThenBody, ATarget, AUri, ALocations);
    WalkListForReferences(TCPIfNode(ANode).ElseBody, ATarget, AUri, ALocations);
  end
  else if ANode is TCPWhileNode then
  begin
    WalkASTForReferences(TCPWhileNode(ANode).Condition, ATarget, AUri, ALocations);
    WalkListForReferences(TCPWhileNode(ANode).Body, ATarget, AUri, ALocations);
  end
  else if ANode is TCPForNode then
  begin
    WalkASTForReferences(TCPForNode(ANode).StartExpr, ATarget, AUri, ALocations);
    WalkASTForReferences(TCPForNode(ANode).EndExpr, ATarget, AUri, ALocations);
    WalkListForReferences(TCPForNode(ANode).Body, ATarget, AUri, ALocations);
  end
  else if ANode is TCPRepeatNode then
  begin
    WalkListForReferences(TCPRepeatNode(ANode).Body, ATarget, AUri, ALocations);
    WalkASTForReferences(TCPRepeatNode(ANode).Condition, ATarget, AUri, ALocations);
  end
  else if ANode is TCPReturnNode then
    WalkASTForReferences(TCPReturnNode(ANode).ValueExpr, ATarget, AUri, ALocations)
  else if ANode is TCPGuardNode then
  begin
    WalkListForReferences(TCPGuardNode(ANode).GuardBody, ATarget, AUri, ALocations);
    WalkListForReferences(TCPGuardNode(ANode).ExceptBody, ATarget, AUri, ALocations);
    WalkListForReferences(TCPGuardNode(ANode).FinallyBody, ATarget, AUri, ALocations);
  end
  else if ANode is TCPVarDeclNode then
  begin
    WalkASTForReferences(TCPVarDeclNode(ANode).TypeExpr, ATarget, AUri, ALocations);
    WalkASTForReferences(TCPVarDeclNode(ANode).InitExpr, ATarget, AUri, ALocations);
  end
  else if ANode is TCPConstDeclNode then
  begin
    WalkASTForReferences(TCPConstDeclNode(ANode).TypeExpr, ATarget, AUri, ALocations);
    WalkASTForReferences(TCPConstDeclNode(ANode).ValueExpr, ATarget, AUri, ALocations);
  end
  else if ANode is TCPTypeDeclNode then
    WalkASTForReferences(TCPTypeDeclNode(ANode).TypeDef, ATarget, AUri, ALocations)
  else if ANode is TCPPrintNode then
  begin
    WalkListForReferences(TCPPrintNode(ANode).Args, ATarget, AUri, ALocations);
  end
  else if ANode is TCPDerefNode then
    WalkASTForReferences(TCPDerefNode(ANode).BaseExpr, ATarget, AUri, ALocations)
  else if ANode is TCPTypeCastExprNode then
    WalkASTForReferences(TCPTypeCastExprNode(ANode).Expr, ATarget, AUri, ALocations)
  else if ANode is TCPTestBlockNode then
    WalkListForReferences(TCPTestBlockNode(ANode).Body, ATarget, AUri, ALocations)
  else if ANode is TCPRecordTypeNode then
    WalkListForReferences(TCPRecordTypeNode(ANode).Fields, ATarget, AUri, ALocations);
end;

procedure TCPLSPService.WalkListForReferences(
  const AList: TObjectList<TCPASTNode>;
  const ATarget: TCPASTNode; const AUri: string;
  var ALocations: TArray<TCPLSPLocation>);
var
  LI: Integer;
begin
  if AList = nil then Exit;
  for LI := 0 to AList.Count - 1 do
    WalkASTForReferences(AList[LI], ATarget, AUri, ALocations);
end;

function TCPLSPService.GetReferences(const AUri: string;
  const ALine: Integer; const ACharacter: Integer;
  const AIncludeDeclaration: Boolean): TArray<TCPLSPLocation>;
var
  LDoc: TCPLSPDocument;
  LPosition: TCPLSPPosition;
  LNode: TCPASTNode;
  LTarget: TCPASTNode;
  LLocation: TCPLSPLocation;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  // Find the declaration this node refers to
  LTarget := nil;
  if LNode is TCPIdentifierNode then
    LTarget := TCPIdentifierNode(LNode).ResolvedDecl
  else if LNode is TCPDotAccessNode then
    LTarget := TCPDotAccessNode(LNode).ResolvedDecl
  else if LNode is TCPDeclNode then
    LTarget := LNode;  // cursor is on the declaration itself
  if LTarget = nil then Exit;

  // Include the declaration itself
  if AIncludeDeclaration and (not LTarget.Location.IsEmpty()) then
  begin
    LLocation.Uri := AUri;
    LLocation.Range := TCPLSPRange.FromSourceRange(LTarget.Location);
    SetLength(Result, 1);
    Result[0] := LLocation;
  end;

  // Walk entire AST for references
  if LDoc.GetModule() <> nil then
    WalkASTForReferences(LDoc.GetModule(), LTarget, AUri, Result);
end;

function TCPLSPService.GetDocumentSymbols(
  const AUri: string): TArray<TCPLSPDocumentSymbol>;
var
  LDoc: TCPLSPDocument;
  LModule: TCPModuleNode;
  LI: Integer;
  LDecl: TCPASTNode;
  LSym: TCPLSPDocumentSymbol;

  function BuildDocSymbol(const ADecl: TCPASTNode): TCPLSPDocumentSymbol;
  var
    LJ: Integer;
    LChildSym: TCPLSPDocumentSymbol;
    LField: TCPASTNode;
    LTypeDef: TCPASTNode;
  begin
    if ADecl is TCPDeclNode then
      Result.SymbolName := TCPDeclNode(ADecl).DeclName
    else if ADecl is TCPFieldDeclNode then
      Result.SymbolName := TCPFieldDeclNode(ADecl).FieldName
    else
      Result.SymbolName := '?';

    Result.Detail := '';
    Result.Kind := DeclToSymbolKind(ADecl);
    Result.Range := TCPLSPRange.FromSourceRange(ADecl.Location);
    Result.SelectionRange := Result.Range;
    SetLength(Result.Children, 0);

    // Recurse into record fields
    if ADecl is TCPTypeDeclNode then
    begin
      LTypeDef := TCPTypeDeclNode(ADecl).TypeDef;
      if LTypeDef is TCPRecordTypeNode then
      begin
        for LJ := 0 to TCPRecordTypeNode(LTypeDef).Fields.Count - 1 do
        begin
          LField := TCPRecordTypeNode(LTypeDef).Fields[LJ];
          if LField is TCPFieldDeclNode then
          begin
            LChildSym := BuildDocSymbol(LField);
            SetLength(Result.Children, Length(Result.Children) + 1);
            Result.Children[High(Result.Children)] := LChildSym;
          end;
        end;
      end
      else if LTypeDef is TCPChoicesTypeNode then
      begin
        for LJ := 0 to TCPChoicesTypeNode(LTypeDef).Members.Count - 1 do
        begin
          LChildSym.SymbolName := TCPChoicesTypeNode(LTypeDef).Members[LJ].MemberName;
          LChildSym.Kind := 22;  // EnumMember
          LChildSym.Detail := '';
          LChildSym.Range := TCPLSPRange.FromSourceRange(
            TCPChoicesTypeNode(LTypeDef).Members[LJ].Location);
          LChildSym.SelectionRange := LChildSym.Range;
          SetLength(LChildSym.Children, 0);
          SetLength(Result.Children, Length(Result.Children) + 1);
          Result.Children[High(Result.Children)] := LChildSym;
        end;
      end;
    end
    // Recurse into routine params
    else if ADecl is TCPRoutineDeclNode then
    begin
      Result.Detail := BuildSignatureString(TCPRoutineDeclNode(ADecl));
    end;
  end;

begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;

  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if not (LDecl is TCPDeclNode) then Continue;
    if TCPDeclNode(LDecl).DeclName = '' then Continue;

    LSym := BuildDocSymbol(LDecl);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LSym;
  end;
end;

function TCPLSPService.GetSignatureHelp(const AUri: string;
  const ALine: Integer;
  const ACharacter: Integer): TCPLSPSignatureHelp;
var
  LDoc: TCPLSPDocument;
  LPosition: TCPLSPPosition;
  LCallNode: TCPCallExprNode;
  LRoutine: TCPRoutineDeclNode;
  LI: Integer;
  LSig: TCPLSPSignatureInfo;
  LParam: TCPLSPParameterInfo;
begin
  SetLength(Result.Signatures, 0);
  Result.ActiveSignature := 0;
  Result.ActiveParameter := 0;

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;

  // Find enclosing call expression (stops at call, doesn't descend into args)
  LCallNode := LDoc.FindCallAtPosition(LPosition);
  if LCallNode = nil then Exit;

  LRoutine := nil;
  if LCallNode.ResolvedRoutine is TCPRoutineDeclNode then
    LRoutine := TCPRoutineDeclNode(LCallNode.ResolvedRoutine);
  if LRoutine = nil then Exit;

  LSig.LabelText := LRoutine.DeclName + BuildSignatureString(LRoutine);
  LSig.Documentation := '';
  SetLength(LSig.Parameters, LRoutine.Params.Count);
  for LI := 0 to LRoutine.Params.Count - 1 do
  begin
    LParam.LabelText := LRoutine.Params[LI].ParamName;
    if LRoutine.Params[LI].TypeExpr <> nil then
      LParam.LabelText := LParam.LabelText + ': ' +
        TypeRefToString(LRoutine.Params[LI].TypeExpr);
    LParam.Documentation := '';
    LSig.Parameters[LI] := LParam;
  end;

  SetLength(Result.Signatures, 1);
  Result.Signatures[0] := LSig;
end;

function TCPLSPService.GetFoldingRanges(
  const AUri: string): TArray<TCPLSPFoldingRange>;

  procedure CollectBodyFolding(const ABody: TObjectList<TCPASTNode>;
    var ARanges: TArray<TCPLSPFoldingRange>); forward;

  procedure CollectFolding(const ANode: TCPASTNode;
    var ARanges: TArray<TCPLSPFoldingRange>);
  var
    LRange: TCPLSPFoldingRange;
    LStartLine: Integer;
    LEndLine: Integer;
    LI: Integer;
  begin
    if ANode = nil then Exit;
    if ANode.Location.IsEmpty() then Exit;

    LStartLine := Integer(ANode.Location.StartLine) - 1;
    LEndLine := Integer(ANode.Location.EndLine) - 1;

    // Only add if it spans multiple lines
    if LEndLine > LStartLine then
    begin
      if (ANode is TCPRoutineDeclNode) or (ANode is TCPIfNode) or
         (ANode is TCPWhileNode) or (ANode is TCPForNode) or
         (ANode is TCPRepeatNode) or (ANode is TCPMatchNode) or
         (ANode is TCPGuardNode) or (ANode is TCPTestBlockNode) or
         (ANode is TCPRecordTypeNode) or (ANode is TCPTypeDeclNode) then
      begin
        LRange.StartLine := LStartLine;
        LRange.EndLine := LEndLine;
        LRange.Kind := 'region';
        SetLength(ARanges, Length(ARanges) + 1);
        ARanges[High(ARanges)] := LRange;
      end;
    end;

    // Recurse
    if ANode is TCPModuleNode then
    begin
      for LI := 0 to TCPModuleNode(ANode).Declarations.Count - 1 do
        CollectFolding(TCPModuleNode(ANode).Declarations[LI], ARanges);
      // Add folding for module body sections
      CollectBodyFolding(TCPModuleNode(ANode).InitBody, ARanges);
      CollectBodyFolding(TCPModuleNode(ANode).MainBody, ARanges);
      CollectBodyFolding(TCPModuleNode(ANode).FinalBody, ARanges);
    end
    else if ANode is TCPRoutineDeclNode then
    begin
      for LI := 0 to TCPRoutineDeclNode(ANode).Body.Count - 1 do
        CollectFolding(TCPRoutineDeclNode(ANode).Body[LI], ARanges);
    end;
  end;

  procedure CollectBodyFolding(const ABody: TObjectList<TCPASTNode>;
    var ARanges: TArray<TCPLSPFoldingRange>);
  var
    LFirst: TCPASTNode;
    LLast: TCPASTNode;
    LStartLine: Integer;
    LEndLine: Integer;
    LRange: TCPLSPFoldingRange;
    LI: Integer;
  begin
    if (ABody = nil) or (ABody.Count = 0) then Exit;
    LFirst := ABody[0];
    LLast := ABody[ABody.Count - 1];
    if LFirst.Location.IsEmpty() or LLast.Location.IsEmpty() then Exit;
    // Use the line before the first statement (the begin keyword) as start
    LStartLine := Integer(LFirst.Location.StartLine) - 1 - 1;
    LEndLine := Integer(LLast.Location.EndLine) - 1;
    if LEndLine > LStartLine then
    begin
      LRange.StartLine := LStartLine;
      LRange.EndLine := LEndLine;
      LRange.Kind := 'region';
      SetLength(ARanges, Length(ARanges) + 1);
      ARanges[High(ARanges)] := LRange;
    end;
    // Recurse into body statements for nested blocks
    for LI := 0 to ABody.Count - 1 do
      CollectFolding(ABody[LI], ARanges);
  end;

var
  LDoc: TCPLSPDocument;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  if LDoc.GetModule() = nil then Exit;
  CollectFolding(LDoc.GetModule(), Result);
end;

function TCPLSPService.GetSemanticTokens(const AUri: string): TArray<Integer>;
var
  LDoc: TCPLSPDocument;
  LTokens: TList<TCPToken>;
  LI: Integer;
  LToken: TCPToken;
  LPrevLine: Integer;
  LPrevChar: Integer;
  LLine: Integer;
  LChar: Integer;
  LDeltaLine: Integer;
  LDeltaChar: Integer;
  LLen: Integer;
  LTokenType: Integer;
  LList: TList<Integer>;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LTokens := LDoc.GetTokens();
  if LTokens = nil then Exit;

  LList := TList<Integer>.Create();
  try
    LPrevLine := 0;
    LPrevChar := 0;

    for LI := 0 to LTokens.Count - 1 do
    begin
      LToken := LTokens[LI];
      if LToken.Kind = tkEOF then Continue;

      // Map category to semantic token type
      // Types: 0=namespace, 1=type, 2=class, 3=enum, 4=interface,
      //        5=struct, 6=typeParameter, 7=parameter, 8=variable,
      //        9=property, 10=enumMember, 11=event, 12=function,
      //        13=method, 14=macro, 15=keyword, 16=modifier,
      //        17=comment, 18=string, 19=number, 20=regexp, 21=operator
      case LToken.Category of
        tcKeyword:    LTokenType := 15;
        tcPrimitive:  LTokenType := 1;
        tcOperator:   LTokenType := 21;
        tcLiteral:
        begin
          if LToken.Kind in [tkIntLiteral, tkFloatLiteral] then
            LTokenType := 19
          else
            LTokenType := 18;
        end;
        tcDirective:  LTokenType := 14;
        tcIdentifier: LTokenType := 8;  // default to variable
      else
        Continue;  // skip delimiters, etc.
      end;

      LLine := Integer(LToken.Location.StartLine) - 1;
      LChar := Integer(LToken.Location.StartColumn) - 1;
      LLen := Length(LToken.RawText);

      LDeltaLine := LLine - LPrevLine;
      if LDeltaLine = 0 then
        LDeltaChar := LChar - LPrevChar
      else
        LDeltaChar := LChar;

      LList.Add(LDeltaLine);
      LList.Add(LDeltaChar);
      LList.Add(LLen);
      LList.Add(LTokenType);
      LList.Add(0);  // modifiers

      LPrevLine := LLine;
      LPrevChar := LChar;
    end;

    SetLength(Result, LList.Count);
    for LI := 0 to LList.Count - 1 do
      Result[LI] := LList[LI];
  finally
    LList.Free();
  end;
end;

function TCPLSPService.GetDocumentFormatting(const AUri: string;
  const ATabSize: Integer;
  const AInsertSpaces: Boolean): TArray<TCPLSPTextEdit>;
var
  LDoc: TCPLSPDocument;
  LTokens: TList<TCPToken>;
  LI: Integer;
  LToken: TCPToken;
  LEdit: TCPLSPTextEdit;
  LCanonical: string;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LTokens := LDoc.GetTokens();
  if LTokens = nil then Exit;

  // Keyword casing: normalize keywords to lowercase canonical form
  for LI := 0 to LTokens.Count - 1 do
  begin
    LToken := LTokens[LI];
    if LToken.Kind = tkEOF then Continue;
    if LToken.Category <> tcKeyword then Continue;
    LCanonical := LToken.TokenText;  // TokenText is canonical (lowercased)
    if LToken.RawText <> LCanonical then
    begin
      LEdit.Range := TCPLSPRange.FromSourceRange(LToken.Location);
      LEdit.NewText := LCanonical;
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LEdit;
    end;
  end;

  // Trailing whitespace removal
  for LI := 0 to LDoc.GetLineCount() - 1 do
  begin
    LCanonical := LDoc.GetLine(LI);
    if (LCanonical <> '') and (LCanonical[Length(LCanonical)] <= ' ') then
    begin
      LEdit.Range.StartPos.Line := LI;
      LEdit.Range.StartPos.Character := Length(TrimRight(LCanonical));
      LEdit.Range.EndPos.Line := LI;
      LEdit.Range.EndPos.Character := Length(LCanonical);
      LEdit.NewText := '';
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := LEdit;
    end;
  end;
end;

function TCPLSPService.GetInlayHints(const AUri: string;
  const AStartLine: Integer; const AStartChar: Integer;
  const AEndLine: Integer;
  const AEndChar: Integer): TArray<TCPLSPInlayHint>;
var
  LDoc: TCPLSPDocument;
  LModule: TCPModuleNode;

  procedure CollectInlayHints(const ANode: TCPASTNode;
    var AHints: TArray<TCPLSPInlayHint>);
  var
    LI: Integer;
    LHint: TCPLSPInlayHint;
    LLine: Integer;
    LRoutine: TCPRoutineDeclNode;
  begin
    if ANode = nil then Exit;

    // Parameter name hints on call expressions
    if ANode is TCPCallExprNode then
    begin
      LRoutine := nil;
      if TCPCallExprNode(ANode).ResolvedRoutine is TCPRoutineDeclNode then
        LRoutine := TCPRoutineDeclNode(TCPCallExprNode(ANode).ResolvedRoutine);
      if (LRoutine <> nil) and (TCPCallExprNode(ANode).Args.Count > 0) then
      begin
        for LI := 0 to Min(TCPCallExprNode(ANode).Args.Count,
          LRoutine.Params.Count) - 1 do
        begin
          LLine := Integer(TCPCallExprNode(ANode).Args[LI].Location.StartLine) - 1;
          if (LLine >= AStartLine) and (LLine <= AEndLine) then
          begin
            LHint.Position.Line := LLine;
            LHint.Position.Character :=
              Integer(TCPCallExprNode(ANode).Args[LI].Location.StartColumn) - 1;
            LHint.LabelText := LRoutine.Params[LI].ParamName + ':';
            LHint.Kind := 2;  // Parameter
            SetLength(AHints, Length(AHints) + 1);
            AHints[High(AHints)] := LHint;
          end;
        end;
      end;
    end

    // Type hints on variable declarations without explicit type
    else if ANode is TCPVarDeclNode then
    begin
      if (TCPVarDeclNode(ANode).TypeExpr = nil) and
         (TCPExprNode(ANode).ResolvedType <> nil) then
      begin
        LLine := Integer(ANode.Location.StartLine) - 1;
        if (LLine >= AStartLine) and (LLine <= AEndLine) then
        begin
          LHint.Position.Line := LLine;
          LHint.Position.Character := Integer(ANode.Location.EndColumn);
          LHint.LabelText := ': ' + TypeRefToString(TCPExprNode(ANode).ResolvedType);
          LHint.Kind := 1;  // Type
          SetLength(AHints, Length(AHints) + 1);
          AHints[High(AHints)] := LHint;
        end;
      end;
    end;

    // Recurse
    if ANode is TCPModuleNode then
    begin
      for LI := 0 to TCPModuleNode(ANode).Declarations.Count - 1 do
        CollectInlayHints(TCPModuleNode(ANode).Declarations[LI], AHints);
      for LI := 0 to TCPModuleNode(ANode).MainBody.Count - 1 do
        CollectInlayHints(TCPModuleNode(ANode).MainBody[LI], AHints);
      for LI := 0 to TCPModuleNode(ANode).InitBody.Count - 1 do
        CollectInlayHints(TCPModuleNode(ANode).InitBody[LI], AHints);
    end
    else if ANode is TCPRoutineDeclNode then
    begin
      for LI := 0 to TCPRoutineDeclNode(ANode).Body.Count - 1 do
        CollectInlayHints(TCPRoutineDeclNode(ANode).Body[LI], AHints);
    end
    else if ANode is TCPIfNode then
    begin
      CollectInlayHints(TCPIfNode(ANode).Condition, AHints);
      for LI := 0 to TCPIfNode(ANode).ThenBody.Count - 1 do
        CollectInlayHints(TCPIfNode(ANode).ThenBody[LI], AHints);
      for LI := 0 to TCPIfNode(ANode).ElseBody.Count - 1 do
        CollectInlayHints(TCPIfNode(ANode).ElseBody[LI], AHints);
    end
    else if ANode is TCPWhileNode then
    begin
      CollectInlayHints(TCPWhileNode(ANode).Condition, AHints);
      for LI := 0 to TCPWhileNode(ANode).Body.Count - 1 do
        CollectInlayHints(TCPWhileNode(ANode).Body[LI], AHints);
    end
    else if ANode is TCPForNode then
    begin
      for LI := 0 to TCPForNode(ANode).Body.Count - 1 do
        CollectInlayHints(TCPForNode(ANode).Body[LI], AHints);
    end
    else if ANode is TCPCallStmtNode then
      CollectInlayHints(TCPCallStmtNode(ANode).CallExpr, AHints)
    else if ANode is TCPAssignNode then
      CollectInlayHints(TCPAssignNode(ANode).ValueExpr, AHints);
  end;

begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;
  CollectInlayHints(LModule, Result);
end;

function TCPLSPService.GetRenameEdits(const AUri: string;
  const ALine: Integer; const ACharacter: Integer;
  const ANewName: string): TCPLSPWorkspaceEdit;
var
  LDoc: TCPLSPDocument;
  LPosition: TCPLSPPosition;
  LNode: TCPASTNode;
  LTarget: TCPASTNode;
  LLocations: TArray<TCPLSPLocation>;
  LI: Integer;
  LEdit: TCPLSPTextEdit;
begin
  Result.Uri := AUri;
  SetLength(Result.Edits, 0);

  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  // Find what we're renaming
  LTarget := nil;
  if LNode is TCPIdentifierNode then
    LTarget := TCPIdentifierNode(LNode).ResolvedDecl
  else if LNode is TCPDotAccessNode then
    LTarget := TCPDotAccessNode(LNode).ResolvedDecl
  else if LNode is TCPDeclNode then
    LTarget := LNode;
  if LTarget = nil then Exit;

  // Collect all references
  SetLength(LLocations, 0);

  // Include the declaration itself
  if not LTarget.Location.IsEmpty() then
  begin
    SetLength(LLocations, 1);
    LLocations[0].Uri := AUri;
    LLocations[0].Range := TCPLSPRange.FromSourceRange(LTarget.Location);
  end;

  // Walk AST for all uses
  if LDoc.GetModule() <> nil then
    WalkASTForReferences(LDoc.GetModule(), LTarget, AUri, LLocations);

  // Convert locations to edits
  SetLength(Result.Edits, Length(LLocations));
  for LI := 0 to High(LLocations) do
  begin
    LEdit.Range := LLocations[LI].Range;
    LEdit.NewText := ANewName;
    Result.Edits[LI] := LEdit;
  end;
end;

function TCPLSPService.GetWorkspaceSymbols(const AQuery: string;
  const AUri: string): TArray<TCPLSPSymbolInformation>;
var
  LDoc: TCPLSPDocument;
  LModule: TCPModuleNode;
  LI: Integer;
  LDecl: TCPASTNode;
  LInfo: TCPLSPSymbolInformation;
  LName: string;
  LQueryLower: string;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;

  LQueryLower := LowerCase(AQuery);

  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if not (LDecl is TCPDeclNode) then Continue;
    LName := TCPDeclNode(LDecl).DeclName;
    if LName = '' then Continue;

    // Filter by query (empty query = return all)
    if (LQueryLower <> '') and (not LowerCase(LName).Contains(LQueryLower)) then
      Continue;

    LInfo.SymbolName := LName;
    LInfo.Kind := DeclToSymbolKind(LDecl);
    LInfo.Uri := AUri;
    LInfo.Range := TCPLSPRange.FromSourceRange(LDecl.Location);

    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := LInfo;
  end;
end;

function TCPLSPService.PrepareCallHierarchy(const AUri: string;
  const ALine: Integer;
  const ACharacter: Integer): TArray<TCPLSPCallHierarchyItem>;
var
  LDoc: TCPLSPDocument;
  LPosition: TCPLSPPosition;
  LNode: TCPASTNode;
  LDecl: TCPASTNode;
  LItem: TCPLSPCallHierarchyItem;
begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;

  LPosition.Line := ALine;
  LPosition.Character := ACharacter;
  LNode := LDoc.FindNodeAtPosition(LPosition);
  if LNode = nil then Exit;

  // Resolve to a routine declaration
  LDecl := nil;
  if LNode is TCPIdentifierNode then
    LDecl := TCPIdentifierNode(LNode).ResolvedDecl
  else if LNode is TCPDotAccessNode then
    LDecl := TCPDotAccessNode(LNode).ResolvedDecl
  else if LNode is TCPRoutineDeclNode then
    LDecl := LNode;

  if not (LDecl is TCPRoutineDeclNode) then Exit;

  LItem.ItemName := TCPRoutineDeclNode(LDecl).DeclName;
  LItem.Kind := 12;  // Function
  LItem.Uri := AUri;
  LItem.Range := TCPLSPRange.FromSourceRange(LDecl.Location);
  LItem.SelectionRange := LItem.Range;

  SetLength(Result, 1);
  Result[0] := LItem;
end;

function TCPLSPService.GetIncomingCalls(const AUri: string;
  const AName: string): TArray<TCPLSPCallHierarchyCall>;
var
  LDoc: TCPLSPDocument;
  LModule: TCPModuleNode;
  LI: Integer;
  LDecl: TCPASTNode;
  LTarget: TCPRoutineDeclNode;

  procedure FindCallsInRoutine(const ARoutine: TCPRoutineDeclNode;
    const ATarget: TCPRoutineDeclNode;
    var ACalls: TArray<TCPLSPCallHierarchyCall>);
  var
    LLocations: TArray<TCPLSPLocation>;
    LCall: TCPLSPCallHierarchyCall;
  begin
    SetLength(LLocations, 0);
    WalkListForReferences(ARoutine.Body, ATarget, AUri, LLocations);
    if Length(LLocations) > 0 then
    begin
      LCall.Item.ItemName := ARoutine.DeclName;
      LCall.Item.Kind := 12;
      LCall.Item.Uri := AUri;
      LCall.Item.Range := TCPLSPRange.FromSourceRange(ARoutine.Location);
      LCall.Item.SelectionRange := LCall.Item.Range;
      LCall.FromRanges := TArray<TCPLSPRange>.Create(LLocations[0].Range);
      SetLength(ACalls, Length(ACalls) + 1);
      ACalls[High(ACalls)] := LCall;
    end;
  end;

begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;

  // Find the target routine by name
  LTarget := nil;
  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if (LDecl is TCPRoutineDeclNode) and
       (TCPRoutineDeclNode(LDecl).DeclName = AName) then
    begin
      LTarget := TCPRoutineDeclNode(LDecl);
      Break;
    end;
  end;
  if LTarget = nil then Exit;

  // Search all routines for calls to the target
  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if (LDecl is TCPRoutineDeclNode) and (LDecl <> LTarget) then
      FindCallsInRoutine(TCPRoutineDeclNode(LDecl), LTarget, Result);
  end;
end;

function TCPLSPService.GetOutgoingCalls(const AUri: string;
  const AName: string): TArray<TCPLSPCallHierarchyCall>;
var
  LDoc: TCPLSPDocument;
  LModule: TCPModuleNode;
  LI: Integer;
  LDecl: TCPASTNode;
  LSource: TCPRoutineDeclNode;

  procedure CollectOutgoing(const ANode: TCPASTNode;
    var ACalls: TArray<TCPLSPCallHierarchyCall>);
  var
    LJ: Integer;
    LCallee: TCPASTNode;
    LCall: TCPLSPCallHierarchyCall;
  begin
    if ANode = nil then Exit;

    if ANode is TCPCallExprNode then
    begin
      LCallee := TCPCallExprNode(ANode).ResolvedRoutine;
      if (LCallee is TCPRoutineDeclNode) then
      begin
        LCall.Item.ItemName := TCPRoutineDeclNode(LCallee).DeclName;
        LCall.Item.Kind := 12;
        LCall.Item.Uri := AUri;
        LCall.Item.Range := TCPLSPRange.FromSourceRange(LCallee.Location);
        LCall.Item.SelectionRange := LCall.Item.Range;
        LCall.FromRanges := TArray<TCPLSPRange>.Create(
          TCPLSPRange.FromSourceRange(ANode.Location));
        SetLength(ACalls, Length(ACalls) + 1);
        ACalls[High(ACalls)] := LCall;
      end;
    end
    else if ANode is TCPCallStmtNode then
      CollectOutgoing(TCPCallStmtNode(ANode).CallExpr, ACalls);

    // Recurse into children
    if ANode is TCPRoutineDeclNode then
    begin
      for LJ := 0 to TCPRoutineDeclNode(ANode).Body.Count - 1 do
        CollectOutgoing(TCPRoutineDeclNode(ANode).Body[LJ], ACalls);
    end
    else if ANode is TCPIfNode then
    begin
      CollectOutgoing(TCPIfNode(ANode).Condition, ACalls);
      for LJ := 0 to TCPIfNode(ANode).ThenBody.Count - 1 do
        CollectOutgoing(TCPIfNode(ANode).ThenBody[LJ], ACalls);
      for LJ := 0 to TCPIfNode(ANode).ElseBody.Count - 1 do
        CollectOutgoing(TCPIfNode(ANode).ElseBody[LJ], ACalls);
    end
    else if ANode is TCPWhileNode then
    begin
      CollectOutgoing(TCPWhileNode(ANode).Condition, ACalls);
      for LJ := 0 to TCPWhileNode(ANode).Body.Count - 1 do
        CollectOutgoing(TCPWhileNode(ANode).Body[LJ], ACalls);
    end
    else if ANode is TCPForNode then
    begin
      for LJ := 0 to TCPForNode(ANode).Body.Count - 1 do
        CollectOutgoing(TCPForNode(ANode).Body[LJ], ACalls);
    end
    else if ANode is TCPAssignNode then
    begin
      CollectOutgoing(TCPAssignNode(ANode).ValueExpr, ACalls);
    end
    else if ANode is TCPReturnNode then
      CollectOutgoing(TCPReturnNode(ANode).ValueExpr, ACalls)
    else if ANode is TCPBinaryExprNode then
    begin
      CollectOutgoing(TCPBinaryExprNode(ANode).Left, ACalls);
      CollectOutgoing(TCPBinaryExprNode(ANode).Right, ACalls);
    end
    else if ANode is TCPUnaryExprNode then
      CollectOutgoing(TCPUnaryExprNode(ANode).Operand, ACalls);
  end;

begin
  SetLength(Result, 0);
  LDoc := GetDocument(AUri);
  if LDoc = nil then Exit;
  LModule := LDoc.GetModule();
  if LModule = nil then Exit;

  // Find the source routine by name
  LSource := nil;
  for LI := 0 to LModule.Declarations.Count - 1 do
  begin
    LDecl := LModule.Declarations[LI];
    if (LDecl is TCPRoutineDeclNode) and
       (TCPRoutineDeclNode(LDecl).DeclName = AName) then
    begin
      LSource := TCPRoutineDeclNode(LDecl);
      Break;
    end;
  end;
  if LSource = nil then Exit;

  CollectOutgoing(LSource, Result);
end;

{ TCPLSPServer }
constructor TCPLSPServer.Create();
begin
  inherited Create();

  FService := TCPLSPService.Create();
  FInitialized := False;
  FShutdownRequested := False;
  FInputStream := nil;
  FOutputStream := nil;
  FOwnsStreams := False;
end;

destructor TCPLSPServer.Destroy();
begin
  FreeAndNil(FService);
  if FOwnsStreams then
  begin
    FreeAndNil(FInputStream);
    FreeAndNil(FOutputStream);
  end;

  inherited Destroy();
end;

procedure TCPLSPServer.SetStreams(const AInput: TStream;
  const AOutput: TStream);
begin
  FInputStream := AInput;
  FOutputStream := AOutput;
end;

function TCPLSPServer.GetService(): TCPLSPService;
begin
  Result := FService;
end;

{ TCPLSPServer.Log }
procedure TCPLSPServer.Log(const AMsg: string);
begin
  if FLogEnabled then
    cpLogStdErr('cpaslsp: ' + AMsg);
end;

function TCPLSPServer.ReadMessage(): TJSONObject;
var
  LHeader: string;
  LContentLength: Integer;
  LCh: AnsiChar;
  LBody: TBytes;
  LBodyStr: string;
begin
  Result := nil;
  LContentLength := -1;

  // Read headers (Content-Length: N\r\n\r\n)
  while True do
  begin
    LHeader := '';
    while True do
    begin
      if FInputStream.Read(LCh, 1) <> 1 then Exit;
      if LCh = #13 then
      begin
        if FInputStream.Read(LCh, 1) <> 1 then Exit;
        Break;
      end;
      LHeader := LHeader + Char(LCh);
    end;

    if LHeader = '' then Break;  // empty line = end of headers

    if LHeader.StartsWith('Content-Length:') then
      LContentLength := StrToIntDef(Trim(Copy(LHeader, 16, MaxInt)), -1);
  end;

  if LContentLength <= 0 then Exit;

  // Read body
  SetLength(LBody, LContentLength);
  if FInputStream.Read(LBody[0], LContentLength) <> LContentLength then Exit;

  LBodyStr := TEncoding.UTF8.GetString(LBody);
  try
    Result := TJSONObject.ParseJSONValue(LBodyStr) as TJSONObject;
  except
    Result := nil;
  end;
end;

procedure TCPLSPServer.WriteMessage(const AMessage: TJSONObject);
var
  LBody: string;
  LBodyBytes: TBytes;
  LHeader: string;
  LHeaderBytes: TBytes;
begin
  LBody := AMessage.ToJSON();
  LBodyBytes := TEncoding.UTF8.GetBytes(LBody);
  LHeader := 'Content-Length: ' + IntToStr(Length(LBodyBytes)) + #13#10 + #13#10;
  LHeaderBytes := TEncoding.ASCII.GetBytes(LHeader);
  FOutputStream.Write(LHeaderBytes[0], Length(LHeaderBytes));
  FOutputStream.Write(LBodyBytes[0], Length(LBodyBytes));
end;

procedure TCPLSPServer.SendResponse(const AId: TJSONValue;
  const AResult: TJSONValue);
var
  LMsg: TJSONObject;
begin
  LMsg := TJSONObject.Create();
  try
    LMsg.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      LMsg.AddPair('id', AId.Clone() as TJSONValue)
    else
      LMsg.AddPair('id', TJSONNull.Create());
    if AResult <> nil then
      LMsg.AddPair('result', AResult)
    else
      LMsg.AddPair('result', TJSONNull.Create());
    WriteMessage(LMsg);
  finally
    LMsg.Free();
  end;
end;

procedure TCPLSPServer.SendError(const AId: TJSONValue;
  const ACode: Integer; const AMessage: string);
var
  LMsg: TJSONObject;
  LError: TJSONObject;
begin
  LMsg := TJSONObject.Create();
  try
    LMsg.AddPair('jsonrpc', '2.0');
    if AId <> nil then
      LMsg.AddPair('id', AId.Clone() as TJSONValue)
    else
      LMsg.AddPair('id', TJSONNull.Create());
    LError := TJSONObject.Create();
    LError.AddPair('code', TJSONNumber.Create(ACode));
    LError.AddPair('message', AMessage);
    LMsg.AddPair('error', LError);
    WriteMessage(LMsg);
  finally
    LMsg.Free();
  end;
end;

procedure TCPLSPServer.SendNotification(const AMethod: string;
  const AParams: TJSONValue);
var
  LMsg: TJSONObject;
begin
  LMsg := TJSONObject.Create();
  try
    LMsg.AddPair('jsonrpc', '2.0');
    LMsg.AddPair('method', AMethod);
    if AParams <> nil then
      LMsg.AddPair('params', AParams)
    else
      LMsg.AddPair('params', TJSONObject.Create());
    WriteMessage(LMsg);
  finally
    LMsg.Free();
  end;
end;

procedure TCPLSPServer.PublishDiagnostics(const AUri: string);
var
  LDiags: TArray<TCPLSPDiagnostic>;
  LParams: TJSONObject;
  LDiagArray: TJSONArray;
  LI: Integer;
begin
  LDiags := FService.GetDiagnostics(AUri);
  LParams := TJSONObject.Create();
  LParams.AddPair('uri', AUri);
  LDiagArray := TJSONArray.Create();
  for LI := 0 to High(LDiags) do
    LDiagArray.AddElement(LDiags[LI].ToJSON());
  LParams.AddPair('diagnostics', LDiagArray);
  SendNotification('textDocument/publishDiagnostics', LParams);
end;

procedure TCPLSPServer.HandleInitialize(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LResult: TJSONObject;
  LCaps: TJSONObject;
  LTextSync: TJSONObject;
  LCompOpts: TJSONObject;
  LSigOpts: TJSONObject;
  LSigChars: TJSONArray;
  LSemanticOpts: TJSONObject;
  LLegend: TJSONObject;
  LTokenTypes: TJSONArray;
  LTokenMods: TJSONArray;
begin
  LResult := TJSONObject.Create();
  LCaps := TJSONObject.Create();

  // Text document sync: full document on every change
  LTextSync := TJSONObject.Create();
  LTextSync.AddPair('openClose', TJSONBool.Create(True));
  LTextSync.AddPair('change', TJSONNumber.Create(1));  // Full
  LCaps.AddPair('textDocumentSync', LTextSync);

  // Completion
  LCompOpts := TJSONObject.Create();
  LCompOpts.AddPair('resolveProvider', TJSONBool.Create(False));
  LCaps.AddPair('completionProvider', LCompOpts);

  // Hover
  LCaps.AddPair('hoverProvider', TJSONBool.Create(True));

  // Go to definition
  LCaps.AddPair('definitionProvider', TJSONBool.Create(True));

  // Go to type definition
  LCaps.AddPair('typeDefinitionProvider', TJSONBool.Create(True));

  // Find references
  LCaps.AddPair('referencesProvider', TJSONBool.Create(True));

  // Document symbols
  LCaps.AddPair('documentSymbolProvider', TJSONBool.Create(True));

  // Signature help
  LSigOpts := TJSONObject.Create();
  LSigChars := TJSONArray.Create();
  LSigChars.Add('(');
  LSigChars.Add(',');
  LSigOpts.AddPair('triggerCharacters', LSigChars);
  LCaps.AddPair('signatureHelpProvider', LSigOpts);

  // Folding
  LCaps.AddPair('foldingRangeProvider', TJSONBool.Create(True));

  // Semantic tokens
  LSemanticOpts := TJSONObject.Create();
  LLegend := TJSONObject.Create();
  LTokenTypes := TJSONArray.Create();
  LTokenTypes.Add('namespace');
  LTokenTypes.Add('type');
  LTokenTypes.Add('class');
  LTokenTypes.Add('enum');
  LTokenTypes.Add('interface');
  LTokenTypes.Add('struct');
  LTokenTypes.Add('typeParameter');
  LTokenTypes.Add('parameter');
  LTokenTypes.Add('variable');
  LTokenTypes.Add('property');
  LTokenTypes.Add('enumMember');
  LTokenTypes.Add('event');
  LTokenTypes.Add('function');
  LTokenTypes.Add('method');
  LTokenTypes.Add('macro');
  LTokenTypes.Add('keyword');
  LTokenTypes.Add('modifier');
  LTokenTypes.Add('comment');
  LTokenTypes.Add('string');
  LTokenTypes.Add('number');
  LTokenTypes.Add('regexp');
  LTokenTypes.Add('operator');
  LLegend.AddPair('tokenTypes', LTokenTypes);
  LTokenMods := TJSONArray.Create();
  LTokenMods.Add('declaration');
  LTokenMods.Add('definition');
  LLegend.AddPair('tokenModifiers', LTokenMods);
  LSemanticOpts.AddPair('legend', LLegend);
  LSemanticOpts.AddPair('full', TJSONBool.Create(True));
  LCaps.AddPair('semanticTokensProvider', LSemanticOpts);

  // Document formatting
  LCaps.AddPair('documentFormattingProvider', TJSONBool.Create(True));

  // Code action
  LCaps.AddPair('codeActionProvider', TJSONBool.Create(True));

  // Inlay hints
  LCaps.AddPair('inlayHintProvider', TJSONBool.Create(True));

  // Rename
  LCaps.AddPair('renameProvider', TJSONBool.Create(True));

  // Workspace symbol
  LCaps.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));

  // Call hierarchy
  LCaps.AddPair('callHierarchyProvider', TJSONBool.Create(True));

  LResult.AddPair('capabilities', LCaps);

  // Server info
  var LServerInfo := TJSONObject.Create();
  LServerInfo.AddPair('name', 'cpaskal-lsp');
  LServerInfo.AddPair('version', '0.1.0');
  LResult.AddPair('serverInfo', LServerInfo);

  SendResponse(AId, LResult);
  FInitialized := True;
end;

procedure TCPLSPServer.HandleInitialized(const AParams: TJSONObject);
begin
  // Client is ready -- nothing to do
end;

procedure TCPLSPServer.HandleShutdown(const AId: TJSONValue);
begin
  FShutdownRequested := True;
  Log('shutdown requested');
  SendResponse(AId, TJSONNull.Create());
end;

procedure TCPLSPServer.HandleExit();
begin
  if FShutdownRequested then
    FExitCode := 0
  else
    FExitCode := 1;
  FRunning := False;
end;

procedure TCPLSPServer.HandleTextDocumentDidOpen(
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LText: string;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then Exit;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LText := LTextDoc.GetValue<string>('text', '');

  if LUri <> '' then
  begin
    FService.OpenDocument(LUri, LText);
    PublishDiagnostics(LUri);
  end;
end;

procedure TCPLSPServer.HandleTextDocumentDidChange(
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LVersion: Integer;
  LChanges: TJSONArray;
  LChange: TJSONObject;
  LText: string;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then Exit;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LVersion := LTextDoc.GetValue<Integer>('version', 0);

  LChanges := AParams.GetValue<TJSONArray>('contentChanges', nil);
  if (LChanges = nil) or (LChanges.Count = 0) then Exit;

  // Full sync mode -- last change has the complete text
  LChange := LChanges.Items[LChanges.Count - 1] as TJSONObject;
  LText := LChange.GetValue<string>('text', '');

  if LUri <> '' then
  begin
    FService.UpdateDocument(LUri, LText, LVersion);
    PublishDiagnostics(LUri);
  end;
end;

procedure TCPLSPServer.HandleTextDocumentDidClose(
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LParams: TJSONObject;
  LDiagArray: TJSONArray;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then Exit;

  LUri := LTextDoc.GetValue<string>('uri', '');
  if LUri <> '' then
  begin
    // Clear diagnostics
    LParams := TJSONObject.Create();
    LParams.AddPair('uri', LUri);
    LDiagArray := TJSONArray.Create();
    LParams.AddPair('diagnostics', LDiagArray);
    SendNotification('textDocument/publishDiagnostics', LParams);

    FService.CloseDocument(LUri);
  end;
end;

procedure TCPLSPServer.HandleTextDocumentCompletion(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LItems: TArray<TCPLSPCompletionItem>;
  LResult: TJSONObject;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LItems := FService.GetCompletions(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  LResult := TJSONObject.Create();
  LResult.AddPair('isIncomplete', TJSONBool.Create(False));
  LArray := TJSONArray.Create();
  for LI := 0 to High(LItems) do
    LArray.AddElement(LItems[LI].ToJSON());
  LResult.AddPair('items', LArray);
  SendResponse(AId, LResult);
end;

procedure TCPLSPServer.HandleTextDocumentHover(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LHover: TCPLSPHover;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LHover := FService.GetHover(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if LHover.IsEmpty() then
    SendResponse(AId, TJSONNull.Create())
  else
    SendResponse(AId, LHover.ToJSON());
end;

procedure TCPLSPServer.HandleTextDocumentDefinition(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LLocation: TCPLSPLocation;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LLocation := FService.GetDefinition(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if LLocation.IsEmpty() then
    SendResponse(AId, TJSONNull.Create())
  else
    SendResponse(AId, LLocation.ToJSON());
end;

procedure TCPLSPServer.HandleTextDocumentTypeDefinition(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LLocation: TCPLSPLocation;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LLocation := FService.GetTypeDefinition(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if LLocation.IsEmpty() then
    SendResponse(AId, TJSONNull.Create())
  else
    SendResponse(AId, LLocation.ToJSON());
end;

procedure TCPLSPServer.HandleTextDocumentReferences(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LContext: TJSONObject;
  LUri: string;
  LIncludeDecl: Boolean;
  LLocations: TArray<TCPLSPLocation>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LContext := AParams.GetValue<TJSONObject>('context', nil);
  LIncludeDecl := True;
  if LContext <> nil then
    LIncludeDecl := LContext.GetValue<Boolean>('includeDeclaration', True);

  LLocations := FService.GetReferences(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0),
    LIncludeDecl);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LLocations) do
    LArray.AddElement(LLocations[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.HandleTextDocumentDocumentSymbol(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LSymbols: TArray<TCPLSPDocumentSymbol>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LSymbols := FService.GetDocumentSymbols(LUri);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LSymbols) do
    LArray.AddElement(LSymbols[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.HandleTextDocumentSignatureHelp(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LSigHelp: TCPLSPSignatureHelp;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LSigHelp := FService.GetSignatureHelp(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if Length(LSigHelp.Signatures) = 0 then
    SendResponse(AId, TJSONNull.Create())
  else
    SendResponse(AId, LSigHelp.ToJSON());
end;

procedure TCPLSPServer.HandleTextDocumentFoldingRange(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LRanges: TArray<TCPLSPFoldingRange>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LRanges := FService.GetFoldingRanges(LUri);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LRanges) do
    LArray.AddElement(LRanges[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.HandleTextDocumentSemanticTokensFull(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LUri: string;
  LData: TArray<Integer>;
  LResult: TJSONObject;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LData := FService.GetSemanticTokens(LUri);

  LResult := TJSONObject.Create();
  LArray := TJSONArray.Create();
  for LI := 0 to High(LData) do
    LArray.Add(LData[LI]);
  LResult.AddPair('data', LArray);
  SendResponse(AId, LResult);
end;

procedure TCPLSPServer.HandleTextDocumentFormatting(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LOptions: TJSONObject;
  LUri: string;
  LTabSize: Integer;
  LInsertSpaces: Boolean;
  LEdits: TArray<TCPLSPTextEdit>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LOptions := AParams.GetValue<TJSONObject>('options', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LTabSize := 2;
  LInsertSpaces := True;
  if LOptions <> nil then
  begin
    LTabSize := LOptions.GetValue<Integer>('tabSize', 2);
    LInsertSpaces := LOptions.GetValue<Boolean>('insertSpaces', True);
  end;

  LEdits := FService.GetDocumentFormatting(LUri, LTabSize, LInsertSpaces);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LEdits) do
    LArray.AddElement(LEdits[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.HandleTextDocumentCodeAction(const AId: TJSONValue;
  const AParams: TJSONObject);
begin
  // No code actions implemented yet
  SendResponse(AId, TJSONArray.Create());
end;

procedure TCPLSPServer.HandleTextDocumentInlayHint(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LRangeObj: TJSONObject;
  LUri: string;
  LLSPRange: TCPLSPRange;
  LHints: TArray<TCPLSPInlayHint>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  if LTextDoc = nil then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LLSPRange.Clear();
  LRangeObj := AParams.GetValue<TJSONObject>('range', nil);
  if LRangeObj <> nil then
    LLSPRange := TCPLSPRange.FromJSON(LRangeObj);

  LHints := FService.GetInlayHints(LUri,
    LLSPRange.StartPos.Line, LLSPRange.StartPos.Character,
    LLSPRange.EndPos.Line, LLSPRange.EndPos.Character);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LHints) do
    LArray.AddElement(LHints[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.HandleTextDocumentRename(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LNewName: string;
  LEdit: TCPLSPWorkspaceEdit;
  LResult: TJSONObject;
  LChanges: TJSONObject;
  LEditsArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LNewName := AParams.GetValue<string>('newName', '');

  LEdit := FService.GetRenameEdits(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0),
    LNewName);

  if Length(LEdit.Edits) = 0 then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LResult := TJSONObject.Create();
  LChanges := TJSONObject.Create();
  LEditsArray := TJSONArray.Create();
  for LI := 0 to High(LEdit.Edits) do
    LEditsArray.AddElement(LEdit.Edits[LI].ToJSON());
  LChanges.AddPair(LEdit.Uri, LEditsArray);
  LResult.AddPair('changes', LChanges);
  SendResponse(AId, LResult);
end;

procedure TCPLSPServer.HandleWorkspaceSymbol(const AId: TJSONValue;
  const AParams: TJSONObject);
var
  LQuery: string;
  LSymbols: TArray<TCPLSPSymbolInformation>;
  LArray: TJSONArray;
  LI: Integer;
  LPair: TPair<string, TCPLSPDocument>;
begin
  LQuery := AParams.GetValue<string>('query', '');

  LArray := TJSONArray.Create();
  // Search all open documents
  for LPair in FService.FDocuments do
  begin
    LSymbols := FService.GetWorkspaceSymbols(LQuery, LPair.Key);
    for LI := 0 to High(LSymbols) do
      LArray.AddElement(LSymbols[LI].ToJSON());
  end;
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.HandleTextDocumentPrepareCallHierarchy(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LTextDoc: TJSONObject;
  LPos: TJSONObject;
  LUri: string;
  LItems: TArray<TCPLSPCallHierarchyItem>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LTextDoc := AParams.GetValue<TJSONObject>('textDocument', nil);
  LPos := AParams.GetValue<TJSONObject>('position', nil);
  if (LTextDoc = nil) or (LPos = nil) then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LUri := LTextDoc.GetValue<string>('uri', '');
  LItems := FService.PrepareCallHierarchy(LUri,
    LPos.GetValue<Integer>('line', 0),
    LPos.GetValue<Integer>('character', 0));

  if Length(LItems) = 0 then
  begin
    SendResponse(AId, TJSONNull.Create());
    Exit;
  end;

  LArray := TJSONArray.Create();
  for LI := 0 to High(LItems) do
    LArray.AddElement(LItems[LI].ToJSON());
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.HandleCallHierarchyIncomingCalls(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LItem: TJSONObject;
  LUri: string;
  LName: string;
  LCalls: TArray<TCPLSPCallHierarchyCall>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LItem := AParams.GetValue<TJSONObject>('item', nil);
  if LItem = nil then
  begin
    SendResponse(AId, TJSONArray.Create());
    Exit;
  end;

  LUri := LItem.GetValue<string>('uri', '');
  LName := LItem.GetValue<string>('name', '');

  LCalls := FService.GetIncomingCalls(LUri, LName);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LCalls) do
    LArray.AddElement(LCalls[LI].ToJSON('from'));
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.HandleCallHierarchyOutgoingCalls(
  const AId: TJSONValue; const AParams: TJSONObject);
var
  LItem: TJSONObject;
  LUri: string;
  LName: string;
  LCalls: TArray<TCPLSPCallHierarchyCall>;
  LArray: TJSONArray;
  LI: Integer;
begin
  LItem := AParams.GetValue<TJSONObject>('item', nil);
  if LItem = nil then
  begin
    SendResponse(AId, TJSONArray.Create());
    Exit;
  end;

  LUri := LItem.GetValue<string>('uri', '');
  LName := LItem.GetValue<string>('name', '');

  LCalls := FService.GetOutgoingCalls(LUri, LName);

  LArray := TJSONArray.Create();
  for LI := 0 to High(LCalls) do
    LArray.AddElement(LCalls[LI].ToJSON('to'));
  SendResponse(AId, LArray);
end;

procedure TCPLSPServer.DispatchMessage(const AMessage: TJSONObject);
var
  LMethod: string;
  LId: TJSONValue;
  LParams: TJSONObject;
begin
  LMethod := AMessage.GetValue<string>('method', '');
  LId := AMessage.GetValue('id');
  LParams := AMessage.GetValue<TJSONObject>('params', nil);

  // Requests (have id)
  if LId <> nil then
  begin
    if LMethod = 'initialize' then
      HandleInitialize(LId, LParams)
    else if LMethod = 'shutdown' then
      HandleShutdown(LId)
    else if LMethod = 'textDocument/completion' then
      HandleTextDocumentCompletion(LId, LParams)
    else if LMethod = 'textDocument/hover' then
      HandleTextDocumentHover(LId, LParams)
    else if LMethod = 'textDocument/definition' then
      HandleTextDocumentDefinition(LId, LParams)
    else if LMethod = 'textDocument/typeDefinition' then
      HandleTextDocumentTypeDefinition(LId, LParams)
    else if LMethod = 'textDocument/references' then
      HandleTextDocumentReferences(LId, LParams)
    else if LMethod = 'textDocument/documentSymbol' then
      HandleTextDocumentDocumentSymbol(LId, LParams)
    else if LMethod = 'textDocument/signatureHelp' then
      HandleTextDocumentSignatureHelp(LId, LParams)
    else if LMethod = 'textDocument/foldingRange' then
      HandleTextDocumentFoldingRange(LId, LParams)
    else if LMethod = 'textDocument/semanticTokens/full' then
      HandleTextDocumentSemanticTokensFull(LId, LParams)
    else if LMethod = 'textDocument/formatting' then
      HandleTextDocumentFormatting(LId, LParams)
    else if LMethod = 'textDocument/codeAction' then
      HandleTextDocumentCodeAction(LId, LParams)
    else if LMethod = 'textDocument/inlayHint' then
      HandleTextDocumentInlayHint(LId, LParams)
    else if LMethod = 'textDocument/rename' then
      HandleTextDocumentRename(LId, LParams)
    else if LMethod = 'workspace/symbol' then
      HandleWorkspaceSymbol(LId, LParams)
    else if LMethod = 'textDocument/prepareCallHierarchy' then
      HandleTextDocumentPrepareCallHierarchy(LId, LParams)
    else if LMethod = 'callHierarchy/incomingCalls' then
      HandleCallHierarchyIncomingCalls(LId, LParams)
    else if LMethod = 'callHierarchy/outgoingCalls' then
      HandleCallHierarchyOutgoingCalls(LId, LParams)
    else
      SendError(LId, -32601, 'Method not found: ' + LMethod);
  end
  else
  begin
    // Notifications (no id)
    if LMethod = 'initialized' then
      HandleInitialized(LParams)
    else if LMethod = 'exit' then
      HandleExit()
    else if LMethod = 'textDocument/didOpen' then
      HandleTextDocumentDidOpen(LParams)
    else if LMethod = 'textDocument/didChange' then
      HandleTextDocumentDidChange(LParams)
    else if LMethod = 'textDocument/didClose' then
      HandleTextDocumentDidClose(LParams);
    // Unknown notifications are silently ignored per spec
  end;
end;

function TCPLSPServer.Run(): Word;
var
  LMsg: TJSONObject;
begin
  // Default to stdin/stdout if no streams set
  if FInputStream = nil then
  begin
    FInputStream := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
    FOutputStream := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
    FOwnsStreams := True;
  end;

  FRunning := True;
  FExitCode := 0;

  Log('started');

  while FRunning do
  begin
    LMsg := ReadMessage();
    if LMsg = nil then Break;
    try
      DispatchMessage(LMsg);
    finally
      LMsg.Free();
    end;
  end;

  Log('exiting with code ' + IntToStr(FExitCode));
  Result := FExitCode;
end;

end.
