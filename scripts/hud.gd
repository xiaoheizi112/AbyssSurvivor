extends CanvasLayer
## HUD — 全部界面: 角色选择 / 战斗 HUD / 升级三选一 / 暂停 / 死亡结算 / Boss 血条
## 全部用代码构建 Control 节点, 保证无 .tscn 也能跑

# 逻辑分辨率(与 project.godot viewport 一致); 所有 UI 坐标/字号基于此, 整屏 2× 整数放大上窗
const W := 640.0
const H := 360.0

# 角色选择界面布局: 左侧纵向列表(可扩展/滚动) + 右侧详情面板
const CHAR_LIST_X := 40.0
const CHAR_LIST_W := 200.0
const CHAR_ITEM_H := 32.0
const CHAR_ITEM_PAD := 6.0        # 角色卡片水平内边距(左右对称, 内容不贴边框)
const CHAR_DETAIL_X := 260.0
const CHAR_DETAIL_W := 332.0
const CHAR_DETAIL_H := 208.0   # 详情面板高度(左属性 / 右武器详情共用)
const CHAR_DETAIL_Y := 66.0    # 详情面板/角色列表顶部 Y(两者同高对齐)
const CHAR_PORTRAIT := 48.0   # 32×32 素材 1.5× 放大显示(整屏 2× 后为 96px, 仍清晰且更省纵向空间)

# 角色详情动效: 切换瞬间头像脉冲回弹 + 面板内缩回正 + 名字上冲 + 文字淡入 + 选中卡片外弹
# (一次性 tween, 只在选中值真正变化时触发)。右侧武器详情面板复用同套参数做同样的回弹。
const CHAR_PUNCH := 1.16        # 头像/武器图标脉冲峰值缩放(从该值回弹到 1)
const CHAR_PANEL_DIP := 0.985   # 详情面板内盒切换瞬间的轻微内缩(→1)
const CHAR_NAME_PUNCH := 1.14   # 名字上冲峰值缩放
const CHAR_CARD_PUNCH := 1.05   # 左侧选中卡片切换瞬间外弹
const CHAR_FADE_FROM := 0.35    # 属性文字切换瞬间起始透明度(self_modulate, →1)
const CHAR_PUNCH_SEC := 0.32    # 过渡总时长

# 武器选择栏(角色选择界面底部): 6 个武器 tile 横向排布居中
const WPN_TILE_W := 80.0
const WPN_TILE_H := 44.0
const WPN_TILE_GAP := 8.0

# 血条配色: 按血量百分比分档(>60% 绿 / 30~60% 黄 / <30% 红并脉动)
const HP_HIGH := Color(0.85, 0.22, 0.26)    # 血条基色: 红(与 Boss 条同红, "红=生命值"语义统一)
const HP_LOW := Color(1.00, 0.35, 0.28)     # 低血警告: 亮红, 整条"亮起"与常态深红拉开对比
const HP_LOW_PULSE := Color(1.00, 0.55, 0.35)
const XP_COLOR := Color(0.35, 0.85, 0.40)   # 经验条: 绿(沿用原血条绿)
const BAR_BG := Color(0.08, 0.08, 0.10, 0.85)

# 数值平滑插值速度(约 0.15s 滑到目标)
const LERP_RATE := 12.0

# 左上状态条组布局: 血条在上 / 经验条在下, 同宽(BAR_W)贴屏幕左边左缘对齐; 经验条更矮(BAR_XP_H)
# 加粗加宽提升可读性: 血量数值内嵌血条居中(白字描边叠任意填充色), 等级数字放血条右侧同层级
const BAR_X := 8.0
const BAR_Y := 8.0
const BAR_W := 150.0
const BAR_HP_H := 16.0      # 血条高度: 加粗到可内嵌「64 / 100」血量数值(字号 8, 行高 12)
const BAR_XP_H := 10.0      # 经验条高度: 略细于血条, 主次分明
const BAR_GAP := 4.0        # 两条间距(2× 放大后清晰不贴)
const BAR_HP_Y := BAR_Y                      # = 8
const BAR_XP_Y := BAR_HP_Y + BAR_HP_H + BAR_GAP   # = 26

# 升级三选一卡片布局(3 张卡整体水平居中)
const LVL_CARD_W := 100.0
const LVL_CARD_H := 90.0
const LVL_CARD_GAP := 110.0
const LVL_CARD_X0 := W / 2.0 - 160.0
const LVL_CARD_Y := 120.0
# 选中演出: 卡片抬升量(▼ 与选中框同步跟随) / 切换瞬间的抖动幅度与总时长
# / 选中框外扩边距 / 框子呼吸脉动的亮度下限
const LVL_CARD_LIFT := 3.0
const LVL_SHAKE_DEG := 7.0
const LVL_SHAKE_SEC := 0.40
const LVL_FRAME_PAD := 4.0
const LVL_FRAME_PULSE_LO := 0.62
const LVL_FRAME_BG_ALPHA := 0.07   # 选中框内底衬: 同稀有度色低透明度铺一层

# 本局属性面板: item_mods 键 → 展示名 + 数值格式(pct 百分比 / flat 整数); 未列入的键跳过
const STAT_MOD_LABELS := {
	"damage_mult":       {"name": "伤害",     "fmt": "pct"},
	"attack_speed_mult": {"name": "攻速",     "fmt": "pct"},
	"move_speed_mult":   {"name": "移速",     "fmt": "pct"},
	"cooldown_mult":     {"name": "冷却",     "fmt": "pct"},
	"pick_range_mult":   {"name": "拾取范围", "fmt": "pct"},
	"max_hp_mult":       {"name": "生命",     "fmt": "pct"},
	"coin_mult":         {"name": "金币获取", "fmt": "pct"},
	"max_hp_flat":       {"name": "生命上限", "fmt": "flat"},
	"crit_chance":       {"name": "暴击率",   "fmt": "pct"},
}

# 本局加成面板: Tab 折叠/展开(仅 PLAYING)。展开带标题行、最多显示 BUFFS_SHOW_MAX 项(超出截断 …(+N));
# 折叠只留一行「N 项」+ 窄宽, 后期 14 项满铺不再糊住左上视野。折叠态会话内保持(不持久化)
const BUFFS_SHOW_MAX := 6
const BUFFS_COLLAPSED_W := 48.0   # 折叠宽: 够放「14 项」+ 边距, 左侧视野全露出

# ---------- 图鉴布局(640×360) ----------
# 图书馆古籍风: 顶部 tab 行 + 左侧索引卡片抽屉 + 右侧摊开的双页书
# 常量全部 CX_ 前缀(本文件 const 不可重名)
const CX_TITLE_Y := 12.0
const CX_TAB_Y := 36.0
const CX_TAB_W := 72.0
const CX_TAB_H := 22.0
const CX_TAB_GAP := 6.0
const CX_BODY_Y := 60.0
const CX_BODY_H := 270.0      # 列表与书同高, 底边 330, 下方留操作提示
const CX_LIST_X := 28.0
const CX_LIST_W := 170.0
const CX_ITEM_H := 32.0
const CX_ITEM_PAD := 6.0      # 列表项水平内边距(选中/未选中共用, 切换时内容不跳动)
const CX_PORTRAIT := 56.0     # 32×32 素材 1.75× 显示; boss sheet 是 32×36 竖图, 48 太局促
const CX_STATS_W := 150.0     # 左页数值列宽: 140 时数值列会折行(页内容宽 180 容得下)
const CX_HINT_Y := 338.0

# 书本几何(全局坐标): 封面 414×270, 右缘 616 留 24px 边距
const CX_BOOK_X := 202.0
const CX_BOOK_Y := 60.0
const CX_BOOK_W := 414.0
const CX_BOOK_H := 270.0
# 以下均为 _cx_book 内的局部坐标
const CX_PAGE_L_X := 6.0
const CX_PAGE_R_X := 212.0
const CX_PAGE_W := 196.0
const CX_PAGE_Y := 4.0
const CX_PAGE_H := 262.0      # 页底局部 266, 封面下沿露 4px
const CX_SPINE_LX := 202.0
const CX_SPINE_W := 10.0
const CX_PAGE_MARGIN := 8.0   # 页左右内边距; 上下用 CX_PAGE_PAD_V → 左页内容 180×250
const CX_PAGE_PAD_V := 6.0
const CX_PAGE_TOP_R := 14.0   # 右页上内边距(留出滚动提示条, 否则提示压住文案首行)
const CX_LIST_BACK_X := 24.0  # 索引卡片抽屉背板(scroll 后垫一层木色面板)
const CX_LIST_BACK_W := 178.0

# 动效时序(秒)
const CX_FLIP_TIME := 0.15        # 单页方向性翻页(切条目 / 切分类共用)
const CX_FLIP_PAGE_TIME := 0.10   # 切分类连翻的每页(当前未用, 保留给未来多页连翻)
const CX_TAB_FLIPS := 1           # 切分类翻页数: 原为 3 页连翻, 观感像"连续加载好几次", 已改为单页
const CX_OPEN_TIME := 0.35        # 书本展开
const CX_CLOSE_TIME := 0.28       # 书本合上(合完才切状态)
const CX_RIBBON_TIME := 0.30
const CX_RIBBON_COLORS := [
	Color(0.557, 0.173, 0.173),   # 角色: 暗红书签
	Color(0.659, 0.463, 0.165),   # 武器: 金棕
	Color(0.180, 0.290, 0.478),   # BOSS: 靛蓝
	Color(0.180, 0.353, 0.227),   # 杂兵词缀: 墨绿
	Color(0.620, 0.478, 0.137),   # 成就: 古铜金书签
]

# ---------- 古籍墨色调色板 ----------
# 纸底(#E8DCC0)上原暗底霓虹配色对比度全废, 一律换暗墨系; 文案字符串本身不动
const CX_INK_LABEL := "#8A3B2A"   # 数值标签(原 #FF6A5A)
const CX_INK_BODY := "#3B2E22"    # 正文/数值(原 #E6F2F5)
const CX_INK_ACCENT := "#2F5D6B"  # 规则/小标题(原 #57C7D6)
const CX_INK_DIM := "#7A6A55"     # 次级说明(原 #999999)
const CX_INK_NAME := Color(0.353, 0.227, 0.063)   # 条目名深棕金(原金色)
const CX_INK_TAG := Color(0.184, 0.369, 0.420)    # 定位标签
const CX_PAPER_FALLBACK := Color(0.859, 0.820, 0.706)   # 缺烘焙纸图时的平色
const CX_LEATHER := Color(0.227, 0.165, 0.110)          # 封面皮革棕
const CX_LEATHER_EDGE := Color(0.341, 0.251, 0.165)     # 封面亮棕边

const CX_TAB_NAMES := ["角 色", "武 器", "BOSS", "杂兵词缀", "成 就"]
const CX_TAB_CHAR := 0
const CX_TAB_ACH := 4         # 成就 tab: 全局共享, 读 GameManager.ACHIEVEMENTS + achieved

# 各界面根 Control
var char_screen: Control = null
var game_hud: Control = null
var levelup_screen: Control = null
var gameover_screen: Control = null
var victory_screen: Control = null
var boss_bar: Control = null
var settings_screen: Control = null
var shop_screen: Control = null
var wave_shop_screen: Control = null
var codex_screen: Control = null

# 主菜单焦躁氛围动效引用(心跳脉动 / 天空红光闪烁 / 余烬粒子 / 标题抖动)
var _menu_pulse: ColorRect = null
var _menu_glow: TextureRect = null
var _menu_title: Control = null
var _menu_t := 0.0
var _menu_flicker := 1.0

# 键盘导航状态(用户要求全界面可键盘操作; 沿用 _unhandled_input + _sel 索引 + _refresh 模式)
# 各 :sel 为当前高亮项索引, _btns 为可聚焦项数组; _clear_all 里对应置 null / 归零
var _menu_btns: Array = []      # 主菜单按钮(无存档 5 项: 开始/设置/商店/图鉴/退出; 有存档 6 项: 继续在最前)
var _menu_sel: int = 0
var _menu_confirm_screen: Control = null   # 「重新开始」确认层(单槽存档将被覆盖)
var _menu_confirm_btns: Array = []
var _menu_confirm_sel: int = 0
var _result_btns: Array = []    # 死亡/通关结算 2 按钮(重开/返回菜单); 两界面共用
var _result_sel: int = 0
var _meta_shop_back: Button = null    # 局外商店底部「返回」按钮(第 N 项, 商品行之外的锚点)
var _meta_shop_sel: int = 0
var _settings_row: int = 3       # 设置面板焦点行: 0音量 1难度 2倍速 3底部按钮行
var _settings_col: int = 0
var _settings_vol_slider: HSlider = null
var _settings_row_labels: Array = []   # 音量/难度/倍速三行的行标签(活动行金高亮)
var _settings_diff_btns: Array = []
var _settings_spd_btns: Array = []
var _settings_spd_values: Array = [0.5, 1.0, 2.0, 3.0]
var _settings_bottom_btns: Array = []

# 长按方向键连发: 首次按下立即走一步(单击路径), 按住 NAV_HOLD_DELAY 后每 NAV_HOLD_INTERVAL 自动续步;
# 由 _process 驱动而非 OS 键盘回显, 所以各状态分支的 echo 过滤不受影响; 续步静音(防 pickup 连点爆音)
const NAV_HOLD_DELAY := 0.35     # 按住多久后开始连发(秒)
const NAV_HOLD_INTERVAL := 0.09  # 连发间隔(秒)
var _hold_keycode: Key = KEY_NONE  # 当前按住的导航键(WASD)
var _hold_state: int = -1          # 按下那一刻的状态, 状态变了连发立即作废
var _hold_elapsed: float = 0.0     # 按住累计秒数
var _hold_next: float = 0.0        # 下一次续步时刻(相对按下)

# 战斗 HUD 动态元素
var _coin_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_label: Label = null
var _xp_bar: ProgressBar = null
var _level_label: Label = null
var _time_label: Label = null
var _kills_label: Label = null
var _kills_icon: TextureRect = null
var _weapon_labels: Dictionary = {}
# 本局加成面板(血条正下方, 读 player.item_mods 非零项): 面板 + 标题行 + bbcode 文本 + 上次缓存串
var _buffs_panel: PanelContainer = null
var _buffs_header: HBoxContainer = null
var _buffs_text_label: RichTextLabel = null
var _buffs_last: String = ""
var _buffs_collapsed := false   # 会话偏好: _clear_all 不清, 重开/恢复局后保持
# 诅咒标签(右上金币下方, curse_level==0 隐藏): _curse_last 缓存避免每帧改 text
var _curse_label: Label = null
var _curse_last: int = -1
# 波次标签缓存: 文本随倒计时每秒变一次, 不必每帧改 text(同 _curse_last 的做法)
var _wave_label_last: String = ""
# 武器槽: id -> { panel:PanelContainer, name:Label, badge:Label, icon:TextureRect, base_scale:Vector2 }

# 填充样式引用(缓存以便每帧改色, 不重复建 StyleBoxFlat)
var _hp_fill: StyleBoxFlat = null
var _xp_fill: StyleBoxFlat = null

# 升级三选一的键盘导航状态(A/D 选择, 空格确认)
var _levelup_cards: Array = []        # PanelContainer, 索引与选项一一对应
var _levelup_options: Array = []      # 选项字典, 确认时按索引取
var _levelup_sel: int = 0             # 当前高亮索引
var _levelup_marker: Label = null     # 选中卡片上方的 ▼ 指示
var _levelup_frame: Panel = null      # 选中框(金色描边), 在卡片间滑动并呼吸脉动, 盖在卡片之上
var _frame_pulse_tw: Tween = null     # 选中框脉动循环(无限循环, 清界面时必须显式 kill)
var _card_shake_tws: Array = []       # 各卡片晃动 tween(绑在 hud 上不随卡片释放, 需显式 kill)
var _levelup_sel_tw: Tween = null     # 选中切换位移动画(框/▼/卡片抬起), 快速连切时先 kill 旧的
# 升级三选一重抽(每局 LEVELUP_REROLL_MAX 次, 见 GameManager): 按钮 + 防连点时间戳 + 反馈 toast
# 时间戳用 Time.get_ticks_msec() 真实时钟 —— 升级界面树是暂停的, GameManager.time_s 不推进, 拿它做冷却永远不解锁
var _levelup_reroll_btn: Button = null
var _lvlup_reroll_t: int = 0
var _levelup_toast: Label = null
var _levelup_toast_tween: Tween = null

# 平滑过渡状态: 显示值与真实值分离, 每帧插值
var _hp_shown: float = 100.0
var _xp_shown: float = 0.0
var _hp_prev: float = 100.0
var _hp_flash: float = 0.0
var _pulse_t: float = 0.0
var _level_prev: int = 1

# 角色选择: id 列表由 CHARACTERS 派生(唯一真相源, 新增角色自动出现);
# 选中项 + 右侧详情引用, 选中切换时刷新内容
var char_ids: Array = []
var char_buttons: Array = []
var _selected_char: String = ""
var _char_scroll: ScrollContainer = null
var _detail_portrait: TextureRect = null
var _detail_name: Label = null
var _detail_info: RichTextLabel = null
# 角色/武器详情动效锚点: 面板内 VBox, 切换瞬间做轻内缩回弹
var _char_detail_inner: Control = null
var _weapon_detail_inner: Control = null
var _detail_weapon_name: Label = null
var _detail_weapon_summary: Label = null
var _detail_weapon_info: RichTextLabel = null
var _detail_weapon_icon: TextureRect = null

# 武器选择: id 列表由 WEAPONS 派生; 每角色独立装备(真相源 _char_weapons, 空串=无)
var weapon_ids: Array = []
var _weapon_buttons: Array = []
var _card_weapon_slots: Dictionary = {}   # char_id -> { "icon": TextureRect, "none": Label }
var _char_weapons: Dictionary = {}        # char_id -> weapon_id("" = 无); 无条目视为无
var _selected_weapon: String = ""         # 当前选中角色已选的武器(镜像 _char_weapons[_selected_char])
var _weapon_sel: int = 0                # 武器栏当前高亮索引
var _char_sel_tw: Tween = null          # 角色/武器选中切换回弹动画(快速连切先 kill 旧的, 防叠加)

# ---------- 图鉴界面 ----------
var _cx_tab: int = 0                    # 当前分类 tab 索引
var _cx_sel: int = 0                    # 当前 tab 内选中条目索引
var _cx_ids: Array = []                 # 当前 tab 的条目 id 列表(切 tab 时重建)
var _cx_tab_btns: Array = []            # tab Button, 索引与 CX_TAB_NAMES 对应
var _cx_item_panels: Array = []         # 左侧列表项 PanelContainer, 索引与 _cx_ids 对应
var _cx_item_subs: Array = []           # 列表项副标 Label, 与 _cx_item_panels 同序(选中态换色)
var _cx_list_box: VBoxContainer = null  # 列表容器(切 tab 时清空重建)
var _cx_scroll: ScrollContainer = null
var _cx_portrait: TextureRect = null
var _cx_name: Label = null
var _cx_tag: Label = null
var _cx_stats: RichTextLabel = null
var _cx_prose: RichTextLabel = null
var _cx_scroll_hint: Label = null  # 文案列溢出时的滚动提示(_process 每帧算可见性)
# 书本结构与动效: _cx_book 是整本书容器(开合动画只 tween 它), 书页/翻页层/书签都是其子节点
var _cx_book: Control = null
var _cx_left_page: Control = null
var _cx_right_page: Control = null
var _cx_page_flip: Control = null       # 翻页 overlay(内部类 CodexPageFlip)
var _cx_ribbon: Control = null          # 书签丝带(内部类 CodexRibbon)
var _cx_book_tw: Tween = null           # 开/合书
var _cx_page_tw: Tween = null           # 翻页(快速连按时 kill 旧的直接开新)
var _cx_ribbon_tw: Tween = null
var _cx_closing: bool = false           # 合书动画期间吞掉全部输入(ESC 连打 gate)
var _cx_anim_enabled: bool = true       # 自检/截图置 false: 跳过动画走直刷路径
var _cx_flip_dir: int = 1               # +1 向后翻 / -1 向前翻
var _cx_flip_pages: int = 1
var _cx_flip_swapped: bool = false      # 本次翻页是否已在过半时切过内容
var _cx_flip_sound_at: int = 1          # 连翻时下一个该响的整数页
var _cx_ribbon_to: int = 0              # 丝带动画的目标 tab(动画中 t=0.5 时换色)

# 音量滑条反馈节流(ms): 拖动时预览音量, 避免 value_changed 连续触发爆音
var _vol_feedback_last := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# ================= 主菜单 =================

func show_menu() -> void:
	_clear_all()
	var menu := _full_screen()
	menu.process_mode = Node.PROCESS_MODE_ALWAYS

	if ResourceLoader.exists("res://assets/ui/menu_bg.png"):
		var bg := TextureRect.new()
		bg.texture = load("res://assets/ui/menu_bg.png")
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		menu.add_child(bg)

	# 天空红光带(地平线以上): 垂直渐变(地平线最亮向上淡出), 避免硬边
	_menu_glow = TextureRect.new()
	_menu_glow.anchor_right = 1.0
	_menu_glow.anchor_bottom = 0.50
	var ggrad := Gradient.new()
	ggrad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	ggrad.colors = PackedColorArray([
		Color(0.75, 0.10, 0.14, 0.0),
		Color(0.75, 0.10, 0.14, 0.10),
		Color(0.85, 0.14, 0.16, 0.38)])
	var gtex := GradientTexture2D.new()
	gtex.fill_from = Vector2(0, 0)   # 默认 FILL_LINEAR: 从顶(透明)到底(亮红)
	gtex.fill_to = Vector2(0, 1)
	gtex.gradient = ggrad
	_menu_glow.texture = gtex
	_menu_glow.material = _additive_mat()
	menu.add_child(_menu_glow)

	# 全屏心跳脉动层: 暗红加色, 双峰心跳曲线驱动 alpha
	_menu_pulse = ColorRect.new()
	_menu_pulse.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_pulse.color = Color(0.55, 0.08, 0.10, 0.03)
	_menu_pulse.material = _additive_mat()
	menu.add_child(_menu_pulse)

	# 肉鸽风主标题: 逐字 terminal 色相循环 + 厚像素描边 + 硬投影 + 底部金线
	var title := Control.new()
	title.position = Vector2(0, 52)
	title.anchor_left = 0.0; title.anchor_right = 1.0
	var tt := "深渊幸存者"
	# 逐字: 终端绿→琥珀→铜色循环(肉鸽 ASCII/终端屏美学), 每字大小错落 + 基线错位
	var tt_colors := [
		Color(0.55, 1.0, 0.55), Color(0.95, 0.98, 0.60), Color(1.0, 0.78, 0.35),
		Color(1.0, 0.55, 0.45), Color(0.55, 1.0, 0.85),
	]
	# 手动居中: CJK 字形接近方字, 每字占用 ≈ 字号; 累计总宽后从中心铺开
	var tt_sizes: Array[int] = [30, 28, 30, 28, 30, 28]
	var gap := 3.0
	var total_w := 0.0
	for s in tt_sizes:
		total_w += float(s)
	total_w += gap * float(tt_sizes.size() - 1)
	var cursor := (W - total_w) / 2.0
	for i in range(tt.length()):
		var gl := _label(tt[i], tt_sizes[i])
		gl.add_theme_color_override("font_color", tt_colors[i % tt_colors.size()])
		gl.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02))
		gl.add_theme_constant_override("outline_size", 3)
		gl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
		gl.add_theme_constant_override("shadow_offset_x", 3)
		gl.add_theme_constant_override("shadow_offset_y", 3)
		gl.position = Vector2(cursor, -2.0 if i % 3 == 0 else 1.0)
		title.add_child(gl)
		cursor += float(tt_sizes[i]) + gap
	# 底部金线: 金橙色分隔, 收窄在两端各留一侧符文
	var sep := _label("◆ ──── ✦ ──── ◆", 8)
	sep.position = Vector2(0, 96)
	sep.anchor_left = 0.0; sep.anchor_right = 1.0
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sep.add_theme_color_override("font_color", Color(1.0, 0.70, 0.30, 0.95))
	title.add_child(sep)
	menu.add_child(title)
	_menu_title = title

	var subtitle := _label("自动攻击 · 拾取经验升级 · 闪避怪潮 · 挺过 %d 波击败深渊领主" % GameManager.WAVE_COUNT, 10)
	subtitle.position = Vector2(0, 106)
	subtitle.anchor_left = 0.0; subtitle.anchor_right = 1.0
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.80, 0.80, 0.82))
	menu.add_child(subtitle)

	# 键盘导航提示(与其它界面一致的按键提示, 说明选中项可键盘切换)
	var hint := _label("W/S 选择 · 长按快速切换 · 空格/回车 确认", 7)
	hint.position = Vector2(0, H - 16)
	hint.anchor_left = 0.0; hint.anchor_right = 1.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58, 0.9))
	menu.add_child(hint)

	_menu_btns.clear()
	_menu_sel = 0
	# 单槽续玩存档(土豆兄弟式): 有档时「继续游戏」置顶,「开始游戏」改名「重新开始」并需确认
	var has_save := GameManager.has_suspend()
	var menu_defs := []
	if has_save:
		menu_defs.append(["继续游戏", _on_menu_resume, Color(0.45, 1.0, 0.55)])
		menu_defs.append(["重新开始", _on_menu_restart_ask, Color(0.60, 1.0, 0.65)])
	else:
		menu_defs.append(["开始游戏", _on_menu_start, Color(0.60, 1.0, 0.65)])
	menu_defs.append(["设 置", _on_menu_settings, Color(0.55, 0.78, 1.0)])
	menu_defs.append(["强化商店", _on_menu_shop, Color(1.0, 0.82, 0.45)])
	menu_defs.append(["游戏图鉴", _on_menu_codex, Color(0.72, 0.88, 0.70)])
	menu_defs.append(["退出游戏", _on_menu_quit, Color(1.0, 0.55, 0.55)])
	# 6 项时行距 32 且整体上移 10px, 末项落在 y=306(避开底部按键提示 y=344)
	var row_h := 32 if menu_defs.size() > 5 else 38
	var top_y := 146 if menu_defs.size() > 5 else 156
	for i in range(menu_defs.size()):
		var b := _make_rogue_btn(menu_defs[i][0], menu_defs[i][2])
		b.position = Vector2(W / 2 - 68, top_y + i * row_h)
		b.size = Vector2(136, 28)
		b.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
		b.pressed.connect(menu_defs[i][1])
		b.set_meta("base_accent", menu_defs[i][2])
		menu.add_child(b)
		_menu_btns.append(b)
	_refresh_menu_focus()

	# 余烬粒子: 从底部升起, 加色混合, 制造"底下有什么在烧"的焦躁感
	var embers := CPUParticles2D.new()
	embers.amount = 40
	embers.lifetime = 5.0
	embers.emitting = true
	embers.position = Vector2(W / 2, H + 4)
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(W / 2, 2)
	embers.direction = Vector2(0, -1)
	embers.spread = 9.0
	embers.gravity = Vector2(0, -5)          # 负重力 = 持续上浮
	embers.initial_velocity_min = 10.0
	embers.initial_velocity_max = 22.0
	embers.scale_amount_min = 2.0
	embers.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.75, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 0.62, 0.22, 0.0),
		Color(1.0, 0.55, 0.18, 0.85),
		Color(0.95, 0.28, 0.12, 0.45),
		Color(0.6, 0.1, 0.1, 0.0)])
	embers.color_ramp = ramp
	embers.material = _additive_mat()
	menu.add_child(embers)
	_menu_t = 0.0
	_menu_flicker = 1.0


# 加色混合材质: 让红光/余烬叠在背景上是"发光"而不是"蒙灰"
func _additive_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	# 不写 fragment: 默认行为是 texture * COLOR, 粒子的 color_ramp 才能生效
	m.shader.code = "shader_type canvas_item;\nrender_mode blend_add;\n"
	return m


var _flicker_target := 1.0

# 主菜单焦躁动效: 心跳脉动 + 天空闪烁 + 标题微抖/亮度闪跳
func _process_menu_fx(delta: float) -> void:
	_menu_t += delta
	var t := _menu_t

	# 双峰心跳: 一个周期内两次收缩, 比正弦更"不安"
	var beat := pow(maxf(0.0, sin(t * 2.4)), 6.0) + 0.55 * pow(maxf(0.0, sin(t * 2.4 - 0.9)), 10.0)
	if _menu_pulse != null and is_instance_valid(_menu_pulse):
		_menu_pulse.color.a = 0.02 + 0.05 * beat
	if _menu_glow != null and is_instance_valid(_menu_glow):
		# 高频低幅噪声闪: 随机换目标值后线性趋近 => 电流般微闪
		_menu_flicker = move_toward(_menu_flicker, _flicker_target, delta * 6.0)
		if randf() < delta * 11.0:
			_flicker_target = randf_range(0.55, 1.45)
		# 渐变本身带 alpha, modulate 只调整体强度
		_menu_glow.modulate.a = 0.45 * _menu_flicker + 0.30 * beat
	if _menu_title != null and is_instance_valid(_menu_title):
		# 1px 级抖动 + 偶发 2px 抽搐; 整体亮度随心跳闪跳(标题已是逐字彩字, 用 modulate 统一脉动)
		var jx := sin(t * 13.7) * 0.7 + sin(t * 31.3) * 0.4
		var jy := cos(t * 17.1) * 0.5
		if randf() < delta * 2.2:
			jx += randf_range(-2.0, 2.0)
			jy += randf_range(-1.0, 1.0)
		_menu_title.position = Vector2(jx, 52.0 + jy)
		var b := 0.85 + 0.15 * beat
		_menu_title.modulate = Color(b, b, b, 1.0)


# 主菜单焦点高亮 + 移动: 复用 _set_btn_highlight(金框提亮), 环绕切换
func _refresh_menu_focus() -> void:
	for i in range(_menu_btns.size()):
		var b: Button = _menu_btns[i]
		if b != null and is_instance_valid(b):
			_set_btn_highlight(b, i == _menu_sel)


func _menu_move(step: int, quiet: bool = false) -> void:
	var n := _menu_btns.size()
	if n == 0:
		return
	_menu_sel = posmod(_menu_sel + step, n)
	if not quiet:
		GameManager.play_sfx("pickup")
	_refresh_menu_focus()


func _menu_confirm() -> void:
	var n := _menu_btns.size()
	if _menu_sel < 0 or _menu_sel >= n:
		return
	var b: Button = _menu_btns[_menu_sel]
	if b != null and is_instance_valid(b):
		b.pressed.emit()


func _on_menu_start() -> void:
	GameManager.play_sfx("select")
	if GameManager.main.has_method("_enter_character_select"):
		GameManager.main._enter_character_select()


# 继续游戏: 恢复单槽续玩存档(main.resume_run 读档即删档)
func _on_menu_resume() -> void:
	GameManager.play_sfx("select")
	GameManager.main.resume_run()


# 重新开始(有存档时): 弹确认层, 明确「覆盖将删除存档」
func _on_menu_restart_ask() -> void:
	GameManager.play_sfx("select")
	if _menu_confirm_screen != null and is_instance_valid(_menu_confirm_screen):
		return
	_menu_confirm_screen = _full_screen()
	_menu_confirm_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_confirm_screen.add_child(dim)

	# 用 Panel 而非 PanelContainer: 容器会把子节点强制铺满内容区, 绝对坐标布局会被覆盖
	var panel := Panel.new()
	panel.position = Vector2(W / 2 - 130, H / 2 - 52)
	panel.size = Vector2(260, 104)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.10, 0.96)
	sb.border_color = Color(0.85, 0.62, 0.30, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	_menu_confirm_screen.add_child(panel)

	var txt := _label("存在上次的游戏存档\n重新开始将删除存档, 继续?", 10)
	txt.position = Vector2(0, 14)
	txt.size = Vector2(260, 34)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80))
	panel.add_child(txt)

	_menu_confirm_btns.clear()
	_menu_confirm_sel = 0
	var defs := [
		["确认重开", _on_menu_restart_confirm, Color(0.95, 0.55, 0.45)],
		["取 消", _on_menu_restart_cancel, Color(0.55, 0.68, 0.90)],
	]
	for i in range(defs.size()):
		var b := _make_btn(defs[i][0], defs[i][2])
		b.position = Vector2(28 + i * 106, 62)
		b.size = Vector2(96, 26)
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("base_accent", defs[i][2])
		b.pressed.connect(defs[i][1])
		panel.add_child(b)
		_menu_confirm_btns.append(b)
	_refresh_menu_confirm_focus()


