{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.Compiler - Top-level compiler driver

  Owns and orchestrates the full pipeline:
    Parser -> Semantics -> Codegen -> ZigBuild

  All components share a single error handler via SetErrors. Status callbacks
  propagate to all components via SetStatusCallback override.

  The caller configures build settings (target, output path, optimize level,
  etc.) before calling Compile(). Compile() runs the full pipeline in one
  shot: parse, analyze, generate C++23, wire generated files into ZigBuild,
  and build the native binary.

  Dependencies: CPaskal.Common, CPaskal.Lexer, CPaskal.AST, CPaskal.Parser,
                CPaskal.Semantics, CPaskal.Codegen, CPaskal.ZigBuild
===============================================================================}

unit CPaskal.Compiler;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Resources,
  CPaskal.Common,
  CPaskal.AST,
  CPaskal.Parser,
  CPaskal.Semantics,
  CPaskal.Codegen,
  CPaskal.ZigBuild;

const
  { CP_ERR_CMP_001 }
  CP_ERR_CMP_001 = 'CMP001';  // Source file not found

  { CP_ERR_CMP_002 }
  CP_ERR_CMP_002 = 'CMP002';  // Cannot auto-run

type

  TCPCompiler = class;

  { TPreParseCallback }
  TPreParseCallback = reference to procedure(const ACompiler: TCPCompiler;
    const AUserData: Pointer);

  { TPreParseCallbackEntry }
  TPreParseCallbackEntry = TCallback<TPreParseCallback>;

  { TPreParseCallbackList }
  TPreParseCallbackList = TList<TPreParseCallbackEntry>;

  { TPreBuildCallback }
  TPreBuildCallback = reference to procedure(const ACompiler: TCPCompiler;
    const AUserData: Pointer);

  { TPreBuildCallbackEntry }
  TPreBuildCallbackEntry = TCallback<TPreBuildCallback>;

  { TPreBuildCallbackList }
  TPreBuildCallbackList = TList<TPreBuildCallbackEntry>;

  { TCPCompiler }
  TCPCompiler = class(TBaseObject)
  protected
    FParser: TCPParser;
    FSemantics: TCPSemantics;
    FCodegen: TCPCodegen;
    FZigBuild: TCPZigBuild;
    FMasterAST: TCPMasterAST;
    FPreParseCallbacks: TPreParseCallbackList;
    FPreBuildCallbacks: TPreBuildCallbackList;
    FKeyValues: TDictionary<string, string>;
    procedure DoProcessDirectives();
    procedure DoFirePreParseCallbacks();
    procedure DoFirePreBuildCallbacks();
    procedure DoSetupPlatformDefines();
    procedure DoCLIDirectives();
    function DoValidateUnitModule(): Boolean;
    procedure DoCollectExternalLibs();
    procedure DoSetBuildMode();
    function DoValidateAutoRun(): Boolean;
  public
    constructor Create(); override;
    destructor Destroy(); override;

    procedure SetStatusCallback(const ACallback: TStatusCallback;
      const AUserData: Pointer = nil); override;

    // Full compilation pipeline: .cpas -> C++23 -> native binary
    procedure Compile(const ASourceFile: string; const AOutputPath: string;
      const AAutoRun: Boolean = False);

    // Run the last built artifact
    function Run(): Boolean;

    // Clean build artifacts
    function ClearCache(): Boolean;
    function ClearOutput(): Boolean;

    // Build configuration (set before calling Compile)
    procedure SetOutputCallback(const ACallback: TCaptureConsoleCallback;
      const AUserData: Pointer = nil);
    procedure SetProjectName(const AProjectName: string);
    procedure SetBuildMode(const ABuildMode: TCPBuildMode);
    procedure SetOptimizeLevel(const AOptimizeLevel: TCPOptimizeLevel);
    procedure SetSubsystem(const ASubsystem: TCPSubsystemType);
    procedure SetRawOutput(const AValue: Boolean);
    procedure SetRunArguments(const AArguments: string);
    procedure SetTarget(const ATarget: string); overload;
    procedure SetTarget(const AArch: string; const AOS: string;
      const AAbi: string = ''); overload;
    procedure SetToolchainPath(const APath: string);

    // Defines
    procedure SetDefine(const ADefineName: string); overload;
    procedure SetDefine(const ADefineName: string; const AValue: string); overload;
    procedure SetDefines(const ADefineNames: array of string);

    // Undefines
    procedure UnsetDefine(const ADefineName: string);
    procedure RemoveUndefine(const ADefineName: string);
    procedure ClearUndefines();

    // Link libraries
    procedure AddLinkLibrary(const ALibrary: string);
    procedure AddLinkLibraries(const ALibraries: array of string);
    procedure AddLibraryPath(const APath: string);

    // Post-build
    procedure AddCopyDLL(const ADLLPath: string);
    procedure AddPostBuildCopy(const ASourceFile: string; const ADestDir: string);
    procedure AddPublishArtifact(const ADestDir: string);

    // Version info
    procedure SetAddVersionInfo(const AValue: Boolean);
    procedure SetVIMajor(const AValue: Word);
    procedure SetVIMinor(const AValue: Word);
    procedure SetVIPatch(const AValue: Word);
    procedure SetVIProductName(const AValue: string);
    procedure SetVIDescription(const AValue: string);
    procedure SetVIFilename(const AValue: string);
    procedure SetVICompanyName(const AValue: string);
    procedure SetVICopyright(const AValue: string);
    procedure SetExeIcon(const AValue: string);

    // Breakpoints
    procedure AddBreakpoint(const AFileName: string; const ALineNumber: Integer);
    procedure ClearBreakpoints();

    // Pre-parse callbacks (fired before parsing begins)
    procedure AddPreParseCallback(const ACallback: TPreParseCallback;
      const AUserData: Pointer = nil);
    procedure ClearPreParseCallbacks();

    // Pre-build callbacks (fired after directives, before ZigBuild)
    procedure AddPreBuildCallback(const ACallback: TPreBuildCallback;
      const AUserData: Pointer = nil);
    procedure ClearPreBuildCallbacks();

    // Key-value store (generic property bag for cross-phase data)
    procedure SetKeyValue(const AKey: string; const AValue: string);
    function GetKeyValue(const AKey: string; const ADefault: string = ''): string;
    procedure ClearKeyValue(const AKey: string);

    // Getters
    function GetLastExitCode(): DWORD;
    function GetOutputPath(): string;
    function GetProjectName(): string;
    function GetBuildMode(): TCPBuildMode;
    function GetOptimizeLevel(): TCPOptimizeLevel;
    function GetSubsystem(): TCPSubsystemType;
    function GetTarget(): string;
    function GetToolchainPath(): string;
    function GetOutputFilename(): string;
    function GetRunArguments(): string;
    function GetZigPath(const AFilename: string = ''): string;
    function GetRuntimePath(const AFilename: string = ''): string;
  end;

