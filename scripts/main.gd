extends Node2D
## Main — 主控: 装配战斗场景(玩家/相机/spawner/UI), 管理状态流转与升级/Boss 预告

var player: CharacterBody2D = null
var camera: Camera2D = null
var spawner: Node = null
var hud: CanvasLayer = null

# 地图: 每局随机一张风格; 记录当前风格与地面节点, 供重开时清理重建
var _ground_style: int = 0
var _ground_nodes: Array = []


func _ready() -> void:
	GameManager.main = self
	ObjectPool.main = self
	# 关窗请求由 _notification 接管(战斗中先写续玩档再退), 不让引擎直接吞掉
	get_tree().set_auto_accept_quit(false)

	# 场景重载(restart)后清残留: 对象池旧节点与实体列表均指向已释放的旧场景
	ObjectPool.reset()
	GameManager.enemies.clear()
	GameManager.gems.clear()
	GameManager.projectiles.clear()

	_build_ground()
	_build_player()
	_build_camera()
	_build_spawner()
	_build_hud()
	_prewarm_pools()

	# 开局进入主菜单(命令行含 --autostart 时直接开战, 便于无头测试)
	# --codex-check: 走查图鉴全部 tab × 条目(无测试框架, 靠这类自检 + autopilot 战报验证)
	var user_args := OS.get_cmdline_user_args()
	# 测试专用难度覆盖(0 简单 / 1 普通 / 2 困难): 只改内存值, 绝不落盘 ——
	# save_settings 已被 test_mode gate, 反向判据天然安全(带参数即测试跑)。
	# 困难档冒烟靠它压难度曲线上限(敌血 ×1.30 / 敌伤 ×1.35 / 刷怪 ×0.75)
	var di := user_args.find("--difficulty")
	if di != -1 and di + 1 < user_args.size():
		var ds: String = str(user_args[di + 1])
		# is_valid_int 先挡: int("abc") 在 GDScript 静默返回 0, 会把困难档冒烟悄悄跑成简单档
		if not ds.is_valid_int() or int(ds) < 0 or int(ds) > 2:
			push_warning("--difficulty 非法(需 0/1/2), 回退 1: " + ds)
		else:
			Settings.difficulty = int(ds)
	# 测试跑一律把倍速钉回 1.0(2026-09-10): Settings 从真实 settings.cfg 读 game_speed,
	# 而它经 apply_game_speed 写 Engine.time_scale —— 玩家调过三倍速后, 所有冒烟与自检就
	# 静默跑在 3× 时间下: --quit-after 的帧数覆盖的游戏时长缩到 1/3、战报 fps 字段失去意义、
	# 依赖"跑够 N 帧到第 12 波"的命令全部提前硬退。这是与 difficulty 同构的测试隔离缺口。
	# 只改内存不落盘(save_settings 已 gate)。要测倍速本身用 --speed <f>。
	var spd_i := user_args.find("--speed")
	if spd_i != -1 and spd_i + 1 < user_args.size():
		var sv := float(str(user_args[spd_i + 1]))
		if sv < 0.5 or sv > 3.0:
			push_warning("--speed 非法(需 0.5~3.0), 回退 1.0: " + str(user_args[spd_i + 1]))
			Settings.game_speed = 1.0
		else:
			Settings.game_speed = sv
	else:
		Settings.game_speed = 1.0
	Settings.apply_game_speed()
	if user_args.has("--codex-check"):
		hud.codex_self_check()   # 内部 await 帧做布局测量, 跑完自行 quit
	elif user_args.has("--resume-check"):
		_resume_check()          # 局内存档 save→load→resume 全链路自检, 跑完自行 quit
	elif user_args.has("--overlimit-check"):
		_overlimit_check()       # 满配池空 → 无限成长兜底自检, 跑完自行 quit
	elif user_args.has("--death-check"):
		_death_check()           # 死亡→结算→重开/回菜单 全链路自检, 跑完自行 quit
	elif user_args.has("--menu-check"):
		_menu_check()            # 各界面键盘输入链自检(真实 _unhandled_input 路径), 跑完自行 quit
	elif user_args.has("--weapon-check"):
		_weapon_check()          # 七武器×进化逐一真实伤害自检, 跑完自行 quit
	elif user_args.has("--char-check"):
		_char_check()            # 五角色被动逐一生效自检, 跑完自行 quit
	elif user_args.has("--affix-check"):
		_affix_check()           # 六词缀行为 + 精英双词缀逐一生效自检, 跑完自行 quit
	elif user_args.has("--codex-shot"):
		hud.codex_shots()        # 带窗口 exe 逐 tab 截图存 PNG, 跑完自行 quit
	elif user_args.has("--ui-shot"):
		_ui_shots()              # 带窗口 exe 逐界面截图存 PNG, 跑完自行 quit
	elif user_args.has("--autostart"):
		var cid := "apprentice"
		var i := user_args.find("--char")
		if i != -1 and i + 1 < user_args.size():
			cid = str(user_args[i + 1])
		start_game(cid, GameManager.CHARACTERS[cid]["weapon"])
	else:
		show_menu()


# ================= 场景装配 =================

func _build_ground() -> void:
	var b := GameManager.BOUND
	var iw := int(b.size.x)
	var ih := int(b.size.y)
	var T := GameManager.TILE

	# 优先加载离线烘焙的地图成品图(assets/maps/ground_map_<style>.png, Python 生成), 缺失时回退程序化草地
	if _load_baked_ground(b):
		return

	# 程序化生成草原地形纹理(一次性, 固定种子 => 每局布局一致)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260906

	var cols := int(ceil(iw / float(T)))
	var rows := int(ceil(ih / float(T)))

	# 1) 每格基础草色: 棋盘微差 + 随机明暗抖动, 拼出草坪质感
	for cy in range(rows):
		for cx in range(cols):
			var base := Color(0.34, 0.60, 0.28)
			base = base.lightened(0.035) if (cx + cy) % 2 == 0 else base.darkened(0.035)
			var j := rng.randf_range(-0.035, 0.035)
			base = Color(clampf(base.r + j * 0.6, 0.0, 1.0),
				clampf(base.g + j, 0.0, 1.0),
				clampf(base.b + j * 0.6, 0.0, 1.0))
			img.fill_rect(Rect2i(cx * T, cy * T, T, T), base)

	# 2) 细节: 深色草叶短竖线 + 偶发小花(黄/白); set_pixel 不裁剪, 越界需守卫
	for cy in range(rows):
		for cx in range(cols):
			var ox := cx * T
			var oy := cy * T
			for k in range(rng.randi_range(1, 3)):
				var px := ox + rng.randi_range(2, T - 3)
				var py := oy + rng.randi_range(2, T - 4)
				if px < iw and py + 1 < ih:
					img.set_pixel(px, py, Color(0.24, 0.47, 0.20))
					img.set_pixel(px, py + 1, Color(0.28, 0.53, 0.22))
			if rng.randf() < 0.07:
				var fx := ox + rng.randi_range(4, T - 5)
				var fy := oy + rng.randi_range(4, T - 5)
				if fx < iw and fy < ih:
					img.set_pixel(fx, fy, Color(1.0, 0.95, 0.45) if rng.randf() < 0.5 else Color(1.0, 1.0, 1.0))

	var ground := TextureRect.new()
	ground.texture = ImageTexture.create_from_image(img)
	ground.position = Vector2.ZERO
	ground.size = b.size
	ground.stretch_mode = TextureRect.STRETCH_SCALE
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground.z_index = -10
	add_child(ground)

	# 战场边界: 土色描边(草坪外圈的泥土步道, 给出明确边界)
	_add_edge_rects(b)


func _load_baked_ground(b: Rect2) -> bool:
	var path := "res://assets/maps/ground_map_%d.png" % _ground_style
	if not ResourceLoader.exists(path):
		return false
	var tex: Texture2D = load(path)
	var ground := TextureRect.new()
	ground.texture = tex
	ground.position = Vector2.ZERO
	ground.size = b.size
	ground.stretch_mode = TextureRect.STRETCH_SCALE
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground.z_index = -10
	add_child(ground)
	_ground_nodes.append(ground)
	return true


# 随机换一张地图风格(进入游戏时调用): 清理旧地面节点, 重新随机 + 重建
# style >= 0 时用指定风格(存档恢复), -1 走随机
func _randomize_map(style: int = -1) -> void:
	_clear_ground()
	if style >= 0:
		_ground_style = style
	else:
		_ground_style = GameManager._rng.randi_range(0, GameManager.MAP_STYLE_COUNT - 1)
	_build_ground()


# 回收地面节点(TextureRect)
func _clear_ground() -> void:
	for n in _ground_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_ground_nodes.clear()


func _add_edge_rects(b: Rect2) -> void:
	_add_edge_rect(Vector2(0, 0), Vector2(b.end.x, 3))
	_add_edge_rect(Vector2(0, b.end.y - 3), Vector2(b.end.x, 3))
	_add_edge_rect(Vector2(0, 0), Vector2(3, b.end.y))
	_add_edge_rect(Vector2(b.end.x - 3, 0), Vector2(3, b.end.y))


func _add_edge_rect(pos: Vector2, size: Vector2) -> void:
	var r := ColorRect.new()
	r.color = Color(0.42, 0.31, 0.19, 1.0)   # 泥土棕
	r.position = pos
	r.size = size
	r.z_index = -1
	add_child(r)


func _build_player() -> void:
	player = CharacterBody2D.new()
	player.set_script(load("res://scripts/player.gd"))
	player.name = "Player"

	# 先装配子节点, 再入树(避免 _ready 触发时找不到子节点)
	# 真 32×32 动画精灵(AnimatedSprite2D), scale=1, 帧集由 player.setup_character 注入
	var s := AnimatedSprite2D.new()
	s.name = "Sprite2D"
	player.add_child(s)

	var weapons := Node2D.new()
	weapons.name = "Weapons"
	player.add_child(weapons)

	var cshape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = GameManager.PLAYER_RADIUS
	cshape.shape = circle
	player.add_child(cshape)

	add_child(player)
	player.global_position = GameManager.BOUND.get_center()
	player.died.connect(_on_player_died)


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.name = "Camera"
	# 像素风标准: 关平滑 + 整数吸附, 避免亚像素抖动
	camera.position_smoothing_enabled = false
	add_child(camera)
	camera.make_current()
	GameManager.camera = camera

	camera.global_position = player.global_position


func _build_spawner() -> void:
	spawner = Node.new()
	spawner.set_script(load("res://scripts/spawner.gd"))
	spawner.name = "Spawner"
	add_child(spawner)


func _prewarm_pools() -> void:
	ObjectPool.prewarm("bullet", "res://scripts/bullet.gd", 400)
	ObjectPool.prewarm("enemy", "res://scripts/enemy.gd", 300)
	ObjectPool.prewarm("boss", "res://scripts/boss.gd", 4)
	ObjectPool.prewarm("gem", "res://scripts/gem.gd", 300)
	ObjectPool.prewarm("coin", "res://scripts/coin.gd", 200)
	ObjectPool.prewarm("pickup", "res://scripts/pickup.gd", 20)
	ObjectPool.prewarm("effect", "res://scripts/effect.gd", 60)
	ObjectPool.prewarm("pixel_fx", "res://scripts/pixel_fx.gd", 60)
	ObjectPool.prewarm("damage_number", "res://scripts/damage_number.gd", 80)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.set_script(load("res://scripts/hud.gd"))
	hud.name = "HUD"
	add_child(hud)


# ================= 状态流转 =================

func show_menu() -> void:
	GameManager.state = GameManager.State.MENU
	GameManager.play_bgm("menu")
	hud.show_menu()


func _enter_character_select() -> void:
	GameManager.state = GameManager.State.CHARACTER_SELECT
	GameManager.play_bgm("menu")
	hud.show_character_select()


func start_game(char_id: String, weapon_id: String = "") -> void:
	# 新开局即放弃旧局: 单槽存档直接删(结算路径 game_over/on_final_boss_defeated 也会删, 这里兜底)
	GameManager.clear_suspend()
	GameManager.current_character = char_id
	if weapon_id != "":
		GameManager.current_weapon = weapon_id
	elif GameManager.current_weapon == "":
		GameManager.current_weapon = GameManager.CHARACTERS[char_id]["weapon"]
	# 重置战斗数据
	GameManager.time_s = 0.0
	GameManager.kills = 0
	GameManager.boss_kills = 0
	GameManager.level = 1
	GameManager.xp = 0.0
	GameManager.coins = 0.0
	GameManager.curse_level = 0      # 诅咒是 run 级状态, 不跨局
	GameManager.levelup_rerolls = 0  # 升级三选一重抽每局重置
	GameManager.final_boss_spawned = false
	GameManager.wave = 0
	GameManager.wave_time = 0.0
	# 换张随机地图(清理旧地面再重建), 每次开局都随机
	_randomize_map()
	spawner.reset_run()
	GameManager.player.init_character(char_id, GameManager.current_weapon)
	# 归位到战场中心: 不 reload 场景的重开会沿用上一局位置, 必须显式复位
	GameManager.player.global_position = GameManager.BOUND.get_center()
	GameManager.state = GameManager.State.PLAYING
	GameManager.play_bgm("battle")
	hud.show_hud()


# 恢复局内存档(土豆兄弟式单槽续玩): 镜像 start_game 的重建路径, 但 build 字段全部来自存档。
# 读档即消费(立刻删档): 再退再存, 崩溃不会复活旧档。坏档 load_suspend 已清, 回主菜单兜底。
func resume_run() -> void:
	var data := GameManager.load_suspend()
	if data.is_empty():
		show_menu()
		return
	var run: Dictionary = data["run"]
	var sp: Dictionary = data["spawner"]
	var p: Dictionary = data["player"]
	GameManager.clear_suspend(true)   # 读档即消费: 删的是刚读进来的这份(自检夹具档), force 绕 test gate

	# 运行态回填
	GameManager.current_character = str(run["char_id"])
	GameManager.current_weapon = str(run["weapon_id"])
	GameManager.time_s = float(run["time_s"])
	GameManager.wave = int(run["wave"])
	GameManager.wave_time = float(run["wave_time"])
	GameManager.kills = int(run["kills"])
	GameManager.boss_kills = int(run["boss_kills"])
	GameManager.level = int(run["level"])
	GameManager.xp = float(run["xp"])
	GameManager.coins = float(run["coins"])
	GameManager.levelup_rerolls = int(run["levelup_rerolls"])
	GameManager.curse_level = int(run["curse"])
	GameManager.set_wave_curse(str(run.get("wave_curse", "")))   # 当前波事件回填(旧档无键 = 无事件)
	GameManager.final_boss_spawned = bool(run["final_boss_spawned"])
	GameManager._rng.state = int(run["rng_state"])   # 刷怪随机流续接
	GameManager.wave_took_damage = false

	# 场景重建: 清残留实体 + 按存档风格重建地图(不 reload 场景)
	_clear_entities()
	_randomize_map(int(data["map_style"]))

	# 玩家: init_character 完整重置(清武器节点/出生保护), 再用存档 build 覆盖
	GameManager.player.init_character(GameManager.current_character, GameManager.current_weapon)
	GameManager.player.base_max_hp = float(p["base_max_hp"])
	GameManager.player.base_move_speed = float(p["base_move_speed"])
	GameManager.player.base_pick_range = float(p["base_pick_range"])
	GameManager.player.char_damage_mult = float(p["char_damage_mult"])
	GameManager.player.char_proj_speed_mult = float(p["char_proj_speed_mult"])
	GameManager.player.heal_mult = float(p["heal_mult"])
	GameManager.player.stat_levels = p["stat_levels"]
	GameManager.player.item_mods = p["item_mods"]
	GameManager.player.overlimit_levels = p["overlimit_levels"]
	# 武器按存档等级重建实例(绕过 gain_weapon 的首获「军械」加成, 防恢复一次加一级)
	GameManager.player.restore_weapons(p["weapon_levels"], p["evolved_weapons"])
	GameManager.player.hp = float(p["hp"])
	GameManager.player.recalc_stats()
	# 归位到战场中心: 玩家位置不入档(实体不存), 恢复点与开局一致
	GameManager.player.global_position = GameManager.BOUND.get_center()

	# spawner 计时器回填: 波内进度/刷怪节奏从存档点续走(预警叉不存, 恢复时场上无叉)
	spawner._spawn_timer = float(sp["spawn_timer"])
	spawner._wave_timer = float(sp["wave_timer"])
	spawner._interval = float(sp["interval"])
	spawner._weights = sp["weights"]
	spawner._telegraphs.clear()

	# Boss 波重摆: 实体不入档, 波 4/8/12 退出时 Boss 还活着的话必须重新排叉,
	# 否则波 12 永远等不到终极 Boss(通关无门 = 软锁)。已击杀的按 boss_kills 计数跳过。
	_respawn_wave_boss()

	GameManager.state = GameManager.State.PLAYING
	GameManager.play_bgm("boss" if _wave_has_boss() else "battle")
	hud.show_hud()


# 当前存档波次是否是 Boss 波(决定恢复时的 BGM)
func _wave_has_boss() -> bool:
	if GameManager.wave < 1 or GameManager.wave > spawner.WAVES.size():
		return false
	return str(spawner.WAVES[GameManager.wave - 1][3]) != ""


# 存档恢复时的 Boss 重摆: 中 Boss 只在该波还没杀掉对应只数时补(波 4→第 1 只 / 波 8→第 2 只 /
# 波 12→第 3 只), 终极 Boss 一律补(被杀即 VICTORY, 不可能带着已杀的终极 Boss 进恢复流程)。
func _respawn_wave_boss() -> void:
	if not _wave_has_boss():
		return
	var kind: String = str(spawner.WAVES[GameManager.wave - 1][3])
	var expect_killed := 1
	if GameManager.wave == 8:
		expect_killed = 2
	elif GameManager.wave == 12:
		expect_killed = 3
	if kind == "boss" and GameManager.boss_kills < expect_killed:
		spawner._spawn_boss(GameManager.boss_kills + 1)
	elif kind == "final":
		if GameManager.boss_kills < expect_killed:
			spawner._spawn_boss(GameManager.boss_kills + 1)
		spawner._spawn_final_boss()


# 关窗请求: 战斗中先写续玩档再退(set_auto_accept_quit(false) 把 quit 交到这里)。
# headless --quit-after 强杀不走通知 => 冒烟测试不会留档, 与 test_mode gate 双保险。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if GameManager.state == GameManager.State.PLAYING:
			GameManager.save_suspend()
		get_tree().quit()


