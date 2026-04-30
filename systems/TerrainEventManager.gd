extends Node
class_name TerrainEventManager

## TerrainEventManager - spawns temporary environmental hazard events during waves.
## Events fire one at a time, at varying intervals and durations.
## Nine event types with randomized size, scope, and arena placement.

var players: Array[Player] = []
var enemies_container: Node = null
var wave_manager: WaveManager = null
var hud: CanvasLayer = null

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------

enum EventType {
	ASTEROID_FIELD,
	SOLAR_FLARE,
	SPACE_GAS,
	GRAVITY_WELL,
	MINEFIELD,
	ION_STORM,
	DEBRIS_CORRIDOR,
	BLACK_HOLE,
	PULSAR_BURST,
}

const FIRST_EVENT_DELAY: float = 18.0
const MIN_INTERVAL: float = 20.0
const MAX_INTERVAL: float = 35.0

var _event_timer: float = FIRST_EVENT_DELAY
var _active_event: Node = null

# Hazard tick damage - keyed by Area2D node -> Array of bodies
var _hazard_bodies: Dictionary = {}
var _hazard_damage_timer: float = 0.0
const HAZARD_DAMAGE_INTERVAL: float = 1.0

# Space gas state - keyed by body node -> original move_speed
var _gas_slowed: Dictionary = {}
var _gas_area: Area2D = null

# Gravity event state (shared by Gravity Well and Black Hole)
var _gravity_center: Vector2 = Vector2.ZERO
var _gravity_strength: float = 0.0
var _gravity_radius: float = 0.0
var _gravity_active: bool = false

# Pulsar state
var _pulsar_timer: float = 0.0
var _pulsar_interval: float = 3.0
var _pulsar_center: Vector2 = Vector2.ZERO
var _pulsar_active: bool = false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _random_arena_pos(hw: float = 700.0, hh: float = 450.0) -> Vector2:
	return Vector2(randf_range(-hw, hw), randf_range(-hh, hh))

func _announce(text: String, color: Color = Color(1.0, 0.8, 0.2)) -> void:
	if is_instance_valid(hud):
		hud.call("show_event_banner", text, color)

func _get_all_bodies() -> Array:
	var result: Array = []
	for p in players:
		if is_instance_valid(p):
			result.append(p)
	if enemies_container:
		for e in enemies_container.get_children():
			if is_instance_valid(e):
				result.append(e)
	return result

func _tick_hazard_damage(delta: float) -> void:
	if _hazard_bodies.is_empty():
		return
	_hazard_damage_timer -= delta
	if _hazard_damage_timer > 0.0:
		return
	_hazard_damage_timer = HAZARD_DAMAGE_INTERVAL
	for area in _hazard_bodies:
		if not is_instance_valid(area):
			continue
		var dmg: float = area.get_meta("damage_per_sec", 6.0)
		for body in _hazard_bodies[area]:
			if is_instance_valid(body) and body.has_method("take_damage"):
				body.take_damage(dmg)

# ---------------------------------------------------------------------------
# Event dispatch
# ---------------------------------------------------------------------------

func _trigger_random_event() -> void:
	var choice: int = randi() % 9
	match choice as EventType:
		EventType.ASTEROID_FIELD:
			_active_event = _spawn_asteroid_field()
		EventType.SOLAR_FLARE:
			_active_event = _spawn_solar_flare()
		EventType.SPACE_GAS:
			_active_event = _spawn_space_gas()
		EventType.GRAVITY_WELL:
			_active_event = _spawn_gravity_well()
		EventType.MINEFIELD:
			_active_event = _spawn_minefield()
		EventType.ION_STORM:
			_active_event = _spawn_ion_storm()
		EventType.DEBRIS_CORRIDOR:
			_active_event = _spawn_debris_corridor()
		EventType.BLACK_HOLE:
			_active_event = _spawn_black_hole()
		EventType.PULSAR_BURST:
			_active_event = _spawn_pulsar_burst()

func _on_event_finished(event_node: Node) -> void:
	if event_node == _active_event:
		_active_event = null

