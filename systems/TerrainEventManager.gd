extends Node
class_name TerrainEventManager

## TerrainEventManager - spawns temporary environmental hazard events during waves.
## Events are one at a time, last ~12 s, and trigger again every 20-35 s.
## Three events: Asteroid Field, Solar Flare, Space Gas.

var players: Array[Player] = []
var enemies_container: Node = null
var wave_manager: WaveManager = null

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

enum EventType { ASTEROID_FIELD, SOLAR_FLARE, SPACE_GAS }

const EVENT_DURATION: float = 12.0
const FIRST_EVENT_DELAY: float = 18.0
const MIN_INTERVAL: float = 20.0
const MAX_INTERVAL: float = 35.0

var _event_timer: float = FIRST_EVENT_DELAY
var _active_event: Node = null

# Asteroid state - keyed by Area2D node, value is Array of bodies in zone
var _asteroid_bodies: Dictionary = {}
var _asteroid_damage_timer: float = 0.0
const ASTEROID_DAMAGE_INTERVAL: float = 1.0
const ASTEROID_DAMAGE: float = 6.0

# Space gas state - keyed by body node, value is original move_speed
var _gas_slowed: Dictionary = {}
var _gas_area: Area2D = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _tick_asteroid_damage(delta: float) -> void:
	if _asteroid_bodies.is_empty():
		return
	_asteroid_damage_timer -= delta
	if _asteroid_damage_timer > 0.0:
		return
	_asteroid_damage_timer = ASTEROID_DAMAGE_INTERVAL
	for area in _asteroid_bodies:
		if not is_instance_valid(area):
			continue
		for body in _asteroid_bodies[area]:
			if is_instance_valid(body) and body.has_method("take_damage"):
				body.take_damage(ASTEROID_DAMAGE)

# ---------------------------------------------------------------------------
# Event dispatch
# ---------------------------------------------------------------------------

func _trigger_random_event() -> void:
	var choice: EventType = randi() % 3 as EventType
	match choice:
		EventType.ASTEROID_FIELD:
			_active_event = _spawn_asteroid_field()
		EventType.SOLAR_FLARE:
			_active_event = _spawn_solar_flare()
		EventType.SPACE_GAS:
			_active_event = _spawn_space_gas()

func _on_event_finished(event_node: Node) -> void:
	if event_node == _active_event:
		_active_event = null

# ---------------------------------------------------------------------------
# Event: Asteroid Field
# ---------------------------------------------------------------------------

func _spawn_asteroid_field() -> Node:
	var root := Node2D.new()
	root.name = "AsteroidField"
	root.z_index = 2
	get_tree().current_scene.add_child(root)

	var meteor_tex: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/meteorBrown_big1.png"):
		meteor_tex = load("res://assets/sprites/meteorBrown_big1.png")

	var hw := 700.0
	var hh := 450.0

	_asteroid_bodies.clear()
	_asteroid_damage_timer = ASTEROID_DAMAGE_INTERVAL

	for i in 5:
		var pos := Vector2(randf_range(-hw, hw), randf_range(-hh, hh))

		var rock := Node2D.new()
		rock.position = pos
		root.add_child(rock)

		var spr := Sprite2D.new()
		spr.name = "Sprite"
		var rock_scale := randf_range(0.7, 1.2)
		spr.scale = Vector2.ONE * rock_scale
		spr.rotation = randf_range(0.0, TAU)
		spr.modulate = Color(1.0, 1.0, 1.0, 0.0)
		if meteor_tex:
			spr.texture = meteor_tex
		else:
			var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.55, 0.35, 0.15))
			spr.texture = ImageTexture.create_from_image(img)
		rock.add_child(spr)

		var rot_speed := randf_range(0.4, 1.2) * (1.0 if randf() > 0.5 else -1.0)
		spr.set_meta("rot_speed", rot_speed)

		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 3
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 52.0 * rock_scale
		col.shape = shape
		area.add_child(col)
		rock.add_child(area)

		var bodies: Array[Node] = []
		_asteroid_bodies[area] = bodies
		area.body_entered.connect(_on_asteroid_body_entered.bind(area))
		area.body_exited.connect(_on_asteroid_body_exited.bind(area))

		# Fade in
		var fade := spr.create_tween()
		fade.tween_property(spr, "modulate:a", 1.0, 0.5)

	# Rotation is handled below via a recurring tween loop trick -- use _process on the root instead.
	# Attach a lightweight script to drive per-frame rotation.
	root.set_meta("rot_sprockets", _collect_rock_sprites(root))

	# End after EVENT_DURATION
	var lifetime := create_tween()
	lifetime.tween_interval(EVENT_DURATION - 0.4)
	lifetime.tween_callback(_begin_asteroid_fadeout.bind(root))

	return root

