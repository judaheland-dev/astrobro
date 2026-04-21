extends Node
## OrbitalTurretPassive - places a stationary auto-firing turret at the player's
## position when the passive is acquired. Fires at enemies within 450 px every 1.8 s
## for 15 damage. Removed when the player dies.

const FIRE_COOLDOWN: float = 1.8
const TURRET_DAMAGE: float = 15.0
const TURRET_SPEED: float = 480.0
const TURRET_RANGE: float = 600.0
const SCAN_RADIUS: float = 450.0

var _player: Player
var _sprite: Sprite2D
var _fire_timer: float = 0.0
var _turret_pos: Vector2

func setup(player: Player) -> void:
	_player = player
	_turret_pos = player.global_position
	player.died.connect(_on_player_died)

	# Turret body - orange/gold cannon shape
	_sprite = Sprite2D.new()
	const SZ: int = 22
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	var cx := SZ * 0.5
	var cy := SZ * 0.5
	for y in SZ:
		for x in SZ:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cy))
			if d <= SZ * 0.4:
				img.set_pixel(x, y, Color(0.9, 0.55, 0.1, 1.0))
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.z_index = 2
	get_tree().current_scene.add_child(_sprite)
	_sprite.global_position = _turret_pos

func _exit_tree() -> void:
	if is_instance_valid(_sprite):
		_sprite.queue_free()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_try_fire()

func _try_fire() -> void:
	var target := _find_nearest_enemy()
	if target == null:
		return
	_fire_timer = FIRE_COOLDOWN
	var dir := (target.global_position - _turret_pos).normalized()

	var proj := BaseProjectile.new()
	proj.collision_layer = 0
	proj.collision_mask = 2
	proj.shooter = _player

	var spr := Sprite2D.new()
	var img := Image.create(10, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.55, 0.1))
	spr.texture = ImageTexture.create_from_image(img)
	spr.rotation_degrees = 90.0
	proj.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10.0, 4.0)
	col.shape = shape
	proj.add_child(col)

	get_tree().current_scene.add_child(proj)
	proj.global_position = _turret_pos
	proj.setup(dir, TURRET_DAMAGE, TURRET_SPEED, TURRET_RANGE, 0)

	# Muzzle flash on the turret sprite
	if is_instance_valid(_sprite):
		var t := _sprite.create_tween()
		t.tween_property(_sprite, "modulate", Color(2.0, 1.5, 0.5), 0.03)
		t.tween_property(_sprite, "modulate", Color.WHITE, 0.12)

func _find_nearest_enemy() -> Node2D:
	if not is_instance_valid(_player):
		return null
	var space := _player.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SCAN_RADIUS
	params.shape = circle
	params.transform = Transform2D(0.0, _turret_pos)
	params.collision_mask = 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits := space.intersect_shape(params, 10)
	var closest: Node2D = null
	var closest_dist: float = INF
	for hit in hits:
		var body: Node2D = hit["collider"]
		if body == null or not body.has_method("take_damage"):
			continue
		var d := _turret_pos.distance_to(body.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = body
	return closest

func _on_player_died() -> void:
	if is_instance_valid(_sprite):
		var t := _sprite.create_tween()
		t.tween_property(_sprite, "modulate:a", 0.0, 0.4)
		t.tween_callback(_sprite.queue_free)
	queue_free()