# 诅咒值变化(局内道具 / 波间商店): 转发 HUD 刷新标签。
# 走 main 而不是 GameManager 直接摸 hud —— 与 trigger_level_up/announce_wave 同一约定。
# 商店暂停中 game_hud 已被 _clear_all 清掉, 此处刷新是空操作; close_wave_shop 重建 HUD 时
# show_hud 末尾会再刷一次, 标签不会丢。
func on_curse_changed() -> void:
	if hud != null:
		hud.update_curse_label()


func trigger_level_up() -> void:
	GameManager.state = GameManager.State.LEVEL_UP
	# 土豆兄弟式: 升级不回血, 血线压力全程保留; 回血只能靠商店消费/道具/升级选「生命强化」
	GameManager.play_sfx("levelup")
	get_tree().paused = true
	hud.show_level_up(GameManager.roll_upgrade_options())


# 波间商店: 由 spawner 在每波结束(非最后一波)时调用
func open_wave_shop() -> void:
	GameManager.state = GameManager.State.SHOP
	GameManager.roll_shop()   # 进店即抽 5 件展示(无刷新, 一次定盘)
	get_tree().paused = true
	hud.show_wave_shop()


# 波间商店关闭: 推进下一波并恢复战斗
func close_wave_shop() -> void:
	get_tree().paused = false
	GameManager.state = GameManager.State.PLAYING
	spawner._start_wave(GameManager.wave + 1)
	hud.show_hud()


func on_upgrade_chosen(option: Dictionary) -> void:
	# 三种路径: 进化(暂停聚气+释放) / 新武器(不暂停, 战斗内横幅) / 普通升级(轻量闪白)
	var is_evo: bool = option["kind"] == "evolution"
	var is_new_weapon: bool = option["kind"] == "weapon" and not GameManager.player.has_weapon(option["id"])
	GameManager.apply_upgrade(option)
	# 立即脱离 LEVEL_UP 防重入(autopilot 每帧轮询 state==LEVEL_UP, await 期间不漏改 state 会重复 apply)
	GameManager.state = GameManager.State.PLAYING
	if is_evo:
		await _evo_ceremony(GameManager.EVOLUTIONS[option["id"]]["name"])
		return
	# 进化以外: 先恢复战斗并重建 HUD(清掉三选一卡片), 再叠加演出, 避免横幅被 _clear_all 清掉
	get_tree().paused = false
	hud.show_hud()
	if is_new_weapon:
		_new_weapon_flourish(GameManager.WEAPONS[option["id"]]["name"])
	else:
		_levelup_flourish()


# 进化演出: 暂停聚气(横幅转写) → 恢复释放(冲击环 + 震屏 + 闪金) → 重建战斗 HUD
# 防卡死(2026-09-09): 协程 await 期间 state 已是 PLAYING 但 paused=true —— 这个窗口
# 内 ESC 开设置/宝箱二开三选一都会让界面易主; 协程醒来必须先验 state 仍归战斗,
# 否则弃权(不动 paused 不动 HUD, 交给当前界面的持有者管), 否则会拆掉新界面
# 留下"世界在跑、输入按已消失界面路由"的死局。
func _evo_ceremony(title: String) -> void:
	var col := Color(1.0, 0.85, 0.35)
	var p := GameManager.player
	var pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	# 1) 聚气: 仍 paused, HUD 层横幅淡入(create_timer process_always=true 暂停时也推进)
	hud.spawn_evo_banner("⚡ %s ⚡" % title, col)
	await get_tree().create_timer(0.9, true).timeout
	if GameManager.state != GameManager.State.PLAYING:
		return   # 窗口内被 ESC/新升级接管: 当前界面自己管 unpause, 剩余演出弃权
	# 2) 释放: 恢复战斗让世界层粒子动起来, 同时爆发冲击环 + 震屏 + 全屏闪
	get_tree().paused = false
	GameManager.add_shake(8.0)
	GameManager.spawn_ring(pos, col, 150.0)
	GameManager.play_sfx("levelup")
	hud.flash_screen(col, 0.35, 0.42)
	await get_tree().create_timer(0.42).timeout   # 恢复后普通计时即可, 等闪屏淡出
	if GameManager.state != GameManager.State.PLAYING:
		return   # 同理: 0.42s 内又进 LEVEL_UP/SETTINGS, 不 show_hud 拆别人的界面
	hud.show_hud()


# 新武器演出(不暂停, 战斗即时): 蓝色横幅 + 冲击环 + 轻震动, 不打断节奏
func _new_weapon_flourish(title: String) -> void:
	var col := Color(0.5, 0.85, 1.0)
	var p := GameManager.player
	var pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	hud.spawn_evo_banner("获得 · %s" % title, col)
	GameManager.spawn_ring(pos, col, 110.0)
	GameManager.add_shake(3.0)
	GameManager.play_sfx("levelup")


# 普通升级(轻量版, 不打断): 一瞬白闪 + 微震, 无横幅无暂停
func _levelup_flourish() -> void:
	GameManager.add_shake(1.2)
	hud.flash_screen(Color(0.85, 0.9, 1.0), 0.18, 0.30)
	GameManager.play_sfx("levelup")


func _on_player_died() -> void:
	game_over()


func game_over() -> void:
	GameManager.state = GameManager.State.GAME_OVER
	GameManager.clear_suspend()   # 本局已终结, 不留续玩档
	GameManager.stop_bgm()
	GameManager.play_sfx("death")
	GameManager.add_shake(6.0)
	# 死亡也结算: 保留已拾取金币, 存入永久 bank(半途死亡仍有积累)
	GameManager.deposit_run_coins()
	var t: float = GameManager.time_s
	var kills: int = GameManager.kills
	var boss: int = GameManager.boss_kills
	var lv: int = GameManager.level
	var char_name: String = GameManager.CHARACTERS[GameManager.current_character]["name"]
	hud.show_game_over(t, kills, boss, lv, char_name)


# 终极 Boss 被击杀 => 通关(幂等: 已胜利则忽略)
func on_final_boss_defeated() -> void:
	if GameManager.state == GameManager.State.VICTORY:
		return
	GameManager.state = GameManager.State.VICTORY
	GameManager.clear_suspend()   # 本局已终结, 不留续玩档
	GameManager.char_wins[GameManager.current_character] = true   # 全角色通关成就用
	GameManager.unlock_achievement("victory")   # 通关成就(all_chars 由下方 deposit → check_achievements 兜住)
	GameManager.stop_bgm()
	GameManager.play_sfx("levelup")
	GameManager.add_shake(4.0)
	# 通关金币加成 x1.5 + 入账永久 bank
	GameManager.coins = ceilf(GameManager.coins * 1.5)
	GameManager.deposit_run_coins()
	var t: float = GameManager.time_s
	var kills: int = GameManager.kills
	var boss: int = GameManager.boss_kills
	var lv: int = GameManager.level
	var char_name: String = GameManager.CHARACTERS[GameManager.current_character]["name"]
	hud.show_victory(t, kills, boss, lv, char_name)


# 重新开始: 回到角色选择界面(不 reload 场景, 保留已生成的草原地形)
func restart() -> void:
	get_tree().paused = false
	_clear_entities()
	_enter_character_select()


func exit_to_menu() -> void:
	get_tree().paused = false
	_clear_entities()
	show_menu()


# 回收场上所有实体: 敌人/宝石/弹幕走 GameManager 列表; pickup(心/箱)无列表, 扫描子节点
func _clear_entities() -> void:
	for e in GameManager.enemies:
		if is_instance_valid(e):
			ObjectPool.release(e)
	GameManager.enemies.clear()
	for g in GameManager.gems:
		if is_instance_valid(g):
			ObjectPool.release(g)
	GameManager.gems.clear()
	for c in GameManager.coins_list:
		if is_instance_valid(c):
			ObjectPool.release(c)
	GameManager.coins_list.clear()
	for b in GameManager.projectiles:
		if is_instance_valid(b):
			ObjectPool.release(b)
	GameManager.projectiles.clear()
	for c in get_children():
		if c.get_meta("pool_id", "") == "pickup" and c.visible:
			ObjectPool.release(c)
	# 燃烧瓶的火池非池化(生命周期短, 直接 free); 重开时扫 group 清残留
	for z in get_tree().get_nodes_in_group("burn_zone"):
		if is_instance_valid(z):
			z.queue_free()
	# 飞行中的燃烧瓶同理: 未落地, 直接清掉
	for v in get_tree().get_nodes_in_group("holy_vial"):
		if is_instance_valid(v):
			v.queue_free()


func announce_wave(n: int, total: int, boss_kind: String = "") -> void:
	if hud.has_method("announce_wave"):
		hud.announce_wave(n, total, boss_kind)


func announce_boss() -> void:
	GameManager.play_bgm("boss")
	if hud.has_method("announce_boss"):
		hud.announce_boss()


func announce_final_boss() -> void:
	GameManager.play_bgm("boss")
	if hud.has_method("announce_final_boss"):
		hud.announce_final_boss()


# ================= 相机跟随 =================

func _process(delta: float) -> void:
	if camera != null and player != null:
		var cpos := player.global_position
		# 限制相机不越出战场(视口一半), 并整数像素吸附
		var hx := GameManager.VIEW_W / 2.0
		var hy := GameManager.VIEW_H / 2.0
		var b := GameManager.BOUND
		cpos.x = clampf(cpos.x, hx, b.end.x - hx)
		cpos.y = clampf(cpos.y, hy, b.end.y - hy)
		camera.global_position = cpos.round()


func _unhandled_input(event: InputEvent) -> void:
	# ESC: 游戏内(PLAYING)直接进设置; 设置/暂停界面的 ESC 各自在 hud._unhandled_input 里关闭
	if event.is_action_pressed("ui_cancel"):
		if GameManager.state == GameManager.State.PLAYING:
			get_tree().paused = true
			hud.show_settings()


# ================= 局内续玩档自检(--resume-check) =================
# resume_run() 是唯一无法被 autopilot 覆盖的路径(test_mode 下 save_suspend 不落盘 →
# 主菜单永远没有「继续游戏」入口), 故用 save_suspend(force_test) 临时旁路真实写一次档,
# 走 save→load→resume→跑帧全链路, 校验状态往返 + 武器节点重建 + Boss 波重摆 + 坏档清除。
# 自检反复覆写 suspend.cfg, 故开头备份玩家真实档(若有)、结尾还原, 不弄丢进度。
func _resume_check() -> void:
	var total := 0
	var fail := 0
	var bak_path := GameManager.SUSPEND_PATH + ".resumecheck.bak"
	var had_real := FileAccess.file_exists(GameManager.SUSPEND_PATH)
	if had_real:
		var src := FileAccess.open(GameManager.SUSPEND_PATH, FileAccess.READ)
		var content := src.get_buffer(src.get_length())
		src.close()
		var bak := FileAccess.open(bak_path, FileAccess.WRITE)
		bak.store_buffer(content)
		bak.close()

	# ---- 场景1: 普通波(第 3 波)中途存档 → 恢复, 校验 build/运行态/地图往返 ----
	start_game("assassin", "dagger")   # 非默认角色+武器, 验证 char/weapon 也走存档
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p = GameManager.player
	p.gain_weapon("orbit")
	p.gain_weapon("aura")
	p.gain_weapon("wand")
	p.gain_stat("damage")
	p.gain_stat("max_hp")
	p.item_mods["damage_mult"] = 0.30        # 商店式临时修正(原 gain_item 通道已删), 验证 item_mods 往返
	p.item_mods["move_speed_mult"] = -0.10   # 负修正一并覆盖
	p.gain_overlimit("damage")               # 无限成长超限层往返: 乘算键
	p.gain_overlimit("damage")               # 叠两层, 验证层数(不只是"有/无")精确回读
	p.gain_overlimit("max_hp")               # flat 键一并覆盖(它额外走 recalc+heal, hp 在下面重设)
	GameManager.add_curse(1)                 # 诅咒往返(原 cursed_idol 转发链测试随 ITEMS 删除改为此)
	GameManager.levelup_rerolls = 1          # 重抽计数非零, 验证入档/回读(键缺失的旧档走默认 0, 这里测有值路径)
	spawner._start_wave(3)
	GameManager.time_s = 88.0
	GameManager.wave_time = 12.5
	GameManager.kills = 47
	GameManager.boss_kills = 0
	GameManager.level = 6
	GameManager.xp = 13.0
	GameManager.coins = 88.0
	spawner._spawn_timer = 0.7
	spawner._wave_timer = 12.5
	p.hp = 73.0                        # 非满血, 验证 hp 不被 recalc 顶满
	var ground_before: int = _ground_style
	var char_before: String = GameManager.current_character
	var wlv_before: Dictionary = p.weapon_levels.duplicate(true)
	var slv_before: Dictionary = p.stat_levels.duplicate(true)
	var mods_before: Dictionary = p.item_mods.duplicate(true)
	var over_before: Dictionary = p.overlimit_levels.duplicate(true)   # 超限层数(int, 精确比)
	var hp_before: float = p.hp
	var curse_before: int = GameManager.curse_level
	var reroll_before: int = GameManager.levelup_rerolls
	var wpn_count_before: int = p.weapons.size()
	# 波间事件: _start_wave(3) 已强制掷出一条(8 选 1), 存档时必须带上当前事件 id
	var wc_before: String = str(GameManager.wave_curse.get("id", ""))

	GameManager.save_suspend(true)
	total += 1
	if not GameManager.has_suspend():
		print("[RESUME]   FAIL 写档后 has_suspend 仍为 false"); fail += 1
	else:
		print("[RESUME]   ok  save_suspend 落盘且 has_suspend=true")

	# 把内存态改成与存档不同的哨兵值, 逼出真正的"从文件读回"而非"内存没动过"
	# (curse 是 run 级标量, resume_run 直接赋值不夹取, 文件里是 1 → 恢复后必须是 1)
	GameManager.curse_level = 99
	GameManager.levelup_rerolls = 7   # 同上哨兵: 文件里是 1, 读回必须压掉这个 7
	GameManager.set_wave_curse("__sentinel__")   # 非法 id → 静默退化为无事件, 读回必须重建真事件
	resume_run()
	total += 1
	if GameManager.state != GameManager.State.PLAYING:
		print("[RESUME]   FAIL 恢复后 state != PLAYING"); fail += 1
	else:
		print("[RESUME]   ok  恢复后 state=PLAYING")

	total += 1
	if GameManager.current_character != char_before or GameManager.wave != 3 \
		or GameManager.kills != 47 or GameManager.level != 6 or int(GameManager.coins) != 88:
		print("[RESUME]   FAIL 运行态未往返 char=%s wave=%d kills=%d lv=%d coins=%d" % [
			GameManager.current_character, GameManager.wave, GameManager.kills,
			GameManager.level, GameManager.coins]); fail += 1
	else:
		print("[RESUME]   ok  运行态往返 char/wave/kills/level/coins 一致")

	total += 1
	# 重抽计数: 与 curse 同款哨兵手法(写档后改脏成 7), 读回必须压回存档时的值才算真从文件往返
	if GameManager.levelup_rerolls != reroll_before:
		print("[RESUME]   FAIL 重抽计数未往返: 恢复后 %d, 存档时 %d" % [
			GameManager.levelup_rerolls, reroll_before]); fail += 1
	else:
		print("[RESUME]   ok  重抽计数往返 =%d" % reroll_before)

	total += 1
	# weapon_levels/stat_levels 是 int 可精确比; item_mods 是 float, 过 ConfigFile 文本序列化
	# 后按容差比(避免把精度表示差异误判成数据丢失)
	var mods_diff := 0
	if p.item_mods.size() != mods_before.size():
		mods_diff += 1
	else:
		for k in mods_before:
			if not p.item_mods.has(k) or absf(float(p.item_mods[k]) - float(mods_before[k])) > 0.0001:
				mods_diff += 1
	if p.weapon_levels != wlv_before or p.stat_levels != slv_before or mods_diff > 0:
		print("[RESUME]   FAIL build 字段未往返 weapon_levels/stat_levels/item_mods(差 %d 项)" % mods_diff); fail += 1
	else:
		print("[RESUME]   ok  build 往返 weapon_levels(%d)/stat_levels/item_mods(%d) 一致" % [
			wlv_before.size(), mods_before.size()])

	total += 1
	# 无限成长超限层数: int dict 精确比(damage 叠了 2 层、max_hp 叠了 1 层), 验证层数不漏读不重读
	if p.overlimit_levels != over_before:
		print("[RESUME]   FAIL 超限层数未往返: 恢复后 %s, 存档时 %s" % [
			str(p.overlimit_levels), str(over_before)]); fail += 1
	else:
		print("[RESUME]   ok  超限层数往返 %s 一致" % str(over_before))

	total += 1
	if p.weapons.size() != wpn_count_before:
		print("[RESUME]   FAIL 武器节点未重建: 恢复后 %d 件, 存档时 %d 件" % [
			p.weapons.size(), wpn_count_before]); fail += 1
	else:
		var all_valid := true
		for w in p.weapons.values():
			if not is_instance_valid(w):
				all_valid = false
		if not all_valid:
			print("[RESUME]   FAIL 重建的武器节点含失效实例"); fail += 1
		else:
			print("[RESUME]   ok  武器节点重建 %d 件全部有效" % p.weapons.size())

	total += 1
	if absf(p.hp - hp_before) > 0.5:
		print("[RESUME]   FAIL hp 未往返: 恢复 %.1f vs 存档 %.1f" % [p.hp, hp_before]); fail += 1
	else:
		print("[RESUME]   ok  hp 往返 %.1f" % p.hp)

	total += 1
	if _ground_style != ground_before:
		print("[RESUME]   FAIL 地图风格未往返: 恢复 %d vs 存档 %d" % [_ground_style, ground_before]); fail += 1
	else:
		print("[RESUME]   ok  地图风格往返 style=%d" % _ground_style)

	total += 1
	if GameManager.curse_level != curse_before:
		print("[RESUME]   FAIL 诅咒值未往返: 恢复 %d vs 存档 %d" % [GameManager.curse_level, curse_before]); fail += 1
	else:
		print("[RESUME]   ok  诅咒值往返 curse=%d" % GameManager.curse_level)

	# 14. 波间事件往返: 存 id 字符串, 读回 set_wave_curse 重建字典。
	#     哨兵 "__sentinel__" 是非法 id(退化为无事件), 恢复后必须被文件里的真事件压掉;
	#     _start_wave(3) 掷的是随机事件, 用 wc_before 捕获实际掷出的 id
	total += 1
	var wc_after: String = str(GameManager.wave_curse.get("id", ""))
	if wc_after != wc_before:
		print("[RESUME]   FAIL 波间事件未往返: 恢复 '%s' vs 存档 '%s'" % [wc_after, wc_before]); fail += 1
	else:
		print("[RESUME]   ok  波间事件往返 wave_curse=%s" % (wc_before if wc_before != "" else "(无事件)"))

	total += 1
	if GameManager.has_suspend():
		print("[RESUME]   FAIL 读档未即消费: resume_run 后档仍在"); fail += 1
	else:
		print("[RESUME]   ok  读档即消费: resume_run 后档已删")

	# 恢复后跑 30 帧(god-lock 锁血防被打死), 确认 spawner/武器在恢复态下不崩、实体数组无失效对象
	var invalid := 0
	for i in range(30):
		p.hp = p.max_hp_value()
		p.invuln_timer = 1.0
		await get_tree().physics_frame
		for e in GameManager.enemies:
			if not is_instance_valid(e):
				invalid += 1
	total += 1
	if invalid > 0 or GameManager.state != GameManager.State.PLAYING:
		print("[RESUME]   FAIL 恢复后跑帧异常 invalid=%d state=%d" % [invalid, GameManager.state]); fail += 1
	else:
		print("[RESUME]   ok  恢复后跑 30 帧 invalid=0 且仍 PLAYING")

	# ---- 场景2: 终极 Boss 波(第 12 波, boss_kills=3 中 Boss 已全清)存档 → 恢复重摆终极叉 ----
	# 防软锁: 实体不入档, 若恢复后不重排终极 Boss, 第 12 波永远等不到通关目标
	GameManager.wave = 12
	GameManager.boss_kills = 3
	GameManager.wave_time = 5.0
	spawner._wave_timer = 5.0
	GameManager.save_suspend(true)
	resume_run()
	var has_final := false
	for t in spawner._telegraphs:
		if bool(t.get("final", false)):
			has_final = true
	total += 1
	if not has_final:
		print("[RESUME]   FAIL 第 12 波恢复未重摆终极 Boss 叉(通关软锁)"); fail += 1
	else:
		print("[RESUME]   ok  第 12 波恢复重摆终极 Boss 叉")

	# ---- 场景3: 坏档(不可解析)→ has_suspend 返回 false 且自动清档 ----
	var wf := FileAccess.open(GameManager.SUSPEND_PATH, FileAccess.WRITE)
	wf.store_string("[run\nchar_id=\"x\ntime_s=<<<GARBAGE")
	wf.close()
	total += 1
	if GameManager.has_suspend():
		print("[RESUME]   FAIL 坏档仍被判定为有效(has_suspend=true)"); fail += 1
	elif FileAccess.file_exists(GameManager.SUSPEND_PATH):
		print("[RESUME]   FAIL 坏档未被清除(文件仍在)"); fail += 1
	else:
		print("[RESUME]   ok  坏档 has_suspend=false 且已自动清档")

	# ---- 还原玩家真实档, 退出 ----
	GameManager.clear_suspend(true)   # 删自检残留夹具档, 再还原备份
	var dir := DirAccess.open("user://")
	if dir != null:
		if had_real:
			dir.rename(bak_path.get_file(), GameManager.SUSPEND_PATH.get_file())
		elif FileAccess.file_exists(bak_path):
			dir.remove(bak_path.get_file())

	print("[RESUME] FINAL total=%d fail=%d" % [total, fail])
	if fail > 0:
		print("[RESUME] ASSERT-FAIL")
	get_tree().quit()


