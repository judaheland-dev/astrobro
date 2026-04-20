extends Node
## Tank passive - Reactive Armor: 50% chance to block an incoming hit entirely.
## Applies an 8-second cooldown after each block (handled via damage_block_chance
## and _block_cooldown in Player.take_damage).

func setup(player: Player) -> void:
	player.damage_block_chance = 0.5
