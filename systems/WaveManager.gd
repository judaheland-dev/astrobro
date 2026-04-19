extends Node
class_name WaveManager

## WaveManager - reads WaveData array, spawns enemies, tracks wave completion.

signal wave_started(wave_number: int, total_waves: int)
signal wave_cleared(wave_number: int)
signal all_waves_cleared()
signal enemy_spawned(enemy: BaseEnemy)

@export var wave_data_list: Array[WaveData] = []
@export var spawn_container: Node = null          # node enemies are added to

var current_wave_index: int = -1
var active_enemies: int = 0
var is_running: bool = false

var _spawn_queue: Array = []   # Array of {data: EnemyData, count: int}
var _spawn_timer: float = 0.0
var _spawn_interval: float = 0.5
var _targets: Array[Node] = []

func register_targets(targets: Array[Node]) -> void:
	_targets = targets

func start_waves() -> void:
	is_running = true
	_advance_wave()

func next_wave() -> void:
	is_running = true
	_advance_wave()

func _advance_wave() -> void:
	current_wave_index += 1
	if current_wave_index >= wave_data_list.size():
		all_waves_cleared.emit()
		is_running = false
		return

	GameManager.run_wave = current_wave_index + 1
	var wave: WaveData = wave_data_list[current_wave_index]
	wave_started.emit(current_wave_index + 1, wave_data_list.size())

	_build_spawn_queue(wave)
	_spawn_interval = wave.spawn_interval
	_spawn_timer = wave.initial_delay
	active_enemies = 0

func _build_spawn_queue(wave: WaveData) -> void:
	_spawn_queue.clear()
	for i in wave.enemy_pool.size():
		var data: EnemyData = wave.enemy_pool[i]
		var count: int = wave.enemy_counts[i] if i < wave.enemy_counts.size() else 1
		# Apply difficulty scaling
		var wave_multiplier := 1.0 + (current_wave_index * 0.15)
		_spawn_queue.append({
			"data": data,
			"count": count,
			"multiplier": wave_multiplier
		})

func _process(delta: float) -> void:
	if not is_running or _spawn_queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_next()
		_spawn_timer = _spawn_interval

func _spawn_next() -> void:
	if _spawn_queue.is_empty():
		return

	var entry: Dictionary = _spawn_queue[0]

	# Build enemy entirely in code - no PackedScene required
	var enemy_node := BaseEnemy.new()
	enemy_node.collision_layer = 2   # enemies on layer 2
	enemy_node.collision_mask  = 3   # collide with layer 1 (players/walls) and layer 2

	# Sprite - pick based on enemy id, fall back to solid color
	var sprite := Sprite2D.new()
	sprite.name = "Sprite2D"
	var enemy_id: StringName = entry["data"].id if entry["data"] else &""
	var sprite_map: Dictionary = {
		&"grunt":    "res://assets/sprites/enemyRed1.png",
		&"speeder":  "res://assets/sprites/enemyBlue1.png",
		&"brute":    "res://assets/sprites/enemyBlack1.png",
		&"exploder": "res://assets/sprites/enemyGreen1.png",
		&"ranger":   "res://assets/sprites/enemyBlue2.png",
		&"boss":     "res://assets/sprites/enemyRed2.png",
	}
	var sprite_path: String = sprite_map.get(enemy_id, "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)
	else:
		var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.2, 0.2))
		sprite.texture = ImageTexture.create_from_image(img)
	if entry["data"] and entry["data"].sprite_scale != Vector2.ONE:
		sprite.scale = entry["data"].sprite_scale
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

	# Contact area - detects players (layer 1) only
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

	enemy_node.enemy_data = entry["data"]
	var parent := spawn_container if spawn_container else get_tree().current_scene
	parent.add_child(enemy_node)

	# Wire contact area signals after adding to tree
	area.body_entered.connect(enemy_node._on_body_entered)
	area.body_exited.connect(enemy_node._on_body_exited)

	enemy_node.register_targets(_targets)
	enemy_node.scale_with_wave(entry["multiplier"])
	enemy_node.global_position = _random_spawn_position()
	enemy_node.died.connect(_on_enemy_died)
	active_enemies += 1
	enemy_spawned.emit(enemy_node)

	entry["count"] -= 1
	if entry["count"] <= 0:
		_spawn_queue.pop_front()

func _random_spawn_position() -> Vector2:
	# Spawn just inside the arena walls so enemies are always on the nav mesh.
	# Arena is 1920x1200 centered at origin; nav mesh covers ~±950 x ±590.
	var hw := 900.0   # safe horizontal half-width (wall at 960)
	var hh := 560.0   # safe vertical half-height (wall at 600)
	var edge := randi() % 4
	match edge:
		0: return Vector2(randf_range(-hw, hw), -hh)   # top edge
		1: return Vector2(randf_range(-hw, hw),  hh)   # bottom edge
		2: return Vector2(-hw, randf_range(-hh, hh))   # left edge
		_: return Vector2( hw, randf_range(-hh, hh))   # right edge

func _on_enemy_died(_enemy: BaseEnemy) -> void:
	active_enemies -= 1
	if active_enemies <= 0 and _spawn_queue.is_empty():
		wave_cleared.emit(current_wave_index + 1)
		is_running = false