# ================= 无限成长兜底自检(--overlimit-check) =================
# 为什么必须单独一条: autopilot god 局把武器数封顶在 FOCUS_WEAPONS=3(为了留出升级预算凑进化),
# 常规池里永远剩 4 把 Lv0 武器 => roll_upgrade_options 的**池空兜底分支整局都走不到**,
# 战报里 ov 恒为 0, 长跑通关也证明不了这个功能生效。
# 这条自检把玩家直接摆成满配(7 武器 Lv3 + 9 被动 Lv3 + 7 进化全拿), 强制压池空路径,
# 逐项验「升级永远有得点」+ 数值通道真的接上 + clamp 不失控。跑完自行 quit。
# test_mode 已由 game_manager._ready 的标志扫描置位 => 不落盘、不解锁成就。
func _overlimit_check() -> void:
	var total := 0
	var fail := 0

	start_game("apprentice", "wand")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p = GameManager.player

	# ---- fixture: 满配 ----
	# 武器必须走 restore_weapons(存档恢复的正规路径)而不是只填 weapon_levels 字典:
	# roll_upgrade_options 的武器准入读 has_weapon()(= weapons 字典有节点), 不建节点的话
	# 这 7 把仍被当 Lv0 新武器塞进池, 池永远不空。
	var wl := {}
	var ev := {}
	for w in GameManager.WEAPONS:
		wl[w] = int(GameManager.WEAPONS[w]["max_level"])
	for w in GameManager.EVOLUTIONS:
		ev[w] = true                      # is_evolved() 为真 => 进化项不再进池
	p.restore_weapons(wl, ev)
	for u in GameManager.UPGRADES:
		p.stat_levels[u] = int(GameManager.UPGRADES[u]["max_level"])
	p.item_mods.clear()                   # 清掉道具修正, 下面的倍率比值才能精确推算
	p.recalc_stats()
	p.hp = p.max_hp_value()

	# ---- 1. 池空 => 三张全是超限, 且互不重复 ----
	total += 1
	var opts: Array = GameManager.roll_upgrade_options()
	if opts.size() != 3:
		print("[OVERLIMIT] FAIL 满配后只给出 %d 张卡(应 3)" % opts.size()); fail += 1
	else:
		var kinds := {}
		var ids := {}
		for o in opts:
			kinds[String(o["kind"])] = true
			ids[String(o["id"])] = true
		if kinds.size() != 1 or not kinds.has("overlimit"):
			print("[OVERLIMIT] FAIL 满配后卡池混入非超限项: %s" % str(kinds.keys())); fail += 1
		elif ids.size() != 3:
			print("[OVERLIMIT] FAIL 三张超限卡出现重复 id: %s" % str(ids.keys())); fail += 1
		else:
			print("[OVERLIMIT] ok  满配池空 => 3 张互不重复的超限卡 %s" % str(ids.keys()))

	# ---- 2. 连抽 50 次都凑满 3 张(兜底与 RNG 无关, 空界面路径不可达) ----
	total += 1
	var empty_rolls := 0
	var short_rolls := 0
	for _i in range(50):
		var r: Array = GameManager.roll_upgrade_options()
		if r.is_empty():
			empty_rolls += 1
		elif r.size() < 3:
			short_rolls += 1
	if empty_rolls > 0 or short_rolls > 0:
		print("[OVERLIMIT] FAIL 50 次抽取中 空=%d 不足3张=%d" % [empty_rolls, short_rolls]); fail += 1
	else:
		print("[OVERLIMIT] ok  连抽 50 次均为 3 张(「没有更多强化」界面已不可达)")

	# ---- 3. apply_upgrade 落层, 且不污染 stat_levels ----
	# stat_levels 是常规池准入(`stat_levels[u] < max_level`)与进化前置的判据,
	# 超限层数写进去会让满级被动重新进池 + 伪造进化前置成立 => 门槛语义全坏。
	total += 1
	var slv_before: Dictionary = p.stat_levels.duplicate(true)
	var first_id := String(opts[0]["id"])
	GameManager.apply_upgrade(opts[0])
	var got: int = int(p.overlimit_levels.get(first_id, 0))
	if got != 1:
		print("[OVERLIMIT] FAIL apply_upgrade 后 %s 层数=%d(应 1)" % [first_id, got]); fail += 1
	elif p.stat_levels != slv_before:
		print("[OVERLIMIT] FAIL 超限层数污染了 stat_levels(门槛语义被破坏)"); fail += 1
	else:
		print("[OVERLIMIT] ok  apply_upgrade 落 1 层且 stat_levels 原样未动")

	# ---- 4. 倍率真的动了: damage 每层 +5%, 比值与 OVERLIMIT 表一致 ----
	# 比值法可消掉 char_damage_mult / meta_damage_mult / item_mod 这些常量因子, 无需知道存档里的局外强化
	total += 1
	var d0: float = p.damage_mult()
	# base 必须含**已有超限层**: 断言 3 的 apply_upgrade 从 6 项超限随机抽, 1/6 概率已落过
	# damage 层(2026-09-10 批量回归抓到的 flaky 根因: d0 已带 1 层时比值基准少算一层)。
	# 0.26 与 player.damage_mult 的常规通道硬编码同步(OVERLIMIT 的 0.05 读表, 消魔法数)
	var ov_step: float = float(GameManager.OVERLIMIT["damage"]["value"])
	var base: float = 1.0 + float(int(p.stat_levels["damage"])) * 0.26 \
		+ float(int(p.overlimit_levels.get("damage", 0))) * ov_step
	p.gain_overlimit("damage")
	var d1: float = p.damage_mult()
	var want: float = d0 * (base + ov_step) / base
	if absf(d1 - want) > 1e-6 * maxf(1.0, absf(want)):
		print("[OVERLIMIT] FAIL damage 倍率 %.6f -> %.6f, 应到 %.6f" % [d0, d1, want]); fail += 1
	else:
		print("[OVERLIMIT] ok  damage 倍率 %.4f -> %.4f (+5%%/层, 与表一致)" % [d0, d1])

	# ---- 5. 冷却无限叠层仍被 clamp 兜住(总攻速上限 5x, 不失控) ----
	total += 1
	p.overlimit_levels["cooldown"] = 14        # 14 层 × -3% 已越过 0.2 下限
	var c14: float = p.cooldown_mult()
	p.overlimit_levels["cooldown"] = 1000      # 再叠到 1000 层
	var c1000: float = p.cooldown_mult()
	if not is_equal_approx(c14, 5.0) or not is_equal_approx(c1000, 5.0):
		print("[OVERLIMIT] FAIL 冷却 clamp 失效: 14层=%.4f 1000层=%.4f(应都 5.0)" % [c14, c1000]); fail += 1
	else:
		print("[OVERLIMIT] ok  冷却叠到 1000 层仍锁 5.0x(clamp 下限 0.2 生效)")
	p.overlimit_levels.erase("cooldown")

	# ---- 6. max_hp 是 flat 例外: 上限 +10 并回 10 血 ----
	total += 1
	p.overlimit_levels.erase("max_hp")
	p.recalc_stats()
	var mhp0: float = p.max_hp_value()
	p.hp = mhp0 - 50.0                         # 留出回血空间, 否则 clamp 在上限看不出 heal
	var hp0: float = p.hp
	p.gain_overlimit("max_hp")
	var d_mhp: float = p.max_hp_value() - mhp0
	var d_hp: float = p.hp - hp0
	var want_heal: float = 10.0 * p.heal_mult
	if absf(d_mhp - 10.0) > 1e-4 or absf(d_hp - want_heal) > 1e-4:
		print("[OVERLIMIT] FAIL max_hp 超限: 上限 +%.2f(应 +10) 回血 +%.2f(应 +%.2f)" % [
			d_mhp, d_hp, want_heal]); fail += 1
	else:
		print("[OVERLIMIT] ok  max_hp 超限 上限 +10 且回 10 血(heal_mult=%.2f)" % p.heal_mult)

	# ---- 7. 其余乘算键都接进了倍率函数(漏接的话叠层点了没效果) ----
	total += 1
	var miss: Array = []
	for id in ["attack_speed", "move_speed", "pick_range"]:
		var before: float = _ov_probe_mult(p, String(id))
		p.overlimit_levels[id] = int(p.overlimit_levels.get(id, 0)) + 1
		var after: float = _ov_probe_mult(p, String(id))
		p.overlimit_levels[id] = int(p.overlimit_levels[id]) - 1
		if after <= before:
			miss.append(id)
	if not miss.is_empty():
		print("[OVERLIMIT] FAIL 这些键叠层后倍率没动(漏接 _overlimit): %s" % str(miss)); fail += 1
	else:
		print("[OVERLIMIT] ok  attack_speed/move_speed/pick_range 叠层均生效")

	# ---- 8. 未知 id 被 gate(不落层不崩) ----
	total += 1
	var n_keys: int = p.overlimit_levels.size()
	p.gain_overlimit("__no_such_key__")
	if p.overlimit_levels.size() != n_keys:
		print("[OVERLIMIT] FAIL 未知 id 仍写入了层数"); fail += 1
	else:
		print("[OVERLIMIT] ok  未知 id 被 gate 掉(不落层不崩)")

	# ---- 9. HUD 卡面走超限分支(不显示 Lv a→b, 改显示叠层数) ----
	total += 1
	var hand: Array = GameManager.roll_upgrade_options()
	hud.show_level_up(hand)
	if hud._levelup_cards.size() != hand.size():
		print("[OVERLIMIT] FAIL HUD 只建了 %d 张卡(应 %d)" % [
			hud._levelup_cards.size(), hand.size()]); fail += 1
	else:
		var bad_cards := 0
		for c in hud._levelup_cards:
			if not _ov_card_has_text(c, "超限"):
				bad_cards += 1
		if bad_cards > 0:
			print("[OVERLIMIT] FAIL %d 张卡面没走超限分支(缺「超限」字样)" % bad_cards); fail += 1
		else:
			print("[OVERLIMIT] ok  HUD %d 张卡面均显示「∞ 超限 · 叠至 N 层」" % hand.size())

	# ---- 10. 真实升级闭环: trigger_level_up → 三张卡 → 选卡 → 恢复战斗 ----
	total += 1
	var ov_before := 0
	for k in p.overlimit_levels:
		ov_before += int(p.overlimit_levels[k])
	trigger_level_up()
	var paused_ok: bool = get_tree().paused and GameManager.state == GameManager.State.LEVEL_UP
	var real: Array = hud._levelup_options
	if real.is_empty():
		print("[OVERLIMIT] FAIL trigger_level_up 给出空选项(界面会停在「没有更多强化」)"); fail += 1
	else:
		var pick: Dictionary = real[0]
		var pick_id := String(pick["id"])
		on_upgrade_chosen(pick)
		var ov_after := 0
		for k in p.overlimit_levels:
			ov_after += int(p.overlimit_levels[k])
		var resumed_ok: bool = (not get_tree().paused) \
			and GameManager.state == GameManager.State.PLAYING
		if not paused_ok:
			print("[OVERLIMIT] FAIL trigger_level_up 未正确暂停进 LEVEL_UP"); fail += 1
		elif ov_after != ov_before + 1 or int(p.overlimit_levels.get(pick_id, 0)) < 1:
			print("[OVERLIMIT] FAIL 闭环选卡后层数没涨(总层 %d -> %d)" % [ov_before, ov_after]); fail += 1
		elif not resumed_ok:
			print("[OVERLIMIT] FAIL 选卡后未恢复战斗(paused=%s state=%d)" % [
				str(get_tree().paused), GameManager.state]); fail += 1
		else:
			print("[OVERLIMIT] ok  真实闭环: 暂停→3 张超限卡→选「%s」→落层→恢复战斗" % pick_id)

	print("[OVERLIMIT] FINAL total=%d fail=%d" % [total, fail])
	if fail > 0:
		print("[OVERLIMIT] ASSERT-FAIL")
	get_tree().quit()


# 超限自检用: 按 id 取对应实时倍率(逐个 match, 不用 call() 以免名字写错时静默返回 null)
func _ov_probe_mult(p: Node2D, id: String) -> float:
	match id:
		"attack_speed":
			return p.attack_speed_mult()
		"move_speed":
			return p.move_speed()
		"pick_range":
			return p.pick_range()
	return 0.0


# 超限自检用: 递归找子树里任意 Label 文本是否含 needle
# (卡面层级由 hud._option_card 内部拼装, 这里不假设结构, 改布局不会让自检假失败)
func _ov_card_has_text(n: Node, needle: String) -> bool:
	if n is Label and String((n as Label).text).find(needle) != -1:
		return true
	for c in n.get_children():
		if _ov_card_has_text(c, needle):
			return true
	return false


