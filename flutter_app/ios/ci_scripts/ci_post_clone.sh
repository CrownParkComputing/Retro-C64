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
# The XCFRAMEWORKS are what the Runner embeds now, and both slices are checked.
# A device binary in the simulator slot builds green and dies at dlopen, and
# only on a simulator -- which is how the app came to open on a phone and show
# nothing but a dlopen dump in the simulator.
for name in libvicecore libvicecore_vsid; do
  xc="ios/Frameworks/$name.xcframework"
  for slice in ios-arm64 ios-arm64-simulator; do
    if [ ! -f "$xc/$slice/$name.framework/$name" ]; then
      echo "error: missing $xc/$slice -- rebuild with" >&2
      echo "       tools/make-core-xcframework.sh, or see docs/NATIVE_BUILD.md" >&2
      exit 1
    fi
  done
done

# Flutter 3.47 enables Swift Package Manager by default, and gamepads_ios has
# not adopted it. The mixed SPM/CocoaPods registrant then fails to compile for
# device -- "Module 'gamepads_ios' not found" -- which Flutter reports as the
# far less specific "No Xcode build settings have been found".
#
# GitHub Actions sets this explicitly in the workflow. Xcode Cloud runs THIS
# script instead, and `flutter config` is a per-machine setting, so a fix made
# on a laptop or in a workflow file never reaches these builders: they have to
# be told separately, which is why cloud builds failed while CI was green.
#
# Tolerated if the flag does not exist: older Flutter has no SPM to disable.
flutter config --no-enable-swift-package-manager || true

echo "--- resolving packages"
flutter precache --ios
flutter pub get

echo "--- generating the Xcode config Flutter's build phases rely on"
flutter build ios --release --no-codesign --config-only

echo "--- pod install"
cd ios
pod install

echo "--- ready for xcodebuild"
