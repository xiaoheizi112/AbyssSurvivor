# resource/ 素材授权清单

> 本目录为**素材库**（非直接使用）。接入游戏时复制到 `assets/` 对应子目录，
> 因为 `kenney_cc0/` 与 `bgm_cc0/` 内各含 `.gdignore`，Godot 不会导入这里的文件
> （避免 950+ PNG 全量导入拖慢编辑器启动）。
> `pixel_srpg/` 不受影响，仍可正常导入。

---

## 一、kenney_cc0/ — Kenney CC0 像素素材

来源：https://kenney.nl 全部为 **Creative Commons Zero (CC0)**，
可个人/教育/商用，**无需署名**（署名是自愿支持行为）。

| 包 | 内容 | 数量 | 规格 | 对应项目缺口 |
|---|---|---|---|---|
| `ui-pack-pixel-adventure` | UI 边框/按钮/血条/经验条/图标 | 514 png | 16×16 (322) + 32×32 (182) | **UI 素材**（`pixel_srpg/ui/` 原为空） |
| `tiny-battle` | 战斗单位/地块 tileset | 198 png | **16×16** | 敌人/地面多样性，可替换 Kenney 占位 |
| `roguelike-characters` | 角色 spritesheet | 2 png | 918×203，**16×16 + 1px margin**（51×11 格） | 4 角色换肤底图 |
| `cursor-pixel-pack` | 像素鼠标指针 | 220 png | **16×16** | 鼠标点击（角色选择/升级三选一用鼠标） |
| `tower-defense-top-down` | top-down 塔防地形图块（草地/泥土/沙/岩石，**无水域**） | 299 png | **64×64** | 草原/地形 map 图块 |

`tower-defense-top-down` 下载自 2026-09-06，已按地形类别额外建分类目录便于取用：
`terrain_grass/`(107) `terrain_dirt/`(54) `terrain_sand/`(49) `terrain_rock/`(40) `terrain_other/`(49)；
原始 `PNG/Default size/` 下 299 张完整保留作备份。**该包不含水域图块**，水域需另从
Kenney `medieval-rts` 或 `roguelike-rpg-pack` 补，或用程序化水面。

各包内含上游 `License.txt`，已随素材保留。

### 接入要点

- **像素过滤已配好**：`project.godot` 中 `default_texture_filter=0` (Nearest)，无需改动。
- **roguelike-characters 切帧**：网格是 16×16 tile + 1px margin，切帧时步进量用 **17px**
  而不是 16px，否则会错位一像素。公式：`x = col * 17`，`y = row * 17`。
- **ui-pack-pixel-adventure 有 4 套变体**：`Tilesheets/{Large,Small} tiles/{Thick,Thin} outline/`
  下的 `tilemap_packed.png` 是整表，Godot TileSet 可直接用；`Tiles/` 下是已切好的单图。
  选一种 outline 风格全局统一，不要混用。
- **tiny-battle** 附带 `Tiled/sampleMap.tmx` + `sampleSheet.tsx`，是 Tiled 编辑器工程文件，
  Godot 用不上，接入时忽略。

---

## 二、bgm_cc0/ — OpenGameArt CC0 背景音乐

来源：https://opengameart.org 均为 **CC0**（部分同时提供 OGA-BY 3.0，此处按 CC0 使用，
即**无需署名**）。对应 README 中「BGM 尚未接入」缺口。

| 本地文件 | 原始作品 | 作者 | 时长 | 建议用途 |
|---|---|---|---|---|
| `menu.ogg` | Chill Main Menu music | haeldb | 01:39 | 主菜单 / 标题画面 |
| `battle.ogg` | Running from something | haeldb | 02:03 | 常规战斗循环 |
| `boss.ogg` | Cave Theme | haeldb | 04:40 | Boss 战（120s 登场） |

原始链接：
- https://opengameart.org/content/chill-main-menu-music
- https://opengameart.org/content/running-from-something
- https://opengameart.org/content/cave-theme

均为 44100Hz Ogg Vorbis，Godot 可直接 `AudioStreamOggVorbis` 加载。
设 `loop = true` 用于战斗循环。

**已接入（2026-09-06）**：三轨复制到 `assets/audio/bgm_{menu,battle,boss}.ogg`，
由 `game_manager.gd:play_bgm()` / `stop_bgm()` 驱动，`main.gd` 按状态机切换：
主菜单/角色选择 → `menu`，开始战斗 → `battle`，Boss 登场 → `boss`，Boss 死 → 回 `battle`，
GameOver/Victory → 停止。原始素材仍在 `resource/bgm_cc0/` 保留。

