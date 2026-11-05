extends Node2D
## Boss — 深渊领主; 简单状态机: 追击 → 冲撞 → 弹幕 → 召唤 循环
## 120s 登场, 击杀掉大量奖励

signal died(boss_node)

enum BossState { CHASE, CHARGE, BARAGE, SUMMON }

const BOSS_SPRITE_SCALE := 1.45   # big_demon 32×36 → 约 46×52, 比原骷髅更有压迫感

var hp: float = 2000.0
var max_hp: float = 2000.0
var speed: float = 25.0
var damage: float = 30.0
var _r: float = 24.0

var state: int = BossState.CHASE
var state_timer: float = 3.0
var _attack_cooldown: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _summon_timer: float = 12.0
var _flash: float = 0.0
var appearance: int = 1
var _dead: bool = false
var is_final: bool = false              # 终极 Boss 标记(击杀即通关)
var _base_tint: Color = Color(1, 1, 1)  # 非闪帧基础色调(终极 Boss 染红)
var _phase: int = 0                     # 终极 Boss 血量阶段 0/1/2(中 Boss 恒 0)
var _barage_mode: int = 0               # 弹幕轮转游标: 0 环 / 1 扇 / 2 瞄(严格轮转, 玩家可学节奏)

var sprite: AnimatedSprite2D = null
var _vel: Vector2 = Vector2.ZERO   # 追击段平滑速度(起停/转向不突变)
var _status := {}   # 状态效果(见 status_fx.gd); Boss 抗性: 持续时间 ×0.4


func setup(appearance_count: int) -> void:
	appearance = appearance_count
	_dead = false
	_vel = Vector2.ZERO
	_status.clear()   # 池复用清残留状态
	# 数值读 GameManager.BOSS_BASE(与图鉴共读); 血量按登场次数每次 +hp_step
	var b: Dictionary = GameManager.BOSS_BASE
	max_hp = float(b["hp"]) * (1.0 + float(appearance - 1) * float(b["hp_step"]))
	hp = max_hp
	# 速度/伤害/半径也必须在这里复位: make_final 会改写它们, 池复用时否则残留终极 Boss 的值
	speed = float(b["speed"])
	damage = float(b["damage"])
	_r = float(b["radius"])
	state = BossState.CHASE
	state_timer = float(b["state_cd"])
	_attack_cooldown = 0.0
	_summon_timer = float(b["summon_cd"])
	_flash = 0.0
	is_final = false
	_base_tint = Color(1, 1, 1)
	# 阶段/轮转复位: make_final 与 _enter_phase 会改写它们, 池复用漏一处
	# = 下一局中 Boss 出场即 2 阶狂暴 / 弹幕从瞄准起手。
	_phase = 0
	_barage_mode = 0
	_ensure_visual()   # 内部已把 sprite.scale 复位到 BOSS_SPRITE_SCALE(覆盖终极形态的放大)


# 终极 Boss: 更高血量/伤害, 体型放大 + 红色调; 由 spawner 在 setup 后调用
func make_final() -> void:
	var f: Dictionary = GameManager.BOSS_FINAL
	is_final = true
	max_hp = float(f["hp"])
	hp = max_hp
	speed = float(f["speed"])
	damage = float(f["damage"])
	_base_tint = Color(f["tint"])
	# 与 setup 同字段复位(make_final 总在 setup 后调, 这里是防御性双保险):
	# 终极 Boss 必须从 0 阶起步, 否则池里捞到带残留阶段的实例 = 出场即狂暴
	_phase = 0
	_barage_mode = 0
	if sprite != null:
		# 终极 Boss 在恶魔基准(BOSS_SPRITE_SCALE)上再放大
		sprite.scale = Vector2.ONE * float(f["sprite_scale"])


func collision_radius() -> float:
	return _r


func _ensure_visual() -> void:
	if sprite == null:
		sprite = AnimatedSprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)
	var frames: SpriteFrames = GameManager.frames_for("boss", GameManager.BOSS_FRAMES)
	if frames.get_animation_names().is_empty():
		frames.add_animation("idle")
		frames.add_frame("idle", GameManager.circle_texture(16, Color(0.6, 0.1, 0.9)))
	sprite.sprite_frames = frames
	# 体型复位: make_final 会放大, 池复用时由这里(每次 setup 都调)拉回基准
	sprite.scale = Vector2.ONE * BOSS_SPRITE_SCALE
	sprite.play(&"idle")


