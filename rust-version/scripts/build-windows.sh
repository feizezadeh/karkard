#!/bin/bash
set -e

echo "=== Building Karkard for Windows (x86_64) ==="
cd "$(dirname "$0")/.."

# Check if target is installed
if ! rustup target list | grep "x86_64-pc-windows-gnu (installed)" > /dev/null; then
    echo "Adding x86_64-pc-windows-gnu target..."
    rustup target add x86_64-pc-windows-gnu
fi

echo "-> Building Windows .exe binary..."
cargo build --package karkard-app --target x86_64-pc-windows-gnu --release

echo "✓ Windows build complete: target/x86_64-pc-windows-gnu/release/karkard-app.exe"
