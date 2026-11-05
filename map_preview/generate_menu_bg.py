# -*- coding: utf-8 -*-
"""
Procedural main-menu backdrop — 深渊幸存者 (上深渊下战场).

Layout on the 640x360 logical canvas (project.godot viewport):

  y   0..175  abyss sky: violet-black gradient, blood-red rifts
  y 148..266  KEEP-OUT: hud.gd still draws the title (y=65), the subtitle
              (y=106) and the three buttons (y=156/194/232), so nothing
              high-contrast goes here
  y 175..360  battlefield: dark-arena floor texture (matches ground_map_0.png
              palette #383030/#282828/#404038), three ranks of monster-tide
              silhouettes closing in, scattered gems + drifting motes

Pure backdrop by default: the baked title, the Boss silhouette and the lone
player figure are all OFF (hud.gd draws the title at runtime); pass
--title / --boss / --player to bake any of them back in.

Every sprite comes straight out of resource/pixel32/ at integer scale, so the
characters read exactly like they do in-game.

Outputs:
  assets/ui/menu_bg.png        (640x360 RGBA, game-ready)
  map_preview/menu_bg_2x.png   (1280x720 nearest upscale, preview for the user)

Usage:
  python map_preview/generate_menu_bg.py [--seed 42] [--title-size 48]
                                         [--title] [--boss] [--player]
"""

import argparse
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
PIXEL32 = os.path.join(ROOT, "resource", "pixel32")
OUT_GAME = os.path.join(ROOT, "assets", "ui", "menu_bg.png")
OUT_PREVIEW = os.path.join(HERE, "menu_bg_2x.png")

W, H = 640, 360
HORIZON = 175

# hud.gd overlays these; keep the art quiet inside the box.
KEEP_OUT = (250, 148, 390, 266)

FONT_CANDIDATES = [
    "C:/Windows/Fonts/simhei.ttf",
    "C:/Windows/Fonts/msyhbd.ttc",
    "C:/Windows/Fonts/simsun.ttc",
]

# Abyss sky / floor / accent palette.
SKY_TOP = (0x07, 0x04, 0x0c)
SKY_MID = (0x18, 0x0a, 0x16)
SKY_LOW = (0x2a, 0x10, 0x1e)
RIFT_CORE = (0xe0, 0x40, 0x40)
RIFT_EDGE = (0x6a, 0x18, 0x2c)

FLOOR_DARK = (0x22, 0x1c, 0x1c)
FLOOR_BASE = (0x38, 0x30, 0x30)
FLOOR_LIT = (0x48, 0x3e, 0x38)

SIL_BODY = (0x12, 0x0d, 0x18)
SIL_RIM_FAR = (0x4a, 0x1c, 0x2a)
SIL_RIM_NEAR = (0x8a, 0x2a, 0x34)

TITLE_HI = (0xff, 0xf0, 0xb8)
TITLE_MID = (0xff, 0xd2, 0x4a)
TITLE_LO = (0xe0, 0x78, 0x18)
TITLE_OUTLINE = (0x1f, 0x05, 0x0d)
TITLE_GLOW = (0xff, 0x6a, 0x20)

GEM_GLOW = (0x40, 0xc0, 0x80)
MOTE_WARM = (0xff, 0xd9, 0x59)
MOTE_COOL = (0x70, 0x90, 0xc0)


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def vgrad(stops, h=H, w=W):
    """Vertical gradient -> (h, w, 3) uint8. stops = [(y, (r,g,b)), ...]."""
    ys = np.array([s[0] for s in stops], float)
    cs = np.array([s[1] for s in stops], float)
    col = np.stack([np.interp(np.arange(h), ys, cs[:, i]) for i in range(3)], axis=1)
    return np.repeat(col[:, None, :], w, axis=1).astype(np.uint8)


def to_rgba(arr, alpha=255):
    a = np.full(arr.shape[:2] + (1,), alpha, np.uint8)
    return Image.fromarray(np.concatenate([arr, a], axis=2), "RGBA")


def load_frame(name, fw, fh, index=0):
    """Grab one frame from a pixel32 spritesheet (no resampling — integer art)."""
    sheet = Image.open(os.path.join(PIXEL32, name)).convert("RGBA")
    return sheet.crop((index * fw, 0, index * fw + fw, fh))


