#!/usr/bin/env python3
"""Builds the launcher icon and every size Android and iOS ask for.

The same three-part icon as the Amiga front end - the Retro script cut from the
Retro Recompilation logo, the machine's name under it, and the machine's own
mark below that - so the two sit together on a home screen and read as one
family. What differs is the mark: an Amiga has its boot tick, a C64 has the
screen it wakes up on, blue with READY. and a cursor waiting.

    python3 tool/make_icons.py

Run from the flutter_app directory. Overwrites the mipmaps and the iOS icon
set.
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(HERE, "assets", "images", "retro_recomp_logo.png")
FONT = "/usr/share/fonts/liberation/LiberationSans-Bold.ttf"
MONO = "/usr/share/fonts/TTF/DejaVuSansMono-Bold.ttf"

SIZE = 1024

BG_TOP = (10, 14, 34)
BG_BOTTOM = (4, 5, 12)

# The wordmark's blue, top to bottom: white highlight into deep blue.
CHROME = [
    (232, 244, 255),
    (150, 205, 250),
    (56, 120, 220),
    (26, 60, 160),
    (120, 180, 240),
]

# The C64's own two blues, as the machine mixes them: the screen is the darker
# one, the border and every character on it the lighter.
C64_SCREEN = (64, 49, 141)
C64_LIGHT = (120, 105, 196)


def vertical_gradient(size, colours):
    width, height = size
    grad = Image.new("RGB", (1, height))
    pixels = grad.load()
    steps = len(colours) - 1
    for y in range(height):
        position = y / max(1, height - 1) * steps
        index = min(int(position), steps - 1)
        blend = position - index
        start, end = colours[index], colours[index + 1]
        pixels[0, y] = tuple(
            int(start[c] + (end[c] - start[c]) * blend) for c in range(3)
        )
    return grad.resize((width, height))


def background():
    canvas = vertical_gradient((SIZE, SIZE), [BG_TOP, BG_BOTTOM]).convert("RGBA")
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse((60, 250, SIZE - 60, SIZE - 120), fill=(60, 60, 200, 110))
    draw.ellipse((200, 520, SIZE - 200, SIZE - 60), fill=(40, 140, 220, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    return Image.alpha_composite(canvas, glow)


def retro_script(width):
    """The Retro script, cut out of the logo rather than redrawn."""
    logo = Image.open(LOGO).convert("RGBA")
    script = logo.crop((168, 0, 578, 92))
    # The bracket rules either side of the script poke into the crop. Every
    # pixel of the script is warm, so anything bluer than it is red is a rule.
    pixels = script.load()
    for y in range(script.height):
        for x in range(script.width):
            r, g, b, a = pixels[x, y]
            if a and b > r:
                pixels[x, y] = (r, g, b, 0)
    height = round(script.height * width / script.width)
    return script.resize((width, height), Image.LANCZOS)


def chrome_text(text, width, height):
    """[text] in the wordmark's blue, with the dark outline it has."""
    size = 10
    font = ImageFont.truetype(FONT, size)
    while True:
        probe = ImageFont.truetype(FONT, size + 4)
        box = probe.getbbox(text)
        if box[2] - box[0] > width or box[3] - box[1] > height:
            break
        size += 4
        font = probe

    box = font.getbbox(text)
    pad = 18
    layer = Image.new("RGBA", (box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2))
    ImageDraw.Draw(layer).text(
        (pad - box[0], pad - box[1]), text, font=font, fill=(255, 255, 255, 255)
    )

    mask = layer.split()[3]
    fill = vertical_gradient(layer.size, CHROME).convert("RGBA")
    fill.putalpha(mask)

    outline = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    outline.paste((12, 20, 48, 255), (0, 0), mask.filter(ImageFilter.MaxFilter(9)))
    return Image.alpha_composite(outline, fill)


