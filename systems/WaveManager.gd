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
var _current_wave_data: WaveData = null  # active wave; kept for continuous queue refill
var _targets: Array[Node] = []

# Wave timer
var _wave_time_remaining: float = 0.0
var _last_timer_second: int = -1
var _active_enemy_nodes: Array[BaseEnemy] = []

## Adaptive difficulty calculator. Assign from Game.gd after spawning players.
var power_calculator: PlayerPowerCalculator = null

# Internal: elapsed seconds since wave started (for kill-time tracking)
var _wave_elapsed: float = 0.0
# Total enemies spawned this wave (for performance scoring)
var _wave_spawned_count: int = 0
# Per-enemy respawn queue: each entry is { timer, data, multiplier, speed_mult }.
# When an enemy dies during a timed wave it is added here with a 5 s countdown.
const ENEMY_RESPAWN_DELAY: float = 5.0
# Minimum seconds before the next enemy spawns from the queue after a kill.
const KILL_SPAWN_COOLDOWN: float = 2.5
var _respawn_queue: Array[Dictionary] = []
var _respawn_delay_timer: float = -1.0
# Surge scale: builds up gradually when the player stays overpowered across waves,
# and decays when they are not.  Applied to spawn counts, cap, and interval compression
# so difficulty ramps slowly rather than blasting all at once.
var _surge_scale: float = 1.0

# Round-robin cursor: which slot in _spawn_queue to pull from next.
# Cycling through types ensures stronger enemies appear alongside grunts
# from the very first spawn rather than after all grunts are exhausted.
var _spawn_queue_index: int = 0

# ---------------------------------------------------------------------------
# Cycling difficulty escalation
#
# Every CYCLE_LENGTH waves there is a "break" wave (the last wave in each
# cycle is the break).  Power ramps inside each cycle, then the *next* cycle
# starts a bit harder than the previous one started, controlled by
# CYCLE_ESCALATION.  Both cycle length and escalation rate vary by difficulty.
#
# CYCLE_LENGTH      – how many waves per cycle (break is the last one)
# BREAK_RELIEF      – multiplier applied to power on break waves (< 1 = easier)
# CYCLE_ESCALATION  – how much the cycle-start baseline grows each cycle
# POWER_RAMP        – power growth per wave inside a cycle (additive)
# ---------------------------------------------------------------------------
const _DIFF_CYCLE: Dictionary = {
	# difficulty_int: { cycle_length, break_relief, cycle_escalation, power_ramp }
	# SUPER_EASY = 0
	0: { "cycle_length": 8,  "break_relief": 0.45, "cycle_escalation": 0.04, "power_ramp": 0.07 },
	# EASY = 1
	1: { "cycle_length": 7,  "break_relief": 0.55, "cycle_escalation": 0.07, "power_ramp": 0.10 },
	# NORMAL = 2
	2: { "cycle_length": 6,  "break_relief": 0.60, "cycle_escalation": 0.10, "power_ramp": 0.14 },
	# HARD = 3
	3: { "cycle_length": 5,  "break_relief": 0.65, "cycle_escalation": 0.14, "power_ramp": 0.18 },
	# SUPER_HARD = 4
	4: { "cycle_length": 4,  "break_relief": 0.70, "cycle_escalation": 0.20, "power_ramp": 0.24 },
}

