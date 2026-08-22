#!/usr/bin/env bash
# Bump the build number, build a release APK, install it, and stop the old
# process so the next launch is clean.
#
# The bump is the point. The setup wizard re-runs when the version changes,
# which is how a tester or a store reviewer sees what a build says on first
# run -- and installing the same build number twice looks identical to not
# installing at all. That has already cost an afternoon of "did it deploy?".
#
# The force-stop matters too: the ROM directory is chosen at startup, so a
# surviving process keeps the old choice.
set -euo pipefail
cd "$(dirname "$0")/.."

current=$(grep -m1 '^version:' pubspec.yaml | sed 's/^version: //')
name=${current%%+*}
build=${current##*+}
next="$name+$((build + 1))"
sed -i "s/^version: .*/version: $next/" pubspec.yaml
echo "version: $current -> $next"

flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am force-stop com.retroc64
echo "installed $next; next launch will show the setup wizard"
