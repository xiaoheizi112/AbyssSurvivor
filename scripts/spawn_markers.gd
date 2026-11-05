extends Node2D
## SpawnMarkers — 刷怪预警叉: 地图上先标红叉, 倒计时结束怪从叉处落地(土豆兄弟式)
## 数据与 spawner._telegraphs 共享同一 Array 引用, 本节点只负责绘制; 无标记时自动隐藏

var telegraphs: Array = []   # [{pos: Vector2, t: float, dur: float, ...}]
var _t := 0.0


func _ready() -> void:
	z_index = -5   # 地面(-10)之上、实体(0)之下 => 叉像画在地上, 怪落地时盖住它
	# 始终处理: 暂停/商店时也要能收叉(否则会留下上一帧的残影, 与闪电特效同一类坑)
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	var active: bool = GameManager.state == GameManager.State.PLAYING and not telegraphs.is_empty()
	if visible != active:
		visible = active
		# 显隐切换时重绘一次: 隐藏前把已画到画布上的叉清掉
		queue_redraw()
	if active:
		queue_redraw()


func _draw() -> void:
	if telegraphs.is_empty():
		return
	for tg in telegraphs:
		var p: Vector2 = tg["pos"]
		var dur: float = float(tg["dur"])
		# k = 剩余比例 1 → 0, 驱动收缩环读秒
		var k := clampf(float(tg["t"]) / dur, 0.0, 1.0) if dur > 0.0 else 0.0
		var pulse := 0.5 + 0.5 * sin(_t * 11.0)

		# 收缩环: 半径 20 → 7, 越接近落地越实(给出明确的"还剩多久"读感)
		var r := lerpf(7.0, 20.0, k)
		draw_arc(p, r, 0.0, TAU, 22, Color(0.95, 0.30, 0.25, 0.20 + 0.45 * (1.0 - k)), 1.5)

		# 红叉: 呼吸脉动, 两条对角线
		var s := 5.0 + 2.5 * pulse
		var col := Color(0.98, 0.28, 0.24, 0.55 + 0.40 * pulse)
		draw_line(p + Vector2(-s, -s), p + Vector2(s, s), col, 2.0)
		draw_line(p + Vector2(-s, s), p + Vector2(s, -s), col, 2.0)

		# 中心暗点: 标记怪将出现的精确位置
		draw_circle(p, 1.6, Color(0.20, 0.04, 0.04, 0.75))

		# 精英双环: 紫主环呼吸 + 金内环定心。0.9s 预警期就要给玩家"这只要专门处理"的信号
		# (落地后精英本体还有 EliteAura 光环, 预警圈是它进场前的唯一预告)。
		# 用 get 而非 [] : boss 叉的 telegraph 没有 elite 键, 直接索引会崩。
		if bool(tg.get("elite", false)):
			PixelUtils.ring(self, p, 14.0 + 3.0 * pulse, 1.5, Color(0.55, 0.30, 0.95, 0.8))
			PixelUtils.ring(self, p, 9.0, 1.0, Color(1.0, 0.85, 0.30, 0.6))
