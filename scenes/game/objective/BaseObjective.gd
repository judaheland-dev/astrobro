extends Node2D
class_name BaseObjective

## BaseObjective - the base/structure players defend in Horde Defense mode.
## All visuals and collision are built in _ready(); no editor wiring needed.

signal health_changed(current: float, maximum: float)
signal destroyed()
signal took_damage()

@export var max_health: float = 500.0

var current_health: float = 500.0
var _sprite_core: Sprite2D
var _sprite_ring: Sprite2D
var _health_bar: ProgressBar
var _shield_pulse_tween: Tween
var _visual_pivot: Node2D

var _patrol_target: Vector2 = Vector2.ZERO
const PATROL_SPEED: float = 45.0
const PATROL_WAYPOINT_RADIUS: float = 32.0
const PATROL_HALF_W: float = 800.0
const PATROL_HALF_H: float = 480.0

func _ready() -> void:
	current_health = max_health
	_build_collision()
	_build_visuals()
	_build_health_bar()

	# Spawn pop-in animation
	scale = Vector2.ZERO
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE * 1.2, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, 0.1)

	_start_shield_pulse()
	_pick_new_waypoint()
	health_changed.emit(current_health, max_health)

func _build_collision() -> void:
	# StaticBody2D child on layer 1 so enemies physically stop at the base
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 30.0
	col.shape = shape
	body.add_child(col)
	add_child(body)

func _build_visuals() -> void:
	# All rotating visuals live under a pivot so the health bar (added later) stays upright
	_visual_pivot = Node2D.new()
	_visual_pivot.name = "VisualPivot"
	add_child(_visual_pivot)

	# Shield ring drawn procedurally (outer cyan glow)
	_sprite_ring = Sprite2D.new()
	_sprite_ring.name = "SpriteRing"
	var ring_img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	var cx := 48.0
	var cy := 48.0
	for y in 96:
		for x in 96:
			var d := Vector2(float(x), float(y)).distance_to(Vector2(cx, cy))
			if d >= 37.0 and d <= 47.0:
				var alpha := (1.0 - absf(d - 42.0) / 5.0) * 0.7
				ring_img.set_pixel(x, y, Color(0.2, 0.85, 1.0, alpha))
	_sprite_ring.texture = ImageTexture.create_from_image(ring_img)
	_sprite_ring.z_index = -1
	_visual_pivot.add_child(_sprite_ring)

	# Core: player ship sprite with golden tint to distinguish from players
	_sprite_core = Sprite2D.new()
	_sprite_core.name = "Sprite2D"
	var core_path := "res://assets/sprites/playerShip1_blue.png"
	if ResourceLoader.exists(core_path):
		_sprite_core.texture = load(core_path)
		_sprite_core.modulate = Color(1.3, 1.0, 0.25, 1.0)
		_sprite_core.scale = Vector2(1.5, 1.5)
	else:
		var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.8, 0.1))
		_sprite_core.texture = ImageTexture.create_from_image(img)
	_visual_pivot.add_child(_sprite_core)

	# 4 turrets at cardinal positions
	var turret_img := Image.create(10, 18, false, Image.FORMAT_RGBA8)
	turret_img.fill(Color(0.3, 0.9, 0.5))
	var turret_tex := ImageTexture.create_from_image(turret_img)
	var offsets := [Vector2(0.0, -46.0), Vector2(0.0, 46.0), Vector2(-46.0, 0.0), Vector2(46.0, 0.0)]
	for i in 4:
		var turret := Sprite2D.new()
		turret.texture = turret_tex
		turret.position = offsets[i]
		if i >= 2:
			turret.rotation_degrees = 90.0
		_visual_pivot.add_child(turret)

func _build_health_bar() -> void:
	_health_bar = ProgressBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.custom_minimum_size = Vector2(90.0, 12.0)
	_health_bar.position = Vector2(-45.0, -62.0)
	_health_bar.max_value = max_health
	_health_bar.value = current_health
	_health_bar.show_percentage = false
	add_child(_health_bar)

func _process(delta: float) -> void:
	_move_patrol(delta)

