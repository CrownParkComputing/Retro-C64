#!/usr/bin/env python3
"""Turn raw device screenshots into App Store / Play Store sized images.

    tools/make-store-screenshots.py store/screenshots-raw

Reads every PNG in the given directory (default store/screenshots-raw) and
writes store-ready copies into store/screenshots/<target>/.

WHY THIS IS NOT JUST A RESIZE. App Store Connect rejects a screenshot whose
dimensions are not exactly one of the sizes it lists, and it rejects an image
with an alpha channel. A device capture is neither the right size nor
guaranteed opaque: this iPad shoots 2388x1668, and the required iPad size is
2752x2064. So each image is scaled to fit and then padded to the exact
dimensions on the app's own background colour, which is invisible against
these screens -- the alternative, stretching to fit, distorts the picture and
looks it.

Sizes are Apple's 13-inch iPad and Google's guidance. The 13-inch set is what
App Store Connect asks for even when you shot on an 11-inch device; a set that
matches the device you happen to own is not one of the options.
"""
import pathlib
import sys

from PIL import Image

REPO = pathlib.Path(__file__).resolve().parent.parent

# The app's background, so padding does not read as a border.
BACKDROP = (13, 17, 23)

TARGETS = {
    # App Store Connect: "iPad 13-inch display". Required for an iPad app,
    # whatever you captured on.
    "ios-ipad-13-landscape": (2752, 2064),
    "ios-ipad-13-portrait": (2064, 2752),
    # Play Store: no fixed size, but wants 16:9-ish and at least 1080 on the
    # short edge. This is a clean 1080p landscape.
    "android-landscape": (1920, 1080),
}


def fit(img: Image.Image, size: tuple) -> Image.Image:
    tw, th = size
    scale = min(tw / img.width, th / img.height)
    w, h = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    canvas = Image.new("RGB", size, BACKDROP)
    canvas.paste(img.resize((w, h), Image.LANCZOS), ((tw - w) // 2, (th - h) // 2))
    return canvas


def main(argv) -> int:
    src = pathlib.Path(argv[1]) if len(argv) > 1 else REPO / "store/screenshots-raw"
    if not src.is_dir():
        print(f"error: no such directory {src}", file=sys.stderr)
        return 1
    shots = sorted(p for p in src.glob("*.png"))
    if not shots:
        print(f"error: no PNGs in {src}", file=sys.stderr)
        return 1

    out_root = REPO / "store/screenshots"
    for target, size in TARGETS.items():
        out = out_root / target
        out.mkdir(parents=True, exist_ok=True)
        for shot in shots:
            img = Image.open(shot).convert("RGB")
            fit(img, size).save(out / shot.name)
        print(f"{target}: {len(shots)} x {size[0]}x{size[1]} -> {out}")

    print(
        "\nNote: these are all derived from iPad captures. iPhone screenshots "
        "must be shot on an iPhone -- padding a 4:3 iPad screen into a 2.2:1 "
        "iPhone frame leaves bars down both sides and looks exactly like what "
        "it is."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
