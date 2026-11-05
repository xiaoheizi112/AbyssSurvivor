extends Node
## Spawner — 波次制刷怪(参照土豆兄弟): 固定 12 波, 密度驱动(只/s 持续刷到波时长结束)
## 刷怪方式也是土豆兄弟式: **先在地图上标红叉预警, 倒计时结束怪从叉处落地**, 不从屏幕外走进来
## 波末清场(释放残怪)后进波间商店; 每 4 波一个 Boss(4/8/12), 第 12 波双 Boss 且终极 Boss 击杀通关

# 波配置表 [ [duration, density, [史莱姆,蝙蝠,巨魔,骷髅]权重, boss], ... ]
#   density  只/秒(波内持续按此密度刷, 直到波时长走完)
#   boss:     "" 无 / "boss" 中 Boss / "final" 终极 Boss(击杀通关)
# 权重是构成比例, 刷怪时加权随机取种; 12 波总时长约 374s
#
# **密度是锯齿不是单调递增**(2026-09-09 重调): 峰在 Boss 前(3/4、7/8、11/12 波),
# 谷在 Boss 后(5、9 波)给喘息与捡物窗口。总和 16.20 与旧表逐项相等 → 全局压力不变,
# 只是把压力从"Boss 刚打完"搬到"Boss 将至"。
# **权重列 = [史莱姆, 蝙蝠, 巨魔, 骷髅, 吐息, 自爆, 护盾]**, 每行和 = 1.00。
# 新怪进场波: 吐息=5(与骷髅同波, 两新面孔均血 +12% 当"新怪更硬"体感),
# 自爆=7, 护盾=8。第 9 波起新三怪合计 ~14%(远程+爆发+肉盾的三角压力), 均血
# 相对上一版(4 列表)偏差控制在 -7%~+10%: 新怪威胁来自机制而非血量, 不必再抬面板。
const WAVES := [
	[25.0, 0.70, [1.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00], ""],
	[26.0, 0.85, [1.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00], ""],
	[27.0, 1.05, [0.80, 0.20, 0.00, 0.00, 0.00, 0.00, 0.00], ""],
	[28.0, 1.20, [0.70, 0.30, 0.00, 0.00, 0.00, 0.00, 0.00], "boss"],
	[30.0, 1.10, [0.53, 0.33, 0.00, 0.08, 0.06, 0.00, 0.00], ""],
	[30.0, 1.35, [0.38, 0.28, 0.09, 0.17, 0.08, 0.00, 0.00], ""],
	[32.0, 1.50, [0.32, 0.24, 0.16, 0.18, 0.04, 0.06, 0.00], ""],
	[32.0, 1.55, [0.27, 0.21, 0.20, 0.18, 0.04, 0.05, 0.05], "boss"],
	[34.0, 1.40, [0.22, 0.20, 0.24, 0.20, 0.04, 0.04, 0.06], ""],
	[34.0, 1.70, [0.16, 0.18, 0.30, 0.20, 0.04, 0.06, 0.06], ""],
	[36.0, 1.85, [0.12, 0.14, 0.34, 0.24, 0.04, 0.06, 0.06], ""],
	[40.0, 1.95, [0.06, 0.11, 0.42, 0.26, 0.03, 0.06, 0.06], "final"],
]

const MAX_ENEMIES := 240

# 预警叉时长: 普通怪 0.9s(够反应但保持压迫), Boss 1.8s(体型大, 需要更长躲避窗口)
const TELEGRAPH_DUR := 0.9
const TELEGRAPH_BOSS_DUR := 1.8

var _spawn_timer := 0.0
var _wave_timer := 0.0     # 当前波已进行时长
var _interval := 1.0       # 当前波刷怪间隔(秒/只)
var _weights: Array = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # 当前波敌人构成权重
# 波时长已走完、正在等 Boss 收尾(2026-09-10 加, 见 _physics_process 的波末段)。
# **不入 suspend.cfg**: 它可由 `_wave_timer >= duration` 现场重推, 恢复后第一帧自动回到 true,
# 存盘反而多一份真相。_start_wave/reset_run 复位。
var _wave_over := false

# 待落地的预警标记(与 spawn_markers.gd 共享同一 Array 引用, 那边只负责画叉)
# 每项 {pos, t 剩余, dur 总时长, boss, kind, affix, appearance, final}
var _telegraphs: Array = []


func _ready() -> void:
	# 预警叉绘制节点: 共享 _telegraphs 数组引用, 每局随场景常驻(不需要重建)
	var markers := Node2D.new()
	markers.name = "SpawnMarkers"
	markers.set_script(load("res://scripts/spawn_markers.gd"))
	add_child(markers)
	markers.telegraphs = _telegraphs