---

## 二.五、Kenney CC0 音效包（2026-09-06 替换）

音频 `assets/audio/sfx_*.ogg` 原为 Kenney Digital Audio 套件，2026-09-06 整体替换为
以下三个 Kenney CC0 包（`https://kenney.nl`，Creative Commons Zero，可商用无需署名）：

| 包 | 归档（resource/kenney_cc0/，含 .gdignore 不导入） | 提供类别 |
|---|---|---|
| `impact-sounds` | `kenney_impact-sounds.zip` | 打击/受击/脚步 |
| `sci-fi-sounds` | `kenney_sci-fi-sounds.zip` | 激光/爆炸/引擎 |
| `interface-sounds` | `kenney_interface-sounds.zip` | UI 点击/确认/拾取 |

最终 `sfx_*.ogg` 映射（源文件 → 用途）：

| sfx | 源文件 | 用途 |
|---|---|---|
| shoot | sci-fi `laserSmall_000` | 玩家普攻 |
| hit | impact `impactPunch_medium_000` | 命中反馈 |
| kill | sci-fi `lowFrequency_explosion_000` | 击杀爆裂 |
| pickup | interface `drop_001` | 拾取 |
| levelup | interface `confirmation_002` | 升级上扬 |
| select | interface `click_001` | UI 选择 |
| hurt | impact `impactWood_light_000` | 玩家受击 |
| death | Kenney `phaserDown1`（相位下行） | 死亡/失败（柔和下行，无爆炸） |
| elite | sci-fi `laserLarge_000` | Boss 登场 |

---

## 三、未采用 / 排除说明

| 候选 | 排除原因 |
|---|---|
| Kenney `minimap-pack` | 150 个 8×8 小地图图块，本游戏无小地图机制 |
| Kenney `music-jingles` | 实测 8-bit jingles 平均 **1.1 秒**，是过场短音不是可循环 BGM |
| Kenney `rpg-audio` | 内容为 bookClose/chop/cloth 等生活音效，与割草战斗无关；项目已有 Kenney 战斗音效 |
| OGA `action-theme-song` | 实际是 RIFF/WAV 8.4MB（非 ogg），本机无 ffmpeg 无法转码 |

---

## 三.五、pixel32_terrain/ — 32×32 地形图块（本地库 PixelSRPG-Forge）

来源：本地 `D:\GameResource\GameArt\PixelSRPG-Forge-main`（MIT 组织许可），2026-09-06 落盘。

| 文件 | 内容 | 尺寸 | 用途 |
|---|---|---|---|
| `GK_A2_CCautotile_1.png` | RPGMaker VXAce A2 自动图块：草地(1-2列)、沙(3-4列)、水(5-6列) + 边界衔接块 | 512×384 (16×12 格 @32) | 地图地表（绿/沙/水三色，含边界过渡） |
| `GK_C_CC_1.png` | 地图装饰（树/草/岩石等，36 块绿色系） | 512×512 (16×16 格 @32) | 地图布景物 |

**图块规格**：均为 **32×32** 实心图块，直接匹配项目 `art-standard.md`。
autotile 表用 `AtlasTexture` 按 32 取帧（不切文件），flatfill 用左上角绿色块即可。

**⚠️ 授权风险（如实标注，非本次引入）**：该仓库根目录 `LICENSE` 虽是 MIT，
但 README 作者自述「素材通过多渠道收集（互联网下载+商城购买），**不清楚所有素材的版权状态**，
商业使用前务必核实版权状态」。`GK_*` 为 RPGMaker 格式素材，可能受 RPG Maker 引擎授权条款约束。
→ 正式发布前需核实；仅供当前开发阶段占位，可用 Kenney CC0 替换（见第一节）。

## 四、待解决的授权隐患（原有，非本次引入）

`pixel_srpg/清单.md` 第四节记录：素材来自 **PixelSRPG-Forge**
（`D:\游戏资源\游戏美术资源\PixelSRPG-Forge-main`，176MB），
**授权条款尚未确认**。该目录 13 个 PNG 已切帧待用。

> 正式发布前必须核实 PixelSRPG-Forge 的授权与署名要求。
> 若授权不明，建议改用本文件第一节的 Kenney CC0 素材替代——
> CC0 无署名义务、可商用，法律风险为零。

---

## 五、本次未接入代码

以上素材**仅落盘到 `resource/`，尚未接入游戏**。
`scripts/game_manager.gd:44` 的 `const TEXTURES := {}` 仍为空表，
游戏当前实际仍使用 `circle_texture()` 纯色圆形占位。

