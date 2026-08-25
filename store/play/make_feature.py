#!/usr/bin/env python3
"""Builds the 1024x500 Play Store feature graphic from a project's icon parts.

The icon stacks its three pieces in a square; a banner has the opposite shape,
so the same pieces are laid out side by side instead - the machine's mark on
the left, the Retro script and the machine's name to the right of it. Colours,
gradient, glow and every drawn element come from that project's own
tool/make_icons.py, so the banner cannot drift away from the icon it belongs to.

    python3 make_feature.py <project> <out.png>

where <project> is one of the keys in PROJECTS below.
"""

from __future__ import annotations

import importlib.util
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 1024, 500

PROJECTS = {
    "amiga": {
        "icons": "/home/jon/StudioProjects/Retro-Amiga/app/tool/make_icons.py",
        "name": "AMIGA",
        # (function, kwarg) - each generator names its mark after the machine.
        "mark": lambda m, h: m.tick(h),
        "glow": (190, 110, 220),
    },
    "dosbox": {
        "icons": "/home/jon/StudioProjects/Retro-Dosbox/flutter_app/tool/make_icons.py",
        "name": "DOSBOX",
        # prompt_screen takes a width and is 0.62 as tall, so it eats far more
        # of the banner than a tick does; asking for a shorter one is what
        # leaves room for the longer wordmark beside it.
        "mark": lambda m, h: m.prompt_screen(round(h * 0.80 / 0.62)),
        "glow": (255, 150, 30),
    },
    "c64": {
        "icons": "/home/jon/StudioProjects/Retro-C64/flutter_app/tool/make_icons.py",
        "name": "64",
        # ready_screen takes a width and returns a wider-than-tall panel.
        "mark": lambda m, h: m.ready_screen(round(h * 1.15)),
        # The C64's own screen is blue-violet; a green pool behind it reads as
        # a different machine's colour bleeding in.
        "glow": (125, 110, 225),
    },
    "saturn": {
        "icons": "/home/jon/StudioProjects/Retro-Saturn/flutter_app/tool/make_icons.py",
        "name": "SATURN",
        # swirl() takes a width and returns a square, so height is the ask.
        "mark": lambda m, h: m.swirl(h),
        "glow": (80, 140, 235),
    },
}


def load(path):
    """Import a project's make_icons.py by path.

    It resolves its own asset paths from __file__, so importing it in place is
    what keeps the logo crop and font lookups working.
    """
    spec = importlib.util.spec_from_file_location("make_icons", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def background(module, glow_rgb):
    canvas = module.vertical_gradient(
        (WIDTH, HEIGHT), [module.BG_TOP, module.BG_BOTTOM]
    ).convert("RGBA")
    # One pool of light behind the mark, matching the icon's own lit-from-below
    # look rather than a flat plate.
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse((-60, 120, 620, HEIGHT + 160), fill=glow_rgb + (105,))
    draw.ellipse((120, 240, 480, HEIGHT + 60), fill=glow_rgb + (80,))
    glow = glow.filter(ImageFilter.GaussianBlur(130))
    return Image.alpha_composite(canvas, glow)


def build(key):
    cfg = PROJECTS[key]
    module = load(cfg["icons"])
    canvas = background(module, cfg["glow"])

    mark = cfg["mark"](module, round(HEIGHT * 0.56))

    # The mark sits in the left third, vertically centred; the wordmark stacks
    # to its right, the pair centred together so neither floats.
    mark_x = round(WIDTH * 0.085)
    canvas.alpha_composite(mark, (mark_x, (HEIGHT - mark.height) // 2))

    text_x = mark_x + mark.width + round(WIDTH * 0.06)
    # Measured from what the mark actually left, not a fixed fraction: DOSBOX
    # is both a wider mark and a longer word than AMIGA, and a constant width
    # runs it off the right edge.
    text_w = WIDTH - text_x - round(WIDTH * 0.05)
    script = module.retro_script(round(text_w * 0.86))
    name = module.chrome_text(cfg["name"], text_w, round(HEIGHT * 0.30))
    stack = script.height + name.height + round(HEIGHT * 0.03)
    top = (HEIGHT - stack) // 2
    canvas.alpha_composite(script, (text_x, top))
    canvas.alpha_composite(name, (text_x, top + script.height + round(HEIGHT * 0.03)))
    return canvas.convert("RGB")


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in PROJECTS:
        sys.exit(f"usage: {os.path.basename(__file__)} "
                 f"{{{'|'.join(PROJECTS)}}} <out.png>")
    build(sys.argv[1]).save(sys.argv[2])
    print(f"wrote {sys.argv[2]}")


if __name__ == "__main__":
    main()
