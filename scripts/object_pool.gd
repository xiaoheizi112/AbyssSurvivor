extends Node
## ObjectPool (Autoload) — 预分配对象池, 消除运行时 instantiate/queue_free 的 GC 抖动
## 节点常驻 main 树下, 靠 visible + process 开关控制活跃; release 只关开关 + 推回栈

var main: Node = null

var _pools := {}   # pool_id -> { "stack": Array[Node] }


# ================= 类型化工厂(统一在 main 下创建) =================

func spawn_bullet(pos: Vector2, vel: Vector2, dmg: float, team: String, pierce: int = 0, visual: String = "orb", proc: Dictionary = {}) -> Node2D:
	var b := acquire("bullet", "res://scripts/bullet.gd")
	GameManager.projectiles.append(b)
	b.setup(pos, vel, dmg, team, pierce, visual, proc)
	return b


# affix2/elite 透传给 enemy.setup(精英 = 双词缀 + 升格档); 分裂子代与 Boss 召唤物
# 一律显式传 ""/""/false —— 子代带精英会指数爆炸, 召唤物带精英会绕过波次门槛。
func spawn_enemy(kind: int, pos: Vector2, affix: String = "", affix2: String = "", elite: bool = false) -> Node2D:
	var e := acquire("enemy", "res://scripts/enemy.gd")
	e.setup(kind, affix, affix2, elite)
	e.global_position = pos
	GameManager.enemies.append(e)
	return e


func spawn_boss(appearance: int, pos: Vector2) -> Node2D:
	var b := acquire("boss", "res://scripts/boss.gd")
	b.setup(appearance)
	b.global_position = pos
	GameManager.enemies.append(b)
	return b


func spawn_gem(pos: Vector2, xp_value: float) -> Node2D:
	var g := acquire("gem", "res://scripts/gem.gd")
	g.setup(pos, xp_value)
	GameManager.gems.append(g)
	return g


func spawn_coin(pos: Vector2, value: int) -> Node2D:
	var c := acquire("coin", "res://scripts/coin.gd")
	c.setup(pos, value)
	GameManager.coins_list.append(c)
	return c


func spawn_pickup(pos: Vector2, kind: String) -> Node2D:
	var p := acquire("pickup", "res://scripts/pickup.gd")
	p.setup(pos, kind)
	return p


func acquire_effect() -> Node2D:
	return acquire("effect", "res://scripts/effect.gd")


func acquire_pixel_fx() -> Node2D:
	return acquire("pixel_fx", "res://scripts/pixel_fx.gd")


func spawn_damage_number(pos: Vector2, val: float, is_crit: bool = false) -> Node2D:
	var d := acquire("damage_number", "res://scripts/damage_number.gd")
	d.setup(pos, val, is_crit)
	return d


# ================= 池核心 =================

func acquire(pool_id: String, script_path: String) -> Node2D:
	var pool := _pool(pool_id)
	var node: Node2D
	if pool["stack"].size() > 0:
		node = pool["stack"].pop_back()
	else:
		node = Node2D.new()
		node.set_script(load(script_path))
		node.set_meta("pool_id", pool_id)
		main.add_child(node)
	node.visible = true
	node.set_process(true)
	node.set_physics_process(true)
	return node


func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	node.visible = false
	node.set_process(false)
	node.set_physics_process(false)
	var pool_id: String = node.get_meta("pool_id", "")
	if pool_id != "" and _pools.has(pool_id):
		_pools[pool_id]["stack"].push_back(node)


func prewarm(pool_id: String, script_path: String, count: int) -> void:
	var pool := _pool(pool_id)
	for i in range(count):
		var n := Node2D.new()
		n.set_script(load(script_path))
		n.set_meta("pool_id", pool_id)
		main.add_child(n)
		n.visible = false
		n.set_process(false)
		n.set_physics_process(false)
		pool["stack"].push_back(n)


func _pool(pool_id: String) -> Dictionary:
	if not _pools.has(pool_id):
		_pools[pool_id] = {"stack": []}
	return _pools[pool_id]


func reset() -> void:
	# 场景重载后, 池内旧节点随旧场景一并释放, 需清空栈避免悬空引用
	_pools.clear()