func _refresh_menu_confirm_focus() -> void:
	for i in range(_menu_confirm_btns.size()):
		var b: Button = _menu_confirm_btns[i]
		if b != null and is_instance_valid(b):
			_set_btn_highlight(b, i == _menu_confirm_sel)


func _menu_confirm_move(step: int) -> void:
	var n := _menu_confirm_btns.size()
	if n == 0:
		return
	_menu_confirm_sel = posmod(_menu_confirm_sel + step, n)
	GameManager.play_sfx("pickup")
	_refresh_menu_confirm_focus()


func _menu_confirm_accept() -> void:
	if _menu_confirm_sel >= 0 and _menu_confirm_sel < _menu_confirm_btns.size():
		var b: Button = _menu_confirm_btns[_menu_confirm_sel]
		if b != null and is_instance_valid(b):
			b.pressed.emit()


func _close_menu_confirm() -> void:
	if _menu_confirm_screen != null and is_instance_valid(_menu_confirm_screen):
		_menu_confirm_screen.queue_free()
	_menu_confirm_screen = null
	_menu_confirm_btns.clear()
	_menu_confirm_sel = 0


func _on_menu_restart_confirm() -> void:
	GameManager.play_sfx("select")
	GameManager.clear_suspend()   # 单槽存档即刻删除
	_close_menu_confirm()
	if GameManager.main.has_method("_enter_character_select"):
		GameManager.main._enter_character_select()


func _on_menu_restart_cancel() -> void:
	GameManager.play_sfx("select")
	_close_menu_confirm()


func _on_menu_settings() -> void:
	GameManager.play_sfx("select")
	show_settings()


func _on_menu_shop() -> void:
	GameManager.play_sfx("select")
	show_shop()


func _on_menu_codex() -> void:
	_on_codex_open()


# 图鉴统一入口(主菜单按钮 / 游戏内设置面板按钮共用)
func _on_codex_open() -> void:
	GameManager.play_sfx("select")
	show_codex()


func _on_menu_quit() -> void:
	GameManager.play_sfx("select")
	get_tree().quit()


# ================= 角色选择 =================

func show_character_select() -> void:
	_clear_all()
	char_screen = _full_screen()
	char_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.36, 0.38)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	char_screen.add_child(bg)

	# id 列表从 CHARACTERS 派生(唯一真相源): 新增角色只改 game_manager.gd, 界面自动跟上
	char_ids.clear()
	_card_weapon_slots.clear()
	for k in GameManager.CHARACTERS.keys():
		char_ids.append(str(k))
	if _selected_char == "" or not char_ids.has(_selected_char):
		_selected_char = char_ids[0]
	# 武器列表 + 起始选择: 每角色独立装备; 当前选中武器镜像该角色的 _char_weapons(无条目=无)
	weapon_ids.clear()
	for k in GameManager.WEAPONS.keys():
		weapon_ids.append(str(k))
	# 默认装备 = 各角色表定起始武器: 不播种则每行显「无」, 与详情面板/实际开局(start_game 回退表默认)不符,
	# 且武器栏高亮会错落在第一格
	for cid in char_ids:
		if not _char_weapons.has(cid):
			_char_weapons[cid] = str(GameManager.CHARACTERS[cid]["weapon"])
	_selected_weapon = str(_char_weapons.get(_selected_char, ""))
	if not weapon_ids.has(_selected_weapon):
		_selected_weapon = ""
	_weapon_sel = weapon_ids.find(_selected_weapon)
	if _weapon_sel < 0:
		_weapon_sel = 0

	var title := _label("选择你的角色", 21)
	title.position = Vector2(0, 30)
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_screen.add_child(title)

	# —— 左侧: 纵向角色名列表(ScrollContainer, 超出可视区可滚动) ——
	char_buttons.clear()
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(CHAR_LIST_X, CHAR_DETAIL_Y)
	scroll.size = Vector2(CHAR_LIST_W, 216.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	char_screen.add_child(scroll)
	_char_scroll = scroll

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for i in range(char_ids.size()):
		var id: String = char_ids[i]
		var btn: PanelContainer = _char_list_item(id)
		list.add_child(btn)
		char_buttons.append(btn)

	# —— 右侧: 详情面板(左侧角色属性 + 右侧当前武器属性) ——
	char_screen.add_child(_detail_panel())
	char_screen.add_child(_weapon_detail_panel())

	# —— 底部武器选择栏: 全部武器横向排布, 选中金框, 图标 16×16 1:1 ——
	_weapon_buttons.clear()
	var wpn_bar := HBoxContainer.new()
	wpn_bar.add_theme_constant_override("separation", WPN_TILE_GAP)
	wpn_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	wpn_bar.position = Vector2(0, 282.0)
	wpn_bar.size = Vector2(W, WPN_TILE_H)
	char_screen.add_child(wpn_bar)

	for i in range(weapon_ids.size()):
		var wid: String = weapon_ids[i]
		var tile: PanelContainer = _weapon_tile(wid)
		wpn_bar.add_child(tile)
		_weapon_buttons.append(tile)

	# 返回菜单: 左上角独立摆放(底部已被武器栏占满, 放左下会与最左武器 tile 重叠)
	var back := _make_btn("返回菜单", Color(0.45, 0.60, 0.85))
	back.position = Vector2(16.0, 16.0)
	back.size = Vector2(90, 28)
	back.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防鼠标点过后焦点驻留导致空格双触发
	back.pressed.connect(_on_char_back)
	char_screen.add_child(back)

	# 操作提示
	var hint := _label("W/S 选角色 · A/D 配武器 · 空格/回车 开始 · ESC 返回菜单 · 鼠标点击亦可", 8)
	hint.position = Vector2(0, 334)
	hint.anchor_left = 0.0; hint.anchor_right = 1.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.85))
	char_screen.add_child(hint)

	_refresh_char_selection()
	_refresh_weapon_selection()


# 详情面板通用样式: 暗底 + 白描边 + 统一内边距(内容贴边框有确定间距, 不吃主题默认)
func _detail_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.12, 0.12, 0.16, 0.92)
	s.border_color = Color(1, 1, 1, 1)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 12.0
	s.content_margin_right = 12.0
	s.content_margin_top = 8.0
	s.content_margin_bottom = 8.0
	return s


# 左侧详情面板: 放大头像 + 名字 + 完整属性(VBox 纵向)
func _detail_panel() -> PanelContainer:
	var detail := PanelContainer.new()
	detail.position = Vector2(CHAR_DETAIL_X, CHAR_DETAIL_Y)
	detail.size = Vector2(CHAR_DETAIL_W / 2.0 - 4.0, CHAR_DETAIL_H)
	detail.add_theme_stylebox_override("panel", _detail_style())
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 3)
	detail.add_child(dbox)
	_char_detail_inner = dbox

	_detail_portrait = TextureRect.new()
	_detail_portrait.custom_minimum_size = Vector2(CHAR_PORTRAIT, CHAR_PORTRAIT)
	_detail_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dbox.add_child(_detail_portrait)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 15)
	_detail_name.add_theme_color_override("font_color", Color(1.0, 0.88, 0.40))
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dbox.add_child(_detail_name)

	_detail_info = RichTextLabel.new()
	_detail_info.bbcode_enabled = true
	_detail_info.fit_content = true
	_detail_info.scroll_active = false
	_detail_info.add_theme_font_size_override("normal_font_size", 8)
	_detail_info.add_theme_constant_override("line_separation", 2)
	_detail_info.custom_minimum_size = Vector2(CHAR_DETAIL_W / 2.0 - 24.0, 0)
	dbox.add_child(_detail_info)
	return detail


# 右侧详情面板: 当前选中角色武器的定位与属性(独立面板, 内容随武器切换刷新)
func _weapon_detail_panel() -> PanelContainer:
	var detail := PanelContainer.new()
	detail.position = Vector2(CHAR_DETAIL_X + CHAR_DETAIL_W / 2.0 + 4.0, CHAR_DETAIL_Y)
	detail.size = Vector2(CHAR_DETAIL_W / 2.0 - 4.0, CHAR_DETAIL_H)
	detail.add_theme_stylebox_override("panel", _detail_style())
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 4)
	detail.add_child(dbox)
	_weapon_detail_inner = dbox

	_detail_weapon_icon = TextureRect.new()
	_detail_weapon_icon.texture = GameManager.weapon_icon_texture("wand")
	_detail_weapon_icon.custom_minimum_size = Vector2(32, 32)
	_detail_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_weapon_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_weapon_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dbox.add_child(_detail_weapon_icon)

	var header := Label.new()
	header.text = "武器"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.57, 0.78, 0.86))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dbox.add_child(header)

	_detail_weapon_name = Label.new()
	_detail_weapon_name.add_theme_font_size_override("font_size", 13)
	_detail_weapon_name.add_theme_color_override("font_color", Color(1.0, 0.88, 0.40))
	_detail_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dbox.add_child(_detail_weapon_name)

	_detail_weapon_summary = Label.new()
	_detail_weapon_summary.add_theme_font_size_override("font_size", 8)
	_detail_weapon_summary.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	_detail_weapon_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_weapon_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dbox.add_child(_detail_weapon_summary)

	_detail_weapon_info = RichTextLabel.new()
	_detail_weapon_info.bbcode_enabled = true
	_detail_weapon_info.fit_content = true
	_detail_weapon_info.scroll_active = false
	_detail_weapon_info.add_theme_font_size_override("normal_font_size", 8)
	_detail_weapon_info.add_theme_constant_override("line_separation", 2)
	_detail_weapon_info.custom_minimum_size = Vector2(CHAR_DETAIL_W / 2.0 - 24.0, 0)
	dbox.add_child(_detail_weapon_info)
	return detail


# 左侧列表单项: 角色名 + 小号武器名, 选中态走 _refresh_char_selection 统一高亮
func _char_list_item(id: String) -> PanelContainer:
	var c: Dictionary = GameManager.CHARACTERS[id]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CHAR_LIST_W, CHAR_ITEM_H)

	# 显式内边距: 内容左右各 CHAR_ITEM_PAD, 垂直居中撑满卡片(不让文字与边框隔空)
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	base.border_color = Color(1, 1, 1, 1)
	base.set_border_width_all(1)
	base.content_margin_left = CHAR_ITEM_PAD
	base.content_margin_right = CHAR_ITEM_PAD
	base.content_margin_top = 4.0
	base.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", base)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)

	var icon := TextureRect.new()
	icon.texture = GameManager.char_preview_texture(id)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = c["name"]
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(name_lbl)

	# 武器图标槽(卡片右侧): 初始显示「无」; 该角色选武器后换成 16×16 图标
	var icon_slot := TextureRect.new()
	icon_slot.custom_minimum_size = Vector2(16, 16)
	icon_slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hbox.add_child(icon_slot)
	var none_lbl := Label.new()
	none_lbl.text = "无"
	none_lbl.add_theme_font_size_override("font_size", 7)
	none_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	none_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(none_lbl)
	_card_weapon_slots[id] = {"icon": icon_slot, "none": none_lbl}

	panel.gui_input.connect(_on_char_pressed.bind(id))
	return panel


# 底部武器 tile: 图标 + 名字, 选中金框
func _weapon_tile(id: String) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(WPN_TILE_W, WPN_TILE_H)

	var wbase := StyleBoxFlat.new()
	wbase.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	wbase.border_color = Color(1, 1, 1, 1)
	wbase.set_border_width_all(1)
	wbase.content_margin_top = 3.0
	wbase.content_margin_bottom = 3.0
	tile.add_theme_stylebox_override("panel", wbase)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tile.add_child(vbox)

	var icon := TextureRect.new()
	icon.texture = GameManager.weapon_icon_texture(id)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = GameManager.WEAPONS[id]["name"]
	name_lbl.add_theme_font_size_override("font_size", 7)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)

	tile.gui_input.connect(_on_weapon_pressed.bind(id))
	return tile


func _on_weapon_pressed(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# 只装备给当前选中角色(每角色独立); 更新该角色条目 + 镜像选中态
		_char_weapons[_selected_char] = id
		_selected_weapon = id
		_weapon_sel = weapon_ids.find(id)
		_refresh_weapon_selection()
		_refresh_char_selection()
		_animate_weapon_selection()
		GameManager.play_sfx("select")


# 武器栏选中态: 金框高亮(无选中时全部普通); 卡片右侧图标槽由 _refresh_card_weapon_slots 同步
func _refresh_weapon_selection() -> void:
	for i in range(_weapon_buttons.size()):
		var tile: PanelContainer = _weapon_buttons[i]
		var id: String = weapon_ids[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.9, 0.75, 0.2, 0.9) if id == _selected_weapon else Color(0.15, 0.15, 0.15, 0.9)
		sb.border_color = Color(1, 1, 1, 1)
		sb.set_border_width_all(2 if id == _selected_weapon else 1)
		# 与初始 stylebox 相同的垂直边距, 选中切换不跳动
		sb.content_margin_top = 3.0
		sb.content_margin_bottom = 3.0
		tile.add_theme_stylebox_override("panel", sb)
	_refresh_card_weapon_slots()


# 卡片右侧武器图标槽(每角色独立): 该角色有装备则显图标, 否则显「无」
func _refresh_card_weapon_slots() -> void:
	for id in _card_weapon_slots.keys():
		var slot: Dictionary = _card_weapon_slots[id]
		var icon: TextureRect = slot["icon"]
		var none_lbl: Label = slot["none"]
		var w: String = str(_char_weapons.get(id, ""))
		var tex := GameManager.weapon_icon_texture(w) if w != "" else null
		icon.texture = tex
		icon.visible = tex != null
		none_lbl.visible = tex == null


# 武器栏左右移动(dx ±1), 到边缘循环(首尾相接, 多把武器来回切换更顺手)
func _weapon_move(dx: int, quiet: bool = false) -> void:
	_weapon_sel = wrapi(_weapon_sel + dx, 0, weapon_ids.size())
	var id: String = weapon_ids[_weapon_sel]
	# 只装备给当前选中角色(每角色独立)
	_char_weapons[_selected_char] = id
	_selected_weapon = id
	_refresh_weapon_selection()
	_refresh_char_selection()
	_animate_weapon_selection()
	if not quiet:
		GameManager.play_sfx("pickup")


func _on_char_pressed(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _selected_char != id:
			_selected_char = id
			_sync_weapon_sel_from_char()
			_refresh_char_selection()
			_refresh_weapon_selection()
			_animate_char_selection()
			GameManager.play_sfx("select")


# 切换角色后, 把「当前选中武器/高亮」镜像到该角色已装武器(无装备 => 全不高亮)
func _sync_weapon_sel_from_char() -> void:
	_selected_weapon = str(_char_weapons.get(_selected_char, ""))
	if not weapon_ids.has(_selected_weapon):
		_selected_weapon = ""
	_weapon_sel = weapon_ids.find(_selected_weapon)
	if _weapon_sel < 0:
		_weapon_sel = 0


# 选中态统一刷新: 列表高亮 + 详情面板内容
func _refresh_char_selection() -> void:
	for i in range(char_buttons.size()):
		var panel: PanelContainer = char_buttons[i]
		var id: String = char_ids[i]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.9, 0.75, 0.2, 0.9) if id == _selected_char else Color(0.15, 0.15, 0.15, 0.9)
		sb.border_color = Color(1, 1, 1, 1)
		sb.set_border_width_all(2 if id == _selected_char else 1)
		# 与初始 stylebox 相同的边距, 保证选中/未选中切换时内容不跳动
		sb.content_margin_left = CHAR_ITEM_PAD
		sb.content_margin_right = CHAR_ITEM_PAD
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		panel.add_theme_stylebox_override("panel", sb)

	var c: Dictionary = GameManager.CHARACTERS[_selected_char]
	if _detail_portrait != null:
		_detail_portrait.texture = GameManager.char_preview_texture(_selected_char)
	if _detail_name != null:
		_detail_name.text = c["name"]
	if _detail_info != null:
		# 垂直列表: 每属性单独一行, 标签(药水红) + 数值(白); 被动/规则(青标签); 当前武器名移到右侧面板
		var lines := PackedStringArray()
		lines.append("[color=#FF6A5A]生命[/color]  [color=#E6F2F5]%d[/color]" % int(c["max_hp"]))
		lines.append("[color=#FF6A5A]移速[/color]  [color=#E6F2F5]%d[/color]" % int(c["move_speed"]))
		lines.append("[color=#FF6A5A]伤害[/color]  [color=#E6F2F5]×%.2f[/color]" % float(c["damage_mult"]))
		lines.append("")
		lines.append("[color=#57C7D6]被动[/color]  %s" % c["passive"])
		lines.append("[color=#57C7D6]规则[/color]  %s" % c["rule"])
		_detail_info.text = "\n".join(lines)

	_refresh_weapon_detail()

	# 选中项滚动到可视区
	if _char_scroll != null:
		var sel_idx := char_ids.find(_selected_char)
		if sel_idx >= 0 and sel_idx < char_buttons.size():
			_char_scroll.ensure_control_visible(char_buttons[sel_idx])


# 选中角色切换的回弹演出: 头像脉冲 + 面板内缩 + 名字上冲 + 文字淡入 + 选中卡片外弹。
# 一次平行 tween 统一驱动; 头像/卡片两段式(前半程冲过头, 后半程回正)用两条同目标 tween 衔接。
func _animate_char_selection() -> void:
	if _char_sel_tw != null and _char_sel_tw.is_valid():
		_char_sel_tw.kill()   # 快速连切时先杀掉旧的, 防多条 tween 抢属性叠加

	# 把上一次动画可能留下的非 1 缩放按各轴回正(避免累计变形), 之后再从 1 开始脉冲
	if _detail_portrait != null and is_instance_valid(_detail_portrait):
		_detail_portrait.scale = Vector2.ONE
	if _detail_name != null and is_instance_valid(_detail_name):
		_detail_name.scale = Vector2.ONE
	if _char_detail_inner != null and is_instance_valid(_char_detail_inner):
		_char_detail_inner.scale = Vector2.ONE
	for panel in char_buttons:
		if panel != null and is_instance_valid(panel):
			panel.scale = Vector2.ONE

	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	var t: float = CHAR_PUNCH_SEC

	# 头像脉冲: 1 → 峰值(前半程)→ 回正(后半程), 带 BACK 回弹
	if _detail_portrait != null and is_instance_valid(_detail_portrait):
		tw.tween_property(_detail_portrait, "scale", Vector2.ONE * CHAR_PUNCH, t * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_detail_portrait, "scale", Vector2.ONE, t * 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(t * 0.5)

	# 面板内盒轻微内缩回正
	if _char_detail_inner != null and is_instance_valid(_char_detail_inner):
		tw.tween_property(_char_detail_inner, "scale", Vector2.ONE * CHAR_PANEL_DIP, t) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 名字上冲回弹
	if _detail_name != null and is_instance_valid(_detail_name):
		tw.tween_property(_detail_name, "scale", Vector2.ONE * CHAR_NAME_PUNCH, t) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 属性文字淡入(半透明 → 不透明)
	if _detail_info != null and is_instance_valid(_detail_info):
		tw.tween_property(_detail_info, "self_modulate:a", CHAR_FADE_FROM, 0.0)
		tw.tween_property(_detail_info, "self_modulate:a", 1.0, t * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 左侧选中卡片外弹回正
	var sel_idx: int = char_ids.find(_selected_char)
	if sel_idx >= 0 and sel_idx < char_buttons.size():
		var card: PanelContainer = char_buttons[sel_idx]
		if card != null and is_instance_valid(card):
			tw.tween_property(card, "scale", Vector2.ONE * CHAR_CARD_PUNCH, t * 0.5) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(card, "scale", Vector2.ONE, t * 0.5) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(t * 0.5)

	_char_sel_tw = tw


# 选中武器切换的回弹演出: 武器图标脉冲 + 面板内缩 + 名字上冲 + 文字淡入(与角色同一套参数)。
func _animate_weapon_selection() -> void:
	if _char_sel_tw != null and _char_sel_tw.is_valid():
		_char_sel_tw.kill()

	if _detail_weapon_icon != null and is_instance_valid(_detail_weapon_icon):
		_detail_weapon_icon.scale = Vector2.ONE
	if _detail_weapon_name != null and is_instance_valid(_detail_weapon_name):
		_detail_weapon_name.scale = Vector2.ONE
	if _weapon_detail_inner != null and is_instance_valid(_weapon_detail_inner):
		_weapon_detail_inner.scale = Vector2.ONE

	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	var t: float = CHAR_PUNCH_SEC

	if _detail_weapon_icon != null and is_instance_valid(_detail_weapon_icon):
		tw.tween_property(_detail_weapon_icon, "scale", Vector2.ONE * CHAR_PUNCH, t * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_detail_weapon_icon, "scale", Vector2.ONE, t * 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(t * 0.5)

	if _weapon_detail_inner != null and is_instance_valid(_weapon_detail_inner):
		tw.tween_property(_weapon_detail_inner, "scale", Vector2.ONE * CHAR_PANEL_DIP, t) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if _detail_weapon_name != null and is_instance_valid(_detail_weapon_name):
		tw.tween_property(_detail_weapon_name, "scale", Vector2.ONE * CHAR_NAME_PUNCH, t) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if _detail_weapon_info != null and is_instance_valid(_detail_weapon_info):
		tw.tween_property(_detail_weapon_info, "self_modulate:a", CHAR_FADE_FROM, 0.0)
		tw.tween_property(_detail_weapon_info, "self_modulate:a", 1.0, t * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_char_sel_tw = tw


# 右侧武器详情: 当前选中武器(无则回退角色推荐武器)的定位与属性; 仅读 UI 表, 不碰武器节点
func _refresh_weapon_detail() -> void:
	var wid := _selected_weapon
	if wid == "":
		wid = GameManager.CHARACTERS[_selected_char]["weapon"]
	var has: bool = GameManager.WEAPON_DETAILS.has(wid)
	var def: Dictionary = GameManager.WEAPON_DETAILS.get(wid, {})
	if _detail_weapon_icon != null:
		_detail_weapon_icon.texture = GameManager.weapon_icon_texture(wid) if has else null
	if _detail_weapon_name != null:
		_detail_weapon_name.text = GameManager.WEAPONS[wid]["name"] if has else "无武器"
	if _detail_weapon_summary != null:
		_detail_weapon_summary.text = str(def.get("summary", "")) if has else ""
	if _detail_weapon_info != null:
		if not has:
			_detail_weapon_info.text = "[color=#8F7BFF]战前未选择武器[/color]"
		else:
			var lines := PackedStringArray()
			# 特性行放在成长节点**之前**: 战前选择时玩家要知道的是"这把能挂什么状态",
			# 等级细节是抽到之后才关心的。配色与图鉴武器页同一套(StatusFx tint), 两处不打架。
			var t_kind := GameManager.trait_of(wid)
			if t_kind != "":
				lines.append("[color=#%s]特性 · %s[/color]  [color=#E6F2F5]%s[/color]" % [
					GameManager.trait_color(wid).to_html(),
					GameManager.trait_name(wid),
					GameManager.trait_desc(wid)])
			for ln in GameManager.weapon_level_lines(wid):
				lines.append("· %s" % str(ln))   # lines 内自带 [color=…] 高亮, 外层只加项目符号
			_detail_weapon_info.text = "\n".join(lines)


# W/S 在纵向列表移动选中角色(dy ±1), 到边缘即停不绕回
func _char_move(dx: int, dy: int, quiet: bool = false) -> void:
	var cur := char_ids.find(_selected_char)
	if cur < 0:
		cur = 0
	var idx: int = wrapi(cur + dy, 0, char_ids.size())   # 环绕: 边缘循环到另一头
	if idx == cur:
		return
	_selected_char = char_ids[idx]
	_sync_weapon_sel_from_char()
	_refresh_char_selection()
	_refresh_weapon_selection()
	_animate_char_selection()
	if not quiet:
		GameManager.play_sfx("pickup")


# 键盘确认开始(与「开始」按钮同一路径)
func _char_confirm() -> void:
	_on_start()


func _on_start() -> void:
	GameManager.play_sfx("select")
	if GameManager.main.has_method("start_game"):
		# 未选武器(「无」)时回退该角色推荐武器, 避免空手入局
		var wid := _selected_weapon
		if wid == "":
			wid = GameManager.CHARACTERS[_selected_char]["weapon"]
		GameManager.main.start_game(_selected_char, wid)


func _on_char_back() -> void:
	GameManager.play_sfx("select")
	if GameManager.main.has_method("exit_to_menu"):
		GameManager.main.exit_to_menu()


# ================= 战斗 HUD =================

func show_hud() -> void:
	_clear_all()
	game_hud = _full_screen()
	game_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	game_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 左上状态条组: 血条在上、经验条在下, 同宽(BAR_W)贴左对齐 => 左缘对齐;
	# 经验条更矮(BAR_XP_H) 突出血条主体且上下不重叠; 血量数值内嵌血条, 等级数字放血条右侧
	_hp_bar = _make_bar(Vector2(BAR_X, BAR_HP_Y), Vector2(BAR_W, BAR_HP_H), 100.0)
	_hp_fill = _hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	game_hud.add_child(_hp_bar)

	_xp_bar = _make_bar(Vector2(BAR_X, BAR_XP_Y), Vector2(BAR_W, BAR_XP_H), 100.0)
	_xp_fill = _xp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	game_hud.add_child(_xp_bar)

	# 本局加成面板: 血条/经验条正下方, 固定窄面板, 无加成时收起不占位
	_build_buffs_panel()

	# 血量数值: 内嵌血条居中(白字 + 深描边, 叠加在任意填充色上都可读)
	_hp_label = Label.new()
	_hp_label.position = Vector2(BAR_X, BAR_HP_Y)
	_hp_label.size = Vector2(BAR_W, BAR_HP_H)
	# Label 树外 theme 退化为默认字号16(min高≈23), size 赋值必被钳高; 树外
	# update_minimum_size() 也救不回(override 字号入树后才解析)。deferred 重设
	# 在入树后、当帧渲染前冲刷, 第一帧即正确尺寸, 无闪烁。根因见 _make_bar 注释。
	_hp_label.set_deferred("size", Vector2(BAR_W, BAR_HP_H))
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 8)
	_hp_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_hp_label.add_theme_color_override("font_outline_color", Color(0.10, 0.10, 0.12))
	_hp_label.add_theme_constant_override("outline_size", 2)
	game_hud.add_child(_hp_label)

	# 等级数字: 血条右侧(与内嵌血量数值同层级), 垂直居中于血条
	_level_label = Label.new()
	_level_label.position = Vector2(BAR_X + BAR_W + 6.0, BAR_HP_Y)
	_level_label.size = Vector2(40.0, BAR_HP_H)
	_level_label.set_deferred("size", Vector2(40.0, BAR_HP_H))
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 9)
	_level_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_level_label.add_theme_color_override("font_outline_color", Color(0.10, 0.10, 0.12))
	_level_label.add_theme_constant_override("outline_size", 2)
	game_hud.add_child(_level_label)

	# 波次信息: 屏幕中上部位水平居中(标题感, 字号稍大)
	# 带倒计时「波次 4/12 · 18s」(2026-09-10): 波末清场会把残敌全部静默回收, 而 HUD 原先
	# 只显示波次序号 => 玩家无从预知, 看着满屏的怪突然消失会当成 bug(用户实测反馈)。
	# 倒计时读 GameManager.wave_time_left()(与 spawner 的波末判定共读 WAVES duration 列)。
	# 宽 70 → 110: 中上区域 x285..355 原先只占 70px, 左上血条到 x=158、右上击杀数从 x=552 起,
	# 加宽后 x265..375 仍然两侧空余充足, 不挤任何既有元素。
	_time_label = Label.new()
	# 高 16 = 字号 11 的真实行高: Label 的 size.y 会被 min(行高) 钳住, 设计值必须 ≥ 行高
	_time_label.position = Vector2(W / 2.0 - 55.0, 10)
	_time_label.size = Vector2(110, 16)
	_time_label.set_deferred("size", Vector2(110, 16))
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 11)
	_time_label.add_theme_color_override("font_outline_color", Color(0.10, 0.10, 0.12))
	_time_label.add_theme_constant_override("outline_size", 2)
	game_hud.add_child(_time_label)

	# 击杀数: 像素骷髅图标 + 数字, 右对齐; 图标与文字垂直居中对齐
	_kills_label = Label.new()
	_kills_label.text = "0"
	_kills_label.add_theme_font_size_override("font_size", 11)
	_kills_label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
	_kills_label.add_theme_color_override("font_outline_color", Color(0.10, 0.10, 0.12))
	_kills_label.add_theme_constant_override("outline_size", 2)

	_kills_icon = TextureRect.new()
	_kills_icon.texture = GameManager.skull_icon_texture()
	_kills_icon.custom_minimum_size = Vector2(16, 16)
	_kills_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_kills_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_kills_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_kills_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var kills_hbox := HBoxContainer.new()
	kills_hbox.add_theme_constant_override("separation", 4)
	kills_hbox.alignment = BoxContainer.ALIGNMENT_END
	kills_hbox.add_child(_kills_icon)
	kills_hbox.add_child(_kills_label)
	kills_hbox.position = Vector2(W - 88, 25)
	kills_hbox.size = Vector2(80, 18)
	game_hud.add_child(kills_hbox)

	# 金币计数: 击杀数下方, 金色圆点 + 数字(右对齐)
	_coin_label = _label("0", 10)
	_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_coin_label.add_theme_color_override("font_outline_color", Color(0.10, 0.10, 0.12))
	_coin_label.add_theme_constant_override("outline_size", 2)
	_coin_label.position = Vector2(W - 96, 44)
	_coin_label.size = Vector2(88, 14)
	_coin_label.set_deferred("size", Vector2(88, 14))
	game_hud.add_child(_coin_label)

	# 诅咒值: 金币下方第三行, 深渊紫(与左上「本局加成」面板对称, 右上是本局风险读数)。
	# 刻意不与加成面板合并 —— 诅咒是 run 级标量不是 item_mods 键, 混进去会占掉 BUFFS_SHOW_MAX 名额
	_curse_label = _label("", 10)
	_curse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_curse_label.add_theme_color_override("font_color", Color(0.72, 0.52, 1.0))
	_curse_label.add_theme_color_override("font_outline_color", Color(0.10, 0.10, 0.12))
	_curse_label.add_theme_constant_override("outline_size", 2)
	_curse_label.position = Vector2(W - 96, 60)
	_curse_label.size = Vector2(88, 14)
	_curse_label.set_deferred("size", Vector2(88, 14))
	_curse_label.visible = false
	game_hud.add_child(_curse_label)

	# 底部武器栏
	_build_weapon_bar()

	# Boss 血条层(平时隐藏)
	_build_boss_bar()

	_reset_bar_smoothing()
	update_curse_label()   # 恢复局/重开时诅咒值可能非 0, 建好就刷(不靠 on_curse_changed)
	set_process(true)


# 刷新中上波次标签: 「波次 4/12 · 18s」。带缓存(文本每秒才变一次)避免每帧改 text。
# 为什么必须有倒计时: 波末清场会把场上残敌全部静默回收(die_without_reward), 而 HUD 原先
# 只显示波次序号 => 玩家看着满屏的怪突然消失, 会当成 bug(用户实测反馈)。有了剩余秒数,
# "再过 3 秒这波就结束、没打完的怪会消失" 是**事前可预知**的, 清场就从 bug 变成规则。
# 波时长已走完但 Boss 未死时(spawner._boss_pending), wave_time_left() 返回 0,
# 照显示会卡在「· 0s」看着像冻住 => 换成明确的收尾语义。
func _update_wave_label() -> void:
	if _time_label == null or not is_instance_valid(_time_label):
		return
	var txt: String = "波次 %d/%d" % [GameManager.wave, GameManager.WAVE_COUNT]
	if GameManager.wave >= 1:
		var left: float = GameManager.wave_time_left()
		if left > 0.0:
			txt += " · %ds" % int(ceilf(left))
		elif GameManager.boss_alive():
			txt += " · 击败首领"
	var is_last: bool = GameManager.wave >= GameManager.WAVE_COUNT
	if is_last:
		txt += " · 终"
	if txt == _wave_label_last:
		return
	_wave_label_last = txt
	_time_label.text = txt
	# 最后 5 秒转橙: 清场临近的阅读信号(不改字号不动布局, 避免标签宽度跳变)
	if not is_last and GameManager.wave >= 1 and GameManager.wave_time_left() <= 5.0 \
		and GameManager.wave_time_left() > 0.0:
		_time_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.28))
	else:
		_time_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))