# ================= 死亡链路自检(--death-check) =================
# 为什么必须单独一条: 常规冒烟从不触发真实死亡 —— balanced 回血抵得住、god 锁血、
# kite 也有被动磁吸+商店自动回血兜着, player.died → game_over → 结算屏 → 重开/回菜单
# 这条链只有玩家手玩才走到。死亡结算恰恰是最不能坏的: 它清续玩档、把本局金币存入
# 永久 bank、还挂着 bank500/survive300 等结算时点成就。
# 做法是确定性的: 开局后直接给玩家一记致死伤害(不走敌人碰撞的随机路径),
# 再走真实输入链(空格确认结算按钮)验证重开与回菜单两条出口。跑完自行 quit。
# test_mode 已由标志扫描置位 => deposit_run_coins 只累加内存 bank, 不落盘。
func _death_check() -> void:
	var total := 0
	var fail := 0

	start_game("apprentice", "wand")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p = GameManager.player

	# ---- fixture: 攒一点本局金币, 验证死亡结算真的把它存进永久 bank ----
	var coins_before := 37.0
	GameManager.coins = coins_before
	var bank_before: float = GameManager.bank
	# 续玩档基线: test_mode 下死亡结算既不写也不删盘上档(玩家真档与测试跑无关),
	# 所以断言是「死亡前后档状态不变」而不是「死亡后无档」—— 后者会误伤玩家真档场景
	var suspend_before: bool = GameManager.has_suspend()

	# ---- 1. 致死一击走真实 take_damage 路径(无敌帧归零; apprentice 无圣盾) ----
	total += 1
	p.invuln_timer = 0.0
	p.take_damage(p.max_hp_value() * 10.0)
	await get_tree().process_frame
	if p.hp != 0.0 or GameManager.state != GameManager.State.GAME_OVER:
		print("[DEATH] FAIL 致死伤害未进结算 hp=%s state=%d" % [str(p.hp), GameManager.state]); fail += 1
	else:
		print("[DEATH] ok  致死伤害 → hp=0 → state=GAME_OVER")

	# ---- 2. 结算副作用: 本局金币入永久 bank(内存态) + 续玩档被清 ----
	total += 1
	if absf(GameManager.bank - (bank_before + coins_before)) > 0.01:
		print("[DEATH] FAIL 死亡结算未入账 bank %s → %s(应 +%s)" % [
			str(bank_before), str(GameManager.bank), str(coins_before)]); fail += 1
	elif GameManager.has_suspend() != suspend_before:
		print("[DEATH] FAIL 死亡结算动了盘上续玩档(前=%s 后=%s)" % [
			str(suspend_before), str(GameManager.has_suspend())]); fail += 1
	else:
		print("[DEATH] ok  结算入账 +%s 且盘上续玩档状态不变(%s)" % [
			str(coins_before), str(suspend_before)])

	# ---- 3. 结算屏真的建出来了(两按钮: 重新开始 / 返回主菜单) ----
	total += 1
	var btns: Array = hud._result_btns
	if hud.gameover_screen == null or not is_instance_valid(hud.gameover_screen) \
			or btns.size() != 2:
		print("[DEATH] FAIL 结算屏缺失或按钮数=%d(应 2)" % btns.size()); fail += 1
	else:
		print("[DEATH] ok  结算屏建立, 按钮 [%s / %s]" % [
			str((btns[0] as Button).text), str((btns[1] as Button).text)])

	# ---- 4. 真实输入链: 空格确认默认选中(第 0 个 = 重新开始)→ 角色选择 ----
	total += 1
	hud._result_confirm()
	await get_tree().process_frame
	if GameManager.state != GameManager.State.CHARACTER_SELECT:
		print("[DEATH] FAIL 空格确认未进角色选择 state=%d" % GameManager.state); fail += 1
	elif hud.gameover_screen != null:
		print("[DEATH] FAIL 进角色选择后结算屏未清(_clear_all 漏置 null)"); fail += 1
	else:
		# 运行态归零是 start_game 的职责(restart 只到角色选择), 此处只验出口与清屏
		print("[DEATH] ok  结算「重新开始」→ 角色选择, 结算屏已清")

	# ---- 5. 再死一次, 走第二条出口: 选中「返回主菜单」→ MENU ----
	start_game("apprentice", "wand")
	await get_tree().physics_frame
	p = GameManager.player
	p.invuln_timer = 0.0
	p.take_damage(p.max_hp_value() * 10.0)
	await get_tree().process_frame
	total += 1
	if GameManager.state != GameManager.State.GAME_OVER:
		print("[DEATH] FAIL 第二局致死未进结算 state=%d" % GameManager.state); fail += 1
	else:
		hud._result_move(1, true)      # 静默移到第 1 个按钮(返回主菜单), 不播 sfx
		hud._result_confirm()
		await get_tree().process_frame
		if GameManager.state != GameManager.State.MENU:
			print("[DEATH] FAIL 「返回主菜单」未回 MENU state=%d" % GameManager.state); fail += 1
		elif hud.gameover_screen != null:
			print("[DEATH] FAIL 回菜单后结算屏未清(_clear_all 漏置 null)"); fail += 1
		else:
			print("[DEATH] ok  结算「返回主菜单」→ MENU, 结算屏已清")

	# ---- 6. 菜单后还能正常开新局(死亡链不污染下一局) ----
	total += 1
	start_game("apprentice", "wand")
	await get_tree().physics_frame
	await get_tree().physics_frame
	p = GameManager.player
	var invalid := 0
	for i in range(20):
		p.hp = p.max_hp_value()
		p.invuln_timer = 1.0
		await get_tree().physics_frame
		for e in GameManager.enemies:
			if not is_instance_valid(e):
				invalid += 1
	if GameManager.state != GameManager.State.PLAYING or invalid > 0 or p.hp <= 0.0:
		print("[DEATH] FAIL 死亡后新局异常 state=%d invalid=%d hp=%s" % [
			GameManager.state, invalid, str(p.hp)]); fail += 1
	else:
		print("[DEATH] ok  死亡后新局跑 20 帧 invalid=0 且仍 PLAYING")

	print("[DEATH] FINAL total=%d fail=%d" % [total, fail])
	if fail > 0:
		print("[DEATH] ASSERT-FAIL")
	get_tree().quit()


# ================= 各界面键盘输入链自检(--menu-check) =================
# 为什么必须单独一条: autopilot 与各自检全走函数路径(直调 _menu_confirm/_char_confirm 等),
# ui-shot 只截界面构建 —— hud._unhandled_input 的键盘分支(各状态 gate + keycode match)
# 此前没有任何自检走过。某界面 gate 写错(分支漏 return、选择变量改名)时玩家键盘全失灵,
# 而所有冒烟照样全绿。本自检合成真实 InputEventKey 走 Input.parse_input_event,
# 与玩家键盘同一条 _unhandled_input 路径; 每步断言「选择真的动了 / 状态真的换了」。
# 按键一律 press+release 成对: 只发 press 会让 _hold_keycode 驻留, 按住连发逻辑后续帧补导航。
func _press_key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	# parse_input_event 只入队: 事件在**下一帧的输入阶段**才派发到 _unhandled_input,
	# 不 await 就读选择索引会读到派发前的旧值(2026-09-10 首跑 9 项假失败的根因)
	await get_tree().process_frame


func _menu_check() -> void:
	var total := 0
	var fail := 0

	show_menu()
	await get_tree().process_frame

	# ---- 1. 主菜单 S/W 环绕移选择 ----
	total += 1
	var m0: int = hud._menu_sel
	await _press_key(KEY_S)
	var m1: int = hud._menu_sel
	await _press_key(KEY_W)
	if m1 != wrapi(m0 + 1, 0, hud._menu_btns.size()) or hud._menu_sel != m0:
		print("[MENU] FAIL 主菜单选择未随 S/W 环绕 (%d→%d→%d)" % [m0, m1, hud._menu_sel]); fail += 1
	else:
		print("[MENU] ok  主菜单 S/W 选择环绕 %d→%d→%d" % [m0, m1, hud._menu_sel])

	# ---- 2. 主菜单空格确认 → 角色选择 ----
	total += 1
	await _press_key(KEY_SPACE)
	await get_tree().process_frame
	if GameManager.state != GameManager.State.CHARACTER_SELECT:
		print("[MENU] FAIL 主菜单空格确认未进角色选择 state=%d" % GameManager.state); fail += 1
	else:
		print("[MENU] ok  主菜单空格 → 角色选择")

	# ---- 3. 角色选择 S/W 换角色 ----
	total += 1
	var c0: String = hud._selected_char
	await _press_key(KEY_S)
	var c1: String = hud._selected_char
	await _press_key(KEY_W)
	if c1 == c0 or hud._selected_char != c0:
		print("[MENU] FAIL 角色选择 S/W 未环绕换角色 (%s→%s→%s)" % [c0, c1, hud._selected_char]); fail += 1
	else:
		print("[MENU] ok  角色选择 S/W 角色环绕 %s→%s→%s" % [c0, c1, hud._selected_char])

	# ---- 4. 角色选择 A/D 换武器 ----
	total += 1
	var w0: int = hud._weapon_sel
	await _press_key(KEY_A)
	var w1: int = hud._weapon_sel
	await _press_key(KEY_D)
	if w1 == w0 or hud._weapon_sel != w0:
		print("[MENU] FAIL 角色选择 A/D 未环绕换武器 (%d→%d→%d)" % [w0, w1, hud._weapon_sel]); fail += 1
	else:
		print("[MENU] ok  角色选择 A/D 武器环绕 %d→%d→%d" % [w0, w1, hud._weapon_sel])

	# ---- 5. 角色选择空格 → 开战 ----
	total += 1
	await _press_key(KEY_SPACE)
	await get_tree().process_frame
	if GameManager.state != GameManager.State.PLAYING or GameManager.player == null:
		print("[MENU] FAIL 角色选择空格未开战 state=%d" % GameManager.state); fail += 1
	else:
		print("[MENU] ok  角色选择空格 → 开战 (%s / %s)" % [
			GameManager.current_character, GameManager.current_weapon])

	# ---- 6. 升级三选一 D 移选择 ----
	total += 1
	trigger_level_up()
	await get_tree().process_frame
	var l0: int = hud._levelup_sel
	await _press_key(KEY_D)
	if GameManager.state != GameManager.State.LEVEL_UP or hud._levelup_sel != wrapi(l0 + 1, 0, 3):
		print("[MENU] FAIL 升级 D 未移选择 (%d→%d) state=%d" % [
			l0, hud._levelup_sel, GameManager.state]); fail += 1
	else:
		print("[MENU] ok  升级三选一 D 移选择 %d→%d" % [l0, hud._levelup_sel])

	# ---- 7. 升级空格确认 → 回战斗 ----
	total += 1
	await _press_key(KEY_SPACE)
	await get_tree().process_frame
	if GameManager.state != GameManager.State.PLAYING:
		print("[MENU] FAIL 升级空格确认未回战斗 state=%d" % GameManager.state); fail += 1
	else:
		print("[MENU] ok  升级空格确认 → 战斗")

	# ---- 8. 波间商店 D 换商品 / S 换行 ----
	total += 1
	open_wave_shop()
	await get_tree().process_frame
	var s0: int = hud._shop_sel
	var r0: int = hud._shop_focus_row
	await _press_key(KEY_D)
	await _press_key(KEY_S)
	if hud._shop_sel == s0 or hud._shop_focus_row != wrapi(r0 + 1, 0, 2):
		print("[MENU] FAIL 波间商店 D/S 未动选择 (sel %d→%d row %d→%d)" % [
			s0, hud._shop_sel, r0, hud._shop_focus_row]); fail += 1
	else:
		print("[MENU] ok  波间商店 D 商品 + S 行移动")

	# ---- 9. 波间商店「继续战斗」行空格 → 回战斗 ----
	total += 1
	if hud._shop_focus_row != 1:
		await _press_key(KEY_S)      # 兜底移到继续行(初始行不确定时)
	await _press_key(KEY_SPACE)
	await get_tree().process_frame
	if GameManager.state != GameManager.State.PLAYING:
		print("[MENU] FAIL 波间商店继续行空格未回战斗 state=%d row=%d" % [
			GameManager.state, hud._shop_focus_row]); fail += 1
	else:
		print("[MENU] ok  波间商店继续行空格 → 战斗")

	# ---- 10. 图鉴 D 切分类 / S 切条目 ----
	total += 1
	hud.show_codex()
	await get_tree().process_frame
	var t0: int = hud._cx_tab
	var e0: int = hud._cx_sel
	await _press_key(KEY_D)
	await _press_key(KEY_S)
	if hud._cx_tab == t0 or hud._cx_sel == e0:
		print("[MENU] FAIL 图鉴 D/S 未动选择 (tab %d→%d sel %d→%d)" % [
			t0, hud._cx_tab, e0, hud._cx_sel]); fail += 1
	else:
		print("[MENU] ok  图鉴 D 分类 + S 条目移动")

	# ---- 11. 图鉴 ESC 合书回来源 ----
	total += 1
	await _press_key(KEY_ESCAPE)
	for i in range(60):        # 合书动画期间 _cx_closing 吞输入, 等 tween 走完
		await get_tree().process_frame
	if GameManager.state != GameManager.State.MENU:
		print("[MENU] FAIL 图鉴 ESC 未回来源 state=%d" % GameManager.state); fail += 1
	else:
		print("[MENU] ok  图鉴 ESC 合书 → 来源(主菜单)")

	# ---- 12. 设置 S 移行 ----
	total += 1
	hud.show_settings()
	await get_tree().process_frame
	var g0: int = hud._settings_row
	await _press_key(KEY_S)
	if hud._settings_row != wrapi(g0 + 1, 0, 4):
		print("[MENU] FAIL 设置 S 未移行 (%d→%d)" % [g0, hud._settings_row]); fail += 1
	else:
		print("[MENU] ok  设置 S 移行 %d→%d" % [g0, hud._settings_row])

	# ---- 13. 设置 ESC 回来源 ----
	total += 1
	await _press_key(KEY_ESCAPE)
	await get_tree().process_frame
	await get_tree().process_frame
	if GameManager.state != GameManager.State.MENU:
		print("[MENU] FAIL 设置 ESC 未回来源 state=%d" % GameManager.state); fail += 1
	else:
		print("[MENU] ok  设置 ESC → 来源(主菜单)")

	# ---- 14. 战斗中 R 重开 → 角色选择 ----
	total += 1
	start_game("apprentice", "wand")
	await get_tree().physics_frame
	await _press_key(KEY_R)
	await get_tree().process_frame
	if GameManager.state != GameManager.State.CHARACTER_SELECT:
		print("[MENU] FAIL 战斗中 R 未回角色选择 state=%d" % GameManager.state); fail += 1
	else:
		print("[MENU] ok  战斗中 R → 角色选择")

	# ---- 15. 局外商店(state 仍 MENU, 靠 shop_screen 判定): S 移选择 + ESC 关闭 ----
	total += 1
	show_menu()          # 必须走 main 的: hud.show_menu 只建 UI 不置 state(2026-09-10 首跑假失败根因)
	await get_tree().process_frame
	hud.show_shop()
	await get_tree().process_frame
	var ms0: int = hud._meta_shop_sel
	var ms_n: int = hud._shop_rows.size() + 1   # ESC 关店后 _clear_all 可能清 rows, 上限提前捕获
	await _press_key(KEY_S)
	var ms1: int = hud._meta_shop_sel
	await _press_key(KEY_ESCAPE)
	await get_tree().process_frame
	if ms1 != wrapi(ms0 + 1, 0, ms_n):
		print("[MENU] FAIL 局外商店 S 未移选择 (%d→%d, 行上限 %d)" % [ms0, ms1, ms_n]); fail += 1
	elif hud.shop_screen != null or GameManager.state != GameManager.State.MENU:
		print("[MENU] FAIL 局外商店 ESC 未关闭回主菜单 state=%d" % GameManager.state); fail += 1
	else:
		print("[MENU] ok  局外商店 S 移选择 + ESC 关闭回主菜单")

	# ---- 16. 重开确认框独占键盘: S 移按钮 + ESC 取消(菜单输入不被永久吞) ----
	total += 1
	hud._on_menu_restart_ask()
	await get_tree().process_frame
	var cf0: int = hud._menu_confirm_sel
	var cf_n: int = hud._menu_confirm_btns.size()   # ESC 后 btns 被清空, 环绕上限须提前捕获
	await _press_key(KEY_S)
	var cf1: int = hud._menu_confirm_sel
	await _press_key(KEY_ESCAPE)
	await get_tree().process_frame
	await get_tree().process_frame
	if cf1 != wrapi(cf0 + 1, 0, cf_n):
		print("[MENU] FAIL 重开确认框 S 未移按钮 (%d→%d)" % [cf0, cf1]); fail += 1
	elif hud._menu_confirm_screen != null or GameManager.state != GameManager.State.MENU:
		print("[MENU] FAIL 重开确认框 ESC 未取消 state=%d" % GameManager.state); fail += 1
	else:
		# 取消后主菜单键盘必须还活着(悬空引用会让 gate 永久吞输入)
		var mm0: int = hud._menu_sel
		await _press_key(KEY_S)
		if hud._menu_sel == mm0:
			print("[MENU] FAIL 确认框取消后主菜单键盘被吞"); fail += 1
		else:
			print("[MENU] ok  重开确认框 S/ESC + 取消后菜单键盘存活")

	print("[MENU] FINAL total=%d fail=%d" % [total, fail])
	if fail > 0:
		print("[MENU] ASSERT-FAIL")
	get_tree().quit()


