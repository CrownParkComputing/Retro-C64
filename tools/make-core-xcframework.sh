#!/usr/bin/env bash
# Packages the device and simulator cores into xcframeworks.
#
#     tools/make-core-xcframework.sh
#
# WHY. The app dlopens Frameworks/<name>.framework/<name>. A plain .framework
# holds one platform's slice, and the one committed here is the DEVICE build --
# so on a simulator dyld refuses it with
#
#   incompatible platform (have 'iOS', need 'iOS-simulator')
#
# and the app opens to a full-screen dlopen dump instead of the workbench. An
# xcframework carries both slices and Xcode embeds whichever the destination
# needs, at the SAME path, so no runtime code changes. This is the shape
# Retro-Amiga and Retro-Saturn already use.
#
# The simulator slices are built by native/vice_core/ios/build-core-simulator.sh
# and land in flutter_app/ios/vicecore/iphonesimulator; the device slices are
# cross-compiled on Linux and committed as .framework bundles.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS="$ROOT/flutter_app/ios/Frameworks"
SIM_DIR="$ROOT/flutter_app/ios/vicecore/iphonesimulator"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# A bare dylib in Frameworks/ is what the old Swift runtime looked like, and
# Apple's validator then demands a SwiftSupport folder Xcode will not generate
# (rejection 90426). So the simulator slice is wrapped as a framework too,
# which also keeps the dlopen path identical on both platforms.
wrap_simulator_framework() {
  local name="$1" dylib="$2" dest="$3"
  # A CFBundleIdentifier may hold only alphanumerics, hyphen and period, and
  # libvicecore_vsid has an underscore. Xcode's embed validation rejects it:
  #   "had an invalid CFBundleIdentifier in its Info.plist"
  # and only on the simulator build, so a device build passes and hides it.
  local bundle_id_name="${name//_/-}"
  mkdir -p "$dest/$name.framework"
  cp "$dylib" "$dest/$name.framework/$name"
  install_name_tool -id "@rpath/$name.framework/$name" \
    "$dest/$name.framework/$name" 2>/dev/null || true
  cat > "$dest/$name.framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>$name</string>
	<key>CFBundleIdentifier</key><string>com.crownpark.retroc64.$bundle_id_name</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>$name</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
	<key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST
}

for name in libvicecore libvicecore_vsid; do
  device="$FRAMEWORKS/$name.framework"
  sim_dylib="$SIM_DIR/$name.dylib"
  out="$FRAMEWORKS/$name.xcframework"

  [ -f "$device/$name" ] || { echo "missing device slice: $device/$name" >&2; exit 1; }
  [ -f "$sim_dylib" ] || { echo "missing simulator slice: $sim_dylib" >&2; exit 1; }

  # Refuse to build a mislabelled xcframework. A device binary in the simulator
  # slot builds green and dies at dlopen, and only on a simulator.
  vtool -show-build "$device/$name" | grep -q "platform IOS$" \
    || { echo "$name device slice is not a device binary" >&2; exit 1; }
  vtool -show-build "$sim_dylib" | grep -q "platform IOSSIMULATOR" \
    || { echo "$name simulator slice is not a simulator binary" >&2; exit 1; }

  mkdir -p "$STAGE/$name"
  cp -R "$device" "$STAGE/$name/device.framework.tmp"
  mv "$STAGE/$name/device.framework.tmp" "$STAGE/$name/$name.framework"
  wrap_simulator_framework "$name" "$sim_dylib" "$STAGE/$name/sim"

  rm -rf "$out"
  xcodebuild -create-xcframework \
    -framework "$STAGE/$name/$name.framework" \
    -framework "$STAGE/$name/sim/$name.framework" \
    -output "$out" >/dev/null
  echo "built $out"
  find "$out" -name "$name" -type f | while read -r bin; do
    printf '   %-46s %s\n' "${bin#$out/}" "$(vtool -show-build "$bin" | awk '/platform/{print $2}')"
  done
done
