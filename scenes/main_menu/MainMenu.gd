extends CanvasLayer

## MainMenu - builds its own UI nodes. No editor wiring needed.

var _star_nodes: Array = []
var _ship_nodes: Array = []

func _ready() -> void:
	GameManager.set_state(GameManager.GameState.MENU)
	get_tree().paused = false
	var music_path := "res://assets/audio/music_menu.ogg"
	if ResourceLoader.exists(music_path):
		AudioManager.play_music(load(music_path))

	# Root control fills the viewport
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Dark base colour so something shows if tex fails
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Tiled space texture
	var bg_tex_path := "res://assets/sprites/bg_darkPurple.png"
	if ResourceLoader.exists(bg_tex_path):
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(bg_tex_path)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_TILE
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tex_rect)

	_spawn_stars(root)
	_spawn_bg_ships(root)

	var font := GameManager.kenney_font()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -160.0
	vbox.offset_top = -175.0
	vbox.offset_right = 160.0
	vbox.offset_bottom = 175.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var title := Label.new()
	title.text = "ASTRO BRO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		title.add_theme_font_override("font", font)
		title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "CO-OP SPACE ROGUELITE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		subtitle.add_theme_font_override("font", font)
		subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	vbox.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer)

	var first_btn := _add_button(vbox, "Wave Survival", _on_survival_pressed, font)
	_add_button(vbox, "Horde Defense", _on_horde_defense_pressed, font)
	_add_button(vbox, "PVP - Overlord", _on_pvp_pressed, font)
	_add_button(vbox, "Upgrades",      _on_meta_menu_pressed, font)
	_add_button(vbox, "Quit",          _on_quit_pressed, font)
	first_btn.grab_focus()

	# Version label — bottom-right corner
	var version_str: String = ProjectSettings.get_setting("application/config/version", "")
	if version_str != "":
		var ver_label := Label.new()
		ver_label.text = "v" + version_str
		ver_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		ver_label.offset_left = -120.0
		ver_label.offset_top = -36.0
		ver_label.offset_right = -8.0
		ver_label.offset_bottom = -8.0
		ver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ver_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if font:
			ver_label.add_theme_font_override("font", font)
			ver_label.add_theme_font_size_override("font_size", 14)
		ver_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.7, 0.8))
		add_child(ver_label)


func _spawn_stars(parent: Control) -> void:
	var star_defs: Array[Dictionary] = [
		{"tex": "res://assets/sprites/star1.png", "count": 30, "sc": 0.4, "speed": 30.0},
		{"tex": "res://assets/sprites/star2.png", "count": 20, "sc": 0.7, "speed": 60.0},
		{"tex": "res://assets/sprites/star3.png", "count": 10, "sc": 1.0, "speed": 100.0},
	]
	for def in star_defs:
		if not ResourceLoader.exists(def["tex"]):
			continue
		var tex: Texture2D = load(def["tex"])
		for i in def["count"]:
			var s := Sprite2D.new()
			s.texture = tex
			s.scale = Vector2(def["sc"], def["sc"])
			s.position = Vector2(randf_range(0.0, 1920.0), randf_range(0.0, 1080.0))
			s.modulate = Color(1.0, 1.0, 1.0, randf_range(0.5, 1.0))
			parent.add_child(s)
			_star_nodes.append({"sprite": s, "speed": def["speed"]})


func _spawn_bg_ships(parent: Control) -> void:
	var base_tex := "res://assets/sprites/playerShip1_blue.png"
	if not ResourceLoader.exists(base_tex):
		return
	var ship_tex: Texture2D = load(base_tex)
	var ship_defs: Array[Dictionary] = [
		{"color": Color(0.4, 0.7, 1.0,  0.18), "y": 200.0, "speed": 40.0, "x": -200.0},
		{"color": Color(1.0, 0.55, 0.1, 0.18), "y": 540.0, "speed": 55.0, "x": -500.0},
		{"color": Color(1.0, 0.25, 0.25, 0.18), "y": 860.0, "speed": 30.0, "x": -800.0},
	]
	for def in ship_defs:
		var s := Sprite2D.new()
		s.texture = ship_tex
		s.rotation_degrees = 90.0
		s.scale = Vector2(1.5, 1.5)
		s.modulate = def["color"]
		s.position = Vector2(def["x"], def["y"])
		parent.add_child(s)
		_ship_nodes.append({"sprite": s, "speed": def["speed"]})


func _process(delta: float) -> void:
	for entry in _star_nodes:
		var s: Sprite2D = entry["sprite"]
		s.position.y += entry["speed"] * delta
		if s.position.y > 1100.0:
			s.position.y = -20.0
			s.position.x = randf_range(0.0, 1920.0)
	for entry in _ship_nodes:
		var s: Sprite2D = entry["sprite"]
		s.position.x += entry["speed"] * delta
		if s.position.x > 2100.0:
			s.position.x = -200.0


func _add_button(parent: Node, text: String, callback: Callable, font: FontFile = null) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 50)
	if font:
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(func():
		AudioManager.play_ui_click()
		callback.call()
	)
	parent.add_child(btn)
	return btn

func _on_survival_pressed() -> void:
	GameManager.current_mode = GameManager.RunMode.WAVE_SURVIVAL
	get_tree().change_scene_to_file("res://scenes/main_menu/CharacterSelect.tscn")

func _on_horde_defense_pressed() -> void:
	GameManager.current_mode = GameManager.RunMode.HORDE_DEFENSE
	get_tree().change_scene_to_file("res://scenes/main_menu/CharacterSelect.tscn")

func _on_pvp_pressed() -> void:
	GameManager.current_mode = GameManager.RunMode.PVP_OVERLORD
	get_tree().change_scene_to_file("res://scenes/main_menu/CharacterSelect.tscn")

func _on_meta_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menus/MetaMenu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
