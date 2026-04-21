extends CanvasLayer

## HUD - builds its own UI nodes in code. No .tscn required.

var _wave_label: Label
var _timer_label: Label
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

	_timer_label = Label.new()
	_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_timer_label.offset_left = -120.0
	_timer_label.offset_top = 12.0
	_timer_label.offset_right = 120.0
	_timer_label.offset_bottom = 52.0
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.modulate = Color(1.0, 0.7, 0.2)
	_timer_label.visible = false
	if hud_font:
		_timer_label.add_theme_font_override("font", hud_font)
		_timer_label.add_theme_font_size_override("font_size", 28)
	root.add_child(_timer_label)

func register_player(player: Player) -> void:
	var panel := _create_player_panel(player.player_index)
	_players_vbox.add_child(panel)
	player.health_changed.connect(func(cur, mx): _update_health(panel, cur, mx))
	player.shield_changed.connect(func(cur, mx): _update_shield(panel, cur, mx))
	player.xp_gained.connect(func(xp, threshold): _update_xp(panel, xp, threshold))
	player.leveled_up.connect(func(lvl): _update_level(panel, lvl))
	player.scrap_changed.connect(func(amount): _update_scrap(panel, amount))
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

	var shield_bar := ProgressBar.new()
	shield_bar.name = "ShieldBar"
	shield_bar.custom_minimum_size = Vector2(220, 8)
	shield_bar.modulate = Color(0.3, 0.7, 1.0)
	shield_bar.visible = false
	vbox.add_child(shield_bar)

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

	var scrap_label := Label.new()
	scrap_label.name = "ScrapLabel"
	scrap_label.text = "Scrap: 0"
	scrap_label.modulate = Color(0.3, 0.9, 1.0)
	if panel_font:
		scrap_label.add_theme_font_override("font", panel_font)
		scrap_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(scrap_label)

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

func _update_shield(panel: Control, current: float, maximum: float) -> void:
	var bar := panel.get_node_or_null("ShieldBar") as ProgressBar
	if bar:
		bar.visible = maximum > 0.0
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

func _update_scrap(panel: Control, amount: int) -> void:
	var lbl := panel.get_node_or_null("ScrapLabel") as Label
	if lbl:
		lbl.text = "Scrap: %d" % amount

func update_wave(current: int, total: int) -> void:
	if _wave_label:
		if total == 0:
			_wave_label.text = "Wave %d" % current
		else:
			_wave_label.text = "Wave %d / %d" % [current, total]

func update_timer(remaining: float) -> void:
	if not _timer_label:
		return
	if remaining <= 0.0:
		_timer_label.visible = false
	else:
		_timer_label.visible = true
		var secs := int(remaining) + 1
		_timer_label.text = "WAVE ENDS: %ds" % secs
