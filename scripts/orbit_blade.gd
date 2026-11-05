extends "res://scripts/weapon_base.gd"
## OrbitBlade — 环绕飞刃, 绕玩家旋转; 刃数 1/4/7 三档跳变, 触碰伤害(独立命中冷却 0.4s)

var radius: float = 35.0
var angular_speed: float = 2.5
var angle: float = 0.0
var _hit_cooldown := {}    # enemy_instance_id -> 剩余冷却
var _hit_flash := 0.0      # 命中爆闪计时: 刀刃命中瞬间增亮, 0.18s 衰减

const HIT_FLASH := 0.18
# 特性「流血」(见 GameManager.WEAPON_TRAITS["orbit"]): 每跳 DoT = 触碰伤害 × 此值, 叠至 3 层
# 0.15 的依据: orbit 对单敌命中冷却 0.4s, ~1.2s 即叠满; 满层 DoT ≈ 本体 dps 的 22%,
# 是补充不是主伤(旋刃的身份仍是贴身物理输出, 流血负责"擦破皮还在淌"的追击收益)
const BLEED_POWER := 0.15


func _id() -> String:
	return "orbit"

func _ready() -> void:
	base_damage = 12.0
	set_process(true)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if player == null:
		return
	# 每把刃随玩家移动
	global_position = player.global_position
	angle += angular_speed * delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
	queue_redraw()

	# 命中冷却递减
	for k in _hit_cooldown.keys():
		_hit_cooldown[k] -= delta
		if _hit_cooldown[k] <= 0.0:
			_hit_cooldown.erase(k)


# 每帧在 _draw 里画刃, 碰撞在 _physics_process 里结算
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if GameManager.state != GameManager.State.PLAYING or player == null:
		return
	_check_hits()


# 刃数: Lv1=1 / Lv2=4 / Lv3=7, 每级 +3 把(3 级制下每级都是质变)
# 三档数字精确沿用原 5 级制的 Lv1/Lv3/Lv5 实际刃数(1 / 3+1 / 5+1+1), 满配手感不缩水
# 再叠数量强化 extra_count()
func _blade_count() -> int:
	var n := 1 + int(player.extra_count())
	if level() >= 2:
		n += 3
	if level() >= 3:
		n += 3
	return n

func _eff_radius() -> float:
	return radius * float(player.area_mult())


func _check_hits() -> void:
	var n := _blade_count()
	var r := _eff_radius()
	var blader := 6.0  # 刃的碰撞半径
	for e in GameManager.enemies.duplicate():
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var eid: int = e.get_instance_id()
		if _hit_cooldown.has(eid):
			continue
		var hit := false
		for i in range(n):
			var a := angle + TAU * float(i) / float(n)
			var blade_pos := player.global_position + Vector2.from_angle(a) * r
			if e.global_position.distance_to(blade_pos) < blader + e.collision_radius():
				e.take_damage(cur_damage())
				hit = true
		# 进化「刃环风暴」: 内圈刀刃反向旋转, 半径减半, 二次结算
		if is_evolved():
			for i in range(n):
				var a := -angle + TAU * float(i) / float(n)
				var blade_pos := player.global_position + Vector2.from_angle(a) * r * 0.55
				if e.global_position.distance_to(blade_pos) < blader + e.collision_radius():
					e.take_damage(cur_damage())
					hit = true
		if hit:
			# 特性「流血」: 本次命中结算(外圈+进化内圈共用)挂一次, 不随刃数放大;
			# 0.4s 命中冷却天然限流叠层速度。状态名读表, apply_trait 内部走 StatusFx.apply
			apply_trait(e, cur_damage() * BLEED_POWER)
			# 强击退: 旋刃沿圆心外推近身敌人(比默认击退更强, 贴身保命)
			# Boss 无 add_knockback(设计上免击退), 需 has_method 守卫
			if e.has_method("add_knockback"):
				var kb_dir: Vector2 = e.global_position - player.global_position
				e.add_knockback(kb_dir, 240.0)
			_hit_cooldown[eid] = 0.4
			_hit_flash = HIT_FLASH
			# Lv3 终极: 命中溅出碎星火花(刃口爆出金属碎光)
			if _fx_tier() >= 2:
				var ep: Vector2 = e.global_position
				var blade_near: Vector2 = player.global_position + (ep - player.global_position).normalized() * _eff_radius()
				GameManager.spawn_spark(blade_near, Color(1.0, 0.82, 0.30))
			GameManager.play_sfx("hit")


# 刀刃配色: 常态冰蓝 / 进化内圈金橙; a 为透明度系数
func _tint(a: float, evolved: bool = false) -> Color:
	return Color(1.0, 0.78, 0.28, a) if evolved else Color(0.42, 0.86, 1.0, a)


