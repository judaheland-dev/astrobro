extends Node
## ReflectiveShieldPassive - intercepted enemy missiles are reflected back at enemies.

func setup(player: Player) -> void:
	player.reflective_shield = true
