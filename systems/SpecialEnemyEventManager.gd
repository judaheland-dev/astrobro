extends Node
class_name SpecialEnemyEventManager

## SpecialEnemyEventManager - triggers surprise special enemy encounters mid-wave.
## Runs on its own timer, independent of TerrainEventManager.
## Events do not fire before wave 5 (current_wave_index < 4).
## Interval is wide and random (50-130 s) so timing is always surprising.

var players: Array[Player] = []
var wave_manager: WaveManager = null
var hud: CanvasLayer = null

const MIN_WAVE_INDEX: int = 4           # no events before wave 5
const MIN_INTERVAL: float = 50.0
const MAX_INTERVAL: float = 130.0

var _event_timer: float = 0.0           # counts DOWN; fires at 0
var _active_event: Node = null          # non-null while an event is live
var _is_stopped: bool = false

# Rogue-beacon buff tracking: enemy node -> original move_speed
var _beaconed_enemies: Dictionary = {}

func _ready() -> void:
	_reset_timer()

func stop() -> void:
	_is_stopped = true

func _reset_timer() -> void:
	_event_timer = randf_range(MIN_INTERVAL, MAX_INTERVAL)

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

func _trigger_random_event() -> void:
	var choice := randi() % 6
	match choice:
		0: _spawn_salvager()
		1: _spawn_carrier()
		2: _spawn_rogue_beacon()
		3: _spawn_warp_ambush()
		4: _spawn_distress_signal()
		5: _spawn_warp_jumper()

func _on_event_finished(node: Node) -> void:
	if node == _active_event:
		_active_event = null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_nearest_player() -> Player:
	var best: Player = null
	var best_d := INF
	for p in players:
		if is_instance_valid(p) and p.is_physics_processing():
			var d := p.global_position.length_squared()
			if d < best_d:
				best_d = d
				best = p
	return best

func _nearest_player_to(pos: Vector2) -> Player:
	var best: Player = null
	var best_d := INF
	for p in players:
		if is_instance_valid(p) and p.is_physics_processing():
			var d := p.global_position.distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = p
	return best

func _show_banner(text: String, color: Color) -> void:
	if hud != null and hud.has_method("show_event_banner"):
		hud.call("show_event_banner", text, color)

func _random_arena_pos(hw: float = 700.0, hh: float = 450.0) -> Vector2:
	return Vector2(randf_range(-hw, hw), randf_range(-hh, hh))

func _random_edge_pos() -> Vector2:
	var hw := 900.0
	var hh := 560.0
	var edge := randi() % 4
	match edge:
		0: return Vector2(randf_range(-hw, hw), -hh)
		1: return Vector2(randf_range(-hw, hw),  hh)
		2: return Vector2(-hw, randf_range(-hh, hh))
		_: return Vector2( hw, randf_range(-hh, hh))

func _edge_exit_direction(from_pos: Vector2) -> Vector2:
	# Direction toward the nearest arena wall
	var to_right := 960.0 - from_pos.x
	var to_left  := from_pos.x + 960.0
	var to_bot   := 600.0 - from_pos.y
	var to_top   := from_pos.y + 600.0
	var min_d := minf(minf(to_right, to_left), minf(to_bot, to_top))
	if min_d == to_right:  return Vector2.RIGHT
	if min_d == to_left:   return Vector2.LEFT
	if min_d == to_bot:    return Vector2.DOWN
	return Vector2.UP

func _build_special_enemy(
		sprite_path: String,
		hp: float,
		col_radius: float = 14.0,
		sprite_scale: Vector2 = Vector2.ONE
	) -> SpecialEnemyBody:
	var body := SpecialEnemyBody.new()
	body.collision_layer = 2
	body.collision_mask  = 3

	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	spr.rotation_degrees = 90.0
	spr.scale = sprite_scale
	if ResourceLoader.exists(sprite_path):
		spr.texture = load(sprite_path)
	else:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.8, 0.2))
		spr.texture = ImageTexture.create_from_image(img)
	body.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = col_radius
	col.shape = shape
	body.add_child(col)

	body.max_health = hp

	return body



# ---------------------------------------------------------------------------
# Event 1 — Salvager Drone
# ---------------------------------------------------------------------------

const SALVAGER_HP: float = 50.0
const SALVAGER_SPEED: float = 210.0
const SALVAGER_LIFETIME: float = 15.0
const SALVAGER_COINS: int = 60
const SALVAGER_XP: int = 40
const SALVAGER_DRIP_INTERVAL: float = 3.0

