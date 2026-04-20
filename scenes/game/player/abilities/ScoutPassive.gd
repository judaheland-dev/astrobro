extends Node
## Scout passive - Target Lock: on XP gain (proxy for kill), +25% weapon damage for 3s.

const BOOST: float = 0.25
const DURATION: float = 3.0

var _player: Player
var _active: bool = false
var _timer: float = 0.0

func setup(player: Player) -> void:
	_player = player
	player.xp_gained.connect(_on_xp_gained)

func _on_xp_gained(_new_xp: int, _threshold: int) -> void:
	_timer = DURATION
	if not _active:
		_active = true
		_apply(true)

func _process(delta: float) -> void:
	if _active:
		_timer -= delta
		if _timer <= 0.0:
			_active = false
			_apply(false)

func _apply(on: bool) -> void:
	for w in _player.weapons:
		if w.has_method("try_fire"):
			w.set("passive_multiplier", (1.0 + BOOST) if on else 1.0)
