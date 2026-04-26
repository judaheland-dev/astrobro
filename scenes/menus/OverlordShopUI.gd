extends CanvasLayer

## OverlordShopUI - between-wave shop for the Overlord.
## Two-column layout: Enemy Roster (left) + Upgrades (right).
## Loadout strip at bottom showing button sequences.
## Assignment: click Assign -> press gamepad buttons one-at-a-time.

signal ui_closed()

var _overlord_state: OverlordState = null
var _root: Control = null
var _budget_label: Label = null
var _roster_container: VBoxContainer = null
var _upgrade_container: VBoxContainer = null
var _loadout_container: HBoxContainer = null
var _enemy_rows: Dictionary = {}  # enemy_id -> row dict
var _ready_btn: Button = null

# Assignment mode state
var _assigning_enemy: StringName = &""  # which enemy is being assigned, or &"" for none
var _assign_overlay: PanelContainer = null
var _assign_remaining_label: Label = null

var _available_enemies: Array[StringName] = []
var _current_wave: int = 0
var _font: FontFile = null

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func show_shop(state: OverlordState, wave_number: int) -> void:
	_overlord_state = state
	_current_wave = wave_number
	_available_enemies = _get_unlocked_enemies(wave_number)
	_assigning_enemy = &""
	_build_ui()
	visible = true

func _get_unlocked_enemies(wave: int) -> Array[StringName]:
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

# ---------------------------------------------------------------------------
# Input — captures gamepad presses during assignment mode
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _assigning_enemy == &"":
		return
	if not visible:
		return
	if event is InputEventJoypadButton and event.pressed:
		var joy_btn: int = event.button_index
		var def_idx: int = _overlord_state.joy_button_to_def_index(joy_btn)
		if def_idx < 0:
			return  # not a deploy button
		get_viewport().set_input_as_handled()
		if _overlord_state.assign_to_button(def_idx, _assigning_enemy):
			AudioManager.play_ui_click()
			_refresh_all()
			# Check if all units assigned
			if _overlord_state.get_unassigned_count(_assigning_enemy) <= 0:
				_end_assign_mode()
			else:
				_update_assign_overlay()

