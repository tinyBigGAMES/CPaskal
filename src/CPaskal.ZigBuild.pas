{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.ZigBuild - Zig/Clang build driver (configuration + target model).

  Drives the bundled Zig/Clang toolchain. This unit models the full target
  triple (arch-os-abi carried as a single raw string), collects build
  configuration (mode, optimize, subsystem, source files, include/library
  paths, link libraries, defines/undefines, copy-DLLs), tracks post-build
  resource metadata (version info, icon), maintains a save/restore state
  stack for nested module builds, and exposes the Zig target-query and
  platform extension derivations used by later build stages.

  Unlike the reference, SetTarget never injects platform -D defines. Platform
  macros come from the compiler for the selected target, not from a define
  list maintained here.

  STAGE 1 of the unit: configuration and the target model only. No zig
  invocation, no file I/O, and no build.zig generation - those arrive in
  later stages that extend this same class.

  Dependencies: StdApp.Base, StdApp.Utils, Jupiter.Build.Targets
===============================================================================}

unit CPaskal.ZigBuild;

{$I StdApp.Defines.inc}

interface

uses
  WinAPI.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  StdApp.Base,
  StdApp.Utils,
  StdApp.Config,
  StdApp.Resources,
  CPaskal.ZigBuild.Targets;

const
  { Error codes }
  CP_ERR_ZIBUILD_NOOUTPUTPATH = 'ZB0001';
  CP_ERR_ZIGBUILD_NOSOURCES     = 'ZB0002';
  CP_ERR_ZIGBUILD_SAVEFAILED    = 'ZB0003';
  CP_ERR_ZIGBUILD_ZIGNOTFOUND  = 'ZB0004';
  CP_ERR_ZIGBUILD_BUILDFAILED   = 'ZB0005';
  LVM_ERR_ZIGBUILD_PUBLISHFAILED = 'ZB0010';

  { Warning codes }
  CP_ERR_ZIGBUILD_WRNCANNOTRUN   = 'ZB0006';
  CP_ERR_ZIGBUILD_WRNMANIFEST     = 'ZB0007';
  CP_ERR_ZIGBUILD_WRNICON         = 'ZB0008';
  CP_ERR_ZIGBUILD_WRNVERSIONINFO  = 'ZB0009';

  { Build constants }
  CP_BREAKPOINT_EXT        = '.bp';
  CP_RESOLVEPATH_BEHAVIOR  = 1;
  CP_DEFAULT_TOOLCHAIN_PATH = '$P:res';
  CP_DEFAULT_TARGET        = 'x86_64-windows-gnu';
  CP_DEFAULT_PROJECT_NAME  = 'output';

  { Language standard flags }
  // Sources are grouped by extension: .c compiles as C, everything else as
  // C++. Each group is emitted as its own addCSourceFiles block with its own
  // std flag, so C libraries (raylib, ...) and C++23 sources can coexist in
  // one artifact.
  //
  // The C group uses the GNU dialect, not strict ISO. Strict ISO suppresses
  // the POSIX feature-test macros, so glibc headers hide declarations such as
  // sigjmp_buf, and third-party C libraries fail to compile for reasons that
  // have nothing to do with their own source. Vendored libraries are fetched,
  // never edited, so the standard must accommodate them rather than the other
  // way round. Upstream C projects universally assume the GNU dialect - bdwgc
  // and raylib both do - and this is the standard their own build scripts use.
  //
  // The C++ group follows the same rule for the same reason. The runtime is
  // systems code that calls the platform directly, and strict ISO C++ hides
  // the same declarations from it that strict ISO C hid from the collector.
  CP_C_STD_FLAG            = '"-std=gnu23"';
  CP_CPP_STD_FLAG          = '"-std=gnu++23"';
  CP_C_SOURCE_EXT          = '.c';

  // Assembly is a third group, and it takes NO -std= flag of any kind.
  // A dialect flag on an assembler-with-cpp input makes clang define the
  // matching language macro: -std=gnu++23 defines __cplusplus, at which point
  // any header opening `extern "C" {` is fed to the assembler and fails with
  // "invalid register name". -std=gnu23 is wrong for the same reason, so
  // folding .S into the C group is not an option either.
  CP_ASM_SOURCE_EXT        = '.S';
  CP_LLVMIR_SOURCE_EXT     = '.ll';

type

  { TCPSourceLanguage }
  // Source files are partitioned by language, not by flag string. Each group
  // is emitted as its own addCSourceFiles block with its own flag list, so C
  // libraries, C++23 sources and assembly can coexist in one artifact.
  TCPSourceLanguage = (
    slC,
    slCpp,
    slAsm,
    slLLVMIR
  );

  { TCPBuildMode }
  TCPBuildMode = (
    bmExe,
    bmLib,
    bmDll
  );

  { TCPOptimizeLevel }
  TCPOptimizeLevel = (
    olDebug,
    olReleaseSafe,
    olReleaseFast,
    olReleaseSmall
  );

  { TCPSubsystemType }
  TCPSubsystemType = (
    stConsole,
    stGUI
  );

  { TCPBreakpointEntry }
  TCPBreakpointEntry = record
    FileName: string;
    LineNumber: Integer;
  end;

  { TCPBuildState }
  // Snapshot of scalar build settings for PushState/PopState. Target is a
  // raw triple string, matching the enhanced string-based target model.
  TCPBuildState = record
    BuildMode: TCPBuildMode;
    OptimizeLevel: TCPOptimizeLevel;
    Target: string;
    Subsystem: TCPSubsystemType;
    ProjectName: string;
    AddVersionInfo: Boolean;
    VIMajor: Word;
    VIMinor: Word;
    VIPatch: Word;
    VIProductName: string;
    VIDescription: string;
    VIFilename: string;
    VICompanyName: string;
    VICopyright: string;
    ExeIcon: string;
  end;

  { TCPZigBuild }
  TCPZigBuild = class(TBaseObject)
  private
    FOutputPath: string;
    FProjectName: string;
    FBuildMode: TCPBuildMode;
    FOptimizeLevel: TCPOptimizeLevel;
    FTarget: string;
    FSubsystem: TCPSubsystemType;
    FSourceFiles: TStringList;
    FIncludePaths: TStringList;
    FLibraryPaths: TStringList;
    FLinkLibraries: TStringList;
    FDefines: TStringList;
    FUndefines: TStringList;
    FCopyDLLs: TStringList;

    // Post-build file copies, one entry per copy, formatted
    // '<source>|<destination directory>'. The source '*' is a sentinel
    // meaning "this build's own artifact", resolved at copy time.
    FPostBuildCopies: TStringList;

    FOutput: TCallback<TCaptureConsoleCallback>;
    FLastExitCode: DWORD;
    FRawOutput: Boolean;
    FRunArguments: string;

    // Toolchain path + persisted build config (build.toml)
    FToolchainPath: string;
    FBuildConfig: TConfig;
    FBuildConfigPath: string;

    // Version info / post-build resources
    FAddVersionInfo: Boolean;
    FVIMajor: Word;
    FVIMinor: Word;
    FVIPatch: Word;
    FVIProductName: string;
    FVIDescription: string;
    FVIFilename: string;
    FVICompanyName: string;
    FVICopyright: string;
    FExeIcon: string;

    // Breakpoints
    FBreakpoints: TList<TCPBreakpointEntry>;

    // State stack for save/restore across module imports
    FStateStack: TStack<TCPBuildState>;

    function FindDefineIndex(const ADefineName: string): Integer;

    // Runs FPostBuildCopies after the artifact is fully built and stamped.
    // AArtifactPath is the resolved artifact, used to expand the '*' source
    // sentinel. Returns False if any copy could not be performed.
    function DoPostBuildCopies(const AArtifactPath: string): Boolean;

    function DoSplitTarget(const ATarget: string; out AArch: string;
      out AOS: string; out AAbi: string): Boolean;

    // build.zig generation helpers (decomposition of GenerateBuildZig)
    function MakeRelativePath(const ABasePath: string;
      const ATargetPath: string): string;
    function GetSourceLanguage(const ASourceFile: string): TCPSourceLanguage;
    procedure DoZigHeader(const ABuilder: TStringBuilder);
    procedure DoZigArtifact(const ABuilder: TStringBuilder;
      out AArtifactVar: string);
    procedure DoZigSourceGroup(const ABuilder: TStringBuilder;
      const AArtifactVar: string; const AFiles: TStringList;
      const AFlagsStr: string);
    procedure DoZigSources(const ABuilder: TStringBuilder;
      const AArtifactVar: string);

    // Diagnostics + post-build helpers
    function FilterOutputBuffer(const ABuffer: string): string;
    procedure HandleOutputLine(const ALine: string; const AUserData: Pointer);
    procedure ApplyPostBuildResources(const AExePath: string);

  public
    constructor Create(); override;
    destructor Destroy(); override;

    // Configuration
    procedure SetOutputPath(const APath: string);
    procedure SetProjectName(const AProjectName: string);
    procedure SetBuildMode(const ABuildMode: TCPBuildMode);
    procedure SetOptimizeLevel(const AOptimizeLevel: TCPOptimizeLevel);
    procedure SetSubsystem(const ASubsystem: TCPSubsystemType);
    procedure SetOutputCallback(const ACallback: TCaptureConsoleCallback;
      const AUserData: Pointer = nil);
    procedure SetRawOutput(const AValue: Boolean);

    // Command line handed to the artifact when it is run. Empty means no
    // arguments, which is the behaviour every caller had before this existed.
    procedure SetRunArguments(const AArguments: string);
    function GetRunArguments(): string;

    // Target model (raw triple string; no define injection)
    procedure SetTarget(const ATarget: string); overload;
    procedure SetTarget(const AArch: string; const AOS: string;
      const AAbi: string = ''); overload;
    function GetTarget(): string;
    function DoZigTargetQuery(): string;

    // Source files
    procedure AddSourceFile(const ASourceFile: string);
    procedure AddSourceFiles(const AFiles: array of string); overload;
    procedure AddSourceFiles(const ABasePath: string;
      const AFiles: array of string); overload;
    procedure RemoveSourceFile(const ASourceFile: string);
    procedure ClearSourceFiles();

    // Include paths
    procedure AddIncludePath(const APath: string);
    procedure RemoveIncludePath(const APath: string);
    procedure ClearIncludePaths();

    // Library paths
    procedure AddLibraryPath(const APath: string);
    procedure RemoveLibraryPath(const APath: string);
    procedure ClearLibraryPaths();

    // Link libraries
    procedure AddLinkLibrary(const ALibrary: string);
    procedure AddLinkLibraries(const ALibraries: array of string);
    procedure RemoveLinkLibrary(const ALibrary: string);
    procedure ClearLinkLibraries();

    // Defines (-DNAME or -DNAME=VALUE)
    procedure SetDefine(const ADefineName: string); overload;
    procedure SetDefine(const ADefineName: string; const AValue: string); overload;
    procedure SetDefines(const ADefineNames: array of string);
    procedure RemoveDefine(const ADefineName: string);
    procedure ClearDefines();
    function HasDefine(const ADefineName: string): Boolean;
    function GetDefines(): TStringList;

    // Undefines (-UNAME)
    procedure UnsetDefine(const ADefineName: string);
    procedure RemoveUndefine(const ADefineName: string);
    procedure ClearUndefines();
    function HasUndefine(const ADefineName: string): Boolean;
    function GetUndefines(): TStringList;

    // Copy DLLs (copied to exe output directory after build)
    procedure AddCopyDLL(const ADLLPath: string);
    procedure RemoveCopyDLL(const ADLLPath: string);
    procedure ClearCopyDLLs();

    // Post-build copies (performed after post-build resources are applied)
    //
    // These run LATER than the copy-DLL step above, and deliberately so. The
    // copy-DLL step brings dependency DLLs in before the artifact is stamped;
    // these publish finished output out. Publishing before ApplyPostBuildResources
    // would ship a copy that predates its own version info.
    procedure AddPostBuildCopy(const ASourceFile: string;
      const ADestDir: string);
    procedure AddPublishArtifact(const ADestDir: string);
    procedure ClearPostBuildCopies();

    // Clear all
    procedure Clear();

    // State stack (save/restore scalar settings across module imports)
    procedure PushState();
    procedure PopState();

    // Actions
    function LoadBuildFile(const AFilename: string): Boolean;
    function SaveBuildFile(): Boolean;
    function Process(const AAutoRun: Boolean = True): Boolean;
    function Run(): Boolean;
    function ClearCache(): Boolean;
    function ClearOutput(): Boolean;

    // Getters
    function GetLastExitCode(): DWORD;
    function GetOutputPath(): string;
    function GetProjectName(): string;
    function GetBuildMode(): TCPBuildMode;
    function GetOptimizeLevel(): TCPOptimizeLevel;
    function GetSubsystem(): TCPSubsystemType;
    function GetSourceFileCount(): Integer;
    function GetSourceFile(const AIndex: Integer): string;

    // Platform extension helpers (derived from the target triple)
    function GetExeExtension(): string;
    function GetDllExtension(): string;
    function GetLibExtension(): string;
    function GetLibPrefix(): string;
    function GetOutputFilename(): string;

    // Display names
    function GetTargetDisplayName(): string;
    function GetOptimizeLevelDisplayName(): string;
    function GetSubsystemDisplayName(): string;

    // build.zig generation
    function GetZigOptimizeString(): string;
    function BuildFlagsString(const ALanguage: TCPSourceLanguage): string;
    function GenerateBuildZig(): string;
    procedure ParseFlagsLine(const ALine: string);

    // Version info / post-build resources
    procedure SetAddVersionInfo(const AValue: Boolean);
    function GetAddVersionInfo(): Boolean;
    procedure SetVIMajor(const AValue: Word);
    function GetVIMajor(): Word;
    procedure SetVIMinor(const AValue: Word);
    function GetVIMinor(): Word;
    procedure SetVIPatch(const AValue: Word);
    function GetVIPatch(): Word;
    procedure SetVIProductName(const AValue: string);
    function GetVIProductName(): string;
    procedure SetVIDescription(const AValue: string);
    function GetVIDescription(): string;
    procedure SetVIFilename(const AValue: string);
    function GetVIFilename(): string;
    procedure SetVICompanyName(const AValue: string);
    function GetVICompanyName(): string;
    procedure SetVICopyright(const AValue: string);
    function GetVICopyright(): string;
    procedure SetExeIcon(const AValue: string);
    function GetExeIcon(): string;

    // Breakpoints
    procedure AddBreakpoint(const AFileName: string; const ALineNumber: Integer);
    procedure ClearBreakpoints();
    function GetBreakpoints(): TArray<TCPBreakpointEntry>;
    procedure WriteBreakpointsFile(const AExePath: string);

    // Toolchain paths
    procedure SetToolchainPath(const APath: string);
    function GetToolchainPath(): string;
    function GetZigPath(const AFilename: string = ''): string;
    function GetRuntimePath(const AFilename: string = ''): string;
    function GetLibsPath(const AFilename: string = ''): string;
    function GetAssetsPath(const AFilename: string = ''): string;

    // Centralized path resolution
    function ResolvePath(const AFilename: string;
      const ARelativePath: string;
      const ABasePath: string = '';
      const ABehavior: Integer = CP_RESOLVEPATH_BEHAVIOR): string;
  end;