# ──────────────────────────────────────────────────────────────────────────────
# Player Display-Power integration
# ──────────────────────────────────────────────────────────────────────────────
## Player power thresholds expressed as multiples of each wave's WaveData.expected_power.
## HIGH    (×1.5): spawn counts increase and the concurrent cap expands.
## EXTREME (×2.5): enemy types from future tiers unlock early.
## SUPREME (×4.0): enemy stats inflate and the concurrent cap is fully bypassed.
const POWER_HIGH_MULT: float    = 1.5
const POWER_EXTREME_MULT: float = 2.5
const POWER_SUPREME_MULT: float = 4.0
## Max HP/damage multiplier applied to every enemy at supreme power.
const POWER_SUPREME_STAT_MULT: float = 1.5
## Max move-speed multiplier at supreme power (capped lower than HP/damage).
const POWER_SUPREME_SPEED_MULT: float = 1.4
## Hard cap on the stat multiplier passed to scale_with_wave.
## Prevents enemy HP/damage from growing to unkillable levels in infinite waves.
const MAX_WAVE_STAT_MULT: float = 8.0
## Surge scale ceiling.  _surge_scale never exceeds this.
const SURGE_MAX: float = 2.0
## How much _surge_scale grows each wave the player is above POWER_HIGH_MULT.
const SURGE_RAMP_PER_WAVE: float = 0.18
## How much _surge_scale decays each wave the player is not overpowered (or on a break wave).
const SURGE_DECAY_PER_WAVE: float = 0.12

## Returns the highest display-power score across all registered players (via _targets).
## Falls back to 1.0 (baseline) if no Player nodes are found.
func _player_display_power() -> float:
	var best: float = 1.0
	for node in _targets:
		if node is Player:
			var s := PlayerPowerCalculator.calc_display_power(node as Player)
			if s > best:
				best = s
	return best

## Returns the expected power baseline for the current wave.
## Uses WaveData.expected_power when set; otherwise estimates from wave tier.
func _wave_expected_power() -> float:
	if current_wave_index >= 0 and current_wave_index < wave_data_list.size():
		var w := wave_data_list[current_wave_index]
		if w.expected_power > 0.0:
			return w.expected_power
	# Procedural waves: grow steadily by wave tier (tier 0 starts at wave 11)
	var tier := maxi(0, current_wave_index - 10)
	return 1.0 + tier * 0.18

## Ratio of the player's current power to the current wave's expected power.
func _power_ratio() -> float:
	return _player_display_power() / maxf(_wave_expected_power(), 0.1)

## Returns a 0–1 factor for how deep into the SUPREME tier the player is.
## 0 = below EXTREME; 1 = fully at SUPREME or beyond.
func _supreme_factor() -> float:
	return clampf(
		(_power_ratio() - POWER_EXTREME_MULT) / (POWER_SUPREME_MULT - POWER_EXTREME_MULT),
		0.0, 1.0
	)

func _diff_params() -> Dictionary:
	var d: int = GameManager.current_difficulty
	return _DIFF_CYCLE.get(d, _DIFF_CYCLE[2])

## Returns a 0-based "effective wave index" that increases inside each cycle
## then is dampened on break waves.  Used as a multiplier base.
func _get_wave_power(wave_idx: int) -> float:
	var p: Dictionary = _diff_params()
	var cycle_len: int   = p["cycle_length"]
	var escalation: float = p["cycle_escalation"]
	var ramp: float       = p["power_ramp"]
	var relief: float     = p["break_relief"]

	var cycle: int        = wave_idx / cycle_len
	var pos_in_cycle: int = wave_idx % cycle_len
	var is_break: bool    = (pos_in_cycle == cycle_len - 1)

	# Baseline rises each completed cycle
	var baseline: float = 1.0 + cycle * escalation
	# Within-cycle ramp (0 at start of cycle, peaks just before break)
	var ramp_val: float = pos_in_cycle * ramp
	var power: float = baseline + ramp_val
	if is_break:
		power *= relief
	return power

func is_break_wave(wave_idx: int) -> bool:
	var p: Dictionary = _diff_params()
	return (wave_idx % p["cycle_length"]) == (p["cycle_length"] - 1)

