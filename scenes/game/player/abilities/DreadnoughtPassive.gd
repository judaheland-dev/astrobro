extends Node
## Dreadnought passive - Heavy Shells: every 5th firing burst deals 1.5x damage.
## Listens to the weapon_fired signal; sets passive_multiplier on all weapons
## BEFORE shots fire (signal is emitted at the start of _fire_all_weapons).

var _player: Player
var _shot_count: int = 0
var _boost_pending: bool = false

func setup(player: Player) -> void:
	_player = player
	player.weapon_fired.connect(_on_weapon_fired)

func _on_weapon_fired() -> void:
	# Reset boost from the previous boosted burst
	if _boost_pending:
		_boost_pending = false
		_set_heavy(false)

	_shot_count += 1
	if _shot_count % 5 == 0:
		_set_heavy(true)
		_boost_pending = true

func _set_heavy(on: bool) -> void:
	for w in _player.weapons:
		if w.has_method("try_fire"):
			w.set("passive_multiplier", 1.5 if on else 1.0)