implementation

uses
  System.IOUtils;

{ TCPCompiler }
constructor TCPCompiler.Create();
begin
  inherited;

  FParser := TCPParser.Create();
  FParser.SetErrors(FErrors);

  FSemantics := TCPSemantics.Create();
  FSemantics.SetErrors(FErrors);

  FCodegen := TCPCodegen.Create();
  FCodegen.SetErrors(FErrors);

  FZigBuild := TCPZigBuild.Create();
  FZigBuild.SetErrors(FErrors);

  FPreParseCallbacks := TPreParseCallbackList.Create();
  FPreBuildCallbacks := TPreBuildCallbackList.Create();
  FKeyValues := TDictionary<string, string>.Create();
  FMasterAST := nil;
end;

destructor TCPCompiler.Destroy();
begin
  FMasterAST.Free();
  FKeyValues.Free();
  FPreBuildCallbacks.Free();
  FPreParseCallbacks.Free();
  FZigBuild.Free();
  FCodegen.Free();
  FSemantics.Free();
  FParser.Free();

  inherited;
end;

procedure TCPCompiler.SetStatusCallback(const ACallback: TStatusCallback;
  const AUserData: Pointer);
begin
  inherited;

  FParser.SetStatusCallback(ACallback, AUserData);
  FSemantics.SetStatusCallback(ACallback, AUserData);
  FCodegen.SetStatusCallback(ACallback, AUserData);
  FZigBuild.SetStatusCallback(ACallback, AUserData);
