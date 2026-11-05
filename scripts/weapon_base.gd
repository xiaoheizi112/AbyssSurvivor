extends Node2D
## WeaponBase — 武器基类; 子类实现 _do_attack(delta)
## 等级由 player.weapon_levels[id] 读取

const _Pixels := preload("res://scripts/pixel_utils.gd")

var weapon_id: String = ""
var player: Node2D = null
var timer: float = 0.0

# 基础数值(子类覆盖)
var base_cooldown: float = 1.0
var base_damage: float = 10.0


func init(p: Node2D) -> void:
	player = p
	weapon_id = _id()
	timer = base_cooldown


func _id() -> String:
	return ""   # 子类覆盖


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if player == null:
		return
	global_position = player.global_position
	_sync_fx_material()

	timer -= delta * player.attack_speed_mult() * player.cooldown_mult()
	if timer <= 0.0:
		_do_attack()
		timer = cur_cooldown()


func _do_attack() -> void:
	pass


# 攻击后的冷却重置值; 子类可覆盖(如进化后落雷更频繁)
func cur_cooldown() -> float:
	return base_cooldown


func level() -> int:
	if player != null and player.weapon_levels.has(weapon_id):
		return player.weapon_levels[weapon_id]
	return 0


# 特效档位(质变点统一 Lv2 / Lv3): 0=Lv1 基础 / 1=Lv2 强档 / 2=Lv3 终极
# 各子类 _draw 里按此分档叠加特效层, 逐级变强可读
func _fx_tier() -> int:
	var lv := level()
	if lv >= 3:
		return 2
	if lv >= 2:
		return 1
	return 0


# 终极档(Lv3)整体切 additive 发光: 程序化绘制的所有光晕/刃体加法叠加, 拉开与普通档的亮度差
# 材质仅在档位变化时重建一次(静态缓存共享), 非终极档恢复默认混合
static var _additive_mat_cache: ShaderMaterial = null

func _sync_fx_material() -> void:
	var t := _fx_tier()
	if t == _fx_tier_cached:
		return
	_fx_tier_cached = t
	if t >= 2:
		if _additive_mat_cache == null:
			_additive_mat_cache = ShaderMaterial.new()
			var sh := Shader.new()
			# 不写 fragment: 默认 texture*COLOR, 保留 draw 颜色(含 alpha)
			sh.code = "shader_type canvas_item;\nrender_mode blend_add;\n"
			_additive_mat_cache.shader = sh
		material = _additive_mat_cache
	else:
		material = null

var _fx_tier_cached := -1


func is_evolved() -> bool:
	return player != null and player.is_evolved(weapon_id)


# ================= 特性接线(读 GameManager.WEAPON_TRAITS) =================
# 武器脚本里**不要写状态名字面量**: 改绑定只动 GameManager 那张表, 这里跟着走。
# 例外: 触发概率与 power 仍由各武器自己算(那是武器手感, 不是特性定义)。

# 本武器的特性状态 id(如 "bleed"); 未登记返回 ""
func trait_status() -> String:
	return GameManager.trait_of(weapon_id)


# 特性染色的显示名(如 "流血"), 未登记返回 ""
func trait_name() -> String:
	return GameManager.trait_name(weapon_id)


