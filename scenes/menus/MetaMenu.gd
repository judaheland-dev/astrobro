extends CanvasLayer

## MetaMenu - spend persistent coins on permanent upgrades. Built entirely in code.

const PERSISTENT_UPGRADES: Array[Dictionary] = [
	{"stat": &"max_health",  "label": "Max HP +10",     "cost": 50,  "delta": 10.0},
	{"stat": &"move_speed",  "label": "Speed +15",      "cost": 75,  "delta": 15.0},
	{"stat": &"armor",       "label": "Armor +2",       "cost": 100, "delta": 2.0},
]

# Ships available for purchase (id, display label, cost matching CharacterData.unlock_cost)
const SHIP_UNLOCKS: Array[Dictionary] = [
	{"id": &"gunship",     "label": "Gunship",      "desc": "120 HP / 185 spd / Gatling",      "cost": 50},
	{"id": &"rogue",       "label": "Rogue",        "desc": "80 HP / 260 spd / Spread Laser",  "cost": 75},
	{"id": &"dreadnought", "label": "Dreadnought",  "desc": "250 HP / 100 spd / Twin Cannon",  "cost": 120},
]

var _coin_label: Label
var _upgrades_container: VBoxContainer
var _ships_container: VBoxContainer

func _ready() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -220.0
	vbox.offset_top = -220.0
	vbox.offset_right = 220.0
	vbox.offset_bottom = 220.0
	add_child(vbox)

	var title := Label.new()
	title.text = "Persistent Upgrades"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_coin_label = Label.new()
	vbox.add_child(_coin_label)

	_upgrades_container = VBoxContainer.new()
	vbox.add_child(_upgrades_container)

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
	_coin_label.text = "Coins: %d" % MetaProgression.get_coins()
	for child in _upgrades_container.get_children():
		child.queue_free()

	for entry in PERSISTENT_UPGRADES:
		var hbox := HBoxContainer.new()
		var label := Label.new()
		var current_val := MetaProgression.get_persistent_stat(entry["stat"])
		label.text = "%s (current: %s)" % [entry["label"], str(current_val)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.text = "Buy (%d)" % entry["cost"]
		btn.pressed.connect(_on_upgrade_pressed.bind(entry))
		hbox.add_child(label)
		hbox.add_child(btn)
		_upgrades_container.add_child(hbox)

	for child in _ships_container.get_children():
		child.queue_free()

	for entry in SHIP_UNLOCKS:
		var hbox := HBoxContainer.new()
		var label := Label.new()
		var already_owned := MetaProgression.is_character_unlocked(entry["id"])
		label.text = "%s - %s" % [entry["label"], entry["desc"]]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		if already_owned:
			btn.text = "Owned"
			btn.disabled = true
		else:
			btn.text = "Buy (%d)" % entry["cost"]
			btn.pressed.connect(_on_ship_unlock_pressed.bind(entry))
		hbox.add_child(label)
		hbox.add_child(btn)
		_ships_container.add_child(hbox)

func _on_upgrade_pressed(entry: Dictionary) -> void:
	if MetaProgression.spend_coins(entry["cost"]):
		MetaProgression.add_persistent_stat(entry["stat"], entry["delta"])
		_refresh()

func _on_ship_unlock_pressed(entry: Dictionary) -> void:
	if MetaProgression.spend_coins(entry["cost"]):
		MetaProgression.unlock_character(entry["id"])
		_refresh()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")