end;

{ TCPCompiler }

{ TCPCompiler.DoSetupPlatformDefines }
procedure TCPCompiler.DoSetupPlatformDefines();
var
  LTarget: string;
  LOptLevel: string;
begin
  // Platform defines based on target -- key-value store overrides FZigBuild default
  FParser.Undefine('WINDOWS');
  FParser.Undefine('MSWINDOWS');
  FParser.Undefine('WIN64');
  FParser.Undefine('TARGET_WIN64');
  FParser.Undefine('LINUX');
  FParser.Undefine('TARGET_LINUX64');

  LTarget := GetKeyValue('target');
  if LTarget = '' then
    LTarget := FZigBuild.GetTarget();
  LTarget := LTarget.ToLower();

  if LTarget.Contains('linux') then
  begin
    FParser.SetDefine('LINUX', '1');
    FParser.SetDefine('TARGET_LINUX64', '1');
  end
  else
  begin
    FParser.SetDefine('WINDOWS', '1');
    FParser.SetDefine('MSWINDOWS', '1');
    FParser.SetDefine('WIN64', '1');
    FParser.SetDefine('TARGET_WIN64', '1');
  end;

  // Optimization level -- key-value store overrides FZigBuild default
  FParser.Undefine('DEBUG');
  FParser.Undefine('RELEASE');

  LOptLevel := GetKeyValue('optimize');
  if LOptLevel <> '' then
  begin
    if LOptLevel = 'debug' then
      FParser.SetDefine('DEBUG', '1')
    else
      FParser.SetDefine('RELEASE', '1');
  end
  else
  begin
    if FZigBuild.GetOptimizeLevel() = olDebug then
      FParser.SetDefine('DEBUG', '1')
    else
      FParser.SetDefine('RELEASE', '1');
  end;
end;

{ TCPCompiler.DoProcessDirectives }
procedure TCPCompiler.DoProcessDirectives();
var
  LMainModule: TCPModuleNode;
  LDir: TCPDirectiveNode;
  LName: string;
  LValue: string;
  I: Integer;
begin
  if (FMasterAST = nil) or (FMasterAST.Modules.Count = 0) then
    Exit;

  // Only the main module (index 0) provides build configuration
  LMainModule := FMasterAST.Modules[0];

  for I := 0 to LMainModule.Directives.Count - 1 do
  begin
    LDir := LMainModule.Directives[I];
    LName := LDir.DirectiveName.ToLower();
    LValue := LDir.DirectiveValue.ToLower();

    if LName = 'target' then
    begin
      // Target is resolved by semantics -- read from AST
      if LMainModule.ResolvedTargetTriple <> '' then
        SetTarget(LMainModule.ResolvedTargetTriple);
    end
    else if LName = 'subsystem' then
    begin
      if LValue = 'console' then
        SetSubsystem(stConsole)
      else if LValue = 'gui' then
        SetSubsystem(stGUI)
      else
        FErrors.Add(LDir.Location, esWarning, CP_ERR_CMP_001,
          'Unknown @subsystem value ''%s''; expected console or gui',
          [LDir.DirectiveValue]);
    end
    else if LName = 'optimize' then
    begin
      if LValue = 'debug' then
        SetOptimizeLevel(olDebug)
      else if LValue = 'release-safe' then
        SetOptimizeLevel(olReleaseSafe)
      else if LValue = 'release-fast' then
        SetOptimizeLevel(olReleaseFast)
      else if LValue = 'release-small' then
        SetOptimizeLevel(olReleaseSmall)
      else
        FErrors.Add(LDir.Location, esWarning, CP_ERR_CMP_001,
          'Unknown @optimize value ''%s''; expected debug, release-safe, release-fast, or release-small',
          [LDir.DirectiveValue]);
    end
    else if LName = 'librarypath' then
    begin
      AddLibraryPath(LDir.ResolvedValue);
    end;
    // @modulepath handled during import resolution (not here)
  end;
