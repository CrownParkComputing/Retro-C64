#!/usr/bin/env bash
# Builds libvicecore.a (x64sc game core) and libvicecore_vsid.a (SID player)
# for iOS, from the bridge sources plus the pre-built VICE object tree that
# build-vice-ios-headless.sh produces.
#
#   ./build.sh                          # device + simulator
#   ./build.sh --sdk iphoneos           # just the device slice
#
# Output: flutter_app/ios/vicecore/<sdk>/libvicecore{,_vsid}.a -- the iOS
# counterpart of the Android build's jniLibs/arm64-v8a/, linked into the
# Runner by flutter_app/ios/Flutter/VICECore.xcconfig. Intermediates stay in
# native/vice_core/ios/build/.
#
# WHY EACH CORE IS ONE PRELINKED OBJECT
#
# On Android the two cores are separate .so files, so each gets its own copy
# of VICE (log.o, sound.o, resid, ...) without either seeing the other's.
# iOS has no such luxury -- both are statically linked into the one app
# binary, and VICE is emphatically not built to have two machines in one
# address space: every one of those thousands of symbols would collide.
#
# So each core is first partially linked (`ld -r`) into a single object with
# -exported_symbols_list naming only its own public API. Everything else
# becomes a private extern -- still there, still callable from inside that
# object, but invisible to the other core and to the rest of the app. The two
# cores then coexist exactly as the two .so files do on Android.
#
# The exported names are also what dart:ffi's DynamicLibrary.process() looks
# up at runtime (see flutter_app/lib/ffi/vice_bindings.dart).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BRIDGE="$HERE/../bridge"
VICE_SRC="${VICE_SRC:-$HOME/AndroidStudioProjects/VICE-source/vice-3.10}"
IOS_MIN="${IOS_MIN:-15.0}"
OBJ_ROOT="${OBJ_ROOT:-$HERE/build}"
OUT_ROOT="${OUT_ROOT:-$HERE/../../../flutter_app/ios/vicecore}"
SDKS="iphoneos iphonesimulator"
ARCHS_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --sdk) SDKS="$2"; shift 2 ;;
    --arch) ARCHS_OVERRIDE="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Devices have been arm64-only since iOS 11. Simulators have not: Xcode still
# builds an x86_64 slice for them (Rosetta, and Intel Macs), and a link
# against an arm64-only archive fails outright with "found architecture
# 'arm64', required architecture 'x86_64'". So the simulator library is fat.
archs_for_sdk() {
  if [ -n "$ARCHS_OVERRIDE" ]; then
    echo "$ARCHS_OVERRIDE"
  elif [ "$1" = "iphonesimulator" ]; then
    echo "arm64 x86_64"
  else
    echo "arm64"
  fi
}

# Same base object list as native/vice_core/{linux,android}/CMakeLists.txt.
VICE_BASE_OBJECT_NAMES="alarm attach autostart autostart-prg cbmdos cbmimage
charset clipboard cmdline color crc32 crt debug dma event findpath fliplist
gcr info init initcmdline interrupt kbdbuf keyboard keymap lib log machine-bus
machine main mainlock m3u network opencbmlib palette profiler ram rawfile
rawnet resources romset screenshot sha1 snapshot socket sound sysfile traps
util vicefeatures vsync zfile zipcode midi"

# Same c64sc (game machine) static lib set as the Android CMakeLists.
VICE_GAME_LIBS="arch/shared/libarchdep.a tapeport/libtapeport.a
c64/libc64sc.a c64/cart/libc64cartsystem.a c64/cart/libc64cart.a
c64/cart/libc64commoncart.a datasette/libdatasette.a drive/iec/libdriveiec.a
drive/iecieee/libdriveiecieee.a drive/iec/c64exp/libdriveiecc64exp.a
drive/ieee/libdriveieee.a drive/libdrive.a drive/tcbm/libdrivetcbm.a
lib/p64/libp64.a iecbus/libiecbus.a parallel/libparallel.a vdrive/libvdrive.a
sid/libsid.a resid/libresid.a resid-dtv/libresiddtv.a monitor/libmonitor.a
joyport/libjoyport.a samplerdrv/libsamplerdrv.a
arch/shared/sounddrv/libsounddrv.a arch/shared/mididrv/libmididrv.a
arch/shared/socketdrv/libsocketdrv.a arch/shared/hwsiddrv/libhwsiddrv.a
gfxoutputdrv/libgfxoutputdrv.a printerdrv/libprinterdrv.a
diskimage/libdiskimage.a fsdevice/libfsdevice.a tape/libtape.a
fileio/libfileio.a serial/libserial.a core/libcore.a rs232drv/librs232drv.a
viciisc/libviciisc.a raster/libraster.a userport/libuserport.a diag/libdiag.a
core/rtc/librtc.a video/libvideo.a arch/headless/libarch.a
imagecontents/libimagecontents.a c64/libc64scstubs.a hvsc/libhvsc.a
lib/libzmbv/libzmbv.a lib/linenoise-ng/liblinenoiseng.a"