# ---------------------------------------------------------------------------
# _process
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if wave_manager == null or not wave_manager.is_running:
		return

	if _active_event != null:
		_tick_hazard_damage(delta)

		if is_instance_valid(_active_event) and _active_event.name == "AsteroidField":
			_process_asteroid_rotation(delta, _active_event as Node2D)

		if _gravity_active:
			_process_gravity_pull(delta)

		if _pulsar_active:
			_pulsar_timer -= delta
			if _pulsar_timer <= 0.0:
				_pulsar_timer = _pulsar_interval
				_fire_pulsar_ring()

		return

	_event_timer -= delta
	if _event_timer <= 0.0:
		_trigger_random_event()
		_event_timer = randf_range(MIN_INTERVAL, MAX_INTERVAL)

# ---------------------------------------------------------------------------
# Event: Asteroid Field
# ---------------------------------------------------------------------------

func _spawn_asteroid_field() -> Node:
	var duration := randf_range(8.0, 18.0)
	var root := Node2D.new()
	root.name = "AsteroidField"
	root.z_index = 2
	get_tree().current_scene.add_child(root)

	var meteor_paths := [
		"res://assets/sprites/meteorBrown_big1.png",
		"res://assets/sprites/meteorBrown_big2.png",
		"res://assets/sprites/meteorBrown_big3.png",
		"res://assets/sprites/meteorBrown_big4.png",
		"res://assets/sprites/meteorBrown_med1.png",
		"res://assets/sprites/meteorBrown_med3.png",
		"res://assets/sprites/meteorGrey_big1.png",
		"res://assets/sprites/meteorGrey_big2.png",
		"res://assets/sprites/meteorGrey_big3.png",
		"res://assets/sprites/meteorGrey_big4.png",
	]
	var loaded_textures: Array = []
	for p in meteor_paths:
		if ResourceLoader.exists(p):
			loaded_textures.append(load(p))

	var cluster := randf() > 0.5
	var hw := 280.0 if cluster else 900.0
	var hh := 180.0 if cluster else 560.0
	var cluster_center := _random_arena_pos(620.0, 400.0)

	_hazard_bodies.clear()
	_hazard_damage_timer = HAZARD_DAMAGE_INTERVAL

	var count := randi_range(3, 10)
	for i in count:
		var pos := cluster_center + Vector2(randf_range(-hw, hw), randf_range(-hh, hh))

		var rock := Node2D.new()
		rock.position = pos
		root.add_child(rock)

		var spr := Sprite2D.new()
		spr.name = "Sprite"
		var rock_scale := randf_range(0.5, 1.8)
		spr.scale = Vector2.ONE * rock_scale
		spr.rotation = randf_range(0.0, TAU)
		spr.modulate = Color(1.0, 1.0, 1.0, 0.0)
		if loaded_textures.size() > 0:
			spr.texture = loaded_textures[randi() % loaded_textures.size()]
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
		area.set_meta("damage_per_sec", 6.0)
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 52.0 * rock_scale
		col.shape = shape
		area.add_child(col)
		rock.add_child(area)

		var bodies: Array[Node] = []
		_hazard_bodies[area] = bodies
		area.body_entered.connect(_on_hazard_body_entered.bind(area, true))
		area.body_exited.connect(_on_hazard_body_exited.bind(area))

		var fade := spr.create_tween()
		fade.tween_property(spr, "modulate:a", 1.0, 0.5)

	root.set_meta("rot_sprockets", _collect_rock_sprites(root))

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_asteroid_fadeout.bind(root))

	_announce("ASTEROID FIELD", Color(0.9, 0.7, 0.4))
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
		_on_event_finished(root)
		return
	var sprites := _collect_rock_sprites(root)
	for spr in sprites:
		if is_instance_valid(spr):
			var node := spr as Node
			if node:
				var t: Tween = node.create_tween()
				t.tween_property(node, "modulate:a", 0.0, 0.4)
	for area in _hazard_bodies:
		if is_instance_valid(area):
			if area.body_entered.is_connected(_on_hazard_body_entered):
				area.body_entered.disconnect(_on_hazard_body_entered)
			if area.body_exited.is_connected(_on_hazard_body_exited):
				area.body_exited.disconnect(_on_hazard_body_exited)
	_hazard_bodies.clear()
	var finish := create_tween()
	finish.tween_interval(0.4)
	finish.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
		_on_event_finished(root)
	)

func _on_hazard_body_entered(body: Node, area: Area2D, instant_hit: bool) -> void:
	if not _hazard_bodies.has(area):
		return
	if not _hazard_bodies[area].has(body):
		_hazard_bodies[area].append(body)
		if instant_hit and body.has_method("take_damage"):
			body.take_damage(area.get_meta("damage_per_sec", 6.0))

