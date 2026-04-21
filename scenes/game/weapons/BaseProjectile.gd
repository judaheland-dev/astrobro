extends Area2D
class_name BaseProjectile

## BaseProjectile - moves in a direction, deals damage on hit, expires by range.

var direction: Vector2 = Vector2.RIGHT
var speed: float = 400.0
var damage: float = 10.0
var max_range: float = 600.0
var piercing: int = 0
var aoe_radius: float = 0.0
var shooter: Node = null
var emit_exhaust_trail: bool = false
var projectile_color: Color = Color(1.0, 1.0, 0.6)

# Homing toward players (used by enemy projectiles)
var homing_strength: float = 0.0   # turn rate toward nearest player (rad/s); 0 = disabled
var homing_lifetime: float = 0.0   # seconds before homing disengages; 0 = never
var _homing_elapsed: float = 0.0
var _homing_players: Array[Node] = []

# Homing toward enemies (used by player homing missiles)
var enemy_homing_strength: float = 0.0  # turn rate toward nearest enemy (rad/s); 0 = disabled
var _enemy_homing_elapsed: float = 0.0

# Interception flags
var is_enemy_projectile: bool = false  # true for all enemy-fired projectiles
var interceptable: bool = false        # true for missiles that players can shoot down

# On-hit status effects (applied to targets that have apply_slow / apply_dot)
var on_hit_slow_factor: float = 0.0
var on_hit_slow_duration: float = 2.0
var on_hit_dot_dps: float = 0.0
var on_hit_dot_ticks: int = 6

var _distance_traveled: float = 0.0
var _hit_entities: Array[Node] = []   # track already-hit to avoid double damage
var _exhaust_timer: float = 0.0
const _EXHAUST_PUFF_PATHS: Array[String] = [
	"res://assets/particles/whitePuff00.png",
	"res://assets/particles/whitePuff01.png",
	"res://assets/particles/whitePuff02.png",
	"res://assets/particles/whitePuff03.png",
	"res://assets/particles/whitePuff04.png",
	"res://assets/particles/whitePuff05.png",
]

func setup(dir: Vector2, dmg: float, spd: float, rng: float, pierce: int) -> void:
	direction = dir.normalized()
	damage = dmg
	speed = spd
	max_range = rng
	piercing = pierce
	rotation = dir.angle()

func register_targets(players: Array[Node]) -> void:
	_homing_players = players

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	# Spawn a small light-trail sprite that fades behind the projectile
	var trail := Sprite2D.new()
	trail.name = "Trail"
	var img := Image.create(12, 4, false, Image.FORMAT_RGBA8)
	for x in 12:
		var a := 1.0 - float(x) / 12.0
		for y in 4:
			img.set_pixel(x, y, Color(1.0, 1.0, 0.6, a * 0.7))
	trail.texture = ImageTexture.create_from_image(img)
	trail.position = Vector2(-10.0, 0.0)  # behind the projectile nose
	add_child(trail)

