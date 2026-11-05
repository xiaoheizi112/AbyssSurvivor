extends Node2D
## Enemy — 七种杂兵共用; kind 区分(史莱姆/蝙蝠/巨魔/骷髅/吐息/自爆/护盾); Boss 用 boss.gd
## 追踪玩家 + 圆距接触伤害 + 击杀掉经验 + 难度倍率; 4/5/6 各有专属行为(见 _physics_process 行为段)

signal died(enemy_node)

enum Kind { SLIME, BAT, TROLL, SKELETON, BREATH, BOMBER, SHIELD }

var kind: int = Kind.SLIME
var hp: float = 30.0
var speed: float = 80.0
var damage: float = 8.0
var xp_value: float = 1.0
var color: Color = Color(0.3, 0.8, 0.3)

var _r: float = 12.0
var _attack_cooldown: float = 0.0
var _flash: float = 0.0
var sprite: AnimatedSprite2D = null
var _dead: bool = false
var _vel: Vector2 = Vector2.ZERO   # 平滑后的实际速度(避免逐帧瞬时转向)
var _knockback: Vector2 = Vector2.ZERO   # 受击击退冲量, 每帧衰减
var _status := {}   # 状态效果: kind -> {"t": 剩余时长, "power": 每跳伤害, "tick": 距下次结算, "stacks": 层数(毒)}

# ---- 词缀(行为多样性, 见 GameManager.ENEMY_AFFIXES) ----
var affix: String = ""            # 该敌人携带的词缀 id("" = 无)
var affix2: String = ""           # 第二词缀(精英专属; 与 affix 互斥取值, 见 roll_enemy_affix2)
var is_elite: bool = false        # 精英档: 双词缀 + 紫色光环 + 大幅数值(见 GameManager.ELITE_BASE)
var _max_hp: float = 0.0          # 供再生词缀回血封顶
var _regen: float = 0.0           # 再生: 每秒回血(0=无)
var _fire_interval: float = 0.0   # 射手: 开火间隔(0=非射手)
var _fire_timer: float = 0.0
var _split: int = 0               # 分裂: 死亡分裂的小怪数
var _explode_r: float = 0.0       # 自爆: 死亡爆炸半径(0=不自爆)
var _explode_dmg: float = 0.0
var _affix_tint: Color = Color(1, 1, 1)   # 词缀染色(无词缀白; 精英时被紫色覆盖)
var _aura: EliteAura = null       # 精英光环子节点(2 圈呼吸环, 非精英隐藏; 相位由本节点驱动)
var _is_offspring: bool = false   # 分裂词缀子代标记(打磨#6): 与 Boss 召唤物区分——召唤物是
                                  # spawn_enemy 直出的满配怪, 子代是父体死亡派生(缩小减半)。
                                  # 供血条副标/统计识别用, 不影响战斗数值。池复用必须复位。
var _elite_label: Label = null    # 精英头顶词缀副标(打磨#7): "疾风·坚韧" 双词缀名,
                                  # 紫光环只说明"是精英", 说明不了"哪两条" —— 自爆+疾风与
                                  # 分裂+再生的处理方针完全相反, 0.9s 内必须读出来。非精英隐藏。

# ---- kind 4/5/6 专属行为(BREATH 吐息 / BOMBER 自爆 / SHIELD 护盾) ----
# 全部参数来自 ENEMY_BASE, 行为状态字段在 setup() 无条件复位(池复用)
var _bstate: int = 0              # 吐息: 0 追击 / 1 站定蓄力 / 2 后撤拉距
var _b_timer: float = 0.0         # 吐息: 当前状态计时
var _breath_cd: float = 0.0       # 吐息: 冷却(<=0 才进入蓄力)
var _breath_n_min: int = 3
var _breath_n_max: int = 5
var _breath_range: float = 130.0
var _breath_speed: float = 110.0
var _breath_cd_full: float = 2.4
var _fuse: float = -1.0           # 自爆: -1 未引信; >=0 引信倒计时(站定闪红)
var _boom_r: float = 46.0
var _boom_dmg: float = 26.0
var _fuse_t: float = 0.4
var _fuse_range: float = 34.0
var _shield_hp: float = 0.0       # 护盾: >0 盾在; <=0 破盾(由 _shatter_t 管重立)
var _shatter_t: float = 0.0       # 破盾易伤倒计时
var _shatter_dur: float = 6.0     # 破盾持续时长(读 ENEMY_BASE["shatter_t"])
var _shield_max: float = 60.0
var _shield_arc: float = 120.0      # 正面减免角(度, 全角; 判定用半角余弦)
var _shield_reduce: float = 0.7
var _shatter_bonus: float = 0.5
var _face := Vector2.RIGHT        # 举盾朝向(慢转向, 玩家绕背才吃全额伤害)


