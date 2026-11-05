# -*- coding: utf-8 -*-
"""
Procedural 2D pixel map — v7 refined (ground-only).

Per-style pipeline (ground PNG):
  0 "dark_arena"   — Brotato-like dark-earth enclosed arena.
  1 "green_meadow" — fresh forest-grass meadow (strong contrast to dark earth).

Refinements over v6 (all baked offline into the PNG, zero runtime cost):
  - Light/shadow color patches (low-freq value-noise field) — the floor reads as
    large soil/grass patches, not flat noise.
  - Vignette (radial edge darkening) — focus the center, subtly frame the arena.
  - Wall brick bevel: inner highlight + inner shadow + mortar ticks on the wall.
  - Clustered edge litter (pebbles / grass tufts + flowers) instead of uniform
    speckle; center stays empty for kiting.
  - Obscure the player spawn with a very faint radial glow (helps eyes land).

Obstacle system removed 2026-09-08: no boulder/crate sprites, no layout JSON.
"""

import os
import random
import math

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.abspath(os.path.join(HERE, "..", "assets", "maps"))

W, H = 800, 450           # = GameManager.BOUND
WALL = 10                 # border wall thickness px
PLAYER_SPAWN = (W // 2, H // 2)

# Bayer 4x4 for ordered dither
BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

# ---------- style palettes ----------
STYLES = {
    0: {  # 暗土竞技场 (Brotato-like)
        "seed": 7,
        "FLOOR_BASE": (58, 54, 50),
        "FLOOR_LT": (74, 69, 62),
        "FLOOR_DK": (44, 40, 38),
        "WALL_BASE": (98, 91, 82),
        "WALL_LT": (118, 111, 100),
        "WALL_DK": (78, 72, 64),
        "litter": "pebble",
        "patch_amp": 0.10,     # 色块明暗幅度
        "vignette": 0.17,      # 暗角强度
    },
    1: {  # 清新草地森林
        "seed": 31,
        "FLOOR_BASE": (96, 152, 76),
        "FLOOR_LT": (118, 176, 92),
        "FLOOR_DK": (68, 118, 54),
        "WALL_BASE": (104, 76, 52),
        "WALL_LT": (138, 104, 72),
        "WALL_DK": (70, 52, 36),
        "litter": "wildflower",
        "patch_amp": 0.12,
        "vignette": 0.15,
    },
}


def _clamp_col(c):
    return tuple(int(max(0, min(255, v))) for v in c)


def _mul_col(c, k):
    return _clamp_col((c[0] * k, c[1] * k, c[2] * k))


# ---------- low-freq color patch field (large soft light/shadow patches) ----------
def _patch_field(seed, cell):
    # 低分辨率随机灰度 + 双线性放大 => 平滑大斑块(0..1)
    rng = random.Random(seed)
    gw = max(2, W // cell)
    gh = max(2, H // cell)
    low = Image.new("L", (gw, gh))
    lp = low.load()
    for y in range(gh):
        for x in range(gw):
            lp[x, y] = rng.randrange(60, 196)
    big = low.resize((W, H), Image.BILINEAR)
    return big


def build_floor(st: dict):
    fb = st["FLOOR_BASE"]; fl = st["FLOOR_LT"]; fk = st["FLOOR_DK"]
    wb = st["WALL_BASE"]; wl = st["WALL_LT"]; wk = st["WALL_DK"]
    amp = st["patch_amp"]
    patch = _patch_field(st["seed"] * 3 + 2, cell=32)
    pl = patch.load()

    img = Image.new("RGB", (W, H), fb)
    px = img.load()

    cx, cy = W / 2.0, H / 2.0
    maxd = math.hypot(cx, cy)

    # 1) 地板: 大斑块调制 fb↔fl/fk + 高频 Bayer 抖动(细颗粒质感)
    for y in range(WALL, H - WALL):
        for x in range(WALL, W - WALL):
            v = pl[x, y] / 255.0                      # 0..1 patch 亮度
            k = 1.0 + (v - 0.5) * 2.0 * amp           # 1±amp 明暗调制
            col = _mul_col(fb, k)
            th = BAYER4[(y // 4) % 4][(x // 4) % 4]
            j = (th - 7.5) * 0.016                    # 高频细抖动
            col = _mul_col(col, 1.0 + j)
            px[x, y] = col

    # 2) 墙体: 内高光 + 内阴影(bevel 导角) + 顶/左亮 底/右暗
    for y in range(H):
        for x in range(W):
            is_wall = x < WALL or x >= W - WALL or y < WALL or y >= H - WALL
            if not is_wall:
                continue
            if x < WALL or y < WALL:
                base = wl
            elif x >= W - WALL or y >= H - WALL:
                base = wk
            else:
                base = wb
            # 墙内侧导角: 贴着地板的墙内缘做一圈暗影 + 一线高光
            if WALL <= x < W - WALL and y == WALL:
                base = wk            # 底部墙内缘(暗)
            if WALL <= x < W - WALL and y < W - WALL and y == WALL - 1:
                continue
            px[x, y] = base

    # 墙内缘高光/阴影线(地板与墙交界)
    for x in range(WALL, W - WALL):
        _put(px, x, WALL, wl)            # 顶缘高光
        _put(px, x, H - WALL - 1, wk)    # 底缘阴影
    for y in range(WALL, H - WALL):
        _put(px, WALL, y, wl)            # 左缘高光
        _put(px, W - WALL - 1, y, wk)    # 右缘阴影

    # 墙砖缝(mortar): 沿墙每 6px 一条深色短横缝, 增加砖砌质感
    for y in range(3, H - 3, 6):
        for x in range(0, WALL - 1):
            px[x, y] = _mul_col(px[x, y], 0.82)      # 左墙
            px[W - 1 - x, y] = _mul_col(px[W - 1 - x, y], 0.82)  # 右墙
    for x in range(3, W - 3, 6):
        for y in range(0, WALL - 1):
            px[x, y] = _mul_col(px[x, y], 0.82)      # 顶墙
            px[x, H - 1 - y] = _mul_col(px[x, H - 1 - y], 0.82)  # 底墙

    # 3) 边缘杂物簇(碎石 / 草丛花簇), 中心留空
    _litter(px, st["litter"], st["seed"] * 9)

    # 4) 暗角 vignette + 中心出生点淡亮
    for y in range(H):
        for x in range(W):
            # vignette: 中心亮, 边缘暗(平方曲线, 中间保持干净)
            d = math.hypot(x - cx, y - cy) / maxd
            vig = 1.0 - st["vignette"] * (d ** 2.2)
            # 中心出生点淡亮(极轻, 辅助视线)
            sp = math.hypot(x - PLAYER_SPAWN[0], y - PLAYER_SPAWN[1])
            if sp < 90.0:
                vig += 0.06 * (1.0 - sp / 90.0)
            if vig != 1.0:
                # 用 Bayer 阈值量化暗化量, 避免色带
                th = BAYER4[(y // 4) % 4][(x // 4) % 4]
                vig_q = 1.0 - (1.0 - vig) * (0.75 + 0.5 * th / 15.0)
                px[x, y] = _mul_col(px[x, y], max(0.0, vig_q))
    return img


def _litter(px, kind, seed):
    rng = random.Random(seed)
    n_clusters = 70
    for _ in range(n_clusters):
        x = rng.randrange(WALL + 8, W - WALL - 8)
        y = rng.randrange(WALL + 8, H - WALL - 8)
        # 边缘偏置: 靠近中心则大概率丢弃, 保中心空
        dx = (x - W / 2) / (W / 2)
        dy = (y - H / 2) / (H / 2)
        if dx * dx + dy * dy < 0.20:
            if rng.random() < 0.85:
                continue
        # 每簇 3~6 个散点
        n = rng.randrange(3, 7)
        for _ in range(n):
            ox = x + rng.randrange(-3, 4)
            oy = y + rng.randrange(-3, 4)
            if kind == "wildflower":
                if rng.random() < 0.22:
                    _put(px, ox, oy, (255, 238, 118) if rng.random() < 0.5 else (250, 250, 250))
                else:
                    _put(px, ox, oy, (58, 104, 46))     # 深草
                    _put(px, ox + 1, oy, (64, 112, 50))
            else:  # pebble
                _put(px, ox, oy, (40, 37, 35) if rng.random() < 0.5 else (82, 76, 68))


def _put(px, x, y, col):
    if 0 <= x < W and 0 <= y < H:
        px[x, y] = col


def main():
    for sid, st in STYLES.items():
        floor = build_floor(st)
        floor.save(os.path.join(ASSETS, "ground_map_%d.png" % sid))
        floor.copy().resize((W * 2, H * 2), Image.NEAREST).save(
            os.path.join(HERE, "map_%02d.png" % (sid + 1)))
        print("style %d: ground baked" % sid)


if __name__ == "__main__":
    main()