func _collect_rock_sprites(root: Node2D) -> Array:
	var out := []
	for rock in root.get_children():
		var spr: Node = rock.get_node_or_null("Sprite")
		if spr:
			out.append(spr)
	return out

func _process_asteroid_rotation(delta: float, root: Node2D) -> void:
	if not is_instance_valid(root):
		return
	for spr in root.get_meta("rot_sprockets", []):
		if is_instance_valid(spr):
			var node := spr as Node2D
			if node:
				var rs: float = node.get_meta("rot_speed", 0.6)
				node.rotation += rs * delta

func _begin_asteroid_fadeout(root: Node2D) -> void:
	if not is_instance_valid(root):
		return
	var sprites := _collect_rock_sprites(root)
	for spr in sprites:
		if is_instance_valid(spr):
			var node := spr as Node
			if node:
				var t: Tween = node.create_tween()
				t.tween_property(node, "modulate:a", 0.0, 0.4)
	# Disconnect signals and clear tracking state
	for area in _asteroid_bodies:
		if is_instance_valid(area):
			if area.body_entered.is_connected(_on_asteroid_body_entered):
				area.body_entered.disconnect(_on_asteroid_body_entered)
			if area.body_exited.is_connected(_on_asteroid_body_exited):
				area.body_exited.disconnect(_on_asteroid_body_exited)
	_asteroid_bodies.clear()
	var finish := create_tween()
	finish.tween_interval(0.4)
	finish.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
		_on_event_finished(root)
	)

func _on_asteroid_body_entered(body: Node, area: Area2D) -> void:
	if not _asteroid_bodies.has(area):
		return
	if not _asteroid_bodies[area].has(body):
		_asteroid_bodies[area].append(body)
		if body.has_method("take_damage"):
			body.take_damage(ASTEROID_DAMAGE)

func _on_asteroid_body_exited(body: Node, area: Area2D) -> void:
	if _asteroid_bodies.has(area):
		_asteroid_bodies[area].erase(body)

# Override _process to also tick asteroid sprite rotation
func _process(delta: float) -> void:
	if wave_manager == null or not wave_manager.is_running:
		return

	if _active_event != null:
		_tick_asteroid_damage(delta)
		if _active_event is Node2D and _active_event.name == "AsteroidField":
			_process_asteroid_rotation(delta, _active_event as Node2D)
		return

	_event_timer -= delta
	if _event_timer <= 0.0:
		_trigger_random_event()
		_event_timer = randf_range(MIN_INTERVAL, MAX_INTERVAL)

# ---------------------------------------------------------------------------
# Event: Solar Flare
# ---------------------------------------------------------------------------

func _spawn_solar_flare() -> Node:
	var layer := CanvasLayer.new()
	layer.name = "SolarFlare"
	layer.layer = 3
	get_tree().current_scene.add_child(layer)

	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1.0, 0.45, 0.05, 0.0)
	# Full-screen: anchor to full rect
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)

	GameManager.solar_flare_active = true

	# Fade in
	var fade_in := rect.create_tween()
	fade_in.tween_property(rect, "color:a", 0.09, 0.5)

	# Pulse loop
	var pulse := rect.create_tween()
	pulse.set_loops()
	pulse.tween_property(rect, "color:a", 0.14, 1.5).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(rect, "color:a", 0.06, 1.5).set_trans(Tween.TRANS_SINE)

	layer.set_meta("pulse_tween", pulse)

	var lifetime := create_tween()
	lifetime.tween_interval(EVENT_DURATION - 0.4)
	lifetime.tween_callback(_begin_flare_fadeout.bind(layer, rect))

	return layer

