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
	player.leveled_up.connect(func(lvl): _update_level(panel, lvl); _update_power(panel, player))
	player.scrap_changed.connect(func(amount): _update_scrap(panel, amount); _update_power(panel, player))
	player.died.connect(func(): _mark_dead(panel))
	player.revived.connect(func(): _mark_alive(panel, player))
	player.ability_cooldown_changed.connect(func(ratio): _update_ability(panel, ratio))
	_update_power(panel, player)

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

	var ability_bar := ProgressBar.new()
	ability_bar.name = "AbilityBar"
	ability_bar.custom_minimum_size = Vector2(220, 8)
	ability_bar.max_value = 1.0
	ability_bar.value = 1.0
	ability_bar.modulate = Color(0.2, 1.0, 0.4)
	ability_bar.visible = false
	vbox.add_child(ability_bar)

	var power_hbox := HBoxContainer.new()
	power_hbox.name = "PowerHBox"
	power_hbox.add_theme_constant_override("separation", 6)
	vbox.add_child(power_hbox)

	var power_label := Label.new()
	power_label.name = "PowerLabel"
	power_label.text = "Pwr Lv 1"
	power_label.modulate = Color(1.0, 0.82, 0.2)
	if panel_font:
		power_label.add_theme_font_override("font", panel_font)
		power_label.add_theme_font_size_override("font_size", 14)
	power_hbox.add_child(power_label)

	var power_bar := ProgressBar.new()
	power_bar.name = "PowerBar"
	power_bar.custom_minimum_size = Vector2(120, 14)
	power_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power_bar.max_value = 1.0
	power_bar.value = 0.0
	power_bar.modulate = Color(1.0, 0.75, 0.1)
	power_hbox.add_child(power_bar)

	return vbox

func _mark_dead(panel: Control) -> void:
	panel.modulate = Color(0.4, 0.4, 0.4, 0.7)
	var lbl := panel.get_node_or_null("LevelLabel") as Label
	if lbl:
		lbl.text = "-- DEAD --"

func _mark_alive(panel: Control, player: Player) -> void:
	panel.modulate = Color.WHITE
	var lbl := panel.get_node_or_null("LevelLabel") as Label
	if lbl and is_instance_valid(player):
		lbl.text = "Lv %d" % player.level

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

func _update_ability(panel: Control, ratio: float) -> void:
	var bar := panel.get_node_or_null("AbilityBar") as ProgressBar
	if not bar:
		return
	bar.visible = true
	bar.value = 1.0 - ratio
	bar.modulate = Color(0.2, 1.0, 0.4) if ratio <= 0.0 else Color(1.0, 0.7, 0.1)

func _update_power(panel: Control, player: Player) -> void:
	if not is_instance_valid(player):
		return
	player.check_and_apply_power_level_bonuses()
	var score := PlayerPowerCalculator.calc_display_power(player)
	var lv    := PlayerPowerCalculator.power_to_level(score)
	var prog  := PlayerPowerCalculator.power_level_progress(score)
	var lbl   := panel.get_node_or_null("PowerHBox/PowerLabel") as Label
	var bar   := panel.get_node_or_null("PowerHBox/PowerBar") as ProgressBar
	if lbl:
		lbl.text = "Pwr Lv %d" % lv
	if bar:
		bar.value = prog

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
		var secs := ceili(remaining)
		_timer_label.text = "WAVE ENDS: %ds" % secs

func show_event_banner(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.modulate.a = 0.0
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left = -300.0
	lbl.offset_right = 300.0
	lbl.offset_top = -28.0
	lbl.offset_bottom = 28.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bfont := GameManager.kenney_font()
	if bfont:
		lbl.add_theme_font_override("font", bfont)
		lbl.add_theme_font_size_override("font_size", 38)
	lbl.scale = Vector2(0.4, 0.4)
	lbl.pivot_offset = Vector2(300.0, 28.0)

	# Mount on a fresh CanvasLayer so it always renders above HUD
	var cl := CanvasLayer.new()
	cl.layer = 10
	get_tree().current_scene.add_child(cl)
	cl.add_child(lbl)

	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.25)
	tw.tween_property(lbl, "scale", Vector2(1.1, 1.1), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.1)
	tw.chain().tween_interval(2.0)
	tw.chain().tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(cl.queue_free)
