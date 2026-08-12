#!/usr/bin/env python3
"""Generate the iOS app icons from the same artwork Android uses.

Run after changing the logo:

    tools/make-ios-icons.py

Two outputs, because the two toolchains find icons in completely different
ways and the app needs one on both:

  * ios/Runner/Assets.xcassets/AppIcon.appiconset/ -- every size the asset
    catalogue declares. This is what a macOS/Xcode build compiles into
    Assets.car, and the only route the App Store accepts.

  * ios/Runner/AppIcon60x60@2x.png and friends, loose in the bundle root,
    listed under CFBundleIcons in Info.plist. The Linux `iosbox` build cannot
    run actool, so it ships no Assets.car at all -- which is why the app has
    been sitting on the home screen under iOS's grey placeholder grid. Loose
    PNGs are the pre-catalogue mechanism iOS still honours, and they cost
    nothing on a Mac build where the catalogue wins anyway.

The artwork is composed rather than copied from Android's PNGs: an adaptive
icon keeps its foreground inside a safe zone (the logo occupies barely a
sixth of Android's 432px layer, because launchers crop it to a circle or
squircle), while iOS masks the corners itself and expects a full-bleed
square. Copying Android's layer straight over would leave a tiny logo adrift
in a black field. So the same two ingredients -- the plate colour and the
logo -- are recomposed at iOS proportions, from the highest-resolution copy
of the logo in the tree.
"""
import json
import pathlib
import sys

from PIL import Image

REPO = pathlib.Path(__file__).resolve().parent.parent
APP = REPO / "flutter_app"
LOGO = APP / "assets/images/retro_recomp_logo.png"
ANDROID_BG = APP / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_background.png"
ICONSET = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
RUNNER = APP / "ios/Runner"

# Fraction of the icon's width the logo spans. iOS trims roughly a tenth off
# each edge with its rounded-rect mask, so the logo is kept inside 80% and
# still reads at 40px.
LOGO_WIDTH_FRACTION = 0.80

# Loose bundle icons, by the names iOS looks for. Only the handful that
# actually get displayed -- home screen, spotlight, settings -- since this
# path is a fallback for the debug build, not the store submission.
LOOSE = {
    "AppIcon60x60@2x.png": 120,
    "AppIcon60x60@3x.png": 180,
    "AppIcon76x76@2x.png": 152,
    "AppIcon83.5x83.5@2x.png": 167,
    "AppIcon40x40@2x.png": 80,
    "AppIcon29x29@2x.png": 58,
}


def plate_colour() -> tuple:
    """The Android icon's background, so the two platforms match exactly."""
    if ANDROID_BG.exists():
        return Image.open(ANDROID_BG).convert("RGB").getpixel((4, 4))
    return (10, 12, 20)


def master(size: int, logo: Image.Image, colour: tuple) -> Image.Image:
    canvas = Image.new("RGB", (size, size), colour)
    target_w = int(size * LOGO_WIDTH_FRACTION)
    target_h = max(1, round(logo.height * target_w / logo.width))
    scaled = logo.resize((target_w, target_h), Image.LANCZOS)
    canvas.paste(scaled, ((size - target_w) // 2, (size - target_h) // 2), scaled)
    return canvas


def main() -> int:
    if not LOGO.exists():
        print(f"error: no logo at {LOGO}", file=sys.stderr)
        return 1
    logo = Image.open(LOGO).convert("RGBA")
    colour = plate_colour()
    print(f"plate {colour}, logo {logo.size}")

    # Render once at high resolution and downsample, rather than compositing
    # at each size: scaling the finished icon keeps the logo's proportions
    # and edges identical at every size.
    big = master(1024, logo, colour)

    contents = json.loads((ICONSET / "Contents.json").read_text())
    written = set()
    for entry in contents["images"]:
        name = entry.get("filename")
        if not name or name in written:
            continue
        w, _, h = entry["size"].partition("x")
        scale = int(entry["scale"].rstrip("x"))
        px = round(float(w) * scale)
        # No alpha: the App Store rejects an icon with a transparent channel.
        big.resize((px, px), Image.LANCZOS).convert("RGB").save(ICONSET / name)
        written.add(name)
        print(f"  {name}  {px}x{px}")

    for name, px in LOOSE.items():
        big.resize((px, px), Image.LANCZOS).convert("RGB").save(RUNNER / name)
        print(f"  {name}  {px}x{px}  (loose, for the iosbox build)")

    print(f"wrote {len(written)} catalogue icons and {len(LOOSE)} loose icons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