func _on_hazard_body_exited(body: Node, area: Area2D) -> void:
	if _hazard_bodies.has(area):
		_hazard_bodies[area].erase(body)

# ---------------------------------------------------------------------------
# Event: Solar Flare
# ---------------------------------------------------------------------------

func _spawn_solar_flare() -> Node:
	var tier := randi() % 3
	var alpha_max: float = [0.06, 0.14, 0.22][tier]
	var intensity: float = [1.3, 1.5, 2.0][tier]
	var duration := randf_range(8.0, 18.0)

	var layer := CanvasLayer.new()
	layer.name = "SolarFlare"
	layer.layer = 3
	get_tree().current_scene.add_child(layer)

	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(1.0, 0.55 + 0.1 * tier, 0.05 + 0.1 * tier, 0.0)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)

	GameManager.solar_flare_active = true
	GameManager.solar_flare_intensity = intensity

	var fade_in := rect.create_tween()
	fade_in.tween_property(rect, "color:a", alpha_max * 0.6, 0.5)

	var pulse := rect.create_tween()
	pulse.set_loops()
	pulse.tween_property(rect, "color:a", alpha_max, 1.5).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(rect, "color:a", alpha_max * 0.4, 1.5).set_trans(Tween.TRANS_SINE)
	layer.set_meta("pulse_tween", pulse)

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_flare_fadeout.bind(layer, rect))

	var tier_names: Array[String] = ["WEAK SOLAR FLARE", "SOLAR FLARE", "SOLAR STORM"]
	_announce(tier_names[tier], Color(1.0, 0.7, 0.2))
	return layer

func _begin_flare_fadeout(layer: CanvasLayer, rect: ColorRect) -> void:
	GameManager.solar_flare_active = false
	GameManager.solar_flare_intensity = 1.0
	if not is_instance_valid(layer):
		_on_event_finished(layer)
		return
	var pt = layer.get_meta("pulse_tween", null)
	if pt is Tween:
		pt.kill()
	var fade := rect.create_tween()
	fade.tween_property(rect, "color:a", 0.0, 0.4)
	var finish := create_tween()
	finish.tween_interval(0.4)
	finish.tween_callback(func():
		if is_instance_valid(layer):
			layer.queue_free()
		_on_event_finished(layer)
	)

# ---------------------------------------------------------------------------
# Event: Space Gas (layered smoke sprites)
# ---------------------------------------------------------------------------

func _spawn_space_gas() -> Node:
	var tier := randi() % 3
	var zone_w: float = [300.0, 600.0, 900.0][tier]
	var zone_h: float = [200.0, 400.0, 600.0][tier]
	var speed_mult: float = [0.65, 0.50, 0.40][tier]
	var duration := randf_range(8.0, 18.0)

	var max_cx := maxf(0.0, 900.0 - zone_w * 0.5)
	var max_cy := maxf(0.0, 560.0 - zone_h * 0.5)
	var center := Vector2(randf_range(-max_cx, max_cx), randf_range(-max_cy, max_cy))

	var root := Node2D.new()
	root.name = "SpaceGas"
	root.position = center
	root.z_index = 1
	get_tree().current_scene.add_child(root)

	var smoke_paths: Array = []
	for i in range(1, 11):
		var p := "res://assets/particles/smoke_%02d.png" % i
		if ResourceLoader.exists(p):
			smoke_paths.append(p)

	var sprite_count := randi_range(5, 8)
	var gas_color := Color(0.1, 0.85, 0.5)
	var sprites: Array = []
	for _i in sprite_count:
		var spr := Sprite2D.new()
		var scale_px := randf_range(zone_w * 0.3, zone_w * 0.8)
		spr.scale = Vector2.ONE * (scale_px / 64.0)
		spr.rotation = randf_range(0.0, TAU)
		spr.position = Vector2(randf_range(-zone_w * 0.3, zone_w * 0.3), randf_range(-zone_h * 0.3, zone_h * 0.3))
		spr.modulate = Color(gas_color.r, gas_color.g, gas_color.b, 0.0)
		if smoke_paths.size() > 0:
			spr.texture = load(smoke_paths[randi() % smoke_paths.size()])
		root.add_child(spr)
		sprites.append(spr)
		var fade_in := spr.create_tween()
		fade_in.tween_property(spr, "modulate:a", randf_range(0.08, 0.18), randf_range(0.4, 0.9))

	root.set_meta("gas_sprites", sprites)

	var pulse_tween := create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_callback(func():
		for spr in sprites:
			if is_instance_valid(spr):
				var target_a := randf_range(0.06, 0.20)
				var t: Tween = spr.create_tween()
				t.tween_property(spr, "modulate:a", target_a, randf_range(1.5, 3.0)).set_trans(Tween.TRANS_SINE)
	).set_delay(2.0)
	root.set_meta("pulse_tween", pulse_tween)

	_gas_slowed.clear()
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 3
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = (zone_w + zone_h) * 0.25
	col.shape = shape
	area.add_child(col)
	root.add_child(area)
	_gas_area = area

	area.body_entered.connect(_on_gas_body_entered.bind(speed_mult))
	area.body_exited.connect(_on_gas_body_exited)

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_gas_fadeout.bind(root))

	var tier_names: Array[String] = ["GAS CLOUD", "GAS CLOUD", "DENSE GAS CLOUD"]
	_announce(tier_names[tier], Color(0.2, 1.0, 0.6))
	return root