# ================= 七武器逐一真实伤害自检(--weapon-check) =================
# 为什么必须单独一条: god 冒烟的 autopilot 把武器数封顶在 FOCUS_WEAPONS=3(铺满 7 把会吃光
# 整局升级预算, 凑不出进化), 且每局抽哪 3 把是随机的 —— 七把武器与七个进化**从未被逐一
# 验证过「真的能打出伤害」**。改坏其中一把(索敌半径写错、弹速归零、burn_zone 不生成、
# id↔脚本映射漏一行)所有冒烟照样全绿。
# 做法是确定性的: 每把武器单独开一局, restore_weapons 只挂它一把(绕过 gain_weapon 的首获
# 「军械」加成), 关掉刷怪, 在固定距离钉一只百万血靶敌, 走真实攻击路径
# (冷却 → _do_attack → 弹道/区域 → take_damage)跑到掉血为止, 断言血量严格下降。
# 靶敌每帧复位位置: take_damage 自带击退、旋刃还叠 240 强击退, 不复位会被推出圣环/旋刃
# 射程变成假失败。
# 特性状态另做断言, 但**只验触发概率 = 1.0 的确定性链路**(旋刃流血 / 圣环易伤 / 飞刀中毒 /
# 燃烧瓶燃烧 / 回旋镖进化必减速); 法杖眩晕 20%、闪电冰冻 10~20% 是掷骰, 验了必然 flaky
# (同 --overlimit-check 断言 4 的教训), 那两条的真实触发归冒烟战报与人工目检。
func _weapon_check() -> void:
	var total := 0
	var fail := 0
	Autopilot.enabled = false
	Engine.time_scale = 1.0

	# ---- 0. 五张伴生表与 WEAPONS 键对齐 ----
	# 加武器要同时改 WEAPONS / WEAPON_SCRIPTS / WEAPON_DETAILS / EVOLUTIONS / WEAPON_ICONS /
	# WEAPON_TRAITS 六处, 漏一个不报错只静默缺功能(图标空白 / 图鉴缺条 / 进化永远凑不出)
	total += 1
	var wkeys: Array = GameManager.WEAPONS.keys()
	var tables := {
		"WEAPON_TRAITS": GameManager.WEAPON_TRAITS.keys(),
		"WEAPON_DETAILS": GameManager.WEAPON_DETAILS.keys(),
		"EVOLUTIONS": GameManager.EVOLUTIONS.keys(),
		"WEAPON_ICONS": GameManager.WEAPON_ICONS.keys(),
		"WEAPON_SCRIPTS": GameManager.player.WEAPON_SCRIPTS.keys(),
	}
	var mismatched: Array = []
	for tname in tables:
		var ks: Array = tables[tname]
		if ks.size() != wkeys.size():
			mismatched.append("%s 条数 %d≠%d" % [str(tname), ks.size(), wkeys.size()])
			continue
		for k in wkeys:
			if not ks.has(k):
				mismatched.append("%s 缺键 %s" % [str(tname), str(k)])
	if not mismatched.is_empty():
		print("[WEAPON] FAIL 武器伴生表未对齐: %s" % ", ".join(mismatched)); fail += 1
	else:
		print("[WEAPON] ok  六表键对齐(WEAPONS/TRAITS/DETAILS/EVOLUTIONS/ICONS/SCRIPTS 各 %d)" % wkeys.size())

	# ---- 1~14. 七把武器 × 常态/进化, 逐一真实开火打死靶敌 ----
	var cfgs: Array = []
	for id in GameManager.WEAPONS.keys():
		cfgs.append([id, false])
		cfgs.append([id, true])

	# 圣环半径记账: 它的进化只加半径(+60%)与结算回血, 单只靶敌的伤害数字与常态一模一样,
	# 光看掉血证明不了"进化真的生效"。半径是确定性函数, 直接比常态/进化两个值(同角色 =>
	# area_mult 两边同乘, 倍率自己消掉)
	var aura_r := {}

	for cfg in cfgs:
		var wid: String = str(cfg[0])
		var evo: bool = bool(cfg[1])
		var lv: int = int(GameManager.WEAPONS[wid]["max_level"])
		var tag: String = wid + ("*" if evo else "")
		total += 1

		_calm_field("apprentice", wid)
		var p: Node2D = GameManager.player
		# 关刷怪 + 清场已含在 _calm_field: 真实波次刷出来的怪会抢 nearest_enemy 的索敌,
		# 靶场必须只有自己摆的那只(也顺带避免上一把武器残留的敌人/弹/火池)
		p.restore_weapons({wid: lv}, {wid: true} if evo else {})
		await get_tree().physics_frame

		if not p.weapons.has(wid):
			print("[WEAPON] FAIL %s Lv%d 武器节点未重建(WEAPON_SCRIPTS 映射缺这把?)" % [tag, lv])
			fail += 1
			continue

		var home: Vector2 = GameManager.BOUND.get_center()
		p.global_position = home
		# 靶距按射程分档: 旋刃是贴身环绕(刃轨半径 35), 圣环是范围(Lv3 半径 81),
		# 其余走弹道/落点(燃烧瓶落点 clamp 30~130), 60px 都在有效射程内
		var dist: float = 35.0 if wid == "orbit" else (50.0 if wid == "aura" else 60.0)
		var epos: Vector2 = home + Vector2.RIGHT * dist
		var e: Node2D = ObjectPool.spawn_enemy(0, epos)
		e.hp = 1000000.0
		e._max_hp = 1000000.0
		e.speed = 0.0
		e._knockback = Vector2.ZERO
		e._status.clear()
		var hp0: float = e.hp

		# 帧预算: 燃烧瓶最慢(冷却 2.2s + 飞行 ~0.2s + 首跳)≈ 150 帧, 给到 420 留富余;
		# 掉血即刻 break, 实际总帧数远低于上限
		var hit := false
		var frames := 0
		for i in range(420):
			frames = i + 1
			e.global_position = epos      # 钉死靶位(击退会把它推出射程)
			e._knockback = Vector2.ZERO
			p.global_position = home
			p.hp = p.max_hp_value()       # 靶敌贴身打不掉血, 但圣环进化会回血, 一并锁住
			p.invuln_timer = 1.0
			await get_tree().physics_frame
			if not is_instance_valid(e) or e._dead or e.hp < hp0:
				hit = true
				break

		var dealt := 0.0
		if wid == "aura":
			# 不写 Node2D 类型标注: radius() 是 aura 子类的, 静态类型上调用会解析报错
			aura_r["evo" if evo else "base"] = p.weapons[wid].radius()
		# 变量名不用 trait: GDScript 保留字, 只在脚本 load 时报错(--import 查不出)
		var tkind: String = GameManager.trait_of(wid)
		# 确定性特性链(概率 1.0): 这五把的挂载不经掷骰, 没挂上就是真断了
		var trait_det: bool = tkind != "" and (wid == "orbit" or wid == "aura" \
			or wid == "dagger" or wid == "holy_water" or (wid == "shuriken" and evo))
		var trait_ok := true
		if is_instance_valid(e):
			dealt = hp0 - e.hp
			if trait_det:
				trait_ok = e._status.has(tkind)
		else:
			trait_ok = false

		if not hit or dealt <= 0.0 or not trait_ok:
			var why: String = "未命中" if (not hit or dealt <= 0.0) else \
				("特性「%s」未挂上" % GameManager.trait_name(wid))
			print("[WEAPON] FAIL %s Lv%d %s(跑 %d 帧, 掉血 %.1f)" % [tag, lv, why, frames, dealt])
			fail += 1
		else:
			var extra: String = (" + 特性「%s」" % GameManager.trait_name(wid)) if trait_det else ""
			print("[WEAPON] ok  %s Lv%d %d 帧打出 %.1f 伤害%s" % [tag, lv, frames, dealt, extra])

	# ---- 15. 圣环进化半径真的 +60%(掉血数字与常态相同, 只能直接量半径) ----
	total += 1
	var ar_b: float = float(aura_r.get("base", 0.0))
	var ar_e: float = float(aura_r.get("evo", 0.0))
	if ar_b <= 0.0 or absf(ar_e / ar_b - 1.6) > 0.01:
		print("[WEAPON] FAIL 圣环进化半径非 +60%% (%.1f → %.1f)" % [ar_b, ar_e]); fail += 1
	else:
		print("[WEAPON] ok  圣环进化半径 +60%% (%.1f → %.1f)" % [ar_b, ar_e])

	# ---- 16. 闪电连锁数: 常态 Lv3 = 3 跳, 进化「雷霆审判」+3 = 6 跳 ----
	# 单靶敌看不出连锁(它只跳第一下), 摆一排怪数"几只被打到"才是真判别。
	# 怪间距 40px < jump_range(70 × area_mult), 链子能一路跳到底; 摆 7 只够进化档用满 6 跳
	total += 1
	var chain_cnt: Array = []
	for evo2 in [false, true]:
		_calm_field("apprentice", "lightning")
		var p2: Node2D = GameManager.player
		p2.restore_weapons({"lightning": 3}, {"lightning": true} if evo2 else {})
		await get_tree().physics_frame
		var home2: Vector2 = GameManager.BOUND.get_center()
		p2.global_position = home2
		var row: Array = []
		for k in range(7):
			var ep: Vector2 = home2 + Vector2.RIGHT * (60.0 + 40.0 * float(k))
			var ek: Node2D = ObjectPool.spawn_enemy(0, ep)
			ek.hp = 1000000.0
			ek._max_hp = 1000000.0
			ek.speed = 0.0
			row.append([ek, ep, ek.hp])
		for i in range(90):
			for r in row:
				(r[0] as Node2D).global_position = r[1]
				(r[0] as Node2D)._knockback = Vector2.ZERO
			p2.global_position = home2
			p2.hp = p2.max_hp_value()
			p2.invuln_timer = 1.0
			await get_tree().physics_frame
		var n := 0
		for r in row:
			if float((r[0] as Node2D).hp) < float(r[2]):
				n += 1
		chain_cnt.append(n)
	var want: Array = [3, 6]
	# 逐元素比: Array 的 != 依赖引擎的值比较语义, 显式比一遍不靠它
	if chain_cnt.size() != 2 or int(chain_cnt[0]) != want[0] or int(chain_cnt[1]) != want[1]:
		print("[WEAPON] FAIL 闪电连锁数 %s (应 %s: 常态 Lv3 = 3 跳 / 进化 = 6 跳)" % [
			str(chain_cnt), str(want)]); fail += 1
	else:
		print("[WEAPON] ok  闪电连锁 常态 3 跳 → 进化 6 跳")

	print("[WEAPON] FINAL total=%d fail=%d" % [total, fail])
	if fail > 0:
		print("[WEAPON] ASSERT-FAIL")
	get_tree().quit()


# ================= 五角色被动逐一生效自检(--char-check) =================
# 为什么必须单独一条: 冒烟默认只跑 apprentice(--char 可指定但从没逐个跑过), 而五个角色的
# 被动是**五条互相独立的代码路径** —— 学徒的经验折扣在 GameManager.xp_to_next、圣骑士/只因
# 信徒的圣盾在 player.take_damage 的前置分支、忍者蛙的拾穗在 gem.collect、面具客的处决在
# enemy.take_damage。改坏任一条(角色 id 拼错、圣盾 gate 写反、heal_mult 漏乘)冒烟照样全绿,
# 玩家选那个角色才会发现"被动没生效"。
# 断言全部确定性, 且**不依赖局外加成**: 属性接线直接比 base_* 字段(表驱动, 不过 meta 通道);
# 跨角色对比走比值/差值(meta 与 stat 通道两边同乘/同加, 自己消掉)—— 脏 meta.cfg(bank 62 万、
# 强化买满)也能跑出同样结果。
func _char_check() -> void:
	var total := 0
	var fail := 0
	Autopilot.enabled = false
	Engine.time_scale = 1.0

	# 每局都要的干净靶场: 关刷怪(否则波次推进会让 enemy_damage_mult 之类的爬坡倍率掺进断言)
	# 注意: 本函数依赖 wave 停在 0 => enemy_damage_mult()=1.0 / enemy_hp_mult()=1.0

	# ---- 1. 三张角色伴生表键对齐 ----
	# CHARACTERS 漏进 CODEX_CHARS = 图鉴缺条; 漏进 CHAR_FRAMES = frames_for 取不到帧,
	# 角色在选人界面/战斗里静默变成程序化圆形(texture_for 的回退不报错)
	total += 1
	var ckeys: Array = GameManager.CHARACTERS.keys()
	var cmis: Array = []
	if GameManager.CODEX_CHARS.keys().size() != ckeys.size():
		cmis.append("CODEX_CHARS 条数 %d≠%d" % [GameManager.CODEX_CHARS.keys().size(), ckeys.size()])
	if GameManager.CHAR_FRAMES.keys().size() != ckeys.size():
		cmis.append("CHAR_FRAMES 条数 %d≠%d" % [GameManager.CHAR_FRAMES.keys().size(), ckeys.size()])
	for k in ckeys:
		if not GameManager.CODEX_CHARS.has(k):
			cmis.append("CODEX_CHARS 缺 " + str(k))
		if not GameManager.CHAR_FRAMES.has(k):
			cmis.append("CHAR_FRAMES 缺 " + str(k))
	if not cmis.is_empty():
		print("[CHAR] FAIL 角色伴生表未对齐: %s" % ", ".join(cmis)); fail += 1
	else:
		print("[CHAR] ok  三表键对齐(CHARACTERS/CODEX_CHARS/CHAR_FRAMES 各 %d)" % ckeys.size())

	# ---- 2~6. 逐角色: 表里六个属性字段真的接到了 player 身上 ----
	# 比 base_*/char_* 字段而非 live 倍率函数: 这些字段由 setup_character 直接抄表,
	# 不经 meta/item/overlimit 任何通道, 可以精确比。圣骑士的 +10% 上限是表外硬编码, 一并验
	for cid in ckeys:
		total += 1
		var c: Dictionary = GameManager.CHARACTERS[cid]
		_calm_field(str(cid), str(c["weapon"]))
		await get_tree().physics_frame
		var p: Node2D = GameManager.player
		var want_hp: float = float(c["max_hp"]) * (1.10 if str(cid) == "paladin" else 1.0)
		var bad: Array = []
		if absf(float(p.base_max_hp) - want_hp) > 0.01:
			bad.append("max_hp %s≠%s" % [str(p.base_max_hp), str(want_hp)])
		if absf(float(p.base_move_speed) - float(c["move_speed"])) > 0.01:
			bad.append("move_speed %s≠%s" % [str(p.base_move_speed), str(c["move_speed"])])
		if absf(float(p.base_pick_range) - float(c["pick_range"])) > 0.01:
			bad.append("pick_range %s≠%s" % [str(p.base_pick_range), str(c["pick_range"])])
		if absf(float(p.char_damage_mult) - float(c["damage_mult"])) > 0.0001:
			bad.append("damage_mult %s≠%s" % [str(p.char_damage_mult), str(c["damage_mult"])])
		if absf(float(p.char_proj_speed_mult) - float(c["proj_speed_mult"])) > 0.0001:
			bad.append("proj_speed_mult %s≠%s" % [str(p.char_proj_speed_mult), str(c["proj_speed_mult"])])
		if absf(float(p.heal_mult) - float(c["heal_mult"])) > 0.0001:
			bad.append("heal_mult %s≠%s" % [str(p.heal_mult), str(c["heal_mult"])])
		if not p.has_weapon(str(c["weapon"])):
			bad.append("起始武器 %s 未挂载" % str(c["weapon"]))
		if not bad.is_empty():
			print("[CHAR] FAIL %s 属性接线: %s" % [str(cid), ", ".join(bad)]); fail += 1
		else:
			print("[CHAR] ok  %s 六项属性 + 起始武器(%s)接线正确" % [str(cid), str(c["weapon"])])

	# ---- 7. 学徒「求知若渴」经验 -20% + 「弹速 +15%」 ----
	total += 1
	_calm_field("apprentice", "wand")
	GameManager.level = 5
	var xp_app: float = GameManager.xp_to_next()
	var ps_app: float = float(GameManager.player.proj_speed_mult())
	_calm_field("paladin", "orbit")
	GameManager.level = 5
	var xp_pal: float = GameManager.xp_to_next()
	var ps_pal: float = float(GameManager.player.proj_speed_mult())
	# 比值法: 两局都是全新开局(stat 清零、item_mods 空), meta 通道两边同乘自动消掉
	if xp_pal <= 0.0 or absf(xp_app / xp_pal - 0.8) > 0.001 or absf(ps_app / ps_pal - 1.15) > 0.001:
		print("[CHAR] FAIL 学徒被动 经验比 %.4f(应 0.8) 弹速比 %.4f(应 1.15)" % [
			xp_app / xp_pal, ps_app / ps_pal]); fail += 1
	else:
		print("[CHAR] ok  学徒 经验 -20%%(%.1f/%.1f) 弹速 +15%%" % [xp_app, xp_pal])

	# ---- 8. 圣骑士「圣盾」: 就绪时格挡一次(零掉血), 之后进 12s 冷却不再挡 ----
	total += 1
	_calm_field("paladin", "orbit")
	await get_tree().physics_frame
	var ps: Node2D = GameManager.player
	ps.invuln_timer = 0.0          # 出生保护会吞掉伤害, 必须先归零(否则测的是无敌帧不是圣盾)
	ps.hp = ps.max_hp_value()
	var hp_full: float = ps.hp
	ps.take_damage(25.0)
	var blocked := absf(ps.hp - hp_full) < 0.01
	var shield_spent: bool = not ps._shield_ready
	# 第二击: 盾已耗尽 => 必须真掉血(wave=0 故 enemy_damage_mult()=1.0, 掉 25)
	ps.take_damage(25.0)
	var hp_after2: float = ps.hp
	var recharged := false
	if shield_spent:
		ps._shield_timer = 0.01     # 把冷却拨到尽头, 下一帧 _physics_process 应重新就绪
		await get_tree().physics_frame
		recharged = ps._shield_ready
	if not blocked or not shield_spent or absf(hp_full - hp_after2 - 25.0) > 0.01 or not recharged:
		print("[CHAR] FAIL 圣骑士圣盾 格挡=%s 耗尽=%s 二次掉血=%.1f(应 25) 冷却后重置=%s" % [
			str(blocked), str(shield_spent), hp_full - hp_after2, str(recharged)]); fail += 1
	else:
		print("[CHAR] ok  圣骑士圣盾 格挡一次零掉血 → 耗尽后吃满伤 → 12s 冷却重置")

	# ---- 9. 忍者蛙「拾穗」: 拾取经验宝石回复 1 × heal_mult(1.5) ----
	total += 1
	_calm_field("priest", "aura")
	await get_tree().physics_frame
	var pp: Node2D = GameManager.player
	GameManager.xp = 0.0
	pp.hp = pp.max_hp_value() - 10.0    # 留 10 血缺口, 否则回血被上限夹住测不出
	var hp_pre: float = pp.hp
	var g: Node2D = ObjectPool.spawn_gem(pp.global_position, 1.0)
	g.collect()                          # 真实拾取路径(磁吸/接触都走这里)
	await get_tree().process_frame
	var healed: float = pp.hp - hp_pre
	if absf(healed - 1.0 * 1.5) > 0.01:
		print("[CHAR] FAIL 忍者蛙拾穗 回血 %.2f(应 1.5 = 1 × heal_mult 1.5)" % healed); fail += 1
	else:
		print("[CHAR] ok  忍者蛙拾穗 拾宝石回血 %.2f(1 × heal_mult 1.5)" % healed)

	# ---- 10. 面具客「处决」: 敌人血量 <25% 时受伤 +40% ----
	total += 1
	_calm_field("assassin", "wand")
	await get_tree().physics_frame
	var ea: Node2D = ObjectPool.spawn_enemy(0, GameManager.BOUND.get_center() + Vector2.RIGHT * 60.0)
	ea._max_hp = 100.0
	ea.hp = 100.0
	ea._status.clear()
	ea.take_damage(10.0)
	var d_full: float = 100.0 - ea.hp
	ea.hp = 20.0                       # 20% < 25% 阈值
	ea._status.clear()
	ea.take_damage(10.0)
	var d_low: float = 20.0 - ea.hp
	# 同一次调用同一把尺: 暴击(cc=0)/冰冻易伤(状态清空)/盾卫(kind 0)三条干扰通道都已排除
	if d_full <= 0.0 or absf(d_low / d_full - 1.4) > 0.001:
		print("[CHAR] FAIL 面具客处决 满血掉 %.1f 残血掉 %.1f(比值应 1.4)" % [d_full, d_low]); fail += 1
	else:
		print("[CHAR] ok  面具客处决 残血(<25%%)受伤 +40%% (%.1f → %.1f)" % [d_full, d_low])

	# ---- 11. 只因信徒「金拱独立」: 与圣骑士同一条圣盾路径 ----
	total += 1
	start_game("xiaoheizi", "aura")
	await get_tree().physics_frame
	await get_tree().physics_frame
	spawner.set_physics_process(false)
	_clear_entities()
	var px: Node2D = GameManager.player
	px.invuln_timer = 0.0
	px.hp = px.max_hp_value()
	var hx: float = px.hp
	px.take_damage(25.0)
	if absf(px.hp - hx) > 0.01 or px._shield_ready:
		print("[CHAR] FAIL 只因信徒圣盾未格挡(hp %.1f→%.1f, ready=%s)" % [
			hx, px.hp, str(px._shield_ready)]); fail += 1
	else:
		print("[CHAR] ok  只因信徒金拱独立 格挡一次零掉血")

	# ---- 12. 反向对照: 没圣盾的三个角色必须真掉血(圣盾 gate 写反会漏给所有人) ----
	total += 1
	var leak: Array = []
	for cid2 in ["apprentice", "priest", "assassin"]:
		_calm_field(str(cid2), str(GameManager.CHARACTERS[cid2]["weapon"]))
		await get_tree().physics_frame
		var pn: Node2D = GameManager.player
		pn.invuln_timer = 0.0
		pn.hp = pn.max_hp_value()
		var h0: float = pn.hp
		pn.take_damage(10.0)
		if absf(pn.hp - h0) < 0.01:
			leak.append(str(cid2))
	if not leak.is_empty():
		print("[CHAR] FAIL 无盾角色被格挡(圣盾 gate 漏了): %s" % ", ".join(leak)); fail += 1
	else:
		print("[CHAR] ok  反向对照 学徒/忍者蛙/面具客 无圣盾, 照常吃伤")

	print("[CHAR] FINAL total=%d fail=%d" % [total, fail])
	if fail > 0:
		print("[CHAR] ASSERT-FAIL")
	get_tree().quit()


