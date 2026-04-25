extends Node
## Tank active - Fortress: armor absorbs all incoming damage for 2 s. 12 s cooldown.
## Saves and restores the player's real armor value around the invulnerable window.

const DURATION: float = 2.0
const COOLDOWN: float = 12.0
const FORTRESS_ARMOR: float = 9999.0

var _player: Player
var _active: bool = false
var _duration_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _saved_armor: float = 0.0
var _was_on_cooldown: bool = false

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
		if _duration_timer <= 0.0:
			_active = false
			_player.armor = _saved_armor
			_cooldown_timer = COOLDOWN
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
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(0.3, 0.7, 2.5), 0.0)
	t.tween_property(_player.sprite, "modulate", Color.WHITE, 0.4)
	var sfx := "res://assets/audio/sfx_explosion.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -8.0, 0.7)
	_player.ability_cooldown_changed.emit(1.0)

func _play_ready_sfx() -> void:
	var sfx := "res://assets/audio/sfx_ability_activate.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -8.0, 0.9)