## Updates _surge_scale at the start of each wave.
## Ramps up when the player stays above POWER_HIGH_MULT for several waves;
## decays on break waves or when they are no longer overpowered.
## This produces a gradual scaling acceleration instead of an instant blast.
func _update_surge_scale() -> void:
	var pr := _power_ratio()
	if not is_break_wave(current_wave_index) and pr >= POWER_HIGH_MULT:
		# Ramp faster the further above HIGH the player is (up to 2× rate at SUPREME).
		var over_factor := clampf((pr - POWER_HIGH_MULT) / (POWER_SUPREME_MULT - POWER_HIGH_MULT), 0.0, 1.0)
		_surge_scale = minf(SURGE_MAX, _surge_scale + SURGE_RAMP_PER_WAVE * (1.0 + over_factor))
	else:
		_surge_scale = maxf(1.0, _surge_scale - SURGE_DECAY_PER_WAVE)

func register_targets(targets: Array[Node]) -> void:
	_targets = targets

func register_power_calculator(calc: PlayerPowerCalculator) -> void:
	power_calculator = calc

func stop() -> void:
	is_stopped = true
	is_running = false
	_spawn_queue.clear()
	_spawn_queue_index = 0
	_wave_time_remaining = 0.0
	_surge_scale = 1.0
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

	_update_surge_scale()
	_build_spawn_queue(wave)
	_current_wave_data = wave
	_spawn_interval = wave.spawn_interval * 1.4  # global slow-down: reduce overall spawn rate
	# Scale how fast enemies trickle in based on difficulty, and slow on break waves
	match GameManager.current_difficulty:
		GameManager.Difficulty.SUPER_EASY: _spawn_interval *= 2.0
		GameManager.Difficulty.EASY:       _spawn_interval *= 1.4
		GameManager.Difficulty.HARD:       _spawn_interval *= 0.82
		GameManager.Difficulty.SUPER_HARD: _spawn_interval *= 0.62
	if is_break_wave(current_wave_index):
		_spawn_interval *= 1.6  # slower trickle on break waves
	else:
		# Adaptive: if player is dominating, enemies arrive faster on static waves
		if power_calculator:
			_spawn_interval /= clampf(power_calculator.pressure_score, 0.7, 1.5)
		# Interval compression scales with _surge_scale for gradual tightening over waves.
		if _surge_scale > 1.0:
			var surge_t := (_surge_scale - 1.0) / (SURGE_MAX - 1.0)
			_spawn_interval /= lerpf(1.0, 1.5, surge_t)
	_spawn_timer = wave.initial_delay
	active_enemies = 0
	_wave_elapsed = 0.0
	_wave_spawned_count = 0
	_active_enemy_nodes.clear()
	_respawn_delay_timer = -1.0
	_wave_time_remaining = wave.time_limit
	_last_timer_second = int(ceil(wave.time_limit)) if wave.time_limit > 0.0 else -1
	wave_timer_updated.emit(_wave_time_remaining)
	if power_calculator:
		power_calculator.begin_wave()
	is_running = true