implementation

{$R CPaskal.ResData.res}

{ TCPZigBuild }

constructor TCPZigBuild.Create();
begin
  inherited;

  FOutputPath := '';
  FProjectName := CP_DEFAULT_PROJECT_NAME;
  FBuildMode := bmExe;
  FOptimizeLevel := olDebug;
  FSubsystem := stConsole;
  FSourceFiles := TStringList.Create();
  FIncludePaths := TStringList.Create();
  FLibraryPaths := TStringList.Create();
  FLinkLibraries := TStringList.Create();
  FDefines := TStringList.Create();
  FUndefines := TStringList.Create();
  FCopyDLLs := TStringList.Create();
  FPostBuildCopies := TStringList.Create();
  FLastExitCode := 0;
  FRawOutput := False;
  FRunArguments := '';

  // Default target triple (raw string; no platform define injection)
  FTarget := CP_DEFAULT_TARGET;

  // Version info defaults
  FAddVersionInfo := False;
  FVIMajor := 0;
  FVIMinor := 0;
  FVIPatch := 0;
  FVIProductName := '';
  FVIDescription := '';
  FVIFilename := '';
  FVICompanyName := '';
  FVICopyright := '';
  FExeIcon := '';

  // Breakpoints + state stack
  FBreakpoints := TList<TCPBreakpointEntry>.Create();
  FStateStack := TStack<TCPBuildState>.Create();

  // Toolchain config: load build.toml next to the executable if present
  FBuildConfig := TConfig.Create();
  FBuildConfig.SetErrors(FErrors);
  FBuildConfigPath := TPath.Combine(
    TPath.GetDirectoryName(ParamStr(0)), 'build.toml');
  FToolchainPath := CP_DEFAULT_TOOLCHAIN_PATH;
  if TFile.Exists(FBuildConfigPath) then
  begin
    FBuildConfig.LoadFromFile(FBuildConfigPath);
    FToolchainPath := FBuildConfig.GetString('build.toolchain_path',
      CP_DEFAULT_TOOLCHAIN_PATH);
  end;

  // Resolve the toolchain path via TUtils.ResolvePath ($P: prefix supported)
  FToolchainPath := TUtils.ResolvePath(FToolchainPath);
end;

destructor TCPZigBuild.Destroy();
begin
  // Persist the toolchain path back to build.toml, then release the config
  if Assigned(FBuildConfig) then
  begin
    FBuildConfig.SetString('build.toolchain_path', FToolchainPath);
    FBuildConfig.SaveToFile(FBuildConfigPath);
  end;
  FreeAndNil(FBuildConfig);

  FreeAndNil(FStateStack);
  FreeAndNil(FBreakpoints);
  FreeAndNil(FPostBuildCopies);
  FreeAndNil(FCopyDLLs);
  FreeAndNil(FUndefines);
  FreeAndNil(FDefines);
  FreeAndNil(FLinkLibraries);
  FreeAndNil(FLibraryPaths);
  FreeAndNil(FIncludePaths);
  FreeAndNil(FSourceFiles);

  inherited;
end;

// Configuration

procedure TCPZigBuild.SetOutputPath(const APath: string);
begin
  FOutputPath := APath;
end;

procedure TCPZigBuild.SetProjectName(const AProjectName: string);
begin
  FProjectName := AProjectName;
end;

procedure TCPZigBuild.SetBuildMode(const ABuildMode: TCPBuildMode);
begin
  FBuildMode := ABuildMode;
end;

procedure TCPZigBuild.SetOptimizeLevel(const AOptimizeLevel: TCPOptimizeLevel);
begin
  FOptimizeLevel := AOptimizeLevel;
end;

procedure TCPZigBuild.SetSubsystem(const ASubsystem: TCPSubsystemType);
begin
  FSubsystem := ASubsystem;
end;

procedure TCPZigBuild.SetOutputCallback(const ACallback: TCaptureConsoleCallback;
  const AUserData: Pointer);
begin
  FOutput.Callback := ACallback;
  FOutput.UserData := AUserData;
end;

procedure TCPZigBuild.SetRawOutput(const AValue: Boolean);
begin
  FRawOutput := AValue;
end;

// Arguments passed to the artifact by Run(). Stored verbatim: the caller is
// responsible for quoting anything containing spaces, exactly as it would be
// when typing the command by hand.
procedure TCPZigBuild.SetRunArguments(const AArguments: string);
begin
  FRunArguments := AArguments;
end;

function TCPZigBuild.GetRunArguments(): string;
begin
  Result := FRunArguments;
end;

// Target model

procedure TCPZigBuild.SetTarget(const ATarget: string);
begin
  FTarget := ATarget;
end;

procedure TCPZigBuild.SetTarget(const AArch: string; const AOS: string;
  const AAbi: string);
var
  LTarget: string;
