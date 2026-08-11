#!/usr/bin/env bash
# Raises the minimum-iOS version recorded in an already-built .ipa, and
# re-signs it.
#
# Apple rejects uploads whose MinimumOSVersion is below 15.0 (validation
# 90068), and it does not only look at the app: the embedded frameworks
# count too. The app's own value comes from IPHONEOS_DEPLOYMENT_TARGET and
# is easy to set, but Flutter.framework and App.framework are produced by
# the Flutter engine at its own floor (13.0 as of Flutter 3.44), and no
# project setting moves them -- setting MinimumOSVersion in
# ios/Flutter/AppFrameworkInfo.plist is ignored, because the tool writes
# that plist itself.
#
# So the version is corrected after the fact, in both places it is recorded:
# the Info.plist key, and the Mach-O LC_BUILD_VERSION load command (patched
# with vtool). Re-signing is then mandatory -- editing anything inside a
# signed bundle invalidates its signature.
#
#   ./raise_min_os.sh <path/to.ipa> [min-version]
set -euo pipefail

IPA="${1:?usage: raise_min_os.sh <ipa> [min-version]}"
# Absolute, because the zip below runs from the work directory.
IPA="$(cd "$(dirname "$IPA")" && pwd)/$(basename "$IPA")"
MIN="${2:-15.0}"
IDENTITY="${CODESIGN_IDENTITY:-Apple Distribution: Jonathan Whittingham (88A3T9K9C5)}"
KEYCHAIN="${CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/vice-build.keychain-db}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "--- unpacking $(basename "$IPA")"
unzip -q "$IPA" -d "$WORK"
APP="$(ls -d "$WORK"/Payload/*.app)"

# The app's entitlements have to be carried over by hand: re-signing without
# them would strip application-identifier and beta-reports-active, and the
# upload would be rejected for a different reason.
ENTITLEMENTS="$WORK/entitlements.plist"
codesign -d --entitlements :"$ENTITLEMENTS" "$APP" 2>/dev/null

patch_bundle() {
  local bundle="$1" binary="$2"
  /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $MIN" "$bundle/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $MIN" "$bundle/Info.plist"
  if [ -f "$binary" ]; then
    # -replace so an existing LC_BUILD_VERSION is rewritten rather than a
    # second one appended.
    xcrun vtool -set-build-version ios "$MIN" "$MIN" -replace \
      -output "$binary" "$binary" >/dev/null
  fi
}

for fw in "$APP"/Frameworks/*.framework; do
  [ -d "$fw" ] || continue
  name="$(basename "$fw" .framework)"
  patch_bundle "$fw" "$fw/$name"
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --timestamp=none "$fw" >/dev/null 2>&1
  echo "    $name -> $MIN"
done

patch_bundle "$APP" ""
codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" \
  --entitlements "$ENTITLEMENTS" --timestamp=none "$APP" >/dev/null 2>&1
echo "    $(basename "$APP") -> $MIN"

OUT="${IPA%.ipa}-min$MIN.ipa"
rm -f "$OUT"
(cd "$WORK" && zip -qry "$OUT" Payload)
echo "--- wrote $OUT"

echo "--- verifying"
V="$(mktemp -d)"; unzip -q "$OUT" -d "$V"; VAPP="$(ls -d "$V"/Payload/*.app)"
echo "    app: $(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$VAPP/Info.plist")"
for fw in "$VAPP"/Frameworks/*.framework; do
  [ -d "$fw" ] || continue
  echo "    $(basename "$fw"): $(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$fw/Info.plist" 2>/dev/null)"
done
codesign --verify --deep --strict "$VAPP" && echo "    signature: valid"
rm -rf "$V"
