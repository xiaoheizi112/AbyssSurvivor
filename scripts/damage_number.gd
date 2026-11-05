extends Node2D
## DamageNumber — 漂浮伤害数字; 受击点向上浮起并淡出, 大伤害更大字
## 走对象池复用; Text 判据: is_crit 金色大号, 普通白色

var label: Label = null
var _life: float = 0.5
var _t: float = 0.0
var _vel: Vector2 = Vector2(0, -24.0)


func setup(pos: Vector2, val: float, is_crit: bool = false) -> void:
	global_position = pos
	_t = 0.0
	if label == null:
		label = Label.new()
		label.name = "Label"
		add_child(label)
	label.text = str(int(round(val)))
	label.add_theme_font_size_override("font_size", 14 if (is_crit or val >= 30.0) else 9)
	label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.2) if is_crit else Color(1.0, 1.0, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("outline_size", 2)
	label.position = Vector2(-8, -8)   # 居中于受击点
	visible = true
	modulate = Color(1, 1, 1, 1)


# DoT(燃烧/中毒)结算时染暖色, 与直伤(白/金)区分; 只改 label 字色, 不动节点淡出
func tint(c: Color) -> void:
	if label != null:
		label.add_theme_color_override("font_color", c)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		recycle()
		return
	global_position += _vel * delta
	modulate.a = 1.0 - (_t / _life)


func recycle() -> void:
	visible = false
	ObjectPool.release(self)