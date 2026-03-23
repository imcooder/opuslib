#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPUS_SRC="$ROOT_DIR/thirdparty/opus-1.6"
BUILD_ROOT="$ROOT_DIR/ios/opus-build"
IOS_DEPLOYMENT_TARGET="15.1"

if [ ! -d "$OPUS_SRC" ]; then
  echo "Error: opus source not found at $OPUS_SRC"
  echo "Run 'node scripts/postinstall.js' first."
  exit 1
fi

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

BUILD_DEVICE="$BUILD_ROOT/_build_device"
BUILD_SIM="$BUILD_ROOT/_build_sim"

echo "=== Building libopus for iOS device (arm64) ==="
mkdir -p "$BUILD_DEVICE"
cmake -S "$OPUS_SRC" -B "$BUILD_DEVICE" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DOPUS_DRED=OFF \
  -DOPUS_BUILD_SHARED_LIBRARY=OFF \
  -DOPUS_BUILD_TESTING=OFF \
  -DOPUS_BUILD_PROGRAMS=OFF \
  -DCMAKE_INSTALL_PREFIX="$BUILD_DEVICE/install"

cmake --build "$BUILD_DEVICE" -j "$(sysctl -n hw.ncpu)"
cmake --install "$BUILD_DEVICE"

echo "=== Building libopus for iOS Simulator (arm64 + x86_64) ==="
mkdir -p "$BUILD_SIM"
cmake -S "$OPUS_SRC" -B "$BUILD_SIM" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DOPUS_DRED=OFF \
  -DOPUS_BUILD_SHARED_LIBRARY=OFF \
  -DOPUS_BUILD_TESTING=OFF \
  -DOPUS_BUILD_PROGRAMS=OFF \
  -DCMAKE_INSTALL_PREFIX="$BUILD_SIM/install"

cmake --build "$BUILD_SIM" -j "$(sysctl -n hw.ncpu)"
cmake --install "$BUILD_SIM"

echo "=== Creating XCFramework ==="
XCFW_OUTPUT="$BUILD_ROOT/libopus.xcframework"
rm -rf "$XCFW_OUTPUT"

xcodebuild -create-xcframework \
  -library "$BUILD_DEVICE/install/lib/libopus.a" \
  -headers "$BUILD_DEVICE/install/include/opus" \
  -library "$BUILD_SIM/install/lib/libopus.a" \
  -headers "$BUILD_SIM/install/include/opus" \
  -output "$XCFW_OUTPUT"

rm -rf "$BUILD_DEVICE" "$BUILD_SIM"

echo "=== Done ==="
echo "XCFramework created at: $XCFW_OUTPUT"
lipo -info "$XCFW_OUTPUT/ios-arm64/libopus.a"
lipo -info "$XCFW_OUTPUT/ios-arm64_x86_64-simulator/libopus.a"
