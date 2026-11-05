# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

《深渊幸存者》— Godot 4.6 (GDScript) 的吸血鬼幸存者 Like,Windows 桌面。全部游戏逻辑与 UI 用代码构建,`.tscn` 只有 `scenes/main.tscn`(一个挂 `main.gd` 的空 Node2D)。

## 沟通约定

- 用户说的「方向键」一律指 **WASD 字母键**（`move_up/down/left/right`），不是 ↑↓←→ 箭头键。无特别说明时，导航键按 WASD 理解/编写。

## 任务分级与模型选择(2026-09-09 用户指定)

按「贵/便宜模型 × 任务类型」自动分级,不必每次询问:

- **主会话(贵档)只做**:规划、架构决策、根因排查、数值平衡、创造性设计 —— 一次性、需要上下文的推理。
- **派子代理(便宜档,`model: "haiku"`,能后台就后台)**:重复性/结构化执行 —— 大范围文件检索与代码定位(Explore)、跑测试/冒烟并汇总输出、批量同构替换、读长文件提取结论。判据:任务不需要本会话的历史上下文、结果可用一两句话验收。
- **高频轮询类等待**(等编译、等渲染完成)优先用脚本/后台命令自轮询,不反复唤起模型查看。
- 拿不准归哪档时,默认留在主会话;明确属于上面第二类的才外派。

## 命令

Godot 装在 `D:\Godot\`,两个 exe:`Godot_v4.6-stable_win64.exe`(带窗口)/ `..._console.exe`(headless 用这个,能拿到 stdout)。

```bash
# 导入资源(新增/替换素材后必跑,否则 texture_for 静默回退成程序化圆形)
"D:/Godot/Godot_v4.6-stable_win64_console.exe" --headless --path . --import

# 冒烟:AI 自玩 + 无敌,覆盖全波次到通关
# 60000 帧才够跑完(实测通关 time≈347s ÷ headless ~145fps ≈ 50000 帧);
# 20000 帧只到第 5 波就硬退,看不到 VICTORY 行
"D:/Godot/Godot_v4.6-stable_win64_console.exe" --headless --path . --quit-after 60000 \
  -- --autostart --autopilot --autopilot-god

# 玩家真实游玩入口(带窗口,无用户参数 => test_mode=false,照常存档)
./run.bat

# 普通自玩(会死,测存活曲线与死亡结算)
... --quit-after 12000 -- --autostart --autopilot

# 移动策略档(盲区 1: 单策略只证明一个玩家能过关): --autopilot-style balanced|glass|kite
#   balanced 默认,健康冲宝石/危险才逃;  glass 永不逃贴脸输出(极限承伤);
#   kite 永不主动吃资源只绕圈(零主动成长龟缩, 卡难度曲线下限; 但被动磁吸+商店自动回血仍兜着,
#   hard 档实测也能通关 358s => 压不出真实死亡, 那条链归 --death-check)
... --quit-after 40000 -- --autostart --autopilot --autopilot-style kite

# 快速语法检查(无冒烟):--import 就会报 Parse Error

# 图鉴自检:走查全部 tab × 条目,量数值列是否被裁 + 结构断言,跑完自行 quit
... --quit-after 8000 -- --codex-check

# 局内续玩档自检:save→load→resume 全链路(状态/武器节点/地图/Boss 波重摆/坏档清除),跑完自行 quit
# 改动 save_suspend/load_suspend/resume_run 任一函数后必跑;会备份并还原玩家真实 suspend.cfg
... --quit-after 6000 -- --resume-check

# 无限成长兜底自检:强制满配(7 武器 Lv3+9 被动 Lv3+7 进化)压池空路径,10 项断言
# 改动 OVERLIMIT/roll_upgrade_options/apply_upgrade/gain_overlimit 任一后必跑
# (autopilot god 局武器数封顶 3,常规池永远抽不干,冒烟覆盖不到这条兜底)
... --quit-after 3000 -- --overlimit-check

# 死亡链路自检:died→game_over 结算→结算屏→重开/回菜单 全链路,6 项断言
# 常规冒烟从不触发真实死亡(balanced 回血抵得住/god 锁血/kite 有磁吸+商店兜着),
# 这条链只有本自检与玩家手玩才走到;改动 take_damage/game_over/show_game_over/restart 后必跑
... --quit-after 3000 -- --death-check

# 各界面键盘输入链自检:合成真实 InputEventKey 走 _unhandled_input,16 项断言
# 覆盖主菜单/角色选择/升级三选一/波间商店/图鉴/设置/战斗 R/局外商店/重开确认框 的键盘分支;
# autopilot 与 ui-shot 全走函数路径,这些 gate 此前无自检覆盖(改坏玩家键盘全失灵而冒烟全绿)。
# 注意:进界面要走 main 的 show_menu()(置 state),hud.show_menu 只建 UI 不置 state
... --quit-after 4000 -- --menu-check

# 七武器逐一真实伤害自检:7 武器 × 常态/进化 = 14 局 + 2 项判别断言,共 17 项
# 盲区:god 冒烟的 autopilot 封顶 FOCUS_WEAPONS=3 且每局抽哪 3 把随机 => 七把武器与七个进化
# 从未被逐一验证「真的能打出伤害」;改坏某把(索敌半径/弹速/burn_zone 不生成/脚本映射漏行)
# 冒烟照样全绿。做法:每把单独开局 + restore_weapons 只挂它(绕军械加成) + 关刷怪 +
# 钉一只百万血靶敌(每帧复位位置,否则击退把它推出射程)跑真实攻击路径到掉血。
# 特性只验概率 1.0 的确定性链(旋刃流血/圣环易伤/飞刀中毒/燃烧瓶燃烧/回旋镖进化减速),
# 法杖眩晕 20%、闪电冰冻 10~20% 是掷骰,验了必 flaky。
# 圣环进化与闪电进化的伤害数字与常态相同(只加半径/连锁),故另有两项直接量:
# 圣环 radius() 必须 ×1.6、一排 7 怪数掉血只数必须 3→6。
# 改动任一武器 _do_attack / WEAPON_SCRIPTS 映射 / WEAPON_TRAITS 后必跑
... --quit-after 16000 -- --weapon-check

# 五角色被动逐一生效自检:三表键对齐 + 逐角色六属性接线 + 五个被动各走自己的代码路径 + 反向对照,共 12 项
# 盲区同 --weapon-check:autopilot 每局只随机选一个角色,五角色被动(学徒经验/弹速、圣骑士圣盾、
# 忍者蛙拾穗、面具客处决、只因信徒金拱)从不一一验证;改坏某条(圣盾 gate 写反、heal_mult 漏接)冒烟照样全绿。
# 做法:_calm_field 冻刷怪让 wave 停 0(倍率恒 1.0), 直接断言。属性比 base_*/char_* 字段(由 setup
# 直接抄表, 不经 meta/item/overlimit); 跨角色被动用比值法两局自消 meta 通道。
# 改动 CHARACTERS 数值 / setup_character / 任一角色被动(player.gd)后必跑
... --quit-after 16000 -- --char-check

# 六词缀 + 精英逐一生效自检:词缀表完整性 + affix_pool 派生 + 三掷骰门槛 + 六词缀倍率/行为 + 精英双词缀,共 18 项
# 盲区:六词缀是互相独立的行为分支(疾风/坚韧改数值、再生每帧回血、射手生敌弹、分裂/自爆各走 die() 一段),
# 而冒烟里刷出哪条全随机(分裂波7/自爆波8 才解锁, 精英几十只一只) => 一局能否凑齐六条纯看运气。
# 改坏一条(尤其 _apply_affix 的 has() 守卫退化成无条件赋值 => "再生+疾风"第二条把 _regen 抹 0)冒烟全绿。
# 做法:_calm_field 冻刷怪 wave 停 0 + restore_weapons({},{}) 清武器(玩家不输出, 不干扰射手敌弹计数) +
# 直接 spawn 指定词缀怪走真实 setup/_physics_process/die。数值断言一律用「同帧无词缀怪当基准」做比值,
# enemy_hp_mult/难度/诅咒三通道两边同乘自消。含 9b 经验诚实性断言(锁 spawn_gems 的 per 修复, 见「刷怪」节)。
# 改动 ENEMY_AFFIXES / ELITE_BASE / _apply_affix / affix_pool / roll_enemy_affix(2) / roll_elite / spawn_gems 后必跑
... --quit-after 16000 -- --affix-check