end;

{ TCPCompiler.DoFirePreParseCallbacks }
procedure TCPCompiler.DoFirePreParseCallbacks();
var
  I: Integer;
begin
  for I := 0 to FPreParseCallbacks.Count - 1 do
    FPreParseCallbacks[I].Callback(Self, FPreParseCallbacks[I].UserData);
end;

{ TCPCompiler.AddPreParseCallback }
procedure TCPCompiler.AddPreParseCallback(const ACallback: TPreParseCallback;
  const AUserData: Pointer);
var
  LEntry: TPreParseCallbackEntry;
begin
  LEntry.Callback := ACallback;
  LEntry.UserData := AUserData;
  FPreParseCallbacks.Add(LEntry);
end;

{ TCPCompiler.ClearPreParseCallbacks }
procedure TCPCompiler.ClearPreParseCallbacks();
begin
  FPreParseCallbacks.Clear();
end;

{ TCPCompiler.SetKeyValue }
procedure TCPCompiler.SetKeyValue(const AKey: string; const AValue: string);
begin
  FKeyValues.AddOrSetValue(AKey, AValue);
end;

{ TCPCompiler.GetKeyValue }
function TCPCompiler.GetKeyValue(const AKey: string; const ADefault: string): string;
begin
  if not FKeyValues.TryGetValue(AKey, Result) then
    Result := ADefault;
end;

{ TCPCompiler.ClearKeyValue }
procedure TCPCompiler.ClearKeyValue(const AKey: string);
begin
  FKeyValues.Remove(AKey);
end;

{ TCPCompiler.DoCLIDirectives }
procedure TCPCompiler.DoCLIDirectives();
var
  LValue: string;
  LTarget: TCPTargetPlatform;
begin
  // Apply CLI overrides from key-value store -- these override source directives
  LValue := GetKeyValue('target');
  if LValue <> '' then
  begin
    if cpTryParseTarget(LValue, LTarget) then
      SetTarget(cpTargetTriple(LTarget))
    else
      SetTarget(LValue); // raw zig triple passthrough from CLI
  end;

  LValue := GetKeyValue('optimize');
  if LValue <> '' then
  begin
    if LValue = 'debug' then
      SetOptimizeLevel(olDebug)
    else if LValue = 'release-safe' then
      SetOptimizeLevel(olReleaseSafe)
    else if LValue = 'release-fast' then
      SetOptimizeLevel(olReleaseFast)
    else if LValue = 'release-small' then
      SetOptimizeLevel(olReleaseSmall);
  end;

  LValue := GetKeyValue('subsystem');
  if LValue <> '' then
  begin
    if SameText(LValue, 'gui') then
      SetSubsystem(stGUI)
    else
      SetSubsystem(stConsole);
  end;
end;

{ TCPCompiler.DoFirePreBuildCallbacks }
procedure TCPCompiler.DoFirePreBuildCallbacks();
var
  I: Integer;
begin
  for I := 0 to FPreBuildCallbacks.Count - 1 do
    FPreBuildCallbacks[I].Callback(Self, FPreBuildCallbacks[I].UserData);
end;

procedure TCPCompiler.AddPreBuildCallback(const ACallback: TPreBuildCallback;
  const AUserData: Pointer);
var
  LEntry: TPreBuildCallbackEntry;
begin
  LEntry.Callback := ACallback;
  LEntry.UserData := AUserData;
  FPreBuildCallbacks.Add(LEntry);
end;

procedure TCPCompiler.ClearPreBuildCallbacks();
begin
  FPreBuildCallbacks.Clear();
end;