func _build_spawn_queue(wave: WaveData) -> void:
	_spawn_queue.clear()
	_spawn_queue_index = 0
	# wave_power already encodes difficulty, cycle position, and break relief
	var wave_power: float = _get_wave_power(current_wave_index)
	# For pre-authored static waves, blend in adaptive pressure so dominating has consequences.
	# Procedural waves already bake pressure into their WaveData counts/timers.
	if current_wave_index < wave_data_list.size() and power_calculator:
		wave_power *= clampf(power_calculator.pressure_score, 0.6, 1.8)
	# Spawn count scales with _surge_scale which builds gradually when the player stays
	# overpowered across multiple waves, rather than blasting immediately.
	if current_wave_index < wave_data_list.size():
		wave_power *= _surge_scale
	var base_speed := 1.0 + (current_wave_index * 0.02)
	for i in wave.enemy_pool.size():
		var data: EnemyData = wave.enemy_pool[i]
		var base_count: int = wave.enemy_counts[i] if i < wave.enemy_counts.size() else 1
		var wave_multiplier: float
		var speed_mult: float
		var count: int
		match GameManager.current_difficulty:
			GameManager.Difficulty.SUPER_EASY:
				wave_multiplier = wave_power * 0.4
				speed_mult = base_speed * 0.6
				count = maxi(1, int(base_count * wave_power * 0.5))
			GameManager.Difficulty.EASY:
				wave_multiplier = wave_power * 0.65
				speed_mult = base_speed * 0.75
				count = maxi(1, int(base_count * wave_power * 0.75))
			GameManager.Difficulty.HARD:
				wave_multiplier = wave_power * 1.35
				speed_mult = base_speed * 0.90
				count = maxi(1, int(ceil(base_count * wave_power * 1.35)))
			GameManager.Difficulty.SUPER_HARD:
				wave_multiplier = wave_power * 1.7
				speed_mult = base_speed * 1.05
				count = maxi(1, int(ceil(base_count * wave_power * 1.65)))
			_:
				wave_multiplier = wave_power
				speed_mult = base_speed
				count = maxi(1, int(ceil(base_count * wave_power)))
		# Cap stat multiplier so enemies never become literally unkillable.
		# Count and speed are left uncapped — more/faster enemies still scale difficulty.
		wave_multiplier = minf(wave_multiplier, MAX_WAVE_STAT_MULT)
		_spawn_queue.append({
			"data": data,
			"count": count,
			"multiplier": wave_multiplier,
			"speed_mult": speed_mult,
		})

func _process(delta: float) -> void:
	if is_stopped:
		return
	if is_running:
		_wave_elapsed += delta
	if _wave_time_remaining > 0.0 and is_running:
		_wave_time_remaining -= delta
		wave_timer_updated.emit(maxf(0.0, _wave_time_remaining))
		if _wave_time_remaining <= 0.0:
			_force_clear_wave()
			return

	if not is_running:
		return
	if _spawn_queue.is_empty() and _respawn_queue.is_empty():
		return
	# Enforce concurrent enemy cap from power calculator.
	# effective_enemy_cap() grows beyond MAX_CAP when player is dominating,
	# and returns 9999 (fully bypass) at extreme dominance.
	var cap: int = power_calculator.effective_enemy_cap() if power_calculator else 999
	# Cap expansion tied to surge scale — grows gradually as the player stays overpowered
	# rather than instantly tripling on a single high-power wave.
	if _surge_scale > 1.0:
		var surge_t := (_surge_scale - 1.0) / (SURGE_MAX - 1.0)
		cap = int(cap * lerpf(1.0, 2.0, surge_t))
	# Tick per-enemy respawn timers and spawn any that are ready.
	for i in range(_respawn_queue.size() - 1, -1, -1):
		_respawn_queue[i]["timer"] -= delta
		if _respawn_queue[i]["timer"] <= 0.0 and active_enemies < cap:
			var rentry := _respawn_queue[i]
			_respawn_queue.remove_at(i)
			_build_and_spawn(rentry)
	if _spawn_queue.is_empty():
		return
	if active_enemies >= cap:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_next()
		# Dynamic interval compression: when the player is dominating,
		# enemies arrive faster to keep them under pressure.
		var eff_interval := _spawn_interval
		if power_calculator and power_calculator.dominance_score >= PlayerPowerCalculator.DOMINANCE_STRONG:
			var dom_ratio: float = (
				(power_calculator.dominance_score - PlayerPowerCalculator.DOMINANCE_STRONG)
				/ (1.0 - PlayerPowerCalculator.DOMINANCE_STRONG)
			)
			# Up to 70% faster at full dominance, floor at 0.06 s
			eff_interval = maxf(0.06, _spawn_interval * (1.0 - dom_ratio * 0.70))
		_spawn_timer = eff_interval

