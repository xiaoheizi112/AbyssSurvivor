extends "res://scripts/weapon_base.gd"
## Lightning — 闪电, 瞬发落雷劈中最近敌人, 并向附近敌人连锁跳电
## 定位: 即时命中(无飞行时间) + 连锁, 克制密集小怪群
## Lv2 连锁+1 · 主弧加粗 / Lv3 连锁+1 · 伤害+25% · 冲击波; 进化「雷霆审判」连锁 +3
## 特性「冰冻」: 命中概率冻结(定身 1.2s + 受伤 +30%), 概率 10%/15%/20%(Lv1/Lv3/进化)
## 视觉: 主弧 + 随机分叉枝杈 + 三层辉光; 显示期内重抽路径 2 次做频闪(经典闪电抖动)

var _bolts: Array = []      # 主弧折线 [[p0, p1, ...], ...](世界坐标)
var _branches: Array = []   # 分叉枝杈 [[p0, p1, ...], ...](世界坐标, 比主弧细暗)
var _nodes: Array = []      # 命中点(世界坐标), 画冲击亮斑
var _show_t: float = 0.0
var _flicker: int = 0       # 剩余频闪次数

const SHOW_DUR := 0.18
const FLICKER_AT := [0.12, 0.06]   # 在这两个剩余时刻重抽路径

# 特性「冰冻」的触发概率三档(见 GameManager.WEAPON_TRAITS["lightning"])
# 从 stun 换成 freeze 是**质变增强**(定身 0.8s→1.2s, 且 freeze 自带受伤 +30%), 故概率整体下调:
#   原 stun 0.12 / 0.18 / 0.25  →  freeze 0.10 / 0.15 / 0.20
# 期望控场时长 Lv1 0.096s→0.12s、Lv3 0.144s→0.18s、进化 0.2s→0.24s: 小幅上扬但不失控,
# 换来"先冻住再爆发"这条 build 线真正成立(freeze 的 ×1.3 受伤是全游戏最大的单体增伤窗口)。
const TRAIT_CHANCE_BASE := 0.10
const TRAIT_CHANCE_LV3 := 0.15
const TRAIT_CHANCE_EVO := 0.20


func _id() -> String:
	return "lightning"


func _ready() -> void:
	base_cooldown = 1.1
	base_damage = 16.0
	set_process(true)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or _show_t <= 0.0:
		return
	_show_t -= delta
	if _show_t <= 0.0:
		_bolts.clear()
		_branches.clear()
		_nodes.clear()
		# 必须重绘一次: 闪电画在节点 local 空间(节点随角色平移), 否则最后一帧图形残留,
		# 表现为「电完后的影子跟着角色走」
		queue_redraw()
		return
	# 频闪: 显示期内重抽几次路径, 让闪电"跳"而不是僵住一条线
	if _flicker < FLICKER_AT.size() and _show_t <= FLICKER_AT[_flicker]:
		_flicker += 1
		_rejitter()
	queue_redraw()


func _do_attack() -> void:
	var first := nearest_enemy()
	if first == null:
		timer = 0.2
		return

	var chains: int = 1 + (1 if level() >= 2 else 0) + (1 if level() >= 3 else 0) + player.extra_count()
	if is_evolved():
		chains += 3
	var dmg := cur_damage()
	if level() >= 3:
		dmg *= 1.25
	# 冰冻概率: 常态命中小概率冰冻; Lv3 小幅提高, 进化「雷霆审判」再提高
	var freeze_chance := TRAIT_CHANCE_EVO if is_evolved() else \
		(TRAIT_CHANCE_LV3 if level() >= 3 else TRAIT_CHANCE_BASE)

	var jump_range: float = 70.0 * float(player.area_mult())
	_bolts.clear()
	_branches.clear()
	_nodes.clear()
	var hit_ids := {}
	var from: Vector2 = global_position
	var cur: Node2D = first

	for n in range(chains):
		if cur == null or not is_instance_valid(cur):
			break
		var to: Vector2 = cur.global_position
		# 落雷: 起点到目标画锯齿折线 + 分叉
		_bolts.append(_zigzag(from, to, 6, 7.0))
		_add_branches(from, to)
		_nodes.append(to)
		cur.take_damage(dmg)
		# 特性「冰冻」: apply_trait 内部掷骰(与原 randf 同一套 RNG 流), 状态名读表不写字面量
		apply_trait(cur, 0.0, freeze_chance)
		hit_ids[cur.get_instance_id()] = true
		# 命中火花: 像素星芒, 配色跟随落雷主题(常态冷蓝/进化紫金)
		GameManager.spawn_spark(to, _tint(1.0))
		# Lv3 终极: 落点冲击波(落雷砸地一圈扩散涟漪 + 更亮的火花)
		if level() >= 3:
			GameManager.spawn_ring(to, _tint(1.0), 22.0)
		# 找下一个未命中的最近敌人连锁
		var nxt: Node2D = null
		var nd: float = jump_range * jump_range
		for e in GameManager.enemies.duplicate():
			if not is_instance_valid(e) or e.is_queued_for_deletion():
				continue
			if hit_ids.has(e.get_instance_id()):
				continue
			var d: float = to.distance_squared_to(e.global_position)
			if d < nd:
				nd = d
				nxt = e
		from = to
		cur = nxt

	_show_t = SHOW_DUR
	_flicker = 0
	queue_redraw()
	GameManager.play_sfx("hit")