接入步骤见 `docs/图标设计方案.md` 第四节。

---

## 六、击杀数骷髅图标（2026-09-06 接入）

右上角击杀数图标由程序化字符画替换为**真 32×32 卡通像素骷髅**：

| 文件 | 内容 | 来源 | 授权 |
|---|---|---|---|
| `assets/ui/skull_kill.png` | 16×16 卡通骷髅头（去透明边后居中） | OpenGameArt 作品 *Pixel Art Skull*，作者 **FancySnacks** | **CC0**（公共领域，可商用免署名） |

原始素材（OpenGameArt 页面提供的两个变体）：
- `pixelart_skull_0.png`（512×512，抗锯齿渲染版）——未采用
- `pixelart_skull_1.png`（16×16，纯像素 5 色调）——采用此版，符合项目 32px 像素标准

来源链接：https://opengameart.org/content/pixel-art-skull

接入方式：`game_manager.gd:skull_icon_texture()` 优先 `load()` 该 PNG，缺失时回退到字符画。
图标在 `hud.gd` 击杀数组件中以 24×24（Nearest）显示。

---

## 七、Boss 贴图（2026-09-07 替换）

原 Boss 用 `skull_idle.png`（Pixel Adventure 骷髅）。2026-09-07 替换为 **big_demon**：

| 文件 | 内容 | 来源 | 授权 |
|---|---|---|---|
| `pixel32/boss_idle.png` | big_demon 卡通恶魔（32×36，idle 4 帧水平拼） | 0x72 **Dungeon Tileset II** v1.7 | **CC0**（公共领域） |

来源：https://0x72.itch.io/dungeontileset-ii

- 原包每帧独立 PNG（`frames/big_demon_idle_anim_f0..3.png`），已用 PIL 水平拼成 128×36 单表适配项目 `make_frames()` 的 region 取帧机制。
- 接入点：`game_manager.gd` 的 `TEXTURES` 加 `boss_idle` 键，`BOSS_FRAMES` 改为 `["idle", "boss_idle", 32, 36, 6.0]` + `["hit", "boss_idle", 32, 36, 10.0]`。
- 尺寸：`boss.gd:_ensure_visual()` 中 `sprite.scale = 1.45`（32×36 → 约 46×52，比原骷髅更有压迫感）；终极 Boss `make_final()` 再放大到 `1.9`。
- `skull_idle.png`/`skull_hit.png` 仍在 `pixel32/` 但已不再被 Boss 引用（保留作素材库）。

---

## 八、三种新怪贴图（2026-09-09 新增）

新增杂兵 kind 4/5/6：炎魔小鬼（吐息）、爆裂魔（自爆）、盾卫巨魔（护盾），全部来自 **0x72 Dungeon Tileset II v1.7**：

| 文件 | 内容 | 帧尺寸 | 授权 |
|---|---|---|---|
| `pixel32/imp_idle.png` | imp 小鬼 idle 4 帧水平拼（64×16） | 16×16 | **CC0** |
| `pixel32/imp_run.png` | imp 小鬼 run 4 帧水平拼（64×16） | 16×16 | **CC0** |
| `pixel32/chort_idle.png` | chort 自爆魔 idle 4 帧水平拼（64×23） | 16×23 | **CC0** |
| `pixel32/chort_run.png` | chort 自爆魔 run 4 帧水平拼（64×23） | 16×23 | **CC0** |
| `pixel32/ogre_idle.png` | ogre 巨魔 idle 4 帧水平拼（128×36） | 32×36 | **CC0** |
| `pixel32/ogre_run.png` | ogre 巨魔 run 4 帧水平拼（128×36） | 32×36 | **CC0** |

来源：https://0x72.itch.io/dungeontileset-ii

- 原包每帧独立 PNG（`frames/<name>_<anim>_anim_f0..3.png`），由 `map_preview/generate_dungeon_monsters.py`（PIL 水平拼接）生成单表，适配 `frames_for()` 的 region 取帧机制（拼接先例同第七节 boss_idle.png）。源 zip 在 `D:/EdgeDownload/0x72_DungeonTilesetII_v1.7 (1).zip`（脚本内 ZIP 常量，移动过需改）。
- 接入点：`game_manager.gd` 的 `TEXTURES` 加 6 键；`ENEMY_FRAMES[4/5/6]` 各 idle+run 两行；`ENEMY_VISUAL` 给每 kind 基准 scale/offset —— imp/chort 是 16px 素材，scale 2.0 对齐项目 32px 视觉重量，ogre 本身就是 32px 格，scale 1.0。