func _move_patrol(delta: float) -> void:
	var to_target := _patrol_target - global_position
	if to_target.length() < PATROL_WAYPOINT_RADIUS:
		_pick_new_waypoint()
		return
	var dir := to_target.normalized()
	global_position += dir * PATROL_SPEED * delta
	# Rotate pivot to face movement direction.
	# Kenney player ships face Up (-Y) at rotation=0, so offset by +PI/2 to align nose with dir.
	if _visual_pivot:
		var target_rot := dir.angle() + PI * 0.5
		_visual_pivot.rotation = lerp_angle(_visual_pivot.rotation, target_rot, delta * 2.5)

func _pick_new_waypoint() -> void:
	_patrol_target = Vector2(
		randf_range(-PATROL_HALF_W, PATROL_HALF_W),
		randf_range(-PATROL_HALF_H, PATROL_HALF_H)
	)

func _start_shield_pulse() -> void:
	_shield_pulse_tween = create_tween()
	_shield_pulse_tween.set_loops()
	_shield_pulse_tween.tween_property(_sprite_ring, "modulate:a", 0.4, 1.2).set_trans(Tween.TRANS_SINE)
	_shield_pulse_tween.tween_property(_sprite_ring, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_SINE)

func take_damage(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health -= amount
	health_changed.emit(current_health, max_health)
	took_damage.emit()
	if _health_bar:
		_health_bar.value = current_health
	_flash_hit()
	if current_health <= 0.0:
		_die()

func _flash_hit() -> void:
	var hit_sfx := "res://assets/audio/sfx_laser2.ogg"
	if ResourceLoader.exists(hit_sfx):
		AudioManager.play_sfx(load(hit_sfx), -8.0, randf_range(0.7, 0.9))
	_sprite_core.modulate = Color(5.0, 3.0, 0.5, 1.0)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_sprite_core, "modulate", Color(1.3, 1.0, 0.25, 1.0), 0.2)
	t.tween_property(self, "scale", Vector2.ONE * 1.12, 0.06).set_trans(Tween.TRANS_SINE)
	t.chain().tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)

func _die() -> void:
	if _shield_pulse_tween:
		_shield_pulse_tween.kill()
	var sfx := "res://assets/audio/sfx_explosion.ogg"
	if not ResourceLoader.exists(sfx):
		sfx = "res://assets/audio/sfx_lose.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), 0.0, 0.8)
	destroyed.emit()
	# Big explosion: flash orange, scale outward, fade to nothing
	var t := create_tween()
	t.set_parallel(true)
	_sprite_core.modulate = Color(4.0, 2.0, 0.3, 1.0)
	t.tween_property(_sprite_core, "modulate", Color(1.0, 0.2, 0.0, 0.0), 0.6)
	t.tween_property(self, "scale", Vector2(3.5, 3.5), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_sprite_ring, "modulate:a", 0.0, 0.3)
	_spawn_debris()
	t.chain().tween_callback(queue_free)

func _spawn_debris() -> void:
	var debris_tex: Texture2D = null
	if ResourceLoader.exists("res://assets/sprites/meteorBrown_big1.png"):
		debris_tex = load("res://assets/sprites/meteorBrown_big1.png")
	for i in 6:
		var d := Sprite2D.new()
		if debris_tex:
			d.texture = debris_tex
			d.scale = Vector2.ONE * randf_range(0.15, 0.28)
		else:
			var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.9, 0.5, 0.1))
			d.texture = ImageTexture.create_from_image(img)
		d.modulate = Color(1.0, randf_range(0.4, 0.9), 0.1, 1.0)
		d.z_index = 10
		get_tree().current_scene.add_child(d)
		d.global_position = global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
		var angle := (TAU / 6.0) * i + randf_range(-0.3, 0.3)
		var dist := randf_range(40.0, 90.0)
		var target_pos := d.global_position + Vector2(cos(angle), sin(angle)) * dist
		var dt := d.create_tween()
		dt.set_parallel(true)
		dt.tween_property(d, "global_position", target_pos, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		dt.tween_property(d, "rotation", d.rotation + randf_range(-PI, PI), 0.5)
		dt.tween_property(d, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		dt.chain().tween_callback(d.queue_free)