def silhouette(frame, body, rim, rim_px=1, alpha=255, top_rim=False):
    """Flatten a sprite to a hard-edged cut-out with a rim light.

    top_rim lights only the upper edge — reads as backlight from the horizon
    glow behind the monster tide, which is what sells the silhouettes.
    """
    mask = frame.split()[3].point(lambda v: 255 if v > 128 else 0)
    out = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    if rim_px > 0:
        if top_rim:
            shifted = ImageChops.offset(mask, 0, rim_px)
            ring = ImageChops.subtract(mask, shifted)
        else:
            big = mask.filter(ImageFilter.MaxFilter(rim_px * 2 + 1))
            ring = ImageChops.subtract(big, mask)
        out.paste(rim + (255,), (0, 0), ring)  # rim stays solid even on dim ranks
    out.paste(body + (alpha,), (0, 0), mask)
    return out


def _fill_holes(mask):
    """Boolean mask with its interior holes filled (border flood-fill)."""
    # .copy() is required: floodfill silently no-ops on fromarray images
    # (their buffer is a read-only numpy view).
    img = Image.fromarray((mask * 255).astype(np.uint8), "L").copy()
    ImageDraw.floodfill(img, (0, 0), 128)
    return np.asarray(img) != 128  # bone + enclosed holes


def scale_int(img, factor):
    """Integer nearest-neighbour upscale — keeps every pixel crunchy."""
    if factor == 1:
        return img
    return img.resize((img.width * factor, img.height * factor), Image.NEAREST)


def paste(canvas, img, cx, cy):
    canvas.alpha_composite(img, (int(cx - img.width / 2), int(cy - img.height / 2)))


def in_keep_out(x, y, pad=6):
    l, t, r, b = KEEP_OUT
    return l - pad < x < r + pad and t - pad < y < b + pad


# --------------------------------------------------------------------------
# layers
# --------------------------------------------------------------------------

def build_sky(rng):
    """Abyss backdrop: violet-black ramp + faint descending light shafts."""
    arr = vgrad([(0, SKY_TOP), (HORIZON * 0.45, SKY_MID), (HORIZON, SKY_LOW)],
                h=HORIZON)
    img = to_rgba(arr)

    shafts = Image.new("RGBA", (W, HORIZON), (0, 0, 0, 0))
    d = ImageDraw.Draw(shafts)
    for _ in range(5):
        cx = int(rng.integers(40, W - 40))
        top_w = int(rng.integers(4, 14))
        bot_w = top_w + int(rng.integers(14, 40))
        d.polygon([(cx - top_w, 0), (cx + top_w, 0),
                   (cx + bot_w, HORIZON), (cx - bot_w, HORIZON)],
                  fill=(0x8a, 0x30, 0x48, int(rng.integers(6, 14))))
    shafts = shafts.filter(ImageFilter.GaussianBlur(6))
    img.alpha_composite(shafts)
    return img


