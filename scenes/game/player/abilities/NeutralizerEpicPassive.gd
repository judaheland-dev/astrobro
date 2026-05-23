extends Node
## Neutralizer (Epic): Exploder AoE damage is quartered.
## Brutes are suppressed — they stop spawning for the rest of the run.

func setup(player: Player) -> void:
	player.exploder_damage_reduction = maxf(player.exploder_damage_reduction, 4.0)
	if not GameManager.banned_enemy_ids.has(&"brute"):
		GameManager.banned_enemy_ids.append(&"brute")