func _spawn_salvager() -> void:
	_show_banner("!  SALVAGER SPOTTED  !", Color(1.0, 0.85, 0.1))

	var root := Node2D.new()
	root.name = "SalvagerEvent"
	get_tree().current_scene.add_child(root)
	_active_event = root

	var body := _build_special_enemy(
		"res://assets/sprites/playerShip2_orange.png", SALVAGER_HP, 14.0, Vector2(0.8, 0.8))
	body.name = "SalvagerBody"

	# Tint it gold
	var spr := body.get_node_or_null("Sprite2D") as Sprite2D
	if spr:
		spr.modulate = Color(1.0, 0.9, 0.1)

	root.add_child(body)
	body.global_position = _random_edge_pos()

	# Determine flee direction toward nearest wall from starting position
	var flee_dir := _edge_exit_direction(body.global_position)
	root.set_meta("flee_dir", flee_dir)
	root.set_meta("lifetime", SALVAGER_LIFETIME)
	root.set_meta("drip_timer", SALVAGER_DRIP_INTERVAL)
	root.set_meta("body_ref", body)
	root.set_meta("escaped", false)

	# Hit area so players can shoot it
	var area := Area2D.new()
	area.collision_layer = 2
	area.collision_mask  = 0
	var ac := CollisionShape2D.new()
	var as_ := CircleShape2D.new()
	as_.radius = 16.0
	ac.shape = as_
	area.add_child(ac)
	body.add_child(area)

	# Spawn pop
	body.scale = Vector2.ZERO
	var spawn_tw := body.create_tween()
	spawn_tw.tween_property(body, "scale", Vector2(1.2, 1.2), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	spawn_tw.tween_property(body, "scale", Vector2.ONE, 0.08)

	# Script-like update via a per-frame callable stored in root metadata
	root.set_meta("alive", true)
	root.set_script(null)  # no script; we drive it from _process below

	# Connect to _process by adding a helper node
	_salvager_root = root
	_salvager_body = body
	_salvager_timer = SALVAGER_LIFETIME
	_salvager_drip = SALVAGER_DRIP_INTERVAL
	body.killed.connect(_salvager_kill)

var _salvager_root: Node = null
var _salvager_body: SpecialEnemyBody = null
var _salvager_timer: float = 0.0
var _salvager_drip: float = 0.0

func _salvager_tick(delta: float) -> void:
	if not is_instance_valid(_salvager_root) or not is_instance_valid(_salvager_body):
		_salvager_root = null
		return

	_salvager_timer -= delta
	_salvager_drip -= delta

	var flee_dir: Vector2 = _salvager_root.get_meta("flee_dir", Vector2.RIGHT)
	_salvager_body.velocity = flee_dir * SALVAGER_SPEED
	_salvager_body.move_and_slide()

	# Face direction
	var spr := _salvager_body.get_node_or_null("Sprite2D") as Sprite2D
	if spr and flee_dir != Vector2.ZERO:
		spr.rotation = flee_dir.angle() + PI * 0.5

	# Coin drip while alive under fire
	if _salvager_drip <= 0.0:
		_salvager_drip = SALVAGER_DRIP_INTERVAL
		var drip_coins := 8
		_emit_reward_at(_salvager_body.global_position, 0, drip_coins)

	if _salvager_timer <= 0.0:
		_salvager_escape()

func _salvager_kill() -> void:
	if not is_instance_valid(_salvager_root):
		return
	_show_banner("SALVAGER DESTROYED", Color(1.0, 0.6, 0.1))
	_emit_reward_at(_salvager_body.global_position, SALVAGER_XP, SALVAGER_COINS)
	_salvager_cleanup()

func _salvager_escape() -> void:
	_show_banner("IT ESCAPED...", Color(0.6, 0.6, 0.6))
	_salvager_cleanup()

func _salvager_cleanup() -> void:
	if is_instance_valid(_salvager_root):
		var tw := _salvager_root.create_tween()
		tw.tween_property(_salvager_root, "modulate:a", 0.0, 0.3)
		tw.tween_callback(_salvager_root.queue_free)
	_on_event_finished(_salvager_root)
	_salvager_root = null
	_salvager_body = null

# ---------------------------------------------------------------------------
# Event 2 — Carrier Ship
# ---------------------------------------------------------------------------

const CARRIER_HP: float = 320.0
const CARRIER_SPEED: float = 38.0
const CARRIER_SPAWN_INTERVAL: float = 4.0
const CARRIER_MAX_MINIONS: int = 8
const CARRIER_LIFETIME: float = 22.0
const CARRIER_COINS: int = 80
const CARRIER_XP: int = 60

var _carrier_root: Node = null
var _carrier_body: SpecialEnemyBody = null
var _carrier_timer: float = 0.0
var _carrier_spawn_timer: float = 0.0
var _carrier_minions: Array[Node] = []

func _spawn_carrier() -> void:
	_show_banner("!! CARRIER INBOUND !!", Color(1.0, 0.3, 0.3))

	var root := Node2D.new()
	root.name = "CarrierEvent"
	get_tree().current_scene.add_child(root)
	_active_event = root

	var body := _build_special_enemy(
		"res://assets/sprites/enemyBlack5.png", CARRIER_HP, 24.0, Vector2(1.8, 1.8))
	body.name = "CarrierBody"
	var spr := body.get_node_or_null("Sprite2D") as Sprite2D
	if spr:
		spr.modulate = Color(0.9, 0.3, 0.3)
		spr.rotation_degrees = -90.0  # enemy ships face down, reverse for carrier

	root.add_child(body)
	body.global_position = _random_edge_pos()
	body.scale = Vector2.ZERO
	var tw := body.create_tween()
	tw.tween_property(body, "scale", Vector2(1.2, 1.2), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "scale", Vector2.ONE, 0.1)

	_carrier_root = root
	_carrier_body = body
	_carrier_timer = CARRIER_LIFETIME
	_carrier_spawn_timer = CARRIER_SPAWN_INTERVAL * 0.5  # first minion comes sooner
	_carrier_minions.clear()
	body.killed.connect(_carrier_kill)

func _carrier_tick(delta: float) -> void:
	if not is_instance_valid(_carrier_root) or not is_instance_valid(_carrier_body):
		_carrier_root = null
		return

	_carrier_timer -= delta
	_carrier_spawn_timer -= delta

	# Move toward center
	var dir := -_carrier_body.global_position.normalized()
	_carrier_body.velocity = dir * CARRIER_SPEED
	_carrier_body.move_and_slide()
	var spr := _carrier_body.get_node_or_null("Sprite2D") as Sprite2D
	if spr and dir != Vector2.ZERO:
		spr.rotation = dir.angle() + PI * 0.5

	# Spawn minions
	if _carrier_spawn_timer <= 0.0 and _carrier_minions.size() < CARRIER_MAX_MINIONS:
		_carrier_spawn_timer = CARRIER_SPAWN_INTERVAL
		_carrier_spawn_minion()

	if _carrier_timer <= 0.0:
		_carrier_retreat()

func _carrier_spawn_minion() -> void:
	var enemy_node := BaseEnemy.new()
	enemy_node.collision_layer = 2
	enemy_node.collision_mask  = 3

	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	if ResourceLoader.exists("res://assets/sprites/enemyRed1.png"):
		spr.texture = load("res://assets/sprites/enemyRed1.png")
	else:
		var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.2, 0.2))
		spr.texture = ImageTexture.create_from_image(img)
	enemy_node.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	enemy_node.add_child(col)

	var nav := NavigationAgent2D.new()
	nav.name = "NavigationAgent2D"
	nav.path_desired_distance = 8.0
	nav.target_desired_distance = 16.0
	enemy_node.add_child(nav)

	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 1
	area.name = "ContactArea"
	var ac := CollisionShape2D.new()
	var as_ := CircleShape2D.new()
	as_.radius = 14.0
	ac.shape = as_
	area.add_child(ac)
	enemy_node.add_child(area)

	var grunt_data: EnemyData = ResourceLoader.load("res://resources/enemies/grunt.tres")
	enemy_node.enemy_data = grunt_data

	var scene_root := get_tree().current_scene
	scene_root.add_child(enemy_node)
	area.body_entered.connect(enemy_node._on_body_entered)
	area.body_exited.connect(enemy_node._on_body_exited)

	var targets: Array[Node] = []
	for p in players:
		targets.append(p)
	enemy_node.register_targets(targets)
	var offset := Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
	enemy_node.global_position = (_carrier_body.global_position if is_instance_valid(_carrier_body) else Vector2.ZERO) + offset

	_carrier_minions.append(enemy_node)
	enemy_node.died.connect(_carrier_minions.erase.bind(enemy_node))

	# Also wire xp/coin drops so Game.gd handles rewards
	enemy_node.xp_dropped.connect(_on_special_xp_dropped)
	enemy_node.coin_dropped.connect(_on_special_coin_dropped)

