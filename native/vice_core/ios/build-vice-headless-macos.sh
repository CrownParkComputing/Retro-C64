#!/usr/bin/env bash
# Build VICE's headless objects for iOS, natively on a Mac.
#
#     IOS_PLATFORM=iphonesimulator native/vice_core/ios/build-vice-headless-macos.sh
#     IOS_PLATFORM=iphoneos       native/vice_core/ios/build-vice-headless-macos.sh
#
# The existing build-vice-ios-headless.sh runs inside the mobaiapp/iosbox
# container and needs Linux plus an extracted iOS SDK. This does the same job
# with Xcode's own toolchain, so the cores can be rebuilt on a Mac -- which
# matters because they are COMMITTED, and a core that drifts behind
# native/vice_core/bridge fails in ways nothing points at: a missing
# vice_core_set_prg_inject turned setPrgInject into a no-op and left the
# bundled demo dying at "?DEVICE NOT PRESENT".
#
# No clang wrappers here. Cross-compiling Darwin-to-Darwin needs only -target
# and -isysroot; the linker is already the right one, which is the whole reason
# the Linux path needs ld64.lld and this does not.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VICE_SRC="${VICE_SRC_HOST:-$HOME/AndroidStudioProjects/VICE-source/vice-3.10}"
IOS_PLATFORM="${IOS_PLATFORM:-iphonesimulator}"
IOS_MIN="${IOS_MIN:-15.0}"

case "$IOS_PLATFORM" in
  iphonesimulator) TRIPLE="arm64-apple-ios${IOS_MIN}-simulator" ;;
  iphoneos)        TRIPLE="arm64-apple-ios${IOS_MIN}" ;;
  *) echo "IOS_PLATFORM must be iphoneos or iphonesimulator" >&2; exit 1 ;;
esac
SDK="$(xcrun --sdk "$IOS_PLATFORM" --show-sdk-path)"
BUILD_DIR="${VICE_BUILD_DIR:-$VICE_SRC/build-$IOS_PLATFORM-headless}"

[ -x "$VICE_SRC/configure" ] || { echo "no configure at $VICE_SRC" >&2; exit 1; }

export CC="$(xcrun -f clang) -target $TRIPLE -isysroot $SDK"
export CXX="$(xcrun -f clang++) -target $TRIPLE -isysroot $SDK"
export CPP="$CC -E"
export CXXCPP="$CXX -E"
export OBJC="$CC"
export OBJCPP="$CC -E"
export CFLAGS="${CFLAGS:--fPIC -O2}"
export CXXFLAGS="${CXXFLAGS:--fPIC -O2}"
export AR="$(xcrun -f ar)"
export RANLIB="$(xcrun -f ranlib)"
export STRIP="$(xcrun -f strip)"

# Nothing installed on this Mac is linkable into an iOS binary, so configure
# must not find any of it -- and it must not refuse to run for want of the
# tool either. configure hard-errors without a pkg-config on PATH ("Could not
# locate pkg-config, please install pkg-config") while every answer it could
# give would be wrong here, so it gets a stub that reports nothing found.
STUB_BIN="$(mktemp -d)/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/pkg-config" <<'STUB'
#!/bin/sh
# Always "not installed". Anything on this Mac is a macOS library and cannot
# be linked into an iOS binary, so a real answer would only mislead configure.
case "$1" in
  # autoconf's PKG_PROG_PKG_CONFIG gates on this one, not --version, and it
  # must succeed or configure stops at "Could not locate pkg-config".
  --atleast-pkgconfig-version) exit 0 ;;
  --version) echo "0.29.2"; exit 0 ;;
esac
# Every other query: nothing found.
exit 1
STUB
chmod +x "$STUB_BIN/pkg-config"
export PATH="$STUB_BIN:$PATH"
export PKG_CONFIG="$STUB_BIN/pkg-config"
export PKG_CONFIG_LIBDIR=/tmp/empty-pkg-config
mkdir -p /tmp/empty-pkg-config

export DOS2UNIX="${DOS2UNIX:-true}"
export XA="${XA:-true}"

# Take VICE's "puredarwin" path rather than its macOS one. With a darwin host
# configure goes hunting for a Mac -- otool, /opt/local, a macOS minimum
# version -- none of which applies to iOS. configure.ac already treats a
# missing CoreServices header as "just another unix", so the probe is
# pre-seeded to say it is absent. Pre-set ac_cv_* is the documented override.
export ac_cv_header_CoreServices_CoreServices_h=no
export ac_cv_header_CoreVideo_CVHostTime_h=no

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# --build must DIFFER from --host or autoconf never enters cross mode and runs
# its test programs, which cannot execute for a different platform.
"$VICE_SRC/configure" \
    --build=x86_64-apple-darwin \
    --host=aarch64-apple-darwin \
    --enable-headlessui \
    --disable-html-docs --disable-pdf-docs \
    --disable-realdevice --disable-rs232 --disable-ipv6 \
    --disable-openmp --disable-usbsid \
    --without-alsa --without-pulse --without-sdlsound --without-portaudio \
    --without-png --without-gif --without-flac --without-mpg123 \
    --without-vorbis --without-lame --without-libcurl \
    --with-resid --with-fastsid

# -k, deliberately: c1541 calls system(), which the iOS SDK marks unavailable.
# It is a standalone disk utility, not part of the core, and nothing links it.
# Judge the build by whether the core's objects exist, not by make's status.
make -k -j"${JOBS:-$(sysctl -n hw.ncpu)}" || true

echo
echo "objects in $BUILD_DIR/src:"
ls "$BUILD_DIR/src"/*.o 2>/dev/null | wc -l