# ---------------------------------------------------------------------------
# Build UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	_enemy_rows.clear()
	_assign_overlay = null

	_font = GameManager.kenney_font()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.08, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# Title
	var title := Label.new()
	title.text = "OVERLORD PREP - Wave %d" % (_current_wave + 1)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 8.0
	title.offset_bottom = 46.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	if _font:
		title.add_theme_font_override("font", _font)
		title.add_theme_font_size_override("font_size", 26)
	_root.add_child(title)

	# Budget
	_budget_label = Label.new()
	_budget_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_budget_label.offset_left = -300.0
	_budget_label.offset_top = 10.0
	_budget_label.offset_right = -30.0
	_budget_label.offset_bottom = 42.0
	_budget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_budget_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	if _font:
		_budget_label.add_theme_font_override("font", _font)
		_budget_label.add_theme_font_size_override("font_size", 22)
	_root.add_child(_budget_label)
	_update_budget_display()

	# Two-column layout: Roster (left) + Upgrades (right)
	var main_hbox := HBoxContainer.new()
	main_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_hbox.offset_left = 30.0
	main_hbox.offset_top = 52.0
	main_hbox.offset_right = -30.0
	main_hbox.offset_bottom = -160.0  # leave room for loadout strip
	main_hbox.add_theme_constant_override("separation", 20)
	_root.add_child(main_hbox)

	# === LEFT: Enemy Roster ===
	var left_panel := _build_panel("ENEMY ROSTER")
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.5
	main_hbox.add_child(left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(left_scroll)

	_roster_container = VBoxContainer.new()
	_roster_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_container.add_theme_constant_override("separation", 4)
	left_scroll.add_child(_roster_container)

	for eid in _available_enemies:
		_build_enemy_row(eid)

	# === RIGHT: Upgrades ===
	var right_panel := _build_panel("UPGRADES")
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	main_hbox.add_child(right_panel)

	_upgrade_container = VBoxContainer.new()
	_upgrade_container.add_theme_constant_override("separation", 6)
	_upgrade_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(_upgrade_container)

	for i in OverlordState.UPGRADES.size():
		_build_upgrade_row(i)

	# Stats summary
	var stats_label := Label.new()
	stats_label.name = "StatsLabel"
	stats_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	if _font:
		stats_label.add_theme_font_override("font", _font)
		stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.text = _get_stats_text()
	_upgrade_container.add_child(stats_label)

	# === BOTTOM: Loadout Strip ===
	_build_loadout_strip()

	# === Ready Button ===
	_ready_btn = Button.new()
	_ready_btn.text = "READY"
	_ready_btn.custom_minimum_size = Vector2(200, 50)
	_ready_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ready_btn.offset_left = -250.0
	_ready_btn.offset_top = -60.0
	_ready_btn.offset_right = -30.0
	_ready_btn.offset_bottom = -6.0
	_ready_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	if _font:
		_ready_btn.add_theme_font_override("font", _font)
		_ready_btn.add_theme_font_size_override("font_size", 22)
	_ready_btn.pressed.connect(_on_ready_pressed)
	_root.add_child(_ready_btn)
	_ready_btn.grab_focus()

func _build_panel(title_text: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = title_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	if _font:
		header.add_theme_font_override("font", _font)
		header.add_theme_font_size_override("font_size", 20)
	vbox.add_child(header)

	var sep := HSeparator.new()
	vbox.add_child(sep)
	return vbox

# ---------------------------------------------------------------------------
# Enemy Row
# ---------------------------------------------------------------------------

func _build_enemy_row(enemy_id: StringName) -> void:
	var cost: int = OverlordState.ENEMY_COSTS.get(enemy_id, 0)
	var owned: int = _overlord_state.roster.get(enemy_id, 0)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.custom_minimum_size = Vector2(0, 38)
	_roster_container.add_child(hbox)

	# Ship icon
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(32, 32)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var spr_path: String = OverlordState.ENEMY_SPRITES.get(enemy_id, "")
	if spr_path != "" and ResourceLoader.exists(spr_path):
		icon.texture = load(spr_path)
	hbox.add_child(icon)

	# Name
	var name_label := Label.new()
	name_label.text = String(enemy_id).capitalize()
	name_label.custom_minimum_size = Vector2(110, 0)
	if _font:
		name_label.add_theme_font_override("font", _font)
		name_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(name_label)

	# Cost
	var cost_label := Label.new()
	cost_label.text = "%d" % cost
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	cost_label.custom_minimum_size = Vector2(36, 0)
	if _font:
		cost_label.add_theme_font_override("font", _font)
		cost_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(cost_label)

	# Owned count
	var count_label := Label.new()
	count_label.text = "x%d" % owned
	count_label.custom_minimum_size = Vector2(36, 0)
	if _font:
		count_label.add_theme_font_override("font", _font)
		count_label.add_theme_font_size_override("font_size", 16)
	hbox.add_child(count_label)

	# Assignment status label (e.g. "[A]x2 [B]x1  1 free")
	var assign_status := Label.new()
	assign_status.custom_minimum_size = Vector2(140, 0)
	assign_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assign_status.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	if _font:
		assign_status.add_theme_font_override("font", _font)
		assign_status.add_theme_font_size_override("font_size", 12)
	hbox.add_child(assign_status)

	# Buy (+)
	var buy_btn := Button.new()
	buy_btn.text = "+"
	buy_btn.custom_minimum_size = Vector2(36, 34)
	buy_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	buy_btn.pressed.connect(_on_buy_enemy.bind(enemy_id))
	if _font:
		buy_btn.add_theme_font_override("font", _font)
		buy_btn.add_theme_font_size_override("font_size", 16)
	hbox.add_child(buy_btn)

	# Sell (-)
	var sell_btn := Button.new()
	sell_btn.text = "-"
	sell_btn.custom_minimum_size = Vector2(36, 34)
	sell_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	sell_btn.pressed.connect(_on_sell_enemy.bind(enemy_id))
	if _font:
		sell_btn.add_theme_font_override("font", _font)
		sell_btn.add_theme_font_size_override("font_size", 16)
	hbox.add_child(sell_btn)

	# Assign button
	var assign_btn := Button.new()
	assign_btn.text = "Assign"
	assign_btn.custom_minimum_size = Vector2(80, 34)
	assign_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	assign_btn.pressed.connect(_on_assign_pressed.bind(enemy_id))
	if _font:
		assign_btn.add_theme_font_override("font", _font)
		assign_btn.add_theme_font_size_override("font_size", 14)
	hbox.add_child(assign_btn)

	# Clear assignments for this enemy
	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.custom_minimum_size = Vector2(64, 34)
	clear_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	clear_btn.pressed.connect(_on_clear_enemy.bind(enemy_id))
	if _font:
		clear_btn.add_theme_font_override("font", _font)
		clear_btn.add_theme_font_size_override("font_size", 14)
	hbox.add_child(clear_btn)

	_enemy_rows[enemy_id] = {
		"count_label": count_label,
		"assign_status": assign_status,
		"assign_btn": assign_btn,
		"clear_btn": clear_btn,
	}
	_update_enemy_row(enemy_id)

func _update_enemy_row(enemy_id: StringName) -> void:
	if not _enemy_rows.has(enemy_id):
		return
	var row: Dictionary = _enemy_rows[enemy_id]
	var count: int = _overlord_state.roster.get(enemy_id, 0)
	row["count_label"].text = "x%d" % count

	# Build assignment status string
	var assignments: Dictionary = _overlord_state.get_assignments_for_enemy(enemy_id)
	var unassigned: int = _overlord_state.get_unassigned_count(enemy_id)
	var parts: Array = []
	var btn_keys: Array = assignments.keys()
	btn_keys.sort()
	for btn_idx in btn_keys:
		var lbl: String = _overlord_state.get_button_label(btn_idx)
		parts.append("[%s]x%d" % [lbl, assignments[btn_idx]])
	if unassigned > 0:
		parts.append("%d free" % unassigned)
	elif count == 0:
		parts.append("-")
	row["assign_status"].text = " ".join(parts) if parts.size() > 0 else "-"

	# Disable assign if nothing to assign
	row["assign_btn"].disabled = (unassigned <= 0)
	row["clear_btn"].disabled = assignments.is_empty()

# ---------------------------------------------------------------------------
# Upgrade Row
# ---------------------------------------------------------------------------

func _build_upgrade_row(index: int) -> void:
	var upgrade: Array = OverlordState.UPGRADES[index]
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	_upgrade_container.add_child(hbox)

	var name_label := Label.new()
	name_label.text = upgrade[0]
	name_label.custom_minimum_size = Vector2(130, 0)
	if _font:
		name_label.add_theme_font_override("font", _font)
		name_label.add_theme_font_size_override("font_size", 15)
	hbox.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = "%d" % upgrade[1]
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	cost_label.custom_minimum_size = Vector2(40, 0)
	if _font:
		cost_label.add_theme_font_override("font", _font)
		cost_label.add_theme_font_size_override("font_size", 14)
	hbox.add_child(cost_label)

	var desc_label := Label.new()
	desc_label.text = upgrade[4]
	desc_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _font:
		desc_label.add_theme_font_override("font", _font)
		desc_label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(desc_label)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(60, 34)
	buy_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	buy_btn.pressed.connect(_on_buy_upgrade.bind(index))
	if _font:
		buy_btn.add_theme_font_override("font", _font)
		buy_btn.add_theme_font_size_override("font_size", 14)
	hbox.add_child(buy_btn)

# ---------------------------------------------------------------------------
# Loadout Strip (bottom)
# ---------------------------------------------------------------------------

func _build_loadout_strip() -> void:
	# Container anchored to bottom
	var strip_bg := PanelContainer.new()
	strip_bg.name = "LoadoutStrip"
	strip_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip_bg.offset_left = 30.0
	strip_bg.offset_top = -150.0
	strip_bg.offset_right = -280.0  # leave room for READY button
	strip_bg.offset_bottom = -6.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.9)
	style.border_color = Color(0.3, 0.3, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	strip_bg.add_theme_stylebox_override("panel", style)
	_root.add_child(strip_bg)

	var strip_vbox := VBoxContainer.new()
	strip_vbox.add_theme_constant_override("separation", 2)
	strip_bg.add_child(strip_vbox)

	var strip_title := Label.new()
	strip_title.text = "LOADOUT"
	strip_title.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	if _font:
		strip_title.add_theme_font_override("font", _font)
		strip_title.add_theme_font_size_override("font_size", 14)
	strip_vbox.add_child(strip_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_vbox.add_child(scroll)

	_loadout_container = HBoxContainer.new()
	_loadout_container.add_theme_constant_override("separation", 10)
	scroll.add_child(_loadout_container)

	_refresh_loadout_strip()

func _refresh_loadout_strip() -> void:
	if _loadout_container == null:
		return
	for c in _loadout_container.get_children():
		c.queue_free()

	# Sort button indices for consistent display order
	var btn_keys: Array = _overlord_state.loadout.keys()
	btn_keys.sort()

	if btn_keys.is_empty():
		var hint := Label.new()
		hint.text = "No assignments yet - buy enemies and click Assign"
		hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		if _font:
			hint.add_theme_font_override("font", _font)
			hint.add_theme_font_size_override("font_size", 13)
		_loadout_container.add_child(hint)
		return

	for btn_idx in btn_keys:
		var seq: Array = _overlord_state.loadout[btn_idx]
		if seq.is_empty():
			continue
		_build_loadout_button_panel(btn_idx, seq)

func _build_loadout_button_panel(btn_idx: int, seq: Array) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 80)

	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.08, 0.14, 0.9)
	var btn_color: Color = _overlord_state.get_button_color(btn_idx)
	pstyle.border_color = btn_color.darkened(0.3)
	pstyle.set_border_width_all(2)
	pstyle.set_corner_radius_all(4)
	pstyle.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", pstyle)
	_loadout_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	panel.add_child(vbox)

	# Header: button label + clear
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)

	var btn_label := Label.new()
	btn_label.text = "[%s]" % _overlord_state.get_button_label(btn_idx)
	btn_label.add_theme_color_override("font_color", btn_color)
	if _font:
		btn_label.add_theme_font_override("font", _font)
		btn_label.add_theme_font_size_override("font_size", 14)
	header.add_child(btn_label)

	var count_lbl := Label.new()
	count_lbl.text = "(%d)" % seq.size()
	count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	if _font:
		count_lbl.add_theme_font_override("font", _font)
		count_lbl.add_theme_font_size_override("font_size", 12)
	header.add_child(count_lbl)

	var clear_btn := Button.new()
	clear_btn.text = "X"
	clear_btn.custom_minimum_size = Vector2(24, 20)
	clear_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	clear_btn.pressed.connect(_on_clear_button.bind(btn_idx))
	header.add_child(clear_btn)

	# Sequence: icons in a flow
	var seq_hbox := HBoxContainer.new()
	seq_hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(seq_hbox)

	for i in seq.size():
		var eid: StringName = seq[i]
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var spr_path: String = OverlordState.ENEMY_SPRITES.get(eid, "")
		if spr_path != "" and ResourceLoader.exists(spr_path):
			icon.texture = load(spr_path)
		icon.tooltip_text = String(eid).capitalize()
		seq_hbox.add_child(icon)
		# Show separator arrow for readability (every 5th)
		if i < seq.size() - 1 and (i + 1) % 5 == 0:
			var arrow := Label.new()
			arrow.text = ">"
			arrow.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			if _font:
				arrow.add_theme_font_override("font", _font)
				arrow.add_theme_font_size_override("font_size", 10)
			seq_hbox.add_child(arrow)