# 自检靶场: 开局 + 立刻冻结刷怪, 让 wave 停在 0。
# **顺序是关键**: start_game 之后若先 await 一帧, spawner._physics_process 会拉起第 1 波,
# 而 _start_wave 里 roll_wave_curse() 会随机掷一条波间事件 —— 掷中「狂化」就带 crit +0.10,
# roll_crit 有 1/10 概率把伤害数字翻倍, 精确比值断言随之间歇假失败(与 --overlimit-check
# 断言 4 同一类坑: 随机前置 + 精确比值)。同步冻结就永远不会掷。
# wave=0 另有好处: enemy_hp_mult()/enemy_damage_mult() 恒为 1.0, 断言不必再除掉爬坡倍率。
func _calm_field(char_id: String = "apprentice", weapon_id: String = "") -> void:
	start_game(char_id, weapon_id)
	spawner.set_physics_process(false)
	spawner._telegraphs.clear()
	GameManager.wave = 0
	GameManager.set_wave_curse("")
	_clear_entities()


# ================= 词缀与精英逐一生效自检(--affix-check) =================
# 为什么必须单独一条: 六条词缀是**互相独立的行为分支**(疾风/坚韧只改数值, 再生走每帧回血,
# 射手走敌弹生成, 分裂与自爆各走 die() 里的一段), 而冒烟里刷出哪条完全随机 —— 波 1~2 恒无
# 词缀, 分裂/自爆要波 7/8 才解锁, 精英(波 4 起 2%~6%)几十只里才一只。autopilot 一局能否
# 凑齐六条纯看运气, 改坏其中一条(例如 _apply_affix 的 has() 守卫退化成无条件赋值 →
# "再生+疾风"的第二条把 _regen 抹成 0, 词缀静默失效)冒烟照样全绿。
# 做法与 --weapon-check / --char-check 同构: _calm_field 冻刷怪让 wave 停在 0,
# restore_weapons({}, {}) 清空玩家武器(靶场里玩家不输出 —— 怪不会被误杀, 也没有己方弹道
# 干扰射手的敌弹计数), 然后**直接 spawn 指定词缀的怪**走真实 setup/_physics_process/die 路径。
# 数值断言一律用「同帧 spawn 的无词缀怪当基准」做比值: enemy_hp_mult / 难度档 / 诅咒三条
# 通道在两边同乘自动消掉(与 --char-check 断言 7 同一手法), 故不必依赖 wave=0 也不必管
# settings.cfg 里玩家真实的难度选择。
# 敌人变量一律**不写类型标注**: collision_radius()/scale_split_offspring() 是 enemy.gd 的,
# 静态类型上调用会解析报错(同 --weapon-check 里 aura.radius() 的坑)。
func _affix_check() -> void:
	var total := 0
	var fail := 0
	Autopilot.enabled = false
	Engine.time_scale = 1.0
	var AFF: Dictionary = GameManager.ENEMY_AFFIXES
	var EL: Dictionary = GameManager.ELITE_BASE
	var home: Vector2 = GameManager.BOUND.get_center()
	var far: Vector2 = home + Vector2.RIGHT * 200.0

	# ---- 1. 词缀表完整性 + mult 键白名单 + 精英刻意不在表内 ----
	# mult 只支持 hp/speed/size 三键(_apply_affix 只读这三个); 写第四键不会报错, 只会静默无效
	# 精英不进 ENEMY_AFFIXES 是设计决定(见 ELITE_BASE 注释四条理由), 混进去会让 affix_pool
	# 把它当普通词缀抽中 + 图鉴以 "af_elite" 串进词缀列
	total += 1
	var akeys: Array = AFF.keys()
	var tbad: Array = []
	if akeys.size() != 6:
		tbad.append("词缀条数 %d≠6" % akeys.size())
	if AFF.has("elite"):
		tbad.append("ELITE_BASE 混进了词缀表(正交维度, 会被 affix_pool 抽中)")
	for k in akeys:
		var d: Dictionary = AFF[k]
		for f in ["name", "color", "mult", "unlock", "note"]:
			if not d.has(f):
				tbad.append("%s 缺字段 %s" % [str(k), str(f)])
		if str(d.get("note", "")) == "":
			tbad.append("%s 的 note 为空(图鉴右页会开天窗)" % str(k))
		for mk in Dictionary(d.get("mult", {})).keys():
			if not ["hp", "speed", "size"].has(str(mk)):
				tbad.append("%s 的 mult 有无效键 %s(_apply_affix 不读它, 静默无效)" % [str(k), str(mk)])
		if int(d.get("unlock", 0)) < 3:
			tbad.append("%s 的 unlock=%d < 3(波 1~2 必须无词缀保新手平滑)" % [str(k), int(d["unlock"])])
	if not tbad.is_empty():
		print("[AFFIX] FAIL 词缀表: %s" % "; ".join(tbad)); fail += 1
	else:
		print("[AFFIX] ok  六词缀表完整(mult 键合法/unlock≥3/note 非空), 精英未混入")

	# ---- 2. affix_pool(w) 由 unlock 字段派生, 边界双向 ----
	# 图鉴「解锁波次」与刷怪池共读这一个函数; 边界写错(>= 变 >)会让图鉴说波 3 解锁、
	# 实际波 4 才刷出来 —— 展示与实战漂移, 且不报错
	total += 1
	var pbad: Array = []
	if not GameManager.affix_pool(1).is_empty() or not GameManager.affix_pool(2).is_empty():
		pbad.append("波 1/2 池非空(%s / %s)" % [str(GameManager.affix_pool(1)), str(GameManager.affix_pool(2))])
	if GameManager.affix_pool(12).size() != akeys.size():
		pbad.append("波 12 池 %d 条≠%d" % [GameManager.affix_pool(12).size(), akeys.size()])
	for k in akeys:
		var u: int = int(AFF[k]["unlock"])
		if not GameManager.affix_pool(u).has(str(k)):
			pbad.append("%s 在 unlock 波 %d 未入池" % [str(k), u])
		if u > 1 and GameManager.affix_pool(u - 1).has(str(k)):
			pbad.append("%s 在波 %d(unlock-1)已入池" % [str(k), u - 1])
	if not pbad.is_empty():
		print("[AFFIX] FAIL affix_pool 派生: %s" % "; ".join(pbad)); fail += 1
	else:
		print("[AFFIX] ok  affix_pool 按 unlock 派生(波 1/2 空 → 波 12 全 %d 条), 边界双向正确" % akeys.size())

	# ---- 3~5. 三条掷骰函数的门槛 ----
	# 这三条都读 GameManager.wave, 集中在一块里改 wave, 结束后 _calm_field 会把它归 0
	_calm_field("apprentice", "wand")
	GameManager.curse_level = 0          # 诅咒会放宽 affix 封顶与精英出率, 归零让门槛可判

	total += 1
	var early_hit := 0
	var late_n := 0
	var off_pool := 0
	var pool12: Array = GameManager.affix_pool(12)
	GameManager.wave = 1
	for i in range(400):
		if GameManager.roll_enemy_affix() != "":
			early_hit += 1
	GameManager.wave = 2
	for i in range(400):
		if GameManager.roll_enemy_affix() != "":
			early_hit += 1
	GameManager.wave = 12
	for i in range(3000):
		var ra: String = GameManager.roll_enemy_affix()
		if ra == "":
			continue
		late_n += 1
		if not pool12.has(ra):
			off_pool += 1
	if early_hit != 0 or late_n <= 0 or off_pool != 0:
		print("[AFFIX] FAIL roll_enemy_affix 波1/2 出了 %d 次词缀(应 0), 波12 出 %d 次(应>0), 池外 %d 次(应 0)" % [
			early_hit, late_n, off_pool]); fail += 1
	else:
		print("[AFFIX] ok  roll_enemy_affix 波 1/2 恒无词缀, 波 12 掷 3000 次出 %d 条且全在池内" % late_n)

	total += 1
	var dup := 0
	var cover_bad: Array = []
	GameManager.wave = 12
	for k in akeys:
		var seen := {}
		for i in range(300):
			var a2: String = GameManager.roll_enemy_affix2(str(k))
			if a2 == str(k):
				dup += 1
			if a2 != "":
				seen[a2] = true
		# 波 12 池满 6 条, 剔除主词缀还剩 5 条 => 300 次必须全覆盖(漏一条说明抽法有偏)
		if seen.size() != akeys.size() - 1:
			cover_bad.append("%s 只覆盖 %d/%d" % [str(k), seen.size(), akeys.size() - 1])
	if dup != 0 or not cover_bad.is_empty():
		print("[AFFIX] FAIL roll_enemy_affix2 撞主词缀 %d 次(应 0); 覆盖不全: %s" % [
			dup, "; ".join(cover_bad)]); fail += 1
	else:
		print("[AFFIX] ok  roll_enemy_affix2 永不返回主词缀(1800 次 0 撞), 且均匀覆盖其余 5 条")

	total += 1
	var elite_early := 0
	var elite_noaff := 0
	var elite_w4 := 0
	var elite_w12 := 0
	GameManager.wave = 3
	for i in range(2000):
		if GameManager.roll_elite("swift"):
			elite_early += 1
	GameManager.wave = 12
	for i in range(2000):
		if GameManager.roll_elite(""):
			elite_noaff += 1
		if GameManager.roll_elite("swift"):
			elite_w12 += 1
	GameManager.wave = 4
	for i in range(3000):
		if GameManager.roll_elite("tanky"):
			elite_w4 += 1
	if elite_early != 0 or elite_noaff != 0 or elite_w4 <= 0 or elite_w12 <= 0:
		print("[AFFIX] FAIL roll_elite 波3 出 %d(应 0) 无词缀出 %d(应 0) 波4 出 %d(应>0) 波12 出 %d(应>0)" % [
			elite_early, elite_noaff, elite_w4, elite_w12]); fail += 1
	else:
		print("[AFFIX] ok  roll_elite 双门槛(波<4 恒否 / 无词缀恒否), 波 4 出 %d/3000 · 波 12 出 %d/2000" % [
			elite_w4, elite_w12])

	# ---- 6. 六词缀数值倍率逐一落地(hp / speed / 碰撞半径 / 视觉缩放) ----
	# 视觉缩放单独验: 它走 _ensure_visual 的乘法链(每 kind 基准 × 词缀 size × 精英 size),
	# 与碰撞半径是**两条独立代码路径** —— 只验 _r 会漏掉"数值对了但看起来没变大"
	total += 1
	_calm_field("apprentice", "wand")
	var p6: Node2D = GameManager.player
	p6.restore_weapons({}, {})
	await get_tree().physics_frame
	var vis_base: float = float(Dictionary(GameManager.ENEMY_VISUAL.get(0, {})).get("scale", 1.0))
	var mbad: Array = []
	for k in akeys:
		var m: Dictionary = AFF[k].get("mult", {})
		var wb: float = float(m.get("hp", 1.0))
		var ws: float = float(m.get("speed", 1.0))
		var wz: float = float(m.get("size", 1.0))
		var eb = ObjectPool.spawn_enemy(0, far)              # 同帧基准: 三条全局倍率自消
		var ea = ObjectPool.spawn_enemy(0, far, str(k))
		var got: Array = [
			["hp", float(ea.hp) / float(eb.hp), wb],
			["max_hp", float(ea._max_hp) / float(eb._max_hp), wb],
			["speed", float(ea.speed) / float(eb.speed), ws],
			["hit_r", float(ea.collision_radius()) / float(eb.collision_radius()), wz],
			["vis", float(ea.sprite.scale.x) / float(eb.sprite.scale.x), wz],
		]
		for g in got:
			if absf(float(g[1]) - float(g[2])) > 0.002:
				mbad.append("%s.%s 实测 %.4f≠表 %.4f" % [str(k), str(g[0]), float(g[1]), float(g[2])])
		if absf(float(ea.sprite.scale.x) - vis_base * wz) > 0.002:
			mbad.append("%s 视觉缩放 %.3f≠基准 %.3f×%.2f" % [str(k), float(ea.sprite.scale.x), vis_base, wz])
		ObjectPool.release(eb)
		ObjectPool.release(ea)
		GameManager.enemies.erase(eb)
		GameManager.enemies.erase(ea)
	if not mbad.is_empty():
		print("[AFFIX] FAIL 词缀倍率: %s" % "; ".join(mbad)); fail += 1
	else:
		print("[AFFIX] ok  六词缀 hp/speed/碰撞/视觉 五项倍率逐一与表一致(共 %d 个比值)" % (akeys.size() * 5))

	# ---- 7. 再生: 按表速率回血 + 封顶 + 非再生对照不回 ----
	total += 1
	_calm_field("apprentice", "wand")
	var p7: Node2D = GameManager.player
	p7.restore_weapons({}, {})
	await get_tree().physics_frame
	p7.global_position = home
	var regen_v: float = float(AFF["regen"]["regen"])
	var erg = ObjectPool.spawn_enemy(0, far, "regen")
	erg.speed = 0.0                     # 钉住: 走近会触发接触伤害, 与回血无关但会扰动玩家
	erg.hp = erg._max_hp * 0.5
	var rg0: float = erg.hp
	# 60 个 physics tick = 精确 1.0s(delta 恒 1/60, headless 下 tick 数由 await 保证)
	for i in range(60):
		erg.global_position = far
		await get_tree().physics_frame
	var gained: float = erg.hp - rg0
	erg.hp = erg._max_hp - 0.5
	for i in range(60):
		erg.global_position = far
		await get_tree().physics_frame
	var capped: float = erg._max_hp - erg.hp
	var esw = ObjectPool.spawn_enemy(0, far, "swift")
	esw.speed = 0.0
	esw.hp = esw._max_hp * 0.5
	var sw0: float = esw.hp
	for i in range(60):
		esw.global_position = far
		await get_tree().physics_frame
	var swift_gain: float = esw.hp - sw0
	if absf(gained - regen_v) > 0.2 or absf(capped) > 0.001 or absf(swift_gain) > 0.001 \
		or float(erg._regen) != regen_v or float(esw._regen) != 0.0:
		print("[AFFIX] FAIL 再生 回血 %.2f(应 %.1f/s) 封顶残差 %.3f(应 0) 疾风对照回血 %.2f(应 0) _regen %.1f/%.1f" % [
			gained, regen_v, capped, swift_gain, float(erg._regen), float(esw._regen)]); fail += 1
	else:
		print("[AFFIX] ok  再生 1s 回 %.2f 血(表 %.1f), 到 _max_hp 夹住不溢, 非再生词缀零回血" % [gained, regen_v])

	# ---- 8. 射手: 拉开距离才开火 + 敌弹伤害 = damage × 0.75 ----
	# 门槛是 to_player.length() > _r + 60 —— 贴身不射是给风筝留空间, 写反就成了贴脸喷
	total += 1
	_calm_field("apprentice", "wand")
	var p8: Node2D = GameManager.player
	p8.restore_weapons({}, {})
	await get_tree().physics_frame
	var near: Vector2 = home + Vector2.RIGHT * 40.0     # 40 < _r+60=72 不射, 且 > _r+PLAYER_RADIUS=22 不接触
	var efar = ObjectPool.spawn_enemy(0, far, "shooter")
	efar.speed = 0.0
	var near_e = ObjectPool.spawn_enemy(0, near, "shooter")
	near_e.speed = 0.0
	# 计数用「无→有」的边沿, 不数每帧在场数: 敌弹命中后被 release 回池, 下一发可能复用
	# 同一节点(instance_id 相同), 用 id 去重会漏计。也**绝不用 projectiles.clear()** ——
	# 那只把节点从列表里摘掉, 节点本身还在树上飞且 visible/processing 全开(泄漏 + 会打玩家)
	var shot_dmg := -1.0
	var shots := 0
	var had := false
	for i in range(240):                # 4s: interval 2.2s => 远的那只应打两发
		efar.global_position = far
		near_e.global_position = near
		p8.global_position = home
		p8.hp = p8.max_hp_value()
		p8.invuln_timer = 1.0           # 免掉敌弹/接触伤害, 否则玩家会死在自检里
		await get_tree().physics_frame
		var now := false
		for b in GameManager.projectiles:
			if is_instance_valid(b) and str(b.team) == "enemy":
				now = true
				if shot_dmg < 0.0:
					shot_dmg = float(b.damage)
		if now and not had:
			shots += 1
		had = now
	var want_dmg: float = float(efar.damage) * 0.75
	if shots <= 0 or absf(shot_dmg - want_dmg) > 0.01 or float(efar._fire_interval) <= 0.0:
		print("[AFFIX] FAIL 射手 敌弹 %d 发(应>0) 伤害 %.2f(应 %.2f = damage×0.75) interval %.2f" % [
			shots, shot_dmg, want_dmg, float(efar._fire_interval)]); fail += 1
	else:
		print("[AFFIX] ok  射手 远距开火, 敌弹伤害 %.2f(= damage %.1f × 0.75)" % [shot_dmg, float(efar.damage)])

	total += 1
	# 反向: 贴身 40px 蹲 4s 必须一发不出(上一组已同时跑了这只, 这里独立复算一次干净的)
	_calm_field("apprentice", "wand")
	var p8b: Node2D = GameManager.player
	p8b.restore_weapons({}, {})
	await get_tree().physics_frame
	var eclose = ObjectPool.spawn_enemy(0, near, "shooter")
	eclose.speed = 0.0
	var close_shots := 0
	for i in range(240):
		eclose.global_position = near
		p8b.global_position = home
		p8b.hp = p8b.max_hp_value()
		p8b.invuln_timer = 1.0
		await get_tree().physics_frame
		for b in GameManager.projectiles:
			if is_instance_valid(b) and str(b.team) == "enemy":
				close_shots += 1
		# 清场走 release(回收节点 + 从列表摘), 不是 clear() 裸摘 —— 否则 240 帧会攒下
		# 一堆仍在飞、仍可见、仍会命中玩家的孤儿敌弹
		for b2 in GameManager.projectiles.duplicate():
			ObjectPool.release(b2)
		GameManager.projectiles.clear()
	if close_shots != 0:
		print("[AFFIX] FAIL 射手近距门槛 40px 蹲 4s 打出 %d 发敌弹(应 0, 门槛 _r+60=%.0f)" % [
			close_shots, float(eclose.collision_radius()) + 60.0]); fail += 1
	else:
		print("[AFFIX] ok  射手 40px 内蹲 4s 零开火(门槛 _r+60=%.0f, 保留风筝空间)" % (
			float(eclose.collision_radius()) + 60.0))

	# ---- 9. 分裂: die() 生 2 只子代, 五项系数 + 不继承词缀/精英 ----
	total += 1
	_calm_field("apprentice", "wand")
	var p9: Node2D = GameManager.player
	p9.restore_weapons({}, {})
	await get_tree().physics_frame
	p9.global_position = home
	var ebase = ObjectPool.spawn_enemy(0, far)          # 无词缀基准(子代也是无词缀 spawn)
	var esp = ObjectPool.spawn_enemy(0, far, "split")
	esp.speed = 0.0
	var before_list: Array = GameManager.enemies.duplicate()   # 按引用差集找新生子代, 不靠数组末尾
	var gems_before: int = GameManager.gems.size()
	GameManager.kills = 0
	esp.die()
	var offspring: Array = []
	for e in GameManager.enemies:
		if not before_list.has(e):
			offspring.append(e)
	var split_n: int = int(AFF["split"]["split"])
	var sbad: Array = []
	if not before_list.has(esp) or GameManager.enemies.has(esp):
		sbad.append("父体未从 enemies 摘除(会重复结算/重复入池)")
	if offspring.size() != split_n:
		sbad.append("子代 %d 只(应 %d)" % [offspring.size(), split_n])
	if int(GameManager.kills) != 1:
		sbad.append("kills=%d(应 1)" % int(GameManager.kills))
	if GameManager.gems.size() <= gems_before:
		sbad.append("未掉宝石(%d→%d)" % [gems_before, GameManager.gems.size()])
	var i := 0
	for o in offspring:
		if not bool(o._is_offspring):
			sbad.append("子代 %d 未打 _is_offspring 标记" % i)
		if str(o.affix) != "" or str(o.affix2) != "" or bool(o.is_elite):
			sbad.append("子代 %d 继承了词缀/精英(%s/%s/%s) —— 会无限分裂" % [
				i, str(o.affix), str(o.affix2), str(o.is_elite)])
		var ratios: Array = [
			["hp", float(o.hp) / float(ebase.hp), 0.4],
			["max_hp", float(o._max_hp) / float(ebase._max_hp), 0.4],
			["damage", float(o.damage) / float(ebase.damage), 0.5],
			["speed", float(o.speed) / float(ebase.speed), 1.2],
			["hit_r", float(o.collision_radius()) / float(ebase.collision_radius()), 0.7],
			["xp", float(o.xp_value) / float(ebase.xp_value), 0.5],
			["vis", float(o.sprite.scale.x) / float(ebase.sprite.scale.x), 0.7],
		]
		for r in ratios:
			if absf(float(r[1]) - float(r[2])) > 0.002:
				sbad.append("子代 %d 的 %s 比值 %.3f≠%.2f" % [i, str(r[0]), float(r[1]), float(r[2])])
		i += 1
	if not sbad.is_empty():
		print("[AFFIX] FAIL 分裂: %s" % "; ".join(sbad)); fail += 1
	else:
		print("[AFFIX] ok  分裂 die() 生 %d 只子代(七项系数 0.4/0.5/1.2/0.7/0.5/0.7 全中), 无词缀继承, 计击杀掉宝石" % split_n)

	# ---- 9b. 经验总量诚实性: 掉的宝石 xp 之和 == 怪的 xp_value(锁死 spawn_gems 的 per 修复) ----
	# 原 spawn_gems 每颗宝石写死 1.0、颗数 = int(xp_value) => 小数被静默截掉, 两处不诚实:
	#   (a) 词缀怪 ×1.3 对 xp=1~2 主流杂兵无效(史莱姆 1.3→1、骷髅 2.6→2), 图鉴明写「×1.3」玩家拿不到;
	#   (b) 分裂子代 ×0.5 让 xp=1 的怪变 0.5 → int → **0 颗**, 图鉴说「经验减半」实为「清零」。
	# 修复后每颗 = xp_value/count, 总量精确等于 xp_value。本断言直接数 spawn_gems 新增宝石的 xp 字段
	# 之和(不经 collect, 故不含 xp_mult 倍率), 应 == xp_value; 并验 xp>0 必掉 ≥1 颗(子代不再清零)。
	# 全程同步无 await: spawn_gems 不依赖 player, 怪在 far 也打不到, 不需要清武器或冻帧。
	total += 1
	_calm_field("apprentice", "wand")
	var xbad: Array = []
	var samples: Array = [
		ObjectPool.spawn_enemy(0, far, "swift"),    # 史莱姆带词缀: xp 1×1.3=1.3, 应掉 1 颗值 1.3
		ObjectPool.spawn_enemy(3, far, "tanky"),    # 骷髅带词缀: xp 2×1.3=2.6, 应掉 2 颗各 1.3
	]
	var sub = ObjectPool.spawn_enemy(0, far)        # 不写类型标注: scale_split_offspring 是 enemy 的
	sub.scale_split_offspring()                     # 分裂子代: xp 1×0.5=0.5, 修复前 0 颗, 应掉 1 颗值 0.5
	samples.append(sub)
	for s in samples:
		var g_before: Array = GameManager.gems.duplicate()
		s.spawn_gems()
		var sum_xp := 0.0
		var n_new := 0
		for g in GameManager.gems:
			if not g_before.has(g):                 # 差集只数本次新增(前一样本的宝石已在 g_before 里)
				sum_xp += float(g.xp)
				n_new += 1
		var tag: String = str(s.affix) if str(s.affix) != "" else "分裂子代"
		if absf(sum_xp - float(s.xp_value)) > 0.01:
			xbad.append("kind%d(%s) 掉 %d 颗 xp 和 %.3f ≠ xp_value %.3f" % [
				int(s.kind), tag, n_new, sum_xp, float(s.xp_value)])
		if float(s.xp_value) > 0.0 and n_new == 0:
			xbad.append("kind%d(%s) xp=%.2f>0 却掉 0 颗(经验被 int 截断清零)" % [int(s.kind), tag, float(s.xp_value)])
	if not xbad.is_empty():
		print("[AFFIX] FAIL 经验总量诚实性: %s" % "; ".join(xbad)); fail += 1
	else:
		print("[AFFIX] ok  词缀怪/分裂子代掉的宝石 xp 之和精确等于 xp_value(无 int 截断丢经验)")

	# ---- 10. die_without_reward(): 波末清场不触发任何词缀 ----
	# 这条是"清场"的语义底线: 残怪若也爆炸/分裂, 玩家会在波末被凭空炸死
	total += 1
	_calm_field("apprentice", "wand")
	var p10: Node2D = GameManager.player
	p10.restore_weapons({}, {})
	await get_tree().physics_frame
	p10.global_position = home
	var edx = ObjectPool.spawn_enemy(0, home + Vector2.RIGHT * 30.0, "explosive", "split", true)
	edx.speed = 0.0
	await get_tree().physics_frame
	p10.global_position = home
	p10.hp = p10.max_hp_value()
	p10.invuln_timer = 0.0
	var hp_dwr: float = p10.hp
	var n_dwr: int = GameManager.enemies.size()
	var gems_dwr: int = GameManager.gems.size()
	GameManager.kills = 0
	edx.die_without_reward()
	await get_tree().physics_frame
	var dwr_bad: Array = []
	if absf(p10.hp - hp_dwr) > 0.001:
		dwr_bad.append("玩家掉血 %.1f(自爆被触发了)" % (hp_dwr - float(p10.hp)))
	if GameManager.enemies.size() != n_dwr - 1:
		dwr_bad.append("敌人数 %d→%d(应只少自己那 1 只, 分裂被触发了)" % [n_dwr, GameManager.enemies.size()])
	if int(GameManager.kills) != 0:
		dwr_bad.append("kills=%d(清场不应计击杀)" % int(GameManager.kills))
	if GameManager.gems.size() != gems_dwr:
		dwr_bad.append("宝石 %d→%d(清场不应掉奖励)" % [gems_dwr, GameManager.gems.size()])
	if not dwr_bad.is_empty():
		print("[AFFIX] FAIL die_without_reward: %s" % "; ".join(dwr_bad)); fail += 1
	else:
		print("[AFFIX] ok  die_without_reward 不爆炸/不分裂/不计击杀/不掉奖励(波末清场静默回收)")

	# ---- 11. 自爆: 圈内吃满表值伤害, 圈外零伤 ----
	total += 1
	_calm_field("apprentice", "wand")
	var p11: Node2D = GameManager.player
	p11.restore_weapons({}, {})
	await get_tree().physics_frame
	var boom_r: float = float(AFF["explosive"]["explode_r"])
	var boom_dmg: float = float(AFF["explosive"]["explode_dmg"])
	var threshold: float = boom_r + GameManager.PLAYER_RADIUS
	# 圈内: 30px(< threshold 52, 但 > _r+PLAYER_RADIUS 22 所以不吃接触伤害, 只可能是爆炸)
	var ein = ObjectPool.spawn_enemy(0, home + Vector2.RIGHT * 30.0, "explosive")
	ein.speed = 0.0
	await get_tree().physics_frame
	p11.global_position = home
	p11.hp = p11.max_hp_value()
	p11.invuln_timer = 0.0
	var hp_in: float = p11.hp
	ein.global_position = home + Vector2.RIGHT * 30.0
	ein.die()
	var lost_in: float = hp_in - p11.hp
	# 圈外: 100px > threshold
	var eout = ObjectPool.spawn_enemy(0, home + Vector2.RIGHT * 100.0, "explosive")
	eout.speed = 0.0
	p11.hp = p11.max_hp_value()
	p11.invuln_timer = 0.0
	var hp_out: float = p11.hp
	eout.die()
	var lost_out: float = hp_out - p11.hp
	if absf(lost_in - boom_dmg) > 0.01 or absf(lost_out) > 0.001:
		print("[AFFIX] FAIL 自爆 圈内(30px)掉 %.1f(应 %.1f) 圈外(100px)掉 %.1f(应 0), 判定半径 %.0f" % [
			lost_in, boom_dmg, lost_out, threshold]); fail += 1
	else:
		print("[AFFIX] ok  自爆 半径 %.0f+玩家 %.0f=%.0f 内掉 %.1f 血, 圈外零伤" % [
			boom_r, GameManager.PLAYER_RADIUS, threshold, lost_in])

	# ---- 12. 精英双词缀: 两条行为参数并存 + has() 守卫两向都不被抹零 ----
	# CLAUDE.md 记的坑: 行为参数是**赋值不是累加**, 若写成 a.get("regen", 0.0) 无条件赋值,
	# "再生+疾风"的第二条(疾风无 regen 键)会把第一条的 _regen 抹成 0 —— 词缀静默失效。
	# 两个顺序都测, 因为 _apply_affix(affix) 与 _apply_affix(affix2) 是先后两次调用
	total += 1
	_calm_field("apprentice", "wand")
	var p12: Node2D = GameManager.player
	p12.restore_weapons({}, {})
	await get_tree().physics_frame
	var split_n2: int = int(AFF["split"]["split"])
	var e_rs = ObjectPool.spawn_enemy(0, far, "regen", "split", true)     # 两条都有行为参数
	var e_rw = ObjectPool.spawn_enemy(0, far, "regen", "swift", true)     # 第二条无行为键(守卫正向)
	var e_wr = ObjectPool.spawn_enemy(0, far, "swift", "regen", true)     # 第一条无行为键(守卫反向)
	var gbad: Array = []
	if absf(float(e_rs._regen) - regen_v) > 0.001 or int(e_rs._split) != split_n2:
		gbad.append("再生+分裂: _regen %.1f(应 %.1f) _split %d(应 %d)" % [
			float(e_rs._regen), regen_v, int(e_rs._split), split_n2])
	if absf(float(e_rw._regen) - regen_v) > 0.001 or int(e_rw._split) != 0:
		gbad.append("再生+疾风: _regen %.1f 被第二条抹零(应 %.1f)" % [float(e_rw._regen), regen_v])
	if absf(float(e_wr._regen) - regen_v) > 0.001:
		gbad.append("疾风+再生: _regen %.1f(应 %.1f)" % [float(e_wr._regen), regen_v])
	for e in [e_rs, e_rw, e_wr]:
		if float(e._fire_interval) != 0.0 or float(e._explode_r) != 0.0:
			gbad.append("未带的词缀参数漏进来了(interval %.2f / explode_r %.1f)" % [
				float(e._fire_interval), float(e._explode_r)])
	if not gbad.is_empty():
		print("[AFFIX] FAIL 精英双词缀: %s" % "; ".join(gbad)); fail += 1
	else:
		print("[AFFIX] ok  精英双词缀行为并存(再生 %.1f/s + 分裂 %d 只), has() 守卫两向都不抹零, 无参数串味" % [
			regen_v, split_n2])

	# ---- 13. 精英数值链: 双词缀 mult 各乘一次, 再叠精英层; 碰撞 1.15 与视觉 1.35 分离 ----
	total += 1
	var eb13 = ObjectPool.spawn_enemy(0, far)
	var ee13 = ObjectPool.spawn_enemy(0, far, "tanky", "swift", true)
	var m1: Dictionary = AFF["tanky"]["mult"]
	var m2: Dictionary = AFF["swift"]["mult"]
	var want_hp: float = float(m1.get("hp", 1.0)) * float(m2.get("hp", 1.0)) * float(EL["hp"])
	var want_spd: float = float(m1.get("speed", 1.0)) * float(m2.get("speed", 1.0)) * float(EL["speed"])
	var want_r: float = float(m1.get("size", 1.0)) * float(m2.get("size", 1.0)) * float(EL["hit_r"])
	var want_vis: float = float(m1.get("size", 1.0)) * float(m2.get("size", 1.0)) * float(EL["size"])
	var want_xp: float = 1.3 * 1.3 * float(EL["xp"])
	var ebad: Array = []
	var pairs: Array = [
		["hp", float(ee13.hp) / float(eb13.hp), want_hp],
		["damage", float(ee13.damage) / float(eb13.damage), float(EL["damage"])],
		["speed", float(ee13.speed) / float(eb13.speed), want_spd],
		["hit_r", float(ee13.collision_radius()) / float(eb13.collision_radius()), want_r],
		["vis", float(ee13.sprite.scale.x) / float(eb13.sprite.scale.x), want_vis],
		["xp", float(ee13.xp_value) / float(eb13.xp_value), want_xp],
	]
	for q in pairs:
		if absf(float(q[1]) - float(q[2])) > 0.005:
			ebad.append("%s 实测 %.4f≠应 %.4f" % [str(q[0]), float(q[1]), float(q[2])])
	# 碰撞放大必须严格小于视觉放大: 相等或更大就会"看着没碰到也掉血"
	if float(EL["hit_r"]) >= float(EL["size"]):
		ebad.append("ELITE_BASE.hit_r %.2f ≥ size %.2f(会打空气掉血)" % [float(EL["hit_r"]), float(EL["size"])])
	if not ebad.is_empty():
		print("[AFFIX] FAIL 精英数值链: %s" % "; ".join(ebad)); fail += 1
	else:
		print("[AFFIX] ok  精英 双词缀各乘一次再叠精英层(hp ×%.2f / 伤 ×%.1f / xp ×%.2f), 碰撞 ×%.2f < 视觉 ×%.2f" % [
			want_hp, float(EL["damage"]), want_xp, float(EL["hit_r"]), float(EL["size"])])

	# ---- 14. 精英识别链: 紫覆盖染色 + 光环 + 头顶双词缀副标; 普通怪三者全隐藏 ----
	# 副标是打磨#7: 紫光环只说明"是精英", 说明不了"哪两条" —— 自爆+疾风与分裂+再生方针相反
	total += 1
	var vbad: Array = []
	if not Color(ee13._affix_tint).is_equal_approx(Color(EL["tint"])):
		vbad.append("精英染色 %s 不是表里的紫 %s(混色会让识别信号失效)" % [
			str(ee13._affix_tint), str(EL["tint"])])
	if not bool(ee13._aura.visible) or not bool(ee13._elite_label.visible):
		vbad.append("精英光环/副标未显示(aura=%s label=%s)" % [
			str(ee13._aura.visible), str(ee13._elite_label.visible)])
	var want_txt: String = str(AFF["tanky"]["name"]) + "·" + str(AFF["swift"]["name"])
	if str(ee13._elite_label.text) != want_txt:
		vbad.append("精英副标 \"%s\"≠\"%s\"" % [str(ee13._elite_label.text), want_txt])
	var et13 = ObjectPool.spawn_enemy(0, far, "tanky")   # 单词缀普通怪: 有染色但绝不该有精英视觉
	for e in [eb13, et13]:
		if bool(e._aura.visible) or bool(e._elite_label.visible) or bool(e.is_elite):
			vbad.append("普通怪(词缀 %s)显示精英视觉(aura=%s label=%s elite=%s)" % [
				str(e.affix), str(e._aura.visible), str(e._elite_label.visible), str(e.is_elite)])
	if not vbad.is_empty():
		print("[AFFIX] FAIL 精英识别链: %s" % "; ".join(vbad)); fail += 1
	else:
		print("[AFFIX] ok  精英 紫覆盖染色 + 光环 + 副标「%s」, 普通怪(含单词缀)三者全隐藏" % want_txt)

	# ---- 15. 词缀染色真的进了 sprite.modulate(玩家能看出来这条的唯一通道) ----
	total += 1
	_calm_field("apprentice", "wand")
	var p15: Node2D = GameManager.player
	p15.restore_weapons({}, {})
	await get_tree().physics_frame
	p15.global_position = home
	var tint_bad: Array = []
	for k in akeys:
		var et = ObjectPool.spawn_enemy(0, home + Vector2.RIGHT * 150.0, str(k))
		et.speed = 0.0
		et._status.clear()
		et._flash = 0.0
		await get_tree().physics_frame
		et.global_position = home + Vector2.RIGHT * 150.0
		if not Color(et.sprite.modulate).is_equal_approx(Color(et._affix_tint)):
			tint_bad.append("%s 染色 %s≠表色 %s" % [str(k), str(et.sprite.modulate), str(AFF[k]["color"])])
		if not Color(et._affix_tint).is_equal_approx(Color(AFF[k]["color"])):
			tint_bad.append("%s 的 _affix_tint %s≠表色 %s" % [str(k), str(et._affix_tint), str(AFF[k]["color"])])
		ObjectPool.release(et)
		GameManager.enemies.erase(et)
	if not tint_bad.is_empty():
		print("[AFFIX] FAIL 词缀染色: %s" % "; ".join(tint_bad)); fail += 1
	else:
		print("[AFFIX] ok  六词缀染色逐一落到 sprite.modulate(与表色一致, 玩家可辨识)")

	# ---- 16. 池复用无条件复位: 精英双词缀怪回收后, 下一个拿到该节点的必须是干净白怪 ----
	# CLAUDE.md 记的坑: setup() 里写条件赋值会漏出"普通怪带紫光环 + 2.6 倍血"。
	# ObjectPool 是 LIFO(pop_back/push_back), 回收后立刻 spawn 必拿回同一节点 ——
	# 顺带断言节点同一性, 若哪天池改成 FIFO 这条会明确报出来(而不是静默变成空测)
	total += 1
	_calm_field("apprentice", "wand")
	var p16: Node2D = GameManager.player
	p16.restore_weapons({}, {})
	await get_tree().physics_frame
	var dirty = ObjectPool.spawn_enemy(0, far, "regen", "explosive", true)
	dirty.die_without_reward()
	var clean = ObjectPool.spawn_enemy(0, far)
	var base_e = ObjectPool.spawn_enemy(0, far)          # 同 kind 干净基准(绝对值直接可比)
	var rbad: Array = []
	if clean != dirty:
		rbad.append("池未复用同一节点(池不是 LIFO 了, 本条复位断言失去意义)")
	if bool(clean.is_elite) or str(clean.affix) != "" or str(clean.affix2) != "":
		rbad.append("elite=%s affix=\"%s\" affix2=\"%s\" 未复位" % [
			str(clean.is_elite), str(clean.affix), str(clean.affix2)])
	if bool(clean._is_offspring):
		rbad.append("_is_offspring 未复位")
	if float(clean._regen) != 0.0 or float(clean._explode_r) != 0.0 or float(clean._explode_dmg) != 0.0 \
		or float(clean._fire_interval) != 0.0 or int(clean._split) != 0:
		rbad.append("行为参数残留(regen %.1f / explode_r %.1f / interval %.2f / split %d)" % [
			float(clean._regen), float(clean._explode_r), float(clean._fire_interval), int(clean._split)])
	if not Color(clean._affix_tint).is_equal_approx(Color(1, 1, 1)):
		rbad.append("_affix_tint 残留紫色 %s" % str(clean._affix_tint))
	# 副标 text 对无词缀怪是 ELITE_BASE["name"] 兜底(不是空串), 故只验 visible + 无 "·" 分隔
	if bool(clean._aura.visible) or bool(clean._elite_label.visible) or str(clean._elite_label.text).find("·") >= 0:
		rbad.append("精英视觉残留(aura=%s label=%s text=\"%s\")" % [
			str(clean._aura.visible), str(clean._elite_label.visible), str(clean._elite_label.text)])
	if absf(float(clean.hp) - float(base_e.hp)) > 0.001 or absf(float(clean._max_hp) - float(base_e._max_hp)) > 0.001:
		rbad.append("hp %.2f/%.2f ≠ 干净基准 %.2f/%.2f(精英 2.6× 或词缀 mult 残留)" % [
			float(clean.hp), float(clean._max_hp), float(base_e.hp), float(base_e._max_hp)])
	if absf(float(clean.collision_radius()) - float(base_e.collision_radius())) > 0.001:
		rbad.append("碰撞半径 %.3f ≠ 干净基准 %.3f(hit_r/size 残留)" % [
			float(clean.collision_radius()), float(base_e.collision_radius())])
	if absf(float(clean.sprite.scale.x) - vis_base) > 0.002:
		rbad.append("视觉缩放 %.3f ≠ kind 基准 %.3f(size 链残留)" % [float(clean.sprite.scale.x), vis_base])
	# offset 残留是"怪飘空"的成因: 骷髅的 -3 会带到复用的史莱姆身上(CLAUDE.md 记的坑)
	var off0: float = float(Dictionary(GameManager.ENEMY_VISUAL.get(0, {})).get("offset", Vector2.ZERO).y)
	if absf(float(clean.sprite.offset.y) - off0) > 0.001:
		rbad.append("sprite.offset.y %.2f ≠ kind0 基准 %.2f —— 怪会飘空" % [
			float(clean.sprite.offset.y), off0])
	if not rbad.is_empty():
		print("[AFFIX] FAIL 池复用复位: %s" % "; ".join(rbad)); fail += 1
	else:
		print("[AFFIX] ok  池复用 13 项无条件复位(精英标记/双词缀/行为参数/染色/光环/副标/hp/碰撞/缩放/offset)")

	print("[AFFIX] FINAL total=%d fail=%d" % [total, fail])
	if fail > 0:
		print("[AFFIX] ASSERT-FAIL")
	get_tree().quit()


