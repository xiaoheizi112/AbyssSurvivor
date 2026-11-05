extends "res://scripts/weapon_base.gd"
## Wand — 魔法飞弹, 朝最近敌人发射; Lv2 穿透 1 · 过载更易触发, Lv3 双发 · 穿透 2
## 视觉: 法球随冷却凝聚(蓄力进度可读), 发射瞬间爆闪; 进化态换紫红奥术配色
##
## 升级重做(2026-09-10): 数量轴(双发)与机制轴(穿透)对调 ——
##   原 Lv2 双发 ±5.2° 在近距离两发几乎打同一只怪(名义翻倍实为单目标 +100%), Lv3 才给穿透;
##   现 Lv2 = 穿透 1(打穿一列怪, 真·换轴) + 过载阈值放宽到 0.70(强化"蓄力可读"身份),
##   Lv3 = 双发 + 穿透 2(数量轴后移到爆发档)。与全局「Lv1 身份 / Lv2 换轴 / Lv3 爆发」语义一致。

# 蓄力光球半径(满蓄力时)与浮空位置
# 光球画在头顶而非角色中心: Weapons 节点在 Sprite2D 之后绘制, 居中会被 32×32 精灵盖住
# 发射点仍留在角色中心(不改判定), 光球只是视觉浮在头顶
# 进化态**不再单独放大法球**: 主效果收敛为「扇形散射 5 发穿透弹」, 体型差异交给配色(_tint 紫红)
const ORB_R := 4.0
const ORB_OFFSET := Vector2(0.0, -21.0)   # 精灵 32×32 centered, 头顶在 -16; 光球浮在其上

var _flash := 0.0            # 发射爆闪计时(0.12s 衰减)
var _t := 0.0                # 累积时间: 驱动法球微旋与呼吸
var _waiting := false        # 已满蓄力但场上没目标: 蓄力显示钉在满格, 不再循环充能

const FLASH_T := 0.12
# 满蓄力待机时的索敌重试间隔: 够快(怪一进射程立刻开火), 又不至于每帧扫 enemies
const NO_TARGET_RETRY := 0.2
# 特性「眩晕」的触发概率(见 GameManager.WEAPON_TRAITS["wand"])。
# 状态名不在本文件写字面量, 由 trait_proc() 读表 —— 改绑定只动那张表。
const TRAIT_CHARGE_CHANCE := 0.20
# 过载触发的蓄力阈值两档: Lv1 = 0.85(原值, 接近满格才过载), Lv2 起 = 0.70(常规节奏即可吃到)。
# 过载 = 伤害 ×1.15 + 命中 20% 眩晕(见 _do_attack)。Lv2 放宽阈值是为了让"蓄力可读"这条身份线
# 在中段更常被触发, 与穿透前移一起构成 Lv2 的机制换轴(不再只是"多一发")。
const OVERLOAD_Q_LV1 := 0.85
const OVERLOAD_Q_LV2 := 0.70


func _id() -> String:
	return "wand"


func _ready() -> void:
	base_cooldown = 0.9
	base_damage = 14.0   # 幸存者类约定: 起始武器应 1~2 发秒掉最弱杂兵(史莱姆 25hp)
	set_process(true)


# 待机(已蓄满但没目标)时缩短冷却, 只做快速索敌重试; 蓄力显示不受影响(见 _charge)
func cur_cooldown() -> float:
	return NO_TARGET_RETRY if _waiting else base_cooldown


# 本次发射的过载蓄力阈值: Lv1 = 0.85, Lv2 起 = 0.70(含进化态, 它必为 Lv3)
func _overload_q() -> float:
	return OVERLOAD_Q_LV2 if level() >= 2 else OVERLOAD_Q_LV1


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or player == null:
		return
	global_position = player.global_position
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	queue_redraw()


func _do_attack() -> void:
	var target := nearest_enemy()
	if target == null:
		# 满蓄力待机: 蓄力显示钉在满格(见 _charge), 只按 NO_TARGET_RETRY 的短周期重新索敌,
		# 不再把法球打回空蓄力重充(基类会在本函数返回后 timer = cur_cooldown())
		_waiting = true
		return

	# 先取蓄力再解除待机: 待机期间 _charge 恒为 1.0 => 待机后的首发必定吃过载
	var q := _charge()
	_waiting = false

	if is_evolved():
		# 奥术星雨: 扇形散射 5 发, 每发穿透 2; 命中火花染紫红(进化主题色)
		var dir: Vector2 = (target.global_position - global_position).normalized()
		_fire_flash(dir)
		var eproc := {"fx_color": _tint(1.0), "hit_ring": true}
		# 特性不因进化而丢失: 满蓄力散射同样带眩晕。门槛/概率与常态**完全一致**不额外增强
		# —— 进化的量变已经落在「5 发穿透」上, 特性只负责保持身份连续(其余 6 把进化后特性都在)
		if q > _overload_q():
			eproc.merge(trait_proc())
			eproc["chance"] = TRAIT_CHARGE_CHANCE
		for i in range(5):
			var a := -0.30 + float(i) * 0.15   # 均匀散射约 ±30°
			var vel: Vector2 = dir.rotated(a) * 220.0 * player.proj_speed_mult()
			ObjectPool.spawn_bullet(global_position, vel, cur_damage(), "player", 2, "orb", eproc)
		GameManager.play_sfx("shoot")
		return

	# 数量与穿透对调(2026-09-10 升级重做): Lv2 = 穿透 1, Lv3 = 双发 + 穿透 2。
	# shots 的 +1 从 Lv2 后移到 Lv3(数量轴归爆发档); pierce 从 Lv3 前移到 Lv2 起有。
	var shots: int = 1 + player.extra_count() + (1 if level() >= 3 else 0)
	var pierce := 0
	if level() >= 2:
		pierce = 1
	if level() >= 3:
		pierce = 2

	var dir2: Vector2 = (target.global_position - global_position).normalized()

	# 过载: 蓄力达阈值时伤害 +15%、命中额外小概率眩晕(点控爆发, 与"蓄力可读"呼应)
	# 阈值随等级放宽(Lv1 0.85 / Lv2+ 0.70, 见 _overload_q): Lv2 起常规节奏就能吃到过载
	var dmg := cur_damage()
	var proc := {}
	if q > _overload_q():
		dmg *= 1.15
		proc = trait_proc()
		proc["chance"] = TRAIT_CHARGE_CHANCE

	# 穿透弹(Lv2 起): 命中点扩散一圈碎光(视觉标记每层命中)
	if level() >= 2:
		proc["hit_ring"] = true
	# 命中火花染常态青蓝(默认金黄), 贴合 wand 主题
	proc["fx_color"] = _tint(1.0)
	_fire_flash(dir2)
	for i in range(shots):
		var vel: Vector2 = dir2 * 200.0 * player.proj_speed_mult()
		if shots > 1:
			# 多轮散射: 发数越多张角越大
			var spread := -0.09 * float(shots - 1) + float(i) * 0.18
			vel = vel.rotated(spread)
		ObjectPool.spawn_bullet(global_position, vel, dmg, "player", pierce, "orb", proc)
	GameManager.play_sfx("shoot")


