#!/usr/bin/env python3
"""
Render the NoNap app icon as a high-resolution PNG.

Design: a macOS-style rounded-rect tile in deep midnight (the website's --void/
--night), holding a warm amber coffee cup with rising steam, and the signature
green "awake" status dot in the upper-right — the same visual language as the
menu-bar status item (a coffee cup + green dot).

Output is a 1024x1024 master PNG. Scripts/make_iconset.sh slices it into the
.iconset / .icns that ships in the app bundle.

    python3 Scripts/make_icon.py Resources/Assets/icon_1024.png
"""

import math
import sys

from PIL import Image, ImageDraw, ImageFilter

# --- brand palette (from web/index.html) ---------------------------------
VOID = (10, 14, 26)        # #0a0e1a deep midnight
NIGHT = (17, 23, 38)       # #111726
SLATE = (26, 34, 51)       # #1a2233
AMBER = (232, 166, 107)    # #e8a66b coffee crema
AMBER_HOT = (245, 184, 119)  # #f5b877
STEAM = (231, 226, 214)    # #e7e2d6 warm off-white
GREEN = (74, 222, 128)     # #4ade80 the active dot


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vertical_gradient(size, top, bottom):
    """A smooth top->bottom vertical gradient image."""
    grad = Image.new("RGB", (1, size), top)
    px = grad.load()
    for y in range(size):
        px[0, y] = lerp(top, bottom, y / (size - 1))
    return grad.resize((size, size))


def rounded_mask(size, radius, supersample=1):
    s = size * supersample
    r = radius * supersample
    mask = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=r, fill=255)
    if supersample > 1:
        mask = mask.resize((size, size), Image.LANCZOS)
    return mask


