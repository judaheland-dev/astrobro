extends Node
class_name WaveManager

## WaveManager - reads WaveData array, spawns enemies, tracks wave completion.

signal wave_started(wave_number: int, total_waves: int)
signal wave_cleared(wave_number: int)
signal all_waves_cleared()
signal enemy_spawned(enemy: BaseEnemy)
signal wave_timer_updated(remaining: float)

@export var wave_data_list: Array[WaveData] = []
@export var spawn_container: Node = null          # node enemies are added to
@export var infinite_after_static: bool = true

var current_wave_index: int = -1
var active_enemies: int = 0
var is_running: bool = false
var is_stopped: bool = false  # set when the run ends; halts all processing

var _spawn_queue: Array = []   # Array of {data: EnemyData, count: int, multiplier: float, speed_mult: float}
var _spawn_timer: float = 0.0
var _spawn_interval: float = 0.5
var _targets: Array[Node] = []

# Wave timer
var _wave_time_remaining: float = 0.0
var _last_timer_second: int = -1
var _active_enemy_nodes: Array[BaseEnemy] = []

func register_targets(targets: Array[Node]) -> void:
	_targets = targets

func stop() -> void:
	is_stopped = true
	is_running = false
	_spawn_queue.clear()
	_wave_time_remaining = 0.0
	wave_timer_updated.emit(0.0)

func start_waves() -> void:
	is_running = true
	_advance_wave()

func next_wave() -> void:
	is_running = true
	_advance_wave()

func _advance_wave() -> void:
	current_wave_index += 1
	_active_enemy_nodes.clear()
	if current_wave_index >= wave_data_list.size():
		if infinite_after_static:
			_start_procedural_wave(current_wave_index)
		else:
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
	_wave_time_remaining = wave.time_limit
	_last_timer_second = int(ceil(wave.time_limit)) if wave.time_limit > 0.0 else -1
	wave_timer_updated.emit(_wave_time_remaining)

func _build_spawn_queue(wave: WaveData) -> void:
	_spawn_queue.clear()
	for i in wave.enemy_pool.size():
		var data: EnemyData = wave.enemy_pool[i]
		var count: int = wave.enemy_counts[i] if i < wave.enemy_counts.size() else 1
		var wave_multiplier := 1.0 + (current_wave_index * 0.15)
		var speed_mult := 1.0 + (current_wave_index * 0.02)
		_spawn_queue.append({
			"data": data,
			"count": count,
			"multiplier": wave_multiplier,
			"speed_mult": speed_mult,
		})

func _process(delta: float) -> void:
	if is_stopped:
		return
	if _wave_time_remaining > 0.0 and is_running:
		_wave_time_remaining -= delta
		wave_timer_updated.emit(maxf(0.0, _wave_time_remaining))
		if _wave_time_remaining <= 0.0:
			_force_clear_wave()
			return

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
		&"grunt":         "res://assets/sprites/enemyRed1.png",
		&"speeder":       "res://assets/sprites/enemyBlue1.png",
		&"brute":         "res://assets/sprites/enemyBlack1.png",
		&"exploder":      "res://assets/sprites/enemyGreen1.png",
		&"ranger":        "res://assets/sprites/enemyBlue2.png",
		&"sniper":        "res://assets/sprites/enemyBlue3.png",
		&"sentinel":      "res://assets/sprites/enemyBlack3.png",
		&"acid_ranger":   "res://assets/sprites/enemyGreen2.png",
		&"heavy_ranger":  "res://assets/sprites/enemyBlue4.png",
		&"tracker":       "res://assets/sprites/enemyRed3.png",
		&"corruptor":     "res://assets/sprites/enemyGreen4.png",
		&"boss":          "res://assets/sprites/enemyBlack5.png",
		&"boss_harbinger":"res://assets/sprites/enemyBlue5.png",
		&"boss_broodmother":"res://assets/sprites/enemyGreen5.png",
		&"boss_titan":    "res://assets/sprites/enemyRed5.png",
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
	enemy_node.scale_with_wave(entry["multiplier"], entry["speed_mult"])
	# Give boss-type enemies a reference to the spawn container for summoning
	if entry["data"] and entry["data"].ai_type in [
			EnemyData.AIType.ELITE_SUMMONER]:
		enemy_node.spawn_container = parent
	enemy_node.global_position = _random_spawn_position()
	enemy_node.died.connect(_on_enemy_died)
	active_enemies += 1
	_active_enemy_nodes.append(enemy_node)
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

