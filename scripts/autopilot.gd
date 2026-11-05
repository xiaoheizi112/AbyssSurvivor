extends Node
## Autopilot (Autoload) — 自玩驱动, 仅在命令行含 --autopilot 时启用
## 职责: 模拟移动输入 / 自动选升级 / 死亡自动重开 / 周期战报 + 一致性断言
## 用法: Godot_v4.6 --headless --path . --quit-after N -- --autopilot (可选 --autostart)

var enabled := false
var god := false
var round := 0
var victories := 0
var assertions_failed := 0

# 移动/取舍策略档(见 _parse_style 与各 *_dir 的注释)。默认 balanced = 原有行为,
# 另两档专补「单策略压测只证明一个玩家能过关」这个盲区。
var style := STYLE_BALANCED

var _time_sum := 0.0
var _time_best := 0.0

var _report_timer := 0.0
var _dir_timer := 0.0
var _angle := 0.0


const TAG := "[AUTOPILOT]"
const REPORT_INTERVAL := 10.0

# 三档策略(命令行 --autopilot-style <id> 选, 缺省 balanced):
#   balanced 血量健康冲宝石、危险才逃 —— 原有默认, 跑通完整成长与通关路径
#   glass    永不逃, 一路贴着怪堆打 —— 测极限承伤与"贴脸输出"路径是否崩(掉帧/秒杀)
#   kite     永不主动吃资源, 只绕圈生存 —— 测"零成长龟缩"能活多久, 卡难度曲线的下限
const STYLE_BALANCED := "balanced"
const STYLE_GLASS := "glass"
const STYLE_KITE := "kite"
const STYLE_IDS: Array[String] = [STYLE_BALANCED, STYLE_GLASS, STYLE_KITE]

# god 局为凑进化而封顶的武器数(理由见 _pick_upgrade): 铺满 7 把会吃光整局升级预算
const FOCUS_WEAPONS := 3
# 为凑进化重摇三选一的次数上限。池里想要的配对被动权重只有 1(新武器/进化是 5),
# 单次三选一命中概率 ~7%, 凑满 3 级要几十次升级而一局只有 ~16 次 => 必零进化。
# 这是**测试驱动取数**问题不是玩法问题, 所以在这里多摇几次挑最好的一组,
# 不去改 roll_upgrade_options 的权重(玩家侧抽取手感必须保持原样)。
const REROLL_TRIES := 16

# 升级选项的优先级档位(_tier_of 与 _pick_upgrade / _handle_levelup 共用同一套语义)
const TIER_EVOLUTION := 5
const TIER_PASSIVE := 4
const TIER_WEAPON_NEW := 3
const TIER_WEAPON_MAX := 2
const TIER_FALLBACK := 1


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--autopilot"):
		enabled = true
		process_mode = Node.PROCESS_MODE_ALWAYS
		god = OS.get_cmdline_user_args().has("--autopilot-god")
		_parse_style()
		_log("enabled" + (" (god mode)" if god else "") + " style=" + style)


# --autopilot-style <id> 选策略档; 非法值回退 balanced 并告警(不崩)
func _parse_style() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--autopilot-style")
	if i < 0 or i + 1 >= args.size():
		return
	var want := args[i + 1]
	if want in STYLE_IDS:
		style = want
	else:
		push_warning("未知 autopilot style '%s', 回退 balanced(合法值 %s)" % [want, str(STYLE_IDS)])


func _log(msg: String) -> void:
	print(TAG + " " + msg)


func _fail(msg: String) -> void:
	assertions_failed += 1
	_log("ASSERT-FAIL: " + msg)


func _process(delta: float) -> void:
	if not enabled:
		return

	_report_timer += delta
	if _report_timer >= REPORT_INTERVAL:
		_report_timer = 0.0
		_report()

	_drive(delta)
	_handle_levelup()
	_handle_shop()
	_handle_gameover()
	_handle_victory()


# ---------------- 移动模拟 ----------------
# 用 Input.action_press 驱动 player 的 Input.get_vector, 走真实移动路径
func _drive(delta: float) -> void:
	var p = GameManager.player
	if p == null or GameManager.state != GameManager.State.PLAYING:
		_release_dir()
		return

	_dir_timer -= delta
	if _dir_timer <= 0.0:
		_dir_timer = 0.12
		# 血量健康时去吃宝石(升级 build), 危险时才逃 —— 否则永远 lv1, 测不出后期/通关路径
		var hp_ratio := float(p.hp) / float(p.max_hp_value())
		var dir := _kite_dir(p, hp_ratio)
		_apply_dir(dir)

	if god:
		p.hp = p.max_hp_value()
		p.invuln_timer = 1.0


