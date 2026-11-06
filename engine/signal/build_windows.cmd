@echo off
setlocal EnableExtensions

for %%I in ("%~dp0.") do set "SCRIPT_DIR=%%~fI"
set "BUILD_DIR=%SCRIPT_DIR%\build"
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

if not defined CUDA_PATH (
  if exist "%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v13.2\bin\nvcc.exe" (
    set "CUDA_PATH=%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v13.2"
  ) else (
    for /d %%P in ("%ProgramFiles%\NVIDIA GPU Computing Toolkit\CUDA\v*") do (
      if exist "%%~fP\bin\nvcc.exe" set "CUDA_PATH=%%~fP"
    )
  )
)

if not defined CUDA_PATH (
  echo ERROR: CUDA_PATH is not set and no CUDA Toolkit installation was found.
  exit /b 1
)

set "CUDA_ARCHITECTURES=75;80;86;89"
if not "%~1"=="" set "CUDA_ARCHITECTURES=%~1"

echo Configuring NutateSignal CPU and GPU targets...
cmake -S "%SCRIPT_DIR%" -B "%BUILD_DIR%" ^
  -G "Visual Studio 18 2026" -A x64 -T "cuda=%CUDA_PATH%" ^
  -DNUTATE_BUILD_GPU=ON ^
  -DNUTATE_USE_OPENMP=ON ^
  -DCMAKE_CUDA_ARCHITECTURES="%CUDA_ARCHITECTURES%"
if errorlevel 1 exit /b 1

echo Building NutateSignal_CPU.exe and NutateSignal_GPU.exe...
set "BUILD_TARGETS=NutateSignal_CPU NutateSignal_GPU"
cmake --build "%BUILD_DIR%" --config Release --target %BUILD_TARGETS%
if errorlevel 1 exit /b 1

if not exist "%BUILD_DIR%\bin\NutateSignal_CPU.exe" (
  echo ERROR: CPU executable was not produced.
  exit /b 1
)
if not exist "%BUILD_DIR%\bin\NutateSignal_GPU.exe" (
  echo ERROR: GPU executable was not produced.
  exit /b 1
)

cmake -E make_directory "%STAGE_DIR%"
cmake -E copy_if_different "%BUILD_DIR%\bin\NutateSignal_CPU.exe" "%STAGE_DIR%\NutateSignal_CPU.exe"
cmake -E copy_if_different "%BUILD_DIR%\bin\NutateSignal_GPU.exe" "%STAGE_DIR%\NutateSignal_GPU.exe"

set "CUDA_RUNTIME_FOUND="
for %%F in ("%CUDA_PATH%\bin\cudart64_*.dll" "%CUDA_PATH%\bin\x64\cudart64_*.dll") do (
  if exist "%%~fF" (
    cmake -E copy_if_different "%%~fF" "%STAGE_DIR%\%%~nxF"
    set "CUDA_RUNTIME_FOUND=1"
  )
)
if not defined CUDA_RUNTIME_FOUND echo WARNING: The CUDA runtime DLL was not found for staging.

call :copy_first_runtime vcomp140.dll
call :copy_first_runtime msvcp140.dll
call :copy_first_runtime vcruntime140.dll
call :copy_first_runtime vcruntime140_1.dll

echo.
echo Build completed successfully.
echo CPU: %STAGE_DIR%\NutateSignal_CPU.exe
echo GPU: %STAGE_DIR%\NutateSignal_GPU.exe
exit /b 0

:copy_first_runtime
if not defined VCToolsRedistDir (
  echo WARNING: VCToolsRedistDir is not set; could not stage %~1.
  goto :eof
)
for /r "%VCToolsRedistDir%" %%F in (%~1) do (
  if exist "%%~fF" (
    cmake -E copy_if_different "%%~fF" "%STAGE_DIR%\%%~nxF"
    goto :eof
  )
)
echo WARNING: Could not locate %~1 under %VCToolsRedistDir%.
goto :eof
