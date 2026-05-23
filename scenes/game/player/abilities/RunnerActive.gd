extends Node
## Runner active - Redline: 2x speed for 4 s, 8 s cooldown.
## On activation: three staggered orange/red shockwave rings, medium screen shake,
## 0.5 s guaranteed-dodge window, and a fiery red aftertrail while boosting.

const BOOST_FACTOR: float = 2.0
const BOOST_DURATION: float = 4.0
const BOOST_RECHARGE: float = 8.0
const DODGE_WINDOW: float = 0.5   # brief invulnerability on takeoff

var _player: Player
var _was_on_cooldown: bool = false
var _prev_boost_active: bool = false
var _dodge_timer: float = 0.0
var _saved_dodge: float = 0.0
var _trail_timer: float = 0.0

func setup(player: Player) -> void:
	_player = player
	player.boost_factor   = BOOST_FACTOR
	player.boost_duration = BOOST_DURATION
	player.boost_recharge = BOOST_RECHARGE
	player.ability_cooldown_changed.emit(0.0)

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	var boost_active := _player._boost_timer > 0.0

	# Detect fresh activation
	if not _prev_boost_active and boost_active:
		_on_activated()

	# Fiery aftertrail while boosting
	if boost_active:
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.07
			_spawn_aftertrail()

	_prev_boost_active = boost_active

	# Dodge window countdown
	if _dodge_timer > 0.0:
		_dodge_timer -= delta
		if _dodge_timer <= 0.0:
			_player.dodge_chance = _saved_dodge

	var ratio := _player._boost_cooldown / BOOST_RECHARGE
	_player.ability_cooldown_changed.emit(ratio)
	if _was_on_cooldown and ratio <= 0.0:
		_play_ready_sfx()
	_was_on_cooldown = ratio > 0.0

func _on_activated() -> void:
	_add_trauma(0.30)
	# Orange-red ship flash
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(3.0, 0.3, 0.05), 0.0)
	t.tween_property(_player.sprite, "modulate", _player.base_sprite_color, 0.45)
	# Three staggered shockwave rings
	_spawn_ring(Color(1.0, 0.35, 0.0, 0.75), 55.0, 0.32)
	_spawn_ring(Color(1.0, 0.6,  0.1, 0.50), 55.0, 0.50)
	_spawn_ring(Color(0.8, 0.2,  0.0, 0.28), 55.0, 0.70)
	# Brief invulnerability window
	_saved_dodge = _player.dodge_chance
	_player.dodge_chance = 1.0
	_dodge_timer = DODGE_WINDOW

func _spawn_aftertrail() -> void:
	if not is_inside_tree() or not is_instance_valid(_player):
		return
	var ghost := Sprite2D.new()
	ghost.texture = _player.sprite.texture
	ghost.scale = _player.sprite.scale
	ghost.rotation = _player.rotation + _player.sprite.rotation
	ghost.modulate = Color(1.0, 0.3, 0.0, 0.50)
	ghost.z_index = _player.z_index - 1
	get_tree().current_scene.add_child(ghost)
	ghost.global_position = _player.global_position
	var gt := ghost.create_tween()
	gt.tween_property(ghost, "modulate:a", 0.0, 0.18)
	gt.tween_callback(ghost.queue_free)

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
	rt.tween_property(ring, "scale", Vector2(3.8, 3.8), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