# 移动策略: 血量健康 => 冲最近宝石(升级 build, 宝石磁吸会自动吸附, 不必踩到)
#           危险/贴身 => 向外逃 + 切线绕圈;  贴墙 => 叠加向内修正(否则被压墙角打死)
func _kite_dir(p: Node2D, hp_ratio: float) -> Vector2:
	if style == STYLE_GLASS:
		return _glass_dir(p)
	if style == STYLE_KITE:
		return _kite_only_dir(p)
	return _balanced_dir(p, hp_ratio)


# glass(极限承伤): 永不逃, 直冲最近怪堆中心贴身输出。只保留贴墙向内的修正,
# 避免被压在边界外。验证"贴脸打法"会不会崩(秒杀/掉帧/敌人挤成一坨)。
func _glass_dir(p: Node2D) -> Vector2:
	var threat: Node2D = null
	var td := INF
	for e in GameManager.enemies:
		if not is_instance_valid(e):
			continue
		var d := p.global_position.distance_squared_to(e.global_position)
		if d < td:
			td = d
			threat = e
	if threat == null:
		var g0 := _gem_dir(p)
		if g0 != Vector2.ZERO:
			return g0
		_angle += deg_to_rad(20.0)
		return Vector2.from_angle(_angle)
	var to_threat: Vector2 = (threat.global_position - p.global_position).normalized()
	return (to_threat + _wall_bias(p) * 0.6).normalized()


# kite(纯生存): 永不主动吃资源, 只远离最近威胁 + 绕圈。验证"零成长龟缩"的存活下限,
# 卡难度曲线 —— 若连这种打法都能轻松拖到通关, 说明压力不足; 若几秒就死, 说明无解。
func _kite_only_dir(p: Node2D) -> Vector2:
	var threat: Node2D = null
	var td := INF
	for e in GameManager.enemies:
		if not is_instance_valid(e):
			continue
		var d := p.global_position.distance_squared_to(e.global_position)
		if d < td:
			td = d
			threat = e
	if threat == null:
		_angle += deg_to_rad(20.0)
		return (_wall_bias(p) * 0.5 + Vector2.from_angle(_angle) * 0.5).normalized()
	var away: Vector2 = p.global_position - threat.global_position
	var norm := away.normalized() if away.length() > 0.01 else Vector2.from_angle(_angle)
	var tangent := norm.rotated(deg_to_rad(70.0))
	return (norm * 0.7 + tangent * 0.3 + _wall_bias(p) * 0.6).normalized()


# balanced(默认): 血量健康冲宝石升级, 危险/贴身才逃
func _balanced_dir(p: Node2D, hp_ratio: float) -> Vector2:
	var threat: Node2D = null
	var td := INF
	for e in GameManager.enemies:
		if not is_instance_valid(e):
			continue
		var d := p.global_position.distance_squared_to(e.global_position)
		if d < td:
			td = d
			threat = e
	if threat == null:
		# 场上无敌人: 缓慢游走(顺带吃宝石)
		var g0 := _gem_dir(p)
		if g0 != Vector2.ZERO:
			return g0
		_angle += deg_to_rad(20.0)
		return Vector2.from_angle(_angle)

	var away: Vector2 = p.global_position - threat.global_position
	var norm := away.normalized() if away.length() > 0.01 else Vector2.from_angle(_angle)
	var tangent := norm.rotated(deg_to_rad(70.0))
	var threat_dist := sqrt(td)

	# 贴身(接触距离内)一律硬逃: 此时吃宝石必被打, 逃出去才有输出窗口。
	# god 模式例外: 玩家每帧 invuln_timer=1.0 完全无敌, 逃跑毫无意义, 反而会因
	# "敌人长期贴身→永远逃→永不吃宝石→等级冻结"陷入死亡螺旋(3 级制武器 Lv2 起步、
	# 清怪变慢时尤其明显)。无敌时贴身阈值不触发, 照常冲宝石把升级/进化路径跑全。
	if (threat_dist < 26.0 and not god) or hp_ratio <= 0.55:
		return (norm * 0.6 + tangent * 0.4 + _wall_bias(p) * 0.5).normalized()

	# 健康且未贴身: 以吃宝石为主(升级 = 生存力), 叠加少量退让与贴墙修正
	var g_dir := _gem_dir(p)
	if g_dir != Vector2.ZERO:
		return (g_dir * 0.7 + norm * 0.2 + _wall_bias(p) * 0.4).normalized()
	return (norm * 0.6 + tangent * 0.4 + _wall_bias(p) * 0.5).normalized()


