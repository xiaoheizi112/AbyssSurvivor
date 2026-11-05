extends "res://scripts/weapon_base.gd"
## HolyWater — 燃烧瓶, 朝最近敌人方向掷出, 落地形成持续灼烧区域
## 定位: 区域持续伤害(DoT), 补 wand/dagger 的「清群留场」空缺
## Lv2 +1 瓶; Lv3 灼烧半径跳增 + 换色爆裂; 进化「炼狱燃烧瓶」紫色炼狱火 · 半径+范围+时长
## 视觉: 悬停瓶身随冷却「重新装满」(液面回升), 装满后瓶口窜火苗, 掷出瞬间闪一下
## 特性「燃烧」: 火焰区内敌人持续灼烧(DoT 由 burn_zone 挂, 见 GameManager.WEAPON_TRAITS)
## 注: 武器 id 仍是 "holy_water" 不改 —— 改名要同步 6 处(WEAPONS/映射表/DETAILS/EVOLUTIONS/
##     ICONS/标签)且会让旧 suspend.cfg 里的 weapon_levels 键失配。只改显示名, 零存档兼容问题。

const FLASH_T := 0.15
const VIAL_POS := Vector2(-11.0, -15.0)   # 悬停在角色左肩侧(不挡脸, 与 wand 头顶法球区分)

var _flash := 0.0
var _t := 0.0


func _id() -> String:
	return "holy_water"


func _ready() -> void:
	base_cooldown = 2.2
	base_damage = 6.0   # 每 tick 伤害, 区域存续期内多次结算
	set_process(true)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING or player == null:
		return
	global_position = player.global_position
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	queue_redraw()


# 充能进度: timer 从 cd 递减到 0 => 0→1 瓶子逐渐装满(读得出下一瓶何时好)
func _charge() -> float:
	var cd := cur_cooldown()
	if cd <= 0.0:
		return 1.0
	return clampf(1.0 - timer / cd, 0.0, 1.0)


# 燃烧瓶配色: 常态橙红燃料 / Lv3 白热金黄 / 进化态炼狱紫
# 紫色留给进化态是全局约定(7 把武器进化后都跳紫/金), 所以 Lv3 不走"更红的橙"
# 而走亮度跳档(橙红→白热金), 让 Lv3 与进化态在色相上仍能一眼分开。
func _tint(a: float) -> Color:
	if is_evolved():
		return Color(0.85, 0.40, 0.95, a)
	if _fx_tier() >= 2:
		return Color(1.00, 0.78, 0.25, a)
	return Color(1.00, 0.45, 0.15, a)


func _do_attack() -> void:
	var target := nearest_enemy()
	if target == null:
		timer = 0.4
		return

	var bottles: int = 1 + (1 if level() >= 2 else 0) + int(player.extra_count() * 0.5)
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var dist := global_position.distance_to(target.global_position)
	dist = clampf(dist, 30.0, 130.0)   # 落点不要太远/太贴脸
	var tier := _fx_tier()

	var r: float = (24.0 + float(level()) * 2.5)
	if level() >= 3:
		r += 19.0   # Lv3 质变: 灼烧半径一次性跳增(终极圈更大)
	r *= float(player.area_mult())
	var dur: float = 2.6 + float(level()) * 0.25
	var dmg: float = cur_damage()

	if is_evolved():
		r *= 1.35
		dur *= 1.4
		dmg *= 1.2

	_flash = FLASH_T
	for i in range(bottles):
		# 多瓶时落点沿垂直方向错开, 铺成一片而非重叠
		var off := Vector2.ZERO
		if bottles > 1:
			off = dir.orthogonal() * (float(i) - float(bottles - 1) * 0.5) * 22.0
		var land := global_position + dir * dist + off
		_throw_vial(global_position, land, r, dmg, dur, tier)
	GameManager.play_sfx("shoot")


# 掷出飞行瓶: 抛物线飞向落点, 砸地时才生成灼烧区域(见 holy_vial._land)
func _throw_vial(from: Vector2, to: Vector2, r: float, dmg: float, dur: float, tier: int) -> void:
	var v := Node2D.new()
	v.set_script(load("res://scripts/holy_vial.gd"))
	GameManager.main.add_child(v)
	# 飞行时长随距离: 近落点更快砸地, 远落点稍久, 上限 0.45s 避免拖沓
	var flight := clampf(from.distance_to(to) * 0.003, 0.14, 0.45)
	v.setup(from, to, r, dmg, dur, is_evolved(), tier, flight)