func _on_enemy_died(enemy: BaseEnemy) -> void:
	active_enemies -= 1
	_active_enemy_nodes.erase(enemy)
	if active_enemies <= 0 and _spawn_queue.is_empty():
		_wave_time_remaining = 0.0
		_last_timer_second = -1
		wave_timer_updated.emit(0.0)
		wave_cleared.emit(current_wave_index + 1)
		is_running = false

func _force_clear_wave() -> void:
	if not is_running:
		return
	_wave_time_remaining = 0.0
	_last_timer_second = -1
	is_running = false
	_spawn_queue.clear()
	wave_timer_updated.emit(0.0)
	for enemy in _active_enemy_nodes:
		if is_instance_valid(enemy):
			if enemy.died.is_connected(_on_enemy_died):
				enemy.died.disconnect(_on_enemy_died)
			enemy.set_physics_process(false)
			var tween := enemy.create_tween()
			tween.tween_property(enemy, "modulate:a", 0.0, 0.35)
			tween.tween_callback(enemy.queue_free)
	active_enemies = 0
	_active_enemy_nodes.clear()
	wave_cleared.emit(current_wave_index + 1)

# ---------------------------------------------------------------------------
# Infinite procedural wave generation
# ---------------------------------------------------------------------------

func _start_procedural_wave(wave_idx: int) -> void:
	var wave := _generate_procedural_wave(wave_idx)
	GameManager.run_wave = wave_idx + 1
	wave_started.emit(wave_idx + 1, 0)
	_build_spawn_queue(wave)
	_spawn_interval = wave.spawn_interval
	_spawn_timer = wave.initial_delay
	active_enemies = 0
	_active_enemy_nodes.clear()
	_wave_time_remaining = wave.time_limit
	_last_timer_second = int(ceil(wave.time_limit)) if wave.time_limit > 0.0 else -1
	wave_timer_updated.emit(_wave_time_remaining)
	is_running = true