# 朝最近宝石的方向; 无宝石返回 ZERO
func _gem_dir(p: Node2D) -> Vector2:
	var best: Node2D = null
	var bd := INF
	for g in GameManager.gems:
		if not is_instance_valid(g):
			continue
		var d := p.global_position.distance_squared_to(g.global_position)
		if d < bd:
			bd = d
			best = g
	if best == null:
		return Vector2.ZERO
	return (best.global_position - p.global_position).normalized()


# 靠战场边界时返回向内的方向(bot 常被压在墙角围殴致死, 需显式修正)
func _wall_bias(p: Node2D) -> Vector2:
	var b := GameManager.BOUND
	var m := 45.0
	var v := Vector2.ZERO
	if p.global_position.x < b.position.x + m:
		v.x += 1.0
	elif p.global_position.x > b.end.x - m:
		v.x -= 1.0
	if p.global_position.y < b.position.y + m:
		v.y += 1.0
	elif p.global_position.y > b.end.y - m:
		v.y -= 1.0
	return v


func _apply_dir(d: Vector2) -> void:
	_release_dir()
	if d.x > 0.3:
		Input.action_press("move_right")
	elif d.x < -0.3:
		Input.action_press("move_left")
	if d.y > 0.3:
		Input.action_press("move_down")
	elif d.y < -0.3:
		Input.action_press("move_up")


func _release_dir() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")


# ---------------- 升级自动选 ----------------
func _handle_levelup() -> void:
	if GameManager.state != GameManager.State.LEVEL_UP:
		return
	if not get_tree().paused:
		return

	var opts: Array = GameManager.roll_upgrade_options()
	if opts.is_empty():
		# 没有可选项: 直接恢复
		get_tree().paused = false
		GameManager.state = GameManager.State.PLAYING
		GameManager.main.hud.show_hud()
		return

	# 想要的选项没被抽到 => 重摇几次取档位最高的一组(动机见 REROLL_TRIES)。
	# 这次 roll 与 main.trigger_level_up 给 HUD 的那次是两条独立抽取, 重摇不动界面;
	# autopilot 直接调 on_upgrade_chosen, 也不依赖 HUD 卡片状态。
	var best_tier := _tier_of(opts)
	if best_tier < TIER_EVOLUTION:
		for _i in range(REROLL_TRIES):
			var alt: Array = GameManager.roll_upgrade_options()
			if alt.is_empty():
				continue
			var t := _tier_of(alt)
			if t > best_tier:
				best_tier = t
				opts = alt
			if t >= TIER_EVOLUTION:
				break

	GameManager.main.on_upgrade_chosen(_pick_upgrade(opts))


# 升级选档(纯测试驱动, 不改玩法数据): _opt_tier 给每项打一个档位, _pick_upgrade/_tier_of
# 取档位最高者。档位由高到低 ——
#   EVOLUTION 进化(满级武器+配对被动, 见 roll_upgrade_options 的 kind=="evolution")
#   PASSIVE   凑进化的配对被动(某把武器已满级、配对被动没满 => 升它把进化推进抽取池)
#   WEAPON_NEW 新武器(next_level==1); god 模式封顶 FOCUS_WEAPONS 把后降为 FALLBACK
#   WEAPON_MAX 把已有武器升到满级(解锁进化前置)
#   FALLBACK   兜底
# 为什么要有档位+重摇: 进化门槛是「武器满级 + 配对被动满级」**双满**。旧策略只认新武器,
# 拿满后剩余升级落 opts[0] 随机撒, 实测整局 lv=17 / 4 把满级 / **零进化**(双满从未同时成立)。
# 单加优先级链仍零进化(god6/god7): 配对被动在池里权重只有 1(新武器/进化是 5), 单次三选一
# 命中概率 ~7%, 凑满 3 级要几十次升级而一局只有 ~16 次 => 想要的选项极少被抽到。
# 故 _handle_levelup 在档位不足时重摇(见 REROLL_TRIES), 取能推进进化的那一组。
# god 封顶武器数: 铺满 7 把吃掉 7 次预算(军械加成让新武器一拿即 Lv2), 剩 9 次凑不出
# 「武器 Lv3(1) + 配对被动 Lv3(3)」的连续投入; 封顶 3 把 => ~7 次出第 1 个进化。
# 代价是另 4 把武器的 _draw 不在 god 局覆盖 —— 由非 god 普通自玩局(不封顶)补上。
func _pick_upgrade(opts: Array) -> Dictionary:
	# 取档位最高的那项(平档取先出现的)。档位语义只在 _opt_tier 一处定义, 与 _tier_of 共用。
	var pick: Dictionary = opts[0]
	var best := _opt_tier(pick)
	for o in opts:
		var t := _opt_tier(o)
		if t > best:
			best = t
			pick = o
	return pick


