@echo off
setlocal EnableExtensions

for %%I in ("%~dp0.") do set "SCRIPT_DIR=%%~fI"
set "BUILD_DIR=%SCRIPT_DIR%\build-msvc"
for %%I in ("%SCRIPT_DIR%\..\bin") do set "STAGE_DIR=%%~fI"

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

echo Configuring NutateNoise and its mathematical tests...
cmake -S "%SCRIPT_DIR%" -B "%BUILD_DIR%" ^
  -G "Visual Studio 18 2026" -A x64 ^
  -DBUILD_TESTING=ON
if errorlevel 1 exit /b 1

echo Building NutateNoise.exe and NutateNoiseMathTests.exe...
cmake --build "%BUILD_DIR%" --config Release --target NutateNoise NutateNoiseMathTests EssentialTests
if errorlevel 1 exit /b 1

echo Running NutateNoise mathematical tests...
ctest --test-dir "%BUILD_DIR%" -C Release --output-on-failure
if errorlevel 1 exit /b 1

set "NOISE_EXE=%BUILD_DIR%\bin\NutateNoise.exe"
if not exist "%NOISE_EXE%" (
  echo ERROR: NutateNoise.exe was not produced.
  exit /b 1
)

cmake -E make_directory "%STAGE_DIR%"
cmake -E copy_if_different "%NOISE_EXE%" "%STAGE_DIR%\NutateNoise.exe"
if errorlevel 1 exit /b 1

call :copy_first_runtime msvcp140.dll
call :copy_first_runtime vcruntime140.dll
call :copy_first_runtime vcruntime140_1.dll

echo.
echo Build and tests completed successfully.
echo Noise: %STAGE_DIR%\NutateNoise.exe
exit /b 0

:copy_first_runtime
if not defined VCToolsRedistDir (
  echo WARNING: VCToolsRedistDir is not set; could not stage %~1.
  goto :eof
)
for /d %%D in ("%VCToolsRedistDir%x64\Microsoft.VC*.CRT") do (
  if exist "%%~fD\%~1" (
    cmake -E copy_if_different "%%~fD\%~1" "%STAGE_DIR%\%~1"
    goto :eof
  )
)
echo WARNING: Could not locate the x64 %~1 under %VCToolsRedistDir%.
goto :eof
