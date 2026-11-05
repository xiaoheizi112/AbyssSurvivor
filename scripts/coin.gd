extends Node2D
## Coin — 金币; 击杀掉落, 拾取后累加本局金币(结算时存入永久存档)
## 待拾时呼吸浮动 + 明暗闪光, 进入拾取范围后磁吸加速(与 gem 一致)
## value 越大金币越大越亮(精英/首领掉大额金币)

var value: int = 1
var _active: bool = true
var sprite: Sprite2D = null
var _base_pos: Vector2 = Vector2.ZERO
var _t: float = 0.0


func setup(pos: Vector2, v: int) -> void:
	global_position = pos
	_base_pos = pos
	value = v
	_active = true
	_t = GameManager._rng.randf_range(0.0, TAU)
	_ensure_visual()
	sprite.modulate = Color(1, 1, 1, 1)


func _ensure_visual() -> void:
	# 三档尺寸: 小额(≤3) / 大额(4~9, 巨魔与 Boss 掉落) / 巨额(≥10, 精英专属 3×12)。
	# 没有 huge 档时 value12 与 value4 长得一样, 精英掉落的"值得专门处理"就丢了一半。
	var big := value >= 4
	var huge := value >= 10
	var r := 7 if huge else (5 if big else 3)
	# 偏金色进圆贴图而不是 modulate: 后者被 _physics_process 的呼吸明暗逐帧写 .a 通道, 会打架
	var col := Color(1.0, 0.92, 0.55) if huge else (Color(1.0, 0.85, 0.25) if big else Color(0.95, 0.78, 0.15))
	if sprite == null:
		sprite = GameManager.sprite_with_circle(r, col)
		sprite.name = "Sprite2D"
		add_child(sprite)
	else:
		sprite.texture = GameManager.circle_texture(r, col)
	# 金币用程序化圆形(无整张贴图); 保持 1:1 像素尺寸
	sprite.scale = Vector2.ONE


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
		_base_pos = global_position
		var t := 1.0 - clampf(dist / pr, 0.0, 1.0)
		var speed := 80.0 + t * 320.0
		global_position = global_position.move_toward(p.global_position, speed * delta)
	else:
		_t += delta
		global_position.y = _base_pos.y + sin(_t * 3.0) * 1.0
		sprite.modulate.a = 0.75 + 0.25 * sin(_t * 5.0)

	if dist < 4.0:
		collect()


func collect() -> void:
	_active = false
	GameManager.coins += float(value) * GameManager.coin_mult()
	GameManager.play_sfx("pickup")
	GameManager.spawn_effect(global_position, Color(1.0, 0.8, 0.2), 4, 18.0)
	GameManager.coins_list.erase(self)   # 与 gem 一致: 出列表再释放, 否则列表残留悬空引用
	ObjectPool.release(self)