# 刷新右上诅咒标签: 0 隐藏, >0 显示「☠ 诅咒 N/M」。带 _curse_last 缓存避免每帧改 text。
# 商店暂停期间 game_hud 已被 _clear_all 清空 → 标签为 null 时静默返回(close_wave_shop
# 重建 HUD 时 show_hud 会再刷一次, 值不会丢)。
func update_curse_label() -> void:
	if _curse_label == null or not is_instance_valid(_curse_label):
		return
	var lv: int = GameManager.curse_level
	if lv == _curse_last:
		return
	_curse_last = lv
	if lv <= 0:
		_curse_label.visible = false
		_curse_label.text = ""
		return
	_curse_label.text = "☠ 诅咒 %d/%d" % [lv, GameManager.CURSE_MAX]
	_curse_label.visible = true


# 构建带自定义样式的进度条: 深色底槽 + 填充色(填充样式返回后可每帧改色)
func _make_bar(pos: Vector2, size: Vector2, max_value: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.max_value = max_value
	bar.value = 0.0
	bar.show_percentage = false

	# 圆角随条高缩放: 矮条(经验条)圆角过大会挤成胶囊状, 与上方血条视觉粘连
	var radius := int(minf(size.y * 0.5, 4.0))

	var bg := StyleBoxFlat.new()
	bg.bg_color = BAR_BG
	bg.set_corner_radius_all(radius)
	bg.set_border_width_all(1)
	bg.border_color = Color(0, 0, 0, 0.6)
	bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.WHITE
	fill.set_corner_radius_all(radius)
	bar.add_theme_stylebox_override("fill", fill)

	# size 不能直接赋: 树外新控件的 min-size 缓存是引擎默认字号16 的陈旧值
	# (ProgressBar 带百分比文字 min 高≈27), 赋值即被钳高且不自愈 —— 血条/经验条/
	# Boss条叠在一起的真因。树外 update_minimum_size() 也不可靠(theme 未初始化)。
	# set_deferred 在入树后、当帧渲染前冲刷, 此时 theme 已结算(show_percentage=false
	# 生效, min≈2), size 原样保留; 第一帧即正确, 无闪烁。
	bar.set_deferred("size", size)
	return bar


# 平滑过渡状态复位: 显示值对齐真实值(开局/重进 HUD 时不播放补间动画)
func _reset_bar_smoothing() -> void:
	var p = GameManager.player
	if p != null:
		_hp_shown = p.hp
		_hp_prev = p.hp
	else:
		_hp_shown = 100.0
		_hp_prev = 100.0
	_xp_shown = GameManager.xp
	_hp_flash = 0.0
	_level_prev = GameManager.level


# 本局加成面板: 固定在血条/经验条正下方(BAR_XP_Y + BAR_XP_H 之下), 暗底描边窄面板
# 只显示 player.item_mods 的非零项(商店一次性 buff), 正绿负红; 无加成隐藏
# 结构: VBox = 标题行(标题 + Tab 提示, 仅展开态) + 正文; 宽与项数上限由 _update_buffs_panel 控制
func _build_buffs_panel() -> void:
	_buffs_panel = PanelContainer.new()
	_buffs_panel.position = Vector2(BAR_X, BAR_XP_Y + BAR_XP_H + 6.0)
	_buffs_panel.custom_minimum_size = Vector2(BAR_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.10, 0.72)
	sb.border_color = Color(0.35, 0.40, 0.50, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	_buffs_panel.add_theme_stylebox_override("panel", sb)

	# VBox: 标题行(展开态) + 正文; 折叠态隐藏标题行, 面板只剩一行高
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_buffs_panel.add_child(vbox)

	_buffs_header = HBoxContainer.new()
	var title := _label("本局加成", 8)
	title.add_theme_color_override("font_color", Color(0.60, 0.63, 0.68))
	_buffs_header.add_child(title)
	var hint := _label("Tab 收起", 7)
	hint.add_theme_color_override("font_color", Color(0.45, 0.48, 0.53))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buffs_header.add_child(hint)
	_buffs_header.visible = not _buffs_collapsed
	vbox.add_child(_buffs_header)

	_buffs_text_label = RichTextLabel.new()
	_buffs_text_label.bbcode_enabled = true
	_buffs_text_label.fit_content = true
	_buffs_text_label.scroll_active = false
	_buffs_text_label.add_theme_font_size_override("normal_font_size", 8)
	_buffs_text_label.add_theme_constant_override("line_separation", 1)
	_buffs_text_label.custom_minimum_size = Vector2(BAR_W - 16.0, 0)
	vbox.add_child(_buffs_text_label)

	_buffs_panel.visible = false
	_buffs_last = ""
	game_hud.add_child(_buffs_panel)


# 按 STAT_MOD_LABELS 顺序拼 bbcode 文本; item_mods 无非零项 => 隐藏面板
func _update_buffs_panel() -> void:
	if _buffs_panel == null or not is_instance_valid(_buffs_panel):
		return
	var p = GameManager.player
	if p == null or p.item_mods.is_empty():
		_buffs_panel.visible = false
		_buffs_last = ""
		return
	var parts: Array = []
	for key in STAT_MOD_LABELS.keys():
		var v: float = float(p.item_mods.get(key, 0.0))
		if absf(v) < 0.001:
			continue
		var meta: Dictionary = STAT_MOD_LABELS[key]
		var shown: String
		if meta["fmt"] == "pct":
			shown = "%+d%%" % int(round(v * 100.0))
		else:
			shown = "%+d" % int(round(v))
		var col := "#7BD88F" if v > 0.0 else "#E8635A"
		parts.append("[color=#9AA0AC]%s[/color] [color=%s]%s[/color]" % [meta["name"], col, shown])
	if parts.is_empty():
		_buffs_panel.visible = false
		_buffs_last = ""
		return
	var joined: String
	if _buffs_collapsed:
		# 折叠: 只留一行「N 项」+ 窄宽 + 隐藏标题行, 左上视野几乎全露出
		joined = "%d 项" % parts.size()
		_buffs_header.visible = false
		_buffs_panel.custom_minimum_size = Vector2(BUFFS_COLLAPSED_W, 0)
		_buffs_text_label.custom_minimum_size = Vector2(BUFFS_COLLAPSED_W - 16.0, 0)
	else:
		# 展开: 与血条同宽左缘对齐; 项数截断到 BUFFS_SHOW_MAX, 后期 14 项满铺不再无限长高
		_buffs_header.visible = true
		_buffs_panel.custom_minimum_size = Vector2(BAR_W, 0)
		_buffs_text_label.custom_minimum_size = Vector2(BAR_W - 16.0, 0)
		if parts.size() > BUFFS_SHOW_MAX:
			var hidden: int = parts.size() - BUFFS_SHOW_MAX
			parts = parts.slice(0, BUFFS_SHOW_MAX)
			parts.append("[color=#6B7078]…(+%d)[/color]" % hidden)
		joined = " · ".join(PackedStringArray(parts))
	if joined == _buffs_last:
		return
	_buffs_last = joined
	_buffs_text_label.text = joined
	_buffs_panel.visible = true


# Tab 切换折叠/展开: 清 _buffs_last 强制下帧重拼, 标题行与面板宽立即同步(不等刷新帧)
func _toggle_buffs_panel() -> void:
	_buffs_collapsed = not _buffs_collapsed
	_buffs_last = ""
	if _buffs_header != null and is_instance_valid(_buffs_header):
		_buffs_header.visible = not _buffs_collapsed
	if _buffs_panel != null and is_instance_valid(_buffs_panel):
		var w: float = BUFFS_COLLAPSED_W if _buffs_collapsed else BAR_W
		_buffs_panel.custom_minimum_size = Vector2(w, 0)
		if _buffs_text_label != null and is_instance_valid(_buffs_text_label):
			_buffs_text_label.custom_minimum_size = Vector2(w - 16.0, 0)


func _build_weapon_bar() -> void:
	_weapon_labels.clear()
	var ids := GameManager.WEAPONS.keys()
	var slot_w := 68.0
	# 槽位随武器数量自动居中(当前 6 把 => 总宽 ~408, 屏宽 640 内留白)
	var total := slot_w * float(ids.size())
	var x := W / 2.0 - total / 2.0
	for id in ids:
		_slot(_weapon_slot(id), x)
		x += slot_w


# 单个武器槽: 卡通圆角底 + 像素图标(左) + 名字/等级徽章(右), 叠呼吸动画层
func _weapon_slot(id: String) -> Dictionary:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 0.78)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(3)
	sb.border_color = Color(0.25, 0.25, 0.32, 0.9)
	sb.set_border_width_all(1)

	var panel := PanelContainer.new()
	panel.size = Vector2(60, 26)
	panel.custom_minimum_size = Vector2(60, 26)
	panel.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	panel.add_child(hbox)

	# 图标: 16×16 程序化像素, 1:1 显示, 居中
	var icon := TextureRect.new()
	icon.texture = GameManager.weapon_icon_texture(id)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var name := Label.new()
	name.add_theme_font_size_override("font_size", 8)
	name.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	vbox.add_child(name)

	var badge := Label.new()
	badge.add_theme_font_size_override("font_size", 7)
	badge.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(badge)

	return {"panel": panel, "name": name, "badge": badge, "icon": icon, "id": id}


# 把槽位放进战斗 HUD; 附一个呼吸缩放摇动层(见 _process_weapons)
var _weapon_slots: Array = []

func _slot(data: Dictionary, x: float) -> void:
	var panel: PanelContainer = data["panel"]
	panel.position = Vector2(x, H - 32)
	game_hud.add_child(panel)
	_weapon_slots.append(data)


func _process(delta: float) -> void:
	# 长按连发驱动: 独立于战斗 HUD, 任何界面/暂停中都生效(本节点 PROCESS_MODE_ALWAYS)
	_hold_process(delta)
	# 主菜单动效独立于战斗 HUD, 必须先于 game_hud 早退判断
	if _menu_pulse != null or _menu_glow != null or _menu_title != null:
		_process_menu_fx(delta)
	if GameManager.state == GameManager.State.CODEX:
		_cx_update_scroll_hint()
	if game_hud == null or not is_instance_valid(game_hud):
		return
	if GameManager.state != GameManager.State.PLAYING:
		return
	var p = GameManager.player
	if p == null:
		return

	_update_hp_bar(p, delta)
	_update_xp_bar(delta)

	_update_wave_label()
	_kills_label.text = str(GameManager.kills)
	if _coin_label != null:
		_coin_label.text = "金币 %d" % int(GameManager.coins)
	_update_buffs_panel()
	update_curse_label()   # 与加成面板同刷新时机; 内部有值缓存, 常态只是一次 int 比较

	_process_weapons(p, delta)

	_process_boss_bar()


# 刷新武器槽: 名字/等级徽章 + 高级框样式 + 呼吸缩放(未拥有暗、进化金呼吸)
var _breathe_t := 0.0

func _process_weapons(p: Node, delta: float) -> void:
	_breathe_t += delta
	var breathe := 1.0 + 0.03 * sin(_breathe_t * 3.5)
	for data in _weapon_slots:
		var id: String = data["id"]
		var lvl: int = p.weapon_levels.get(id, 0)
		var evolved: bool = p.is_evolved(id)
		var owned: bool = lvl > 0
		var panel: PanelContainer = data["panel"]
		var name: Label = data["name"]
		var badge: Label = data["badge"]
		var icon: TextureRect = data["icon"]

		# 未拥有: 变暗 + 灰字「未获得」
		panel.modulate = Color(1, 1, 1, 1) if owned else Color(0.45, 0.45, 0.5, 0.6)
		if not owned:
			name.text = GameManager.WEAPONS[id]["name"]
			badge.text = "未获得"
			name.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
			_set_slot_border(panel, Color(0.25, 0.25, 0.32, 0.6), 1)
			continue

		# 已拥有: 图标亮起; 进化卡金色呼吸框 + 星标
		if evolved:
			name.text = GameManager.EVOLUTIONS[id]["name"]
			badge.text = "★ 进化"
			name.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			_set_slot_border(panel, Color(1.0, 0.80, 0.25, 0.9), 2)
			panel.scale = Vector2.ONE * breathe
		else:
			name.text = GameManager.WEAPONS[id]["name"]
			badge.text = "Lv%d" % lvl
			name.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
			badge.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
			_set_slot_border(panel, Color(0.35, 0.55, 0.85, 0.8), 1)
			panel.scale = Vector2.ONE


func _set_slot_border(panel: PanelContainer, color: Color, width: int) -> void:
	var sb: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = color
		sb.set_border_width_all(width)


func _update_hp_bar(p: Node, delta: float) -> void:
	var max_hp: float = p.max_hp_value()
	var hp: float = p.hp
	_hp_bar.max_value = max_hp
	_hp_label.text = "%d / %d" % [int(hp), int(max_hp)]

	# 掉血时触发白闪(升血不闪)
	if hp < _hp_prev - 0.01:
		_hp_flash = 1.0
	_hp_prev = hp
	_hp_flash = maxf(_hp_flash - delta * 5.0, 0.0)
	_pulse_t += delta

	# 平滑过渡: 显示值追真实值
	var ratio := clampf(delta * LERP_RATE, 0.0, 1.0)
	_hp_shown = lerpf(_hp_shown, hp, ratio)
	if absf(_hp_shown - hp) < 0.05:
		_hp_shown = hp
	_hp_bar.value = _hp_shown

	# 配色: 血条恒红(基色即红, 原绿→黄→红渐变警告失效), ≤30% 亮红脉动靠"亮起"报警
	var pct := hp / max_hp if max_hp > 0.0 else 0.0
	var base: Color
	if pct > 0.3:
		base = HP_HIGH
	else:
		var pulse: float = 0.5 + 0.5 * sin(_pulse_t * 8.0)
		base = HP_LOW.lerp(HP_LOW_PULSE, pulse)
	if _hp_fill != null:
		_hp_fill.bg_color = base.lerp(Color.WHITE, _hp_flash * 0.8)


func _update_xp_bar(delta: float) -> void:
	var need := GameManager.xp_to_next()
	_xp_bar.max_value = need
	_level_label.text = "Lv %d" % GameManager.level

	# 升级瞬间 xp 被扣减归零, 直接跳变而非缓慢回退
	if GameManager.level != _level_prev:
		_level_prev = GameManager.level
		_xp_shown = GameManager.xp
	else:
		var ratio := clampf(delta * LERP_RATE, 0.0, 1.0)
		_xp_shown = lerpf(_xp_shown, GameManager.xp, ratio)
	_xp_bar.value = _xp_shown

	if _xp_fill != null:
		_xp_fill.bg_color = XP_COLOR


func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	return "%02d:%02d" % [m, s]


# 结算界面统计行: 标签右对齐 + 数值左对齐分色, 两列对位不再靠空格硬凑
func _make_stat_row(label: String, value: String, value_color: Color, font_size: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.72, 0.72, 0.76))
	l.custom_minimum_size = Vector2(78, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(l)

	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", font_size)
	v.add_theme_color_override("font_color", value_color)
	row.add_child(v)

	return row


func _difficulty_name() -> String:
	match Settings.difficulty:
		0: return "简单"
		2: return "困难"
		_: return "普通"


func _difficulty_color() -> Color:
	match Settings.difficulty:
		0: return Color(0.55, 0.95, 0.55)   # 简单 绿
		2: return Color(1.0, 0.40, 0.35)    # 困难 红
		_: return Color(0.95, 0.85, 0.40)   # 普通 金


# ================= 升级三选一 =================

func show_level_up(options: Array) -> void:
	_clear_all()
	levelup_screen = _full_screen()
	levelup_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	levelup_screen.add_child(overlay)

	var title := _label("✦ 升级! ✦", 20)
	title.position = Vector2(0, 60)
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	levelup_screen.add_child(title)

	if options.is_empty():
		# 无可用项, 直接恢复(E/Enter 同样可触发, 见 _unhandled_input)
		_levelup_cards.clear()
		_levelup_options.clear()
		var cont := _make_btn("没有更多强化, 继续", Color(0.45, 0.60, 0.85))
		cont.position = Vector2(W / 2 - 60, 200)
		cont.size = Vector2(120, 28)
		cont.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
		cont.pressed.connect(_resume_from_levelup)
		levelup_screen.add_child(cont)
		return

	_levelup_options = options
	_levelup_cards.clear()
	_levelup_sel = 0

	for i in range(options.size()):
		var opt: Dictionary = options[i]
		var card := _option_card(opt)
		card.position = Vector2(LVL_CARD_X0 + float(i) * LVL_CARD_GAP, LVL_CARD_Y)
		# 晃动绕卡片中心旋转: pivot 默认在左上角, 不设会变成"甩尾"
		card.pivot_offset = card.size / 2.0
		levelup_screen.add_child(card)
		_levelup_cards.append(card)

	# 选中框: 卡片之后加入 => 盖在卡片之上, 切换时沿卡片间滑动并换成新卡的稀有度色
	_levelup_frame = _make_levelup_frame(_sel_rarity())
	levelup_screen.add_child(_levelup_frame)

	# ▼ 选中标记(在卡片上方, 随选择左右移动, 同稀有度色)
	_levelup_marker = _label("▼", 12)
	_levelup_marker.size = Vector2(LVL_CARD_W, 12)
	_levelup_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	levelup_screen.add_child(_levelup_marker)

	# 操作提示
	var hint := _label("A / D 选择 · 空格 确认 · R 重抽 · 鼠标点击亦可", 8)
	hint.position = Vector2(0, LVL_CARD_Y + LVL_CARD_H + 16)
	hint.anchor_left = 0.0; hint.anchor_right = 1.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.85))
	levelup_screen.add_child(hint)

	# 重抽按钮: 提示行下方居中; 用尽不隐藏只置灰(让剩余次数对玩家始终可见)。
	# 不用 .disabled —— 禁用态会吞点击导致无反馈, 次数判定收在 _on_levelup_reroll 里统一处理。
	_levelup_reroll_btn = _make_btn("", Color(0.85, 0.62, 0.30))
	_levelup_reroll_btn.position = Vector2(W / 2.0 - 75.0, LVL_CARD_Y + LVL_CARD_H + 32)
	_levelup_reroll_btn.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留空格双触发
	_levelup_reroll_btn.pressed.connect(_on_levelup_reroll)
	levelup_screen.add_child(_levelup_reroll_btn)
	# 入树后再冲刷尺寸: 树外 theme 退化时 .size 会被陈旧 min-size 钳住(血条/经验条踩过的坑)
	_levelup_reroll_btn.set_deferred("size", Vector2(150, 22))
	_update_reroll_btn()

	_update_levelup_selection()


# ================= 波间商店 =================
# 每波结束(非最后一波)进入; 用本局金币买一次性增益, 关闭后进下一波

var _wave_shop_coin_label: Label = null
var _wave_shop_row: HBoxContainer = null   # 商品卡容器(进店一次性构建, 无刷新)
var _wave_shop_cont_btn: Button = null     # 继续战斗按钮(上下键可达)
var _wave_shop_action_row: HBoxContainer = null   # 继续战斗按钮行(整体居中)
var _wave_shop_btns: Array = []   # 商品卡片 [{"panel","border","border_w","base_bg","cost","price_lbl","price_icon"}], 供红/金两态与焦点导航
var _shop_sel: int = 0           # 当前选中商品索引(左右键在商品行内切换)
var _shop_focus_row: int = 0     # 纵向焦点: 0=商品行 / 1=继续战斗按钮
var _shop_toast: Label = null     # 金币不足提示(单例复用, 连续点击只刷新不走堆叠)
var _shop_toast_tween: Tween = null   # 提示动画 tween(重复弹时先杀掉旧的, 防止多个 tween 抢透明度)
var _meta_shop_info: Label = null # 局外商店面板底部固定介绍行(toast 显示期间暂隐, 见 _shop_toast_show)
var _wave_shop_stat_flow: HFlowContainer = null   # 本局加成芯片流(购买后全量重建)
var _wave_shop_stat_empty: Label = null   # 空态暗字提示(有芯片时隐藏)
var _wave_shop_stat_title: Label = null   # 「本局属性加成」小标题(空态时隐藏)
var _shop_glow_overlay: Control = null   # 商品卡流光边框绘制层(盖在全部卡片上, 按选中卡自绘)


# ================= 商品/升级卡稀有度配色 =================
# 与 SHOP_OFFERS 同一套 rarity 体系: common 普通(灰) / uncommon 精良(蓝) / rare 稀有(紫)
# legendary 传说(金)仅升级三选一的进化卡使用, 波间商店不会出现
# 稀有度决定卡框颜色+粗细、名称字色; 越稀有越贵越强、抽取权重越低(见 GameManager.roll_shop)

func _rarity_border(rarity: String) -> Color:
	match rarity:
		"uncommon":  return Color(0.35, 0.68, 1.0, 0.85)
		"rare":      return Color(0.78, 0.42, 1.0, 0.90)
		"legendary": return Color(1.0, 0.75, 0.2, 1.0)
		_:           return Color(0.45, 0.50, 0.60, 0.60)


func _rarity_border_w(rarity: String) -> int:
	if rarity == "common":
		return 1
	return 3 if rarity == "legendary" else 2


func _rarity_text(rarity: String) -> Color:
	match rarity:
		"uncommon":  return Color(0.62, 0.83, 1.0)
		"rare":      return Color(0.88, 0.68, 1.0)
		"legendary": return Color(1.0, 0.85, 0.3)
		_:           return Color(0.95, 0.95, 1.0)


func _rarity_name(rarity: String) -> String:
	match rarity:
		"uncommon":  return "精良"
		"rare":      return "稀有"
		"legendary": return "传说"
		_:           return "普通"


# 选中框配色: 比卡框更亮更实(选中态要跳出来), 底衬用同色低透明度铺一层
# 进化卡沿用金色但更饱和, 与原有「金色 = 最高级」的视觉记忆一致
func _rarity_select(rarity: String) -> Color:
	match rarity:
		"uncommon":  return Color(0.55, 0.82, 1.0, 1.0)
		"rare":      return Color(0.90, 0.55, 1.0, 1.0)
		"legendary": return Color(1.0, 0.92, 0.55, 1.0)
		_:           return Color(0.80, 0.85, 0.95, 1.0)


# 商品卡选中流光绘制层: 盖在商品行之上, 每帧自绘选中卡的高亮动效
# 叠加在静态金边框之上, 形成双层聚焦——两道金色光弧沿椭圆形卡缘反向缓缓游走(流光),
# 同时选中卡背景做正弦呼吸染色(深底→亮蓝起→回), 动态地把视线拉到当前选中/可购商品上
class ShopCardGlow extends Control:
	var _t := 0.0

	func _ready() -> void:
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		var hud = get_meta("hud", null)
		if hud == null:
			return
		var idx: int = hud._shop_sel if hud._shop_focus_row == 0 else -1
		if idx >= 0 and idx < hud._wave_shop_btns.size():
			var panel: PanelContainer = hud._wave_shop_btns[idx].get("panel")
			if panel != null and is_instance_valid(panel):
				var sb2: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
				if sb2 != null:
					# 背景呼吸染色: 低点接近原深底, 高点亮蓝(贴合冷色主题)
					var low := Color(0.09, 0.11, 0.20, 0.94)
					var high := Color(0.20, 0.30, 0.52, 0.94)
					var k := 0.5 + 0.5 * sin(_t * 3.0)
					sb2.bg_color = low.lerp(high, k)
		queue_redraw()

	# 流光轨 = 卡片圆角矩形环(外扩 3px): 椭圆轨的对角段会沉进卡片内部,
	# 横切标题与价格按钮(实测截图), 环轨才贴着卡边游走
	const RING_RAD := 9.0   # 卡片 stylebox 圆角 6 + 外扩 3

	func _draw() -> void:
		var hud = get_meta("hud", null)
		if hud == null:
			return
		var idx: int = hud._shop_sel if hud._shop_focus_row == 0 else -1
		if idx < 0 or idx >= hud._wave_shop_btns.size():
			return
		var panel: PanelContainer = hud._wave_shop_btns[idx].get("panel")
		if panel == null or not is_instance_valid(panel):
			return
		# overlay 全屏铺满, 本地坐标 == 全局; 取卡片全局矩形外扩 3px 作为流光环轨
		var r: Rect2 = panel.get_global_rect().grow(3.0)
		var phase := _t * 110.0     # 弧长偏移 px/s, 环周 ~510px => 一圈约 4.6s
		var span := 0.30 * _ring_len(r)
		# 主流光: 两道半周等距的金色亮弧, 顺向
		for i in range(2):
			var s0 := phase + float(i) * 0.5 * _ring_len(r)
			_draw_ring_arc(r, s0, s0 + span, Color(1.0, 0.85, 0.35, 0.95), 2.0)
		# 副流光: 反向的淡金弧, 形成交错呼应
		for i in range(2):
			var s0 := -phase + float(i) * 0.5 * _ring_len(r)
			_draw_ring_arc(r, s0, s0 + span * 0.8, Color(1.0, 0.92, 0.62, 0.45), 1.0)

	# 圆角矩形环周长: 4 直边 + 4 个 1/4 圆弧
	func _ring_len(r: Rect2) -> float:
		var w := r.size.x - 2.0 * RING_RAD
		var h := r.size.y - 2.0 * RING_RAD
		return 2.0 * (w + h) + TAU * RING_RAD

	# 环上按弧长 s 取点(顺时针: 上边→右弧→右边→…); posmod 支持反向弧
	func _ring_point(r: Rect2, s: float) -> Vector2:
		var w := r.size.x - 2.0 * RING_RAD
		var h := r.size.y - 2.0 * RING_RAD
		var arc := 0.5 * PI * RING_RAD
		s = posmod(s, _ring_len(r))
		if s < w:
			return Vector2(r.position.x + RING_RAD + s, r.position.y)
		s -= w
		if s < arc:
			return _ring_corner(r.position + Vector2(r.size.x - RING_RAD, RING_RAD), -0.5 * PI, s / RING_RAD)
		s -= arc
		if s < h:
			return Vector2(r.end.x, r.position.y + RING_RAD + s)
		s -= h
		if s < arc:
			return _ring_corner(r.end - Vector2(RING_RAD, RING_RAD), 0.0, s / RING_RAD)
		s -= arc
		if s < w:
			return Vector2(r.end.x - RING_RAD - s, r.end.y)
		s -= w
		if s < arc:
			return _ring_corner(r.position + Vector2(RING_RAD, r.size.y - RING_RAD), 0.5 * PI, s / RING_RAD)
		s -= arc
		if s < h:
			return Vector2(r.position.x, r.end.y - RING_RAD - s)
		s -= h
		return _ring_corner(r.position + Vector2(RING_RAD, RING_RAD), PI, s / RING_RAD)

	func _ring_corner(c: Vector2, a0: float, da: float) -> Vector2:
		return c + Vector2(cos(a0 + da), sin(a0 + da)) * RING_RAD

	func _draw_ring_arc(r: Rect2, s0: float, s1: float, col: Color, w: float) -> void:
		var pts := PackedVector2Array()
		var n := 36
		for k in range(n + 1):
			pts.append(_ring_point(r, s0 + (s1 - s0) * float(k) / float(n)))
		draw_polyline(pts, col, w, true)


func show_wave_shop() -> void:
	_clear_all()
	wave_shop_screen = _full_screen()
	wave_shop_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.66)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	wave_shop_screen.add_child(overlay)

	# 纵向预算(640×360): 标题 8 / 金币胶囊 31..51 / 卡行 57..183 / 动作行 190..216 / 加成区 222..≤306
	var title := _label("补 给 商 店", 17)
	title.position = Vector2(0, 8)
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	wave_shop_screen.add_child(title)

	wave_shop_screen.add_child(_wave_shop_coin_pill())

	# 商品列表(5 卡横排并列一行, 池子共 7 件抽 5; 无刷新, 进店抽定即所见)
	_wave_shop_row = HBoxContainer.new()
	_wave_shop_row.add_theme_constant_override("separation", 12)
	_wave_shop_row.position = Vector2(56, 57)   # 5×96 + 4×12 = 528, 水平居中于 640
	wave_shop_screen.add_child(_wave_shop_row)

	_rebuild_shop_cards()

	# 动作行: 只剩「继续战斗」单钮, 150 宽水平居中于 640 → x=245
	_wave_shop_action_row = HBoxContainer.new()
	_wave_shop_action_row.add_theme_constant_override("separation", 12)
	_wave_shop_action_row.position = Vector2(245, 190)
	wave_shop_screen.add_child(_wave_shop_action_row)

	_wave_shop_cont_btn = _make_btn("继续战斗 →", Color(0.35, 0.75, 0.45))
	_wave_shop_cont_btn.set_meta("base_accent", Color(0.35, 0.75, 0.45))
	_wave_shop_cont_btn.custom_minimum_size = Vector2(150, 26)
	_wave_shop_cont_btn.focus_mode = Control.FOCUS_NONE   # 同商品按钮: 防焦点残留导致空格双触发
	_wave_shop_cont_btn.pressed.connect(_on_wave_shop_close)
	_wave_shop_action_row.add_child(_wave_shop_cont_btn)

	# —— 本局加成区: 标题 + 芯片流(自适应换行, 不再固定高度/截断) ——
	wave_shop_screen.add_child(_wave_shop_stat_zone())

	# 商品卡流光绘制层: 最后加, 盖在所有卡片/按钮之上; 全屏铺满, 每帧自绘选中卡的流光边框与背景呼吸
	_shop_glow_overlay = ShopCardGlow.new()
	_shop_glow_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop_glow_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 不挡点击
	_shop_glow_overlay.set_meta("hud", self)
	wave_shop_screen.add_child(_shop_glow_overlay)

	_refresh_wave_shop()


# 金币计数胶囊: 圆角暗底金边, 金币图标 + 数字(只存数字 Label, 刷新时改 text)
func _wave_shop_coin_pill() -> PanelContainer:
	var pill := PanelContainer.new()
	pill.position = Vector2(278, 31)   # (640-84)/2 居中
	pill.custom_minimum_size = Vector2(84, 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.06, 0.92)
	sb.border_color = Color(0.72, 0.56, 0.18, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)   # 高 20 → 半径 10 即胶囊
	sb.content_margin_left = 10.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	pill.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 5)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pill.add_child(hbox)

	var icon := TextureRect.new()
	icon.texture = GameManager.coin_icon_texture()
	icon.custom_minimum_size = Vector2(12, 12)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)

	_wave_shop_coin_label = _label("0", 12)
	_wave_shop_coin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_wave_shop_coin_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_wave_shop_coin_label)

	return pill