func _generate_procedural_wave(wave_idx: int) -> WaveData:
	var wave := WaveData.new()
	wave.wave_number = wave_idx + 1
	var is_boss := (wave_idx + 1) % 5 == 0
	wave.is_boss_wave = is_boss

	var tier: int = wave_idx - 10  # 0 at wave 11
	var grunt_data: EnemyData = ResourceLoader.load("res://resources/enemies/grunt.tres")
	var speeder_data: EnemyData = ResourceLoader.load("res://resources/enemies/speeder.tres")
	var exploder_data: EnemyData = ResourceLoader.load("res://resources/enemies/exploder.tres")

	wave.time_limit = maxf(50.0, 90.0 - tier * 2.0)
	wave.spawn_interval = maxf(0.25, 0.55 - tier * 0.01)
	wave.initial_delay = 1.0
	wave.bonus_coins = 20 + tier * 5
	wave.bonus_xp = 0

	if is_boss:
		# Rotate through boss pool: Dreadlord, Harbinger, Broodmother, Titan
		var boss_paths: Array[String] = [
			"res://resources/enemies/boss.tres",
			"res://resources/enemies/boss_harbinger.tres",
			"res://resources/enemies/boss_broodmother.tres",
			"res://resources/enemies/boss_titan.tres",
		]
		# Boss waves occur at 15, 20, 25, 30... (tier 4, 9, 14, 19...)
		# Use tier / 5 to advance the pool index once every 5 boss waves
		var boss_pool_idx: int = (tier / 5) % boss_paths.size()
		var boss_path: String = boss_paths[boss_pool_idx]
		var boss_data: EnemyData = ResourceLoader.load(boss_path)
		wave.enemy_pool.append(boss_data)
		wave.enemy_counts.append(1)
		wave.enemy_pool.append(grunt_data)
		wave.enemy_counts.append(8 + (tier / 2))
		if tier >= 3:
			var brute_data: EnemyData = ResourceLoader.load("res://resources/enemies/brute.tres")
			wave.enemy_pool.append(brute_data)
			wave.enemy_counts.append(2 + (tier / 4))
	else:
		var total_enemies: int = 25 + tier * 4
		var grunt_count: int = (total_enemies * 4) / 10
		var speeder_count: int = (total_enemies * 2) / 10
		var exploder_count: int = (total_enemies * 2) / 10
		var extra_count: int = 0
		wave.enemy_pool.append(grunt_data)
		wave.enemy_counts.append(maxi(grunt_count, 1))
		wave.enemy_pool.append(speeder_data)
		wave.enemy_counts.append(maxi(speeder_count, 1))
		wave.enemy_pool.append(exploder_data)
		wave.enemy_counts.append(maxi(exploder_count, 1))
		# tier >= 1: snipers + heavy_rangers
		if tier >= 1:
			var sniper_data: EnemyData = ResourceLoader.load("res://resources/enemies/sniper.tres")
			wave.enemy_pool.append(sniper_data)
			wave.enemy_counts.append(maxi((total_enemies * 1) / 10, 1))
			extra_count += (total_enemies * 1) / 10
			var heavy_ranger_data: EnemyData = ResourceLoader.load("res://resources/enemies/heavy_ranger.tres")
			wave.enemy_pool.append(heavy_ranger_data)
			wave.enemy_counts.append(maxi((total_enemies * 1) / 10, 1))
			extra_count += (total_enemies * 1) / 10
		# tier >= 2: trackers + sentinels + acid_rangers
		if tier >= 2:
			var tracker_data: EnemyData = ResourceLoader.load("res://resources/enemies/tracker.tres")
			wave.enemy_pool.append(tracker_data)
			wave.enemy_counts.append(maxi((total_enemies * 1) / 10, 1))
			extra_count += (total_enemies * 1) / 10
			var sentinel_data: EnemyData = ResourceLoader.load("res://resources/enemies/sentinel.tres")
			wave.enemy_pool.append(sentinel_data)
			wave.enemy_counts.append(maxi((total_enemies * 1) / 10, 1))
			extra_count += (total_enemies * 1) / 10
			var acid_ranger_data: EnemyData = ResourceLoader.load("res://resources/enemies/acid_ranger.tres")
			wave.enemy_pool.append(acid_ranger_data)
			wave.enemy_counts.append(maxi((total_enemies * 1) / 10, 1))
			extra_count += (total_enemies * 1) / 10
		# tier >= 3: brutes
		if tier >= 3:
			var brute_data: EnemyData = ResourceLoader.load("res://resources/enemies/brute.tres")
			var brute_count: int = (total_enemies * 1) / 10
			wave.enemy_pool.append(brute_data)
			wave.enemy_counts.append(maxi(brute_count, 1))
			extra_count += brute_count
		# tier >= 4: corruptors
		if tier >= 4:
			var corruptor_data: EnemyData = ResourceLoader.load("res://resources/enemies/corruptor.tres")
			var corruptor_count: int = (total_enemies * 1) / 10
			wave.enemy_pool.append(corruptor_data)
			wave.enemy_counts.append(maxi(corruptor_count, 1))
			extra_count += corruptor_count
		# tier >= 6: rangers
		if tier >= 6:
			var ranger_data: EnemyData = ResourceLoader.load("res://resources/enemies/ranger.tres")
			var ranger_count: int = (total_enemies * 1) / 10
			wave.enemy_pool.append(ranger_data)
			wave.enemy_counts.append(maxi(ranger_count, 1))
			extra_count += ranger_count
		var assigned: int = grunt_count + speeder_count + exploder_count + extra_count
		var leftover: int = total_enemies - assigned
		if leftover > 0:
			wave.enemy_counts[0] = wave.enemy_counts[0] + leftover

	return wave
