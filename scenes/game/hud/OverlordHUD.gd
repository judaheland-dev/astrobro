extends CanvasLayer

## OverlordHUD - in-wave HUD overlay for the Overlord player.
## Shows 4 deploy slots (face button icons + enemy name + count + cooldown),
## budget, wave timer, and wave number.

var _overlord_controller: Node = null  # OverlordController
var _overlord_state: OverlordState = null
var _overlord_mode: Node = null  # OverlordMode

var _slot_panels: Array = []  # Array of {panel, icon, count_label, cooldown_bar, button_label}
var _budget_label: Label = null
var _wave_label: Label = null
var _timer_label: Label = null
var _root: Control = null

func _ready() -> void:
	layer = 2  # Above game HUD (layer 1)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

func setup(controller: Node, state: OverlordState, mode: Node) -> void:
	_overlord_controller = controller
	_overlord_state = state
	_overlord_mode = mode

func _build_ui() -> void:
	var font := GameManager.kenney_font()

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# --- Top-right: Budget + Wave info ---
	var top_right := VBoxContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_left = -260.0
	top_right.offset_top = 8.0
	top_right.offset_right = -8.0
	top_right.offset_bottom = 120.0
	top_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top_right)

	var overlord_title := Label.new()
	overlord_title.text = "OVERLORD"
	overlord_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	overlord_title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	if font:
		overlord_title.add_theme_font_override("font", font)
		overlord_title.add_theme_font_size_override("font_size", 20)
	top_right.add_child(overlord_title)

	_budget_label = Label.new()
	_budget_label.text = "Budget: 100"
	_budget_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_budget_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	if font:
		_budget_label.add_theme_font_override("font", font)
		_budget_label.add_theme_font_size_override("font_size", 16)
	top_right.add_child(_budget_label)

	_wave_label = Label.new()
	_wave_label.text = "Wave 1"
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if font:
		_wave_label.add_theme_font_override("font", font)
		_wave_label.add_theme_font_size_override("font_size", 16)
	top_right.add_child(_wave_label)

	_timer_label = Label.new()
	_timer_label.text = "90s"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	if font:
		_timer_label.add_theme_font_override("font", font)
		_timer_label.add_theme_font_size_override("font_size", 14)
	top_right.add_child(_timer_label)

	# --- Bottom-right: 4 deploy slots ---
	var slots_container := HBoxContainer.new()
	slots_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	slots_container.offset_left = -440.0
	slots_container.offset_top = -100.0
	slots_container.offset_right = -8.0
	slots_container.offset_bottom = -8.0
	slots_container.alignment = BoxContainer.ALIGNMENT_END
	slots_container.add_theme_constant_override("separation", 8)
	slots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(slots_container)

	var button_labels: Array[String] = ["A", "B", "X", "Y"]
	var button_colors: Array[Color] = [
		Color(0.2, 0.8, 0.2),   # A - green
		Color(0.8, 0.2, 0.2),   # B - red
		Color(0.2, 0.5, 1.0),   # X - blue
		Color(1.0, 0.8, 0.1),   # Y - yellow
	]

	for i in 4:
		var slot_data := _build_slot_panel(i, button_labels[i], button_colors[i], font)
		slots_container.add_child(slot_data["panel"])
		_slot_panels.append(slot_data)

func _build_slot_panel(index: int, btn_text: String, btn_color: Color, font: FontFile) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(100, 88)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	style.border_color = btn_color.darkened(0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	# Button label (A/B/X/Y)
	var button_label := Label.new()
	button_label.text = btn_text
	button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_label.add_theme_color_override("font_color", btn_color)
	if font:
		button_label.add_theme_font_override("font", font)
		button_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(button_label)

	# Enemy name
	var icon_label := Label.new()
	icon_label.text = "-"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		icon_label.add_theme_font_override("font", font)
		icon_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(icon_label)

	# Count
	var count_label := Label.new()
	count_label.text = "x0"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	if font:
		count_label.add_theme_font_override("font", font)
		count_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(count_label)

	# Cooldown bar (ColorRect behind a filled ColorRect)
	var cd_bg := ColorRect.new()
	cd_bg.color = Color(0.2, 0.2, 0.2, 0.6)
	cd_bg.custom_minimum_size = Vector2(90, 6)
	cd_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(cd_bg)

	var cd_fill := ColorRect.new()
	cd_fill.color = btn_color
	cd_fill.custom_minimum_size = Vector2(0, 6)
	cd_fill.size = Vector2(0, 6)
	cd_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_bg.add_child(cd_fill)

	return {
		"panel": panel,
		"icon_label": icon_label,
		"count_label": count_label,
		"cd_bg": cd_bg,
		"cd_fill": cd_fill,
		"button_label": button_label,
	}

func _process(_delta: float) -> void:
	if _overlord_state == null or _overlord_mode == null:
		return

	# Update budget
	_budget_label.text = "Budget: %d" % _overlord_state.budget

	# Update wave/timer
	_wave_label.text = "Wave %d" % GameManager.run_wave
	if _overlord_mode.has_method("get_wave_timer"):
		var remaining: float = _overlord_mode.call("get_wave_timer")
		_timer_label.text = "%ds" % int(ceil(remaining))

	# Update slot panels
	for i in 4:
		var slot: Dictionary = _slot_panels[i]
		var eid: StringName = _overlord_state.loadout[i]
		if eid == &"":
			slot["icon_label"].text = "-"
			slot["count_label"].text = "x0"
		else:
			slot["icon_label"].text = eid.capitalize() if eid is StringName else str(eid)
			slot["count_label"].text = "x%d" % _overlord_state.deploy_remaining[i]

		# Cooldown bar
		if _overlord_controller and _overlord_controller.has_method("get_cooldown_ratio"):
			var ratio: float = _overlord_controller.call("get_cooldown_ratio", i)
			var max_w: float = slot["cd_bg"].size.x
			slot["cd_fill"].size.x = max_w * (1.0 - ratio)
		else:
			slot["cd_fill"].size.x = slot["cd_bg"].size.x

func show_hud() -> void:
	visible = true

func hide_hud() -> void:
	visible = false
