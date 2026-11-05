# -*- coding: utf-8 -*-
"""0x72 Dungeon Tileset II v1.7 -> resource/pixel32/ 怪物精灵表拼接。

三只新怪(吐息 imp / 自爆 chort / 护盾 ogre)每帧独立 PNG,
水平拼成单表适配 game_manager.frames_for() 的 region 取帧机制。
先例同 boss_idle.png(见 resource/CREDITS.md 第七节)。

源 zip 在 D:/EdgeDownload/,若移动过改 ZIP 常量即可。
产物是运行时素材(非临时目检图),落在 resource/pixel32/ 并随 --import 生成 .import。
"""
import io
import zipfile
from pathlib import Path

from PIL import Image

ZIP = Path("D:/EdgeDownload/0x72_DungeonTilesetII_v1.7 (1).zip")
OUT = Path(__file__).resolve().parent.parent / "resource" / "pixel32"

# kind 键名 -> 源角色名(0x72 frames/ 下的前缀)
MONSTERS = {
    "imp": "imp",
    "chort": "chort",
    "ogre": "ogre",
}
ANIMS = ["idle", "run"]


def main() -> None:
    z = zipfile.ZipFile(ZIP)
    names = z.namelist()
    OUT.mkdir(parents=True, exist_ok=True)
    for key, base in MONSTERS.items():
        for anim in ANIMS:
            files = sorted(
                n for n in names
                if ("/" + base + "_" + anim + "_anim_f") in n
                and n.endswith(".png")
                and "__MACOSX" not in n
            )
            frames = [Image.open(io.BytesIO(z.read(f))).convert("RGBA") for f in files]
            fw, fh = frames[0].size
            assert all(fr.size == (fw, fh) for fr in frames), f"{base}_{anim} 帧尺寸不一致"
            sheet = Image.new("RGBA", (fw * len(frames), fh), (0, 0, 0, 0))
            for i, fr in enumerate(frames):
                sheet.paste(fr, (i * fw, 0))
            dst = OUT / f"{key}_{anim}.png"
            sheet.save(dst)
            print(f"{dst.name}: {sheet.width}x{sheet.height} ({len(frames)} frames @ {fw}x{fh})")


if __name__ == "__main__":
    main()
