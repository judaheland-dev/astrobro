extends Node
## Runner passive - Afterburner: +20% weapon damage while moving at >90% top speed.

const BOOST: float = 0.2
const SPEED_THRESHOLD: float = 0.9

var _player: Player
var _boosted: bool = false

func setup(player: Player) -> void:
	_player = player

func _process(_delta: float) -> void:
	var ratio := _player.velocity.length() / maxf(1.0, _player.move_speed)
	var should_boost := ratio >= SPEED_THRESHOLD
	if should_boost == _boosted:
		return
	_boosted = should_boost
	var mult := (1.0 + BOOST) if _boosted else 1.0
	for w in _player.weapons:
		if w.has_method("try_fire"):
			w.set("passive_multiplier", mult)