begin
  LTarget := AArch + '-' + AOS;
  if AAbi <> '' then
    LTarget := LTarget + '-' + AAbi;
  FTarget := LTarget;
end;

function TCPZigBuild.GetTarget(): string;
begin
  Result := FTarget;
end;

function TCPZigBuild.DoSplitTarget(const ATarget: string; out AArch: string;
  out AOS: string; out AAbi: string): Boolean;
var
  LParts: TArray<string>;
  LI: Integer;
begin
  AArch := '';
  AOS := '';
  AAbi := '';
  Result := False;

  LParts := ATarget.Split(['-']);
  if Length(LParts) < 2 then
    Exit;

  AArch := LParts[0];
  AOS := LParts[1];

  // Third and any further segments together form the ABI, rejoined with '-'
  if Length(LParts) >= 3 then
  begin
    AAbi := LParts[2];
    for LI := 3 to High(LParts) do
      AAbi := AAbi + '-' + LParts[LI];
  end;

  Result := True;
end;

function TCPZigBuild.DoZigTargetQuery(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  // Fall back to the default triple if the current target is malformed
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(CP_DEFAULT_TARGET, LArch, LOS, LAbi);

  Result := '.{ .cpu_arch = .' + LArch + ', .os_tag = .' + LOS;
  if LAbi <> '' then
    Result := Result + ', .abi = .' + LAbi;
  Result := Result + ' }';
end;

// Source files

procedure TCPZigBuild.AddSourceFile(const ASourceFile: string);
begin
  if (ASourceFile <> '') and (FSourceFiles.IndexOf(ASourceFile) < 0) then
    FSourceFiles.Add(ASourceFile);
end;

// Adds a list of source files as given. Each entry is passed through
// AddSourceFile, so empty entries and duplicates are skipped.
procedure TCPZigBuild.AddSourceFiles(const AFiles: array of string);
var
  LIndex: Integer;
begin
  for LIndex := Low(AFiles) to High(AFiles) do
    AddSourceFile(AFiles[LIndex]);
end;

// Adds a list of source files resolved against a common base path. This is
// the curated-manifest form: the caller states exactly which files belong to
// the build, which matters for source trees where only a subset compiles as
// its own translation unit.
procedure TCPZigBuild.AddSourceFiles(const ABasePath: string;
  const AFiles: array of string);
var
  LIndex: Integer;
  LSourceFile: string;
begin
  for LIndex := Low(AFiles) to High(AFiles) do
  begin
    // An empty base path passes the entry through unchanged rather than
    // letting TPath.Combine decide what to do with it.
    if ABasePath = '' then
      LSourceFile := AFiles[LIndex]
    else
      LSourceFile := TPath.Combine(ABasePath, AFiles[LIndex]);

    AddSourceFile(LSourceFile);
  end;
end;

procedure TCPZigBuild.RemoveSourceFile(const ASourceFile: string);
var
  LIndex: Integer;
begin
  LIndex := FSourceFiles.IndexOf(ASourceFile);
  if LIndex >= 0 then
    FSourceFiles.Delete(LIndex);
end;

procedure TCPZigBuild.ClearSourceFiles();
begin
  FSourceFiles.Clear();
end;

// Include paths

procedure TCPZigBuild.AddIncludePath(const APath: string);
begin
  if (APath <> '') and (FIncludePaths.IndexOf(APath) < 0) then
    FIncludePaths.Add(APath);
end;

procedure TCPZigBuild.RemoveIncludePath(const APath: string);
var
  LIndex: Integer;
begin
  LIndex := FIncludePaths.IndexOf(APath);
  if LIndex >= 0 then
    FIncludePaths.Delete(LIndex);
end;

procedure TCPZigBuild.ClearIncludePaths();
begin
  FIncludePaths.Clear();
end;

// Library paths

procedure TCPZigBuild.AddLibraryPath(const APath: string);
begin
  if (APath <> '') and (FLibraryPaths.IndexOf(APath) < 0) then
    FLibraryPaths.Add(APath);
end;

procedure TCPZigBuild.RemoveLibraryPath(const APath: string);
var
  LIndex: Integer;
begin
  LIndex := FLibraryPaths.IndexOf(APath);
  if LIndex >= 0 then
    FLibraryPaths.Delete(LIndex);
end;

procedure TCPZigBuild.ClearLibraryPaths();
begin
  FLibraryPaths.Clear();
end;

// Link libraries

procedure TCPZigBuild.AddLinkLibrary(const ALibrary: string);
begin
  if (ALibrary <> '') and (FLinkLibraries.IndexOf(ALibrary) < 0) then
    FLinkLibraries.Add(ALibrary);
end;

// Adds a list of link libraries. Each entry is passed through
// AddLinkLibrary, so empty entries and duplicates are skipped.
procedure TCPZigBuild.AddLinkLibraries(const ALibraries: array of string);
var
  LIndex: Integer;
begin
  for LIndex := Low(ALibraries) to High(ALibraries) do
    AddLinkLibrary(ALibraries[LIndex]);
end;

procedure TCPZigBuild.RemoveLinkLibrary(const ALibrary: string);
var
  LIndex: Integer;
begin
  LIndex := FLinkLibraries.IndexOf(ALibrary);
  if LIndex >= 0 then
    FLinkLibraries.Delete(LIndex);
end;

procedure TCPZigBuild.ClearLinkLibraries();
begin
  FLinkLibraries.Clear();
end;

// Defines

function TCPZigBuild.FindDefineIndex(const ADefineName: string): Integer;
var
  LI: Integer;
  LEntry: string;
  LEqualPos: Integer;
  LName: string;
begin
  Result := -1;
  for LI := 0 to FDefines.Count - 1 do
  begin
    LEntry := FDefines[LI];
    LEqualPos := Pos('=', LEntry);
    if LEqualPos > 0 then
      LName := Copy(LEntry, 1, LEqualPos - 1)
    else
      LName := LEntry;

    if SameText(LName, ADefineName) then
    begin
      Result := LI;
      Exit;
    end;
  end;
end;

procedure TCPZigBuild.SetDefine(const ADefineName: string);
var
  LIndex: Integer;
begin
  if ADefineName = '' then
    Exit;

  // Update in place if already present, otherwise append
  LIndex := FindDefineIndex(ADefineName);
  if LIndex >= 0 then
    FDefines[LIndex] := ADefineName
  else
    FDefines.Add(ADefineName);
end;

procedure TCPZigBuild.SetDefine(const ADefineName: string; const AValue: string);
var
  LIndex: Integer;
  LEntry: string;
begin
  if ADefineName = '' then
    Exit;

  LEntry := ADefineName + '=' + AValue;

  // Update in place if already present, otherwise append
  LIndex := FindDefineIndex(ADefineName);
  if LIndex >= 0 then
    FDefines[LIndex] := LEntry
  else
    FDefines.Add(LEntry);
end;

// Sets a list of value-less defines. Each entry is passed through the
// single-argument SetDefine overload.
procedure TCPZigBuild.SetDefines(const ADefineNames: array of string);
var
  LIndex: Integer;
begin
  for LIndex := Low(ADefineNames) to High(ADefineNames) do
    SetDefine(ADefineNames[LIndex]);
end;

procedure TCPZigBuild.RemoveDefine(const ADefineName: string);
var
  LIndex: Integer;
begin
  LIndex := FindDefineIndex(ADefineName);
  if LIndex >= 0 then
    FDefines.Delete(LIndex);
end;

procedure TCPZigBuild.ClearDefines();
begin
  FDefines.Clear();
end;

function TCPZigBuild.HasDefine(const ADefineName: string): Boolean;
begin
  Result := FindDefineIndex(ADefineName) >= 0;
end;

function TCPZigBuild.GetDefines(): TStringList;
begin
  Result := FDefines;
end;

// Undefines

procedure TCPZigBuild.UnsetDefine(const ADefineName: string);
begin
  if ADefineName = '' then
    Exit;

  if FUndefines.IndexOf(ADefineName) < 0 then
    FUndefines.Add(ADefineName);
end;

procedure TCPZigBuild.RemoveUndefine(const ADefineName: string);
var
  LIndex: Integer;
begin
  LIndex := FUndefines.IndexOf(ADefineName);
  if LIndex >= 0 then
    FUndefines.Delete(LIndex);
end;

procedure TCPZigBuild.ClearUndefines();
begin
  FUndefines.Clear();
end;

function TCPZigBuild.HasUndefine(const ADefineName: string): Boolean;
begin
  Result := FUndefines.IndexOf(ADefineName) >= 0;
end;

function TCPZigBuild.GetUndefines(): TStringList;
begin
  Result := FUndefines;
end;

// Copy DLLs

procedure TCPZigBuild.AddCopyDLL(const ADLLPath: string);
begin
  if (ADLLPath <> '') and (FCopyDLLs.IndexOf(ADLLPath) < 0) then
    FCopyDLLs.Add(ADLLPath);
end;

procedure TCPZigBuild.RemoveCopyDLL(const ADLLPath: string);
var
  LIndex: Integer;
begin
  LIndex := FCopyDLLs.IndexOf(ADLLPath);
  if LIndex >= 0 then
    FCopyDLLs.Delete(LIndex);
end;

procedure TCPZigBuild.ClearCopyDLLs();
begin
  FCopyDLLs.Clear();
end;

// Post-build copies

procedure TCPZigBuild.AddPostBuildCopy(const ASourceFile: string;
  const ADestDir: string);
var
  LEntry: string;
begin
  if ASourceFile = '' then
    Exit;

  // The pair is stored in one line because the two halves are only ever
  // meaningful together. A separate list per half would let them drift.
  LEntry := ASourceFile + '|' + ADestDir;

  if FPostBuildCopies.IndexOf(LEntry) < 0 then
    FPostBuildCopies.Add(LEntry);
end;

procedure TCPZigBuild.AddPublishArtifact(const ADestDir: string);
begin
  // '*' is expanded at copy time to the artifact path Process already
  // resolved. Callers never write 'zig-out\bin'; that layout is private to
  // the build layer and must stay that way.
  AddPostBuildCopy('*', ADestDir);
end;

procedure TCPZigBuild.ClearPostBuildCopies();
begin
  FPostBuildCopies.Clear();
end;

function TCPZigBuild.DoPostBuildCopies(const AArtifactPath: string): Boolean;
var
  LI: Integer;
  LEntry: string;
  LBarPos: Integer;
  LSource: string;
  LDestDir: string;
  LSrcPath: string;
  LDestPath: string;
begin
  Result := True;

  for LI := 0 to FPostBuildCopies.Count - 1 do
  begin
    LEntry := FPostBuildCopies[LI];

    LBarPos := Pos('|', LEntry);
    if LBarPos <= 0 then
      Continue;

    LSource := Copy(LEntry, 1, LBarPos - 1);
    LDestDir := Copy(LEntry, LBarPos + 1, Length(LEntry) - LBarPos);

    // Expand the artifact sentinel. AArtifactPath is already resolved by
    // Process, so no path layout is re-derived here.
    if LSource = '*' then
      LSrcPath := AArtifactPath
    else
      LSrcPath := ResolvePath('', LSource);

    // An empty destination means the executable directory. ResolvePath with
    // an empty relative path and the default behavior yields exactly that.
    LDestDir := ResolvePath('', LDestDir);

    // Nothing to do if the file is already where it is wanted.
    if SameText(TPath.GetFullPath(TPath.GetDirectoryName(LSrcPath)),
      TPath.GetFullPath(LDestDir)) then
      Continue;

    // A missing source is an ERROR, not a warning. If our own artifact is
    // not where the build just said it was, the build did not do what it
    // claimed and reporting green would be a false pass.
    if not TFile.Exists(LSrcPath) then
    begin
      Result := False;
      if Assigned(FErrors) then
        FErrors.Add(esError, LVM_ERR_ZIGBUILD_PUBLISHFAILED,
          RSZigBuildPublishFailed, [LSrcPath]);
      Continue;
    end;

    LDestPath := TPath.Combine(LDestDir, TPath.GetFileName(LSrcPath));

    try
      TUtils.CreateDirInPath(LDestDir);
      Status(RSZigBuildPublishing, [TPath.GetFileName(LSrcPath),
        TUtils.NormalizePath(LDestDir)]);
      TFile.Copy(LSrcPath, LDestPath, True);
    except
      on E: Exception do
      begin
        Result := False;
        if Assigned(FErrors) then
          FErrors.Add(esError, LVM_ERR_ZIGBUILD_PUBLISHFAILED,
            RSZigBuildPublishError, [LDestPath, E.Message]);
      end;
    end;
  end;
end;

// Clear all

procedure TCPZigBuild.Clear();
begin
  ClearSourceFiles();
  ClearIncludePaths();
  ClearLibraryPaths();
  ClearLinkLibraries();
  ClearDefines();
  ClearUndefines();
  ClearCopyDLLs();
  ClearPostBuildCopies();
  ClearBreakpoints();
  FProjectName := CP_DEFAULT_PROJECT_NAME;
  FBuildMode := bmExe;
  FOptimizeLevel := olDebug;
  FTarget := CP_DEFAULT_TARGET;
  FSubsystem := stConsole;
  FLastExitCode := 0;

  // Reset version info
  FAddVersionInfo := False;
  FVIMajor := 0;
  FVIMinor := 0;
  FVIPatch := 0;
  FVIProductName := '';
  FVIDescription := '';
  FVIFilename := '';
  FVICompanyName := '';
  FVICopyright := '';
  FExeIcon := '';
end;

// State stack

procedure TCPZigBuild.PushState();
var
  LState: TCPBuildState;
begin
  LState.BuildMode := FBuildMode;
  LState.OptimizeLevel := FOptimizeLevel;
  LState.Target := FTarget;
  LState.Subsystem := FSubsystem;
  LState.ProjectName := FProjectName;
  LState.AddVersionInfo := FAddVersionInfo;
  LState.VIMajor := FVIMajor;
  LState.VIMinor := FVIMinor;
  LState.VIPatch := FVIPatch;
  LState.VIProductName := FVIProductName;
  LState.VIDescription := FVIDescription;
  LState.VIFilename := FVIFilename;
  LState.VICompanyName := FVICompanyName;
  LState.VICopyright := FVICopyright;
  LState.ExeIcon := FExeIcon;
  FStateStack.Push(LState);
end;

procedure TCPZigBuild.PopState();
var
  LState: TCPBuildState;
begin
  if FStateStack.Count = 0 then
    Exit;

  LState := FStateStack.Pop();
  FBuildMode := LState.BuildMode;
  FOptimizeLevel := LState.OptimizeLevel;
  FTarget := LState.Target;
  FSubsystem := LState.Subsystem;
  FProjectName := LState.ProjectName;
  FAddVersionInfo := LState.AddVersionInfo;
  FVIMajor := LState.VIMajor;
  FVIMinor := LState.VIMinor;
  FVIPatch := LState.VIPatch;
  FVIProductName := LState.VIProductName;
  FVIDescription := LState.VIDescription;
  FVIFilename := LState.VIFilename;
  FVICompanyName := LState.VICompanyName;
  FVICopyright := LState.VICopyright;
  FExeIcon := LState.ExeIcon;
end;

// Getters

function TCPZigBuild.GetLastExitCode(): DWORD;
begin
  Result := FLastExitCode;
end;

function TCPZigBuild.GetOutputPath(): string;
begin
  Result := FOutputPath;
end;

function TCPZigBuild.GetProjectName(): string;
begin
  Result := FProjectName;
end;

function TCPZigBuild.GetBuildMode(): TCPBuildMode;
begin
  Result := FBuildMode;
end;

function TCPZigBuild.GetOptimizeLevel(): TCPOptimizeLevel;
begin
  Result := FOptimizeLevel;
end;

function TCPZigBuild.GetSubsystem(): TCPSubsystemType;
begin
  Result := FSubsystem;
end;

function TCPZigBuild.GetSourceFileCount(): Integer;
begin
  Result := FSourceFiles.Count;
end;

function TCPZigBuild.GetSourceFile(const AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FSourceFiles.Count) then
    Result := FSourceFiles[AIndex]
  else
    Result := '';
end;

// Platform extension helpers

function TCPZigBuild.GetExeExtension(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(CP_DEFAULT_TARGET, LArch, LOS, LAbi);

  if SameText(LArch, ARCH_WASM32) or SameText(LArch, ARCH_WASM64) then
    Result := '.wasm'
  else if SameText(LOS, OS_WINDOWS) then
    Result := '.exe'
  else if SameText(LOS, OS_UEFI) then
    Result := '.efi'
  else
    Result := '';
end;

function TCPZigBuild.GetDllExtension(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(CP_DEFAULT_TARGET, LArch, LOS, LAbi);

  if SameText(LOS, OS_WINDOWS) then
    Result := '.dll'
  else if SameText(LOS, OS_MACOS) or SameText(LOS, OS_IOS)
       or SameText(LOS, OS_TVOS) or SameText(LOS, OS_WATCHOS)
       or SameText(LOS, OS_VISIONOS) or SameText(LOS, OS_DRIVERKIT)
       or SameText(LOS, OS_MACCATALYST) then
    Result := '.dylib'
  else if SameText(LArch, ARCH_WASM32) or SameText(LArch, ARCH_WASM64) then
    Result := '.wasm'
  else
    Result := '.so';
end;

function TCPZigBuild.GetLibExtension(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(CP_DEFAULT_TARGET, LArch, LOS, LAbi);

  if SameText(LOS, OS_WINDOWS) then
    Result := '.lib'
  else
    Result := '.a';
end;

// Unix toolchains prefix library artifacts with "lib" - libfoo.so, libfoo.a,
// libfoo.dylib. Windows does not, and neither does wasm. The prefix belongs
// to library build modes only; executables never take it.
function TCPZigBuild.GetLibPrefix(): string;
var
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(CP_DEFAULT_TARGET, LArch, LOS, LAbi);

  if SameText(LOS, OS_WINDOWS) then
    Result := ''
  else if SameText(LArch, ARCH_WASM32) or SameText(LArch, ARCH_WASM64) then
    Result := ''
  else
    Result := 'lib';
end;

function TCPZigBuild.GetOutputFilename(): string;
var
  LPrefix: string;
  LExtension: string;
begin
  LPrefix := '';

  case FBuildMode of
    bmExe:
      LExtension := GetExeExtension();
    bmLib:
      begin
        LPrefix := GetLibPrefix();
        LExtension := GetLibExtension();
      end;
    bmDll:
      begin
        LPrefix := GetLibPrefix();
        LExtension := GetDllExtension();
      end;
  else
    LExtension := GetExeExtension();
  end;

  Result := LPrefix + FProjectName + LExtension;
end;

// Display names

function TCPZigBuild.GetTargetDisplayName(): string;
begin
  if FTarget = '' then
    Result := 'native'
  else
    Result := FTarget;
end;

function TCPZigBuild.GetOptimizeLevelDisplayName(): string;
begin
  case FOptimizeLevel of
    olDebug:
      Result := 'Debug';
    olReleaseSafe:
      Result := 'ReleaseSafe';
    olReleaseFast:
      Result := 'ReleaseFast';
    olReleaseSmall:
      Result := 'ReleaseSmall';
  else
    Result := 'Unknown';
  end;
end;

function TCPZigBuild.GetSubsystemDisplayName(): string;
begin
  if FSubsystem = stGUI then
    Result := 'GUI'
  else
    Result := 'Console';
end;

// build.zig generation

function TCPZigBuild.GetZigOptimizeString(): string;
begin
  case FOptimizeLevel of
    olDebug:
      Result := '.Debug';
    olReleaseSafe:
      Result := '.ReleaseSafe';
    olReleaseFast:
      Result := '.ReleaseFast';
    olReleaseSmall:
      Result := '.ReleaseSmall';
  else
    Result := '.Debug';
  end;
end;

function TCPZigBuild.BuildFlagsString(const ALanguage: TCPSourceLanguage): string;
var
  LFlags: TStringList;
  LI: Integer;
  LEntry: string;
  LMaxErrors: Integer;
begin
  LFlags := TStringList.Create();
  try
    // Language standard for this group. Assembly gets none: a dialect flag on
    // an assembler-with-cpp input defines the corresponding language macro,
    // and a defined __cplusplus turns every `extern "C" {` in an included
    // header into an assembler syntax error.
    if ALanguage = slCpp then
      LFlags.Add(CP_CPP_STD_FLAG)
    else if ALanguage = slC then
      LFlags.Add(CP_C_STD_FLAG);

    // C++-only flags
    if ALanguage = slCpp then
    begin
      LFlags.Add('"-fexceptions"');
      LFlags.Add('"-frtti"');
      LFlags.Add('"-fexperimental-library"');
    end;

    // Compiler codegen and diagnostic flags. These describe how to compile a
    // translation unit, so they apply to the C and C++ groups only - none of
    // them mean anything when assembling a .S.
    if (ALanguage <> slAsm) and (ALanguage <> slLLVMIR) then
    begin
      // Required for hardware exception handling
      LFlags.Add('"-fno-sanitize=undefined"');
      // Suppress warning about ((a == b)) in if statements
      LFlags.Add('"-Wno-parentheses-equality"');
      LFlags.Add('"-fdeclspec"');
      LFlags.Add('"-fms-extensions"');
      // Required for debugger stack unwinding via [RBP+8]
      LFlags.Add('"-fno-omit-frame-pointer"');

      // Hide symbols by default in DLLs to prevent runtime symbol conflicts
      if FBuildMode = bmDll then
        LFlags.Add('"-fvisibility=hidden"');
    end;

    // Suppress Zig-injected flags like -fno-rtlib-defaultlib. Every group
    // needs this, assembly included.
    LFlags.Add('"-Wno-unused-command-line-argument"');

    // Add defines (-DNAME or -DNAME=VALUE)
    for LI := 0 to FDefines.Count - 1 do
    begin
      LEntry := FDefines[LI];
      LFlags.Add('"-D' + LEntry + '"');
    end;

    // Add undefines (-UNAME)
    for LI := 0 to FUndefines.Count - 1 do
    begin
      LEntry := FUndefines[LI];
      LFlags.Add('"-U' + LEntry + '"');
    end;

    // Error limit (default to 1); honor the shared error budget when set
    LMaxErrors := 1;
    if (FErrors <> nil) and (FErrors.GetMaxErrors() > 0) then
      LMaxErrors := FErrors.GetMaxErrors();
    LFlags.Add(Format('"-ferror-limit=%d"', [LMaxErrors]));

    // Join into a single comma-separated flag list
    Result := '';
    for LI := 0 to LFlags.Count - 1 do
    begin
      if LI > 0 then
        Result := Result + ', ';
      Result := Result + LFlags[LI];
    end;
  finally
    LFlags.Free();
  end;
end;

function TCPZigBuild.MakeRelativePath(const ABasePath: string;
  const ATargetPath: string): string;
var
  LBase: string;
  LTarget: string;
  LBaseParts: TArray<string>;
  LTargetParts: TArray<string>;
  LCommonCount: Integer;
  LIdx: Integer;
  LRelativeParts: TList<string>;
begin
  // Resolve both to absolute, forward-slash paths for a stable comparison
  LBase := TPath.GetFullPath(ABasePath).Replace('\', '/');
  LTarget := TPath.GetFullPath(ATargetPath).Replace('\', '/');

  if SameText(LBase, LTarget) then
    Exit('.');

  LBaseParts := LBase.Split(['/']);
  LTargetParts := LTarget.Split(['/']);

  // Count the shared leading path segments
  LCommonCount := 0;
  while (LCommonCount < Length(LBaseParts)) and
        (LCommonCount < Length(LTargetParts)) and
        SameText(LBaseParts[LCommonCount], LTargetParts[LCommonCount]) do
    Inc(LCommonCount);

  LRelativeParts := TList<string>.Create();
  try
    // One '..' for each remaining base segment, then the target remainder
    for LIdx := LCommonCount to High(LBaseParts) do
      LRelativeParts.Add('..');

    for LIdx := LCommonCount to High(LTargetParts) do
      LRelativeParts.Add(LTargetParts[LIdx]);

    Result := string.Join('/', LRelativeParts.ToArray());
  finally
    LRelativeParts.Free();
  end;
end;

function TCPZigBuild.GetSourceLanguage(const ASourceFile: string): TCPSourceLanguage;
var
  LExtension: string;
begin
  // .S is assembly with the C preprocessor. .s (lowercase) is plain assembly;
  // both belong in the same group, because clang decides whether to
  // preprocess from the literal file name, not from anything passed here.
  //
  // Only a bare .c compiles as C. Everything else (.cpp/.cc/.cxx) is C++.
  LExtension := TPath.GetExtension(ASourceFile);

  if SameText(LExtension, CP_ASM_SOURCE_EXT) then
    Result := slAsm
  else if SameText(LExtension, CP_LLVMIR_SOURCE_EXT) then
    Result := slLLVMIR
  else if SameText(LExtension, CP_C_SOURCE_EXT) then
    Result := slC
  else
    Result := slCpp;
end;

procedure TCPZigBuild.DoZigHeader(const ABuilder: TStringBuilder);
begin
  ABuilder.AppendLine('const std = @import("std");');
  ABuilder.AppendLine();
  ABuilder.AppendLine('pub fn build(b: *std.Build) void {');

  // Explicit target query derived from the raw triple string
  ABuilder.AppendLine('    const target = b.resolveTargetQuery(' +
    DoZigTargetQuery() + ');');
  ABuilder.AppendLine('    const optimize: std.builtin.OptimizeMode = ' +
    GetZigOptimizeString() + ';');
  ABuilder.AppendLine();
end;

procedure TCPZigBuild.DoZigArtifact(const ABuilder: TStringBuilder;
  out AArtifactVar: string);
var
  LLinkage: string;
begin
  // Executable vs library declaration
  if FBuildMode = bmExe then
  begin
    AArtifactVar := 'exe';
    ABuilder.AppendLine('    const exe = b.addExecutable(.{');
  end
  else
  begin
    AArtifactVar := 'lib';
    ABuilder.AppendLine('    const lib = b.addLibrary(.{');
    if FBuildMode = bmLib then
      LLinkage := '.static'
    else
      LLinkage := '.dynamic';
    ABuilder.AppendLine('        .linkage = ' + LLinkage + ',');
  end;

  // Name and root module
  ABuilder.AppendLine('        .name = "' + FProjectName + '",');
  ABuilder.AppendLine('        .root_module = b.createModule(.{');
  ABuilder.AppendLine('            .target = target,');
  ABuilder.AppendLine('            .optimize = optimize,');
  ABuilder.AppendLine('            .link_libc = true,');
  ABuilder.AppendLine('            .link_libcpp = true,');
  ABuilder.AppendLine('        }),');
  ABuilder.AppendLine('    });');

  // GUI subsystem: suppress the console window on Windows (executables only)
  if (FBuildMode = bmExe) and (FSubsystem = stGUI) then
  begin
    ABuilder.AppendLine();
    ABuilder.AppendLine('    // GUI subsystem: no console window');
    ABuilder.AppendLine('    if (target.result.os.tag == .windows) {');
    ABuilder.AppendLine('        exe.subsystem = .windows;');
    ABuilder.AppendLine('    }');
  end;

  ABuilder.AppendLine();
end;

procedure TCPZigBuild.DoZigSourceGroup(const ABuilder: TStringBuilder;
  const AArtifactVar: string; const AFiles: TStringList;
  const AFlagsStr: string);
var
  LI: Integer;
  LSourcePath: string;
begin
  if AFiles.Count = 0 then
    Exit;

  ABuilder.AppendLine('    ' + AArtifactVar +
    '.root_module.addCSourceFiles(.{');
  ABuilder.AppendLine('        .files = &.{');

  for LI := 0 to AFiles.Count - 1 do
  begin
    LSourcePath := MakeRelativePath(FOutputPath, AFiles[LI]);
    ABuilder.Append('            "' + LSourcePath + '"');
    if LI < AFiles.Count - 1 then
      ABuilder.AppendLine(',')
    else
      ABuilder.AppendLine();
  end;

  ABuilder.AppendLine('        },');
  ABuilder.AppendLine('        .flags = &.{ ' + AFlagsStr + ' },');
  ABuilder.AppendLine('    });');
end;

procedure TCPZigBuild.DoZigSources(const ABuilder: TStringBuilder;
  const AArtifactVar: string);
var
  LI: Integer;
  LArch: string;
  LOS: string;
  LAbi: string;
  LCFiles: TStringList;
  LCppFiles: TStringList;
  LAsmFiles: TStringList;
  LLLFiles: TStringList;
begin
  // Include paths (relative to the output directory)
  for LI := 0 to FIncludePaths.Count - 1 do
    ABuilder.AppendLine('    ' + AArtifactVar +
      '.root_module.addIncludePath(b.path("' +
      MakeRelativePath(FOutputPath, FIncludePaths[LI]) + '"));');

  // Library paths (relative to the output directory)
  for LI := 0 to FLibraryPaths.Count - 1 do
    ABuilder.AppendLine('    ' + AArtifactVar +
      '.root_module.addLibraryPath(b.path("' +
      MakeRelativePath(FOutputPath, FLibraryPaths[LI]) + '"));');

  // On Linux (executables only), add rpath $ORIGIN so the binary finds .so
  // files in its own directory
  if FBuildMode = bmExe then
  begin
    if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
      DoSplitTarget(CP_DEFAULT_TARGET, LArch, LOS, LAbi);
    if SameText(LOS, OS_LINUX) then
      ABuilder.AppendLine('    ' + AArtifactVar +
        '.root_module.addRPathSpecial("$ORIGIN");');
  end;

  // Link libraries
  for LI := 0 to FLinkLibraries.Count - 1 do
    ABuilder.AppendLine('    ' + AArtifactVar +
      '.root_module.linkSystemLibrary("' + FLinkLibraries[LI] + '", .{});');

  // Source files, partitioned by language. Each group gets its own
  // addCSourceFiles block with its own flag list, so C libraries, C++23
  // sources and assembly can live in one artifact. A project with only .cpp
  // sources emits exactly one C++ group, as before. Empty groups emit
  // nothing - DoZigSourceGroup returns early.
  if FSourceFiles.Count > 0 then
  begin
    LCFiles := TStringList.Create();
    try
      LCppFiles := TStringList.Create();
      try
        LAsmFiles := TStringList.Create();
        try
          LLLFiles := TStringList.Create();
          try
            for LI := 0 to FSourceFiles.Count - 1 do
            begin
              case GetSourceLanguage(FSourceFiles[LI]) of
                slC:
                  LCFiles.Add(FSourceFiles[LI]);
                slAsm:
                  LAsmFiles.Add(FSourceFiles[LI]);
                slLLVMIR:
                  LLLFiles.Add(FSourceFiles[LI]);
              else
                LCppFiles.Add(FSourceFiles[LI]);
              end;
            end;

            DoZigSourceGroup(ABuilder, AArtifactVar, LCppFiles,
              BuildFlagsString(slCpp));
            DoZigSourceGroup(ABuilder, AArtifactVar, LCFiles,
              BuildFlagsString(slC));
            DoZigSourceGroup(ABuilder, AArtifactVar, LAsmFiles,
              BuildFlagsString(slAsm));
            DoZigSourceGroup(ABuilder, AArtifactVar, LLLFiles,
              BuildFlagsString(slLLVMIR));
          finally
            LLLFiles.Free();
          end;
        finally
          LAsmFiles.Free();
        end;
      finally
        LCppFiles.Free();
      end;
    finally
      LCFiles.Free();
    end;
  end;

  ABuilder.AppendLine();

  // Dynamic libraries install beside the executable, not into zig-out/lib.
  // Zig's default splits them - DLLs to bin on Windows, shared objects to lib
  // everywhere else - which would leave a launcher unable to find its runtime
  // by the same rule on every platform. Forcing bin makes the deployed shape
  // identical across targets. Static libraries keep the default: they are a
  // link-time input and are never loaded at run time.
  if FBuildMode = bmDll then
  begin
    ABuilder.AppendLine('    b.getInstallStep().dependOn(&b.addInstallArtifact(' +
      AArtifactVar + ', .{');
    ABuilder.AppendLine('        .dest_dir = .{ .override = .bin },');
    ABuilder.AppendLine('    }).step);');
  end
  else
    ABuilder.AppendLine('    b.installArtifact(' + AArtifactVar + ');');
end;

function TCPZigBuild.GenerateBuildZig(): string;
var
  LBuilder: TStringBuilder;
  LArtifactVar: string;
begin
  LBuilder := TStringBuilder.Create();
  try
    DoZigHeader(LBuilder);
    DoZigArtifact(LBuilder, LArtifactVar);
    DoZigSources(LBuilder, LArtifactVar);

    LBuilder.AppendLine('}');

    Result := LBuilder.ToString();
  finally
    LBuilder.Free();
  end;
end;

procedure TCPZigBuild.ParseFlagsLine(const ALine: string);
var
  LStart: Integer;
  LEnd: Integer;
  LFlag: string;
  LDefineName: string;
  LEqualPos: Integer;
begin
  // Parse flags from a line like:
  //   .flags = &.{ "-std=gnu++23", "-DFOO", "-DBAR=1", "-UBAZ" },
  LStart := 1;
  while LStart <= Length(ALine) do
  begin
    // Find the start of the next quoted flag
    LStart := Pos('"-', ALine, LStart);
    if LStart = 0 then
      Break;

    // Find its closing quote
    LEnd := Pos('"', ALine, LStart + 1);
    if LEnd = 0 then
      Break;

    // Extract the flag text without the surrounding quotes
    LFlag := Copy(ALine, LStart + 1, LEnd - LStart - 1);

    // Reconstruct defines (-D) and undefines (-U); ignore other flags
    if LFlag.StartsWith('-D') then
    begin
      LDefineName := Copy(LFlag, 3, Length(LFlag) - 2);
      // Skip the standard language-version flag
      if not LDefineName.StartsWith('std=') then
      begin
        LEqualPos := Pos('=', LDefineName);
        if LEqualPos > 0 then
          SetDefine(Copy(LDefineName, 1, LEqualPos - 1),
            Copy(LDefineName, LEqualPos + 1, Length(LDefineName)))
        else
          SetDefine(LDefineName);
      end;
    end
    else if LFlag.StartsWith('-U') then
    begin
      LDefineName := Copy(LFlag, 3, Length(LFlag) - 2);
      UnsetDefine(LDefineName);
    end;

    LStart := LEnd + 1;
  end;
end;

// Diagnostics

function TCPZigBuild.FilterOutputBuffer(const ABuffer: string): string;
var
  LCleanLine: string;
  LFilePath: string;
  LLineNum: Integer;
  LColNum: Integer;
  LSeverity: string;
  LMessage: string;
  LErrorSeverity: TErrorSeverity;

  function TryParseCompilerMessage(const ALine: string; out AFilePath: string;
    out ALineNum: Integer; out AColNum: Integer; out ASeverity: string;
    out AMessage: string): Boolean;
  var
    LPos1: Integer;
    LPos2: Integer;
    LPos3: Integer;
    LLineStr: string;
    LColStr: string;
    LSevStr: string;
  begin
    Result := False;

    // Pattern: filepath:line:col: severity: message
    // Skip the drive-letter colon on Windows paths (e.g. C:\...)
    if (Length(ALine) > 2) and (ALine[2] = ':') then
      LPos1 := ALine.IndexOf(':', 2)
    else
      LPos1 := ALine.IndexOf(':');

    if LPos1 < 1 then
      Exit;

    LPos2 := ALine.IndexOf(':', LPos1 + 1);
    if LPos2 < 0 then
      Exit;

    LPos3 := ALine.IndexOf(':', LPos2 + 1);
    if LPos3 < 0 then
      Exit;

    LLineStr := ALine.Substring(LPos1 + 1, LPos2 - LPos1 - 1).Trim();
    if not TryStrToInt(LLineStr, ALineNum) then
      Exit;

    LColStr := ALine.Substring(LPos2 + 1, LPos3 - LPos2 - 1).Trim();
    if not TryStrToInt(LColStr, AColNum) then
      Exit;

    AFilePath := ALine.Substring(0, LPos1);

    LSevStr := ALine.Substring(LPos3 + 1).TrimLeft();

    if LSevStr.StartsWith('error:') then
    begin
      ASeverity := 'error';
      AMessage := LSevStr.Substring(6).Trim();
      Result := True;
    end
    else if LSevStr.StartsWith('warning:') then
    begin
      ASeverity := 'warning';
      AMessage := LSevStr.Substring(8).Trim();
      Result := True;
    end
    else if LSevStr.StartsWith('note:') then
    begin
      ASeverity := 'note';
      AMessage := LSevStr.Substring(5).Trim();
      Result := True;
    end;
  end;

begin
  // Strip ANSI codes for parsing only; the original line always passes through
  LCleanLine := TUtils.StripAnsi(ABuffer);

  // If this is a clang error/warning/note line, capture it in FErrors
  if Assigned(FErrors) and TryParseCompilerMessage(LCleanLine, LFilePath,
    LLineNum, LColNum, LSeverity, LMessage) then
  begin
    if LSeverity = 'error' then
      LErrorSeverity := esError
    else if LSeverity = 'warning' then
      LErrorSeverity := esWarning
    else
      LErrorSeverity := esHint;

    FErrors.Add(LFilePath, LLineNum, LColNum, LErrorSeverity,
      CP_ERR_ZIGBUILD_BUILDFAILED, LMessage.Trim());
  end;

  // Always return the original line unchanged
  Result := ABuffer;
end;

procedure TCPZigBuild.HandleOutputLine(const ALine: string;
  const AUserData: Pointer);
var
  LFiltered: string;
begin
  if not FOutput.IsAssigned() then
    Exit;

  if FRawOutput then
  begin
    FOutput.Callback(ALine, FOutput.UserData);
    Exit;
  end;

  LFiltered := FilterOutputBuffer(ALine);
  if LFiltered.Length > 0 then
    FOutput.Callback(LFiltered, FOutput.UserData);
end;

// Persistence

function TCPZigBuild.LoadBuildFile(const AFilename: string): Boolean;
var
  LLines: TStringList;
  LLine: string;
  LI: Integer;
  LIdx: Integer;
  LValue: string;
  LSourceName: string;
begin
  Result := False;

  if not TFile.Exists(AFilename) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIGBUILD_SAVEFAILED, RSZigBuildFileNotFound,
        [AFilename]);
    Exit;
  end;

  // Clear existing data and set the output path from the file location
  Clear();
  FOutputPath := TPath.GetDirectoryName(AFilename);

  LLines := TStringList.Create();
  try
    LLines.Text := TFile.ReadAllText(AFilename);

    for LI := 0 to LLines.Count - 1 do
    begin
      LLine := LLines[LI].Trim();

      // .name = "<projectname>"
      LIdx := LLine.IndexOf('.name = "');
      if LIdx >= 0 then
      begin
        LValue := LLine.Substring(LIdx + 9);
        LIdx := LValue.IndexOf('"');
        if LIdx >= 0 then
          FProjectName := LValue.Substring(0, LIdx);
        Continue;
      end;

      // addExecutable -> bmExe
      if LLine.Contains('addExecutable') then
      begin
        FBuildMode := bmExe;
        Continue;
      end;

      // addLibrary -> bmLib (refined to bmDll by the .linkage line below)
      if LLine.Contains('addLibrary') then
      begin
        FBuildMode := bmLib;
        Continue;
      end;

      // .linkage = .dynamic -> bmDll
      if LLine.Contains('.linkage = .dynamic') then
      begin
        FBuildMode := bmDll;
        Continue;
      end;

      // GUI subsystem
      if LLine.Contains('exe.subsystem = .windows') then
      begin
        FSubsystem := stGUI;
        Continue;
      end;

      // Target platform: reconstruct the raw triple string
      if LLine.Contains('.cpu_arch = .x86_64') and
         LLine.Contains('.os_tag = .windows') then
      begin
        FTarget := CP_DEFAULT_TARGET;
        Continue;
      end;

      if LLine.Contains('.cpu_arch = .x86_64') and
         LLine.Contains('.os_tag = .linux') then
      begin
        FTarget := 'x86_64-linux-gnu';
        Continue;
      end;

      // addIncludePath
      LIdx := LLine.IndexOf('root_module.addIncludePath(b.path("');
      if LIdx >= 0 then
      begin
        LValue := LLine.Substring(LIdx + 35);
        LIdx := LValue.IndexOf('"');
        if LIdx >= 0 then
          FIncludePaths.Add(TPath.Combine(FOutputPath,
            LValue.Substring(0, LIdx)));
        Continue;
      end;

      // addLibraryPath
      LIdx := LLine.IndexOf('root_module.addLibraryPath(b.path("');
      if LIdx >= 0 then
      begin
        LValue := LLine.Substring(LIdx + 35);
        LIdx := LValue.IndexOf('"');
        if LIdx >= 0 then
          FLibraryPaths.Add(TPath.Combine(FOutputPath,
            LValue.Substring(0, LIdx)));
        Continue;
      end;

      // linkSystemLibrary
      LIdx := LLine.IndexOf('root_module.linkSystemLibrary("');
      if LIdx >= 0 then
      begin
        LValue := LLine.Substring(LIdx + 32);
        LIdx := LValue.IndexOf('"');
        if LIdx >= 0 then
          FLinkLibraries.Add(LValue.Substring(0, LIdx));
        Continue;
      end;

      // .flags line -> defines and undefines
      if LLine.Contains('.flags = &.{') then
      begin
        ParseFlagsLine(LLine);
        Continue;
      end;

      // Source files inside .files = &.{ (C and C++ groups alike)
      LIdx := LLine.IndexOf('"');
      if LIdx >= 0 then
      begin
        LValue := LLine.Substring(LIdx + 1);
        LIdx := LValue.IndexOf('"');
        if LIdx >= 0 then
        begin
          LSourceName := LValue.Substring(0, LIdx);
          if LSourceName.Contains('.cpp') or LSourceName.EndsWith(CP_C_SOURCE_EXT,
            True) then
            FSourceFiles.Add(TPath.Combine(FOutputPath, LSourceName));
        end;
      end;
    end;

    Result := not FProjectName.IsEmpty;
  finally
    LLines.Free();
  end;
end;

function TCPZigBuild.SaveBuildFile(): Boolean;
var
  LBuildZigPath: string;
  LContent: string;
  LUTF8NoBOM: TEncoding;
begin
  Result := False;

  if FOutputPath = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIBUILD_NOOUTPUTPATH, RSZigBuildNoOutputPath);
    Exit;
  end;

  if FSourceFiles.Count = 0 then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIGBUILD_NOSOURCES, RSZigBuildNoSources);
    Exit;
  end;

  // Generate build.zig and ensure the target directory exists
  LBuildZigPath := TPath.Combine(FOutputPath, 'build.zig');
  TUtils.CreateDirInPath(LBuildZigPath);
  LContent := GenerateBuildZig();

  // Write without a BOM - Zig does not accept a BOM in source files
  LUTF8NoBOM := TUTF8Encoding.Create(False);
  try
    try
      TFile.WriteAllText(LBuildZigPath, LContent, LUTF8NoBOM);
      Result := True;
    except
      on E: Exception do
      begin
        if Assigned(FErrors) then
          FErrors.Add(esError, CP_ERR_ZIGBUILD_SAVEFAILED, RSZigBuildSaveFailed,
            [E.Message]);
      end;
    end;
  finally
    LUTF8NoBOM.Free();
  end;
end;

// Invocation

function TCPZigBuild.Process(const AAutoRun: Boolean): Boolean;
var
  LZigExe: string;
  LI: Integer;
  LSrcPath: string;
  LDestPath: string;
  LDestDir: string;
  LOutputFile: string;
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  Result := False;

  // Status: target, optimize, and (Windows only) subsystem
  Status(RSZigBuildTargetPlatform, [GetTargetDisplayName()]);
  Status(RSZigBuildOptimizeLevel, [GetOptimizeLevelDisplayName()]);
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(CP_DEFAULT_TARGET, LArch, LOS, LAbi);
  if SameText(LOS, OS_WINDOWS) then
    Status(RSZigBuildSubsystem, [GetSubsystemDisplayName()]);

  // Always save the build file first
  Status(RSZigBuildSaving);
  if not SaveBuildFile() then
    Exit;

  // Locate the zig executable
  LZigExe := GetZigPath('zig.exe');
  if (LZigExe = '') or (not TFile.Exists(LZigExe)) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIGBUILD_ZIGNOTFOUND, RSZigBuildZigNotFound,
        [LZigExe]);
    Exit;
  end;

  // Force colored output from the toolchain
  TUtils.SetEnv('YES_COLOR', '1');
  TUtils.SetEnv('CLICOLOR_FORCE', '1');
  TUtils.SetEnv('TERM', 'xterm-256color');
  TUtils.SetEnv('ZIG_GLOBAL_CACHE_DIR',
    TPath.Combine(GetZigPath(), '.zig-cache'));

  // Copy DLLs into the output directory BEFORE building so the linker can find them
  if FCopyDLLs.Count > 0 then
  begin
    LDestDir := TPath.Combine(FOutputPath, TPath.Combine('zig-out', 'bin'));
    TUtils.CreateDirInPath(LDestDir);
    for LI := 0 to FCopyDLLs.Count - 1 do
    begin
      LSrcPath := ResolvePath('', FCopyDLLs[LI]);

      // Skip if the source already sits in the destination directory
      if SameText(TPath.GetFullPath(TPath.GetDirectoryName(LSrcPath)),
        TPath.GetFullPath(LDestDir)) then
        Continue;

      if TFile.Exists(LSrcPath) then
      begin
        LDestPath := TPath.Combine(LDestDir, TPath.GetFileName(LSrcPath));
        Status(RSZigBuildCopying, [TPath.GetFileName(LSrcPath)]);
        TFile.Copy(LSrcPath, LDestPath, True);
      end
      else if Assigned(FErrors) then
        FErrors.Add(esWarning, CP_ERR_ZIGBUILD_WRNCANNOTRUN, RSZigBuildDllNotFound,
          [LSrcPath]);
    end;
  end;

  // Run zig build
  Status(RSZigBuildBuilding, [FProjectName]);
  TUtils.CaptureConsolePTY(
    PChar(LZigExe),
    'build --color auto --summary none --multiline-errors newline --error-style minimal',
    FOutputPath,
    FLastExitCode,
    nil,
    HandleOutputLine
  );

  if FLastExitCode <> 0 then
  begin
    Status(RSZigBuildFailedWithCode, [FLastExitCode]);
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIGBUILD_BUILDFAILED, RSZigBuildFailed,
        [FLastExitCode]);
    Exit;
  end;

  Status(RSZigBuildSucceeded);

  // Resolve the built artifact path (lib -> zig-out/lib, else zig-out/bin)
  if FBuildMode = bmLib then
    LOutputFile := TPath.Combine(FOutputPath,
      TPath.Combine('zig-out', TPath.Combine('lib', GetOutputFilename())))
  else
    LOutputFile := TPath.Combine(FOutputPath,
      TPath.Combine('zig-out', TPath.Combine('bin', GetOutputFilename())));
  Status(RSZigBuildOutput,
    [TUtils.NormalizePath(TPath.GetFullPath(LOutputFile))]);

  // Apply post-build resources (manifest, icon, version info)
  ApplyPostBuildResources(LOutputFile);

  // Publish finished output. AFTER the artifact is stamped, so a published
  // copy always carries its version info.
  if FPostBuildCopies.Count > 0 then
  begin
    if not DoPostBuildCopies(LOutputFile) then
      Exit;
  end;

  // Write the breakpoints file if any were collected
  WriteBreakpointsFile(LOutputFile);

  if AAutoRun then
    Result := Run()
  else
    Result := True;
end;

function TCPZigBuild.Run(): Boolean;
var
  LExePath: string;
  LWslPath: string;
  LRunCommand: string;
  LArch: string;
  LOS: string;
  LAbi: string;
begin
  Result := False;

  // Only executables can be run
  if FBuildMode <> bmExe then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIGBUILD_BUILDFAILED, RSZigBuildCannotRunLib);
    Exit;
  end;

  // Only Windows and Linux hosts can be launched here
  if not DoSplitTarget(FTarget, LArch, LOS, LAbi) then
    DoSplitTarget(CP_DEFAULT_TARGET, LArch, LOS, LAbi);
  if not (SameText(LOS, OS_WINDOWS) or SameText(LOS, OS_LINUX)) then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esWarning, CP_ERR_ZIGBUILD_WRNCANNOTRUN, RSZigBuildCannotRunCross,
        [GetTargetDisplayName()]);
    Result := True;
    Exit;
  end;

  // Validate the project name
  if FProjectName = '' then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIBUILD_NOOUTPUTPATH, RSZigBuildNoProjectName);
    Exit;
  end;

  // Build the executable path
  LExePath := TPath.Combine(FOutputPath,
    TPath.Combine('zig-out', TPath.Combine('bin', GetOutputFilename())));

  if not TFile.Exists(LExePath) then
  begin
    FLastExitCode := 2;
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIGBUILD_BUILDFAILED, RSZigBuildExeNotFound,
        [LExePath]);
    Exit;
  end;

  // Run and capture output
  Status(RSZigBuildRunning, [GetOutputFilename()]);

  if SameText(LOS, OS_LINUX) then
  begin
    // Convert to a WSL path and mark executable before running
    LWslPath := TUtils.WindowsPathToWSL(LExePath);
    TUtils.CaptureConsolePTY('wsl.exe',
      PChar('chmod +x "' + LWslPath + '"'),
      TPath.GetDirectoryName(LExePath), FLastExitCode, nil, nil);

    // The program is an argument to wsl.exe, so its own arguments follow the
    // quoted path in the same command line rather than being a separate list.
    LRunCommand := '"' + LWslPath + '"';
    if FRunArguments <> '' then
      LRunCommand := LRunCommand + ' ' + FRunArguments;

    TUtils.CaptureConsolePTY(
      'wsl.exe',
      PChar(LRunCommand),
      TPath.GetDirectoryName(LExePath),
      FLastExitCode,
      nil,
      HandleOutputLine
    );
  end
  else
  begin
    TUtils.CaptureConsolePTY(
      PChar(LExePath),
      PChar(FRunArguments),
      TPath.GetDirectoryName(LExePath),
      FLastExitCode,
      nil,
      HandleOutputLine
    );
  end;

  if FLastExitCode <> 0 then
  begin
    if Assigned(FErrors) then
      FErrors.Add(esError, CP_ERR_ZIGBUILD_BUILDFAILED, RSZigBuildRunFailed,
        [FLastExitCode]);
    Exit;
  end;

  Result := True;