# 本局加成区: 小标题 + HFlowContainer 芯片流(自动换行, 高度自适应, 14 键全显示不截断)
# 空态: 隐藏标题与流, 只留一行暗字提示(不再是大空框)
func _wave_shop_stat_zone() -> Control:
	var zone := Control.new()
	zone.position = Vector2(28, 222)
	zone.size = Vector2(584, 84)   # 芯片最坏 4 行底 ≈306, 360 前留安全垫
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_wave_shop_stat_title = _label("本局属性加成", 8)
	_wave_shop_stat_title.add_theme_color_override("font_color", Color(0.55, 0.58, 0.66))
	zone.add_child(_wave_shop_stat_title)

	_wave_shop_stat_flow = HFlowContainer.new()
	_wave_shop_stat_flow.position = Vector2(0, 14)
	_wave_shop_stat_flow.size = Vector2(584, 70)
	_wave_shop_stat_flow.add_theme_constant_override("h_separation", 4)
	_wave_shop_stat_flow.add_theme_constant_override("v_separation", 4)
	zone.add_child(_wave_shop_stat_flow)

	_wave_shop_stat_empty = _label("暂无加成 · 购买商品后在此累计", 8)
	_wave_shop_stat_empty.position = Vector2(0, 6)
	_wave_shop_stat_empty.size = Vector2(584, 14)
	_wave_shop_stat_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_shop_stat_empty.add_theme_color_override("font_color", Color(0.42, 0.44, 0.48))
	zone.add_child(_wave_shop_stat_empty)

	return zone


# 单条加成芯片: 圆角胶囊, 正=绿系 / 负=红系(字色沿用原 bbcode 的 #7BD88F/#E8635A)
func _stat_chip(text: String, positive: bool) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if positive:
		sb.bg_color = Color(0.10, 0.22, 0.14, 0.92)
		sb.border_color = Color(0.30, 0.62, 0.38, 0.8)
	else:
		sb.bg_color = Color(0.24, 0.10, 0.10, 0.92)
		sb.border_color = Color(0.62, 0.28, 0.26, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)   # 内容高 ~14 → 胶囊
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", sb)

	var lbl := _label(text, 8)
	lbl.add_theme_color_override("font_color",
		Color(0.483, 0.847, 0.561) if positive else Color(0.910, 0.388, 0.353))
	chip.add_child(lbl)
	return chip


# 刷新加成芯片流: 读 player.item_mods 全部非零项, 全量重建(先 queue_free 旧芯片防叠层)
func _refresh_shop_stats() -> void:
	if _wave_shop_stat_flow == null:
		return
	for child in _wave_shop_stat_flow.get_children():
		child.queue_free()
	var p = GameManager.player
	var count := 0
	if p != null:
		var mods: Dictionary = p.item_mods
		for key in STAT_MOD_LABELS.keys():
			var v: float = float(mods.get(key, 0.0))
			if absf(v) < 0.001:
				continue
			var meta: Dictionary = STAT_MOD_LABELS[key]
			var shown: String
			if meta["fmt"] == "pct":
				shown = "%+d%%" % int(round(v * 100.0))
			else:
				shown = "%+d" % int(round(v))
			_wave_shop_stat_flow.add_child(_stat_chip("%s %s" % [str(meta["name"]), shown], v > 0.0))
			count += 1
	var empty := count == 0
	if _wave_shop_stat_title != null:
		_wave_shop_stat_title.visible = not empty
	_wave_shop_stat_flow.visible = not empty
	if _wave_shop_stat_empty != null:
		_wave_shop_stat_empty.visible = empty


# 单个商品卡(Brotato 风): 稀有度角标 + 大图标 + 名称 + 描述 + 价格行(读 cur_shop 当前展示池)
# 整卡 gui_input 左键 = 选中并购买(价格不再是卡内 Button); 卡底按稀有度淡 tint
# 卡框色/宽度/底色存进 _wave_shop_btns, 焦点取消时按此恢复(不被金框覆盖后回不去)
func _wave_shop_card(idx: int) -> Control:
	var offer: Dictionary = GameManager.cur_shop[idx]
	var rarity: String = str(offer.get("rarity", "common"))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(96, 126)   # 5 卡一行(5×96+4×12=528), 原 140 宽只容得下 4 卡
	var sb := StyleBoxFlat.new()
	# 底色 = 暗底混 16% 稀有度色, 卡片带淡淡的稀有度氛围
	sb.bg_color = Color(0.10, 0.10, 0.15, 0.92).lerp(Color(_rarity_border(rarity)), 0.16)
	sb.border_color = _rarity_border(rarity)
	sb.set_border_width_all(_rarity_border_w(rarity))
	sb.set_corner_radius_all(6)   # ShopCardGlow 的环轨半径按圆角 6+3 写死, 不可改
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	# 稀有度角标(顶部小字居中)
	var rarity_lbl := _label(_rarity_name(rarity), 7)
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.add_theme_color_override("font_color", _rarity_text(rarity))
	vbox.add_child(rarity_lbl)

	# 商品图标: 12×12 程序化像素 @4× 整数倍显示(全局 Nearest, 放大不糊)
	var icon := TextureRect.new()
	icon.texture = GameManager.shop_icon_texture(str(offer.get("kind", "")))
	icon.custom_minimum_size = Vector2(0, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(icon)

	var name := _label(str(offer["name"]), 10)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_color_override("font_color", _rarity_text(rarity))
	vbox.add_child(name)

	var desc := _label(str(offer["desc"]), 7)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	vbox.add_child(desc)

	# 价格行: 金币图标 + 数字(纯展示; 买得起=金 / 买不起=红, 两态由 _refresh_wave_shop 染)
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 3)
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(price_row)

	var price_icon := TextureRect.new()
	price_icon.texture = GameManager.coin_icon_texture()
	price_icon.custom_minimum_size = Vector2(9, 9)
	price_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	price_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	price_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_row.add_child(price_icon)

	var price_lbl := _label("%d" % int(offer["cost"]), 9)
	price_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_row.add_child(price_lbl)

	panel.gui_input.connect(_on_shop_card_pressed.bind(idx))
	_wave_shop_btns.append({"panel": panel, "cost": int(offer["cost"]),
		"border": _rarity_border(rarity), "border_w": _rarity_border_w(rarity),
		"base_bg": sb.bg_color, "price_lbl": price_lbl, "price_icon": price_icon})

	return panel


# 鼠标点卡 = 选中 + 购买(照升级卡 _on_option_pressed 模式); 买不起时 _on_wave_shop_buy 会弹 toast
func _on_shop_card_pressed(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_shop_sel = idx
		_shop_focus_row = 0
		_update_shop_focus()
		_on_wave_shop_buy(idx)


# 清空商品卡容器并按 cur_shop 重建(进店时一次性)
func _rebuild_shop_cards() -> void:
	if _wave_shop_row == null:
		return
	for child in _wave_shop_row.get_children():
		child.queue_free()
	_wave_shop_btns.clear()
	for i in range(GameManager.cur_shop.size()):
		_wave_shop_row.add_child(_wave_shop_card(i))
	_shop_sel = 0
	_shop_focus_row = 0   # 开局焦点在商品行, 让玩家先看商品
	_update_shop_focus()


# 波间商店键盘导航: A/D 在商品行内切换选中商品(动作行只剩继续战斗单钮, 无需横选)
func _wave_shop_move(step: int, quiet: bool = false) -> void:
	if _shop_focus_row == 0:
		var n := _wave_shop_btns.size()
		if n == 0:
			return
		_shop_sel = posmod(_shop_sel + step, n)
	if not quiet:
		GameManager.play_sfx("pickup")
	_update_shop_focus()


# 纵向焦点移动: W 上移, S 下移; 两层 0=商品行 1=继续战斗按钮, 到边缘环绕
func _wave_shop_row_move(step: int, quiet: bool = false) -> void:
	_shop_focus_row = posmod(_shop_focus_row + step, 2)
	if not quiet:
		GameManager.play_sfx("pickup")
	_update_shop_focus()


# 统一刷新焦点高亮: 商品行选中卡金框提亮; 动作行只有继续战斗单钮, 整行提亮
# (按钮边框色保留红/金价位语义, 焦点用亮度区分, 互不打架; 不碰 focus 避免双层触发)
func _update_shop_focus() -> void:
	var on_cards: bool = _shop_focus_row == 0
	for i in range(_wave_shop_btns.size()):
		var card: Dictionary = _wave_shop_btns[i]
		var panel: PanelContainer = card.get("panel")
		if panel == null or not is_instance_valid(panel):
			continue
		var sb: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if sb == null:
			continue
		if on_cards and i == _shop_sel:
			sb.border_color = Color(1.0, 0.80, 0.30)
			sb.set_border_width_all(3)
			panel.modulate = Color(1.12, 1.12, 1.12)
		else:
			# 恢复该卡稀有度边框(而非写死灰框), 否则选中过的卡丢失稀有度信息
			sb.border_color = Color(card.get("border", Color(0.45, 0.50, 0.60, 0.6)))
			sb.set_border_width_all(int(card.get("border_w", 1)))
			sb.bg_color = Color(card.get("base_bg", Color(0.10, 0.10, 0.15, 0.92)))
			panel.modulate = Color(1.0, 1.0, 1.0)
	if _wave_shop_cont_btn != null:
		_set_btn_highlight(_wave_shop_cont_btn, _shop_focus_row == 1)


# 空格/Enter: 按当前焦点层分发动作(商品行 = 购买 / 动作行 = 继续战斗)
func _wave_shop_confirm() -> void:
	match _shop_focus_row:
		0:
			if _shop_sel >= 0 and _shop_sel < _wave_shop_btns.size():
				_on_wave_shop_buy(_shop_sel)
		1:
			_on_wave_shop_close()


func _refresh_wave_shop() -> void:
	if _wave_shop_coin_label != null:
		_wave_shop_coin_label.text = "%d" % int(GameManager.coins)
	# 价格两态: 买不起染红 / 买得起金(染字色 + 金币图标 modulate; 卡片本身保持可点击弹 toast)
	var coins: int = int(GameManager.coins)
	for b in _wave_shop_btns:
		var cost: int = int(b["cost"])
		var afford := coins >= cost
		var price_lbl: Label = b["price_lbl"]
		if price_lbl != null and is_instance_valid(price_lbl):
			price_lbl.add_theme_color_override("font_color",
				Color(1.0, 0.82, 0.30) if afford else Color(0.90, 0.32, 0.30))
		var price_icon: TextureRect = b["price_icon"]
		if price_icon != null and is_instance_valid(price_icon):
			price_icon.modulate = Color(1, 1, 1) if afford else Color(1.0, 0.45, 0.42)
	# 加成芯片流同步(购买/进店都要刷新; 金币数变化也顺带更新)
	_refresh_shop_stats()


# 局部改按钮边框色(红=买不起 / 金=可负担); 复用 _make_btn 的样式, 只换描边
# 存下基础色, 供焦点高亮取消时恢复(见 _set_btn_highlight)
func _set_btn_border(btn: Button, accent: Color) -> void:
	btn.set_meta("base_accent", accent)
	_set_btn_border_w(btn, accent, 1)


# 按钮焦点高亮: 选中时换成金色加粗边框 + 提亮; 未选中恢复基础价位色(边框挡住原红/金)
func _set_btn_highlight(btn: Button, focused: bool) -> void:
	if btn == null:
		return
	var accent: Color = btn.get_meta("base_accent", Color(0.45, 0.50, 0.60))
	if focused:
		_set_btn_border_w(btn, Color(1.0, 0.90, 0.40), 2)
		btn.modulate = Color(1.2, 1.2, 1.2)
	else:
		_set_btn_border_w(btn, accent, 1)
		btn.modulate = Color(1, 1, 1)


func _set_btn_border_w(btn: Button, accent: Color, width: int) -> void:
	for key in ["normal", "hover"]:
		var sb: StyleBoxFlat = btn.get_theme_stylebox(key) as StyleBoxFlat
		if sb != null:
			sb.border_color = accent
			sb.set_border_width_all(width)


func _on_wave_shop_buy(idx: int) -> void:
	if idx < 0 or idx >= GameManager.cur_shop.size():
		return
	var offer: Dictionary = GameManager.cur_shop[idx]
	# 诅咒商品加不满(已达上限或本件会溢出): 拒买并说明, 不扣钱(与 buy_shop_offer 的 return false 对应)
	if str(offer.get("kind", "")) == "curse" and \
		GameManager.curse_level + int(offer.get("value", 0)) > GameManager.CURSE_MAX:
		GameManager.play_sfx("hurt")
		_wave_shop_toast("诅咒接近上限 · 本件无法整件生效")
		return
	if GameManager.coins < float(offer["cost"]):
		GameManager.play_sfx("hurt")
		var short: int = int(offer["cost"]) - int(GameManager.coins)
		_wave_shop_toast("金币不足 · 还差 %d" % short)
		_refresh_wave_shop()
		return
	if GameManager.buy_shop_offer(idx):
		_refresh_wave_shop()


# 商店提示(波间/局外共用一个 Label 单例): 红字 + 描边, 上浮淡出; parent = 当前商店界面。
# 两店不会同时存在(进界面先 _clear_all 全清并把 _shop_toast 置 null), 故共用字段安全。
func _shop_toast_show(parent: Control, text: String, y: float) -> void:
	if parent == null:
		return
	if _shop_toast == null:
		_shop_toast = Label.new()
		_shop_toast.add_theme_font_size_override("font_size", 11)
		_shop_toast.add_theme_color_override("font_color", Color(1.0, 0.55, 0.50))
		_shop_toast.add_theme_color_override("font_outline_color", Color(0.20, 0.03, 0.03))
		_shop_toast.add_theme_constant_override("outline_size", 2)
		_shop_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		parent.add_child(_shop_toast)
	# 旧动画先杀(连续点击不叠加)
	if _shop_toast_tween != null and _shop_toast_tween.is_valid():
		_shop_toast_tween.kill()
	_shop_toast.text = text
	_shop_toast.modulate = Color(1, 1, 1, 1)
	_shop_toast.position = Vector2(0, y)
	_shop_toast.anchor_left = 0.0; _shop_toast.anchor_right = 1.0
	_shop_toast.visible = true
	# 局外商店的 toast(y=284)与面板底部固定介绍行同一 y、同居中 —— 直接叠字两行都读不了
	# (2026-09-10 目检 07b)。toast 显示期间暂隐介绍行, 动画结束还原; 两店不同时存在,
	# 波间商店(y=68)不经过这里(_meta_shop_info 只在 shop_screen 构建时赋值)。
	if parent == shop_screen and _meta_shop_info != null and is_instance_valid(_meta_shop_info):
		_meta_shop_info.visible = false
	_shop_toast_tween = create_tween()
	_shop_toast_tween.tween_interval(0.9)
	_shop_toast_tween.parallel().tween_property(_shop_toast, "modulate:a", 0.0, 0.35)
	_shop_toast_tween.parallel().tween_property(_shop_toast, "position:y", y - 8.0, 0.35)
	_shop_toast_tween.tween_callback(_restore_meta_shop_info)


func _restore_meta_shop_info() -> void:
	if _meta_shop_info != null and is_instance_valid(_meta_shop_info):
		_meta_shop_info.visible = true


# 金币不足提示: 商品卡下方(不遮挡)
func _wave_shop_toast(text: String) -> void:
	_shop_toast_show(wave_shop_screen, text, 68.0)


func _on_wave_shop_close() -> void:
	GameManager.play_sfx("select")
	if GameManager.main.has_method("close_wave_shop"):
		GameManager.main.close_wave_shop()


# 无可用强化项时的继续(E/Enter 与按钮共用)
func _resume_from_levelup() -> void:
	GameManager.play_sfx("select")
	get_tree().paused = false
	GameManager.state = GameManager.State.PLAYING
	GameManager.main.hud.show_hud()


# 键盘左右移动选中项(循环), 并刷新高亮
func _levelup_move(step: int, quiet: bool = false) -> void:
	var n := _levelup_cards.size()
	if n == 0:
		return
	_levelup_sel = posmod(_levelup_sel + step, n)
	if not quiet:
		GameManager.play_sfx("pickup")
	_update_levelup_selection()


# 确认当前选中项
func _levelup_confirm() -> void:
	if _levelup_cards.is_empty():
		_resume_from_levelup()
		return
	if _levelup_sel < 0 or _levelup_sel >= _levelup_options.size():
		return
	var opt: Dictionary = _levelup_options[_levelup_sel]
	GameManager.play_sfx("select")
	GameManager.main.on_upgrade_chosen(opt)


# ---------- 升级三选一重抽 ----------
# 按钮文案: 剩余次数一目了然; 用尽后换成「已用尽」
func _reroll_btn_text() -> String:
	var left: int = GameManager.LEVELUP_REROLL_MAX - GameManager.levelup_rerolls
	if left <= 0:
		return "重抽  (已用尽)"
	return "重抽  剩 %d · R" % left


func _update_reroll_btn() -> void:
	if _levelup_reroll_btn == null or not is_instance_valid(_levelup_reroll_btn):
		return
	var left: int = GameManager.LEVELUP_REROLL_MAX - GameManager.levelup_rerolls
	_levelup_reroll_btn.text = _reroll_btn_text()
	# 用尽置灰不隐藏: 保留位置避免布局跳动, 半透明传达"不可用"
	_levelup_reroll_btn.modulate.a = 1.0 if left > 0 else 0.45


func _on_levelup_reroll() -> void:
	if GameManager.state != GameManager.State.LEVEL_UP or _levelup_options.is_empty():
		return
	if GameManager.levelup_rerolls >= GameManager.LEVELUP_REROLL_MAX:
		_lvlup_toast("重抽次数已用尽")
		GameManager.play_sfx("hurt")
		return
	# 防连点: 两次重抽至少隔 0.5s(按钮 + R 键同一入口, 这里统一 gate)
	var now: int = Time.get_ticks_msec()
	if now - _lvlup_reroll_t < 500:
		return
	_lvlup_reroll_t = now
	var new_opts: Array = GameManager.roll_upgrade_options()
	if new_opts.is_empty():
		_lvlup_toast("没有更多强化可抽")
		GameManager.play_sfx("hurt")
		return
	GameManager.levelup_rerolls += 1
	# 原地换卡: 释放旧卡片, 重排新卡片; 选中框/▼ 留在原位由 _update_levelup_selection 重新驱动
	for card in _levelup_cards:
		if is_instance_valid(card):
			card.queue_free()
	_levelup_cards.clear()
	_levelup_options = new_opts
	_levelup_sel = 0
	for i in range(new_opts.size()):
		var opt: Dictionary = new_opts[i]
		var card := _option_card(opt)
		card.position = Vector2(LVL_CARD_X0 + float(i) * LVL_CARD_GAP, LVL_CARD_Y)
		card.pivot_offset = card.size / 2.0
		levelup_screen.add_child(card)
		_levelup_cards.append(card)
	GameManager.play_sfx("levelup")
	_update_levelup_selection()
	_update_reroll_btn()
	_lvlup_toast("已重抽 · 剩 %d 次" % (GameManager.LEVELUP_REROLL_MAX - GameManager.levelup_rerolls))


# 升级界面内的反馈 toast(复用波间商店那套: 单例 Label + 淡出上浮)
func _lvlup_toast(text: String) -> void:
	if levelup_screen == null or not is_instance_valid(levelup_screen):
		return
	if _levelup_toast == null or not is_instance_valid(_levelup_toast):
		_levelup_toast = Label.new()
		_levelup_toast.add_theme_font_size_override("font_size", 10)
		_levelup_toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.50))
		_levelup_toast.add_theme_color_override("font_outline_color", Color(0.20, 0.10, 0.02))
		_levelup_toast.add_theme_constant_override("outline_size", 2)
		_levelup_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		levelup_screen.add_child(_levelup_toast)
	if _levelup_toast_tween != null and _levelup_toast_tween.is_valid():
		_levelup_toast_tween.kill()
	_levelup_toast.text = text
	_levelup_toast.modulate = Color(1, 1, 1, 1)
	_levelup_toast.position = Vector2(0, LVL_CARD_Y - 36)
	_levelup_toast.anchor_left = 0.0; _levelup_toast.anchor_right = 1.0
	_levelup_toast.visible = true
	_levelup_toast_tween = create_tween()
	_levelup_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)   # 升级界面是暂停帧
	_levelup_toast_tween.tween_interval(0.8)
	_levelup_toast_tween.parallel().tween_property(_levelup_toast, "modulate:a", 0.0, 0.3)
	_levelup_toast_tween.parallel().tween_property(_levelup_toast, "position:y", LVL_CARD_Y - 46, 0.3)


# 当前选中项的稀有度(无选中或越界时回退 common)
func _sel_rarity() -> String:
	if _levelup_sel < 0 or _levelup_sel >= _levelup_options.size():
		return "common"
	return str(_levelup_options[_levelup_sel].get("rarity", "common"))


# 高亮选中卡片: 加亮加粗边框; 未选中卡片恢复基础边框
# 位移/晃动/选中框交给 _animate_levelup_selection(), 这里只管静态配色
func _update_levelup_selection() -> void:
	if _levelup_cards.is_empty():
		return
	for i in range(_levelup_cards.size()):
		var card: PanelContainer = _levelup_cards[i]
		var sb: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
		if sb == null:
			continue
		var rarity: String = str(card.get_meta("rarity", "common"))
		if i == _levelup_sel:
			# 选中: 同稀有度色提亮加粗(用更亮的选中色, 与选中框/▼ 统一)
			sb.border_color = _rarity_select(rarity)
			sb.set_border_width_all(_rarity_border_w(rarity) + 1)
			card.modulate = Color(1.12, 1.12, 1.12)
		else:
			sb.border_color = _rarity_border(rarity)
			sb.set_border_width_all(_rarity_border_w(rarity))
			card.modulate = Color(0.82, 0.82, 0.88)
	# ▼ 与选中框的变色交给 _animate_levelup_selection() 与滑动同步过渡
	_animate_levelup_selection()


