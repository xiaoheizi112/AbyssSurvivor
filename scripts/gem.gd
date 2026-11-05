extends Node2D
## Gem — 经验宝石; 待拾时呼吸浮动 + 明暗闪光, 进入拾取范围后磁吸加速, <4px 拾取

var xp: float = 1.0
var speed: float = 0.0
var _active: bool = true
var sprite: Sprite2D = null
var _base_pos: Vector2 = Vector2.ZERO   # setup 时世界坐标(浮动偏移的基准)
var _t: float = 0.0


func setup(pos: Vector2, xp_value: float) -> void:
	global_position = pos
	_base_pos = pos
	xp = xp_value
	_active = true
	speed = 0.0
	_t = GameManager._rng.randf_range(0.0, TAU)   # 随机相位, 避免同屏宝石齐浮
	_ensure_visual()
	sprite.modulate = Color(1, 1, 1, 1)   # 复位回收残留的透明度


func _ensure_visual() -> void:
	if sprite == null:
		sprite = GameManager.sprite_with_circle(4, Color(0.3, 1.0, 0.4), "gem")
		sprite.name = "Sprite2D"
		add_child(sprite)
	# 32×32 图标固定 0.5 缩放(= 16 逻辑像素, 2× 整数放大后对齐像素网格)
	sprite.scale = Vector2.ONE * 0.5


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if GameManager.state != GameManager.State.PLAYING or GameManager.player == null:
		return

	var p := GameManager.player
	var to_player := p.global_position - global_position
	var dist := to_player.length()
	var pr: float = p.pick_range()

	if dist < pr:
		# 磁吸: 越近越快; 一旦吸附即贴向玩家, 不再浮动
		_base_pos = global_position
		var t := 1.0 - clampf(dist / pr, 0.0, 1.0)
		speed = 60.0 + t * 300.0
		global_position = global_position.move_toward(p.global_position, speed * delta)
	else:
		# 待拾: 呼吸浮动(±1px) + 明暗闪光(卡通生命感)
		_t += delta
		global_position.y = _base_pos.y + sin(_t * 3.0) * 1.0
		sprite.modulate.a = 0.75 + 0.25 * sin(_t * 5.0)

	if dist < 4.0:
		collect()


func collect() -> void:
	_active = false
	# 经验咽喉: 诅咒加成在这里乘(而非 spawn_gem 生成端), 与 coin.collect() 的金币咽喉对称
	GameManager.xp += xp * GameManager.xp_mult()
	# 忍者蛙「拾穗」: 每拾取一颗经验宝石回复 1 生命(小回复, 靠拾取频率叠续航)
	if GameManager.current_character == "priest" and GameManager.player != null:
		GameManager.player.heal(1.0)
	GameManager.play_sfx("pickup")
	GameManager.spawn_effect(global_position, Color(0.3, 1.0, 0.4), 5, 20.0)
	if GameManager.xp >= GameManager.xp_to_next():
		GameManager.xp -= GameManager.xp_to_next()
		GameManager.level += 1
		GameManager.main.trigger_level_up()
	GameManager.gems.erase(self)
	ObjectPool.release(self)