func setup(k: int, aff: String = "", aff2: String = "", elite: bool = false) -> void:
	kind = k
	affix = aff
	affix2 = aff2      # 池复用必须清(漏了就是"普通怪带双词缀")
	is_elite = elite   # 同上(漏了就是"普通怪带紫光环 + 2.6 倍血")
	_is_offspring = false   # 子代标记同上复位(漏了就是"满配怪顶着分裂子体的小血条")
	_attack_cooldown = 0.0
	_flash = 0.0
	_dead = false
	_vel = Vector2.ZERO   # 出生从 0 加速起步(自然涌现而非瞬移满速)
	_knockback = Vector2.ZERO   # 池复用清残留: 上一只被旋刃推飞的怪会把冲量带给下一只
	_status.clear()       # 池复用清残留状态
	# 词缀行为参数归零(池复用清残留, 再按 aff/aff2 重设)
	_regen = 0.0
	_fire_interval = 0.0
	_fire_timer = 0.0
	_split = 0
	_explode_r = 0.0
	_explode_dmg = 0.0
	_affix_tint = Color(1, 1, 1)
	# 新怪行为状态归零(kind 0-3 永不读写这些字段, 复位零成本)
	_bstate = 0
	_b_timer = 0.0
	_breath_cd = 0.0
	_fuse = -1.0
	_shield_hp = 0.0
	_shatter_t = 0.0
	_face = Vector2.RIGHT

	# 基础数值读 GameManager.ENEMY_BASE(与图鉴共读同一张表, 改数值只改一处)
	# 巨魔定位是肉盾而非秒杀者: 无敌帧期间免疫所有伤害, 真实 DPS 上限 = 最高伤害敌人 / 0.75s
	var base: Dictionary = GameManager.ENEMY_BASE[kind]
	hp = float(base["hp"])
	speed = float(base["speed"])
	damage = float(base["damage"])
	xp_value = float(base["xp"])
	color = Color(base["color"])
	_r = float(base["radius"])
	# 血量随登场时间成长(封顶 3 倍): 越晚出现的怪越肉
	hp *= GameManager.enemy_hp_mult()
	# 难度倍率(普通=1 基线, 简单=0.75, 困难=1.3): 只调敌人侧, 不削玩家
	hp *= GameManager.difficulty_hp_mult()
	damage *= GameManager.difficulty_damage_mult()
	# 诅咒倍率(玩家自选的风险旋钮, 与难度档正交相乘; L=0 时恒 1.0 → 零变化)
	hp *= GameManager.curse_hp_mult()
	damage *= GameManager.curse_damage_mult()

	# 词缀应用: 数值倍率 + 行为标记 + 染色(在难度/时间倍率之后叠加, 词缀是"这一只"的额外强化)
	# 精英带两条, 各乘一次(双词缀 size 也叠 → 视觉与碰撞同步放大)
	_apply_affix(affix)
	_apply_affix(affix2)
	# 词缀敌人相对更强: 经验按每条词缀 +30%(双词缀 ×1.69, 风险收益对等)
	if affix != "":
		xp_value *= 1.3
	if affix2 != "":
		xp_value *= 1.3

	# 精英档: 双词缀之上再乘一层(风险换 3 枚大额金币 + 1/4 宝箱)
	if is_elite:
		var e: Dictionary = GameManager.ELITE_BASE
		hp *= float(e["hp"])
		damage *= float(e["damage"])
		speed *= float(e["speed"])
		_r *= float(e["hit_r"])
		xp_value *= float(e["xp"])
		# 紫色**覆盖**词缀染色而非混色: 染色优先级是 flash > status > _affix_tint,
		# 混色会让"疾风青 + 精英紫"变灰白 → 单一颜色才能让「紫 = 精英」成为可靠识别信号
		_affix_tint = Color(e["tint"])

	# 新怪行为参数读表(ENEMY_BASE 同表共读, 图鉴/实战一致)
	if kind == Kind.BREATH:
		_breath_n_min = int(base.get("breath_n_min", 3))
		_breath_n_max = int(base.get("breath_n_max", 5))
		_breath_range = float(base.get("breath_range", 130.0))
		_breath_speed = float(base.get("breath_speed", 110.0))
		_breath_cd_full = float(base.get("breath_cd", 2.4))
		_breath_cd = 0.8   # 落地 0.8s 后才第一次蓄力: 给玩家反应窗口, 不"出场即喷脸"
	elif kind == Kind.BOMBER:
		_boom_r = float(base.get("boom_r", 46.0))
		_boom_dmg = float(base.get("boom_dmg", 26.0))
		_fuse_t = float(base.get("fuse_t", 0.4))
		_fuse_range = float(base.get("fuse_range", 34.0))
	elif kind == Kind.SHIELD:
		_shield_max = float(base.get("shield_hp", 60.0))
		_shield_hp = _shield_max
		_shield_arc = float(base.get("shield_arc", 120.0))
		_shield_reduce = float(base.get("shield_reduce", 0.7))
		_shatter_bonus = float(base.get("shatter_bonus", 0.5))
		_shatter_dur = float(base.get("shatter_t", 6.0))
		_face = Vector2.ZERO   # _tick_shield 首帧会初始化为朝向玩家; 零向量 = 哨兵值

	_max_hp = hp   # 再生回血封顶(必须在所有乘数之后)
	_ensure_visual()


