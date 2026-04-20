extends Resource
class_name UpgradeData

## Data resource defining a single upgrade choice offered on level-up or in the shop.

enum UpgradeScope {
	CHARACTER,  # buffs the player character stats
	WEAPON,     # buffs current/all weapons
	PASSIVE,    # adds a passive effect
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

enum StatKey {
	MAX_HEALTH,
	MOVE_SPEED,
	ARMOR,
	DAMAGE,
	FIRE_RATE,
	PROJECTILE_SPEED,
	XP_MULTIPLIER,
	COIN_MULTIPLIER,
	LIFESTEAL,         # % of damage dealt returned as HP
	RANGE,
	SPREAD,            # negative = better (less spread)
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null
@export var scope: UpgradeScope = UpgradeScope.CHARACTER
@export var rarity: Rarity = Rarity.COMMON

# Which stats change and by how much (additive, absolute values)
@export var stat_deltas: Dictionary = {}  # StatKey -> float

# Shop-only price (0 = level-up only)
@export var shop_price: int = 0

# Max times this upgrade can be taken per run (-1 = unlimited)
@export var max_stacks: int = -1

# Optional passive scene to add to the player
@export var passive_scene: PackedScene = null
