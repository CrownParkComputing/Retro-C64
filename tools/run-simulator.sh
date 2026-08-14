#!/bin/sh
# Build, install and launch the app on an iOS Simulator, with a core it can
# actually load.
#
#     tools/run-simulator.sh                 # iPhone 17 Pro Max
#     tools/run-simulator.sh "iPad Pro 13-inch (M4)"
#     tools/run-simulator.sh "iPhone 17 Pro Max" ~/Desktop/c64-roms.zip
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
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"

if [ -n "$ROMZIP" ]; then
  # Straight into the app's Documents, which is the only place iOS lets it
  # read. On a real device the user does this through the Files app; there is
  # no picker any more, the folder is the door.
  CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
  mkdir -p "$CONTAINER/Documents"
  cp "$ROMZIP" "$CONTAINER/Documents/"
  echo "--- placed $(basename "$ROMZIP") in the app's Documents"
fi

xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
echo "--- running. Screenshot with:"
echo "    xcrun simctl io $UDID screenshot shot.png"
