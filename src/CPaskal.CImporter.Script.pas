{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.CImporter.Script - CImport Script Execution via Script Engine

  Wraps TCPScriptEngine to execute .cps CImport scripts. Registers all
  CImporter commands as builtins so scripts use full CPaskal syntax:

    module script mylib;
    begin
      SetHeader("mylib.h");
      SetModuleName("mylib");
      Process();
    end.

  Public API is unchanged from the previous TCISLexer-based implementation.

  Dependencies: CPaskal.Script, CPaskal.CImporter, CPaskal.Common, StdApp.Base
===============================================================================}

unit CPaskal.CImporter.Script;

interface

uses
  System.SysUtils,
  System.Rtti,
  StdApp.Base,
  CPaskal.Common,
  CPaskal.CImporter,
  CPaskal.Script;

const
  { CP_ERR_CIS_001 }
  CP_ERR_CIS_001 = 'CIS001';

type
  { TCPCImportScript }
  TCPCImportScript = class(TBaseObject)
  private
    FImporter: TCImporter;
    FEngine: TCPScriptEngine;
    procedure RegisterBuiltins();
    function ResolveTarget(const AValue: string): TCPTargetPlatform;
    function ResolveBindingMode(const AValue: string): TBindingMode;
  public
    constructor Create(); override;
    destructor Destroy(); override;
    procedure SetStatusCallback(const ACallback: TStatusCallback;
      const AUserData: Pointer = nil); override;
    procedure ShowHelp();
    function ExecuteFile(const AFilename: string): Boolean;
  end;

implementation

uses
  StdApp.Console;

{ TCPCImportScript }

constructor TCPCImportScript.Create();
begin
  inherited;

  FImporter := TCImporter.Create();
  FEngine := TCPScriptEngine.Create();
  FEngine.SetErrors(FErrors);
  RegisterBuiltins();
end;

destructor TCPCImportScript.Destroy();
begin
  FreeAndNil(FEngine);
  FreeAndNil(FImporter);

  inherited;
end;

procedure TCPCImportScript.SetStatusCallback(const ACallback: TStatusCallback;
  const AUserData: Pointer);
begin
  inherited;

  FImporter.SetStatusCallback(ACallback, AUserData);
  FEngine.SetStatusCallback(ACallback, AUserData)
end;

function TCPCImportScript.ResolveTarget(const AValue: string): TCPTargetPlatform;
begin
  if not cpTryParseTarget(AValue, Result) then
  begin
    FErrors.Add(esError, CP_ERR_CIS_001,
      'Unknown target platform: %s', [AValue]);
    Result := tpX86_64_Windows;
  end;
end;

function TCPCImportScript.ResolveBindingMode(const AValue: string): TBindingMode;
var
  LText: string;
begin
  LText := AValue.ToLower();
  if LText = 'dynamic' then
    Result := bmDynamic
  else
  begin
    FErrors.Add(esError, CP_ERR_CIS_001,
      'Unknown binding mode: %s', [AValue]);
    Result := bmDynamic;
  end;
end;