end;

function TCPZigBuild.ClearCache(): Boolean;
var
  LCachePath: string;
begin
  Result := True;
  LCachePath := TPath.Combine(FOutputPath, '.zig-cache');
  if TDirectory.Exists(LCachePath) then
    TDirectory.Delete(LCachePath, True);
end;

function TCPZigBuild.ClearOutput(): Boolean;
var
  LOutputDir: string;
begin
  Result := True;
  LOutputDir := TPath.Combine(FOutputPath, 'zig-out');
  if TDirectory.Exists(LOutputDir) then
    TDirectory.Delete(LOutputDir, True);
end;

// Post-build resources

procedure TCPZigBuild.ApplyPostBuildResources(const AExePath: string);
var
  LIsExe: Boolean;
  LIsDll: Boolean;
begin
  LIsExe := AExePath.EndsWith('.exe', True);
  LIsDll := AExePath.EndsWith('.dll', True);
  if not LIsExe and not LIsDll then
    Exit;

  // Manifest (executables only)
  if LIsExe then
  begin
    if TUtils.ResourceExist('EXE_MANIFEST') then
      if not TUtils.AddResManifestFromResource('EXE_MANIFEST', AExePath) then
        if Assigned(FErrors) then
          FErrors.Add(esWarning, CP_ERR_ZIGBUILD_WRNMANIFEST, RSZigBuildManifestFailed);
  end;

  // Icon (executables only)
  if LIsExe and (FExeIcon <> '') then
  begin
    if TFile.Exists(FExeIcon) then
      TUtils.UpdateIconResource(AExePath, FExeIcon)
    else if Assigned(FErrors) then
      FErrors.Add(esWarning, CP_ERR_ZIGBUILD_WRNICON, RSZigBuildIconNotFound,
        [FExeIcon]);
  end;

  // Version info
  if FAddVersionInfo then
    TUtils.UpdateVersionInfoResource(AExePath,
      FVIMajor, FVIMinor, FVIPatch, FVIProductName,
      FVIDescription, FVIFilename, FVICompanyName, FVICopyright);