func _physics_process(delta: float) -> void:
	# Homing steering toward players (enemy projectiles)
	if homing_strength > 0.0:
		var active := homing_lifetime <= 0.0 or _homing_elapsed < homing_lifetime
		if active:
			_homing_elapsed += delta
			var nearest: Node = null
			var nearest_d := INF
			for p in _homing_players:
				if not is_instance_valid(p) or not p.is_physics_processing():
					continue
				var d := global_position.distance_squared_to(p.global_position)
				if d < nearest_d:
					nearest_d = d
					nearest = p
			if nearest != null:
				var desired: Vector2 = (nearest.global_position - global_position).normalized()
				direction = direction.rotated(
					clampf(direction.angle_to(desired), -homing_strength * delta, homing_strength * delta)
				)
				rotation = direction.angle()
	# Homing steering toward enemies (player homing missiles)
	if enemy_homing_strength > 0.0:
		_enemy_homing_elapsed += delta
		var nearest_enemy: Node = null
		var nearest_d := INF
		for e in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(e) or not e.is_physics_processing():
				continue
			var d := global_position.distance_squared_to(e.global_position)
			if d < nearest_d:
				nearest_d = d
				nearest_enemy = e
		if nearest_enemy != null:
			var desired: Vector2 = (nearest_enemy.global_position - global_position).normalized()
			direction = direction.rotated(
				clampf(direction.angle_to(desired), -enemy_homing_strength * delta, enemy_homing_strength * delta)
			)
			rotation = direction.angle()
	var move := direction * speed * delta
	global_position += move
	_distance_traveled += move.length()
	if emit_exhaust_trail:
		_exhaust_timer -= delta
		if _exhaust_timer <= 0.0:
			_exhaust_timer = 0.06
			_spawn_exhaust_puff()
	if _distance_traveled >= max_range:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body in _hit_entities:
		return
	_hit_entities.append(body)

	if body.has_method("take_damage"):
		# Crit check (player shooter only)
		var actual_damage := damage
		var is_crit := false
		if shooter != null and "crit_chance" in shooter and shooter.crit_chance > 0.0:
			if randf() < shooter.crit_chance:
				actual_damage *= shooter.crit_multiplier
				is_crit = true
		body.take_damage(actual_damage)
		_spawn_impact_flash()
		if shooter != null and "lifesteal" in shooter and shooter.lifesteal > 0.0:
			if shooter.has_method("heal"):
				shooter.heal(actual_damage * shooter.lifesteal)
		# EMP pulse on crit
		if is_crit and shooter != null and "emp_radius" in shooter and shooter.emp_radius > 0.0:
			_emp_pulse(shooter.emp_radius)
		# Status effects
		if on_hit_slow_factor > 0.0 and body.has_method("apply_slow"):
			body.apply_slow(on_hit_slow_factor, on_hit_slow_duration)
		if on_hit_dot_dps > 0.0 and body.has_method("apply_dot"):
			body.apply_dot(on_hit_dot_dps, on_hit_dot_ticks)

func _on_area_entered(area: Area2D) -> void:
	## Intercept enemy missiles: destroy both this projectile and the incoming missile.
	if is_enemy_projectile:
		return  # enemy projectiles don't intercept each other
	if not (area is BaseProjectile):
		return
	var incoming := area as BaseProjectile
	if not incoming.interceptable:
		return
	# Both projectiles annihilate
	_spawn_intercept_flash(global_position.lerp(incoming.global_position, 0.5))
	# Reflective shield: fire back toward the missile's origin
	if shooter != null and "reflective_shield" in shooter and shooter.reflective_shield:
		var reflect_dir: Vector2 = -incoming.direction
		var reflect_proj := BaseProjectile.new()
		reflect_proj.collision_layer = 0
		reflect_proj.collision_mask = 2
		var spr := Sprite2D.new()
		var img := Image.create(10, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.8, 1.0))
		spr.texture = ImageTexture.create_from_image(img)
		reflect_proj.add_child(spr)
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(10.0, 4.0)
		col.shape = shape
		reflect_proj.add_child(col)
		reflect_proj.shooter = shooter
		get_tree().current_scene.add_child(reflect_proj)
		reflect_proj.global_position = global_position
		reflect_proj.setup(reflect_dir, incoming.damage, 500.0, 800.0, 0)
	incoming.queue_free()
	queue_free()

func _emp_pulse(radius: float) -> void:
	## Stun all enemies in radius and show a blue ring.
	# Visual ring
	var ring := Sprite2D.new()
	ring.z_index = 9
	const RING_SIZE: int = 128
	var img := Image.create(RING_SIZE, RING_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(RING_SIZE * 0.5, RING_SIZE * 0.5)
	var outer := RING_SIZE * 0.5
	var inner := outer - 6.0
	for y in RING_SIZE:
		for x in RING_SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= outer and d >= inner:
				img.set_pixel(x, y, Color(0.3, 0.7, 1.0, 0.9))
	ring.texture = ImageTexture.create_from_image(img)
	var pixel_radius := radius * 2.0 / RING_SIZE
	ring.scale = Vector2(pixel_radius, pixel_radius)
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	var t := ring.create_tween()
	t.set_parallel(true)
	t.tween_property(ring, "scale", Vector2(pixel_radius * 1.5, pixel_radius * 1.5), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.4)
	t.chain().tween_callback(ring.queue_free)
	# Damage query
	var space := get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	params.shape = shape
	params.transform = Transform2D(0.0, global_position)
	params.collision_mask = 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var results := space.intersect_shape(params, 32)
	for result in results:
		var body: Node = result["collider"]
		if body.has_method("stun"):
			body.stun(1.5)

func _spawn_intercept_flash(pos: Vector2) -> void:
	var flash := Sprite2D.new()
	flash.z_index = 10
	var flash_path := "res://assets/sprites/flash00.png"
	if ResourceLoader.exists(flash_path):
		flash.texture = load(flash_path)
	else:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.8, 0.9, 1.0, 1.0))
		flash.texture = ImageTexture.create_from_image(img)
	flash.scale = Vector2(0.08, 0.08)
	flash.modulate = Color(0.5, 0.9, 1.0)
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector2(0.15, 0.15), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(flash, "modulate:a", 0.0, 0.12)
	t.chain().tween_callback(flash.queue_free)
	var sfx_path := "res://assets/audio/sfx_laser2.ogg"
	if ResourceLoader.exists(sfx_path):
		AudioManager.play_sfx(load(sfx_path), -6.0, 1.4)

	if aoe_radius > 0.0:
		_explode_aoe()
		queue_free()
		return

	if piercing <= 0:
		queue_free()
	else:
		piercing -= 1

