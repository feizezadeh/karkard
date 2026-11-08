#!/bin/bash
set -e

echo "=== Building Karkard for Linux (x86_64) ==="
cd "$(dirname "$0")/.."

# Compile core tests first
echo "-> Running verification tests..."
cargo test --package karkard-core

# Build release application
echo "-> Building release binary..."
cargo build --package karkard-app --release

echo "✓ Linux build successful! Output binary located at: target/release/karkard-app"
