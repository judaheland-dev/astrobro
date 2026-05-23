extends CanvasLayer

## GameOverUI - built entirely in code. Shows win/lose and navigation buttons.

var _result_label: Label
var _coins_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20   # render on top of HUD (layer 1) and BetweenWaveUI

	# Root control fills the viewport so all children receive mouse input correctly.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -260.0
	vbox.offset_top    = -200.0
	vbox.offset_right  =  260.0
	vbox.offset_bottom =  200.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	root.add_child(vbox)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.text = ""
	var font := GameManager.kenney_font()
	if font:
		_result_label.add_theme_font_override("font", font)
		_result_label.add_theme_font_size_override("font_size", 52)
	vbox.add_child(_result_label)

	_coins_label = Label.new()
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		_coins_label.add_theme_font_override("font", font)
		_coins_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_coins_label)

	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(260, 60)
	menu_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	if font:
		menu_btn.add_theme_font_override("font", font)
		menu_btn.add_theme_font_size_override("font_size", 26)
	menu_btn.pressed.connect(_go_to_menu)
	vbox.add_child(menu_btn)

	var hint := Label.new()
	hint.text = "(or press Escape)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.6, 0.6, 0.6)
	vbox.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_go_to_menu()

func _go_to_menu() -> void:
	get_tree().paused = false
	GameManager.go_to_main_menu()

func show_result(victory: bool) -> void:
	_result_label.text = "VICTORY!" if victory else "GAME OVER"
	_result_label.modulate = Color(0.3, 1.0, 0.3) if victory else Color(1.0, 0.3, 0.3)
	_coins_label.text = "Coins earned: %d" % GameManager.run_coins_earned
	AudioManager.stop_music()
	var sfx_path := "res://assets/audio/sfx_victory.ogg" if victory else "res://assets/audio/sfx_lose.ogg"
	if ResourceLoader.exists(sfx_path):
		AudioManager.play_sfx(load(sfx_path))
	visible = true