# 单条词缀的数值/行为/染色。精英会调两次 → 行为参数必须 has() 守卫:
# 它们是赋值不是累加, 若照搬旧的 a.get("regen", 0.0) 写法, "再生+分裂"的第二条
# 会把第一条的 _regen 用默认 0 覆盖掉(词缀静默失效, 数值不诚实)
func _apply_affix(a: String) -> void:
	if a == "" or not GameManager.ENEMY_AFFIXES.has(a):
		return
	var d: Dictionary = GameManager.ENEMY_AFFIXES[a]
	var m: Dictionary = d.get("mult", {})
	hp *= float(m.get("hp", 1.0))
	speed *= float(m.get("speed", 1.0))
	_r *= float(m.get("size", 1.0))
	if d.has("regen"):
		_regen = float(d["regen"])
	if d.has("interval"):
		_fire_interval = float(d["interval"])
	if d.has("split"):
		_split = int(d["split"])
	if d.has("explode_r"):
		_explode_r = float(d["explode_r"])
	if d.has("explode_dmg"):
		_explode_dmg = float(d["explode_dmg"])
	_affix_tint = Color(d.get("color", Color(1, 1, 1)))


func collision_radius() -> float:
	return _r


func _ready() -> void:
	add_to_group("enemies")
	_ensure_visual()


