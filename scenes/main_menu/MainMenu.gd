extends CanvasLayer

## MainMenu - builds its own UI nodes. No editor wiring needed.

func _ready() -> void:
	GameManager.set_state(GameManager.GameState.MENU)
	get_tree().paused = false
	var music_path := "res://assets/audio/music_menu.ogg"
	if ResourceLoader.exists(music_path):
		AudioManager.play_music(load(music_path))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -120.0
	vbox.offset_top = -120.0
	vbox.offset_right = 120.0
	vbox.offset_bottom = 120.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)

	var title := Label.new()
	title.text = "SPACE ROGUELITE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := GameManager.kenney_font()
	if font:
		title.add_theme_font_override("font", font)
		title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)

	_add_button(vbox, "Wave Survival", _on_survival_pressed)
	_add_button(vbox, "Horde Defense", _on_horde_defense_pressed)
	_add_button(vbox, "Upgrades",      _on_meta_menu_pressed)
	_add_button(vbox, "Quit",          _on_quit_pressed)

func _add_button(parent: Node, text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(func():
		AudioManager.play_ui_click()
		callback.call()
	)
	parent.add_child(btn)

func _on_survival_pressed() -> void:
	GameManager.current_mode = GameManager.RunMode.WAVE_SURVIVAL
	get_tree().change_scene_to_file("res://scenes/main_menu/CharacterSelect.tscn")

func _on_horde_defense_pressed() -> void:
	GameManager.current_mode = GameManager.RunMode.HORDE_DEFENSE
	get_tree().change_scene_to_file("res://scenes/main_menu/CharacterSelect.tscn")

func _on_meta_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MetaMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