func _spawn_next() -> void:
	if _spawn_queue.is_empty():
		return
	# Round-robin through enemy types so stronger enemies appear alongside
	# grunts from the start rather than only after all grunts are exhausted.
	_spawn_queue_index = _spawn_queue_index % _spawn_queue.size()
	var entry: Dictionary = _spawn_queue[_spawn_queue_index]
	_build_and_spawn(entry)
	entry["count"] -= 1
	if entry["count"] <= 0:
		_spawn_queue.remove_at(_spawn_queue_index)
		# Don't advance — the next entry slid into this slot after removal.
		# The modulo at the top of the next call handles the boundary case.
	else:
		_spawn_queue_index += 1

func _build_and_spawn(entry: Dictionary) -> void:
	# Build enemy entirely in code - no PackedScene required
	var enemy_node := BaseEnemy.new()
	enemy_node.collision_layer = 2   # enemies on layer 2
	enemy_node.collision_mask  = 6   # collide with layer 2 (enemies) + layer 3 (walls); player contact via Area2D

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

	# ── Supreme-power stat inflation ────────────────────────────────────────────
	# When the player's power reaches SUPREME (4× the wave's expected power),
	# every enemy receives bonus HP, damage, and speed to keep the challenge alive.
	var sf := _supreme_factor()
	if sf > 0.0:
		var stat_scale := 1.0 + sf * (POWER_SUPREME_STAT_MULT - 1.0)
		var spd_scale  := 1.0 + sf * (POWER_SUPREME_SPEED_MULT - 1.0)
		enemy_node.max_health     *= stat_scale
		enemy_node.current_health  = enemy_node.max_health
		enemy_node.contact_damage *= stat_scale
		enemy_node.move_speed     *= spd_scale
		enemy_node.armor          *= stat_scale
		if enemy_node.shield_max > 0.0:
			enemy_node.shield_max        *= stat_scale
			enemy_node.current_shield     = enemy_node.shield_max
			enemy_node.shield_regen_rate *= stat_scale
	# Copier: override with 1/5 of the live player's current stats
	if entry["data"] and entry["data"].id == &"copier":
		var player_node: Player = null
		for t in _targets:
			if t is Player:
				player_node = t
				break
		if player_node:
			enemy_node.copier_sync_to_player(player_node)
	# Give boss-type enemies a reference to the spawn container for summoning
	if entry["data"] and entry["data"].ai_type in [
			EnemyData.AIType.ELITE_SUMMONER]:
		enemy_node.spawn_container = parent
	enemy_node.global_position = _random_spawn_position()
	enemy_node.died.connect(_on_enemy_died)
	active_enemies += 1
	_wave_spawned_count += 1
	_active_enemy_nodes.append(enemy_node)
	enemy_spawned.emit(enemy_node)

func _random_spawn_position() -> Vector2:
	# Spawn just inside the arena walls so enemies are always on the nav mesh.
	# Arena is 1920x1200 centered at origin; nav mesh covers ~±950 x ±590.
	var hw := 900.0   # safe horizontal half-width (wall at 960)
	var hh := 560.0   # safe vertical half-height (wall at 600)
	const MIN_PLAYER_DIST: float = 200.0
	for _attempt in 10:
		var edge := randi() % 4
		var pos: Vector2
		match edge:
			0: pos = Vector2(randf_range(-hw, hw), -hh)
			1: pos = Vector2(randf_range(-hw, hw),  hh)
			2: pos = Vector2(-hw, randf_range(-hh, hh))
			_: pos = Vector2( hw, randf_range(-hh, hh))
		var too_close := false
		for p in _targets:
			if is_instance_valid(p) and pos.distance_to(p.global_position) < MIN_PLAYER_DIST:
				too_close = true
				break
		if not too_close:
			return pos
	# Fallback if all attempts were too close (shouldn't normally happen)
	var edge := randi() % 4
	match edge:
		0: return Vector2(randf_range(-hw, hw), -hh)
		1: return Vector2(randf_range(-hw, hw),  hh)
		2: return Vector2(-hw, randf_range(-hh, hh))
		_: return Vector2( hw, randf_range(-hh, hh))