func _ensure_visual() -> void:
	if sprite == null:
		sprite = AnimatedSprite2D.new()
		sprite.name = "Sprite2D"
		var frames: SpriteFrames = GameManager.frames_for(
			"enemy%d" % kind, GameManager.ENEMY_FRAMES[kind])
		if frames.get_animation_names().is_empty():
			# 素材缺失兜底: 单帧圆形占位, 保证实体仍可见
			frames.add_animation("run")
			frames.add_frame("run", GameManager.circle_texture(8, color))
		sprite.sprite_frames = frames
		add_child(sprite)
	# 池复用后 kind 可能变化, 每次 setup 重绑帧表并从头播
	sprite.sprite_frames = GameManager.frames_for("enemy%d" % kind, GameManager.ENEMY_FRAMES[kind])
	# 缩放乘法链: 每 kind 基准(骷髅帧格 52×54 需缩到与其他怪同视觉重量) × 词缀 size × 精英 size
	# offset 必须无条件复位 —— 否则骷髅的 -3 会残留在下一次复用的史莱姆身上(表现为"怪飘空")
	var v: Dictionary = GameManager.ENEMY_VISUAL.get(kind, {})
	var s: float = float(v.get("scale", 1.0))
	sprite.offset = Vector2(v.get("offset", Vector2.ZERO))
	for a in [affix, affix2]:
		if a != "" and GameManager.ENEMY_AFFIXES.has(a):
			s *= float(GameManager.ENEMY_AFFIXES[a]["mult"].get("size", 1.0))
	if is_elite:
		s *= float(GameManager.ELITE_BASE["size"])
	sprite.scale = Vector2.ONE * s
	sprite.play(&"run")
	# 精英光环: 只建一次并钉在子节点树最底(贴地光晕不得盖住本体);
	# visible 无条件复位 —— setup 与 _ready 都走这条, 池复用不漏(漏了就是"普通怪带紫光环")。
	if _aura == null:
		_aura = EliteAura.new()
		add_child(_aura)
		move_child(_aura, 0)
	_aura.visible = is_elite
	# 精英头顶词缀副标(打磨#7): 名字实时拼(池复用 kind/affix 都变), visible 无条件复位。
	# 只给精英挂 —— 普通词缀怪的染色已足够识别, 满屏 Label 反而糊脸。
	if _elite_label == null:
		_elite_label = Label.new()
		_elite_label.add_theme_font_size_override("font_size", 8)
		_elite_label.add_theme_color_override("font_color", Color(1.0, 0.88, 1.0))
		_elite_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_elite_label.add_theme_constant_override("outline_size", 2)
		_elite_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_elite_label)
	var label_txt := ""
	for a in [affix, affix2]:
		if a != "" and GameManager.ENEMY_AFFIXES.has(a):
			if label_txt != "":
				label_txt += "·"
			label_txt += str(GameManager.ENEMY_AFFIXES[a]["name"])
	_elite_label.text = label_txt if label_txt != "" else str(GameManager.ELITE_BASE["name"])
	_elite_label.visible = is_elite
	if is_elite:
		# 钉在头顶: 帧格半高 × 总缩放(词缀/精英 size 链已乘进 sprite.scale) + 4px 抬离
		var fh: float = float(GameManager.ENEMY_FRAMES[kind][0][3])
		var top_y: float = sprite.offset.y - fh * sprite.scale.y * 0.5 - 4.0
		_elite_label.position = Vector2(-32.0, top_y - 10.0)
		_elite_label.size = Vector2(64, 10)
		_elite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if GameManager.player == null:
		return

	# 精英光环相位: 父驱动子(理由见 EliteAura 类注释)。非精英直接跳过 —— 池里预分配的
	# 数百个隐藏节点每帧都走这条函数, 这里多一次判断比让它们各自空跑 _draw 便宜得多。
	if is_elite and _aura != null:
		_aura.advance(delta)

	# 状态效果结算: DoT + 定身判定 + 染色; spd_mult=0 表示冰冻/眩晕定身
	var spd_mult: float = StatusFx.tick(_status, self, delta)

	# 再生词缀: 缓慢回血(封顶), 被控住也回(回血不是"行动")
	if _regen > 0.0 and not _dead:
		hp = minf(hp + _regen * delta, _max_hp)

	# 追踪玩家: 目标速度方向 + 平滑转向(lerp), 转向圆润不瞬切
	var p := GameManager.player
	var to_player := p.global_position - global_position
	# 诅咒速度: 乘在每帧(与 enemy_speed_mult 同位置), 局内加诅咒立刻对全场在屏敌人生效,
	# 不必等下一只怪出生 —— 玩家能即时感到"我刚刚把怪变快了"
	var sp: float = speed * GameManager.enemy_speed_mult() * GameManager.curse_speed_mult() * spd_mult
	var target_vel := Vector2.ZERO
	if to_player.length() > 0.0001:
		target_vel = to_player.normalized() * sp
	# 新怪行为 override(kind 4/5/6): 返回该怪本帧的目标速度(可站定/后撤/照常追击)
	match kind:
		Kind.BREATH:
			target_vel = _tick_breath(delta, to_player, sp)
		Kind.BOMBER:
			target_vel = _tick_bomber(delta, to_player, sp)
		Kind.SHIELD:
			target_vel = _tick_shield(delta, to_player, sp)
	# 转向惯性: 390≈0.06s 追平目标速度(跟手且不摆尾); 减速比提速稍慢, 掉头更自然
	var turn := 390.0 if target_vel.length_squared() >= _vel.length_squared() else 240.0
	_vel = _vel.move_toward(target_vel, turn * delta)
	global_position += _vel * delta
	# 击退冲量: 每帧按指数衰减, 叠加到位移(受击后短暂被推开, 再回归追踪)
	if _knockback.length_squared() > 1.0:
		global_position += _knockback * delta
		_knockback = _knockback.move_toward(Vector2.ZERO, _knockback.length() * 6.0 * delta)
	# 朝向翻转(像素素材默认朝右)
	sprite.flip_h = to_player.x < 0.0

	# 接触伤害(圆距)
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	# 染色: 受击闪帧优先(白/灰交替), 否则显示状态色(冰冻蓝/燃烧橙/中毒绿/眩晕黄)
	if _flash > 0.0:
		_flash -= delta
		sprite.modulate = Color(1, 1, 1) if int(_flash * 20) % 2 == 0 else Color(0.5, 0.5, 0.5)
	elif kind == Kind.BOMBER and _fuse >= 0.0:
		# 引信闪烁: 红色高频交替(~15Hz), 盖过状态色 —— "要炸了"是最高优先级阅读信号,
		# 被冰冻/燃烧也不能把它藏起来
		sprite.modulate = Color(1.0, 0.25, 0.25) if int(_fuse * 30.0) % 2 == 0 else Color(1.0, 0.55, 0.35)
	else:
		# 状态色优先(冰冻蓝/燃烧橙...), 无状态时用词缀色(疾风青/坚韧橙...), 都无则白
		var st: Color = StatusFx.tint_color(_status)
		sprite.modulate = st if not st.is_equal_approx(Color(1, 1, 1)) else _affix_tint
	# 定身(冰冻/眩晕)时冻结动画, 强化"被控住"的观感
	if spd_mult <= 0.0:
		sprite.pause()
	else:
		if not sprite.is_playing():
			sprite.play(&"run")

	# 控制状态(冰冻/眩晕)下不能发起接触伤害
	if StatusFx.blocks_action(_status):
		return
	if global_position.distance_to(p.global_position) < _r + GameManager.PLAYER_RADIUS:
		if _attack_cooldown <= 0.0:
			p.take_damage(damage, self)   # source 当前无消费方(荆棘反伤已随商店改版删除), 保留形参备将来用
			_attack_cooldown = 1.0
			# 撞击后微退
			global_position += (global_position - p.global_position).normalized() * 9.0

	# 射手词缀: 距玩家一段距离时开火(不贴身射, 保留风筝空间); 走动中周期性发射敌弹
	if _fire_interval > 0.0:
		_fire_timer -= delta
		if _fire_timer <= 0.0 and to_player.length() > _r + 60.0:
			_fire_timer = _fire_interval
			_fire()