func _begin_flare_fadeout(layer: CanvasLayer, rect: ColorRect) -> void:
	if not is_instance_valid(layer):
		GameManager.solar_flare_active = false
		_on_event_finished(layer)
		return
	# Kill pulse tween
	var pt = layer.get_meta("pulse_tween", null)
	if pt is Tween:
		pt.kill()
	var fade := rect.create_tween()
	fade.tween_property(rect, "color:a", 0.0, 0.4)
	var finish := create_tween()
	finish.tween_interval(0.4)
	finish.tween_callback(func():
		GameManager.solar_flare_active = false
		if is_instance_valid(layer):
			layer.queue_free()
		_on_event_finished(layer)
	)

# ---------------------------------------------------------------------------
# Event: Space Gas
# ---------------------------------------------------------------------------

const GAS_ZONE_W: float = 700.0
const GAS_ZONE_H: float = 500.0
const GAS_SPEED_MULT: float = 0.5

func _spawn_space_gas() -> Node:
	var cx := randf_range(-200.0, 200.0)
	var cy := randf_range(-100.0, 100.0)
	var center := Vector2(cx, cy)

	var root := Node2D.new()
	root.name = "SpaceGas"
	root.position = center
	root.z_index = 1
	get_tree().current_scene.add_child(root)

	# Visual: irregular blob polygon - 24 vertices with per-vertex radial jitter
	var poly := Polygon2D.new()
	var base_rx := GAS_ZONE_W * 0.5
	var base_ry := GAS_ZONE_H * 0.5
	var num_pts := 24
	var verts := PackedVector2Array()
	for vi in num_pts:
		var angle := (TAU / num_pts) * vi
		var jitter := randf_range(0.65, 1.0)
		verts.append(Vector2(cos(angle) * base_rx * jitter, sin(angle) * base_ry * jitter))
	poly.polygon = verts
	poly.color = Color(0.15, 0.9, 0.6, 0.0)
	root.add_child(poly)

	# Fade in
	var fade_in := poly.create_tween()
	fade_in.tween_property(poly, "color:a", 0.14, 0.5)

	# Pulse
	var pulse := poly.create_tween()
	pulse.set_loops()
	pulse.tween_property(poly, "color:a", 0.18, 2.0).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(poly, "color:a", 0.10, 2.0).set_trans(Tween.TRANS_SINE)
	root.set_meta("pulse_tween", pulse)

	# Collision area
	_gas_slowed.clear()
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 3
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = (GAS_ZONE_W + GAS_ZONE_H) * 0.25
	col.shape = shape
	area.add_child(col)
	root.add_child(area)
	_gas_area = area

	area.body_entered.connect(_on_gas_body_entered)
	area.body_exited.connect(_on_gas_body_exited)

	var lifetime := create_tween()
	lifetime.tween_interval(EVENT_DURATION - 0.4)
	lifetime.tween_callback(_begin_gas_fadeout.bind(root, poly))

	return root

func _on_gas_body_entered(body: Node) -> void:
	if not body.has_method("take_damage"):
		return
	if not "move_speed" in body:
		return
	if _gas_slowed.has(body):
		return
	_gas_slowed[body] = body.move_speed
	body.move_speed *= GAS_SPEED_MULT

func _on_gas_body_exited(body: Node) -> void:
	if _gas_slowed.has(body):
		if is_instance_valid(body):
			body.move_speed = _gas_slowed[body]
		_gas_slowed.erase(body)

func _begin_gas_fadeout(root: Node2D, poly: Polygon2D) -> void:
	# Restore all bodies still inside the zone
	for body in _gas_slowed:
		if is_instance_valid(body):
			body.move_speed = _gas_slowed[body]
	_gas_slowed.clear()

	# Disconnect area signals
	if is_instance_valid(_gas_area):
		if _gas_area.body_entered.is_connected(_on_gas_body_entered):
			_gas_area.body_entered.disconnect(_on_gas_body_entered)
		if _gas_area.body_exited.is_connected(_on_gas_body_exited):
			_gas_area.body_exited.disconnect(_on_gas_body_exited)
	_gas_area = null

	if not is_instance_valid(root):
		_on_event_finished(root)
		return

	var pt = root.get_meta("pulse_tween", null)
	if pt is Tween:
		pt.kill()
	var fade := poly.create_tween()
	fade.tween_property(poly, "color:a", 0.0, 0.4)
	var finish := create_tween()
	finish.tween_interval(0.4)
	finish.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
		_on_event_finished(root)
	)
