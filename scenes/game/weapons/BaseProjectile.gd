extends Area2D
class_name BaseProjectile

## BaseProjectile - moves in a direction, deals damage on hit, expires by range.

var direction: Vector2 = Vector2.RIGHT
var speed: float = 400.0
var damage: float = 10.0
var max_range: float = 600.0
var piercing: int = 0

var _distance_traveled: float = 0.0
var _hit_entities: Array[Node] = []   # track already-hit to avoid double damage

func setup(dir: Vector2, dmg: float, spd: float, rng: float, pierce: int) -> void:
	direction = dir.normalized()
	damage = dmg
	speed = spd
	max_range = rng
	piercing = pierce
	rotation = dir.angle()

func _ready() -> void:
	body_entered.connect(_on_body_entered)
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
	var move := direction * speed * delta
	global_position += move
	_distance_traveled += move.length()
	if _distance_traveled >= max_range:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body in _hit_entities:
		return
	_hit_entities.append(body)

	if body.has_method("take_damage"):
		body.take_damage(damage)
		_spawn_impact_flash()

	if piercing <= 0:
		queue_free()
	else:
		piercing -= 1

func _spawn_impact_flash() -> void:
	var flash := Sprite2D.new()
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.9, 0.3, 1.0))
	flash.texture = ImageTexture.create_from_image(img)
	flash.z_index = 10
	var parent := get_tree().current_scene
	parent.add_child(flash)
	flash.global_position = global_position
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector2(2.5, 2.5), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(flash, "modulate:a", 0.0, 0.15)
	t.chain().tween_callback(flash.queue_free)