# 每局开始复位: 不 reload 场景时刷怪计时器会跨局残留, 必须手动归零
func reset_run() -> void:
	_spawn_timer = 0.0
	_wave_timer = 0.0
	_wave_over = false
	_interval = 1.0
	_weights = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	_telegraphs.clear()   # 上一局的预警叉不能带进新一局
	GameManager.wave = 0
	GameManager.wave_time = 0.0
	GameManager.set_wave_curse("")   # 事件同属波级状态, 跨局必清(首波 _start_wave 会重掷)


# 进入第 n 波: 载入配置、重置波内状态、广播波次预告(=1 时也要预告开局)
func _start_wave(n: int) -> void:
	GameManager.wave = n
	GameManager.wave_time = 0.0
	GameManager.wave_took_damage = false   # 新一波重置无伤判定
	GameManager.check_achievements()       # 波次/时长类成就在波开始事件点统一检查
	# 波间诅咒事件: 每波强制掷一条(_rng 走存档的随机流, resume 后同波重掷结果一致),
	# 整波生效, _clear_wave 清零。与 curse_level 正交 —— 事件被动抽, 诅咒主动买。
	GameManager.roll_wave_curse()
	var def: Array = WAVES[n - 1]
	_wave_timer = 0.0
	_wave_over = false   # 新一波重新开始计时(残留会让本波开局即停刷杂兵)
	_interval = 1.0 / float(def[1])   # density 只/s -> 秒/只
	_weights = def[2].duplicate()
	_spawn_timer = 0.0   # 新波立刻开始刷
	# Boss 波: 开局即在预定位置刷 Boss(第 4/8/12 波终局)
	var boss_kind: String = str(def[3])
	# 刷新预告 UI(含 boss_kind, 让带 Boss 的波次红字预警; 事件名随横幅副标播报)
	if GameManager.main != null and GameManager.main.has_method("announce_wave"):
		GameManager.main.announce_wave(n, WAVES.size(), boss_kind)
	if boss_kind == "boss":
		_spawn_boss(GameManager.boss_kills + 1)
	elif boss_kind == "final":
		# 终极波双 Boss: 堵上"4 波一 Boss"的终局凑齐 — 中 Boss(路障) + 终极 Boss(击杀通关)
		_spawn_boss(GameManager.boss_kills + 1)
		_spawn_final_boss()


func _physics_process(delta: float) -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return

	# 开局首波; 正常流程由 reset_run + 首帧拉起到第 1 波
	if GameManager.wave == 0:
		_start_wave(1)
		return

	GameManager.time_s += delta
	GameManager.wave_time += delta
	_wave_timer += delta

	var def: Array = WAVES[GameManager.wave - 1]
	var duration: float = float(def[0])

	# 密度驱动: 波内持续按 interval 排预警叉, 直到波时长走完(土豆兄弟: 不设总数上限, 密度恒定)
	if _wave_timer < duration:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			# 诅咒密度: 乘到刷怪间隔(<1 = 更密)。唯一密度咽喉 —— 所有波次/难度/诅咒都走这一行
			_spawn_timer = _interval * GameManager.difficulty_spawn_mult() * GameManager.curse_spawn_mult()
			# 上限按「场上敌人 + 待落地预警」一起算, 否则预警堆积后会瞬间超员
			if GameManager.enemies.size() + _telegraphs.size() < MAX_ENEMIES:
				_queue_spawn()

	# 预警倒计时: 到点的叉落地成真怪
	_tick_telegraphs(delta)

	# 波时长走完 → 停刷杂兵 + 清场 + 进商店(最后一波靠终极 Boss 击杀通关, 不进商店)。
	# **但 Boss 必须打完才推进**(2026-09-10 改, 用户指定): 原先 Boss 也被 _clear_wave 一起
	# die_without_reward —— 实测 kite 困难档波 4 的中 Boss 打到 611/1200 就凭空消失, 不计击杀、
	# 白丢 20 宝石 + 红药 + 48 金币, 且 BGM 卡在 boss 轨 90s(play_bgm("battle") 只在 boss.die() 里)。
	# 新语义与波 12「终极 Boss 击杀才通关」统一: 波时长一到就停止刷杂兵(不再凭空添敌),
	# 场上残敌与 Boss 留着打, Boss 死了才清场进店。DPS 不够时 Boss 会把玩家打死走死亡结算,
	# 不存在软锁(Boss 一直在动一直打人, 不会僵在那儿)。
	var is_last: bool = GameManager.wave >= WAVES.size()
	if not is_last and _wave_timer >= duration and GameManager.state == GameManager.State.PLAYING:
		if not _wave_over:
			_wave_over = true
			# 取消尚未落地的**杂兵**预警叉(波已结束, 不该再凭空添敌); Boss 叉保留,
			# 否则会把还没落地的 Boss 也一并取消 —— 那又回到"Boss 悄悄消失"
			for i in range(_telegraphs.size() - 1, -1, -1):
				if not bool(_telegraphs[i]["boss"]):
					_telegraphs.remove_at(i)
		if not _boss_pending():
			if not GameManager.wave_took_damage:
				GameManager.unlock_achievement("no_hit_wave")
			_clear_wave()
			_open_shop()


