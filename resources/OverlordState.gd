extends RefCounted
class_name OverlordState

## Tracks the Overlord player's economy, roster, loadout, and global upgrades
## for the PVP Overlord game mode.

# Economy
var budget: int = 250
var carry_over: int = 0  # unspent budget from previous wave (60% carried)

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

# Sprite paths for enemy ship icons (shared with OverlordController + ShopUI)
const ENEMY_SPRITES: Dictionary = {
	&"grunt":         "res://assets/sprites/enemyRed1.png",
	&"speeder":       "res://assets/sprites/enemyBlue1.png",
	&"brute":         "res://assets/sprites/enemyBlack1.png",
	&"exploder":      "res://assets/sprites/enemyGreen1.png",
	&"ranger":        "res://assets/sprites/enemyBlue2.png",
	&"sniper":        "res://assets/sprites/enemyBlue3.png",
	&"sentinel":      "res://assets/sprites/enemyBlack3.png",
	&"acid_ranger":   "res://assets/sprites/enemyGreen2.png",
	&"heavy_ranger":  "res://assets/sprites/enemyBlue4.png",
	&"tracker":       "res://assets/sprites/enemyRed3.png",
	&"corruptor":     "res://assets/sprites/enemyGreen4.png",
	&"shielded":      "res://assets/sprites/enemyRed1.png",
	&"tank":          "res://assets/sprites/enemyBlack1.png",
}

# All supported deploy buttons: face + d-pad + shoulders
# Each entry: [joy_constant, display_label, color]
const BUTTON_DEFS: Array = [
	[JOY_BUTTON_A,              "B",     Color(0.8, 0.2, 0.2)],
	[JOY_BUTTON_B,              "A",     Color(0.2, 0.8, 0.2)],
	[JOY_BUTTON_X,              "Y",     Color(1.0, 0.8, 0.1)],
	[JOY_BUTTON_Y,              "X",     Color(0.2, 0.5, 1.0)],
	[JOY_BUTTON_DPAD_UP,        "Up",    Color(0.7, 0.7, 0.7)],
	[JOY_BUTTON_DPAD_DOWN,      "Down",  Color(0.7, 0.7, 0.7)],
	[JOY_BUTTON_DPAD_LEFT,      "Left",  Color(0.7, 0.7, 0.7)],
	[JOY_BUTTON_DPAD_RIGHT,     "Right", Color(0.7, 0.7, 0.7)],
	[JOY_BUTTON_LEFT_SHOULDER,  "LB",    Color(0.6, 0.4, 0.8)],
	[JOY_BUTTON_RIGHT_SHOULDER, "RB",    Color(0.6, 0.4, 0.8)],
]

# Roster: how many of each enemy the Overlord owns for the current wave
# {enemy_id: int count}
var roster: Dictionary = {}

# Loadout: maps button index (into BUTTON_DEFS) -> ordered Array of enemy_ids.
# Each entry is one unit. E.g. {0: [&"grunt", &"grunt", &"speeder"], 1: [&"tank"]}
var loadout: Dictionary = {}

# Deploy state: index into each button's sequence (reset each wave)
var deploy_index: Dictionary = {}  # {int button_index: int next_index}

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
	return int((100 + wave_number * 50) * income_mult)

func start_wave() -> void:
	## Reset deploy indices so each button deploys from the start of its sequence.
	deploy_index.clear()
	for btn_idx in loadout:
		deploy_index[btn_idx] = 0

func end_wave(wave_number: int) -> void:
	## Award next wave's income. Auto-repurchase previous roster from new budget.
	carry_over = int(budget * 0.6)
	budget = carry_over + wave_income(wave_number + 1)
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
	# Also remove any loadout assignments for this enemy that exceed new count
	_trim_assignments(enemy_id)
	var cost: int = ENEMY_COSTS.get(enemy_id, 0)
	budget += cost / 2
	return true

func _trim_assignments(enemy_id: StringName) -> void:
	## If roster count drops, remove excess assignments from loadout (LIFO per button).
	var allowed: int = roster.get(enemy_id, 0)
	var total_assigned := _count_total_assigned(enemy_id)
	if total_assigned <= allowed:
		return
	var to_remove: int = total_assigned - allowed
	# Remove from highest button index first
	var btn_keys: Array = loadout.keys()
	btn_keys.sort()
	btn_keys.reverse()
	for btn_idx in btn_keys:
		if to_remove <= 0:
			break
		var seq: Array = loadout[btn_idx]
		var i: int = seq.size() - 1
		while i >= 0 and to_remove > 0:
			if seq[i] == enemy_id:
				seq.remove_at(i)
				to_remove -= 1
			i -= 1
		if seq.is_empty():
			loadout.erase(btn_idx)

