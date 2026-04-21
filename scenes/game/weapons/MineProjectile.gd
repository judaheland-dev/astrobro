extends Area2D
class_name MineProjectile

## MineProjectile - a stationary proximity mine that arms after a short delay then
## detonates with an AoE blast when an enemy enters its trigger radius.

var damage: float = 55.0
var aoe_radius: float = 80.0
var shooter: Node = null
var armed: bool = false
const ARM_DELAY: float = 1.5
const SZ: int = 20
var _arm_timer: float = ARM_DELAY

var _sprite: Sprite2D = null

func setup(dmg: float, radius: float, owner_node: Node) -> void:
	damage = dmg
	aoe_radius = radius
	shooter = owner_node

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # detect enemies on layer 2
	monitoring = true
	body_entered.connect(_on_body_entered)

	# Build mine sprite (yellow diamond shape via Image)
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	var center := Vector2(SZ * 0.5, SZ * 0.5)
	for y in SZ:
		for x in SZ:
			var dx: float = abs(x + 0.5 - center.x)
			var dy: float = abs(y + 0.5 - center.y)
			if dx + dy <= SZ * 0.45:
				img.set_pixel(x, y, Color(0.9, 0.75, 0.1, 1.0))
	_sprite = Sprite2D.new()
	_sprite.texture = ImageTexture.create_from_image(img)
	_sprite.z_index = 2
	_sprite.modulate = Color(0.5, 0.5, 0.5, 0.6)   # dim while unarmed
	add_child(_sprite)

	# Collision trigger area
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	col.shape = shape
	add_child(col)

func _process(delta: float) -> void:
	if armed:
		return
	_arm_timer -= delta
	if _arm_timer <= 0.0:
		armed = true
		_sprite.modulate = Color.WHITE
		# Arm flash
		var t := create_tween()
		t.tween_property(_sprite, "modulate", Color(2.0, 1.6, 0.2), 0.05)
		t.tween_property(_sprite, "modulate", Color.WHITE, 0.15)
		# Pulse to indicate armed state
		var pulse := create_tween()
		pulse.set_loops()
		pulse.tween_property(_sprite, "modulate", Color(1.8, 1.2, 0.2), 0.4)
		pulse.tween_property(_sprite, "modulate", Color.WHITE, 0.4)

func _on_body_entered(body: Node) -> void:
	if not armed:
		return
	if not body.is_in_group("enemies"):
		return
	_detonate()

func _detonate() -> void:
	if not is_inside_tree():
		return

	# Explosion visual
	var exp := Sprite2D.new()
	exp.z_index = 8
	var exp_path := "res://assets/particles/explosion02.png"
	if ResourceLoader.exists(exp_path):
		exp.texture = load(exp_path)
	exp.scale = Vector2(0.08, 0.08)
	get_tree().current_scene.add_child(exp)
	exp.global_position = global_position
	var rt := exp.create_tween()
	rt.set_parallel(true)
	rt.tween_property(exp, "scale", Vector2(0.55, 0.55), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(exp, "modulate:a", 0.0, 0.55).set_delay(0.1)
	rt.chain().tween_callback(exp.queue_free)

	# AoE damage via physics shape query
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
		if body in already_damaged:
			continue
		already_damaged.append(body)
		if body.has_method("take_damage"):
			body.take_damage(damage)
			if shooter != null and "lifesteal" in shooter and shooter.lifesteal > 0.0:
				if shooter.has_method("heal"):
					shooter.heal(damage * shooter.lifesteal)

	var sfx_path := "res://assets/audio/sfx_explosion.ogg"
	if ResourceLoader.exists(sfx_path):
		AudioManager.play_sfx(load(sfx_path), -2.0, randf_range(0.9, 1.1))

	queue_free()
