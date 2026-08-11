#!/usr/bin/env bash
# Cross-compile VICE's headless object files and static libs for iOS, from
# the same shared VICE-source checkout the Linux and Android builds use.
# Mirrors native/vice_core/linux/build-vice-linux-headless.sh, with three
# iOS-specific twists documented below.
#
#   ./build-vice-ios-headless.sh                    # device, arm64
#   ./build-vice-ios-headless.sh --sdk iphonesimulator --arch x86_64
#
# 1. HOST TRIPLET. --host=aarch64-apple-darwin makes configure take its
#    macOS branch: -mmacosx-version-min (which clang refuses alongside
#    -mios-version-min), -framework AppKit/CoreText, and MacPorts/Homebrew
#    include paths, none of which exist on iOS. <arch>-apple-ios is accepted
#    by config.sub and lands in the generic UNIX branch instead.
#
# 2. TARGET FLAGS LIVE IN $CC, NOT $CFLAGS. VICE's configure replaces CFLAGS
#    with its own warning set, so an -isysroot passed in CFLAGS is dropped
#    and every header check fails ("time.h not found").
#
# 3. --wrap EMULATION. See wrap_defines() below: Apple's ld has no
#    -Wl,--wrap, so the same interception is done with -D renames at compile
#    time.
#
# c1541 (VICE's standalone disk-image tool, not part of the core) cannot
# build for iOS -- it calls system(), which the iOS SDK marks unavailable.
# The build therefore runs under `make -k` and this script verifies the
# objects and archives the bridge actually needs, rather than make's exit
# code.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VICE_SRC="${VICE_SRC:-$HOME/AndroidStudioProjects/VICE-source/vice-3.10}"
SDK_NAME="iphoneos"
ARCH="${ARCH:-arm64}"
IOS_MIN="${IOS_MIN:-13.0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --sdk) SDK_NAME="$2"; shift 2 ;;
    --arch) ARCH="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$SDK_NAME" in
  iphoneos)        MIN_FLAG="-mios-version-min=$IOS_MIN"; BUILD_TAG="ios" ;;
  iphonesimulator) MIN_FLAG="-mios-simulator-version-min=$IOS_MIN"; BUILD_TAG="iossim" ;;
  *) echo "--sdk must be iphoneos or iphonesimulator" >&2; exit 1 ;;
esac

case "$ARCH" in
  arm64)  HOST_TRIPLET="aarch64-apple-ios" ;;
  x86_64) HOST_TRIPLET="x86_64-apple-ios" ;;
  *) echo "--arch must be arm64 or x86_64" >&2; exit 1 ;;
esac

BUILD_DIR="${VICE_BUILD_DIR:-$VICE_SRC/build-$BUILD_TAG-$ARCH-headless}"

if [ ! -x "$VICE_SRC/configure" ]; then
  echo "VICE source/configure not found at $VICE_SRC" >&2
  echo "Download vice-3.10.tar.gz from https://vice-emu.sourceforge.io/ and" >&2
  echo "extract it there, or set VICE_SRC." >&2
  exit 1
fi

SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
TARGET_FLAGS="-arch $ARCH -isysroot $SDK_PATH $MIN_FLAG"

# ---------------------------------------------------------------------------
# --wrap emulation
#
# The bridges intercept a handful of VICE functions with GNU ld's
# -Wl,--wrap=X (see native/vice_core/{linux,android}/CMakeLists.txt): every
# reference to X is redirected to __wrap_X, which the bridge defines, and the
# bridge reaches the original through __real_X. Apple's ld has no such flag
# ("ld: unknown options: --wrap=..."), so we reproduce it with the
# preprocessor:
#
#   - the whole tree is compiled with -DX=__wrap_X, so every *reference*
#     to X becomes a reference to the bridge's __wrap_X;
#   - the single file that *defines* X is recompiled with -DX=__real_X
#     instead, so the original lands under the name the bridge calls.
#
# This matches --wrap down to its one subtlety: a call to X from inside X's
# own file is not redirected (the assembler binds it locally), and here it
# likewise stays a call to __real_X.
# ---------------------------------------------------------------------------

WRAPPED_SYMBOLS=(
  archdep_init
  log_init
  video_init
  init_main
  video_canvas_create
  video_canvas_can_resize
  video_canvas_resize
  video_canvas_refresh
  sound_init_dummy_device
  vsync_do_vsync
  maincpu_mainloop
)

# "<source files>:<the symbols those files define>". Everything else in the
# tree only ever references them. Files that define the same symbol are
# grouped so they can share one recompile pass -- maincpu_mainloop has one
# definition per emulated machine (only x64sc's and vsid's are ever linked
# here, but leaving the others as __wrap_ would be a trap for whoever adds
# a machine next).
DEFINING_FILES=(
  "arch/headless/archdep.c:archdep_init"
  "log.c:log_init"
  "init.c:init_main"
  "arch/headless/video.c:video_init video_canvas_create video_canvas_can_resize video_canvas_resize video_canvas_refresh"
  "arch/shared/sounddrv/sounddummy.c:sound_init_dummy_device"
  "vsync.c:vsync_do_vsync"
  "c64/c64cpusc.c c64/vsidcpu.c c64/c64cpu.c c128/c128cpu.c c64dtv/c64dtvcpu.c cbm2/cbm2cpu.c pet/petcpu.c plus4/plus4cpu.c scpu64/scpu64cpu.c vic20/vic20cpu.c:maincpu_mainloop"
)

# Prints -D flags mapping every wrapped symbol to __wrap_, except the ones
# named in $1, which map to __real_.
wrap_defines() {
  local real_syms=" ${1:-} "
  local sym
  for sym in "${WRAPPED_SYMBOLS[@]}"; do
    if [[ "$real_syms" == *" $sym "* ]]; then
      printf ' -D%s=__real_%s' "$sym" "$sym"
    else
      printf ' -D%s=__wrap_%s' "$sym" "$sym"
    fi
  done
}

