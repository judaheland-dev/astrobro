extends Node
## Scout active ability - Afterburner: 1.8x speed for 3 s, 8 s cooldown.
## Activated by the "boost" input action (Shift / L1).
## Emits ability_cooldown_changed on the player each frame so the HUD bar stays current.

const BOOST_FACTOR: float = 1.8
const BOOST_DURATION: float = 3.0
const BOOST_RECHARGE: float = 8.0

var _player: Player
var _was_on_cooldown: bool = false

func setup(player: Player) -> void:
	_player = player
	player.boost_factor   = BOOST_FACTOR
	player.boost_duration = BOOST_DURATION
	player.boost_recharge = BOOST_RECHARGE
	player.ability_cooldown_changed.emit(0.0)

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var ratio := _player._boost_cooldown / BOOST_RECHARGE
	_player.ability_cooldown_changed.emit(ratio)
	# Play a soft chime the moment the cooldown expires
	if _was_on_cooldown and ratio <= 0.0:
		var sfx := "res://assets/audio/sfx_twoTone.ogg"
		if ResourceLoader.exists(sfx):
			AudioManager.play_sfx(load(sfx), -8.0, 0.9)
	_was_on_cooldown = ratio > 0.0