func _fire() -> void:
	var p := GameManager.player
	if p == null:
		return
	var dir := (p.global_position - global_position).normalized()
	# 复用敌弹(team="enemy"), 伤害取敌人 damage 的 0.75(远程较接触弱)
	ObjectPool.spawn_bullet(global_position + dir * (_r + 4.0), dir * 110.0, damage * 0.75, "enemy", 0)


# ================= kind 4/5/6 行为(吐息 / 自爆 / 护盾) =================

# 吐息: 追击 → (距离≤_breath_range 且冷却好)站定 0.6s 蓄力 → 扇形喷 3~5 发短程弹
#       → 后撤 0.8s 拉距 → 循环。蓄力/后撤期间若被拉出射程则直接恢复追击。
# 返回本帧目标速度(与主追踪段同构, 只是方向/大小按状态机改)
func _tick_breath(delta: float, to_player: Vector2, sp: float) -> Vector2:
	var dist := to_player.length()
	if _bstate == 0:
		_breath_cd -= delta
		if _breath_cd <= 0.0 and dist <= _breath_range and dist > 0.0001:
			_bstate = 1
			_b_timer = 0.6   # 蓄力时长(弹前摇, 玩家可横移躲)
		return to_player.normalized() * sp if dist > 0.0001 else Vector2.ZERO
	if _bstate == 1:
		_b_timer -= delta
		if dist > _breath_range * 1.25:
			_bstate = 0      # 拉出射程: 吐息落空, 回到追击
			_breath_cd = 1.0
			return to_player.normalized() * sp
		if _b_timer <= 0.0:
			_breath()
			_bstate = 2
			_b_timer = 0.8
		return Vector2.ZERO  # 站定蓄力
	# 后撤态
	_b_timer -= delta
	if _b_timer <= 0.0 or dist < 20.0:
		_bstate = 0
		_breath_cd = _breath_cd_full
	# 后撤: 沿远离玩家方向走(速度打 0.8 折, 保持压迫但不脱离战场)
	return -to_player.normalized() * sp * 0.8 if dist > 0.0001 else Vector2.ZERO


func _breath() -> void:
	var p := GameManager.player
	if p == null:
		return
	GameManager.play_sfx("shoot")
	var n: int = GameManager._rng.randi_range(_breath_n_min, _breath_n_max)
	var base_a := (p.global_position - global_position).normalized().angle()
	var arc := deg_to_rad(50.0)
	for i in range(n):
		var a := base_a + (float(i) - float(n - 1) / 2.0) * arc / float(maxi(n - 1, 1))
		ObjectPool.spawn_bullet(
			global_position + Vector2.from_angle(a) * (_r + 3.0),
			Vector2.from_angle(a) * _breath_speed,
			damage, "enemy", 0)


# 自爆: 高速冲锋; 进入 _fuse_range 引爆引信(站定闪红 _fuse_t 秒)→ 爆炸 AOE + 自毁(不掉奖励)。
# 引信一旦点燃不熄灭(玩家跑出去也炸, 只是炸空)—— "看见红光往侧向跑" 是核心阅读。
func _tick_bomber(delta: float, to_player: Vector2, sp: float) -> Vector2:
	var dist := to_player.length()
	if _fuse < 0.0:
		if dist <= _fuse_range:
			_fuse = _fuse_t
			GameManager.play_sfx("elite")   # 引信点燃音(复用精英音, 短促有辨识度)
		return to_player.normalized() * sp if dist > 0.0001 else Vector2.ZERO
	_fuse -= delta
	if _fuse <= 0.0:
		_detonate()
		return Vector2.ZERO
	return Vector2.ZERO   # 引信期间站定


