extends Node
## EMPModulePassive - 15% crit chance; critical hits fire an EMP pulse that stuns
## enemies within 120 px for 1.5 s.

func setup(player: Player) -> void:
	player.crit_chance  += 0.15
	player.emp_radius    = 120.0