func _on_gas_body_entered(body: Node, speed_mult: float) -> void:
	if not body.has_method("take_damage"):
		return
	if not "move_speed" in body:
		return
	if _gas_slowed.has(body):
		return
	_gas_slowed[body] = body.move_speed
	body.move_speed *= speed_mult

func _on_gas_body_exited(body: Node) -> void:
	if _gas_slowed.has(body):
		if is_instance_valid(body):
			body.move_speed = _gas_slowed[body]
		_gas_slowed.erase(body)

func _begin_gas_fadeout(root: Node2D) -> void:
	for body in _gas_slowed:
		if is_instance_valid(body):
			body.move_speed = _gas_slowed[body]
	_gas_slowed.clear()

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

	for spr in root.get_meta("gas_sprites", []):
		if is_instance_valid(spr):
			var t: Tween = spr.create_tween()
			t.tween_property(spr, "modulate:a", 0.0, 0.4)
	var finish := create_tween()
	finish.tween_interval(0.4)
	finish.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
		_on_event_finished(root)
	)

# ---------------------------------------------------------------------------
# Event: Gravity Well
# ---------------------------------------------------------------------------

func _spawn_gravity_well() -> Node:
	var duration := randf_range(10.0, 16.0)
	var center := _random_arena_pos(600.0, 380.0)
	_gravity_center = center
	_gravity_strength = randf_range(80.0, 160.0)
	_gravity_radius = 600.0
	_gravity_active = true

	var root := Node2D.new()
	root.name = "GravityWell"
	root.position = center
	root.z_index = 1
	get_tree().current_scene.add_child(root)

	var outer_tex_path := "res://assets/particles/circle_01.png"
	var core_tex_path := "res://assets/particles/circle_03.png"

	for i in 3:
		var ring := Sprite2D.new()
		var s := 0.8 + i * 0.7
		ring.scale = Vector2.ONE * s
		ring.modulate = Color(0.6, 0.2, 1.0, 0.0)
		if ResourceLoader.exists(outer_tex_path):
			ring.texture = load(outer_tex_path)
		root.add_child(ring)
		var f := ring.create_tween()
		f.tween_property(ring, "modulate:a", 0.3 - i * 0.06, 0.5)
		var p := ring.create_tween()
		p.set_loops()
		p.tween_property(ring, "scale", Vector2.ONE * (s + 0.15), 1.2 + i * 0.3).set_trans(Tween.TRANS_SINE)
		p.tween_property(ring, "scale", Vector2.ONE * s, 1.2 + i * 0.3).set_trans(Tween.TRANS_SINE)

	var core := Sprite2D.new()
	core.modulate = Color(0.8, 0.4, 1.0, 0.0)
	core.scale = Vector2.ONE * 0.5
	if ResourceLoader.exists(core_tex_path):
		core.texture = load(core_tex_path)
	root.add_child(core)
	var core_fade := core.create_tween()
	core_fade.tween_property(core, "modulate:a", 0.8, 0.4)

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_gravity_fadeout.bind(root))

	_announce("GRAVITY WELL", Color(0.7, 0.3, 1.0))
	return root