# 选中框: 盖在卡片之上的稀有度描边, 切换时在卡片间滑动、变色并持续呼吸
# mouse_filter 必须 IGNORE —— 它在卡片上层, 否则挡住 gui_input 的点击选择
func _make_levelup_frame(rarity: String) -> Panel:
	var p := Panel.new()
	p.size = Vector2(LVL_CARD_W + LVL_FRAME_PAD * 2.0, LVL_CARD_H + LVL_FRAME_PAD * 2.0)
	p.pivot_offset = p.size / 2.0
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = Vector2(LVL_CARD_X0 - LVL_FRAME_PAD, LVL_CARD_Y - LVL_CARD_LIFT - LVL_FRAME_PAD)
	var sb := StyleBoxFlat.new()
	var c := _rarity_select(rarity)
	sb.bg_color = Color(c.r, c.g, c.b, LVL_FRAME_BG_ALPHA)
	sb.border_color = c
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	p.add_theme_stylebox_override("panel", sb)

	# 呼吸脉动: 透明度 + 轻微缩放同步循环; LEVEL_UP 期间树是暂停的, 必须 TWEEN_PAUSE_PROCESS
	# 顺序模式 + 第 2/4 步 .parallel(): 两拍各自「变暗并微缩」「变亮并回正」同时进行
	_frame_pulse_tw = create_tween()
	_frame_pulse_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_frame_pulse_tw.set_loops()
	var half := 0.62
	_frame_pulse_tw.tween_property(p, "modulate:a", LVL_FRAME_PULSE_LO, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_frame_pulse_tw.parallel().tween_property(p, "scale", Vector2(1.035, 1.035), half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_frame_pulse_tw.tween_property(p, "modulate:a", 1.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_frame_pulse_tw.parallel().tween_property(p, "scale", Vector2.ONE, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return p


# 选中切换动画: 选中框与 ▼ 滑到新卡并渐变到新卡的稀有度色, 新卡抬起 / 旧卡落回, 再对新卡来一次晃动
# 一条 parallel tween 统一驱动, 避免多条 tween 抢同一个属性
func _animate_levelup_selection() -> void:
	if _levelup_sel_tw != null and _levelup_sel_tw.is_valid():
		_levelup_sel_tw.kill()
	var sel_x := LVL_CARD_X0 + float(_levelup_sel) * LVL_CARD_GAP
	var slide := 0.16
	var c := _rarity_select(_sel_rarity())

	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_parallel(true)
	if _levelup_frame != null and is_instance_valid(_levelup_frame):
		tw.tween_property(_levelup_frame, "position",
			Vector2(sel_x - LVL_FRAME_PAD, LVL_CARD_Y - LVL_CARD_LIFT - LVL_FRAME_PAD), slide) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# 颜色补在 stylebox 资源上而非 frame.modulate —— 后者已被呼吸脉动 tween 占用, 两条会互相抢
		var fsb: StyleBoxFlat = _levelup_frame.get_theme_stylebox("panel") as StyleBoxFlat
		if fsb != null:
			tw.tween_property(fsb, "border_color", c, slide)
			tw.tween_property(fsb, "bg_color", Color(c.r, c.g, c.b, LVL_FRAME_BG_ALPHA), slide)
	if _levelup_marker != null and is_instance_valid(_levelup_marker):
		tw.tween_property(_levelup_marker, "position",
			Vector2(sel_x, LVL_CARD_Y - 15 - LVL_CARD_LIFT), slide) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# ▼ 是白字, 用 modulate 染色才能补间(font_color 主题覆盖不参与插值)
		tw.tween_property(_levelup_marker, "modulate", c, slide)
	for i in range(_levelup_cards.size()):
		var card: PanelContainer = _levelup_cards[i]
		if not is_instance_valid(card):
			continue
		var y: float = LVL_CARD_Y - LVL_CARD_LIFT if i == _levelup_sel else LVL_CARD_Y
		tw.tween_property(card, "position:y", y, slide).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_levelup_sel_tw = tw

	if _levelup_sel < _levelup_cards.size():
		_shake_card(_levelup_sel, LVL_SHAKE_DEG, LVL_SHAKE_SEC)


# 卡牌晃动: 阻尼余弦驱动 rotation + 轻微缩放, 起手幅度最大随后越晃越小
# 只碰 rotation/scale, 与 _animate_levelup_selection 的 position 不冲突
# 连续切回同一张卡时先杀旧 tween 再重置变换, 防止两条晃动叠加
func _shake_card(idx: int, amp_deg: float, dur: float) -> void:
	if idx < 0 or idx >= _levelup_cards.size():
		return
	var card: PanelContainer = _levelup_cards[idx]
	if not is_instance_valid(card):
		return
	# PanelContainer 会被子节点最小尺寸撑大, 晃之前按当时 size 重设 pivot 才真绕中心转
	card.pivot_offset = card.size / 2.0
	while _card_shake_tws.size() < _levelup_cards.size():
		_card_shake_tws.append(null)
	var old: Tween = _card_shake_tws[idx]
	if old != null and old.is_valid():
		old.kill()
	_reset_card_transform(card)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(_apply_card_shake.bind(card, amp_deg, dur), 1.0, 0.0, dur)
	tw.tween_callback(_reset_card_transform.bind(card))
	_card_shake_tws[idx] = tw


# p: 1 → 0 的线性衰减包络(tween_method 默认 TRANS_LINEAR, 故可反推已过时间)
func _apply_card_shake(p: float, card: Control, amp_deg: float, dur: float) -> void:
	if not is_instance_valid(card):
		return
	var t := (1.0 - p) * dur
	var wave := cos(t * 34.0)          # ~5.4Hz, 0.4s 内约 2.2 个来回
	card.rotation_degrees = amp_deg * p * wave
	var s := 1.0 + 0.05 * p * (0.5 + 0.5 * wave)
	card.scale = Vector2(s, s)


func _reset_card_transform(card: Control) -> void:
	if not is_instance_valid(card):
		return
	card.rotation_degrees = 0.0
	card.scale = Vector2.ONE


func _option_card(opt: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size = Vector2(100, 90)
	panel.custom_minimum_size = Vector2(100, 90)

	var rarity: String = str(opt.get("rarity", "common"))
	var is_evo: bool = opt["kind"] == "evolution"
	var is_over: bool = opt["kind"] == "overlimit"
	var rc := _rarity_border(rarity)
	var sb := StyleBoxFlat.new()
	# 底色: 深冷底朝稀有度色 lerp 22%, 保住色相(各通道等量相加会把金色洗成中性褐)
	sb.bg_color = Color(0.07, 0.06, 0.10, 0.95).lerp(Color(rc.r, rc.g, rc.b, 0.95), 0.22)
	sb.border_color = rc
	sb.set_border_width_all(_rarity_border_w(rarity))
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = opt["name"]
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", _rarity_text(rarity))
	vbox.add_child(name_lbl)

	# 类型 + 稀有度合并到同一行(卡面 100×90 已排满, 再加一行会挤掉 desc)
	# 超限卡(满配后的无限成长)不显示 Lv a → b(它不封顶), 改显示叠后的总层数
	var lvl_lbl := Label.new()
	if is_evo:
		lvl_lbl.text = "★ 进化 · %s" % _rarity_name(rarity)
	elif is_over:
		lvl_lbl.text = "∞ 超限 · 叠至 %d 层" % int(opt["next_level"])
	else:
		lvl_lbl.text = "Lv %d → %d · %s" % [opt["next_level"] - 1, opt["next_level"], _rarity_name(rarity)]
	lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_lbl.add_theme_font_size_override("font_size", 7)
	lvl_lbl.add_theme_color_override("font_color", _rarity_text(rarity) * Color(1, 1, 1, 0.85))
	vbox.add_child(lvl_lbl)

	# 特性标签: 新武器卡片显示「特性 · 眩晕」等, 颜色 = 状态实际染色(与角色选择/图鉴同一套)。
	# 替代旧套装 tag 行 —— 套装系统已删, 抽卡时最有用的信息就是"这把能挂什么状态"。
	if opt.has("trait"):
		# opt["id"] 就是武器 id(weapon 卡), trait_color/trait_name 均按武器 id 查表
		var trait_lbl := Label.new()
		trait_lbl.text = "特性 · %s" % GameManager.trait_name(str(opt["id"]))
		trait_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		trait_lbl.custom_minimum_size = Vector2(90, 13)
		trait_lbl.add_theme_font_size_override("font_size", 6)
		# 深色卡底用原 tint(不压墨 —— 压墨版 _cx_trait_ink 只服务图鉴纸底)
		trait_lbl.add_theme_color_override("font_color", GameManager.trait_color(str(opt["id"])))
		vbox.add_child(trait_lbl)

	var desc := Label.new()
	desc.text = opt["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 逐级文案最长 ~16 个中文字符, 7 号字在 90px 宽下约 2 行 => 高度留 26(带特性行)/30(不带)。
	# 原先 17 是按恒为"获得/升级武器"这 7 个字算的, 接上 WEAPON_LEVELS 后会被裁。
	desc.custom_minimum_size = Vector2(90, 26 if opt.has("trait") else 30)
	desc.add_theme_font_size_override("font_size", 7)
	# 武器**升级**卡(非新武器)的 desc 就是这一级的机制文案, 染该武器特性色让它跳出来 ——
	# 玩家在弹窗里一眼看到"这级买的是穿透/减速/减伤", 与图鉴、角色选择屏同一套状态配色。
	# 新武器卡已有独立的「特性 · X」色行, desc 保持中性不重复抢色。
	if opt["kind"] == "weapon" and not opt.has("trait") and GameManager.trait_of(str(opt["id"])) != "":
		desc.add_theme_color_override("font_color", GameManager.trait_color(str(opt["id"])))
	vbox.add_child(desc)

	panel.gui_input.connect(_on_option_pressed.bind(opt))
	panel.set_meta("rarity", rarity)   # 取消高亮时按稀有度恢复基础边框
	return panel


func _on_option_pressed(event: InputEvent, opt: Dictionary) -> void:
	# 状态 gate: 进化卡片确认后面板还要挂 ~1.3s(演出协程), 期间残卡仍在, 双击会重复 apply + 起第二个演出协程
	if GameManager.state != GameManager.State.LEVEL_UP:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		GameManager.play_sfx("select")
		GameManager.main.on_upgrade_chosen(opt)


# ================= 设置面板 =================

func show_settings() -> void:
	# 记录来源, 再切到 SETTINGS; 关闭时按来源恢复
	# 重入守卫: 从图鉴返回时 state 已是 SETTINGS, 此时不能再记(否则把真正的来源 PLAYING/MENU 覆盖掉)
	if GameManager.state != GameManager.State.SETTINGS:
		GameManager.settings_return_state = GameManager.state
	GameManager.state = GameManager.State.SETTINGS
	_clear_all()
	settings_screen = _full_screen()
	settings_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_screen.add_child(overlay)

	# 居中面板承载全部内容, 替代散落绝对坐标
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_screen.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.10, 0.92)
	sb.border_color = Color(0.45, 0.50, 0.60, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# 标题
	var title := _label("设 置", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(title)

	# --- 音量行: 标签列(52) + 滑条列(180) + 数值列(44) ---
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	vbox.add_child(vol_row)

	var vol_lbl := _label("音量", 12)
	vol_lbl.custom_minimum_size = Vector2(52, 0)
	vol_row.add_child(vol_lbl)

	# 数值 label 先声明(供下方 lambda 引用), 但 add_child 放到滑条之后保持「标签→滑条→数值」顺序
	var vol_val := _label("%d%%" % int(round(Settings.master_volume * 100.0)), 11)
	vol_val.custom_minimum_size = Vector2(44, 0)
	vol_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vol_val.add_theme_color_override("font_color", Color(0.45, 0.80, 0.95))

	var vol_slider := HSlider.new()
	vol_slider.custom_minimum_size = Vector2(180, 14)
	vol_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = Settings.master_volume
	_style_slider(vol_slider, Color(0.36, 0.70, 0.92))
	vol_slider.drag_ended.connect(func(_value_changed: bool):
		_preview_volume(int(round(vol_slider.value * 100.0))))
	vol_slider.value_changed.connect(func(v: float):
		Settings.master_volume = v
		Settings.apply_volume()
		vol_val.text = "%d%%" % int(round(v * 100.0))
		_preview_volume(int(round(v * 100.0))))
	vol_row.add_child(vol_slider)
	vol_row.add_child(vol_val)
	_settings_vol_slider = vol_slider
	_settings_row_labels.append(vol_lbl)

	# --- 难度行(简单/普通/困难; 普通=已调校平衡基线) ---
	# 三档离散值改用互斥按钮组, 比 step=1 的滑条更直白, 选中档高亮
	var DIFF_NAMES := ["简单", "普通", "困难"]
	var DIFF_ACCENTS := [Color(0.42, 0.74, 0.44), Color(0.90, 0.68, 0.30), Color(0.90, 0.45, 0.40)]

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	vbox.add_child(diff_row)

	var diff_lbl := _label("难度", 12)
	diff_lbl.custom_minimum_size = Vector2(52, 0)
	diff_row.add_child(diff_lbl)
	_settings_row_labels.append(diff_lbl)

	var diff_group := ButtonGroup.new()
	var DIFF_VALUES := [0, 1, 2]
	for i in range(3):
		var b := _make_pick_btn(DIFF_NAMES[i], DIFF_ACCENTS[i])
		b.toggle_mode = true
		b.button_group = diff_group
		b.button_pressed = (i == Settings.difficulty)
		b.custom_minimum_size = Vector2(0, 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
		b.pressed.connect(_on_diff_pick.bind(i))
		diff_row.add_child(b)
		_settings_diff_btns.append(b)

	# --- 游戏倍速行(0.5× / 1× / 2× / 3×; 只影响战斗节奏, 独立于暂停) ---
	var SPD_NAMES := ["0.5×", "1×", "2×", "3×"]
	var SPD_ACCENTS := [Color(0.55, 0.55, 0.62), Color(0.45, 0.72, 0.90), Color(0.90, 0.66, 0.30), Color(0.90, 0.45, 0.40)]

	var spd_row := HBoxContainer.new()
	spd_row.add_theme_constant_override("separation", 8)
	vbox.add_child(spd_row)

	var spd_lbl := _label("倍速", 12)
	spd_lbl.custom_minimum_size = Vector2(52, 0)
	spd_row.add_child(spd_lbl)
	_settings_row_labels.append(spd_lbl)

	var spd_group := ButtonGroup.new()
	for i in range(_settings_spd_values.size()):
		var b := _make_pick_btn(SPD_NAMES[i], SPD_ACCENTS[i])
		b.toggle_mode = true
		b.button_group = spd_group
		b.button_pressed = is_equal_approx(Settings.game_speed, _settings_spd_values[i])
		b.custom_minimum_size = Vector2(0, 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
		b.pressed.connect(_on_speed_pick.bind(_settings_spd_values[i]))
		spd_row.add_child(b)
		_settings_spd_btns.append(b)

	# --- 按键说明 ---
	var sep := HSeparator.new()
	vbox.add_child(sep)

	var key_title := _label("按键说明", 12)
	vbox.add_child(key_title)

	var keys := Label.new()
	keys.text = "移动          W A S D\n界面导航       W S 选择 · A D 切换\n设置菜单      ESC\n升级选择       鼠标 / A D + 空格\n图鉴翻页       A D 切分类 · W S 选条目\n重新开始       R（游戏 / 死亡界面）\n返回上一层     ESC（所有带返回按钮的界面）"
	keys.add_theme_font_size_override("font_size", 9)
	keys.add_theme_color_override("font_color", Color(0.82, 0.82, 0.86))
	vbox.add_child(keys)

	# --- 底部按钮区(居中) ---
	# 游戏内(PLAYING)打开: 显示「继续游戏」+「返回菜单」并列; 其它来源保持单「返回」
	var back_hbox := HBoxContainer.new()
	back_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	back_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(back_hbox)

	var is_playing := GameManager.settings_return_state == GameManager.State.PLAYING

	# 底部按钮行收集到 _settings_bottom_btns 供键盘横向导航; 默认焦点落在「继续游戏/返回」按钮
	_settings_bottom_btns.clear()

	# 游戏内入口: 图鉴(此时面板即事实上的暂停菜单; 主菜单另有独立图鉴按钮)
	if is_playing:
		var to_codex := _make_btn("图鉴", Color(0.72, 0.88, 0.70))
		to_codex.custom_minimum_size = Vector2(70, 28)
		to_codex.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
		to_codex.set_meta("base_accent", Color(0.72, 0.88, 0.70))
		to_codex.pressed.connect(_on_codex_open)
		back_hbox.add_child(to_codex)
		_settings_bottom_btns.append(to_codex)

	var back := _make_btn("继续游戏" if is_playing else "返回", Color(0.35, 0.75, 0.45) if is_playing else Color(0.45, 0.60, 0.85))
	back.custom_minimum_size = Vector2(100, 28)
	back.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
	back.set_meta("base_accent", Color(0.35, 0.75, 0.45) if is_playing else Color(0.45, 0.60, 0.85))
	back.pressed.connect(_on_settings_close)
	back_hbox.add_child(back)
	_settings_bottom_btns.append(back)

	# 保存并退出(仅游戏内): 写单槽续玩档后回主菜单, 下次进游戏主菜单出现「继续游戏」
	if is_playing:
		var to_save_exit := _make_btn("保存并退出", Color(0.45, 0.85, 0.55))
		to_save_exit.custom_minimum_size = Vector2(92, 28)
		to_save_exit.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
		to_save_exit.set_meta("base_accent", Color(0.45, 0.85, 0.55))
		to_save_exit.pressed.connect(_on_save_and_exit)
		back_hbox.add_child(to_save_exit)
		_settings_bottom_btns.append(to_save_exit)

	if is_playing:
		var to_menu := _make_btn("返回菜单", Color(0.75, 0.40, 0.40))
		to_menu.custom_minimum_size = Vector2(100, 28)
		to_menu.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
		to_menu.set_meta("base_accent", Color(0.75, 0.40, 0.40))
		to_menu.pressed.connect(_on_exit_menu)
		back_hbox.add_child(to_menu)
		_settings_bottom_btns.append(to_menu)

	# 行焦点初始化: 底部按钮行(3), 列指向「继续游戏/返回」(若游戏内则是中间按钮, 否则唯一按钮)
	_settings_row = 3
	_settings_col = 1 if is_playing else 0
	_refresh_settings_focus()


func _on_settings_close() -> void:
	GameManager.play_sfx("select")
	Settings.save_settings()
	var st := GameManager.settings_return_state
	if st == GameManager.State.PLAYING:
		get_tree().paused = false
		GameManager.state = GameManager.State.PLAYING
		show_hud()
	elif st == GameManager.State.MENU:
		GameManager.state = GameManager.State.MENU
		show_menu()
	elif st == GameManager.State.CHARACTER_SELECT:
		GameManager.state = GameManager.State.CHARACTER_SELECT
		show_character_select()
	else:
		# 兜底(如来源未知): 回主菜单
		GameManager.state = GameManager.State.MENU
		show_menu()


# ================= 设置面板键盘导航 =================
# 行: 0音量 / 1难度 / 2倍速 / 3底部按钮行; 列仅底部按钮行与音量(单列)有意义
func _refresh_settings_focus() -> void:
	# 三行标签: 活动行金色, 其余灰(音量/难度/倍速行无原生按钮焦点, 用标签亮色指示所在行)
	for i in range(_settings_row_labels.size()):
		var lbl: Label = _settings_row_labels[i]
		if lbl == null or not is_instance_valid(lbl):
			continue
		lbl.add_theme_color_override("font_color",
			Color(1.0, 0.88, 0.40) if i == _settings_row else Color(0.82, 0.82, 0.86))
	# 底部按钮行: 活动列金框提亮; 其余行靠标签已足够
	for i in range(_settings_bottom_btns.size()):
		var b: Button = _settings_bottom_btns[i]
		if b != null and is_instance_valid(b):
			_set_btn_highlight(b, _settings_row == 3 and i == _settings_col)


func _settings_move(step: int, quiet: bool = false) -> void:
	_settings_row = posmod(_settings_row + step, 4)   # 四层环绕(音量/难度/倍速/底部按钮)
	# 进入难度/倍速行时, 列初始化为当前档位(与 button_pressed 选中态一致)
	if _settings_row == 1:
		_settings_col = clampi(Settings.difficulty, 0, _settings_diff_btns.size() - 1)
	elif _settings_row == 2:
		var s := Settings.game_speed
		_settings_col = 0
		var best := INF
		for i in range(_settings_spd_values.size()):
			var spd: float = float(_settings_spd_values[i])
			var d := absf(spd - s)
			if d < best:
				best = d
				_settings_col = i
	elif _settings_row == 3:
		_settings_col = clampi(_settings_col, 0, _settings_bottom_btns.size() - 1)
	if not quiet:
		GameManager.play_sfx("pickup")
	_refresh_settings_focus()


func _settings_col_move(step: int) -> void:
	match _settings_row:
		0:
			# 音量行: A/D 调音量 ±0.05; 走 slider.value, 复用 value_changed 路径(apply + 数值 + 预览)
			if _settings_vol_slider != null:
				_settings_vol_slider.value = clampf(_settings_vol_slider.value + step * 0.05,
					_settings_vol_slider.min_value, _settings_vol_slider.max_value)
		1:
			if not _settings_diff_btns.is_empty():
				var idx: int = posmod(_settings_col + step, _settings_diff_btns.size())   # 三档环绕
				if idx != _settings_col:
					_settings_col = idx
					_on_diff_pick(idx)
					(_settings_diff_btns[idx] as Button).button_pressed = true
		2:
			if not _settings_spd_btns.is_empty():
				var idx: int = posmod(_settings_col + step, _settings_spd_btns.size())   # 四档环绕
				if idx != _settings_col:
					_settings_col = idx
					_on_speed_pick(float(_settings_spd_values[idx]))
					(_settings_spd_btns[idx] as Button).button_pressed = true
		3:
			if not _settings_bottom_btns.is_empty():
				_settings_col = posmod(_settings_col + step, _settings_bottom_btns.size())
	_refresh_settings_focus()


func _settings_confirm() -> void:
	if _settings_row == 3:
		if _settings_col >= 0 and _settings_col < _settings_bottom_btns.size():
			var b: Button = _settings_bottom_btns[_settings_col]
			if b != null and is_instance_valid(b):
				b.pressed.emit()


func _on_restart() -> void:
	GameManager.play_sfx("select")
	GameManager.main.restart()


func _on_exit_menu() -> void:
	GameManager.play_sfx("select")
	GameManager.main.exit_to_menu()


# 保存并退出: 写单槽续玩档(含当前设置) → 解暂停 → 回主菜单。
# test_mode 时 save_suspend/save_meta 自动不落盘(冒烟测试不污染真存档)。
func _on_save_and_exit() -> void:
	GameManager.play_sfx("select")
	GameManager.save_suspend()
	Settings.save_settings()
	GameManager.main.exit_to_menu()


# 死亡/通关结算共用: 二选一(重开=默认第 0 项 / 返回主菜单), W/S 环绕切换 + 确认
func _refresh_result_focus() -> void:
	for i in range(_result_btns.size()):
		var b: Button = _result_btns[i]
		if b != null and is_instance_valid(b):
			_set_btn_highlight(b, i == _result_sel)


func _result_move(step: int, quiet: bool = false) -> void:
	var n := _result_btns.size()
	if n == 0:
		return
	_result_sel = posmod(_result_sel + step, n)
	if not quiet:
		GameManager.play_sfx("pickup")
	_refresh_result_focus()


func _result_confirm() -> void:
	var n := _result_btns.size()
	if _result_sel < 0 or _result_sel >= n:
		return
	var b: Button = _result_btns[_result_sel]
	if b != null and is_instance_valid(b):
		b.pressed.emit()


# ================= 死亡结算 =================

func show_game_over(t: float, kills: int, boss: int, lv: int, char_name: String) -> void:
	_clear_all()
	gameover_screen = _full_screen()
	gameover_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	var overlay := ColorRect.new()
	overlay.color = Color(0.16, 0.02, 0.02, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	gameover_screen.add_child(overlay)

	var title := _label("你 被 击 败 了", 24)
	title.position = Vector2(0, 48)
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.22, 0.22))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.0, 0.0))
	title.add_theme_constant_override("outline_size", 3)
	gameover_screen.add_child(title)

	# 统计面板: 暗色底 + 两列对齐, 标签亮灰 / 数值分类着色
	# 不设固定 height —— PanelContainer 按内容自适应, 避免内容溢出与下方按钮重叠
	var panel := PanelContainer.new()
	panel.position = Vector2(W / 2 - 110, 98)
	panel.custom_minimum_size = Vector2(220, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.04, 0.85)
	sb.border_color = Color(0.55, 0.15, 0.15, 0.7)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	gameover_screen.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	col.add_child(_make_stat_row("存活时间", _fmt_time(t), Color(0.95, 0.85, 0.40), 11))   # 金
	col.add_child(_make_stat_row("击杀数", str(kills), Color(0.95, 0.45, 0.30), 11))        # 橙
	col.add_child(_make_stat_row("Boss 击杀", str(boss), Color(0.85, 0.55, 1.0), 11))       # 紫
	col.add_child(_make_stat_row("难度", _difficulty_name(), _difficulty_color(), 11))
	col.add_child(_make_stat_row("角色", char_name, Color(0.55, 0.90, 1.0), 11))            # 青
	col.add_child(_make_stat_row("最终等级", str(lv), Color(0.60, 1.0, 0.60), 11))          # 绿
	col.add_child(_make_stat_row("金币", "+%d" % int(GameManager.coins), Color(1.0, 0.85, 0.30), 11))  # 金
	col.add_child(_make_stat_row("累计金币", "%d" % int(GameManager.bank), Color(0.75, 0.72, 0.55), 11))

	# 按钮: 重新开始(绿) + 返回主菜单(橙), 分色区分
	# y=286: 统计面板 8 行自适应高约 180(底边 ~278), 按钮必须让到面板下方, 否则盖住「金币/累计金币」两行
	_result_btns.clear()
	_result_sel = 0
	var restart := _make_btn("重新开始", Color(0.35, 0.75, 0.45))
	restart.position = Vector2(W / 2 - 140, 286)
	restart.size = Vector2(130, 28)
	restart.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
	restart.pressed.connect(_on_restart)
	gameover_screen.add_child(restart)
	_result_btns.append(restart)

	var menu := _make_btn("返回主菜单", Color(0.85, 0.60, 0.25))
	menu.position = Vector2(W / 2 + 10, 286)
	menu.size = Vector2(130, 28)
	menu.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
	menu.pressed.connect(_on_exit_menu)
	gameover_screen.add_child(menu)
	_result_btns.append(menu)
	_refresh_result_focus()


# ================= 通关结算 =================

func show_victory(t: float, kills: int, boss: int, lv: int, char_name: String) -> void:
	_clear_all()
	victory_screen = _full_screen()
	victory_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	victory_screen.add_child(overlay)

	var title := _label("✦ 通 关 ✦", 24)
	title.position = Vector2(0, 56)
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	victory_screen.add_child(title)

	var sub := _label("终极深渊领主已被击败", 10)
	sub.position = Vector2(0, 92)
	sub.anchor_left = 0.0; sub.anchor_right = 1.0
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_screen.add_child(sub)

	# 统计面板: 与失败结算同款(暗底 + 两列对齐 + 分类着色), 旧版整块居中
	# 单 Label 导致列参差("Boss 击杀 4" 挤成一行、标签数值不对齐)
	# 不设固定 height —— PanelContainer 按内容自适应, 避免与下方按钮重叠
	var panel := PanelContainer.new()
	panel.position = Vector2(W / 2 - 110, 110)
	panel.custom_minimum_size = Vector2(220, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.02, 0.85)
	sb.border_color = Color(0.65, 0.50, 0.15, 0.7)   # 金边呼应通关主题(失败屏为红边)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	victory_screen.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	col.add_child(_make_stat_row("通关用时", _fmt_time(t), Color(0.95, 0.85, 0.40), 11))  # 金
	col.add_child(_make_stat_row("击杀数", str(kills), Color(0.95, 0.45, 0.30), 11))      # 橙
	col.add_child(_make_stat_row("Boss 击杀", str(boss), Color(0.85, 0.55, 1.0), 11))     # 紫
	col.add_child(_make_stat_row("角色", char_name, Color(0.55, 0.90, 1.0), 11))          # 青
	col.add_child(_make_stat_row("最终等级", str(lv), Color(0.60, 1.0, 0.60), 11))        # 绿
	col.add_child(_make_stat_row("金币", "+%d" % int(GameManager.coins), Color(1.0, 0.85, 0.30), 11))  # 金
	col.add_child(_make_stat_row("累计金币", "%d" % int(GameManager.bank), Color(0.75, 0.72, 0.55), 11))

	# 按钮左右并排(同失败屏): 统计面板 7 行自适应高约 156(底边 ~266),
	# 旧版竖排 y=236/270 会压住面板底部
	_result_btns.clear()
	_result_sel = 0
	var again := _make_btn("再来一局", Color(0.35, 0.75, 0.45))
	again.position = Vector2(W / 2 - 140, 274)
	again.size = Vector2(130, 28)
	again.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
	again.pressed.connect(_on_restart)
	victory_screen.add_child(again)
	_result_btns.append(again)

	var menu := _make_btn("返回主菜单", Color(0.85, 0.60, 0.25))
	menu.position = Vector2(W / 2 + 10, 274)
	menu.size = Vector2(130, 28)
	menu.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
	menu.pressed.connect(_on_exit_menu)
	victory_screen.add_child(menu)
	_result_btns.append(menu)
	_refresh_result_focus()

	var hint := Label.new()
	hint.text = "W/S 选择 · 空格/R 再来一局 · ESC 返回菜单"
	hint.position = Vector2(W / 2 - 110, 310)
	hint.size = Vector2(220, 12)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 7)
	victory_screen.add_child(hint)


# ================= 长按方向键连发 =================

# 记录/清除当前按住的导航键: 仅 WASD 四个字母键(与 _unhandled_input 各分支的导航键一致)
func _hold_update(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if ke.pressed and not ke.echo and _hold_dir(ke.keycode) != Vector2i.ZERO:
		_hold_keycode = ke.keycode
		_hold_state = GameManager.state
		_hold_elapsed = 0.0
		_hold_next = NAV_HOLD_DELAY
	elif not ke.pressed and ke.keycode == _hold_keycode:
		_hold_clear()


# 每帧驱动: 到点自动续步(与单击同一路径, 静音防连点爆音)
func _hold_process(delta: float) -> void:
	if _hold_keycode == KEY_NONE:
		return
	_hold_elapsed += delta
	while _hold_keycode != KEY_NONE and _hold_elapsed >= _hold_next:
		_hold_next += NAV_HOLD_INTERVAL
		_hold_step()


func _hold_clear() -> void:
	_hold_keycode = KEY_NONE
	_hold_state = -1
	_hold_elapsed = 0.0
	_hold_next = 0.0


# 按键 → 导航方向(x=A/D 左右, y=W/S 上下), 非导航键返回 ZERO
func _hold_dir(keycode: Key) -> Vector2i:
	match keycode:
		KEY_W:
			return Vector2i(0, -1)
		KEY_S:
			return Vector2i(0, 1)
		KEY_A:
			return Vector2i(-1, 0)
		KEY_D:
			return Vector2i(1, 0)
	return Vector2i.ZERO


# 按「按下那一刻的状态」分发一步导航, 与 _unhandled_input 的单击分支一一对应;
# 期间状态变了(如升级结算打断)立即作废连发
func _hold_step() -> void:
	if GameManager.state != _hold_state:
		_hold_clear()
		return
	var d := _hold_dir(_hold_keycode)
	if d == Vector2i.ZERO:
		return
	match GameManager.state:
		GameManager.State.MENU:
			if shop_screen != null:
				if d.y != 0:
					_meta_shop_move(d.y, true)
			elif d.y != 0:
				_menu_move(d.y, true)
		GameManager.State.CHARACTER_SELECT:
			if d.x != 0:
				_weapon_move(d.x, true)
			else:
				_char_move(0, d.y, true)
		GameManager.State.LEVEL_UP:
			if d.x != 0:
				_levelup_move(d.x, true)
		GameManager.State.SHOP:
			if d.x != 0:
				_wave_shop_move(d.x, true)
			elif d.y != 0:
				_wave_shop_row_move(d.y, true)
		GameManager.State.GAME_OVER, GameManager.State.VICTORY:
			_result_move(1, true)
		GameManager.State.CODEX:
			if d.x != 0:
				_codex_tab_move(d.x, true)
			else:
				_codex_sel_move(d.y)
		GameManager.State.SETTINGS:
			if d.y != 0:
				_settings_move(d.y, true)
			else:
				_settings_col_move(d.x)
		GameManager.State.PLAYING:
			pass


func _unhandled_input(event: InputEvent) -> void:
	# 先跟踪按住/释放, 再走各状态分支(分支各自 return, 不受影响)
	_hold_update(event)
	var st := GameManager.state

	# 主菜单层的强化商店: W/S 在商品行 + 「返回」间移动, 空格/Enter 触发; ESC 关闭回主菜单。
	# show_shop 不改 state(仍为 MENU), 故只能靠 shop_screen 是否存活来判定商店正显示。
	if st == GameManager.State.MENU and shop_screen != null:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_W:
					_meta_shop_move(-1); get_viewport().set_input_as_handled()
				KEY_S:
					_meta_shop_move(1); get_viewport().set_input_as_handled()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_meta_shop_confirm(); get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_on_shop_close(); get_viewport().set_input_as_handled()
		return

	# 重开确认框盖在主菜单上(state 仍为 MENU): 打开期间独占键盘, W/S(A/D 同效)切按钮,
	# 空格/Enter 触发选中项, ESC 等同「取消」。底层菜单导航全部被 gate 掉。
	if st == GameManager.State.MENU and _menu_confirm_screen != null and is_instance_valid(_menu_confirm_screen):
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_W, KEY_A:
					_menu_confirm_move(-1); get_viewport().set_input_as_handled()
				KEY_S, KEY_D:
					_menu_confirm_move(1); get_viewport().set_input_as_handled()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_menu_confirm_accept(); get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_on_menu_restart_cancel(); get_viewport().set_input_as_handled()
		return

	# 主菜单: W/S 在 5 按钮间移动, 空格/Enter 触发选中项
	if st == GameManager.State.MENU:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_W:
					_menu_move(-1); get_viewport().set_input_as_handled()
				KEY_S:
					_menu_move(1); get_viewport().set_input_as_handled()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_menu_confirm(); get_viewport().set_input_as_handled()
		return

	# 角色选择: W/S 选角色 / A/D 选武器 / 空格 Enter 开始
	# ESC 回主菜单(等同左上角「返回菜单」按钮)
	if st == GameManager.State.CHARACTER_SELECT:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_A:
					_weapon_move(-1); get_viewport().set_input_as_handled()
				KEY_D:
					_weapon_move(1); get_viewport().set_input_as_handled()
				KEY_W:
					_char_move(0, -1); get_viewport().set_input_as_handled()
				KEY_S:
					_char_move(0, 1); get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_on_char_back(); get_viewport().set_input_as_handled()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_char_confirm(); get_viewport().set_input_as_handled()
		return

	# 升级三选一: A/D 选择, 空格/Enter 确认
	# (A/D 不会误触发移动 —— 此时 state 为 LEVEL_UP, player._physics_process 直接 return)
	if st == GameManager.State.LEVEL_UP:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_A:
					_levelup_move(-1)
					get_viewport().set_input_as_handled()
				KEY_D:
					_levelup_move(1)
					get_viewport().set_input_as_handled()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_levelup_confirm()
					get_viewport().set_input_as_handled()
				KEY_R:
					_on_levelup_reroll()
					get_viewport().set_input_as_handled()
		return

	# 波间商店: A/D 在商品行内切换选中项, W/S 在商品行/继续战斗两层间移动, 空格/Enter 触发当前层
	# 空格长按走 echo 连续触发 = 按住连买; 字母键仍只在初次按下响应(去 echo 防长按连跳)
	if st == GameManager.State.SHOP:
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_A:
					if not event.echo: _wave_shop_move(-1)
					get_viewport().set_input_as_handled()
				KEY_D:
					if not event.echo: _wave_shop_move(1)
					get_viewport().set_input_as_handled()
				KEY_W:
					if not event.echo: _wave_shop_row_move(-1)
					get_viewport().set_input_as_handled()
				KEY_S:
					if not event.echo: _wave_shop_row_move(1)
					get_viewport().set_input_as_handled()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_wave_shop_confirm()
					get_viewport().set_input_as_handled()
		return

	if st == GameManager.State.PLAYING:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				# 游戏中按 R 直接重新开始(回角色选择界面)
				KEY_R:
					GameManager.main.restart()
					get_viewport().set_input_as_handled()
				# Tab 折叠/展开左上「本局加成」面板(战斗 HUD 无焦点控件, Tab 无竞争消费点)
				KEY_TAB:
					_toggle_buffs_panel()
					get_viewport().set_input_as_handled()
		return

	if st == GameManager.State.GAME_OVER or st == GameManager.State.VICTORY:
		# W/S(或任意字母键)在重开/返回主菜单间移动; 空格/Enter 确认; R 固定重开(快捷)
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_W, KEY_S, KEY_A, KEY_D:
					_result_move(1)
					get_viewport().set_input_as_handled()
				KEY_R:
					GameManager.main.restart()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_result_confirm()
					get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_on_exit_menu()
					get_viewport().set_input_as_handled()
			return
		# 触屏/手柄确认与取消仍走 action 路径(无键盘时)
		if event.is_action_pressed("ui_accept"):
			_result_confirm()
		elif event.is_action_pressed("ui_cancel"):
			_on_exit_menu()
		return

	# 图鉴: A/D 切分类, W/S 切条目, ESC 关闭回来源(空格同样关闭)
	# 字母键去 echo: 长按不连跳(翻页比商店连买更需要精确停位)
	if st == GameManager.State.CODEX:
		# 合书动画期间吞掉全部输入: ESC 连打不会二次触发关闭(重入 guard 之外再加一层)
		if _cx_closing:
			if event is InputEventKey and event.pressed:
				get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_A:
					if not event.echo:
						_codex_tab_move(-1)
						get_viewport().set_input_as_handled()
				KEY_D:
					if not event.echo:
						_codex_tab_move(1)
						get_viewport().set_input_as_handled()
				KEY_W:
					if not event.echo:
						_codex_sel_move(-1)
						get_viewport().set_input_as_handled()
				KEY_S:
					if not event.echo:
						_codex_sel_move(1)
						get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_on_codex_close()
					get_viewport().set_input_as_handled()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_on_codex_close()
					get_viewport().set_input_as_handled()
		return

	# 设置界面: A/D 切换列、W/S 切换行, 空格/Enter 触发底部按钮; ESC 关闭并回到来源
	if st == GameManager.State.SETTINGS:
		if event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_W:
					_settings_move(-1); get_viewport().set_input_as_handled()
				KEY_S:
					_settings_move(1); get_viewport().set_input_as_handled()
				KEY_A:
					_settings_col_move(-1); get_viewport().set_input_as_handled()
				KEY_D:
					_settings_col_move(1); get_viewport().set_input_as_handled()
				KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
					_settings_confirm(); get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_on_settings_close(); get_viewport().set_input_as_handled()


# ================= Boss 血条与预告 =================

# 波次预告: 屏幕上半部分居中显示「第 N 波」, 淡入淡出后消失
# 含 Boss 的波次字样变红预警(boss_kind: "" 无 / "boss" 中 Boss / "final" 终极 Boss)
# 波间事件: spawner._start_wave 先 roll_wave_curse 再调这里 → wave_curse 已就绪,
# 直接读 GameManager(单一数据源, 不改签名), 在主横幅下方补一行紫色副标播报
func announce_wave(n: int, total: int, boss_kind: String = "") -> void:
	var main_y := H * 0.30
	var dur := 2.0
	match boss_kind:
		"final":
			_announce_warn("第 %d 波 · 最终战" % n, Color(1, 0.22, 0.20), 24, dur, main_y)
		"boss":
			_announce_warn("第 %d 波 · BOSS" % n, Color(1, 0.22, 0.20), 24, dur, main_y)
		_:
			dur = 1.5
			_announce_warn("第 %d 波" % n, Color(0.95, 0.85, 0.4), 22, dur, main_y)
	var wc: Dictionary = GameManager.wave_curse
	if not wc.is_empty():
		_announce_warn("☠ %s · %s" % [str(wc.get("name", "")), str(wc.get("desc", ""))],
			Color(0.72, 0.55, 1.0), 13, dur, main_y + 34.0)


func announce_boss() -> void:
	_announce_warn("⚠ BOSS 来袭 ⚠", Color(1, 0.2, 0.2), 24, 2.0)


func announce_final_boss() -> void:
	_announce_warn("⚠ 终极 BOSS 降临 ⚠", Color(1, 0.45, 0.15), 22, 3.0)


# 大字预告: label_y 定显示高度(屏幕中心附近), duration 秒后自动消失
# 动画只做淡入淡出, 无位移; 用 tween 串 fade→hold→fade, 淡出后自清
func _announce_warn(text: String, color: Color, font_size: int, duration: float, label_y: float = H / 2.0 - 20.0) -> void:
	var warn := Label.new()
	warn.text = text
	warn.add_theme_font_size_override("font_size", font_size)
	warn.add_theme_color_override("font_color", color)
	warn.position = Vector2(0, label_y)
	warn.anchor_left = 0.0; warn.anchor_right = 1.0
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.modulate.a = 0.0
	warn.name = "BossWarn"
	add_child(warn)

	var fade := 0.25
	var hold := maxf(duration - fade * 2.0, 0.0)

	var fade_tw := create_tween()
	fade_tw.tween_property(warn, "modulate:a", 1.0, fade)
	fade_tw.tween_interval(hold)
	fade_tw.tween_property(warn, "modulate:a", 0.0, fade)
	fade_tw.tween_callback(warn.queue_free)


# 成就解锁 toast: 屏幕上方金色横幅(低于波次预告的 H*0.30, 不与 Boss 预警叠字), 淡入停留淡出。
# 图标 + 文字一条 HBox 水平居中; 图标取该成就专属字符画(2× 显示, Nearest 保持锐利)。
# PROCESS_MODE_ALWAYS + TWEEN_PAUSE_PROCESS: 解锁事件可能落在升级/商店暂停帧, 也要看得见。
func announce_achievement(ach_id: String, ach_name: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.position = Vector2(0, 92)
	box.anchor_left = 0.0; box.anchor_right = 1.0
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.modulate.a = 0.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.name = "AchToast"
	var icon := TextureRect.new()
	icon.texture = GameManager.achievement_icon_texture(ach_id)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(icon)
	var b := Label.new()
	b.text = "成就解锁 · %s" % ach_name
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	b.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.02))
	b.add_theme_constant_override("outline_size", 3)
	box.add_child(b)
	add_child(box)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(box, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.8)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)


# ================= 进化/新武器演出 =================
# 聚气横幅(暂停中仍推进): 屏幕上方大金字滑入停留淡出; PROCESS_MODE_ALWAYS 保证 paused 时 tween 照跑
func spawn_evo_banner(text: String, col: Color) -> void:
	var b := Label.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_outline_color", Color(0.10, 0.02, 0.04))
	b.add_theme_constant_override("outline_size", 3)
	b.position = Vector2(0, 62)
	b.anchor_left = 0.0; b.anchor_right = 1.0
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.modulate.a = 0.0
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(b)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)   # 暂停时也推进, 聚气阶段才看得到横幅
	tw.tween_property(b, "modulate:a", 1.0, 0.18)
	tw.tween_interval(0.56)
	tw.tween_property(b, "modulate:a", 0.0, 0.26)
	tw.tween_callback(b.queue_free)


# 全屏闪(进化金/新武器蓝/升级白): 加色亮斑一瞬, 播放后自清; PROCESS_MODE_ALWAYS 不受状态机影响
# strength 控制起始 alpha 与淡出时长(进化 0.35/0.42 华丽, 升级 0.18/0.30 轻量)
func flash_screen(col: Color, strength: float = 0.35, dur: float = 0.42) -> void:
	var f := ColorRect.new()
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.color = Color(col.r, col.g, col.b, strength)
	f.material = _additive_mat()
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(f)
	var tw := create_tween()
	tw.tween_property(f, "modulate:a", 0.0, dur)
	tw.tween_callback(f.queue_free)


func _build_boss_bar() -> void:
	boss_bar = Control.new()
	boss_bar.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(boss_bar)

	# 顶部正中 y11..25 是波次标签的固定位置, Boss 条整组下移避让,
	# 旧布局(名字 y10 居中)在 Boss 波(4/8/12)与「波次 X/12」叠字
	var name := Label.new()
	name.name = "Name"
	name.text = GameManager.BOSS_NAME
	# y28 起、高 14(字号 10 真实行高): Boss 条在 y40 高 10, 名字底边 42 与条顶留 2px 缝;
	# 顶部 y10..26 是波次标签(高 16)的固定位置, 不侵入
	name.position = Vector2(W / 2 - 60, 28)
	name.size = Vector2(120, 14)
	name.set_deferred("size", Vector2(120, 14))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_size_override("font_size", 10)
	boss_bar.add_child(name)

	# 复用全局条样式: 裸 ProgressBar 默认灰底, 满血时整条发灰看不出血量;
	# 填充染血红, 与玩家绿血条区分
	var bar := _make_bar(Vector2(W / 2 - 100, 44), Vector2(200, 10), 1.0)
	bar.name = "Bar"
	(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.85, 0.22, 0.26)
	boss_bar.add_child(bar)


func _process_boss_bar() -> void:
	if boss_bar == null:
		return
	# 找到 Boss
	var b: Node2D = null
	for e in GameManager.enemies:
		if e != null and is_instance_valid(e) and e.get_script() != null and \
			e.get_script().resource_path.ends_with("boss.gd"):
			b = e
			break
	if b == null or not is_instance_valid(b):
		boss_bar.visible = false
		return
	boss_bar.visible = true
	var name_lbl: Label = boss_bar.get_node("Name")
	name_lbl.text = GameManager.BOSS_FINAL_NAME if b.is_final else GameManager.BOSS_NAME
	var bar: ProgressBar = boss_bar.get_node("Bar")
	bar.max_value = b.max_hp
	bar.value = b.hp


# ================= 工具 =================

func _full_screen() -> Control:
	var c := Control.new()
	c.anchor_left = 0.0; c.anchor_top = 0.0
	c.anchor_right = 1.0; c.anchor_bottom = 1.0
	c.offset_right = 0; c.offset_bottom = 0
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	return c


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


# 统一样式的按钮: 圆角暗底 + 描边 + 悬停/按下态, 全项目按钮复用
func _make_btn(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 10)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.10, 0.14, 0.92)
	normal.border_color = accent
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0

	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.16, 0.22, 0.95)
	hover.set_border_width_all(2)

	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.07, 0.07, 0.10, 1.0)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)

	b.add_theme_color_override("font_color", Color(0.92, 0.92, 0.94))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.88))
	return b


