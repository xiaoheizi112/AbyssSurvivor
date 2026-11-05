extends RefCounted
class_name StatusFx
## StatusFx — 状态效果系统(静态工具, enemy/boss 共享)
## 状态池: freeze 冰冻(定身+受伤+30%) / burn 燃烧(DoT) / poison 中毒(可叠 3 层 DoT) / stun 眩晕(定身)
##        / bleed 流血(可叠 DoT, 撕裂缝隙) / slow 减速(移动变慢) / vulnerable 易伤(受伤+15%)
## 每个持有者维护一个 _status: Dictionary, 键=状态名, 值={t 剩余时长, power 每跳伤害, tick 距下次结算, stacks 层数, factor 强度系数}
## DoT 通过 owner.take_damage(power, true) 结算(true=不触发击退); 触发源见 bullet/lightning 与进化附加 proc

# 状态配置: [默认时长, DoT结算间隔, 是否定身, 是否禁止行动, 染色]
# slow/vulnerable 无 DoT(interval=0), 靠 factor 提供数值(减速倍率 / 易伤倍率)
const CONFIG := {
	"freeze":     {"dur": 1.2, "interval": 0.0, "root": true,  "noact": true,  "tint": Color(0.55, 0.82, 1.0)},
	"burn":       {"dur": 3.0, "interval": 0.5, "root": false, "noact": false, "tint": Color(1.0, 0.60, 0.30)},
	"poison":     {"dur": 4.0, "interval": 0.8, "root": false, "noact": false, "tint": Color(0.55, 0.92, 0.45)},
	"stun":       {"dur": 0.8, "interval": 0.0, "root": true,  "noact": true,  "tint": Color(1.0, 1.0, 0.60)},
	"bleed":      {"dur": 3.0, "interval": 0.6, "root": false, "noact": false, "tint": Color(0.85, 0.35, 0.30)},
	"slow":       {"dur": 1.6, "interval": 0.0, "root": false, "noact": false, "tint": Color(0.60, 0.85, 1.0)},
	"vulnerable": {"dur": 3.0, "interval": 0.0, "root": false, "noact": false, "tint": Color(0.90, 0.75, 0.35)},
}
const POISON_MAX_STACKS := 3
const BLEED_MAX_STACKS := 3
# slow / vulnerable 的默认强度系数(可被 apply 的 factor 参数按来源覆写)
const SLOW_FACTOR_DEFAULT := 0.7      # 速度倍率: 0.7 = 减速 30%
const VULN_FACTOR_DEFAULT := 1.15     # 受伤倍率: 1.15 = 易伤 +15%
# 染色优先级(多状态并存时取最高优先级的色): CC > 燃烧/易伤 > 减速 > 中毒/流血
const TINT_PRIORITY := ["stun", "freeze", "burn", "vulnerable", "slow", "poison", "bleed"]


# 施加/刷新一个状态; resist 为持续时长倍率(Boss 抗性 <1)
# power 仅 burn/poison/bleed 用(每跳 DoT 伤害), factor 仅 slow/vulnerable 用(强度系数)
# max_stacks 仅 poison/bleed 用(叠层上限; 0 = 用表默认 3)
#
# factor / max_stacks 是**按来源分级**的通道: 同一状态在不同等级/武器下强度可以不同
# (圣环 Lv3 易伤 +25% vs Lv1 +15%、回旋镖 Lv3 减速 0.55 vs Lv2 0.7、飞刀 Lv2 毒 5 层 vs Lv1 3 层)。
# 传 <=0 表示"用默认值", 这样老调用点(只传 power)逐字节等价。
# 刷新时 factor / max_stacks 一律**取较大值**: 高等级的强效果不该被随后一次低等级刷新抹掉
# (与 power 的 maxf 同理); 否则高频武器会把刚挂上的 Lv3 易伤刷回 Lv1 的 15%。
# 已存在则刷新时长, poison/bleed 叠层
static func apply(status: Dictionary, kind: String, power: float = 0.0, resist: float = 1.0,
		factor: float = 0.0, max_stacks: int = 0) -> void:
	if not CONFIG.has(kind):
		return
	var cfg: Dictionary = CONFIG[kind]
	var dur: float = float(cfg["dur"]) * resist
	# 归一化 factor: <=0 一律回退到该状态的默认值(0 对 slow 是合法数字但语义上等于"没传")
	var f: float = factor if factor > 0.0 else default_factor(kind)
	# 归一化 max_stacks: <=0 回退到表默认
	var cap: int = max_stacks if max_stacks > 0 else default_max_stacks(kind)
	if status.has(kind):
		var s: Dictionary = status[kind]
		s["t"] = maxf(float(s["t"]), dur)   # 刷新取较长剩余, 不无限叠加
		# 旧条目可能没有 factor/max_stacks 键(本函数改造前挂上的): 用 .get 带默认值读, 不 KeyError
		s["factor"] = maxf(float(s.get("factor", f)), f)
		s["max_stacks"] = maxi(int(s.get("max_stacks", cap)), cap)
		if kind == "poison" or kind == "bleed":
			s["stacks"] = mini(int(s["stacks"]) + 1, int(s["max_stacks"]))
			s["power"] = maxf(float(s["power"]), power)
		return
	status[kind] = {
		"t": dur,
		"power": power,
		"tick": float(cfg["interval"]),   # 首次结算等满一个间隔
		"stacks": 1,
		"factor": f,
		"max_stacks": cap,
	}