{ TCPCompiler.DoCollectExternalLibs }
procedure TCPCompiler.DoCollectExternalLibs();
var
  LModIdx: Integer;
  LDeclIdx: Integer;
  LModule: TCPModuleNode;
  LDecl: TCPASTNode;
  LLib: string;
begin
  for LModIdx := 0 to FMasterAST.Modules.Count - 1 do
  begin
    LModule := FMasterAST.Modules[LModIdx];
    for LDeclIdx := 0 to LModule.Declarations.Count - 1 do
    begin
      LDecl := LModule.Declarations[LDeclIdx];

      LLib := '';
      if (LDecl is TCPRoutineDeclNode) and TCPRoutineDeclNode(LDecl).IsExternal then
        LLib := TCPRoutineDeclNode(LDecl).ResolvedExternalLib
      else if (LDecl is TCPVarDeclNode) and TCPVarDeclNode(LDecl).IsExternal then
        LLib := TCPVarDeclNode(LDecl).ResolvedExternalLib;

      if LLib <> '' then
        FZigBuild.AddLinkLibrary(LLib);
    end;
  end;
end;

{ TCPCompiler.DoSetBuildMode }
procedure TCPCompiler.DoSetBuildMode();
var
  LModuleKind: TCPModuleKind;
begin
  LModuleKind := FMasterAST.Modules[0].ModuleKind;
  case LModuleKind of
    mkExe: FZigBuild.SetBuildMode(bmExe);
    mkDll: FZigBuild.SetBuildMode(bmDll);
    mkLib: FZigBuild.SetBuildMode(bmLib);
  end;
  // mkUnit never reaches here -- DoValidateUnitModule exits earlier
end;

{ TCPCompiler.DoValidateAutoRun }
function TCPCompiler.DoValidateAutoRun(): Boolean;
var
  LModuleKind: TCPModuleKind;
  LTarget: string;
begin
  Result := True;
  LModuleKind := FMasterAST.Modules[0].ModuleKind;

  // Only exe modules can be run
  if LModuleKind <> mkExe then
  begin
    if LModuleKind = mkDll then
      FErrors.Add(FMasterAST.Modules[0].Location, esError, CP_ERR_CMP_002,
        RSSemCannotRunModule, ['dll'])
    else if LModuleKind = mkLib then
      FErrors.Add(FMasterAST.Modules[0].Location, esError, CP_ERR_CMP_002,
        RSSemCannotRunModule, ['lib'])
    else
      FErrors.Add(FMasterAST.Modules[0].Location, esError, CP_ERR_CMP_002,
        RSSemCannotRunModule, ['unit']);
    Result := False;
    Exit;
  end;

  // Only native targets can be run
  LTarget := FZigBuild.GetTarget();
  if (LTarget <> cpTargetTriple(tpX86_64_Windows)) and
     (LTarget <> cpTargetTriple(tpX86_64_Linux)) then
  begin
    FErrors.Add(FMasterAST.Modules[0].Location, esError, CP_ERR_CMP_002,
      RSSemCannotRunTarget, [LTarget]);
    Result := False;
  end;
end;

{ TCPCompiler.DoValidateUnitModule }
function TCPCompiler.DoValidateUnitModule(): Boolean;
begin
  Result := FMasterAST.Modules[0].ModuleKind = mkUnit;
  if not Result then
    Exit;

  Status('Unit ''%s'' validated successfully.',
    [FMasterAST.Modules[0].ModuleName]);
  Status('Warning: Unit modules produce no output. Import this unit from an exe, dll, or lib module.');
end;

procedure TCPCompiler.Compile(const ASourceFile: string;
  const AOutputPath: string; const AAutoRun: Boolean);
var
  LGeneratedPath: string;
  LProjectName: string;
  LSourceFile: string;
  LSourceDir: string;
  LAutoRun: Boolean;
  LModule: TCPModuleNode;
  LPendingName: string;
  LPendingFile: string;
  I: Integer;
