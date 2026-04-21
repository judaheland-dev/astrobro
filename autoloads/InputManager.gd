extends Node

## InputManager - routes keyboard/mouse and gamepad input per player device.
## Player 0: keyboard + mouse (device_id = -1 in Godot = any keyboard)
## Player 1: gamepad device 0 (first gamepad)
## Player 2: IJKL keyboard + gamepad device 1 (second gamepad only)

const DEADZONE: float = 0.2

# Returns normalized movement direction for given player index (0-based).
func get_move_dir(player_index: int) -> Vector2:
	if player_index == 0:
		var dir := Vector2.ZERO
		if Input.is_action_pressed("move_up"):    dir.y -= 1.0
		if Input.is_action_pressed("move_down"):  dir.y += 1.0
		if Input.is_action_pressed("move_left"):  dir.x -= 1.0
		if Input.is_action_pressed("move_right"): dir.x += 1.0
		if dir == Vector2.ZERO:
			dir = _get_gamepad_stick(0, 0)
		return dir.normalized() if dir.length() > DEADZONE else Vector2.ZERO
	else:
		# P2: IJKL keyboard first, then gamepad 2 (device 1 only)
		var dir := Vector2.ZERO
		if Input.is_action_pressed("p2_move_up"):    dir.y -= 1.0
		if Input.is_action_pressed("p2_move_down"):  dir.y += 1.0
		if Input.is_action_pressed("p2_move_left"):  dir.x -= 1.0
		if Input.is_action_pressed("p2_move_right"): dir.x += 1.0
		if dir == Vector2.ZERO:
			var device: int = player_index
			dir = _get_gamepad_stick(device, 0)
		return dir.normalized() if dir.length() > DEADZONE else Vector2.ZERO

# Returns aim direction. Player 0: mouse world position relative to player.
# Player 1: right analog stick, or auto-aim toward nearest enemy if no stick input.
func get_aim_dir(player_index: int, player_world_pos: Vector2) -> Vector2:
	if player_index == 0:
		# Right analog stick takes priority over mouse for P1
		var stick := _get_gamepad_stick(0, 1)
		if stick.length() > DEADZONE:
			return stick.normalized()
		var viewport: Viewport = Engine.get_main_loop().root.get_viewport()
		var mouse_world: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
		var dir: Vector2 = mouse_world - player_world_pos
		return dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	else:
		# P2: right analog stick (gamepad 2 only), fall back to movement direction
		var device: int = player_index
		var dir := _get_gamepad_stick(device, 1)
		if dir.length() > DEADZONE:
			return dir.normalized()
		# Fall back to the movement direction so P2 always fires forward
		var move := get_move_dir(player_index)
		return move if move != Vector2.ZERO else Vector2.RIGHT

# Returns true if fire is held this frame.
func is_firing(player_index: int) -> bool:
	if player_index == 0:
		return Input.is_action_pressed("fire")
	else:
		# P2: Space key or gamepad 2 (device 1) right shoulder
		if Input.is_action_pressed("p2_fire"):
			return true
		var device: int = player_index
		return Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)

# Returns true if interact was just pressed.
func is_interact_pressed(player_index: int) -> bool:
	if player_index == 0:
		return Input.is_action_just_pressed("interact")
	else:
		var device: int = player_index
		return Input.is_joy_button_pressed(device, JOY_BUTTON_A)

func _get_gamepad_stick(device: int, stick: int) -> Vector2:
	# stick 0 = left analog, stick 1 = right analog
	var x_axis: int = JOY_AXIS_LEFT_X if stick == 0 else JOY_AXIS_RIGHT_X
	var y_axis: int = JOY_AXIS_LEFT_Y if stick == 0 else JOY_AXIS_RIGHT_Y
	return Vector2(
		Input.get_joy_axis(device, x_axis),
		Input.get_joy_axis(device, y_axis)
	)