func _carrier_kill() -> void:
	if not is_instance_valid(_carrier_root):
		return
	_show_banner("CARRIER DESTROYED!", Color(1.0, 0.5, 0.0))
	_emit_reward_at(_carrier_body.global_position, CARRIER_XP, CARRIER_COINS)
	# Kill all minions in a chain explosion
	for minion in _carrier_minions.duplicate():
		if is_instance_valid(minion):
			minion.queue_free()
	_carrier_minions.clear()
	_carrier_cleanup()

func _carrier_retreat() -> void:
	_show_banner("CARRIER RETREATED", Color(0.6, 0.6, 0.6))
	_carrier_cleanup()

func _carrier_cleanup() -> void:
	if is_instance_valid(_carrier_root):
		var tw := _carrier_root.create_tween()
		tw.tween_property(_carrier_root, "modulate:a", 0.0, 0.35)
		tw.tween_callback(_carrier_root.queue_free)
	_on_event_finished(_carrier_root)
	_carrier_root = null
	_carrier_body = null

# ---------------------------------------------------------------------------
# Event 3 — Rogue Beacon
# ---------------------------------------------------------------------------

const BEACON_HP: float = 65.0
const BEACON_RADIUS: float = 300.0
const BEACON_SPEED_BONUS: float = 0.4
const BEACON_LIFETIME: float = 18.0
const BEACON_COINS: int = 45
const BEACON_XP: int = 30

