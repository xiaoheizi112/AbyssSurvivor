extends Node2D
## Effect — 通用一次性战斗特效(对象池复用)
## 全程序化绘制(零新资源), 走 ObjectPool reuse; 高频命中(spark)与低频爆裂(burst)都适用
## 模式: "spark" 命中火花 / "burst" 击杀爆裂(扩散环 + 像素碎片)

var mode: String = "spark"
var color: Color = Color.WHITE
var life: float = 0.2
var _t: float = 0.0
var _scale: float = 1.0
var _dir: Vector2 = Vector2.RIGHT   # muzzle 用: 发射方向
var _shards: Array = []   # burst 用: [ [angle, speed, size], ... ] setup 时预生成, 绘制确定性
var _follow: Node2D = null   # 可选跟随目标(如圣环涟漪贴着玩家扩散), 每帧同步位置; 释放时清空


func setup(m: String, pos: Vector2, col: Color, lf: float = 0.2, sc: float = 1.0, dir: Vector2 = Vector2.ZERO, follow: Node2D = null) -> void:
	mode = m
	global_position = pos
	color = col
	life = lf
	_scale = sc
	_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_follow = follow
	_t = 0.0
	# 爆裂碎片在 setup 一次性随机, 保证整个生命周期内不闪烁重构
	if mode == "burst":
		_shards.clear()
		for i in range(4):
			var a := TAU * float(i) / 4.0 + GameManager._rng.randf_range(-0.35, 0.35)
			_shards.append([
				a,
				GameManager._rng.randf_range(26.0, 42.0),
				GameManager._rng.randi_range(2, 4),
			])
	visible = true


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		recycle()
		return
	# 有跟随目标则每帧同步位置(涟漪贴目标扩散, 目标移动也不残留)
	if _follow != null and is_instance_valid(_follow):
		global_position = _follow.global_position
	queue_redraw()


func recycle() -> void:
	visible = false
	_follow = null
	ObjectPool.release(self)


func _draw() -> void:
	match mode:
		"spark":
			_draw_spark()
		"burst":
			_draw_burst()
		"ring":
			_draw_ring()
		"muzzle":
			_draw_muzzle()


# 命中火花: 像素十字 + 45° 斜叉, 白→黄→橙, 随生命周期收缩渐隐
func _draw_spark() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	var r := lerpf(7.0, 2.0, k) * _scale
	var col: Color
	if k < 0.5:
		col = Color.WHITE.lerp(Color(1.0, 0.85, 0.3), k * 2.0)
	else:
		col = Color(1.0, 0.85, 0.3).lerp(Color(1.0, 0.45, 0.15), (k - 0.5) * 2.0)
	col.a = 1.0 - k
	draw_line(Vector2(0, -r), Vector2(0, r), col, 1.0)
	draw_line(Vector2(-r, 0), Vector2(r, 0), col, 1.0)
	var d := r * 0.7
	draw_line(Vector2(-d, -d), Vector2(d, d), col, 1.0)
	draw_line(Vector2(-d, d), Vector2(d, -d), col, 1.0)


# 击杀爆裂: 由中心扩散的环 + 外向飞出的像素碎片, 颜色取实体主色
func _draw_burst() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	var ring_r := lerpf(3.0, 18.0, ease(k, 0.4)) * _scale
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 24, Color(color.r, color.g, color.b, (1.0 - k) * 0.8), 1.0)
	for s in _shards:
		var dpos := Vector2.from_angle(float(s[0])) * float(s[1]) * k * _scale
		var sz: int = int(s[2])
		var sc := color.lightened(0.3)
		sc.a = 1.0 - k
		draw_rect(Rect2(dpos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), sc, true)


# 扩散涟漪: 由中心扩散到 _scale(半径像素)的一圈环, 用于圣环结算脉冲
func _draw_ring() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	var r := lerpf(3.0, _scale, ease(k, 0.5))
	var c := color
	c.a = (1.0 - k) * 0.6
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, c, 1.0)


# 枪口闪光: 朝发射方向 3 条短放射线(主向 + 两侧微偏), 极快收缩淡出
func _draw_muzzle() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	var r := lerpf(9.0, 1.0, k) * _scale
	var c := color
	c.a = 1.0 - k
	for ang in [-0.3, 0.0, 0.3]:
		var d := _dir.rotated(ang)
		draw_line(Vector2.ZERO, d * r, c, 1.0)