# 给一个目标挂上本武器的特性状态
#   power: DoT 每跳伤害(burn/poison/bleed 用; 定身/减速类传 0)
#   chance: 触发概率 0~1, 这里掷骰(与 bullet 的 proc 同一套语义)
#   resist: 抗性系数, 只缩短状态持续时间(见 StatusFx.apply)
#     Boss 走 0.4 —— 但这个 0.4 目前只硬编码在 boss.gd:216 的 try_proc_from_player 调用点,
#     BOSS_BASE["status_resist"] 字段只有图鉴(hud.gd)在读, boss.gd 自己不读它。
#     本 helper 的调用方全是"直接命中"路径(敌人/Boss 通吃), 历史上这些路径一律不带抗性,
#     所以默认 1.0 以保持改表前后逐字节等价 —— 别在中途顺手给 Boss 加抗性, 那是另一个平衡决定。
#   factor: 强度系数(slow 的速度倍率 / vulnerable 的受伤倍率); <=0 = 用表默认值。
#     按武器等级分级的通道 —— 圣环 Lv3 易伤传 1.25, 回旋镖 Lv3 减速传 0.55。
#   max_stacks: 叠层上限(poison/bleed); <=0 = 用表默认值 3。飞刀 Lv2 传 5。
# 返回是否真的挂上了, 方便调用方决定要不要顺带播特效。
# 目标无效 / 未登记特性 / 掷骰未中 一律 false。
func apply_trait(target, power: float = 0.0, chance: float = 1.0, resist: float = 1.0,
		factor: float = 0.0, max_stacks: int = 0) -> bool:
	var kind := trait_status()
	if kind == "":
		return false
	if target == null or not is_instance_valid(target):
		return false
	# 只认带 _status 字典的持有者(enemy/boss); get() 对缺失属性返回 null,
	# 不用 `in` 探测 —— Object 的属性检查在静态分析下不稳, 且空字典也该放行
	var st: Variant = target.get("_status")
	if st == null:
		return false
	if chance < 1.0 and GameManager._rng.randf() >= chance:
		return false
	StatusFx.apply(st, kind, power, resist, factor, max_stacks)
	return true


# 构造 bullet 的 proc 字典(填好 kind, 调用方再补 power/chance 与视觉键)
# 用于走弹道命中的武器(wand/dagger/shuriken) —— bullet 内部自己掷骰挂状态,
# 所以这里只给 kind, 不调 apply_trait。未登记返回空字典(bullet 读到无 kind 即不挂)。
func trait_proc() -> Dictionary:
	var kind := trait_status()
	if kind == "":
		return {}
	return {"kind": kind}


func cur_damage() -> float:
	# 每级 +30%(原 +15%): 3 级制下 Lv3 = 1.69×, 略低于原 5 级的 1.75×, 满级强度基本持平
	return base_damage * pow(1.30, float(maxi(level() - 1, 0))) * player.damage_mult()


# 工具: 最近敌人
func nearest_enemy() -> Node2D:
	var best: Node2D = null
	var bd := INF
	for e in GameManager.enemies.duplicate():
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var d := global_position.distance_squared_to(e.global_position)
		if d < bd:
			bd = d
			best = e
	return best


# ================= 像素绘制工具(无抗锯齿 + 整数对齐) =================
# 在 _draw 里画实心矩形/圆盘/圆环/线段/多边形; 全部对齐整数像素, 2× 放大下锐利不糊
# 替换 draw_circle/draw_arc/draw_line 的抗锯齿边。
# 注意: draw_colored_polygon 本身硬边无抗锯齿, 填充不必替换(只有 draw_* 线条系需要)。
# bullet/holy_vial/burn_zone 等不继承本类的节点用同一套实现 → 见 PixelUtils。

# 整数对齐实心矩形(p 为左上角, sz 为尺寸; 内部 round 到整像素)
func px_rect(p: Vector2, sz: Vector2, col: Color) -> void:
	_Pixels.rect(self, p, sz, col)


# 像素实心圆盘: 逐扫描线算半宽, 每行画整数矩形(无抗锯齿的"圆")
func px_disc(c: Vector2, r: float, col: Color) -> void:
	_Pixels.disc(self, c, r, col)


# 像素圆环描边: 外圆盘减去内圆盘(只画环带), thickness 为环宽
func px_ring(c: Vector2, r: float, thickness: float, col: Color) -> void:
	_Pixels.ring(self, c, r, thickness, col)


# 像素线段: 从 a 到 b 用 width 尺寸的方形印章逐格覆盖(width=1 即 1px 线)
func px_line(a: Vector2, b: Vector2, col: Color, width: float = 1.0) -> void:
	_Pixels.line(self, a, b, col, width)


# 像素多边形轮廓: 对闭合多边形每条边走 px_line(顶点整数化由取样完成)
func px_poly(points: PackedVector2Array, col: Color, width: float = 1.0) -> void:
	_Pixels.poly(self, points, col, width)


# 像素实心凸多边形: 逐扫描线整数填充(floor 左 / ceil 右, 凸形每行恰 2 交点)
func px_fill_convex(points: PackedVector2Array, col: Color) -> void:
	_Pixels.fill_convex(self, points, col)