begin
  LAutoRun := AAutoRun;
  FErrors.Clear();
  FreeAndNil(FMasterAST);
  FMasterAST := TCPMasterAST.Create();

  // Normalize source file extension
  LSourceFile := TPath.ChangeExtension(ASourceFile, CP_SRC_EXT);

  if not TFile.Exists(LSourceFile) then
  begin
    FErrors.Add(esFatal, CP_ERR_CMP_001,
      'Source file not found: %s', [LSourceFile]);
    Exit;
  end;

  LProjectName := TPath.GetFileNameWithoutExtension(LSourceFile);
  LSourceDir := TPath.GetDirectoryName(TPath.GetFullPath(LSourceFile));

  // Phase 1: Parse -- queue-based import processing
  // Fire pre-parse callbacks (CLI stores key-values here)
  DoFirePreParseCallbacks();

  // Set up platform defines before parsing begins
  DoSetupPlatformDefines();

  // Parse the main module, then process any imports it declares
  Status('Parsing %s...', [TPath.GetFileName(LSourceFile)]);
  LModule := FParser.ParseModule(LSourceFile, FMasterAST);
  if LModule = nil then
    Exit;
  FMasterAST.AddModule(LModule);
  if FErrors.HasErrors() then
    Exit;

  // Process pending imports until queue is empty
  while FMasterAST.HasPending() do
  begin
    LPendingName := FMasterAST.DequeuePending();

    // Resolve import name to file path
    // First search: source file's own directory
    LPendingFile := TPath.Combine(LSourceDir,
      TPath.ChangeExtension(LPendingName, CP_SRC_EXT));

    // TODO: search @modulepath directories if not found in source dir

    if not TFile.Exists(LPendingFile) then
    begin
      FErrors.Add(esError, CP_ERR_CMP_001,
        'Imported module file not found: %s', [LPendingName]);
      Exit;
    end;

    Status('Parsing %s...', [TPath.GetFileName(LPendingFile)]);
    LModule := FParser.ParseModule(LPendingFile, FMasterAST);
    if LModule = nil then
      Exit;

    // Verify imported module is a unit
    if LModule.ModuleKind <> mkUnit then
    begin
      FErrors.Add(LModule.Location, esError, CP_ERR_CMP_001,
        'Cannot import module ''%s'': only unit modules can be imported',
        [LModule.ModuleName]);
      LModule.Free();
      Exit;
    end;

    FMasterAST.AddModule(LModule);
    if FErrors.HasErrors() then
      Exit;
  end;

  // Fire pre-build callbacks (user hooks)
  Status('Processing pre-build callbacks...');
  DoFirePreBuildCallbacks();

  // Phase 2: Semantic analysis
  Status('Analyzing...');
  FErrors.RaiseOnError := True;
  try
    FSemantics.Analyze(FMasterAST);
  except
    on EStdAppException do;
  end;
  FErrors.RaiseOnError := False;
  if FErrors.HasErrors() then
    Exit;

  // Process directives from enriched AST (after semantics)
  Status('Processing directives...');
  DoProcessDirectives();

  // Apply CLI directive overrides from key-value store
  DoCLIDirectives();

  // Unit modules: validate only, no codegen or build
  if DoValidateUnitModule() then
    Exit;

  // Set build mode from module kind (exe/dll/lib)
  DoSetBuildMode();

  // Phase 3: Code generation
  LGeneratedPath := TPath.Combine(AOutputPath, 'generated');
  TUtils.CreateDirInPath(LGeneratedPath);

  Status('Generating C++23...');
  FCodegen.Generate(FMasterAST, LGeneratedPath);
  if FErrors.HasErrors() then
    Exit;

  // Phase 4: Wire ZigBuild and compile
  FZigBuild.SetOutputPath(AOutputPath);
  FZigBuild.SetProjectName(LProjectName);
  FZigBuild.ClearSourceFiles();
  FZigBuild.ClearIncludePaths();

  // Runtime
  FZigBuild.AddSourceFile(FZigBuild.GetRuntimePath('runtime.cpp'));
  FZigBuild.AddIncludePath(FZigBuild.GetRuntimePath());

  // Generated sources and headers
  FZigBuild.AddIncludePath(LGeneratedPath);
  for I := 0 to FMasterAST.Modules.Count - 1 do
    FZigBuild.AddSourceFile(
      TPath.Combine(LGeneratedPath, FMasterAST.Modules[I].ModuleName + '.cpp'));

  // Collect external library references from AST
  DoCollectExternalLibs();

  // Default library path for exe builds: output/zig-out/bin (where DLLs are built)
  if FMasterAST.Modules[0].ModuleKind = mkExe then
    FZigBuild.AddLibraryPath(
      TPath.Combine(TPath.Combine(AOutputPath, 'zig-out'), 'bin'));

  // Validate auto-run before build
  if LAutoRun and (not DoValidateAutoRun()) then
    LAutoRun := False;

  // Build (and optionally run)
  FZigBuild.Process(LAutoRun);
