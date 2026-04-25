extends CanvasLayer

## OverlordShopUI - shown between waves for the Overlord to buy enemies,
## assign them to face-button slots, and purchase global upgrades.

signal ui_closed()

var _overlord_state: OverlordState = null
var _root: Control = null
var _budget_label: Label = null
var _wave_label: Label = null
var _roster_container: VBoxContainer = null
var _loadout_slots: Array = []  # Array of {panel, label, btn, enemy_id}
var _upgrade_container: VBoxContainer = null
var _enemy_rows: Dictionary = {}  # enemy_id -> {count_label, buy_btn, sell_btn, assign_btns}
var _ready_btn: Button = null
var _active_assign_slot: int = -1  # which loadout slot is being assigned

# Track which enemies are available for purchase (unlocked progressively)
var _available_enemies: Array[StringName] = []
var _current_wave: int = 0

func _ready() -> void:
	layer = 5  # Same as BetweenWaveUI
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func show_shop(state: OverlordState, wave_number: int) -> void:
	_overlord_state = state
	_current_wave = wave_number
	_available_enemies = _get_unlocked_enemies(wave_number)
	_build_ui()
	visible = true

func _get_unlocked_enemies(wave: int) -> Array[StringName]:
	## Progressive unlock based on wave number.
	var pool: Array[StringName] = [&"grunt", &"speeder"]
	if wave >= 2:
		pool.append(&"exploder")
	if wave >= 3:
		pool.append(&"tracker")
		pool.append(&"shielded")
	if wave >= 4:
		pool.append(&"sniper")
		pool.append(&"ranger")
	if wave >= 5:
		pool.append(&"tank")
		pool.append(&"heavy_ranger")
	if wave >= 7:
		pool.append(&"sentinel")
		pool.append(&"acid_ranger")
	if wave >= 9:
		pool.append(&"brute")
	if wave >= 11:
		pool.append(&"corruptor")
	return pool

func _build_ui() -> void:
	# Clear previous UI
	for c in get_children():
		c.queue_free()
	_enemy_rows.clear()
	_loadout_slots.clear()

	var font := GameManager.kenney_font()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Semi-transparent background
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.08, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# Main layout: 3 columns
	var main_hbox := HBoxContainer.new()
	main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hbox.offset_left = 40.0
	main_hbox.offset_top = 60.0
	main_hbox.offset_right = -40.0
	main_hbox.offset_bottom = -20.0
	main_hbox.add_theme_constant_override("separation", 20)
	_root.add_child(main_hbox)

	# --- Title bar ---
	var title := Label.new()
	title.text = "OVERLORD PREPARATION - Wave %d" % (_current_wave + 1)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 12.0
	title.offset_bottom = 50.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	if font:
		title.add_theme_font_override("font", font)
		title.add_theme_font_size_override("font_size", 28)
	_root.add_child(title)

	# Budget display
	_budget_label = Label.new()
	_budget_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_budget_label.offset_left = -280.0
	_budget_label.offset_top = 14.0
	_budget_label.offset_right = -40.0
	_budget_label.offset_bottom = 46.0
	_budget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_budget_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	if font:
		_budget_label.add_theme_font_override("font", font)
		_budget_label.add_theme_font_size_override("font_size", 22)
	_root.add_child(_budget_label)
	_update_budget_display()

	# === LEFT PANEL: Enemy Roster ===
	var left_panel := _build_panel("ENEMY ROSTER", font)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.4
	main_hbox.add_child(left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)

	_roster_container = VBoxContainer.new()
	_roster_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_container.add_theme_constant_override("separation", 4)
	left_scroll.add_child(_roster_container)

	for eid in _available_enemies:
		_build_enemy_row(eid, font)

	# === CENTER PANEL: Loadout ===
	var center_panel := _build_panel("LOADOUT", font)
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.size_flags_stretch_ratio = 0.8
	main_hbox.add_child(center_panel)

	var loadout_vbox := VBoxContainer.new()
	loadout_vbox.add_theme_constant_override("separation", 8)
	loadout_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_panel.add_child(loadout_vbox)

	var button_labels: Array[String] = ["A", "B", "X", "Y"]
	var button_colors: Array[Color] = [
		Color(0.2, 0.8, 0.2),
		Color(0.8, 0.2, 0.2),
		Color(0.2, 0.5, 1.0),
		Color(1.0, 0.8, 0.1),
	]

	for i in 4:
		_build_loadout_slot(loadout_vbox, i, button_labels[i], button_colors[i], font)

	var loadout_hint := Label.new()
	loadout_hint.text = "Click slot then click\nan enemy to assign"
	loadout_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loadout_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	if font:
		loadout_hint.add_theme_font_override("font", font)
		loadout_hint.add_theme_font_size_override("font_size", 11)
	loadout_vbox.add_child(loadout_hint)

	# === RIGHT PANEL: Upgrades ===
	var right_panel := _build_panel("UPGRADES", font)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	main_hbox.add_child(right_panel)

	_upgrade_container = VBoxContainer.new()
	_upgrade_container.add_theme_constant_override("separation", 6)
	_upgrade_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(_upgrade_container)

	for i in OverlordState.UPGRADES.size():
		_build_upgrade_row(i, font)

	# Current stats summary
	var stats_label := Label.new()
	stats_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	if font:
		stats_label.add_theme_font_override("font", font)
		stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.text = _get_stats_text()
	_upgrade_container.add_child(stats_label)

	# === Ready Button ===
	_ready_btn = Button.new()
	_ready_btn.text = "READY"
	_ready_btn.custom_minimum_size = Vector2(200, 50)
	_ready_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ready_btn.offset_left = -260.0
	_ready_btn.offset_top = -70.0
	_ready_btn.offset_right = -40.0
	_ready_btn.offset_bottom = -12.0
	_ready_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	if font:
		_ready_btn.add_theme_font_override("font", font)
		_ready_btn.add_theme_font_size_override("font_size", 22)
	_ready_btn.pressed.connect(_on_ready_pressed)
	_root.add_child(_ready_btn)
	_ready_btn.grab_focus()