func _draw() -> void:
	if player == null or not player.weapons.has("orbit"):
		return
	var n := _blade_count()
	var r := _eff_radius()
	# 命中爆闪: 刚命中时整体增亮放大, 0.18s 内衰减; Lv2+ 爆闪更亮更强(质变档)
	var tier := _fx_tier()
	var f := _hit_flash / HIT_FLASH
	var fl := f * f * (1.0 + 0.45 * float(tier))

	# 轨道引导环: 极淡一圈标出覆盖范围(与圣环同语言, 但更弱不抢戏)
	px_ring(Vector2.ZERO, roundf(r), 1.0, _tint(0.07 + 0.05 * fl))

	for i in range(n):
		_draw_blade(angle + TAU * float(i) / float(n), r, 1.0, false, fl)

	# 进化「刃环风暴」: 内圈反向刀刃, 金色 + 自己的引导环
	if is_evolved():
		var ri := r * 0.55
		px_ring(Vector2.ZERO, roundf(ri), 1.0, _tint(0.07 + 0.05 * fl, true))
		for i in range(n):
			_draw_blade(-angle + TAU * float(i) / float(n), ri, -1.0, true, fl)


# 单把刃: 弧形拖尾(顺滑, 替代离散圆点) + 有朝向的刀形多边形 + 白热刃芯
# dir_sign: +1 逆时针(拖尾在角度减小侧) / -1 顺时针(反向旋转, 拖尾镜像)
func _draw_blade(a: float, r: float, dir_sign: float, evolved: bool, fl: float) -> void:
	var p := Vector2.from_angle(a) * r
	# 切向 = 运动方向(逆时针时 a+90°); 顺时针取反
	var tangent := Vector2.from_angle(a + PI * 0.5 * dir_sign)
	var normal := Vector2.from_angle(a)
	var tier := _fx_tier()

	# 1) 弧形拖尾: 沿运动反方向的像素点列(逐点 stamp, 宽窄两层), 长度随爆闪拉长
	#    Lv2+ 拖尾弧长 ×1.5(更快更带感); Lv3 再叠一条更外圈的淡光点列(双层结构)
	var sweep := (0.55 + 0.25 * fl) * dir_sign
	if tier >= 1:
		sweep *= 1.5
	var a0 := a - sweep
	_px_arc_trail(r, a0, a, _tint(0.10 + 0.10 * fl, evolved), 2)
	_px_arc_trail(r, a0, a, _tint(0.20 + 0.25 * fl, evolved), 1)
	if tier >= 2:
		_px_arc_trail(r + 2.5, a0, a, _tint(0.07 + 0.09 * fl, evolved), 1)

	# 2) 刀形多边形: 沿切向拉长的四角刀身(前尖后钝)。draw_colored_polygon 本身硬边,
	#    但顶点平滑旋转会产生半像素漂移; 轴向吸附到 45° 步进 + 顶点取整后填充,
	#    形状 8 向切换(像素"刀"不糊不抖)。
	var snap := snappedf(rad_to_deg(a), 45.0)
	var sn := Vector2.from_angle(deg_to_rad(snap))                    # 吸附后的径向
	var st := Vector2.from_angle(deg_to_rad(snap) + PI * 0.5)         # 吸附后的切向
	var pc: Vector2 = p.round()
	var bc := _tint(1.0, evolved)
	bc.a = 0.55 + 0.35 * fl
	px_fill_convex(PackedVector2Array([
		pc + st * (5.5 + 1.5 * fl), pc + sn * 2.6,
		pc - st * 4.0, pc - sn * 2.6,
	]), bc)

	# 3) 刃芯白热点: 命中时放大增亮(像素方块)
	var core_sz := 2.0 if fl > 0.5 else 1.0
	px_rect(p + tangent * 1.0 - Vector2(core_sz, core_sz) * 0.5, Vector2(core_sz, core_sz),
		Color(1.0, 1.0, 1.0, 0.85 + 0.15 * fl))


# 弧形拖尾的像素化: 原 draw_arc(抗锯齿) 改为沿弧取整数点列, 用方形印章盖出
# a0 → a 求得弧角区间, 取样点 ~4px 一个(上限 20), 位置 round 到整数像素
func _px_arc_trail(r: float, a0: float, a1: float, col: Color, wpx: int) -> void:
	var ra := absf(a1 - a0)
	if ra <= 0.0:
		return
	var pts := mini(int(ceilf(ra * r / 4.0)), 20) + 1
	for i in range(pts):
		var aa := lerpf(a0, a1, float(i) / float(pts - 1))
		var lp: Vector2 = (Vector2.from_angle(aa) * r).round()
		px_rect(lp - Vector2(wpx, wpx) * 0.5, Vector2(wpx, wpx), col)