procedure TCPCImportScript.RegisterBuiltins();
begin
  // -- No-arg commands --

  FEngine.RegisterGlobalRoutine(
    'routine Process(): boolean',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    var
      LResult: Boolean;
    begin
      LResult := FImporter.Process();
      if not LResult then
        FErrors.Add(esError, CP_ERR_CIS_001,
          'Process failed: %s', [FImporter.GetLastError()]);
      Result := TValue.From<Boolean>(LResult);
    end);

  FEngine.RegisterGlobalRoutine(
    'routine Clear()',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.Clear();
      Result := TValue.Empty;
    end);

  // -- Single string commands --

  FEngine.RegisterGlobalRoutine(
    'routine SetHeader(const AFilename: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.SetHeader(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine SetModuleName(const AName: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.SetModuleName(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine SetDllName(const AName: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.SetDllName(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine SetDllPath(const APath: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.SetDllPath(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine SetOutputPath(const APath: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.SetOutputPath(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddSourcePath(const APath: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddSourcePath(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddExcludedType(const AName: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddExcludedType(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddExcludedFunction(const AName: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddExcludedFunction(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddUsesUnit(const AUnit: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddUsesUnit(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddUndefine(const AName: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddUndefine(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  // -- Boolean command --

  FEngine.RegisterGlobalRoutine(
    'routine SetSavePreprocessed(const AValue: boolean)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.SetSavePreprocessed(AArgs[0].AsBoolean);
      Result := TValue.Empty;
    end);

  // -- Binding mode (string -> enum) --

  FEngine.RegisterGlobalRoutine(
    'routine SetBindingMode(const AMode: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.SetBindingMode(ResolveBindingMode(AArgs[0].AsString));
      Result := TValue.Empty;
    end);

  // -- Target + string commands --

  FEngine.RegisterGlobalRoutine(
    'routine SetTargetDllName(const ATarget: string; const AName: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.SetDllName(ResolveTarget(AArgs[0].AsString), AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddCopyDll(const ATarget: string; const APath: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddCopyDll(ResolveTarget(AArgs[0].AsString), AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddLinkLibrary(const ATarget: string; const APath: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddLinkLibrary(ResolveTarget(AArgs[0].AsString), AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  // -- Two string commands --

  FEngine.RegisterGlobalRoutine(
    'routine AddIncludePath(const APath: string; const AModule: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      if AArgs[1].AsString <> '' then
        FImporter.AddIncludePath(AArgs[0].AsString, AArgs[1].AsString)
      else
        FImporter.AddIncludePath(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddDefine(const AName: string; const AValue: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      if AArgs[1].AsString <> '' then
        FImporter.AddDefine(AArgs[0].AsString, AArgs[1].AsString)
      else
        FImporter.AddDefine(AArgs[0].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddFunctionRename(const AOriginal: string; const ANewName: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddFunctionRename(AArgs[0].AsString, AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine AddDepDll(const ADllName: string; const ADllPath: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddDepDll(AArgs[0].AsString, AArgs[1].AsString);
      Result := TValue.Empty;
    end);

  // -- Three string commands --

  FEngine.RegisterGlobalRoutine(
    'routine AddDllNameMap(const APath: string; const ADllName: string; const ADllPath: string)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.AddDllNameMap(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsString);
      Result := TValue.Empty;
    end);

  // -- Two strings + occurrence commands --

  FEngine.RegisterGlobalRoutine(
    'routine InsertTextAfter(const ATarget: string; const AText: string; const AOccurrence: int32)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.InsertTextAfter(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine InsertTextBefore(const ATarget: string; const AText: string; const AOccurrence: int32)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.InsertTextBefore(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine InsertFileAfter(const ATarget: string; const AFile: string; const AOccurrence: int32)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.InsertFileAfter(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine InsertFileBefore(const ATarget: string; const AFile: string; const AOccurrence: int32)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.InsertFileBefore(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);

  FEngine.RegisterGlobalRoutine(
    'routine ReplaceText(const AOld: string; const ANew: string; const AOccurrence: int32)',
    function(const AArgs: TCPScriptArgs;
      const AInterpreter: TCPScriptInterpreter;
      const AUserData: Pointer): TCPScriptValue
    begin
      FImporter.ReplaceText(AArgs[0].AsString, AArgs[1].AsString, AArgs[2].AsInteger);
      Result := TValue.Empty;
    end);
end;

procedure TCPCImportScript.ShowHelp();
begin
  TConsole.PrintLn(COLOR_BOLD + 'USAGE:');
  TConsole.PrintLn('  cpas ' + COLOR_CYAN + 'cimport <script.cps>' + COLOR_RESET);
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + 'SCRIPT FORMAT:');
  TConsole.PrintLn('  CImport scripts use standard CPaskal script syntax:');
  TConsole.PrintLn('');
  TConsole.PrintLn('    module script mylib;');
  TConsole.PrintLn('    begin');
  TConsole.PrintLn('      SetHeader("mylib.h");');
  TConsole.PrintLn('      SetModuleName("mylib");');
  TConsole.PrintLn('      Process();');
  TConsole.PrintLn('    end.');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + 'SCRIPT COMMANDS:');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Configuration:');
  TConsole.PrintLn(COLOR_CYAN + '    SetHeader' + COLOR_RESET +
    '("filename")                          C header file to import');
  TConsole.PrintLn(COLOR_CYAN + '    SetModuleName' + COLOR_RESET +
    '("name")                           Output module name');
  TConsole.PrintLn(COLOR_CYAN + '    SetDllName' + COLOR_RESET +
    '("name")                              DLL name');
  TConsole.PrintLn(COLOR_CYAN + '    SetTargetDllName' + COLOR_RESET +
    '("target", "name")              DLL name for specific target');
  TConsole.PrintLn(COLOR_CYAN + '    SetDllPath' + COLOR_RESET +
    '("path")                              Path to DLL for preprocessing');
  TConsole.PrintLn(COLOR_CYAN + '    SetOutputPath' + COLOR_RESET +
    '("path")                           Output directory');
  TConsole.PrintLn(COLOR_CYAN + '    SetBindingMode' + COLOR_RESET +
    '("mode")                          Binding mode');
  TConsole.PrintLn(COLOR_CYAN + '    SetSavePreprocessed' + COLOR_RESET +
    '(bool)                       Save preprocessor output');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Paths & Filtering:');
  TConsole.PrintLn(COLOR_CYAN + '    AddIncludePath' + COLOR_RESET +
    '("path", "module")               C include search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddSourcePath' + COLOR_RESET +
    '("path")                            C source search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddExcludedType' + COLOR_RESET +
    '("name")                          Skip a C type');
  TConsole.PrintLn(COLOR_CYAN + '    AddExcludedFunction' + COLOR_RESET +
    '("name")                      Skip a C function');
  TConsole.PrintLn(COLOR_CYAN + '    AddFunctionRename' + COLOR_RESET +
    '("original", "newname")         Rename an imported function');
  TConsole.PrintLn(COLOR_CYAN + '    AddUsesUnit' + COLOR_RESET +
    '("unit")                              Add a uses dependency');
  TConsole.PrintLn(COLOR_CYAN + '    AddDefine' + COLOR_RESET +
    '("name", "value")                      Preprocessor #define');
  TConsole.PrintLn(COLOR_CYAN + '    AddUndefine' + COLOR_RESET +
    '("name")                              Preprocessor #undef');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Text Manipulation:');
  TConsole.PrintLn(COLOR_CYAN + '    InsertTextAfter' + COLOR_RESET +
    '("target", "text", occurrence)');
  TConsole.PrintLn(COLOR_CYAN + '    InsertTextBefore' + COLOR_RESET +
    '("target", "text", occurrence)');
  TConsole.PrintLn(COLOR_CYAN + '    InsertFileAfter' + COLOR_RESET +
    '("target", "file", occurrence)');
  TConsole.PrintLn(COLOR_CYAN + '    InsertFileBefore' + COLOR_RESET +
    '("target", "file", occurrence)');
  TConsole.PrintLn(COLOR_CYAN + '    ReplaceText' + COLOR_RESET +
    '("old", "new", occurrence)');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Linking:');
  TConsole.PrintLn(COLOR_CYAN + '    AddCopyDll' + COLOR_RESET +
    '("target", "path")                    Copy DLL to output');
  TConsole.PrintLn(COLOR_CYAN + '    AddLinkLibrary' + COLOR_RESET +
    '("target", "path")               Library search path');
  TConsole.PrintLn(COLOR_CYAN + '    AddDllNameMap' + COLOR_RESET +
    '("path", "dllname", "dllpath")    DLL name mapping');
  TConsole.PrintLn(COLOR_CYAN + '    AddDepDll' + COLOR_RESET +
    '("dllname", "dllpath")                 Dependency DLL');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + '  Execution:');
  TConsole.PrintLn(COLOR_CYAN + '    Process' + COLOR_RESET +
    '()                                       Run the import');
  TConsole.PrintLn(COLOR_CYAN + '    Clear' + COLOR_RESET +
    '()                                         Reset all settings');
  TConsole.PrintLn('');

  TConsole.PrintLn(COLOR_BOLD + 'TARGET VALUES:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '"x86_64_windows"' + COLOR_RESET +
    ', ' + COLOR_CYAN + '"x86_64_linux"' + COLOR_RESET);
  TConsole.PrintLn('');
  TConsole.PrintLn(COLOR_BOLD + 'BINDING MODES:');
  TConsole.PrintLn('  ' + COLOR_CYAN + '"dynamic"' + COLOR_RESET);
  TConsole.PrintLn('');
end;

function TCPCImportScript.ExecuteFile(const AFilename: string): Boolean;
begin
  Result := FEngine.ExecuteFile(AFilename);
end;

end.
