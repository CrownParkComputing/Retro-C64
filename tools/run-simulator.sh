#!/bin/sh
# Build, install and launch the app on an iOS Simulator, with a core it can
# actually load.
#
#     tools/run-simulator.sh                 # iPhone 17 Pro Max
#     tools/run-simulator.sh "iPad Pro 13-inch (M4)"
#     tools/run-simulator.sh "iPhone 17 Pro Max" ~/Desktop/c64-roms.zip \
#         ~/Downloads/"1942 (1986)(Elite).zip"     # any number of zips, or a dir
#
# App data (imported ROMs, library) is preserved across the reinstall, so the
# zips only need supplying the first time.
#
# WHY THIS EXISTS. `flutter run` alone gives a black screen or "Failed to load
# libvicecore", for two reasons that have nothing to do with the app:
#
#   1. flutter_app/ios/Frameworks/libvicecore.framework is built for
#      platform IOS -- a device binary. A simulator cannot dlopen it at all
#      ("incompatible platform (have 'iOS', need 'iOS-simulator')").
#
#   2. The simulator archives under ios/vicecore/iphonesimulator/ ARE
#      simulator-platform, but predate five status getters the Dart bindings
#      look up: tape counter/motor/control, drive LED and half-track.
#      ViceCoreBindings.load() resolves every symbol eagerly, so five missing
#      getters fail the whole dlopen.
#
# So this links those archives into simulator dylibs, fills the five gaps with
# stubs returning 0 (status reads only -- the simulator loses two indicators
# and nothing else), and swaps them into the built .app. Device builds are
# untouched: they link the real archive and never see the stubs.
#
# WHAT THE SIMULATOR CANNOT TELL YOU. Those archives are an old build of the
# core, so the simulator runs old emulator behaviour however current the Dart
# side is. Most visibly, they predate a9a1a4d ("Tell VICE the drive is a 1541
# before attaching a disk"), which changed vice_bridge.c and the prebuilt
# binaries but never the simulator archives. So in the simulator every .d64
# dies on ?DEVICE NOT PRESENT, exactly as it did before that fix -- and that is
# the simulator being out of date, not a regression. Check with:
#
#     strings ios/Frameworks/libvicecore.framework/libvicecore | grep 'cold-start drive'
#     strings ios/vicecore/iphonesimulator/libvicecore.a       | grep 'cold-start drive'
#
# One hit and no hit: the device core has the fix, the simulator core does not.
# Tapes (.tap) and programs (.prg) need no drive and do work here, so use those
# to exercise media in the simulator, and test disks on a device.
#
# The proper fix is a simulator target in native/vice_core/ios/build.sh, which
# needs the cross-compiled VICE tree that is not in this repo.
set -eu

DEVICE="${1:-iPhone 17 Pro Max}"
ROMZIP="${2:-}"
BUNDLE_ID="com.vicemultiplatform.app"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APPDIR="$REPO/flutter_app"
SIMLIBS="$APPDIR/ios/vicecore/iphonesimulator"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SIMLIBS/libvicecore.a" ] || {
  echo "error: no simulator archives at $SIMLIBS" >&2
  echo "       they are untracked build output; you need them to run here." >&2
  exit 1
}

UDID="$(xcrun simctl list devices available \
  | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "error: no available simulator named '$DEVICE'" >&2; exit 1; }

echo "--- booting $DEVICE"
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
until xcrun simctl list devices | grep -q "$UDID) (Booted)"; do sleep 1; done
# A clean status bar, so captures are presentable without a second pass.
xcrun simctl status_bar "$UDID" override --time "09:41" \
  --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null || true

echo "--- building for simulator"
( cd "$APPDIR" && flutter build ios --simulator --debug >/dev/null )
APP="$APPDIR/build/ios/iphonesimulator/Runner.app"

echo "--- linking simulator cores"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="arm64-apple-ios15.0-simulator"
FRAMEWORKS="-framework AudioToolbox -framework AVFoundation -framework Foundation \
            -framework CoreAudio -framework CoreFoundation -lz"

cat > "$WORK/stubs.c" <<'STUBS'
#include <stdint.h>
int32_t vice_core_get_tape_counter(void)     { return 0; }
int32_t vice_core_get_tape_motor(void)       { return 0; }
int32_t vice_core_get_tape_control(void)     { return 0; }
int32_t vice_core_get_drive_led(void)        { return 0; }
int32_t vice_core_get_drive_half_track(void) { return 0; }
STUBS
clang -c -arch arm64 -target "$TARGET" -isysroot "$SDK" "$WORK/stubs.c" -o "$WORK/stubs.o"

# shellcheck disable=SC2086
clang++ -dynamiclib -arch arm64 -target "$TARGET" -isysroot "$SDK" \
  -Wl,-all_load "$SIMLIBS/libvicecore.a" "$WORK/stubs.o" $FRAMEWORKS \
  -install_name @rpath/libvicecore.framework/libvicecore \
  -o "$APP/Frameworks/libvicecore.framework/libvicecore"

# shellcheck disable=SC2086
clang++ -dynamiclib -arch arm64 -target "$TARGET" -isysroot "$SDK" \
  -Wl,-all_load "$SIMLIBS/libvicecore_vsid.a" $FRAMEWORKS \
  -install_name @rpath/libvicecore_vsid.framework/libvicecore_vsid \
  -o "$APP/Frameworks/libvicecore_vsid.framework/libvicecore_vsid"

echo "--- installing"
# Uninstall wipes the data container, taking the imported ROMs under
# Library/Application Support/vice with it -- so without this every run starts
# from no ROMs and the zips have to be copied again. Keep the data, reinstall
# the code.
OLD_CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data 2>/dev/null || true)"
if [ -n "$OLD_CONTAINER" ] && [ -d "$OLD_CONTAINER" ]; then
  mkdir -p "$WORK/keep"
  for d in Documents "Library/Application Support"; do
    [ -d "$OLD_CONTAINER/$d" ] || continue
    mkdir -p "$WORK/keep/$(dirname "$d")"
    cp -R "$OLD_CONTAINER/$d" "$WORK/keep/$d"
  done
  echo "--- kept the existing app data"
fi

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
if [ -d "$WORK/keep" ]; then
  ( cd "$WORK/keep" && find . -mindepth 1 -maxdepth 2 -type d -print0 2>/dev/null \
    | xargs -0 -I{} mkdir -p "$CONTAINER/{}" ) 2>/dev/null || true
  cp -R "$WORK/keep/". "$CONTAINER/" 2>/dev/null || true
  echo "--- restored it, so imported ROMs survive the reinstall"
fi

# Every remaining argument is a zip (or a directory of them) to drop in. They
# go straight into Documents, the only directory iOS lets the app read -- the
# same place a user reaches through Files, now that the folder is the door.
if [ -n "$ROMZIP" ]; then
  mkdir -p "$CONTAINER/Documents"
  for item in "$@"; do
    [ "$item" = "$DEVICE" ] && continue
    if [ -d "$item" ]; then
      find "$item" -maxdepth 1 -name '*.zip' -exec cp {} "$CONTAINER/Documents/" \;
      echo "--- placed $(find "$item" -maxdepth 1 -name '*.zip' | wc -l | tr -d ' ') zip(s) from $(basename "$item")"
    elif [ -f "$item" ]; then
      cp "$item" "$CONTAINER/Documents/"
      echo "--- placed $(basename "$item")"
    fi
  done
fi

xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
echo "--- running. Screenshot with:"
echo "    xcrun simctl io $UDID screenshot shot.png"
