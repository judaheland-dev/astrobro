extends Node
## Rogue passive - Windfall: 30% chance to double each Scrap drop.
## Applied by setting scrap_bonus_chance on the player (checked in add_scrap).

func setup(player: Player) -> void:
	player.scrap_bonus_chance = 0.3