# 肉鸽终端风按钮: 直角硬框 + 终端光标前缀 ">", hover 时前缀点亮 + accent 描边收亮。
# 仅主菜单复用; 通用按钮(_make_btn)保持圆角暗底不变, 避免波及其他界面。
func _make_rogue_btn(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = "> " + text
	b.add_theme_font_size_override("font_size", 10)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.07, 0.07, 0.94)
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)   # 肉鸽/像素风: 近直角的小圆角, 硬朗不圆滑
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0

	var hover := normal.duplicate()
	hover.bg_color = Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, 0.95)
	hover.border_color = accent
	hover.set_border_width_all(2)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(accent.r * 0.30, accent.g * 0.30, accent.b * 0.30, 0.96)
	pressed.border_color = Color(accent.r, accent.g, accent.b, 0.80)
	pressed.set_border_width_all(1)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)

	b.add_theme_color_override("font_color", Color(accent.r * 0.85, accent.g * 0.85, accent.b * 0.85))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.85, 0.85, 0.85))
	return b


# 难度三选一按钮: 未选中暗底+彩色描边, 选中(toggle pressed)高亮填充+白字
func _make_pick_btn(text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 10)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.10, 0.14, 0.92)
	normal.border_color = accent
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_top = 4.0
	normal.content_margin_bottom = 4.0

	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.16, 0.22, 0.95)
	hover.set_border_width_all(2)

	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(accent.r, accent.g, accent.b, 0.30)
	sel.border_color = accent
	sel.set_border_width_all(2)
	sel.set_corner_radius_all(6)
	sel.content_margin_top = 4.0
	sel.content_margin_bottom = 4.0

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("focus", normal)

	b.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))
	return b


# 难度档被选中: 更新全局设置; 按钮互斥由 ButtonGroup 自动管理
func _on_diff_pick(i: int) -> void:
	Settings.difficulty = i


# 倍速档被选中: 写入全局设置并立即生效(Engine.time_scale)
func _on_speed_pick(s: float) -> void:
	Settings.game_speed = s
	Settings.apply_game_speed()


# 音量预览: 以当前音量播一声 "select", 用于辨别大小; 节流, 拖动过程只响少量次
func _preview_volume(_pct: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _vol_feedback_last < 120:
		return
	_vol_feedback_last = now
	GameManager.play_sfx("select")


# 生成带描边的圆形抓手纹理: 内芯 inner 色, 外环 ring 色(1px)
func _grabber_tex(radius: int, inner: Color, ring: Color) -> Texture2D:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in range(size):
		for x in range(size):
			var dx := float(x - radius)
			var dy := float(y - radius)
			var d := sqrt(dx * dx + dy * dy)
			if d <= float(radius):
				img.set_pixel(x, y, inner if d <= float(radius - 1) else ring)
	return ImageTexture.create_from_image(img)


# 设置滑条统一样式: 深色细轨 + 描边 + 彩色填充进度 + 带描边圆形抓手, hover 放大
# 注意: Slider 无 fill 属性, "已填充"部分 = grabber_area(非悬停)/grabber_area_highlight(悬停)
func _style_slider(slider: HSlider, accent: Color) -> void:
	# 轨道: 深色底 + 1px 中灰描边, 圆角。在暗色面板上勾勒出清晰的条状范围
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(0.12, 0.12, 0.18, 0.95)
	rail.border_color = Color(0.38, 0.42, 0.50, 0.9)
	rail.set_border_width_all(1)
	rail.set_corner_radius_all(4)

	# 已填充部分: accent 色, 圆角与轨道对齐
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = accent
	fill_sb.set_corner_radius_all(4)

	var dot := _grabber_tex(6, Color(0.98, 0.98, 1.0), Color(0.12, 0.12, 0.18))
	var dot_hl := _grabber_tex(7, Color(1.0, 1.0, 1.0), accent)

	slider.add_theme_stylebox_override("slider", rail)
	slider.add_theme_stylebox_override("grabber_area", fill_sb)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_sb)
	slider.add_theme_icon_override("grabber", dot)
	slider.add_theme_icon_override("grabber_highlight", dot_hl)
	slider.add_theme_icon_override("grabber_disabled", dot)


# ================= 强化商店(局外永久成长) =================
# 主菜单入口, 用局外金币(bank)购买永久强化; 购买即保存, 立即反映到下一局

var _shop_bank_label: Label = null
var _shop_rows: Array = []   # 每项 {id, level_label, buy_btn}


func show_shop() -> void:
	_clear_all()
	shop_screen = _full_screen()
	shop_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_screen.add_child(overlay)

	var title := _label("强 化 商 店", 22)
	title.position = Vector2(0, 14)
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	shop_screen.add_child(title)

	# 累计金币: 居中胶囊徽章(固定尺寸, 文字内嵌居中, 不会溢出到屏外)
	var bank_panel := PanelContainer.new()
	bank_panel.position = Vector2(W / 2.0 - 60.0, 44.0)
	bank_panel.size = Vector2(120.0, 24.0)
	var bp := StyleBoxFlat.new()
	bp.bg_color = Color(0.13, 0.11, 0.04, 0.90)
	bp.border_color = Color(0.95, 0.75, 0.25, 0.65)
	bp.set_border_width_all(1)
	bp.set_corner_radius_all(12)
	bank_panel.add_theme_stylebox_override("panel", bp)
	_shop_bank_label = _label("", 12)
	_shop_bank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_bank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_bank_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	bank_panel.add_child(_shop_bank_label)
	shop_screen.add_child(bank_panel)

	# 列表面板: 固定高度, VBox 装「滚动商品区 + 底部介绍文字」, 内部滚动不压介绍
	var panel := PanelContainer.new()
	panel.position = Vector2(W / 2 - 160, 80)
	panel.size = Vector2(320, 226)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.10, 0.92)
	sb.border_color = Color(0.45, 0.50, 0.60, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	shop_screen.add_child(panel)

	var pvbox := VBoxContainer.new()
	pvbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pvbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(pvbox)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pvbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	_shop_rows.clear()
	for id in GameManager.META_UPGRADES:
		vbox.add_child(_shop_row(id))

	# 介绍文字: 面板底部固定(不随商品滚动), 说明强化的永久性与金币来源
	var info := _label("永久强化 · 跨局继承 · 击杀掉落金币累积", 8)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", Color(0.66, 0.66, 0.72))
	pvbox.add_child(info)
	_meta_shop_info = info

	# 返回按钮: 面板下方居中(y=320, 面板底 306, 留 14px); 存引用供键盘导航的「最后一格」锚定
	_meta_shop_back = _make_btn("返回", Color(0.45, 0.60, 0.85))
	_meta_shop_back.position = Vector2(W / 2 - 60, 320)
	_meta_shop_back.size = Vector2(120, 28)
	_meta_shop_back.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
	_meta_shop_back.pressed.connect(_on_shop_close)
	shop_screen.add_child(_meta_shop_back)

	_meta_shop_sel = 0
	_refresh_shop()
	_refresh_meta_shop_focus()


# 单行: 名称+描述(左列) | 等级 x/y(中) | 购买按钮(右)
func _shop_row(id: String) -> Control:
	var def: Dictionary = GameManager.META_UPGRADES[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var name := Label.new()
	name.text = def["name"]
	name.add_theme_font_size_override("font_size", 11)
	name.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	info.add_child(name)

	var desc := Label.new()
	desc.text = def["desc"]
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	info.add_child(desc)

	var lvl := Label.new()
	lvl.text = "0/5"
	lvl.add_theme_font_size_override("font_size", 10)
	lvl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	lvl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lvl)

	var btn := _make_btn("购买", Color(0.95, 0.75, 0.25))
	btn.custom_minimum_size = Vector2(64, 24)
	btn.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
	btn.set_meta("base_accent", Color(0.95, 0.75, 0.25))
	btn.pressed.connect(_on_shop_buy.bind(id))
	row.add_child(btn)

	_shop_rows.append({"id": id, "level": lvl, "btn": btn})
	return row


func _refresh_shop() -> void:
	_shop_bank_label.text = "累计金币  %d" % int(GameManager.bank)
	var bank: int = int(GameManager.bank)
	for r in _shop_rows:
		var id: String = r["id"]
		var lvl_label: Label = r["level"]
		var btn: Button = r["btn"]
		var def: Dictionary = GameManager.META_UPGRADES[id]
		var lv := GameManager.meta_level(id)
		var maxlv: int = int(def["max"])
		lvl_label.text = "%d/%d" % [lv, maxlv]
		if lv >= maxlv:
			btn.text = "已满级"
			btn.disabled = true
			_set_price_color(btn, Color(0.62, 0.62, 0.66), Color(0.70, 0.70, 0.74))
		else:
			var cost: int = GameManager.meta_cost(id)
			btn.text = "%d G" % cost
			btn.disabled = false
			# 价格两态与波间商店同法: 买得起金 / 买不起红(按钮仍可点, 点了弹「还差 N」toast)
			if bank >= cost:
				_set_price_color(btn, Color(1.0, 0.82, 0.30), Color(1.0, 0.90, 0.50))
			else:
				_set_price_color(btn, Color(0.90, 0.32, 0.30), Color(1.0, 0.45, 0.42))


# 价格字色: _make_btn 只设了 font_color/font_hover_color, 两态都要覆盖才不残留上一次的颜色
func _set_price_color(btn: Button, normal: Color, hover: Color) -> void:
	btn.add_theme_color_override("font_color", normal)
	btn.add_theme_color_override("font_hover_color", hover)
	btn.add_theme_color_override("font_pressed_color", normal)
	btn.add_theme_color_override("font_disabled_color", normal)


func _on_shop_buy(id: String) -> void:
	if GameManager.buy_meta(id):
		GameManager.play_sfx("levelup")
		_refresh_shop()
		return
	GameManager.play_sfx("hurt")   # 余额不足/已满级提示音
	# 满级行按钮已 disabled, 走不到这里; 剩下的失败一律是余额不足 → 报差额(与波间商店文案一致)
	var cost: int = GameManager.meta_cost(id)
	if cost >= 0:
		var short: int = cost - int(GameManager.bank)
		# y=284: 压在列表面板底部那行静态说明文字上(panel 内区 92..294), 0.9s 淡出;
		# 面板底 306 与返回按钮顶 320 之间只有 14px, 放不下 11 号字, 故取面板内底位
		_shop_toast_show(shop_screen, "金币不足 · 还差 %d" % short, 284.0)


func _on_shop_close() -> void:
	GameManager.play_sfx("select")
	GameManager.main.show_menu()


func _refresh_meta_shop_focus() -> void:
	for i in range(_shop_rows.size()):
		var btn: Button = _shop_rows[i]["btn"]
		_set_btn_highlight(btn, i == _meta_shop_sel)
	if _meta_shop_back != null:
		_set_btn_highlight(_meta_shop_back, _meta_shop_sel == _shop_rows.size())


func _meta_shop_move(step: int, quiet: bool = false) -> void:
	var n := _shop_rows.size() + 1   # 商品行 + 返回按钮
	if n <= 1:
		return
	_meta_shop_sel = posmod(_meta_shop_sel + step, n)   # 环绕: 长按可一圈圈扫
	if not quiet:
		GameManager.play_sfx("pickup")
	_refresh_meta_shop_focus()


func _meta_shop_confirm() -> void:
	if _meta_shop_sel < _shop_rows.size():
		var id: String = _shop_rows[_meta_shop_sel]["id"]
		_on_shop_buy(id)
	else:
		_on_shop_close()


# ================= 图鉴(教学手册) =================
# 全部条目直接可见, 不做解锁/收集, 无持久化 —— 目的是让玩家开局前就能读懂系统
# 四类 tab: 角色 / 武器 / Boss / 杂兵词缀; 数值一律实时读 GameManager 数据表, 不另存快照


# 书签丝带: 垂在书脊顶端、盖住右页上角; 切 tab 时换色 + bob 抬升(带子缩短)
# 内部类不引用外层常量(通过字段注入), 与 ShopCardGlow 的 get_meta("hud") 同思路但更直接
class CodexRibbon extends Control:
	var tab_idx: int = 0
	var bob: float = 0.0
	var color: Color = Color(0.557, 0.173, 0.173)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var band_h: float = 62.0 + 6.0 * sin(bob * PI)
		# 燕尾书签(底端 V 形缺口): 直接画五边形, 不做"剪洞"
		var pts := PackedVector2Array([
			Vector2(8.0, 0.0), Vector2(16.0, 0.0),
			Vector2(16.0, band_h), Vector2(12.0, band_h + 7.0), Vector2(8.0, band_h)])
		draw_colored_polygon(pts, color)
		# 带面 1px 高光竖线
		draw_rect(Rect2(9.0, 1.0, 1.0, band_h), Color(1.0, 1.0, 1.0, 0.22))


# 翻页 overlay: 盖住整本书, 只画"扫过的素纸 + 移动明暗边界带", 不动内容节点
# 无自身 _process: 重绘全靠 hud 的 tween 步进 queue_redraw; 静止 visible=false 零开销
class CodexPageFlip extends Control:
	var progress: float = 0.0   # 0..pages, hud tween_method 驱动
	var dir: int = 1            # +1 向后翻 / -1 向前翻
	var pages: int = 1
	var paper_tex: Texture2D = null
	var page_rect := Rect2()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		if progress <= 0.0 or page_rect.size.x <= 1.0:
			return
		var RP := page_rect
		var frac: float = fposmod(progress, 1.0)
		if dir < 0:
			frac = 1.0 - frac   # 反向: 素纸从另一侧铺开
		# boundary: 素纸展开的边界。Phase A(<0.5) 从右缘向左铺满; Phase B 从右缘向左收缩露出新内容
		var boundary: float
		if frac < 0.5:
			boundary = RP.end.x - 2.0 * frac * RP.size.x
		else:
			boundary = RP.position.x + (2.0 * frac - 1.0) * RP.size.x
		var w := RP.end.x - boundary
		if w < 0.5:
			return
		# 素纸区(纸背比正面暗)。关键: 用 region 裁切不能压缩, 否则纸纹被挤成条纹
		if paper_tex != null:
			draw_texture_rect_region(paper_tex,
				Rect2(boundary, RP.position.y, w, RP.size.y),
				Rect2(boundary - RP.position.x, 0.0, w, RP.size.y),
				Color(0.84, 0.82, 0.76))
		else:
			draw_rect(Rect2(boundary, RP.position.y, w, RP.size.y), Color(0.80, 0.76, 0.64))
		# 移动边界带(像素阶梯, 不用 AA): 素纸侧 2px 亮边 + 内容侧 3 条阶梯软影
		draw_rect(Rect2(boundary - 2.0, RP.position.y, 2.0, RP.size.y), Color(1.0, 0.97, 0.88, 0.9))
		var sh: Array = [0.28, 0.16, 0.08]
		for i in range(3):
			draw_rect(Rect2(boundary + 3.0 * float(i), RP.position.y + 1.0, 3.0, RP.size.y - 2.0),
				Color(0.05, 0.03, 0.02, float(sh[i])))
		# Phase B 附加: 书脊侧投影随进度渐弱
		if frac >= 0.5:
			var t2: float = (frac - 0.5) * 2.0
			draw_rect(Rect2(RP.position.x - 6.0, RP.position.y, 6.0, RP.size.y),
				Color(0.05, 0.03, 0.02, 0.18 * (1.0 - t2)))

func show_codex() -> void:
	# 记录来源再切 CODEX(同 show_settings 的做法): 关闭时据此恢复, 游戏内进来仍保持暂停
	GameManager.codex_return_state = GameManager.state
	GameManager.state = GameManager.State.CODEX
	_clear_all()
	codex_screen = _full_screen()
	# PROCESS_MODE_ALWAYS: 从暂停菜单进来时 get_tree().paused 仍为 true, 不设就收不到输入
	codex_screen.process_mode = Node.PROCESS_MODE_ALWAYS

	# 暖棕木桌底: 烘焙图缺失时退化成深棕平色(界面不炸, 只是没有木纹与烛光)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.06, 0.04, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	codex_screen.add_child(bg)

	var desk_tex: Texture2D = _cx_baked_tex("res://assets/ui/codex_desk.png")
	if desk_tex != null:
		var desk := TextureRect.new()
		desk.texture = desk_tex
		desk.stretch_mode = TextureRect.STRETCH_SCALE
		desk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		desk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		desk.set_anchors_preset(Control.PRESET_FULL_RECT)
		codex_screen.add_child(desk)

	var title := _label("游 戏 图 鉴", 18)
	title.position = Vector2(0, CX_TITLE_Y)
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	codex_screen.add_child(title)

	# 顶部返回(左上角, 与标题居中不冲突)
	var back := _make_btn("返回", Color(0.45, 0.60, 0.85))
	back.position = Vector2(16.0, 10.0)
	back.size = Vector2(84, 24)
	back.focus_mode = Control.FOCUS_NONE   # 键盘走 _unhandled_input, 防焦点驻留导致空格双触发
	back.pressed.connect(_on_codex_close)
	codex_screen.add_child(back)

	# 分类 tab 行: 居中排布, ButtonGroup 保证互斥(选中态由 toggle pressed 呈现)
	_cx_tab_btns.clear()
	var tab_group := ButtonGroup.new()
	var tabs_w := float(CX_TAB_NAMES.size()) * CX_TAB_W + float(CX_TAB_NAMES.size() - 1) * CX_TAB_GAP
	var tab_x := (W - tabs_w) / 2.0
	for i in range(CX_TAB_NAMES.size()):
		var tb := _make_pick_btn(CX_TAB_NAMES[i], Color(0.72, 0.88, 0.70))
		tb.toggle_mode = true
		tb.button_group = tab_group
		tb.button_pressed = (i == _cx_tab)
		tb.position = Vector2(tab_x + float(i) * (CX_TAB_W + CX_TAB_GAP), CX_TAB_Y)
		tb.size = Vector2(CX_TAB_W, CX_TAB_H)
		tb.focus_mode = Control.FOCUS_NONE
		tb.pressed.connect(_on_codex_tab.bind(i))
		codex_screen.add_child(tb)
		_cx_tab_btns.append(tb)
	# tab 皮革棕底 + 金棕字(逐个覆盖, 不动 _make_pick_btn 本体 —— 它还被难度/速度选择用)
	_cx_tab_styles()

	# 左侧索引卡片抽屉: scroll 之下垫一层木色背板
	var drawer := PanelContainer.new()
	drawer.position = Vector2(CX_LIST_BACK_X, CX_BODY_Y - 4.0)
	drawer.size = Vector2(CX_LIST_BACK_W, CX_BODY_H + 8.0)
	drawer.add_theme_stylebox_override("panel", _cx_drawer_style())
	codex_screen.add_child(drawer)

	# 左侧条目列表(切 tab 时重建内容, 容器与滚动条保留)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(CX_LIST_X, CX_BODY_Y)
	scroll.size = Vector2(CX_LIST_W, CX_BODY_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	codex_screen.add_child(scroll)
	_cx_scroll = scroll

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	_cx_list_box = list

	# 右侧详情 = 一本摊开的双页书。_cx_book 是整本书容器(开/合动画只 tween 它),
	# 子节点顺序即 z 序: 封面底 → 左页 → 右页 → 书脊 → 书签丝带 → 翻页 overlay(最后, 盖住两页)
	_cx_book = Control.new()
	_cx_book.position = Vector2(CX_BOOK_X, CX_BOOK_Y)
	_cx_book.size = Vector2(CX_BOOK_W, CX_BOOK_H)
	_cx_book.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 空白处不挡, 交互全在页内的 RTL/滚动条
	codex_screen.add_child(_cx_book)

	var cover := PanelContainer.new()
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_theme_stylebox_override("panel", _cx_cover_style())
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cx_book.add_child(cover)

	var page_tex: Texture2D = _cx_baked_tex("res://assets/ui/codex_page.png")

	# 左页: 立绘 + 名称 + 定位 + 分隔线 + 数值表
	# _cx_build_page 已把页节点挂进 _cx_book 并返回其内部的内容宿主, 不能再 add_child 一次(会脱离页)
	var lhost := _cx_build_page(Rect2(CX_PAGE_L_X, CX_PAGE_Y, CX_PAGE_W, CX_PAGE_H), true, page_tex)

	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 4)
	lhost.add_child(lbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	lbox.add_child(head)

	_cx_portrait = TextureRect.new()
	_cx_portrait.custom_minimum_size = Vector2(CX_PORTRAIT, CX_PORTRAIT)
	_cx_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cx_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cx_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cx_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_cx_portrait)

	var htext := VBoxContainer.new()
	htext.add_theme_constant_override("separation", 2)
	htext.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	htext.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(htext)

	_cx_name = Label.new()
	_cx_name.add_theme_font_size_override("font_size", 16)
	_cx_name.add_theme_color_override("font_color", CX_INK_NAME)
	_cx_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	htext.add_child(_cx_name)

	_cx_tag = Label.new()
	_cx_tag.add_theme_font_size_override("font_size", 9)
	_cx_tag.add_theme_color_override("font_color", CX_INK_TAG)
	_cx_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	htext.add_child(_cx_tag)

	lbox.add_child(_cx_page_rule())

	# 数值列: 定宽, 内容短不滚动
	_cx_stats = RichTextLabel.new()
	_cx_stats.bbcode_enabled = true
	_cx_stats.fit_content = true
	_cx_stats.scroll_active = false
	_cx_stats.add_theme_font_size_override("normal_font_size", 8)
	_cx_stats.add_theme_constant_override("line_separation", 3)
	# 未包 [color=] 的裸文本(如角色页「被动 …」的值)默认是白字, 纸底上不可读 ——
	# 默认色压到墨棕, 与 _cx_inkify 的正文色一致
	_cx_stats.add_theme_color_override("default_color", Color(CX_INK_BODY))
	_cx_stats.custom_minimum_size = Vector2(CX_STATS_W, 0)
	_cx_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbox.add_child(_cx_stats)

	# 右页: 背景文案。fit_content 关掉 + 允许滚动, 长文案溢出时可滚而非被裁
	var rhost := _cx_build_page(Rect2(CX_PAGE_R_X, CX_PAGE_Y, CX_PAGE_W, CX_PAGE_H), false, page_tex)

	_cx_prose = RichTextLabel.new()
	_cx_prose.bbcode_enabled = true
	_cx_prose.fit_content = false
	_cx_prose.scroll_active = true
	_cx_prose.add_theme_font_size_override("normal_font_size", 8)
	_cx_prose.add_theme_constant_override("line_separation", 3)
	_cx_prose.add_theme_color_override("default_color", Color(CX_INK_BODY))
	_cx_prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cx_prose.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rhost.add_child(_cx_prose)

	_cx_book.add_child(_cx_build_spine(page_tex))

	# 书签丝带: 垂在书脊顶端盖住右页上角, 切分类换色
	_cx_ribbon = CodexRibbon.new()
	_cx_ribbon.position = Vector2(CX_SPINE_LX - 6.0, -4.0)
	_cx_ribbon.size = Vector2(22, 84)
	_cx_ribbon.tab_idx = _cx_tab
	_cx_ribbon.color = CX_RIBBON_COLORS[_cx_tab]
	_cx_book.add_child(_cx_ribbon)

	# 翻页 overlay: 必须是最后一个子节点才能盖住两页内容
	_cx_page_flip = CodexPageFlip.new()
	_cx_page_flip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cx_page_flip.paper_tex = page_tex
	_cx_page_flip.page_rect = Rect2(CX_PAGE_R_X, CX_PAGE_Y, CX_PAGE_W, CX_PAGE_H)
	_cx_book.add_child(_cx_page_flip)

	# 文案溢出提示: 滚动条太细几乎不可见, 靠这行字告诉玩家能滚(可见性由 _process 每帧算)
	# 落在右页顶部预留的 CX_PAGE_TOP_R 条内, 不压住文案首行
	_cx_scroll_hint = _label("▼ 长文可滚轮查看", 7)
	_cx_scroll_hint.anchor_left = 0.0; _cx_scroll_hint.anchor_right = 1.0
	_cx_scroll_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cx_scroll_hint.offset_left = CX_PAGE_MARGIN
	_cx_scroll_hint.offset_right = -CX_PAGE_MARGIN
	_cx_scroll_hint.offset_top = 1.0
	_cx_scroll_hint.offset_bottom = 11.0
	_cx_scroll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cx_scroll_hint.add_theme_color_override("font_color", Color(0.42, 0.35, 0.24, 0.85))
	_cx_scroll_hint.visible = false
	_cx_right_page.add_child(_cx_scroll_hint)

	var hint := _label("A D 切分类 · W S 翻页 · 滚轮滚动文案 · ESC 合上书本 · 鼠标点击亦可", 8)
	hint.position = Vector2(0, CX_HINT_Y)
	hint.anchor_left = 0.0; hint.anchor_right = 1.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.86, 0.78, 0.62, 0.9))
	codex_screen.add_child(hint)

	_cx_rebuild_list()
	_cx_refresh_tabs()
	_cx_refresh_detail()
	_cx_ribbon_refresh(true)
	if _cx_anim_enabled:
		_cx_book_open_anim()


# 烘焙 UI 图: 存在就返回纹理, 不存在返回 null(调用方退化平色, 绝不报错)
func _cx_baked_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res: Resource = load(path)
	return res as Texture2D


# 书封面: 皮革棕 + 亮棕内边, 圆角 3(像素风小圆角, 不做抗锯齿大圆角)
func _cx_cover_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CX_LEATHER
	sb.border_color = CX_LEATHER_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	return sb


# 左侧索引卡片抽屉背板: 木色 + 1px 棕边(目录抽屉感)
func _cx_drawer_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.165, 0.114, 0.071, 0.96)
	sb.border_color = CX_LEATHER_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


# 页内分隔线: 1px 棕线(HSeparator 默认线太浅, 纸底上看不见)
func _cx_page_rule() -> HSeparator:
	var sep := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.541, 0.455, 0.306)
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	sep.add_theme_stylebox_override("separator", sb)
	sep.add_theme_constant_override("separation", 3)
	sep.custom_minimum_size = Vector2(0, 1)
	return sep


