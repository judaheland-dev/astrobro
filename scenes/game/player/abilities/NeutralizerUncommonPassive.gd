extends Node
## Neutralizer (Uncommon): Exploder AoE damage is quartered.
## Grunt and Speeder contact damage is reduced by 10 flat.

func setup(player: Player) -> void:
	player.exploder_damage_reduction = maxf(player.exploder_damage_reduction, 4.0)
	player.grunt_speeder_damage_reduction += 10.0
