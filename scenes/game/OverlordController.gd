extends Node2D
class_name OverlordController

## OverlordController - handles the Overlord's spawn cursor and enemy
## deployment during active PVP waves. Added as a child of Game.

const CURSOR_SPEED: float = 600.0
const SAFE_ZONE_RADIUS: float = 200.0
const BASE_COOLDOWN: float = 0.8
const ARENA_HW: float = 900.0  # safe spawn bounds (walls at 960)
const ARENA_HH: float = 560.0

var overlord_mode: OverlordMode = null
var overlord_state: OverlordState = null
var enemies_container: Node2D = null
var targets: Array[Node] = []  # player targets for spawned enemies

var _cursor_pos: Vector2 = Vector2(500.0, 0.0)
var _cursor_sprite: Sprite2D = null
var _cursor_safe_indicator: Node2D = null  # turns red when in safe zone
var _cooldowns: Dictionary = {}  # {button_def_index: float}
var _in_safe_zone: bool = false

# Keyboard fallback keys for 10 deploy buttons (indices into BUTTON_DEFS)
# Z=A, X=B, C=X, V=Y, I=Up, K=Down, J=Left, L=Right, Q=LB, E=RB
const KB_DEPLOY_KEYS: Array = [
	KEY_Z, KEY_X, KEY_C, KEY_V,
	KEY_I, KEY_K, KEY_J, KEY_L,
	KEY_Q, KEY_E,
]

signal enemy_spawned_by_overlord(enemy: BaseEnemy)

func _ready() -> void:
	_build_cursor()
	_ensure_deploy_actions()

func _ensure_deploy_actions() -> void:
	for i in KB_DEPLOY_KEYS.size():
		var action_name: String = "p2_deploy_%d" % i
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			var ev := InputEventKey.new()
			ev.keycode = KB_DEPLOY_KEYS[i]
			InputMap.action_add_event(action_name, ev)

func _build_cursor() -> void:
	# Cursor reticle - a simple crosshair drawn with lines
	_cursor_safe_indicator = Node2D.new()
	_cursor_safe_indicator.name = "CursorReticle"
	add_child(_cursor_safe_indicator)

	# Use a ring drawn via _draw on the indicator
	_cursor_safe_indicator.set_script(load("res://scenes/game/OverlordCursor.gd") if ResourceLoader.exists("res://scenes/game/OverlordCursor.gd") else null)

	# Fallback: simple sprite-based cursor
	_cursor_sprite = Sprite2D.new()
	_cursor_sprite.name = "CursorSprite"
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	# Draw a simple crosshair
	for i in 32:
		img.set_pixel(i, 15, Color(0.2, 1.0, 0.4, 0.9))
		img.set_pixel(i, 16, Color(0.2, 1.0, 0.4, 0.9))
		img.set_pixel(15, i, Color(0.2, 1.0, 0.4, 0.9))
		img.set_pixel(16, i, Color(0.2, 1.0, 0.4, 0.9))
	# Draw a circle outline
	for angle_i in 64:
		var angle := angle_i * TAU / 64.0
		var px := int(16.0 + cos(angle) * 12.0)
		var py := int(16.0 + sin(angle) * 12.0)
		if px >= 0 and px < 32 and py >= 0 and py < 32:
			img.set_pixel(px, py, Color(0.2, 1.0, 0.4, 0.9))
	_cursor_sprite.texture = ImageTexture.create_from_image(img)
	_cursor_sprite.z_index = 50
	add_child(_cursor_sprite)
	_cursor_sprite.global_position = _cursor_pos

func _process(delta: float) -> void:
	if overlord_mode == null or overlord_state == null:
		return
	if not overlord_mode.is_wave_active():
		_cursor_sprite.visible = false
		return
	_cursor_sprite.visible = true

	# Process wave timer
	overlord_mode.process_wave(delta)

	# Move cursor with P2 input (player_index = 1)
	var move_dir := InputManager.get_move_dir(1)
	_cursor_pos += move_dir * CURSOR_SPEED * delta
	_cursor_pos.x = clampf(_cursor_pos.x, -ARENA_HW, ARENA_HW)
	_cursor_pos.y = clampf(_cursor_pos.y, -ARENA_HH, ARENA_HH)
	_cursor_sprite.global_position = _cursor_pos

	# Check safe zone around all players
	_in_safe_zone = false
	for t in targets:
		if is_instance_valid(t) and t is Player and t.is_physics_processing():
			if _cursor_pos.distance_to(t.global_position) < SAFE_ZONE_RADIUS:
				_in_safe_zone = true
				break
	_cursor_sprite.modulate = Color(1.0, 0.3, 0.3) if _in_safe_zone else Color(0.2, 1.0, 0.4)

	# Tick cooldowns
	for btn_idx in _cooldowns.keys():
		if _cooldowns[btn_idx] > 0.0:
			_cooldowns[btn_idx] -= delta

	# Check deploy inputs
	_check_deploy_inputs()

