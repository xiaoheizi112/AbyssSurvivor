extends Node
## GameManager (Autoload) — 全局运行态 + 静态数据表(角色/升级/难度曲线/音效接口)
## 单例名: GameManager

# ---------- 世界几何常量(640×360 逻辑分辨率, 32×32 图块) ----------
# 单一真相源: 视口/图块/战场/碰撞半径全项目引用此处, 不写魔法数字
const VIEW_W := 640
const VIEW_H := 360
const TILE := 32
const WORLD_W := 800
const WORLD_H := 450
const BOUND := Rect2(0, 0, WORLD_W, WORLD_H)
const PLAYER_RADIUS := 10.0
# 地图风格数(离线烘焙的地图成品图 ground_map_<i>.png, i = 0..MAP_STYLE_COUNT-1)
const MAP_STYLE_COUNT := 2
# 波次制(参照土豆兄弟): 固定 12 波, 通完即胜; 每 4 波一个 Boss(4/8/12), 第 12 波双 Boss 且终极 Boss 击杀通关
const WAVE_COUNT := 12

# ---------- 游戏状态机 ----------
enum State { MENU, CHARACTER_SELECT, PLAYING, SHOP, LEVEL_UP, SETTINGS, GAME_OVER, VICTORY, CODEX }
var state: int = State.MENU

# ---------- 运行态引用(由 main.gd 注入) ----------
var player: Node2D = null
var camera: Camera2D = null
var main: Node = null

# ---------- 实体列表(由 main.gd / spawner 维护, 供武器与碰撞使用) ----------
var enemies: Array = []
var gems: Array = []
var coins_list: Array = []   # 金币掉落物(与经验宝石分离)
var projectiles: Array = []  # 所有飞行物(玩家弹 + Boss 敌弹)

# ---------- 战斗数据 ----------
var coins: float = 0.0       # 本局已拾取金币(结算时存入永久金币 bank)
var time_s: float = 0.0
var wave: int = 0            # 当前波次(0 表示尚未开局, 首帧拉起到 1)
var wave_time: float = 0.0   # 当前波已进行时长(秒)
var kills: int = 0
var boss_kills: int = 0
var level: int = 1
var xp: float = 0.0
var final_boss_spawned: bool = false   # 本局终极 Boss 是否已登场(防止重复触发胜利)

# 设置界面来源状态: ESC 进设置时记录, 关闭时据此恢复(游戏内直接回 PLAYING, 主菜单回 MENU)
var settings_return_state: int = State.MENU

# 图鉴来源状态: 同 settings_return_state 的做法, 关闭时回来源(主菜单→MENU, 设置→SETTINGS)
var codex_return_state: int = State.MENU

# ---------- 当前角色 / 武器 ----------
var current_character: String = "apprentice"
var current_weapon: String = "wand"   # 角色选择界面选定的起始武器(供 autopilot 重开沿用)

# ---------- 相机震动 ----------
var _shake: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_validate_weapon_icons()
	_validate_achievement_icons()
	# 隔离判据取「反向」而非白名单枚举: **带任何用户参数(-- 之后)即测试跑**, 永久存档只读不写。
	# 枚举标志的失败模式是静默的 —— 新增一条自检忘了往表里加, 那一跑就会写真档, 且没有任何报错。
	# 实测代价: --overlimit-check 曾漏在表外, 自检跑以 test_mode=false 完整执行, 解锁成就 +
	# deposit_run_coins 落盘, 玩家真实 meta.cfg 被测试数据灌到 bank=62 万+ 且原值不可恢复
	# (2026-09-09 排查)。反向判据让今后新增的测试标志天然安全。
	# 真实游玩(run.bat / 编辑器 F5)不带用户参数 => test_mode 保持 false, 照常存档。
	test_mode = not OS.get_cmdline_user_args().is_empty()
	_load_meta()


# ================= 视觉工具 =================
# 优先用 Kenney 纹理, 缺失时回退到程序化圆形
var _circle_cache := {}
var _tex_cache := {}

# 贴图映射 — 整张精灵表入 res://, 用 SpriteFrames+AtlasTexture region 取帧(不切文件)
# 素材来源: resource/pixel32/ = Pixel Adventure 套(32×32 系) + 0x72 Dungeon Tileset II 拼接表
# (imp/chort/ogre 六张, 由 map_preview/generate_dungeon_monsters.py 从 zip 拼出, 见 CREDITS.md)
const PIXEL_BASE := "res://resource/pixel32/"
const TEXTURES := {
	"char_apprentice_idle": PIXEL_BASE + "char_apprentice_idle.png",
	"char_apprentice_run":  PIXEL_BASE + "char_apprentice_run.png",
	"char_apprentice_hit":  PIXEL_BASE + "char_apprentice_hit.png",
	"char_paladin_idle": PIXEL_BASE + "char_paladin_idle.png",
	"char_paladin_run":  PIXEL_BASE + "char_paladin_run.png",
	"char_paladin_hit":  PIXEL_BASE + "char_paladin_hit.png",
	"char_priest_idle": PIXEL_BASE + "char_priest_idle.png",
	"char_priest_run":  PIXEL_BASE + "char_priest_run.png",
	"char_priest_hit":  PIXEL_BASE + "char_priest_hit.png",
	"char_assassin_idle": PIXEL_BASE + "char_assassin_idle.png",
	"char_assassin_run":  PIXEL_BASE + "char_assassin_run.png",
	"char_assassin_hit":  PIXEL_BASE + "char_assassin_hit.png",
	"char_xiaoheizi_idle": PIXEL_BASE + "char_xiaoheizi_idle.png",
	"char_xiaoheizi_run":  PIXEL_BASE + "char_xiaoheizi_run.png",
	"char_xiaoheizi_hit":  PIXEL_BASE + "char_xiaoheizi_hit.png",
	"mushroom_idle": PIXEL_BASE + "mushroom_idle.png",
	"mushroom_run":  PIXEL_BASE + "mushroom_run.png",
	"mushroom_hit":  PIXEL_BASE + "mushroom_hit.png",
	"bluebird_fly":  PIXEL_BASE + "bluebird_fly.png",
	"bluebird_hit":  PIXEL_BASE + "bluebird_hit.png",
	"trunk_idle":    PIXEL_BASE + "trunk_idle.png",
	"trunk_run":     PIXEL_BASE + "trunk_run.png",
	"trunk_attack":  PIXEL_BASE + "trunk_attack.png",
	"trunk_hit":     PIXEL_BASE + "trunk_hit.png",
	"skull_idle":    PIXEL_BASE + "skull_idle.png",
	"skull_hit":     PIXEL_BASE + "skull_hit.png",
	# 0x72 Dungeon Tileset II v1.7 拼接表(见 map_preview/generate_dungeon_monsters.py 与 CREDITS.md)
	"imp_idle":      PIXEL_BASE + "imp_idle.png",
	"imp_run":       PIXEL_BASE + "imp_run.png",
	"chort_idle":    PIXEL_BASE + "chort_idle.png",
	"chort_run":     PIXEL_BASE + "chort_run.png",
	"ogre_idle":     PIXEL_BASE + "ogre_idle.png",
	"ogre_run":      PIXEL_BASE + "ogre_run.png",
	"boss_idle":     PIXEL_BASE + "boss_idle.png",
	"bullet":        PIXEL_BASE + "bullet.png",
	"gem":           PIXEL_BASE + "gem.png",
	"heart":         PIXEL_BASE + "heart.png",
	"chest":         PIXEL_BASE + "chest.png",
}

# 怪物动画表: kind -> [ [动画名, sheet 键, 帧宽, 帧高, fps], ... ]
const ENEMY_FRAMES := {
	0: [["idle", "mushroom_idle", 32, 32, 8.0],
		["run", "mushroom_run", 32, 32, 12.0],
		["hit", "mushroom_hit", 32, 32, 10.0]],
	1: [["run", "bluebird_fly", 32, 32, 12.0],
		["hit", "bluebird_hit", 32, 32, 10.0]],
	2: [["idle", "trunk_idle", 64, 32, 10.0],
		["run", "trunk_run", 64, 32, 10.0],
		["attack", "trunk_attack", 64, 32, 12.0],
		["hit", "trunk_hit", 64, 32, 10.0]],
	# 骷髅: sheet 是 416×54 / 帧宽 52 → 8 帧(416/32=13 也整除但会切错位, 52 是实测帧宽)
	# "run" 借用 idle sheet —— enemy.gd 固定 play(&"run"), 动画名字面量必须叫 "run"
	# (沿用蝙蝠 kind 1 用 bluebird_fly 当 run 的先例)
	# skull_hit 不接线: enemy.gd 从不 play(&"hit")(受击走 modulate 闪白, 四种怪一致),
	# 且该 sheet 美术只占格高 18~24px, 声明了反而在兜底路径上埋雷
	3: [["idle", "skull_idle", 52, 54, 8.0],
		["run", "skull_idle", 52, 54, 12.0]],
	# 0x72 新三怪(吐息/自爆/护盾): idle/run 各有真动画 sheet, 不必借帧
	4: [["idle", "imp_idle", 16, 16, 8.0],
		["run", "imp_run", 16, 16, 12.0]],
	5: [["idle", "chort_idle", 16, 23, 8.0],
		["run", "chort_run", 16, 23, 12.0]],
	6: [["idle", "ogre_idle", 32, 36, 8.0],
		["run", "ogre_run", 32, 36, 10.0]],
}

# 每 kind 的基准视觉缩放/偏移(在词缀 size 与精英 size 之前先乘)
# 骷髅格内美术 ~50×53px(帧格 52×54), scale=1 会比其他怪大一圈 → 缩到与史莱姆同视觉重量
# 0/1/2 全为 1.0 → 现有三怪零行为变化; offset 必须无条件复位(池复用否则骷髅的 -3 会飘到史莱姆身上)
const ENEMY_VISUAL := {
	0: {"scale": 1.0, "offset": Vector2.ZERO},
	1: {"scale": 1.0, "offset": Vector2.ZERO},
	2: {"scale": 1.0, "offset": Vector2.ZERO},
	3: {"scale": 0.62, "offset": Vector2(0, -3)},
	# 0x72 新三怪: 16px 格放大到与 32px 怪同视觉重量(scale≈2);
	# offset 把脚底对齐到碰撞圆心附近(素材默认朝右, 帧格底部 = 脚)
	4: {"scale": 2.0, "offset": Vector2(0, -5)},
	5: {"scale": 2.0, "offset": Vector2(0, -9)},
	6: {"scale": 1.0, "offset": Vector2(0, -6)},
}

const BOSS_FRAMES := [
	["idle", "boss_idle", 32, 36, 6.0],
	["hit",  "boss_idle", 32, 36, 10.0],
]

# 玩家角色动画表: char_id -> [ [动画名, sheet 键, 帧宽, 帧高, fps], ... ]
# 职业 → 卡通角色映射: apprentice→Virtual Guy, paladin→Pink Man, priest→Ninja Frog, assassin→Mask Dude
const CHAR_FRAMES := {
	"apprentice": [["idle", "char_apprentice_idle", 32, 32, 8.0],
		["run", "char_apprentice_run", 32, 32, 12.0],
		["hit", "char_apprentice_hit", 32, 32, 10.0]],
	"paladin": [["idle", "char_paladin_idle", 32, 32, 8.0],
		["run", "char_paladin_run", 32, 32, 12.0],
		["hit", "char_paladin_hit", 32, 32, 10.0]],
	"priest": [["idle", "char_priest_idle", 32, 32, 8.0],
		["run", "char_priest_run", 32, 32, 12.0],
		["hit", "char_priest_hit", 32, 32, 10.0]],
	"assassin": [["idle", "char_assassin_idle", 32, 32, 8.0],
		["run", "char_assassin_run", 32, 32, 12.0],
		["hit", "char_assassin_hit", 32, 32, 10.0]],
	"xiaoheizi": [["idle", "char_xiaoheizi_idle", 32, 32, 8.0],
		["run", "char_xiaoheizi_run", 32, 32, 12.0],
		["hit", "char_xiaoheizi_hit", 32, 32, 10.0]],
}

func texture_for(key: String) -> Texture2D:
	if _tex_cache.has(key):
		return _tex_cache[key]
	if TEXTURES.has(key) and ResourceLoader.exists(TEXTURES[key]):
		var tex: Texture2D = load(TEXTURES[key])
		_tex_cache[key] = tex
		return tex
	return null


func circle_texture(radius: int, color: Color) -> Texture2D:
	var key := "%d_%s" % [radius, color.to_html()]
	if _circle_cache.has(key):
		return _circle_cache[key]
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(size):
		for x in range(size):
			var dx := float(x - radius)
			var dy := float(y - radius)
			if dx * dx + dy * dy <= float(radius * radius):
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_circle_cache[key] = tex
	return tex


func sprite_with_circle(radius: int, color: Color, tex_key: String = "") -> Sprite2D:
	var s := Sprite2D.new()
	if tex_key != "":
		var tex := texture_for(tex_key)
		if tex != null:
			s.texture = tex
			return s
	s.texture = circle_texture(radius, color)
	return s


# 由整张精灵表构建 SpriteFrames(region 取帧, 不切文件); 结果缓存
# specs = [ [动画名, sheet 键, 帧宽, 帧高, fps], ... ]
var _frames_cache := {}

func frames_for(cache_key: String, specs: Array) -> SpriteFrames:
	if _frames_cache.has(cache_key):
		return _frames_cache[cache_key]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for s in specs:
		var tex: Texture2D = texture_for(str(s[1]))
		if tex == null:
			continue
		var anim: String = str(s[0])
		var fw: int = int(s[2])
		var fh: int = int(s[3])
		sf.add_animation(anim)
		sf.set_animation_speed(anim, float(s[4]))
		sf.set_animation_loop(anim, true)
		var n: int = int(tex.get_width()) / fw
		for i in range(n):
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(float(i * fw), 0.0, float(fw), float(fh))
			sf.add_frame(anim, at)
	_frames_cache[cache_key] = sf
	return sf


# 角色选择界面用: 取该角色 idle 动画首帧(AtlasTexture 32×32), 供 Control 显示
# 缓存避免每次重建
var _char_preview_cache := {}

func char_preview_texture(char_id: String) -> Texture2D:
	if _char_preview_cache.has(char_id):
		return _char_preview_cache[char_id]
	var idle_spec: Array = CHAR_FRAMES[char_id][0]
	var sheet: Texture2D = texture_for(str(idle_spec[1]))
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(0.0, 0.0, float(int(idle_spec[2])), float(int(idle_spec[3])))
	_char_preview_cache[char_id] = at
	return at


# ================= 武器图标(程序化像素, 零资源) =================
# 16×16 像素图标(HUD 最小槽即 16×16 → 1:1; 32×32 详情槽整数 2×), Nearest 显示保持锐利。
# 字符画映射色板(见 WEAPON_ICON_PALETTE): '#' 冷黑描边 / 'W' 镜面高光 / '.' 透明,
# 8 个材质族各 暗/基/亮 三段(大写 = 基色, 沿用旧 8 色板字符与色值)。
# 光从左上来: 实体武器外缘一圈 '#' 描边 + 三段色阶 + 左上点 W;
# 能量体(法杖青晶 / 闪电)不描边, 靠三段色 + 孤立亮点表现自发光。
# 每张必须 16 行 × 16 字符, 字符 ∈ 色板 ∪ '.' —— _ready() 里有校验, 不合格 push_warning。
const WEAPON_ICONS := {
	# 斜置法杖: 青晶在右上(能量体→无描边), 金箍, 木杆 45° 到左下
	"wand": [
		"............CC..",
		"...........yCCc.",
		"..........yWCCc.",
		".........yWWCCCc",
		".........yWCCCc.",
		"..........yCCCc.",
		"...........yCc..",
		".........#gGq#..",
		"........#gGq#...",
		".......#hDd#....",
		"......#hDd#.....",
		".....#hDd#......",
		"....#hDd#.......",
		"...#hDd#........",
		"..#hDd#.........",
		"..#####.........",
	],
	# 十字旋刃: 臂宽 6px(描边 1 + 本体 4), 中心 4×4 白热核; 上/左受光 v, 下/右背光 u
	"orbit": [
		".....######.....",
		".....#vvBu#.....",
		".....#vvBu#.....",
		".....#vBBu#.....",
		".....#vBBu#.....",
		"######vBBu######",
		"#vvvvvWWWWvvvvv#",
		"#vvvvvWWWWvvvvv#",
		"#BBBBBWWWWBBBBB#",
		"#uuuuuWWWWuuuuu#",
		"######uuuu######",
		".....#BBuu#.....",
		".....#BBuu#.....",
		".....#BBuu#.....",
		".....#BBuu#.....",
		".....######.....",
	],
	# 圣环: 正圆环(旧版是方环), 外径 16 / 中心孔 8, 环壁等厚 4px。
	# 金三段色: 左上弧 g + 3px 镜面反光块, 主体 G, 右下弧 q; 外缘一圈 '#' 描边,
	# 孔内壁也压暗成 q(环是立体的, 内圈背光), 孔本身镂空透背景。
	"aura": [
		"......#gg#......",
		"....#gggggg#....",
		"..#gWWgGGGGGq#..",
		".#WggGGGGGGqqq#.",
		"#ggGq......GGqq#",
		"#gGq........Gqq#",
		"#gGq........Gqq#",
		"#GGq........Gqq#",
		"#Gqq........Gqq#",
		"#qqq........qqq#",
		"#qqq........qqq#",
		"#qqqq......qqqq#",
		".#Gqqqqqqqqqqq#.",
		"..#qqqqqqqqqq#..",
		"....#qqqqqq#....",
		"......#qq#......",
	],
	# 垂直匕首: 银刃(左 s 受光 / W 脊线 / 右 t 背光) + 金护手 + 木柄(d 缠绳暗纹) + 金圆头
	"dagger": [
		".......WS.......",
		".....#sWSt#.....",
		".....#sWSt#.....",
		".....#sWSt#.....",
		".....#sWSt#.....",
		".....#sWSt#.....",
		".....#sWSt#.....",
		"..############..",
		"..#ggGGGGGGqq#..",
		"..#gGGGGGGqqq#..",
		"..############..",
		".....#hDDd#.....",
		".....#dDDd#.....",
		".....#hDDd#.....",
		".....#dDDd#.....",
		"....#gGGGGq#....",
	],
	# 燃烧瓶: 木塞 → 收窄瓶颈 → 玻璃瓶身(左 r 竖高光 + W 镜面点) → 内盛燃料(n 液面亮线 / 气泡)
	"holy_water": [
		".....######.....",
		".....#hhDd#.....",
		".....#hDDd#.....",
		"......#PP#......",
		"......#rP#......",
		"..#rrPPPPPPpp#..",
		".#WPPPPPPPPppp#.",
		".#rPPPPPPPPppp#.",
		".#rnnnnnnnnnnp#.",
		".#rnNNNNNNNNmp#.",
		".#rnNNNnNNNNmp#.",
		".#rnNNNNNNNNmp#.",
		".#rnNNNNNNNNmp#.",
		".#rnNNNNNNNNmp#.",
		"..#nNNNNNNNNm#..",
		"...##########...",
	],
	# 闪电: 能量体不描边, 锯齿主体左上 l 受光 / 中 L / 右下 z 背光,
	# 四周孤立 l 火花点表现放电辉光(旧 8×8 版的 2 倍宽锯齿, 折点错位保留)
	"lightning": [
		"..........ll....",
		"l........lLLl...",
		"........lLLLl...",
		".......lLLLl..l.",
		"......lLLLl.....",
		".....lLLLLl.....",
		"....lLLLLLl.....",
		"l..lLLLLLLLl....",
		"...lLLLLLLLll.l.",
		"....lLLLLLzl....",
		"......LLLzl.....",
		".l...LLLzl......",
		".....LLzl.......",
		"....LLzl........",
		"...LLzl..l......",
		"...Lzl........l.",
	],
	# 回旋镖: V 形木镖, 弯折点(握把)在上、两臂向下张开 —— 与飞行态 bullet._draw_boomerang 同一造型语言。
	# 臂横截面左 h 受光 / 中 D 基色 / 右 d 背光(光从左上, 同其余实体武器); 两臂端 W = 镖尖刃口闪光。
	# 不用 '#' 描边: 16px 下 V 形臂只有 3px 宽, 再包一圈黑会把臂压成 1px 断线, 靠三段木色自身分界即可。
	"shuriken": [
		".......WW.......",
		"......hDd.......",
		".....hDdhDd.....",
		".....hDdhDd.....",
		"....hDd..hDd....",
		"....hDd..hDd....",
		"...hDd....hDd...",
		"...hDd....hDd...",
		"..hDd......hDd..",
		"..hDd......hDd..",
		".hDd........hDd.",
		".hDd........hDd.",
		".hDd........hDd.",
		"hWd..........hWd",
		"hWd..........hWd",
		"................",
	],
}