def ready_screen(width):
    """The screen a C64 wakes up on: READY. and a cursor, in its own blues.

    Not the whole boot message. At 48 pixels a paragraph of text is grey mush,
    whereas one word and a block still read as a machine waiting for you.
    """
    height = round(width * 0.62)
    scale = 4
    layer = Image.new("RGBA", (width * scale, height * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    border = round(width * 0.085) * scale
    radius = round(width * 0.06) * scale
    draw.rounded_rectangle(
        (0, 0, width * scale - 1, height * scale - 1),
        radius=radius,
        fill=C64_LIGHT + (255,),
    )
    draw.rounded_rectangle(
        (
            border,
            border,
            width * scale - 1 - border,
            height * scale - 1 - border,
        ),
        radius=round(radius * 0.6),
        fill=C64_SCREEN + (255,),
    )

    text = "READY."
    inner = width * scale - border * 2
    size = 10
    font = ImageFont.truetype(MONO, size)
    while True:
        probe = ImageFont.truetype(MONO, size + 4)
        box = probe.getbbox(text)
        if box[2] - box[0] > inner * 0.74:
            break
        size += 4
        font = probe

    box = font.getbbox(text)
    left = border + round(inner * 0.10)
    top = border + round((height * scale - border * 2) * 0.22)
    draw.text((left - box[0], top - box[1]), text, font=font, fill=C64_LIGHT + (255,))

    # The cursor, on the line below - a solid block, which is what a C64 shows
    # while it waits.
    cell_w = (box[2] - box[0]) / len(text)
    cell_h = box[3] - box[1]
    cursor_top = top + round(cell_h * 1.6)
    draw.rectangle(
        (left, cursor_top, left + round(cell_w), cursor_top + round(cell_h * 1.15)),
        fill=C64_LIGHT + (255,),
    )
    return layer.resize((width, height), Image.LANCZOS)


def artwork(width):
    layer = Image.new("RGBA", (width, width), (0, 0, 0, 0))

    script = retro_script(round(width * 0.80))
    name = chrome_text("C64", round(width * 0.46), round(width * 0.19))
    screen = ready_screen(round(width * 0.62))

    stack = script.height + name.height + screen.height + round(width * 0.05)
    top = max(0, (width - stack) // 2)

    layer.alpha_composite(script, ((width - script.width) // 2, top))
    top += script.height + round(width * 0.015)
    layer.alpha_composite(name, ((width - name.width) // 2, top))
    top += name.height + round(width * 0.035)
    layer.alpha_composite(screen, ((width - screen.width) // 2, top))
    return layer


def master():
    canvas = background()
    art = artwork(round(SIZE * 0.86))
    canvas.alpha_composite(art, ((SIZE - art.width) // 2, (SIZE - art.width) // 2))
    return canvas


def foreground():
    """Everything inside the middle two-thirds, where the launcher's mask
    cannot eat it."""
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    art = artwork(round(SIZE * 0.62))
    layer.alpha_composite(art, ((SIZE - art.width) // 2, (SIZE - art.width) // 2))
    return layer


def rounded(image, radius_fraction=0.22):
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, image.width - 1, image.height - 1),
        radius=round(image.width * radius_fraction),
        fill=255,
    )
    out = image.copy()
    out.putalpha(mask)
    return out


def main():
    icon = master()
    fore = foreground()
    # This project ships its background as a layer of its own rather than a
    # colour, so it gets the icon's ground with the artwork left off.
    back = background()

    res = os.path.join(HERE, "android", "app", "src", "main", "res")
    legacy = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    layers = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for density, px in legacy.items():
        folder = os.path.join(res, f"mipmap-{density}")
        os.makedirs(folder, exist_ok=True)
        icon.resize((px, px), Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher.png")
        )
        rounded(icon.resize((px, px), Image.LANCZOS), 0.5).save(
            os.path.join(folder, "ic_launcher_round.png")
        )
        fore.resize((layers[density],) * 2, Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher_foreground.png")
        )
        back.convert("RGB").resize((layers[density],) * 2, Image.LANCZOS).save(
            os.path.join(folder, "ic_launcher_background.png")
        )

    ios = os.path.join(HERE, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    sizes = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    if os.path.isdir(ios):
        for name, px in sizes.items():
            icon.convert("RGB").resize((px, px), Image.LANCZOS).save(
                os.path.join(ios, name)
            )

    print("icons written")


if __name__ == "__main__":
    main()
