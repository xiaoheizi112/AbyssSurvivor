# -*- coding: utf-8 -*-
"""烘焙图鉴(图书馆古籍风)三张贴图, 运行时零生成成本。

产物:
  assets/ui/codex_desk.png   640x360  暖棕木桌 + 中心烛光 + 四角暗角
  assets/ui/codex_page.png   196x262  做旧米黄纸页(低频噪点 + 颗粒 + 霉斑 + 纤维 + 边缘暗角)
  assets/ui/codex_spine.png   10x262  书脊(中缝 + 渐变暗带 + 缝线)
  map_preview/codex_*_2x.png          2x NEAREST 预览(目检用, 游戏不加载)

用法:  python map_preview/generate_codex_bg.py --seed 7
改完必须回 Godot 跑 --import, 否则 ResourceLoader.exists 为假走平色回退。
"""
import argparse
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
UI_DIR = os.path.join(ROOT, "assets", "ui")


def to_rgba(arr: np.ndarray) -> Image.Image:
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def save(img: Image.Image, name: str, preview: bool = True) -> None:
    os.makedirs(UI_DIR, exist_ok=True)
    path = os.path.join(UI_DIR, name)
    img.save(path)
    print("[bake] %s (%dx%d)" % (path, img.width, img.height))
    if preview:
        big = img.resize((img.width * 2, img.height * 2), Image.NEAREST)
        ppath = os.path.join(HERE, name.replace(".png", "_2x.png"))
        big.save(ppath)
        print("[bake] preview %s" % ppath)


# ---------------- 木桌 ----------------

def build_desk(rng: np.random.Generator, w: int = 640, h: int = 360) -> Image.Image:
    base = np.array([36, 26, 18], dtype=np.float64)  # #241A12
    img = np.zeros((h, w, 3), dtype=np.float64)

    yy = np.arange(h, dtype=np.float64)[:, None]
    xx = np.arange(w, dtype=np.float64)[None, :]

    # 水平木纹: 沿 y 的低频 sin + 随机相位扰动(木板横向铺)
    grain = np.sin(yy * 0.8 + np.sin(xx * 0.013 + yy * 0.05) * 2.0) * 6.0
    grain += rng.normal(0, 2.2, (h, 1)) * np.ones((1, w))
    img[:] = base
    img += grain[..., None] * np.array([1.0, 0.82, 0.6])

    # 板缝: 每隔 40-60px 一条 1px 暗线 + 1px 高光线(模拟拼板)
    y = rng.integers(30, 50)
    while y < h:
        img[y, :] *= 0.55
        if y + 1 < h:
            img[y + 1, :] += np.array([7, 5, 3])
        y += int(rng.integers(40, 61))

    # 木节: 几个椭圆暗斑, 低频即可
    for _ in range(5):
        cx0, cy0 = rng.integers(40, w - 40), rng.integers(30, h - 30)
        rx, ry = rng.integers(6, 14), rng.integers(3, 7)
        gx, gy = np.meshgrid(np.arange(w), np.arange(h))
        m = ((gx - cx0) / rx) ** 2 + ((gy - cy0) / ry) ** 2 < 1.0
        img[m] *= 0.78

    # 中心烛光: 暖黄 radial, 书本位置(右侧偏中)最亮
    gx, gy = np.meshgrid(np.arange(w), np.arange(h))
    lx, ly = w * 0.56, h * 0.42
    d = np.sqrt(((gx - lx) / (w * 0.62)) ** 2 + ((gy - ly) / (h * 0.72)) ** 2)
    glow = np.clip(1.0 - d, 0, 1) ** 1.6
    img += glow[..., None] * np.array([0.45, 0.32, 0.18]) * 96.0

    # 四角暗角
    vign = np.clip(np.maximum(np.abs(gx - w / 2) / (w / 2), np.abs(gy - h / 2) / (h / 2)), 0, 1)
    img *= (1.0 - 0.42 * vign[..., None] ** 1.8)

    rgba = np.dstack([img, np.full((h, w), 255.0)])
    return to_rgba(rgba)