# 26 色: '#' 冷黑描边 + 'W' 镜面高光 + 8 个材质族各 暗/基/亮 三段。
# 大写字母 = 基色(沿用旧 8 色板的字符与色值), 同族小写 = 亮/暗。光从左上来。
const WEAPON_ICON_PALETTE := {
	"#": Color(0.10, 0.10, 0.13),  # 描边(仅实体武器; 能量体不描边)
	"W": Color(1.00, 1.00, 1.00),  # 镜面高光
	# 木: 杖杆 / 刀柄 / 瓶塞
	"d": Color(0.32, 0.21, 0.10),
	"D": Color(0.55, 0.38, 0.20),
	"h": Color(0.78, 0.58, 0.34),
	# 青晶: 法杖能量核
	"c": Color(0.18, 0.52, 0.70),
	"C": Color(0.55, 0.92, 1.00),
	"y": Color(0.86, 0.98, 1.00),
	# 钢蓝: 旋刃
	"u": Color(0.13, 0.38, 0.60),
	"B": Color(0.40, 0.85, 1.00),
	"v": Color(0.76, 0.95, 1.00),
	# 金: 圣环 / 护手 / 箍
	"q": Color(0.60, 0.44, 0.10),
	"G": Color(1.00, 0.85, 0.30),
	"g": Color(1.00, 0.95, 0.62),
	# 银: 刀刃 / 飞刀
	"t": Color(0.40, 0.44, 0.53),
	"S": Color(0.82, 0.86, 0.92),
	"s": Color(0.96, 0.98, 1.00),
	# 焰液: 燃烧瓶内燃料(暗底 → 火焰橙 → 焰心金黄, 光从左上来故 n 用在左上液面)
	# 这三个键全项目只有 holy_water 一张图标在用, 改色不会串到别的武器
	"m": Color(0.55, 0.16, 0.08),
	"N": Color(1.00, 0.45, 0.12),
	"n": Color(1.00, 0.82, 0.35),
	# 玻璃: 瓶身
	"p": Color(0.52, 0.57, 0.64),
	"P": Color(0.78, 0.83, 0.89),
	"r": Color(0.94, 0.97, 1.00),
	# 电: 闪电
	"z": Color(0.26, 0.40, 0.78),
	"L": Color(0.65, 0.80, 1.00),
	"l": Color(0.93, 0.97, 1.00),
}

var _weapon_icon_cache := {}


# ================= 击杀数骷髅图标(程序化像素, 零资源) =================
# 右上角击杀数用的骷髅头字符画: 16×12 白骨架 + 黑眼眶/鼻翼/牙缝, Nearest 显示保持锐利
const SKULL_ICON := [
	"..WWWWWWWWWWWW..",
	".WWWWWWWWWWWWWW.",
	".WWKWWWWWWWWKWW.",
	".WKKWWWWWWWWKKW.",
	".WKKWWWWWWWWKKW.",
	".WWKWWWWWWWWKWW.",
	".WWWWWWWWWWWWWW.",
	"..WWWKKKKKKWWW..",
	".WWWWWWWWWWWWWW.",
	".WWWWWWWWWWWWWW.",
	"WWKWKWKWKWKWKWW.",
	".WWWWWWWWWWWWWW.",
]
const SKULL_PALETTE := {
	"W": Color(0.93, 0.93, 0.90),
	"K": Color(0.10, 0.10, 0.12),
}

var _skull_icon: Texture2D = null

func skull_icon_texture() -> Texture2D:
	if _skull_icon != null:
		return _skull_icon
	# 优先用真 32×32 卡通骷髅 PNG(CC0, OpenGameArt by FancySnacks), 缺失回退字符画
	var png := "res://assets/ui/skull_kill.png"
	if ResourceLoader.exists(png):
		_skull_icon = load(png)
		return _skull_icon
	var rows := SKULL_ICON
	var h := rows.size()
	var w := str(rows[0]).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		var row := str(rows[y])
		for x in range(row.length()):
			var ch := row.substr(x, 1)
			if SKULL_PALETTE.has(ch):
				img.set_pixel(x, y, SKULL_PALETTE[ch])
	_skull_icon = ImageTexture.create_from_image(img)
	return _skull_icon

func weapon_icon_texture(weapon_id: String) -> Texture2D:
	if _weapon_icon_cache.has(weapon_id):
		return _weapon_icon_cache[weapon_id]
	var rows: Array = WEAPON_ICONS.get(weapon_id, [])
	# 宽高从字符画派生(照 skull_icon_texture 的写法), 不硬编码 —— 改网格尺寸只改数据。
	# 未知 id 回退空表 → 8×8 全透明贴图(保持非 null 的旧契约, 消费方靠 visible 判定)
	var h := 8 if rows.is_empty() else rows.size()
	var w := 8 if rows.is_empty() else str(rows[0]).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		var row: String = str(rows[y])
		for x in range(row.length()):
			var ch := row.substr(x, 1)
			if WEAPON_ICON_PALETTE.has(ch):
				img.set_pixel(x, y, WEAPON_ICON_PALETTE[ch])
	var tex := ImageTexture.create_from_image(img)
	_weapon_icon_cache[weapon_id] = tex
	return tex

# 字符画拼写保险: 行长一致 + 字符 ∈ 色板 ∪ '.'。
# set_pixel 越界在 4.6 打 ERROR(ERR_FAIL_INDEX, 不崩但刷屏), 短行则静默留 1px 缺口造成
# 图标不对称 —— 手写 7×16 行字符画, 这是唯一的拼写保险。放 _ready() 只告警一次。
func _validate_weapon_icons() -> void:
	for wid in WEAPON_ICONS.keys():
		var rows: Array = WEAPON_ICONS[wid]
		if rows.is_empty():
			push_warning("WEAPON_ICONS[%s] 是空表" % wid)
			continue
		var w: int = str(rows[0]).length()
		for i in range(rows.size()):
			var row: String = str(rows[i])
			if row.length() != w:
				push_warning("WEAPON_ICONS[%s] 第 %d 行长 %d != 首行 %d: %s" % [wid, i, row.length(), w, row])
				continue
			for x in range(w):
				var ch := row.substr(x, 1)
				if ch != "." and not WEAPON_ICON_PALETTE.has(ch):
					push_warning("WEAPON_ICONS[%s] 第 %d 行未知字符 '%s'(不在色板)" % [wid, i, ch])


# ================= 成就图标(程序化像素, 零资源) =================
# 16×16 字符画, 键与 ACHIEVEMENTS 一一对应。光从左上来, 与 WEAPON_ICONS 同约定:
# '#' 冷黑描边 / 'W' 镜面高光 / '.' 透明; 色板独立一套(成就要红/紫等
# 武器色板没有的族, 不混进 WEAPON_ICON_PALETTE)。
const ACHIEVEMENT_ICONS := {
	"first_kill": [   # 滴血短剑: 立置, 柄上刃下, 血滴挂在刃尖
		"......#dd#......",
		"......#DD#......",
		"...#qqqqqqqq#...",
		"...#qGGGGGGq#...",
		".....#ssss#.....",
		".....#sWSs#.....",
		".....#sSSs#.....",
		".....#sSSs#.....",
		".....#sSSs#.....",
		".....#sSSs#.....",
		".....#sSSs#.....",
		"......#SS#......",
		"......#ss#......",
		".......##.......",
		"......RNNR......",
		".......RR.......",
	],
	"wave4": [   # 领主盔: 银盔 + 双角 + 黑眼缝
		"....#......#....",
		"...#S#....#S#...",
		"...#SS#..#SS#...",
		"....#SS##SS#....",
		"....#SSSSSS#....",
		"...#SSSSSSSS#...",
		"...#SssssssS#...",
		"...#SSSSSSSS#...",
		"...#SKSSSSKS#...",
		"...#SKSSSSKS#...",
		"...#SSSSSSSS#...",
		"...#SS#SS#SS#...",
		"....#S#SS#S#....",
		".....#SSSS#.....",
		"......####......",
		"................",
	],
	"wave8": [   # 深渊漩涡: 紫环旋臂 + 黑心
		"................",
		".....######.....",
		"...##vvvvvv##...",
		"..#vv......vv#..",
		".#v...MMMM...v#.",
		".#v..MMmmMM..v#.",
		"#v...MmKKMm...v#",
		"#v...MmKKMm...v#",
		".#v...MMMM...v#.",
		"..#vv......vv#..",
		"...##vvvvvv##...",
		".....######.....",
		"................",
		"................",
		"................",
		"................",
	],
	"victory": [   # 金奖杯: 杯身双耳 + 柱脚
		"....########....",
		"....#gggggg#....",
		".#..#gGGGGg#..#.",
		".#G.#GWGGGg#.G#.",
		".#G.#GGGGGg#.G#.",
		"..#.#GGGGg#..#..",
		"...##GGGGg##....",
		".....#GGg#......",
		".....#Gg#.......",
		".....#qq#.......",
		"....#qqqq#......",
		"...#qqqqqq#.....",
		"...#dddddd#.....",
		"..#dDDDDDDd#....",
		"..##########....",
		"................",
	],
	"kill500": [   # 骷髅 + 交叉骨(屠杀标记)
		"................",
		".....######.....",
		"....#SSSSSS#....",
		"...#SSSSSSSS#...",
		"...#SKSSSSKS#...",
		"...#SKSSSSKS#...",
		"...#SSSSSSSS#...",
		"....#SSKKSS#....",
		"....#S#SS#S#....",
		".S...#SSSS#...S.",
		".#S..######..S#.",
		"..#S.........S#.",
		"...#S.......S#..",
		"....##.....##...",
		"................",
		"................",
	],
	"survive300": [   # 沙漏: 金框 + 白沙 + 红沙
		"................",
		"...##########...",
		"...#rrrrrrrr#...",
		"....#rrrrrr#....",
		".....#rrrr#.....",
		"......#rr#......",
		".......##.......",
		".......##.......",
		"......#NN#......",
		".....#NNNN#.....",
		"....#NNNNNN#....",
		"...#NNNNNNNN#...",
		"...#rrrrrrrr#...",
		"...##########...",
		"................",
		"................",
	],
	"no_hit_wave": [   # 银盾 + 金勾(片叶不沾)
		"................",
		"...##########...",
		"..#SSSSSSSSSS#..",
		".#SSssssssssSS#.",
		".#Ss........sS#.",
		".#Ss.......G.s#.",
		".#Ss......G..s#.",
		".#Ss.....G...s#.",
		".#Ss....G....s#.",
		".#Ss...G.....s#.",
		"..#Ss.G.....sS#.",
		"..#SsG.....sS#..",
		"...#Ss....sS#...",
		"....#Ss..sS#....",
		".....#SssS#.....",
		"......####......",
	],
	"evolve": [   # 紫晶星爆: 八角星 + 白芯
		".......##.......",
		".......MM.......",
		"......#MM#......",
		"......#MM#......",
		"..#...#MM#...#..",
		"...#..#MM#..#...",
		"....##mMMm##....",
		"####MMmWWmMM####",
		"####MMmWWmMM####",
		"....##mMMm##....",
		"...#..#MM#..#...",
		"..#...#MM#...#..",
		"......#MM#......",
		"......#MM#......",
		".......MM.......",
		".......##.......",
	],
	"bank500": [   # 金币袋: 棕袋 + 金 G 纹 + 扎绳
		"................",
		"......####......",
		".....#dDDd#.....",
		"....#dDDDDd#....",
		"....#qqqqqq#....",
		"...#DDDDDDDD#...",
		"..#DDDDDDDDDD#..",
		".#DDD####DDDDD#.",
		".#DDD#..#DDDDD#.",
		".#DDD#GG#DDDDD#.",
		".#DDD#G.#DDDDD#.",
		".#DDD#GG#DDDDD#.",
		".#DDD####DDDDD#.",
		"..#DDDDDDDDDD#..",
		"...#DDDDDDDD#...",
		"....########....",
	],
	"all_chars": [   # 五角色头像环: 蓝/粉/白/黑 四色 + 中银
		"................",
		"......####......",
		".....#CCCC#.....",
		"....#CCWWCC#....",
		"..###......###..",
		".#NNN#....#RRR#.",
		"#NNNNN#..#RRRRR#",
		"#NNWNN#..#RWRWR#",
		".#NNN#....#RRR#.",
		"..###..##..###..",
		"......#SS#......",
		".....#SWWS#.....",
		".....#SSSS#.....",
		"..##..#SS#..##..",
		".#WW#.....#KK#..",
		"..##.......##...",
	],
	"curse_max": [   # 深渊宠儿: 银颅戴紫冠(三尖冠 + K 宝石), 区别于 kill500 的交叉骨骷髅
		"................",
		"....M...MM...M..",
		"..#MMMMMMMMMM#..",
		"..#KMMMMMMMMK#..",
		"..############..",
		".....######.....",
		"....#WSSSSS#....",
		"...#WSSSSSSS#...",
		"...#SKSSSSKS#...",
		"...#SKSSSSKS#...",
		"...#SSSSSSSS#...",
		"....#SSKKSS#....",
		"....#S#SS#S#....",
		".....#S##S#.....",
		"......####......",
		"................",
	],
}

# 成就图标色板: '#'/'W' 与武器色板同值(视觉统一), 其余为成就专用族
const ACHIEVEMENT_ICON_PALETTE := {
	"#": Color(0.10, 0.10, 0.13),  # 描边
	"W": Color(1.00, 1.00, 1.00),  # 镜面高光
	# 银: 剑刃 / 盔 / 盾 / 骨
	"t": Color(0.40, 0.44, 0.53),
	"S": Color(0.82, 0.86, 0.92),
	"s": Color(0.96, 0.98, 1.00),
	# 金: 奖杯 / 护手 / 盾勾 / 袋绳
	"q": Color(0.60, 0.44, 0.10),
	"G": Color(1.00, 0.85, 0.30),
	"g": Color(1.00, 0.95, 0.62),
	# 血/沙红: 血滴 / 沙 / 粉头像
	"R": Color(0.85, 0.20, 0.22),
	"N": Color(0.95, 0.45, 0.40),
	"n": Color(1.00, 0.72, 0.66),
	# 深渊紫: 漩涡 / 星爆; K=涡心黑洞; v=外环亮紫
	"M": Color(0.55, 0.25, 0.80),
	"m": Color(0.75, 0.50, 0.95),
	"v": Color(0.85, 0.70, 1.00),
	"K": Color(0.10, 0.08, 0.14),
	# 白沙: 沙漏上腔(与武器色板玻璃亮同值的近白)
	"r": Color(0.94, 0.97, 1.00),
	# 木棕: 剑柄 / 奖杯脚 / 钱袋
	"d": Color(0.32, 0.21, 0.10),
	"D": Color(0.55, 0.38, 0.20),
	"h": Color(0.78, 0.58, 0.34),
	# 青晶: 蓝帽头像
	"c": Color(0.18, 0.52, 0.70),
	"C": Color(0.55, 0.92, 1.00),
	"y": Color(0.86, 0.98, 1.00),
}

var _achievement_icon_cache := {}


# 成就图标贴图: 与 weapon_icon_texture 同构(宽高从字符画派生, 缓存复用)。
# 未知 id 回退 8×8 全透明(保持非 null 契约, 消费方靠 visible/texture 判定)。
func achievement_icon_texture(ach_id: String) -> Texture2D:
	if _achievement_icon_cache.has(ach_id):
		return _achievement_icon_cache[ach_id]
	var rows: Array = ACHIEVEMENT_ICONS.get(ach_id, [])
	var h := 8 if rows.is_empty() else rows.size()
	var w := 8 if rows.is_empty() else str(rows[0]).length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		var row: String = str(rows[y])
		for x in range(row.length()):
			var ch := row.substr(x, 1)
			if ACHIEVEMENT_ICON_PALETTE.has(ch):
				img.set_pixel(x, y, ACHIEVEMENT_ICON_PALETTE[ch])
	var tex := ImageTexture.create_from_image(img)
	_achievement_icon_cache[ach_id] = tex
	return tex