var _beacon_root: Node = null
var _beacon_body: SpecialEnemyBody = null
var _beacon_timer: float = 0.0
var _beaconed: Dictionary = {}    # enemy node -> original speed

func _spawn_rogue_beacon() -> void:
	_show_banner("ROGUE BEACON DETECTED", Color(1.0, 0.4, 1.0))

	var root := Node2D.new()
	root.name = "RogueBeacon"
	root.position = _random_arena_pos(600.0, 400.0)
	root.z_index = 1
	get_tree().current_scene.add_child(root)
	_active_event = root

	# Visual: pulsing ring
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	var segs := 32
	for i in segs:
		var a := (TAU / segs) * i
		pts.append(Vector2(cos(a) * BEACON_RADIUS, sin(a) * BEACON_RADIUS))
	ring.polygon = pts
	ring.color = Color(0.9, 0.2, 0.9, 0.0)
	root.add_child(ring)

	var inner := Polygon2D.new()
	var ipts := PackedVector2Array()
	for i in 16:
		var a := (TAU / 16) * i
		ipts.append(Vector2(cos(a) * 18.0, sin(a) * 18.0))
	inner.polygon = ipts
	inner.color = Color(1.0, 0.4, 1.0, 0.0)
	root.add_child(inner)

	# Collision body for beacon hit-detection (players shoot it)
	var body := SpecialEnemyBody.new()
	body.name = "BeaconBody"
	body.max_health = BEACON_HP
	body.collision_layer = 2
	body.collision_mask  = 0
	var bc := CollisionShape2D.new()
	var bs := CircleShape2D.new()
	bs.radius = 18.0
	bc.shape = bs
	body.add_child(bc)
	root.add_child(body)

	# Fade in visuals
	var tw := ring.create_tween()
	tw.tween_property(ring, "color:a", 0.12, 0.5)
	var itw := inner.create_tween()
	itw.set_loops()
	itw.tween_property(inner, "color:a", 0.85, 1.0).set_trans(Tween.TRANS_SINE)
	itw.tween_property(inner, "color:a", 0.35, 1.0).set_trans(Tween.TRANS_SINE)

	root.set_meta("ring_ref", ring)
	root.set_meta("inner_ref", inner)

	_beacon_root = root
	_beacon_body = body
	_beacon_timer = BEACON_LIFETIME
	_beaconed.clear()
	body.killed.connect(_beacon_kill)

func _beacon_tick(delta: float) -> void:
	if not is_instance_valid(_beacon_root):
		_beacon_root = null
		_beacon_clear_buffs()
		return

	_beacon_timer -= delta

	# Apply/maintain speed buff to all enemies within radius
	var beacon_pos: Vector2 = (_beacon_root as Node2D).global_position
	var enemies := get_tree().get_nodes_in_group("enemies")
	# Also scan the scene for BaseEnemy nodes
	_beacon_buff_nearby(beacon_pos)

	if _beacon_timer <= 0.0:
		_beacon_expire()

func _beacon_buff_nearby(beacon_pos: Vector2) -> void:
	var scene := get_tree().current_scene
	_beacon_buff_children(scene, beacon_pos)