func _explode_aoe() -> void:
	# Explosion sprite visual
	var exp := Sprite2D.new()
	exp.z_index = 8
	var exp_path := "res://assets/particles/explosion01.png"
	if ResourceLoader.exists(exp_path):
		exp.texture = load(exp_path)
	exp.scale = Vector2(0.08, 0.08)
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	var rt := exp.create_tween()
	rt.set_parallel(true)
	rt.tween_property(exp, "scale", Vector2(0.42, 0.42), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(exp, "modulate:a", 0.0, 0.5).set_delay(0.1)
	rt.chain().tween_callback(exp.queue_free)

	# Damage all enemies in radius via physics shape query
	var space := get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = aoe_radius
	params.shape = shape
	params.transform = Transform2D(0.0, global_position)
	params.collision_mask = 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var results := space.intersect_shape(params, 32)
	var already_damaged: Array[Node] = []
	for result in results:
		var body: Node = result["collider"]
		if body in already_damaged or body in _hit_entities:
			continue
		already_damaged.append(body)
		if body.has_method("take_damage"):
			body.take_damage(damage)
			if shooter != null and "lifesteal" in shooter and shooter.lifesteal > 0.0:
				if shooter.has_method("heal"):
					shooter.heal(damage * shooter.lifesteal)

	# Explosion SFX
	var sfx_path := "res://assets/audio/sfx_explosion.ogg"
	if ResourceLoader.exists(sfx_path):
		AudioManager.play_sfx(load(sfx_path), 0.0, randf_range(0.9, 1.1))

func _spawn_exhaust_puff() -> void:
	var puff := Sprite2D.new()
	var path := _EXHAUST_PUFF_PATHS[randi() % _EXHAUST_PUFF_PATHS.size()]
	if ResourceLoader.exists(path):
		puff.texture = load(path)
	else:
		return
	puff.scale = Vector2(0.05, 0.05)
	puff.modulate = Color(0.85, 0.85, 0.85, 0.65)
	puff.z_index = -1
	# Spawn slightly behind and offset from travel direction
	var behind := -direction * 10.0 + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0))
	var parent := get_tree().current_scene
	parent.add_child(puff)
	puff.global_position = global_position + behind
	var t := puff.create_tween()
	t.set_parallel(true)
	t.tween_property(puff, "scale", Vector2(0.09, 0.09), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(puff, "modulate:a", 0.0, 0.35)
	t.chain().tween_callback(puff.queue_free)

func _spawn_impact_flash() -> void:
	var flash := Sprite2D.new()
	flash.z_index = 10
	var flash_path := "res://assets/sprites/flash00.png"
	if ResourceLoader.exists(flash_path):
		flash.texture = load(flash_path)
	else:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.9, 0.3, 1.0))
		flash.texture = ImageTexture.create_from_image(img)
	flash.scale = Vector2(0.03, 0.03)
	flash.modulate = projectile_color
	var parent := get_tree().current_scene
	parent.add_child(flash)
	flash.global_position = global_position
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector2(0.10, 0.10), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(flash, "modulate:a", 0.0, 0.12)
	t.chain().tween_callback(flash.queue_free)
