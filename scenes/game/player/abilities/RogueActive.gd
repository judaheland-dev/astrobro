extends Node
## Rogue active - Vanish: 1.5x speed for 3 s with guaranteed double scrap. 10 s cooldown.
## Uses Player.activate_boost() for the speed burst; scrap bonus tracked per-frame.

const BOOST_FACTOR: float = 1.5
const BOOST_DURATION: float = 3.0
const BOOST_RECHARGE: float = 10.0
const ROGUE_BASE_SCRAP_CHANCE: float = 0.3   # matches RoguePassive

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
	# Guarantee double scrap while vanish is active
	if _player._boost_timer > 0.0:
		_player.scrap_bonus_chance = 1.0
	else:
		_player.scrap_bonus_chance = ROGUE_BASE_SCRAP_CHANCE
	var ratio := _player._boost_cooldown / BOOST_RECHARGE
	_player.ability_cooldown_changed.emit(ratio)
	if _was_on_cooldown and ratio <= 0.0:
		var sfx := "res://assets/audio/sfx_twoTone.ogg"
		if ResourceLoader.exists(sfx):
			AudioManager.play_sfx(load(sfx), -8.0, 0.9)
	_was_on_cooldown = ratio > 0.0
