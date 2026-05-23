extends CanvasLayer

## TestHarness – quick-launch UI for jumping to any game state without
## going through the main menu.  Only for debugging / testing.
##
## Sets GameManager state then loads Game.tscn directly.
##
## Access: run the game with this scene as the main scene, or navigate to
## res://scenes/test/TestHarness.tscn from the Godot editor.

const CHARACTERS: Array[StringName] = [
	&"scout", &"sniper", &"tank", &"rogue", &"runner", &"gunship",
	&"fortress", &"nexus", &"phantom", &"dreadnought", &"vanguard", &"singularity",
]
const CHAR_LABELS: Dictionary = {
	&"scout":       "Scout",
	&"sniper":      "Sniper",
	&"tank":        "Tank",
	&"rogue":       "Rogue",
	&"runner":      "Runner",
	&"gunship":     "Gunship",
	&"fortress":    "Fortress",
	&"nexus":       "Nexus",
	&"phantom":     "Phantom",
	&"dreadnought": "Dreadnought",
	&"vanguard":    "Vanguard",
	&"singularity": "Singularity",
}
const MAX_WAVE: int = 20

var _char_p1: StringName = &"scout"
var _char_p2: StringName = &"scout"
var _player_count: int = 1
var _game_mode: int = GameManager.RunMode.WAVE_SURVIVAL
var _difficulty: int = GameManager.Difficulty.NORMAL
var _start_wave: int = 1
var _god_mode: bool = false

# UI refs for radio-group logic
var _p1_btn: Button
var _p2_btn: Button
var _p2_char_row: VBoxContainer
var _mode_btns: Array[Button] = []
var _diff_btns: Array[Button] = []
var _wave_label: Label