end;

function TCPCompiler.Run(): Boolean;
begin
  Result := FZigBuild.Run();
end;

function TCPCompiler.ClearCache(): Boolean;
begin
  Result := FZigBuild.ClearCache();
end;

function TCPCompiler.ClearOutput(): Boolean;
begin
  Result := FZigBuild.ClearOutput();
end;

procedure TCPCompiler.SetOutputCallback(const ACallback: TCaptureConsoleCallback;
  const AUserData: Pointer);
begin
  FZigBuild.SetOutputCallback(ACallback, AUserData);
end;

procedure TCPCompiler.SetProjectName(const AProjectName: string);
begin
  FZigBuild.SetProjectName(AProjectName);
end;

procedure TCPCompiler.SetBuildMode(const ABuildMode: TCPBuildMode);
begin
  FZigBuild.SetBuildMode(ABuildMode);
end;

procedure TCPCompiler.SetOptimizeLevel(const AOptimizeLevel: TCPOptimizeLevel);
begin
  FZigBuild.SetOptimizeLevel(AOptimizeLevel);
end;

procedure TCPCompiler.SetSubsystem(const ASubsystem: TCPSubsystemType);
begin
  FZigBuild.SetSubsystem(ASubsystem);
end;

procedure TCPCompiler.SetRawOutput(const AValue: Boolean);
begin
  FZigBuild.SetRawOutput(AValue);
end;

procedure TCPCompiler.SetRunArguments(const AArguments: string);
begin
  FZigBuild.SetRunArguments(AArguments);
end;

procedure TCPCompiler.SetTarget(const ATarget: string);
begin
  FZigBuild.SetTarget(ATarget);
end;

procedure TCPCompiler.SetTarget(const AArch: string; const AOS: string;
  const AAbi: string);
begin
  FZigBuild.SetTarget(AArch, AOS, AAbi);
end;

procedure TCPCompiler.SetToolchainPath(const APath: string);
begin
  FZigBuild.SetToolchainPath(APath);
end;

procedure TCPCompiler.SetDefine(const ADefineName: string);
begin
  FZigBuild.SetDefine(ADefineName);
end;

procedure TCPCompiler.SetDefine(const ADefineName: string; const AValue: string);
begin
  FZigBuild.SetDefine(ADefineName, AValue);
end;

procedure TCPCompiler.SetDefines(const ADefineNames: array of string);
begin
  FZigBuild.SetDefines(ADefineNames);
end;

procedure TCPCompiler.UnsetDefine(const ADefineName: string);
begin
  FZigBuild.UnsetDefine(ADefineName);
end;

procedure TCPCompiler.RemoveUndefine(const ADefineName: string);
begin
  FZigBuild.RemoveUndefine(ADefineName);
end;

procedure TCPCompiler.ClearUndefines();
begin
  FZigBuild.ClearUndefines();
end;

procedure TCPCompiler.AddLinkLibrary(const ALibrary: string);
begin
  FZigBuild.AddLinkLibrary(ALibrary);
end;

procedure TCPCompiler.AddLinkLibraries(const ALibraries: array of string);
begin
  FZigBuild.AddLinkLibraries(ALibraries);