# ---------------------------------------------------------------------------
# Assignment overlay
# ---------------------------------------------------------------------------

func _start_assign_mode(enemy_id: StringName) -> void:
	var unassigned: int = _overlord_state.get_unassigned_count(enemy_id)
	if unassigned <= 0:
		return
	_assigning_enemy = enemy_id

	# Build overlay
	_assign_overlay = PanelContainer.new()
	_assign_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_assign_overlay.offset_left = -220.0
	_assign_overlay.offset_top = -60.0
	_assign_overlay.offset_right = 220.0
	_assign_overlay.offset_bottom = 60.0

	var ostyle := StyleBoxFlat.new()
	ostyle.bg_color = Color(0.05, 0.05, 0.15, 0.95)
	ostyle.border_color = Color(0.4, 0.7, 1.0)
	ostyle.set_border_width_all(3)
	ostyle.set_corner_radius_all(8)
	ostyle.set_content_margin_all(12)
	_assign_overlay.add_theme_stylebox_override("panel", ostyle)

	var ovbox := VBoxContainer.new()
	ovbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ovbox.add_theme_constant_override("separation", 8)
	_assign_overlay.add_child(ovbox)

	var prompt := Label.new()
	prompt.text = "Assigning: %s" % String(enemy_id).capitalize()
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	if _font:
		prompt.add_theme_font_override("font", _font)
		prompt.add_theme_font_size_override("font_size", 20)
	ovbox.add_child(prompt)

	_assign_remaining_label = Label.new()
	_assign_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_assign_remaining_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if _font:
		_assign_remaining_label.add_theme_font_override("font", _font)
		_assign_remaining_label.add_theme_font_size_override("font_size", 16)
	ovbox.add_child(_assign_remaining_label)
	_update_assign_overlay()

	var hint := Label.new()
	hint.text = "Press a gamepad button to assign one unit"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	if _font:
		hint.add_theme_font_override("font", _font)
		hint.add_theme_font_size_override("font_size", 13)
	ovbox.add_child(hint)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(120, 36)
	cancel_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_btn.pressed.connect(_end_assign_mode)
	if _font:
		cancel_btn.add_theme_font_override("font", _font)
		cancel_btn.add_theme_font_size_override("font_size", 16)
	ovbox.add_child(cancel_btn)

	_root.add_child(_assign_overlay)