func _beacon_buff_children(node: Node, beacon_pos: Vector2) -> void:
	for child in node.get_children():
		if child is BaseEnemy:
			var dist: float = (child as Node2D).global_position.distance_to(beacon_pos)
			if dist <= BEACON_RADIUS:
				if not _beaconed.has(child):
					_beaconed[child] = child.move_speed
					child.move_speed *= (1.0 + BEACON_SPEED_BONUS)
			else:
				if _beaconed.has(child):
					child.move_speed = _beaconed[child]
					_beaconed.erase(child)
		_beacon_buff_children(child, beacon_pos)

func _beacon_clear_buffs() -> void:
	for enemy in _beaconed:
		if is_instance_valid(enemy):
			enemy.move_speed = _beaconed[enemy]
	_beaconed.clear()

func _beacon_kill() -> void:
	if not is_instance_valid(_beacon_root):
		return
	_show_banner("BEACON DESTROYED!", Color(1.0, 0.6, 1.0))
	_beacon_clear_buffs()
	_emit_reward_at(_beacon_root.global_position, BEACON_XP, BEACON_COINS)
	_beacon_cleanup()

func _beacon_expire() -> void:
	_show_banner("BEACON OFFLINE", Color(0.6, 0.6, 0.6))
	_beacon_clear_buffs()
	_beacon_cleanup()

func _beacon_cleanup() -> void:
	if is_instance_valid(_beacon_root):
		var ring = _beacon_root.get_meta("ring_ref", null)
		var inner = _beacon_root.get_meta("inner_ref", null)
		var tw := _beacon_root.create_tween()
		tw.set_parallel(true)
		if ring is Node:
			tw.tween_property(ring, "color:a", 0.0, 0.35)
		if inner is Node:
			tw.tween_property(inner, "color:a", 0.0, 0.35)
		tw.chain().tween_callback(_beacon_root.queue_free)
	_on_event_finished(_beacon_root)
	_beacon_root = null
	_beacon_body = null

# ---------------------------------------------------------------------------
# Event 4 — Warp Ambush
# ---------------------------------------------------------------------------

const AMBUSH_COUNT_MIN: int = 6
const AMBUSH_COUNT_MAX: int = 10
const AMBUSH_RING_RADIUS: float = 130.0

func _spawn_warp_ambush() -> void:
	_show_banner("!! WARP AMBUSH !!", Color(1.0, 0.2, 0.2))

	var nearest := _get_nearest_player()
	var center := nearest.global_position if nearest else Vector2.ZERO

	# Brief screen flash
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 8
	get_tree().current_scene.add_child(flash_layer)
	var flash_rect := ColorRect.new()
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1.0, 0.2, 0.2, 0.0)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_layer.add_child(flash_rect)
	var flash_tw := flash_rect.create_tween()
	flash_tw.tween_property(flash_rect, "color:a", 0.18, 0.1)
	flash_tw.tween_property(flash_rect, "color:a", 0.0, 0.35)
	flash_tw.tween_callback(flash_layer.queue_free)

	var count := randi_range(AMBUSH_COUNT_MIN, AMBUSH_COUNT_MAX)
	for i in count:
		var angle := (TAU / count) * i + randf_range(-0.3, 0.3)
		var spawn_pos := center + Vector2(cos(angle), sin(angle)) * (AMBUSH_RING_RADIUS + randf_range(-20.0, 20.0))

		var enemy_node := BaseEnemy.new()
		enemy_node.collision_layer = 2
		enemy_node.collision_mask  = 3

		var spr := Sprite2D.new()
		spr.name = "Sprite2D"
		if ResourceLoader.exists("res://assets/sprites/enemyBlue2.png"):
			spr.texture = load("res://assets/sprites/enemyBlue2.png")
		else:
			var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.2, 0.5, 1.0))
			spr.texture = ImageTexture.create_from_image(img)
		enemy_node.add_child(spr)

		var col := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 12.0
		col.shape = shape
		enemy_node.add_child(col)

		var nav := NavigationAgent2D.new()
		nav.name = "NavigationAgent2D"
		nav.path_desired_distance = 8.0
		nav.target_desired_distance = 16.0
		enemy_node.add_child(nav)

		var contact_area := Area2D.new()
		contact_area.collision_layer = 0
		contact_area.collision_mask  = 1
		contact_area.name = "ContactArea"
		var ac := CollisionShape2D.new()
		var as_ := CircleShape2D.new()
		as_.radius = 14.0
		ac.shape = as_
		contact_area.add_child(ac)
		enemy_node.add_child(contact_area)

		var speeder_data: EnemyData = ResourceLoader.load("res://resources/enemies/speeder.tres")
		enemy_node.enemy_data = speeder_data

		var scene_root := get_tree().current_scene
		scene_root.add_child(enemy_node)
		contact_area.body_entered.connect(enemy_node._on_body_entered)
		contact_area.body_exited.connect(enemy_node._on_body_exited)

		var targets: Array[Node] = []
		for p in players:
			targets.append(p)
		enemy_node.register_targets(targets)
		enemy_node.global_position = spawn_pos

		# Wire wave manager so these enemies count toward wave completion
		if wave_manager != null:
			wave_manager.active_enemies += 1
			enemy_node.died.connect(wave_manager._on_enemy_died)
			wave_manager._active_enemy_nodes.append(enemy_node)

		enemy_node.xp_dropped.connect(_on_special_xp_dropped)
		enemy_node.coin_dropped.connect(_on_special_coin_dropped)

	# Ambush has no persistent event node; fire-and-forget
	_active_event = null

