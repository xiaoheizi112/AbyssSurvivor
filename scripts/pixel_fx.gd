extends Node2D
## PixelFx — 程序化像素一次性特效播放器(对象池复用)
## 帧由 GameManager.fx_frames() 从字符画烘焙成 ImageTexture(灰度), 这里按 fps 步进播放
## 染色走 draw_texture_rect 的 modulate 参数: 同一套灰度帧 → 各武器按主题色 tint(法杖青/进化紫/落雷金…)
## 与矢量 effect.gd 的区别: 无抗锯齿、整数对齐、贴图帧 => 真像素观感

var _frames: Array = []        # Array[Texture2D], 当前特效的帧序列
var _fps: float = 30.0
var _t: float = 0.0
var _tint: Color = Color.WHITE # 含 alpha; alpha 随生命衰减做淡出
var _fade: bool = true         # 是否随时间淡出(枪口/火花淡出, 环不淡只缩)
var _additive: bool = false    # 加法混合(深色背景下更发光)
var _done: bool = false

static var _add_mat: ShaderMaterial = null   # 加法混合材质(全实例共享)


# fx_name: PIXEL_FX 表键; pos: 世界坐标; tint: 染色(灰度帧 × tint); sc: 整数倍放大(默认 1)
# rot_deg: 旋转角度(枪口对齐发射方向); fade: 是否淡出; additive: 加法混合
func setup(fx_name: String, pos: Vector2, tint: Color = Color.WHITE, sc: float = 1.0, rot_deg: float = 0.0, fade: bool = true, additive: bool = false) -> void:
	var def: Dictionary = GameManager.PIXEL_FX.get(fx_name, {})
	if def.is_empty():
		# 未知特效名: 立即回收(不能只藏不 release, 否则节点卡在池外)
		_done = false
		_recycle()
		return
	_frames = GameManager.fx_frames(fx_name)
	_fps = float(def.get("fps", 30.0))
	_tint = tint
	_fade = fade
	_additive = additive
	_t = 0.0
	_done = false
	# 加法混合材质(深色战场下光效更亮); 非加法恢复默认
	material = _add_material() if additive else null
	# 整数对齐: 像素帧落在整数世界坐标, 2× 整数放大下不抖动/不糊
	global_position = pos.round()
	rotation = deg_to_rad(rot_deg)
	# sc>=1 取整数倍(放大保持锐利), <1 允许小数(缩小)
	scale = Vector2.ONE * (roundf(sc) if sc >= 1.0 else sc)
	visible = true
	set_process(true)
	queue_redraw()


func _add_material() -> ShaderMaterial:
	if _add_mat == null:
		_add_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nrender_mode blend_add;\n"
		_add_mat.shader = sh
	return _add_mat


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var n := _frames.size()
	if n == 0:
		_recycle()
		return
	var total := float(n) / _fps
	if _t >= total:
		_recycle()
		return
	# 淡出: alpha 随生命线性衰减(末帧更透, 收得干净)
	if _fade:
		var k := clampf(_t / total, 0.0, 1.0)
		modulate.a = 1.0 - k * k
	queue_redraw()


func _draw() -> void:
	if _frames.is_empty():
		return
	var idx := int(_t * _fps)
	idx = clampi(idx, 0, _frames.size() - 1)
	var tex: Texture2D = _frames[idx]
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	# 居中绘制(节点已按 sc 缩放, 这里按原始尺寸画, 缩放交给 transform)
	draw_texture_rect(tex, Rect2(-w * 0.5, -h * 0.5, w, h), false, _tint)


func _recycle() -> void:
	if _done:
		return
	_done = true
	visible = false
	modulate.a = 1.0
	rotation = 0.0
	scale = Vector2.ONE
	material = null
	_frames = []
	ObjectPool.release(self)
