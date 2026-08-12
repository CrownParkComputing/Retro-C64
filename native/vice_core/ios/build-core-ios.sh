#!/usr/bin/env bash
# Link libvicecore.dylib / libvicecore_vsid.dylib for arm64 iOS.
#
# Runs INSIDE the container (see build.sh). Consumes the Mach-O objects and
# static libraries produced by build-vice-ios-headless.sh and links them with
# the plain-C bridge plus the CoreAudio backend.
#
# ---------------------------------------------------------------------------
# Why this is a shell script and not a CMakeLists like linux/ and android/
# ---------------------------------------------------------------------------
# The Linux and Android cores intercept a dozen VICE functions with
# -Wl,--wrap=symbol. That is a GNU ld/ELF feature; ld64.lld rejects -wrap
# outright ("unknown argument '-wrap'"), and Mach-O has no equivalent flag.
#
# The same effect is reproduced by renaming symbols, which is what --wrap does
# internally:
#
#   * in the single object that DEFINES foo, rename foo -> __real_foo;
#   * in the bridge object, rename __wrap_foo -> foo.
#
# Every other translation unit still has an undefined reference to foo, which
# now binds to the bridge's wrapper, and the wrapper's call to __real_foo binds
# to the renamed original. References inside the defining object bind straight
# to __real_foo -- the same behaviour as --wrap, which only ever rewrites
# undefined references.
#
# Mach-O prefixes C symbols with an underscore, hence _foo / ___real_foo below.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$HERE/../bridge"
VICE_SRC="${VICE_SRC:-/vice}"
VICE_BUILD_DIR="${VICE_BUILD_DIR:-$VICE_SRC/build-ios-arm64-headless}"
OUT_DIR="${OUT_DIR:-$HERE/build}"
STAGE="$OUT_DIR/stage"

IOSBOX_ROOT="${IOSBOX_ROOT:-/root/.iosbox}"
IOS_SDK="${IOS_SDK:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk}"
IOS_LD="${IOS_LD:-$IOSBOX_ROOT/sdk/darwin.artifactbundle/toolset/bin/ld64.lld}"
IOS_MIN="${IOS_MIN:-13.0}"
TARGET="arm64-apple-ios${IOS_MIN}"

VS="$VICE_BUILD_DIR/src"
if [ ! -f "$VS/lib.o" ]; then
    echo "VICE iOS objects not found in $VS -- run build-vice-ios-headless.sh first" >&2
    exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT_DIR"

CFLAGS_COMMON=(-target "$TARGET" -isysroot "$IOS_SDK" -fPIC -O2 -fno-common)
LDFLAGS_COMMON=(
    -target "$TARGET" -isysroot "$IOS_SDK"
    -fuse-ld="$IOS_LD"
    -Wl,-arch,arm64
    -Wl,-platform_version,ios,"${IOS_MIN}.0",16.0.0
    -Wl,-adhoc_codesign
)

# --------------------------------------------------------------------------
# Symbol renaming (the --wrap replacement)
# --------------------------------------------------------------------------

# Rename symbols inside one member of a static library, working on a private
# copy so the VICE build tree is never modified -- the Linux and Android cores
# read the same tree. Repeated calls for the same archive accumulate.
#
# Staged copies are namespaced by variant: the game core and the SID player
# wrap different symbol sets (vsid runs with video disabled and does not wrap
# the video_canvas_* family), so they cannot share one patched libarch.a. A
# single shared copy renamed video_canvas_* out from under the vsid link left
# those symbols undefined for raster/ and video/, which still call them.
staged_path() {
    local variant="$1" rel="$2"
    echo "$STAGE/${variant}_$(echo "$rel" | tr '/' '_')"
}

stage_archive() {
    local variant="$1"; shift
    local rel="$1"; shift
    local member="$1"; shift
    local staged
    staged="$(staged_path "$variant" "$rel")"

    [ -f "$staged" ] || cp "$VS/$rel" "$staged"

    local work="$STAGE/work"
    rm -rf "$work"; mkdir -p "$work"
    ( cd "$work" && llvm-ar x "$staged" "$member" )
    local args=()
    for sym in "$@"; do
        args+=(--redefine-sym "_${sym}=___real_${sym}")
    done
    llvm-objcopy "${args[@]}" "$work/$member"
    ( cd "$work" && llvm-ar r "$staged" "$member" )
}

# Same, for one of the loose base objects in src/.
stage_object() {
    local variant="$1"; shift
    local rel="$1"; shift
    local staged
    staged="$(staged_path "$variant" "$rel")"
    local args=()
    for sym in "$@"; do
        args+=(--redefine-sym "_${sym}=___real_${sym}")
    done
    llvm-objcopy "${args[@]}" "$VS/$rel" "$staged"
}

echo "==> renaming wrapped symbols"

