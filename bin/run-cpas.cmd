@echo off
rem ============================================================================
rem  CPaskal(tm) Programming Language
rem
rem  Copyright (c) 2026-present tinyBigGAMES(tm) LLC
rem  All Rights Reserved.
rem
rem  See LICENSE for license information
rem ============================================================================
rem  run-cpas.cmd -- run the CPaskal CLI compiler with console output capture
rem
rem  Usage:   run-cpas.cmd hello
rem           run-cpas.cmd hello -r
rem           run-cpas.cmd hello -r -t x86_64-linux-gnu
rem           run-cpas.cmd -h
rem ============================================================================

cd /d "%~dp0"
start "" /wait cmd /c cpas.exe %* ^> cpas.txt 2^>^&1
type cpas.txt