# 单页构造: 返回装好纸底 + 四边内边距的 MarginContainer(调用方往里塞内容)
# is_left 决定纸纹翻转(左右两页共用一张图, 镜像后暗角/霉斑不重复)与顶部内边距
func _cx_build_page(rect: Rect2, is_left: bool, paper_tex: Texture2D) -> MarginContainer:
	var page := Control.new()
	page.position = rect.position
	page.size = rect.size
	page.mouse_filter = Control.MOUSE_FILTER_PASS   # prose 滚动条要能点
	if is_left:
		_cx_left_page = page
	else:
		_cx_right_page = page

	if paper_tex != null:
		var paper := TextureRect.new()
		paper.texture = paper_tex
		paper.stretch_mode = TextureRect.STRETCH_SCALE
		paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		paper.flip_h = not is_left
		paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.add_child(paper)
	else:
		var plain := ColorRect.new()
		plain.color = CX_PAPER_FALLBACK
		plain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plain.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.add_child(plain)

	var host := MarginContainer.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_theme_constant_override("margin_left", int(CX_PAGE_MARGIN))
	host.add_theme_constant_override("margin_right", int(CX_PAGE_MARGIN))
	host.add_theme_constant_override("margin_top", int(CX_PAGE_PAD_V) if is_left else int(CX_PAGE_TOP_R))
	host.add_theme_constant_override("margin_bottom", int(CX_PAGE_PAD_V))
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(host)

	_cx_book.add_child(page)
	return host


# 书脊: 有烘焙图就贴, 没有退化成"暗带 + 中缝 + 缝线"三条 ColorRect
func _cx_build_spine(spine_tex: Texture2D) -> Control:
	var spine := Control.new()
	spine.position = Vector2(CX_SPINE_LX, CX_PAGE_Y)
	spine.size = Vector2(CX_SPINE_W, CX_PAGE_H)
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if spine_tex != null:
		var tr := TextureRect.new()
		tr.texture = spine_tex
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		spine.add_child(tr)
		return spine
	for band in [Rect2(0, 0, CX_SPINE_W, CX_PAGE_H), Rect2(4, 0, 2, CX_PAGE_H), Rect2(4, 0, 1, CX_PAGE_H)]:
		var cr := ColorRect.new()
		cr.color = Color(0.18, 0.13, 0.09, 0.9) if band.size.x >= CX_SPINE_W else (
			Color(0.10, 0.07, 0.05, 0.95) if band.size.x == 2 else Color(0.42, 0.32, 0.18, 0.7))
		cr.position = band.position
		cr.size = band.size
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spine.add_child(cr)
	return spine


# 图鉴 tab 专属样式: 皮革棕底 + 金棕字, 按下亮金底(覆盖 _make_pick_btn 的冷色三态)
func _cx_tab_styles() -> void:
	for tb in _cx_tab_btns:
		if tb == null or not is_instance_valid(tb):
			continue
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.200, 0.141, 0.102, 0.96)
		normal.border_color = Color(0.44, 0.34, 0.20)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(3)
		normal.content_margin_top = 4.0
		normal.content_margin_bottom = 4.0

		var hover: StyleBoxFlat = normal.duplicate()
		hover.bg_color = Color(0.263, 0.192, 0.133, 0.98)
		hover.border_color = Color(0.804, 0.643, 0.353)
		hover.set_border_width_all(2)

		var sel: StyleBoxFlat = hover.duplicate()
		sel.bg_color = Color(0.353, 0.267, 0.125, 1.0)

		tb.add_theme_stylebox_override("normal", normal)
		tb.add_theme_stylebox_override("hover", hover)
		tb.add_theme_stylebox_override("pressed", sel)
		tb.add_theme_stylebox_override("focus", normal)
		tb.add_theme_color_override("font_color", Color(0.784, 0.643, 0.353))
		tb.add_theme_color_override("font_hover_color", Color(0.92, 0.80, 0.50))
		tb.add_theme_color_override("font_pressed_color", Color(1.0, 0.824, 0.251))


# 当前 tab 的条目 id 列表
# 角色/武器直接用表键; Boss 两条(中/终极); 杂兵词缀用前缀区分(m = 杂兵 kind, af = 词缀 id)
func _cx_entry_ids() -> Array:
	var out: Array = []
	match _cx_tab:
		CX_TAB_CHAR:
			for k in GameManager.CHARACTERS.keys():
				out.append(str(k))
		1:
			for k in GameManager.WEAPONS.keys():
				out.append(str(k))
		2:
			out.append("mid")
			out.append("final")
		3:
			for k in GameManager.ENEMY_BASE.keys():
				out.append("en%d" % int(k))
			for k in GameManager.ENEMY_AFFIXES.keys():
				out.append("af_" + str(k))
			# 精英是独立于词缀的正交维度(ELITE_BASE), 不进 ENEMY_AFFIXES 也不进其 keys() 枚举,
			# 只能在词缀列之后手动追加一条。裸 id "elite" 不以 en/af_/ach_ 开头, 无静默串类风险。
			out.append("elite")
		CX_TAB_ACH:
			for k in GameManager.ACHIEVEMENTS.keys():
				out.append("ach_" + str(k))
	return out


# 切 tab: 重建列表并把选中项夹到新范围内, 再刷新详情
func _cx_rebuild_list() -> void:
	_cx_ids = _cx_entry_ids()
	_cx_sel = clampi(_cx_sel, 0, maxi(0, _cx_ids.size() - 1))
	for c in _cx_item_panels:
		if c != null and is_instance_valid(c):
			c.queue_free()
	_cx_item_panels.clear()
	_cx_item_subs.clear()
	if _cx_list_box == null:
		return
	for i in range(_cx_ids.size()):
		var id: String = str(_cx_ids[i])
		var item: PanelContainer = _cx_list_item(id)
		_cx_list_box.add_child(item)
		_cx_item_panels.append(item)
		# 无副标的条目(如 Boss 中条)没这个 meta; get_meta 带默认值仍会打 ERROR, 先 has_meta
		_cx_item_subs.append(item.get_meta("cx_sub") if item.has_meta("cx_sub") else null)
	_cx_refresh_list()


# 左侧列表单项 = 图书馆索引卡片: 牛皮纸底 + 墨棕字; 选中态走 _cx_refresh_list 换借书章红边
func _cx_list_item(id: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CX_LIST_W, CX_ITEM_H)

	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.788, 0.718, 0.604)   # 牛皮纸 #C9B79A
	base.border_color = Color(0.42, 0.33, 0.22)
	base.set_border_width_all(1)
	base.set_corner_radius_all(2)
	base.content_margin_left = CX_ITEM_PAD
	base.content_margin_right = CX_ITEM_PAD
	base.content_margin_top = 4.0
	base.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", base)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)

	var icon := TextureRect.new()
	icon.texture = _cx_entry_icon(id)
	icon.custom_minimum_size = Vector2(22, 22)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.modulate = _cx_entry_tint(id)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(texts)

	var name_lbl := Label.new()
	name_lbl.text = _cx_entry_name(id)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.231, 0.180, 0.133))   # 墨棕
	texts.add_child(name_lbl)

	var sub := _cx_entry_sub(id)
	if sub != "":
		var sub_lbl := Label.new()
		sub_lbl.text = sub
		sub_lbl.add_theme_font_size_override("font_size", 7)
		sub_lbl.add_theme_color_override("font_color", Color(0.478, 0.416, 0.333))
		texts.add_child(sub_lbl)
		panel.set_meta("cx_sub", sub_lbl)

	panel.gui_input.connect(_on_cx_item_pressed.bind(id))
	return panel


func _cx_refresh_list() -> void:
	for i in range(_cx_item_panels.size()):
		var panel: PanelContainer = _cx_item_panels[i]
		if panel == null or not is_instance_valid(panel):
			continue
		var sb := StyleBoxFlat.new()
		# 选中态: 亮纸底 + 借书章红边(2px); 未选中: 牛皮纸 + 棕边(1px)
		sb.bg_color = Color(0.910, 0.851, 0.659) if i == _cx_sel else Color(0.788, 0.718, 0.604)
		sb.border_color = Color(0.627, 0.188, 0.188) if i == _cx_sel else Color(0.42, 0.33, 0.22)
		sb.set_border_width_all(2 if i == _cx_sel else 1)
		sb.set_corner_radius_all(2)
		# 与初始 stylebox 同边距: 选中/未选中切换时内容不跳动
		sb.content_margin_left = CX_ITEM_PAD
		sb.content_margin_right = CX_ITEM_PAD
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		panel.add_theme_stylebox_override("panel", sb)
		# 副标随选中态换色: 亮纸底上原灰棕对比度略降, 选中加深
		if i < _cx_item_subs.size():
			var sub_lbl: Label = _cx_item_subs[i]
			if sub_lbl != null and is_instance_valid(sub_lbl):
				sub_lbl.add_theme_color_override("font_color",
					Color(0.400, 0.345, 0.270) if i == _cx_sel else Color(0.478, 0.416, 0.333))
	if _cx_scroll != null and _cx_sel < _cx_item_panels.size():
		_cx_scroll.ensure_control_visible(_cx_item_panels[_cx_sel])


func _cx_refresh_tabs() -> void:
	for i in range(_cx_tab_btns.size()):
		var b: Button = _cx_tab_btns[i]
		if b != null and is_instance_valid(b):
			b.button_pressed = (i == _cx_tab)


func _cx_refresh_detail() -> void:
	if _cx_ids.is_empty():
		return
	var id: String = str(_cx_ids[_cx_sel])
	if _cx_portrait != null:
		_cx_portrait.texture = _cx_entry_icon(id)
		_cx_portrait.modulate = _cx_entry_tint(id)
	if _cx_name != null:
		_cx_name.text = _cx_entry_name(id)
	if _cx_tag != null:
		_cx_tag.text = _cx_detail_tag(id)
	if _cx_stats != null:
		_cx_stats.text = _cx_inkify("\n".join(_cx_stats_lines(id)))
	if _cx_prose != null:
		_cx_prose.text = _cx_inkify("\n".join(_cx_prose_lines(id)))
		# 换条目重置滚动: 否则上一条的滚动位置残留, 新条目从半截开始显示
		# 4.6 无 scroll_vertical 属性, 滚动走内部 VScrollBar
		_cx_prose.get_v_scroll_bar().value = 0.0


# 图鉴专属: 旧霓虹 BBCode 色标 → 墨色系重映射(纸底 #E8DCC0 上原浅色对比度全废)
# 不改 _cx_stats_lines/_cx_prose_lines 的字面量与 GameManager 共享表:
# WEAPON_DETAILS/CODEX_BOSSES 的内联色标还被角色选择屏复用, 改表会串界面
# 词缀色块 col.to_html(false) 生成小写 hex, 与四个大写旧标签不匹配, 不会被误染
func _cx_inkify(s: String) -> String:
	return s.replace("#FF6A5A", CX_INK_LABEL) \
		.replace("#E6F2F5", CX_INK_BODY) \
		.replace("#57C7D6", CX_INK_ACCENT) \
		.replace("#999999", CX_INK_DIM)


# 特性色在纸底上的可读版本: 状态 tint 是给**深色战场上的敌人**用的(要亮才看得见),
# 直接搬到 #E8DCC0 纸底上对比度全废(stun #ffff99 亮度 0.92 ≈ 纸色本身)。
# _cx_inkify 的字符串替换救不了它 —— tint 是运行时 Color, 不是固定的四个字面量。
# 所以按亮度自适应压暗: 亮色往墨棕拉, 本来就暗的(bleed #d9594d)原样放行, 色相一律保留。
func _cx_trait_ink(c: Color) -> Color:
	var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	if lum <= 0.45:
		return c
	var t := clampf((lum - 0.45) / 0.55, 0.0, 1.0) * 0.62
	return c.lerp(Color(0.24, 0.17, 0.10), t)


# ---------- 条目展示信息(名称 / 副标 / 图标) ----------

func _cx_entry_name(id: String) -> String:
	if id.begins_with("en"):
		var k: int = int(id.substr(2))
		if GameManager.ENEMY_BASE.has(k):
			return str(GameManager.ENEMY_BASE[k]["name"])
		return "?"
	if id.begins_with("af_"):
		var ak: String = id.substr(3)
		if GameManager.ENEMY_AFFIXES.has(ak):
			return "词缀 · " + str(GameManager.ENEMY_AFFIXES[ak]["name"])
		return "?"
	if id.begins_with("ach_"):
		var ck: String = id.substr(4)
		if GameManager.ACHIEVEMENTS.has(ck):
			return str(GameManager.ACHIEVEMENTS[ck]["name"])
		return "?"
	if GameManager.CHARACTERS.has(id):
		return str(GameManager.CHARACTERS[id]["name"])
	if GameManager.WEAPONS.has(id):
		return str(GameManager.WEAPONS[id]["name"])
	if id == "mid":
		return GameManager.BOSS_NAME
	if id == "final":
		return GameManager.BOSS_FINAL_NAME
	if id == "elite":
		return str(GameManager.ELITE_BASE["name"])
	return id


# 列表项副标: 一句话区分同类条目(角色=定位标签, 杂兵=首现波次, 词缀=解锁波次)
func _cx_entry_sub(id: String) -> String:
	if id.begins_with("en"):
		var k: int = int(id.substr(2))
		return "第 %d 波起" % GameManager.enemy_first_wave(k)
	if id.begins_with("af_"):
		var ak: String = id.substr(3)
		if GameManager.ENEMY_AFFIXES.has(ak):
			return "第 %d 波解锁" % int(GameManager.ENEMY_AFFIXES[ak].get("unlock", 3))
		return ""
	if id.begins_with("ach_"):
		var ck: String = id.substr(4)
		if not GameManager.ACHIEVEMENTS.has(ck):
			return ""
		return "✔ 已解锁" if GameManager.achieved.has(ck) else "✖ 未解锁"
	if GameManager.CODEX_CHARS.has(id):
		return str(GameManager.CODEX_CHARS[id].get("tag", ""))
	if GameManager.WEAPONS.has(id):
		var wid: String = id
		if GameManager.EVOLUTIONS.has(wid):
			return "可进化 → " + str(GameManager.EVOLUTIONS[wid]["name"])
		return ""
	if id == "final":
		return "击杀即通关"
	if id == "elite":
		return "第 4 波起 · 词缀怪升格"
	return ""


func _cx_entry_icon(id: String) -> Texture2D:
	if id.begins_with("en"):
		var k: int = int(id.substr(2))
		if GameManager.ENEMY_FRAMES.has(k):
			return GameManager.codex_frame_texture("enemy%d" % k, GameManager.ENEMY_FRAMES[k])
		return null
	if id.begins_with("af_"):
		var ak: String = id.substr(3)
		if GameManager.ENEMY_AFFIXES.has(ak):
			# 词缀没有独立美术, 用其染色画一个色点(与实战中词缀怪身上的染色一致)
			return GameManager.circle_texture(7, Color(GameManager.ENEMY_AFFIXES[ak]["color"]))
		return null
	if id.begins_with("ach_"):
		# 每条成就有专属 16×16 字符画图标(见 GameManager.ACHIEVEMENT_ICONS);
		# 解锁与否靠列表副标与左页状态区分, 图标本身不变色
		return GameManager.achievement_icon_texture(id.substr(4))
	if GameManager.CHARACTERS.has(id):
		return GameManager.char_preview_texture(id)
	if GameManager.WEAPONS.has(id):
		return GameManager.weapon_icon_texture(id)
	if id == "mid" or id == "final":
		return GameManager.codex_frame_texture("boss", GameManager.BOSS_FRAMES)
	if id == "elite":
		# 精英无独立美术, 用其光环紫色画色点(与词缀色点先例一致, 也与实战 tint 一致)
		return GameManager.circle_texture(7, Color(GameManager.ELITE_BASE["tint"]))
	return null


# 终极 Boss 与实战一致地染红(boss.gd 的 _base_tint)
func _cx_entry_tint(id: String) -> Color:
	if id == "final":
		return Color(GameManager.BOSS_FINAL["tint"])
	return Color(1, 1, 1)


func _cx_detail_tag(id: String) -> String:
	if id.begins_with("en"):
		var k: int = int(id.substr(2))
		if GameManager.ENEMY_BASE.has(k):
			return str(GameManager.ENEMY_BASE[k].get("tag", ""))
		return ""
	if id.begins_with("af_"):
		return "敌人词缀 · 第 %d 波起进入词缀池" % int(GameManager.ENEMY_AFFIXES.get(id.substr(3), {}).get("unlock", 3))
	if id.begins_with("ach_"):
		var ck: String = id.substr(4)
		if GameManager.ACHIEVEMENTS.has(ck):
			return "全局成就 · 已解锁" if GameManager.achieved.has(ck) else "全局成就 · 未解锁"
		return ""
	if GameManager.CODEX_CHARS.has(id):
		return str(GameManager.CODEX_CHARS[id].get("tag", ""))
	if GameManager.WEAPON_DETAILS.has(id):
		return str(GameManager.WEAPON_DETAILS[id].get("summary", ""))
	if GameManager.CODEX_BOSSES.has(id):
		return str(GameManager.CODEX_BOSSES[id].get("tag", ""))
	if id == "elite":
		return "精英词缀档 · 双词缀 + 紫色光环的高威胁个体"
	return ""


# ---------- 详情左列: 数值(全部实时读表, 不写死) ----------
# BBCode 配色沿用项目约定: 标签 #FF6A5A / 数值 #E6F2F5 / 规则 #57C7D6 / 次级 #999999