# UI 全景截图:19 屏(菜单/角色选择/战斗×2/圣水三态/精英/Boss/升级/波间商店/局外商店×2/设置/图鉴/失败/通关/带档菜单/重开确认)
# 只改 UI 布局时用它目检,headless 全黑,必须带窗口 exe;产物 _ui_shots/(可整目录删)
# fixture 注意:升级弹窗会污染截图(宝石 <4px 接触拾取+磁吸恢复后成堆吃),截图前必须
# _dismiss_levelup() 或清光 gems;带档菜单/重开确认两屏用 save_suspend(true) 造夹具,
# 开头备份玩家真档、结尾还原
"D:/Godot/Godot_v4.6-stable_win64.exe" --path . --quit-after 100000 -- --ui-shot
```

`--quit-after N` 的 **N 是帧数不是秒**(headless ~150fps,120s ≈ 18000 帧)。`--` 之后才是传给游戏的用户参数。

没有单元测试框架。**改完数值靠 autopilot 战报对照验证**:每 10s 一行,含时间/等级/击杀/血量/实体数/`fps=`/超限层数 `ov=N`/持有武器清单 `wpn[id级[*进化]]`/对象池水位/Boss 血量,以及实体数组与池的一致性断言(失效对象打 `ASSERT-FAIL`,正常应全程 `invalid=0`)。战报里的 `fps` 字段**只在带窗口跑才有意义**(headless 无 vsync/渲染,测不出帧预算崩盘);排查"后期卡死"必须带窗口 exe 看后期 fps 是否跌到个位数。

命令行标志:`--autostart`(跳过主菜单直接开战,可带 `--char <id>` 指定角色)、`--autopilot`(启用自玩)、`--autopilot-god`(锁满血)、`--difficulty <0|1|2>`(测试专用难度覆盖,只改内存不落盘;困难档冒烟靠它压曲线上限)、`--speed <0.5~3.0>`(测试专用倍速覆盖,缺省一律钉 1.0 —— `Settings.game_speed` 从真实 settings.cfg 读且经 `apply_game_speed` 写 `Engine.time_scale`,玩家调过 3× 后所有冒烟会静默跑在 3× 时间下:`--quit-after` 帧数覆盖的游戏时长缩到 1/3、战报 fps 失去意义、"跑够 N 帧到第 12 波"的命令全部提前硬退。2026-09-10 实测发现)、`--codex-check`(图鉴自检)、`--codex-shot`(图鉴截图)、`--resume-check`(续玩档自检)、`--overlimit-check`(无限成长兜底自检)、`--death-check`(死亡链路自检)、`--menu-check`(各界面键盘输入链自检)、`--weapon-check`(七武器逐一真实伤害自检)、`--char-check`(五角色被动逐一生效自检)、`--affix-check`(六词缀+精英逐一生效自检)、`--ui-shot`(全界面截图)。

**测试隔离判据是「反向」的,不要改回白名单**:`GameManager._ready()` 里 `test_mode = not OS.get_cmdline_user_args().is_empty()` —— **带任何用户参数(`--` 之后有东西)即测试跑**,永久存档只读不写。白名单枚举的失败模式是静默的:新增一条自检忘了往表里加,那一跑就以 `test_mode=false` 完整执行,解锁成就 + `deposit_run_coins` 落盘,**没有任何报错**。已实测付出代价:2026-09-09 `--overlimit-check` 漏在表外,真实 `meta.cfg` 被测试数据灌到 `bank=629298`(原值不可恢复)。反向判据让今后新增的测试标志天然安全。真实游玩(`run.bat` / 编辑器 F5)不带用户参数 ⇒ `test_mode=false`,照常存档。`test_mode` 下 `save_meta()`/`save_suspend()` 不落盘,内存态照常累加,结算/商店路径不受影响;唯一例外是 `save_suspend(true)` 的 `force_test` 旁路,专供 `--resume-check` 写一次真档,自检结尾还原。**`clear_suspend()` 同构 gate**(2026-09-10 补的洞):结算(`game_over`/`on_final_boss_defeated`)与新开局(`start_game`)都调它,不 gate 的话**每次冒烟/自检都会静默删掉玩家真实的局内续玩档**,且 md5 隔离比对查不出(suspend.cfg 平时不存在,比不出变化)。force 旁路只给三处:自检删自己的夹具档、`resume_run` 读档即消费、`load_suspend` 三条坏档分支(测试跑里坏档只可能是自检夹具)。

验证测试隔离:跑测试前后比对 `user://` 下 `meta.cfg`/`settings.cfg` 的 md5 与 `suspend.cfg` 是否存在(目录在 `$APPDATA/Godot/app_userdata/深渊幸存者`),应完全不变。**注意当前 `meta.cfg` 已是被污染的脏档**(`bank=629298.5`、11 条成就里 10 条已解锁 —— 只剩 `all_chars` 因 `char_wins` 仅有 apprentice 而未达成),md5 比对只能证明"没有变得更脏",不能当干净基线用。

## 架构

### 四个 autoload(见 `project.godot`)

- **`GameManager`** (`scripts/game_manager.gd`, ~118KB / ~2700 行,第二大的文件) — 全局真相源。世界几何常量(`VIEW_W/H=640×360`、`TILE=32`、`WORLD_W/H=800×450`、`BOUND`、`PLAYER_RADIUS`)、状态机、本局运行态(`time_s`/`wave`/`kills`/`level`/`xp`/`coins`/`curse_level`)、跨局永久态(`bank`/`upgrades_owned`/`achieved`/`char_wins`,存 `user://meta.cfg`)、局内续玩档(`save_suspend`/`load_suspend`/`has_suspend`/`clear_suspend`,存 `user://suspend.cfg`,见「存档」)、成就(`ACHIEVEMENTS`/`unlock_achievement`/`check_achievements`)、实体列表(`enemies`/`gems`/`projectiles`/`coins_list`)、难度倍率、音频接口(`play_sfx`/`play_bgm`/`play_page_sfx`)、相机震动、程序化贴图工具(`circle_texture`/`skull_icon_texture`/`frames_for`/各类 `*_icon_texture`)。

  **一半篇幅是静态数据表(改数值就改这里,别在代码里写魔法数)**,按主题成组:`CHARACTERS`/`CODEX_CHARS`/`WEAPONS`/`WEAPON_TRAITS`/`WEAPON_DETAILS`/`EVOLUTIONS`/`EVOLUTION_TRAITS`/`STATUS_NAMES`/`UPGRADES`/`OVERLIMIT`/`META_UPGRADES`/`SHOP_OFFERS`/`SHOP_RARITY_WEIGHT`/`LEVELUP_REROLL_MAX`/`WAVE_CURSES`/`CURSE_MAX`/`ENEMY_BASE`/`ENEMY_VISUAL`/`ENEMY_DROPS`/`ENEMY_AFFIXES`/`ELITE_BASE`/`BOSS_BASE`/`BOSS_FINAL`/`CODEX_BOSSES`/`WAVE_COUNT`,加贴图与图标族(`PIXEL_BASE`/`TEXTURES`/`ENEMY_FRAMES`/`BOSS_FRAMES`/`CHAR_FRAMES`/`WEAPON_ICONS`/`ACHIEVEMENT_ICONS`/`SHOP_ICONS`/`COIN_ICON`/`SKULL_ICON` 及各自 `_PALETTE`/`FX_PALETTE`/`PIXEL_FX`)。

  **已删且别再加回来**:`ITEMS` 表与 `player.gain_item()`(带负修正的一次性代价道具整条链已移除)。`player.item_mods` 仍在,但**唯一写入者是波间商店** `buy_shop_offer()` 的 `damage_mult`/`crit_chance`/`coin_mult`/`max_hp_flat` 四项临时修正。
- **`ObjectPool`** (`scripts/object_pool.gd`) — 全实体池化。**节点常驻 `main` 树下不销毁**,`acquire`/`release` 只切 `visible` + `set_process`/`set_physics_process`。类型化工厂:`spawn_bullet`/`spawn_enemy`/`spawn_boss`/`spawn_gem`/`spawn_pickup`/`acquire_effect`。`main._prewarm_pools()` 开局预分配(bullet 400 / enemy 300 / gem 300 / effect 60)。
- **`Settings`** (`scripts/settings.gd`) — 音量 + 难度,持久化到 `user://settings.cfg`。`_ensure_actions()` 在运行时注册 `move_up/down/left/right`(WASD + 方向键双套),**不支持重映射**。
- **`Autopilot`** (`scripts/autopilot.gd`) — 自玩驱动。用 `Input.action_press` 走真实移动路径(血量健康→冲最近宝石吃经验,危险/贴身→向外逃+切线绕圈,贴墙→叠加向内修正);自动选升级(god 模式封顶 `FOCUS_WEAPONS=3` 把 + 档位 `_opt_tier` + 重摇 `REROLL_TRIES=16`,理由全写在 `_pick_upgrade` 上方注释里);死亡/通关自动重开。**三档移动策略** `--autopilot-style balanced|glass|kite`(2026-09-09):balanced=原逻辑;glass=永不逃直冲怪堆(压极限承伤);kite=永不主动吃资源只绕圈躲(压零成长存活曲线)。**已知盲区**:常规冒烟从不触发真实死亡 —— balanced 回血抵得住、god 锁血、kite 也有被动磁吸+商店自动回血兜着,`player.died`→死亡结算→重开链路只有玩家手玩或长局才走到,改动死亡/结算路径时别指望冒烟覆盖。另一条同源盲区是**武器覆盖不全**:`FOCUS_WEAPONS=3` 封顶 + 每局抽哪 3 把随机,七把武器与七个进化在冒烟里从不一一出现(非 god 局不封顶,但也不保证七把全凑齐),改坏某把武器冒烟照样全绿 —— 这条归 `--weapon-check`(见「命令」)。同源还有两条:**角色覆盖不全**(autopilot 每局只随机选一个角色,五角色被动从不一一验证 → `--char-check`)、**词缀覆盖不全**(六词缀按波次随机刷,分裂波7/自爆波8 才解锁、精英几十只一只,一局能否凑齐六条纯看运气 → `--affix-check`)。

