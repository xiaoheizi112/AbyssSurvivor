extends Node2D
## BurnZone — 燃烧瓶落地的持续灼烧区域(非池化: 数量有限, 生命周期短, 直接 free)
## 每 0.35s 对圈内敌人结算一次伤害 + 挂「燃烧」特性(出站后余烬继续烧 3s)
## 随生命周期渐隐, 结束自毁
## 视觉: 多层燃料渐变 + 边缘火光环 + 上升火星; 每次结算(tick)区域爆亮一下, 让 DoT 可读

const _Pixels := preload("res://scripts/pixel_utils.gd")

var radius: float = 26.0
var damage: float = 6.0
var life: float = 3.0
var _t: float = 0.0
var _tick: float = 0.0
var _evolved: bool = false
var _tier: int = 0             # 武器特效档位(Lv3=2), 影响配色分层
var _pulse: float = 0.0        # 结算爆亮计时(0 → 静息)

const TICK_INTERVAL := 0.35
const PULSE_T := 0.28
# 灼烧 DoT 系数: 每跳 = 区域每跳伤害 × 此值(burn 间隔 0.5s, 区域本体 0.35s)
# 0.4 的依据: 区内总 dps +~35%, 离区后还烧 3s(燃烧瓶的身份 —— 火沾身上带走),
# 又不让区域伤害翻倍盖过其他武器
const BURN_POWER := 0.4
# 气泡: [角度偏移, 半径系数, 上浮速度, 相位] — setup 时定死, 生命周期内不重构(避免闪烁)
var _bubbles: Array = []


func _ready() -> void:
	# 入 group: 重开清场时 main 扫 group 统一 free(非池化, 不进 ObjectPool)
	add_to_group("burn_zone")


func setup(pos: Vector2, r: float, dmg: float, dur: float, evolved: bool, tier: int = 0) -> void:
	global_position = pos
	radius = r
	damage = dmg
	life = dur
	_evolved = evolved
	_tier = tier
	_t = 0.0
	_tick = 0.0
	_pulse = PULSE_T          # 落地瞬间也亮一下(与 holy_water 的 spawn_burst 呼应)
	visible = true
	z_index = -1   # 画在地面之上、实体之下
	# 气泡数随区域大小, 5~9 颗; 参数一次性随机
	_bubbles.clear()
	var nb := clampi(int(r / 6.0), 5, 9)
	for i in range(nb):
		_bubbles.append([
			GameManager._rng.randf() * TAU,
			GameManager._rng.randf_range(0.25, 0.85),
			GameManager._rng.randf_range(8.0, 16.0),
			GameManager._rng.randf() * TAU,
		])


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_t += delta
	_tick -= delta
	if _pulse > 0.0:
		_pulse = maxf(0.0, _pulse - delta)
	if _t >= life:
		queue_free()
		return
	if _tick <= 0.0:
		_tick = TICK_INTERVAL
		_burn()
		_pulse = PULSE_T
	queue_redraw()


func _burn() -> void:
	# 特性「燃烧」(读 GameManager.WEAPON_TRAITS["holy_water"]): 原减速泽地改灼烧 DoT。
	# 不继承 weapon_base(区域节点), 故直接读表; 本区域只由燃烧瓶链式生成, 武器 id 写死无害
	var kind := GameManager.trait_of("holy_water")
	for e in GameManager.enemies.duplicate():
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if global_position.distance_to(e.global_position) < radius + e.collision_radius():
			e.take_damage(damage, true)   # DoT: 不击退/不触发 proc, 用暗色小号数字
			# 灼烧: 区内刷新时长, 出站后余烬继续烧 3s(StatusFx.CONFIG burn)
			if kind != "":
				StatusFx.apply(e._status, kind, damage * BURN_POWER)