func _process_gravity_pull(delta: float) -> void:
	var all := _get_all_bodies()
	for body in all:
		if not is_instance_valid(body):
			continue
		if not "velocity" in body:
			continue
		var dist: float = (body as Node2D).global_position.distance_to(_gravity_center)
		if dist > _gravity_radius or dist < 5.0:
			continue
		var dir: Vector2 = (_gravity_center - (body as Node2D).global_position).normalized()
		var falloff: float = 1.0 - (dist / _gravity_radius)
		body.velocity += dir * _gravity_strength * falloff * delta

func _begin_gravity_fadeout(root: Node2D) -> void:
	_gravity_active = false
	if not is_instance_valid(root):
		_on_event_finished(root)
		return
	for child in root.get_children():
		if is_instance_valid(child):
			var t: Tween = (child as Node).create_tween()
			t.tween_property(child, "modulate:a", 0.0, 0.4)
	var gf_finish := create_tween()
	gf_finish.tween_interval(0.4)
	gf_finish.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
		_on_event_finished(root)
	)

# ---------------------------------------------------------------------------
# Event: Minefield
# ---------------------------------------------------------------------------

func _spawn_minefield() -> Node:
	var duration := randf_range(12.0, 20.0)
	var root := Node2D.new()
	root.name = "Minefield"
	root.z_index = 2
	get_tree().current_scene.add_child(root)

	var mine_tex_path := "res://assets/sprites/spaceParts_050.png"
	var mine_count := randi_range(6, 12)
	var placed_positions: Array = []

	for _i in mine_count:
		var pos := _random_arena_pos(820.0, 520.0)
		var too_close := false
		for pp in placed_positions:
			if pos.distance_to(pp) < 120.0:
				too_close = true
				break
		if too_close:
			pos = _random_arena_pos(820.0, 520.0)
		placed_positions.append(pos)

		var mine := Node2D.new()
		mine.name = "Mine"
		mine.position = pos
		root.add_child(mine)

		var spr := Sprite2D.new()
		spr.scale = Vector2.ONE * 0.4
		spr.modulate = Color(0.8, 0.1, 0.1, 0.0)
		if ResourceLoader.exists(mine_tex_path):
			spr.texture = load(mine_tex_path)
		else:
			var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.6, 0.0, 0.0))
			spr.texture = ImageTexture.create_from_image(img)
		mine.add_child(spr)

		var fade := spr.create_tween()
		fade.tween_property(spr, "modulate:a", 0.4, 0.5)

		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 3
		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 60.0
		col.shape = shape
		area.add_child(col)
		mine.add_child(area)
		area.body_entered.connect(_on_mine_triggered.bind(mine, spr))

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_minefield_fadeout.bind(root))

	_announce("MINEFIELD", Color(1.0, 0.3, 0.2))
	return root

func _on_mine_triggered(body: Node, mine: Node2D, spr: Sprite2D) -> void:
	if not is_instance_valid(mine):
		return
	if body.has_method("take_damage"):
		body.take_damage(25.0)
	if is_instance_valid(spr):
		spr.modulate = Color(1.0, 0.8, 0.1, 1.0)
		var t := spr.create_tween()
		t.tween_property(spr, "modulate:a", 0.0, 0.15)
	var del := create_tween()
	del.tween_interval(0.15)
	del.tween_callback(func():
		if is_instance_valid(mine):
			mine.queue_free()
	)

func _begin_minefield_fadeout(root: Node2D) -> void:
	if not is_instance_valid(root):
		_on_event_finished(root)
		return
	for mine in root.get_children():
		if not is_instance_valid(mine):
			continue
		for child in mine.get_children():
			if child is Sprite2D:
				var t: Tween = (child as Sprite2D).create_tween()
				t.tween_property(child, "modulate:a", 0.0, 0.4)
	var mf_finish := create_tween()
	mf_finish.tween_interval(0.4)
	mf_finish.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
		_on_event_finished(root)
	)

# ---------------------------------------------------------------------------
# Event: Ion Storm
# ---------------------------------------------------------------------------

