extends Node
## Gunship active - Overclock: forces max heat (passive_multiplier 1.3) for 4 s. 10 s cooldown.
## Re-applies the cap every frame to override GunshipPassive's heat curve while active.

const DURATION: float = 4.0
const COOLDOWN: float = 10.0
const MAX_MULT: float = 1.3   # matches GunshipPassive MAX_BONUS = 0.3

var _player: Player
var _active: bool = false
var _duration_timer: float = 0.0
var _cooldown_timer: float = 0.0
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
		if _duration_timer > 0.0:
			_set_multiplier(MAX_MULT)
		else:
			_active = false
			_cooldown_timer = COOLDOWN
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
	_set_multiplier(MAX_MULT)
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(2.5, 1.0, 0.1), 0.0)
	t.tween_property(_player.sprite, "modulate", Color.WHITE, 0.5)
	var sfx := "res://assets/audio/sfx_levelup.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -4.0, 1.2)
	_player.ability_cooldown_changed.emit(1.0)

func _set_multiplier(mult: float) -> void:
	for w in _player.weapons:
		if w.has_method("try_fire"):
			w.set("passive_multiplier", mult)

func _play_ready_sfx() -> void:
	var sfx := "res://assets/audio/sfx_ability_activate.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -8.0, 0.9)