func _ready() -> void:
	add_to_group("enemies")
	_ensure_visual()


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	if GameManager.player == null:
		return

	# 血量阶段检测放**最开头、定身冻结 return 之前**: 冰冻时 DoT 照样削血, 阈值在冻结期间
	# 就该跨过 —— 若放冻结判定之后, 解冻瞬间补触发会突兀(玩家看到 Boss 突然变色加速)。
	# 不放 take_damage 里: 那里有暴击/状态抗性路径, 会与伤害数字抢同一帧。
	# 无需防重入标志: _enter_phase 内 _phase += 1 后阈值数组已指向下一档, 同帧不可能再触发。
	if is_final and _phase < 2:
		if hp <= max_hp * float(GameManager.BOSS_FINAL["phase_hp"][_phase]):
			_enter_phase()

	# 状态效果结算: DoT + 定身判定; Boss 抗性(时长 ×0.4)在 take_damage 的 proc 里传入
	var spd_mult: float = StatusFx.tick(_status, self, delta)

	# 染色: 受击闪帧优先; 有状态时用状态色(冰冻蓝/燃烧橙...), 否则用基础色调
	if _flash > 0.0:
		_flash -= delta
		sprite.modulate = _base_tint if int(_flash * 20) % 2 == 0 else _base_tint.darkened(0.5)
		if sprite.animation != &"hit":
			sprite.play(&"hit")
	else:
		var tint := StatusFx.tint_color(_status)
		sprite.modulate = _base_tint if tint.is_equal_approx(Color(1, 1, 1)) else tint
		if sprite.animation != &"idle":
			sprite.play(&"idle")

	# 定身(冰冻/眩晕)下 Boss 冻结: 不推进状态机、不移动、不接触伤害、不施法/召唤
	if spd_mult <= 0.0:
		return

	state_timer -= delta
	_summon_timer -= delta

	match state:
		BossState.CHASE:
			var p := GameManager.player
			var tp := p.global_position - global_position
			var target := tp.normalized() * speed
			_vel = _vel.move_toward(target, 120.0 * delta)
			global_position += _vel * delta
			_try_contact_damage(delta)
			if state_timer <= 0.0:
				state = BossState.CHARGE
				_charge_dir = tp.normalized()
				state_timer = 1.0    # 蓄力
		BossState.CHARGE:
			# 蓄力(不动); 蓄力完 0.5s 快速冲撞
			if state_timer > -0.5:
				pass
			else:
				global_position += _charge_dir * speed * 6.0 * delta
				_try_contact_damage(delta)
			if state_timer <= -1.0:
				state = BossState.BARAGE
				state_timer = 2.0
		BossState.BARAGE:
			_do_barage()
			state = BossState.SUMMON
			state_timer = 1.0
		BossState.SUMMON:
			_try_contact_damage(delta)
			if state_timer <= 0.0:
				_do_summon()
				state = BossState.CHASE
				state_timer = float(GameManager.BOSS_BASE["state_cd"])   # re-arm 读表(原硬编码 3.0)

	# 周期性召唤: 间隔读表并随阶段收紧(12s → 10.4s → 9.1s), 数量随阶段 +1
	if _summon_timer <= 0.0:
		var b: Dictionary = GameManager.BOSS_BASE
		_summon_timer = float(b["summon_cd"]) / (1.0 + float(_phase) * 0.15)
		_spawn_minions(int(b["summon_count"]) + _phase * int(GameManager.BOSS_FINAL["phase_summon_extra"]), _phase >= 1)