func _ready() -> void:
	var font := GameManager.kenney_font()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── Background ──────────────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var bg_tex_path := "res://assets/sprites/bg_darkPurple.png"
	if ResourceLoader.exists(bg_tex_path):
		var tex_rect := TextureRect.new()
		tex_rect.texture = load(bg_tex_path)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_TILE
		tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tex_rect)

	# ── Center panel ────────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -440.0
	panel.offset_top    = -360.0
	panel.offset_right  =  440.0
	panel.offset_bottom =  360.0
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   28)
	margin.add_theme_constant_override("margin_right",  28)
	margin.add_theme_constant_override("margin_top",    22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	margin.add_child(inner)

	# ── Title ───────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "TEST HARNESS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		title.add_theme_font_override("font", font)
		title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.1))
	inner.add_child(title)

	inner.add_child(_hsep())

	# ── Player count ────────────────────────────────────────────────────────
	inner.add_child(_section_label("Players", font))
	var players_hbox := HBoxContainer.new()
	players_hbox.add_theme_constant_override("separation", 8)
	inner.add_child(players_hbox)

	var p1_grp := ButtonGroup.new()
	for i: int in [1, 2]:
		var b := Button.new()
		b.text = "%dP" % i
		b.toggle_mode = true
		b.button_pressed = (i == 1)
		b.button_group = p1_grp
		b.custom_minimum_size = Vector2(80, 36)
		b.pressed.connect(_on_player_count.bind(i))
		players_hbox.add_child(b)
		if i == 1:
			_p1_btn = b
		else:
			_p2_btn = b

	# ── Character P1 ────────────────────────────────────────────────────────
	inner.add_child(_section_label("Character (P1)", font))
	var char_opt1 := OptionButton.new()
	for c: StringName in CHARACTERS:
		char_opt1.add_item(CHAR_LABELS.get(c, str(c)))
	char_opt1.selected = 0
	char_opt1.item_selected.connect(func(idx: int) -> void: _char_p1 = CHARACTERS[idx])
	inner.add_child(char_opt1)

	# ── Character P2 (hidden until 2P) ──────────────────────────────────────
	_p2_char_row = VBoxContainer.new()
	_p2_char_row.visible = false
	_p2_char_row.add_theme_constant_override("separation", 6)
	inner.add_child(_p2_char_row)
	_p2_char_row.add_child(_section_label("Character (P2)", font))
	var char_opt2 := OptionButton.new()
	for c: StringName in CHARACTERS:
		char_opt2.add_item(CHAR_LABELS.get(c, str(c)))
	char_opt2.selected = 0
	char_opt2.item_selected.connect(func(idx: int) -> void: _char_p2 = CHARACTERS[idx])
	_p2_char_row.add_child(char_opt2)

	# ── Game mode ───────────────────────────────────────────────────────────
	inner.add_child(_section_label("Mode", font))
	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 8)
	inner.add_child(mode_hbox)
	var mode_grp := ButtonGroup.new()
	var modes: Array = [
		["Wave Survival", GameManager.RunMode.WAVE_SURVIVAL],
		["Horde Defense", GameManager.RunMode.HORDE_DEFENSE],
	]
	for m: Array in modes:
		var b := Button.new()
		b.text = m[0]
		b.toggle_mode = true
		b.button_pressed = (m[1] == GameManager.RunMode.WAVE_SURVIVAL)
		b.button_group = mode_grp
		b.custom_minimum_size = Vector2(150, 36)
		b.pressed.connect(_on_mode.bind(m[1]))
		mode_hbox.add_child(b)
		_mode_btns.append(b)

	# ── Difficulty ──────────────────────────────────────────────────────────
	inner.add_child(_section_label("Difficulty", font))
	var diff_hbox := HBoxContainer.new()
	diff_hbox.add_theme_constant_override("separation", 6)
	inner.add_child(diff_hbox)
	var diff_grp := ButtonGroup.new()
	var diffs: Array = [
		["S.Easy", GameManager.Difficulty.SUPER_EASY],
		["Easy",   GameManager.Difficulty.EASY],
		["Normal", GameManager.Difficulty.NORMAL],
		["Hard",   GameManager.Difficulty.HARD],
		["S.Hard", GameManager.Difficulty.SUPER_HARD],
	]
	for d: Array in diffs:
		var b := Button.new()
		b.text = d[0]
		b.toggle_mode = true
		b.button_pressed = (d[1] == GameManager.Difficulty.NORMAL)
		b.button_group = diff_grp
		b.custom_minimum_size = Vector2(82, 36)
		b.pressed.connect(_on_diff.bind(d[1]))
		diff_hbox.add_child(b)
		_diff_btns.append(b)

	# ── Start wave ──────────────────────────────────────────────────────────
	inner.add_child(_section_label("Start at Wave", font))
	var wave_hbox := HBoxContainer.new()
	wave_hbox.add_theme_constant_override("separation", 8)
	inner.add_child(wave_hbox)

	var minus_btn := Button.new()
	minus_btn.text = "−"
	minus_btn.custom_minimum_size = Vector2(44, 36)
	minus_btn.pressed.connect(_on_wave_dec)
	wave_hbox.add_child(minus_btn)

	_wave_label = Label.new()
	_wave_label.text = "1"
	_wave_label.custom_minimum_size = Vector2(60, 36)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font:
		_wave_label.add_theme_font_override("font", font)
		_wave_label.add_theme_font_size_override("font_size", 20)
	wave_hbox.add_child(_wave_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(44, 36)
	plus_btn.pressed.connect(_on_wave_inc)
	wave_hbox.add_child(plus_btn)

	# ── God mode ────────────────────────────────────────────────────────────
	var god_check := CheckButton.new()
	god_check.text = "God Mode  (players take no damage)"
	god_check.button_pressed = false
	god_check.toggled.connect(func(v: bool) -> void: _god_mode = v)
	inner.add_child(god_check)

	inner.add_child(_hsep())

	# ── Debug shortcut hint ─────────────────────────────────────────────────
	var hint := Label.new()
	hint.text = "In-game debug keys: F1 toggle HUD  F2 kill enemies  F3 heal  F4 skip wave  F5 +scrap  F6 godmode"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6))
	hint.add_theme_font_size_override("font_size", 13)
	inner.add_child(hint)

	inner.add_child(_hsep())

	# ── Launch button ───────────────────────────────────────────────────────
	var launch_btn := Button.new()
	launch_btn.text = "LAUNCH GAME"
	launch_btn.custom_minimum_size = Vector2(0, 52)
	if font:
		launch_btn.add_theme_font_override("font", font)
		launch_btn.add_theme_font_size_override("font_size", 24)
	launch_btn.pressed.connect(_launch)
	inner.add_child(launch_btn)

	# ── Back to main menu ───────────────────────────────────────────────────
	var menu_btn := Button.new()
	menu_btn.text = "← Back to Main Menu"
	menu_btn.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")
	)
	inner.add_child(menu_btn)

# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _on_player_count(count: int) -> void:
	_player_count = count
	_p2_char_row.visible = (count == 2)

func _on_mode(mode: int) -> void:
	_game_mode = mode

func _on_diff(diff: int) -> void:
	_difficulty = diff

func _on_wave_dec() -> void:
	_start_wave = max(1, _start_wave - 1)
	_wave_label.text = str(_start_wave)

func _on_wave_inc() -> void:
	_start_wave = min(MAX_WAVE, _start_wave + 1)
	_wave_label.text = str(_start_wave)

func _launch() -> void:
	# Configure GameManager
	GameManager.player_count = _player_count
	GameManager.current_mode = _game_mode
	GameManager.current_difficulty = _difficulty

	GameManager.selected_characters.clear()
	GameManager.selected_characters.append(_char_p1)
	if _player_count >= 2:
		GameManager.selected_characters.append(_char_p2)

	# Unlock chosen characters so Game.gd can load their data
	if not MetaProgression.is_character_unlocked(_char_p1):
		MetaProgression.unlock_character(_char_p1)
	if _player_count >= 2 and not MetaProgression.is_character_unlocked(_char_p2):
		MetaProgression.unlock_character(_char_p2)

	# Debug flags
	GameManager.debug_mode       = true
	GameManager.debug_start_wave = _start_wave
	GameManager.debug_god_mode   = _god_mode

	# Reset per-run stats
	GameManager.run_wave         = 0
	GameManager.run_coins_earned = 0

	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _section_label(text: String, font: Font) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	if font:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 14)
	return lbl

func _hsep() -> HSeparator:
	return HSeparator.new()
