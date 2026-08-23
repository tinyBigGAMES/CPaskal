@echo off
rem ============================================================================
rem  CPaskal(tm) Programming Language
rem
rem  Copyright (c) 2026-present tinyBigGAMES(tm) LLC
rem  All Rights Reserved.
rem
rem  See LICENSE for license information
rem ============================================================================
rem  run-testbed.cmd -- run the Testbed with console output capture
rem
rem  Usage:   run-testbed.cmd -all
rem           run-testbed.cmd TestName
rem           run-testbed.cmd CaseName.TestName
rem           run-testbed.cmd -list
rem           run-testbed.cmd -h
rem ============================================================================

cd /d "%~dp0"
start "" /wait cmd /c Testbed.exe %* ^> testbed.txt 2^>^&1
type testbed.txt