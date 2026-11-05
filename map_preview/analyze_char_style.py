# -*- coding: utf-8 -*-
"""角色精灵像素级风格分析器(新角色 AI 生成后的验收/参照工具)。

对 resource/pixel32/char_<id>_<anim>.png 逐帧输出:
  - 非透明像素包围盒(每帧 + 全表)
  - 全表调色板(hex + 像素计数)
  - idle 第 0 帧的逐行游程编码(RLE): 每行若干段 [x0-x1] #hex
  - 动画帧差: 相对 idle f0 的变化像素数 + 变化区包围盒
  - hit 白闪帧的调色板

用法: python map_preview/analyze_char_style.py [char_id ...]
      不带参数 = 分析除 xiaoheizi 外的四个基础角色
"""
import os
import sys
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIX = os.path.join(ROOT, "resource", "pixel32")
ANIMS = ("idle", "run", "hit")
DEFAULT = ("apprentice", "paladin", "priest", "assassin")


def hx(p):
    return "#%02X%02X%02X" % p[:3]


def bbox(img, ox=0):
    px = img.load()
    xs, ys = [], []
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3] > 0:
                xs.append(x + ox)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))


def row_rle(img):
    """逐行游程: [(y, [(x0, x1, hex), ...]), ...] 只含有像素的行。"""
    px = img.load()
    out = []
    for y in range(img.height):
        segs = []
        for x in range(img.width):
            p = px[x, y]
            if p[3] == 0:
                continue
            if segs and segs[-1][2] == p[:3]:
                segs[-1][1] = x
            else:
                segs.append([x, x, p[:3]])
        if segs:
            out.append((y, [(a, b, hx(c)) for a, b, c in segs]))
    return out


def diff(f0, f1):
    a, b = f0.load(), f1.load()
    n, xs, ys = 0, [], []
    for y in range(32):
        for x in range(32):
            if a[x, y] != b[x, y]:
                n += 1
                xs.append(x)
                ys.append(y)
    if not n:
        return 0, None
    return n, (min(xs), min(ys), max(xs), max(ys))


def main():
    chars = sys.argv[1:] or list(DEFAULT)
    for cid in chars:
        print("=" * 72)
        print("CHAR:", cid)
        frames = {}
        pal = Counter()
        for anim in ANIMS:
            path = os.path.join(PIX, "char_%s_%s.png" % (cid, anim))
            img = Image.open(path).convert("RGBA")
            nf = img.width // 32
            frames[anim] = [img.crop((i * 32, 0, i * 32 + 32, 32)) for i in range(nf)]
            for f in frames[anim]:
                for p in f.getdata():
                    if p[3] > 0:
                        pal[p[:3]] += 1
            bbs = [bbox(f) for f in frames[anim]]
            print("  %-5s frames=%d  sheet=%dx%d" % (anim, nf, img.width, img.height))
            for i, bb in enumerate(bbs):
                print("      f%d bbox x[%d..%d] y[%d..%d]  (w%d h%d)" % (
                    i, bb[0], bb[2], bb[1], bb[3], bb[2] - bb[0] + 1, bb[3] - bb[1] + 1))
        print("  palette (%d colors):" % len(pal))
        for col, n in pal.most_common(24):
            print("      %s rgb%-15s x%d" % (hx(col), str(col), n))
        print("  idle f0 row RLE (y: [x0-x1]#hex ...):")
        for y, segs in row_rle(frames["idle"][0]):
            print("      y%02d: %s" % (y, " ".join(
                "[%d-%d]%s" % (a, b, c) for a, b, c in segs)))
        print("  frame diffs vs idle f0:")
        for anim in ANIMS:
            for i, f in enumerate(frames[anim]):
                if anim == "idle" and i == 0:
                    continue
                n, bb = diff(frames["idle"][0], f)
                print("      %-5s f%d: %3d px changed%s" % (
                    anim, i, n,
                    ("  bbox x[%d..%d] y[%d..%d]" % (bb[0], bb[2], bb[1], bb[3])) if bb else ""))
    print("=" * 72)


if __name__ == "__main__":
    main()