func _draw() -> void:
	if player == null or not player.weapons.has("holy_water"):
		return
	var q := _charge()
	var f := _flash / FLASH_T
	var fo := f * f
	var p := VIAL_POS
	# 掷出瞬间瓶子向下后收一点(投掷动作), 悬停时轻微浮动
	var bob := sin(_t * 2.4) * 1.0
	p += Vector2(0.0, bob + 2.5 * fo)

	# 1) 瓶身轮廓: 圆底 + 细颈(程序化像素瓶形), 玻璃淡青
	var body_r := 4.2
	var glass := Color(0.78, 0.92, 0.95, 0.30 + 0.12 * q)
	var pc: Vector2 = (p + Vector2(0.0, 1.5)).round() + Vector2(0.5, 0.5)
	px_disc(pc, body_r, glass)
	px_rect(pc + Vector2(-1.0, -6.0), Vector2(2.0, 3.0), glass)
	# 瓶口软木塞
	px_rect(pc + Vector2(-2.0, -8.0), Vector2(4.0, 2.0), Color(0.62, 0.46, 0.30, 0.9))

	# 2) 瓶内液体: 液面高度随充能上升(核心可读性 —— 看瓶子就知道还剩多久)
	var fill := body_r * 2.0 * q
	if fill > 0.4:
		var lc := _tint(0.55 + 0.30 * q + 0.15 * fo)
		var cy := pc.y
		var top := cy + body_r - fill          # 液面 y(圆内自上而下)
		var top_i := int(floorf(top))
		# 液体 = 下半圆盘 + 上部矩形补到液面(裁剪近似), 全像素整数
		px_disc(pc, body_r, lc)
		if top_i < cy:
			px_rect(Vector2(pc.x - int(body_r), top_i), Vector2(int(body_r) * 2, cy - top_i), lc)
		# 液面高光线: 横线, 2 段取样(y 取整)
		px_rect(Vector2(pc.x - int(body_r * 0.8), top_i), Vector2(int(body_r * 1.6), 1.0),
			Color(1.0, 1.0, 1.0, 0.45 + 0.35 * q))

	# 3) 满充能: 瓶口窜起火苗(燃烧瓶的「可以投掷了」提示 —— 瓶口布条已点燃)
	#    三段色全从 _tint 派生: 常态橙焰 / Lv3 金焰 / 进化紫焰, 不另立一套火色
	if q > 0.97:
		var c_out: Color = _tint(1.0)
		var c_mid: Color = c_out.lerp(Color(1.00, 0.85, 0.45), 0.35)
		var c_core: Color = c_out.lerp(Color(1.00, 0.98, 0.85), 0.70)
		var fl: Vector2 = pc + Vector2(0.0, -9.0)        # 火苗根部: 软木塞正上方
		var flick := 0.5 + 0.5 * sin(_t * 11.0)          # 快频抖动(火不稳定, 区别于圣光的慢呼吸)
		var sway := roundf(sin(_t * 7.0))                # 左右摆 ±1px, 整数不糊
		# 外焰 → 中焰 → 焰心: 由宽到窄向上收(火的形状语言), 全整数像素
		px_disc(fl + Vector2(sway, 0.0), 3.0, Color(c_out.r, c_out.g, c_out.b, 0.40 + 0.15 * flick))
		px_disc(fl + Vector2(sway, -2.0), 2.2, Color(c_mid.r, c_mid.g, c_mid.b, 0.55 + 0.20 * flick))
		px_disc(fl + Vector2(sway, -4.0), 1.4, Color(c_core.r, c_core.g, c_core.b, 0.70 + 0.25 * flick))
		# 瓶身余晖: 火光映在玻璃上(保留原来那个"备好了"的可读信号, 但压暗不抢火苗)
		var glow_a := 0.08 + 0.06 * flick
		px_disc(pc - Vector2(0.0, 0.5), body_r + 2.5, _tint(glow_a))

	# 4) 玻璃高光: 左侧一道斜亮线(体积感)
	px_line(pc + Vector2(-2.2, 1.7), pc + Vector2(-1.2, -2.0), Color(1.0, 1.0, 1.0, 0.35), 1.0)
