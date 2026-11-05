extends Node2D
## Bullet — 直线飞行物; team = "player" 或 "enemy", 决定伤害目标
## 由对象池 acquire/release 复用
## visual: "orb" 光球(默认, 走 GameManager bullet 纹理) / "blade" 飞刀(程序化刀形, 朝向飞行方向)
##         / "boomerang" 回旋镖(程序化 V 形, 飞够距离掉头回玩家手上, 来回各结算一遍)

const _Pixels := preload("res://scripts/pixel_utils.gd")

var team: String = "player"
var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var pierce: int = 0
var life: float = 3.0
var visual: String = "orb"
var _proc: Dictionary = {}   # 命中的额外状态附加 { "kind": 状态名, "power": 每跳伤害, "chance": 触发概率 0~1 }

var _r := 4.0
var _hit_ids := {}
var sprite: Sprite2D = null

# ---- 回旋镖返程模式(proc["boomerang"]=true 时启用) ----
# 去程飞够 _max_dist 掉头, 返程直线飞回玩家, 到手里(<=10px)才回收。
# 掉头时清空 _hit_ids 并恢复穿透 => 同一批敌人去程回程各挨一次, 这是回旋镖的核心回报。
# 穿透耗尽**不销毁**, 只标记 _spent 停手, 飞完弧线掉头再恢复 —— 否则 Lv1(穿透 1)打两只就消失,
# 「会回来」这个身份当场崩掉。
var _boomerang := false
var _returning := false
var _spent := false
var _origin := Vector2.ZERO
var _max_dist := 130.0
var _spd := 340.0
var _pierce0 := 0

# ---- 短程剑气(proc["life_dist"] > 0 时启用) ----
# 飞出这么远就回收, 而不是等 life(3s) 走完或出界。
# 用途: 旋刃 Lv3 命中后沿切向甩出一道穿透剑气, 伤害外溢到轨道之外的怪(见 orbit_blade.gd)。
# 与回旋镖互斥(回旋镖的 _max_dist 是"掉头点", 这个是"消亡点"), 池复用时必须一起重置。
var _life_dist := 0.0


func setup(pos: Vector2, vel: Vector2, dmg: float, t: String, pierce_count: int = 0, vis: String = "orb", proc: Dictionary = {}) -> void:
	global_position = pos
	velocity = vel
	damage = dmg
	team = t
	pierce = pierce_count
	visual = vis
	_proc = proc
	life = 3.0
	_hit_ids.clear()
	# 池复用: 回旋镖四个状态位必须每次重置, 否则上一条弹的返程标记会带到新弹上
	_boomerang = bool(proc.get("boomerang", false))
	_returning = false
	_spent = false
	_origin = pos
	_max_dist = float(proc.get("boom_range", 130.0))
	_life_dist = float(proc.get("life_dist", 0.0))
	_spd = vel.length()
	_pierce0 = pierce_count
	# 刀形/回旋镖弹: 节点旋转到飞行方向, 局部 +X 即前进方向(_draw 按局部坐标画)
	# 光球弹保持不旋转 —— 像素贴图任意角度旋转会歪斜抖动, 彗尾直接用世界速度方向
	var oriented := visual == "blade" or visual == "boomerang"
	rotation = (vel.angle() if vel != Vector2.ZERO else 0.0) if oriented else 0.0
	_ensure_visual()
	set_physics_process(true)
	visible = true
	# 彗尾/刀形只取决于速度方向与团队色(飞行中恒定), 池复用后画一次即可, 无需每帧重绘
	queue_redraw()


func _ensure_visual() -> void:
	if sprite == null:
		sprite = GameManager.sprite_with_circle(4, Color(0.5, 0.9, 1.0), "bullet")
		sprite.name = "Sprite2D"
		sprite.scale = Vector2.ONE
		add_child(sprite)
	# 飞刀/回旋镖走 _draw 程序化形状, 隐藏光球贴图; 光球弹敌弹染品红
	if visual == "blade" or visual == "boomerang":
		sprite.visible = false
	else:
		sprite.visible = true
		sprite.modulate = Color(1.0, 1.0, 1.0) if team == "player" else Color(1.0, 0.45, 0.6)


