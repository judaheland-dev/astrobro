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

var _state: State = State.CHASE
var _contact_timer: float = 0.0
var _ranged_timer: float = 0.0
var _targets: Array[Node] = []
var _player_targets: Array[Node] = []
var _base_target: Node = null

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
	if enemy_data:
		_apply_data()
	current_health = max_health
	# Spawn scale-in: pop in from 0 to 1
	self.scale = Vector2.ZERO
	var spawn_tween := create_tween()
	spawn_tween.tween_property(self, "scale", Vector2.ONE * 1.2, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	spawn_tween.tween_property(self, "scale", Vector2.ONE, 0.08)
	_setup_enemy_thruster()

func _apply_data() -> void:
	max_health      = enemy_data.max_health
	current_health  = enemy_data.max_health
	move_speed      = enemy_data.move_speed
	contact_damage  = enemy_data.contact_damage
	contact_cooldown = enemy_data.contact_damage_cooldown
	armor           = enemy_data.armor
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

func take_damage(amount: float) -> void:
	if _state == State.DEAD:
		return
	var effective := maxf(0.0, amount - armor)
	current_health -= effective
	_flash_hit()
	if current_health <= 0.0:
		_die()

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
			AudioManager.play_sfx(enemy_data.death_sfx)

	# Exploder: AoE damage on death before the visual
	if enemy_data and enemy_data.ai_type == EnemyData.AIType.EXPLODER:
		var expl_sfx := "res://assets/audio/sfx_explosion.ogg"
		if ResourceLoader.exists(expl_sfx):
			AudioManager.play_sfx(load(expl_sfx), 0.0, randf_range(0.9, 1.1))
		_explode_aoe()

	died.emit(self)
	# Explosion: orange flash, spin outward, fade debris
	var tween := create_tween()
	tween.set_parallel(true)
	sprite.modulate = Color(3.0, 1.5, 0.2, 1.0)
	tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.0, 0.0), 0.35)
	tween.tween_property(self, "scale", Vector2(2.2, 2.2), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "rotation", sprite.rotation + 1.8, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Spawn debris sprites from meteorBrown
	_spawn_debris()
	tween.chain().tween_callback(queue_free)

func _spawn_debris() -> void:
	var debris_tex: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/meteorBrown_big1.png"):
		debris_tex = load("res://assets/sprites/meteorBrown_big1.png")
	for i in 4:
		var d := Sprite2D.new()
		if debris_tex:
			d.texture = debris_tex
			d.scale = Vector2.ONE * randf_range(0.12, 0.22)
		else:
			var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.9, 0.5, 0.1))
			d.texture = ImageTexture.create_from_image(img)
		d.modulate = Color(1.0, randf_range(0.4, 0.9), 0.1, 1.0)
		d.z_index = 5
		get_tree().current_scene.add_child(d)
		d.global_position = global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
		var angle := (TAU / 4.0) * i + randf_range(-0.4, 0.4)
		var dist := randf_range(30.0, 70.0)
		var target_pos := d.global_position + Vector2(cos(angle), sin(angle)) * dist
		var dt := create_tween()
		dt.set_parallel(true)
		dt.tween_property(d, "global_position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		dt.tween_property(d, "rotation", d.rotation + randf_range(-PI, PI), 0.4)
		dt.tween_property(d, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		dt.chain().tween_callback(d.queue_free)

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

	if _ranged_timer <= 0.0:
		_fire_at_target(target)
		_ranged_timer = RANGED_COOLDOWN

func _fire_at_target(target: Node) -> void:
	if GameManager.solar_flare_active:
		return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var proj := BaseProjectile.new()
	proj.collision_layer = 0
	proj.collision_mask  = 1   # hit players only

	var spr := Sprite2D.new()
	var laser_path := "res://assets/sprites/laserRed01.png"
	if ResourceLoader.exists(laser_path):
		spr.texture = load(laser_path)
		spr.rotation_degrees = 90.0
	else:
		var img := Image.create(12, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.2, 0.2))
		spr.texture = ImageTexture.create_from_image(img)
	proj.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10.0, 4.0)
	col.shape = shape
	proj.add_child(col)

	get_tree().current_scene.add_child(proj)
	proj.global_position = global_position
	proj.setup(dir, contact_damage * 0.6, 280.0, 700.0, 0)

	var sfx := "res://assets/audio/sfx_laser1.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -14.0, randf_range(0.75, 0.95))

func _explode_aoe() -> void:
	# Visual shockwave ring
	var ring := ColorRect.new()
	ring.color = Color(1.0, 0.5, 0.1, 0.55)
	ring.size = Vector2(EXPLODER_RADIUS * 2.0, EXPLODER_RADIUS * 2.0)
	ring.pivot_offset = ring.size * 0.5
	ring.position = global_position - ring.size * 0.5
	get_tree().current_scene.add_child(ring)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(2.0, 2.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.35)
	rt.chain().tween_callback(ring.queue_free)

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
