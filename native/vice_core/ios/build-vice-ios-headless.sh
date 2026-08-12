#!/usr/bin/env bash
# Build VICE's headless object files and static libs for arm64 iOS.
#
# Runs INSIDE the mobaiapp/iosbox container (see build.sh, which is the host
# entry point). Mirrors build-vice-android-headless.sh, but points the
# autotools cross-build at the iOS SDK via the ios-clang wrappers.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VICE_SRC="${VICE_SRC:-/vice}"
BUILD_DIR="${VICE_BUILD_DIR:-$VICE_SRC/build-ios-arm64-headless}"

IOSBOX_ROOT="${IOSBOX_ROOT:-/root/.iosbox}"
export IOS_SDK="${IOS_SDK:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk}"
export IOS_LD="${IOS_LD:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/toolset/bin/ld64.lld}"
export IOS_MIN="${IOS_MIN:-13.0}"

if [ ! -x "$VICE_SRC/configure" ]; then
    echo "VICE source/configure not found at $VICE_SRC" >&2
    exit 1
fi
if [ ! -d "$IOS_SDK" ]; then
    echo "iOS SDK not found at $IOS_SDK" >&2
    exit 1
fi

export PATH="$HERE/toolchain:$PATH"
export CC=ios-clang
export CXX=ios-clang++
# configure sees the Darwin headers in the SDK and takes its macOS branch,
# which probes for an Objective-C compiler. Left unset it falls back to the
# host's /lib/cpp, which knows nothing about the iOS sysroot and fails the
# sanity check.
export OBJC=ios-clang
export OBJCPP="ios-clang -E"
export CPP="ios-clang -E"
export CXXCPP="ios-clang++ -E"
export CFLAGS="${CFLAGS:--fPIC -O2}"
export CXXFLAGS="${CXXFLAGS:--fPIC -O2}"
export LDFLAGS="${LDFLAGS:-}"

# GNU ar/ranlib write ELF-flavoured archives that the Mach-O linker rejects.
export AR="llvm-ar"
export RANLIB="llvm-ranlib"
export STRIP="llvm-strip"

# Don't let configure discover host libraries -- nothing on this Linux box is
# linkable into an iOS binary.
export PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-/tmp/empty-pkg-config}"
mkdir -p /tmp/empty-pkg-config

# Same reasoning as the Linux/Android scripts: the release tarball ships the
# generated files, and these tools aren't needed for a headless build.
export DOS2UNIX="${DOS2UNIX:-true}"
export XA="${XA:-true}"

# Take VICE's "puredarwin" path rather than its macOS path.
#
# --host=aarch64-apple-darwin makes configure match darwin* and go looking for
# a Mac: it wants otool, probes /opt/local for MacPorts (a hard error under
# cross-compilation, since AC_CHECK_FILE cannot test the build host's
# filesystem for the target), and works out a macOS minimum version. None of
# that applies to iOS. configure.ac already has the escape hatch we want -- if
# the CoreServices header is missing it sets host_os=puredarwin to "make the
# configure think it is just another unix", which is precisely how iOS should
# be treated here. Those headers do exist in the iOS SDK, so we pre-seed
# autoconf's cache to say otherwise. Pre-set ac_cv_* variables are the
# documented way to override a configure probe.
export ac_cv_header_CoreServices_CoreServices_h=no
export ac_cv_header_CoreVideo_CVHostTime_h=no

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
if [ "${VICE_CLEAN:-0}" = "1" ] && [ -f Makefile ]; then
    make clean || true
fi

# --host tells autotools this is a cross-build, so configure links its test
# programs but never tries to run them.
"$VICE_SRC/configure" \
    --host=aarch64-apple-darwin \
    --enable-headlessui \
    --disable-html-docs \
    --disable-pdf-docs \
    --disable-realdevice \
    --disable-rs232 \
    --disable-ipv6 \
    --disable-openmp \
    --disable-usbsid \
    --without-alsa \
    --without-pulse \
    --without-sdlsound \
    --without-portaudio \
    --without-png \
    --without-gif \
    --without-flac \
    --without-mpg123 \
    --without-vorbis \
    --without-lame \
    --without-libcurl \
    --with-resid \
    --with-fastsid

# -k, deliberately: c1541 (a standalone disk-image utility, not part of the
# emulator core and not linked by us) calls system(), which the iOS SDK marks
# __attribute__((unavailable)). That one file cannot compile for iOS and never
# needs to. Everything the core links -- the base objects and the per-subsystem
# static libraries -- builds fine, so keep going and judge the build by whether
# those artifacts exist rather than by make's exit status.
make -k -j"${JOBS:-4}" || true

missing=0
for artifact in \
    src/lib.o \
    src/main.o \
    src/arch/shared/libarchdep.a \
    src/arch/headless/libarch.a \
    src/c64/libc64sc.a \
    src/c64/libc64scstubs.a \
    src/c64/libvsid.a \
    src/c64/libvsidstubs.a \
    src/sid/libsid.a \
    src/resid/libresid.a \
    src/core/libcore.a \
    src/monitor/libmonitor.a \
    src/video/libvideo.a \
    src/vdrive/libvdrive.a \
    src/drive/libdrive.a
do
    if [ ! -f "$BUILD_DIR/$artifact" ]; then
        echo "missing required artifact: $artifact" >&2
        missing=1
    fi
done
if [ "$missing" != "0" ]; then
    echo "VICE iOS build did not produce the objects the core links against." >&2
    exit 1
fi

echo "Built iOS arm64 VICE headless objects in $BUILD_DIR"