# ---------------------------------------------------------------------------
# Event 5 — Distress Signal
# ---------------------------------------------------------------------------

const DISTRESS_GUARD_COUNT: int = 3
const DISTRESS_LIFETIME: float = 20.0
const DISTRESS_COINS: int = 70
const DISTRESS_XP: int = 50

var _distress_root: Node = null
var _distress_timer: float = 0.0
var _distress_guards: Array[Node] = []
var _distress_derelict_hp: float = 80.0

func _spawn_distress_signal() -> void:
	_show_banner("-- DISTRESS SIGNAL --", Color(0.4, 1.0, 0.4))

	var root := Node2D.new()
	root.name = "DistressSignal"
	root.position = _random_arena_pos(500.0, 350.0)
	get_tree().current_scene.add_child(root)
	_active_event = root

	# Derelict ship visual (friendly, non-enemy)
	var derelict := Node2D.new()
	derelict.name = "Derelict"
	root.add_child(derelict)

	var dspr := Sprite2D.new()
	dspr.rotation_degrees = 90.0
	if ResourceLoader.exists("res://assets/sprites/playerShip3_blue.png"):
		dspr.texture = load("res://assets/sprites/playerShip3_blue.png")
	else:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.2, 0.6, 1.0))
		dspr.texture = ImageTexture.create_from_image(img)
	dspr.modulate = Color(0.7, 0.7, 1.0, 0.9)
	derelict.add_child(dspr)

	# Beacon pulse around derelict
	var beacon_spr := Sprite2D.new()
	if ResourceLoader.exists("res://assets/particles/light_01.png"):
		beacon_spr.texture = load("res://assets/particles/light_01.png")
		beacon_spr.scale = Vector2(1.5, 1.5)
		beacon_spr.modulate = Color(0.3, 1.0, 0.3, 0.0)
		derelict.add_child(beacon_spr)
		var ptw := beacon_spr.create_tween()
		ptw.set_loops()
		ptw.tween_property(beacon_spr, "modulate:a", 0.6, 0.8).set_trans(Tween.TRANS_SINE)
		ptw.tween_property(beacon_spr, "modulate:a", 0.1, 0.8).set_trans(Tween.TRANS_SINE)

	root.set_meta("derelict_hp", _distress_derelict_hp)
	root.set_meta("derelict_ref", derelict)

	_distress_root = root
	_distress_timer = DISTRESS_LIFETIME
	_distress_guards.clear()

	# Spawn guards around the derelict
	for i in DISTRESS_GUARD_COUNT:
		var angle := (TAU / DISTRESS_GUARD_COUNT) * i
		var gpos := root.global_position + Vector2(cos(angle), sin(angle)) * 90.0
		_spawn_distress_guard(gpos)

