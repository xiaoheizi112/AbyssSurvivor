extends Node
## Settings (Autoload) — 全局设置: 音量 / 难度 / 倍速; 持久化到 user://settings.cfg
## 移动键固定 WASD(唯一方向键方案), 不支持重映射(见 _ensure_actions)

const SAVE_PATH := "user://settings.cfg"

var master_volume: float = 1.0
# 难度: 0=简单 1=普通(默认, 与已调校平衡基线一致) 2=困难
var difficulty: int = 1
# 游戏倍速: 通过 Engine.time_scale 全局缩放(暂停系统 get_tree().paused 与其独立)
var game_speed: float = 1.0

var _cfg := ConfigFile.new()


func _ready() -> void:
	_ensure_actions()
	load_settings()
	apply_volume()
	apply_game_speed()


# 注册移动 action: 固定 WASD 单套(方向键已移除, 字母键为唯一方向方案)。已存在则跳过。
func _ensure_actions() -> void:
	var defaults := {
		"move_up": [KEY_W],
		"move_down": [KEY_S],
		"move_left": [KEY_A],
		"move_right": [KEY_D],
	}
	for action in defaults:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in defaults[action]:
			InputMap.action_add_event(action, _key_event(k))


func load_settings() -> void:
	if _cfg.load(SAVE_PATH) != OK:
		return   # 首次运行, 用默认值
	master_volume = float(_cfg.get_value("audio", "master_volume", 1.0))
	difficulty = int(_cfg.get_value("gameplay", "difficulty", 1))
	game_speed = float(_cfg.get_value("gameplay", "game_speed", 1.0))


func save_settings() -> void:
	# test_mode gate(与 save_meta/save_suspend 同纪律): 冒烟/自检进过设置面板就会触发保存,
	# 不 gate 会污染玩家真实 settings.cfg(2026-09-09 实测 difficulty 被测试流程改写)
	if GameManager.test_mode:
		return
	_cfg.set_value("audio", "master_volume", master_volume)
	_cfg.set_value("gameplay", "difficulty", difficulty)
	_cfg.set_value("gameplay", "game_speed", game_speed)
	_cfg.save(SAVE_PATH)


func apply_game_speed() -> void:
	Engine.time_scale = clampf(game_speed, 0.5, 3.0)


func apply_volume() -> void:
	# 0~1 线性 → dB; 0 需要极小值避免 -inf(Master 总线 index=0)
	var v := clampf(master_volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


func _key_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	@warning_ignore("int_as_enum_without_cast")
	ev.keycode = code
	@warning_ignore("int_as_enum_without_cast")
	ev.physical_keycode = code
	return ev