func _physics_process(delta: float) -> void:
	# 回旋镖掉头: 先判返程再积分位移, 保证转向当帧就朝玩家飞
	# 到手时 _steer_boomerang 内部已 recycle, 必须立刻 return —— release 只关开关不摘节点,
	# 继续往下走会让一个已回收(不可见)的弹再结算一次命中
	if _boomerang and not _steer_boomerang():
		return

	global_position += velocity * delta
	life -= delta
	# 回旋镖: 飞行中自旋(弯月扫过半像素位置, _draw 吸附到 45° 保持锐利)
	# 转速比旧手里剑慢一档(22→13): V 形两臂比四角星占面积大, 转太快糊成圆盘读不出形状
	if visual == "boomerang":
		rotation += delta * 13.0
		queue_redraw()

	# 超出地图范围 → 回收(战场外扩 50)
	# 回旋镖豁免: 贴边投掷时弧线必然出界, 按 BOUND 回收会让它飞出去就凭空消失、永不返回;
	# 它的寿命由 life(3s) 与「飞回玩家手上」两条共同兜住, 不会滞留
	var b := GameManager.BOUND.grow(50.0)
	if life <= 0.0 or (not _boomerang and not b.has_point(global_position)):
		recycle()
		return
	# 短程剑气: 飞出射程就消亡(旋刃 Lv3 的切向甩刃, 只负责把伤害外溢一段距离)
	if _life_dist > 0.0 and global_position.distance_to(_origin) >= _life_dist:
		recycle()
		return

	# 注意分支写法: else 是**敌方弹**(打玩家)。穿透用尽的回旋镖若并进 if 条件
	# (and not _spent) 会掉进 else => 飞回途中咬玩家一口再自毁, 「会回来」当场崩掉。
	# 所以 _spent 必须在 player 分支内部早退: 只飞不结算, 掉头时 _steer_boomerang 恢复。
	if team == "player":
		if _spent:
			return
		for e in GameManager.enemies.duplicate():
			if not is_instance_valid(e) or e.is_queued_for_deletion():
				continue
			if _hit_ids.has(e.get_instance_id()):
				continue
			if e.has_method("collision_radius") and \
				global_position.distance_to(e.global_position) < _r + e.collision_radius():
				_hit_ids[e.get_instance_id()] = true
				# 处决(proc["execute"] = 倍率): 对残血敌人直接放大这一击(飞刀 Lv3)。
				# 阈值读 proc 的 execute_below(默认 0.30), 倍率读 execute(默认不放大)。
				# 与面具客「处决」被动同语言(enemy.take_damage 里已有一条 25%/×1.4 的角色版),
				# 但那条 gate 在 current_character, 这条 gate 在武器等级 => 两者可叠乘, 语义都是"收尾更快"。
				var dmg := damage
				var exe_m: float = float(_proc.get("execute", 0.0))
				if exe_m > 1.0 and e.get("_max_hp") != null:
					var mh: float = float(e.get("_max_hp"))
					if mh > 0.0 and float(e.get("hp")) < mh * float(_proc.get("execute_below", 0.30)):
						dmg *= exe_m
						# 处决命中反馈: 金色碎光(与常规命中的主题色火花分开, 让玩家看见"这刀是处决")
						GameManager.spawn_spark(global_position, Color(1.0, 0.82, 0.25))
				e.take_damage(dmg)
				# 命中附加状态(飞刀撕裂/能量弹冰冻等): 命中即掷骰(仅当 proc 含 kind)
				if _proc.has("kind") and e.has_method("take_damage"):
					var chance: float = float(_proc.get("chance", 1.0))
					if GameManager._rng.randf() < chance:
						# factor / max_stacks 是"按来源分级"通道(回旋镖 Lv3 减速更狠 / 飞刀 Lv2 毒叠 5 层);
						# 缺省 0 时 StatusFx.apply 内部回退到表默认值, 老调用点逐字节等价
						StatusFx.apply(e._status, String(_proc["kind"]), float(_proc.get("power", 0.0)), 1.0,
							float(_proc.get("factor", 0.0)), int(_proc.get("max_stacks", 0)))
				# 命中火花色: 武器可通过 proc["fx_color"] 指定主题色(法杖青/进化紫), 默认金黄
				var hit_col := Color(_proc.get("fx_color", Color(1.0, 0.85, 0.3)))
				GameManager.spawn_spark(global_position, hit_col)
				# 穿透弹标记: 每层命中扩散一圈碎光(能量弹 Lv3 穿透弹视觉), 染色跟随主题
				if _proc.get("hit_ring", false):
					GameManager.spawn_ring(global_position, hit_col, 16.0)
				if pierce > 0:
					pierce -= 1
				elif _boomerang:
					_spent = true   # 穿透用尽但继续飞完弧线, 掉头时 _steer_boomerang 恢复
				else:
					recycle()
					return
	else:
		var p = GameManager.player
		if p != null and global_position.distance_to(p.global_position) < _r + GameManager.PLAYER_RADIUS:
			p.take_damage(damage)
			recycle()