# 整组选项的最高档位(_handle_levelup 用它决定是否重摇)
func _tier_of(opts: Array) -> int:
	var best := 0
	for o in opts:
		best = maxi(best, _opt_tier(o))
	return best


# 单个选项的优先级档位
func _opt_tier(o: Dictionary) -> int:
	var kind := String(o["kind"])
	if kind == "evolution":
		return TIER_EVOLUTION
	var p = GameManager.player
	if kind == "upgrade" and p != null and _unlocks_evolution(String(o["id"]), p):
		return TIER_PASSIVE
	if kind == "weapon":
		var nl := int(o["next_level"])
		if nl == 1:
			# god 模式封顶武器数: 铺满 7 把会吃光整局升级预算, 凑不出进化的连续投入
			if p != null and god and p.weapon_levels.size() >= FOCUS_WEAPONS:
				return TIER_FALLBACK
			return TIER_WEAPON_NEW
		if nl == int(o["max_level"]):
			return TIER_WEAPON_MAX
	return TIER_FALLBACK


# 这个被动是否是某把「已满级且尚未进化」武器的配对被动
func _unlocks_evolution(stat_id: String, p: Node) -> bool:
	for w in GameManager.EVOLUTIONS:
		var evo: Dictionary = GameManager.EVOLUTIONS[w]
		if String(evo["passive"]) != stat_id:
			continue
		if not p.has_weapon(w) or p.is_evolved(w):
			continue
		if int(p.weapon_levels.get(w, 0)) >= int(GameManager.WEAPONS[w]["max_level"]):
			return true
	return false


# ---------------- 波间商店自动消费(autopilot 用) ----------------
# 有钱就按顺序买第一个买得起的, 买完直接继续
func _handle_shop() -> void:
	if GameManager.state != GameManager.State.SHOP:
		return
	for i in range(GameManager.cur_shop.size()):
		if GameManager.buy_shop_offer(i):
			break   # 只买一件就继续(测试节奏)
	GameManager.main.close_wave_shop()


# ---------------- 死亡/通关自动重开 ----------------
# 注意: 面向玩家的 restart() 已改为「进角色选择界面」, bot 无法点选,
# 所以这里直接清场 + start_game 重开一局, 才能连续压测存活/通关路径
func _handle_gameover() -> void:
	if GameManager.state != GameManager.State.GAME_OVER:
		return
	_round_end("DIED")
	_relaunch()


func _handle_victory() -> void:
	if GameManager.state != GameManager.State.VICTORY:
		return
	victories += 1
	_round_end("VICTORY")
	_relaunch()


func _relaunch() -> void:
	GameManager.main._clear_entities()
	GameManager.main.start_game(GameManager.current_character, GameManager.current_weapon)


func _round_end(outcome: String) -> void:
	round += 1
	_time_sum += GameManager.time_s
	_time_best = maxf(_time_best, GameManager.time_s)
	_log("ROUND %d %s | time=%.1f kills=%d lv=%d boss_kills=%d final_boss=%s" % [
		round, outcome, GameManager.time_s, GameManager.kills, GameManager.level,
		GameManager.boss_kills, str(GameManager.final_boss_spawned)])
	# headless 强退无关闭钩子, 每局滚动打印汇总(存活时长分布 => 判断 6 分钟通关是否可达)
	_log("SUMMARY | rounds=%d victories=%d avg_time=%.1f best_time=%.1f" % [
		round, victories, _time_sum / float(round), _time_best])