# 与 _validate_weapon_icons 同款拼写保险: 行长一致 + 字符 ∈ 色板 ∪ '.',
# 外加表对齐(每条成就有图标 / 无孤儿键)
func _validate_achievement_icons() -> void:
	for aid in ACHIEVEMENT_ICONS.keys():
		var rows: Array = ACHIEVEMENT_ICONS[aid]
		if rows.is_empty():
			push_warning("ACHIEVEMENT_ICONS[%s] 是空表" % aid)
			continue
		var w: int = str(rows[0]).length()
		for i in range(rows.size()):
			var row: String = str(rows[i])
			if row.length() != w:
				push_warning("ACHIEVEMENT_ICONS[%s] 第 %d 行长 %d != 首行 %d: %s" % [aid, i, row.length(), w, row])
				continue
			for x in range(w):
				var ch := row.substr(x, 1)
				if ch != "." and not ACHIEVEMENT_ICON_PALETTE.has(ch):
					push_warning("ACHIEVEMENT_ICONS[%s] 第 %d 行未知字符 '%s'(不在色板)" % [aid, i, ch])
	for aid in ACHIEVEMENTS.keys():
		if not ACHIEVEMENT_ICONS.has(aid):
			push_warning("成就 %s 缺图标字符画" % aid)
	for aid in ACHIEVEMENT_ICONS.keys():
		if not ACHIEVEMENTS.has(aid):
			push_warning("ACHIEVEMENT_ICONS[%s] 无对应成就定义(孤儿键)" % aid)


# ================= 波间商店图标(程序化像素, 零资源) =================
# 12×12 字符画, 键与 SHOP_OFFERS 的 kind 一一对应; 商店卡/价格金币图标共用
const SHOP_ICON_PALETTE := {
	"W": Color(0.93, 0.93, 0.90),   # 白高光
	"G": Color(0.72, 0.50, 0.10),   # 暗金边
	"Y": Color(1.0, 0.82, 0.25),    # 金面
	"R": Color(0.90, 0.28, 0.28),   # 红(治疗/血/磁铁)
	"S": Color(0.82, 0.86, 0.92),   # 银(刃/盾边/尖刺)
	"B": Color(0.35, 0.65, 0.95),   # 盾蓝
	"L": Color(0.55, 0.80, 1.0),    # 电蓝(速度类)
	"D": Color(0.45, 0.30, 0.16),   # 握柄棕
	# 深渊紫(诅咒): 与 ACHIEVEMENT_ICON_PALETTE 的 M/v/K 同值, 全项目"深渊"只有一个紫
	"P": Color(0.55, 0.25, 0.80),   # 颅骨基色
	"p": Color(0.85, 0.70, 1.00),   # 左上高光
	"K": Color(0.10, 0.08, 0.14),   # 眼窝/鼻腔空洞
}

const SHOP_ICONS := {
	"heal": [   # 红十字 + 左上白高光
		"............",
		"....RRRR....",
		"....RWRR....",
		"....RRRR....",
		"....RRRR....",
		"..RRRRRRRR..",
		"..RWRRRRRR..",
		"..RRRRRRRR..",
		"....RRRR....",
		"....RRRR....",
		"....RRRR....",
		"............",
	],
	"magnet": [   # U 形磁铁: 银白极尖 + 红双腿
		"..WW....WW..",
		"..WW....WW..",
		"..RR....RR..",
		"..RR....RR..",
		"..RR....RR..",
		"..RR....RR..",
		"..RR....RR..",
		"..RRRRRRRR..",
		"...RRRRRR...",
		"...RRRRRR...",
		"....RRRR....",
		"............",
	],
	"shield": [   # 盾: 银边蓝面 + 左上高光
		".SSSSSSSSSS.",
		".SBBBBBBBBS.",
		".SBWWBBBBBS.",
		".SBWWBBBBBS.",
		".SBBBBBBBBS.",
		".SBBBBBBBBS.",
		"..SBBBBBBS..",
		"...SBBBBS...",
		"....SBBS....",
		".....SS.....",
		"............",
		"............",
	],
	"greed": [   # 三层金币叠
		"....GGGG....",
		"...GYYYYG...",
		"...GYWYYG...",
		"...GYYYYG...",
		"....GGGG....",
		"..GGGGGGGG..",
		".GYYYYYYYYG.",
		".GYYWYYYYYG.",
		"..GGGGGGGG..",
		".GGGGGGGGGG.",
		"GYYYYYYYYYYG",
		"GGGGGGGGGGGG",
	],
	"temp_damage": [   # 竖剑: 银刃白脊 + 金护手棕柄
		".....SS.....",
		".....SS.....",
		"....SWWS....",
		"....SWWS....",
		"....SWWS....",
		"....SWWS....",
		"....SWWS....",
		"....SWWS....",
		"..GGGGGGGG..",
		".....DD.....",
		".....DD.....",
		"....GGGG....",
	],
	"crit": [   # 四芒星爆
		".....WW.....",
		".....WW.....",
		"....WWWW....",
		"....WWWW....",
		".W..WWWW..W.",
		"WWWWWWWWWWWW",
		"WWWWWWWWWWWW",
		".W..WWWW..W.",
		"....WWWW....",
		"....WWWW....",
		".....WW.....",
		".....WW.....",
	],
	"curse": [   # 深渊紫颅骨: 眼窝/鼻腔/牙缝用 K(空洞), 左上 p 高光 —— 与骷髅兵同题材
		"............",
		"...PPPPPP...",
		"..PPPPPPPP..",
		"..PpPPPPPP..",
		".PPPPPPPPPP.",
		".PPKKPPKKPP.",
		".PPKKPPKKPP.",
		".PPPPKKPPPP.",
		"..PPPPPPPP..",
		"..PKPKPKKP..",
		"...PPPPPP...",
		"............",
	],
}

# 金币图标: 价格行与顶部金币计数胶囊共用
const COIN_ICON := [
	"....GGGG....",
	"..GGYYYYGG..",
	".GYWWYYYYYG.",
	".GYWYYYYYYG.",
	"GYYYYDDYYYYG",
	"GYYYDDDDYYYG",
	"GYYYDDDDYYYG",
	"GYYYYDDYYYYG",
	".GYYYYYYYYG.",
	".GYYYYYYYYG.",
	"..GGYYYYGG..",
	"....GGGG....",
]

var _shop_icon_cache := {}
var _coin_icon: Texture2D = null

# 尺寸按表动态取(同 skull_icon_texture 写法); 缺 kind 回退全透明图不崩
func shop_icon_texture(kind: String) -> Texture2D:
	if _shop_icon_cache.has(kind):
		return _shop_icon_cache[kind]
	var rows: Array = SHOP_ICONS.get(kind, [])
	var tex := _icon_from_rows(rows, SHOP_ICON_PALETTE, 12)
	_shop_icon_cache[kind] = tex
	return tex


func coin_icon_texture() -> Texture2D:
	if _coin_icon != null:
		return _coin_icon
	_coin_icon = _icon_from_rows(COIN_ICON, SHOP_ICON_PALETTE, 12)
	return _coin_icon


# 字符画 → ImageTexture 通用构建: 表空时返回 fallback_size 见方全透明图
func _icon_from_rows(rows: Array, palette: Dictionary, fallback_size: int) -> Texture2D:
	var h := rows.size()
	var w := fallback_size
	if h > 0:
		w = str(rows[0]).length()
	else:
		h = fallback_size
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(h):
		var row := str(rows[y])
		for x in range(row.length()):
			var ch := row.substr(x, 1)
			if palette.has(ch):
				img.set_pixel(x, y, palette[ch])
	return ImageTexture.create_from_image(img)


# ================= 掉落物图标(程序化像素, 零资源) =================
# 念珠/磁铁无整张贴图, 用 16×16 数学绘制像素图; 心/箱走 texture_for 真贴图
var _pickup_icon_cache := {}

func pickup_icon_texture(kind: String) -> Texture2D:
	if _pickup_icon_cache.has(kind):
		return _pickup_icon_cache[kind]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if kind == "rosary":
		_draw_rosary(img)
	elif kind == "magnet":
		_draw_magnet(img)
	var tex := ImageTexture.create_from_image(img)
	_pickup_icon_cache[kind] = tex
	return tex


# 念珠: 紫色珠环 + 中心深紫十字(白高光交叠), 宗教意象一眼识别
func _draw_rosary(img: Image) -> void:
	var center := Vector2(7.5, 7.5)
	var purple := Color(0.82, 0.45, 1.0)
	var deep := Color(0.45, 0.18, 0.58)
	var white := Color(1.0, 1.0, 1.0)
	for y in range(16):
		for x in range(16):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center)
			if d >= 4.8 and d <= 6.6:
				img.set_pixel(x, y, purple)
				continue
			var in_v := x >= 7 and x <= 8 and y >= 5 and y <= 10
			var in_h := y >= 7 and y <= 8 and x >= 5 and x <= 10
			if in_v and in_h:
				img.set_pixel(x, y, white)
			elif in_v or in_h:
				img.set_pixel(x, y, deep)


# 磁铁: 红色 U 形 + 双极白尖(上), 底部横连, 一眼识别「全屏吸宝石」
func _draw_magnet(img: Image) -> void:
	var red := Color(0.90, 0.33, 0.30)
	var white := Color(1.0, 1.0, 1.0)
	for y in range(16):
		for x in range(16):
			var leg := (x >= 3 and x <= 5 or x >= 10 and x <= 12) and y >= 3 and y <= 11
			var bottom := y >= 10 and y <= 11 and x >= 3 and x <= 12
			if leg or bottom:
				if leg and y <= 4:
					img.set_pixel(x, y, white)
				else:
					img.set_pixel(x, y, red)


# ================= 难度曲线 =================
func xp_to_next() -> float:
	# 土豆兄弟式: 经验曲线更陡(12+7/级), 前期升级不再是 6 只怪一次, 拉长发育节奏
	# 角色差异: 学徒「求知若渴」升级所需经验 -20%(更快成型)
	var base := 12.0 + float(level) * 7.0
	if current_character == "apprentice":
		base *= 0.8
	return base

func enemy_hp_mult() -> float:
	# 敌人随波次变肉(12 波依次 1.0→3.0, 每波 +0.2), 与固化波表对齐, 不再随时间漂移
	return minf(1.0 + float(maxf(wave - 1, 0)) * 0.20, 3.0)

func enemy_speed_mult() -> float:
	# 速度随波次爬升到 2.4(每波 +0.11), 后段敌人不全面超速玩家, 保留风筝空间
	return minf(1.0 + float(maxf(wave - 1, 0)) * 0.11, 2.4)

func enemy_damage_mult() -> float:
	# 第 3 波起伤害才爬升(前两波给玩家攒武器缓冲), 每波 +0.28 封顶 4.0
	return minf(1.0 + float(maxf(wave - 3, 0)) * 0.28, 4.0)

# ================= 难度倍率(仅作用敌人侧, 不削弱玩家) =================
# 普通(1)= 已调校平衡基线(320s god 通关 / 非god 78s 平均); 简单(0)弱化, 困难(2)强化
func difficulty_hp_mult() -> float:
	match Settings.difficulty:
		0: return 0.75
		2: return 1.30
		_: return 1.0


func difficulty_damage_mult() -> float:
	match Settings.difficulty:
		0: return 0.70
		2: return 1.35
		_: return 1.0


func difficulty_spawn_mult() -> float:
	# 乘到刷怪间隔: 越大越慢越简单; 困难档加快密度
	match Settings.difficulty:
		0: return 1.40
		2: return 0.75
		_: return 1.0


# ================= 诅咒倍率(敌人侧 = 风险) =================
# 每个系数都写成两个函数: xxx_at(lv) 是**纯公式**(图鉴按给定层数算, 进图鉴时当前值可能是 0),
# xxx() 转调 xxx_at(curse_level) 给战斗侧用。一套系数两个入口 —— 直接写两份数字必然在调参时漂移。
# L=0 时恒返回中性值 → 不选诅咒的玩家数值零变化。与难度档正交(难度只削敌人, 诅咒两边都加)。
# 系数取"每层可感但不致命": L=10 时 hp ×2.2 / dmg ×1.7 / speed ×1.2 / 密度 +43%。
func curse_hp_mult() -> float:
	# 战斗侧 = 诅咒层数公式 × 波间事件乘子; 图鉴侧读 _at() 保持纯公式不被事件污染
	return curse_hp_mult_at(curse_level) * wc_f("hp", 1.0)

func curse_hp_mult_at(lv: int) -> float:
	return 1.0 + float(lv) * 0.12

func curse_damage_mult() -> float:
	return curse_damage_mult_at(curse_level) * wc_f("dmg", 1.0)

func curse_damage_mult_at(lv: int) -> float:
	return 1.0 + float(lv) * 0.07

func curse_speed_mult() -> float:
	return curse_speed_mult_at(curse_level) * wc_f("spd", 1.0)

func curse_speed_mult_at(lv: int) -> float:
	return 1.0 + float(lv) * 0.02

func curse_spawn_mult() -> float:
	# 乘到刷怪间隔(与 difficulty_spawn_mult 同语义): <1 = 更密。L=10 → 0.70 → 密度 +43%
	# 事件的 density 是**密度乘子**(>1 = 更密), 故除到间隔上: 贪食 1.40 → 间隔 ×0.714
	return curse_spawn_mult_at(curse_level) / wc_f("density", 1.0)

func curse_spawn_mult_at(lv: int) -> float:
	return 1.0 - float(lv) * 0.03

func curse_affix_bonus() -> float:
	# 加到词缀概率的封顶值上(0.28 是原硬顶): L=10 → 上限 48%, 更多词缀怪。
	# 血月事件是**乘子**(封顶与实际掷骰概率都翻倍, 在 roll_enemy_affix 处消费), 这里不掺和
	return curse_affix_bonus_at(curse_level)

func curse_affix_bonus_at(lv: int) -> float:
	return float(lv) * 0.02

func curse_elite_bonus() -> float:
	# 加到精英掷骰概率上: L=10 → +12%, 配合波次档最高 6% → 约 4.1% 实际出率(词缀率 × 精英率)
	return curse_elite_bonus_at(curse_level)

func curse_elite_bonus_at(lv: int) -> float:
	return float(lv) * 0.012


# ================= 诅咒倍率(玩家侧 = 回报) =================
# 收益系数刻意高于风险系数(金币 +18%/层 vs 血量 +12%/层): 选诅咒必须是净赚, 否则没人点。
func curse_coin_mult() -> float:
	return curse_coin_mult_at(curse_level)

func curse_coin_mult_at(lv: int) -> float:
	return 1.0 + float(lv) * 0.18

func curse_drop_bonus() -> float:
	# 加到巨魔四项额外掉率上: L=10 → 红药 30%→50% / 宝箱 10%→30% / 念珠与磁铁 4%→24%
	# 铁壁事件再加 15 个点(drop_add 是加值); 静谧的 drop_mult=0 在 enemy.spawn_gems 消费端乘掉整列
	return curse_drop_bonus_at(curse_level) + wc_f("drop_add", 0.0)

func curse_drop_bonus_at(lv: int) -> float:
	return float(lv) * 0.02

# 经验倍率: 咽喉在 gem.collect() 而非 spawn_gem 生成端 —— 与 coin.collect() 的金币咽喉对称,
# 只改一处; 且不会因 enemy.spawn_gems() 的 count = int(xp_value) 导致屏幕宝石爆量
func xp_mult() -> float:
	# 战斗侧乘波间事件(贪食 ×1.8 / 虚空 ×2 / 静谧 ×0); 图鉴读 _at() 保持纯公式
	return xp_mult_at(curse_level) * wc_f("xp", 1.0)

func xp_mult_at(lv: int) -> float:
	return 1.0 + float(lv) * 0.14


# ================= 元进度(局外永久成长) =================
# 参照吸血鬼幸存者 PowerUp: 击杀→金币→局内拾取→结算入账→商店买永久强化
# 永久数据存 user://meta.cfg(与 Settings 分离, 互不干扰)

const META_PATH := "user://meta.cfg"
var _meta_cfg := ConfigFile.new()

const META_VERSION := 2        # 存档格式版本(旧档无 version 键按 v1 读, 字段全带默认值)

var bank: float = 0.0          # 永久金币余额(可跨局累积消费)
var upgrades_owned := {}       # upgrade_id -> 当前等级(0=未购买)

# 成就(全局共享, 与 bank 同存 meta.cfg): achieved/char_wins 为持久化字典
var achieved := {}             # achievement_id -> true
var char_wins := {}            # char_id -> true(通关过的角色集合, all_chars 成就用)
var wave_took_damage := false  # 本波是否受过伤(无伤过波成就用, 波开始/受击时维护)

# 成就定义: id -> { name, desc }; 检查逻辑在 check_achievements() 集中, 事件点只调它
const ACHIEVEMENTS := {
	"first_kill":  {"name": "初次见血", "desc": "击败第一个敌人"},
	"wave4":       {"name": "初见领主", "desc": "抵达第 4 波(中 Boss 登场)"},
	"wave8":       {"name": "深渊再临", "desc": "抵达第 8 波(第二个中 Boss)"},
	"victory":     {"name": "深渊幸存者", "desc": "击败终极深渊领主, 通关一次"},
	"kill500":     {"name": "屠杀机器", "desc": "单局击败 500 个敌人"},
	"survive300":  {"name": "持久战", "desc": "单局存活 300 秒"},
	"no_hit_wave": {"name": "片叶不沾", "desc": "完整撑过一波且未受任何伤害"},
	"evolve":      {"name": "超越极限", "desc": "触发一次武器进化"},
	"bank500":     {"name": "小有积蓄", "desc": "永久金币余额达到 500"},
	"all_chars":   {"name": "五面手", "desc": "用全部五个角色各通关一次"},
	"curse_max":   {"name": "深渊宠儿", "desc": "单局诅咒值达到上限 10"},
}

# 测试模式(autopilot / 各类自检 / 截图): 永久存档只读不写。
# bot 每局通关都走 deposit_run_coins(), 写盘会把测试金币灌进玩家真实 bank
# (实测已累积到 17 万+, 元进度被污染成满级), 所以测试跑一律不落盘。
# 内存态照常累加 => 商店/结算逻辑路径与真实游玩一致, 只是不持久化。
var test_mode: bool = false