func _spawn_ion_storm() -> Node:
	var duration := randf_range(10.0, 14.0)

	var layer := CanvasLayer.new()
	layer.name = "IonStorm"
	layer.layer = 3
	get_tree().current_scene.add_child(layer)

	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = Color(0.3, 0.5, 1.0, 0.0)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)

	var fade_in := rect.create_tween()
	fade_in.tween_property(rect, "color:a", 0.08, 0.3)
	var flicker := rect.create_tween()
	flicker.set_loops()
	flicker.tween_property(rect, "color:a", 0.15, 0.2).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(rect, "color:a", 0.05, 0.3).set_trans(Tween.TRANS_SINE)
	layer.set_meta("flicker_tween", flicker)

	var spark_paths: Array = []
	for i in range(1, 8):
		var p := "res://assets/particles/spark_%02d.png" % i
		if ResourceLoader.exists(p):
			spark_paths.append(p)
	for i in range(1, 4):
		var p := "res://assets/particles/light_%02d.png" % i
		if ResourceLoader.exists(p):
			spark_paths.append(p)

	var vp := get_viewport()
	var vp_size := vp.get_visible_rect().size if vp else Vector2(1920.0, 1080.0)

	for _i in randi_range(5, 8):
		var spr := Sprite2D.new()
		spr.scale = Vector2.ONE * randf_range(0.5, 1.2)
		spr.modulate = Color(0.6, 0.8, 1.0, 0.0)
		if spark_paths.size() > 0:
			spr.texture = load(spark_paths[randi() % spark_paths.size()])
		var start_x := randf_range(0.0, vp_size.x)
		var end_x := randf_range(0.0, vp_size.x)
		var y := randf_range(0.0, vp_size.y)
		spr.position = Vector2(start_x, y)
		layer.add_child(spr)
		var delay := randf_range(0.0, duration * 0.6)
		var streak := spr.create_tween()
		streak.tween_interval(delay)
		streak.tween_property(spr, "modulate:a", 0.8, 0.15)
		streak.tween_property(spr, "position:x", end_x, randf_range(0.3, 0.8))
		streak.tween_property(spr, "modulate:a", 0.0, 0.15)

	GameManager.ion_storm_active = true

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_ion_storm_fadeout.bind(layer, rect))

	_announce("ION STORM", Color(0.4, 0.7, 1.0))
	return layer

func _begin_ion_storm_fadeout(layer: CanvasLayer, rect: ColorRect) -> void:
	GameManager.ion_storm_active = false
	if not is_instance_valid(layer):
		_on_event_finished(layer)
		return
	var ft = layer.get_meta("flicker_tween", null)
	if ft is Tween:
		ft.kill()
	var fade := rect.create_tween()
	fade.tween_property(rect, "color:a", 0.0, 0.4)
	var is_finish := create_tween()
	is_finish.tween_interval(0.4)
	is_finish.tween_callback(func():
		if is_instance_valid(layer):
			layer.queue_free()
		_on_event_finished(layer)
	)

# ---------------------------------------------------------------------------
# Event: Debris Corridor
# ---------------------------------------------------------------------------

func _spawn_debris_corridor() -> Node:
	var duration := randf_range(10.0, 16.0)
	var angle := randf_range(0.0, PI)
	var center := _random_arena_pos(400.0, 250.0)

	var root := Node2D.new()
	root.name = "DebrisCorridor"
	root.position = center
	root.rotation = angle
	root.z_index = 2
	get_tree().current_scene.add_child(root)

	const CORRIDOR_W: float = 120.0
	const CORRIDOR_LEN: float = 1200.0

	var tiny_paths: Array = []
	for p in [
		"res://assets/sprites/meteorBrown_tiny1.png",
		"res://assets/sprites/meteorBrown_tiny2.png",
		"res://assets/sprites/meteorGrey_tiny1.png",
		"res://assets/sprites/meteorGrey_tiny2.png",
	]:
		if ResourceLoader.exists(p):
			tiny_paths.append(load(p))

	var debris_sprites: Array = []
	for _i in randi_range(18, 30):
		var spr := Sprite2D.new()
		spr.scale = Vector2.ONE * randf_range(0.3, 0.8)
		spr.rotation = randf_range(0.0, TAU)
		spr.position = Vector2(randf_range(-CORRIDOR_LEN * 0.5, CORRIDOR_LEN * 0.5), randf_range(-CORRIDOR_W * 0.4, CORRIDOR_W * 0.4))
		spr.modulate = Color(1.0, 1.0, 1.0, 0.0)
		if tiny_paths.size() > 0:
			spr.texture = tiny_paths[randi() % tiny_paths.size()]
		root.add_child(spr)
		debris_sprites.append(spr)
		var fd := spr.create_tween()
		fd.tween_property(spr, "modulate:a", 0.7, randf_range(0.3, 0.7))
		var drift_y := spr.position.y
		var drift_t := spr.create_tween()
		drift_t.set_loops()
		drift_t.tween_property(spr, "position:y", drift_y + randf_range(-15.0, 15.0), randf_range(1.5, 3.0)).set_trans(Tween.TRANS_SINE)
		drift_t.tween_property(spr, "position:y", drift_y, randf_range(1.5, 3.0)).set_trans(Tween.TRANS_SINE)

	root.set_meta("debris_sprites", debris_sprites)

	_hazard_bodies.clear()
	_hazard_damage_timer = HAZARD_DAMAGE_INTERVAL

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 3
	area.set_meta("damage_per_sec", 4.0)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(CORRIDOR_LEN, CORRIDOR_W)
	col.shape = shape
	area.add_child(col)
	root.add_child(area)
	_hazard_bodies[area] = []
	area.body_entered.connect(_on_hazard_body_entered.bind(area, false))
	area.body_exited.connect(_on_hazard_body_exited.bind(area))

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_corridor_fadeout.bind(root, area))

	_announce("DEBRIS CORRIDOR", Color(0.8, 0.6, 0.4))
	return root