# Wrapped by both targets.
stage_object common log.o log_init
stage_object common init.o init_main
stage_object common vsync.o vsync_do_vsync
for variant in core vsid; do
    stage_archive "$variant" arch/headless/libarch.a archdep.o archdep_init
    stage_archive "$variant" arch/shared/sounddrv/libsounddrv.a \
        sounddummy.o sound_init_dummy_device
done

# video_init is wrapped by both; the video_canvas_* family only by the game
# core, matching the two --wrap lists in android/CMakeLists.txt.
stage_archive core arch/headless/libarch.a video.o \
    video_init video_canvas_create video_canvas_can_resize \
    video_canvas_resize video_canvas_refresh
stage_archive vsid arch/headless/libarch.a video.o video_init

# maincpu_mainloop lives in the per-machine CPU object: c64cpusc.o for the
# x64sc game core, vsidcpu.o for the SID player.
# The tape/drive status callbacks the loading indicators read. All five are
# empty stubs in the headless arch's uistatusbar.o; the bridge wraps them to
# capture the values on their way past. Game core only -- vsid has no media.
stage_archive core arch/headless/libarch.a uistatusbar.o \
    ui_display_tape_counter ui_display_tape_motor_status \
    ui_display_tape_control_status ui_display_drive_track \
    ui_display_drive_led

stage_archive core c64/libc64sc.a c64cpusc.o maincpu_mainloop
stage_archive vsid c64/libvsid.a vsidcpu.o maincpu_mainloop

# Base objects, with the three renamed ones swapped in.
BASE_NAMES="alarm attach autostart autostart-prg cbmdos cbmimage charset
    clipboard cmdline color crc32 crt debug dma event findpath fliplist gcr
    info initcmdline interrupt kbdbuf keyboard keymap lib machine-bus machine
    main mainlock m3u network opencbmlib palette profiler ram rawfile rawnet
    resources romset screenshot sha1 snapshot socket sound sysfile traps util
    vicefeatures zfile zipcode midi"
BASE_OBJECTS=()
for n in $BASE_NAMES; do
    [ -f "$VS/$n.o" ] && BASE_OBJECTS+=("$VS/$n.o")
done
BASE_OBJECTS+=("$(staged_path common log.o)" "$(staged_path common init.o)" \
               "$(staged_path common vsync.o)")

# --------------------------------------------------------------------------
# Bridge objects
# --------------------------------------------------------------------------
INCLUDES=(
    -I"$BRIDGE"
    -I"$VS"
    -I"$VICE_SRC/src"
    -I"$VICE_SRC/src/arch/headless"
    -I"$VICE_SRC/src/arch/shared"
    -I"$VICE_SRC/src/arch"
    -I"$VICE_SRC/src/c64"
    -I"$VICE_SRC/src/datasette"
    -I"$VICE_SRC/src/drive"
    -I"$VICE_SRC/src/monitor"
    -I"$VICE_SRC/src/tape"
    -I"$VICE_SRC/src/tapeport"
)

WRAPPED_SYMS="archdep_init log_init video_init init_main video_canvas_create
    video_canvas_can_resize video_canvas_resize video_canvas_refresh
    sound_init_dummy_device vsync_do_vsync maincpu_mainloop
    ui_display_tape_counter ui_display_tape_motor_status
    ui_display_tape_control_status ui_display_drive_track
    ui_display_drive_led"

# Turn the bridge's __wrap_foo definitions into plain foo, so every unresolved
# reference in VICE binds to them.
unwrap_bridge_object() {
    local args=()
    for sym in $WRAPPED_SYMS; do
        args+=(--redefine-sym "___wrap_${sym}=_${sym}")
    done
    llvm-objcopy "${args[@]}" "$1"
}

echo "==> compiling bridge"
clang "${CFLAGS_COMMON[@]}" "${INCLUDES[@]}" -c "$BRIDGE/vice_bridge.c" -o "$STAGE/vice_bridge.o"
unwrap_bridge_object "$STAGE/vice_bridge.o"
clang "${CFLAGS_COMMON[@]}" "${INCLUDES[@]}" -c "$BRIDGE/vice_vsid_bridge.c" -o "$STAGE/vice_vsid_bridge.o"
unwrap_bridge_object "$STAGE/vice_vsid_bridge.o"
clang "${CFLAGS_COMMON[@]}" "${INCLUDES[@]}" -c "$BRIDGE/audio_backend_ios.m" -o "$STAGE/audio_backend_ios.o"

# --------------------------------------------------------------------------
# Link
# --------------------------------------------------------------------------
# Archive order mirrors src/Makefile's x64sc / vsid link lines, which already
# link on Mach-O -- build-vice-ios-headless.sh produces working x64sc and vsid
# binaries with exactly this ordering.
A() { echo "$VS/$1"; }              # archive straight from the VICE build
S() { staged_path "$1" "$2"; }      # staged (symbol-renamed) copy, by variant

