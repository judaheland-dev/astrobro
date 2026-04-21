extends Node
## Plasma Coil passive: every 3 s, pulses outward and burns all enemies
## within 300 px for 3 ticks of 4 damage each (12 total per pulse).

const PULSE_COOLDOWN: float = 3.0
const PULSE_RADIUS: float = 300.0
const BURN_DAMAGE: float = 4.0
const BURN_TICKS: int = 3
const BURN_INTERVAL: float = 0.4

var _player: Player
var _pulse_timer: float = 1.0   # slight delay before first pulse
# Each entry: { targets: Array, ticks: int, timer: float }
var _burn_queue: Array = []

func setup(player: Player) -> void:
	_player = player

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	_pulse_timer -= delta
	if _pulse_timer <= 0.0:
		_pulse_timer = PULSE_COOLDOWN
		_fire_pulse()

	var i := _burn_queue.size() - 1
	while i >= 0:
		var burn: Dictionary = _burn_queue[i]
		burn["timer"] -= delta
		if burn["timer"] <= 0.0:
			burn["timer"] = BURN_INTERVAL
			burn["ticks"] -= 1
			for target in burn["targets"]:
				if is_instance_valid(target):
					target.take_damage(BURN_DAMAGE)
			if burn["ticks"] <= 0:
				_burn_queue.remove_at(i)
		i -= 1

func _fire_pulse() -> void:
	var space := _player.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PULSE_RADIUS
	params.shape = circle
	params.transform = Transform2D(0.0, _player.global_position)
	params.collision_mask = 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits := space.intersect_shape(params, 20)

	var targets: Array = []
	for hit in hits:
		var body: Node = hit["collider"]
		if body != null and body.has_method("take_damage"):
			targets.append(body)
	if targets.is_empty():
		return

	# Visual: expanding ring that fades out
	var ring := ColorRect.new()
	ring.color = Color(1.0, 0.45, 0.1, 0.55)
	ring.size = Vector2(PULSE_RADIUS * 2.0, PULSE_RADIUS * 2.0)
	ring.pivot_offset = ring.size * 0.5
	ring.position = _player.global_position - ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(ring)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.3, 1.3), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.5)
	rt.chain().tween_callback(ring.queue_free)

	_burn_queue.append({"targets": targets, "ticks": BURN_TICKS, "timer": BURN_INTERVAL})
