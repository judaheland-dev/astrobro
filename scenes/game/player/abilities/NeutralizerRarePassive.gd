extends Node
## Neutralizer (Rare): Exploder AoE damage is divided by 7 (base 4x + bonus 3x).

func setup(player: Player) -> void:
	player.exploder_damage_reduction = maxf(player.exploder_damage_reduction, 7.0)
