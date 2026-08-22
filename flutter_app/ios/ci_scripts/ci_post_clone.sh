#!/bin/sh
# Xcode Cloud post-clone step.
#
# Xcode Cloud's images have Xcode and CocoaPods but no Flutter, and it does not
# run `flutter build` -- it invokes xcodebuild on the Runner scheme directly.
# That only works if Flutter has already generated ios/Flutter/Generated.xcconfig,
# because the Runner target's "Thin Binary" build phase calls
# "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" and FLUTTER_ROOT is
# defined in that file. So: install Flutter, resolve packages, and let
# `--config-only` write the config the Xcode build needs.
#
# Apple runs this from the ci_scripts directory, which must sit next to the
# Xcode project -- hence ios/ci_scripts/ rather than the repo root.
set -e

# Pinned rather than tracking stable, and pinned to the same version
# .github/workflows/build.yml uses. A newer Flutter resolves newer transitive
# packages and rewrites pubspec.lock mid-build, so an untracked toolchain makes
# cloud builds differ from CI for reasons that have nothing to do with the
# commit being built.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.1}"
FLUTTER_HOME="$HOME/flutter"

echo "--- installing Flutter $FLUTTER_VERSION"
git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
export PATH="$FLUTTER_HOME/bin:$PATH"
flutter --version

APP_DIR="$CI_PRIMARY_REPOSITORY_PATH/flutter_app"
cd "$APP_DIR"

# The native cores cannot be rebuilt here: they need the cross-compiled VICE
# object tree, which lives outside this repository (see docs/NATIVE_BUILD.md).
# They are committed for exactly this reason, so fail clearly if they are absent
# rather than producing an app that installs and then dies at "Failed to load
# libvicecore". These are the framework bundles the Runner target embeds and
# the Dart side dlopens by absolute path -- not static archives; nothing links
# them. The loose .dylib beside each one is the same bytes, the build script's
# raw output; checking that instead would pass while the app shipped no core.
for name in libvicecore libvicecore_vsid; do
  if [ ! -f "ios/Frameworks/$name.framework/$name" ]; then
    echo "error: missing ios/Frameworks/$name.framework -- see docs/NATIVE_BUILD.md" >&2
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