def make_icon(size=1024):
    SS = 4  # supersample factor for crisp curves
    W = size * SS

    base = Image.new("RGBA", (W, W), (0, 0, 0, 0))

    # --- background tile: midnight vertical gradient -----------------------
    grad = vertical_gradient(W, lerp(NIGHT, SLATE, 0.35), VOID).convert("RGBA")
    # Apple's continuous-corner radius is ~22.37% of the icon size.
    radius = int(W * 0.2237)
    tile_mask = rounded_mask(W, radius)
    base.paste(grad, (0, 0), tile_mask)

    draw = ImageDraw.Draw(base)

    # subtle top sheen for depth
    sheen = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse([-W * 0.3, -W * 0.55, W * 1.3, W * 0.45],
               fill=(255, 255, 255, 16))
    sheen = sheen.filter(ImageFilter.GaussianBlur(W * 0.04))
    base = Image.alpha_composite(base, Image.composite(
        sheen, Image.new("RGBA", (W, W), (0, 0, 0, 0)), tile_mask))
    draw = ImageDraw.Draw(base)

    # --- geometry of the cup ----------------------------------------------
    cx = W * 0.46          # cup centred slightly left to leave room for steam
    cup_top = W * 0.44
    cup_bottom = W * 0.72
    cup_half_top = W * 0.20
    cup_half_bot = W * 0.145   # gentle taper

    # --- rising steam (behind the cup) ------------------------------------
    steam_layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(steam_layer)
    for i, dx in enumerate((-0.075, 0.0, 0.075)):
        x0 = cx + W * dx
        top_y = W * 0.165
        bot_y = cup_top - W * 0.015
        width = W * 0.026
        pts = []
        steps = 48
        for s in range(steps + 1):
            t = s / steps
            y = bot_y + (top_y - bot_y) * t
            wobble = math.sin(t * math.pi * 2.4 + i * 1.7) * W * 0.024
            pts.append((x0 + wobble, y))
        # fade the wisp out toward the top so it dissolves like real steam
        for s in range(steps):
            t = s / steps
            alpha = int(190 * (1.0 - t * 0.75))
            sdraw.line([pts[s], pts[s + 1]], fill=(*STEAM, alpha),
                       width=int(width), joint="curve")
    steam_layer = steam_layer.filter(ImageFilter.GaussianBlur(W * 0.010))
    base = Image.alpha_composite(base, steam_layer)
    draw = ImageDraw.Draw(base)

    # --- saucer ------------------------------------------------------------
    saucer_y = cup_bottom + W * 0.012
    saucer_hw = W * 0.255
    draw.ellipse([cx - saucer_hw, saucer_y - W * 0.028,
                  cx + saucer_hw, saucer_y + W * 0.05],
                 fill=lerp(AMBER, VOID, 0.45))
    draw.ellipse([cx - saucer_hw, saucer_y - W * 0.032,
                  cx + saucer_hw, saucer_y + W * 0.03],
                 fill=AMBER)

    # --- handle ------------------------------------------------------------
    handle_cx = cx + cup_half_top * 0.92
    handle_cy = (cup_top + cup_bottom) / 2
    hr_out = W * 0.085
    hr_in = W * 0.045
    draw.ellipse([handle_cx - hr_out, handle_cy - hr_out,
                  handle_cx + hr_out, handle_cy + hr_out], fill=AMBER)
    draw.ellipse([handle_cx - hr_in, handle_cy - hr_in,
                  handle_cx + hr_in, handle_cy + hr_in],
                 fill=lerp(NIGHT, SLATE, 0.35))

    # --- cup body (tapered) with a warm vertical gradient ------------------
    cup_poly = [
        (cx - cup_half_top, cup_top),
        (cx + cup_half_top, cup_top),
        (cx + cup_half_bot, cup_bottom),
        (cx - cup_half_bot, cup_bottom),
    ]
    cup_mask = Image.new("L", (W, W), 0)
    cm = ImageDraw.Draw(cup_mask)
    cm.polygon(cup_poly, fill=255)
    # round the bottom corners a touch
    cm.ellipse([cx - cup_half_bot, cup_bottom - W * 0.05,
                cx + cup_half_bot, cup_bottom + W * 0.05], fill=255)
    cup_grad = vertical_gradient(W, AMBER_HOT, lerp(AMBER, VOID, 0.32)).convert("RGBA")
    base.paste(cup_grad, (0, 0), cup_mask)
    draw = ImageDraw.Draw(base)

    # coffee surface (ellipse at the top rim)
    rim_y = cup_top
    draw.ellipse([cx - cup_half_top, rim_y - W * 0.03,
                  cx + cup_half_top, rim_y + W * 0.03],
                 fill=lerp(AMBER, VOID, 0.15))
    draw.ellipse([cx - cup_half_top * 0.86, rim_y - W * 0.022,
                  cx + cup_half_top * 0.86, rim_y + W * 0.022],
                 fill=lerp((40, 24, 14), AMBER, 0.18))  # dark coffee

    # left-side highlight on the cup for a bit of dimensionality
    hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hl)
    hd.line([(cx - cup_half_top * 0.75, cup_top + W * 0.04),
             (cx - cup_half_bot * 0.75, cup_bottom - W * 0.03)],
            fill=(255, 255, 255, 70), width=int(W * 0.012))
    hl = hl.filter(ImageFilter.GaussianBlur(W * 0.006))
    base = Image.alpha_composite(base, Image.composite(
        hl, Image.new("RGBA", (W, W), (0, 0, 0, 0)), cup_mask))
    draw = ImageDraw.Draw(base)

    # --- the "awake" green status dot (upper-right), with glow -------------
    dot_r = W * 0.072
    dot_cx = W * 0.775
    dot_cy = W * 0.225
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([dot_cx - dot_r * 2.4, dot_cy - dot_r * 2.4,
                dot_cx + dot_r * 2.4, dot_cy + dot_r * 2.4],
               fill=(*GREEN, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(W * 0.03))
    base = Image.alpha_composite(base, glow)
    draw = ImageDraw.Draw(base)
    draw.ellipse([dot_cx - dot_r, dot_cy - dot_r,
                  dot_cx + dot_r, dot_cy + dot_r], fill=GREEN)
    # inner sheen on the dot
    draw.ellipse([dot_cx - dot_r * 0.55, dot_cy - dot_r * 0.7,
                  dot_cx + dot_r * 0.2, dot_cy - dot_r * 0.05],
                 fill=(*lerp(GREEN, (255, 255, 255), 0.6), 200))

    # --- finish: clip to the tile and downsample --------------------------
    base.putalpha(Image.composite(base.getchannel("A"),
                                  Image.new("L", (W, W), 0), tile_mask))
    icon = base.resize((size, size), Image.LANCZOS)
    return icon


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "Resources/Assets/icon_1024.png"
    icon = make_icon(1024)
    icon.save(out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