# Boss 还在场上, 或 Boss 预警叉还没落地 —— 两种情况都必须等, 否则会把 Boss 一起清掉。
func _boss_pending() -> bool:
	if GameManager.boss_alive():
		return true
	for tg in _telegraphs:
		if bool(tg["boss"]):
			return true
	return false


# 波末清场: 残怪直接释放(不掉经验金币), 让"打完一波松口气"的节奏成立, 商店从打断变奖励
func _clear_wave() -> void:
	for e in GameManager.enemies.duplicate():
		if is_instance_valid(e):
			e.die_without_reward()
	# 未落地的预警叉一并取消(波已结束, 不能让"上一波的怪"在商店里冒出来)
	_telegraphs.clear()
	# 事件波末消失(单波扰动, 不跨波残留); 下一波 _start_wave 重掷
	GameManager.set_wave_curse("")


# 波间商店: 暂停刷怪, 交给 main 打开商店界面
func _open_shop() -> void:
	if GameManager.main == null or not GameManager.main.has_method("open_wave_shop"):
		# 无商店时直接推进下一波(兜底, 保持旧行为)
		_start_wave(GameManager.wave + 1)
		return
	GameManager.play_sfx("select")
	GameManager.main.open_wave_shop()


# 排一个预警叉(而非直接刷怪): 到点后由 _tick_telegraphs 落地成真怪
# 位置在**地图内**随机(土豆兄弟式), 不再从屏幕外走进来
func _queue_spawn() -> void:
	var kind := _weighted_kind()
	# 掷骰顺序: 词缀 → 精英 → 第二词缀。精英是"词缀怪的升格", 必须先掷中词缀才可能中精英;
	# 第二词缀只在精英时掷(单词缀裸怪没有双持资格), 且必与主词缀不同(见 roll_enemy_affix2)。
	# 必须在 telegraph 阶段掷而非 _materialize: spawn_markers 的预警圈要提前 0.9s 画出精英双环。
	var affix: String = GameManager.roll_enemy_affix()
	var elite: bool = GameManager.roll_elite(affix)
	_telegraphs.append({
		"pos": _map_pos(),
		"t": TELEGRAPH_DUR,
		"dur": TELEGRAPH_DUR,
		"boss": false,
		"kind": kind,
		"affix": affix,
		"elite": elite,
		"affix2": GameManager.roll_enemy_affix2(affix) if elite else "",
	})


# 预警倒计时推进: 到点的标记落地(Boss 落地伴随震屏与音效)
func _tick_telegraphs(delta: float) -> void:
	if _telegraphs.is_empty():
		return
	for i in range(_telegraphs.size() - 1, -1, -1):
		var tg: Dictionary = _telegraphs[i]
		tg["t"] = float(tg["t"]) - delta
		if float(tg["t"]) > 0.0:
			continue
		_telegraphs.remove_at(i)
		_materialize(tg)


func _materialize(tg: Dictionary) -> void:
	var pos: Vector2 = tg["pos"]
	if bool(tg["boss"]):
		var appearance: int = int(tg["appearance"])
		var b := ObjectPool.spawn_boss(appearance, pos)
		# 预告(BGM/横幅/音效)在标叉时已发出, 这里只给落地的冲击反馈
		if bool(tg["final"]):
			b.make_final()
			GameManager.final_boss_spawned = true
			GameManager.add_shake(8.0)
		else:
			GameManager.add_shake(5.0)
		GameManager.spawn_effect(pos, Color(0.6, 0.1, 0.9), 20, 60.0)
		return
	GameManager.spawn_effect(pos, Color(0.95, 0.35, 0.30), 8, 45.0)
	# telegraph 两键在 _queue_spawn 掷好, 这里只搬运(0.9s 预警期内 spawn_markers 已按 elite 画双环)。
	# get 带默认值: 兼容理论上的旧 telegraph 形状(boss 叉走上面分支, 永远不带这两键)。
	spawn_enemy_at(pos, int(tg["kind"]), str(tg["affix"]), str(tg.get("affix2", "")), bool(tg.get("elite", false)))