BASE_CFLAGS="-O2 -fno-common"
WRAP_CFLAGS="$(wrap_defines)"

# VICE's configure hard-requires pkg-config to probe optional libraries.
# This build disables all of them, and Homebrew may not be writable, so a
# stub that never finds anything is enough.
if ! command -v pkg-config >/dev/null 2>&1; then
  STUB_BIN="$BUILD_DIR/stubbin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/pkg-config" <<'STUB'
#!/bin/sh
# Stub: this build disables every optional library, so nothing is ever found.
case "$1" in
  --version) echo "0.29.2"; exit 0 ;;
  --atleast-pkgconfig-version) exit 0 ;;
esac
exit 1
STUB
  chmod +x "$STUB_BIN/pkg-config"
  export PATH="$STUB_BIN:$PATH"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

export CC="$(xcrun -f clang) $TARGET_FLAGS"
export CXX="$(xcrun -f clang++) $TARGET_FLAGS"
export AR="$(xcrun -f ar)"
export RANLIB="$(xcrun -f ranlib)"
export LDFLAGS=""
# As with the Android and Linux builds, treat the release tarball's
# already-generated files as good enough.
export DOS2UNIX="${DOS2UNIX:-true}"
export XA="${XA:-true}"

if [ "${VICE_CLEAN:-0}" = "1" ] && [ -f Makefile ]; then
  make clean || true
fi

if [ ! -f Makefile ]; then
  # The wrap defines go in at configure time so that a bare `make` in this
  # build dir stays consistent with what this script produces.
  CFLAGS="$BASE_CFLAGS$WRAP_CFLAGS" \
  CXXFLAGS="$BASE_CFLAGS" \
  "$VICE_SRC/configure" \
    --host="$HOST_TRIPLET" \
    --build="$("$VICE_SRC/config.guess")" \
    --enable-headlessui \
    --disable-html-docs \
    --disable-pdf-docs \
    --disable-realdevice \
    --disable-rs232 \
    --disable-ipv6 \
    --disable-openmp \
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
fi

JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

echo "=== pass 1: whole tree, wrapped symbols redirected to __wrap_* ==="
{ make -k -j"$JOBS" 2>&1 || true; } > make.log
tail -3 make.log

echo "=== pass 2: recompiling the files that define them ==="
for entry in "${DEFINING_FILES[@]}"; do
  files="${entry%%:*}"
  syms="${entry#*:}"
  echo "  __real_{${syms// /,}} <- ${files// /, }"
  for file in $files; do
    if [ ! -f "$VICE_SRC/src/$file" ]; then
      echo "expected VICE source file missing: src/$file" >&2
      exit 1
    fi
    touch "$VICE_SRC/src/$file"
  done
  { make -k -j"$JOBS" CFLAGS="$BASE_CFLAGS$(wrap_defines "$syms")" 2>&1 || true; } >> make.log
done

# ---------------------------------------------------------------------------
# Verify. `make -k` always exits non-zero here (c1541), so check the actual
# artifacts instead: every object and archive the bridge links, plus the
# wrap rename having come out the way it was meant to.
# ---------------------------------------------------------------------------
echo "=== verifying ==="

BASE_OBJECTS="alarm attach autostart autostart-prg cbmdos cbmimage charset
clipboard cmdline color crc32 crt debug dma event findpath fliplist gcr info
init initcmdline interrupt kbdbuf keyboard keymap lib log machine-bus machine
main mainlock m3u network opencbmlib palette profiler ram rawfile rawnet
resources romset screenshot sha1 snapshot socket sound sysfile traps util
vicefeatures vsync zfile zipcode midi"

missing=0
for obj in $BASE_OBJECTS; do
  if [ ! -f "$BUILD_DIR/src/$obj.o" ]; then
    echo "missing object: src/$obj.o" >&2
    missing=1
  fi
done
for lib in src/arch/shared/libarchdep.a src/arch/headless/libarch.a \
           src/c64/libc64sc.a src/c64/libvsid.a src/sid/libsid.a \
           src/resid/libresid.a src/core/libcore.a src/viciisc/libviciisc.a \
           src/video/libvideo.a src/drive/libdrive.a; do
  if [ ! -f "$BUILD_DIR/$lib" ]; then
    echo "missing archive: $lib" >&2
    missing=1
  fi
done
if [ "$missing" != "0" ]; then
  echo "VICE iOS build incomplete -- see $BUILD_DIR/make.log" >&2
  exit 1
fi

# A __wrap_X *defined* anywhere in the VICE tree means pass 2 missed the file
# that defines X; that would collide with the bridge's own definition at link
# time. A missing __real_X means the rename didn't happen at all.
symbols="$(find "$BUILD_DIR/src" \( -name '*.o' -o -name '*.a' \) -print0 \
  | xargs -0 nm -g 2>/dev/null || true)"
# (Herestrings, not pipes: `grep -q` exits at the first match, and the
# SIGPIPE that gives the writer would trip `set -o pipefail`.)
for sym in "${WRAPPED_SYMBOLS[@]}"; do
  if grep -qE "^[0-9a-f]* T ___wrap_$sym\$" <<< "$symbols"; then
    echo "wrap emulation broken: VICE still defines __wrap_$sym" >&2
    exit 1
  fi
  if ! grep -qE "^[0-9a-f]* T ___real_$sym\$" <<< "$symbols"; then
    echo "wrap emulation broken: nothing defines __real_$sym" >&2
    exit 1
  fi
done

echo "Built $SDK_NAME/$ARCH VICE headless objects in $BUILD_DIR"