# 发射表现: 起爆闪计时 + 朝发射方向的像素枪口闪光(染色跟随常态青/进化紫)
func _fire_flash(dir: Vector2) -> void:
	_flash = FLASH_T
	# 枪口闪光旋转量化到 45° 八方向(保像素锐利); 进化态叠一颗小星芒, 爆点更炸
	var deg := snappedf(rad_to_deg(dir.angle()), 45.0)
	GameManager.spawn_pixel_fx("muzzle", global_position, _tint(1.0), 1.0, deg, true, true)
	if is_evolved():
		GameManager.spawn_pixel_fx("spark", global_position, _tint(0.9), 1.0, 0.0, true, true)


# 蓄力进度: timer 从 cd 递减到 0 => 0→1 逐渐凝聚(读得出"下一发什么时候到")
# 待机中恒为满蓄力: 能量已攒满只是在等目标, 不该跟着索敌重试的短周期反复抽干重充
func _charge() -> float:
	if _waiting:
		return 1.0
	var cd := base_cooldown
	if cd <= 0.0:
		return 1.0
	return clampf(1.0 - timer / cd, 0.0, 1.0)


# 法球配色: 常态青蓝奥术 / 进化态紫红; a 为透明度系数
func _tint(a: float) -> Color:
	return Color(0.86, 0.45, 1.0, a) if is_evolved() else Color(0.45, 0.85, 1.0, a)


func _draw() -> void:
	if player == null or not player.weapons.has("wand"):
		return
	var q := _charge()
	# 发射瞬间: 法球缩到最小并爆亮(能量已释放), 0.12s 内回落
	var f := _flash / FLASH_T
	var fo := f * f
	# 蓄力主半径: 随进度长大; 发射瞬间骤缩(读作"打出去了")
	# 特效档位: Lv2 法球 +18% / Lv3 再 +18%(终极档), 半径逐档长大(视觉"逐渐变强")
	var tier := _fx_tier()
	var base_r := ORB_R * (1.0 + 0.18 * float(tier))
	var r := lerpf(1.5, base_r, ease(q, 0.7)) * (1.0 - 0.55 * fo)
	var breathe := 0.5 + 0.5 * sin(_t * 3.0)
	# 整数对齐光球中心(像素绘制要求), 浮在头顶不被精灵遮挡
	var o := ORB_OFFSET.round()

	# 1) 外层柔光: 低透明像素圆盘, 让法球有光晕而非硬边圆点(整数半径, 无抗锯齿)
	px_disc(o, roundf(r * 2.0), _tint(0.05 + 0.04 * q + 0.10 * fo))
	px_disc(o, roundf(r * 1.45), _tint(0.08 + 0.05 * q + 0.12 * fo))

	# 2) 法球本体: 满蓄力时最实, 发射瞬间白热
	px_disc(o, roundf(r), _tint(0.30 + 0.45 * q + 0.25 * fo))

	# 3) 白热核心: 越接近发射越亮越大(临界感)
	px_disc(o, roundf(r * 0.5), Color(1.0, 1.0, 1.0, 0.35 + 0.45 * q + 0.20 * fo))

	# 4) 蓄力描边环: 像素圆环(替代抗锯齿 draw_arc), 随进度从暗到亮 + 呼吸微脉动
	px_ring(o, roundf(r + 1.5 + 0.6 * breathe), 1.0, _tint(0.12 + 0.30 * q + 0.25 * fo))

	# 5) 环绕奥术碎点: 基础 2 颗, Lv2 3 颗, Lv3 4 颗, 进化态 4 颗(像素小方块, 整数对齐)
	var n := 4 if is_evolved() else (2 + tier)
	var spin := _t * 2.2
	var dot := Color(1.0, 0.96, 0.9, (0.25 + 0.35 * q) * (0.7 + 0.3 * fo))
	for i in range(n):
		var a := spin + TAU * float(i) / float(n)
		var dp := (o + Vector2.from_angle(a) * (r + 3.0)).round()
		var s := 2.0 if fo > 0.3 else 1.0   # 发射瞬间碎点放大成 2×2, 强化爆闪
		px_rect(dp - Vector2(s * 0.5, s * 0.5), Vector2(s, s), dot)