func _on_enemy_died(enemy: BaseEnemy) -> void:
	active_enemies -= 1
	_active_enemy_nodes.erase(enemy)
	if power_calculator:
		power_calculator.record_kill(_wave_elapsed)
	# Apply a cooldown before the next enemy spawns from the queue after a kill.
	if is_running and not _spawn_queue.is_empty():
		_spawn_timer = maxf(_spawn_timer, KILL_SPAWN_COOLDOWN)
	# Queue an individual 5 s respawn for this enemy when the wave is still running.
	if is_running and _wave_time_remaining > 0.0 and enemy.enemy_data != null:
		_respawn_queue.append({
			"timer": ENEMY_RESPAWN_DELAY,
			"data": enemy.enemy_data,
			"multiplier": enemy.wave_multiplier,
			"speed_mult": enemy.wave_speed_mult,
		})
	if active_enemies <= 0 and _spawn_queue.is_empty() and _respawn_queue.is_empty() and _wave_time_remaining <= 0.0:
		_wave_time_remaining = 0.0
		_last_timer_second = -1
		wave_timer_updated.emit(0.0)
		if power_calculator:
			power_calculator.end_wave(_wave_spawned_count, _wave_elapsed)
		wave_cleared.emit(current_wave_index + 1)
		is_running = false

func _force_clear_wave() -> void:
	if not is_running:
		return
	_wave_time_remaining = 0.0
	_last_timer_second = -1
	is_running = false
	_spawn_queue.clear()
	_respawn_queue.clear()
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
	if power_calculator:
		power_calculator.end_wave(_wave_spawned_count, _wave_elapsed)
	wave_cleared.emit(current_wave_index + 1)

# ---------------------------------------------------------------------------
# Infinite procedural wave generation
# ---------------------------------------------------------------------------

func _start_procedural_wave(wave_idx: int) -> void:
	_update_surge_scale()
	var wave := _generate_procedural_wave(wave_idx)
	GameManager.run_wave = wave_idx + 1
	wave_started.emit(wave_idx + 1, 0)
	_build_spawn_queue(wave)
	_current_wave_data = wave
	_spawn_interval = wave.spawn_interval * 1.4  # global slow-down: reduce overall spawn rate
	# Scale how fast enemies trickle in based on difficulty, and slow on break waves
	match GameManager.current_difficulty:
		GameManager.Difficulty.SUPER_EASY: _spawn_interval *= 2.0
		GameManager.Difficulty.EASY:       _spawn_interval *= 1.4
		GameManager.Difficulty.HARD:       _spawn_interval *= 0.82
		GameManager.Difficulty.SUPER_HARD: _spawn_interval *= 0.62
	if is_break_wave(wave_idx):
		_spawn_interval *= 1.6  # slower trickle on break waves
	else:
		# Adaptive: if player is dominating, enemies arrive faster on static waves
		if power_calculator:
			_spawn_interval /= clampf(power_calculator.pressure_score, 0.7, 1.5)
		# Interval compression scales with _surge_scale for gradual tightening over waves.
		if _surge_scale > 1.0:
			var surge_t := (_surge_scale - 1.0) / (SURGE_MAX - 1.0)
			_spawn_interval /= lerpf(1.0, 1.5, surge_t)
	_spawn_timer = wave.initial_delay
	active_enemies = 0
	_wave_elapsed = 0.0
	_wave_spawned_count = 0
	_active_enemy_nodes.clear()
	_respawn_delay_timer = -1.0
	_wave_time_remaining = wave.time_limit
	_last_timer_second = int(ceil(wave.time_limit)) if wave.time_limit > 0.0 else -1
	wave_timer_updated.emit(_wave_time_remaining)
	if power_calculator:
		power_calculator.begin_wave()
	is_running = true

