# -*- coding: utf-8 -*-
"""只因信徒 · 高清原型降采样版精灵生成器(2026-09-08 二版,加动画对齐旧角色基线)。

输入(用户投放的高清原型,RGB 带烘焙棋盘透明底 + 脚下浅灰阴影):
  resource/xiaoheizi1.png     2048x2048 立绘(正面站姿)
  resource/xioaheizi_run.png  4096x1024 跑步 4 帧横排(注意文件名是 xioa 不是 xiao,用户原样)

一版(2026-09-07)只做了降采样贴帧,实测问题:
  - idle 4 帧全同 → 游戏里是静止纸片人(旧角色 idle 是 11 帧呼吸);
  - run 4 帧帧间 alpha 差仅 12px(旧角色 ~100px)→ 跑步像平移;
  - 内容高 24px,旧角色基线 26px(y6-31)→ 比别的角色小一圈;
  - 脚本引用了未定义的 CONTENT_H_MAX,直接跑必 NameError(磁盘上的表是更早版本产的)。

二版管线:
  1. 去背景 + 去脚下阴影: 一次 BFS, 通行 = 背景色或低饱和浅灰阶(阴影环),
     灰环带路把近白内芯一起吃净(行带 mask 会留内芯 = 走路帧脚底白斑,
     或误删下摆浅灰饰边); 开运算杀噪点;
  2. 共享调色板(中位切分, 上限 24 色)保证三表同色;
  3. **按表归一高度**: 立绘与跑步源的艺术比例不同(跑姿前倾跨步, 包围盒矮而宽),
     共用一个缩放比会把 run 压成半截 —— 站姿内容高 CONTENT_H=26(旧角色基线
     y6-31), 跑姿 CONTENT_H_RUN=24(跑步微蹲), 宽各随原比例; 量化挪到降采样
     **之后**, 边缘像素贴最近调色板色, 不出灰边;
  4. 动画:
     - idle 10 帧 = 两姿态(高 26 / 压 1px 到高 25)按 [0×3,1×4,0×3] 持帧呼吸, 8fps 约 1.25s 一轮;
     - run 12 帧 = 源 4 姿态各持 3 帧(12fps 一轮 1s, 与旧角色步频一致),
       并加步幅 bob: 并腿过渡姿(1/3)整体上提 1px, 跨步姿(0/2)落脚 y31 —— 跑步循环的
       高低起伏, 帧间差从 12px 提到 ~40px;
     - hit 7 帧 = 2 帧白闪 + 站姿微弹(与旧角色 hit 结构一致, 不改);
  5. 脚底一律贴 y=31, 水平居中, 换角色不跳位。

产出:
  resource/pixel32/char_xiaoheizi_{idle,run,hit}.png   (10/12/7 帧)
  map_preview/xiaoheizi_template_sheets_8x.png         三表 8x 预览(行宽 12 帧)
  map_preview/xiaoheizi_template_compare.png           新版 vs 旧手绘版逐帧对比

用法: python map_preview/generate_xiaoheizi_template.py
改完必须跑 --import 重建 .import 缓存, 否则游戏里 texture_for 静默回退旧图。
"""
import os
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_PORTRAIT = os.path.join(ROOT, "resource", "xiaoheizi1.png")
SRC_RUN = os.path.join(ROOT, "resource", "xioaheizi_run.png")
OUT = os.path.join(ROOT, "resource", "pixel32")
PREVIEW = os.path.join(ROOT, "map_preview")

FRAME_W = 32          # 帧格宽(项目约定 32x32, scale=1)
CONTENT_H = 26        # 站姿内容高(旧角色基线 y6-31 = 26px)
CONTENT_H_RUN = 24    # 跑姿内容高(前倾跨步微蹲, 比站姿矮 2px)
CONTENT_H_MAX = 30    # 高上限兜底, 避免趴姿把格子撑爆
FOOT_Y = 31           # 脚底行
MAX_PAL = 24          # 共享调色板上限
RUN_BOB = 1           # 跑步并腿过渡姿上提像素

