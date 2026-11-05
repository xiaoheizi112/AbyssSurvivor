extends "res://scripts/weapon_base.gd"
## Aura — 圣光光环; 圆形区域每 1.0s 结算, 对范围内所有敌人同时伤害
## Lv2 半径跳增 + 双圈脉冲, Lv3 结算提速 25%
## 视觉: 三层柔光渐变 + 脉动边界环 + 环绕圣光粒子; 结算瞬间边界爆亮(脉冲与光环呼应)

# 粒子数: 随特效档位 +2/档(Lv1 6 / Lv2 8 / Lv3 10)
# 进化态**不再单独加密度**: 主效果收敛为「半径 +60% · 结算回血 3」,
# 区分度交给配色(_tint 橙红)与内侧反向细环, 不与等级档位抢视觉通道
const SPARK_COUNT := 6

var _t: float = 0.0          # 累积时间: 驱动粒子环绕 / 边界脉动 / 呼吸


func _id() -> String:
	return "aura"


func _ready() -> void:
	base_cooldown = 1.0
	base_damage = 8.0
	set_process(true)


func radius() -> float:
	var r := 45.0 + float(level() - 1) * 7.5
	if level() >= 2:
		r += 21.0   # Lv2 质变: 覆盖半径一次性跳增(逐级线性之外再加一档)
	r *= float(player.area_mult())
	if is_evolved():
		r *= 1.6   # 圣域: 半径 +60%
	return r


# Lv3 质变: 结算周期 -25%(1.0s → 0.75s), 光环从"稳态覆盖"变成"持续烫脚"
func cur_cooldown() -> float:
	return base_cooldown * (0.75 if level() >= 3 else 1.0)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or player == null:
		return
	global_position = player.global_position
	_t += delta
	queue_redraw()


func _do_attack() -> void:
	var r := radius()
	var hit_any := false
	for e in GameManager.enemies.duplicate():
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		if global_position.distance_to(e.global_position) < r + e.collision_radius():
			e.take_damage(cur_damage())
			# 易伤领域: 光环覆盖的敌人受伤 +15%(同 freeze 易伤乘算)
			# 特性状态读表(见 GameManager.WEAPON_TRAITS["aura"]), 不写 "vulnerable" 字面量
			apply_trait(e)
			# Lv3 终极: 命中敌人溅火花, 把"被标易伤"可视化出来(配色随光环主题, 进化态橙红)
			if _fx_tier() >= 2:
				GameManager.spawn_spark(e.global_position, _tint(1.0))
			hit_any = true
	# 结算脉冲: 边界扩散涟漪(贴玩家, 移动不残留) + 光环本体爆亮(由 timer 驱动)
	GameManager.spawn_ring(global_position, _tint(1.0), r, player)
	# Lv2 强档: 内圈二次涟漪(双圈脉冲, 结算更有层次)
	if _fx_tier() >= 1:
		GameManager.spawn_ring(global_position, _tint(0.7), r * 0.62, player)
	if hit_any:
		if is_evolved():
			player.heal(3.0)   # 圣域: 每次结算回血 3
		GameManager.play_sfx("pickup")


# 光环配色: 常态金黄 / 进化态橙红(圣域), a 乘全局透明度系数
func _tint(a: float) -> Color:
	return Color(1.0, 0.62, 0.18, a) if is_evolved() else Color(1.0, 0.85, 0.30, a)


func _draw() -> void:
	if player == null:
		return
	var r := radius()
	var cd := cur_cooldown()
	# timer 刚结算时≈cd, 随攻速/冷却缩减递减到 0 => 直接用 timer/cd 做脉冲相位, 节奏与实际结算周期同步
	var p := 0.0 if cd <= 0.0 else clampf(timer / cd, 0.0, 1.0)
	# 余晖曲线: 刚结算最亮, 前半段快速衰减, 后半段留一点余光(避免边界死板)
	var pulse := p * p
	# 呼吸: 缓慢正弦, 让光环"活着"而非静止贴图
	var breath := 0.5 + 0.5 * sin(_t * 2.2)

	# 1) 三层同心柔光: 由外到内渐亮, 近似径向渐变
	#    大半径(45~150px)光晕保留软边: 硬切会出难看阶梯, 且 alpha 极低(0.045)本身无硬边观感
	draw_circle(Vector2.ZERO, r, _tint(0.045 + 0.02 * breath + 0.05 * pulse))
	draw_circle(Vector2.ZERO, r * 0.78, _tint(0.045 + 0.03 * pulse))
	draw_circle(Vector2.ZERO, r * 0.50, _tint(0.05 + 0.03 * pulse))

	# 2) 边界环: 呼吸微缩放 + 结算爆亮; 像素圆环(阶梯边界, 主环 2px + 外侧 1px 淡环辉光)
	var rr := r * (1.0 + 0.012 * sin(_t * 2.2))
	px_ring(Vector2.ZERO, roundf(rr), 2.0, _tint(0.30 + 0.20 * breath + 0.45 * pulse))
	px_ring(Vector2.ZERO, roundf(rr + 2.0), 1.0, _tint(0.10 + 0.25 * pulse))

	# 3) 进化态: 内侧反向细环(双层结构, 与普通态拉开档次)
	if is_evolved():
		px_ring(Vector2.ZERO, roundf(r * 0.62), 1.0, _tint(0.22 + 0.20 * pulse))

	# 4) 环绕圣光粒子: 小亮点沿边界慢转, 亮部拖一道渐隐尾迹(旋转方向一致 => 尾迹在身后)
	#    粒子密度随档位 +2/档(更密集神圣); 粒子/尾迹都整数对齐(像素点)
	var n := SPARK_COUNT + _fx_tier() * 2
	var spin := _t * (0.9 if is_evolved() else 0.7)
	for i in range(n):
		var a := spin + TAU * float(i) / float(n)
		var pos := Vector2.from_angle(a) * rr
		# 尾迹: 3 段递减, 朝旋转反方向回退(像素小方块)
		for k in range(3, 0, -1):
			var ta := a - 0.10 * float(k)
			var tp := (Vector2.from_angle(ta) * rr).round()
			px_rect(tp - Vector2(0.5, 0.5), Vector2.ONE, _tint((0.30 - 0.09 * float(k)) * (0.6 + 0.4 * pulse)))
		# 亮点本体: 白热核心(结算时更亮更大, 2×2 像素方块)
		var core := Color(1.0, 0.96, 0.82, 0.75 + 0.25 * pulse)
		var core_sz := 2.0 if pulse > 0.5 else 1.0
		px_rect((pos - Vector2(core_sz, core_sz) * 0.5).round(), Vector2(core_sz, core_sz), core)