func _generate_procedural_wave(wave_idx: int) -> WaveData:
	var wave := WaveData.new()
	wave.wave_number = wave_idx + 1

	var tier: int = wave_idx - 10  # 0 at wave 11
	var grunt_data: EnemyData = ResourceLoader.load("res://resources/enemies/grunt.tres")
	var speeder_data: EnemyData = ResourceLoader.load("res://resources/enemies/speeder.tres")
	var exploder_data: EnemyData = ResourceLoader.load("res://resources/enemies/exploder.tres")

	# Break waves override normal boss / enemy logic
	var is_break: bool = is_break_wave(wave_idx)

	# Boss waves occur every 5 waves but NOT on break waves
	var is_boss := not is_break and ((wave_idx + 1) % 5 == 0)
	wave.is_boss_wave = is_boss

	# ── Pressure from adaptive calculator ─────────────────────────────────────
	var pressure: float = power_calculator.pressure_score if power_calculator else 1.0
	# ── Display power from player loadout ──────────────────────────────────────
	var display_pwr := _player_display_power()
	# Power ratio: how far the player exceeds this wave's expected power.
	var pr_gen := display_pwr / maxf(_wave_expected_power(), 0.1)
	# EXTREME power unlocks future enemy types early; SUPREME unlocks everything.
	var power_tier_bonus := 0
	if pr_gen >= POWER_SUPREME_MULT:
		power_tier_bonus = 6
	elif pr_gen >= POWER_EXTREME_MULT:
		power_tier_bonus = clampi(int((pr_gen - POWER_EXTREME_MULT) / ((POWER_SUPREME_MULT - POWER_EXTREME_MULT) / 4.0)) + 2, 2, 6)
	elif pr_gen >= POWER_HIGH_MULT:
		power_tier_bonus = 1
	# Hard/super-hard also unlock ranged enemies sooner so challenge comes from
	# bullet pressure rather than pure movement speed.
	var diff_tier_bonus := 0
	match GameManager.current_difficulty:
		GameManager.Difficulty.HARD:       diff_tier_bonus = 1
		GameManager.Difficulty.SUPER_HARD: diff_tier_bonus = 2
	var eff_tier := tier + power_tier_bonus + diff_tier_bonus  # effective tier for enemy-type gate checks
	# On break waves, clamp pressure down so they always feel like a breather
	if is_break:
		pressure = minf(pressure, 0.85)
	# Hard cap to prevent runaway difficulty on boss waves
	if is_boss:
		pressure = minf(pressure, 1.6)

	if is_break:
		# Catch-your-breath round: longer timer, slow spawn, fewer grunts only
		wave.time_limit = maxf(60.0, 100.0 - tier * 1.0)
		wave.spawn_interval = maxf(0.55, 0.80 - tier * 0.005)
		wave.initial_delay = 2.0
		wave.bonus_coins = 10 + tier * 2
		wave.bonus_xp = 0
		# Scale break-wave count via _get_wave_power (already applies relief)
		var break_count: int = maxi(5, int((15 + tier * 2) * _get_wave_power(wave_idx) * pressure))
		wave.enemy_pool.append(grunt_data)
		wave.enemy_counts.append(break_count)
		wave.enemy_pool.append(speeder_data)
		wave.enemy_counts.append(maxi(1, break_count / 3))
		return wave

	# Pressure scales time limit (higher pressure = shorter window to clear)
	wave.time_limit = maxf(40.0, (90.0 - tier * 2.0) / clampf(pressure, 0.8, 1.3))
	# Interval compression uses surge scale so it tightens gradually across waves.
	var interval_scale_gen := 1.0 + (_surge_scale - 1.0) * 0.5
	wave.spawn_interval = maxf(0.14, (0.55 - tier * 0.01) / clampf(pressure, 0.9, 1.4) / interval_scale_gen)
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
		wave.enemy_counts.append(int((8 + tier / 2) * pressure))
		if tier >= 3:
			var brute_data: EnemyData = ResourceLoader.load("res://resources/enemies/brute.tres")
			wave.enemy_pool.append(brute_data)
			wave.enemy_counts.append(int((2 + tier / 4) * pressure))
	else:
		var bias: Dictionary = power_calculator.enemy_bias if power_calculator else {}

		# Spawn count uses surge scale which builds up gradually across overpowered waves.
		var total_enemies: int = int((25 + tier * 4) * pressure * _surge_scale)

		# Power-driven composition shift: grunts and speeders fade to rare appearances
		# at high power. Exploders are treated as a high-tier threat and keep their
		# full fraction. power_fade: 0.0 = grunt-heavy  →  1.0 = elite-only.
		var power_fade: float = clampf(
			(pr_gen - POWER_HIGH_MULT) / (POWER_SUPREME_MULT - POWER_HIGH_MULT), 0.0, 1.0)
		# Grunts/speeders floor at 0.02 (rare but can still appear); never fully removed.
		var grunt_frac: float   = lerpf(0.4, 0.02, power_fade)
		var speeder_frac: float = lerpf(0.2, 0.02, power_fade)

		# Build a weighted pool so biased enemy types get extra count
		# Each entry: {path, base_fraction, bias_bonus}
		var pool_def: Array[Dictionary] = []
		pool_def.append({"path": "", "data": grunt_data,    "frac": grunt_frac,   "id": &"grunt"})
		pool_def.append({"path": "", "data": speeder_data,  "frac": speeder_frac, "id": &"speeder"})
		pool_def.append({"path": "", "data": exploder_data, "frac": 0.2,          "id": &"exploder"})
		if eff_tier >= 1:
			pool_def.append({"path": "res://resources/enemies/sniper.tres",       "data": null, "frac": 0.1, "id": &"sniper"})
			pool_def.append({"path": "res://resources/enemies/heavy_ranger.tres", "data": null, "frac": 0.1, "id": &"heavy_ranger"})
		if eff_tier >= 2:
			pool_def.append({"path": "res://resources/enemies/tracker.tres",    "data": null, "frac": 0.1, "id": &"tracker"})
			pool_def.append({"path": "res://resources/enemies/sentinel.tres",   "data": null, "frac": 0.1, "id": &"sentinel"})
			pool_def.append({"path": "res://resources/enemies/acid_ranger.tres","data": null, "frac": 0.1, "id": &"acid_ranger"})
		if eff_tier >= 3:
			pool_def.append({"path": "res://resources/enemies/brute.tres",      "data": null, "frac": 0.1, "id": &"brute"})
		if eff_tier >= 4:
			pool_def.append({"path": "res://resources/enemies/corruptor.tres",  "data": null, "frac": 0.1, "id": &"corruptor"})
		if eff_tier >= 6:
			pool_def.append({"path": "res://resources/enemies/ranger.tres",     "data": null, "frac": 0.1, "id": &"ranger"})

		# Compute total weight (base fraction + bias bonus)
		var total_weight: float = 0.0
		for e in pool_def:
			var w: float = e["frac"] + (bias.get(e["id"], 0.0) as float)
			total_weight += w

		# Distribute enemies proportionally by weight
		var assigned: int = 0
		for i in pool_def.size():
			var e: Dictionary = pool_def[i]
			var edata: EnemyData = e["data"]
			if edata == null:
				if ResourceLoader.exists(e["path"]):
					edata = ResourceLoader.load(e["path"])
				else:
					continue
			var w: float = e["frac"] + (bias.get(e["id"], 0.0) as float)
			var count: int = maxi(1, int(total_enemies * w / total_weight))
			wave.enemy_pool.append(edata)
			wave.enemy_counts.append(count)
			assigned += count

		# Remainder goes to last slot (highest-tier unlocked enemy)
		var leftover: int = total_enemies - assigned
		if leftover > 0 and wave.enemy_counts.size() > 0:
			wave.enemy_counts[wave.enemy_counts.size() - 1] += leftover

	return wave
