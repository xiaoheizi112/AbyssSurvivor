extends CharacterBody2D
## Player — 移动/生命/受击无敌帧/属性重算/拾取/武器归属

signal died

# ---------- 基础属性(角色设定) ----------
var base_max_hp: float = 100.0
var base_move_speed: float = 180.0
var base_pick_range: float = 60.0
var char_damage_mult: float = 1.0       # 角色伤害倍率(圣骑士/刺客等)
var char_proj_speed_mult: float = 1.0
var heal_mult: float = 1.0              # 祭司回血加成

# 移动加速度(px/s²): 起步/停止/转向的惯性平滑, 越大越跟手
# 2400 => 0→180px/s 约 75ms 到位: 圆润但无拖沓感, 消除"瞬时 90° 转弯"的生硬
const ACCEL := 2400.0

# ---------- 运行时 ----------
var hp: float = 100.0
var invuln_timer: float = 2.0           # 出生保护 2s 无敌

# ---------- 属性强化等级(通用强化) ----------
var stat_levels := {
	"damage": 0, "attack_speed": 0, "cooldown": 0, "extra_count": 0, "area": 0,
	"proj_speed": 0, "move_speed": 0, "pick_range": 0, "max_hp": 0,
}

# ---------- 武器栏 ----------
var weapon_levels := {}   # weapon_id -> level
var weapons := {}         # weapon_id -> Node (武器实例)
var evolved_weapons := {} # weapon_id -> true (已进化的武器)

# 代价道具修正(乘法, 叠加): 键为派生属性名, 值 float(如 damage_mult: 0.30)
var item_mods := {}

# 无限成长超限层数(2026-09-09): 键与 GameManager.OVERLIMIT 同名, 值 = 已叠层数, 不封顶。
# **独立于 stat_levels**: 后者是常规升级池准入(`stat_levels[u] < max_level`)与进化前置的判据,
# 超限层数写进去会让满级被动重新进池、并伪造进化前置成立 => 门槛语义全坏。
var overlimit_levels := {}

# ---------- 节点引用 ----------
@onready var sprite: AnimatedSprite2D = $Sprite2D
@onready var weapon_parent: Node2D = $Weapons

var flash_timer: float = 0.0

# 圣骑士「圣盾」: 就绪时格挡一次伤害, 之后进入 12s 冷却
var _shield_ready: bool = true
var _shield_timer: float = 0.0

# ---------- 脚下指示圆环(主流游戏造型) ----------
# 软投影阴影 + 呼吸脉动的金色描边圆环 + 微弱内填; 椭圆压扁贴合地面视角, 仅战斗界面可见
var _ring_t: float = 0.0
const RING_RX := 15.0                        # 环水平半径(略大于角色本体, 让环清晰可见)
const RING_RY := 6.5                         # 环垂直半径(压扁 ~43% 模拟地面)
const RING_BREATH := 1.4                     # 呼吸脉动周期(秒)
const RING_TINT := Color(1.0, 0.78, 0.30)    # 金色描边, 呼应标题/圣环主色


func _ready() -> void:
	GameManager.player = self


# 每帧推进呼吸相位并在战斗界面重绘(暂停时冻结, 保留上一帧画面)
func _process(delta: float) -> void:
	var st := GameManager.state
	if st == GameManager.State.PLAYING or st == GameManager.State.LEVEL_UP:
		if not get_tree().paused:
			_ring_t += delta
			queue_redraw()