# 永久强化定义: id -> { name, desc, max_level, cost_fn 变体由 cost() 出价 }
# 属性: 基础伤害 / 移速 / 拾取范围 / 初始血量 / 金币加成 / 起始武器强化
const META_UPGRADES := {
	"meta_damage":   {"name": "力量", "desc": "所有伤害永久 +8%", "max": 5, "base": 60, "step": 90},
	"meta_speed":    {"name": "迅捷", "desc": "移动速度永久 +6%", "max": 5, "base": 60, "step": 80},
	"meta_pick":     {"name": "磁力", "desc": "拾取范围永久 +15%", "max": 5, "base": 50, "step": 70},
	"meta_hp":       {"name": "体魄", "desc": "初始生命永久 +15", "max": 5, "base": 70, "step": 90},
	"meta_greed":    {"name": "贪婪", "desc": "金币获取永久 +15%", "max": 5, "base": 80, "step": 110},
	# 军械上限 1(不是 2/3): gain_weapon 的首获加成是 mini(1 + 军械, 武器满级)。
	# 原 5 级制下军械 3 → 首获 Lv4, 还差 1 级满级; 武器降到 3 级后要保持"差 1 级"这个手感,
	# 军械必须同步降到 1(首获 Lv2, Lv3 仍需局内升一次)。给 2 会让新武器一拿到就满级,
	# 等于把 Lv3 进化门槛和整个升级过程白送 —— 3 级制的质变节奏当场失效。
	"meta_weapon":   {"name": "军械", "desc": "武器初始永久 +1 级", "max": 1, "base": 200, "step": 250},
}


func _load_meta() -> void:
	if _meta_cfg.load(META_PATH) != OK:
		bank = 0.0
		upgrades_owned = {}
		achieved = {}
		char_wins = {}
		return
	bank = float(_meta_cfg.get_value("meta", "bank", 0.0))
	upgrades_owned = _meta_cfg.get_value("meta", "upgrades", {})
	achieved = _meta_cfg.get_value("meta", "achievements", {})
	char_wins = _meta_cfg.get_value("meta", "char_wins", {})
	# 无 version 键的旧档按 v1 字段读(全带默认值, 天然向后兼容)


func save_meta() -> void:
	if test_mode:
		return   # 测试跑不落盘(见 test_mode 注释); 内存态已更新, 结算路径不受影响
	_meta_cfg.set_value("meta", "version", META_VERSION)
	_meta_cfg.set_value("meta", "bank", bank)
	_meta_cfg.set_value("meta", "upgrades", upgrades_owned)
	_meta_cfg.set_value("meta", "achievements", achieved)
	_meta_cfg.set_value("meta", "char_wins", char_wins)
	_save_atomic(_meta_cfg, META_PATH)


# 原子写: 先写 .tmp 再 rename 覆盖, 关窗/崩溃中断只留半截 tmp, 不会写坏正档
func _save_atomic(cfg: ConfigFile, path: String) -> void:
	var tmp := path + ".tmp"
	if cfg.save(tmp) != OK:
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.rename(tmp.get_file(), path.get_file())


# 某永久的当前等级
# 按表内 max 夹取: 存档可能来自上限更高的旧版本(军械 3 级 → 2 级), 不夹则
# gain_weapon 的首获加成 mini(1+3, 3) 会让新武器一拿到就满级, 进化门槛直接白给。
# 夹在读口(而非改档) => 商店显示/出价/加成一次全对, 且不动玩家已有存档数据。
func meta_level(id: String) -> int:
	var maxlv: int = int(META_UPGRADES.get(id, {}).get("max", 99))
	return mini(int(upgrades_owned.get(id, 0)), maxlv)


# 某永久下一级价格(满级返回 -1)
func meta_cost(id: String) -> int:
	var def: Dictionary = META_UPGRADES[id]
	var lv := meta_level(id)
	if lv >= int(def["max"]):
		return -1
	return int(def["base"]) + lv * int(def["step"])


# 购买一级永久强化; 余额不足或已满级返回 false
func buy_meta(id: String) -> bool:
	var c := meta_cost(id)
	if c < 0:
		return false
	if bank < float(c):
		return false
	bank -= float(c)
	upgrades_owned[id] = meta_level(id) + 1
	save_meta()
	return true


# 永久加成派生(供 player 初始化与掉落结算读取)
func meta_damage_mult() -> float:
	return 1.0 + meta_level("meta_damage") * 0.08

func meta_speed_mult() -> float:
	return 1.0 + meta_level("meta_speed") * 0.06

func meta_pick_mult() -> float:
	return 1.0 + meta_level("meta_pick") * 0.15

func meta_hp_bonus() -> float:
	return meta_level("meta_hp") * 15.0

func coin_mult() -> float:
	# 局外永久「贪婪」+ 商店「贪婪」本局临时加成(玩家 item_mods["coin_mult"])
	var item: float = 0.0
	if player != null and player.has_method("_item_mod"):
		item = float(player._item_mod("coin_mult"))
	# 诅咒是**乘法**层(不是加进上面那串): 它是独立的风险旋钮, 与贪婪叠加时应相乘放大,
	# 否则"贪婪 + 诅咒"两条线互相摊薄, 玩家感受不到诅咒的收益强度
	# 波间事件同样乘在这一层: 怒潮 ×2 / 贫瘠 ×0.5 / 静谧 ×0(无收益喘息波)
	return (1.0 + meta_level("meta_greed") * 0.15 + item) * curse_coin_mult() * wc_f("coin", 1.0)

func meta_weapon_levels() -> int:
	return meta_level("meta_weapon")


# 本局金币入账(结算时调用; autopilot/重开不误加)
func deposit_run_coins() -> void:
	bank += coins
	save_meta()
	check_achievements()   # bank500 / survive300 等结算时点的成就


# ---------- 局内续玩存档(土豆兄弟式单槽, user://suspend.cfg) ----------
# 写入时机: 设置面板「保存并退出」/ 关窗自动保存; 删除时机: 结算 / 新开局 / 重新开始。
# test_mode 一律不写(冒烟测试不留档), 读不受 gate(测试跑本来就没有真档)。

const SUSPEND_PATH := "user://suspend.cfg"


# 是否有可用续玩档。**不只查文件存在**: 坏档(解析失败 / version 不符 / char_id 非法)
# 会让主菜单显示「继续游戏」却点进去啥也恢复不了, 所以这里走完整校验路径 ——
# load_suspend() 判定为坏档时自己 clear_suspend(), 返回空字典 => 菜单直接不显示继续。
# 调用点只有 hud.show_menu()(非每帧), 重复解析一次文件的成本可忽略。
func has_suspend() -> bool:
	return not load_suspend().is_empty()


# 与 save_suspend 同构的 test_mode gate: 结算(game_over/on_final_boss_defeated)与新开局
# (start_game)都会清档, 不 gate 的话**每次冒烟/自检跑都会静默删掉玩家真实的局内续玩档**
# (2026-09-10 排查死亡链路时发现; md5 隔离比对查不出, 因为 suspend.cfg 平时不存在)。
# force_test=true 旁路仅供自检删自己的夹具档 / resume_run 的读档即消费。
func clear_suspend(force_test: bool = false) -> void:
	if test_mode and not force_test:
		return
	if FileAccess.file_exists(SUSPEND_PATH):
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(SUSPEND_PATH.get_file())


# 写单槽续玩档。force_test=true 仅供 --resume-check 自检使用: 自检必须置 test_mode(否则
# 成就/meta 会落盘污染真档), 但它又要跑真实的 save→load→resume 全链路, 故开这一个旁路。
# 自检结束时自己 clear_suspend(), 不会给玩家留下「继续游戏」。
func save_suspend(force_test: bool = false) -> void:
	if test_mode and not force_test:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("run", "version", META_VERSION)
	cfg.set_value("run", "char_id", current_character)
	cfg.set_value("run", "weapon_id", current_weapon)
	cfg.set_value("run", "time_s", time_s)
	cfg.set_value("run", "wave", wave)
	cfg.set_value("run", "wave_time", wave_time)
	cfg.set_value("run", "kills", kills)
	cfg.set_value("run", "boss_kills", boss_kills)
	cfg.set_value("run", "level", level)
	cfg.set_value("run", "xp", xp)
	cfg.set_value("run", "coins", coins)
	cfg.set_value("run", "levelup_rerolls", levelup_rerolls)
	cfg.set_value("run", "curse", curse_level)
	# 当前波间事件 id(空 = 无事件): 存档只存 id 字符串, 恢复时 set_wave_curse(id) 重建字典
	cfg.set_value("run", "wave_curse", str(wave_curse.get("id", "")))
	cfg.set_value("run", "final_boss_spawned", final_boss_spawned)
	cfg.set_value("run", "rng_state", _rng.state)
	var sp: Node = main.spawner if main != null else null
	if sp != null:
		cfg.set_value("spawner", "spawn_timer", sp._spawn_timer)
		cfg.set_value("spawner", "wave_timer", sp._wave_timer)
		cfg.set_value("spawner", "interval", sp._interval)
		cfg.set_value("spawner", "weights", sp._weights)
	if main != null:
		cfg.set_value("map", "style", main._ground_style)
	if player != null:
		cfg.set_value("player", "base_max_hp", player.base_max_hp)
		cfg.set_value("player", "base_move_speed", player.base_move_speed)
		cfg.set_value("player", "base_pick_range", player.base_pick_range)
		cfg.set_value("player", "char_damage_mult", player.char_damage_mult)
		cfg.set_value("player", "char_proj_speed_mult", player.char_proj_speed_mult)
		cfg.set_value("player", "heal_mult", player.heal_mult)
		cfg.set_value("player", "hp", player.hp)
		cfg.set_value("player", "stat_levels", player.stat_levels)
		cfg.set_value("player", "weapon_levels", player.weapon_levels)
		cfg.set_value("player", "evolved_weapons", player.evolved_weapons)
		cfg.set_value("player", "item_mods", player.item_mods)
		cfg.set_value("player", "overlimit_levels", player.overlimit_levels)
	_save_atomic(cfg, SUSPEND_PATH)


# 读 suspend 档; 不存在/损坏/版本不符返回 {}(调用方回退), 坏档顺手删掉
func load_suspend() -> Dictionary:
	if not FileAccess.file_exists(SUSPEND_PATH):
		return {}
	# 三条坏档分支一律 force: 测试跑里 save_suspend 被 gate 不落盘, 能存在的 suspend.cfg
	# 只可能是自检写的夹具, 必须真删(否则「坏档已清除」断言假失败); 玩家真档在测试跑里
	# 根本不会被 load 到坏档分支之外碰到 —— 正常读档路径不删文件, 只有这三条判坏才删。
	var cfg := ConfigFile.new()
	if cfg.load(SUSPEND_PATH) != OK:
		clear_suspend(true)
		return {}
	if int(cfg.get_value("run", "version", 0)) != META_VERSION:
		clear_suspend(true)
		return {}
	var out := {}
	out["run"] = {
		"char_id": str(cfg.get_value("run", "char_id", "")),
		"weapon_id": str(cfg.get_value("run", "weapon_id", "")),
		"time_s": float(cfg.get_value("run", "time_s", 0.0)),
		"wave": int(cfg.get_value("run", "wave", 0)),
		"wave_time": float(cfg.get_value("run", "wave_time", 0.0)),
		"kills": int(cfg.get_value("run", "kills", 0)),
		"boss_kills": int(cfg.get_value("run", "boss_kills", 0)),
		"level": int(cfg.get_value("run", "level", 1)),
		"xp": float(cfg.get_value("run", "xp", 0.0)),
		"coins": float(cfg.get_value("run", "coins", 0.0)),
		# 重抽次数: 键缺失(重抽加入前的旧档)默认 0; META_VERSION 不 bump, 向后兼容
		"levelup_rerolls": int(cfg.get_value("run", "levelup_rerolls", 0)),
		# 诅咒键缺失(骷髅/诅咒加入前的旧档)默认 0 = 无诅咒局; META_VERSION 不 bump, 向后兼容
		"curse": int(cfg.get_value("run", "curse", 0)),
		# 事件键缺失(事件轮加入前的旧档)默认 "" = 无事件波, 同样不 bump 版本
		"wave_curse": str(cfg.get_value("run", "wave_curse", "")),
		"final_boss_spawned": bool(cfg.get_value("run", "final_boss_spawned", false)),
		"rng_state": int(cfg.get_value("run", "rng_state", 0)),
	}
	out["spawner"] = {
		"spawn_timer": float(cfg.get_value("spawner", "spawn_timer", 0.0)),
		"wave_timer": float(cfg.get_value("spawner", "wave_timer", 0.0)),
		"interval": float(cfg.get_value("spawner", "interval", 1.0)),
		"weights": cfg.get_value("spawner", "weights", [1.0, 0.0, 0.0, 0.0]),
	}
	# 旧档权重列数少于当前表(骷髅 4 元 / 新三怪 7 元之前的档) → 用当前波的完整配置覆盖。
	# 不补的话 _weighted_kind() 按 _weights.size() 泛化, 旧档永远刷不出新怪但不崩 ——
	# 静默的"内容缺失"比崩更难查, 所以这里直接回填成该波的标准构成。
	var w_arr: Array = out["spawner"]["weights"]
	if w_arr.size() < SPAWNER_SCRIPT.WAVES[0][2].size():
		var wv: int = clampi(int(out["run"]["wave"]), 1, SPAWNER_SCRIPT.WAVES.size())
		out["spawner"]["weights"] = SPAWNER_SCRIPT.WAVES[wv - 1][2].duplicate()
	out["map_style"] = int(cfg.get_value("map", "style", 0))
	out["player"] = {
		"base_max_hp": float(cfg.get_value("player", "base_max_hp", 100.0)),
		"base_move_speed": float(cfg.get_value("player", "base_move_speed", 180.0)),
		"base_pick_range": float(cfg.get_value("player", "base_pick_range", 60.0)),
		"char_damage_mult": float(cfg.get_value("player", "char_damage_mult", 1.0)),
		"char_proj_speed_mult": float(cfg.get_value("player", "char_proj_speed_mult", 1.0)),
		"heal_mult": float(cfg.get_value("player", "heal_mult", 1.0)),
		"hp": float(cfg.get_value("player", "hp", 100.0)),
		"stat_levels": cfg.get_value("player", "stat_levels", {}),
		"weapon_levels": cfg.get_value("player", "weapon_levels", {}),
		"evolved_weapons": cfg.get_value("player", "evolved_weapons", {}),
		"item_mods": cfg.get_value("player", "item_mods", {}),
		# 超限层数: 键缺失(无限成长加入前的旧档)默认 {} = 零层; META_VERSION 不 bump, 向后兼容
		"overlimit_levels": cfg.get_value("player", "overlimit_levels", {}),
	}
	# 关键字段缺失(角色 id 不在表里)视为坏档
	# force: 测试跑里坏档只可能是自检自己写的夹具, 必须真删掉, 否则断言「坏档已清除」假失败
	if not CHARACTERS.has(out["run"]["char_id"]):
		clear_suspend(true)
		return {}
	return out


# ---------- 成就检查(事件点统一调, 不新增轮询) ----------

func unlock_achievement(id: String) -> void:
	if test_mode or achieved.has(id):
		return
	achieved[id] = true
	save_meta()
	if main != null and main.hud != null and main.hud.has_method("announce_achievement"):
		main.hud.announce_achievement(id, ACHIEVEMENTS[id]["name"])


func check_achievements() -> void:
	if test_mode:
		return
	if kills >= 1:
		unlock_achievement("first_kill")
	if wave >= 4:
		unlock_achievement("wave4")
	if wave >= 8:
		unlock_achievement("wave8")
	if kills >= 500:
		unlock_achievement("kill500")
	if time_s >= 300.0:
		unlock_achievement("survive300")
	if bank >= 500.0:
		unlock_achievement("bank500")
	if char_wins.size() >= CHARACTERS.size():
		unlock_achievement("all_chars")


# 波间商店消费: 用本局金币买一次性增益; 余额不足返回 false
func buy_shop_offer(idx: int) -> bool:
	if idx < 0 or idx >= cur_shop.size():
		return false
	var offer: Dictionary = cur_shop[idx]
	var kind: String = str(offer["kind"])
	var value: float = float(offer["value"])
	# 诅咒商品在"加不满"时拒买(不扣钱): 诅咒契约 +1 可反复买到上限,
	# 若照旧"先扣钱再 add_curse 夹取", curse=10 更是买空气 ——
	# 静默吞金币比不卖更糟。拒买走 return false, HUD 侧弹 toast 说明原因(见 hud._on_wave_shop_buy)。
	# 判据用 curse_level + value > CURSE_MAX 而非 == CURSE_MAX: 商店卖的东西必须全额生效。
	if kind == "curse" and curse_level + int(value) > CURSE_MAX:
		return false
	var cost := int(offer["cost"])
	if coins < float(cost):
		return false
	coins -= float(cost)
	# kind/value 已在函数头解析(诅咒满级拒买要提前读 kind), 此处不再重复声明
	match kind:
		"heal":
			if player != null:
				player.heal(value)
		"magnet":
			# 复用磁铁逻辑: 全屏金币与经验拉向玩家
			_magnet_all()
		"temp_damage":
			if player != null:
				player.item_mods["damage_mult"] = float(player.item_mods.get("damage_mult", 0.0)) + value
		# 以下走本局临时修正(叠加到 item_mods, 局终随 item_mods 清空)。
		# 原 temp_speed/thorns/lifesteal/attack_speed 四支随对应商品的删减一并移除。
		"crit":
			if player != null:
				player.item_mods["crit_chance"] = float(player.item_mods.get("crit_chance", 0.0)) + value
		"greed":
			if player != null:
				player.item_mods["coin_mult"] = float(player.item_mods.get("coin_mult", 0.0)) + value
		"curse":
			# 诅咒商品: 不走 item_mods(它是 GameManager 的 run 级标量, 敌方侧要读)。
			# add_curse 内部夹取 0~CURSE_MAX 并广播 HUD; 商店暂停中 HUD 已被清 →
			# 该广播是空操作, close_wave_shop 重建 HUD 时 show_hud 末尾会补刷一次。
			# 满级拒买已在函数头处理(不扣钱), 走到这里必然有余量
			add_curse(int(value))
		"shield":
			if player != null:
				# 生命上限固定 +15(非乘法), 走独立 flat 修正, 不受角色基数影响
				player.item_mods["max_hp_flat"] = float(player.item_mods.get("max_hp_flat", 0.0)) + value
				player.recalc_stats()
				player.heal(player.max_hp_value())   # 回满
	play_sfx("pickup")
	return true


# 全屏吸附: 金币与经验宝石瞬移到玩家周围(黄金角铺开)
func _magnet_all() -> void:
	if player == null:
		return
	var angle := 0.0
	for g in coins_list.duplicate():
		if not is_instance_valid(g) or g.is_queued_for_deletion():
			continue
		angle += 2.399963
		var r := 45.0 + fmod(angle, 1.0) * 25.0
		g.global_position = player.global_position + Vector2.from_angle(angle) * r
	for g in gems.duplicate():
		if not is_instance_valid(g) or g.is_queued_for_deletion():
			continue
		angle += 2.399963
		var r := 45.0 + fmod(angle, 1.0) * 25.0
		g.global_position = player.global_position + Vector2.from_angle(angle) * r


