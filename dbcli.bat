@echo off
Setlocal EnableDelayedExpansion EnableExtensions
for /f "delims=" %%i in ('ver') do set "OSVERSION=%%i"

pushd "%~dp0"
SET CLASSPATH=
SET JAVA=
SET JAVA_TOOL_OPTIONS=
if not defined CONSOLE_COLOR SET CONSOLE_COLOR=0A
If not exist "%TNS_ADMIN%\tnsnames.ora" if defined ORACLE_HOME (set "TNS_ADMIN=%ORACLE_HOME%\network\admin" )

rem read config file
If exist "data\init.cfg" (for /f "eol=# delims=" %%i in (data\init.cfg) do (%%i))

rem search java 1.8+ executable
SET TEMP_PATH=!PATH!
SET "PATH=%JRE_HOME%\bin;%JRE_HOME%;%JAVA_HOME%\bin;!PATH!"
SET JAVA_HOME=
SET "SEP= = "

for /F "usebackq delims=" %%p in (`where java.exe 2^>NUL`) do (
  If exist %%~sp (
      set "JAVA_EXE_=%%~sp"
	  SET found=0
      FOR /F "tokens=1,2 delims==" %%i IN ('""!JAVA_EXE_!" -XshowSettings:properties 2^>^&1^|findstr "java\.home java\.class\.version os\.arch""' ) do (

        for /f "tokens=* delims= " %%a in ("%%i") do set n=%%a
        for /l %%a in (1,1,255) do if "!n:~-1!"==" " set n=!n:~0,-1!
        for /f "tokens=* delims= " %%a in ("%%j") do set "v=%%a"
        for /l %%a in (1,1,255) do if "!v:~-1!"==" " set "v=!v:~0,-1!"
        if "!n!" equ "java.home" (
            for %%a in ("!v!") do set v1=%%~sa
            set "JAVA_BIN_=!v1!\bin"
        )
        if "!n!" equ "os.arch" if "!v!" equ "x86" (set bit_=x86) else (set bit_=x64)
        if "!n!" equ "java.class.version" (
            SET found=1
            SET "JAVA_VER_=!v!"
            if "52.0" GTR "!v!" (SET found=0)
            rem if "64.0" LSS "!v!" (SET found=0)
        )
      )
	  if "!found!" == "0" (set "JAVA_EXE_=")
      if "!JAVA_EXE_!" neq "" if "!JAVA_BIN_!" neq "" (
        set "JAVA_BIN=!JAVA_BIN_!" & set "JAVA_EXE=!JAVA_BIN_!\java.exe" & set "bit=!bit_!"
        goto next
      ) else ( set "JAVA_BIN_=")
   )
)

:next
If not exist "!JAVA_EXE!" (
    ver|findstr -r " 5.[0-9]*\.[0-9]" > NUL && (SET "BASE=!JRE_HOME!" && if not exist "!BASE!\bin\java.exe" SET "BASE=jre") || (SET "BASE=jre")
    if not exist "jre\bin\java.exe" (
        echo Cannot find Java 8+ executable, please manually set JRE_HOME for available Java program.
        pause
        popd
        exit /b 1
    ) else (
        set "JAVA_BIN=jre\bin"
        set "JAVA_EXE=jre\bin\java.exe"
        set "bit=x86"
        SET "JAVA_VER_=52"
    )
)

if defined ANSICON (
    set "ANSICON_DEF=ansicon"
    set "TERM=windows-conemu"
) else (
    if not defined TERM (
        if "!ANSICON_DEF!" equ "render" (
            set "TERM=windows-render"
        )
    ) else (
        set "ANSICON_DEF="
    )
)

SET "PATH=.\lib\!bit!;!JAVA_BIN!;!EXT_PATH!;.\bin;!TEMP_PATH!"

if defined MSYSTEM set "ANSICON_DEF=msys"
rem set "ANSICON_DEF=native"
rem set "ANSICON_DEF=ffm"
rem set "ANSICON_DEF=jna"

IF !CONSOLE_COLOR! NEQ NA color !CONSOLE_COLOR!

cmd.exe /c .\lib\%bit%\luajit .\lib\bootstrap.lua "!JAVA_EXE!" "!JAVA_VER_!" %*
popd
EndLocal
