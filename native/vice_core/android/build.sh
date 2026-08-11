#!/usr/bin/env bash
# Cross-compiles libvicecore.so / libvicecore_vsid.so for arm64-v8a using
# the NDK's CMake toolchain file, then copies them into the Flutter
# project's jniLibs so `flutter build apk` picks them up.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$HOME/Android/Sdk/ndk/28.2.13676358}}"
API="${ANDROID_API:-26}"
BUILD_DIR="${BUILD_DIR:-$HERE/build}"
JNI_LIBS_DIR="${JNI_LIBS_DIR:-$HERE/../../../flutter_app/android/app/src/main/jniLibs/arm64-v8a}"

if [ ! -f "$NDK/build/cmake/android.toolchain.cmake" ]; then
  echo "NDK toolchain file not found under $NDK" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM="android-${API}" \
  -DCMAKE_BUILD_TYPE=Release \
  "$HERE"

cmake --build . -j"${JOBS:-4}"

mkdir -p "$JNI_LIBS_DIR"
cp -v "$BUILD_DIR/libvicecore.so" "$JNI_LIBS_DIR/"
if [ -f "$BUILD_DIR/libvicecore_vsid.so" ]; then
  cp -v "$BUILD_DIR/libvicecore_vsid.so" "$JNI_LIBS_DIR/"
fi

echo "Done. Libraries in $JNI_LIBS_DIR:"
ls -la "$JNI_LIBS_DIR"
