extends Node
## Escort Drone passive: an orbiting sprite that fires at the nearest enemy
## every 1.5 s for 8 damage. The drone orbits in world space (compensating for
## player rotation) and is added directly to the scene root so it stays upright.

const ORBIT_RADIUS: float = 80.0
const ORBIT_SPEED: float = TAU / 3.0   # one full orbit every 3 s
const FIRE_COOLDOWN: float = 1.5
const DRONE_DAMAGE: float = 8.0
const DRONE_SPEED: float = 500.0
const DRONE_RANGE: float = 500.0
const SCAN_RADIUS: float = 400.0

var _player: Player
var _orbit_angle: float = 0.0
var _fire_timer: float = 0.0
var _sprite: Sprite2D

func setup(player: Player) -> void:
	_player = player
	_orbit_angle = randf() * TAU

	_sprite = Sprite2D.new()
	var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.9, 1.0, 1.0))
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.z_index = 2
	get_tree().current_scene.add_child(_sprite)

func _exit_tree() -> void:
	if is_instance_valid(_sprite):
		_sprite.queue_free()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	_orbit_angle += ORBIT_SPEED * delta
	_sprite.global_position = _player.global_position + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * ORBIT_RADIUS

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_try_fire()

func _try_fire() -> void:
	var target := _find_nearest_enemy()
	if target == null:
		return
	_fire_timer = FIRE_COOLDOWN
	var origin := _sprite.global_position
	var dir := (target.global_position - origin).normalized()

	var proj := BaseProjectile.new()
	proj.collision_layer = 0
	proj.collision_mask = 2
	proj.shooter = _player

	var spr := Sprite2D.new()
	var img := Image.create(8, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.3, 0.9, 1.0))
	spr.texture = ImageTexture.create_from_image(img)
	spr.rotation_degrees = 90.0
	proj.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 4.0
	col.shape = shape
	proj.add_child(col)

	get_tree().current_scene.add_child(proj)
	proj.global_position = origin
	proj.setup(dir, DRONE_DAMAGE, DRONE_SPEED, DRONE_RANGE, 0)

func _find_nearest_enemy() -> Node:
	var space := _player.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SCAN_RADIUS
	params.shape = circle
	params.transform = Transform2D(0.0, _player.global_position)
	params.collision_mask = 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits := space.intersect_shape(params, 10)
	var closest: Node = null
	var closest_dist: float = INF
	for hit in hits:
		var body: Node = hit["collider"]
		if body == null or not body.has_method("take_damage"):
			continue
		var d := _player.global_position.distance_to(body.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = body
	return closest
