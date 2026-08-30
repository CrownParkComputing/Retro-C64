#!/bin/sh
# Build a C64 ROM zip for testing the in-app import, from the VICE project's
# own data directory.
#
#     tools/fetch-test-roms.sh [output.zip]        # default: ./c64-roms.zip
#
# The ROMs are NOT in this repo and must not be. kernal, BASIC, chargen and the
# 1541 DOS ROM are Commodore's, Cloanto's today, and shipping them inside an app
# -- or committing them here -- is redistribution that is not ours to do. See
# the asset block in flutter_app/pubspec.yaml, which is commented out for the
# same reason.
#
# Fetching them for your own testing is a different act, and is exactly what
# RomInstallService.guidance already tells users to do ("copy them from an
# existing VICE installation"). This script just automates that, so a tester can
# be handed one zip instead of instructions.
#
# What it produces is deliberately shaped like a real download: VICE's own
# C64/ and DRIVES/ layout, nested rather than flat, so it exercises the zip
# import's basename routing rather than a tidied-up best case.
set -eu

OUT="${1:-c64-roms.zip}"
BASE="https://raw.githubusercontent.com/VICE-Team/svn-mirror/main/vice/data"
DRIVE_ROM="dos1541-325302-01+901229-05.bin"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/C64" "$WORK/DRIVES"

echo "--- machine ROMs"
for f in kernal-901227-03.bin basic-901226-01.bin chargen-901225-01.bin; do
  curl -fsSL "$BASE/C64/$f" -o "$WORK/C64/$f"
  echo "    $f  $(wc -c < "$WORK/C64/$f" | tr -d ' ') bytes"
done

# The + in the drive ROM's name is legal in a filename and means "space" in a
# URL, so it has to be encoded or the fetch 404s.
echo "--- drive ROM"
curl -fsSL "$BASE/DRIVES/$(printf '%s' "$DRIVE_ROM" | sed 's/+/%2B/g')" \
  -o "$WORK/DRIVES/$DRIVE_ROM"
echo "    $DRIVE_ROM  $(wc -c < "$WORK/DRIVES/$DRIVE_ROM" | tr -d ' ') bytes"

rm -f "$OUT"
( cd "$WORK" && zip -qr "$OUT" C64 DRIVES ) 2>/dev/null || \
  ( cd "$WORK" && zip -qr "$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")" C64 DRIVES )
echo "--- wrote $OUT"
echo
echo "Drop it in the app's folder (Files -> On My iPad -> Retro-C64)"
echo "and use Scan for ROMs. No unpacking: the scan reads the zip."
echo
echo "Without the drive ROM the machine boots and only .d64 fails, with"
echo "?DEVICE NOT PRESENT -- which is why it is in here and not left optional."