func _detonate() -> void:
	if _dead:
		return
	_dead = true
	GameManager.play_sfx("death")
	GameManager.spawn_effect(global_position, Color(1.0, 0.4, 0.15), 22, _boom_r * 1.4)
	GameManager.spawn_burst(global_position, Color(1.0, 0.5, 0.2), 1.6)
	if GameManager.player != null and \
		global_position.distance_to(GameManager.player.global_position) < _boom_r + GameManager.PLAYER_RADIUS:
		GameManager.player.take_damage(_boom_dmg, self)
	# 自爆身亡: 不计击杀、不掉经验金币(设计意图: 杀它没收益, 让它炸空才是正解)
	GameManager.enemies.erase(self)
	ObjectPool.release(self)


# 护盾: 照常追击, 但举盾朝向 _face 以 ~1.0 rad/s 慢转向玩家 —— 玩家绕圈快于盾转就能打背。
# 盾挡(正面来伤减 70%)在 take_damage 判定; 盾值打空 → 破盾易伤 _shatter_t 秒后重立。
func _tick_shield(delta: float, to_player: Vector2, sp: float) -> Vector2:
	if _face.length_squared() < 0.0001:
		_face = to_player.normalized() if to_player.length() > 0.0001 else Vector2.RIGHT
	if _shatter_t > 0.0:
		_shatter_t -= delta
		if _shatter_t <= 0.0:
			_shield_hp = _shield_max   # 冷却结束重立满盾
	# 破盾期间不再转向(盾没了举什么举), 有盾时慢转跟玩家
	if _shield_hp > 0.0 and to_player.length() > 0.0001:
		var want := to_player.normalized().angle()
		var cur := _face.angle()
		var diff := wrapf(want - cur, -PI, PI)
		_face = Vector2.from_angle(cur + clampf(diff, -1.0 * delta, 1.0 * delta))
	return to_player.normalized() * sp if to_player.length() > 0.0001 else Vector2.ZERO


# 外部施加击退冲量(旋刃等强击退武器用): 乘到基础击退方向, 反复命中可累积
func add_knockback(dir: Vector2, strength: float) -> void:
	if dir.length() > 0.01:
		_knockback += dir.normalized() * strength


func take_damage(amount: float, from_dot: bool = false) -> void:
	if _dead:
		return
	var is_crit := false
	# 冰冻易伤: 被冻住的敌人受到的非 DoT 伤害 +30%(鼓励先控后爆发)
	if not from_dot:
		amount *= StatusFx.damage_taken_mult(_status)
		# 面具客「处决」: 对生命低于 25% 的敌人伤害 +40%(处决残血收尾)
		if GameManager.current_character == "assassin" and _max_hp > 0.0 and hp < _max_hp * 0.25:
			amount *= 1.4
		# 暴击: 商店「致命一击」按概率 2 倍(统一在受击端, 覆盖所有武器伤害)
		var pre: float = amount
		amount = GameManager.roll_crit(amount)
		is_crit = amount > pre + 0.01
		# 盾卫巨魔(kind 6): 正面 _shield_arc 度内来伤被盾挡掉 _shield_reduce(盾值扣原始伤害),
		# 绕到侧面/背面吃全额。盾值打空 → 破盾易伤窗口(_shatter_dur 秒全程受伤 +_shatter_bonus)。
		# 只在非 DoT 直伤判定: 灼烧/中毒是环境伤害, 不该被"举盾朝向"过滤, 否则绕背攻略被 DoT 稀释。
		if kind == Kind.SHIELD:
			if _shield_hp > 0.0 and GameManager.player != null:
				var to_attk: Vector2 = (GameManager.player.global_position - global_position).normalized()
				if _face.dot(to_attk) > cos(deg_to_rad(_shield_arc * 0.5)):
					_shield_hp -= amount
					amount *= 1.0 - _shield_reduce
					if _shield_hp <= 0.0:
						_shatter_t = _shatter_dur
						GameManager.play_sfx("hit")
						GameManager.spawn_effect(global_position, Color(0.55, 0.75, 1.0), 14, 42.0)
			elif _shatter_t > 0.0:
				amount *= 1.0 + _shatter_bonus
	hp -= amount
	_flash = 0.1
	# 漂浮伤害数字: DoT 走小号暗色; 暴击金字大号, 大伤害(≥30)走大号白
	var num := ObjectPool.spawn_damage_number(global_position + Vector2(0, -_r - 4.0), amount, is_crit)
	if from_dot and num != null:
		num.tint(Color(1.0, 0.7, 0.4))   # DoT 染暖色, 与直伤区分
	# 子弹直伤命中: 按玩家道具 proc 概率掷骰施加状态(DoT 不再二次触发)
	if not from_dot:
		StatusFx.try_proc_from_player(_status, amount)
	# 击退: 沿远离玩家方向推开(所有伤害来自玩家武器/光环); DoT 不击退
	if not from_dot and GameManager.player != null:
		var dir: Vector2 = global_position - GameManager.player.global_position
		if dir.length() > 0.01:
			dir = dir.normalized()
		else:
			dir = Vector2.UP
		_knockback += dir * 70.0   # 基础击退冲量
	if hp <= 0.0:
		die()