func _update_assign_overlay() -> void:
	if _assign_remaining_label and _assigning_enemy != &"":
		var remaining: int = _overlord_state.get_unassigned_count(_assigning_enemy)
		_assign_remaining_label.text = "%d remaining to assign" % remaining

func _end_assign_mode() -> void:
	_assigning_enemy = &""
	if _assign_overlay:
		_assign_overlay.queue_free()
		_assign_overlay = null
		_assign_remaining_label = null

# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _on_buy_enemy(enemy_id: StringName) -> void:
	AudioManager.play_ui_click()
	if _overlord_state.buy_enemy(enemy_id):
		_refresh_all()

func _on_sell_enemy(enemy_id: StringName) -> void:
	AudioManager.play_ui_click()
	if _overlord_state.sell_enemy(enemy_id):
		_refresh_all()

func _on_assign_pressed(enemy_id: StringName) -> void:
	AudioManager.play_ui_click()
	if _assigning_enemy != &"":
		_end_assign_mode()
	_start_assign_mode(enemy_id)

func _on_clear_enemy(enemy_id: StringName) -> void:
	AudioManager.play_ui_click()
	_overlord_state.clear_enemy_assignments(enemy_id)
	_refresh_all()

func _on_clear_button(button_index: int) -> void:
	AudioManager.play_ui_click()
	_overlord_state.clear_button(button_index)
	_refresh_all()