func _build_panel(title_text: String, font: FontFile) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.text = title_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	if font:
		header.add_theme_font_override("font", font)
		header.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	return vbox

func _build_enemy_row(enemy_id: StringName, font: FontFile) -> void:
	var cost: int = OverlordState.ENEMY_COSTS.get(enemy_id, 0)
	var owned: int = _overlord_state.roster.get(enemy_id, 0)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.custom_minimum_size = Vector2(0, 32)
	_roster_container.add_child(hbox)

	# Enemy name
	var name_label := Label.new()
	name_label.text = String(enemy_id).capitalize()
	name_label.custom_minimum_size = Vector2(100, 0)
	if font:
		name_label.add_theme_font_override("font", font)
		name_label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(name_label)

	# Cost
	var cost_label := Label.new()
	cost_label.text = "%d" % cost
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	cost_label.custom_minimum_size = Vector2(35, 0)
	if font:
		cost_label.add_theme_font_override("font", font)
		cost_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(cost_label)

	# Count owned
	var count_label := Label.new()
	count_label.text = "x%d" % owned
	count_label.custom_minimum_size = Vector2(35, 0)
	if font:
		count_label.add_theme_font_override("font", font)
		count_label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(count_label)

	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "+"
	buy_btn.custom_minimum_size = Vector2(32, 28)
	buy_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	buy_btn.pressed.connect(_on_buy_enemy.bind(enemy_id))
	hbox.add_child(buy_btn)

	# Sell button
	var sell_btn := Button.new()
	sell_btn.text = "-"
	sell_btn.custom_minimum_size = Vector2(32, 28)
	sell_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	sell_btn.pressed.connect(_on_sell_enemy.bind(enemy_id))
	hbox.add_child(sell_btn)

	# Assign button (assign to active loadout slot)
	var assign_btn := Button.new()
	assign_btn.text = "Assign"
	assign_btn.custom_minimum_size = Vector2(64, 28)
	assign_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	assign_btn.pressed.connect(_on_assign_enemy.bind(enemy_id))
	if font:
		assign_btn.add_theme_font_override("font", font)
		assign_btn.add_theme_font_size_override("font_size", 10)
	hbox.add_child(assign_btn)

	_enemy_rows[enemy_id] = {
		"count_label": count_label,
		"buy_btn": buy_btn,
		"sell_btn": sell_btn,
		"assign_btn": assign_btn,
	}

func _build_loadout_slot(parent: VBoxContainer, index: int, btn_text: String, btn_color: Color, font: FontFile) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	# Button indicator
	var btn_label := Label.new()
	btn_label.text = "[%s]" % btn_text
	btn_label.add_theme_color_override("font_color", btn_color)
	btn_label.custom_minimum_size = Vector2(40, 0)
	if font:
		btn_label.add_theme_font_override("font", font)
		btn_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(btn_label)

	# Current assignment label
	var slot_label := Label.new()
	var eid: StringName = _overlord_state.loadout[index]
	slot_label.text = String(eid).capitalize() if eid != &"" else "(empty)"
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font:
		slot_label.add_theme_font_override("font", font)
		slot_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(slot_label)

	# Select slot button
	var select_btn := Button.new()
	select_btn.text = "Select"
	select_btn.custom_minimum_size = Vector2(64, 28)
	select_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	select_btn.pressed.connect(_on_select_slot.bind(index))
	hbox.add_child(select_btn)

	# Clear slot button
	var clear_btn := Button.new()
	clear_btn.text = "X"
	clear_btn.custom_minimum_size = Vector2(28, 28)
	clear_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	clear_btn.pressed.connect(_on_clear_slot.bind(index))
	hbox.add_child(clear_btn)

	_loadout_slots.append({
		"label": slot_label,
		"select_btn": select_btn,
		"btn_label": btn_label,
		"index": index,
	})