# 区域配色: 常态橙红火池 / Lv3 白热金 / 进化态炼狱紫
# 三个色值与 holy_water._tint、holy_vial._tint_liquid 必须一致(瓶子→飞行→火池一条视觉链)
func _tint(a: float) -> Color:
	if _evolved:
		return Color(0.85, 0.40, 0.95, a)
	if _tier >= 2:
		return Color(1.00, 0.78, 0.25, a)
	return Color(1.00, 0.45, 0.15, a)


func _draw() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	# 淡入淡出: 前 0.15s 展开(落地泼溅感), 后 35% 渐隐
	var appear := clampf(_t / 0.15, 0.0, 1.0)
	var fade := appear * (1.0 - smoothstep(0.65, 1.0, k))
	var pulse := 0.0 if PULSE_T <= 0.0 else clampf(_pulse / PULSE_T, 0.0, 1.0)
	pulse = pulse * pulse      # 余晖曲线: 结算瞬间最亮, 快速回落
	var r := radius * lerpf(0.7, 1.0, ease(appear, 0.4))

	# 1) 火池: 三层同心渐亮, 近似径向渐变(中心燃料最深)。大半径(24~60px)池面保留
	#    低 alpha 软渐变(硬切出难看阶梯), 仅最后半透明度色阶按像素圆盘画; 观感保持一致
	if r <= 30.0:
		# 小半径时用像素圆盘增强"硬边燃料"感
		_Pixels.disc(self, Vector2.ZERO, r, _tint((0.10 + 0.05 * pulse) * fade))
		_Pixels.disc(self, Vector2.ZERO, r * 0.80, _tint((0.09 + 0.06 * pulse) * fade))
		_Pixels.disc(self, Vector2.ZERO, r * 0.52, _tint((0.08 + 0.07 * pulse) * fade))
	else:
		# 大半径保持原三层渐变(同 aura 大光晕的理由)
		draw_circle(Vector2.ZERO, r, _tint((0.10 + 0.05 * pulse) * fade))
		draw_circle(Vector2.ZERO, r * 0.80, _tint((0.09 + 0.06 * pulse) * fade))
		draw_circle(Vector2.ZERO, r * 0.52, _tint((0.08 + 0.07 * pulse) * fade))

	# 2) 边缘火光环: 主环 + 外侧淡辉, 结算时爆亮(DoT 正在生效的反馈)—— 像素圆环
	_Pixels.ring(self, Vector2.ZERO, roundf(r), 2.0, _tint((0.30 + 0.45 * pulse) * fade))
	_Pixels.ring(self, Vector2.ZERO, roundf(r + 2.0), 1.0, _tint((0.10 + 0.22 * pulse) * fade))

	# 3) 上升火星: 沿各自轨道缓慢上浮, 到顶缩小消散; 大小/速度 setup 时定死
	#    原"沸腾气泡"的运动学(上浮 + 到顶消散)本来就是火星, 只改配色语义
	var bright := Color(1.00, 0.86, 0.48, 1.0) if not _evolved else Color(0.96, 0.78, 1.00, 1.0)
	for b in _bubbles:
		var a := float(b[0]) + _t * 0.6                 # 缓慢绕转, 不是死板直线
		var rr := r * float(b[1])
		var rise := fmod(_t * float(b[2]) + float(b[3]) * 2.0, 14.0)
		var bp := Vector2.from_angle(a) * rr - Vector2(0.0, rise)
		# 接近顶端(14px)时缩小消散, 避免火星凭空消失
		var live := 1.0 - clampf(rise / 14.0, 0.0, 1.0)
		var sz := (1.0 + 1.0 * live) * (0.8 + 0.4 * pulse)
		var bc := bright
		bc.a = (0.20 + 0.30 * live + 0.20 * pulse) * fade
		_Pixels.disc(self, bp, sz, bc)
		# 火星亮芯(左上一点白热), 给一点体积感
		if live > 0.5:
			var hc := Color(1.0, 1.0, 0.92, 0.35 * live * fade)
			_Pixels.rect(self, bp + Vector2(-0.5, -0.5) - Vector2(sz * 0.4, sz * 0.4), Vector2(1.0, 1.0), hc)
