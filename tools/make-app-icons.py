#!/usr/bin/env python3
"""Generate the app icons for iOS and Android from one master.

Run after changing the logo or the badge:

    tools/make-app-icons.py

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

from PIL import Image, ImageDraw, ImageFont

REPO = pathlib.Path(__file__).resolve().parent.parent
APP = REPO / "flutter_app"
LOGO = APP / "assets/images/retro_recomp_logo.png"
ANDROID_BG = APP / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_background.png"
ICONSET = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
RUNNER = APP / "ios/Runner"
ANDROID_RES = APP / "android/app/src/main/res"

# Android density buckets, as multiples of the 48dp legacy / 108dp adaptive
# baseline.
ANDROID_DENSITIES = {
    "mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4,
}

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


def _font(px: int) -> ImageFont.FreeTypeFont:
    for path in (
        "/usr/share/fonts/liberation/LiberationSans-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/noto/NotoSans-Bold.ttf",
    ):
        if pathlib.Path(path).exists():
            return ImageFont.truetype(path, px)
    return ImageFont.load_default()


def badge_only(size: int, colour: tuple) -> Image.Image:
    """Just the ring and the C64, on transparency, for Android's foreground."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    ring_col = (108, 94, 181, 255)
    text_col = (160, 160, 255, 255)
    cx = cy = size / 2
    radius = size * 0.44
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        outline=ring_col,
        width=max(2, round(size * 0.05)),
    )
    font = _font(round(size * 0.36))
    l, t, r, b = draw.textbbox((0, 0), "C64", font=font)
    draw.text((cx - (r + l) / 2, cy - (b + t) / 2), "C64", font=font, fill=text_col)
    return img


def master(size: int, logo: Image.Image, colour: tuple) -> Image.Image:
    """The icon: a C64 badge over the Retro Recompilation wordmark.

    The badge carries the icon and the wordmark identifies it. That order
    matters, because an app icon is mostly seen at 58-120px: the wordmark
    alone was an unreadable smear at those sizes (it is 720x185 artwork
    squeezed into a square), while three big characters in a ring stay
    legible all the way down to Settings.

    Deliberately "C64" set as type rather than Commodore's own chicken-head
    logo. That mark is still a live trademark and this is going on a store.
    """
    canvas = Image.new("RGB", (size, size), colour)
    draw = ImageDraw.Draw(canvas)

    # C64 screen colours, so the badge reads as the machine rather than as
    # generic chrome: the border blue and the lighter text blue.
    ring_col = (108, 94, 181)
    text_col = (160, 160, 255)

    # Badge sits in the upper two-thirds; the wordmark takes the bottom strip.
    cx, cy = size / 2, size * 0.415
    radius = size * 0.285
    stroke = max(2, round(size * 0.032))
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        outline=ring_col,
        width=stroke,
    )

    label = "C64"
    fsize = round(size * 0.235)
    font = _font(fsize)
    l, t, r, b = draw.textbbox((0, 0), label, font=font)
    draw.text((cx - (r + l) / 2, cy - (b + t) / 2), label, font=font, fill=text_col)

    # Wordmark underneath, small: it names the app for anyone reading the
    # 1024px store listing, and simply disappears at thumbnail sizes, which
    # is the correct behaviour rather than a compromise.
    target_w = int(size * 0.74)
    target_h = max(1, round(logo.height * target_w / logo.width))
    scaled = logo.resize((target_w, target_h), Image.LANCZOS)
    canvas.paste(
        scaled,
        ((size - target_w) // 2, round(size * 0.795) - target_h // 2),
        scaled,
    )
    return canvas


def write_android(logo: Image.Image, colour: tuple) -> int:
    """Android's three layers, from the same master.

    The adaptive foreground is NOT the full icon. A launcher crops that layer
    to a circle or squircle and animates it, so anything outside the central
    safe zone is thrown away -- which is why the badge is scaled to well
    under the layer size here and the wordmark is left out of it entirely.
    The legacy square icon, which older launchers show uncropped, does get
    the full composition.
    """
    written = 0
    for bucket, factor in ANDROID_DENSITIES.items():
        out = ANDROID_RES / f"mipmap-{bucket}"
        if not out.is_dir():
            continue

        legacy_px = round(48 * factor)
        master(1024, logo, colour).resize(
            (legacy_px, legacy_px), Image.LANCZOS
        ).save(out / "ic_launcher.png")

        adaptive_px = round(108 * factor)
        Image.new("RGB", (adaptive_px, adaptive_px), colour).save(
            out / "ic_launcher_background.png"
        )

        # Badge only, inside the safe zone: the foreground layer is 108dp but
        # only the middle 72dp is guaranteed visible.
        fg = Image.new("RGBA", (adaptive_px, adaptive_px), (0, 0, 0, 0))
        badge_px = round(adaptive_px * 0.62)
        badge = badge_only(badge_px, colour)
        fg.paste(badge, ((adaptive_px - badge_px) // 2,) * 2, badge)
        fg.save(out / "ic_launcher_foreground.png")

        written += 3
        print(f"  mipmap-{bucket}: legacy {legacy_px}px, adaptive {adaptive_px}px")
    return written


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

    android = write_android(logo, colour)
    print(
        f"wrote {len(written)} catalogue icons, {len(LOOSE)} loose icons "
        f"and {android} Android icons"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
