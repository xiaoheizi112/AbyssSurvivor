extends Node2D
## Pickup — 红药(回血)/金宝箱(三选一)/念珠(全屏清场)/磁铁(吸全屏宝石)
## 待拾时呼吸浮动 + 明暗闪光, 进入范围后磁吸; 念珠/磁铁用程序化像素图标

var kind: String = "heart"    # "heart" | "chest" | "rosary" | "magnet"
var _active: bool = true
var sprite: Sprite2D = null
var _base_pos: Vector2 = Vector2.ZERO
var _t: float = 0.0


func setup(pos: Vector2, k: String) -> void:
	global_position = pos
	_base_pos = pos
	kind = k
	_active = true
	_t = GameManager._rng.randf_range(0.0, TAU)
	_ensure_visual()
	sprite.modulate = Color(1, 1, 1, 1)   # 复位回收残留的透明度


func _visual() -> Array:
	# 返回 [tex_key, 回退颜色]: 有真贴图用贴图, 念珠/磁铁走程序化像素图标
	match kind:
		"heart":  return ["heart", Color(1.0, 0.3, 0.35)]
		"chest":  return ["chest", Color(0.9, 0.75, 0.25)]
		"rosary": return ["", Color(0.85, 0.45, 1.0)]
		"magnet": return ["", Color(0.9, 0.3, 0.3)]
	return ["heart", Color(1.0, 0.3, 0.35)]


func _ensure_visual() -> void:
	# 池复用后 kind 可能改变, 每次 setup 都以当前 kind 重建贴图
	# 32×32 图标统一 0.5 缩放(= 16 逻辑像素, 2× 整数放大后对齐像素网格)
	var v: Array = _visual()
	var tex_key: String = v[0]
	var col: Color = v[1]
	if sprite == null:
		sprite = GameManager.sprite_with_circle(6, col, tex_key)
		sprite.name = "Sprite2D"
		add_child(sprite)
	else:
		var tex: Texture2D = GameManager.texture_for(tex_key) if tex_key != "" else null
		sprite.texture = tex if tex != null else GameManager.circle_texture(6, col)
	# 念珠/磁铁: 无整张贴图, 换用程序化像素图标(16×16)
	if kind == "rosary" or kind == "magnet":
		sprite.texture = GameManager.pickup_icon_texture(kind)
	sprite.scale = Vector2.ONE * 0.5


func _physics_process(delta: float) -> void:
	if not _active:
		return
	if GameManager.state != GameManager.State.PLAYING or GameManager.player == null:
		return
	var p := GameManager.player
	var dist := global_position.distance_to(p.global_position)
	if dist < p.pick_range():
		# 磁吸: 一旦吸附即贴向玩家, 不再浮动
		_base_pos = global_position
		global_position = global_position.move_toward(p.global_position, 150.0 * delta)
	else:
		# 待拾: 呼吸浮动 + 明暗闪光
		_t += delta
		global_position.y = _base_pos.y + sin(_t * 3.0) * 1.5
		sprite.modulate.a = 0.8 + 0.2 * sin(_t * 4.0)
	if dist < 5.0:
		_collect()


func _collect() -> void:
	_active = false
	match kind:
		"heart":
			GameManager.player.heal(25.0)
			GameManager.play_sfx("pickup")
		"chest":
			GameManager.main.trigger_level_up()
			GameManager.play_sfx("levelup")
		"rosary":
			_trigger_rosary()
		"magnet":
			_trigger_magnet()
	ObjectPool.release(self)


# 念珠: 全屏清场 —— 普通敌人秒杀, Boss 固定 300 伤害(不秒终极 Boss, 避免绕过胜利条件)
func _trigger_rosary() -> void:
	for e in GameManager.enemies.duplicate():
		if not is_instance_valid(e) or e.is_queued_for_deletion():
			continue
		var is_boss: bool = e.get_script() != null and e.get_script().resource_path.ends_with("boss.gd")
		if is_boss:
			e.take_damage(300.0)
		else:
			e.take_damage(99999.0)
	GameManager.add_shake(6.0)
	GameManager.play_sfx("levelup")


# 磁铁: 把全屏经验宝石瞬移到玩家周围(黄金角铺开防堆叠), 走正常磁吸逐个拾取
func _trigger_magnet() -> void:
	var p := GameManager.player
	if p == null:
		return
	var angle := 0.0
	for g in GameManager.gems.duplicate():
		if not is_instance_valid(g) or g.is_queued_for_deletion():
			continue
		angle += 2.399963   # 黄金角 (137.5°), 均匀铺开
		var r := 45.0 + fmod(angle, 1.0) * 25.0
		g.global_position = p.global_position + Vector2.from_angle(angle) * r
	GameManager.play_sfx("pickup")