func _begin_corridor_fadeout(root: Node2D, area: Area2D) -> void:
	if is_instance_valid(area):
		if area.body_entered.is_connected(_on_hazard_body_entered):
			area.body_entered.disconnect(_on_hazard_body_entered)
		if area.body_exited.is_connected(_on_hazard_body_exited):
			area.body_exited.disconnect(_on_hazard_body_exited)
	_hazard_bodies.erase(area)

	if not is_instance_valid(root):
		_on_event_finished(root)
		return

	for spr in root.get_meta("debris_sprites", []):
		if is_instance_valid(spr):
			var t: Tween = (spr as Node).create_tween()
			t.tween_property(spr, "modulate:a", 0.0, 0.4)
	var dc_finish := create_tween()
	dc_finish.tween_interval(0.4)
	dc_finish.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
		_on_event_finished(root)
	)

# ---------------------------------------------------------------------------
# Event: Black Hole
# ---------------------------------------------------------------------------

func _spawn_black_hole() -> Node:
	var duration := randf_range(8.0, 12.0)
	var corner_signs: Array[Vector2] = [Vector2(1.0, 1.0), Vector2(-1.0, 1.0), Vector2(1.0, -1.0), Vector2(-1.0, -1.0)]
	var cs := corner_signs[randi() % 4]
	_gravity_center = Vector2(cs.x * randf_range(500.0, 780.0), cs.y * randf_range(350.0, 530.0))
	_gravity_strength = randf_range(260.0, 400.0)
	_gravity_radius = 400.0
	_gravity_active = true

	var root := Node2D.new()
	root.name = "BlackHole"
	root.position = _gravity_center
	root.z_index = 2
	get_tree().current_scene.add_child(root)

	var outer_tex := "res://assets/particles/circle_01.png"
	for i in 3:
		var ring := Sprite2D.new()
		var s := 1.2 + i * 0.6
		ring.scale = Vector2.ONE * s
		ring.modulate = Color(0.8, 0.4, 1.0, 0.0)
		if ResourceLoader.exists(outer_tex):
			ring.texture = load(outer_tex)
		root.add_child(ring)
		var f := ring.create_tween()
		f.tween_property(ring, "modulate:a", 0.25 - i * 0.05, 0.5)
		var rp := ring.create_tween()
		rp.set_loops()
		rp.tween_property(ring, "rotation", TAU, 4.0 + i * 1.5)

	var core_tex := "res://assets/particles/circle_05.png"
	var core := Sprite2D.new()
	core.scale = Vector2.ONE * 0.6
	core.modulate = Color(0.0, 0.0, 0.0, 0.0)
	if ResourceLoader.exists(core_tex):
		core.texture = load(core_tex)
	root.add_child(core)
	var core_f := core.create_tween()
	core_f.tween_property(core, "modulate:a", 1.0, 0.5)

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_gravity_fadeout.bind(root))

	_announce("BLACK HOLE", Color(0.8, 0.3, 1.0))
	return root

# ---------------------------------------------------------------------------
# Event: Pulsar Burst
# ---------------------------------------------------------------------------

