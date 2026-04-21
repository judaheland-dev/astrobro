extends Node
## AfterburnerPassive - grants the player a rechargeable speed burst on demand.
## Boost: 2.2x speed for 0.7 s, 6 s recharge. Activated by the "boost" input action.

func setup(player: Player) -> void:
	player.boost_factor   = 2.2
	player.boost_duration = 0.7
	player._boost_recharge = 6.0
