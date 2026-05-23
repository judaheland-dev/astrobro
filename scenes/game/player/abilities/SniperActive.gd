extends Node
## Sniper active - Overcharge: 3x weapon damage for 2.5 s. 10 s cooldown.
## On activation: screen shake, three expanding energy rings, and a pulsing gold halo
## around the ship for the duration. Bug fix: explicitly resets multiplier on expiry.

const WINDOW: float = 2.5         # extended from 2 s
const COOLDOWN: float = 10.0
const DAMAGE_MULT: float = 3.0

var _player: Player
var _active: bool = false
var _window_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _was_on_cooldown: bool = false
var _halo: Node2D = null

func setup(player: Player) -> void:
	_player = player
	player.ability_cooldown_changed.emit(0.0)

func _exit_tree() -> void:
	if _halo != null and is_instance_valid(_halo):
		_halo.queue_free()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	if InputManager.is_boosting(_player.player_index) and not _active and _cooldown_timer <= 0.0:
		_activate()

	if _active:
		_window_timer -= delta
		if _window_timer > 0.0:
			_set_multiplier(DAMAGE_MULT)
		else:
			_active = false
			_cooldown_timer = COOLDOWN
			_set_multiplier(1.0)   # explicitly reset so multiplier doesn't linger
			_dismiss_halo()
	elif _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
		var ratio := _cooldown_timer / COOLDOWN
		_player.ability_cooldown_changed.emit(ratio)
		if _was_on_cooldown and _cooldown_timer <= 0.0:
			_play_ready_sfx()

	_was_on_cooldown = _cooldown_timer > 0.0 or _active

func _activate() -> void:
	_active = true
	_window_timer = WINDOW
	_set_multiplier(DAMAGE_MULT)
	_add_trauma(0.25)
	# Bright yellow-white ship flash
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(3.5, 2.5, 0.1), 0.0)
	t.tween_property(_player.sprite, "modulate", _player.base_sprite_color, 0.5)
	# Three expanding energy rings
	_spawn_ring(Color(2.5, 2.0, 0.1, 0.70), 55.0, 0.40)
	_spawn_ring(Color(2.0, 1.5, 0.1, 0.50), 55.0, 0.56)
	_spawn_ring(Color(1.5, 1.0, 0.1, 0.30), 55.0, 0.72)
	# Persistent pulsing halo
	_spawn_halo()
	var sfx := "res://assets/audio/sfx_sniper.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -4.0, 0.6)
	_player.ability_cooldown_changed.emit(1.0)

func _spawn_halo() -> void:
	if _halo != null and is_instance_valid(_halo):
		_halo.queue_free()
	_halo = Node2D.new()
	_player.add_child(_halo)
	# Procedural ring texture
	const SZ := 96
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	var ctr := SZ * 0.5
	for y in SZ:
		for x in SZ:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(ctr, ctr))
			if d >= SZ * 0.36 and d <= SZ * 0.48:
				img.set_pixel(x, y, Color(2.5, 2.0, 0.2, 0.9))
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	_halo.add_child(spr)
	# Pop-in
	_halo.scale = Vector2.ZERO
	var pt := _halo.create_tween()
	pt.tween_property(_halo, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pt.tween_property(_halo, "scale", Vector2.ONE, 0.08)
	# Pulsing glow loop
	var gl := spr.create_tween()
	gl.set_loops()
	gl.tween_property(spr, "modulate:a", 0.3, 0.35).set_trans(Tween.TRANS_SINE)
	gl.tween_property(spr, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_SINE)

func _dismiss_halo() -> void:
	if _halo != null and is_instance_valid(_halo):
		var node := _halo
		_halo = null
		var t := node.create_tween()
		t.tween_property(node, "modulate:a", 0.0, 0.3)
		t.tween_callback(node.queue_free)

func _set_multiplier(mult: float) -> void:
	for w in _player.weapons:
		if w.has_method("try_fire"):
			w.set("passive_multiplier", mult)

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
	rt.tween_property(ring, "scale", Vector2(3.5, 3.5), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
