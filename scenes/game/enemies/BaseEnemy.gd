extends CharacterBody2D
class_name BaseEnemy

## BaseEnemy - loads EnemyData, handles state machine, damage, and death.

signal died(enemy: BaseEnemy)
signal xp_dropped(amount: int, world_pos: Vector2)
signal coin_dropped(amount: int, world_pos: Vector2)

enum State {
	CHASE,
	ATTACK,
	DEAD,
}

@export var enemy_data: EnemyData = null

var max_health: float = 30.0
var current_health: float = 30.0
var move_speed: float = 80.0
var contact_damage: float = 10.0
var contact_cooldown: float = 1.0
var armor: float = 0.0

# Rechargeable shield
var shield_max: float = 0.0
var current_shield: float = 0.0
var shield_regen_rate: float = 0.0
var shield_regen_delay: float = 4.0
var _shield_regen_timer: float = 0.0
var _shield_ring: Sprite2D = null

# Stun state
var _stun_timer: float = 0.0

# Knockback
var _knockback_velocity: Vector2 = Vector2.ZERO

func apply_knockback(impulse: Vector2) -> void:
	_knockback_velocity += impulse

var _state: State = State.CHASE
var _contact_timer: float = 0.0
var _ranged_timer: float = 0.0
var _targets: Array[Node] = []
var _player_targets: Array[Node] = []
var _base_target: Node = null

# Boss phase tracking
var _boss_phase: int = 1
var _phase_triggered: bool = false
var spawn_container: Node = null  # set by WaveManager for ELITE_SUMMONER

# Sentinel / summoner timers
var _sentinel_timer: float = 0.0
var _summon_timer: float = 0.0

const RANGED_COOLDOWN: float = 2.5
const RANGED_MIN_DIST: float = 220.0

var _e_thruster: Sprite2D = null
var _e_thruster_textures: Array = []
var _e_thruster_tick: float = 0.0
var _e_thruster_frame: int = 0
const _E_THRUSTER_FPS: float = 10.0
const RANGED_MAX_DIST: float = 370.0
const EXPLODER_RADIUS: float = 150.0

const PLAYER_PREFER_RADIUS: float = 350.0  # prefer player when within this distance
const ATTACK_RANGE: float = 52.0           # melee range for all targets

@onready var sprite: Sprite2D = $Sprite2D
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D

