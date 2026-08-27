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
# WHY THIS EXISTS. flutter_app/ios/Frameworks/libvicecore.framework is built
# for platform IOS -- a device binary a simulator cannot dlopen at all
# ("incompatible platform (have 'iOS', need 'iOS-simulator')"). So the built
# .app gets the simulator cores from ios/vicecore/iphonesimulator/ swapped in
# before it is installed. Device builds are untouched.
#
# Those cores are built by native/vice_core/ios/build-core-simulator.sh from
# the same VICE source and the same bridge as the device ones, so the simulator
# now runs the same emulator -- including the 1541 drive fix, which means .d64
# images work here. They did not before: the old hand-linked archives predated
# a9a1a4d and every disk died on ?DEVICE NOT PRESENT.

set -eu

DEVICE="${1:-iPhone 17 Pro Max}"
ROMZIP="${2:-}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APPDIR="$REPO/flutter_app"
SIMLIBS="$APPDIR/ios/vicecore/iphonesimulator"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$SIMLIBS/libvicecore.dylib" ] || {
  echo "error: no simulator cores at $SIMLIBS" >&2
  echo "       build them with native/vice_core/ios/build-core-simulator.sh" >&2
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

# Read the bundle ID off the bundle just built, rather than keeping a copy
# here. The hardcoded one was still com.vicemultiplatform.app after the app
# was renamed, so install worked and every simctl call that took the ID --
# get_app_container, uninstall, launch -- addressed an app that was not there.
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")"
echo "--- bundle id $BUNDLE_ID"

echo "--- swapping in the simulator cores"
for n in libvicecore libvicecore_vsid; do
  [ -f "$SIMLIBS/$n.dylib" ] || { echo "error: $SIMLIBS/$n.dylib missing" >&2; exit 1; }
  cp "$SIMLIBS/$n.dylib" "$APP/Frameworks/$n.framework/$n"
done

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
