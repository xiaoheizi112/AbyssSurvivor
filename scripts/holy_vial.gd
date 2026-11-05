extends Node2D
## HolyVial — 投掷中的燃烧瓶: 从角色飞向落点, 砸地瞬间才生成灼烧区域
## 非池化(数量与生命周期都短, 与 burn_zone 同理由直接 free); 入 group 供重开清场
## 视觉: 抛物线飞行 + 自旋, 落地爆裂 flash + 生成 burn_zone
## group 名 "holy_vial" 与文件名一并保留(id/路径改名要同步 main.gd 的清场扫描, 收益为零)

const _Pixels := preload("res://scripts/pixel_utils.gd")

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _radius: float = 26.0
var _damage: float = 6.0
var _dur: float = 3.0
var _evolved: bool = false
var _tier: int = 0
var _flight: float = 0.4     # 飞行时长(秒); setup 时随距离定
var _t: float = 0.0

const ARC := 26.0            # 抛物线弧高(世界像素)
const SPIN := 1.6            # 全程自旋圈数


func _ready() -> void:
	add_to_group("holy_vial")


func setup(from: Vector2, to: Vector2, r: float, dmg: float, dur: float, evolved: bool, tier: int, flight: float) -> void:
	_from = from
	_to = to
	_radius = r
	_damage = dmg
	_dur = dur
	_evolved = evolved
	_tier = tier
	_flight = flight
	_t = 0.0
	global_position = _from
	rotation = 0.0
	visible = true


func _process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	_t += delta
	var k := clampf(_t / _flight, 0.0, 1.0)
	var base := _from.lerp(_to, k)
	var arc := sin(k * PI) * ARC
	global_position = base - Vector2(0.0, arc)
	rotation = k * TAU * SPIN
	if k >= 1.0:
		_land()
		return
	queue_redraw()


# 落地: 生成灼烧区域(此时才生效) + 爆裂 flash + 轻音效
# Lv3 终极: 换色(白热金) + 更大爆裂粒子(落点炸开一圈); 进化态另走紫焰
func _land() -> void:
	var z := Node2D.new()
	z.set_script(load("res://scripts/burn_zone.gd"))
	GameManager.main.add_child(z)
	z.setup(_to, _radius, _damage, _dur, _evolved, _tier)
	# 爆裂色跟瓶内燃料同一套火色(三档分开, 原先 Lv3 与进化态共用一色)
	var burst_col := _tint_liquid(1.0)
	GameManager.spawn_burst(_to, burst_col, 1.1 if _tier >= 2 else 0.7)
	GameManager.play_sfx("hit")
	queue_free()


# 瓶身配色: 常态玻璃青 + 橙红燃料; Lv3 换白热金 / 进化紫(按档位)
# 与 holy_water._tint、burn_zone._tint 必须是同一组三个色值 —— 瓶子/火苗/火池
# 是一条视觉链, 任一处偏色都会读成"两种武器"
func _tint_liquid(a: float) -> Color:
	if _evolved:
		return Color(0.85, 0.40, 0.95, a)
	if _tier >= 2:
		return Color(1.00, 0.78, 0.25, a)
	return Color(1.00, 0.45, 0.15, a)


# 玻璃淡青机身 + 液体椭球; 节点随旋转自旋, 局部 +X 即瓶轴
# 连续自旋 → 轴吸附 45° 步进, 瓶形只用 8 个朝向(像素不糊); 整像素圆盘/方块绘制
func _draw() -> void:
	var body := Color(0.78, 0.92, 0.95, 0.85)
	var liq := _tint_liquid(0.9)
	var snap := snappedf(rad_to_deg(rotation), 45.0)
	var fx := Vector2.from_angle(deg_to_rad(snap))         # 吸附后瓶轴(局部)
	var fy := fx.orthogonal()
	# 瓶身(圆底) + 瓶颈(细长); 中心取整锚定
	var cc: Vector2 = Vector2(2.5, 0.0).dot(fx) * fx + Vector2(2.5, 0.0).dot(fy) * fy
	cc = cc.round() + Vector2(0.5, 0.5)
	_Pixels.disc(self, cc, 4.0, body)
	# 瓶颈: 沿瓶轴反向往瓶口排 2 个 2px 方块(接住瓶身 -4 边到 -6)
	for k in range(2):
		var gx := cc - fx * (5.0 + 1.5 * float(k))
		_Pixels.rect(self, gx - fy - Vector2.ONE, Vector2(2.0, 2.0), body)
	# 内部液体(圆盘)
	_Pixels.disc(self, cc, 3.0, liq)
	# 瓶口软木塞
	_Pixels.rect(self, cc - fx * 7.5 - fy - Vector2.ONE, Vector2(2.0, 2.0), Color(0.62, 0.46, 0.30, 0.9))
	# 玻璃高光: 瓶身左上方一道斜亮线(像素)
	_Pixels.line(self, cc + fx * (-2.5) + fy * (-3.5), cc + fx * (2.5) + fy * 2.5, Color(1.0, 1.0, 1.0, 0.45), 1.0)