extends CanvasLayer

## CharacterSelect - builds its own UI. No editor wiring needed.

const SHIP_SPRITES: Dictionary = {
	&"scout":       "res://assets/sprites/playerShip1_blue.png",
	&"sniper":      "res://assets/sprites/playerShip2_orange.png",
	&"gunship":     "res://assets/sprites/playerShip3_red.png",
	&"rogue":       "res://assets/sprites/spaceShips_001.png",
	&"runner":      "res://assets/sprites/spaceShips_002.png",
	&"dreadnought": "res://assets/sprites/spaceShips_003.png",
	&"tank":        "res://assets/sprites/spaceShips_004.png",
}

var _selected: Array[StringName] = [&"scout", &"scout"]
var _player_count: int = 1
var _available: Array[StringName] = []
var _p1_btn: Button
var _p2_btn: Button
var _p2_panel: Control   # shown/hidden on 1P/2P toggle
var _ship_sprites: Array = [null, null]
var _star_nodes: Array = []

func _ready() -> void:
	_available = MetaProgression._data.unlocked_characters.duplicate()
	if _available.is_empty():
		_available = [&"scout"]
	_selected[0] = _available[0]
	_selected[1] = _available[0]

	var font := GameManager.kenney_font()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Dark base
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

	# Scrolling stars
	var star_tex_path := "res://assets/sprites/star1.png"
	if ResourceLoader.exists(star_tex_path):
		var star_tex: Texture2D = load(star_tex_path)
		for i in 25:
			var s := Sprite2D.new()
			s.texture = star_tex
			s.scale = Vector2(randf_range(0.3, 0.8), randf_range(0.3, 0.8))
			s.position = Vector2(randf_range(0.0, 1920.0), randf_range(0.0, 1080.0))
			s.modulate = Color(1.0, 1.0, 1.0, randf_range(0.4, 0.9))
			root.add_child(s)
			_star_nodes.append(s)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left  = -320.0
	vbox.offset_top   = -300.0
	vbox.offset_right =  320.0
	vbox.offset_bottom = 300.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	root.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Select Your Ship"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		title.add_theme_font_override("font", font)
		title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)

	# 1P / 2P toggle row
	var mode_hbox := HBoxContainer.new()
	mode_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(mode_hbox)

	_p1_btn = Button.new()
	_p1_btn.text = "1 Player"
	_p1_btn.toggle_mode = true
	_p1_btn.button_pressed = true
	_p1_btn.custom_minimum_size = Vector2(140, 40)
	_p1_btn.pressed.connect(_on_players_1_pressed)
	mode_hbox.add_child(_p1_btn)

	_p2_btn = Button.new()
	_p2_btn.text = "2 Players (Co-op)"
	_p2_btn.toggle_mode = true
	_p2_btn.custom_minimum_size = Vector2(200, 40)
	_p2_btn.pressed.connect(_on_players_2_pressed)
	mode_hbox.add_child(_p2_btn)

	# Character picker row (P1 | P2)
	var pickers_hbox := HBoxContainer.new()
	pickers_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pickers_hbox.add_theme_constant_override("separation", 40)
	vbox.add_child(pickers_hbox)

	pickers_hbox.add_child(_build_char_picker(0, "Player 1 (WASD)", font))

	_p2_panel = _build_char_picker(1, "Player 2 (IJKL / Gamepad)", font)
	_p2_panel.visible = false
	pickers_hbox.add_child(_p2_panel)

	# Start / Back
	var start_btn := Button.new()
	start_btn.text = "Start"
	start_btn.custom_minimum_size = Vector2(200, 50)
	start_btn.pressed.connect(_on_start_pressed)
	if font:
		start_btn.add_theme_font_override("font", font)
		start_btn.add_theme_font_size_override("font_size", 24)
	vbox.add_child(start_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_on_back_pressed)
	vbox.add_child(back_btn)

	_p1_btn.grab_focus()


func _process(delta: float) -> void:
	for s in _star_nodes:
		(s as Sprite2D).position.y += 25.0 * delta
		if (s as Sprite2D).position.y > 1100.0:
			(s as Sprite2D).position.y = -20.0
			(s as Sprite2D).position.x = randf_range(0.0, 1920.0)


func _ship_tex_for(char_id: StringName) -> Texture2D:
	var path: String = SHIP_SPRITES.get(char_id, "res://assets/sprites/playerShip1_blue.png")
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _build_char_picker(player_idx: int, label_text: String, font: FontFile) -> Control:
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 18)
	vbox.add_child(lbl)

	# Ship sprite preview
	var ship_preview := TextureRect.new()
	ship_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ship_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ship_preview.custom_minimum_size = Vector2(120, 120)
	ship_preview.texture = _ship_tex_for(_selected[player_idx])
	vbox.add_child(ship_preview)
	_ship_sprites[player_idx] = ship_preview

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.text = _selected[player_idx].capitalize()
	if font:
		name_lbl.add_theme_font_override("font", font)
		name_lbl.add_theme_font_size_override("font_size", 22)
	vbox.add_child(name_lbl)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(40, 40)
	prev.pressed.connect(func(): _cycle_char(player_idx, -1, name_lbl))
	hbox.add_child(prev)

	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(40, 40)
	next.pressed.connect(func(): _cycle_char(player_idx, 1, name_lbl))
	hbox.add_child(next)

	return vbox


func _cycle_char(player_idx: int, dir: int, name_lbl: Label) -> void:
	AudioManager.play_ui_click()
	var cur_i := _available.find(_selected[player_idx])
	cur_i = (cur_i + dir + _available.size()) % _available.size()
	_selected[player_idx] = _available[cur_i]
	name_lbl.text = _selected[player_idx].capitalize()
	var preview: TextureRect = _ship_sprites[player_idx]
	if preview:
		preview.texture = _ship_tex_for(_selected[player_idx])
		preview.scale = Vector2.ZERO
		var tw := create_tween()
		tw.tween_property(preview, "scale", Vector2(1.15, 1.15), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(preview, "scale", Vector2(1.0, 1.0), 0.1)


func _on_start_pressed() -> void:
	AudioManager.play_ui_click()
	GameManager.start_run(
		GameManager.current_mode,
		_selected.slice(0, _player_count),
		_player_count
	)

func _on_back_pressed() -> void:
	AudioManager.play_ui_click()
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")

func _on_players_1_pressed() -> void:
	_player_count = 1
	_p1_btn.button_pressed = true
	_p2_btn.button_pressed = false
	_p2_panel.visible = false

func _on_players_2_pressed() -> void:
	_player_count = 2
	_p1_btn.button_pressed = false
	_p2_btn.button_pressed = true
	_p2_panel.visible = true
