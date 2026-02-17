@echo off
setlocal enabledelayedexpansion

echo Cleaning npm dependencies...
rd /s /q node_modules 2>nul
del /f /q package-lock.json 2>nul

echo Installing npm dependencies...
call pnpm.cmd install
if errorlevel 1 (
    echo Error: pnpm install failed
    exit /b 1
)

REM Use a short target path to avoid Windows MAX_PATH issues in CMake/MSBuild.
set "CARGO_TARGET_DIR=C:\mm_target"
if not exist "%CARGO_TARGET_DIR%" mkdir "%CARGO_TARGET_DIR%"

REM Required by whisper-rs-sys bindgen.
set "LIBCLANG_PATH=C:\Program Files\LLVM\bin"

REM Auto-detect Vulkan SDK if installed.
set "VULKAN_SDK="
for /f "delims=" %%d in ('dir /b /ad /o-n "C:\VulkanSDK" 2^>nul') do (
    if not defined VULKAN_SDK set "VULKAN_SDK=C:\VulkanSDK\%%d"
)
if defined VULKAN_SDK (
    echo Detected Vulkan SDK: %VULKAN_SDK%
    set "PATH=%VULKAN_SDK%\Bin;%PATH%"
)

REM Setup Visual Studio build environment (required for Rust/C++ crates).
if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" (
    call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>&1
)

REM Build llama-helper sidecar first (CPU build is the most robust on Windows).
echo Building llama-helper sidecar...
pushd ..\llama-helper
call cargo build --release
if errorlevel 1 (
    echo Error: llama-helper build failed
    popd
    exit /b 1
)
popd

REM Copy sidecar binary where tauri externalBin expects it.
for /f "tokens=2" %%i in ('rustc -vV ^| findstr "host:"') do set "TARGET_TRIPLE=%%i"
if not defined TARGET_TRIPLE set "TARGET_TRIPLE=x86_64-pc-windows-msvc"
if not exist "src-tauri\binaries" mkdir "src-tauri\binaries"
copy /Y "%CARGO_TARGET_DIR%\release\llama-helper.exe" "src-tauri\binaries\llama-helper-%TARGET_TRIPLE%.exe" >nul

echo Building the project...
if defined VULKAN_SDK (
    call pnpm.cmd run tauri:build:vulkan
) else (
    call pnpm.cmd run tauri:build:cpu
)

REM Tauri can fail at the very end if updater private key is missing.
REM If the app binary exists, treat build as usable for local execution.
if errorlevel 1 (
    if exist "%CARGO_TARGET_DIR%\release\meetily.exe" (
        echo Warning: build finished with signing/updater errors, but executable was created.
        exit /b 0
    )
    exit /b 1
)