# 回旋镖飞行控制: 去程飞够 _max_dist 掉头 → 返程直线飞回玩家 → 到手回收
# 返回 false 表示本帧已 recycle, 调用方必须立刻 return
func _steer_boomerang() -> bool:
	var p = GameManager.player
	if p == null:
		recycle()
		return false

	if not _returning:
		# 去程: 离手距离达标即掉头
		if global_position.distance_to(_origin) >= _max_dist:
			_returning = true
			_hit_ids.clear()        # 返程重新结算, 同一批敌人再挨一遍
			_spent = false
			pierce = _pierce0
			velocity = (p.global_position - global_position).normalized() * _spd
	else:
		# 返程: 朝玩家当前位置持续修正(玩家会移动), 速率恒定
		var to_p: Vector2 = p.global_position - global_position
		if to_p.length() <= 10.0:
			recycle()               # 回到手上, 本次投掷结束
			return false
		velocity = to_p.normalized() * _spd
	return true


func recycle() -> void:
	GameManager.projectiles.erase(self)
	ObjectPool.release(self)


# 节点已旋转到飞行方向(局部 +X = 前进): 刀形/回旋镖按朝向绘制, 彗尾沿局部 -X 拖
func _draw() -> void:
	if visual == "blade":
		_draw_blade()
		return
	if visual == "boomerang":
		_draw_boomerang()
		return
	_draw_orb_trail()


# 光球弹彗尾: 沿速度反方向的渐隐拖尾(3 段递减圆, 长度随弹速), 帧率无关
func _draw_orb_trail() -> void:
	if velocity == Vector2.ZERO:
		return
	var back := -velocity.normalized()
	var spd := clampf(velocity.length() / 220.0, 0.6, 1.6)   # 归一到常规弹速, 快弹尾更长
	var col := Color(0.6, 0.95, 1.0) if team == "player" else Color(1.0, 0.55, 0.7)
	for i in range(3):
		var k := float(i + 1) / 3.0
		var c := col
		c.a = 0.30 * (1.0 - k * 0.75)
		draw_circle(back * (4.0 + 9.0 * k) * spd, lerpf(2.6, 1.0, k), c)


# 飞刀: 银白刀身(前尖后钝) + 暗色刀柄 + 速度残影; 朝向即局部 +X
func _draw_blade() -> void:
	# 1) 残影: 两道沿 -X 拖出的淡色刀形轮廓(速度感, 比圆点尾迹更像"飞刀")
	for i in range(2):
		var off := -6.0 - 5.0 * float(i)
		var gc := Color(0.80, 0.88, 1.0, 0.22 - 0.09 * float(i))
		_Pixels.fill_convex(self, PackedVector2Array([
			Vector2(off + 7.0, 0.0), Vector2(off - 2.0, 1.4),
			Vector2(off - 5.0, 0.0), Vector2(off - 2.0, -1.4),
		]), gc)

	# 2) 刀身: 菱形刃(刀尖在最前), 上半亮下半暗 => 有金属立体感
	_Pixels.fill_convex(self, PackedVector2Array([
		Vector2(8.0, 0.0), Vector2(-1.0, 2.0), Vector2(-3.0, 0.0),
	]), Color(0.92, 0.95, 1.0, 0.95))
	_Pixels.fill_convex(self, PackedVector2Array([
		Vector2(8.0, 0.0), Vector2(-3.0, 0.0), Vector2(-1.0, -2.0),
	]), Color(0.62, 0.70, 0.86, 0.95))

	# 3) 刀柄 + 护手: 暗棕短柄, 护手一道竖线分隔刃与柄
	_Pixels.rect(self, Vector2(-6.5, -1.0), Vector2(3.5, 2.0), Color(0.42, 0.32, 0.24, 0.95))
	_Pixels.line(self, Vector2(-3.0, -2.4), Vector2(-3.0, 2.4), Color(0.85, 0.75, 0.35, 0.9), 1.0)

	# 4) 刃口高光: 沿上刃一道白线, 强化"锋利"读感
	_Pixels.line(self, Vector2(-1.0, 1.4), Vector2(7.0, 0.0), Color(1.0, 1.0, 1.0, 0.85), 1.0)