# ---------------- 纸页 ----------------

def build_page(rng: np.random.Generator, w: int = 196, h: int = 262) -> Image.Image:
    base = np.array([232, 220, 192], dtype=np.float64)  # #E8DCC0
    img = np.zeros((h, w, 3), dtype=np.float64)
    img[:] = base

    gx, gy = np.meshgrid(np.arange(w), np.arange(h))

    # 低频噪点: 小图随机灰度 bicubic 放大, 振幅 ±8
    small = rng.normal(0, 8, (h // 16 + 2, w // 16 + 2))
    low = np.array(Image.fromarray(np.clip(small + 128, 0, 255).astype(np.uint8), "L")
                   .resize((w, h), Image.BICUBIC), dtype=np.float64) - 128.0
    img += low[..., None]

    # 高频颗粒: 逐像素 ±4
    img += rng.normal(0, 4, (h, w))[..., None]

    # 霉斑: ~35 个 r=1-3px 褐斑
    for _ in range(35):
        cx0, cy0 = rng.integers(2, w - 2), rng.integers(2, h - 2)
        r = float(rng.integers(1, 4))
        m = ((gx - cx0) ** 2 + (gy - cy0) ** 2) < r * r
        img[m] = img[m] * (1.0 - 0.14) + np.array([176, 144, 96]) * 0.14

    # 纤维: ~60 条 3-8px 近水平暗线
    for _ in range(60):
        fx, fy = rng.integers(0, w - 8), rng.integers(0, h)
        ln = int(rng.integers(3, 9))
        ln = min(ln, w - fx)
        img[fy, fx:fx + ln] *= 0.94

    # 边缘暗角: 四周向内 18px 渐暗; 左右两条短边(书脊侧/翻页侧)对称加强出沟槽
    dl = gx.astype(np.float64)
    dr = (w - 1 - gx).astype(np.float64)
    dt = gy.astype(np.float64)
    db = (h - 1 - gy).astype(np.float64)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt, db))
    fade = np.clip(d / 18.0, 0, 1)
    img *= (0.84 + 0.16 * fade)[..., None]
    side = np.clip(np.minimum(dl, dr) / 5.0, 0, 1)
    img *= (0.93 + 0.07 * side)[..., None]

    rgba = np.dstack([img, np.full((h, w), 255.0)])
    return to_rgba(rgba)


# ---------------- 书脊 ----------------

def build_spine(rng: np.random.Generator, w: int = 10, h: int = 262) -> Image.Image:
    img = np.zeros((h, w, 3), dtype=np.float64)
    gx = np.arange(w, dtype=np.float64)[None, :]

    # 两侧 5px 渐变暗带 + 中间 2px 深缝 #3A2C18
    leather = np.array([58, 42, 28], dtype=np.float64)
    img[:] = leather
    center = (w - 1) / 2.0
    dc = np.abs(gx - center)
    img *= (0.62 + 0.38 * np.clip(dc / (w / 2.0), 0, 1))[..., None]
    seam = (dc < 1.0)[0]
    img[:, seam] = np.array([34, 26, 15], dtype=np.float64)

    # 缝线: 每隔 24px 一段 6px 亮线 #8A6A3A(压在缝上, 模拟装订)
    y = 8
    while y + 6 <= h:
        img[y:y + 6, seam] = np.array([138, 106, 58], dtype=np.float64)
        y += 24

    # 轻微纵向噪声
    img += rng.normal(0, 3, (h, w))[..., None]

    rgba = np.dstack([img, np.full((h, w), 255.0)])
    return to_rgba(rgba)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    save(build_desk(np.random.default_rng(args.seed)), "codex_desk.png")
    save(build_page(np.random.default_rng(args.seed + 1)), "codex_page.png")
    save(build_spine(np.random.default_rng(args.seed + 2)), "codex_spine.png", preview=False)


if __name__ == "__main__":
    main()
