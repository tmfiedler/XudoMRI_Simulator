@echo off
setlocal EnableExtensions

rem MSBuild treats PATH and Path as duplicate environment keys. Normalize the
rem inherited environment before Visual Studio prepends its tool directories.
set "NUTATE_SAR_INITIAL_PATH=%PATH%"
set "Path="
set "PATH=%NUTATE_SAR_INITIAL_PATH%;%SystemRoot%\System32"

for %%I in ("%~dp0.") do set "SCRIPT_DIR=%%~fI"
set "BUILD_DIR=%SCRIPT_DIR%\build-msvc"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
  echo ERROR: Visual Studio Installer vswhere.exe was not found.
  exit /b 1
)

set "VS_INSTALL_DIR="
for /f "usebackq tokens=*" %%P in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_INSTALL_DIR=%%~fP"
if not defined VS_INSTALL_DIR (
  echo ERROR: A Visual Studio installation with the C++ toolchain was not found.
  exit /b 1
)

call "%VS_INSTALL_DIR%\Common7\Tools\VsDevCmd.bat" -arch=x64 >nul
if errorlevel 1 (
  echo ERROR: Failed to initialize the Visual Studio developer environment.
  exit /b 1
)

echo Configuring the historical NutateSAR source...
cmake -S "%SCRIPT_DIR%" -B "%BUILD_DIR%" ^
  -G "Visual Studio 18 2026" -A x64
if errorlevel 1 exit /b 1

echo Building NutateSAR.exe for source review only...
cmake --build "%BUILD_DIR%" --config Release --target NutateSAR
if errorlevel 1 exit /b 1

set "SAR_EXE=%BUILD_DIR%\bin\NutateSAR.exe"
if not exist "%SAR_EXE%" (
  echo ERROR: NutateSAR.exe was not produced.
  exit /b 1
)

echo.
echo Build completed: %SAR_EXE%
echo This executable is historical and unvalidated. It is not staged in engine\bin.
exit /b 0