func die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	GameManager.kills += 1
	GameManager.check_achievements()   # 击杀类成就(首杀/500 杀)在击杀事件点检查
	GameManager.play_sfx("kill")
	GameManager.spawn_effect(global_position, color, 10, 35.0)
	GameManager.spawn_burst(global_position, color, 1.0)
	spawn_gems()
	# 自爆词缀: 死亡时对圈内玩家造成伤害(AOE), 强制玩家别贴脸收割
	if _explode_r > 0.0:
		GameManager.spawn_effect(global_position, Color(1.0, 0.35, 0.2), 16, 90.0)
		if GameManager.player != null and \
			global_position.distance_to(GameManager.player.global_position) < _explode_r + GameManager.PLAYER_RADIUS:
			GameManager.player.take_damage(_explode_dmg, self)
	# 分裂词缀: 死亡分裂成 _split 只同种小怪(体型缩小、无词缀, 避免无限分裂)
	if _split > 0:
		for i in range(_split):
			var a := TAU * float(i) / float(_split)
			# 子代显式清空词缀/精英: 默认参数虽也是空, 但这里必须让"子代永不继承"写在调用点上 ——
			# 子代带 split 会无限分裂, 带 elite 会让精英数量指数爆炸且绕过波次门槛。
			var e := ObjectPool.spawn_enemy(kind, global_position + Vector2.from_angle(a) * 16.0, "", "", false)
			e.scale_split_offspring()
	GameManager.enemies.erase(self)
	ObjectPool.release(self)


# 波末清场专用: 不计击杀/不掉经验金币/不触发词缀(自爆分裂), 直接静默回收
func die_without_reward() -> void:
	if _dead:
		return
	_dead = true
	GameManager.enemies.erase(self)
	ObjectPool.release(self)


# 分裂子体: 缩小体型 + 减半攻防(轻量小怪), 别继承词缀防递归爆炸
func scale_split_offspring() -> void:
	_is_offspring = true   # 标记与 Boss 召唤物区分(召唤物走 spawn_enemy 直出, 不经此函数)
	hp *= 0.4
	_max_hp = hp   # 同步封顶/处决阈值基准, 别沿用父体血量
	damage *= 0.5
	speed *= 1.2
	_r *= 0.7
	xp_value *= 0.5
	if sprite != null:
		sprite.scale *= 0.7


