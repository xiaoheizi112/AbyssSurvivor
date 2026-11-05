# -*- coding: utf-8 -*-
"""角色精灵像素全录生成器(除只因信徒外的四个基础角色)。

把 resource/pixel32/char_<id>_<anim>.png 的**每一个像素**落成文字:
  - 帧清单: 逐帧像素级去重, 给出 唯一姿势↔帧号 映射(≡ 表示完全相同)
  - 站姿逐色像素索引: 每种颜色的全部游程, 按行列出
  - 每个唯一姿势的逐行游程 RLE: `y行: [x0-x1]#HEX ...` (含两端)

产出: docs/角色精灵像素全录.md
用法: python map_preview/dump_char_pixels.py
"""
import os
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIX = os.path.join(ROOT, "resource", "pixel32")
OUT = os.path.join(ROOT, "docs", "角色精灵像素全录.md")
CHARS = ("apprentice", "paladin", "priest", "assassin")
NAMES = {"apprentice": "蓝帽小子", "paladin": "粉红壮汉",
         "priest": "忍者蛙", "assassin": "面具客"}
ANIMS = ("idle", "run", "hit")


def hx(p):
    return "#%02X%02X%02X" % p[:3]


def frame_rle(frame):
    px = frame.load()
    lines = []
    for y in range(frame.height):
        segs = []
        for x in range(frame.width):
            p = px[x, y]
            if p[3] == 0:
                continue
            if segs and segs[-1][2] == p[:3]:
                segs[-1][1] = x
            else:
                segs.append([x, x, p[:3]])
        if segs:
            lines.append("y%02d: %s" % (y, " ".join(
                "[%d-%d]%s" % (a, b, hx(c)) for a, b, c in segs)))
    return lines


def color_index(frame):
    """色 -> (像素数, [(y, [(x0,x1),...]), ...])"""
    px = frame.load()
    runs = {}
    counts = Counter()
    for y in range(frame.height):
        for x in range(frame.width):
            p = px[x, y]
            if p[3] == 0:
                continue
            c = p[:3]
            counts[c] += 1
            rows = runs.setdefault(c, [])
            if rows and rows[-1][0] == y and rows[-1][1][-1][1] == x - 1:
                rows[-1][1][-1] = (rows[-1][1][-1][0], x)
            elif rows and rows[-1][0] == y:
                rows[-1][1].append((x, x))
            else:
                rows.append((y, [(x, x)]))
    return runs, counts


def fmt_index(runs, counts):
    out = []
    for c, n in counts.most_common():
        toks = []
        for y, xr in runs[c]:
            toks.append("y%02d:%s" % (y, ",".join(
                "%d" % a if a == b else "%d-%d" % (a, b) for a, b in xr)))
        out.append("- `%s` ×%d px: %s" % (hx(c), n, " ".join(toks)))
    return out


def dedupe(frames):
    """返回 (唯一帧列表, 每帧对应的唯一索引)"""
    uniq, keys, mapping = [], [], []
    for f in frames:
        k = f.tobytes()
        if k in keys:
            mapping.append(keys.index(k))
        else:
            keys.append(k)
            uniq.append(f)
            mapping.append(len(uniq) - 1)
    return uniq, mapping


def fmt_mapping(mapping):
    groups = {}
    for fi, ui in enumerate(mapping):
        groups.setdefault(ui, []).append(fi)
    return ", ".join("P%d=f%d" % (ui, g[0]) if len(g) == 1
                     else "P%d=f%d≡f%d" % (ui, g[0], g[-1]) if len(g) == 2
                     else "P%d=f%d≡…≡f%d" % (ui, g[0], g[-1])
                     for ui, g in sorted(groups.items()))


def main():
    doc = ["# 角色精灵像素全录(四个基础角色)",
           "",
           "> 由 `map_preview/dump_char_pixels.py` 自 `resource/pixel32/char_*.png` 逐像素导出,",
           "> 是《角色精灵像素规范》的像素级地面真相附录:规范讲风格与特征,本文件录全部像素。",
           "> 读法:`[x0-x1]#HEX` = 该行 x0..x1(含两端)连续同色像素;索引行 `y行:x0-x1,x2` 同理。",
           "> `fA≡fB` = 两帧像素完全相同(持帧)。hit 的 P0 为纯白剪影闪帧。",
           ""]
    for cid in CHARS:
        doc.append("---")
        doc.append("")
        doc.append("## %s %s" % (cid, NAMES[cid]))
        doc.append("")
        frames = {}
        for anim in ANIMS:
            img = Image.open(os.path.join(
                PIX, "char_%s_%s.png" % (cid, anim))).convert("RGBA")
            frames[anim] = [img.crop((i * 32, 0, i * 32 + 32, 32))
                            for i in range(img.width // 32)]
        doc.append("### 帧清单(像素级去重)")
        doc.append("")
        uniq_all = {}
        for anim in ANIMS:
            uniq, mapping = dedupe(frames[anim])
            uniq_all[anim] = uniq
            doc.append("- %s:%d 帧 → %d 唯一姿势:%s" % (
                anim, len(frames[anim]), len(uniq), fmt_mapping(mapping)))
        doc.append("")
        doc.append("### 站姿逐色像素索引(idle P0)")
        doc.append("")
        runs, counts = color_index(frames["idle"][0])
        doc.extend(fmt_index(runs, counts))
        doc.append("")
        for anim in ANIMS:
            for pi, f in enumerate(uniq_all[anim]):
                doc.append("### %s P%d" % (anim, pi))
                doc.append("")
                doc.append("```")
                doc.extend(frame_rle(f))
                doc.append("```")
                doc.append("")
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write("\n".join(doc) + "\n")
    print("written", OUT, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    main()