def build_rifts(rng):
    """Jagged blood-red fissures tearing down from the top edge."""
    layer = Image.new("RGBA", (W, HORIZON), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(7):
        x = float(rng.integers(20, W - 20))
        y = 0.0
        depth = float(rng.integers(50, 150))
        pts = []
        while y < depth:
            pts.append((x, y))
            y += float(rng.integers(6, 16))
            x += float(rng.integers(-9, 10))
        if len(pts) < 2:
            continue
        width = int(rng.integers(1, 3))
        d.line(pts, fill=RIFT_EDGE + (170,), width=width + 2)
        d.line(pts, fill=RIFT_CORE + (int(rng.integers(110, 190)),), width=width)
    return layer.filter(ImageFilter.GaussianBlur(0.6))


def build_boss(factor=5, cy=26):
    """The abyss lord as a looming cut-out behind the title.

    skull_idle frame 0 is 52x54; scaled up and darkened so it reads as a
    background idol rather than a foreground sprite. A full red rim keeps the
    silhouette legible against the near-black sky; the eye sockets are cut out
    and re-lit so they burn through the title.
    """
    frame = load_frame("skull_idle.png", 52, 54, 0)
    big = scale_int(frame, factor)
    sil = silhouette(big, (0x3a, 0x20, 0x34), (0xc0, 0x30, 0x3a), rim_px=2, alpha=250)

    # Eye sockets: red pixels trapped *inside* the bone region (the cranium
    # outline is red too, so a plain colour test would light the whole skull).
    rgb = np.asarray(frame.convert("RGB")).astype(int)
    red = (rgb[..., 0] > 150) & (rgb[..., 1] < 110) & (rgb[..., 2] < 110)
    bone = (rgb[..., 0] > 200) & (rgb[..., 1] > 140)
    eyes_mask = red & _fill_holes(bone) & ~bone
    # Stay in mode L and putalpha — an L->RGBA convert would set alpha=255
    # everywhere and paste a full-frame white slab over the sky.
    eyes_l = scale_int(Image.fromarray((eyes_mask * 255).astype(np.uint8), "L"),
                       factor)
    glow_l = eyes_l.filter(ImageFilter.GaussianBlur(factor * 1.6)) \
                   .point(lambda v: min(200, int(v * 1.3)))
    glow = Image.new("RGBA", sil.size, (0xff, 0x30, 0x30, 0))
    glow.putalpha(glow_l)
    eyes = Image.new("RGBA", sil.size, (0xff, 0x48, 0x40, 0))
    eyes.putalpha(eyes_l)
    sil.alpha_composite(glow, (0, 0))
    sil.alpha_composite(eyes, (0, 0))

    # Bleed the lower third into the horizon fog so it never looks pasted on.
    fade = Image.new("L", sil.size, 0)
    fd = ImageDraw.Draw(fade)
    for y in range(sil.height):
        t = max(0.0, (y - sil.height * 0.62)) / (sil.height * 0.38)
        fd.line([(0, y), (sil.width, y)], fill=int(255 * min(1.0, t) ** 1.3))
    sil.putalpha(ImageChops.subtract(sil.split()[3], fade))
    return sil, W // 2, cy


def horizon_line(rng):
    """Jagged sky/floor seam: low-frequency walk + pixel steps, per column."""
    xs = np.arange(W)
    low = np.interp(xs, np.linspace(0, W, 9), rng.integers(-7, 8, 9))
    mid = np.interp(xs, np.linspace(0, W, 33), rng.integers(-3, 4, 33))
    y = HORIZON + np.round(low + mid)
    return np.clip(y, HORIZON - 12, HORIZON + 12).astype(int)


def build_floor(rng, seam):
    """Dark-arena dirt: 8px blocky value noise over the ground_map_0 palette.

    The top edge follows `seam` so the horizon is a torn line, not a ruler cut.
    """
    fh = H - HORIZON + 16  # extra headroom above HORIZON for the jagged seam
    # Blocky value noise with jittered cell borders — a plain grid of cells
    # reads as a checkerboard, so each row/column boundary wobbles ±3px.
    def octave(cell):
        gx, gy = W // cell + 2, fh // cell + 2
        g = rng.random((gy, gx))
        xs = np.clip((np.arange(W) + rng.integers(-3, 4, W)) // cell, 0, gx - 1)
        ys = np.clip((np.arange(fh) + rng.integers(-3, 4, fh)) // cell, 0, gy - 1)
        return g[np.ix_(ys, xs)]
    nv = octave(16) * 0.65 + octave(8) * 0.35

    lo = nv < 0.5
    t = np.where(lo, nv * 2.0, (nv - 0.5) * 2.0)[..., None]
    a = np.where(lo[..., None], np.array(FLOOR_DARK), np.array(FLOOR_BASE))
    b = np.where(lo[..., None], np.array(FLOOR_BASE), np.array(FLOOR_LIT))
    arr = a + (b - a) * t

    # Distance falloff: darker at the horizon, brighter where the player stands.
    arr *= np.linspace(0.62, 1.16, fh)[:, None, None]

    # Faint 32px tile grid, just enough to hint at the in-game ground.
    for gx in range(0, W, 32):
        arr[:, gx:gx + 1] *= 0.90
    for gy in range(0, fh, 32):
        arr[gy:gy + 1, :] *= 0.90

    img = to_rgba(np.clip(arr, 0, 255).astype(np.uint8))

    # A few long, shallow cracks — sparse, so the dirt stays readable.
    d = ImageDraw.Draw(img)
    for _ in range(6):
        x = float(rng.integers(20, W - 20))
        y = float(rng.integers(HORIZON + 24, H - 14))
        pts = [(x, y)]
        for _ in range(int(rng.integers(6, 12))):
            x += float(rng.integers(-14, 15))
            y += float(rng.integers(1, 5))
            pts.append((x, y))
        d.line(pts, fill=(0x16, 0x10, 0x12, int(rng.integers(50, 90))), width=1)

    # Cut everything above the seam so the sky shows through the tears.
    top = HORIZON - 16
    cut = Image.new("L", (W, fh), 255)
    cd = ImageDraw.Draw(cut)
    for x in range(W):
        cd.line([(x, 0), (x, seam[x] - top)], fill=0)
    img.putalpha(ImageChops.multiply(img.split()[3], cut))
    return img, top


def build_horizon_fog(seam):
    """Blood-lit haze hugging the torn seam, column by column."""
    top = HORIZON - 26
    bot = HORIZON + 18
    band_h = bot - top
    arr = np.zeros((band_h, W, 4), np.uint8)
    for x in range(W):
        peak = seam[x]
        for y in range(top, bot):
            t = max(0.0, 1.0 - abs(y - peak) / 14.0) ** 1.8
            arr[y - top, x, 0] = 0x8a
            arr[y - top, x, 1] = 0x20
            arr[y - top, x, 2] = 0x2c
            arr[y - top, x, 3] = int(120 * t)
    img = Image.fromarray(arr, "RGBA").filter(ImageFilter.GaussianBlur(1.8))
    return img, top


MONSTER_SPECS = [
    # (sheet, frame_w, frame_h)
    ("mushroom_idle.png", 32, 32),
    ("bluebird_fly.png", 32, 32),
    ("trunk_idle.png", 32, 32),
]


def build_tide(rng):
    """Three ranks of monster silhouettes surging toward the player.

    Positions are structured, not pure noise: each rank is a jittered row with
    a guaranteed minimum spacing so the horde reads as ranks closing in rather
    than scattered ink blots. Far rank: dense, small, dim. Near rank: big trunk
    brutes at the flanks. The centre stays open so the player is never covered.
    """
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ranks = [
        # (y, scale, alpha, rim, count, trunk bias, min gap)
        (266, 1, 165, SIL_RIM_FAR, 22, 0.15, 24),
        (294, 1, 205, (0x6a, 0x24, 0x30), 15, 0.35, 34),
        (332, 2, 250, SIL_RIM_NEAR, 8, 0.60, 74),
    ]
    for cy, factor, alpha, rim, count, trunk_bias, gap in ranks:
        slots = np.linspace(14, W - 14, count)
        for slot in slots:
            cx = int(slot + rng.integers(-gap // 3, gap // 3 + 1))
            yy = cy + int(rng.integers(-5, 6))
            r = rng.random()
            idx = 2 if r < trunk_bias else int(rng.integers(0, 2))
            if idx == 1:
                yy -= int(rng.integers(12, 30))  # flying imps hover
            if in_keep_out(cx, yy):
                continue
            if abs(cx - W // 2) < (100 if factor == 2 else 46):
                continue  # leave the player's stance clear
            sheet, fw, fh = MONSTER_SPECS[idx]
            frame = load_frame(sheet, fw, fh, int(rng.integers(0, 3)))
            sil = silhouette(scale_int(frame, factor), SIL_BODY, rim,
                             rim_px=1, alpha=alpha, top_rim=True)
            paste(layer, sil, cx, yy)
    return layer


def build_player(factor=2):
    """The lone survivor — the only fully-coloured sprite on the canvas."""
    frame = load_frame("char_paladin_idle.png", 32, 32, 0)
    spr = scale_int(frame, factor)

    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cx, cy = W // 2, 306

    # Warm light pool underfoot so the figure separates from the dirt.
    pool = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pool)
    pd.ellipse([cx - 46, cy + 14, cx + 46, cy + 40], fill=(0xff, 0xb0, 0x50, 46))
    pool = pool.filter(ImageFilter.GaussianBlur(9))
    layer.alpha_composite(pool)

    paste(layer, spr, cx, cy)
    return layer


def build_gems(rng):
    """XP gems glinting on the dirt around the player."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    frame = load_frame("gem.png", 32, 32, 0)
    gem = frame.resize((16, 16), Image.NEAREST)
    for _ in range(16):
        cx = int(rng.integers(24, W - 24))
        cy = int(rng.integers(300, H - 10))
        if abs(cx - W // 2) < 34 and cy < 336:
            continue  # don't clutter the player's feet
        glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse([cx - 11, cy - 11, cx + 11, cy + 11], fill=GEM_GLOW + (58,))
        layer.alpha_composite(glow.filter(ImageFilter.GaussianBlur(5)))
        paste(layer, gem, cx, cy)
    return layer


def build_motes(rng, count=90):
    """Drifting embers (below) and ash flecks (above)."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(count):
        below = rng.random() < 0.62
        x = int(rng.integers(0, W))
        y = int(rng.integers(HORIZON - 40, H)) if below else int(rng.integers(4, HORIZON - 30))
        if in_keep_out(x, y) and below:
            continue
        col = MOTE_WARM if rng.random() < 0.72 else MOTE_COOL
        a = int(rng.integers(40, 165))
        s = 1 if rng.random() < 0.78 else 2
        d.rectangle([x, y, x + s - 1, y + s - 1], fill=col + (a,))
    return layer


def bake_title(text, size=48, tracking=5):
    """Pixel-hard title art: gold ramp, dark outline, warm outer glow."""
    font_path = next((p for p in FONT_CANDIDATES if os.path.exists(p)), None)
    if font_path is None:
        print("WARN: no CJK font found, skipping title", flush=True)
        return None
    font = ImageFont.truetype(font_path, size)

    probe = ImageDraw.Draw(Image.new("L", (8, 8)))
    widths = [probe.textlength(c, font=font) for c in text]
    asc, desc = font.getmetrics()
    pad = size  # room for outline + glow
    tw = int(sum(widths) + tracking * (len(text) - 1)) + pad * 2
    th = asc + desc + pad * 2

    mask = Image.new("L", (tw, th), 0)
    d = ImageDraw.Draw(mask)
    x = float(pad)
    for c, cw in zip(text, widths):
        d.text((x, pad - asc * 0.12), c, font=font, fill=255)
        x += cw + tracking
    # Snap anti-aliasing to hard edges so the glyphs sit with the pixel art.
    mask = mask.point(lambda v: 255 if v > 105 else 0)

    layer = Image.new("RGBA", (tw, th), (0, 0, 0, 0))

    glow_mask = mask.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.GaussianBlur(5))
    layer.paste(TITLE_GLOW + (255,), (0, 0), glow_mask.point(lambda v: int(v * 0.5)))

    outline = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(7)), mask)
    layer.paste(TITLE_OUTLINE + (255,), (0, 0), outline)

    ramp = vgrad([(pad * 0.6, TITLE_HI), (pad + size * 0.55, TITLE_MID),
                  (pad + size * 1.15, TITLE_LO)], h=th, w=tw)
    layer.paste(to_rgba(ramp), (0, 0), mask)

    return layer


def build_vignette():
    """Radial corner darkening to push the eye to the centre."""
    yy, xx = np.mgrid[0:H, 0:W]
    dx = (xx - W / 2) / (W / 2)
    dy = (yy - H / 2) / (H / 2)
    d = np.sqrt(dx * dx * 0.82 + dy * dy * 1.25)
    a = np.clip((d - 0.52) / 0.62, 0, 1) ** 1.5 * 190
    arr = np.zeros((H, W, 4), np.uint8)
    arr[..., 0] = 0x05
    arr[..., 1] = 0x02
    arr[..., 2] = 0x06
    arr[..., 3] = a.astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


# --------------------------------------------------------------------------

def render(seed, title_size, with_title=False, with_boss=False, with_player=False):
    rng = np.random.default_rng(seed)
    canvas = Image.new("RGBA", (W, H), SKY_TOP + (255,))

    canvas.alpha_composite(build_sky(rng), (0, 0))

    if with_boss:
        boss, bx, by = build_boss()
        paste(canvas, boss, bx, by)

    canvas.alpha_composite(build_rifts(rng), (0, 0))

    seam = horizon_line(rng)
    floor, floor_top = build_floor(rng, seam)
    canvas.alpha_composite(floor, (0, floor_top))

    fog, fy = build_horizon_fog(seam)
    canvas.alpha_composite(fog, (0, fy))

    canvas.alpha_composite(build_tide(rng), (0, 0))
    canvas.alpha_composite(build_gems(rng), (0, 0))
    if with_player:
        canvas.alpha_composite(build_player(), (0, 0))
    canvas.alpha_composite(build_motes(rng), (0, 0))

    if with_title:
        title = bake_title("深渊幸存者", size=title_size)
        if title is not None:
            paste(canvas, title, W // 2, 63)

    canvas.alpha_composite(build_vignette(), (0, 0))
    return canvas


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--title-size", type=int, default=48)
    ap.add_argument("--title", action="store_true",
                    help="bake the gold title in (hud.gd draws it at runtime by default)")
    ap.add_argument("--boss", action="store_true",
                    help="draw the boss skull silhouette behind the title")
    ap.add_argument("--player", action="store_true",
                    help="draw the lone full-colour player figure")
    args = ap.parse_args()

    img = render(args.seed, args.title_size, with_title=args.title,
                 with_boss=args.boss, with_player=args.player)

    os.makedirs(os.path.dirname(OUT_GAME), exist_ok=True)
    img.convert("RGB").save(OUT_GAME)
    img.resize((W * 2, H * 2), Image.NEAREST).convert("RGB").save(OUT_PREVIEW)
    print("wrote %s (%dx%d)" % (OUT_GAME, W, H))
    print("wrote %s (%dx%d)" % (OUT_PREVIEW, W * 2, H * 2))


if __name__ == "__main__":
    main()