func _weighted_kind() -> int:
	var total := 0.0
	for w in _weights:
		total += float(w)
	var r := GameManager._rng.randf() * total
	var acc := 0.0
	for i in range(_weights.size()):
		acc += float(_weights[i])
		if r <= acc:
			return i
	return _weights.size() - 1


# 地图内落点: 避开玩家贴身(否则预警叉直接糊脸, 没有躲避空间)
# 前期策划注释: 首波玩家仅起始武器, 若一开始就混蝙蝠会让开局追不上, 故波 1~2 纯史莱姆
const SPAWN_MIN_DIST := 70.0    # 距玩家最小距离(预警叉不会糊在脚下)
const SPAWN_MARGIN := 16.0      # 距战场边缘内缩, 保证怪与叉完整可见

func _map_pos() -> Vector2:
	var b := GameManager.BOUND
	for _attempt in range(24):
		var p := Vector2(
			GameManager._rng.randf_range(b.position.x + SPAWN_MARGIN, b.end.x - SPAWN_MARGIN),
			GameManager._rng.randf_range(b.position.y + SPAWN_MARGIN, b.end.y - SPAWN_MARGIN))
		if _spawn_pos_ok(p):
			return p
	# 兜底: 多次未命中合法点时取玩家对侧远处, 保证刷怪不停摆
	var c := b.get_center()
	var away := c
	if GameManager.player != null:
		var dir := (c - GameManager.player.global_position).normalized()
		if dir.length_squared() < 0.0001:
			dir = Vector2.RIGHT
		away = c + dir * 120.0
	away.x = clampf(away.x, b.position.x + SPAWN_MARGIN, b.end.x - SPAWN_MARGIN)
	away.y = clampf(away.y, b.position.y + SPAWN_MARGIN, b.end.y - SPAWN_MARGIN)
	return away


func _spawn_pos_ok(p: Vector2) -> bool:
	return GameManager.player == null or p.distance_to(GameManager.player.global_position) >= SPAWN_MIN_DIST


func spawn_enemy_at(pos: Vector2, kind: int, affix: String = "", affix2: String = "", elite: bool = false) -> Node2D:
	return ObjectPool.spawn_enemy(kind, pos, affix, affix2, elite)


# Boss 也走预警叉(时长更长, 给躲避窗口), 落地位置在地图内而非固定 (100, 225)
func _spawn_boss(appearance: int) -> void:
	_telegraphs.append({
		"pos": _boss_pos(),
		"t": TELEGRAPH_BOSS_DUR,
		"dur": TELEGRAPH_BOSS_DUR,
		"boss": true,
		"appearance": appearance,
		"final": false,
	})
	# 标叉时即预告: BGM 切 Boss 轨 + 横幅 + 音效, 给玩家 1.8s 准备时间
	GameManager.play_sfx("elite")
	if GameManager.main.has_method("announce_boss"):
		GameManager.main.announce_boss()


# 终极 Boss: 体型放大 + 染红 + 5000 血, 击杀即通关(落地时由 _materialize 调 make_final)
func _spawn_final_boss() -> void:
	_telegraphs.append({
		"pos": _boss_pos(),
		"t": TELEGRAPH_BOSS_DUR,
		"dur": TELEGRAPH_BOSS_DUR,
		"boss": true,
		"appearance": GameManager.boss_kills + 1,
		"final": true,
	})
	GameManager.play_sfx("elite")
	if GameManager.main.has_method("announce_final_boss"):
		GameManager.main.announce_final_boss()


# Boss 落点: 离玩家稍远(体型大, 贴身刷等于秒杀), 且在地图内
func _boss_pos() -> Vector2:
	var b := GameManager.BOUND
	var p := b.get_center()
	if GameManager.player != null:
		p = GameManager.player.global_position
	for _attempt in range(24):
		var q := Vector2(
			GameManager._rng.randf_range(b.position.x + 40.0, b.end.x - 40.0),
			GameManager._rng.randf_range(b.position.y + 40.0, b.end.y - 40.0))
		if q.distance_to(p) < 110.0:
			continue
		return q
	return Vector2(100.0, 225.0)   # 兜底: 原固定登场点