end;

{ TCPCompiler.AddLibraryPath }
procedure TCPCompiler.AddLibraryPath(const APath: string);
begin
  FZigBuild.AddLibraryPath(APath);
end;

procedure TCPCompiler.AddCopyDLL(const ADLLPath: string);
begin
  FZigBuild.AddCopyDLL(ADLLPath);
end;

procedure TCPCompiler.AddPostBuildCopy(const ASourceFile: string;
  const ADestDir: string);
begin
  FZigBuild.AddPostBuildCopy(ASourceFile, ADestDir);
end;

procedure TCPCompiler.AddPublishArtifact(const ADestDir: string);
begin
  FZigBuild.AddPublishArtifact(ADestDir);
end;

procedure TCPCompiler.SetAddVersionInfo(const AValue: Boolean);
begin
  FZigBuild.SetAddVersionInfo(AValue);
end;

procedure TCPCompiler.SetVIMajor(const AValue: Word);
begin
  FZigBuild.SetVIMajor(AValue);
end;

procedure TCPCompiler.SetVIMinor(const AValue: Word);
begin
  FZigBuild.SetVIMinor(AValue);
end;

procedure TCPCompiler.SetVIPatch(const AValue: Word);
begin
  FZigBuild.SetVIPatch(AValue);
end;

procedure TCPCompiler.SetVIProductName(const AValue: string);
begin
  FZigBuild.SetVIProductName(AValue);
end;

procedure TCPCompiler.SetVIDescription(const AValue: string);
begin
  FZigBuild.SetVIDescription(AValue);
end;

procedure TCPCompiler.SetVIFilename(const AValue: string);
begin
  FZigBuild.SetVIFilename(AValue);
end;

procedure TCPCompiler.SetVICompanyName(const AValue: string);
begin
  FZigBuild.SetVICompanyName(AValue);
end;

procedure TCPCompiler.SetVICopyright(const AValue: string);
begin
  FZigBuild.SetVICopyright(AValue);
end;

procedure TCPCompiler.SetExeIcon(const AValue: string);
begin
  FZigBuild.SetExeIcon(AValue);
end;

procedure TCPCompiler.AddBreakpoint(const AFileName: string;
  const ALineNumber: Integer);
begin
  FZigBuild.AddBreakpoint(AFileName, ALineNumber);
end;

procedure TCPCompiler.ClearBreakpoints();
begin
  FZigBuild.ClearBreakpoints();
end;

function TCPCompiler.GetLastExitCode(): DWORD;
begin
  Result := FZigBuild.GetLastExitCode();
end;

function TCPCompiler.GetOutputPath(): string;
begin
  Result := FZigBuild.GetOutputPath();
end;

function TCPCompiler.GetProjectName(): string;
begin
  Result := FZigBuild.GetProjectName();
end;

function TCPCompiler.GetBuildMode(): TCPBuildMode;
begin
  Result := FZigBuild.GetBuildMode();
end;

function TCPCompiler.GetOptimizeLevel(): TCPOptimizeLevel;
begin
  Result := FZigBuild.GetOptimizeLevel();
end;

function TCPCompiler.GetSubsystem(): TCPSubsystemType;
begin
  Result := FZigBuild.GetSubsystem();
end;

function TCPCompiler.GetTarget(): string;
begin
  Result := FZigBuild.GetTarget();
end;

function TCPCompiler.GetToolchainPath(): string;
begin
  Result := FZigBuild.GetToolchainPath();
end;

function TCPCompiler.GetOutputFilename(): string;
begin
  Result := FZigBuild.GetOutputFilename();
end;

function TCPCompiler.GetRunArguments(): string;
begin
  Result := FZigBuild.GetRunArguments();
end;

function TCPCompiler.GetZigPath(const AFilename: string): string;
begin
  Result := FZigBuild.GetZigPath(AFilename);
end;

function TCPCompiler.GetRuntimePath(const AFilename: string): string;
begin
  Result := FZigBuild.GetRuntimePath(AFilename);
end;

end.
