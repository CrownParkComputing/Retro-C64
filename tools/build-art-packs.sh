#!/usr/bin/env bash
# Build one artwork pack per game title from a LaunchBox/EmulationStation
# media set.
#
# Each pack is a zip of four WebP images -- box3d, wheel, title, thumbnail --
# resized for a phone/tablet screen. The app fetches "<title>.zip", extracts
# it once and shows box3d in the games grid (see ArtworkService).
#
# Why re-encode rather than zip the originals: the source PNGs are already
# compressed, so zipping them saves nothing (measured: a 2000 KB set zipped
# to 1990 KB). The size comes from the pixels -- a 1031 KB 3D box render is
# drawn as a grid tile a few hundred pixels wide. Resizing to WebP takes a
# typical title from ~2 MB to ~250 KB with no visible loss at that size.
#
# videos/ and manuals/ are deliberately excluded: 3 GB of the source set, and
# nothing a game grid can use.
#
# Usage:
#   tools/build-art-packs.sh OUT_DIR [title ...]
#
# With no titles, builds every title present in the media set's box3d/ dir.
set -euo pipefail

MEDIA_ROOT="${MEDIA_ROOT:-$HOME/Downloads/aria2/c64/media}"
OUT_DIR="${1:-}"
if [ -z "$OUT_DIR" ]; then
    echo "usage: $0 OUT_DIR [title ...]" >&2
    exit 1
fi
shift || true

if [ ! -d "$MEDIA_ROOT/box3d" ]; then
    echo "error: media set not found at $MEDIA_ROOT" >&2
    echo "       set MEDIA_ROOT to the directory holding box3d/, wheel/, ..." >&2
    exit 1
fi
command -v magick >/dev/null || { echo "error: ImageMagick (magick) required" >&2; exit 1; }

mkdir -p "$OUT_DIR"

# source subdir : output name : target width
SPECS=(
    "box3d:box3d:600"
    "wheel:wheel:512"
    "titles:title:512"
    "thumbnails:thumb:600"
)

# lowercase, letters and digits only: the one normalisation both sides can
# agree on without sharing a lookup table.
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

build_one() {
    local title="$1"
    local staging
    staging="$(mktemp -d)"
    local found=0

    for spec in "${SPECS[@]}"; do
        local dir="${spec%%:*}"
        local rest="${spec#*:}"
        local name="${rest%%:*}"
        local width="${rest##*:}"

        # The set mixes .png/.jpg/.PNG, so take whatever is there.
        local src
        src="$(find "$MEDIA_ROOT/$dir" -maxdepth 1 -iname "$title.png" -o \
                    -maxdepth 1 -iname "$title.jpg" 2>/dev/null | head -1)"
        [ -n "$src" ] || continue

        if magick "$src" -resize "${width}x>" -quality 85 \
                "$staging/$name.webp" 2>/dev/null; then
            found=$((found + 1))
        fi
    done

    if [ "$found" -eq 0 ]; then
        rm -rf "$staging"
        return 1
    fi

    # Packs are named by SLUG, not by display title: the app derives the same
    # slug from its own filename ("outrun.prg" -> outrun) and asks for that.
    # Matching display names instead would need an alias table -- "Out Run"
    # vs "outrun", "Saint Dragon" vs "saint_dragon" -- which rots the moment
    # anyone renames a file.
    ( cd "$staging" && zip -qr "$OUT_DIR/$(slugify "$title").zip" . )
    rm -rf "$staging"
    return 0
}

titles=("$@")
if [ ${#titles[@]} -eq 0 ]; then
    mapfile -t titles < <(find "$MEDIA_ROOT/box3d" -maxdepth 1 -type f \
        \( -iname '*.png' -o -iname '*.jpg' \) -printf '%f\n' \
        | sed 's/\.[^.]*$//' | sort)
fi

built=0
missing=0
for title in "${titles[@]}"; do
    if build_one "$title"; then
        built=$((built + 1))
    else
        echo "  no art for: $title" >&2
        missing=$((missing + 1))
    fi
done

echo "built $built pack(s) in $OUT_DIR ($missing without art)"
du -sh "$OUT_DIR"