VICE_VSID_LIBS="arch/shared/libarchdep.a c64/libvsid.a c64/libvsidstubs.a
sid/libsid.a resid/libresid.a resid-dtv/libresiddtv.a monitor/libmonitor.a
arch/shared/sounddrv/libsounddrv.a arch/shared/mididrv/libmididrv.a
arch/shared/socketdrv/libsocketdrv.a arch/shared/hwsiddrv/libhwsiddrv.a
serial/libserial.a core/libcore.a vicii/libvicii.a
c64/cart/libc64cartsystem.a c64/cart/libc64cart.a c64/cart/libc64commoncart.a
lib/md5/libmd5.a raster/libraster.a video/libvideo.a joyport/libjoyport.a
hvsc/libhvsc.a datasette/libdatasette.a arch/headless/libarch.a
imagecontents/libimagecontents.a lib/libzmbv/libzmbv.a
samplerdrv/libsamplerdrv.a"

# Builds one core for one (sdk, arch) into $OBJ_ROOT/<sdk>/<arch>/lib<core>.a.
build_core() {
  local core_name="$1" bridge_src="$2" export_pattern="$3" libs="$4"
  local sdk="$5" arch="$6"

  local sdk_path min_flag vice_build build_tag
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
  if [ "$sdk" = "iphonesimulator" ]; then
    min_flag="-mios-simulator-version-min=$IOS_MIN"
    build_tag="iossim"
  else
    min_flag="-mios-version-min=$IOS_MIN"
    build_tag="ios"
  fi
  vice_build="$VICE_SRC/build-$build_tag-$arch-headless"

  local obj_dir="$OBJ_ROOT/$sdk/$arch/$core_name"
  local out_dir="$OBJ_ROOT/$sdk/$arch"
  mkdir -p "$obj_dir"

  local cflags=(
    -arch "$arch" -isysroot "$sdk_path" "$min_flag"
    -std=c11 -O2 -fno-common -fPIC -Wall
    -I"$BRIDGE"
    -I"$vice_build/src"
    -I"$VICE_SRC/src"
    -I"$VICE_SRC/src/arch/headless"
    -I"$VICE_SRC/src/arch/shared"
    -I"$VICE_SRC/src/arch"
    -I"$VICE_SRC/src/c64"
    -I"$VICE_SRC/src/datasette"
    -I"$VICE_SRC/src/drive"
    -I"$VICE_SRC/src/monitor"
    -I"$VICE_SRC/src/tape"
    -I"$VICE_SRC/src/tapeport"
  )

  # The bridge is compiled WITHOUT the wrap renames: it defines __wrap_* and
  # calls __real_* under those literal names, exactly as it does for GNU ld.
  xcrun clang "${cflags[@]}" -c "$bridge_src" -o "$obj_dir/bridge.o"
  xcrun clang "${cflags[@]}" -c "$BRIDGE/audio_backend_ios.c" -o "$obj_dir/audio_backend_ios.o"

  local base_objects=()
  local obj
  for obj in $VICE_BASE_OBJECT_NAMES; do
    base_objects+=("$vice_build/src/$obj.o")
  done

  # Missing archives are skipped rather than fatal, matching the Android
  # CMakeLists: which ones exist depends on the configure options.
  #
  # Listed twice, and NOT force-loaded. ld resolves archives in command-line
  # order, so a second pass stands in for GNU ld's --start-group (which the
  # Linux and Android builds use); pulling every member in instead would drag
  # in unreferenced ones that collide -- libresid.a and libresid-dtv.a both
  # have a version.o defining _resid_version_string.
  local archives=() lib pass
  for pass in 1 2; do
    for lib in $libs; do
      [ -f "$vice_build/src/$lib" ] && archives+=("$vice_build/src/$lib")
    done
  done

  printf '%s\n' "$export_pattern" > "$obj_dir/exports.txt"

  # Each bridge wraps its own subset: the vsid core runs with video disabled
  # and so, unlike the game core, does not intercept the video_canvas_*
  # calls (see the --wrap lists in native/vice_core/android/CMakeLists.txt).
  # Under GNU ld a symbol nobody wraps simply resolves to VICE's own
  # definition. Here the whole tree was compiled to call __wrap_*, so point
  # the unwrapped ones straight back at the originals.
  local aliases=() sym
  for sym in ${CORE_PASSTHROUGH:-}; do
    aliases+=("-alias" "___real_$sym" "___wrap_$sym")
  done

  xcrun ld -r -arch "$arch" \
    -o "$obj_dir/$core_name.o" \
    "$obj_dir/bridge.o" "$obj_dir/audio_backend_ios.o" \
    "${base_objects[@]}" \
    "${archives[@]}" \
    ${aliases[@]+"${aliases[@]}"} \
    -exported_symbols_list "$obj_dir/exports.txt"

  rm -f "$out_dir/lib$core_name.a"
  xcrun libtool -static -o "$out_dir/lib$core_name.a" "$obj_dir/$core_name.o"

  # The whole point of the prelink: the API is visible, VICE's innards are
  # not. If this stops holding, the two cores collide at app link time.
  local exported
  exported="$(xcrun nm -gU "$out_dir/lib$core_name.a" | awk '$2 == "T" {print $3}' | sort)"
  if [ -z "$exported" ]; then
    echo "$core_name exports nothing -- prelink went wrong" >&2
    exit 1
  fi
  local leaked
  leaked="$(grep -cv "^${export_pattern%\*}" <<< "$exported" || true)"
  if [ "$leaked" != "0" ]; then
    echo "$core_name leaks $leaked non-API symbols:" >&2
    grep -v "^${export_pattern%\*}" <<< "$exported" | head -10 >&2
    exit 1
  fi

  # Archives are pulled in lazily above, so a VICE object that nothing in the
  # command line reached would silently leave a dangling reference to be
  # discovered only when Xcode links the app. Do that link here instead: this
  # is also the check that the frameworks named in
  # flutter_app/ios/Flutter/VICECore.xcconfig are the ones actually needed.
  if ! xcrun clang -arch "$arch" -isysroot "$sdk_path" "$min_flag" \
      -dynamiclib -o "$obj_dir/linkcheck.dylib" \
      -Wl,-force_load,"$out_dir/lib$core_name.a" \
      -lz -lc++ -framework AudioToolbox -framework CoreFoundation \
      -Wl,-undefined,error 2>"$obj_dir/linkcheck.log"; then
    echo "$core_name has unresolved symbols:" >&2
    head -20 "$obj_dir/linkcheck.log" >&2
    exit 1
  fi
  echo "  $arch/lib$core_name.a  $(du -h "$out_dir/lib$core_name.a" | cut -f1)  ($(wc -l <<< "$exported" | tr -d ' ') exported symbols)"
}

