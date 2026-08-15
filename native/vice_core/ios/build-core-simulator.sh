#!/bin/sh
# Link libvicecore / libvicecore_vsid for the iOS Simulator, natively on a Mac.
#
#     VICE_BUILD_DIR=/path/to/vice-sim-build native/vice_core/ios/build-core-simulator.sh
#
# The device cores are cross-compiled on Linux inside the iosbox container
# (build.sh -> build-vice-ios-headless.sh -> build-core-ios.sh). Nothing about
# that pipeline runs on a Mac, so the simulator archives in
# flutter_app/ios/vicecore/iphonesimulator/ went stale: they predate a9a1a4d
# and every .d64 in the simulator dies on ?DEVICE NOT PRESENT, which reads as a
# regression and is not one. This builds them from the same VICE source with
# Xcode's own toolchain, so the simulator runs the same emulator the device
# does.
#
# TWO SUBSTITUTIONS make that possible without the Linux toolchain:
#
#   llvm-objcopy --redefine-sym  ->  ld -r -alias + -unexported_symbol
#     macOS ships no objcopy, and Xcode's LLVM tools omit llvm-objcopy. The
#     --wrap emulation only needs a defined global renamed, which ld64 does:
#     -alias publishes the new name, -unexported_symbol demotes the old one to
#     a local. The result is what --redefine-sym produces, including the detail
#     that callers inside the same object keep reaching the original.
#
#   pkg-config  ->  a stub that answers "not found"
#     configure refuses to run without the binary, but must not find anything:
#     nothing on this Mac is linkable into a simulator binary. See
#     build-vice-simulator-env.sh, which writes the stub and the environment.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
BRIDGE="${BRIDGE:-$REPO_ROOT/native/vice_core/bridge}"
VICE_SRC="${VICE_SRC_HOST:-$HOME/AndroidStudioProjects/VICE-source/vice-3.10}"
VICE_BUILD_DIR="${VICE_BUILD_DIR:?set VICE_BUILD_DIR to the simulator VICE build}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/flutter_app/ios/vicecore/iphonesimulator}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

IOS_MIN="${IOS_MIN:-15.0}"
TARGET="arm64-apple-ios${IOS_MIN}-simulator"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

VS="$VICE_BUILD_DIR/src"
[ -f "$VS/lib.o" ] || { echo "no VICE objects in $VS" >&2; exit 1; }

CFLAGS_COMMON="-target $TARGET -isysroot $SDK -fPIC -O2 -fno-common"
mkdir -p "$STAGE" "$OUT_DIR"

# --- the --wrap replacement -------------------------------------------------
# Rename each global to ___real_<sym>: alias it under the new name, then demote
# the old one so the bridge's definition is the only global <sym> at link time.
rename_object() {
    src="$1"; dst="$2"; shift 2
    set -- "$@"
    # Only rename what this object actually defines: -alias on an absent
    # symbol publishes a name that resolves to nothing, and the link fails
    # later with an undefined reference that points nowhere useful.
    args=""
    for sym in "$@"; do
        nm -g "$src" 2>/dev/null | grep -qE " T _$sym$| D _$sym$" || continue
        args="$args -alias _$sym ___real_$sym -unexported_symbol _$sym"
    done
    if [ -z "$args" ]; then cp "$src" "$dst"; return 0; fi
    # shellcheck disable=SC2086
    ld -r -arch arm64 -platform_version ios-simulator "$IOS_MIN" "$IOS_MIN" \
        "$src" -o "$dst" $args
}

staged_path() { echo "$STAGE/${1}_$(echo "$2" | tr '/' '_')"; }

stage_archive() {
    variant="$1"; rel="$2"; member="$3"; shift 3
    staged="$(staged_path "$variant" "$rel")"
    [ -f "$staged" ] || cp "$VS/$rel" "$staged"
    work="$STAGE/work"; rm -rf "$work"; mkdir -p "$work"
    ( cd "$work" && ar x "$staged" "$member" )
    rename_object "$work/$member" "$work/renamed.o" "$@"
    mv "$work/renamed.o" "$work/$member"
    ( cd "$work" && ar r "$staged" "$member" )
    ranlib "$staged"
}

stage_object() {
    variant="$1"; rel="$2"; shift 2
    rename_object "$VS/$rel" "$(staged_path "$variant" "$rel")" "$@"
}

