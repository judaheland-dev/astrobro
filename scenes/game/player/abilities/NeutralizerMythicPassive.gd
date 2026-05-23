extends Node
## Neutralizer (Mythic): Exploder AoE damage is quartered.
## Each upgrade has a 50% chance to not apply any of its debuff stats.
## Costs no power to apply (empty stat_deltas → zero module_power_delta).

func setup(player: Player) -> void:
	player.exploder_damage_reduction = maxf(player.exploder_damage_reduction, 4.0)
	player.no_debuff_chance = clampf(player.no_debuff_chance + 0.5, 0.0, 1.0)
