@echo off
REM Wrapper for tool/run.dart - see that file for usage.
REM Kept ASCII-only on purpose: cmd parses .bat files using the system
REM ANSI codepage, so UTF-8 Chinese comments turn into garbage commands.
dart tool\run.dart %*
