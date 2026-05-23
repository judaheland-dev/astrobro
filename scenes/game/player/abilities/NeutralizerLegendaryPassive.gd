extends Node
## Neutralizer (Legendary): Exploder AoE damage is quartered.
## All weapons — current and future — deal 2x damage.
## Costs no power to apply (empty stat_deltas → zero module_power_delta).

func setup(player: Player) -> void:
	player.exploder_damage_reduction = maxf(player.exploder_damage_reduction, 4.0)
	# Double all existing weapons' effective damage multiplier
	for weapon in player.weapons:
		if weapon.has_method("get") and weapon.get("damage_multiplier") != null:
			weapon.set("damage_multiplier", weapon.get("damage_multiplier") * 2.0)
	# Future weapons will inherit 2x via the raised damage_bonus
	player.damage_bonus += 1.0
