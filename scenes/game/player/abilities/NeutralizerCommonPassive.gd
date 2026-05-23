extends Node
## Neutralizer (Common): Exploder AoE damage is quartered.
## The XP multiplier penalty is handled via stat_deltas in the .tres resource.

func setup(player: Player) -> void:
	player.exploder_damage_reduction = maxf(player.exploder_damage_reduction, 4.0)