end;

// Version info / post-build resources

procedure TCPZigBuild.SetAddVersionInfo(const AValue: Boolean);
begin
  FAddVersionInfo := AValue;
end;

function TCPZigBuild.GetAddVersionInfo(): Boolean;
begin
  Result := FAddVersionInfo;
end;

procedure TCPZigBuild.SetVIMajor(const AValue: Word);
begin
  FVIMajor := AValue;
end;

function TCPZigBuild.GetVIMajor(): Word;
begin
  Result := FVIMajor;
end;

procedure TCPZigBuild.SetVIMinor(const AValue: Word);
begin
  FVIMinor := AValue;
end;

function TCPZigBuild.GetVIMinor(): Word;
begin
  Result := FVIMinor;
end;

procedure TCPZigBuild.SetVIPatch(const AValue: Word);
begin
  FVIPatch := AValue;
end;

function TCPZigBuild.GetVIPatch(): Word;
begin
  Result := FVIPatch;
end;

procedure TCPZigBuild.SetVIProductName(const AValue: string);
begin
  FVIProductName := AValue;
end;

function TCPZigBuild.GetVIProductName(): string;
begin
  Result := FVIProductName;
end;

procedure TCPZigBuild.SetVIDescription(const AValue: string);
begin
  FVIDescription := AValue;
