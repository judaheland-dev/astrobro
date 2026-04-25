extends Node

## InputManager - routes keyboard/mouse and gamepad input per player device.
## Player 0: keyboard + mouse; gamepad assigned via _device_map[0]
## Player 1: IJKL keyboard; gamepad assigned via _device_map[1]
##
## _device_map maps player_index -> SDL device ID.
## It is built from Input.get_connected_joypads() on _ready() and updated
## via Input.joy_connection_changed so IDs never drift mid-session.

const DEADZONE: float = 0.2

# _device_map[player_index] = SDL device id, or -1 if no pad assigned.
var _device_map: Array[int] = [-1, -1]

func _ready() -> void:
	# Assign currently connected pads in the order SDL reports them.
	_rebuild_device_map()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _rebuild_device_map() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	_device_map[0] = pads[0] if pads.size() > 0 else -1
	_device_map[1] = pads[1] if pads.size() > 1 else -1

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# Rebuild the full map so connection-order stays stable.
	_rebuild_device_map()

# Returns normalized movement direction for given player index (0-based).
func get_move_dir(player_index: int) -> Vector2:
	if player_index == 0:
		var dir := Vector2.ZERO
		if Input.is_action_pressed("move_up"):    dir.y -= 1.0
		if Input.is_action_pressed("move_down"):  dir.y += 1.0
		if Input.is_action_pressed("move_left"):  dir.x -= 1.0
		if Input.is_action_pressed("move_right"): dir.x += 1.0
		if dir == Vector2.ZERO:
			dir = _get_gamepad_stick(_device_map[0], 0)
		return dir.normalized() if dir.length() > DEADZONE else Vector2.ZERO
	else:
		# P2: IJKL keyboard first, then assigned gamepad
		var dir := Vector2.ZERO
		if Input.is_action_pressed("p2_move_up"):    dir.y -= 1.0
		if Input.is_action_pressed("p2_move_down"):  dir.y += 1.0
		if Input.is_action_pressed("p2_move_left"):  dir.x -= 1.0
		if Input.is_action_pressed("p2_move_right"): dir.x += 1.0
		if dir == Vector2.ZERO:
			dir = _get_gamepad_stick(_device_map[player_index], 0)
		return dir.normalized() if dir.length() > DEADZONE else Vector2.ZERO

# Returns aim direction. Player 0: mouse world position relative to player.
# Player 1: right analog stick, or auto-aim toward nearest enemy if no stick input.
func get_aim_dir(player_index: int, player_world_pos: Vector2) -> Vector2:
	if player_index == 0:
		# Right analog stick takes priority over mouse for P1
		var stick := _get_gamepad_stick(_device_map[0], 1)
		if stick.length() > DEADZONE:
			return stick.normalized()
		var viewport: Viewport = Engine.get_main_loop().root.get_viewport()
		var mouse_world: Vector2 = viewport.get_canvas_transform().affine_inverse() * viewport.get_mouse_position()
		var dir: Vector2 = mouse_world - player_world_pos
		return dir.normalized() if dir.length() > 1.0 else Vector2.RIGHT
	else:
		# P2: right analog stick (assigned pad), fall back to movement direction
		var dir := _get_gamepad_stick(_device_map[player_index], 1)
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
		# P2: Space key or assigned gamepad right shoulder
		if Input.is_action_pressed("p2_fire"):
			return true
		return Input.is_joy_button_pressed(_device_map[player_index], JOY_BUTTON_RIGHT_SHOULDER)

# Returns true if interact was just pressed.
func is_interact_pressed(player_index: int) -> bool:
	if player_index == 0:
		return Input.is_action_just_pressed("interact")
	else:
		return Input.is_joy_button_pressed(_device_map[player_index], JOY_BUTTON_A)

# Returns true if the boost (afterburner) button was just pressed this frame.
func is_boosting(player_index: int) -> bool:
	if player_index == 0:
		return Input.is_action_just_pressed("boost")
	else:
		return Input.is_action_just_pressed("p2_boost")

func _get_gamepad_stick(device: int, stick: int) -> Vector2:
	# stick 0 = left analog, stick 1 = right analog
	if device < 0:
		return Vector2.ZERO
	var x_axis: int = JOY_AXIS_LEFT_X if stick == 0 else JOY_AXIS_RIGHT_X
	var y_axis: int = JOY_AXIS_LEFT_Y if stick == 0 else JOY_AXIS_RIGHT_Y
	return Vector2(
		Input.get_joy_axis(device, x_axis),
		Input.get_joy_axis(device, y_axis)
	)