func _cx_stats_lines(id: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if id.begins_with("ach_"):
		var ck: String = id.substr(4)
		if not GameManager.ACHIEVEMENTS.has(ck):
			return lines
		var got: bool = GameManager.achieved.has(ck)
		# 已解锁墨红(借书章色) / 未解锁灰描(沿用纸面墨色, 不引新配色)
		var mark: String = CX_INK_LABEL if got else CX_INK_DIM
		lines.append("[color=%s]状态[/color]  [color=%s]%s[/color]" % [
			CX_INK_ACCENT, mark, "✔ 已解锁" if got else "✖ 未解锁"])
		lines.append("")
		lines.append("[color=#57C7D6]解锁进度[/color]")
		lines.append("[color=#E6F2F5]已解锁 %d / %d[/color]" % [
			GameManager.achieved.size(), GameManager.ACHIEVEMENTS.size()])
		return lines

	if GameManager.CHARACTERS.has(id):
		var c: Dictionary = GameManager.CHARACTERS[id]
		lines.append("[color=#FF6A5A]生命上限[/color]  [color=#E6F2F5]%d[/color]" % int(c["max_hp"]))
		lines.append("[color=#FF6A5A]移动速度[/color]  [color=#E6F2F5]%d[/color]" % int(c["move_speed"]))
		lines.append("[color=#FF6A5A]伤害倍率[/color]  [color=#E6F2F5]×%.2f[/color]" % float(c["damage_mult"]))
		lines.append("[color=#FF6A5A]弹速倍率[/color]  [color=#E6F2F5]×%.2f[/color]" % float(c["proj_speed_mult"]))
		lines.append("[color=#FF6A5A]拾取范围[/color]  [color=#E6F2F5]%d[/color]" % int(c["pick_range"]))
		lines.append("[color=#FF6A5A]回血倍率[/color]  [color=#E6F2F5]×%.2f[/color]" % float(c["heal_mult"]))
		lines.append("")
		var wid: String = str(c["weapon"])
		var wname: String = str(GameManager.WEAPONS[wid]["name"]) if GameManager.WEAPONS.has(wid) else "无"
		lines.append("[color=#57C7D6]起始武器[/color]  [color=#E6F2F5]%s[/color]" % wname)
		lines.append("[color=#57C7D6]被动[/color]  %s" % str(c["passive"]))
		lines.append("[color=#57C7D6]规则[/color]  %s" % str(c["rule"]))
		return lines

	if GameManager.WEAPONS.has(id):
		var w: Dictionary = GameManager.WEAPONS[id]
		lines.append("[color=#FF6A5A]满级[/color]  [color=#E6F2F5]%d 级[/color]" % int(w["max_level"]))
		lines.append("[color=#FF6A5A]质变点[/color]  [color=#E6F2F5]2 级 / 3 级[/color]")
		lines.append("")
		if GameManager.EVOLUTIONS.has(id):
			var ev: Dictionary = GameManager.EVOLUTIONS[id]
			var pid: String = str(ev["passive"])
			var pname: String = str(GameManager.UPGRADES[pid]["name"]) if GameManager.UPGRADES.has(pid) else pid
			lines.append("[color=#57C7D6]进化形态[/color]  [color=#E6F2F5]%s[/color]" % str(ev["name"]))
			lines.append("[color=#57C7D6]配方[/color]  %s 满级 + %s 满级" % [str(w["name"]), pname])
		return lines

	if id == "mid" or id == "final":
		var b: Dictionary = GameManager.BOSS_BASE
		var is_fin: bool = (id == "final")
		var hpv: float = float(b["hp"])
		var spdv: float = float(b["speed"])
		var dmgv: float = float(b["damage"])
		var waves: Array = GameManager.boss_waves(is_fin)
		if is_fin:
			var f: Dictionary = GameManager.BOSS_FINAL
			hpv = float(f["hp"])
			spdv = float(f["speed"])
			dmgv = float(f["damage"])
		lines.append("[color=#FF6A5A]登场波次[/color]  [color=#E6F2F5]%s[/color]" % _cx_join_ints(waves, " / "))
		lines.append("[color=#FF6A5A]生命[/color]  [color=#E6F2F5]%d[/color]" % int(hpv))
		lines.append("[color=#FF6A5A]移动速度[/color]  [color=#E6F2F5]%d[/color]" % int(spdv))
		lines.append("[color=#FF6A5A]接触伤害[/color]  [color=#E6F2F5]%d[/color]" % int(dmgv))
		lines.append("[color=#FF6A5A]碰撞半径[/color]  [color=#E6F2F5]%d[/color]" % int(b["radius"]))
		lines.append("[color=#FF6A5A]接触间隔[/color]  [color=#E6F2F5]%.1f 秒[/color]" % float(b["contact_cd"]))
		lines.append("")
		lines.append("[color=#57C7D6]状态抗性[/color]  持续时长 ×%.1f" % float(b["status_resist"]))
		if not is_fin:
			lines.append("[color=#57C7D6]血量成长[/color]  每次登场 +%.0f%%" % (float(b["hp_step"]) * 100.0))
			# 三次登场的实际血量(由表算出, 便于对照实战血条)
			var growth := PackedStringArray()
			for i in range(waves.size()):
				growth.append("%d" % int(GameManager.boss_hp_for(i + 1)))
			lines.append("[color=#999999]  依次 %s[/color]" % " → ".join(growth))
		return lines

	if id.begins_with("en"):
		var k: int = int(id.substr(2))
		if not GameManager.ENEMY_BASE.has(k):
			return lines
		var e: Dictionary = GameManager.ENEMY_BASE[k]
		lines.append("[color=#FF6A5A]首次出现[/color]  [color=#E6F2F5]第 %d 波[/color]" % GameManager.enemy_first_wave(k))
		lines.append("[color=#FF6A5A]生命[/color]  [color=#E6F2F5]%d[/color]" % int(e["hp"]))
		lines.append("[color=#FF6A5A]移动速度[/color]  [color=#E6F2F5]%d[/color]" % int(e["speed"]))
		lines.append("[color=#FF6A5A]接触伤害[/color]  [color=#E6F2F5]%d[/color]" % int(e["damage"]))
		lines.append("[color=#FF6A5A]碰撞半径[/color]  [color=#E6F2F5]%d[/color]" % int(e["radius"]))
		lines.append("[color=#FF6A5A]经验值[/color]  [color=#E6F2F5]%d[/color]" % int(e["xp"]))
		lines.append("")
		lines.append("[color=#57C7D6]掉落[/color]")
		lines.append("[color=#999999]%s[/color]" % str(GameManager.ENEMY_DROPS.get(k, "")))
		return lines

	if id.begins_with("af_"):
		var ak: String = id.substr(3)
		if not GameManager.ENEMY_AFFIXES.has(ak):
			return lines
		var a: Dictionary = GameManager.ENEMY_AFFIXES[ak]
		var m: Dictionary = a.get("mult", {})
		lines.append("[color=#FF6A5A]解锁波次[/color]  [color=#E6F2F5]第 %d 波[/color]" % int(a.get("unlock", 3)))
		lines.append("[color=#FF6A5A]生命[/color]  [color=#E6F2F5]×%.2f[/color]" % float(m.get("hp", 1.0)))
		if m.has("speed"):
			lines.append("[color=#FF6A5A]速度[/color]  [color=#E6F2F5]×%.2f[/color]" % float(m.get("speed", 1.0)))
		if m.has("size"):
			lines.append("[color=#FF6A5A]体型[/color]  [color=#E6F2F5]×%.2f[/color]" % float(m.get("size", 1.0)))
		lines.append("")
		if a.has("regen"):
			lines.append("[color=#57C7D6]每秒回血[/color]  [color=#E6F2F5]%d[/color]" % int(a["regen"]))
		if a.has("interval"):
			lines.append("[color=#57C7D6]开火间隔[/color]  [color=#E6F2F5]%.1f 秒[/color]" % float(a["interval"]))
		if a.has("split"):
			lines.append("[color=#57C7D6]死亡分裂[/color]  [color=#E6F2F5]%d 只[/color]" % int(a["split"]))
		if a.has("explode_r"):
			lines.append("[color=#57C7D6]爆炸半径[/color]  [color=#E6F2F5]%d[/color]" % int(a["explode_r"]))
			lines.append("[color=#57C7D6]爆炸伤害[/color]  [color=#E6F2F5]%d[/color]" % int(a["explode_dmg"]))
		lines.append("[color=#57C7D6]经验加成[/color]  [color=#E6F2F5]×1.3[/color]")
		return lines

	if id == "elite":
		# 数值全部读 ELITE_BASE(单一真相源, 与 enemy.setup 共表)。
		# 行数被 codex_self_check 的裁切断言卡住(≤10, mid 分支实测 10 行是安全上限):
		# 掉落「金币 3×12 · 25% 宝箱」拆两行, 波次爬坡细节移入 prose。
		var el: Dictionary = GameManager.ELITE_BASE
		lines.append("[color=#FF6A5A]登场波次[/color]  [color=#E6F2F5]第 4 波起[/color]")
		lines.append("[color=#FF6A5A]生命[/color]  [color=#E6F2F5]×%.1f[/color]" % float(el["hp"]))
		lines.append("[color=#FF6A5A]伤害[/color]  [color=#E6F2F5]×%.1f[/color]" % float(el["damage"]))
		lines.append("[color=#FF6A5A]速度[/color]  [color=#E6F2F5]×%.2f[/color]" % float(el["speed"]))
		lines.append("[color=#FF6A5A]体型[/color]  [color=#E6F2F5]×%.2f (碰撞×1.15)[/color]" % float(el["size"]))
		lines.append("[color=#FF6A5A]经验[/color]  [color=#E6F2F5]×%.1f · 词缀各×1.3[/color]" % float(el["xp"]))
		lines.append("")
		lines.append("[color=#57C7D6]掉落[/color]  [color=#E6F2F5]金币 %d×%d[/color]" % [int(el["coin_n"]), int(el["coin_value"])])
		lines.append("[color=#57C7D6]宝箱[/color]  [color=#E6F2F5]%.0f%%[/color]" % (float(el["item_drop"]) * 100.0))
		lines.append("[color=#57C7D6]出率[/color]  [color=#E6F2F5]2%%~6%% +诅咒[/color]")
		return lines

	return lines


# ---------- 详情右列: 文案(玩法/应对/成长) ----------

func _cx_prose_lines(id: String) -> PackedStringArray:
	var lines := PackedStringArray()
	if id.begins_with("ach_"):
		var ck: String = id.substr(4)
		if not GameManager.ACHIEVEMENTS.has(ck):
			return lines
		var a: Dictionary = GameManager.ACHIEVEMENTS[ck]
		# 每条成就右页含自身标题+达成条件(逐条唯一, 不与相邻条目同文); 解锁计数在左页数值列
		lines.append("[color=#57C7D6]「%s」[/color]" % str(a["name"]))
		lines.append("[color=#E6F2F5]%s[/color]" % str(a["desc"]))
		lines.append("")
		lines.append("[color=#57C7D6]档案[/color]")
		lines.append("[color=#E6F2F5]成就为全局共享, 跨存档槽与单局永久保留, 解锁后写入永久档案。[/color]")
		return lines

	if GameManager.CODEX_CHARS.has(id):
		var d: Dictionary = GameManager.CODEX_CHARS[id]
		lines.append("[color=#57C7D6]怎么玩[/color]")
		lines.append("[color=#E6F2F5]%s[/color]" % str(d.get("play", "")))
		lines.append("")
		lines.append("[color=#57C7D6]要点[/color]")
		lines.append("[color=#E6F2F5]%s[/color]" % str(d.get("key", "")))
		return lines

	if GameManager.WEAPON_DETAILS.has(id):
		var def: Dictionary = GameManager.WEAPON_DETAILS[id]
		lines.append("[color=#57C7D6]定位[/color]")
		lines.append("[color=#E6F2F5]%s[/color]" % str(def.get("summary", "")))
		# 特性行: 七把武器 ↔ 七个状态一对一(见 GameManager.WEAPON_TRAITS), 所以翻完 7 条武器
		# 条目就等于读完整张状态表, 不另开「状态说明」页。
		# 颜色取 StatusFx.CONFIG 的 tint —— UI 上标的颜色 == 敌人身上实际染的颜色,
		# 玩家看图鉴学到"紫色 = 易伤", 实战看见紫怪立刻能对上。
		# 未登记特性的武器整行不显示(不会留下光秃秃的标题)。
		var t_kind := GameManager.trait_of(id)
		if t_kind != "":
			lines.append("")
			lines.append("[color=#%s]特性 · %s[/color]" % [
				_cx_trait_ink(GameManager.trait_color(id)).to_html(false),
				GameManager.trait_name(id)])
			lines.append("[color=#E6F2F5]%s[/color]" % GameManager.trait_desc(id))
		lines.append("")
		lines.append("[color=#57C7D6]成长节点(每级都是质变, 满级 3 级)[/color]")
		for ln in GameManager.weapon_level_lines(id):
			lines.append("· %s" % str(ln))   # lines 内自带配色, 外层只加项目符号
		if GameManager.EVOLUTIONS.has(id):
			var ev: Dictionary = GameManager.EVOLUTIONS[id]
			lines.append("")
			lines.append("[color=#57C7D6]进化 · %s[/color]" % str(ev["name"]))
			lines.append("[color=#E6F2F5]%s[/color]" % str(ev["desc"]))
		lines.append("")
		lines.append("[color=#999999]武器等级在三选一里抽到重复武器时提升, 满级 3 级。[/color]")
		return lines

	if GameManager.CODEX_BOSSES.has(id):
		var bd: Dictionary = GameManager.CODEX_BOSSES[id]
		lines.append("[color=#57C7D6]概览[/color]")
		lines.append("[color=#E6F2F5]%s[/color]" % str(bd.get("summary", "")))
		lines.append("")
		lines.append("[color=#57C7D6]技能循环[/color]")
		for s in bd.get("skills", []):
			lines.append("· %s" % str(s))
		lines.append("")
		lines.append("[color=#57C7D6]应对[/color]")
		for s in bd.get("counter", []):
			lines.append("· [color=#E6F2F5]%s[/color]" % str(s))
		lines.append("")
		lines.append("[color=#57C7D6]击杀掉落[/color]")
		lines.append("[color=#E6F2F5]%s[/color]" % str(bd.get("reward", "")))
		return lines

	if id.begins_with("en"):
		var k: int = int(id.substr(2))
		if GameManager.ENEMY_BASE.has(k):
			lines.append("[color=#57C7D6]应对[/color]")
			lines.append("[color=#E6F2F5]%s[/color]" % str(GameManager.ENEMY_BASE[k].get("note", "")))
			lines.append("")
			lines.append("[color=#999999]数值为第 1 波 / 普通难度 / 无词缀的面板值。[/color]")
			lines.append("[color=#999999]实战血量还要乘波次成长(每波 +20%, 封顶 3 倍)、难度倍率与词缀倍率。[/color]")
		return lines

	if id.begins_with("af_"):
		var ak: String = id.substr(3)
		if GameManager.ENEMY_AFFIXES.has(ak):
			var a: Dictionary = GameManager.ENEMY_AFFIXES[ak]
			lines.append("[color=#57C7D6]应对[/color]")
			lines.append("[color=#E6F2F5]%s[/color]" % str(a.get("note", "")))
			lines.append("")
			var col: Color = Color(a["color"])
			lines.append("[color=#57C7D6]辨认[/color]  [color=#%s]■[/color] 实战中该怪整体染成这个颜色, 体型也会按倍数缩放。" % col.to_html(false))
			lines.append("")
			# 上限随诅咒放宽(0.28 是基础硬顶) —— 必须动态取, 否则玩家叠了诅咒后图鉴在说谎
			lines.append("[color=#999999]词缀自第 3 波起按概率附加(波次越深概率越高, 上限 %.0f%%), 词缀怪经验 ×1.3。[/color]"
				% ((0.28 + GameManager.curse_affix_bonus()) * 100.0))
			# 诅咒说明挂在词缀条目下: 诅咒正是通过抬高词缀/精英出率来放大威胁的, 两者是同一套机制的两端
			for cl in GameManager.codex_curse_lines():
				lines.append(cl)
		return lines

	if id == "elite":
		lines.append("[color=#57C7D6]应对[/color]")
		lines.append("[color=#E6F2F5]%s[/color]" % str(GameManager.ELITE_BASE["note"]))
		lines.append("")
		var ec: Color = Color(GameManager.ELITE_BASE["tint"])
		lines.append("[color=#57C7D6]辨认[/color]  [color=#%s]■[/color] 本体染紫 + 脚下紫色呼吸光环(金心定环); 进场前 0.9 秒预警圈就是同款双环, 看到即可预备集火。" % ec.to_html(false))
		lines.append("")
		lines.append("[color=#57C7D6]规则[/color]")
		lines.append("[color=#E6F2F5]精英不是独立怪物, 而是「词缀怪的升格」: 先掷中词缀, 再按波次深度掷精英率(第 4 波 2% / 第 6 波 4% / 第 9 波 6%), 诅咒每层再 +1.2%。它同时携带两个不同词缀(双持), 属性再乘右侧倍率。[/color]")
		lines.append("[color=#E6F2F5]分裂型精英的子代不会继承精英身份 —— 子代只是普通词缀怪, 不会指数爆炸。[/color]")
		lines.append("")
		lines.append("[color=#999999]数值为普通难度第 12 波前(波次成长 ×3 之前)相对同种基础怪的倍率; 实战还叠波次成长、难度倍率与诅咒。[/color]")
		return lines

	return lines


# 文案溢出提示的可见性: 布局每帧都可能变(切条目/切 tab), 在 _process 里算最稳
func _cx_update_scroll_hint() -> void:
	if _cx_scroll_hint == null or not is_instance_valid(_cx_scroll_hint):
		return
	var over: bool = _cx_prose != null and is_instance_valid(_cx_prose) \
		and _cx_prose.get_content_height() > _cx_prose.size.y + 1.0
	_cx_scroll_hint.visible = over


func _cx_join_ints(arr: Array, sep: String) -> String:
	var parts := PackedStringArray()
	for v in arr:
		parts.append("%d" % int(v))
	return sep.join(parts)


# ---------- 导航 ----------

# A/D 切分类: 到边缘即停不绕回; 切 tab 后选中项归零(各类条目无对应关系)
# 单页方向性翻页 + 书签丝带换色(原 "pickup" 声保留, 与翻页声节流 key 不同不冲突)
func _codex_tab_move(dx: int, quiet: bool = false) -> void:
	if _cx_closing:
		return
	var idx: int = wrapi(_cx_tab + dx, 0, CX_TAB_NAMES.size())   # 环绕: 长按可跨分类循环
	if idx == _cx_tab:
		return
	var dir: int = signi(idx - _cx_tab)
	_cx_tab = idx
	_cx_sel = 0
	_cx_rebuild_list()
	_cx_refresh_tabs()
	_cx_start_flip(dir, CX_TAB_FLIPS)
	_cx_ribbon_animate(idx)
	if not quiet:
		GameManager.play_sfx("pickup")


# W/S 切条目: 到边缘环绕。列表在书外立即刷新, 书内走单页方向性翻页(翻页声取代原 pickup)
func _codex_sel_move(dy: int) -> void:
	if _cx_closing:
		return
	if _cx_ids.is_empty():
		return
	var idx: int = wrapi(_cx_sel + dy, 0, _cx_ids.size())   # 环绕: 长按可一圈圈扫
	if idx == _cx_sel:
		return
	_cx_sel = idx
	_cx_refresh_list()
	_cx_start_flip(signi(dy), 1)


func _on_codex_tab(i: int) -> void:
	if _cx_closing:
		return
	if i == _cx_tab:
		return
	GameManager.play_sfx("select")
	var dir: int = signi(i - _cx_tab)
	_cx_tab = i
	_cx_sel = 0
	_cx_rebuild_list()
	_cx_refresh_tabs()
	_cx_start_flip(dir, CX_TAB_FLIPS)
	_cx_ribbon_animate(i)


func _on_cx_item_pressed(event: InputEvent, id: String) -> void:
	if _cx_closing:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var idx: int = _cx_ids.find(id)
		if idx >= 0 and idx != _cx_sel:
			var dir: int = 1 if idx > _cx_sel else -1
			_cx_sel = idx
			_cx_refresh_list()
			_cx_start_flip(dir, 1)


# ---------- 翻页 / 书签 / 开合书 ----------

# 启动翻页: 打断策略 = 杀旧 tween 直接开新(0.15s 足够短, 连按视觉上就是连续快扫)
# force = true 时无视 _cx_anim_enabled(自检要验证翻页闭环); 否则关动画就直接刷新内容
func _cx_start_flip(dir: int, pages: int, force: bool = false) -> void:
	if _cx_page_flip == null:
		_cx_refresh_detail()
		return
	if not _cx_anim_enabled and not force:
		_cx_refresh_detail()
		return
	if _cx_page_tw != null and _cx_page_tw.is_valid():
		_cx_page_tw.kill()
	_cx_page_tw = null
	_cx_flip_dir = dir
	_cx_flip_pages = pages
	_cx_flip_swapped = false
	_cx_flip_sound_at = 1
	_cx_page_flip.dir = dir
	_cx_page_flip.pages = pages
	_cx_page_flip.progress = 0.0
	_cx_page_flip.visible = true
	GameManager.play_page_sfx(0)
	_cx_page_tw = create_tween()
	_cx_page_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var dur: float = CX_FLIP_TIME if pages == 1 else float(pages) * CX_FLIP_PAGE_TIME
	_cx_page_tw.tween_method(_cx_on_flip_progress, 0.0, float(pages), dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_cx_page_tw.tween_callback(_cx_flip_finish)


# 内容切换时机 = 第一页中点(p >= 0.5)。_cx_refresh_detail 永远读最新 _cx_sel,
# 所以连打 W/S 时中途刷新的自动就是最新条目, 不存在旧内容闪回
func _cx_on_flip_progress(p: float) -> void:
	if not _cx_flip_swapped and p >= 0.5:
		_cx_flip_swapped = true
		_cx_refresh_detail()
	while _cx_flip_sound_at < _cx_flip_pages and p >= float(_cx_flip_sound_at):
		GameManager.play_page_sfx(0)
		_cx_flip_sound_at += 1
	if _cx_page_flip != null:
		_cx_page_flip.progress = p
		_cx_page_flip.queue_redraw()


func _cx_flip_finish() -> void:
	if not _cx_flip_swapped:
		_cx_refresh_detail()   # 被 kill 打断时的兜底刷新
	_cx_flip_swapped = true
	if _cx_page_flip != null:
		_cx_page_flip.progress = 0.0
		_cx_page_flip.visible = false
		_cx_page_flip.queue_redraw()
	_cx_page_tw = null


# 书签丝带换色: 前半 bob 抬升(带子缩短), t=0.5 切色, 后半落回
func _cx_ribbon_refresh(instant: bool) -> void:
	if _cx_ribbon == null:
		return
	if instant:
		if _cx_ribbon_tw != null and _cx_ribbon_tw.is_valid():
			_cx_ribbon_tw.kill()
		_cx_ribbon_tw = null
		_cx_ribbon.tab_idx = _cx_tab
		_cx_ribbon.color = CX_RIBBON_COLORS[_cx_tab]
		_cx_ribbon.bob = 0.0
		_cx_ribbon.queue_redraw()
		return
	_cx_ribbon_animate(_cx_tab)


func _cx_ribbon_animate(to_tab: int) -> void:
	if _cx_ribbon == null:
		return
	if not _cx_anim_enabled:
		_cx_ribbon_refresh(true)
		return
	if _cx_ribbon_tw != null and _cx_ribbon_tw.is_valid():
		_cx_ribbon_tw.kill()
	_cx_ribbon_to = to_tab
	_cx_ribbon_tw = create_tween()
	_cx_ribbon_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_cx_ribbon_tw.tween_method(_cx_on_ribbon_progress, 0.0, 1.0, CX_RIBBON_TIME)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cx_ribbon_tw.tween_callback(_cx_ribbon_finish)


func _cx_on_ribbon_progress(t: float) -> void:
	if _cx_ribbon == null:
		return
	if t >= 0.5 and _cx_ribbon.tab_idx != _cx_ribbon_to:
		_cx_ribbon.tab_idx = _cx_ribbon_to
		_cx_ribbon.color = CX_RIBBON_COLORS[_cx_ribbon_to]
	_cx_ribbon.bob = t
	_cx_ribbon.queue_redraw()


func _cx_ribbon_finish() -> void:
	if _cx_ribbon != null:
		_cx_ribbon.tab_idx = _cx_ribbon_to
		_cx_ribbon.color = CX_RIBBON_COLORS[_cx_ribbon_to]
		_cx_ribbon.bob = 0.0
		_cx_ribbon.queue_redraw()
	_cx_ribbon_tw = null


# 开书: 以书脊为中轴两侧展开(scale.x 0.12 → 1.0, 轻微过冲 = 摊开落定感)
# 书脊居中 pivot 让过冲左右对称: scale 1.1 时全局 x 跨 181..637, 仍在 640 屏内
func _cx_book_open_anim() -> void:
	if _cx_book == null:
		return
	_cx_book.pivot_offset = Vector2(CX_SPINE_LX + CX_SPINE_W / 2.0, CX_BOOK_H / 2.0)
	_cx_book.scale = Vector2(0.12, 1.0)
	if _cx_book_tw != null and _cx_book_tw.is_valid():
		_cx_book_tw.kill()
	_cx_book_tw = create_tween()
	_cx_book_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_cx_book_tw.tween_property(_cx_book, "scale", Vector2.ONE, CX_OPEN_TIME)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_cx_book_tw.tween_callback(_cx_book_open_finish)


func _cx_book_open_finish() -> void:
	if _cx_book != null:
		_cx_book.scale = Vector2.ONE
	_cx_book_tw = null


# 关闭: 合书动画播完才真正切回来源。用 tween_callback 而非 finished 信号 ——
# _cx_close_finish 内部 show_menu() → _clear_all() 会 kill tween, finished 在 kill 时不发射
func _on_codex_close() -> void:
	if _cx_closing:
		return   # ESC 连打重入 guard
	if _cx_book == null or not _cx_anim_enabled:
		_cx_close_finish()
		return
	_cx_closing = true
	GameManager.play_page_sfx(1)   # 合书闷响
	if _cx_page_tw != null and _cx_page_tw.is_valid():
		_cx_page_tw.kill()
	_cx_page_tw = null
	if _cx_page_flip != null:
		_cx_page_flip.progress = 0.0
		_cx_page_flip.visible = false
		_cx_page_flip.queue_redraw()
	_cx_book.pivot_offset = Vector2(CX_SPINE_LX + CX_SPINE_W / 2.0, CX_BOOK_H / 2.0)
	if _cx_book_tw != null and _cx_book_tw.is_valid():
		_cx_book_tw.kill()
	_cx_book_tw = create_tween()
	_cx_book_tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_cx_book_tw.tween_property(_cx_book, "scale", Vector2(0.10, 1.0), CX_CLOSE_TIME)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_cx_book_tw.parallel().tween_property(_cx_book, "modulate:a", 0.4, CX_CLOSE_TIME)
	_cx_book_tw.tween_callback(_cx_close_finish)


# 回来源(主菜单→MENU; 设置→SETTINGS)
# paused 一律不动: 游戏内 ESC 时 main.gd 已置 true, 图鉴只是叠在上层, 回设置时还在暂停中
func _cx_close_finish() -> void:
	_cx_closing = false
	if _cx_book_tw != null and _cx_book_tw.is_valid():
		_cx_book_tw.kill()
	_cx_book_tw = null
	GameManager.play_sfx("select")
	var st := GameManager.codex_return_state
	if st == GameManager.State.SETTINGS:
		GameManager.state = GameManager.State.SETTINGS
		show_settings()
	else:
		GameManager.state = GameManager.State.MENU
		show_menu()


# 图鉴自检(--codex-check): headless 走查全部 tab × 全部条目
# 校验: 条目非空 / 图标取到 / 数值列与文案列都有内容 / 数值列没被裁掉
# 每换一条 await 2 帧, 等 Control 布局算完再量尺寸(_ready 同帧读到的 size 是 0)
func codex_self_check() -> void:
	_cx_anim_enabled = false   # headless 下关动画走直刷路径, 否则开书 tween 永远不播完
	show_codex()
	await get_tree().process_frame
	await get_tree().process_frame
	var total := 0
	var fail := 0
	for tab in range(CX_TAB_NAMES.size()):
		_cx_tab = tab
		_cx_sel = 0
		_cx_rebuild_list()
		_cx_refresh_tabs()
		_cx_ribbon_refresh(true)   # 直刷路径下丝带必须跟上, 否则后面的 tab 同步断言会误报
		print("[CODEX] tab=%d %s entries=%d" % [tab, CX_TAB_NAMES[tab], _cx_ids.size()])
		if _cx_ids.is_empty():
			print("[CODEX]   FAIL tab %d 无任何条目" % tab)
			fail += 1
			continue
		for i in range(_cx_ids.size()):
			_cx_sel = i
			_cx_refresh_list()
			_cx_refresh_detail()
			await get_tree().process_frame
			await get_tree().process_frame
			total += 1
			var nm: String = _cx_name.text if _cx_name != null else ""
			var icon_ok: bool = _cx_portrait != null and _cx_portrait.texture != null
			var stats_len: int = _cx_stats.text.length() if _cx_stats != null else 0
			var prose_len: int = _cx_prose.text.length() if _cx_prose != null else 0
			var msgs := PackedStringArray()
			if nm == "" or nm == "?":
				msgs.append("名称缺失")
			if not icon_ok:
				msgs.append("图标缺失")
			if stats_len == 0:
				msgs.append("数值列为空")
			if prose_len == 0:
				msgs.append("文案列为空")
			# size.y 被容器拉伸成整列高, 量不出内容; 必须用 get_content_height()
			# 数值列 scroll_active=false: 内容高于可视区就是被裁掉, 判失败
			var stats_h: float = _cx_stats.get_content_height() if _cx_stats != null else 0.0
			var stats_vis: float = _cx_stats.size.y if _cx_stats != null else 0.0
			if stats_h > stats_vis + 1.0:
				msgs.append("数值列被裁(内容%.0f > 可视%.0f)" % [stats_h, stats_vis])
			# 文案列开了滚动: 超出可视是允许滚的, 只报信息不判失败
			var prose_h: float = _cx_prose.get_content_height() if _cx_prose != null else 0.0
			var prose_vis: float = _cx_prose.size.y if _cx_prose != null else 0.0
			# 滚动提示可见性必须与溢出状态一致(提示由 _process 每帧算, await 后已生效)
			if _cx_scroll_hint != null and _cx_scroll_hint.visible != (prose_h > prose_vis + 1.0):
				msgs.append("滚动提示状态不符")
			if msgs.is_empty():
				var scroll_note := " (文案需滚动 %.0f/%.0f)" % [prose_h, prose_vis] if prose_h > prose_vis + 1.0 else ""
				print("[CODEX]   ok  %-10s | stats=%3d/%.0f prose=%4d/%.0f%s" % [nm, stats_len, stats_h, prose_len, prose_h, scroll_note])
			else:
				print("[CODEX]   FAIL %-10s | %s" % [nm, ", ".join(msgs)])
				fail += 1
	print("[CODEX] SELF-CHECK total=%d fail=%d" % [total, fail])

	# 新增结构性断言: 书本节点齐全; 翻页/丝带/开合闭环; 关闭 gate; 合成音可用
	if _cx_book == null or _cx_left_page == null or _cx_right_page == null \
			or _cx_page_flip == null or _cx_ribbon == null:
		print("[CODEX]   FAIL 书本节点缺失(book/left/right/flip/ribbon)")
		fail += 1
	else:
		# 空闲态 overlay 必须隐藏且不挡鼠标; 丝带 tab 必须与当前 tab 一致
		if _cx_page_flip.visible or _cx_page_flip.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			print("[CODEX]   FAIL 翻页 overlay 空闲态异常")
			fail += 1
		if _cx_ribbon.tab_idx != _cx_tab:
			print("[CODEX]   FAIL 书签丝带 tab 未同步")
			fail += 1
		# 内容挂载位置: portrait/stats 在左页子树, prose 在右页子树
		if _cx_portrait == null or not _cx_left_page.is_ancestor_of(_cx_portrait):
			print("[CODEX]   FAIL 立绘不在左页")
			fail += 1
		if _cx_stats == null or not _cx_left_page.is_ancestor_of(_cx_stats):
			print("[CODEX]   FAIL 数值列不在左页")
			fail += 1
		if _cx_prose == null or not _cx_right_page.is_ancestor_of(_cx_prose):
			print("[CODEX]   FAIL 文案不在右页")
			fail += 1

	# 武器图标非全透明: 整张空 = 字符画/色板写错(8×8→16×16 重绘的回归网)。
	# 独立成段不塞进 per-entry 循环: 循环里那个 texture 对角色是 AtlasTexture、对词缀是
	# circle ImageTexture, 混测会把武器美术检查耦合到 tab 状态上。
	for wid in GameManager.WEAPONS.keys():
		var wtex: Texture2D = GameManager.weapon_icon_texture(wid)
		if wtex == null or wtex.get_image().is_invisible():
			print("[CODEX]   FAIL 武器图标全透明: %s" % wid)
			fail += 1

	# 翻页闭环(force 无视 anim flag): 启动后应自动收尾, tween 归 null + overlay 隐藏
	# 约定同 _codex_sel_move: 先改 _cx_sel 再翻页(中点刷新读最新选中项)
	if _cx_ids.size() > 1:
		_cx_sel = 0
		_cx_refresh_list()
		_cx_refresh_detail()   # 基线: 第 1 条
		_cx_sel = 1
		_cx_refresh_list()
		_cx_start_flip(1, 1, true)
		for _n in range(40):
			await get_tree().process_frame
		if _cx_page_tw != null or (_cx_page_flip != null and _cx_page_flip.visible):
			print("[CODEX]   FAIL 翻页未收尾")
			fail += 1
		var exp_name: String = _cx_entry_name(str(_cx_ids[1]))
		if _cx_name == null or _cx_name.text != exp_name:
			print("[CODEX]   FAIL 翻页后详情未切到目标条目(得 %s 期望 %s)" % [_cx_name.text, exp_name])
			fail += 1
	else:
		print("[CODEX]   skip 翻页闭环(当前 tab 仅 1 条, 无法向前翻)")

	# 动画禁用路径: 直刷(不启动 tween), 调用后内容立即就是新条目
	var anim_was: bool = _cx_anim_enabled
	_cx_anim_enabled = false
	if _cx_ids.size() > 1:
		var before: String = _cx_prose.text if _cx_prose != null else ""
		var ns2: int = clampi(_cx_sel + 1, 0, _cx_ids.size() - 1)
		if ns2 != _cx_sel:
			_cx_sel = ns2
			_cx_refresh_list()
			_cx_start_flip(1, 1)
			if _cx_page_tw != null:
				print("[CODEX]   FAIL 动画禁用路径不应启动 tween")
				fail += 1
			if _cx_prose != null and _cx_prose.text == before:
				print("[CODEX]   FAIL 动画禁用路径未同步刷新")
				fail += 1
	_cx_anim_enabled = anim_was

	# 关闭 gate: _cx_closing 期间导航必须被忽略(放在最后, 前面已复位 _cx_sel)
	if _cx_ids.size() > 1:
		var g_tab: int = _cx_tab
		var g_sel: int = _cx_sel
		_cx_closing = true
		_codex_sel_move(1)
		_codex_tab_move(1)
		_cx_closing = false
		if _cx_tab != g_tab or _cx_sel != g_sel:
			print("[CODEX]   FAIL 关闭 gate 未拦住导航")
			fail += 1

	# 合成音频: stream 非空且样本量充足(data 是 16bit 小端 PCM, 每采样 2 字节)
	var streak: AudioStreamWAV = GameManager.page_sfx_stream(0)
	if streak == null or streak.data.size() < 2000:
		print("[CODEX]   FAIL 翻页合成音未生成")
		fail += 1
	var thud: AudioStreamWAV = GameManager.page_sfx_stream(1)
	if thud == null or thud.data.size() < 2000:
		print("[CODEX]   FAIL 合书合成音未生成")
		fail += 1

	print("[CODEX] FINAL total=%d fail=%d" % [total, fail])
	if fail > 0:
		print("[CODEX] ASSERT-FAIL")
	get_tree().quit()


# 图鉴截图(--codex-shot): 必须用带窗口 exe 跑(headless 是 dummy renderer 截出来全黑)
# 逐 tab 截一张 PNG(默认选中第一条), 存到项目目录 _codex_shots/tab<n>.png 供目检布局/配色
func codex_shots() -> void:
	_cx_anim_enabled = false   # 截图要确定性画面, 跳过开书/翻页动画
	var dir := ProjectSettings.globalize_path("res://") + "_codex_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	show_codex()
	await get_tree().process_frame
	await get_tree().process_frame
	for tab in range(CX_TAB_NAMES.size()):
		_cx_tab = tab
		_cx_sel = 0
		_cx_rebuild_list()
		_cx_refresh_tabs()
		_cx_refresh_list()
		_cx_refresh_detail()
		_cx_ribbon_refresh(true)
		await get_tree().process_frame
		await get_tree().process_frame
		var img: Image = get_viewport().get_texture().get_image()
		var path := dir + "/tab%d.png" % tab
		img.save_png(path)
		print("[CODEX-SHOT] saved %s" % path)
	# 精英条目帧: 主循环每 tab 只截 sel=0(tab3 是史莱姆), 而精英是词缀列之后的独立追加末条,
	# 默认帧永远拍不到 —— 单独定位它目检紫色色点图标 / stats 拆行不裁切 / prose 辨认+规则排版。
	_cx_tab = 3
	_cx_rebuild_list()
	var ei: int = _cx_ids.find("elite")
	if ei >= 0:
		_cx_sel = ei
		_cx_refresh_tabs()
		_cx_refresh_list()
		_cx_refresh_detail()
		_cx_ribbon_refresh(true)
		await get_tree().process_frame
		await get_tree().process_frame
		var eimg: Image = get_viewport().get_texture().get_image()
		eimg.save_png(dir + "/tab3_elite.png")
		print("[CODEX-SHOT] saved %s/tab3_elite.png" % dir)
	# 全解锁态帧: 成就图标/副标/左页状态在解锁前后不同, 而真档通常没解几条,
	# 故内存态全解锁(test_mode 不落盘, 不污染真档)重刷成就 tab 供目检。
	# 必须在翻页帧之前截: flip_mid 会把翻页遮罩留在 visible 状态。
	for aid in GameManager.ACHIEVEMENTS.keys():
		GameManager.achieved[aid] = true
	_cx_tab = CX_TAB_NAMES.size() - 1
	_cx_sel = 0
	_cx_rebuild_list()
	_cx_refresh_tabs()
	_cx_refresh_list()
	_cx_refresh_detail()
	_cx_ribbon_refresh(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var unl: Image = get_viewport().get_texture().get_image()
	unl.save_png(dir + "/tab4_unlocked.png")
	print("[CODEX-SHOT] saved %s/tab4_unlocked.png" % dir)
	# 列表尾帧: 成就 10 条一屏放不下, 选末条让 ensure_control_visible 滚到底,
	# 目检后几个图标(_cx_refresh_detail 内部会跟滚)
	_cx_sel = _cx_ids.size() - 1
	_cx_refresh_list()
	_cx_refresh_detail()
	await get_tree().process_frame
	await get_tree().process_frame
	var tail: Image = get_viewport().get_texture().get_image()
	tail.save_png(dir + "/tab4_tail.png")
	print("[CODEX-SHOT] saved %s/tab4_tail.png" % dir)
	# 翻页中间帧: 手动驱动 progress 到 0.35, 确定性地画出边界带供目检(不动动画状态机)
	if _cx_page_flip != null and _cx_ids.size() > 1:
		_cx_page_flip.dir = 1
		_cx_page_flip.pages = 1
		_cx_page_flip.visible = true
		_cx_on_flip_progress(0.35)
		await get_tree().process_frame
		await get_tree().process_frame
		var mid: Image = get_viewport().get_texture().get_image()
		mid.save_png(dir + "/flip_mid.png")
		print("[CODEX-SHOT] saved %s/flip_mid.png" % dir)
	get_tree().quit()


func _clear_all() -> void:
	for child in get_children():
		if child is Control:
			child.queue_free()
	_hold_clear()   # 界面清了连发必须作废(否则会作用到新界面上)
	game_hud = null
	_buffs_panel = null
	_buffs_header = null
	_buffs_text_label = null
	_buffs_last = ""
	_curse_label = null
	_curse_last = -1   # 必须重置: 否则新 HUD 的诅咒值与上次相同(如都是 0)时被缓存吃掉, 标签状态不刷
	_wave_label_last = ""   # 同理: 否则新 HUD 波次与上次相同(如都是波 1)时倒计时被缓存吃掉不刷
	char_screen = null
	_detail_portrait = null
	_detail_name = null
	_detail_info = null
	_char_detail_inner = null
	_weapon_detail_inner = null
	if _char_sel_tw != null and _char_sel_tw.is_valid():
		_char_sel_tw.kill()
	_char_sel_tw = null
	_detail_weapon_icon = null
	_detail_weapon_name = null
	_detail_weapon_summary = null
	_detail_weapon_info = null
	levelup_screen = null
	gameover_screen = null
	victory_screen = null
	settings_screen = null
	shop_screen = null
	wave_shop_screen = null
	# 图鉴: 界面与条目列表都随界面释放, 引用必须一并清空(否则下次访问悬空节点)
	codex_screen = null
	_cx_tab_btns.clear()
	_cx_item_panels.clear()
	_cx_item_subs.clear()
	_cx_ids.clear()
	_cx_scroll = null
	_cx_list_box = null
	_cx_portrait = null
	_cx_name = null
	_cx_tag = null
	_cx_stats = null
	_cx_prose = null
	_cx_scroll_hint = null
	# 书本结构与动效: 界面释放即全部失效, tween 必须 kill 再置 null(照 _frame_pulse_tw 模式)
	if _cx_book_tw != null and _cx_book_tw.is_valid():
		_cx_book_tw.kill()
	_cx_book_tw = null
	if _cx_page_tw != null and _cx_page_tw.is_valid():
		_cx_page_tw.kill()
	_cx_page_tw = null
	if _cx_ribbon_tw != null and _cx_ribbon_tw.is_valid():
		_cx_ribbon_tw.kill()
	_cx_ribbon_tw = null
	_cx_book = null
	_cx_left_page = null
	_cx_right_page = null
	_cx_page_flip = null
	_cx_ribbon = null
	# _cx_closing 必须复位: 否则合书中途被 _clear_all 打断(autopilot/restart)后下次进图鉴输入全被吞
	_cx_closing = false
	_cx_anim_enabled = true
	_cx_flip_dir = 1
	_cx_flip_pages = 1
	_cx_flip_swapped = false
	_cx_flip_sound_at = 1
	_cx_ribbon_to = 0
	_wave_shop_row = null
	_wave_shop_cont_btn = null
	_wave_shop_action_row = null
	_wave_shop_coin_label = null
	_wave_shop_btns.clear()
	_shop_sel = 0
	_shop_focus_row = 0
	_shop_toast = null
	_meta_shop_info = null
	# toast tween 必须 kill 再置 null(同 _cx_*_tw 纪律): 界面已释放而 tween 还在跑,
	# 它的目标节点随 shop_screen 一起 free, 下一帧 tween 步进会打 target freed 错
	if _shop_toast_tween != null and _shop_toast_tween.is_valid():
		_shop_toast_tween.kill()
	_shop_toast_tween = null
	_wave_shop_stat_flow = null
	_wave_shop_stat_empty = null
	_wave_shop_stat_title = null
	_shop_glow_overlay = null
	boss_bar = null
	# 主菜单动效节点随界面释放, 引用清空停止 _process_menu_fx
	_menu_pulse = null
	_menu_glow = null
	_menu_title = null
	# 重开确认框: 盖在主菜单上, 随 _clear_all 一并释放; 引用/选中态必须清空,
	# 否则 _unhandled_input 的 MENU 确认 gate 会判定悬空节点为打开, 永久吞掉菜单输入
	_menu_confirm_screen = null
	_menu_confirm_btns.clear()
	_menu_confirm_sel = 0
	# 升级键盘导航状态: 卡片随界面释放, 引用必须清空, 否则下次 _levelup_move 会访问悬空节点
	_weapon_slots.clear()
	_levelup_cards.clear()
	_levelup_options.clear()
	_levelup_sel = 0
	_levelup_marker = null
	_levelup_frame = null
	_levelup_reroll_btn = null
	_levelup_toast = null
	# 所有 tween 都由 hud.create_tween() 建立, 绑在 hud 上不随卡片/界面释放, 不显式 kill 会一直跑下去
	for t in _card_shake_tws:
		if t != null and t.is_valid():
			t.kill()
	_card_shake_tws.clear()
	if _frame_pulse_tw != null and _frame_pulse_tw.is_valid():
		_frame_pulse_tw.kill()
	_frame_pulse_tw = null
	if _levelup_sel_tw != null and _levelup_sel_tw.is_valid():
		_levelup_sel_tw.kill()
	_levelup_sel_tw = null
	if _levelup_toast_tween != null and _levelup_toast_tween.is_valid():
		_levelup_toast_tween.kill()
	_levelup_toast_tween = null
	# 键盘导航状态随界面释放, 引用/索引一并清空归零(否则下次访问悬空节点)
	_menu_btns.clear()
	_menu_sel = 0
	_result_btns.clear()
	_result_sel = 0
	_meta_shop_back = null
	_meta_shop_sel = 0
	_settings_row = 3
	_settings_col = 0
	_settings_vol_slider = null
	_settings_row_labels.clear()
	_settings_diff_btns.clear()
	_settings_spd_btns.clear()
	_settings_bottom_btns.clear()