# 频闪重抽: 保留端点, 只重算抖动(端点可能已随敌人移动, 用当前 _bolts 的首尾)
func _rejitter() -> void:
	for i in range(_bolts.size()):
		var pts: Array = _bolts[i]
		if pts.size() < 2:
			continue
		_bolts[i] = _zigzag(pts[0], pts[pts.size() - 1], 6, 7.0)


# 生成 a→b 的锯齿闪电路径: segs 段, 垂直抖动幅度 jitter
func _zigzag(a: Vector2, b: Vector2, segs: int, jitter: float) -> Array:
	var pts: Array = [a]
	var d := b - a
	var perp := d.orthogonal().normalized()
	for i in range(1, segs):
		var t := float(i) / float(segs)
		# 中段抖得最厉害, 靠端点收敛(闪电不会从目标身上偏移出去)
		var w := sin(t * PI)
		pts.append(a + d * t + perp * GameManager._rng.randf_range(-jitter, jitter) * w)
	pts.append(b)
	return pts


# 分叉枝杈: 主弧上随机取 1~2 点, 岔出短折线(进化态更多), 让闪电有"树状"读感
func _add_branches(a: Vector2, b: Vector2) -> void:
	var n := 2 if is_evolved() else (1 + (1 if _fx_tier() >= 1 else 0))
	if GameManager._rng.randf() < 0.35:
		n += 1
	var d := b - a
	for i in range(n):
		var t := GameManager._rng.randf_range(0.25, 0.75)
		var origin: Vector2 = a + d * t
		# 岔出方向: 主方向偏 ±35~75°, 长度为主弧的 25~45%
		var ang := deg_to_rad(GameManager._rng.randf_range(35.0, 75.0)) * (1.0 if GameManager._rng.randf() < 0.5 else -1.0)
		var end: Vector2 = origin + d.normalized().rotated(ang) * d.length() * GameManager._rng.randf_range(0.25, 0.45)
		_branches.append(_zigzag(origin, end, 3, 4.0))


# 雷霆配色: 常态冷蓝白 / 进化态紫金(雷霆审判)
func _tint(a: float) -> Color:
	return Color(0.80, 0.55, 1.0, a) if is_evolved() else Color(0.45, 0.70, 1.0, a)


# 主弧宽度倍率: Lv2 起加粗 +25%, Lv3 再加 +25%(终极更粗更亮, 层级分明)
func _width_mult() -> float:
	return 1.0 + 0.25 * float(_fx_tier())


func _draw() -> void:
	if _bolts.is_empty() or _show_t <= 0.0:
		return
	var a := clampf(_show_t / SHOW_DUR, 0.0, 1.0)
	# 频闪时亮度轻微跳动(配合路径重抽, 强化"电"的不稳定感)
	var flick := 0.85 + 0.15 * sin(_show_t * 90.0)
	var w := _width_mult()

	# 1) 分叉枝杈: 先画(垫在主弧下), 细且暗
	for br in _branches:
		_stroke(br, _tint(0.30 * a * flick), 2.0 * w)
		_stroke(br, Color(0.90, 0.95, 1.0, 0.55 * a * flick), 1.0 * w)

	# 2) 主弧三层辉光: 宽淡外晕 → 中层 → 白热芯(宽度递减, 近似 bloom)
	for bolt in _bolts:
		_stroke(bolt, _tint(0.22 * a * flick), 6.0 * w)
		_stroke(bolt, _tint(0.55 * a * flick), 3.0 * w)
		_stroke(bolt, Color(0.95, 0.98, 1.0, 0.95 * a * flick), 1.5 * w)

	# 3) 命中点冲击亮斑: 两层同心(外晕 + 白芯), 随淡出收缩(像素圆盘, 无抗锯齿)
	for p in _nodes:
		var lp: Vector2 = (p - global_position).round()
		px_disc(lp, roundf(5.0 * a), _tint(0.30 * a))
		px_disc(lp, roundf(2.2 * a), Color(1.0, 1.0, 1.0, 0.75 * a))


# 折线描边(世界坐标点集 → 局部坐标)
func _stroke(pts: Array, col: Color, width: float) -> void:
	for i in range(pts.size() - 1):
		draw_line(pts[i] - global_position, pts[i + 1] - global_position, col, width)