for sdk in $SDKS; do
  case "$sdk" in
    iphoneos|iphonesimulator) ;;
    *) echo "--sdk must be iphoneos or iphonesimulator" >&2; exit 1 ;;
  esac

  archs="$(archs_for_sdk "$sdk")"
  out_dir="$OUT_ROOT/$sdk"
  mkdir -p "$out_dir"

  for arch in $archs; do
    if [ "$sdk" = "iphonesimulator" ]; then
      vice_build="$VICE_SRC/build-iossim-$arch-headless"
    else
      vice_build="$VICE_SRC/build-ios-$arch-headless"
    fi
    if [ ! -f "$vice_build/src/log.o" ]; then
      echo "=== VICE $sdk/$arch tree not built yet; building it now ==="
      "$HERE/build-vice-ios-headless.sh" --sdk "$sdk" --arch "$arch"
    fi

    echo "=== $sdk/$arch ==="
    CORE_PASSTHROUGH="" \
    build_core vicecore "$BRIDGE/vice_bridge.c" '_vice_core_*' \
      "$VICE_GAME_LIBS" "$sdk" "$arch"
    CORE_PASSTHROUGH="video_canvas_create video_canvas_can_resize video_canvas_resize video_canvas_refresh" \
    build_core vicecore_vsid "$BRIDGE/vice_vsid_bridge.c" '_vice_vsid_*' \
      "$VICE_VSID_LIBS" "$sdk" "$arch"
  done

  # One archive per SDK, holding every arch that SDK builds for.
  for core_name in vicecore vicecore_vsid; do
    slices=()
    for arch in $archs; do
      slices+=("$OBJ_ROOT/$sdk/$arch/lib$core_name.a")
    done
    rm -f "$out_dir/lib$core_name.a"
    xcrun lipo -create "${slices[@]}" -output "$out_dir/lib$core_name.a"
  done
done

echo
echo "Done. Libraries in $OUT_ROOT:"
find "$OUT_ROOT" -name '*.a' | sort | while read -r lib; do
  echo "  $(du -h "$lib" | cut -f1)	${lib#"$OUT_ROOT"/}	[$(xcrun lipo -archs "$lib")]"
done
