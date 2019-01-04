@echo off
Setlocal EnableDelayedExpansion EnableExtensions
cd /d "%~dp0"
SET CLASSPATH=
SET JAVA=
SET JAVA_TOOL_OPTIONS=
if not defined CONSOLE_COLOR SET CONSOLE_COLOR=0A
if not defined ANSICON_CMD SET "ANSICON_CMD=.\lib\x64\ConEmuHk64.dll"
if !ANSICOLOR!==off set ANSICON_CMD=
If not exist "%TNS_ADM%\tnsnames.ora" if defined ORACLE_HOME (set "TNS_ADM=%ORACLE_HOME%\network\admin" )

rem read config file
SET JRE_HOME=
If exist "data\init.cfg" (for /f "eol=# delims=" %%i in (data\init.cfg) do (%%i))

rem search java 1.8+ executable
SET TEMP_PATH=!PATH!
set "PATH=.\jre\bin;!PATH!;%JAVA_HOME%\bin;%JRE_HOME%\bin;%JRE_HOME%"
SET JAVA_HOME=

for /F "usebackq delims=" %%p in (`where java.exe 2^>NUL ^& echo %JRE_HOME%\bin\java.exe`) do (
  If exist "%%p" (
      set "JAVA_EXE_=%%~sp"
      FOR /F "tokens=1,2 delims== " %%i IN ('!JAVA_EXE_! -XshowSettings:properties -version 2^>^&1^|findstr "java\.home java.version os.arch"' ) do (
        if "%%i" equ "java.home" set "JAVA_BIN_=%%~sj\bin"
        if "%%i" equ "os.arch" if "%%j" equ "x86" (set bit_=x86) else (set bit_=x64)
        if "%%i" equ "java.version" if "1.8" GTR "%%j" set "JAVA_EXE_="
      )
      if "!JAVA_EXE_!" neq "" if "!JAVA_BIN_!" neq "" (
        set "JAVA_BIN=!JAVA_BIN_!" & set "JAVA_EXE=!JAVA_BIN_!\java.exe" & set "bit=!bit_!"
      ) else ( set "JAVA_BIN_=")
   )
)

IF not exist "!JAVA_EXE!" (set "JAVA_BIN=.\jre\bin" & set "JAVA_EXE=.\jre\bin\java.exe" & set "bit=x86")
If not exist "!JAVA_EXE!" (
    echo "Cannot find Java 1.8 executable, exit."
    exit /b 1
)

SET "PATH=.\lib\!bit!;!JAVA_BIN!;!EXT_PATH!;.\bin;!TEMP_PATH!"

rem check if ConEmu dll exists to determine whether use it as the ANSI renderer
if not defined ANSICON if defined ANSICON_CMD (
   SET ANSICON_EXC=nvd3d9wrap.dll;nvd3d9wrapx.dll
   SET ANSICON_DEF=ansicon
   if "!bit!"=="x86" set "ANSICON_CMD=.\lib\x86\ConEmuHk.dll"
)

set "ANSICON_DEF=jline"
if defined ConEmuPID set "ANSICON_DEF=conemu"
if defined MSYSTEM set "ANSICON_DEF=msys"
set "ANSICON_CMD="

rem For win10, don't used both JLINE/Ansicon to escape the ANSI codes
rem ver|findstr -r "[1-9][0-9]\.[0-9]*\.[0-9]">NUL && (SET "ANSICON_CMD=" && set "ANSICON_DEF=native")

IF !CONSOLE_COLOR! NEQ NA color !CONSOLE_COLOR!
rem unpack jar files for the first use
for /f %%i in ('dir /s/b *.pack.gz 2^>NUL ^|findstr -v "cache dump" ') do (
   set "var=%%i" &set "str=!var:@=!"
   echo Unpacking %%i to jar file for the first use...
   If exist "jre\bin\unpack200" (
       jre\bin\unpack200 -q -r "%%i" "!str:~0,-8!"
   ) else (
       "!JAVA_BIN!\unpack200" -q -r "%%i" "!str:~0,-8!"
   )
)

cmd.exe /c .\lib\%bit%\luajit .\lib\bootstrap.lua "!JAVA_EXE!" %*
EndLocal