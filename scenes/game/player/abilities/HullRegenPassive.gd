extends Node
## Hull Regen passive: regenerates 3 HP/s up to max health.
## Accumulates partial HP each frame and heals in 1-HP increments to avoid
## flooding health_changed with 60 emissions per second.

const REGEN_RATE: float = 3.0

var _player: Player
var _accum: float = 0.0

func setup(player: Player) -> void:
	_player = player

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	if _player.current_health >= _player.max_health:
		_accum = 0.0
		return
	_accum += REGEN_RATE * delta
	if _accum >= 1.0:
		var to_heal := floorf(_accum)
		_accum -= to_heal
		_player.heal(to_heal)
