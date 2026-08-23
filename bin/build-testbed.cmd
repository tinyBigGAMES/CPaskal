@echo off
rem ============================================================================
rem  CPaskal(tm) Programming Language
rem
rem  Copyright (c) 2026-present tinyBigGAMES(tm) LLC
rem  All Rights Reserved.
rem
rem  See LICENSE for license information
rem ============================================================================
rem  build-testbed.cmd -- build the Testbed project
rem
rem  Output:  C:\Dev\Delphi\Projects\CPaskal\repo\bin\Testbed.exe
rem
rem  Usage:   build-testbed.cmd
rem ============================================================================

setlocal

call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"

cd /d "C:\Dev\Delphi\Projects\CPaskal\repo\projects"
if errorlevel 1 (echo BUILD FAILED - project folder not found & exit /b 1)

msbuild "CPaskal.groupproj" /t:Testbed /p:Config=Release /p:Platform=Win64 /verbosity:minimal
if errorlevel 1 (echo BUILD FAILED & exit /b 1)

echo BUILD OK
exit /b 0