func _build_upgrade_row(index: int, font: FontFile) -> void:
	var upgrade: Array = OverlordState.UPGRADES[index]
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	_upgrade_container.add_child(hbox)

	var name_label := Label.new()
	name_label.text = upgrade[0]
	name_label.custom_minimum_size = Vector2(120, 0)
	if font:
		name_label.add_theme_font_override("font", font)
		name_label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = "%d" % upgrade[1]
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	cost_label.custom_minimum_size = Vector2(35, 0)
	if font:
		cost_label.add_theme_font_override("font", font)
		cost_label.add_theme_font_size_override("font_size", 12)
	hbox.add_child(cost_label)

	var desc_label := Label.new()
	desc_label.text = upgrade[4]
	desc_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font:
		desc_label.add_theme_font_override("font", font)
		desc_label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(desc_label)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(50, 28)
	buy_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	buy_btn.pressed.connect(_on_buy_upgrade.bind(index))
	hbox.add_child(buy_btn)

func _on_buy_enemy(enemy_id: StringName) -> void:
	AudioManager.play_ui_click()
	if _overlord_state.buy_enemy(enemy_id):
		_refresh_roster_display()
		_update_budget_display()

func _on_sell_enemy(enemy_id: StringName) -> void:
	AudioManager.play_ui_click()
	if _overlord_state.sell_enemy(enemy_id):
		_refresh_roster_display()
		_update_budget_display()

func _on_assign_enemy(enemy_id: StringName) -> void:
	AudioManager.play_ui_click()
	if _active_assign_slot >= 0 and _active_assign_slot < 4:
		_overlord_state.loadout[_active_assign_slot] = enemy_id
		_refresh_loadout_display()
		_active_assign_slot = -1
		_update_slot_highlights()

func _on_select_slot(index: int) -> void:
	AudioManager.play_ui_click()
	_active_assign_slot = index
	_update_slot_highlights()

func _on_clear_slot(index: int) -> void:
	AudioManager.play_ui_click()
	_overlord_state.loadout[index] = &""
	_refresh_loadout_display()

func _on_buy_upgrade(index: int) -> void:
	AudioManager.play_ui_click()
	if _overlord_state.buy_upgrade(index):
		_update_budget_display()
		# Rebuild upgrade panel to reflect new stats
		_refresh_stats_display()

func _on_ready_pressed() -> void:
	AudioManager.play_ui_click()
	visible = false
	ui_closed.emit()

func _update_budget_display() -> void:
	if _budget_label:
		_budget_label.text = "Budget: %d" % _overlord_state.budget

func _refresh_roster_display() -> void:
	for eid in _enemy_rows:
		var row: Dictionary = _enemy_rows[eid]
		var count: int = _overlord_state.roster.get(eid, 0)
		row["count_label"].text = "x%d" % count

func _refresh_loadout_display() -> void:
	for slot_data in _loadout_slots:
		var idx: int = slot_data["index"]
		var eid: StringName = _overlord_state.loadout[idx]
		slot_data["label"].text = String(eid).capitalize() if eid != &"" else "(empty)"

func _update_slot_highlights() -> void:
	for slot_data in _loadout_slots:
		var idx: int = slot_data["index"]
		var btn_label: Label = slot_data["btn_label"]
		if idx == _active_assign_slot:
			btn_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		else:
			# Restore original color
			var colors: Array[Color] = [
				Color(0.2, 0.8, 0.2),
				Color(0.8, 0.2, 0.2),
				Color(0.2, 0.5, 1.0),
				Color(1.0, 0.8, 0.1),
			]
			btn_label.add_theme_color_override("font_color", colors[idx])

func _refresh_stats_display() -> void:
	# Update the stats summary label at the bottom of upgrades panel
	# Find it - it's the last child of _upgrade_container that is a Label
	for i in range(_upgrade_container.get_child_count() - 1, -1, -1):
		var child := _upgrade_container.get_child(i)
		if child is Label and child.text.begins_with("HP:"):
			child.text = _get_stats_text()
			break

func _get_stats_text() -> String:
	return "HP: x%.0f%%  Armor: +%.0f  Speed: x%.0f%%\nSpawn CD: x%.0f%%  Income: x%.0f%%" % [
		_overlord_state.hp_mult * 100.0,
		_overlord_state.armor_bonus,
		_overlord_state.speed_mult * 100.0,
		_overlord_state.spawn_cooldown_mult * 100.0,
		_overlord_state.income_mult * 100.0,
	]
