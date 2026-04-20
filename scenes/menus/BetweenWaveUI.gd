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
	vbox.offset_left = -330.0
	vbox.offset_top = -180.0
	vbox.offset_right = 330.0
	vbox.offset_bottom = 180.0
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
	_choices_container.add_theme_constant_override("separation", 16)
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
	var weights := _get_rarity_weights(_wave_number)
	var preferred: Array[StringName] = []
	if player.character_data:
		preferred = player.character_data.preferred_upgrades
	var offered := _weighted_sample(all_upgrades, weights, CHOICES_COUNT, preferred)

	var card_font := GameManager.kenney_font()
	for data in offered:
		var btn := Button.new()
		btn.text = "[%s]\n%s\n%s" % [_rarity_name(data.rarity), data.display_name, data.description]
		btn.custom_minimum_size = Vector2(180.0, 110.0)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if card_font:
			btn.add_theme_font_override("font", card_font)
			btn.add_theme_font_size_override("font_size", 14)

		var rarity_col := _rarity_color(data.rarity)
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = rarity_col.darkened(0.55)
		normal_style.border_color = rarity_col
		normal_style.set_border_width_all(2)
		normal_style.set_corner_radius_all(6)
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = rarity_col.darkened(0.3)
		hover_style.border_color = rarity_col.lightened(0.3)
		hover_style.set_border_width_all(2)
		hover_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", hover_style)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)

		btn.pressed.connect(_on_upgrade_chosen.bind(player, data))
		_choices_container.add_child(btn)

# Returns per-rarity weights [Common, Uncommon, Rare, Epic, Legendary]
# linearly scaled by wave progress so higher rarities become more likely over time.
func _get_rarity_weights(wave: int) -> Array[float]:
	var t := clampf(float(wave - 1) / 9.0, 0.0, 1.0)
	var weights: Array[float] = [
		lerpf(60.0, 25.0, t),   # COMMON
		lerpf(25.0, 28.0, t),   # UNCOMMON
		lerpf(12.0, 25.0, t),   # RARE
		lerpf(3.0,  15.0, t),   # EPIC
		lerpf(0.0,  7.0,  t),   # LEGENDARY
	]
	return weights

# Draws `count` unique upgrades from pool, weighted by each item's rarity weight.
# Items whose id appears in `preferred` get 3x weight.
func _weighted_sample(pool: Array[UpgradeData], weights: Array[float], count: int, preferred: Array[StringName] = []) -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	var remaining := pool.duplicate()
	var attempts := 0
	while result.size() < count and remaining.size() > 0 and attempts < 1000:
		attempts += 1
		var total := 0.0
		for item in remaining:
			var w := weights[item.rarity] * (3.0 if item.id in preferred else 1.0)
			total += w
		if total <= 0.0:
			break
		var roll := randf() * total
		var acc := 0.0
		for i in range(remaining.size()):
			var w := weights[remaining[i].rarity] * (3.0 if remaining[i].id in preferred else 1.0)
			acc += w
			if roll <= acc:
				result.append(remaining[i])
				remaining.remove_at(i)
				break
	return result

func _rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.55, 0.55, 0.55)   # COMMON - grey
		1: return Color(0.15, 0.75, 0.3)    # UNCOMMON - green
		2: return Color(0.2,  0.45, 0.95)   # RARE - blue
		3: return Color(0.65, 0.1,  0.95)   # EPIC - purple
		4: return Color(0.95, 0.7,  0.0)    # LEGENDARY - gold
		_: return Color(0.55, 0.55, 0.55)

func _rarity_name(rarity: int) -> String:
	match rarity:
		0: return "COMMON"
		1: return "UNCOMMON"
		2: return "RARE"
		3: return "EPIC"
		4: return "LEGENDARY"
		_: return "COMMON"

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
	ui_closed.emit()