func _spawn_pulsar_burst() -> Node:
	var duration := randf_range(12.0, 18.0)
	_pulsar_center = _random_arena_pos(500.0, 300.0)
	_pulsar_interval = randf_range(2.5, 3.5)
	_pulsar_timer = _pulsar_interval
	_pulsar_active = true

	var root := Node2D.new()
	root.name = "PulsarBurst"
	root.position = _pulsar_center
	root.z_index = 2
	get_tree().current_scene.add_child(root)

	var core_tex_path := "res://assets/particles/flare_01.png"
	var fallback_path := "res://assets/particles/light_02.png"
	var core := Sprite2D.new()
	core.scale = Vector2.ONE * 0.4
	core.modulate = Color(1.0, 0.8, 0.3, 0.0)
	if ResourceLoader.exists(core_tex_path):
		core.texture = load(core_tex_path)
	elif ResourceLoader.exists(fallback_path):
		core.texture = load(fallback_path)
	root.add_child(core)
	root.set_meta("core_sprite", core)

	var fade_in := core.create_tween()
	fade_in.tween_property(core, "modulate:a", 0.9, 0.4)
	var pulse := core.create_tween()
	pulse.set_loops()
	pulse.tween_property(core, "scale", Vector2.ONE * 0.55, 0.4).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(core, "scale", Vector2.ONE * 0.35, 0.4).set_trans(Tween.TRANS_SINE)

	var lifetime := create_tween()
	lifetime.tween_interval(duration - 0.4)
	lifetime.tween_callback(_begin_pulsar_fadeout.bind(root))

	_announce("PULSAR", Color(1.0, 0.6, 0.1))

	# Show a "BRACE!" label that pulses during the charge window before the first ring fires
	var brace_layer := CanvasLayer.new()
	brace_layer.layer = 9
	get_tree().current_scene.add_child(brace_layer)
	var brace_label := Label.new()
	brace_label.text = "BRACE!"
	brace_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brace_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brace_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	brace_label.add_theme_font_size_override("font_size", 48)
	brace_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	brace_label.modulate.a = 0.0
	if is_instance_valid(hud):
		var kfont := GameManager.kenney_font()
		if kfont:
			brace_label.add_theme_font_override("font", kfont)
	brace_layer.add_child(brace_label)
	var brace_tw := brace_label.create_tween()
	brace_tw.tween_property(brace_label, "modulate:a", 1.0, 0.2)
	brace_tw.tween_interval(_pulsar_interval - 0.5)
	brace_tw.tween_property(brace_label, "modulate:a", 0.0, 0.3)
	brace_tw.tween_callback(brace_layer.queue_free)

	return root

func _fire_pulsar_ring() -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return

	var ring_tex := "res://assets/particles/circle_03.png"
	var ring := Sprite2D.new()
	ring.position = _pulsar_center
	ring.scale = Vector2.ONE * 0.1
	ring.modulate = Color(1.0, 0.6, 0.1, 0.9)
	if ResourceLoader.exists(ring_tex):
		ring.texture = load(ring_tex)
	ring.z_index = 3
	scene_root.add_child(ring)

	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2.ONE * 4.5, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.5)
	t.chain().tween_callback(ring.queue_free)

	var pulse_node := Node2D.new()
	pulse_node.position = _pulsar_center
	scene_root.add_child(pulse_node)

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 3
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 200.0
	col.shape = shape
	area.add_child(col)
	pulse_node.add_child(area)

	var del := create_tween()
	del.tween_interval(0.05)
	del.tween_callback(func():
		if not is_instance_valid(area):
			return
		for body in area.get_overlapping_bodies():
			if is_instance_valid(body) and body.has_method("take_damage"):
				body.take_damage(12.0)
		if is_instance_valid(pulse_node):
			pulse_node.queue_free()
	)

func _begin_pulsar_fadeout(root: Node2D) -> void:
	_pulsar_active = false
	if not is_instance_valid(root):
		_on_event_finished(root)
		return
	var core = root.get_meta("core_sprite", null)
	if core is Node:
		var t := (core as Node).create_tween()
		t.tween_property(core, "modulate:a", 0.0, 0.4)
	var pb_finish := create_tween()
	pb_finish.tween_interval(0.4)
	pb_finish.tween_callback(func():
		if is_instance_valid(root):
			root.queue_free()
		_on_event_finished(root)
	)
