#!/bin/sh
# Raises MinimumOSVersion on the frameworks embedded in the app bundle, as a
# build phase, so the archive is correct when it is produced rather than
# corrected afterwards.
#
# This is raise_min_os.sh's job moved inside the build. That script patches a
# finished .ipa and re-signs with a named identity out of a local keychain,
# which is fine on a developer's machine and impossible on Xcode Cloud, where
# there is no keychain to name and the archive goes straight to App Store
# Connect. Validation 90068 rejects an upload whose frameworks declare a
# MinimumOSVersion below Apple's floor, and the Flutter engine ships
# Flutter.framework and App.framework at its own floor (13.0 as of Flutter
# 3.44) no matter what IPHONEOS_DEPLOYMENT_TARGET says. Setting
# MinimumOSVersion in ios/Flutter/AppFrameworkInfo.plist does not help: the
# tool rewrites that plist during the build.
#
# Both places the version is recorded have to agree -- the Info.plist key and
# the Mach-O LC_BUILD_VERSION load command -- because Apple reads the load
# command, not just the plist.
#
# Runs as the last phase of the Runner target: after "Thin Binary"
# (embed_and_thin) and "[CP] Embed Pods Frameworks" have put everything in
# place. Editing a framework invalidates its signature, so each one is
# re-signed here with EXPANDED_CODE_SIGN_IDENTITY, the identity Xcode
# resolved for this build -- which is exactly what makes this work under
# cloud-managed signing. Xcode signs the outer .app after all build phases,
# so the app's own signature is unaffected.
set -eu

APP="${CODESIGNING_FOLDER_PATH:-${TARGET_BUILD_DIR:-}/${WRAPPER_NAME:-}}"
MIN="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

[ -n "$APP" ] && [ -d "$APP/Frameworks" ] || {
  echo "note: no embedded frameworks to patch"
  exit 0
}

for fw in "$APP"/Frameworks/*.framework; do
  [ -d "$fw" ] || continue
  name="$(basename "$fw" .framework)"
  plist="$fw/Info.plist"
  binary="$fw/$name"

  if [ -f "$plist" ]; then
    /usr/libexec/PlistBuddy -c "Set :MinimumOSVersion $MIN" "$plist" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :MinimumOSVersion string $MIN" "$plist"
  fi

  # -replace rewrites an existing LC_BUILD_VERSION rather than appending a
  # second one, which would make the binary invalid.
  if [ -f "$binary" ]; then
    xcrun vtool -set-build-version ios "$MIN" "$MIN" -replace \
      -output "$binary" "$binary" >/dev/null
  fi

  # An unsigned build (flutter build ios --no-codesign) has no identity to
  # re-sign with, and needs none -- the patch is still correct, it just is
  # not signed. Only skip in that case; a signing build that somehow lacks
  # the identity should fail loudly rather than ship a broken signature.
  # Flags deliberately match Pods-Runner-frameworks.sh, which re-signs the
  # embedded frameworks in this same bundle -- same identity, same preserved
  # metadata, so this phase cannot disagree with the one before it.
  if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:?no signing identity for $name}" \
      ${OTHER_CODE_SIGN_FLAGS:-} --preserve-metadata=identifier,entitlements "$fw"
  fi

  echo "note: $name -> MinimumOSVersion $MIN"
done
