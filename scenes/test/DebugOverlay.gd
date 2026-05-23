extends CanvasLayer

## DebugOverlay – in-game HUD shown when GameManager.debug_mode is true.
##
## Keyboard shortcuts (active while this node is in the tree):
##   `  – open / close the dev overlay
##   1  – kill all enemies instantly
##   2  – restore all players to full HP & shield
##   3  – skip to next wave
##   4  – give each player +500 scrap
##   5  – toggle god mode on/off

# Set from Game.gd immediately after add_child()
var _game: Node = null
var _wave_manager: Node = null        # WaveManager
var _players_ref: Array = []          # Array[Player]
var _enemies_container: Node = null

var _panel: PanelContainer
var _label: Label
var _godmode_lbl: Label
var _tab_btn: Button
var _visible_toggle: bool = false

func _ready() -> void:
	layer = 128  # render above everything

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(root)

	# Always-visible DEV tab in the top-left corner
	_tab_btn = Button.new()
	_tab_btn.text = "DEV"
	_tab_btn.position = Vector2(10.0, 10.0)
	_tab_btn.custom_minimum_size = Vector2(50.0, 24.0)
	_tab_btn.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
	_tab_btn.pressed.connect(_toggle_panel)
	root.add_child(_tab_btn)

	_panel = PanelContainer.new()
	_panel.position = Vector2(10.0, 40.0)
	_panel.visible = false
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "[ DEBUG ]  `=close  1=kill  2=heal  3=skip  4=scrap  5=godmode"
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
	vbox.add_child(title)

	_label = Label.new()
	_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(_label)

	_godmode_lbl = Label.new()
	_godmode_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	vbox.add_child(_godmode_lbl)

	_refresh_ui()

func _process(_delta: float) -> void:
	_refresh_ui()

func _refresh_ui() -> void:
	if not _label:
		return

	var wave_idx: int = _wave_manager.current_wave_index + 1 if _wave_manager else 0
	var enemy_count: int = _enemies_container.get_child_count() if _enemies_container else 0
	var fps: int = int(Engine.get_frames_per_second())

	var player_info := ""
	for i in _players_ref.size():
		var p = _players_ref[i]
		if is_instance_valid(p):
			player_info += "  P%d  HP: %d/%d" % [i + 1, int(p.current_health), int(p.max_health)]
			if p.shield_max > 0.0:
				player_info += "  Shield: %d/%d" % [int(p.current_shield), int(p.shield_max)]
			player_info += "\n"

	_label.text = "Wave: %d  |  Enemies: %d  |  FPS: %d\n%s" % [
		wave_idx, enemy_count, fps, player_info.strip_edges()
	]
	_godmode_lbl.text = "GOD MODE: %s" % ("ON" if GameManager.debug_god_mode else "off")
	_godmode_lbl.add_theme_color_override(
		"font_color",
		Color(0.3, 1.0, 0.3) if GameManager.debug_god_mode else Color(0.5, 0.5, 0.5)
	)

func _toggle_panel() -> void:
	_visible_toggle = not _visible_toggle
	_panel.visible = _visible_toggle

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	# Backtick always toggles the overlay open/closed
	if event.keycode == KEY_QUOTELEFT:
		_toggle_panel()
		return
	# Number keys only work while the overlay is open
	if not _visible_toggle:
		return
	match event.keycode:
		KEY_1:
			_kill_all_enemies()
		KEY_2:
			_heal_all_players()
		KEY_3:
			_skip_wave()
		KEY_4:
			_add_scrap()
		KEY_5:
			GameManager.debug_god_mode = not GameManager.debug_god_mode

func _kill_all_enemies() -> void:
	if not _enemies_container:
		return
	for child in _enemies_container.get_children():
		if child.has_method("die"):
			child.die()
		else:
			child.queue_free()

func _heal_all_players() -> void:
	for p in _players_ref:
		if is_instance_valid(p):
			p.current_health = p.max_health
			if p.shield_max > 0.0:
				p.current_shield = p.shield_max
			p.health_changed.emit(p.current_health, p.max_health)
			p.shield_changed.emit(p.current_shield, p.shield_max)

func _skip_wave() -> void:
	if not _wave_manager:
		return
	# Kill remaining enemies first so the wave-cleared logic fires cleanly
	_kill_all_enemies()

func _add_scrap() -> void:
	for p in _players_ref:
		if is_instance_valid(p):
			p.scrap += 500
			p.scrap_changed.emit(p.scrap)
