#!/usr/bin/env bash
# Build VICE's headless (no GTK UI) object files and static libs for the
# native Linux x86_64 host. Mirrors
# ~/AndroidStudioProjects/VICEAndroid/tools/build-vice-android-headless.sh
# but targets the host toolchain instead of the Android NDK, and points at
# the existing shared VICE-source checkout rather than copying the ~50MB
# source tree into this project.
set -euo pipefail

VICE_SRC="${VICE_SRC:-$HOME/AndroidStudioProjects/VICE-source/vice-3.10}"
BUILD_DIR="${VICE_BUILD_DIR:-$VICE_SRC/build-linux-x64-headless}"

if [ ! -x "$VICE_SRC/configure" ]; then
  echo "VICE source/configure not found at $VICE_SRC" >&2
  exit 1
fi

mkdir -p "$BUILD_DIR"

export CC="${CC:-gcc}"
export CXX="${CXX:-g++}"
export CFLAGS="${CFLAGS:--fPIC -O2}"
export CXXFLAGS="${CXXFLAGS:--fPIC -O2}"
export LDFLAGS="${LDFLAGS:-}"
export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"

# As with the Android build, treat the release tarball's already-generated
# files as good enough; these external tools aren't needed for a headless
# build and may not be installed.
export DOS2UNIX="${DOS2UNIX:-true}"
export XA="${XA:-true}"

cd "$BUILD_DIR"
if [ "${VICE_CLEAN:-0}" = "1" ] && [ -f Makefile ]; then
  make clean
fi

"$VICE_SRC/configure" \
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

make -j"${JOBS:-$(nproc)}"

echo "Built Linux x64 VICE headless binaries:"
file "$BUILD_DIR/src/x64sc" || true
