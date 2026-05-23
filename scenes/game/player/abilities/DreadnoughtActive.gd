extends Node
## Dreadnought active - Salvo: all weapons deal 3x damage for 1.5 s. 12 s cooldown.
## On activation: big screen shake and four expanding explosion rings.
## Ship pulses gold throughout the active window. Multiplier explicitly reset on expiry.

const DURATION: float = 1.5
const COOLDOWN: float = 12.0
const SALVO_MULT: float = 3.0

var _player: Player
var _active: bool = false
var _duration_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _was_on_cooldown: bool = false
var _pulse_timer: float = 0.0

func setup(player: Player) -> void:
	_player = player
	player.ability_cooldown_changed.emit(0.0)

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	if InputManager.is_boosting(_player.player_index) and not _active and _cooldown_timer <= 0.0:
		_activate()

	if _active:
		_duration_timer -= delta
		# Rapid gold pulses while firing the Salvo
		_pulse_timer -= delta
		if _pulse_timer <= 0.0:
			_pulse_timer = 0.38
			_pulse_ship_gold()
		if _duration_timer > 0.0:
			_set_multiplier(SALVO_MULT)
		else:
			_active = false
			_cooldown_timer = COOLDOWN
			_set_multiplier(1.0)
	elif _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
		var ratio := _cooldown_timer / COOLDOWN
		_player.ability_cooldown_changed.emit(ratio)
		if _was_on_cooldown and _cooldown_timer <= 0.0:
			_play_ready_sfx()

	_was_on_cooldown = _cooldown_timer > 0.0 or _active

func _activate() -> void:
	_active = true
	_duration_timer = DURATION
	_pulse_timer = 0.0
	_set_multiplier(SALVO_MULT)
	_add_trauma(0.50)   # big shake
	# Initial fiery ship flash
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(3.0, 1.0, 0.05), 0.0)
	t.tween_property(_player.sprite, "modulate", _player.base_sprite_color, 0.35)
	# Four explosion rings expanding outward
	_spawn_ring(Color(2.5, 1.0, 0.0, 0.80), 55.0, 0.28)
	_spawn_ring(Color(2.0, 0.7, 0.0, 0.60), 55.0, 0.40)
	_spawn_ring(Color(1.5, 0.5, 0.0, 0.40), 55.0, 0.54)
	_spawn_ring(Color(1.0, 0.3, 0.0, 0.22), 55.0, 0.70)
	var sfx := "res://assets/audio/sfx_explosion.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -6.0, 0.8)
	_player.ability_cooldown_changed.emit(1.0)

func _pulse_ship_gold() -> void:
	if not is_instance_valid(_player):
		return
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(2.8, 1.4, 0.05), 0.06)
	t.tween_property(_player.sprite, "modulate", _player.base_sprite_color, 0.28)

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
	rt.tween_property(ring, "scale", Vector2(4.5, 4.5), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