### 非 autoload 脚本分组

`scripts/` 扁平无子目录,~40 个文件按职责分四组:

- **场景与驱动**:`main.gd`(场景装配 + 状态流转 + 全部自检入口,~1250 行)、`hud.gd`(全部界面,项目最大文件)、`player.gd`(build/属性/武器挂载)、`spawner.gd`(波次刷怪)、`settings.gd`
- **实体**:`enemy.gd`/`boss.gd`/`bullet.gd`/`gem.gd`/`coin.gd`/`pickup.gd`/`damage_number.gd`/`effect.gd` —— 全部池化,节点常驻不销毁
- **武器**:七把各一文件(`wand`/`orbit_blade`/`aura`/`dagger`/`shuriken`/`holy_water`/`lightning`)继承 `weapon_base.gd`;`burn_zone.gd`/`holy_vial.gd` 是圣水的链式辅助体,不独立挂载
- **程序化像素/特效工具(4 个,无外部素材)**:
  - 两个 `RefCounted` 静态工具(**不进树、不池化**):`status_fx.gd`(`class_name StatusFx`,7 种状态效果,见「状态效果」节)、`pixel_utils.gd`(`class_name PixelUtils`,整数对齐无抗锯齿的逐像素绘制,供**不继承 WeaponBase 的散件** bullet/holy_vial/burn_zone 用;武器本体的持续绘制走 `weapon_base.gd` 的 `px_*` 实例方法,两者实现一致)
  - 两个 `Node2D`(**池化复用**):`pixel_fx.gd`(一次性像素特效,帧由 `GameManager.fx_frames()` 从 `PIXEL_FX` 字符画烘焙成灰度 `ImageTexture`,再用 `draw_texture_rect` 的 modulate 按武器主题色染色 —— 同一套灰度帧喂所有武器;支持整数倍放大/旋转/淡出/加法混合)、`spawn_markers.gd`(刷怪预警叉,**与 `spawner._telegraphs` 共享同一个 Array 引用**,本节点只画不拥有数据;`z_index=-5` 卡在地面与实体之间,`PROCESS_MODE_ALWAYS` 保证暂停/商店时也能收叉不留残影)

### 场景装配与状态流转

`main.gd` 在 `_ready` 里按序 `_build_ground` → `_build_player` → `_build_camera` → `_build_spawner` → `_build_hud` → `_prewarm_pools`。所有节点都是代码 new 出来的,先装子节点再 `add_child`(避免子节点 `_ready` 时找不到兄弟)。

状态机 `GameManager.State`:`MENU → CHARACTER_SELECT → PLAYING ⇄ LEVEL_UP / SHOP / SETTINGS → GAME_OVER | VICTORY`,另有 `CODEX`(图鉴,主菜单 + 游戏内设置面板进入)。图鉴用 `codex_return_state` 记录来源(同 `settings_return_state` 的做法),关闭按来源恢复。**没有 `PAUSED` 状态**(2026-09-07 清理删除):`main.gd` 把 ESC-in-PLAYING 直接路由到 `show_settings()`,设置面板就是实际暂停菜单(靠 `get_tree().paused`)。旧 `show_pause()`/`pause_screen`/`_pause_btns` 整条链是死代码 —— 唯一能进入 `PAUSED` 的代码本身就在 `if st == PAUSED` 分支里(自引用死锁),已连枚举值一并删除。`State` 全项目按名字比较、从不序列化(存盘只有 `bank`/`upgrades_owned`),所以增删枚举成员是安全的。

**重开不 reload 场景**(`restart()` 只回角色选择),所以跨局残留必须手动清:`ObjectPool.reset()`、三个实体列表 `.clear()`、`spawner.reset_run()`、玩家位置显式复位到 `BOUND.get_center()`、`_randomize_map()` 重建地面。加新的计时器/累计量时记得在对应 reset 里归零。

### 存档:局内单槽续玩 + 全局成就(2026-09-08)

