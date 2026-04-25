extends RefCounted
class_name OverlordState

## Tracks the Overlord player's economy, roster, loadout, and global upgrades
## for the PVP Overlord game mode.

# Economy
var budget: int = 100
var carry_over: int = 0  # unspent budget from previous wave (50% carried)

# Per-enemy cost table
const ENEMY_COSTS: Dictionary = {
	&"grunt": 10,
	&"speeder": 12,
	&"exploder": 15,
	&"tracker": 18,
	&"sniper": 20,
	&"shielded": 22,
	&"ranger": 25,
	&"tank": 25,
	&"acid_ranger": 28,
	&"heavy_ranger": 28,
	&"sentinel": 30,
	&"brute": 35,
	&"corruptor": 40,
}

# Roster: how many of each enemy the Overlord owns for the current wave
# {enemy_id: int count}
var roster: Dictionary = {}

# Loadout: 4 face-button slots, each holds an enemy_id or &"" for empty
var loadout: Array[StringName] = [&"", &"", &"", &""]

# Deploy counts remaining per slot for the current wave (reset each wave from roster)
var deploy_remaining: Array[int] = [0, 0, 0, 0]

# Global upgrades (stackable)
var hp_mult: float = 1.0
var armor_bonus: float = 0.0
var speed_mult: float = 1.0
var spawn_cooldown_mult: float = 1.0  # lower = faster
var income_mult: float = 1.0

# Upgrade definitions: [display_name, cost, stat_key, delta_per_stack, description]
const UPGRADES: Array = [
	["HP Boost", 40, "hp_mult", 0.15, "+15% enemy HP"],
	["Armor Boost", 50, "armor_bonus", 2.0, "+2 enemy armor"],
	["Speed Boost", 35, "speed_mult", 0.10, "+10% enemy speed"],
	["Spawn Rate", 60, "spawn_cooldown_mult", -0.10, "-10% spawn cooldown"],
	["Income Boost", 80, "income_mult", 0.20, "+20% wave income"],
]

func wave_income(wave_number: int) -> int:
	return int((50 + wave_number * 20) * income_mult)

func start_wave() -> void:
	## Prepare deploy counts from roster into loadout slots.
	for i in 4:
		var eid: StringName = loadout[i]
		if eid != &"" and roster.has(eid):
			deploy_remaining[i] = roster[eid]
		else:
			deploy_remaining[i] = 0

func end_wave(wave_number: int) -> void:
	## Award next wave's income. Keep previous roster and auto-buy it from new budget.
	carry_over = budget / 2
	budget = carry_over + wave_income(wave_number + 1)
	# Auto-repurchase previous roster from the new budget.
	# If budget runs short, buy as many as we can afford per type.
	var prev_roster := roster.duplicate()
	roster.clear()
	for eid in prev_roster:
		var count: int = prev_roster[eid]
		var cost: int = ENEMY_COSTS.get(eid, 999)
		for _i in count:
			if budget >= cost:
				budget -= cost
				roster[eid] = roster.get(eid, 0) + 1
			else:
				break

func buy_enemy(enemy_id: StringName) -> bool:
	var cost: int = ENEMY_COSTS.get(enemy_id, 999)
	if budget < cost:
		return false
	budget -= cost
	roster[enemy_id] = roster.get(enemy_id, 0) + 1
	return true

func sell_enemy(enemy_id: StringName) -> bool:
	if not roster.has(enemy_id) or roster[enemy_id] <= 0:
		return false
	roster[enemy_id] -= 1
	if roster[enemy_id] <= 0:
		roster.erase(enemy_id)
	var cost: int = ENEMY_COSTS.get(enemy_id, 0)
	budget += cost / 2
	return true

func buy_upgrade(index: int) -> bool:
	if index < 0 or index >= UPGRADES.size():
		return false
	var cost: int = UPGRADES[index][1]
	if budget < cost:
		return false
	budget -= cost
	var stat_key: String = UPGRADES[index][2]
	var delta: float = UPGRADES[index][3]
	set(stat_key, get(stat_key) + delta)
	# Clamp spawn cooldown mult so it doesn't go below 0.5
	if stat_key == "spawn_cooldown_mult":
		spawn_cooldown_mult = maxf(0.5, spawn_cooldown_mult)
	return true

func deploy_enemy(slot: int) -> StringName:
	## Attempt to deploy from the given slot. Returns enemy_id or &"".
	if slot < 0 or slot >= 4:
		return &""
	if deploy_remaining[slot] <= 0:
		return &""
	var eid: StringName = loadout[slot]
	if eid == &"":
		return &""
	deploy_remaining[slot] -= 1
	return eid

func get_total_remaining() -> int:
	var total := 0
	for i in 4:
		total += deploy_remaining[i]
	return total