func _spawn_distress_guard(pos: Vector2) -> void:
	var enemy_node := BaseEnemy.new()
	enemy_node.collision_layer = 2
	enemy_node.collision_mask  = 3

	var spr := Sprite2D.new()
	spr.name = "Sprite2D"
	if ResourceLoader.exists("res://assets/sprites/enemyBlack4.png"):
		spr.texture = load("res://assets/sprites/enemyBlack4.png")
	else:
		var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.3, 0.8))
		spr.texture = ImageTexture.create_from_image(img)
	enemy_node.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	col.shape = shape
	enemy_node.add_child(col)

	var nav := NavigationAgent2D.new()
	nav.name = "NavigationAgent2D"
	nav.path_desired_distance = 8.0
	nav.target_desired_distance = 16.0
	enemy_node.add_child(nav)

	var contact_area := Area2D.new()
	contact_area.collision_layer = 0
	contact_area.collision_mask  = 1
	contact_area.name = "ContactArea"
	var ac := CollisionShape2D.new()
	var as_ := CircleShape2D.new()
	as_.radius = 16.0
	ac.shape = as_
	contact_area.add_child(ac)
	enemy_node.add_child(contact_area)

	var brute_data: EnemyData = ResourceLoader.load("res://resources/enemies/brute.tres")
	enemy_node.enemy_data = brute_data

	var scene_root := get_tree().current_scene
	scene_root.add_child(enemy_node)
	contact_area.body_entered.connect(enemy_node._on_body_entered)
	contact_area.body_exited.connect(enemy_node._on_body_exited)

	var targets: Array[Node] = []
	for p in players:
		targets.append(p)
	enemy_node.register_targets(targets)
	enemy_node.global_position = pos

	_distress_guards.append(enemy_node)
	enemy_node.died.connect(_on_distress_guard_died.bind(enemy_node))
	enemy_node.xp_dropped.connect(_on_special_xp_dropped)
	enemy_node.coin_dropped.connect(_on_special_coin_dropped)

func _on_distress_guard_died(guard: BaseEnemy) -> void:
	_distress_guards.erase(guard)
	if _distress_guards.is_empty() and is_instance_valid(_distress_root):
		_distress_success()

func _distress_tick(delta: float) -> void:
	if not is_instance_valid(_distress_root):
		_distress_root = null
		return

	_distress_timer -= delta
	if _distress_timer <= 0.0:
		_distress_fail("SIGNAL LOST...")

func _distress_success() -> void:
	_show_banner("CREW RESCUED!", Color(0.3, 1.0, 0.5))
	_emit_reward_at(_distress_root.global_position, DISTRESS_XP, DISTRESS_COINS)
	_distress_cleanup()

func _distress_fail(msg: String) -> void:
	_show_banner(msg, Color(0.6, 0.6, 0.6))
	# Kill remaining guards
	for g in _distress_guards.duplicate():
		if is_instance_valid(g):
			g.queue_free()
	_distress_guards.clear()
	_distress_cleanup()

func _distress_cleanup() -> void:
	if is_instance_valid(_distress_root):
		var tw := _distress_root.create_tween()
		tw.tween_property(_distress_root, "modulate:a", 0.0, 0.4)
		tw.tween_callback(_distress_root.queue_free)
	_on_event_finished(_distress_root)
	_distress_root = null

# ---------------------------------------------------------------------------
# Event 6 — Warp Jumper
# ---------------------------------------------------------------------------

const WARP_HP: float = 55.0
const WARP_SPEED: float = 160.0
const WARP_JUMP_INTERVAL: float = 3.5
const WARP_JUMP_INVIS_DURATION: float = 0.6
const WARP_LIFETIME: float = 20.0
const WARP_COINS: int = 35
const WARP_XP: int = 80

var _warp_root: Node = null
var _warp_body: SpecialEnemyBody = null
var _warp_timer: float = 0.0
var _warp_jump_timer: float = 0.0
var _warp_invulnerable: bool = false

func _spawn_warp_jumper() -> void:
	_show_banner("WARP JUMPER DETECTED", Color(0.3, 0.8, 1.0))

	var root := Node2D.new()
	root.name = "WarpJumperEvent"
	get_tree().current_scene.add_child(root)
	_active_event = root

	var body := _build_special_enemy(
		"res://assets/sprites/enemyGreen3.png", WARP_HP, 13.0, Vector2(0.9, 0.9))
	body.name = "WarpBody"
	var spr := body.get_node_or_null("Sprite2D") as Sprite2D
	if spr:
		spr.modulate = Color(0.4, 1.0, 1.0)

	root.add_child(body)
	body.global_position = _random_edge_pos()
	body.scale = Vector2.ZERO
	var tw := body.create_tween()
	tw.tween_property(body, "scale", Vector2(1.3, 1.3), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "scale", Vector2.ONE, 0.08)

	_warp_root = root
	_warp_body = body
	_warp_timer = WARP_LIFETIME
	_warp_jump_timer = WARP_JUMP_INTERVAL
	_warp_invulnerable = false
	body.killed.connect(_warp_kill)

