extends "res://scripts/weapon_base.gd"
## Boomerang — 回旋镖, 朝最近敌人掷出, 飞够距离掉头回手上; 去程回程各结算一遍
## 定位: 近中程「来回双段」武器, 与 wand(追踪单发)/dagger(直线穿透不回) 形成手感差异
##   —— 飞刀穿出去就没了, 回旋镖会把伤害**送回来**, 贴脸站桩时同一批敌人吃两轮
## Lv2 穿透+1 · 命中减速 / Lv3 再 +2 把 · 射程拉长 · 减速强化 · 火焰尾迹; 进化「风魔回旋镖」+2 把 · 穿透+2 · 必减速
## 视觉: 待发回旋镖悬停身侧自旋, 掷出瞬间爆闪(冷却进度可读)
##
## 升级重做(2026-09-10): 控场轴前移、数量轴后移 ——
##   原 Lv2 双镖 + 穿透, Lv3 才解锁减速; 现 Lv2 = 穿透 2 + 命中减速(控场是回旋镖的身份, 该早给),
##   镖数(数量轴)统一后移到 Lv3 一次性 +2(1→3 把)。减速强度本身也分档: Lv2 -30%, Lv3 -45%。

# 悬停镖数上限: 实际显示 min(待发数, 4), 避免高等级糊成一圈
const SHOW_MAX := 4
const HOVER_R := 14.0        # 悬停环半径
const FLASH_T := 0.12

# 去程射程(px): 飞这么远掉头回来。约 3 个身位, 覆盖近中程; 太短变贴身, 太长等不到回程
const BOOM_RANGE := 130.0

# 减速强度两档(slow 的 factor = 速度倍率, 越小越狠): Lv2 = 0.70(减速 30%), Lv3 = 0.55(减速 45%)。
# 经 proc["factor"] 透传到 StatusFx.apply —— 0 表示用表默认, 这里显式传值让两档分开。
const SLOW_FACTOR_LV2 := 0.70
const SLOW_FACTOR_LV3 := 0.55

var _aim := 0.0              # 当前朝向(平滑追踪最近敌人)
var _flash := 0.0
var _t := 0.0


func _id() -> String:
	return "shuriken"


func _ready() -> void:
	base_cooldown = 0.75   # 比飞刀略慢(单发低), 靠来回双段打平
	base_damage = 8.0
	set_process(true)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or player == null:
		return
	global_position = player.global_position
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	# 平滑转向最近敌人(无目标时保持当前朝向), 避免每帧硬切抖动
	var target := nearest_enemy()
	if target != null:
		var want := (target.global_position - global_position).angle()
		_aim = lerp_angle(_aim, want, clampf(delta * 10.0, 0.0, 1.0))
	queue_redraw()


# 本次掷出的镖数(与 _do_attack 同一套公式, 供悬停显示)
# 数量轴后移到 Lv3: Lv1/Lv2 = 1 把, Lv3 一次性 +2 = 3 把(进化态再 +2)。
# 原 1/+1/+1 三档让 Lv2 与 wand 双发同质, 现 Lv2 的换轴交给减速(见 _do_attack)。
func _star_count() -> int:
	var n: int = 1 + (2 if level() >= 3 else 0) + player.extra_count()
	if is_evolved():
		n += 2
	return n


