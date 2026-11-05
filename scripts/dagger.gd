extends "res://scripts/weapon_base.gd"
## Dagger — 飞刀, 朝最近敌人方向直线掷出, 穿透多个敌人
## 定位: 高频低伤的直线穿透武器, 与 wand(追踪单发) 形成手感差异
## Lv2 +1 把 · 穿透+1 · 扇形扩角 / Lv3 再 +1 把 · 金边高光; 进化「千刃暴雨」掷出密集扇形
## 特性「中毒」: 命中必挂, 叠 3 层 DoT(系数 0.18, 见 POISON_POWER 注释)
## 视觉: 待发飞刀悬停身侧并朝向目标, 掷出瞬间刀位爆闪(冷却进度可读)

# 悬停刀数上限: 实际显示 min(待发数, 4), 避免高等级时糊成一圈
const SHOW_MAX := 4
const HOVER_R := 14.0        # 悬停环半径
const FLASH_T := 0.12
# 中毒 DoT 系数(每跳 = 武器伤害 × 此值, 叠层后乘层数; 理由见 _do_attack 注释)
const POISON_POWER := 0.18

var _aim := 0.0              # 当前朝向(平滑追踪最近敌人)
var _flash := 0.0
var _t := 0.0


func _id() -> String:
	return "dagger"


func _ready() -> void:
	base_cooldown = 0.55   # 比 wand 更快, 单发伤害更低
	base_damage = 9.0
	set_process(true)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or player == null:
		return
	global_position = player.global_position
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	# 平滑转向最近敌人(无目标时保持当前朝向), 避免每帧硬切造成抖动
	var target := nearest_enemy()
	if target != null:
		var want := (target.global_position - global_position).angle()
		_aim = lerp_angle(_aim, want, clampf(delta * 10.0, 0.0, 1.0))
	queue_redraw()


# 本次掷出的刀数(与 _do_attack 同一套公式, 供悬停显示)
func _knife_count() -> int:
	var knives: int = 1 + (1 if level() >= 2 else 0) + (1 if level() >= 3 else 0) + player.extra_count()
	if is_evolved():
		knives += 3
	return knives


func _do_attack() -> void:
	var target := nearest_enemy()
	if target == null:
		timer = 0.2
		return

	var dir: Vector2 = (target.global_position - global_position).normalized()
	var knives: int = _knife_count()
	var pierce: int = 1 + (1 if level() >= 2 else 0)   # Lv2 质变: 提前获得穿透
	if is_evolved():
		pierce += 2

	_flash = FLASH_T
	GameManager.spawn_muzzle(global_position, dir)
	# Lv2 强档: 齐射扇形扩角(更宽的覆盖扫射, 群攻读感)
	var spread_mult := 1.0
	if level() >= 2:
		spread_mult = 1.6
	for i in range(knives):
		# 多把时小幅扇形展开(飞刀齐射), 单把直射
		var spread := 0.0
		if knives > 1:
			spread = (-0.06 * float(knives - 1) + float(i) * 0.12) * spread_mult
		var vel: Vector2 = dir.rotated(spread) * 300.0 * player.proj_speed_mult()
		# 剧毒涂层: 命中挂中毒 DoT(随武器伤害缩放, 层数上限由 status_fx 统一)
		# 特性从 bleed 换成 poison(见 GameManager.WEAPON_TRAITS["dagger"]):
		# 飞刀 0.55s 冷却 + 穿透会秒叠满层, 沿用 bleed 系数 0.30 会让 DoT(~35dps)反超本体(~16dps),
		# 收到 0.18(满层 ~6dps)—— 毒是补充伤害不是主伤害。
		var proc := trait_proc()
		proc["power"] = cur_damage() * POISON_POWER
		proc["chance"] = 1.0
		ObjectPool.spawn_bullet(global_position, vel, cur_damage(), "player", pierce, "blade", proc)
	GameManager.play_sfx("shoot")


# 飞刀配色: 常态银白冷光 / 进化态金刃(千刃暴雨)
func _tint(a: float) -> Color:
	return Color(1.0, 0.82, 0.35, a) if is_evolved() else Color(0.82, 0.90, 1.0, a)


func _draw() -> void:
	if player == null or not player.weapons.has("dagger"):
		return
	var f := _flash / FLASH_T
	var fl := f * f
	var n := mini(_knife_count(), SHOW_MAX)
	# 冷却进度: 越接近下次掷出, 刀身越亮越靠外(蓄力感)
	var cd := cur_cooldown()
	var q := 0.0 if cd <= 0.0 else clampf(1.0 - timer / cd, 0.0, 1.0)

	for i in range(n):
		# 悬停位: 以瞄准方向为中心均匀散开(±40°), 掷出时向后收(闪一下)
		var off := 0.0 if n == 1 else (-0.7 + 1.4 * float(i) / float(n - 1))
		var a := _aim + off
		var bob := sin(_t * 3.0 + float(i) * 1.1) * 1.2   # 上下浮动, 悬空感
		var dist := HOVER_R + 1.5 * q - 3.0 * fl
		var p := Vector2.from_angle(a) * dist + Vector2(0.0, bob - 6.0)

		# 刀身: 沿瞄准方向的像素菱形(前尖后钝), 蓄力时增亮
		#   平滑转向中形状只用吸附向 8 段, 避免顶点逐帧半像素抖动。
		var snap := snappedf(a, PI * 0.25)
		var fwd := Vector2.from_angle(snap)
		var side := fwd.orthogonal()
		var pc: Vector2 = p.round() + Vector2(0.5, 0.5)
		var blade := PackedVector2Array([
			pc + fwd * (4.5 + 1.0 * q),
			pc + side * 1.5,
			pc - fwd * 3.0,
			pc - side * 1.5,
		])
		px_fill_convex(blade, _tint(0.45 + 0.35 * q + 0.20 * fl))
		# 刃口高光: Lv2 起镀金边, Lv3 亮度上限再升(终极档更锐利)
		var tier := _fx_tier()
		var hl := Color(1.0, 0.85, 0.40) if tier >= 1 else Color(1.0, 1.0, 1.0)
		var hl_a := (0.42 if tier >= 2 else 0.30) + 0.45 * q
		px_line(pc - fwd * 2.5, pc + fwd * (4.0 + 1.0 * q), Color(hl.r, hl.g, hl.b, hl_a), 1.0)
		# Lv3 终极: 刀身外再包一圈细金描边(双层刃, 银白刀身 + 金轮廓)
		if tier >= 2:
			for s in range(blade.size()):
				var a2: Vector2 = blade[s]
				var b2: Vector2 = blade[(s + 1) % blade.size()]
				px_line(a2 + fwd * 1.5, b2 + fwd * 1.5, Color(1.0, 0.80, 0.35, 0.35 + 0.3 * q), 1.0)
		# 刀柄
		px_line(pc - fwd * 3.0, pc - fwd * 5.5, Color(0.45, 0.35, 0.26, 0.9), 1.0)