func _try_contact_damage(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	var p := GameManager.player
	if global_position.distance_to(p.global_position) < _r + GameManager.PLAYER_RADIUS:
		if _attack_cooldown <= 0.0:
			p.take_damage(damage, self)   # source 当前无消费方(荆棘反伤已随商店改版删除), 保留形参备将来用
			_attack_cooldown = float(GameManager.BOSS_BASE["contact_cd"])   # 读表(原硬编码 1.0)


# 弹幕严格轮转 环→扇→瞄(非随机: 玩家可学习节奏, 战报/截图可复现)。
# 中 Boss 同样生效(_barage_mode 在 setup 复位, _phase 恒 0)→ 三次登场手感不再重复,
# 但环仍 12 发、召唤仍 2 只, 难度增量温和。
func _do_barage() -> void:
	GameManager.add_shake(4.0)
	GameManager.play_sfx("shoot")
	var b: Dictionary = GameManager.BOSS_BASE
	match _barage_mode:
		1: _do_barage_fan(b)
		2: _do_barage_aim(b)
		# 虚空事件给环形弹幕 +4 发(barage 因子; 只加环不加扇/瞄, 环是唯一"无死角"弹幕, 加它才有压迫感)
		_: _do_barage_ring(int(b["barage_count"]) + _phase * int(GameManager.BOSS_FINAL["phase_barage_extra"]) + int(GameManager.wc_f("barage", 0.0)), b)
	_barage_mode = (_barage_mode + 1) % 3


# 环形弹幕: 均匀一圈, 数量随终极 Boss 阶段 12 → 16 → 20
func _do_barage_ring(n: int, b: Dictionary) -> void:
	for i in range(n):
		var a := TAU * float(i) / float(n)
		_spawn_enemy_bullet(global_position, Vector2.from_angle(a) * float(b["barage_speed"]), float(b["barage_dmg"]))


# 扇形弹幕: 5 发朝玩家的窄扇面(arc 0.9 rad ≈ 51.6°), 侧移可躲 —— 考验走位而非反应
func _do_barage_fan(b: Dictionary) -> void:
	var base := (GameManager.player.global_position - global_position).normalized().angle()
	var n: int = int(b["barage_fan_count"])
	var arc: float = float(b["barage_fan_arc"])
	for i in range(n):
		var a := base + (float(i) - float(n - 1) / 2.0) * arc / float(n - 1)
		_spawn_enemy_bullet(global_position, Vector2.from_angle(a) * float(b["barage_fan_speed"]), float(b["barage_fan_dmg"]))


# 瞄准三连: 3 发小夹角快弹(speed 120 比环快 50%), 唯一需要预判走位的弹幕
func _do_barage_aim(b: Dictionary) -> void:
	var base := (GameManager.player.global_position - global_position).normalized().angle()
	var n: int = int(b["barage_aim_count"])
	var spread: float = float(b["barage_aim_spread"])
	for i in range(n):
		var a := base + (float(i) - float(n - 1) / 2.0) * spread
		_spawn_enemy_bullet(global_position, Vector2.from_angle(a) * float(b["barage_aim_speed"]), float(b["barage_aim_dmg"]))


# 终极 Boss 跨阈值进阶: 属性乘算 + 变色 + 震屏 + 一波"见面礼"(召唤 + 环弹幕)。
# 防同帧重入靠 _phase += 1: 阈值数组 phase_hp[_phase] 随即指向下一档, 本帧不可能再触发。
func _enter_phase() -> void:
	_phase += 1
	var f: Dictionary = GameManager.BOSS_FINAL
	var b: Dictionary = GameManager.BOSS_BASE
	speed *= float(f["phase_speed_mult"])
	damage *= float(f["phase_damage_mult"])
	_r *= 1.06
	# 染深红但不完全覆盖原 tint: lerp 0.35 让阶段 1/2 有可辨的"更红"层次
	_base_tint = Color(f["phase_tint"]).lerp(_base_tint, 0.35)
	GameManager.add_shake(8.0)
	GameManager.play_sfx("elite")
	_spawn_minions(int(b["summon_count"]) + _phase * int(f["phase_summon_extra"]), bool(f["phase_summon_affix"]))
	_do_barage_ring(int(b["barage_count"]) + _phase * int(f["phase_barage_extra"]) + int(GameManager.wc_f("barage", 0.0)), b)


func _do_summon() -> void:
	GameManager.play_sfx("elite")
	# 阶段 1 起召唤物带词缀(掷骰走 roll_enemy_affix, 与波次刷怪同一概率模型)
	_spawn_minions(int(GameManager.BOSS_BASE["summon_count"]), _phase >= 1)
	_spawn_minions(int(GameManager.BOSS_BASE["summon_count"]), _phase >= 1)


func _spawn_minions(n: int, with_affix: bool = false) -> void:
	for i in range(n):
		var b: Dictionary = GameManager.BOSS_BASE
		var k: int = int(b["summon_kind"])          # 0 = 史莱姆(读表, 原硬编码)
		if _phase >= 2:
			k = 3                                  # 阶段 2 起召骷髅(hp 45 > 史莱姆 25, 更硬)
		# 精英永不开: 掷骰门槛在 spawner, Boss 战中途无预警刷精英会毁掉"精英只来自波次"的阅读预期
		var aff: String = GameManager.roll_enemy_affix() if with_affix else ""
		ObjectPool.spawn_enemy(k, global_position + Vector2(
			GameManager._rng.randf_range(-30, 30),
			GameManager._rng.randf_range(-30, 30)), aff, "", false)


func _spawn_enemy_bullet(pos: Vector2, vel: Vector2, dmg: float) -> void:
	ObjectPool.spawn_bullet(pos, vel, dmg, "enemy", 0)


func take_damage(amount: float, from_dot: bool = false) -> void:
	if _dead:
		return
	var is_crit := false
	# 冰冻易伤: 非 DoT 伤害 +30%(Boss 也吃, 维持"先控后爆发"的一致手感)
	if not from_dot:
		amount *= StatusFx.damage_taken_mult(_status)
		# 暴击: 商店「致命一击」按概率 2 倍(与敌人一致, 受击端统一)
		var pre: float = amount
		amount = GameManager.roll_crit(amount)
		is_crit = amount > pre + 0.01
	hp -= amount
	_flash = 0.08
	# 漂浮伤害数字(Boss 体积大, 抬高起点); DoT 染暖色小号; 暴击金字
	var num := ObjectPool.spawn_damage_number(global_position + Vector2(0, -_r - 8.0), amount, is_crit)
	if from_dot and num != null:
		num.tint(Color(1.0, 0.7, 0.4))
	# 子弹直伤命中: 掷骰施加状态(Boss 抗性: 时长 ×0.4); DoT 不二次触发
	if not from_dot:
		StatusFx.try_proc_from_player(_status, amount, 0.4)
	if hp <= 0.0:
		die()


func die() -> void:
	if _dead:
		return
	_dead = true
	died.emit(self)
	GameManager.kills += 1
	GameManager.boss_kills += 1
	GameManager.check_achievements()   # 击杀类成就(首领也计 kills)
	GameManager.play_sfx("death")
	GameManager.spawn_effect(global_position, Color(0.6, 0.1, 0.9), 40, 70.0)
	GameManager.spawn_burst(global_position, Color(0.6, 0.1, 0.9), 2.0)
	_emerge_gems(20)
	# 必掉大治疗(暂用红药)
	ObjectPool.spawn_pickup(global_position, "heart")
	# 金币掉落: 首领掉一圈大额金币(每枚 value=4), 是局外商店主要金币来源
	for i in range(12):
		var a := TAU * float(i) / 12.0
		ObjectPool.spawn_coin(global_position + Vector2.from_angle(a) * 22.0, 4)
	GameManager.enemies.erase(self)
	ObjectPool.release(self)
	# 终极 Boss 被击杀 => 通关; 普通 Boss 死亡则回到战斗循环 BGM
	if is_final and GameManager.main != null and GameManager.main.has_method("on_final_boss_defeated"):
		GameManager.main.on_final_boss_defeated()
	elif not GameManager.boss_alive():
		# 波 12 是双 Boss(中 Boss + 终极): 中 Boss 先死时终极还在场上, 切回 battle 轨就错了。
		# 上面已 enemies.erase(self), 故 boss_alive() 这里判的是"是否还有另一只 Boss"。
		# (原先无条件切 battle, 波 12 打掉中 Boss 的瞬间 Boss 战音乐就没了, 而终极 Boss 还在追人)
		GameManager.play_bgm("battle")


# 波末清场专用: 不计击杀/不掉奖励/终极 Boss 也不触发胜利(残 Boss 随波清空), 静默回收
func die_without_reward() -> void:
	if _dead:
		return
	_dead = true
	GameManager.enemies.erase(self)
	ObjectPool.release(self)


func _emerge_gems(count: int) -> void:
	for i in range(count):
		ObjectPool.spawn_gem(global_position + Vector2(
			GameManager._rng.randf_range(-20, 20),
			GameManager._rng.randf_range(-20, 20)), 1.0)