func _do_attack() -> void:
	var target := nearest_enemy()
	if target == null:
		timer = 0.2
		return

	var dir: Vector2 = (target.global_position - global_position).normalized()
	var n: int = _star_count()
	var pierce: int = 1 + (1 if level() >= 2 else 0)   # Lv2 质变: 提前获得穿透
	if is_evolved():
		pierce += 2

	_flash = FLASH_T
	GameManager.spawn_muzzle(global_position, dir)
	# 控场轴前移: Lv2 起命中即可能减速(回程那一轮尤其有用 —— 减速后玩家更容易追上去)
	var slow_proc := level() >= 2
	# 减速强度随等级加深(Lv2 -30% / Lv3 -45%); 进化态必带且取 Lv3 强度
	var slow_factor := SLOW_FACTOR_LV3 if (is_evolved() or level() >= 3) else SLOW_FACTOR_LV2
	# 射程随等级拉长: Lv1/Lv2 130 / Lv3 156(去程更远, 回程扫过的面积更大)
	var boom_r := BOOM_RANGE + (26.0 if level() >= 3 else 0.0)
	for i in range(n):
		# 多把时扇形展开(齐射), 单把直射
		var spread := 0.0
		if n > 1:
			spread = -0.08 * float(n - 1) + float(i) * 0.16
		var vel: Vector2 = dir.rotated(spread) * 340.0 * player.proj_speed_mult()
		# 回旋镖标记: bullet 读到后启用返程模式(见 bullet._steer_boomerang)
		var proc := {"boomerang": true, "boom_range": boom_r}
		# 特性「减速」(读 GameManager.WEAPON_TRAITS["shuriken"]):
		# Lv2 命中 25% 减速(-30%), Lv3 减速加深(-45%), 进化「风魔回旋镖」必带
		if is_evolved() or slow_proc:
			var tk := trait_status()
			if tk != "":
				proc["kind"] = tk
				proc["chance"] = 1.0 if is_evolved() else 0.25
				proc["factor"] = slow_factor   # 经 StatusFx.apply 按来源分级强度
		if level() >= 3:
			proc["fire_trail"] = true   # 终极: 飞行拖火焰尾迹(见 bullet._draw_boomerang)
		ObjectPool.spawn_bullet(global_position, vel, cur_damage(), "player", pierce, "boomerang", proc)
	GameManager.play_sfx("shoot")


# 回旋镖配色: 常态木质冷白 / 进化态青蓝风刃
func _tint(a: float) -> Color:
	return Color(0.55, 0.90, 1.0, a) if is_evolved() else Color(0.80, 0.86, 0.95, a)


func _draw() -> void:
	if player == null or not player.weapons.has("shuriken"):
		return
	var f := _flash / FLASH_T
	var fl := f * f
	var n := mini(_star_count(), SHOW_MAX)
	# 冷却进度: 越接近下次掷出, 镖越亮越靠外(蓄力感)
	var cd := cur_cooldown()
	var q := 0.0 if cd <= 0.0 else clampf(1.0 - timer / cd, 0.0, 1.0)

	for i in range(n):
		# 悬停位: 以瞄准方向为中心均匀散开(±40°), 掷出时向后收(闪一下)
		var off := 0.0 if n == 1 else (-0.7 + 1.4 * float(i) / float(n - 1))
		var a := _aim + off
		var bob := sin(_t * 3.0 + float(i) * 1.3) * 1.2   # 上下浮动, 悬空感
		var dist := HOVER_R + 1.5 * q - 3.0 * fl
		var p := Vector2.from_angle(a) * dist + Vector2(0.0, bob - 6.0)
		_draw_boom(p, _t * 4.0 + float(i), _tint(0.45 + 0.35 * q + 0.20 * fl))


# 悬停回旋镖: V 形两臂(弯折点朝上), 每把各自相位自旋
#   与飞行弹(bullet._draw_boomerang)同一造型语言, 只是缩小一号贴在身侧。
#   自旋吸附到 45° 步进(8 向), 斜边不会半像素抖动。
#   不用 px_fill_convex: V 形是凹多边形, 凸填充会画成菱形。
func _draw_boom(p: Vector2, spin: float, col: Color) -> void:
	var sp := snappedf(spin, PI * 0.25)
	var pc: Vector2 = p.round() + Vector2(0.5, 0.5)
	var fx := Vector2.from_angle(sp)
	var fy := fx.orthogonal()
	var bend := pc + fx * 1.5
	var a1 := pc - fx * 2.0 + fy * 3.0
	var a2 := pc - fx * 2.0 - fy * 3.0
	px_line(bend, a1, col, 2.0)
	px_line(bend, a2, col, 2.0)
	# 弯折点握把 + 两臂尖白色标记(和飞行态一致)
	px_rect((bend - Vector2(0.5, 0.5)).round(), Vector2.ONE, Color(0.95, 0.90, 0.80, 0.90))
	px_rect((a1 - Vector2(0.5, 0.5)).round(), Vector2.ONE, Color(1.0, 1.0, 1.0, 0.80))
	px_rect((a2 - Vector2(0.5, 0.5)).round(), Vector2.ONE, Color(1.0, 1.0, 1.0, 0.50))