func spawn_gems() -> void:
	var gm = GameManager
	# 宝石**颗数** = int(xp_value)(史莱姆/蝙蝠 1, 巨魔 8; 精英双词缀 ×1.69 再 ×3, 一只可达 40 颗) ——
	# 颗数只决定视觉密度与图鉴「经验宝石 ×N」文案, 也顺带决定忍者蛙「拾穗」的每颗回血频率, 故不动它。
	# **每颗的值 = xp_value / count**(2026-09-10 修): 原先每颗写死 1.0, 于是 int() 把小数静默截掉,
	# 两处数值不诚实 —— (a) 词缀怪 ×1.3 对 xp=1~2 的主流杂兵**完全无效**(史莱姆 1.3→1、骷髅 2.6→2),
	# 图鉴明写「词缀怪经验 ×1.3」玩家却拿不到, 风险给了回报没给; (b) 分裂子代 ×0.5 让 xp=1 的怪
	# 变成 0.5 → **0 颗宝石**, 图鉴说「经验减半」实际是「经验清零」。
	# 摊到每颗后总量精确等于 xp_value, 颗数与拾穗节奏不变 => 只补回该给的经验, 不改手感。
	var count := maxi(int(xp_value), 1 if xp_value > 0.0 else 0)
	var per: float = xp_value / float(count) if count > 0 else 0.0
	for i in range(count):
		ObjectPool.spawn_gem(global_position + Vector2(gm._rng.randf_range(-10, 10), gm._rng.randf_range(-10, 10)), per)
	# 金币掉落: 普通怪 1~2, 巨魔 3 枚大额(4)必掉; 供波间商店消费
	var coin_n := 1
	var coin_v := 1
	if kind != Kind.TROLL:
		coin_n = 1 if gm._rng.randf() < 0.6 else 2
		coin_v = 1
	else:
		coin_n = 3
		coin_v = 4
	for i in range(coin_n):
		ObjectPool.spawn_coin(global_position + Vector2(gm._rng.randf_range(-12, 12), gm._rng.randf_range(-12, 12)), coin_v)
	# 巨魔额外掉落: 红药/宝箱/念珠/磁铁(强力道具低概率, 作为中后期惊喜)
	# 诅咒把四项掉率整体抬 curse_drop_bonus()(L=10 → +20%): 回报侧与金币/经验同一旋钮
	if kind == Kind.TROLL:
		var rng := GameManager._rng
		var db: float = GameManager.curse_drop_bonus()
		# 静谧事件(drop_mult=0)整列乘 0: 喘息波不掉任何道具, 与金币/经验归零同一语义
		var dm: float = GameManager.wc_f("drop_mult", 1.0)
		if rng.randf() < (0.30 + db) * dm:
			ObjectPool.spawn_pickup(global_position, "heart")
		if rng.randf() < (0.10 + db) * dm:
			ObjectPool.spawn_pickup(global_position, "chest")
		if rng.randf() < (0.04 + db) * dm:
			ObjectPool.spawn_pickup(global_position, "rosary")
		if rng.randf() < (0.04 + db) * dm:
			ObjectPool.spawn_pickup(global_position, "magnet")
	# 精英掉落: 3 枚大额金币(12/枚, coin.gd 的 huge 档画得更亮更大) + 25% 宝箱。
	# 宝箱 = 一次三选一(pickup.gd 的 "chest" → trigger_level_up), 与诅咒道具形成正反馈:
	# 打精英 → 三选一 → 可能抽到诅咒道具 → 更多精英。36 基础金 ×L10 诅咒 ×2.80 ≈ 101 金,
	# 够买 2 件商店货 + 1 次刷新 —— 强激励, 但 ≤4.1% 出率保证经济不崩。
	if is_elite:
		var e: Dictionary = GameManager.ELITE_BASE
		for i in range(int(e["coin_n"])):
			ObjectPool.spawn_coin(global_position + Vector2.from_angle(TAU * float(i) / 3.0) * 10.0, int(e["coin_value"]))
		if GameManager._rng.randf() < float(e["item_drop"]):
			ObjectPool.spawn_pickup(global_position + Vector2(0, -8), "chest")


# 精英光环: 贴地呼吸双环(外环紫色主色 + 内环金色点缀), 画在敌人子节点树最底 → 不遮本体。
# 半径/速度直接读 ELITE_BASE(打磨#2: 原 const 硬编码 22.0/1.6, 与表双源必漂移)。
# **相位由父节点驱动, 本类不自持 _process**(2026-09-10 修): 原版每帧 _process + queue_redraw,
# 而 ObjectPool 的 set_process(false) 只关父节点 —— Godot 不级联到子节点(实测父 visible=false
# 也不给子发 NOTIFICATION_VISIBILITY_CHANGED)。后果是敌人池预分配的 300 个节点各挂一个光环,
# 即使全程隐藏也每帧空跑 300 次 _draw(两次逐像素 ring)。改由 enemy._physics_process 调
# advance() 后, 非精英与池释放态的开销归零(父停子停), 且不必维护任何额外的 process 开关。
class EliteAura extends Node2D:
	var _t := 0.0

	# 父节点每帧调一次(仅精英怪); 自持相位不复用 enemy 字段, 池复用时残留的 _t 只影响
	# sin() 起点, 外观上不可察觉
	func advance(delta: float) -> void:
		_t += delta * float(GameManager.ELITE_BASE["aura_speed"])
		queue_redraw()

	func _draw() -> void:
		var k := sin(_t)                          # -1..1 呼吸相位
		var e: Dictionary = GameManager.ELITE_BASE
		var base: Color = e["tint"]
		# 主环: 半径与透明度同相位呼吸(alpha 0.15..0.55, 像素风保持低饱和不抢本体)
		PixelUtils.ring(self, Vector2.ZERO, float(e["aura_r"]) + k * 3.0, 1.5,
			Color(base.r, base.g, base.b, 0.35 + 0.20 * k))
		# 点缀环: 反相位小内环, 呼吸错开让光环"有厚度"; 金色与紫主环互补提识别度
		PixelUtils.ring(self, Vector2.ZERO, 9.0 - k * 1.5, 1.0,
			Color(1.0, 0.85, 0.30, 0.40 - 0.12 * k))