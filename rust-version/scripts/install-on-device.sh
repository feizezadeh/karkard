#!/bin/bash
set -e

APK_PATH="/home/mehdi/karkard/rust-version/android/app/build/outputs/apk/debug/app-debug.apk"

if [ ! -f "$APK_PATH" ]; then
    echo "Error: APK not found at $APK_PATH"
    exit 1
fi

echo "Waiting for Android device to connect via USB..."
adb wait-for-device

DEVICE_ID=$(adb devices | grep -w "device" | head -n 1 | awk '{print $1}')
echo "Device connected: $DEVICE_ID"

echo "Installing Karkard Rust APK ($APK_PATH)..."
adb -s "$DEVICE_ID" install -r "$APK_PATH"

echo "✓ Successfully installed ir.karkard.rust on device $DEVICE_ID!"
