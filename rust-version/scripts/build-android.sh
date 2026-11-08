#!/bin/bash
set -e

echo "=== Building Karkard for Android ==="
cd "$(dirname "$0")/.."

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}"
export NDK_HOME="$ANDROID_NDK_HOME"

echo "Using ANDROID_HOME: $ANDROID_HOME"
echo "Using ANDROID_NDK_HOME: $ANDROID_NDK_HOME"

# Check Android targets
TARGETS=("aarch64-linux-android" "armv7-linux-androideabi" "x86_64-linux-android")
for target in "${TARGETS[@]}"; do
    if ! rustup target list | grep "$target (installed)" > /dev/null; then
        echo "Installing target $target..."
        rustup target add "$target"
    fi
done

echo "-> Compiling core library for Android targets..."
for target in "${TARGETS[@]}"; do
    echo "  Compiling for $target..."
    cargo build --package karkard-core --target "$target" --release
done

echo "✓ Android targets built successfully in target/[target]/release/"