end;

function TCPZigBuild.GetVIDescription(): string;
begin
  Result := FVIDescription;
end;

procedure TCPZigBuild.SetVIFilename(const AValue: string);
begin
  FVIFilename := AValue;
end;

function TCPZigBuild.GetVIFilename(): string;
begin
  Result := FVIFilename;
end;

procedure TCPZigBuild.SetVICompanyName(const AValue: string);
begin
  FVICompanyName := AValue;
end;

function TCPZigBuild.GetVICompanyName(): string;
begin
  Result := FVICompanyName;
end;

procedure TCPZigBuild.SetVICopyright(const AValue: string);
begin
  FVICopyright := AValue;
end;

function TCPZigBuild.GetVICopyright(): string;
begin
  Result := FVICopyright;
end;

procedure TCPZigBuild.SetExeIcon(const AValue: string);
begin
  FExeIcon := AValue;
end;

function TCPZigBuild.GetExeIcon(): string;
begin
  Result := FExeIcon;
end;

// Breakpoints

procedure TCPZigBuild.AddBreakpoint(const AFileName: string; const ALineNumber: Integer);
var
  LEntry: TCPBreakpointEntry;
begin
  LEntry.FileName := AFileName;
  LEntry.LineNumber := ALineNumber;
  FBreakpoints.Add(LEntry);
