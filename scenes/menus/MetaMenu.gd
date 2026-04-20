extends CanvasLayer

## MetaMenu - Hangar. Spend Credits to unlock ships. Built entirely in code.

# Ships available to unlock; Scout and Sniper start unlocked (unlock_cost = 0).
const SHIP_UNLOCKS: Array[Dictionary] = [
	{"id": &"gunship",     "label": "Gunship",     "desc": "120 HP | 185 spd | Gatling",       "cost": 50},
	{"id": &"rogue",       "label": "Rogue",       "desc": "80 HP | 260 spd | Spread Laser",   "cost": 75},
	{"id": &"runner",      "label": "Runner",      "desc": "60 HP | 300 spd | Pistol",         "cost": 100},
	{"id": &"dreadnought", "label": "Dreadnought", "desc": "250 HP | 100 spd | Twin Cannon",   "cost": 120},
	{"id": &"tank",        "label": "Tank",        "desc": "180 HP | 130 spd | Shotgun",       "cost": 150},
]

var _credits_label: Label
var _ships_container: VBoxContainer

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -260.0
	vbox.offset_top = -220.0
	vbox.offset_right = 260.0
	vbox.offset_bottom = 220.0
	add_child(vbox)

	var title := Label.new()
	title.text = "Hangar"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := GameManager.kenney_font()
	if font:
		title.add_theme_font_override("font", font)
		title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	_credits_label = Label.new()
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_credits_label)

	var ships_title := Label.new()
	ships_title.text = "Unlock Ships"
	ships_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ships_title)

	_ships_container = VBoxContainer.new()
	vbox.add_child(_ships_container)

	var back_btn := Button.new()
	back_btn.text = "Back to Menu"
	back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(back_btn)

	_refresh()

func _refresh() -> void:
	_credits_label.text = "Credits: %d" % MetaProgression.get_coins()
	for child in _ships_container.get_children():
		child.queue_free()

	for entry in SHIP_UNLOCKS:
		var hbox := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s - %s" % [entry["label"], entry["desc"]]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		if MetaProgression.is_character_unlocked(entry["id"]):
			btn.text = "Owned"
			btn.disabled = true
		else:
			btn.text = "Buy (%d Credits)" % entry["cost"]
			btn.pressed.connect(_on_ship_unlock_pressed.bind(entry))
		hbox.add_child(label)
		hbox.add_child(btn)
		_ships_container.add_child(hbox)

func _on_ship_unlock_pressed(entry: Dictionary) -> void:
	AudioManager.play_ui_click()
	if MetaProgression.spend_coins(entry["cost"]):
		MetaProgression.unlock_character(entry["id"])
		_refresh()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")
