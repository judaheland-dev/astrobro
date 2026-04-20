extends Node
## Sniper passive - Precision: standing still >=1.5s grants +50% weapon damage.
## Resets immediately on movement.

const THRESHOLD: float = 1.5
const BOOST: float = 0.5
const STILL_SPEED_SQ: float = 100.0

var _player: Player
var _still_time: float = 0.0
var _boosted: bool = false

func setup(player: Player) -> void:
	_player = player

func _process(delta: float) -> void:
	if _player.velocity.length_squared() < STILL_SPEED_SQ:
		_still_time += delta
		if not _boosted and _still_time >= THRESHOLD:
			_set_boost(true)
	else:
		_still_time = 0.0
		if _boosted:
			_set_boost(false)

func _set_boost(on: bool) -> void:
	_boosted = on
	for w in _player.weapons:
		if w.has_method("try_fire"):
			w.set("passive_multiplier", (1.0 + BOOST) if on else 1.0)
