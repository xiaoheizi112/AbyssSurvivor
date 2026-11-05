class_name PixelUtils
extends RefCounted
## 像素绘制静态工具 —— 供不继承 WeaponBase 的 Node2D 使用(bullet / holy_vial / burn_zone)
## 实现与 weapon_base.gd 的 px_* 实例方法一致: 整数对齐、无抗锯齿、硬边。
## 武器本体的持续绘制走 weapon_base 的实例方法; 独立散件走这里。

static func rect(ci: CanvasItem, p: Vector2, sz: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(p.round(), sz.round()), col, true)


# 像素实心圆盘: 逐扫描线算半宽, 每行画整数矩形
static func disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.0:
		return
	var ri := int(roundf(r))
	var cc := c.round()
	for dy in range(-ri, ri + 1):
		var half := int(floor(sqrt(float(ri * ri - dy * dy))))
		if half < 0:
			continue
		ci.draw_rect(Rect2(cc.x - float(half), cc.y + float(dy), float(half * 2 + 1), 1.0), col, true)


# 像素圆环描边: 外圆盘减去内圆盘(只画环带), thickness 为环宽
static func ring(ci: CanvasItem, c: Vector2, r: float, thickness: float, col: Color) -> void:
	if r <= 0.0:
		return
	var ro := int(roundf(r))
	var rin := int(roundf(r - thickness))   # 内半径(<0 则退化为实心圆盘)
	var cc := c.round()
	for dy in range(-ro, ro + 1):
		var ho := int(floor(sqrt(float(ro * ro - dy * dy))))
		var hi := -1
		if rin >= 0 and absi(dy) <= rin:
			hi = int(floor(sqrt(float(rin * rin - dy * dy))))
		if hi < 0:
			ci.draw_rect(Rect2(cc.x - float(ho), cc.y + float(dy), float(ho * 2 + 1), 1.0), col, true)
		else:
			var seg := float(ho - hi)
			if seg > 0.0:
				ci.draw_rect(Rect2(cc.x - float(ho), cc.y + float(dy), seg, 1.0), col, true)
				ci.draw_rect(Rect2(cc.x + float(hi + 1), cc.y + float(dy), seg, 1.0), col, true)


# 像素线段: 从 a 到 b 用 width 尺寸的方形印章逐格覆盖(width=1 即 1px 线)
static func line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, width: float = 1.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var steps := int(ceilf(len)) + 1
	var wpx := maxi(int(roundf(width)), 1)
	for s in range(steps):
		var p: Vector2 = a.lerp(b, float(s) / float(steps - 1)).round()
		ci.draw_rect(Rect2(p - Vector2(wpx * 0.5, wpx * 0.5), Vector2(wpx, wpx)), col, true)


# 像素多边形轮廓: 对闭合多边形每条边走 line
static func poly(ci: CanvasItem, points: PackedVector2Array, col: Color, width: float = 1.0) -> void:
	for i in range(points.size()):
		line(ci, points[i], points[(i + 1) % points.size()], col, width)


# 像素实心凸多边形: 逐扫描线求左右交点, floor 左 / ceil 右(永不留缝),
# 凸形每行恰 2 个交点; 替代 draw_colored_polygon 以获得整数对齐的硬边填充
static func fill_convex(ci: CanvasItem, points: PackedVector2Array, col: Color) -> void:
	var n := points.size()
	if n < 3:
		return
	var miny := INF
	var maxy := -INF
	for v in points:
		miny = minf(miny, v.y)
		maxy = maxf(maxy, v.y)
	var y0 := int(floorf(miny + 0.5))
	var y1 := int(floorf(maxy + 0.5))
	for y in range(y0, y1 + 1):
		var xs: Array[float] = []
		for i in range(n):
			var v0: Vector2 = points[i]
			var v1: Vector2 = points[(i + 1) % n]
			if (v0.y <= float(y) + 0.5 and v1.y > float(y) + 0.5) or (v1.y <= float(y) + 0.5 and v0.y > float(y) + 0.5):
				if v1.y == v0.y:
					continue
				var t := (float(y) + 0.5 - v0.y) / (v1.y - v0.y)
				xs.append(v0.x + t * (v1.x - v0.x))
		xs.sort()
		for i in range(0, xs.size() - 1, 2):
			var xa := int(floorf(xs[i]))
			var xb := int(ceilf(xs[i + 1]))
			if xb > xa:
				ci.draw_rect(Rect2(xa, y, xb - xa, 1), col, true)