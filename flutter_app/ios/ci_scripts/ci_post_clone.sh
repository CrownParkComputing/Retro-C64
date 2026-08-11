#!/bin/sh
# Xcode Cloud post-clone step.
#
# Xcode Cloud's images have Xcode and CocoaPods but no Flutter, and it does
# not run `flutter build` -- it invokes xcodebuild on the Runner scheme
# directly. That only works if Flutter has already generated
# ios/Flutter/Generated.xcconfig, because the Runner target's "Thin Binary"
# build phase calls "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh"
# and FLUTTER_ROOT is defined in that file. So: install Flutter, resolve
# packages, and let `--config-only` write the config the Xcode build needs.
#
# Apple runs this from the ci_scripts directory, which must sit next to the
# Xcode project -- hence ios/ci_scripts/ rather than the repo root.
set -e

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
FLUTTER_HOME="$HOME/flutter"

echo "--- installing Flutter ($FLUTTER_CHANNEL)"
git clone --depth 1 -b "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
export PATH="$FLUTTER_HOME/bin:$PATH"
flutter --version

APP_DIR="$CI_PRIMARY_REPOSITORY_PATH/flutter_app"
cd "$APP_DIR"

# The native cores cannot be rebuilt here: they need the cross-compiled VICE
# object tree, which lives outside this repository (see docs/NATIVE_BUILD.md).
# They are committed for exactly this reason, so fail clearly if they are
# absent rather than producing an app that links but cannot emulate.
for lib in libvicecore.a libvicecore_vsid.a; do
  if [ ! -f "ios/vicecore/iphoneos/$lib" ]; then
    echo "error: missing ios/vicecore/iphoneos/$lib -- see docs/NATIVE_BUILD.md" >&2
    exit 1
  fi
done

echo "--- resolving packages"
flutter precache --ios
flutter pub get

echo "--- generating the Xcode config Flutter's build phases rely on"
flutter build ios --release --no-codesign --config-only

echo "--- pod install"
cd ios
pod install

echo "--- ready for xcodebuild"
