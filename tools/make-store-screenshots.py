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

iPhone targets exist but are not fed by the iPad source, and that separation is
the point. Apple demands a screenshot set for every family the binary claims;
the app currently declares iPad only (UIDeviceFamily = [2],
TARGETED_DEVICE_FAMILY = "2"), so the iPhone sizes go unused until iPhone is
added back. What must never happen is padding an iPad capture into a 6.9-inch
iPhone frame: it is a legal upload that looks exactly like what it is, a 4:3
picture with bars down both sides. SOURCES below enforces that -- iPhone sizes
can only be produced from an iPhone source folder, shot on an iPhone or an
iPhone simulator.
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
    # App Store Connect: "iPhone 6.9-inch display". Required while the app
    # claims iPhone support. An iPhone 16/17 Pro Max simulator captures at
    # exactly this size, so these pass through unscaled -- the run still
    # matters, because it flattens the alpha channel that a capture carries
    # and App Store Connect rejects.
    "ios-iphone-69-portrait": (1320, 2868),
    "ios-iphone-69-landscape": (2868, 1320),
    # Play Store: no fixed size, but wants 16:9-ish and at least 1080 on the
    # short edge. This is a clean 1080p landscape.
    "android-landscape": (1920, 1080),
}

# Which targets each source folder is allowed to produce.
#
# Sources are NOT interchangeable, which is the whole reason this mapping
# exists: padding a 4:3 iPad capture into a 2.2:1 iPhone frame leaves bars down
# both sides and looks exactly like what it is. An iPad capture may only
# produce iPad and Play sizes; iPhone sizes have to come from an iPhone or an
# iPhone simulator.
SOURCES = {
    "screenshots-raw": [
        "ios-ipad-13-landscape",
        "ios-ipad-13-portrait",
        "android-landscape",
    ],
    "screenshots-raw-iphone": [
        "ios-iphone-69-portrait",
        "ios-iphone-69-landscape",
    ],
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

    targets = SOURCES.get(src.name)
    if targets is None:
        print(
            f"error: {src.name} is not a known source folder. Add it to "
            f"SOURCES, naming the sizes it may produce -- an iPad capture "
            f"must never be padded into an iPhone frame.",
            file=sys.stderr,
        )
        return 1

    out_root = REPO / "store/screenshots"
    for target in targets:
        size = TARGETS[target]
        out = out_root / target
        out.mkdir(parents=True, exist_ok=True)
        for shot in shots:
            img = Image.open(shot).convert("RGB")
            exact = img.size == size
            fit(img, size).save(out / shot.name)
        print(
            f"{target}: {len(shots)} x {size[0]}x{size[1]} -> {out}"
            f"{'  (native, unscaled)' if exact else ''}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
