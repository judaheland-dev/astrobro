extends Node
## Tank active - Fortress: armor absorbs all incoming damage for 2 s. 12 s cooldown.
## On activation: blue rotating shield ring appears around the ship, medium screen shake.
## On expiry: the ring shatters outward as a 30-damage shockwave pulse to nearby enemies.

const DURATION: float = 2.0
const COOLDOWN: float = 12.0
const FORTRESS_ARMOR: float = 9999.0
const BLAST_DAMAGE: float = 30.0
const BLAST_RADIUS: float = 200.0

var _player: Player
var _active: bool = false
var _duration_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _saved_armor: float = 0.0
var _was_on_cooldown: bool = false
var _shield_ring: Node2D = null
var _ring_angle: float = 0.0

func setup(player: Player) -> void:
	_player = player
	player.ability_cooldown_changed.emit(0.0)

func _exit_tree() -> void:
	if _shield_ring != null and is_instance_valid(_shield_ring):
		_shield_ring.queue_free()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	if InputManager.is_boosting(_player.player_index) and not _active and _cooldown_timer <= 0.0:
		_activate()

	if _active:
		_duration_timer -= delta
		# Rotate the shield ring
		_ring_angle += 1.8 * delta
		if _shield_ring != null and is_instance_valid(_shield_ring):
			_shield_ring.rotation = _ring_angle
		if _duration_timer <= 0.0:
			_active = false
			_player.armor = _saved_armor
			_cooldown_timer = COOLDOWN
			_fortress_end()
	elif _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
		var ratio := _cooldown_timer / COOLDOWN
		_player.ability_cooldown_changed.emit(ratio)
		if _was_on_cooldown and _cooldown_timer <= 0.0:
			_play_ready_sfx()

	_was_on_cooldown = _cooldown_timer > 0.0 or _active

func _activate() -> void:
	_saved_armor = _player.armor
	_player.armor = FORTRESS_ARMOR
	_active = true
	_duration_timer = DURATION
	_ring_angle = 0.0
	_add_trauma(0.30)
	# Blue flash
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(0.3, 0.7, 3.0), 0.0)
	t.tween_property(_player.sprite, "modulate", _player.base_sprite_color, 0.4)
	# Shockwave rings on activation
	_spawn_ring(Color(0.3, 0.6, 2.5, 0.80), 55.0, 0.38)
	_spawn_ring(Color(0.2, 0.5, 2.0, 0.45), 55.0, 0.56)
	# Spawn the rotating shield ring visual
	_spawn_shield_ring()
	var sfx := "res://assets/audio/sfx_explosion.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -8.0, 0.7)
	_player.ability_cooldown_changed.emit(1.0)

func _spawn_shield_ring() -> void:
	if _shield_ring != null and is_instance_valid(_shield_ring):
		_shield_ring.queue_free()
	_shield_ring = Node2D.new()
	_player.add_child(_shield_ring)
	# Build a blue ring texture
	const SZ := 120
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	var ctr := SZ * 0.5
	for y in SZ:
		for x in SZ:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(ctr, ctr))
			if d >= SZ * 0.38 and d <= SZ * 0.50:
				img.set_pixel(x, y, Color(0.3, 0.7, 2.5, 0.85))
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	_shield_ring.add_child(spr)
	# Pop-in
	_shield_ring.scale = Vector2.ZERO
	var t := _shield_ring.create_tween()
	t.tween_property(_shield_ring, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_shield_ring, "scale", Vector2.ONE, 0.08)
	# Pulsing glow
	var gl := spr.create_tween()
	gl.set_loops()
	gl.tween_property(spr, "modulate:a", 0.4, 0.3).set_trans(Tween.TRANS_SINE)
	gl.tween_property(spr, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)

func _fortress_end() -> void:
	# Shatter the shield ring outward
	if _shield_ring != null and is_instance_valid(_shield_ring):
		var node := _shield_ring
		_shield_ring = null
		var t := node.create_tween()
		t.set_parallel(true)
		t.tween_property(node, "scale", Vector2(2.2, 2.2), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(node, "modulate:a", 0.0, 0.35)
		t.chain().tween_callback(node.queue_free)
	# AoE damage blast to nearby enemies
	_blast_nearby_enemies()
	_spawn_ring(Color(0.3, 0.6, 2.5, 0.7), 100.0, 0.45)
	_add_trauma(0.20)

func _blast_nearby_enemies() -> void:
	if not is_instance_valid(_player):
		return
	var space := _player.get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BLAST_RADIUS
	params.shape = circle
	params.transform = Transform2D(0.0, _player.global_position)
	params.collision_mask = 2
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits := space.intersect_shape(params, 20)
	for hit in hits:
		var body: Node = hit["collider"]
		if is_instance_valid(body) and body.has_method("take_damage"):
			body.take_damage(BLAST_DAMAGE)

func _spawn_ring(color: Color, radius: float, duration: float) -> void:
	if not is_inside_tree() or not is_instance_valid(_player):
		return
	var ring := ColorRect.new()
	ring.color = color
	var sz := radius * 2.0
	ring.size = Vector2(sz, sz)
	ring.pivot_offset = ring.size * 0.5
	ring.position = _player.global_position - ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(ring)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(4.0, 4.0), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, duration)
	rt.chain().tween_callback(ring.queue_free)

func _play_ready_sfx() -> void:
	var sfx := "res://assets/audio/sfx_ability_activate.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -8.0, 0.9)

func _add_trauma(amount: float) -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("_add_trauma"):
		scene._add_trauma(amount)