func _check_deploy_inputs() -> void:
	var device: int = 1  # Overlord is always gamepad device 1

	for i in OverlordState.BUTTON_DEFS.size():
		var pressed := false
		# Gamepad button
		var joy_id: int = OverlordState.BUTTON_DEFS[i][0]
		if Input.is_joy_button_pressed(device, joy_id):
			pressed = true
		# Keyboard fallback
		var kb_action: String = "p2_deploy_%d" % i
		if not pressed and InputMap.has_action(kb_action) and Input.is_action_just_pressed(kb_action):
			pressed = true

		if pressed and _cooldowns.get(i, 0.0) <= 0.0 and not _in_safe_zone:
			_try_deploy(i)

func _try_deploy(button_index: int) -> void:
	var enemy_id := overlord_state.deploy_enemy(button_index)
	if enemy_id == &"":
		return

	var data_path := "res://resources/enemies/%s.tres" % enemy_id
	if not ResourceLoader.exists(data_path):
		return
	var enemy_data: EnemyData = ResourceLoader.load(data_path)
	if enemy_data == null:
		return

	var enemy_node := _spawn_enemy(enemy_data)
	if enemy_node:
		_cooldowns[button_index] = BASE_COOLDOWN * overlord_state.spawn_cooldown_mult
		overlord_mode.active_overlord_enemies += 1

func _spawn_enemy(data: EnemyData) -> BaseEnemy:
	## Builds an enemy node using the same pattern as WaveManager._spawn_next().
	var enemy_node := BaseEnemy.new()
	enemy_node.collision_layer = 2
	enemy_node.collision_mask  = 3

	# Sprite
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	var sprite_path: String = OverlordState.ENEMY_SPRITES.get(data.id, "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.2, 0.2))
		sprite.texture = ImageTexture.create_from_image(img)
	if data.sprite_scale != Vector2.ONE:
		sprite.scale = data.sprite_scale
	enemy_node.add_child(sprite)

	# Collision
	var col := CollisionShape2D.new()
	col.name = "CollisionShape2D"
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	enemy_node.add_child(col)

	# Navigation
	var nav := NavigationAgent2D.new()
	nav.name = "NavigationAgent2D"
	nav.path_desired_distance = 8.0
	nav.target_desired_distance = 16.0
	enemy_node.add_child(nav)

	# Contact area
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 1
	area.name = "ContactArea"
	var area_col := CollisionShape2D.new()
	var area_shape := CircleShape2D.new()
	area_shape.radius = 14.0
	area_col.shape = area_shape
	area.add_child(area_col)
	enemy_node.add_child(area)

	enemy_node.enemy_data = data
	var parent := enemies_container if enemies_container else get_tree().current_scene
	parent.add_child(enemy_node)

	# Wire contact signals after adding to tree
	area.body_entered.connect(enemy_node._on_body_entered)
	area.body_exited.connect(enemy_node._on_body_exited)

	enemy_node.register_targets(targets)

	# Apply wave scaling + Overlord global upgrades
	var wave_mult := overlord_mode.get_wave_multiplier() * overlord_state.hp_mult
	var spd_mult := overlord_mode.get_speed_multiplier() * overlord_state.speed_mult
	enemy_node.scale_with_wave(wave_mult, spd_mult)
	# Apply flat armor bonus
	if overlord_state.armor_bonus > 0.0:
		enemy_node.enemy_data = enemy_node.enemy_data.duplicate()
		enemy_node.enemy_data.armor += overlord_state.armor_bonus

	# Summoner support
	if data.ai_type in [EnemyData.AIType.ELITE_SUMMONER]:
		enemy_node.spawn_container = parent

	enemy_node.global_position = _cursor_pos
	enemy_node.died.connect(_on_overlord_enemy_died)

	# Spawn pop-in animation
	enemy_node.scale = Vector2.ZERO
	var tween := enemy_node.create_tween()
	tween.tween_property(enemy_node, "scale", Vector2(1.2, 1.2), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(enemy_node, "scale", Vector2(1.0, 1.0), 0.08)

	enemy_spawned_by_overlord.emit(enemy_node)
	return enemy_node

func _on_overlord_enemy_died(enemy: BaseEnemy) -> void:
	overlord_mode.on_overlord_enemy_died()

func get_cooldown_ratio(button_index: int) -> float:
	## Returns 0.0 (ready) to 1.0 (full cooldown) for HUD display.
	var max_cd := BASE_COOLDOWN * overlord_state.spawn_cooldown_mult
	if max_cd <= 0.0:
		return 0.0
	return clampf(_cooldowns.get(button_index, 0.0) / max_cd, 0.0, 1.0)

func hide_cursor() -> void:
	_cursor_sprite.visible = false
