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
  CPaskal.Common,
  CPaskal.AST,
  CPaskal.Parser,
  CPaskal.Semantics,
  CPaskal.Codegen,
  CPaskal.ZigBuild;

const
  { CP_ERR_CMP_001 }
  CP_ERR_CMP_001 = 'CMP001';  // Source file not found

type

  { TCPCompiler }
  TCPCompiler = class(TBaseObject)
  protected
    FParser: TCPParser;
    FSemantics: TCPSemantics;
    FCodegen: TCPCodegen;
    FZigBuild: TCPZigBuild;
    FMasterAST: TCPMasterAST;
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

  FMasterAST := nil;
end;

destructor TCPCompiler.Destroy();
begin
  FMasterAST.Free();
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

procedure TCPCompiler.Compile(const ASourceFile: string;
  const AOutputPath: string; const AAutoRun: Boolean);
var
  LGeneratedPath: string;
  LProjectName: string;
  LSourceFile: string;
  LModule: TCPModuleNode;
  I: Integer;
begin
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

  // Phase 1: Parse
  Status('Parsing %s...', [TPath.GetFileName(LSourceFile)]);
  LModule := FParser.ParseModule(LSourceFile, FMasterAST);
  if LModule = nil then
    Exit;
  FMasterAST.AddModule(LModule);
  if FErrors.HasErrors() then
    Exit;

  // Phase 2: Semantic analysis
  Status('Analyzing...');
  FSemantics.Analyze(FMasterAST);
  if FErrors.HasErrors() then
    Exit;

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

  // Build
  FZigBuild.Process(AAutoRun);
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