func _warp_tick(delta: float) -> void:
	if not is_instance_valid(_warp_root) or not is_instance_valid(_warp_body):
		_warp_root = null
		return

	_warp_timer -= delta
	_warp_jump_timer -= delta

	if not _warp_invulnerable:
		# Chase nearest player
		var target := _nearest_player_to(_warp_body.global_position)
		if target:
			var dir := (target.global_position - _warp_body.global_position).normalized()
			_warp_body.velocity = dir * WARP_SPEED
			_warp_body.move_and_slide()
			var spr := _warp_body.get_node_or_null("Sprite2D") as Sprite2D
			if spr and dir != Vector2.ZERO:
				spr.rotation = dir.angle() + PI * 0.5

	if _warp_jump_timer <= 0.0:
		_warp_jump_timer = WARP_JUMP_INTERVAL
		_do_warp_jump()

	if _warp_timer <= 0.0:
		_warp_escape()

func _do_warp_jump() -> void:
	if not is_instance_valid(_warp_body):
		return
	_warp_invulnerable = true
	_warp_body.collision_layer = 0   # invulnerable while jumping

	var spr := _warp_body.get_node_or_null("Sprite2D") as Sprite2D

	# Flash out
	var tw := _warp_body.create_tween()
	tw.set_parallel(true)
	if spr:
		tw.tween_property(spr, "modulate:a", 0.0, WARP_JUMP_INVIS_DURATION * 0.4)
	tw.tween_property(_warp_body, "scale", Vector2(0.1, 0.1), WARP_JUMP_INVIS_DURATION * 0.4)
	tw.chain().tween_callback(func():
		if not is_instance_valid(_warp_body):
			return
		# Teleport
		_warp_body.global_position = _random_arena_pos(700.0, 440.0)
		# Flash back in
		var tw2 := _warp_body.create_tween()
		tw2.set_parallel(true)
		if is_instance_valid(spr):
			tw2.tween_property(spr, "modulate:a", 1.0, WARP_JUMP_INVIS_DURATION * 0.6)
		tw2.tween_property(_warp_body, "scale", Vector2(1.3, 1.3), WARP_JUMP_INVIS_DURATION * 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.chain().tween_property(_warp_body, "scale", Vector2.ONE, 0.1)
		tw2.chain().tween_callback(func():
			if is_instance_valid(_warp_body):
				_warp_body.collision_layer = 2
			_warp_invulnerable = false
		)
	)

func _warp_kill() -> void:
	if not is_instance_valid(_warp_root):
		return
	_show_banner("WARP JUMPER ELIMINATED!", Color(0.3, 0.9, 1.0))
	_emit_reward_at(_warp_body.global_position, WARP_XP, WARP_COINS)
	_warp_cleanup()

func _warp_escape() -> void:
	_show_banner("WARP JUMPER ESCAPED", Color(0.6, 0.6, 0.6))
	_warp_cleanup()

func _warp_cleanup() -> void:
	if is_instance_valid(_warp_root):
		var tw := _warp_root.create_tween()
		tw.tween_property(_warp_root, "modulate:a", 0.0, 0.3)
		tw.tween_callback(_warp_root.queue_free)
	_on_event_finished(_warp_root)
	_warp_root = null
	_warp_body = null

# ---------------------------------------------------------------------------
# Damage dispatch — called by Game.gd projectile hits
# ---------------------------------------------------------------------------



# ---------------------------------------------------------------------------
# Reward helpers
# ---------------------------------------------------------------------------

signal special_xp_dropped(amount: int, world_pos: Vector2)
signal special_coin_dropped(amount: int, world_pos: Vector2)

func _emit_reward_at(pos: Vector2, xp: int, coins: int) -> void:
	if xp > 0:
		special_xp_dropped.emit(xp, pos)
	if coins > 0:
		special_coin_dropped.emit(coins, pos)

func _on_special_xp_dropped(amount: int, pos: Vector2) -> void:
	special_xp_dropped.emit(amount, pos)

func _on_special_coin_dropped(amount: int, pos: Vector2) -> void:
	special_coin_dropped.emit(amount, pos)

# ---------------------------------------------------------------------------
# Main process override — drives all active events each frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _is_stopped:
		return
	if wave_manager == null or not wave_manager.is_running:
		return
	if wave_manager.current_wave_index < MIN_WAVE_INDEX:
		return

	# Tick active events
	if is_instance_valid(_salvager_root):
		_salvager_tick(delta)
	if is_instance_valid(_carrier_root):
		_carrier_tick(delta)
	if is_instance_valid(_beacon_root):
		_beacon_tick(delta)
	if is_instance_valid(_distress_root):
		_distress_tick(delta)
	if is_instance_valid(_warp_root):
		_warp_tick(delta)

	if _active_event != null:
		return  # don't start a new event while one is live

	_event_timer -= delta
	if _event_timer <= 0.0:
		_trigger_random_event()
		_reset_timer()