func _draw() -> void:
	var st := GameManager.state
	if st != GameManager.State.PLAYING and st != GameManager.State.LEVEL_UP:
		return
	var k := 0.5 + 0.5 * sin(_ring_t * TAU / RING_BREATH)   # 0→1 呼吸相位
	var c := Vector2(0.0, 15.0)                             # 脚底(精灵 32×32 centered, 脚底 +16)
	# 用 Y 缩放把圆形压成贴地椭圆; 绘制完须复位变换
	var yscale := RING_RY / RING_RX
	draw_set_transform(c, 0.0, Vector2(1.0, yscale))
	# 1) 软投影阴影: 近黑椭圆, 把角色"钉"在地上(景深)
	draw_circle(Vector2.ZERO, RING_RX + 1.5, Color(0.04, 0.04, 0.08, 0.30))
	# 2) 内填光晕: 两层同心弱光模拟柔和径向渐变(选中/目标指示感)
	draw_circle(Vector2.ZERO, RING_RX, Color(RING_TINT.r, RING_TINT.g, RING_TINT.b, 0.08 + 0.05 * k))
	draw_circle(Vector2.ZERO, RING_RX * 0.66, Color(RING_TINT.r, RING_TINT.g, RING_TINT.b, 0.07))
	# 3) 明锐描边: 金色环, 呼吸时微放大增亮
	draw_circle(Vector2.ZERO, RING_RX + k * 0.7, Color(RING_TINT.r, RING_TINT.g, RING_TINT.b, 0.55 + 0.30 * k), false, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 每局开始/角色切换时调用: 完整重置角色(属性/武器/强化等级), 避免退出重开携带上局养成
func init_character(char_id: String, weapon_id: String = "") -> void:
	setup_character(char_id)
	# 起始武器: 显式传入(角色选择界面自定义) > 角色默认推荐武器
	if weapon_id == "":
		weapon_id = GameManager.CHARACTERS[char_id]["weapon"]
	for k in stat_levels:
		stat_levels[k] = 0
	overlimit_levels.clear()
	for w in weapons.values():
		if is_instance_valid(w):
			weapon_parent.remove_child(w)
			w.queue_free()
	weapons.clear()
	weapon_levels.clear()
	evolved_weapons.clear()
	item_mods.clear()
	gain_weapon(weapon_id)
	hp = max_hp_value()
	invuln_timer = 2.0      # 出生保护
	flash_timer = 0.0
	_shield_ready = true    # 圣骑士圣盾每次开局就绪
	_shield_timer = 0.0
	recalc_stats()


func setup_character(char_id: String) -> void:
	var c: Dictionary = GameManager.CHARACTERS[char_id]
	# 按角色装配 32×32 动画帧集(AnimatedSprite2D), scale=1
	var frames: SpriteFrames = GameManager.frames_for("char_" + char_id, GameManager.CHAR_FRAMES[char_id])
	if sprite != null:
		sprite.sprite_frames = frames
		sprite.scale = Vector2.ONE
		sprite.play(&"idle")
	base_max_hp = float(c["max_hp"])
	base_move_speed = float(c["move_speed"])
	base_pick_range = float(c["pick_range"])
	char_damage_mult = float(c["damage_mult"])
	char_proj_speed_mult = float(c["proj_speed_mult"])
	heal_mult = float(c["heal_mult"])
	# 圣骑士被动: 生命上限 +10%
	if char_id == "paladin":
		base_max_hp *= 1.10


func max_hp_value() -> float:
	return (base_max_hp + stat_levels["max_hp"] * 35.0 + _overlimit("max_hp") \
			+ GameManager.meta_hp_bonus() + _item_mod("max_hp_flat")) \
		* (1.0 + _item_mod("max_hp_mult"))


func recalc_stats() -> void:
	# 生命上限(含"生命强化"每级 +35、局外永久"体魄"、道具修正、圣骑士被动)
	var max_hp: float = max_hp_value()
	hp = clampf(hp, 0.0, max_hp)
	# 若因 max_hp 提升而上限变大, MVP 不自动回满, 由"生命强化"本身回 30 处理


# ---------- 派生属性 ----------
# 代价道具的乘法修正累加后乘以基础值(负修正会衰减对应属性)
func _item_mod(key: String) -> float:
	return float(item_mods.get(key, 0.0))


# 超限成长加成 = 已叠层数 × 每层幅度(GameManager.OVERLIMIT[id]["value"]); 无层数返回 0。
# 与 _item_mod 同为加算项, 在各实时倍率函数里并进 (1.0 + ...) 通道
func _overlimit(id: String) -> float:
	var lv: int = int(overlimit_levels.get(id, 0))
	if lv == 0 or not GameManager.OVERLIMIT.has(id):
		return 0.0
	return float(lv) * float(GameManager.OVERLIMIT[id]["value"])


# 状态触发概率(冰冻/燃烧/中毒): 由已进化武器的附加效果提供(见 GameManager.EVOLUTION_TRAITS), 0~1
# 子弹命中敌人时掷骰(status_fx.try_proc_from_player); 同状态多来源只取最高, 不叠加
func proc_chance(kind: String) -> float:
	var total := 0.0
	for w in evolved_weapons:
		if not GameManager.EVOLUTION_TRAITS.has(w):
			continue
		if String(GameManager.EVOLUTION_TRAITS[w]["status"]) == kind:
			total = maxf(total, float(GameManager.EVOLUTION_TRAITS[w]["chance"]))
	return total


# 暴击率(0~1): 商店「致命一击」本局临时加成
func crit_chance() -> float:
	return clampf(_item_mod("crit_chance"), 0.0, 1.0)


# ---- 通用强化倍率(每类满级 3, 见 GameManager.UPGRADES) ----
# 每级幅度按"3 级总收益 ≈ 原 5 级总收益"重调: 原 5×0.15 → 3×0.26 一类
# 改幅度必须同步 UPGRADES 的 desc 文案, 两处不一致会在图鉴/升级卡上直接看出来
# 超限层数(overlimit_levels, 不封顶)以小幅度并进同一加算通道: 见 GameManager.OVERLIMIT

func move_speed() -> float:
	return base_move_speed * (1.0 + stat_levels["move_speed"] * 0.17 + _overlimit("move_speed")) \
		* GameManager.meta_speed_mult() * (1.0 + _item_mod("move_speed_mult"))

func pick_range() -> float:
	return base_pick_range * (1.0 + stat_levels["pick_range"] * 0.45 + _overlimit("pick_range")) \
		* GameManager.meta_pick_mult() * (1.0 + _item_mod("pick_range_mult"))

func damage_mult() -> float:
	return char_damage_mult * (1.0 + stat_levels["damage"] * 0.26 + _overlimit("damage")) \
		* GameManager.meta_damage_mult() * (1.0 + _item_mod("damage_mult"))

func attack_speed_mult() -> float:
	return (1.0 + stat_levels["attack_speed"] * 0.26 + _overlimit("attack_speed")) \
		* (1.0 + _item_mod("attack_speed_mult"))

func proj_speed_mult() -> float:
	return char_proj_speed_mult * (1.0 + stat_levels["proj_speed"] * 0.45)

# 冷却缩减: -13%/级(满级 3 = -39%, 原满级 5×8% = -40%), 换算成冷却计数速度倍率
# 道具可负修正(如 -0.20 表示冷却计数速度下降, 即变慢)
# 超限层(-3%/层)并进同一 clamp: 总缩减触底 0.2(=5× 攻速)后不再涨, 无限叠层也不会失控
func cooldown_mult() -> float:
	return 1.0 / clampf(1.0 - stat_levels["cooldown"] * 0.13 - _overlimit("cooldown"), 0.2, 1.0) \
		* (1.0 + _item_mod("cooldown_mult"))

# 数量强化: Lv1/Lv2 各 +1, Lv3 额外再 +1(共 +4), 由武器读取
# 例外于"3 级 ≈ 5 级总量"的线性折算: 数量是幸存者类最直观的爽点,
# 若只给 +3 则数量流满配从 12 刃掉到 9 刃, 手感退化明显, 故满级补一档
func extra_count() -> int:
	var lv: int = stat_levels["extra_count"]
	return lv + (1 if lv >= 3 else 0)


# 范围强化: 每级 +20%(圣环/旋刃半径), 满级 3 = +60%(原 5×12% = +60%)
func area_mult() -> float:
	return 1.0 + stat_levels["area"] * 0.20


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return

	# ---- 移动: 目标速度 + 加速度平滑(move_toward), 消起停/转向的瞬时突变 ----
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var target: Vector2 = dir * move_speed()
	velocity = velocity.move_toward(target, ACCEL * delta)
	move_and_slide()
	_update_visual(dir)

	# 边界 clamp(留半图块, 保证精灵整体在战场内)
	var m := GameManager.TILE / 2.0
	var b := GameManager.BOUND
	global_position.x = clampf(global_position.x, b.position.x + m, b.end.x - m)
	global_position.y = clampf(global_position.y, b.position.y + m, b.end.y - m)

	# ---- 无敌/闪光计时 ----
	if invuln_timer > 0.0:
		invuln_timer -= delta
	if flash_timer > 0.0:
		flash_timer -= delta
		sprite.modulate.a = 0.4 if int(flash_timer * 20.0) % 2 == 0 else 1.0
	else:
		sprite.modulate.a = 1.0
	# 圣骑士圣盾冷却递减(就绪后计时器停, 待格挡触发再启动)
	if not _shield_ready and _shield_timer > 0.0:
		_shield_timer -= delta
		if _shield_timer <= 0.0:
			_shield_ready = true


# 按移动/受击切换动画: 受击闪帧优先, 移动播 run(按水平方向翻转), 静止播 idle
func _update_visual(dir: Vector2) -> void:
	if sprite == null:
		return
	if flash_timer > 0.0:
		if sprite.animation != &"hit":
			sprite.play(&"hit")
		return
	# 水平翻转: 素材默认朝右, 向左走时镜像; 纯竖直移动(dir.x≈0)保留上一朝向
	if absf(dir.x) > 0.1:
		sprite.flip_h = dir.x < 0.0
	if dir.length_squared() > 0.01:
		if sprite.animation != &"run":
			sprite.play(&"run")
	else:
		if sprite.animation != &"idle":
			sprite.play(&"idle")


# ---------- 受击 ----------
func take_damage(amount: float, source: Node = null) -> void:
	if invuln_timer > 0.0:
		return
	# 圣骑士/只因信徒「圣盾」: 就绪时格挡一次伤害(无敌帧外单独判定)
	if _has_shield() and _shield_ready:
		_shield_ready = false
		_shield_timer = 12.0
		GameManager.play_sfx("select")
		GameManager.spawn_effect(global_position, Color(0.7, 0.85, 1.0), 12, 40.0)
		return
	var dmg := amount * GameManager.enemy_damage_mult()
	hp -= dmg
	GameManager.wave_took_damage = true   # 无伤过波成就: 本波受过伤
	invuln_timer = 0.75         # 无敌帧(延长: 前期被围殴时掉血速率更可控)
	flash_timer = 0.5
	GameManager.add_shake(3.0)
	GameManager.play_sfx("hurt")
	GameManager.spawn_effect(global_position, Color(1.0, 0.2, 0.2), 8, 30.0)
	if hp <= 0.0:
		hp = 0.0
		died.emit()


# 圣盾持有者: 圣骑士(格挡) 与 只因信徒(金拱独立)
func _has_shield() -> bool:
	var c: String = GameManager.current_character
	return c == "paladin" or c == "xiaoheizi"


func heal(amount: float) -> void:
	var max_hp: float = max_hp_value()
	hp = clampf(hp + amount * heal_mult, 0.0, max_hp)


# ---------- 升级接口 ----------

# 武器 id -> 脚本文件名(唯一映射表; gain_weapon 与存档恢复重建共用)
const WEAPON_SCRIPTS := {
	"wand": "wand", "orbit": "orbit_blade", "aura": "aura",
	"dagger": "dagger", "shuriken": "shuriken", "holy_water": "holy_water", "lightning": "lightning",
}


# 实例化武器节点并入树(gain_weapon / restore_weapons 共用)
func _make_weapon_node(id: String) -> Node2D:
	var inst := Node2D.new()
	inst.set_script(load("res://scripts/%s.gd" % WEAPON_SCRIPTS[id]))
	inst.name = id.capitalize()
	weapon_parent.add_child(inst)
	inst.init(self)
	return inst


# 存档恢复: 按存档的 weapon_levels/evolved_weapons 直接重建武器节点。
# 不走 gain_weapon —— 那条路首获会叠加局外「军械」加成, 恢复时再走一遍会重复加级。
func restore_weapons(levels: Dictionary, evolved: Dictionary) -> void:
	for w in weapons.values():
		if is_instance_valid(w):
			weapon_parent.remove_child(w)
			w.queue_free()
	weapons.clear()
	weapon_levels = levels.duplicate(true)
	evolved_weapons = evolved.duplicate(true)
	for id in weapon_levels:
		if int(weapon_levels[id]) > 0 and WEAPON_SCRIPTS.has(id):
			weapons[id] = _make_weapon_node(id)


func gain_weapon(id: String) -> void:
	# 首次获得武器时, 叠加局外永久"军械"等级(不会超过该武器满级)
	var is_new: bool = (not weapon_levels.has(id)) or weapon_levels[id] == 0
	if not weapon_levels.has(id):
		weapon_levels[id] = 0
	weapon_levels[id] += 1
	if is_new:
		var maxlv: int = int(GameManager.WEAPONS[id]["max_level"])
		var bonus: int = GameManager.meta_weapon_levels()
		weapon_levels[id] = mini(weapon_levels[id] + bonus, maxlv)

	if not weapons.has(id):
		weapons[id] = _make_weapon_node(id)

	GameManager.play_sfx("select")


func gain_stat(id: String) -> void:
	stat_levels[id] += 1
	recalc_stats()
	if id == "max_hp":
		heal(30.0)   # 生命强化: 上限+20 并回 30 血
	GameManager.play_sfx("select")


# 无限成长超限项: 叠一层(不封顶)。max_hp 走 flat 通道(上限+10 并回 10 血),
# 其余键经 _overlimit() 进实时倍率函数, 无需 recalc(全是每帧现算)
func gain_overlimit(id: String) -> void:
	if not GameManager.OVERLIMIT.has(id):
		return
	overlimit_levels[id] = int(overlimit_levels.get(id, 0)) + 1
	if id == "max_hp":
		recalc_stats()
		heal(10.0)
	GameManager.play_sfx("select")


func has_weapon(id: String) -> bool:
	return weapons.has(id)


func is_evolved(id: String) -> bool:
	return evolved_weapons.has(id)


# 进化武器: 标记并通知武器节点刷新(武器内部按 is_evolved 分支), 播放强化音效
func evolve_weapon(id: String) -> void:
	evolved_weapons[id] = true
	GameManager.unlock_achievement("evolve")
	GameManager.play_sfx("levelup")
	GameManager.spawn_effect(global_position, Color(0.9, 0.75, 0.2), 20, 60.0)