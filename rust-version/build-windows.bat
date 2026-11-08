@echo off
echo ========================================================
echo Building Karkard Windows Release (Rust + Tauri v2)
echo ========================================================

cargo build --release --package karkard-app

if %ERRORLEVEL% equ 0 (
    echo.
    echo [SUCCESS] Windows executable built successfully!
    echo Location: target\release\karkard-app.exe
) else (
    echo.
    echo [ERROR] Build failed! Please ensure Rust and MSVC C++ tools are installed.
)
pause