echo "==> renaming wrapped symbols"
stage_object common log.o log_init
stage_object common init.o init_main
stage_object common vsync.o vsync_do_vsync
for variant in core vsid; do
    stage_archive "$variant" arch/headless/libarch.a archdep.o archdep_init
    stage_archive "$variant" arch/shared/sounddrv/libsounddrv.a \
        sounddummy.o sound_init_dummy_device
done
stage_archive core arch/headless/libarch.a video.o \
    video_init video_canvas_create video_canvas_can_resize \
    video_canvas_resize video_canvas_refresh
stage_archive vsid arch/headless/libarch.a video.o video_init
stage_archive core arch/headless/libarch.a uistatusbar.o \
    ui_display_tape_counter ui_display_tape_motor_status \
    ui_display_tape_control_status ui_display_drive_track \
    ui_display_drive_led
stage_archive core c64/libc64sc.a c64cpusc.o maincpu_mainloop
stage_archive vsid c64/libvsid.a vsidcpu.o maincpu_mainloop

BASE_NAMES="alarm attach autostart autostart-prg cbmdos cbmimage charset
    clipboard cmdline color crc32 crt debug dma event findpath fliplist gcr
    info initcmdline interrupt kbdbuf keyboard keymap lib machine-bus machine
    main mainlock m3u network opencbmlib palette profiler ram rawfile rawnet
    resources romset screenshot sha1 snapshot socket sound sysfile traps util
    vicefeatures zfile zipcode midi"
BASE_OBJECTS=""
for n in $BASE_NAMES; do
    [ -f "$VS/$n.o" ] && BASE_OBJECTS="$BASE_OBJECTS $VS/$n.o"
done
BASE_OBJECTS="$BASE_OBJECTS $(staged_path common log.o) $(staged_path common init.o) $(staged_path common vsync.o)"

INCLUDES="-I$BRIDGE -I$VS -I$VICE_SRC/src -I$VICE_SRC/src/arch/headless
    -I$VICE_SRC/src/arch/shared -I$VICE_SRC/src/arch -I$VICE_SRC/src/c64
    -I$VICE_SRC/src/datasette -I$VICE_SRC/src/drive -I$VICE_SRC/src/monitor
    -I$VICE_SRC/src/tape -I$VICE_SRC/src/tapeport"

WRAPPED_SYMS="archdep_init log_init video_init init_main video_canvas_create
    video_canvas_can_resize video_canvas_resize video_canvas_refresh
    sound_init_dummy_device vsync_do_vsync maincpu_mainloop
    ui_display_tape_counter ui_display_tape_motor_status
    ui_display_tape_control_status ui_display_drive_track
    ui_display_drive_led"

# The mirror image: the bridge's __wrap_foo becomes plain foo, so every
# unresolved reference in VICE binds to it.
unwrap_bridge_object() {
    # Same filter: the vsid bridge implements only some of the wrappers.
    args=""
    for sym in $WRAPPED_SYMS; do
        nm -g "$1" 2>/dev/null | grep -qE " T ___wrap_$sym$" || continue
        args="$args -alias ___wrap_$sym _$sym -unexported_symbol ___wrap_$sym"
    done
    if [ -z "$args" ]; then return 0; fi
    # shellcheck disable=SC2086
    ld -r -arch arm64 -platform_version ios-simulator "$IOS_MIN" "$IOS_MIN" \
        "$1" -o "$1.unwrapped" $args
    mv "$1.unwrapped" "$1"
}

echo "==> compiling bridge"
# shellcheck disable=SC2086
clang $CFLAGS_COMMON $INCLUDES -c "$BRIDGE/vice_bridge.c" -o "$STAGE/vice_bridge.o"
unwrap_bridge_object "$STAGE/vice_bridge.o"
# shellcheck disable=SC2086
clang $CFLAGS_COMMON $INCLUDES -c "$BRIDGE/vice_vsid_bridge.c" -o "$STAGE/vice_vsid_bridge.o"
unwrap_bridge_object "$STAGE/vice_vsid_bridge.o"
# shellcheck disable=SC2086
clang $CFLAGS_COMMON $INCLUDES -c "$BRIDGE/audio_backend_ios.m" -o "$STAGE/audio_backend_ios.o"

A() { echo "$VS/$1"; }
S() { staged_path "$1" "$2"; }