# ---------------- 战报与断言 ----------------
func _report() -> void:
	if GameManager.state != GameManager.State.PLAYING:
		return
	var p = GameManager.player
	if p == null:
		return

	# 实体数组一致性: 不应含失效/已回收对象
	var invalid := 0
	for e in GameManager.enemies:
		if not is_instance_valid(e):
			invalid += 1
	for g in GameManager.gems:
		if not is_instance_valid(g):
			invalid += 1
	for b in GameManager.projectiles:
		if not is_instance_valid(b):
			invalid += 1

	# 对象池一致性: 栈内节点均有效且已隐藏; 达到池容量
	var pool_stats := _pool_stats()

	# fps 字段(2026-09-09 排查"后期卡死"): headless 无 vsync/渲染, 测不出帧预算崩盘;
	# 带窗口跑局看后期 fps 是否跌到个位数 => 区分"逻辑死锁"与"渲染/逻辑过载"(用户体感都是"卡死")
	# ov=N(2026-09-09 无限成长): 超限层数总和。满配(池抽干)后每次升级都叠超限, ov 持续增长
	# => 证明 roll_upgrade_options 的池空兜底生效、apply_upgrade 的 overlimit 分支生效
	# bgm=当前背景音乐轨(2026-09-10): BGM 状态机全程静默 —— 切轨失败/卡在错误轨在战报里
	# 完全不可见。实测发现一条真 bug: play_bgm("battle") 只在 boss.die() 里调, Boss 若在波末
	# 没被打死就被 _clear_wave() 静默清场(die_without_reward 不切轨), BGM 会永远卡在 boss 轨
	# 直到下一个 Boss 登场或结算。低成长档(kite/非 god)波 4 的 1200 血 Boss 打不完就会触发。
	_log("t=%.1fs wave=%d lv=%d kills=%d hp=%.0f enemies=%d gems=%d bullets=%d invalid=%d fps=%.0f ov=%d bgm=%s wpn[%s] %s %s" % [
		GameManager.time_s, GameManager.wave, GameManager.level, GameManager.kills, p.hp,
		GameManager.enemies.size(), GameManager.gems.size(), GameManager.projectiles.size(),
		invalid, Engine.get_frames_per_second(), _overlimit_total(p), GameManager._bgm_current,
		_weapon_stats(p), pool_stats, _boss_stats()])

	# 硬断言: 实体数组含失效对象 = 池一致性 bug(与平衡无关), 立即报警
	if invalid > 0:
		_fail("实体数组含 %d 个失效对象" % invalid)


# 超限成长层数总和(无限成长项, 见 GameManager.OVERLIMIT): 满配后持续涨 => 升级永远有得点
func _overlimit_total(p: Node2D) -> int:
	var n := 0
	for k in p.overlimit_levels:
		n += int(p.overlimit_levels[k])
	return n


# 当前持有武器清单: "id级[*进化]", 用于确认长时间跑是否轮全所有武器(_draw 覆盖)
func _weapon_stats(p: Node2D) -> String:
	var out := PackedStringArray()
	for id in p.weapon_levels.keys():
		var s := "%s%d" % [id, p.weapon_levels[id]]
		if p.evolved_weapons.has(id):
			s += "*"
		out.append(s)
	return ",".join(out)


# Boss 状态追踪: 验证 120s 登场 → 放技能 → 掉血 → 死亡掉宝 全链路
func _boss_stats() -> String:
	for e in GameManager.enemies:
		if is_instance_valid(e) and e.get_script() != null and \
			e.get_script().resource_path.ends_with("boss.gd"):
			return "BOSS[h=%.0f/%.0f st=%d]" % [e.hp, e.max_hp, e.state]
	return ""


func _pool_stats() -> String:
	var parts: Array = []
	for pid in ObjectPool._pools:
		var pool: Dictionary = ObjectPool._pools[pid]
		var stack: Array = pool["stack"]
		var bad := 0
		for n in stack:
			if not is_instance_valid(n):
				bad += 1
			elif n.visible:
				bad += 1
		parts.append("%s=%d(%d坏)" % [pid, stack.size(), bad])
		if bad > 0:
			_fail("池 %s 含 %d 个异常节点" % [pid, bad])
	return "[" + " ".join(parts) + "]"