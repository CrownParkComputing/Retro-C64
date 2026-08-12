#!/usr/bin/env bash
# Host entry point: builds libvicecore.dylib / libvicecore_vsid.dylib for
# arm64 iOS, from Linux, with no Mac involved.
#
# Two stages, both inside a container built from the Dockerfile next to this
# file (iosbox's cross toolchain plus flex/bison, which VICE's configure
# needs on the host):
#
#   1. build-vice-ios-headless.sh  cross-compiles VICE itself
#   2. build-core-ios.sh           links VICE + the bridge into the dylibs
#
# Stage 1 is the slow one (~10 min) and only needs redoing when the VICE
# source changes; pass SKIP_VICE=1 to relink the bridge alone.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
VICE_SRC_HOST="${VICE_SRC_HOST:-$HOME/AndroidStudioProjects/VICE-source/vice-3.10}"
IMAGE="${VICECORE_IOS_IMAGE:-vicecore-iosbox:latest}"
SDK_VOLUME="${IOSBOX_SDK_VOLUME:-iosbox-sdk}"

if [ ! -x "$VICE_SRC_HOST/configure" ]; then
    echo "error: VICE source not found at $VICE_SRC_HOST" >&2
    echo "       set VICE_SRC_HOST to the vice-3.10 checkout" >&2
    exit 1
fi
if ! docker volume inspect "$SDK_VOLUME" >/dev/null 2>&1; then
    echo "error: Docker volume '$SDK_VOLUME' not found -- the iOS SDK is not" >&2
    echo "       registered. See docs/IOS_BUILD.md." >&2
    exit 1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "==> building $IMAGE"
    docker build -t "$IMAGE" "$HERE"
fi

run_in_container() {
    docker run --rm \
        -v "$SDK_VOLUME:/root/.iosbox" \
        -v "$REPO_ROOT:/proj" \
        -v "$VICE_SRC_HOST:/vice" \
        "$IMAGE" bash -lc "$1"
}

if [ "${SKIP_VICE:-0}" != "1" ]; then
    echo "==> stage 1/2: cross-compiling VICE for arm64 iOS"
    run_in_container "/proj/native/vice_core/ios/build-vice-ios-headless.sh"
else
    echo "==> stage 1/2: skipped (SKIP_VICE=1)"
fi

echo "==> stage 2/2: linking the native core"
run_in_container "/proj/native/vice_core/ios/build-core-ios.sh"

# Everything above ran as root in the container; hand the outputs back so the
# host toolchain can read and package them.
docker run --rm -v "$REPO_ROOT:/proj" alpine \
    chown -R "$(id -u):$(id -g)" /proj/native/vice_core/ios/build
docker run --rm -v "$VICE_SRC_HOST:/vice" alpine \
    chown -R "$(id -u):$(id -g)" /vice/build-ios-arm64-headless 2>/dev/null || true

echo
echo "==> done:"
ls -lh "$HERE/build"/*.dylib