**局内续玩档 `user://suspend.cfg`(土豆兄弟式,单槽)**:`save_suspend()` 写四段 `run`(角色/武器/时间/波次/等级/经验/金币/道具/刷新次数/终极 Boss 标记/**`_rng.state`** 保证刷怪随机流续接)/ `spawner`(四个计时器与权重,**预警叉不存**)/ `map`(`_ground_style`)/ `player`(build 全字段;`weapons` 节点不存,恢复时按 `weapon_levels` 重建实例)。写入时机三处:设置面板「保存并退出」、`main._notification(NOTIFICATION_WM_CLOSE_REQUEST)`(PLAYING 时关窗,`set_auto_accept_quit(false)` 把 quit 交给它)、`--resume-check` 的 `force_test` 旁路。删除时机:结算(胜利/死亡)、`start_game()` 新开局、**`resume_run()` 读档即消费**(再退再存,崩溃不复活旧档)。

恢复走 `main.resume_run()`:镜像 `start_game` 的重建路径但不走 `init_character` 重置 —— 先 `init_character(char, weapon)` 再用存档字段**覆盖** → `player.restore_weapons(levels, evolved)`(绕过 `gain_weapon` 的首获「军械」加成,否则恢复一次涨一级)→ `_randomize_map(saved_style)` → spawner 四字段回填 → `_respawn_wave_boss()`。**玩家位置不入档**(实体不存),恢复点与开局一致(`BOUND.get_center()`)。`_respawn_wave_boss` 是防软锁的关键:第 12 波存档退出时终极 Boss 随实体消失,不重排叉就永远等不到通关目标 —— 中 Boss 按 `boss_kills` 计数决定补不补,终极一律补。

**`has_suspend()` 必须走完整校验,不能只查文件存在**:坏档(解析失败 / `version != META_VERSION` / `char_id` 不在 `CHARACTERS`)会让主菜单显示「继续游戏」却恢复不出任何东西。实现是 `return not load_suspend().is_empty()`,而 `load_suspend()` 三条坏档判据都顺手 `clear_suspend()` —— 所以构建主菜单时坏档即被清掉。调用点只有 `hud.show_menu()`,重复解析一次文件的成本可忽略。

主菜单:有档 → 「继续游戏」(绿)+「重新开始」(弹确认层,明示覆盖将删档);无档 → 原「开始游戏」。确认框盖在 `state` 仍为 `MENU` 的菜单上,键盘独占在 `_unhandled_input` 的 MENU 分支**之前** gate 掉并 `return`(W/S 切按钮、空格/Enter 确认、ESC 取消);`_clear_all()` 必须把 `_menu_confirm_screen`/`_menu_confirm_btns`/`_menu_confirm_sel` 一并清空,否则悬空引用会让 gate 永久吞掉菜单输入(同 `_cx_closing` 那类坑)。

**成就 `ACHIEVEMENTS`(11 条,全局共享)**:解锁态存 `meta.cfg` 的 `achievements`,`char_wins` 记五角色通关集合,`META_VERSION=2` 让旧 v1 档迁移时有默认值。钩子全挂在既有事件点,不新增轮询:`enemy.die()`/`boss.die()`(击杀类)、`spawner._start_wave()`(波次/时长类)、波结束(无伤类,读 `wave_took_damage`,该标记在 `player.take_damage` 过无敌帧/圣盾判定后才置位)、`player.evolve_weapon()`(进化)、`on_final_boss_defeated()`(通关)、`deposit_run_coins()`(bank500/all_chars 兜底,胜利与死亡两条结算路都走)、`add_curse()` 内 `curse_level >= CURSE_MAX`(curse_max)。`unlock_achievement()` gate `test_mode`,弹 `hud.announce_achievement()` toast(`PROCESS_MODE_ALWAYS` + `TWEEN_PAUSE_PROCESS`,解锁可能落在升级/商店暂停帧)。图鉴第 5 tab「成 就」条目 id 前缀 `"ach_"`。

**原子写** `_save_atomic(cfg, path)`:先 `cfg.save(path + ".tmp")` 再 `DirAccess.open("user://").rename(...)`,关窗中断只留半截 tmp。注意 `DirAccess.remove_absolute`/`rename_absolute` **不认 `user://` scheme 路径**,必须 `DirAccess.open("user://")` 后用 `.get_file()` 的裸文件名。

**回归自检 `--resume-check`**(`main._resume_check()`):`resume_run()` 是唯一 autopilot 覆盖不到的路径(test_mode 不落盘 → 菜单永无「继续」),改 `save_suspend`/`load_suspend`/`resume_run`/`restore_weapons` 任一函数后必跑。15 项断言:落盘与 `has_suspend`、恢复后 `state=PLAYING`、运行态往返、重抽计数往返、build 往返(`weapon_levels`/`stat_levels` 精确比,`item_mods` 是 float 过 ConfigFile 文本序列化按 1e-4 容差比)、**超限层数往返**(int dict 精确比)、武器节点重建且全部有效、hp 往返、地图风格往返、诅咒值往返、波间事件往返、读档即消费、恢复后跑 30 帧 `invalid=0`、第 12 波终极 Boss 叉重摆、坏档清除。自检会反复覆写 `suspend.cfg`,故开头备份玩家真实档(若有)、结尾还原。

### 刷怪:波次制(参照土豆兄弟)

`spawner.gd` 的 `const WAVES` 是 **12 波**定死配置 `[duration, density, [七种怪的权重], boss]`(density 只/秒)。波内按密度持续刷到波时长走完,波结束**清场**(残怪 `die_without_reward`,不计击杀/不掉奖励)后进波间商店。第 4/8 波刷中 Boss,第 12 波刷**双 Boss**(中 Boss + 终极 Boss `make_final()`,击杀终极即 `VICTORY`)。上限 `MAX_ENEMIES=240`(计数含预警叉 `_telegraphs`)。

**Boss 必须打完才推进**(2026-09-10 用户指定):波时长一到只是**停止刷杂兵**(不再凭空添敌)并取消尚未落地的杂兵预警叉,场上残敌与 Boss 留着打,Boss 死了才 `_clear_wave()` + 进店。判据是 `_boss_pending()`(场上有活 Boss **或** Boss 叉未落地 —— 后者漏掉就等于 Boss 在标叉阶段被静默取消,又回到"悄悄消失")。`_wave_over` 标记这段等待期,**故意不入 `suspend.cfg`**:它可由 `_wave_timer >= duration` 现场重推,恢复后第一帧自动回到 true,存盘反而多一份真相(`--resume-check` 15 项验证过)。

原行为是 Boss 也一起 `die_without_reward`,代价是实测出来的(kite/困难,波 4):中 Boss 打到 **611/1200** 就凭空消失 —— 不计击杀、白丢 20 宝石 + 红药 + 48 金币,且 **BGM 卡在 boss 轨约 90s**(`play_bgm("battle")` 只在 `boss.die()` 里,`die_without_reward` 不切轨)。新语义与波 12「终极 Boss 击杀才通关」统一。**DPS 不够时不存在软锁**:Boss 一直在动一直打人,打不死它就被它打死,走死亡结算 —— kite/困难实测波 4 的 1200 血 Boss 在波时长后多打约 20s 被击杀(t=80 落地 → t=120 剩 39 血 → t=130 已进波 5)。

**`find_boss()` / `boss_alive()` / `wave_time_left()` 是单一真相源**(`game_manager.gd`):HUD Boss 血条、autopilot 战报、spawner 的波末门槛、`boss.die()` 的 BGM 切换、HUD 波次倒计时**共读同一份**,别处不要再写"遍历 enemies 找 boss.gd"的拷贝 —— 加第三个消费方时三份必然漂移,症状是"血条没了但波次不推进"这类自相矛盾。`wave_time_left()` 读 `GameManager.wave_time`(入档的那个)而非 `spawner._wave_timer`,与 `WAVES` 的 duration 列共源,改时长不会出现"倒计时归零但波没结束"。

**波次标签带倒计时**(`hud._update_wave_label()`):`波次 4/12 · 18s` → 最后 5 秒转橙 → Boss 收尾期改显 `· 击败首领` → 第 12 波追加 `· 终`。加它的直接原因是用户实测反馈"场上还有怪却跳商店,选完怪全没了"当成 bug —— 波末清场本身是设计("打完一波松口气"的节奏,商店是奖励不是打断),但 HUD 原先只给波次序号、**零预告**,于是设计读起来像故障。标签宽 70 → 110(x265..375,左上血条到 x=158、右上击杀数从 x=552 起,两侧仍空余充足)。缓存 `_wave_label_last` 与 `_curse_last` 同纪律:`_clear_all` 必须一并清,否则新 HUD 波次与上次相同(都是波 1)时倒计时被缓存吃掉不刷。

**权重数组是 7 宽,与 `ENEMY_BASE`/`ENEMY_VISUAL` 的键一一对应**:史莱姆 / 蝙蝠 / 巨魔 / 骷髅 / 炎魔小鬼 / 爆裂魔 / 盾卫巨魔。加新怪要同时改这三处 + `ENEMY_DROPS` + 12 行的 `WAVES` 权重(数组长度不齐会静默错位,`_draw` 按下标取 kind)。

**精英怪**(`ELITE_BASE`,`roll_elite()`):**第 4 波起、且这只怪已带词缀**才可能升格(无词缀的白怪永不精英),基础概率随波次 2% → 4%(≥6 波)→ 6%(≥9 波),再乘诅咒与波间事件的放大。数值:血 ×2.6 / 伤 ×1.6 / 视觉 ×1.35,但**碰撞半径只 ×1.15**(`hit_r`),否则出现"看着没碰到也掉血";第二词缀用 `roll_enemy_affix2()` **剔除已抽到的那条**再均匀抽(同词缀叠加会出"分裂+分裂"生 4 只子代、"再生+再生"后者覆盖前者)。掉 3 枚各 12 金币 + 1/4 概率掉宝箱。

**精英字段在池复用时必须无条件重置**:`enemy.gd` 的 `setup()` 里 `is_elite = elite` 之类若写成条件赋值,会出现"普通怪带紫光环 + 2.6 倍血"。加新的池化实体字段时同理 —— 先想清楚 release→acquire 之后旧值还在不在。

**敌人掉经验:宝石「颗数」与「每颗值」分开算**(`enemy.gd` 的 `spawn_gems`,2026-09-10 修)。颗数 = `maxi(int(xp_value), …)` 只决定视觉密度、图鉴「经验宝石 ×N」文案与忍者蛙「拾穗」每颗回血频率;**每颗的值 = `xp_value / count`**,这样所有宝石的 xp 之和精确等于 `xp_value`。原先每颗写死 `1.0`,`int()` 把小数静默截掉,两处数值不诚实:(a) 词缀怪 ×1.3 经验对 xp=1~2 的主流杂兵**完全无效**(史莱姆 1.3→1、骷髅 2.6→2),图鉴明写「词缀怪经验 ×1.3」玩家却拿不到 —— 风险给了回报没给;(b) 分裂子代 ×0.5 让 xp=1 的怪变 0.5→`int`→**0 颗**,图鉴说「经验减半」实为「经验清零」。摊到每颗后总量补回,颗数与拾穗节奏不变 => 只补该给的经验不改手感。经验咽喉仍在 `gem.collect()`(`× xp_mult()`),与 `coin.collect()` 对称,`spawn_gems` 只负责把 `xp_value` 忠实拆成几颗。**改 `spawn_gems` 后必跑 `--affix-check`**(断言 9b 直接数 spawn_gems 新增宝石的 xp 字段之和 == `xp_value`)。

### 难度

**只作用敌人侧,永不削弱玩家**。`difficulty_hp_mult`(0.75/1.0/1.30)、`difficulty_damage_mult`(0.70/1.0/1.35)、`difficulty_spawn_mult`(1.40/1.0/0.75,乘到刷怪间隔)。`普通=1.0` 是已调校的平衡基线(god 自测 ~320s 通关)。**三档实测(2026-09-10,god 通关)**:简单 340.4s kills 354 / 普通 340.5s kills 530 / 困难 339.3s kills 646 —— 通关时长被固定波次时长主导,三档几乎一样(339~340s)是设计使然,难度差体现在 **kills 密度**(简单刷怪间隔 ×1.40 最稀、困难 ×0.75 最密),不是通关快慢。hard kite **不是稳赢**(2026-09-10 五样本实测:3 VICTORY 340~357s / 2 DIED 207~297s,死亡均在非 Boss 波 bgm=battle,是杂兵把龟缩玩家耗死)—— 旧文档"55000 帧也通关(358.2s)"是单次跑恰好赢了被当结论记下。龟缩能通是品类特性(土豆兄弟同),但困难档下约 40% 概率死在波 7~10,不算失衡也不算稳过,真实死亡覆盖归 `--death-check`。测试覆盖走 `--difficulty <0|1|2>`(只改内存不落盘)。另有随时间爬坡的 `enemy_hp_mult`/`enemy_speed_mult`/`enemy_damage_mult`/`spawn_interval`,注释里写了每档的实测依据与触顶时间,改前先读。

### 两个风险旋钮:诅咒值 + 波间事件(互相正交)

难度是**开局选的**,这两个是**局内长出来的**。共同设计原则:**加压与回报成对出现,绝不给玩家负面属性**(不移速、不降上限)—— 代价全部体现在敌人身上,直接可感;也因此 `player.item_mods` 通道与 HUD 的 `STAT_MOD_LABELS` 白名单对它们零改动。

- **`curse_level`(0–`CURSE_MAX=10`,run 级)** —— 玩家**主动买**的永久(本局)放大。加层唯一入口是 `add_curse(n)`(夹取后广播 `main.on_curse_changed()` 刷 HUD,**GameManager 不直接摸 UI**,与 `trigger_level_up` 同法);生产调用点只有 `buy_shop_offer()` 里 `kind="curse"` 的契约项,`main.gd` 的两处是自检 fixture。超卖判据是 `curse_level + value > CURSE_MAX`(`>` 不是 `==`,商店卖的东西必须全额生效)。`curse_max` 成就钩在**值实际变化之后**(顶格再加不重复弹)。HUD 右上金币下方有诅咒标签(`curse_level==0` 隐藏,`_curse_last` 缓存避免每帧改 text)。
- **`WAVE_CURSES`(8 条)→ `wave_curse: Dictionary`** —— **被动抽**的单波扰动。`spawner._start_wave()` 调 `roll_wave_curse()` 掷一条整波生效,`_clear_wave()` 与 `reset_run()` 调 `set_wave_curse("")` 清零(事件同属波级状态,跨局必清)。8 条:怒潮 / 贪食 / 铁壁 / 狂化 / 贫瘠 / 静谧 / 血月 / 虚空(**显示名以 `WAVE_CURSES` 表为准**:是「静谧」「虚空」,不是宁静/虚无)。**双向设计**:每条既有压你的面也有喂你的面(怒潮=敌快但金币×2、贪食=更密但经验×1.8、静谧=密度-35% 且整波零收益=喘息波),**没有纯惩罚事件** —— 纯负随机让玩家觉得被系统针对,双向才是"这波怎么打"的决策素材。

**因子键全部「省略即中性」**:`wc_f(key, def)` 走 `wave_curse.get(key, def)`,所以 8 行各只写自己动的 1~2 个旋钮(`hp`/`dmg`/`spd` 乘子、`density` 密度乘子(>1 更密,咽喉处**除**到间隔上)、`affix`/`elite` 掷骰概率乘子、`barage` Boss 环形弹幕加发数、`coin`/`xp` 收益乘子、`crit` 暴率加值、`drop_add` 掉率加点、`drop_mult` 掉率乘子)。

**一套系数两个入口**:每个 `curse_xxx_mult()` 都只 `return curse_xxx_mult_at(curse_level) * wc_f(对应键, 中性值)`。`_at(lv)` 版本是给图鉴/商店"预览第 N 层效果"用的,不带 `_at` 的给运行时用 —— 改系数只改 `_at` 一处,两条路自动同步。接入点全在 `enemy_hp_mult` 之类的既有咽喉函数末尾乘一层(与难度档同构,**零新调用链**)。

存档:`suspend.cfg` 的 `run` 段存 `curse`(int)与 `wave_curse`(**只存 id 字符串**,恢复时 `set_wave_curse(id)` 重建字典 —— 存整字典会让数据表和存档各有一份真相)。

### 角色 / 武器 / 升级

`CHARACTERS` **五角色**(蓝帽小子 apprentice / 粉红壮汉 paladin / 忍者蛙 priest / 面具客 assassin / 只因信徒 xiaoheizi),各带起始武器 + 属性倍率 + 被动。**武器七种**(`wand` 能量弹 / `orbit` 旋刃 / `aura` 圣环 / `dagger` 飞刀 / `shuriken` 手里剑 / `holy_water` 圣水 / `lightning` 闪电),继承 `weapon_base.gd`,子类只实现 `_do_attack()`,等级从 `player.weapon_levels[id]` 读。`UPGRADES` 九类通用强化**各 3 级**。**`EVOLUTIONS` 是核心爽点**:满级武器 + 满级配对被动 → 进化武器(如 wand + proj_speed 满级 → 奥术星雨)。三选一由 `roll_upgrade_options()` 按权重抽取,`apply_upgrade()` 分发到 `player.gain_weapon`/`evolve_weapon`/`gain_stat`/`gain_overlimit`。

**升级三选一带重抽**:`LEVELUP_REROLL_MAX=2` 次/局,计数在 `GameManager.levelup_rerolls`(每局 `main` 里重置为 0,入 `suspend.cfg` 的 `run` 段)。HUD 用完后**置灰不隐藏**(按钮留着提示"曾经有这个能力"),并弹 `_lvlup_toast("已重抽 · 剩 N 次")`。注意这与 autopilot 的 `REROLL_TRIES=16` 是两码事:后者是测试驱动内部重摇取最高档位,不动界面、不消耗玩家次数。

**`ITEMS` 代价道具系统已整体删除**(表与 `player.gain_item()` 都没了)。原本的"负修正换强化"语义被两处接替:风险面归诅咒/波间事件(见上节),proc 面归 `EVOLUTION_TRAITS`(见下节)。

**`OVERLIMIT` 无限成长兜底(2026-09-09)**:常规池是**可被抽干**的(7 武器 Lv3 + 9 被动 Lv3 + 7 进化 ≈ 20+ 次选择),而经验曲线 `xp_to_next()` 永不封顶 → 后期会反复弹「没有更多强化」的空三选一。故 `roll_upgrade_options()` 在加权抽完之后**补位到 3 张**:常规池非空时超限项**不进池**(前期不稀释正常手感),池抽干后三张全是超限,升级永远有得点。6 项(damage/attack_speed +5%、cooldown -3%、move_speed +3%、pick_range +10% 每层,max_hp 是 flat 例外 +10 上限并回 10 血),幅度刻意压到常规被动的 ~1/5(超限是细水长流,不是第二个常规池)。

**层数存 `player.overlimit_levels`,绝不写回 `stat_levels`** —— 后者同时是常规池准入(`stat_levels[u] < max_level`)与进化前置的判据,把无限层数混进去会让满级被动重新进池 + 伪造进化前置成立,门槛语义全坏。键名与 `UPGRADES` 故意同名,这样各实时倍率函数只需在 `(1.0 + stat_levels[k]*x + _overlimit(k))` 通道里多并一项。`cooldown` 超限折进既有 `clampf(..., 0.2, 1.0)`,叠到 1000 层总攻速仍锁 5×。选项字典保留 `next_level`/`max_level` 字段(`max_level=0` 表示不封顶),autopilot `_opt_tier` 与 hud `_option_card` 读它不崩;卡面第三分支显示「∞ 超限 · 叠至 N 层」而非 `Lv a → b`。入 `suspend.cfg` 的 `player` 段,旧档缺键默认 `{}`(不 bump `META_VERSION`)。自检 `--overlimit-check`(10 项,见「命令」)。

**武器 id ≠ 脚本名**:`player.gain_weapon()` 里有一张字面量映射表,`"orbit"` → `orbit_blade.gd`,其余六个同名。加武器必须同时改 `WEAPONS`、这张映射表、`WEAPON_DETAILS`、`EVOLUTIONS`、`WEAPON_ICONS`。辅助脚本:`burn_zone.gd`(圣水灼烧地)`/`holy_vial.gd`(圣水瓶)由 `holy_water.gd` 链式 `load`,不独立挂载。

### 状态效果(`status_fx.gd` + `WEAPON_TRAITS`/`EVOLUTION_TRAITS`)

**每把武器自带一条特性状态**,这是武器之间手感差异的主要来源(`WEAPON_TRAITS`,7 条):法杖眩晕 / 旋刃流血 / 圣环易伤 / 飞刀中毒 / 手里剑减速(3 级解锁)/ 圣水燃烧 / 闪电冰冻。

`StatusFx` 是 `RefCounted` 静态工具类(**不是 Node,不进树,不池化**),`enemy.gd` 与 `boss.gd` 各自持有一个 `_status: Dictionary`(键=状态 id,值=`{t 剩余时长, power 每跳伤害, tick 距下次结算, stacks 层数}`),调 `StatusFx.apply/tick/speed_mult/blocks_action/damage_taken_mult/tint_color`。

七种状态的机制全在 `StatusFx.CONFIG` 一张表里(`dur`/`interval`/`root`/`noact`/`tint`):冰冻(定身 1.2s + 受伤 +30%)、眩晕(定身 0.8s)、燃烧(DoT 0.5s 一跳)、中毒(可叠 3 层 DoT)、流血(可叠 3 层 DoT)、减速(速度 ×0.7)、易伤(受伤 +15%)。`slow`/`vulnerable` 的 `interval=0`(无 DoT),靠 `factor` 提供数值。

改状态时的几条约定:
- **DoT 走 `owner.take_damage(power, true)`**,第二个参数 `true` = 不触发击退(否则中毒的怪会被自己的 DoT 推着走)。
- **刷新取较长剩余而非累加**(`s["t"] = maxf(s["t"], dur)`),否则高频武器把状态时长无限叠成永久;毒/流血例外,它们叠 `stacks`(上限 3)且 `power` 取较大值。
- **多状态并存时染色取 `TINT_PRIORITY` 最高的一条**(CC > 燃烧/易伤 > 减速 > 中毒/流血),不是混色。
- `tick()` 返回速度倍率、`blocks_action()` 返回能否行动 —— 敌人侧的移动/攻击分支读这两个,别在 `enemy.gd` 里直接判 `has("freeze")`。
- Boss 有抗性:`try_proc_from_player(_status, amount, 0.4)` 的第三参 `resist=0.4` 把全局 proc 的时长压到四成(小怪不传,默认 1.0)。
- **`_status.clear()` 必须在池复用的 `setup()` 里调**,否则上一只怪的中毒/流血会跟着节点传给下一只。

**`EVOLUTION_TRAITS` 是进化后的全局 proc**(wand 冰冻 15% / orbit 中毒 25% / aura 燃烧 20%,替代已删的代价道具 `proc_*` 通道):走 `StatusFx.try_proc_from_player()`,挂在 enemy/boss `take_damage` 的**非 DoT 分支**,所以是**全局生效**(任何武器打出的直伤都能触发,不只进化那把)。同一状态多来源**只取最高概率不叠加**(`player.proc_chance` 用 `max`)。`lightning` 故意不在表里 —— 它的冰冻是脚本内连锁命中自带,不占全局通道。

**UI 颜色必须从机制表反查,不要另写一份**:`GameManager.trait_color()` 直接读 `StatusFx.CONFIG[kind]["tint"]`,保证界面标的色 == 敌人身上实际染的色。`STATUS_NAMES` 只存中文显示名(键与 `CONFIG` 一一对应),`status_name()` 对未知键回退成键名本身(不崩,便于发现拼错)。**不加"元素名/风味名"这一层** —— 机制名就是显示名(BG3 的教训:它的 vulnerabilities 在游戏内 tooltip 根本不提,等于白设计)。

**武器图标是 16×16 字符画**(`game_manager.gd` 的 `WEAPON_ICONS` + `WEAPON_ICON_PALETTE`,零素材):每张 16 行 × 16 字符,`'.'` 透明、`'#'` 冷黑描边、`'W'` 镜面高光,8 个材质族各暗/基/亮三段(大写 = 基色)。光从左上来;实体武器描边,能量体(法杖青晶/闪电)不描边靠发光。`weapon_icon_texture()` 宽高从数据派生不硬编码;`_ready()` 的 `_validate_weapon_icons()` 校验行长与字符合法性(不合格 `push_warning`)。HUD 最小槽 16×16 即 1:1,32×32 详情槽整数 2×。

**成就图标同法**(`ACHIEVEMENT_ICONS` + `ACHIEVEMENT_ICON_PALETTE`,键与 `ACHIEVEMENTS` 一一对应):16×16 字符画,`'#'`/`'W'` 与武器色板同值,其余为成就专用族(血红/深渊紫/金/银/木棕/青晶)。`achievement_icon_texture()` 同构渲染 + 缓存;`_ready()` 的 `_validate_achievement_icons()` 除行长/字符合法性外还校验**表对齐**(每条成就有图标、无孤儿键)。消费三处:图鉴成就 tab 列表项与左页立绘(`_cx_entry_icon` 的 `ach_` 分支)、解锁 toast(`announce_achievement(id, name)` 带图标 HBox,签名含 id)。解锁与否不靠图标变色,靠列表副标与左页状态行。

**两套商店不是一回事,都在用**:局外永久强化商店 `show_shop()`(主菜单进入,花 `bank` 永久金币,读 `META_UPGRADES` 六项,**不改 state**,靠 `shop_screen != null` 判定);波间一次性商店 `show_wave_shop()`(每波清场后由 `main.open_wave_shop()` 进入,`state = SHOP`,花本局 `coins`,读 `SHOP_OFFERS` 抽 **5** 件,关闭推进下一波;稀有度配色与抽中权重读 `SHOP_RARITY_WEIGHT`)。结算时本局 `coins` 存入 `bank`。

玩家属性不缓存成字段,全部走**实时倍率函数**(`damage_mult()`/`cooldown_mult()`/`attack_speed_mult()`/`proj_speed_mult()`),武器每帧读。加新强化项就在 `player.stat_levels` 加键 + 加一个倍率函数。

### 图鉴(codex,hud.gd)

游戏图鉴 = **五分类**(`hud.CX_TAB_NAMES` = 角色 / 武器 / BOSS / 杂兵词缀 / 成就),**全部条目可见**(无解锁门禁、无持久化,纯教学手册读静态表;成就 tab 例外,它读 `meta.cfg` 的真实解锁态)。入口:主菜单「游戏图鉴」按钮 + 游戏内设置面板「图鉴」(仅 `is_playing` 显示)。数据源全部读 `GameManager` 的共享表,**不走快照**:角色/武器读 `CHARACTERS`/`WEAPONS`/`EVOLUTIONS`/`UPGRADES`,杂兵/Boss 读 `ENEMY_BASE`/`ENEMY_DROPS`/`BOSS_BASE`/`BOSS_FINAL`(这些表同时被 `enemy.gd`/`boss.gd` 读,改数值只改一处)。角色页的人话文案另存 `CODEX_CHARS`(`tag` 定位标签 / `play` 上手指引 / `key` 关键要点,**只存文案不存数值**,数值一律从 `CHARACTERS` 实时读,改数值不会出现图鉴与实战对不上;三项缺失时界面自动跳过该行)。Boss 登场波次/血量由 `boss_waves()`/`boss_hp_for()` 读 `spawner.WAVES` 现场派生;杂兵首波由 `enemy_first_wave()` 派生;词缀解锁波次(`ENEMY_AFFIXES[k].unlock`)同时驱动 `roll_enemy_affix()` 的 `affix_pool()`,展示与刷怪不漂移。

图鉴条目 id 约定:角色/武器=裸表键, Boss=`"mid"`/`"final"`, 杂兵=`"en%d"`, 词缀=`"af_"+id`(前缀 `en`/`af_` 加 `substr` 偏移,前缀碰撞会静默串类,改时对比 `_cx_entry_ids` 与各 dispatch)。自检:`--codex-check` 走查全 tab,`codex_self_check()` 用 `get_content_height()` 量数值列是否被裁;**截图 `--codex-shot` 必须用带窗口 exe**(headless 全黑),产物 `_codex_shots/tab0..4.png` + `tab4_unlocked.png`(内存态全解锁重刷成就 tab,`test_mode` 不落盘)+ `tab4_tail.png`(列表滚到底看后几个图标)+ `flip_mid.png`。

**视觉:图书馆古籍风(暖棕木桌 + 烛光)。**详情区是一本摊开的双页书(`_cx_book`,局部坐标全 `CX_` 常量),左页=立绘+名称+数值表,右页=背景文案;左侧条目列表是索引卡。三层结构:封面 `_cx_cover_style()`(皮革棕)/ 双页 `_cx_build_page()`(纸 `TextureRect` + `MarginContainer`,右页 `flip_h`)/ 书脊 `_cx_build_spine()`;`_cx_page_flip`(`CodexPageFlip` inner class)是 `_cx_book` **最后一个子节点**盖住两页。贴图走 `_cx_baked_tex()` 加载 `assets/ui/codex_{desk,page,spine}.png`,**缺失静默回退平色**(`CX_PAPER_FALLBACK`/`CX_LEATHER` 等)。

**三类翻页动效**:切条目单页方向翻(`_cx_start_flip(dir,1)`,内容在 `p>=0.5` 切,`_cx_refresh_detail` 永远读最新 `_cx_sel`)、切分类三连翻(`CX_TAB_FLIPS`)+ 书签丝带 `_cx_ribbon` 换色、开/合书(`_cx_book_open_anim`/`_on_codex_close` 用 pivot 在书脊 + scale.x)。打断策略=杀旧 tween 开新。三个 tween 全 `TWEEN_PAUSE_PROCESS`。合书期间 `_cx_closing` gate 吞掉全部输入,`_clear_all` 必须重置它(否则 autopilot/restart 打断后下次进图鉴输入被永久吞)。**自检/截图置 `_cx_anim_enabled=false` 走直刷路径**(翻页 `_cx_start_flip` 的 `force=true` 才无视此标志)。旧霓虹 BBCode(浅色)在纸底上不可读 → 运行时 `_cx_inkify()` 重映射成墨色(`CX_INK_*`),**不改 `_cx_stats_lines`/`_cx_prose_lines` 字面量与共享表**(`WEAPON_DETAILS`/`CODEX_BOSSES` 的内联色标还被角色选择屏复用)。翻页声程序合成:见 `game_manager.gd` 的 `page_sfx_stream`/`play_page_sfx`(滤波噪声 → `AudioStreamWAV`,零素材)。

### UI:`hud.gd`(~230KB / ~5740 行,项目最大文件)

一个 `CanvasLayer`,所有界面都是 `Control` 树代码构建,靠 `_clear_all()` 全清后重建(`queue_free` + 引用置 null)。复用 helper:`_full_screen()`、`_label(text, size)`、`_make_btn(text, accent)`、`_make_stat_row()`、`_style_slider()`、`_make_bar()`。改按钮/滑条外观改 helper 即可全局生效。

界面根节点存成员变量(`game_hud`/`char_screen`/`levelup_screen`/`settings_screen`/`boss_bar`/`gameover_screen`/`victory_screen`),`_clear_all` 必须一并置 null,否则下次访问悬空节点。

输入走 `_unhandled_input` + 各 Control 的 `process_mode = PROCESS_MODE_ALWAYS`,按 `GameManager.state` 分支 gate。按键约定:**空格 = 确认/重开,ESC = 进设置/返回菜单,R = 游戏内与死亡界面重开,Tab = 折叠/展开左上「本局加成」面板(仅 PLAYING)**。ESC 进设置时把来源状态记到 `GameManager.settings_return_state`,关闭时据此恢复(PLAYING→解暂停回战斗,MENU→回主菜单…)。

血条/经验条布局全从常量派生(`BAR_X`/`BAR_W`/`BAR_HP_H`/`BAR_XP_H`/`BAR_GAP` → `BAR_HP_Y`/`BAR_XP_Y`),改间距只改 `BAR_GAP`。

**左上「本局加成」面板**(`_buffs_panel`,读 `player.item_mods` 里**在 `STAT_MOD_LABELS` 白名单内且非零**的项,无加成隐藏;白名单同时给出中文名与 `pct`/`flat` 格式 —— **往 `item_mods` 写新键必须同时进白名单,否则数值生效但面板上看不到**):VBox = 标题行(「本局加成」+ 右对齐「Tab 收起」,仅展开态)+ 正文 RichTextLabel。展开宽 `BAR_W` 与血条左缘对齐、项数截断到 `BUFFS_SHOW_MAX`(超出追加 `…(+N)`);折叠只剩一行「N 项」+ 窄宽 `BUFFS_COLLAPSED_W`,由 `_toggle_buffs_panel()` 切换,折叠态会话内保持(不持久化、`_clear_all` 不清 `_buffs_collapsed`)。改展示上限/宽度只改这两个常量。

### 美术管线

**640×360 逻辑分辨率 → 2× 整数放大到 1280×720 窗口**(`stretch/mode="canvas_items"` + `scale_mode="integer"`,全局 Nearest 过滤)。

**素材不再统一 32×32**(旧规矩已被多来源素材打破):角色/史莱姆/蝙蝠 32×32,巨魔 64×32,骷髅 52×54,0x72 三怪 16×16 / 16×23 / 32×36,Boss 32×36。**帧格尺寸写在 `ENEMY_FRAMES`/`BOSS_FRAMES`/`CHAR_FRAMES` 表里,视觉大小统一靠 `ENEMY_VISUAL` 的每 kind `scale` 调**(16px 格放大到 ~2.0、骷髅格内美术偏大缩到 0.62),`offset` 把脚底对齐到碰撞圆心。所以加新怪的正确姿势是:量清源 sheet 的真实帧格 → 填表 → 用 `ENEMY_VISUAL` 配平视觉重量,**不要去改素材文件的像素**。`ENEMY_VISUAL` 的 `offset` **必须无条件复位**(池复用否则骷髅的 -3 会飘到史莱姆身上)。

- **精灵表整张入 `res://`,不切文件**:`resource/pixel32/*.png`(37 个 sheet,两套来源:Pixel Adventure 的角色/史莱姆/蝙蝠/巨魔,0x72 Dungeon Tileset II v1.7 的骷髅/小鬼/爆裂魔/盾卫/Boss/道具)。`TEXTURES` 表映射 key→路径(前缀统一是 `PIXEL_BASE = "res://resource/pixel32/"`),`ENEMY_FRAMES`/`BOSS_FRAMES`/`CHAR_FRAMES` 声明 `[动画名, sheet 键, 帧宽, 帧高, fps]`,由 `frames_for()` 用 `AtlasTexture` region 取帧生成 `SpriteFrames`,**帧数 = sheet 宽 / 帧宽**(改表帧数自动生效,不用改代码)。加新怪/新动画只改表,不写取帧代码。
- **实体用 `AnimatedSprite2D`**,朝玩家移动时 `play("run")` + `flip_h`;受击闪用 `modulate` 不用换帧(所以 `skull_hit` 故意不接线 —— `enemy.gd` 从不 `play(&"hit")`,声明了反而在兜底路径埋雷)。**动画名字面量必须叫 `"run"`**(`enemy.gd` 固定 `play(&"run")`),源 sheet 没有 run 动画就借 idle/fly 帧顶上(蝙蝠用 `bluebird_fly`、骷髅用 `skull_idle`)。骷髅那张 sheet 的真实帧宽是 52px 不是 32(`416/32=13` 也整除但会切错位)。
- **地图离线烘焙**:`map_preview/generate_map.py`(Python + PIL)生成两种风格的地面成品图 → `assets/maps/ground_map_<i>.png`。运行时 `_load_baked_ground` 直接贴图,**零运行时生成成本**;文件缺失才回退到 `main.gd` 里的程序化草地。`MAP_STYLE_COUNT=2`,每局随机一张。改地图跑 `python map_preview/generate_map.py`。**障碍物机制已于 2026-09-08 整体删除**(代码/资产/生成器全清,地面图本身不画障碍,删除不影响烘焙管线),不要重新引入。**`map_preview/` 只剩生成器,不留产物**:预览图是临时目检用,不要提交(见「注意」)。现有脚本:`generate_map.py`(地面)、`generate_menu_bg.py`(主菜单背景)、`generate_codex_bg.py`(图鉴木桌/纸页/书脊,跑 `--seed 7`)、`generate_xiaoheizi_template.py`(只因信徒角色精灵,读 `resource/xiaoheizi1.png` 立绘 + `resource/xioaheizi_run.png` 跑步帧两个原型;**run 源文件名是 `xioa` 不是 `xiao`**,两个原型图当前都在)、`generate_dungeon_monsters.py`(把 0x72 Dungeon Tileset II 的逐帧散图 PIL 水平拼成单表 → `resource/pixel32/`,**产物是运行时素材不是临时目检图**;源 zip 路径写死在脚本内 `ZIP` 常量,zip 移走过就要改)、`analyze_char_style.py`(逐帧输出包围盒/调色板/RLE,新角色验收用)、`dump_char_pixels.py`(生成 `docs/角色精灵像素全录.md`,**该产物当前不在 docs/ 里**,需要时重跑)。
- **贴图缺失时静默回退**成 `circle_texture()` 纯色圆形(不报错)。所以素材没显示先查 `.import` 是否生成、`TEXTURES` key 是否拼对。
- **`resource/` 是混合目录,别一刀切**:
  - `resource/pixel32/` **是运行时目录**(`PIXEL_BASE = "res://resource/pixel32/"`),**无 `.gdignore`,会被导入**,删不得。
  - `kenney_cc0/` 与 `bgm_cc0/` 内含 `.gdignore`,Godot **不导入**(避免 950+ PNG 拖慢编辑器启动)。要用就复制到 `assets/` 干净路径(原路径含中文/空格,Godot 加载会失败)。
  - `xiaoheizi1.png`/`xioaheizi_run.png`(各 ~2.5MB)是 `generate_xiaoheizi_template.py` 的原型输入,**必须保留**。
  - 授权清单见 `resource/CREDITS.md`(0x72 三怪与 boss_idle 的 CC0 来源、源 zip 路径都记在里面)。
- **`resource/pixel32_terrain/` 已于 2026-09-07 删除**:`GK_*` 素材来自 PixelSRPG-Forge,上游作者自述"不清楚所有素材的版权状态",且可能受 RPG Maker 引擎条款约束,而代码里零引用(唯一读取者 `preview_real_tiles.py` 同批删除)。**不要重新引入该套素材**,需要地形贴图换 Kenney CC0。

### 音频管线

`assets/audio/` 下 12 个真实 CC0 `.ogg`(3 轨 BGM:`bgm_menu`/`bgm_battle`/`bgm_boss`;9 个 SFX:`sfx_{shoot,hit,kill,hurt,death,levelup,pickup,select,elite}`),来源与授权见 `resource/CREDITS.md` 与同目录 `LICENSE_kenney.txt`。

**靠文件名约定加载,没有素材表**:`play_sfx(name)` 拼 `res://assets/audio/sfx_%s.ogg`、`play_bgm(track)` 拼 `bgm_%s.ogg`,`ResourceLoader.exists()` 不通过就**静默 return**(加新音效只要按命名丢文件进去,不用改代码;反之拼错名字也不报错,听不到先查文件名)。SFX 每次 new 一个 `AudioStreamPlayer`、`finished` 后 `queue_free`,带 **30ms 同名节流**(`_sfx_last`)与 **0.9–1.1 随机 pitch** 防机关枪感。BGM 是**单例常驻播放器**,`_bgm_current == track` 直接 return(切场景不重启同一轨),`volume_db = -6.0` 压低于 SFX,`stream.loop = true` 三轨都循环。

**唯一还程序合成的是图鉴翻页声**:`page_sfx_stream`/`play_page_sfx`(滤波噪声 → `AudioStreamWAV`,零素材)。图标类贴图同理仍走字符画(见上)。

## GDScript 易踩坑(本项目实测踩过)

- **`:=` 不能推断 Variant**:从字典/数组取值(如 `WAVES[i]`、`Settings.difficulty` 之外的动态结构)推断会报 `Cannot infer the type`,必须写显式类型 `var is_last: bool = ...`。
- **lambda 引用的变量必须先声明**:先写 `var vol_val := ...` 再写 `connect(func(): vol_val.text = ...)`,但 `add_child` 的顺序仍可后置以保持视觉顺序。反过来写报 `Identifier not declared`。
- **同一文件内 const 不能重名**:角色选择和升级卡片都在这一个文件里,常量需加前缀区分(`CHAR_COLS` vs `LVL_CARD_W`)。
- **`HSlider` 的抓手是 icon 不是 stylebox**:必须 `add_theme_icon_override("grabber", tex)`,`add_theme_stylebox_override` 对抓手无效。填充段则靠 `grabber_area` stylebox 染主题色,否则填充完全看不出来。
- **Godot 4.6 的 `RichTextLabel` 没有 `scroll_vertical` 属性**(int/float 赋值都报 `Invalid assignment`):滚动走 `get_v_scroll_bar().value`(Range,自带夹取)。
- **`get_meta(key, default)` 带默认值仍会打 ERROR 日志**(key 不存在时):先 `has_meta(key)` 再取。
- 一个脚本 Parse Error 会级联成别处的 `Nonexistent function`(脚本没加载成功),看到这类报错先回头查解析错误。
- **`trait` 是 GDScript 保留字,`var trait` 只在脚本 load 时报错**:写进局部变量名(哪怕只是个特性状态 id 字符串)会让整个脚本加载失败,而 `--import` 只查 Parse Error 查不出这条 —— 必须靠 headless `--autostart` 或任一自检跑起来才会暴露。本项目 `--weapon-check` 里就差点用 `var trait` 存特性 id,绕开成 `tkind`。同理避开其它保留字(如 `enum`/`class`/`signal` 等),变量名拿不准就加前缀。
- **比值法断言的基准必须含全部既有通道**:自检里用「加层前后比值」验证倍率时,base 只算常规通道、漏算已有超限层,会在前置步骤随机落过同键时假失败(`--overlimit-check` 断言 4 的 1/6 概率 flaky,2026-09-10 批量回归抓到;20 连跑验证修复)。随机前置 + 精确比值 = 间歇假失败,写断言时先问「此刻这个值已经含几条通道」。
- **`Input.parse_input_event` 只入队不派发**:合成事件在**下一帧的输入阶段**才到 `_unhandled_input`,自检里发完键不 `await get_tree().process_frame` 就读选择索引,读到的是派发前旧值(`--menu-check` 首跑 9 项假失败的根因)。连带坑:**含 await 的函数被裸调(不写 await)会在第一个 await 点立即返回**,调用方一行都不等 —— 修了 `_press_key` 不修调用点等于没修。
- **树外新控件赋 `.size` 会被陈旧 min-size 钳高**(2026-09-09 左上血条/经验条重叠的真因):未入树控件的 theme 退化为引擎默认字号 16,`size` 赋值瞬间被 `get_combined_minimum_size()` 夹下限(ProgressBar 带百分比文字 min 高≈27、Label min 高≈23)且**不自愈**;树外 `update_minimum_size()` 也不可靠(theme 未初始化)。唯一可靠写法:`add_child` 前后均可 `set_deferred("size", ...)`,在入树后、当帧渲染前冲刷,第一帧即正确无闪烁(`_make_bar` 与战斗 HUD 五个 Label 已照此修)。连带约束:**Label 的设计高必须 ≥ 字号真实行高**(8→12、10→14、11→16),否则被行高钳住 —— 故 `BAR_HP_H=16`/`BAR_XP_H=10`、波次标签高 16。

## 注意

`README.md` 已于 2026-11-05 为 GitHub 发布重写(面向访客:下载入口、玩法总览、AI 工作流展示、素材授权),技术细节与纪律仍以本文件为准。仓库根已加 `.gitignore`:`.godot/`、`export/`、`_ui_shots/`、`_codex_shots/`、`resource/kenney_cc0|bgm_cc0/`、`map_preview/*.png` 产物、`pm-data.json|backups/|.claude/` 均不入库;README 截图固化在 `docs/screenshots/`(带 `.gdignore`,Godot 不导入)。exe(107MB,超 GitHub 100MB 单文件限)经 GitHub Release 附件分发。

### 调试产物纪律(2026-09-07 清理的直接教训)

**项目里任何 `.png`/`.jpg`/`.ogg` 都会被 Godot 导入** —— 每次 `--import` 多生成一个 `.import` 文件 + 一份 `.godot/imported/` 缓存。调试截图随手丢项目根目录,几天就堆出 191 个 `.import`、23M 缓存(清理后是 53 个 / 9.7M)。规矩:

- 临时目检图**不要落在 `assets/` 或项目根**,放系统临时目录(`$TMP`),或用完即删。`assets/` 只放运行时真正 `load` 的素材。
- `map_preview/` 只留 `.py` 生成器,产物(`*_2x.png`、`map_*.png`、`_*.png`)是一次性的,别提交。
- `_codex_shots/` 由 `--codex-shot` 按需生成,**整个目录可删**(一条命令重建)。
- 音频/素材 zip 解包进 `assets/` 后**原 zip 就可以删**,`resource/CREDITS.md` 只记来源名不依赖原包。
- 删完素材务必跑 `--import` 重建缓存,再跑一遍 autopilot 冒烟确认没删掉运行时真在用的东西。

已删且**不要再加回来**的:`assets/audio_tmp/`(代码零引用,音频走 `assets/audio/`,它一个目录就贡献 63 个 `.import`)、`resource/*.zip` ×4、`resource/pixel32_terrain/`、`assets/maps/ground_map.png` 与 `obstacles.json`(无索引旧版,运行时只读 `ground_map_%d.png`)、`map_preview/generate_menu_bg_plain.py`(被 `generate_menu_bg.py` 取代)、`map_preview/preview_real_tiles.py`(唯一读 pixel32_terrain)、`map_preview/generate_xiaoheizi.py`(被 `generate_xiaoheizi_template.py` 取代;当前在用的 `char_xiaoheizi_*.png` 是 template 版产出的)。

**`resource/xiaoheizi1.png` 与 `resource/xioaheizi_run.png` 必须保留** —— 是 `generate_xiaoheizi_template.py` 的立绘/跑步原型输入,删了脚本崩(注意 run 源文件名是 `xioa` 不是 `xiao`)。

**`map_preview/` 残留清单**(删除属红线,需用户确认):可删的是 `__pycache__/`、`xiaoheizi_template_compare.png`(+`.import`)、`xiaoheizi_template_sheets_8x.png`(+`.import`)—— 后两者是 `generate_xiaoheizi_template.py` 每次重跑都会再生的目检输出。**`_old_xiaoheizi_idle.png`(+`.import`)不能删**:它是 2026-09-07 前手绘版角色表的唯一备份(项目无 git),脚本读它做 compare 预览(「只在备份不存在时写」),旧描述「代码零引用」是错的。