CORE_LIBS="$(A arch/shared/libarchdep.a) $(A tapeport/libtapeport.a)
    $(S core c64/libc64sc.a)
    $(A c64/cart/libc64cartsystem.a) $(A c64/cart/libc64cart.a)
    $(A c64/cart/libc64commoncart.a) $(A datasette/libdatasette.a)
    $(A drive/iec/libdriveiec.a) $(A drive/iecieee/libdriveiecieee.a)
    $(A drive/iec/c64exp/libdriveiecc64exp.a) $(A drive/ieee/libdriveieee.a)
    $(A drive/libdrive.a) $(A drive/tcbm/libdrivetcbm.a)
    $(A lib/p64/libp64.a) $(A iecbus/libiecbus.a) $(A parallel/libparallel.a)
    $(A vdrive/libvdrive.a) $(A sid/libsid.a) $(A monitor/libmonitor.a)
    $(A joyport/libjoyport.a) $(A samplerdrv/libsamplerdrv.a)
    $(S core arch/shared/sounddrv/libsounddrv.a)
    $(A arch/shared/mididrv/libmididrv.a) $(A arch/shared/socketdrv/libsocketdrv.a)
    $(A arch/shared/hwsiddrv/libhwsiddrv.a) $(A gfxoutputdrv/libgfxoutputdrv.a)
    $(A printerdrv/libprinterdrv.a) $(A diskimage/libdiskimage.a)
    $(A fsdevice/libfsdevice.a) $(A tape/libtape.a) $(A fileio/libfileio.a)
    $(A serial/libserial.a) $(A core/libcore.a) $(A rs232drv/librs232drv.a)
    $(A viciisc/libviciisc.a) $(A raster/libraster.a) $(A userport/libuserport.a)
    $(A diag/libdiag.a) $(A core/rtc/librtc.a) $(A video/libvideo.a)
    $(S core arch/headless/libarch.a)
    $(A imagecontents/libimagecontents.a) $(A c64/libc64scstubs.a)
    $(A resid/libresid.a) $(A hvsc/libhvsc.a) $(A lib/libzmbv/libzmbv.a)
    $(S core arch/headless/libarch.a) $(A arch/shared/libarchdep.a)
    $(A lib/linenoise-ng/liblinenoiseng.a)"

VSID_LIBS="$(A arch/shared/libarchdep.a)
    $(S vsid c64/libvsid.a)
    $(A sid/libsid.a) $(A monitor/libmonitor.a)
    $(S vsid arch/shared/sounddrv/libsounddrv.a)
    $(A arch/shared/mididrv/libmididrv.a) $(A arch/shared/socketdrv/libsocketdrv.a)
    $(A arch/shared/hwsiddrv/libhwsiddrv.a) $(A serial/libserial.a)
    $(A core/libcore.a) $(A vicii/libvicii.a) $(A raster/libraster.a)
    $(A video/libvideo.a) $(S vsid arch/headless/libarch.a)
    $(A resid/libresid.a) $(A joyport/libjoyport.a) $(A hvsc/libhvsc.a)
    $(A datasette/libdatasette.a) $(A c64/libvsidstubs.a) $(A lib/md5/libmd5.a)
    $(S vsid arch/headless/libarch.a) $(A arch/shared/libarchdep.a)
    $(A lib/linenoise-ng/liblinenoiseng.a)"

FRAMEWORKS="-framework AudioToolbox -framework AVFoundation -framework Foundation -framework CoreFoundation"

echo "==> linking libvicecore"
# shellcheck disable=SC2086
clang++ -target "$TARGET" -isysroot "$SDK" -dynamiclib \
    -install_name "@rpath/libvicecore.framework/libvicecore" \
    -o "$OUT_DIR/libvicecore.dylib" \
    "$STAGE/vice_bridge.o" "$STAGE/audio_backend_ios.o" \
    $BASE_OBJECTS $CORE_LIBS -lz -lc++ $FRAMEWORKS

echo "==> linking libvicecore_vsid"
# shellcheck disable=SC2086
clang++ -target "$TARGET" -isysroot "$SDK" -dynamiclib \
    -install_name "@rpath/libvicecore_vsid.framework/libvicecore_vsid" \
    -o "$OUT_DIR/libvicecore_vsid.dylib" \
    "$STAGE/vice_vsid_bridge.o" "$STAGE/audio_backend_ios.o" \
    $BASE_OBJECTS $VSID_LIBS -lz -lc++ $FRAMEWORKS

echo "==> built:"
ls -lh "$OUT_DIR"/*.dylib