end;

procedure TCPZigBuild.ClearBreakpoints();
begin
  FBreakpoints.Clear();
end;

function TCPZigBuild.GetBreakpoints(): TArray<TCPBreakpointEntry>;
begin
  Result := FBreakpoints.ToArray();
end;

procedure TCPZigBuild.WriteBreakpointsFile(const AExePath: string);
var
  LBreakpointFile: string;
  LConfig: TConfig;
  LExeDir: string;
  LRelativePath: string;
  LI: Integer;
  LIndex: Integer;
begin
  if FBreakpoints.Count = 0 then
    Exit;

  LBreakpointFile := TUtils.ResolvePath(
    TPath.ChangeExtension(AExePath, CP_BREAKPOINT_EXT));
  LExeDir := TPath.GetFullPath(TPath.GetDirectoryName(AExePath));

  LConfig := TConfig.Create();
  try
    for LI := 0 to FBreakpoints.Count - 1 do
    begin
      LIndex := LConfig.AddTableEntry('breakpoints');
      // ExtractRelativePath needs native backslash paths on Windows
      LRelativePath := ExtractRelativePath(
        IncludeTrailingPathDelimiter(LExeDir),
        TPath.GetFullPath(FBreakpoints[LI].FileName.Replace('/', '\')));
      // Normalize output to forward slashes
      LRelativePath := LRelativePath.Replace('\', '/');
      LConfig.SetTableString('breakpoints', LIndex, 'file', LRelativePath);
      LConfig.SetTableInteger('breakpoints', LIndex, 'line',
        FBreakpoints[LI].LineNumber);
    end;
    LConfig.SaveToFile(LBreakpointFile);
  finally
    LConfig.Free();
  end;
end;

// Toolchain paths

procedure TCPZigBuild.SetToolchainPath(const APath: string);
begin
  if APath = '' then
    FToolchainPath := TUtils.ResolvePath(CP_DEFAULT_TOOLCHAIN_PATH)
  else
    FToolchainPath := TUtils.ResolvePath(APath);

  // Persist the raw value (empty or user-provided)
  FBuildConfig.SetString('build.toolchain_path', APath);
end;

function TCPZigBuild.GetToolchainPath(): string;
begin
  Result := FToolchainPath;
end;

function TCPZigBuild.GetZigPath(const AFilename: string): string;
begin
  Result := TPath.Combine(FToolchainPath, 'zig');
  if AFilename <> '' then
    Result := TPath.Combine(Result, AFilename);
end;

function TCPZigBuild.GetRuntimePath(const AFilename: string): string;
begin
  Result := TPath.Combine(FToolchainPath, 'runtime');
  if AFilename <> '' then
    Result := TPath.Combine(Result, AFilename);
end;

function TCPZigBuild.GetLibsPath(const AFilename: string): string;
begin
  Result := TPath.Combine(FToolchainPath, 'libs');
  if AFilename <> '' then
    Result := TPath.Combine(Result, AFilename);
end;

function TCPZigBuild.GetAssetsPath(const AFilename: string): string;
begin
  Result := TPath.Combine(FToolchainPath, 'assets');
  if AFilename <> '' then
    Result := TPath.Combine(Result, AFilename);
end;

function TCPZigBuild.ResolvePath(const AFilename: string;
  const ARelativePath: string; const ABasePath: string;
  const ABehavior: Integer): string;
var
  LBase: string;
begin
  // (a) Absolute path: use as-is
  if TPath.IsPathRooted(ARelativePath) then
  begin
    if AFilename <> '' then
      Result := TPath.Combine(ARelativePath, AFilename)
    else
      Result := ARelativePath;
    Exit;
  end;

  // (b) Relative path with an explicit base
  if ABasePath <> '' then
    LBase := ABasePath
  // (c) Relative path, no base: resolve per behavior
  else if ABehavior = 1 then
    LBase := TPath.GetDirectoryName(ParamStr(0))
  else
  begin
    // (d) Behavior 0 or unknown: raw passthrough
    if AFilename <> '' then
      Result := TPath.Combine(ARelativePath, AFilename)
    else
      Result := ARelativePath;
    Exit;
  end;

  // Combine base + relative (+ filename)
  Result := TPath.Combine(LBase, ARelativePath);
  if AFilename <> '' then
    Result := TPath.Combine(Result, AFilename);
end;

end.