CORE_LIBS=(
    "$(A arch/shared/libarchdep.a)" "$(A tapeport/libtapeport.a)"
    "$(S core c64/libc64sc.a)"
    "$(A c64/cart/libc64cartsystem.a)" "$(A c64/cart/libc64cart.a)"
    "$(A c64/cart/libc64commoncart.a)" "$(A datasette/libdatasette.a)"
    "$(A drive/iec/libdriveiec.a)" "$(A drive/iecieee/libdriveiecieee.a)"
    "$(A drive/iec/c64exp/libdriveiecc64exp.a)" "$(A drive/ieee/libdriveieee.a)"
    "$(A drive/libdrive.a)" "$(A drive/tcbm/libdrivetcbm.a)"
    "$(A lib/p64/libp64.a)" "$(A iecbus/libiecbus.a)" "$(A parallel/libparallel.a)"
    "$(A vdrive/libvdrive.a)" "$(A sid/libsid.a)" "$(A monitor/libmonitor.a)"
    "$(A joyport/libjoyport.a)" "$(A samplerdrv/libsamplerdrv.a)"
    "$(S core arch/shared/sounddrv/libsounddrv.a)"
    "$(A arch/shared/mididrv/libmididrv.a)" "$(A arch/shared/socketdrv/libsocketdrv.a)"
    "$(A arch/shared/hwsiddrv/libhwsiddrv.a)" "$(A gfxoutputdrv/libgfxoutputdrv.a)"
    "$(A printerdrv/libprinterdrv.a)" "$(A diskimage/libdiskimage.a)"
    "$(A fsdevice/libfsdevice.a)" "$(A tape/libtape.a)" "$(A fileio/libfileio.a)"
    "$(A serial/libserial.a)" "$(A core/libcore.a)" "$(A rs232drv/librs232drv.a)"
    "$(A viciisc/libviciisc.a)" "$(A raster/libraster.a)" "$(A userport/libuserport.a)"
    "$(A diag/libdiag.a)" "$(A core/rtc/librtc.a)" "$(A video/libvideo.a)"
    "$(S core arch/headless/libarch.a)"
    "$(A imagecontents/libimagecontents.a)" "$(A c64/libc64scstubs.a)"
    "$(A resid/libresid.a)" "$(A hvsc/libhvsc.a)" "$(A lib/libzmbv/libzmbv.a)"
    "$(S core arch/headless/libarch.a)" "$(A arch/shared/libarchdep.a)"
    "$(A lib/linenoise-ng/liblinenoiseng.a)"
)

VSID_LIBS=(
    "$(A arch/shared/libarchdep.a)"
    "$(S vsid c64/libvsid.a)"
    "$(A sid/libsid.a)" "$(A monitor/libmonitor.a)"
    "$(S vsid arch/shared/sounddrv/libsounddrv.a)"
    "$(A arch/shared/mididrv/libmididrv.a)" "$(A arch/shared/socketdrv/libsocketdrv.a)"
    "$(A arch/shared/hwsiddrv/libhwsiddrv.a)" "$(A serial/libserial.a)"
    "$(A core/libcore.a)" "$(A vicii/libvicii.a)" "$(A raster/libraster.a)"
    "$(A video/libvideo.a)" "$(S vsid arch/headless/libarch.a)"
    "$(A resid/libresid.a)" "$(A joyport/libjoyport.a)" "$(A hvsc/libhvsc.a)"
    "$(A datasette/libdatasette.a)" "$(A c64/libvsidstubs.a)" "$(A lib/md5/libmd5.a)"
    "$(S vsid arch/headless/libarch.a)" "$(A arch/shared/libarchdep.a)"
    "$(A lib/linenoise-ng/liblinenoiseng.a)"
)

FRAMEWORKS=(-framework AudioToolbox -framework AVFoundation
            -framework Foundation -framework CoreFoundation)

echo "==> linking libvicecore.dylib"
clang++ "${LDFLAGS_COMMON[@]}" -dynamiclib \
    -install_name "@rpath/libvicecore.dylib" \
    -o "$OUT_DIR/libvicecore.dylib" \
    "$STAGE/vice_bridge.o" "$STAGE/audio_backend_ios.o" \
    "${BASE_OBJECTS[@]}" "${CORE_LIBS[@]}" \
    -lz -lc++ "${FRAMEWORKS[@]}"

echo "==> linking libvicecore_vsid.dylib"
clang++ "${LDFLAGS_COMMON[@]}" -dynamiclib \
    -install_name "@rpath/libvicecore_vsid.dylib" \
    -o "$OUT_DIR/libvicecore_vsid.dylib" \
    "$STAGE/vice_vsid_bridge.o" "$STAGE/audio_backend_ios.o" \
    "${BASE_OBJECTS[@]}" "${VSID_LIBS[@]}" \
    -lz -lc++ "${FRAMEWORKS[@]}"

echo "==> built:"
ls -lh "$OUT_DIR"/*.dylib
