#!/usr/bin/env bash
# Build the iOS app on Linux, without macOS or Xcode.
#
# Uses the mobaiapp/iosbox image: clang + swiftc targeting arm64-apple-ios,
# linked with ld64.lld against an iOS SDK extracted from Xcode. The SDK is not
# in the image -- it lives in the `iosbox-sdk` Docker volume, put there once by
# `iosbox setup /path/to/Xcode.xip`. See docs/IOS_BUILD.md.
#
# Output: flutter_app/build/iosbox/Runner.ipa (unsigned, debug configuration).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IOSBOX_IMAGE:-mobaiapp/iosbox:latest}"
SDK_VOLUME="${IOSBOX_SDK_VOLUME:-iosbox-sdk}"

if ! docker volume inspect "$SDK_VOLUME" >/dev/null 2>&1; then
  echo "error: Docker volume '$SDK_VOLUME' not found -- the iOS SDK is not registered." >&2
  echo "       Run: docker run --rm -v $SDK_VOLUME:/root/.iosbox -v /path/to:/x \\" >&2
  echo "                 $IMAGE iosbox setup /x/Xcode.xip" >&2
  exit 1
fi

# Fail fast on an unparseable Info.plist. XML forbids a double hyphen inside
# a comment; Apple's tooling does not warn, the plist just fails to parse, iOS
# ignores the scene configuration, and the app launches to a black screen with
# nothing in any log. Cheaper to catch here than on the device.
echo "==> checking Info.plist"
if ! python3 -c 'import plistlib,sys; plistlib.load(open(sys.argv[1],"rb"))' \
        "$REPO_ROOT/flutter_app/ios/Runner/Info.plist"; then
  echo "error: ios/Runner/Info.plist is not valid XML." >&2
  echo "       Most likely a double hyphen inside a comment, which XML forbids." >&2
  exit 1
fi

echo "==> building iOS app (this takes ~2 minutes)"
docker run --rm \
  -v "$SDK_VOLUME:/root/.iosbox" \
  -v "$REPO_ROOT:/proj" \
  "$IMAGE" iosbox build /proj/flutter_app

# The container runs as root and every file it wrote into the bind mount is
# left root-owned. That silently breaks the *host* Flutter afterwards -- the
# next `flutter build apk` dies on "Flutter failed to delete a directory" when
# it tries to refresh .dart_tool and linux/flutter/ephemeral. It also blocks
# the bundling step below from writing into Runner.app, so hand ownership back
# before touching anything, not at the end.
echo "==> restoring file ownership"
docker run --rm -v "$REPO_ROOT:/proj" alpine \
  chown -R "$(id -u):$(id -g)" /proj

# Bundle the native core. iosbox regenerates its SwiftPM package on every run,
# so there is no supported way to add link flags to the Runner target -- the
# dylibs are copied into the app afterwards instead and dlopened by path at
# runtime (ViceNativePaths._iosFrameworkLibrary). The IPA is then repacked,
# because iosbox has already zipped one without them.
CORE_BUILD="$REPO_ROOT/native/vice_core/ios/build"
APP="$REPO_ROOT/flutter_app/build/iosbox/Runner.app"
IPA="$REPO_ROOT/flutter_app/build/iosbox/Runner.ipa"

if [ -f "$CORE_BUILD/libvicecore.dylib" ]; then
  echo "==> bundling native core"
  mkdir -p "$APP/Frameworks"
  cp -v "$CORE_BUILD"/libvicecore.dylib "$CORE_BUILD"/libvicecore_vsid.dylib \
        "$APP/Frameworks/"

  rm -rf "$REPO_ROOT/flutter_app/build/iosbox/Payload"
  mkdir -p "$REPO_ROOT/flutter_app/build/iosbox/Payload"
  cp -a "$APP" "$REPO_ROOT/flutter_app/build/iosbox/Payload/"
  ( cd "$REPO_ROOT/flutter_app/build/iosbox" \
      && rm -f Runner.ipa \
      && zip -qry Runner.ipa Payload \
      && rm -rf Payload )
  echo "    repacked $(basename "$IPA")"
else
  echo "==> WARNING: no native core at $CORE_BUILD -- the app will build and"
  echo "    launch but report 'Failed to load libvicecore'. Build it with"
  echo "    native/vice_core/ios/build.sh"
fi

echo "==> done: flutter_app/build/iosbox/Runner.ipa"
ls -lh "$REPO_ROOT/flutter_app/build/iosbox/Runner.ipa"
