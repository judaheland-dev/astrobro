extends CanvasLayer

## BetweenWaveUI - builds its own UI nodes. Shown after each wave for upgrade selection.

signal ui_closed()

const CHOICES_COUNT: int = 3

var _players: Array[Player] = []
var _current_player_index: int = 0
var _wave_number: int = 0
var _wave_manager: WaveManager = null

var _title_label: Label
var _choices_container: HBoxContainer
var _continue_button: Button

func _ready() -> void:
	# Must keep processing while the game tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -300.0
	vbox.offset_top = -150.0
	vbox.offset_right = 300.0
	vbox.offset_bottom = 150.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_font := GameManager.kenney_font()
	if title_font:
		_title_label.add_theme_font_override("font", title_font)
		_title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_title_label)

	_choices_container = HBoxContainer.new()
	_choices_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_choices_container)

	_continue_button = Button.new()
	_continue_button.text = "Skip"
	_continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(_continue_button)

func show_for_players(players: Array[Player], wave_number: int, wave_manager: WaveManager) -> void:
	_players = players
	_wave_number = wave_number
	_wave_manager = wave_manager
	_current_player_index = 0
	visible = true
	_show_level_up_for_player()

func _show_level_up_for_player() -> void:
	_title_label.text = "Wave %d cleared!\nPlayer %d - Choose an upgrade:" % [_wave_number, _current_player_index + 1]
	_populate_choices(_players[_current_player_index])

func _populate_choices(player: Player) -> void:
	for child in _choices_container.get_children():
		child.queue_free()

	var all_upgrades := _load_all_upgrades()
	all_upgrades.shuffle()
	var offered := all_upgrades.slice(0, CHOICES_COUNT)

	for data in offered:
		var btn := Button.new()
		btn.text = "%s\n%s" % [data.display_name, data.description]
		btn.custom_minimum_size = Vector2(160.0, 80.0)
		btn.pressed.connect(_on_upgrade_chosen.bind(player, data))
		_choices_container.add_child(btn)

func _load_all_upgrades() -> Array[UpgradeData]:
	var upgrades: Array[UpgradeData] = []
	var dir := DirAccess.open("res://resources/upgrades")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				var res = ResourceLoader.load("res://resources/upgrades/" + fname)
				if res is UpgradeData:
					upgrades.append(res)
			fname = dir.get_next()
	return upgrades

func _on_upgrade_chosen(player: Player, data: UpgradeData) -> void:
	AudioManager.play_ui_click()
	player.apply_upgrade(data)
	_current_player_index += 1
	if _current_player_index < _players.size():
		_show_level_up_for_player()
	else:
		_close()

func _on_continue_pressed() -> void:
	AudioManager.play_ui_click()
	_close()

func _close() -> void:
	visible = false
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.PLAYING)
	if _wave_manager:
		_wave_manager.next_wave()
	ui_closed.emit()
