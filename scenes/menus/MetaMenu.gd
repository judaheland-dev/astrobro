extends CanvasLayer

## MetaMenu - Hangar. Spend Credits to unlock ships. Built entirely in code.

# Ships available to unlock; Scout and Sniper start unlocked (unlock_cost = 0).
const SHIP_UNLOCKS: Array[Dictionary] = [
	{"id": &"gunship",     "label": "Gunship",     "desc": "120 HP | 185 spd | 1 armor | Gatling",              "cost": 300},
	{"id": &"rogue",       "label": "Rogue",       "desc": "80 HP | 260 spd | 2x coins | Spread Laser",         "cost": 600},
	{"id": &"runner",      "label": "Runner",      "desc": "60 HP | 300 spd | 1.5x XP | Pistol",               "cost": 1200},
	{"id": &"dreadnought", "label": "Dreadnought", "desc": "250 HP | 100 spd | 8 armor | Twin Cannon",          "cost": 2500},
	{"id": &"tank",        "label": "Tank",        "desc": "180 HP | 130 spd | 5 armor | 6 slots | Shotgun",    "cost": 5000},
	{"id": &"vanguard",    "label": "Vanguard",    "desc": "200 HP | 220 spd | 3 armor | Shield | Beam Laser",  "cost": 15000},
	{"id": &"phantom",     "label": "Phantom",     "desc": "50 HP | 380 spd | 2x XP | 1.5x coins | Spread",    "cost": 75000},
	{"id": &"fortress",    "label": "Fortress",    "desc": "600 HP | 75 spd | 25 armor | Shield | 3x coins",    "cost": 150000},
	{"id": &"nexus",       "label": "Nexus",       "desc": "350 HP | 270 spd | 12 armor | Shield | 8 slots",    "cost": 350000},
	{"id": &"singularity", "label": "Singularity", "desc": "1200 HP | 330 spd | 35 armor | Shield | 10 slots",  "cost": 750000},
]

## Format large numbers with commas for readability (e.g. 1000000 -> "1,000,000").
static func _format_credits(amount: int) -> String:
	var s := str(amount)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

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
	_credits_label.text = "Credits: %s" % _format_credits(MetaProgression.get_coins())
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
			btn.text = "Buy (%s Credits)" % _format_credits(entry["cost"])
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