func _ready() -> void:
	add_to_group("enemies")
	if enemy_data:
		_apply_data()
	current_health = max_health
	# Spawn scale-in: pop in from 0 to 1
	self.scale = Vector2.ZERO
	var spawn_tween := create_tween()
	spawn_tween.tween_property(self, "scale", Vector2.ONE * 1.2, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	spawn_tween.tween_property(self, "scale", Vector2.ONE, 0.08)
	_setup_enemy_thruster()
	if shield_max > 0.0:
		_setup_shield_ring()

func _apply_data() -> void:
	max_health       = enemy_data.max_health
	current_health   = enemy_data.max_health
	move_speed       = enemy_data.move_speed
	contact_damage   = enemy_data.contact_damage
	contact_cooldown = enemy_data.contact_damage_cooldown
	armor            = enemy_data.armor
	shield_max         = enemy_data.shield_max
	shield_regen_rate  = enemy_data.shield_regen_rate
	shield_regen_delay = enemy_data.shield_regen_delay
	current_shield     = shield_max
	if enemy_data.sprite:
		sprite.texture = enemy_data.sprite
		sprite.scale   = enemy_data.sprite_scale

func register_targets(targets: Array[Node]) -> void:
	_targets = targets
	_player_targets.clear()
	_base_target = null
	for t in targets:
		if t is Player:
			_player_targets.append(t)
		else:
			_base_target = t

func scale_with_wave(wave_multiplier: float, speed_mult: float = 1.0) -> void:
	max_health     = max_health * wave_multiplier
	current_health = max_health
	contact_damage = contact_damage * wave_multiplier
	move_speed     = move_speed * speed_mult

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_update_enemy_thruster(delta)
	if _contact_timer > 0.0:
		_contact_timer -= delta

	# Shield regeneration
	if shield_max > 0.0:
		if _shield_regen_timer > 0.0:
			_shield_regen_timer -= delta
		elif current_shield < shield_max:
			current_shield = minf(current_shield + shield_regen_rate * delta, shield_max)
			_update_shield_ring()

	# Stun: skip all AI while stunned
	if _stun_timer > 0.0:
		_stun_timer -= delta
		velocity = Vector2.ZERO
		return

	# Knockback: override AI movement briefly while impulse decays
	if _knockback_velocity.length_squared() > 4.0:
		velocity = _knockback_velocity
		move_and_slide()
		_knockback_velocity = _knockback_velocity.lerp(Vector2.ZERO, delta * 10.0)
		return
	else:
		_knockback_velocity = Vector2.ZERO

	var target := _get_primary_target()
	if target == null:
		return

	# Non-player targets (base): use pure distance-based attack
	if not target is Player:
		var dist := global_position.distance_to(target.global_position)
		if dist <= ATTACK_RANGE:
			_attack_contact(target)
			return
		_chase(target, delta)
		return

	# Ranged AI: maintain distance and fire projectiles
	if enemy_data and enemy_data.ai_type == EnemyData.AIType.RANGED:
		_ranged_update(target, delta)
		return

	# Sentinel: stationary turret
	if enemy_data and enemy_data.ai_type == EnemyData.AIType.SENTINEL:
		_sentinel_update(delta)
		return

	# Boss types
	if enemy_data and enemy_data.ai_type in [
			EnemyData.AIType.ELITE, EnemyData.AIType.ELITE_RANGED,
			EnemyData.AIType.ELITE_SUMMONER, EnemyData.AIType.ELITE_PHASE]:
		_boss_update(target, delta)
		return

	match _state:
		State.CHASE:
			_chase(target, delta)
		State.ATTACK:
			_attack_contact(target)

func _get_primary_target() -> Node:
	# Prefer the nearest living player within PLAYER_PREFER_RADIUS
	var best_player: Node = null
	var best_dist_sq := PLAYER_PREFER_RADIUS * PLAYER_PREFER_RADIUS
	for t in _player_targets:
		if not is_instance_valid(t) or not t.is_physics_processing():
			continue
		var d := global_position.distance_squared_to(t.global_position)
		if d < best_dist_sq:
			best_dist_sq = d
			best_player = t
	if best_player != null:
		return best_player
	# No nearby player - attack the base objective
	if _base_target != null and is_instance_valid(_base_target):
		return _base_target
	# Fallback: nearest living player regardless of distance (wave survival / no base)
	var fallback: Node = null
	var fallback_d := INF
	for t in _player_targets:
		if not is_instance_valid(t) or not t.is_physics_processing():
			continue
		var d := global_position.distance_squared_to(t.global_position)
		if d < fallback_d:
			fallback_d = d
			fallback = t
	return fallback

func _chase(target: Node, _delta: float) -> void:
	nav_agent.target_position = target.global_position
	if nav_agent.is_navigation_finished():
		return
	var next_pos := nav_agent.get_next_path_position()
	var dir := (next_pos - global_position).normalized()
	velocity = dir * move_speed
	move_and_slide()

	# Rotate sprite to face direction of travel.
	# Kenney enemy PNGs face DOWN at rotation 0, so offset by -PI/2 to align nose with velocity.
	if velocity.length_squared() > 1.0:
		sprite.rotation = velocity.angle() - PI * 0.5

func _attack_contact(target: Node) -> void:
	if _contact_timer <= 0.0 and target.has_method("take_damage"):
		target.take_damage(contact_damage)
		_contact_timer = contact_cooldown

func take_damage(amount: float, armor_penetration: float = 0.0) -> void:
	if _state == State.DEAD:
		return
	_shield_regen_timer = shield_regen_delay  # reset regen delay on any hit
	if GameManager.ion_storm_active:
		amount *= 1.5
	var effective := maxf(0.0, amount - maxf(0.0, armor - armor_penetration))
	if current_shield > 0.0:
		var absorbed := minf(current_shield, effective)
		current_shield -= absorbed
		effective -= absorbed
		_update_shield_ring()
		if effective <= 0.0:
			_flash_shield_hit()
			return
	current_health -= effective
	_flash_hit()
	# Boss phase transition at 50% HP
	if not _phase_triggered and current_health / max_health < 0.5:
		_phase_triggered = true
		_boss_phase = 2
		_trigger_phase_2()
	if current_health <= 0.0:
		_die()

func stun(duration: float) -> void:
	## Temporarily halt this enemy's AI. Stacks by taking the longest duration.
	if duration > _stun_timer:
		_stun_timer = duration
	# Blue pulse visual to signal stun
	sprite.modulate = Color(0.4, 0.6, 1.0, 1.0)
	var t := create_tween()
	t.tween_property(sprite, "modulate", Color.WHITE, duration * 0.5)

func _setup_shield_ring() -> void:
	const RING_SIZE: int = 64
	var img := Image.create(RING_SIZE, RING_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(RING_SIZE * 0.5, RING_SIZE * 0.5)
	var outer := RING_SIZE * 0.5
	var inner := outer - 4.0
	for y in RING_SIZE:
		for x in RING_SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= outer and d >= inner:
				var edge := minf((d - inner) / 2.0, (outer - d) / 2.0)
				img.set_pixel(x, y, Color(0.2, 0.6, 1.0, clampf(edge, 0.0, 1.0)))
	_shield_ring = Sprite2D.new()
	_shield_ring.texture = ImageTexture.create_from_image(img)
	_shield_ring.scale = Vector2(1.4, 1.4)
	_shield_ring.z_index = 3
	add_child(_shield_ring)
	_update_shield_ring()

func _update_shield_ring() -> void:
	if _shield_ring == null:
		return
	if shield_max <= 0.0:
		_shield_ring.visible = false
		return
	var frac := current_shield / shield_max
	_shield_ring.visible = frac > 0.0
	_shield_ring.modulate = Color(0.2, 0.6, 1.0, frac)

func _flash_shield_hit() -> void:
	if _shield_ring == null:
		return
	var tween := create_tween()
	tween.tween_property(_shield_ring, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.04)
	tween.tween_property(_shield_ring, "modulate", Color(0.2, 0.6, 1.0, current_shield / shield_max), 0.15)

func _flash_hit() -> void:
	# White flash + quick scale punch
	var hit_sfx := "res://assets/audio/sfx_laser2.ogg"
	if ResourceLoader.exists(hit_sfx):
		AudioManager.play_sfx(load(hit_sfx), -10.0, randf_range(0.85, 1.15))
	sprite.modulate = Color(5.0, 5.0, 5.0, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
	tween.tween_property(self, "scale", Vector2.ONE * 1.15, 0.05).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_property(self, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_SINE)

func _die() -> void:
	_state = State.DEAD
	set_physics_process(false)

	if enemy_data:
		xp_dropped.emit(enemy_data.xp_drop, global_position)
		if randf() < enemy_data.coin_drop_chance:
			coin_dropped.emit(enemy_data.coin_drop_amount, global_position)
		if enemy_data.death_sfx:
			AudioManager.play_sfx(enemy_data.death_sfx, -6.0, randf_range(0.9, 1.1))

	# Exploder: AoE damage on death before the visual
	if enemy_data and enemy_data.ai_type == EnemyData.AIType.EXPLODER:
		var expl_sfx := "res://assets/audio/sfx_explosion.ogg"
		if ResourceLoader.exists(expl_sfx):
			AudioManager.play_sfx(load(expl_sfx), 0.0, randf_range(0.9, 1.1))
		_explode_aoe()

	died.emit(self)
	# Flash the sprite overbright briefly, spawn explosion, then free the enemy node
	sprite.modulate = Color(3.0, 2.0, 0.5, 1.0)
	# Spawn debris immediately so it flies from the current position
	_spawn_debris()
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.12)
	tween.tween_callback(_spawn_explosion)
	tween.tween_interval(0.05)
	tween.tween_callback(queue_free)

func _spawn_explosion() -> void:
	var exp := Sprite2D.new()
	exp.z_index = 8
	var frames := [
		"res://assets/particles/explosion00.png",
		"res://assets/particles/explosion01.png",
		"res://assets/particles/explosion02.png",
		"res://assets/particles/explosion03.png",
		"res://assets/particles/explosion04.png",
	]
	var path: String = frames[randi() % frames.size()]
	if not ResourceLoader.exists(path):
		return
	exp.texture = load(path)
	exp.scale = Vector2(0.05, 0.05)
	var parent := get_tree().current_scene
	parent.add_child(exp)
	exp.global_position = global_position
	var t := exp.create_tween()
	t.set_parallel(true)
	t.tween_property(exp, "scale", Vector2(0.18, 0.18), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(exp, "modulate:a", 0.0, 0.4).set_delay(0.12)
	t.chain().tween_callback(exp.queue_free)

func _spawn_debris() -> void:
	var shard_paths := [
		"res://assets/particles/spaceParts_050.png",
		"res://assets/particles/spaceParts_001.png",
	]
	var num_pieces := 5
	for i in num_pieces:
		var d := Sprite2D.new()
		var tex_path: String = shard_paths[i % shard_paths.size()]
		if ResourceLoader.exists(tex_path):
			d.texture = load(tex_path)
			d.scale = Vector2.ONE * randf_range(0.18, 0.32)
		else:
			var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.6, 0.6, 0.7))
			d.texture = ImageTexture.create_from_image(img)
		# Tint shards with a slight orange-grey scorched look
		d.modulate = Color(randf_range(0.7, 1.0), randf_range(0.4, 0.7), 0.2, 1.0)
		d.z_index = 5
		var scene_root := get_tree().current_scene
		scene_root.add_child(d)
		d.global_position = global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
		var angle := (TAU / num_pieces) * i + randf_range(-0.5, 0.5)
		var dist := randf_range(35.0, 75.0)
		var target_pos := d.global_position + Vector2(cos(angle), sin(angle)) * dist
		var dt := d.create_tween()
		dt.set_parallel(true)
		dt.tween_property(d, "global_position", target_pos, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		dt.tween_property(d, "rotation", d.rotation + randf_range(-PI, PI), 0.45)
		# Hold for 2s then fade out over 0.5s
		var fade := d.create_tween()
		fade.tween_interval(2.0)
		fade.tween_property(d, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fade.tween_callback(d.queue_free)

func _ranged_update(target: Node, delta: float) -> void:
	if _ranged_timer > 0.0:
		_ranged_timer -= delta

	var dist := global_position.distance_to(target.global_position)
	var dir: Vector2 = (target.global_position - global_position).normalized()

	if dist < RANGED_MIN_DIST:
		# Too close - back away directly
		velocity = -dir * move_speed
		move_and_slide()
	elif dist > RANGED_MAX_DIST:
		# Too far - close in via nav
		nav_agent.target_position = target.global_position
		if not nav_agent.is_navigation_finished():
			var next_pos := nav_agent.get_next_path_position()
			velocity = (next_pos - global_position).normalized() * move_speed
			move_and_slide()
	else:
		velocity = Vector2.ZERO

	# Always face the target
	if dir != Vector2.ZERO:
		sprite.rotation = dir.angle() - PI * 0.5

	var cooldown := RANGED_COOLDOWN
	if enemy_data and enemy_data.ranged_attack:
		cooldown = enemy_data.ranged_attack.fire_cooldown
	if _ranged_timer <= 0.0:
		_fire_at_target(target)
		_ranged_timer = cooldown

func _sentinel_update(delta: float) -> void:
	_sentinel_timer -= delta
	velocity = Vector2.ZERO
	# Slowly rotate sprite
	sprite.rotation += delta * 0.8
	var cooldown := RANGED_COOLDOWN
	if enemy_data and enemy_data.ranged_attack:
		cooldown = enemy_data.ranged_attack.fire_cooldown
	if _sentinel_timer <= 0.0:
		_sentinel_timer = cooldown
		_fire_rotating_volley()

func _boss_update(target: Node, delta: float) -> void:
	if _ranged_timer > 0.0:
		_ranged_timer -= delta
	if _summon_timer > 0.0:
		_summon_timer -= delta

	match enemy_data.ai_type:
		EnemyData.AIType.ELITE:
			# Phase 1: chase + fire single shots every 3s
			# Phase 2 (speed already boosted in _trigger_phase_2): fire burst-3
			_chase(target, delta)
			var fire_cd := 3.0 if _boss_phase == 1 else 2.0
			if _ranged_timer <= 0.0:
				_ranged_timer = fire_cd
				if _boss_phase == 1:
					_fire_single(target)
				else:
					_fire_burst(target, 3, 0.12)
		EnemyData.AIType.ELITE_RANGED:
			# Phase 1: kite + fire spread burst
			# Phase 2: kite + fire homing acid shot
			_ranged_update(target, delta)
		EnemyData.AIType.ELITE_SUMMONER:
			# Chase slowly, periodically summon minions
			_chase(target, delta)
			if _summon_timer <= 0.0:
				_summon_timer = 8.0 if _boss_phase == 1 else 5.0
				_summon_minions(_boss_phase == 1)
			if _boss_phase == 2 and _ranged_timer <= 0.0:
				_ranged_timer = 2.5
				_fire_rotating_volley()
		EnemyData.AIType.ELITE_PHASE:
			# Phase 1: very slow chase, big contact damage
			# Phase 2: fast + fire homing darts
			_chase(target, delta)
			if _boss_phase == 2 and _ranged_timer <= 0.0:
				_ranged_timer = 1.8
				_fire_homing_dart(target)

func _trigger_phase_2() -> void:
	# Visual: overbright white flash + scale pop
	sprite.modulate = Color(5.0, 5.0, 5.0, 1.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	t.tween_property(self, "scale", Vector2.ONE * 1.5, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(self, "scale", Vector2.ONE, 0.12)

	if not enemy_data:
		return
	match enemy_data.ai_type:
		EnemyData.AIType.ELITE:
			move_speed *= 1.4
		EnemyData.AIType.ELITE_PHASE:
			move_speed = 150.0

	# Switch ELITE_RANGED to homing acid fire mode by swapping ranged_attack at runtime
	if enemy_data.ai_type == EnemyData.AIType.ELITE_RANGED:
		var acid := RangedAttackData.new()
		acid.fire_mode = RangedAttackData.FireMode.SINGLE
		acid.fire_cooldown = 2.0
		acid.projectile_speed = 220.0
		acid.damage_multiplier = 0.7
		acid.homing_strength = 2.2
		acid.homing_lifetime = 2.0
		acid.on_hit_slow_factor = 0.45
		acid.on_hit_slow_duration = 2.5
		acid.on_hit_dot_dps = 5.0
		acid.on_hit_dot_ticks = 6
		enemy_data = enemy_data.duplicate()
		enemy_data.ranged_attack = acid

func _summon_minions(use_basic: bool) -> void:
	var container := spawn_container if is_instance_valid(spawn_container) else get_tree().current_scene
	var data_path := "res://resources/enemies/grunt.tres" if use_basic else "res://resources/enemies/exploder.tres"
	var speeder_path := "res://resources/enemies/speeder.tres"
	if not ResourceLoader.exists(data_path):
		return
	var summon_data: EnemyData = ResourceLoader.load(data_path)
	var count := 3 if use_basic else 2
	for i in count:
		var minion := BaseEnemy.new()
		minion.collision_layer = 2
		minion.collision_mask  = 6   # enemies + walls; player contact via Area2D
		var mspr := Sprite2D.new()
		mspr.name = "Sprite2D"
		var stex_path := "res://assets/sprites/enemyRed1.png" if use_basic else "res://assets/sprites/enemyGreen1.png"
		if ResourceLoader.exists(stex_path):
			mspr.texture = load(stex_path)
		minion.add_child(mspr)
		var mcol := CollisionShape2D.new()
		mcol.name = "CollisionShape2D"
		var mshape := CircleShape2D.new()
		mshape.radius = 12.0
		mcol.shape = mshape
		minion.add_child(mcol)
		var mnav := NavigationAgent2D.new()
		mnav.name = "NavigationAgent2D"
		mnav.path_desired_distance = 8.0
		mnav.target_desired_distance = 16.0
		minion.add_child(mnav)
		var marea := Area2D.new()
		marea.collision_layer = 0
		marea.collision_mask  = 1
		marea.name = "ContactArea"
		var marea_col := CollisionShape2D.new()
		var marea_shape := CircleShape2D.new()
		marea_shape.radius = 14.0
		marea_col.shape = marea_shape
		marea.add_child(marea_col)
		minion.add_child(marea)
		minion.enemy_data = summon_data
		container.add_child(minion)
		marea.body_entered.connect(minion._on_body_entered)
		marea.body_exited.connect(minion._on_body_exited)
		minion.register_targets(_targets)
		var angle := (TAU / count) * i
		minion.global_position = global_position + Vector2(cos(angle), sin(angle)) * 60.0
		# Summoned minions do NOT connect died signal to WaveManager - wave clears by boss death

func _fire_at_target(target: Node) -> void:
	if GameManager.solar_flare_intensity >= 2.0:
		return
	if not enemy_data or not enemy_data.ranged_attack:
		# Legacy fallback: single straight laser
		_fire_single(target)
		return
	var ra: RangedAttackData = enemy_data.ranged_attack
	match ra.fire_mode:
		RangedAttackData.FireMode.SINGLE:
			_fire_single(target, ra)
		RangedAttackData.FireMode.SPREAD:
			_fire_spread(target, ra)
		RangedAttackData.FireMode.ROTATING_VOLLEY:
			_fire_rotating_volley(ra)
		RangedAttackData.FireMode.BURST_3:
			_fire_burst(target, 3, ra.burst_interval, ra)

func _build_projectile(spr_path: String, color_fallback: Color) -> BaseProjectile:
	var proj := BaseProjectile.new()
	proj.is_enemy_projectile = true
	if enemy_data and enemy_data.fires_interceptable_missiles:
		proj.interceptable = true
		proj.collision_layer = 8   # layer 4 (bit 3) - interceptable enemy projectiles
	else:
		proj.collision_layer = 0
	proj.collision_mask  = 1
	var spr := Sprite2D.new()
	if ResourceLoader.exists(spr_path):
		spr.texture = load(spr_path)
		spr.rotation_degrees = 90.0
	else:
		var img := Image.create(12, 4, false, Image.FORMAT_RGBA8)
		img.fill(color_fallback)
		spr.texture = ImageTexture.create_from_image(img)
	proj.add_child(spr)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10.0, 4.0)
	col.shape = shape
	proj.add_child(col)
	return proj

func _launch_projectile(proj: BaseProjectile, dir: Vector2, dmg: float, spd: float, rng: float) -> void:
	get_tree().current_scene.add_child(proj)
	proj.global_position = global_position
	proj.setup(dir, dmg, spd, rng, 0)
	proj.register_targets(_player_targets)

func _fire_sfx() -> void:
	var sfx := "res://assets/audio/sfx_laser1.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -14.0, randf_range(0.75, 0.95))

func _apply_ranged_attack_fields(proj: BaseProjectile, ra: RangedAttackData) -> void:
	proj.homing_strength = ra.homing_strength
	proj.homing_lifetime = ra.homing_lifetime
	proj.on_hit_slow_factor = ra.on_hit_slow_factor
	proj.on_hit_slow_duration = ra.on_hit_slow_duration
	proj.on_hit_dot_dps = ra.on_hit_dot_dps
	proj.on_hit_dot_ticks = ra.on_hit_dot_ticks

func _fire_single(target: Node, ra: RangedAttackData = null) -> void:
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var spr_path := "res://assets/sprites/laserRed01.png"
	var spd := 280.0
	var dmg_mult := 0.6
	var rng := 700.0
	if ra:
		spr_path = "res://assets/sprites/laserGreen11.png" if ra.on_hit_dot_dps > 0.0 else spr_path
		spr_path = "res://assets/sprites/laserBlue01.png" if ra.on_hit_slow_factor > 0.0 else spr_path
		spd = ra.projectile_speed
		dmg_mult = ra.damage_multiplier
	var proj := _build_projectile(spr_path, Color(1.0, 0.2, 0.2))
	if ra:
		_apply_ranged_attack_fields(proj, ra)
	_launch_projectile(proj, dir, contact_damage * dmg_mult, spd, rng)
	_fire_sfx()

func _fire_spread(target: Node, ra: RangedAttackData) -> void:
	var base_dir: Vector2 = (target.global_position - global_position).normalized()
	var count := maxi(ra.projectile_count, 2)
	var total_rad := deg_to_rad(ra.spread_angle_deg)
	var step := total_rad / float(count - 1) if count > 1 else 0.0
	var spr_path := "res://assets/sprites/laserBlue01.png" if ra.on_hit_slow_factor > 0.0 else "res://assets/sprites/laserRed01.png"
	spr_path = "res://assets/sprites/laserGreen11.png" if ra.on_hit_dot_dps > 0.0 else spr_path
	for i in count:
		var angle_offset := -total_rad * 0.5 + step * float(i)
		var dir := base_dir.rotated(angle_offset)
		var proj := _build_projectile(spr_path, Color(1.0, 0.3, 0.3))
		_apply_ranged_attack_fields(proj, ra)
		_launch_projectile(proj, dir, contact_damage * ra.damage_multiplier, ra.projectile_speed, 700.0)
	_fire_sfx()

func _fire_rotating_volley(ra: RangedAttackData = null) -> void:
	var count := 4
	for i in count:
		var dir := Vector2(cos(TAU / count * i), sin(TAU / count * i))
		var spd := 260.0 if ra == null else ra.projectile_speed
		var dmg := contact_damage * 0.5
		var proj := _build_projectile("res://assets/sprites/laserRed01.png", Color(1.0, 0.2, 0.2))
		if ra:
			_apply_ranged_attack_fields(proj, ra)
		_launch_projectile(proj, dir, dmg, spd, 800.0)
	_fire_sfx()

func _fire_homing_dart(target: Node) -> void:
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var proj := _build_projectile("res://assets/sprites/laserBlue01.png", Color(0.3, 0.3, 1.0))
	proj.homing_strength = 2.5
	proj.homing_lifetime = 1.8
	_launch_projectile(proj, dir, contact_damage * 0.5, 340.0, 900.0)
	_fire_sfx()

func _fire_burst(target: Node, count: int, interval: float, ra: RangedAttackData = null) -> void:
	# Fire the first shot immediately, schedule the rest
	if not is_inside_tree():
		return
	if ra:
		_fire_single(target, ra)
	else:
		_fire_single(target)
	for i in count - 1:
		var t := get_tree().create_timer(interval * (i + 1))
		t.timeout.connect(func():
			if is_inside_tree() and _state != State.DEAD:
				if ra:
					_fire_single(_get_primary_target() if _get_primary_target() else target, ra)
				else:
					_fire_single(_get_primary_target() if _get_primary_target() else target)
		)

func _explode_aoe() -> void:
	# Visual explosion sprite
	var exp := Sprite2D.new()
	exp.z_index = 8
	var exp_path := "res://assets/particles/explosion02.png"
	if ResourceLoader.exists(exp_path):
		exp.texture = load(exp_path)
	exp.scale = Vector2(0.1, 0.1)
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	var rt := exp.create_tween()
	rt.set_parallel(true)
	rt.tween_property(exp, "scale", Vector2(0.52, 0.52), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(exp, "modulate:a", 0.0, 0.55).set_delay(0.12)
	rt.chain().tween_callback(exp.queue_free)

	# AoE damage to all players in radius
	for t in _player_targets:
		if not is_instance_valid(t):
			continue
		if global_position.distance_to(t.global_position) <= EXPLODER_RADIUS:
			if t.has_method("take_damage"):
				t.take_damage(contact_damage * 4.0)

func _on_body_entered(body: Node) -> void:
	if body is Player:
		_state = State.ATTACK
		_attack_contact(body)

func _on_body_exited(body: Node) -> void:
	if body is Player and _state == State.ATTACK:
		_state = State.CHASE

func _setup_enemy_thruster() -> void:
	for i in 7:
		var p := "res://assets/sprites/fire%02d.png" % i
		_e_thruster_textures.append(load(p) if ResourceLoader.exists(p) else null)
	_e_thruster = Sprite2D.new()
	_e_thruster.position = Vector2(0.0, -38.0)
	_e_thruster.rotation_degrees = 0.0
	_e_thruster.scale = Vector2(0.35, 0.35)
	_e_thruster.z_index = -1
	_e_thruster.visible = false
	sprite.add_child(_e_thruster)
	if _e_thruster_textures.size() > 0 and _e_thruster_textures[0] != null:
		_e_thruster.texture = _e_thruster_textures[0]

func _update_enemy_thruster(delta: float) -> void:
	if _e_thruster == null:
		return
	var moving := velocity.length_squared() > 1.0
	_e_thruster.visible = moving
	if not moving:
		return
	_e_thruster_tick += delta
	if _e_thruster_tick < 1.0 / _E_THRUSTER_FPS:
		return
	_e_thruster_tick -= 1.0 / _E_THRUSTER_FPS
	_e_thruster_frame = (_e_thruster_frame + 1) % 7
	var tex = _e_thruster_textures[_e_thruster_frame] if _e_thruster_textures.size() > _e_thruster_frame else null
	if tex != null:
		_e_thruster.texture = tex