# 持帧序列: idle 呼吸 10 帧 / run 4 姿态各持 3 帧 = 12 帧(步频对齐旧角色 12 帧表)
IDLE_SEQ = [0, 0, 0, 1, 1, 1, 1, 0, 0, 0]
RUN_SEQ = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3]

BG_TOL = 25           # flood fill 背景容差(棋盘白 255 / 灰 ~243 + 噪声点; 角色有黑描边
                      # 包围, 白发高光在描边内, 容差再大也吃不到角色)


# ---------- 去背景 ----------

def _flood(rgb: np.ndarray, allowed: np.ndarray) -> np.ndarray:
    """从四边 BFS 穿过 allowed mask, 返回到达区(True=背景/可达)。连通域内颜色渐变也吃得动。"""
    h, w = rgb.shape[:2]
    reached = np.zeros((h, w), dtype=bool)
    seeds = ([(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)]
             + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)])
    q = deque()
    for y, x in seeds:
        if allowed[y, x] and not reached[y, x]:
            reached[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and allowed[ny, nx] and not reached[ny, nx]:
                reached[ny, nx] = True
                q.append((ny, nx))
    return reached


def _open3(mask: np.ndarray) -> np.ndarray:
    """3x3 二值开运算: 杀孤立噪点(棋盘噪声残留), 实体边缘(>=8px 厚)不受影响。"""
    def erode(m):
        out = m.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                out &= np.roll(np.roll(m, dy, 0), dx, 1)
        return out
    def dilate(m):
        out = m.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                out |= np.roll(np.roll(m, dy, 0), dx, 1)
        return out
    return dilate(erode(mask))


def cutout(path: str) -> np.ndarray:
    """RGB 图 -> RGBA, 背景与脚下阴影 alpha=0。

    一次 BFS 同时吃背景与阴影: 通行条件 = 背景色(棋盘白/灰)或低饱和浅灰阶
    (阴影环)。阴影椭圆是"灰环包近白内芯", 旧版行带 mask 两难 —— 窗口放宽到
    近白会连下摆浅灰饰边一起删, 卡 235 又留下内芯(走路帧脚底白斑); 让 BFS
    沿灰环绕进去, 环与芯一次吃净。角色白发/饰边都在黑描边包围内, BFS 进不去,
    不误删。
    """
    rgb = np.array(Image.open(path).convert("RGB"))
    lum = rgb.astype(int).mean(axis=2)
    sat = rgb.max(axis=2).astype(int) - rgb.min(axis=2).astype(int)
    start = rgb[0, 0].astype(int)
    bg_like = (np.abs(rgb.astype(int) - start).max(axis=2) <= BG_TOL)
    shadow_like = (sat <= 20) & (lum >= 140)
    bg = _flood(rgb, bg_like | shadow_like)
    alpha = ~bg
    alpha = _open3(alpha)     # 噪点会撑大包围盒, 把缩放比例与映射全带偏
    out = np.dstack([rgb, np.where(alpha, 255, 0).astype(np.uint8)])
    return out


def split_run_sheet(rgba: np.ndarray) -> list:
    """4096x1024 横排 4 帧 -> 4 个内容裁切 RGBA。按列空白切分。"""
    a = rgba[..., 3] > 8
    col_has = a.any(axis=0)
    frames = []
    start = None
    for x, has in enumerate(col_has):
        if has and start is None:
            start = x
        elif not has and start is not None:
            if x - start > 32:
                frames.append((start, x))
            start = None
    if start is not None:
        frames.append((start, len(col_has)))
    out = []
    for x0, x1 in frames:
        sub = rgba[:, x0:x1]
        ys, xs = np.where(sub[..., 3] > 8)
        out.append(sub[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    return out


def crop_content(rgba: np.ndarray) -> np.ndarray:
    ys, xs = np.where(rgba[..., 3] > 8)
    return rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


# ---------- 共享调色板 ----------

def build_palette(blobs: list) -> list:
    """中位切分量化: 反复劈颜色跨度最大的簇, 直到 MAX_PAL 个。"""
    px = np.vstack([b[..., :3].reshape(-1, 3)[b[..., 3].reshape(-1) > 128]
                    for b in blobs]).astype(int)
    clusters = [px]
    while len(clusters) < MAX_PAL:
        # 挑跨度最大的簇劈开
        best_i, best_span, best_axis = 0, -1, 0
        for i, c in enumerate(clusters):
            spans = c.max(axis=0) - c.min(axis=0)
            ax = int(spans.argmax())
            if spans[ax] > best_span:
                best_i, best_span, best_axis = i, spans[ax], ax
        if best_span <= 8:
            break
        c = clusters.pop(best_i)
        med = np.median(c[:, best_axis])
        lo = c[c[:, best_axis] <= med]
        hi = c[c[:, best_axis] > med]
        if len(lo) == 0 or len(hi) == 0:
            clusters.append(c)
            break
        clusters += [lo, hi]
    return [tuple(int(v) for v in c.mean(axis=0)) for c in clusters if len(c)]


def quantize(rgba: np.ndarray, pal: list) -> np.ndarray:
    """逐像素贴最近调色板色。在降采样**之后**调: 边缘抗锯齿像素也贴到纯调色板色,
    不出灰边; 半透明 alpha 直接二值化, 像素风不要羽化。"""
    out = rgba.copy()
    m = rgba[..., 3] > 128
    src = rgba[..., :3][m].astype(int)
    pals = np.array(pal, dtype=int)
    d = ((src[:, None, :] - pals[None, :, :]) ** 2).sum(axis=2)
    out[..., :3][m] = pals[d.argmin(axis=1)].astype(np.uint8)
    out[..., 3] = np.where(rgba[..., 3] > 128, 255, 0).astype(np.uint8)
    return out


# ---------- 降采样入帧格 ----------

def to_frame(blob: np.ndarray, target_h: int, foot_y: int = FOOT_Y) -> np.ndarray:
    """内容裁切 RGBA -> 32x32 帧格(未量化)。

    按目标高 target_h 缩放, 宽随原比例(站姿/跑姿各传各的归一高)。降采样后低阈值
    二值化 alpha 再重裁, 消掉 LANCZOS 边缘侵蚀; 水平居中, 脚底贴 foot_y。
    """
    ys, xs = np.where(blob[..., 3] > 128)
    blob = blob[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = blob.shape[:2]
    th = target_h
    tw = max(1, round(w * th / h))
    if th > CONTENT_H_MAX:
        th = CONTENT_H_MAX
        tw = max(1, round(w * th / h))
    img = Image.fromarray(blob).resize((tw, th), Image.LANCZOS)
    arr = np.array(img)
    arr[..., 3] = np.where(arr[..., 3] > 48, 255, 0).astype(np.uint8)
    ys, xs = np.where(arr[..., 3] > 0)
    arr = arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    th, tw = arr.shape[:2]
    frame = np.zeros((FRAME_W, FRAME_W, 4), dtype=np.uint8)
    x0 = (FRAME_W - tw) // 2
    y0 = foot_y - th + 1
    frame[y0:y0 + th, x0:x0 + tw] = arr
    return frame


def sheet(frames: list) -> Image.Image:
    img = Image.new("RGBA", (FRAME_W * len(frames), FRAME_W))
    for i, f in enumerate(frames):
        img.paste(Image.fromarray(f), (i * FRAME_W, 0))
    return img


def frame_diffs(frames: list) -> list:
    """相邻帧 alpha 差像素数, 产出自检用(旧角色基线: idle ~几十 / run ~100)。"""
    out = []
    for i in range(len(frames) - 1):
        d = (frames[i][..., 3] > 8) != (frames[i + 1][..., 3] > 8)
        out.append(int(d.sum()))
    return out


def main() -> None:
    portrait = crop_content(cutout(SRC_PORTRAIT))
    run_blobs = split_run_sheet(cutout(SRC_RUN))
    print("run frames:", [b.shape[:2] for b in run_blobs])

    pal = build_palette([portrait] + run_blobs)
    print("palette:", len(pal), "colors")

    # idle 两姿态: 标准站姿 + 压 1px 的呼吸姿
    idle_poses = [quantize(to_frame(portrait, CONTENT_H), pal),
                  quantize(to_frame(portrait, CONTENT_H - 1), pal)]
    # run 四姿态: 并腿过渡姿(1/3)上提 RUN_BOB, 跨步姿落脚 y31
    run_poses = [quantize(to_frame(b, CONTENT_H_RUN,
                                   foot_y=FOOT_Y - (RUN_BOB if i in (1, 3) else 0)), pal)
                 for i, b in enumerate(run_blobs)]

    idle_f = [idle_poses[i] for i in IDLE_SEQ]
    run_f = [run_poses[i] for i in RUN_SEQ]

    # hit: 前 2 帧白闪(与 apprentice 等旧表一致) + 站姿微弹
    p0 = idle_poses[0]
    p0_up = quantize(to_frame(portrait, CONTENT_H, foot_y=FOOT_Y - RUN_BOB), pal)
    white = p0.copy()
    white[..., :3] = np.where(white[..., 3][..., None] > 0, 255, white[..., :3])
    hit_f = [white, white, p0, p0_up, p0, p0_up, p0]

    os.makedirs(OUT, exist_ok=True)
    # 覆盖前备份旧表, 供 compare 预览并排; 只在备份不存在时写
    # (项目无 git, 2026-09-07 前的手绘版只此一份, 别被后续重跑覆盖)
    old_idle = os.path.join(PREVIEW, "_old_xiaoheizi_idle.png")
    src_old = os.path.join(OUT, "char_xiaoheizi_idle.png")
    if os.path.exists(src_old) and not os.path.exists(old_idle):
        Image.open(src_old).save(old_idle)
    sheet(idle_f).save(os.path.join(OUT, "char_xiaoheizi_idle.png"))
    sheet(run_f).save(os.path.join(OUT, "char_xiaoheizi_run.png"))
    sheet(hit_f).save(os.path.join(OUT, "char_xiaoheizi_hit.png"))
    print("idle diffs:", frame_diffs(idle_f))
    print("run diffs:", frame_diffs(run_f))

    # ---- 预览: 三表 8x(行宽按最长表 12 帧) ----
    os.makedirs(PREVIEW, exist_ok=True)
    prev = Image.new("RGBA", (32 * 12 * 8, 32 * 8 * 3 + 16), (40, 40, 48, 255))
    for row, n in enumerate(["idle", "run", "hit"]):
        s = Image.open(os.path.join(OUT, f"char_xiaoheizi_{n}.png"))
        big = s.resize((s.width * 8, s.height * 8), Image.NEAREST)
        prev.paste(big, (0, row * (32 * 8 + 8)), big)   # 带 mask, 白闪帧可见
    prev.save(os.path.join(PREVIEW, "xiaoheizi_template_sheets_8x.png"))

    # ---- 预览: 新版 vs 旧手绘版(旧表若还在则并排) ----
    rows = []
    new = Image.open(os.path.join(OUT, "char_xiaoheizi_idle.png"))
    rows.append(("new idle", new))
    if os.path.exists(old_idle):
        rows.append(("old idle", Image.open(old_idle)))
    w = max(r[1].width for r in rows) * 8
    cmp_img = Image.new("RGBA", (w, sum(r[1].height for r in rows) * 8), (40, 40, 48, 255))
    y = 0
    for _, im in rows:
        big = im.resize((im.width * 8, im.height * 8), Image.NEAREST)
        cmp_img.paste(big, (0, y), big)
        y += big.height
    cmp_img.save(os.path.join(PREVIEW, "xiaoheizi_template_compare.png"))
    print("done:", OUT)


if __name__ == "__main__":
    main()