# 回旋镖: V 形木镖(局部 +X = 前进方向, 弯折点在前、两臂向后张开), 残影 + 木纹双色 + 白色臂尖
# 节点自旋在 _physics_process 里叠加到 rotation。
# 为什么用描边不用 fill_convex: V 形是**凹**多边形, 凸填充画不出来(会读成飞镖/菱形);
# 两臂各画一条粗线即是天然凹形, 像素印章本身硬边无抗锯齿。
# 像素化说明: 连续旋转会让臂身扫过半像素位置(斜边抖动) ——
# 角度吸附到 45° 步进, V 形只以 8 向切换, 观感锐利无补间糊态(同旧手里剑的处理)。
func _draw_boomerang() -> void:
	var snap := snappedf(rad_to_deg(rotation), 45.0)
	var fx := Vector2.from_angle(deg_to_rad(snap))
	var fy := fx.orthogonal()
	# 弯折点在前, 两臂端在后侧张开 => 顶视飞行中的回旋镖
	var bend := fx * 2.5
	var a1 := -fx * 3.5 + fy * 5.0
	var a2 := -fx * 3.5 - fy * 5.0

	# 0) Lv3 火焰尾迹: 放最底, 沿 -X 渐隐橙色 V 形拖影(终极档, 速度感 + 热度)
	if _proc.get("fire_trail", false):
		for i in range(3):
			var off := Vector2(-6.0 - 5.0 * float(i), 0.0)
			_draw_boom_arms(bend + off, a1 + off, a2 + off, Color(1.0, 0.55, 0.20, 0.26 - 0.07 * float(i)), 3.0)

	# 1) 残影: 两道沿 -X 拖出的淡色 V 形轮廓(速度感)
	for i in range(2):
		var off2 := Vector2(-5.0 - 4.5 * float(i), 0.0)
		_draw_boom_arms(bend + off2, a1 + off2, a2 + off2, Color(0.80, 0.88, 1.0, 0.18 - 0.07 * float(i)), 3.0)

	# 2) 镖体: 暗木粗臂(厚度) + 亮木细臂(受光面统一偏 -fy 一侧 => 光从一侧来)
	_draw_boom_arms(bend, a1, a2, Color(0.46, 0.32, 0.20, 0.97), 3.0)
	var lit := -fy * 0.9
	_draw_boom_arms(bend + lit, a1 + lit, a2 + lit, Color(0.78, 0.58, 0.34, 0.90), 1.0)

	# 3) 弯折点(握把)与两臂尖: 白色 1px 标记, 强化"锋利 + 会转回来"的读感
	_Pixels.rect(self, (bend - Vector2.ONE).round(), Vector2(2.0, 2.0), Color(0.95, 0.90, 0.80, 0.90))
	_Pixels.rect(self, (a1 - Vector2(0.5, 0.5)).round(), Vector2.ONE, Color(1.0, 1.0, 1.0, 0.85))
	_Pixels.rect(self, (a2 - Vector2(0.5, 0.5)).round(), Vector2.ONE, Color(1.0, 1.0, 1.0, 0.55))


# 画两臂: 弯折点 bend 分别连到 a1 / a2, 线宽 w
func _draw_boom_arms(bend: Vector2, a1: Vector2, a2: Vector2, col: Color, w: float) -> void:
	_Pixels.line(self, bend, a1, col, w)
	_Pixels.line(self, bend, a2, col, w)