func _on_buy_upgrade(index: int) -> void:
	AudioManager.play_ui_click()
	if _overlord_state.buy_upgrade(index):
		_update_budget_display()
		_refresh_stats_display()

func _on_ready_pressed() -> void:
	AudioManager.play_ui_click()
	_end_assign_mode()
	visible = false
	ui_closed.emit()

# ---------------------------------------------------------------------------
# Refresh helpers
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_update_budget_display()
	for eid in _enemy_rows:
		_update_enemy_row(eid)
	_refresh_loadout_strip()

func _update_budget_display() -> void:
	if _budget_label:
		_budget_label.text = "Budget: %d" % _overlord_state.budget

func _refresh_stats_display() -> void:
	var stats_node := _upgrade_container.get_node_or_null("StatsLabel")
	if stats_node and stats_node is Label:
		stats_node.text = _get_stats_text()

func _get_stats_text() -> String:
	return "HP: x%.0f%%  Armor: +%.0f  Speed: x%.0f%%\nSpawn CD: x%.0f%%  Income: x%.0f%%" % [
		_overlord_state.hp_mult * 100.0,
		_overlord_state.armor_bonus,
		_overlord_state.speed_mult * 100.0,
		_overlord_state.spawn_cooldown_mult * 100.0,
		_overlord_state.income_mult * 100.0,
	]
