extends Node
## Gunship passive - Heat Up: weapon damage scales up to +30% as the ship moves.
## Heat builds at 0.4/s while moving, cools at 0.6/s while still.

const HEAT_BUILD: float = 0.4
const HEAT_COOL: float = 0.6
const MAX_BONUS: float = 0.3
const STILL_SPEED_SQ: float = 100.0

var _player: Player
var _heat: float = 0.0

func setup(player: Player) -> void:
	_player = player

func _process(delta: float) -> void:
	if _player.velocity.length_squared() > STILL_SPEED_SQ:
		_heat = minf(1.0, _heat + HEAT_BUILD * delta)
	else:
		_heat = maxf(0.0, _heat - HEAT_COOL * delta)
	var mult := 1.0 + _heat * MAX_BONUS
	for w in _player.weapons:
		if w.has_method("try_fire"):
			w.set("passive_multiplier", mult)