# 该状态的默认强度系数(slow 速度倍率 / vulnerable 受伤倍率); 其余状态返回 0(不参与 factor 通道)
static func default_factor(kind: String) -> float:
	if kind == "slow":
		return SLOW_FACTOR_DEFAULT
	if kind == "vulnerable":
		return VULN_FACTOR_DEFAULT
	return 0.0


# 该状态的默认叠层上限(poison/bleed = 3); 其余状态返回 1(不可叠)
static func default_max_stacks(kind: String) -> int:
	if kind == "poison" or kind == "bleed":
		return POISON_MAX_STACKS
	return 1


# 每帧结算: 递减时长, burn/poison/bleed 到点造成 DoT; 返回速度倍率(定身=0, 减速=0.7)
# owner 需提供 take_damage(amount, from_dot) 与 _dead 字段(不加类型标注: 走动态派发, 静态 Node 上没有这些成员)
static func tick(status: Dictionary, owner, delta: float) -> float:
	if status.is_empty():
		return 1.0
	var expired: Array = []
	for kind in status.keys():
		var s: Dictionary = status[kind]
		s["t"] -= delta
		if float(s["t"]) <= 0.0:
			expired.append(kind)
			continue
		var cfg: Dictionary = CONFIG[kind]
		var interval: float = float(cfg["interval"])
		if interval > 0.0:
			s["tick"] -= delta
			if float(s["tick"]) <= 0.0:
				s["tick"] = interval
				var dmg: float = float(s["power"])
				if kind == "poison" or kind == "bleed":
					dmg *= float(int(s["stacks"]))   # 毒/流血按层数放大每跳
				if dmg > 0.0 and is_instance_valid(owner) and not owner._dead:
					owner.take_damage(dmg, true)
	for kind in expired:
		status.erase(kind)
	return speed_mult(status)


# 速度倍率: 冰冻/眩晕定身(0), slow 减速(读该条目的 factor, 默认 0.7), 否则 1
static func speed_mult(status: Dictionary) -> float:
	for kind in ["freeze", "stun"]:
		if status.has(kind):
			return 0.0
	if status.has("slow"):
		# 按来源分级的减速强度(回旋镖 Lv3 = 0.55 比 Lv2 的 0.7 更狠); 夹在 (0,1] 防传错值变成加速
		return clampf(float(status["slow"].get("factor", SLOW_FACTOR_DEFAULT)), 0.05, 1.0)
	return 1.0


# 是否禁止行动(攻击/施法): 冰冻/眩晕
static func blocks_action(status: Dictionary) -> bool:
	return status.has("freeze") or status.has("stun")


# 受伤倍率: 冰冻 +30%, vulnerable 易伤(读该条目的 factor, 默认 1.15)(乘算叠加); 其余状态不改变受伤
static func damage_taken_mult(status: Dictionary) -> float:
	var m := 1.0
	if status.has("freeze"):
		m *= 1.3
	if status.has("vulnerable"):
		# 按来源分级的易伤强度(圣环 Lv3 = 1.25 比 Lv1 的 1.15 更狠); 夹在 [1,3] 防传错值变成减伤
		m *= clampf(float(status["vulnerable"].get("factor", VULN_FACTOR_DEFAULT)), 1.0, 3.0)
	return m


# 当前应显示的染色(白=无状态); 取优先级最高的活跃状态色
static func tint_color(status: Dictionary) -> Color:
	for kind in TINT_PRIORITY:
		if status.has(kind):
			return Color(CONFIG[kind]["tint"])
	return Color(1, 1, 1)


# 触发源掷骰: 读玩家进化附加效果的 proc 概率(见 GameManager.EVOLUTION_TRAITS), 命中敌人时按概率施加对应状态
# hit_damage 用于换算 burn/poison 的每跳 DoT(随武器伤害缩放, 后期更强)
static func try_proc_from_player(status: Dictionary, hit_damage: float, resist: float = 1.0) -> void:
	var p = GameManager.player
	if p == null or not p.has_method("proc_chance"):
		return
	if GameManager._rng.randf() < p.proc_chance("freeze"):
		apply(status, "freeze", 0.0, resist)
	if GameManager._rng.randf() < p.proc_chance("burn"):
		apply(status, "burn", hit_damage * 0.18, resist)
	if GameManager._rng.randf() < p.proc_chance("poison"):
		apply(status, "poison", hit_damage * 0.12, resist)
