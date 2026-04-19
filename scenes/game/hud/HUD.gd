extends CanvasLayer

## HUD - builds its own UI nodes in code. No .tscn required.

var _wave_label: Label
var _coin_label: Label
var _players_vbox: VBoxContainer

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_players_vbox = VBoxContainer.new()
	_players_vbox.position = Vector2(12.0, 12.0)
	root.add_child(_players_vbox)

	var hud_font := GameManager.kenney_font()

	_wave_label = Label.new()
	_wave_label.text = "Wave 0 / 0"
	_wave_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_wave_label.offset_left = -220.0
	_wave_label.offset_top = 12.0
	_wave_label.offset_right = -12.0
	_wave_label.offset_bottom = 48.0
	if hud_font:
		_wave_label.add_theme_font_override("font", hud_font)
		_wave_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_wave_label)

	_coin_label = Label.new()
	_coin_label.text = "Coins: 0"
	_coin_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_coin_label.offset_left = -220.0
	_coin_label.offset_top = 52.0
	_coin_label.offset_right = -12.0
	_coin_label.offset_bottom = 88.0
	if hud_font:
		_coin_label.add_theme_font_override("font", hud_font)
		_coin_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_coin_label)

func register_player(player: Player) -> void:
	var panel := _create_player_panel(player.player_index)
	_players_vbox.add_child(panel)
	player.health_changed.connect(func(cur, mx): _update_health(panel, cur, mx))
	player.xp_gained.connect(func(xp, threshold): _update_xp(panel, xp, threshold))
	player.leveled_up.connect(func(lvl): _update_level(panel, lvl))
	player.died.connect(func(): _mark_dead(panel))

func _create_player_panel(index: int) -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "P%d" % (index + 1)

	var panel_font := GameManager.kenney_font()

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.text = "Player %d" % (index + 1)
	if panel_font:
		name_label.add_theme_font_override("font", panel_font)
		name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(name_label)

	var hp_bar := ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.custom_minimum_size = Vector2(220, 20)
	vbox.add_child(hp_bar)

	var xp_bar := ProgressBar.new()
	xp_bar.name = "XPBar"
	xp_bar.custom_minimum_size = Vector2(220, 12)
	vbox.add_child(xp_bar)

	var level_label := Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "Lv 1"
	if panel_font:
		level_label.add_theme_font_override("font", panel_font)
		level_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(level_label)

	return vbox

func _mark_dead(panel: Control) -> void:
	panel.modulate = Color(0.4, 0.4, 0.4, 0.7)
	var lbl := panel.get_node_or_null("LevelLabel") as Label
	if lbl:
		lbl.text = "-- DEAD --"

func _update_health(panel: Control, current: float, maximum: float) -> void:
	var bar := panel.get_node_or_null("HPBar") as ProgressBar
	if bar:
		bar.max_value = maximum
		bar.value = current

func _update_xp(panel: Control, xp: int, threshold: int) -> void:
	var bar := panel.get_node_or_null("XPBar") as ProgressBar
	if bar:
		bar.max_value = threshold
		bar.value = xp

func _update_level(panel: Control, level: int) -> void:
	var lbl := panel.get_node_or_null("LevelLabel") as Label
	if lbl:
		lbl.text = "Lv %d" % level

func update_wave(current: int, total: int) -> void:
	if _wave_label:
		_wave_label.text = "Wave %d / %d" % [current, total]

func _process(_delta: float) -> void:
	if _coin_label:
		_coin_label.text = "Coins: %d" % MetaProgression.get_coins()