func _count_total_assigned(enemy_id: StringName) -> int:
	var total := 0
	for btn_idx in loadout:
		var seq: Array = loadout[btn_idx]
		for eid in seq:
			if eid == enemy_id:
				total += 1
	return total

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
	if stat_key == "spawn_cooldown_mult":
		spawn_cooldown_mult = maxf(0.5, spawn_cooldown_mult)
	return true

# ---------------------------------------------------------------------------
# Loadout assignment
# ---------------------------------------------------------------------------

func assign_to_button(button_index: int, enemy_id: StringName) -> bool:
	## Assign one unit of enemy_id to a button. Returns false if none unassigned.
	if get_unassigned_count(enemy_id) <= 0:
		return false
	if not loadout.has(button_index):
		loadout[button_index] = []
	loadout[button_index].append(enemy_id)
	return true

func unassign_from_button(button_index: int, list_index: int) -> void:
	## Remove one entry from a button's sequence by index.
	if not loadout.has(button_index):
		return
	var seq: Array = loadout[button_index]
	if list_index >= 0 and list_index < seq.size():
		seq.remove_at(list_index)
	if seq.is_empty():
		loadout.erase(button_index)

func clear_button(button_index: int) -> void:
	loadout.erase(button_index)

func clear_enemy_assignments(enemy_id: StringName) -> void:
	## Remove ALL instances of enemy_id from every button's sequence.
	for btn_idx in loadout.keys():
		var seq: Array = loadout[btn_idx]
		var i: int = seq.size() - 1
		while i >= 0:
			if seq[i] == enemy_id:
				seq.remove_at(i)
			i -= 1
		if seq.is_empty():
			loadout.erase(btn_idx)

func get_unassigned_count(enemy_id: StringName) -> int:
	## Roster count minus total assigned across all buttons.
	return roster.get(enemy_id, 0) - _count_total_assigned(enemy_id)

func get_assignments_for_enemy(enemy_id: StringName) -> Dictionary:
	## Returns {button_index: count} for every button that has this enemy.
	var result: Dictionary = {}
	for btn_idx in loadout:
		var seq: Array = loadout[btn_idx]
		var c := 0
		for eid in seq:
			if eid == enemy_id:
				c += 1
		if c > 0:
			result[btn_idx] = c
	return result

# ---------------------------------------------------------------------------
# Deployment
# ---------------------------------------------------------------------------

func deploy_enemy(button_index: int) -> StringName:
	## Deploy the next unit in sequence for this button. Returns enemy_id or &"".
	if not loadout.has(button_index):
		return &""
	var seq: Array = loadout[button_index]
	var idx: int = deploy_index.get(button_index, 0)
	if idx >= seq.size():
		return &""
	var eid: StringName = seq[idx]
	deploy_index[button_index] = idx + 1
	return eid

func get_total_remaining() -> int:
	var total := 0
	for btn_idx in loadout:
		var seq: Array = loadout[btn_idx]
		var idx: int = deploy_index.get(btn_idx, 0)
		total += maxi(seq.size() - idx, 0)
	return total

func get_button_remaining(button_index: int) -> int:
	if not loadout.has(button_index):
		return 0
	var seq: Array = loadout[button_index]
	var idx: int = deploy_index.get(button_index, 0)
	return maxi(seq.size() - idx, 0)

func get_next_deploy_enemy(button_index: int) -> StringName:
	## Peek at what enemy would deploy next (for HUD display).
	if not loadout.has(button_index):
		return &""
	var seq: Array = loadout[button_index]
	var idx: int = deploy_index.get(button_index, 0)
	if idx >= seq.size():
		return &""
	return seq[idx]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func get_button_label(button_index: int) -> String:
	if button_index >= 0 and button_index < BUTTON_DEFS.size():
		return BUTTON_DEFS[button_index][1]
	return "?"

func get_button_color(button_index: int) -> Color:
	if button_index >= 0 and button_index < BUTTON_DEFS.size():
		return BUTTON_DEFS[button_index][2]
	return Color.WHITE

func get_button_joy_id(button_index: int) -> int:
	if button_index >= 0 and button_index < BUTTON_DEFS.size():
		return BUTTON_DEFS[button_index][0]
	return -1

func joy_button_to_def_index(joy_button: int) -> int:
	## Map a JoyButton constant to a BUTTON_DEFS index, or -1.
	for i in BUTTON_DEFS.size():
		if BUTTON_DEFS[i][0] == joy_button:
			return i
	return -1