# ================= 全界面截图(--ui-shot) =================
# 必须用带窗口 exe(headless dummy renderer 截出来全黑, 同 --codex-shot)
# 逐界面截 PNG 存 _ui_shots/, 供目检布局/配色/遮挡; 跑完自行 quit
# 战斗图不等真实刷怪: start_game 后手动在玩家附近摆怪, 确定性且快

func _ui_shots() -> void:
	Autopilot.enabled = false
	Engine.time_scale = 1.0   # 截图要确定性, 忽略用户倍速设置
	var dir := ProjectSettings.globalize_path("res://") + "_ui_shots"
	DirAccess.make_dir_recursive_absolute(dir)

	show_menu()
	await _shot(dir, "01_menu")

	_enter_character_select()
	await _shot(dir, "02_char_select")

	# 战斗: 开局后摆一圈怪 + 金币/拾取, 等 1.2s 让武器真的开火
	# 不撒经验宝石: 磁吸秒吃会当场触发升级, 三选一界面盖住后续所有截图
	start_game("apprentice", "wand")
	# 加成面板正/负/flat 样本: 默认夹具 item_mods 为空面板隐藏, 不塞值目检不到左上排版
	# (test_mode 不落盘, 不污染真档; 波间商店夹具在下方另行覆盖同键)
	player.item_mods["damage_mult"] = 0.15
	player.item_mods["attack_speed_mult"] = 0.10
	player.item_mods["max_hp_flat"] = 20.0
	player.item_mods["move_speed_mult"] = -0.08
	# 诅咒标签目检: 右上第三行(金币下方)紫色「☠ 诅咒 3/10」; 不塞值截图里看不到该标签排版
	GameManager.add_curse(3)
	# 7 只绕圈: i%7 让七种怪各出一只(吐息/自爆/护盾进场后截图必须全覆盖, 目检 scale/offset);
	# 再补 2 只精英(双词缀 swift+tanky / shooter+split): 目检紫色 tint 覆盖、1.35 倍体型、
	# 光环(3d 批)与预警圈。摆在外圈 130px 处, 不与普通怪圈重叠。
	for i in range(7):
		var a := TAU * float(i) / 7.0
		var pos: Vector2 = player.global_position + Vector2.from_angle(a) * 85.0
		spawner.spawn_enemy_at(pos, i, "" if i != 0 else "swift")
	for i in range(2):
		var ea := TAU * (0.25 + float(i) * 0.5)
		var epos: Vector2 = player.global_position + Vector2.from_angle(ea) * 130.0
		if i == 0:
			spawner.spawn_enemy_at(epos, 2, "swift", "tanky", true)
		else:
			spawner.spawn_enemy_at(epos, 3, "shooter", "split", true)
	ObjectPool.spawn_coin(player.global_position + Vector2(50, 30), 5)
	ObjectPool.spawn_pickup(player.global_position + Vector2(-60, 40), "heart")
	await get_tree().create_timer(1.2).timeout
	await _shot(dir, "03_battle")

	# 精英预警圈目检: spawn_enemy_at 直接落地不产 telegraph, 预警圈(0.9s 存活)拍不到,
	# 故手动塞一个 elite 叉。0.4s 后截图(仍在 0.9s 窗口内、未落地), 画面同时有 spawner
	# 自刷的普通红叉与这只紫金双环, 直接对比"进场前"的差异。截完立刻 erase —— 不撤的话
	# 它会落地成一只真精英, 被后续 molotov 火池烧死掉 chest → 三选一暂停 → 废掉后面所有截图。
	var _etg := {"pos": player.global_position + Vector2(0, -70), "t": 0.9, "dur": 0.9,
		"boss": false, "kind": 0, "affix": "swift", "elite": true, "affix2": "tanky"}
	spawner._telegraphs.append(_etg)
	await get_tree().create_timer(0.4).timeout
	await _shot(dir, "03d_elite_marker")
	spawner._telegraphs.erase(_etg)

	# 加成面板折叠态: Tab 折叠的目检(一行「N 项」+ 窄宽); 截完切回展开, 不影响后续界面
	hud._toggle_buffs_panel()
	await get_tree().process_frame
	await _shot(dir, "03b_battle_buffs_collapsed")
	hud._toggle_buffs_panel()
	await get_tree().process_frame

	# 燃烧瓶三档目检: 常态橙红 / Lv3 白热金 / 进化紫(瓶身→火苗→火池是一条视觉链, 三档同屏比)
	# 战斗屏固定 apprentice/wand, 而五角色无一起始 holy_water —— 不加这段夹具,
	# 改这把武器的配色永远拍不到。restore_weapons 直接摆等级, 绕过 gain_weapon 的「军械」加成。
	# 每档等 2.6s(冷却 2.2s): 既要瓶子装满露出瓶口火苗, 也要地上真有一个火池在烧。
	# 夹具纪律(2026-09-10 第二版: t3/evo 两档曾被升级三选一盖屏, 拍出来全是弹窗):
	#   1) 磁吸压成 0 **挡不住升级** —— gem.gd 的 <4px 接触拾取与拾取范围无关, 火池在玩家
	#      脚下烧死怪, 宝石掉在脚边被接触吃掉, xp 攒够就弹三选一暂停。旧注释以为压磁吸就
	#      安全, 实测 t1 之后必弹。
	#   2) 故 2.6s 切成 0.2s 小步, 每步检查: 一旦 state==LEVEL_UP 立即 dismiss(不选卡,
	#      夹具不关心 build)恢复战斗 —— 弹窗只冻结 0.2s, 拍到的仍是战斗画面。
	#   3) 每档开场补撒 4 只怪 —— 上一档火池会把场上烧空, 不补拍到的就是空火池没伤害数字。
	var prev_lv: Dictionary = player.weapon_levels.duplicate(true)
	var prev_ev: Dictionary = player.evolved_weapons.duplicate(true)
	var prev_pick: float = player.base_pick_range
	player.base_pick_range = 0.0
	for mol in [["t1", 1, false], ["t3", 3, false], ["evo", 3, true]]:
		for i in range(4):
			var mpos: Vector2 = player.global_position + Vector2.from_angle(TAU * float(i) / 4.0 + 0.4) * 30.0
			spawner.spawn_enemy_at(mpos, i % 4, "")
		player.restore_weapons({"holy_water": mol[1]}, {"holy_water": true} if mol[2] else {})
		for _step in range(13):
			await get_tree().create_timer(0.2).timeout
			_dismiss_levelup()
		await _shot(dir, "03c_molotov_%s" % mol[0])
	player.base_pick_range = prev_pick
	player.restore_weapons(prev_lv, prev_ev)
	# 清光地上残留宝石: 燃烧瓶三档期间磁吸压 0, 火池烧死的怪掉的宝石全堆在场内(几十颗)。
	# 磁吸一恢复它们成群飞向玩家被连吃, xp 瞬间过阈弹三选一 —— 单次 _dismiss_levelup 挡不住
	# 「_shot 等 2 帧里又吃一颗」, 必须从源头清掉(2026-09-10 实测 04_boss 二次被盖)。
	for g in GameManager.gems.duplicate():
		if is_instance_valid(g):
			ObjectPool.release(g)
	GameManager.gems.clear()
	await get_tree().process_frame

	# Boss 战: 场上摆中 Boss + 终极 Boss
	var bpos: Vector2 = player.global_position + Vector2(110, -30)
	ObjectPool.spawn_boss(1, bpos)
	var fb := ObjectPool.spawn_boss(2, bpos + Vector2(0, 70))
	fb.make_final()
	await get_tree().create_timer(0.8).timeout
	# 0.8s 等待里残留宝石仍可能被接触拾取弹三选一(2026-09-10 实测 04_boss 被弹窗盖), 拍前再收一次
	_dismiss_levelup()
	await _shot(dir, "04_boss")

	# 升级三选一(暂停界面): 给点等级让选项池像实战
	GameManager.level = 8
	trigger_level_up()
	await _shot(dir, "05_levelup")
	get_tree().paused = false
	GameManager.state = GameManager.State.PLAYING
	hud.show_hud()
	await get_tree().process_frame

	# 波间商店: coins=12 让「买得起(金价)/买不起(红价)」两态同屏可见(刷新费也超预算)
	# item_mods 塞正负样本, 露芯片流两态(绿正/红负); 都是截图夹具, test_mode 不落盘
	GameManager.coins = 12.0
	GameManager.wave = 4
	player.item_mods["damage_mult"] = 0.15
	player.item_mods["attack_speed_mult"] = 0.10
	player.item_mods["max_hp_flat"] = 20.0
	player.item_mods["move_speed_mult"] = -0.08
	player.item_mods["pick_range_mult"] = -0.12
	open_wave_shop()
	await _shot(dir, "06_wave_shop")
	get_tree().paused = false
	GameManager.state = GameManager.State.PLAYING

	# 局外永久商店(主菜单进入)。show_shop 不改 state 也不暂停(真实入口在 MENU),
	# 夹具里游戏还在跑 => _shot 等待帧中升级会触发 trigger_level_up 的 _clear_all 把商店屏清掉。
	# 夹具手动暂停、拍完恢复(渲染与暂停无关, 截图不受影响; 不给真实商店路径引入暂停)。
	# upgrades_owned 是玩家真档的内存态, 不钉死则截图随存档漂移(满档全「已满级」/新档全金价),
	# 故备份后塞混合等级: 金价(买得起)/红价(买不起)/已满级三态同屏; test_mode 不落盘, 拍完还原。
	var owned_bak: Dictionary = GameManager.upgrades_owned.duplicate()
	GameManager.upgrades_owned = {"meta_damage": 0, "meta_speed": 2, "meta_pick": 5,
		"meta_hp": 4, "meta_greed": 4, "meta_weapon": 0}
	GameManager.bank = 500.0
	get_tree().paused = true
	hud.show_shop()
	await _shot(dir, "07_meta_shop")
	# 余额不足反馈取证: 点红价行(贪婪 lv4 下一级 520 > 500)→「还差 20」toast。
	# 暂停中 toast 的 tween 不走 => 截帧时红字满不透明度, 正好取证
	hud._on_shop_buy("meta_greed")
	await _shot(dir, "07b_meta_shop_short")
	get_tree().paused = false
	GameManager.upgrades_owned = owned_bak

	# 设置(游戏内来源, 带「返回战斗」与图鉴入口)
	GameManager.state = GameManager.State.PLAYING
	GameManager.settings_return_state = GameManager.State.PLAYING
	hud.show_settings()
	await _shot(dir, "08_settings")

	# 图鉴首页(细部走 --codex-shot, 这里只验入口与开书布局)
	hud.show_codex()
	await get_tree().create_timer(0.5).timeout
	await _shot(dir, "09_codex")

	# 死亡结算
	get_tree().paused = false
	GameManager.state = GameManager.State.PLAYING
	GameManager.time_s = 214.0
	GameManager.kills = 183
	GameManager.level = 11
	game_over()
	await _shot(dir, "10_game_over")

	# 通关结算
	GameManager.time_s = 347.0
	GameManager.kills = 601
	GameManager.boss_kills = 4
	GameManager.level = 20
	on_final_boss_defeated()
	await _shot(dir, "11_victory")

	# 有续玩档时的主菜单(6 项: 继续/重新开始/设置/商店/图鉴/退出)+ 重开确认框。
	# test_mode 下 save_suspend 不落盘, 故用 force_test 旁路造一份夹具档; 会覆写玩家真实档,
	# 所以开头备份、结尾还原(start_game 会 clear_suspend, 备份必须在它之前做)。
	var bak := GameManager.SUSPEND_PATH + ".uishot.bak"
	var had_real := FileAccess.file_exists(GameManager.SUSPEND_PATH)
	if had_real:
		var src := FileAccess.open(GameManager.SUSPEND_PATH, FileAccess.READ)
		var content := src.get_buffer(src.get_length())
		src.close()
		var bf := FileAccess.open(bak, FileAccess.WRITE)
		bf.store_buffer(content)
		bf.close()

	get_tree().paused = false
	start_game("apprentice", "wand")   # 取一份合法的 player/spawner 状态供写档
	GameManager.wave = 5
	GameManager.wave_time = 11.0
	GameManager.time_s = 132.0
	GameManager.kills = 96
	GameManager.level = 9
	GameManager.coins = 41.0
	spawner._start_wave(5)
	GameManager.save_suspend(true)
	show_menu()
	await _shot(dir, "12_menu_with_save")

	hud._on_menu_restart_ask()   # 确认框盖在主菜单上(state 仍为 MENU)
	await _shot(dir, "13_restart_confirm")
	hud._on_menu_restart_cancel()

	# 还原玩家真实档
	GameManager.clear_suspend(true)   # 删夹具档, 再还原备份
	var udir := DirAccess.open("user://")
	if udir != null:
		if had_real:
			udir.rename(bak.get_file(), GameManager.SUSPEND_PATH.get_file())
		elif FileAccess.file_exists(bak):
			udir.remove(bak.get_file())

	get_tree().quit()


# 截图夹具专用: 若升级三选一已弹出则不选卡直接关掉恢复战斗。
# 宝石的 <4px 接触拾取与拾取范围无关(gem.gd), 夹具等待期间怪死在玩家脚边掉宝石
# 必被接触吃掉, xp 攒够即弹三选一暂停 —— 不关掉, 后续所有截图都会被弹窗盖住
# (2026-09-10 实测 03c_molotov_t3/evo 与 04_boss 三张全废)。
func _dismiss_levelup() -> void:
	if GameManager.state != GameManager.State.LEVEL_UP:
		return
	get_tree().paused = false
	GameManager.state = GameManager.State.PLAYING
	hud.show_hud()


# 等 2 帧渲染稳定后截图(与 codex_shots 同款节奏)
func _shot(dir: String, name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	var path := dir + "/" + name + ".png"
	img.save_png(path)
	print("[UI-SHOT] saved %s" % path)