# ================= 相机震动 =================
func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

func _process(delta: float) -> void:
	if _shake > 0.01:
		if camera != null:
			camera.offset = Vector2(
				_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0)
			) * _shake
		_shake = lerpf(_shake, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	elif camera != null and camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


# ================= 粒子 =================
# 一次性爆发 CPUParticles2D, 结束自动销毁; 击杀/拾取/受击偶发, 无需对象池
func spawn_effect(pos: Vector2, color: Color, count: int = 12, speed: float = 40.0) -> void:
	if main == null:
		return
	var p := CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = count
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.global_position = pos
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	main.add_child(p)
	p.finished.connect(p.queue_free)


# ================= 程序化像素特效(字符画烘焙帧, 零资源) =================
# 帧为灰度字符画: 颜色固定白, 字符控 alpha 阶 => 运行时 tint 染色(同一套帧适配各武器主题色)
# 与矢量 effect.gd 的区别: 无抗锯齿 + 整数对齐 + 贴图帧 => 真像素观感
# 字符: g 暗晕 / m 中 / l 亮 / w 白热
const FX_PALETTE := {
	"g": Color(1, 1, 1, 0.30),
	"m": Color(1, 1, 1, 0.55),
	"l": Color(1, 1, 1, 0.80),
	"w": Color(1, 1, 1, 1.00),
}

# 特效帧表: name -> {fps, frames:[字符画行数组]}
# spark 命中星芒(9→7→3 收缩) / muzzle 枪口爆闪(扁十字, 旋转对齐发射向) / ring 扩散环(7→13→17 渐暗)
const PIXEL_FX := {
	"spark": {"fps": 30.0, "frames": [
		[
			"....g....",
			".g..m..g.",
			"..m.l.m..",
			"...www...",
			"gmlwwwlmg",
			"...www...",
			"..m.l.m..",
			".g..m..g.",
			"....g....",
		],
		[
			"...g...",
			".g.l.g.",
			"..www..",
			"glwwwlg",
			"..www..",
			".g.l.g.",
			"...g...",
		],
		[
			".l.",
			"lwl",
			".l.",
		],
	]},
	"muzzle": {"fps": 24.0, "frames": [
		[
			"....g....",
			"....l....",
			"...www...",
			"gmlwwwlmg",
			"...www...",
			"....l....",
			"....g....",
		],
		[
			".l.",
			"lwl",
			".l.",
		],
	]},
	"ring": {"fps": 18.0, "frames": [
		[
			".lllll.",
			"ll...ll",
			"l.....l",
			"l.....l",
			"l.....l",
			"ll...ll",
			".lllll.",
		],
		[
			".....mmm.....",
			"...mm...mm...",
			"..m.......m..",
			".m.........m.",
			".m.........m.",
			"m...........m",
			"m...........m",
			"m...........m",
			".m.........m.",
			".m.........m.",
			"..m.......m..",
			"...mm...mm...",
			".....mmm.....",
		],
		[
			".......ggg.......",
			".....gg...gg.....",
			"....g.......g....",
			"...gg.......gg...",
			"..gg.........gg..",
			"..g...........g..",
			".g.............g.",
			".g.............g.",
			"g...............g",
			".g.............g.",
			".g.............g.",
			"..g...........g..",
			"..gg.........gg..",
			"...gg.......gg...",
			"....g.......g....",
			".....gg...gg.....",
			".......ggg.......",
		],
	]},
}

var _fx_frames_cache := {}   # name -> Array[Texture2D]

# 烘焙某特效的全部帧(字符画 → 白+alpha 阶 Image → ImageTexture), 结果缓存
func fx_frames(fx_name: String) -> Array:
	if _fx_frames_cache.has(fx_name):
		return _fx_frames_cache[fx_name]
	var def: Dictionary = PIXEL_FX.get(fx_name, {})
	var out: Array = []
	for frame_rows in def.get("frames", []):
		var rows: Array = frame_rows
		if rows.is_empty():
			continue
		var h := rows.size()
		var w := str(rows[0]).length()
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in range(h):
			var row := str(rows[y])
			for x in range(row.length()):
				var ch := row.substr(x, 1)
				if FX_PALETTE.has(ch):
					img.set_pixel(x, y, FX_PALETTE[ch])
		out.append(ImageTexture.create_from_image(img))
	_fx_frames_cache[fx_name] = out
	return out


# 像素特效工厂: 播放一遍即回收(池化)
# tint 染色(灰度帧 × tint); sc 整数倍放大; rot_deg 旋转(枪口对齐发射向);
# fade 随生命淡出; additive 用加法混合(深色背景下更"发光")
func spawn_pixel_fx(fx_name: String, pos: Vector2, tint: Color = Color.WHITE, sc: float = 1.0, rot_deg: float = 0.0, fade: bool = true, additive: bool = false) -> void:
	if not PIXEL_FX.has(fx_name):
		return
	var fx := ObjectPool.acquire_pixel_fx()
	if fx == null:
		return
	fx.setup(fx_name, pos, tint, sc, rot_deg, fade, additive)


# 命中火花(高频): 像素星芒, 子弹命中敌人时触发
func spawn_spark(pos: Vector2, col: Color) -> void:
	spawn_pixel_fx("spark", pos, col, 1.0, 0.0, true, true)


# 击杀爆裂(低频): 池化扩散环 + 碎片; scale 放大 Boss 死亡
func spawn_burst(pos: Vector2, col: Color, scale: float = 1.0) -> void:
	var e := ObjectPool.acquire_effect()
	e.setup("burst", pos, col, 0.35, scale)


# 扩散涟漪: radius 即终点半径(像素)
# 小半径(≤30, 如 wand 穿透环/落雷冲击波)走像素环; 大半径(圣环 45~150px)保留矢量(像素环帧最大 17px 覆盖不了)
# follow 非空则矢量涟漪贴目标扩散(圣环跟手); 像素环不跟随(一次性扩散, 短到跟不跟无感)
func spawn_ring(pos: Vector2, col: Color, radius: float, follow: Node2D = null) -> void:
	if radius <= 30.0 and follow == null:
		spawn_pixel_fx("ring", pos, col, clampf(roundf(radius / 8.0), 1.0, 3.0), 0.0, true, true)
		return
	var e := ObjectPool.acquire_effect()
	e.setup("ring", pos, col, 0.32, radius, Vector2.ZERO, follow)


# 枪口闪光: 像素十字爆闪, 旋转量化到 45° 八方向(任意角度旋转像素贴图会歪斜, 量化保锐利)
func spawn_muzzle(pos: Vector2, dir: Vector2) -> void:
	var deg := snappedf(rad_to_deg(dir.angle()), 45.0)
	spawn_pixel_fx("muzzle", pos, Color(0.75, 0.95, 1.0), 1.0, deg, true, true)


# ================= 音效(BGM/SFX) =================
# 素材放 assets/audio/sfx_*.ogg 即自动生效; 缺素材时静默跳过
# 限流 + 音高随机, 避免射速高时同类音效机械重复/爆音
var _sfx_last := {}   # sfx_name -> 上次播放时间戳(ms)


# ================= 背景音乐(BGM) =================
# 三轨: menu / battle / boss, 循环播放; 按游戏状态自动切换。
# 素材位于 assets/audio/bgm_*.ogg(CC0, 见 CREDITS.md), 缺素材时静默跳过。
var _bgm_player: AudioStreamPlayer = null
var _bgm_current: String = ""

func play_bgm(track: String) -> void:
	if _bgm_current == track:
		return
	_bgm_current = track
	if _bgm_player == null:
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.bus = "Master"
		_bgm_player.volume_db = -6.0   # 压低于 SFX, 避免盖过战斗音效
		add_child(_bgm_player)
	var path := "res://assets/audio/bgm_%s.ogg" % track
	if not ResourceLoader.exists(path):
		_bgm_player.stop()
		return
	# 同名流惰性加载(res:// 自带缓存, 三轨仅各载一次); 战斗/菜单循环播放
	var stream: AudioStream = load(path)
	stream.loop = true
	if _bgm_player.stream != stream:
		_bgm_player.stream = stream
	_bgm_player.play()

func stop_bgm() -> void:
	if _bgm_player != null:
		_bgm_player.stop()

func play_sfx(sfx_name: String) -> void:
	var path := "res://assets/audio/sfx_%s.ogg" % sfx_name
	if not ResourceLoader.exists(path):
		return
	var now := Time.get_ticks_msec()
	if _sfx_last.has(sfx_name) and now - int(_sfx_last[sfx_name]) < 30:
		return
	_sfx_last[sfx_name] = now
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.pitch_scale = _rng.randf_range(0.9, 1.1)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ================= 程序合成音效(零素材) =================
# 图鉴翻页声: 白噪声 → 一阶低通 = 纸张沙沙; variant 0 = 翻页(短亮), 1 = 合书(长暗闷)
# 不动 play_sfx(它只认 .ogg); 节流 key "page%d" 与 .ogg 音效分开, 连翻 3 声间隔 100ms 都能响
const SYNTH_RATE := 22050
var _synth_cache := {}

func page_sfx_stream(variant: int) -> AudioStreamWAV:
	if _synth_cache.has(variant):
		return _synth_cache[variant]
	var dur: float = 0.14 if variant == 0 else 0.26
	var tau: float = 0.032 if variant == 0 else 0.070
	var lp_a: float = 0.42 if variant == 0 else 0.20
	var n: int = int(float(SYNTH_RATE) * dur)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var lp := 0.0
	var peak := 0.0001
	for i in range(n):
		var t := float(i) / float(SYNTH_RATE)
		lp += lp_a * (_rng.randf_range(-1.0, 1.0) - lp)
		var env := exp(-t / tau) * minf(1.0, t / 0.003)   # 3ms attack 防爆音
		var snap := 1.0 + 1.6 * exp(-t / 0.006)            # 起手 6ms "脆"瞬态
		samples[i] = lp * env * snap
		peak = maxf(peak, absf(samples[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var v: int = clampi(int(samples[i] / peak * 0.55 * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SYNTH_RATE
	wav.stereo = false
	wav.data = data
	_synth_cache[variant] = wav
	return wav

func play_page_sfx(variant: int = 0) -> void:
	var key := "page%d" % variant
	var now := Time.get_ticks_msec()
	if _sfx_last.has(key) and now - int(_sfx_last[key]) < 30:
		return
	_sfx_last[key] = now
	var stream: AudioStreamWAV = page_sfx_stream(variant)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.pitch_scale = _rng.randf_range(0.92, 1.08)
	p.volume_db = -4.0
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ================= 角色表 =================
const CHARACTERS := {
	"apprentice": {
		"name": "蓝帽小子",
		"weapon": "wand",
		"max_hp": 90,
		"move_speed": 95.0,
		"damage_mult": 1.10,
		"proj_speed_mult": 1.15,
		"pick_range": 50.0,
		"heal_mult": 1.0,
		"passive": "弹速 +15%",
		"rule": "求知若渴: 升级所需经验 -20%",
	},
	"paladin": {
		"name": "粉红壮汉",
		"weapon": "orbit",
		"max_hp": 120,
		"move_speed": 85.0,
		"damage_mult": 1.0,
		"proj_speed_mult": 1.0,
		"pick_range": 50.0,
		"heal_mult": 1.0,
		"passive": "生命上限 +10%",
		"rule": "圣盾: 每 12s 格挡一次伤害",
	},
	"priest": {
		"name": "忍者蛙",
		"weapon": "aura",
		"max_hp": 100,
		"move_speed": 90.0,
		"damage_mult": 1.0,
		"proj_speed_mult": 1.0,
		"pick_range": 65.0,
		"heal_mult": 1.5,
		"passive": "拾取范围 +30% · 回血 +50%",
		"rule": "拾穗: 拾取经验宝石回复 1 生命",
	},
	"assassin": {
		"name": "面具客",
		"weapon": "wand",
		"max_hp": 80,
		"move_speed": 105.0,
		"damage_mult": 1.20,
		"proj_speed_mult": 1.0,
		"pick_range": 50.0,
		"heal_mult": 1.0,
		"passive": "伤害 +20% · 生命上限 -10%",
		"rule": "处决: 对生命低于 25% 的敌人伤害 +40%",
	},
	"xiaoheizi": {
		"name": "只因信徒",
		"weapon": "aura",
		"max_hp": 85,
		"move_speed": 100.0,
		"damage_mult": 1.0,
		"proj_speed_mult": 1.0,
		"pick_range": 60.0,
		"heal_mult": 1.0,
		"passive": "移速较快 · 拾取范围 +20%",
		"rule": "金拱独立: 每 12s 格挡一次伤害",
	},
}

# 圣骑士被动: 生命上限 +10% —— 在 player.recalc_stats 里按角色特殊处理。

# 图鉴文案: 只存"人话"部分(定位标签 / 上手指引 / 关键要点), 数值一律从 CHARACTERS 实时读
# 这样改数值不会出现图鉴与实战对不上的同步问题; tag/play/key 三项缺失时界面自动跳过该行
const CODEX_CHARS := {
	"apprentice": {
		"tag": "速成型 · 远程风筝",
		"play": "升级经验 -20%, 同等击杀下比别的角色早 1~2 级, 前 4 波就能凑出 2~3 把武器。弹速 +15% 让追踪弹飞得更快, 远距离也咬得住目标。",
		"key": "90 血偏低, 千万别贴脸。用移速绕大圈, 让追踪弹自己找目标, 靠等级差碾压前期。",
	},
	"paladin": {
		"tag": "重装 · 近身缠斗",
		"play": "面板 120 血经被动放大到 132, 全角色最厚。圣盾每 12s 完全格挡一次伤害 —— 不看数值大小, Boss 的 30 点重击也能整次吃掉。",
		"key": "圣盾是被动触发、不能留手, 想吃掉 Boss 冲撞就掐着冷却刚转好的时机去接。移速 85 最慢, 被围住跑不掉, 顺着怪潮外沿绕圈让旋刃扫, 别主动冲进人堆。",
	},
	"priest": {
		"tag": "续航 · 新手推荐",
		"play": "拾取范围 65 最大, 回血 ×1.5, 每颗经验宝石实际回 1.5 血 —— 边打边回, 血线基本不用管。起始武器圣环是自动环绕的被动伤害, 完全不需要瞄准。",
		"key": "最省心的开局: 站在怪潮边缘让圣环磨, 宝石自动吸过来。代价是缺爆发、打 Boss 慢, 中期务必补一把单体武器(能量弹 / 闪电)。",
	},
	"assassin": {
		"tag": "爆发 · 高风险",
		"play": "移速 105 最快、伤害 ×1.20 最高。处决对残血(低于 25%)敌人再 ×1.4, 且与暴击叠乘 —— 一记暴击处决是 3.36 倍伤害, 收割精英与 Boss 尾段极快。",
		"key": "80 血全角色最低, 一次失误就见底。处决只吃直接伤害(灼烧 / 中毒等持续伤害不触发), 得靠走位活到把怪打进残血。建议先熟悉其他角色再上手。",
	},
	"xiaoheizi": {
		"tag": "敏捷 · 灵动闪身",
		"play": "移速 100 偏快、拾取范围 60 比普通大一圈, 起始圣环自动环绕, 边跑边磨、宝石自动吸过来。圣盾每 12s 格挡一次伤害, 低血量被冲击时能救命。",
		"key": "85 血偏低, 别停着硬吃。靠移速绕大圈、让圣环磨怪、靠格挡吃 Boss 重击, 节奏上是「打一枪换一个地方」的游走型。",
	},
}


# ================= 升级定义 =================
# 武器(0 级 = 未获得; 拿到后为 1 级, 满级 3)
# 3 级制: 每级都是质变(数量/穿透/机制跳档), 不再有"只 +15% 伤害"的空档
# 质变点 = Lv2 / Lv3, Lv3 同时是进化门槛(见 EVOLUTIONS)
const WEAPONS := {
	"wand":       {"name": "能量弹", "max_level": 3},
	"orbit":      {"name": "旋刃", "max_level": 3},
	"aura":       {"name": "圣环", "max_level": 3},
	"dagger":     {"name": "飞刀", "max_level": 3},
	"shuriken":   {"name": "回旋镖", "max_level": 3},
	"holy_water": {"name": "燃烧瓶", "max_level": 3},
	"lightning":  {"name": "闪电", "max_level": 3},
}

# ================= 武器特性(一对一状态绑定) =================
# 设计: 7 把武器 ↔ StatusFx 7 个状态, **一把一状态, 无重复无空缺**。
# 玩家翻图鉴 7 条武器条目 = 读完整张状态表, 不需要另开"状态说明"页。
# 与 StatusFx 的分工: StatusFx 只管状态怎么结算(时长/DoT/定身/受伤倍率/染色),
# 本表只管"哪把武器挂哪个状态"。改绑定只动这张表 + 对应武器脚本里的接线,
# 永远不要改 StatusFx.CONFIG —— 状态效果是共享语义, 改一处会串所有持有者。
#
# desc 是给图鉴/角色选择面板读的一行说明, 必须与武器脚本里的实际触发条件一致:
#   - 概率/等级门槛写在 desc 里(玩家要知道"这把几级才开始挂状态")
#   - 数值效果直接抄 StatusFx.CONFIG 的结果(定身时长/受伤倍率), 不另立一套说法
# status 取值必须是 StatusFx.CONFIG 的键; status_name() 会校验, 错键静默回退成键名。
const WEAPON_TRAITS := {
	"wand":       {"status": "stun",       "desc": "满蓄力命中 20% 眩晕(定身 0.8s)"},
	"orbit":      {"status": "bleed",      "desc": "触碰命中挂流血(叠 3 层 DoT)"},
	"aura":       {"status": "vulnerable", "desc": "光环内敌人受伤 +15%(3 级 +25%)"},
	"dagger":     {"status": "poison",     "desc": "命中挂中毒(叠 3 层 DoT · 2 级可叠 5 层)"},
	"shuriken":   {"status": "slow",       "desc": "2 级解锁: 命中减速 -30%(3 级 -45%, 进化必触发)"},
	"holy_water": {"status": "burn",       "desc": "火焰区内敌人持续灼烧"},
	"lightning":  {"status": "freeze",     "desc": "命中概率冰冻(定身 1.2s + 受伤 +30%)"},
}

# 状态中文名: 键与 StatusFx.CONFIG 一一对应(那里是英文 id, 这里是给 UI 读的名字)
# 不加"元素名/风味名"这一层 —— 机制名就是显示名, 少一层要记的东西
# (BG3 的教训: 它的 vulnerabilities 在游戏内 tooltip 里根本不提, 等于白设计)
const STATUS_NAMES := {
	"freeze":     "冰冻",
	"burn":       "燃烧",
	"poison":     "中毒",
	"stun":       "眩晕",
	"bleed":      "流血",
	"slow":       "减速",
	"vulnerable": "易伤",
}

# 状态的中文显示名; 未知键回退成键名本身(不崩, 便于发现拼错)
func status_name(kind: String) -> String:
	return String(STATUS_NAMES.get(kind, kind))


# 一把武器的特性状态 id; 未登记返回 ""(调用方据此跳过挂状态)
func trait_of(weapon_id: String) -> String:
	var t: Dictionary = WEAPON_TRAITS.get(weapon_id, {})
	return String(t.get("status", ""))


# 特性的中文显示名, 如 "流血"; 未登记返回 ""
func trait_name(weapon_id: String) -> String:
	return status_name(trait_of(weapon_id))


# 特性的效果说明(WEAPON_TRAITS[id]["desc"]), 未登记返回 ""
func trait_desc(weapon_id: String) -> String:
	var t: Dictionary = WEAPON_TRAITS.get(weapon_id, {})
	return String(t.get("desc", ""))


# 特性染色: 直接读 StatusFx.CONFIG 的 tint, 保证 UI 上标的颜色 == 敌人身上实际染的颜色
# (Warframe 的做法: 配方本身就是显示名, 不要再造一层色)未登记回退白色。
func trait_color(weapon_id: String) -> Color:
	var kind := trait_of(weapon_id)
	if kind == "" or not StatusFx.CONFIG.has(kind):
		return Color.WHITE
	return Color(StatusFx.CONFIG[kind]["tint"])


# ================= 武器逐级文案(读 WEAPON_LEVELS, 三处 UI 同源) =================

# 图鉴/角色选择屏用的成长节点数组: [Lv1 数值快照, "2 级 …", "3 级 …"]
# 保留改造前 lines 的逐字节观感(base 行自带配色, 等级行统一染 #57C7D6 冷青),
# 消费方(hud.gd)只加 "· " 前缀 —— 与旧 WEAPON_DETAILS["lines"] 的格式契约一致。
func weapon_level_lines(weapon_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var def: Dictionary = WEAPON_DETAILS.get(weapon_id, {})
	if def.has("base"):
		out.append(String(def["base"]))
	var lv: Dictionary = WEAPON_LEVELS.get(weapon_id, {})
	for n in [2, 3]:
		if lv.has(n):
			out.append("[color=#57C7D6]%d 级 %s[/color]" % [n, String(lv[n])])
	return out


# 升级三选一卡片用的短文案: 玩家点之前就能看到"这一级买的是什么"
# 纯文本(卡面 Label 不吃 BBCode); lv 是要升到的目标等级(= next_level)。
# 新武器(lv == 1)走 WEAPON_DETAILS 的 summary —— 第一次拿到时该介绍身份, 不是介绍 Lv1 数值。
# 缺表回退成旧的字面量, 不崩。
func weapon_option_desc(weapon_id: String, lv: int) -> String:
	if lv <= 1:
		return String(WEAPON_DETAILS.get(weapon_id, {}).get("summary", "获得武器"))
	var l: Dictionary = WEAPON_LEVELS.get(weapon_id, {})
	return String(l.get(lv, "强化武器"))


# ================= 进化附加效果: 全局状态触发 =================
# 武器进化后额外获得一条"直伤命中概率挂状态"的被动 —— 替代已删除的代价道具 proc_* 通道:
# 走 status_fx.try_proc_from_player(enemy/boss take_damage 的非 DoT 分支), 所以是**全局**生效
# (任何武器打出的直伤都能触发, 不只进化那把), 与原道具(frost_touch 等)的语义一致。
# 同一状态多来源只取最高概率, 不叠加(player.proc_chance 用 max)。
# lightning 不在表里: 它的冰冻是脚本内连锁命中自带(见 WEAPON_TRAITS), 不占全局通道。
const EVOLUTION_TRAITS := {
	"wand":  {"status": "freeze", "chance": 0.15},
	"orbit": {"status": "poison", "chance": 0.25},
	"aura":  {"status": "burn",   "chance": 0.20},
}


# 武器逐级效果表(**逐级文案的唯一真相源**): id -> {2: Lv2 质变, 3: Lv3 质变}
# 纯文本不带 BBCode —— 配色由各消费方自己加(升级卡面染特性色, 图鉴经 _cx_inkify 重映射成墨色)。
#
# 这张表同时驱动三处 UI: ①升级三选一的武器卡 desc(roll_upgrade_options → weapon_option_desc)
# ②图鉴武器页「成长节点」(_cx_prose_lines) ③角色选择屏右侧详情(_refresh_weapon_detail)。
# 改造前的病灶: ②③读 WEAPON_DETAILS 的手写 lines, 而①恒显示字面量"获得/升级武器" ——
# 玩家在弹窗里**看不到**这一级买了什么, 七把武器的 Lv2 卡面完全一样(同质化的主因之一),
# 且改了武器脚本两处文案就各自漂移。现在三处同源, 改武器只改这一张表。
#
# 设计语义(2026-09-10 武器升级重做): **Lv1 = 身份 / Lv2 = 换轴 / Lv3 = 爆发**。
# Lv2 给的是"新的作用方式"(穿透、减速、减伤、毒层、命中冷却), 不是"更多的同样东西";
# 数量轴(双发/三刃/双瓶)统一后移到 Lv3。所以这张表的 2 级行里不该再出现"数量+N"。
#
# **文案长度上限约 16 个中文字符**: 卡面 desc 是 90px 宽 / 7 号字 / 高 34 的 autowrap Label,
# 超过两行会顶到卡片下缘。要写更详细的解释就写进武器脚本的注释, 不要塞这张表。
const WEAPON_LEVELS := {
	"wand":       {2: "穿透 1 · 过载更易触发", 3: "双发 · 穿透 2 · 命中碎光"},
	"orbit":      {2: "3 刃 · 命中冷却 0.28 秒", 3: "6 刃 · 刃体加大 · 甩剑气"},
	"aura":       {2: "受伤减免 28% · 每跳回血 1", 3: "减免 40% · 回血 2 · 易伤 +25%"},
	"dagger":     {2: "双刀 · 穿透 2 · 毒叠 5 层", 3: "三刀 · 扇形扩角 · 残血处决"},
	"shuriken":   {2: "穿透 2 · 命中减速 30%", 3: "三镖 · 射程拉长 · 减速 45%"},
	"holy_water": {2: "落地爆炸 · 火池半径跳增", 3: "双瓶 · 爆炸加强 · 白热爆裂"},
	"lightning":  {2: "连锁 +1 · 跳跃 110px · 递增伤害", 3: "连锁 +1 · 伤害 +25% · 冲击波"},
}

# 武器详情(角色选择详情面板右侧展示): 定位 + Lv1 关键数值快照, 仅供 UI
# 实际数值在各武器脚本 _ready 里, 改动需两处同步
# **逐级文案不在这里** —— 已抽到 WEAPON_LEVELS, 由 weapon_level_lines() 派生成 lines 数组,
# 消费方(hud.gd 两处)改读该 helper, 不要再直接读 def["lines"](该键已不存在)
const WEAPON_DETAILS := {
	"wand":       {"summary": "追踪单发魔法弹", "base": "[color=#FF6A5A]伤害[/color] [color=#E6F2F5]14[/color] · [color=#FF6A5A]冷却[/color] [color=#E6F2F5]0.9 秒[/color]"},
	"orbit":      {"summary": "环绕旋转刀刃", "base": "[color=#FF6A5A]触碰伤害[/color] [color=#E6F2F5]13[/color] · [color=#FF6A5A]轨道[/color] [color=#E6F2F5]55px[/color]"},
	"aura":       {"summary": "守护光环 · 伤敌并减免自身伤害", "base": "[color=#FF6A5A]每跳[/color] [color=#E6F2F5]8[/color] · [color=#FF6A5A]结算[/color] [color=#E6F2F5]1 秒[/color] · [color=#FF6A5A]受伤减免[/color] [color=#E6F2F5]15%[/color]"},
	"dagger":     {"summary": "高频直线穿透飞刀", "base": "[color=#FF6A5A]伤害[/color] [color=#E6F2F5]9[/color] · [color=#FF6A5A]冷却[/color] [color=#E6F2F5]0.55 秒[/color]"},
	"shuriken":   {"summary": "去程回程各扫一遍的回旋镖", "base": "[color=#FF6A5A]伤害[/color] [color=#E6F2F5]8[/color] · [color=#FF6A5A]冷却[/color] [color=#E6F2F5]0.75 秒[/color]"},
	"holy_water": {"summary": "落地燃烧火池", "base": "[color=#FF6A5A]每跳[/color] [color=#E6F2F5]6[/color] · [color=#FF6A5A]冷却[/color] [color=#E6F2F5]2.2 秒[/color]"},
	"lightning":  {"summary": "瞬发落雷连锁", "base": "[color=#FF6A5A]伤害[/color] [color=#E6F2F5]16[/color] · [color=#FF6A5A]冷却[/color] [color=#E6F2F5]1.1 秒[/color]"},
}

# 通用强化(每类满级 3)
# 设计: 属性刻意错开覆盖不同武器, 让 build 有取舍(仿吸血鬼幸存者)
#   冷却 => 全部武器;  数量 => 能量弹/旋刃;  范围 => 圣环/旋刃
# 幅度按"3 级总收益 ≈ 原 5 级总收益"重调(原 5×每级 → 3×每级), 见 player.gd 各倍率函数
# extra_count 例外: 3 级制下 Lv3 额外 +1(共 +4), 避免数量流被砍到原 5 级的 60%
const UPGRADES := {
	"damage":       {"name": "伤害强化", "max_level": 3, "desc": "所有伤害 +26%"},
	"attack_speed": {"name": "攻速强化", "max_level": 3, "desc": "攻击/结算更快 +26%"},
	"cooldown":     {"name": "冷却缩减", "max_level": 3, "desc": "所有武器冷却 -13%"},
	"extra_count":  {"name": "数量强化", "max_level": 3, "desc": "能量弹/飞刀/回旋镖 +1 · 满级再 +1"},
	"area":         {"name": "范围强化", "max_level": 3, "desc": "圣环/旋刃半径 +20%"},
	"proj_speed":   {"name": "弹速强化", "max_level": 3, "desc": "子弹速度 +45%"},
	"move_speed":   {"name": "移速强化", "max_level": 3, "desc": "移动速度 +17%"},
	"pick_range":   {"name": "拾取范围", "max_level": 3, "desc": "吸附半径 +45%"},
	"max_hp":       {"name": "生命强化", "max_level": 3, "desc": "上限 +35 并回 30 血"},
}

# 无限成长超限项(2026-09-09): 常规池抽干(7 武器 Lv3 + 9 被动 Lv3 + 进化全拿)后的兜底,
# 让后期经验继续涨时三选一永远有得点 —— 不封顶, 每选一次叠一层。
# value = 每层幅度(乘算加成项, 经 player._overlimit() 进对应实时倍率函数);
# 幅度刻意压小(伤害 5% ≈ 常规被动每级 26% 的 1/5): 超限是"细水长流", 不是第二个常规池。
# max_hp 是 flat 例外(+10 上限并回 10 血, 同 gain_stat 的 max_hp 手法但量减半)。
# 键与 UPGRADES 同名但**独立计数**(player.overlimit_levels), 绝不写回 stat_levels ——
# 那是常规池准入与进化前置的判据, 混进去会破坏 roll_upgrade_options 的门槛语义。
const OVERLIMIT := {
	"damage":       {"name": "伤害超限", "value": 0.05, "desc": "所有伤害 +5% (不封顶)"},
	"attack_speed": {"name": "攻速超限", "value": 0.05, "desc": "攻击速度 +5% (不封顶)"},
	"cooldown":     {"name": "冷却超限", "value": 0.03, "desc": "武器冷却 -3% (不封顶)"},
	"move_speed":   {"name": "移速超限", "value": 0.03, "desc": "移动速度 +3% (不封顶)"},
	"pick_range":   {"name": "拾取超限", "value": 0.10, "desc": "吸附半径 +10% (不封顶)"},
	"max_hp":       {"name": "生命超限", "value": 10.0, "desc": "上限 +10 并回 10 血 (不封顶)"},
}

# 进化配方: 满级武器(Lv3) + 满级配对被动(Lv3) → 进化武器(幸存者类核心爽点)
# weapon_id -> { "passive": 配对被动id, "name": 进化后武器名, "desc": 效果描述 }
# 设计约束: 每个进化只有「一个读得出的主效果」+ 换色, 不叠一堆看不见的小倍率
# (desc 必须与武器脚本 is_evolved() 分支的实际行为逐条对得上, 改一处同步另一处)
const EVOLUTIONS := {
	"wand":       {"passive": "proj_speed",  "name": "奥术星雨",   "desc": "扇形散射 5 发穿透弹 · 直伤 15% 冰冻"},
	"orbit":      {"passive": "damage",      "name": "刃环风暴",   "desc": "内圈反向刀刃 · 同一次触碰结算两遍 · 直伤 25% 中毒"},
	"aura":       {"passive": "max_hp",      "name": "圣域",       "desc": "半径 +60% · 每次结算回血 3 · 直伤 20% 燃烧"},
	"dagger":     {"passive": "attack_speed", "name": "千刃暴雨",  "desc": "+3 把飞刀 · 穿透 +2"},
	"shuriken":   {"passive": "move_speed",   "name": "风魔回旋镖", "desc": "+2 把回旋镖 · 穿透 +2 · 命中必减速"},
	"holy_water": {"passive": "area",        "name": "炼狱燃烧瓶", "desc": "紫色炼狱火 · 灼烧区更大更久更痛"},
	"lightning":  {"passive": "cooldown",    "name": "雷霆审判",   "desc": "连锁 +3 · 命中 20% 冰冻"},
}

# 波间商店商品(用本局金币购买一次性增益, 状态机 SHOP 阶段消费)
# rarity 分三档驱动卡框配色与抽取权重(参照土豆兄弟的等级分档):
#   common 普通(灰) / uncommon 精良(蓝) / rare 稀有(紫); 越稀有越贵越强、越难抽到
# 池子 12→7: 删除荆棘之甲/临时神速/嗜血/急速冷却/深渊献祭(与其绑定的 item_mods 通道一并清理),
# 保留致命一击 —— crit_chance 是 roll_crit(敌人/首领受击端共用)的唯一数据源, 砍了暴击率永远为 0。
const SHOP_OFFERS := [
	{"name": "生命恢复", "cost": 8, "kind": "heal", "value": 40.0, "rarity": "common", "desc": "立即回复 40 生命"},
	{"name": "全屏吸金", "cost": 6, "kind": "magnet", "value": 0.0, "rarity": "common", "desc": "吸附全屏金币与经验"},
	{"name": "坚盾", "cost": 11, "kind": "shield", "value": 15.0, "rarity": "common", "desc": "生命上限 +15 并回满"},
	{"name": "贪婪", "cost": 9, "kind": "greed", "value": 0.30, "rarity": "uncommon", "desc": "本局金币获取 +30%"},
	{"name": "临时利刃", "cost": 15, "kind": "temp_damage", "value": 0.25, "rarity": "rare", "desc": "本局伤害 +25%"},
	{"name": "致命一击", "cost": 12, "kind": "crit", "value": 0.20, "rarity": "rare", "desc": "攻击 20% 概率 2 倍伤害"},
	# 诅咒商品: value 是要加的诅咒层数(int), 走 buy_shop_offer 的 "curse" 支。
	# cost 4 是全场最低 —— 刻意压低门槛: 诅咒是"主动选的额外难度", 买它应当像买一次赌博而不是攒钱;
	# 副作用是 autopilot 的 _handle_shop(买第一件买得起的)会高频买中, 正好当高压测试样本,
	# 但 normal 冒烟的基线会偏斜(见验证章节: 批次 6 另跑一条关店对照 run 分离变量)。
	# desc 必须单行(与上面各条一致): 卡片高 126, 两行会挤掉价格行。
	{"name": "诅咒契约", "cost": 4, "kind": "curse", "value": 1.0, "rarity": "common", "desc": "诅咒 +1 · 怪更强钱更多"},
]

# 本局商店状态: cur_shop = 从池子随机抽出的 5 件展示商品(索引即商品位; 无刷新, 进店抽定即所见)
var cur_shop: Array = []

# 升级三选一重抽(每局 2 次, 入续玩档): 抽到 3 个都不想要的死局保险
var levelup_rerolls: int = 0
const LEVELUP_REROLL_MAX := 2

# ================= 全局诅咒值(土豆兄弟式风险收益旋钮) =================
# run 级标量(0~10), 唯一来源: 波间 SHOP_OFFERS(kind="curse" 的诅咒契约, 可反复买)。
# (原升级池的 3 件诅咒道具随 ITEMS 系统一并删除)
# 语义: **同时放大敌人侧与玩家收益侧**, 玩家主动选的额外难度, 不属于难度档(难度只削敌人不削玩家,
# 诅咒两边都加)。不给玩家负面属性(不移速/不降上限) —— 代价全部体现在敌人身上, 直接可感;
# 也因此 player.item_mods 通道与 STAT_MOD_LABELS 白名单零改动。
const CURSE_MAX := 10

var curse_level: int = 0


# ================= 波间诅咒事件(每波强制随机一条, 波末消失) =================
# 与 curse_level 正交的第二个风险旋钮: curse_level 是玩家**主动买**的永久(本局)放大,
# 事件是**被动抽**的单波扰动 —— 每波 _start_wave 掷一条, 整波生效, _clear_wave 清零。
# 双向设计: 每条事件既有压你的面也有喂你的面(怒潮=敌快但金币×2), 没有纯惩罚事件 ——
# 纯负随机 = 玩家觉得被系统针对; 双向 = "这波怎么打"的决策素材。
# 因子键全部**省略即中性**(get 默认值), 8 行各只写自己动的 1~2 个旋钮;
# 接入点全在 curse_*/roll_*/coin/xp 等既有咽喉函数末尾乘/加一层(与难度档同构, 零新调用链)。
#   hp/dmg/spd 乘子(1.x=加压) · density 密度乘子(>1 更密, 咽喉处除到间隔上)
#   affix/elite 掷骰概率乘子 · barage Boss 环形弹幕加发数(整数)
#   coin/xp 收益乘子(0=无收益) · crit 暴率加值 · drop_add 掉率加点 · drop_mult 掉率乘子
const WAVE_CURSES := [
	{"id": "rage",      "name": "怒潮", "desc": "敌速 +30% · 金币 ×2",
		"spd": 1.30, "coin": 2.0},
	{"id": "glutton",   "name": "贪食", "desc": "密度 +40% · 经验 ×1.8",
		"density": 1.40, "xp": 1.8},
	{"id": "ironwall",  "name": "铁壁", "desc": "敌血 +50% · 巨魔掉率 +15%",
		"hp": 1.50, "drop_add": 0.15},
	{"id": "frenzy",    "name": "狂化", "desc": "敌伤 +35% · 暴击率 +10%",
		"dmg": 1.35, "crit": 0.10},
	{"id": "barren",    "name": "贫瘠", "desc": "敌血 -25% · 金币 ×0.5",
		"hp": 0.75, "coin": 0.5},
	{"id": "tranquil",  "name": "静谧", "desc": "密度 -35% · 本波无收益(喘息波)",
		"density": 0.65, "coin": 0.0, "xp": 0.0, "drop_mult": 0.0},
	{"id": "bloodmoon", "name": "血月", "desc": "词缀率 ×2 · 精英率 ×2",
		"affix": 2.0, "elite": 2.0},
	{"id": "void",      "name": "虚空", "desc": "Boss 弹幕 +4 发 · 经验 ×2",
		"barage": 4, "xp": 2.0},
]

# 当前事件(空字典 = 无事件)。存**字典**而非 id: 咽喉函数每帧被读, 免去线性查表;
# 落盘/存档只存 id 字符串, 恢复时 set_wave_curse(id) 重建字典。
var wave_curse: Dictionary = {}


func set_wave_curse(id: String) -> void:
	wave_curse = {}
	if id == "":
		return
	for c in WAVE_CURSES:
		if str(c["id"]) == id:
			wave_curse = c
			return
	# id 非法(理论上只有坏档路径能到这): 静默按无事件处理, 不崩


func roll_wave_curse() -> void:
	set_wave_curse(str(WAVE_CURSES[_rng.randi_range(0, WAVE_CURSES.size() - 1)]["id"]))


# 读当前事件的某个因子; 无事件/无该键返回中性默认值。所有接入点统一走这个口。
func wc_f(key: String, def: float) -> float:
	return float(wave_curse.get(key, def))


# 加诅咒: 夹取到 0~CURSE_MAX 后广播 HUD 刷新(与 trigger_level_up 同法, GameManager 不直接摸 UI)
func add_curse(n: int) -> void:
	var before: int = curse_level
	curse_level = clampi(curse_level + n, 0, CURSE_MAX)
	if curse_level == before:
		return   # 已到上限(或 n=0)不必刷 HUD, 也避免重复弹反馈
	if main != null and main.has_method("on_curse_changed"):
		main.on_curse_changed()
	# 诅咒满成就: 钩在值实际变化之后(顶格再加不加不重复弹)。add_curse 的两个入口
	# (升级三选一/波间商店)都在暂停帧, unlock_achievement 的 toast 是 PROCESS_MODE_ALWAYS, 能正常显示。
	if curse_level >= CURSE_MAX:
		unlock_achievement("curse_max")


# 进店时加权抽 5 件(不重复); 固定 5 格
# 稀有度权重: rare 更难抽到(高价值但稀缺), common 最容易; 仿土豆兄弟入店概率
const SHOP_RARITY_WEIGHT := {"common": 5, "uncommon": 3, "rare": 1}

func roll_shop() -> void:
	cur_shop.clear()
	var pool: Array = SHOP_OFFERS.duplicate()
	for i in range(5):
		if pool.is_empty():
			break
		var idx: int = _weighted_shop_pick(pool)
		cur_shop.append(pool[idx])
		pool.remove_at(idx)


# 按稀有度加权抽一件商品(返回其在传入池中的索引)
func _weighted_shop_pick(pool: Array) -> int:
	var total := 0.0
	for o in pool:
		total += float(SHOP_RARITY_WEIGHT.get(o["rarity"], 1))
	var r := _rng.randf_range(0.0, total)
	var acc := 0.0
	for i in range(pool.size()):
		acc += float(SHOP_RARITY_WEIGHT.get(pool[i]["rarity"], 1))
		if r <= acc:
			return i
	return pool.size() - 1


# 暴击统一判定: 玩家暴击率掷骰, 命中 2 倍(直伤分支专用, DoT 不暴击)
func roll_crit(amount: float) -> float:
	var cc: float = 0.0
	if player != null and player.has_method("crit_chance"):
		cc = player.crit_chance()
	# 狂化事件 +10% 暴率是**加值**: 零暴 build 在狂化波也能暴击(事件的"喂"面)
	cc += wc_f("crit", 0.0)
	if cc > 0.0 and _rng.randf() < cc:
		return amount * 2.0
	return amount

# ================= 杂兵基础数值(enemy.gd setup 与图鉴共读) =================
# key 对应 enemy.gd 的 Kind 枚举(0/1/2/3 = 史莱姆/蝙蝠/巨魔/骷髅; 4/5/6 = 吐息/自爆/护盾)
# 数值是"第 1 波、普通难度、无词缀"下的面板值; 实战还要乘波次成长/难度/词缀倍率
const ENEMY_BASE := {
	0: {"name": "史莱姆", "hp": 25.0, "speed": 40.0, "damage": 8.0, "xp": 1.0, "radius": 12.0,
		"color": Color(0.35, 0.8, 0.35),
		"tag": "基础杂兵 · 全期主力",
		"note": "从第 1 波刷到最后, 速度慢、血薄、伤害低, 是用来熟悉走位的靶子。威胁只来自数量 —— 被十几只同时围住时, 8 点接触伤害会连着结算。"},
	1: {"name": "蝙蝠", "hp": 15.0, "speed": 70.0, "damage": 5.0, "xp": 1.0, "radius": 10.0,
		"color": Color(0.7, 0.4, 0.9),
		"tag": "高速骚扰 · 第 3 波起",
		"note": "速度 70 是史莱姆的近两倍, 但只有 15 血, 随便擦一下就死。它会抢在别的怪前面贴脸, 所以真正的作用是把你的走位打乱 —— 不要为了躲蝙蝠冲进怪堆。"},
	2: {"name": "巨魔", "hp": 180.0, "speed": 27.0, "damage": 14.0, "xp": 8.0, "radius": 20.0,
		"color": Color(0.85, 0.25, 0.25),
		"tag": "精英肉盾 · 第 6 波起",
		"note": "180 血 + 20 碰撞半径的移动城墙, 走得比谁都慢但谁都撞得疼。经验 8 倍、金币必掉 3 枚大额, 还会低概率掉红药/宝箱/念珠/磁铁 —— 是中后期主要的发育来源, 值得专门绕过去清。"},
	3: {"name": "骷髅", "hp": 45.0, "speed": 52.0, "damage": 10.0, "xp": 2.0, "radius": 13.0,
		"color": Color(0.85, 0.87, 0.92),
		"tag": "中坚数量 · 第 5 波起",
		"note": "血 45、速度 52, 两项都卡在史莱姆(25/40)和巨魔(180/27)之间, 单看毫不起眼 —— 它的威胁全在数量。第 5 波起逐步接替史莱姆当主力, 后期常常一次十几只同时落地。别用单体武器点射, 交给圣环 / 燃烧瓶 / 闪电这类范围清场最划算。"},
	4: {"name": "炎魔小鬼", "hp": 30.0, "speed": 45.0, "damage": 7.0, "xp": 2.0, "radius": 11.0,
		"color": Color(0.95, 0.45, 0.15),
		"breath_n_min": 3, "breath_n_max": 5, "breath_cd": 2.4, "breath_range": 130.0, "breath_speed": 110.0,
		"tag": "吐息远程 · 第 5 波起",
		"note": "站定后会朝你扇形喷出 3~5 发短程火弹, 喷完立刻后撤拉开距离再喷。弹速慢、射程短(约 130px), 横向绕开它的吐息线就几乎打不中你 —— 但别贴脸, 贴身时它放弃吐息改用接触骚扰。处理优先级: 比蝙蝠高, 比巨魔低。"},
	5: {"name": "爆裂魔", "hp": 20.0, "speed": 95.0, "damage": 0.0, "xp": 2.0, "radius": 10.0,
		"color": Color(0.95, 0.25, 0.35),
		"boom_r": 46.0, "boom_dmg": 26.0, "fuse_t": 0.4, "fuse_range": 34.0,
		"tag": "自爆冲锋 · 第 7 波起",
		"note": "全场最快的冲锋者, 接触不掉血 —— 它贴近后会全身闪红 0.4 秒然后自爆, 炸完不留尸体也不掉任何东西(所以别指望杀它发育)。看到红光立刻往侧向跑, 它的爆速有限追不上变向。血薄(20), 半路点掉最划算; 让它炸在空地上等于零收益。"},
	6: {"name": "盾卫巨魔", "hp": 140.0, "speed": 24.0, "damage": 12.0, "xp": 5.0, "radius": 16.0,
		"color": Color(0.55, 0.6, 0.75),
		"shield_hp": 60.0, "shield_arc": 120.0, "shield_reduce": 0.7, "shatter_t": 6.0, "shatter_bonus": 0.5,
		"tag": "正面减伤 · 第 8 波起",
		"note": "举盾的慢速肉盾: 正面 120° 来伤减 70%, 绕到背后或侧面吃全额。持续打盾会破盾(盾血 60), 破盾后它 6 秒内受到的伤害 +50% 且不再回盾 —— 破盾窗口内爆发收割, 6 秒后盾会重新举起。打不动就先别硬怼正面, 绕背是它唯一的死穴。"},
}

# 杂兵掉落表(图鉴展示用; 实际掷骰在 enemy.gd spawn_gems)
const ENEMY_DROPS := {
	0: "经验宝石 ×1 · 金币 1~2(每枚 1)",
	1: "经验宝石 ×1 · 金币 1~2(每枚 1)",
	2: "经验宝石 ×8 · 金币 3(每枚 4) · 红药 30% / 宝箱 10% / 念珠 4% / 磁铁 4%",
	3: "经验宝石 ×2 · 金币 1~2(每枚 1)",
	4: "经验宝石 ×2 · 金币 1~2(每枚 1)",
	5: "经验宝石 ×2 · 金币 1~2(每枚 1) · 自爆身亡时不掉任何奖励",
	6: "经验宝石 ×5 · 金币 1~2(每枚 1)",
}

# 各杂兵首次出现的波次(读 spawner.WAVES 的权重表派生, 避免写死)
# spawner 不是 autoload(main.gd 里 new 的节点), 只能 preload 脚本资源取常量
const SPAWNER_SCRIPT := preload("res://scripts/spawner.gd")

func enemy_first_wave(kind: int) -> int:
	var waves: Array = SPAWNER_SCRIPT.WAVES
	for i in range(waves.size()):
		var ws: Array = waves[i]
		var weights: Array = ws[2]
		if kind < weights.size() and float(weights[kind]) > 0.0:
			return i + 1
	return 1

# Boss 登场波次(读 WAVES 的 boss_kind 列): final 为 true 时只取终极波
# 注意第 12 波 boss_kind = "final" 但同时刷中 Boss(spawner._start_wave), 故中 Boss 要把 final 波也算进来
func boss_waves(final: bool = false) -> Array:
	var out: Array = []
	var waves: Array = SPAWNER_SCRIPT.WAVES
	for i in range(waves.size()):
		var ws: Array = waves[i]
		var bk: String = str(ws[3])
		if final:
			if bk == "final":
				out.append(i + 1)
		elif bk != "":
			out.append(i + 1)
	return out

# Boss 血量(按登场次数): 第 n 次登场 = BASE.hp × (1 + (n-1) × hp_step)
func boss_hp_for(appearance: int) -> float:
	return float(BOSS_BASE["hp"]) * (1.0 + float(appearance - 1) * float(BOSS_BASE["hp_step"]))


# 场上的 Boss 节点(没有则 null)。**单一真相源**: HUD 血条 / autopilot 战报 / spawner 的
# 波末推进门槛三处共读 —— 原先 HUD 与战报各写一份"遍历 enemies 找 boss.gd"的扫描,
# 加第三个消费方时三份拷贝必然漂移(判定条件不同就会出现"血条没了但波次不推进")。
func find_boss() -> Node2D:
	for e in enemies:
		if is_instance_valid(e) and e.get_script() != null and \
			e.get_script().resource_path.ends_with("boss.gd"):
			return e
	return null


func boss_alive() -> bool:
	return find_boss() != null


# 当前波剩余时长(秒)。HUD 倒计时与 spawner 的波末判定共读 WAVES 的 duration 列,
# 不另存一份 —— 否则改了 WAVES 的时长会出现"倒计时归零但波没结束"。
# 读运行时 wave_time(而非 spawner._wave_timer): 两者在 _start_wave/_physics_process 里
# 同步递增同值, 但 wave_time 是入 suspend.cfg 的那一个, 恢复后倒计时不会读不到。
func wave_time_left() -> float:
	if wave < 1 or wave > SPAWNER_SCRIPT.WAVES.size():
		return 0.0
	var dur: float = float(SPAWNER_SCRIPT.WAVES[wave - 1][0])
	return maxf(0.0, dur - wave_time)


# ================= Boss 数值(boss.gd 与图鉴共读) =================
# BASE 是"第 1 次登场"(第 4 波)的面板; 血量按登场次数每次 +40%(第 8 波 ×1.4 / 第 12 波 ×1.8)
const BOSS_BASE := {
	"hp": 1200.0, "hp_step": 0.4, "speed": 25.0, "damage": 30.0, "radius": 24.0,
	"contact_cd": 1.0, "state_cd": 3.0,
	"charge_windup": 1.0, "charge_dash": 0.5, "charge_speed_mult": 6.0,
	"barage_count": 12, "barage_speed": 80.0, "barage_dmg": 10.0,
	# 弹幕三变体(严格轮转 环→扇→瞄准, 见 boss.gd _do_barage): 扇=朝玩家的窄扇面(侧移可躲),
	# 瞄=快三连(需预判走位)。arc 0.9 rad ≈ 51.6°: 再窄能贴着走躲光, 再宽变必中。
	"barage_fan_count": 5, "barage_fan_arc": 0.9, "barage_fan_dmg": 9.0, "barage_fan_speed": 95.0,
	"barage_aim_count": 3, "barage_aim_spread": 0.22, "barage_aim_dmg": 8.0, "barage_aim_speed": 120.0,
	"summon_count": 2, "summon_kind": 0, "summon_cd": 12.0,
	"status_resist": 0.4,
	"gem_drop": 20, "coin_drop": 12, "coin_value": 4, "heal_drop": 25.0,
}
# 终极 Boss(make_final): 覆盖 BASE 的血量/速度/伤害, 另带染红与体型放大
const BOSS_FINAL := {
	"hp": 5000.0, "speed": 30.0, "damage": 34.0,
	"tint": Color(1.0, 0.45, 0.45), "sprite_scale": 1.9,
	# 血量阶段: 跨过 60% / 30% 各进一阶(共 2 阶)。检测在 _physics_process 开头(冻结时也算),
	# 每次进阶: 速度×1.22、伤害×1.15、体型×1.06、弹幕 +4 发、召唤 +1 只且收紧间隔。
	# 两阶叠满后 30×1.22²=44.7 速、34×1.15²=44.9 伤、环弹幕 12→20 发。
	"phase_hp": [0.60, 0.30],
	"phase_speed_mult": 1.22, "phase_damage_mult": 1.15,
	"phase_barage_extra": 4, "phase_summon_extra": 1, "phase_summon_affix": true,
	"phase_tint": Color(1.0, 0.25, 0.25),
}

# Boss 名字(原先硬编码在 hud.gd 的血条与图鉴两处, 统一收口)
const BOSS_NAME := "深渊领主"
const BOSS_FINAL_NAME := "终极深渊领主"

# Boss 登场波次与图鉴文案(boss.gd 只有数值, 技能循环的行为说明在这里)
const CODEX_BOSSES := {
	"mid": {
		"tag": "第 4 / 8 / 12 波登场",
		"summary": "四技能循环的追击型 Boss: 追击 → 蓄力冲撞 → 弹幕(环/扇/瞄准三变体轮转) → 召唤小怪, 每 3 秒换一招, 循环不停。",
		"skills": [
			"[color=#FF6A5A]追击[/color] [color=#999999]3 秒[/color] — 以 25 速度直线压向你, 接触伤害 30, 每次接触后 1 秒内不再结算。绕圈风筝即可, 它转向有加速度不会瞬移。",
			"[color=#FF6A5A]蓄力冲撞[/color] [color=#999999]蓄力 1 秒 + 冲刺 0.5 秒[/color] — 蓄力时完全静止, 这是唯一的预警窗口: 看到它停住立刻往侧后方撤。冲刺速度是平时的 6 倍, 正面站桩必吃 30 点。",
			"[color=#FF6A5A]弹幕三变体[/color] [color=#999999]环 → 扇 → 瞄准, 严格轮转[/color] — 每次进弹幕阶段换一种: ① 环形 12 发(速度 80), 弹幕之间有空隙, 贴缝走位而不是往外跑; ② 扇形 5 发(朝你当前方向, 约 52° 窄扇面), 看到它抬手就往侧移, 站桩必中; ③ 瞄准三连(速度快 50%), 唯一需要预判走位的弹幕 —— 朝它出手瞬间的移动方向躲, 不是朝你现在站的位置。",
			"[color=#FF6A5A]召唤[/color] [color=#999999]每轮 4 只[/color] — 每次吐 2 只史莱姆 ×2 批, 另外每 12 秒还有一次独立召唤。场上小怪会越堆越多, 拖得越久越难收 —— 别把输出浪费在小怪上。",
		],
		"counter": [
			"冰冻 / 眩晕能冻住整个技能循环(连冲撞都停), 但 Boss 抗性把所有状态时长 ×0.4 —— 是延后不是取消。",
			"冰冻状态下 Boss 受到的直接伤害 +30%, 先控后爆发的收益对 Boss 同样成立。",
			"持续伤害(灼烧/中毒)不触发暴击、也不吃冰冻易伤加成, 打 Boss 优先堆直接伤害。",
		],
		"reward": "经验宝石 ×20 · 红药(回 25 血)必掉 · 金币 ×12(每枚 4)",
	},
	"final": {
		"tag": "第 12 波登场 · 击杀即通关",
		"summary": "同一个 Boss 的强化形态: 5000 血、速度 30、接触伤害 34, 全身染红、体型放大到 1.9 倍。技能循环与中 Boss 相同(含弹幕三变体轮转), 但多了两段血量阶段 —— 掉到 60% 和 30% 时各狂暴一次。第 12 波会同时刷一只中 Boss, 场上是双 Boss。",
		"skills": [
			"[color=#FF6A5A]血量 5000[/color] — 是中 Boss 首次登场(1200)的 4 倍以上, 按面板 DPS 估算至少要留 60 秒以上。",
			"[color=#FF6A5A]接触伤害 34[/color] — 玩家受击后有 0.75 秒无敌帧, 被贴身连续撞两下就是 68 点, 对 80 血的面具客是致死量。",
			"[color=#FF6A5A]双 Boss 同场[/color] — 两只的冲撞方向可能夹击。优先杀掉血少的中 Boss, 把场地清成 1v1 再收终极。",
			"[color=#FF6A5A]一阶狂暴(60% 血)[/color] — 速度 ×1.22、伤害 ×1.15、体型微涨, 全身染得更深, 伴随震屏 + 一波见面礼(3 只带词缀仆从 + 16 发环弹幕)。从这刻起弹幕变密、贴身更疼。",
			"[color=#FF6A5A]二阶狂暴(30% 血)[/color] — 再乘一次同样的倍率(累计速度 44.7 / 伤害 44.9), 召唤收紧到 9 秒一次且改召骷髅(hp 45, 比史莱姆硬一倍), 环弹幕涨到 20 发。",
			"[color=#FF6A5A]阶段检测不看冰冻[/color] — 阈值判定在定身冻结之前结算: 把 Boss 冻着磨血并不能推迟狂暴, 解冻时它已经是红眼状态了。",
		],
		"counter": [
			"抗性、冰冻易伤、召唤节奏与中 Boss 一致, 前面练过的走位直接沿用 —— 但 60% 之后一切都要再让出一点距离。",
			"进第 12 波前务必留好红药与念珠(全屏清场)—— 召唤的小怪会把你推离安全位, 念珠能一次性清干净。",
			"留一张位移卡到 30% 之后: 最后一次狂暴的 20 发环弹幕没有安全角, 只能靠拉开距离穿缝。",
			"通关后金币按 ×1.5 结算入账, 是局外强化的最大一笔收入。",
		],
		"reward": "同中 Boss(经验宝石 ×20 · 红药 · 金币 ×12), 通关金币 ×1.5 入账",
	},
}


# 诅咒图鉴说明(由 hud._cx_prose_lines 的 af_ 分支追加)。做成函数而非常量:
# 每行都要内插 curse_* 函数的实算值, 常量数组里写死数字会随调参漂移 —— 图鉴说谎比不写更糟。
# **只进 prose 不进 stats 列**: codex_self_check 的 FAIL 判据只量 stats 列是否被裁,
# prose 有滚动提示兜底(_cx_update_scroll_hint), 长行在这里是安全的。
# 改任一 curse_* 系数后这里自动跟着变, 无需同步。
func codex_curse_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("")
	out.append("[color=#57C7D6]诅咒[/color]  本局风险旋钮(0~%d 层)" % CURSE_MAX)
	out.append("[color=#999999]来源只有波间商店的诅咒契约(可反复买)。不给玩家任何负面属性 —— 代价全部落在敌人身上, 打起来立刻能感到。[/color]")
	out.append("")
	out.append("[color=#FF6A5A]敌人侧[/color](每层)")
	out.append("[color=#999999]血量 +%.0f%% · 伤害 +%.0f%% · 移速 +%.0f%% · 刷怪更密(满层 +%.0f%%)[/color]" % [
		(curse_hp_mult_at(1) - 1.0) * 100.0, (curse_damage_mult_at(1) - 1.0) * 100.0,
		(curse_speed_mult_at(1) - 1.0) * 100.0, (1.0 / curse_spawn_mult_at(CURSE_MAX) - 1.0) * 100.0])
	out.append("[color=#999999]词缀概率上限 %.0f%% → %.0f%% · 精英出率 +%.0f%%[/color]" % [
		28.0, (0.28 + curse_affix_bonus_at(CURSE_MAX)) * 100.0, curse_elite_bonus_at(CURSE_MAX) * 100.0])
	out.append("")
	out.append("[color=#57C7D6]回报侧[/color](每层)")
	out.append("[color=#999999]金币 +%.0f%% · 经验 +%.0f%% · 巨魔额外掉率 +%.0f%%[/color]" % [
		(curse_coin_mult_at(1) - 1.0) * 100.0, (xp_mult_at(1) - 1.0) * 100.0,
		curse_drop_bonus_at(CURSE_MAX) * 100.0])
	out.append("[color=#999999]收益系数刻意高于风险系数: 满层金币 ×%.2f / 经验 ×%.2f, 而血量只 ×%.2f —— 选诅咒必须是净赚。[/color]" % [
		curse_coin_mult_at(CURSE_MAX), xp_mult_at(CURSE_MAX), curse_hp_mult_at(CURSE_MAX)])
	# 波间事件: 每波强制随机一条、波末消失, 与诅咒层数正交(事件被动抽、诅咒主动买)。
	# 迭代 WAVE_CURSES 现场生成 → 调参/增删事件图鉴自动跟随, 不漂移
	out.append("")
	out.append("[color=#57C7D6]波间事件[/color]  每波强制随机一条, 波末消失")
	out.append("[color=#999999]与诅咒层数互不干扰, 可叠加。开战横幅会播报当前事件, 整波生效。[/color]")
	for c in WAVE_CURSES:
		out.append("[color=#E6F2F5]%s[/color]  [color=#999999]%s[/color]" % [str(c["name"]), str(c["desc"])])
	return out


# 图鉴图标: 取 SpriteFrames 第一个动画的首帧作 Texture2D(杂兵/ Boss 无独立预览图)
# 巨魔帧宽 64, 用 KEEP_ASPECT_CENTERED 显示时自动等比缩放, 不需要单独处理
var _codex_frame_cache := {}

func codex_frame_texture(cache_key: String, specs: Array) -> Texture2D:
	if _codex_frame_cache.has(cache_key):
		return _codex_frame_cache[cache_key]
	var first_spec: Array = specs[0]
	var sheet: Texture2D = texture_for(str(first_spec[1]))
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(0.0, 0.0, float(int(first_spec[2])), float(int(first_spec[3])))
	_codex_frame_cache[cache_key] = at
	return at


# 敌人词缀(行为多样性): 刷怪时按波次概率附加, 改变数值/行为/外观
#   mult  数值倍率(hp/speed/size 乘到敌人基础属性)
#   regen 每秒回血(HP/s); shooter 开火间隔; split 死亡分裂数; explode 死亡自爆半径/伤害
#   unlock 该词缀进入词缀池的波次(roll_enemy_affix 与图鉴共用, 不在两处各写一遍)
#   note   图鉴文案: 玩家该知道的"怎么应对", 不重复数值
const ENEMY_AFFIXES := {
	"swift":     {"name": "疾风", "color": Color(0.55, 0.90, 1.0), "mult": {"hp": 0.9, "speed": 1.55, "size": 0.85},
		"unlock": 3, "note": "淡蓝色调、体型缩小。速度是普通怪的 1.5 倍以上, 会率先贴上来 —— 别等它近身, 看到就掉头拉开, 用范围武器顺路扫掉。"},
	"tanky":     {"name": "坚韧", "color": Color(0.80, 0.45, 0.20), "mult": {"hp": 2.2, "speed": 0.72, "size": 1.25},
		"unlock": 3, "note": "橙褐色、体型放大。血厚但走得慢, 是移动的墙 —— 绕着它打, 不要为了赶时间正面穿过去。"},
	"regen":     {"name": "再生", "color": Color(0.45, 0.95, 0.45), "mult": {"hp": 1.15}, "regen": 3.0,
		"unlock": 4, "note": "鲜绿色调。每秒回 3 血, 输出不够就会被它耗着回满。要么一波带走, 要么先清掉周围小怪再集火它。"},
	"shooter":   {"name": "射手", "color": Color(1.0, 0.75, 0.30), "mult": {"hp": 1.0}, "interval": 2.2,
		"unlock": 6, "note": "橙黄色调。远程开火, 站在原地等它靠近是最亏的打法。优先击杀, 或者用走位让别的怪挡在弹道上。"},
	"split":     {"name": "分裂", "color": Color(1.0, 0.55, 0.75), "mult": {"hp": 0.9}, "split": 2,
		"unlock": 7, "note": "粉色调。死亡后裂成 2 只更小的(更小更快、经验减半)。人堆里杀它等于凭空多出两个目标, 尽量把它引到外围单独处理。"},
	"explosive": {"name": "自爆", "color": Color(1.0, 0.35, 0.20), "mult": {"hp": 1.0, "speed": 1.1}, "explode_r": 42.0, "explode_dmg": 22.0,
		"unlock": 8, "note": "红橙色调、微加速。死亡原地爆炸, 半径 42 内吃 22 点伤害 —— 这是后期最容易被秒的方式。绝不要在贴身时补最后一刀, 留距离用远程收。"},
}


# 精英档(风险收益的"高威胁个体"): 双词缀 + 紫色光环 + 大幅数值, 掉大额金币与宝箱
# **刻意不进 ENEMY_AFFIXES** —— 精英与词缀是正交维度, 不是第 7 个词缀:
#   1. affix_pool()/roll_enemy_affix() 会把它当普通词缀抽中, 概率模型崩
#   2. _cx_entry_ids() 会以 "af_elite" 混进图鉴词缀列(前缀串类)
#   3. 词缀 mult 只支持 hp/speed/size 三键, 精英要 xp/coin/item_drop/aura 四类新语义
#   4. 精英本身携带两个词缀, 与 affix 是"叠加"而非"替代"关系
const ELITE_BASE := {
	"name": "精英", "tint": Color(0.55, 0.30, 0.95),
	"hp": 2.6, "damage": 1.6, "speed": 1.10, "size": 1.35,
	"xp": 3.0, "coin_n": 3, "coin_value": 12, "item_drop": 0.25,
	"aura_r": 22.0, "aura_speed": 1.6,
	"hit_r": 1.15,   # 碰撞放大 < 视觉放大(1.35), 避免"打空气也掉血"
	"note": "身缠紫色光环的双词缀头目 —— 词缀怪里有极小概率升格而来(第 4 波起, 越晚越高)。优先集火: 它掉 3 枚大额金币(每枚 12), 还有 1/4 概率掉宝箱(= 白拿一次三选一)。但它同时带两条词缀, 可能是「自爆 + 疾风」这种贴脸就炸的组合, 不要用近战武器收尾。",
}


# 词缀池: 由 ENEMY_AFFIXES 的 unlock 字段派生(当前波次 >= unlock 即入池)
func affix_pool(w: int) -> Array:
	var pool: Array = []
	for k in ENEMY_AFFIXES.keys():
		if w >= int(ENEMY_AFFIXES[k].get("unlock", 3)):
			pool.append(str(k))
	return pool


# 按当前波次掷一个词缀: 波次越深概率越高, 稀有词缀后期才解锁(波 1~2 无词缀保新手平滑)
# 封顶值随诅咒放宽(0.28 → 0.28 + L*0.02); 图鉴 af_ 条目同步读 curse_affix_bonus() 才不说谎
func roll_enemy_affix() -> String:
	var w: int = wave
	if w < 3:
		return ""
	# 血月事件(affix ×2): 掷骰概率与封顶**一起**翻倍 —— 只翻概率不翻封顶的话,
	# 深波次概率早已贴顶, ×2 会被 clamp 吃掉等于没翻
	var bm: float = wc_f("affix", 1.0)
	var chance := clampf((0.05 + float(w) * 0.02) * bm, 0.0, (0.28 + curse_affix_bonus()) * bm)
	if _rng.randf() > chance:
		return ""
	var pool: Array = affix_pool(w)
	if pool.is_empty():
		return ""
	return pool[_rng.randi_range(0, pool.size() - 1)]


# 精英掷骰(独立于词缀的正交维度, 见 ELITE_BASE 注释): **必须先掷中词缀才可能成精英** ——
# 语义就是"词缀怪里的极小概率升格", 无词缀裸怪不配精英光环。门槛比词缀晚一波(3→4):
# 玩家先认识词缀(第 3 波)再认识精英(第 4 波), 认知曲线不平铺。出率随波次三档爬坡 + 诅咒加成。
func roll_elite(affix: String) -> bool:
	if wave < 4 or affix == "":
		return false
	var base := 0.02
	if wave >= 9:
		base = 0.06
	elif wave >= 6:
		base = 0.04
	return _rng.randf() < (base + curse_elite_bonus()) * wc_f("elite", 1.0)


# 第二词缀(精英专属): 从当前词缀池剔除 affix1 后均匀抽。
# **必须剔除同词缀**: "分裂+分裂"会一次生 4 只子代; "再生+再生"后者覆盖前者(行为参数是
# 赋值不是累加)→ 数值不诚实。池里只剩 affix1 一种时返回 ""(退化为单词缀精英, 不硬凑)。
func roll_enemy_affix2(affix1: String) -> String:
	var pool: Array = []
	for a in affix_pool(wave):
		if a != affix1:
			pool.append(a)
	if pool.is_empty():
		return ""
	return pool[_rng.randi_range(0, pool.size() - 1)]


# ================= 三选一生成 =================
# 返回 3 个选项, 每项: {"id","kind","name","desc","rarity","next_level","max_level"}
# kind = "weapon" | "upgrade" | "evolution" | "overlimit"(满配后的无限成长兜底, 见 OVERLIMIT)
# rarity 驱动卡框/名称/选中框配色(见 hud.gd 的 _rarity_* 系列), 与 SHOP_OFFERS 同一套体系:
#   upgrade 普通(灰) / weapon 精良(蓝) / evolution 传说(金)
func roll_upgrade_options() -> Array:
	var pool: Array = []
	# 武器(只列尚未满级的)
	for w in WEAPONS:
		var lv: int = 0
		if player != null and player.has_weapon(w):
			lv = player.weapon_levels[w]
		if lv < WEAPONS[w]["max_level"]:
			# 新武器(0级)权重 x5, 前期更快凑齐三件套(单武器清不动前中期围殴)
			var weight := 5 if lv == 0 else 1
			var opt := {"id": w, "kind": "weapon", "name": WEAPONS[w]["name"],
				"rarity": "uncommon",
				"next_level": lv + 1, "max_level": WEAPONS[w]["max_level"], "weight": weight,
				# 逐级文案读 WEAPON_LEVELS(与图鉴/角色选择屏同源): 玩家点之前就看见"这级买的是什么"。
				# 原先恒为字面量"获得/升级武器" —— 七把武器的 Lv2 卡面完全一样, 这是升级同质化的
				# 主因之一(aura 的 Lv2 半径跳增是全场唯一做了差异化的, 却因为读不到而白做)。
				"desc": weapon_option_desc(w, lv + 1)}
			# 新武器卡附特性标签(见 WEAPON_TRAITS): 抽之前就知道这把能挂什么状态
			if lv == 0 and WEAPON_TRAITS.has(w):
				opt["trait"] = String(WEAPON_TRAITS[w]["status"])
			pool.append(opt)
	# 通用强化
	for u in UPGRADES:
		var lv: int = 0
		if player != null:
			lv = player.stat_levels[u]
		if lv < UPGRADES[u]["max_level"]:
			pool.append({"id": u, "kind": "upgrade", "name": UPGRADES[u]["name"],
				"rarity": "common",
				"next_level": lv + 1, "max_level": UPGRADES[u]["max_level"], "weight": 1,
				"desc": UPGRADES[u]["desc"]})
	# 进化(满级武器 + 满级配对被动, 尚未进化; 高权重优先出现)
	for w in EVOLUTIONS:
		var evo: Dictionary = EVOLUTIONS[w]
		if player == null or not player.has_weapon(w):
			continue
		if player.is_evolved(w):
			continue
		if player.weapon_levels.get(w, 0) < WEAPONS[w]["max_level"]:
			continue
		if player.stat_levels.get(evo["passive"], 0) < UPGRADES[evo["passive"]]["max_level"]:
			continue
		pool.append({"id": w, "kind": "evolution", "name": evo["name"],
			"rarity": "legendary",
			"weight": 5, "desc": evo["desc"]})

	# 加权不重复抽 3 个
	var chosen: Array = []
	var candidates := pool.duplicate()
	for i in range(3):
		if candidates.is_empty():
			break
		var picked := _weighted_pick(candidates)
		chosen.append(picked)
		candidates.erase(picked)

	# 无限成长兜底(2026-09-09): 常规池抽干(满配)后凑不满 3 张 => 用超限项补齐。
	# 常规池非空时超限项**不进池**(前期不该稀释正常选择); 池空时三张全是超限, 升级永远有得点。
	# 补齐发生在 weighted pick 之后, 不影响常规项的抽取手感。
	while chosen.size() < 3:
		var over := _roll_overlimit_option(chosen)
		if over.is_empty():
			break   # 理论上到不了(OVERLIMIT 6 项 > 3), 防御性退出防死循环
		chosen.append(over)
	return chosen


# 抽一个超限项(不与已选中的超限项重复): kind="overlimit", next_level 字段沿用
# (值 = 当前层数+1, hud 卡片与 autopilot 读它不崩), max_level 给 0 表示不封顶
func _roll_overlimit_option(exclude: Array) -> Dictionary:
	var taken := {}
	for o in exclude:
		if String(o.get("kind", "")) == "overlimit":
			taken[String(o["id"])] = true
	var ids: Array = []
	for id in OVERLIMIT:
		if not taken.has(id):
			ids.append(id)
	if ids.is_empty():
		return {}
	var id: String = ids[_rng.randi_range(0, ids.size() - 1)]
	var cfg: Dictionary = OVERLIMIT[id]
	var lv: int = 0
	if player != null:
		lv = int(player.overlimit_levels.get(id, 0))
	return {"id": id, "kind": "overlimit", "name": cfg["name"],
		"rarity": "common",
		"next_level": lv + 1, "max_level": 0, "weight": 1,
		"desc": cfg["desc"]}


func _weighted_pick(candidates: Array) -> Dictionary:
	var total := 0.0
	for c in candidates:
		total += float(c["weight"])
	var r := _rng.randf_range(0.0, total)
	var acc := 0.0
	for c in candidates:
		acc += float(c["weight"])
		if r <= acc:
			return c
	return candidates[-1]


# ================= 应用升级 =================
func apply_upgrade(option: Dictionary) -> void:
	if player == null:
		return
	match option["kind"]:
		"weapon":
			player.gain_weapon(option["id"])
		"evolution":
			player.evolve_weapon(option["id"])
		"overlimit":
			player.gain_overlimit(option["id"])
		_:
			player.gain_stat(option["id"])