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
	MYTHIC,
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
	DAMAGE_BLOCK_CHANCE,   # additive block chance (0..1)
	SCRAP_BONUS_CHANCE,    # additive chance to double scrap drops
	INSTANT_HEAL,          # one-time: heals player by delta HP on pickup
	SHIELD_MAX,            # increases max shield capacity
	SHIELD_REGEN_RATE,     # increases shield regen speed (HP/s)
	CRIT_CHANCE,           # additive crit probability (0..1)
	CRIT_MULTIPLIER,       # additive crit damage multiplier (default 2.0, e.g. +0.5 → 2.5×)
	BOUNCE_COUNT,          # weapon: projectiles ricochet to N additional enemies after first hit
	CHAIN_COUNT,           # weapon: arcs to N nearby enemies on each hit
	FORK_COUNT,            # weapon: spawns N fan-out sub-projectiles on projectile death
	ARMOR_PEN,             # weapon: flat armor bypass (subtracted from target's armor)
	KNOCKBACK_FORCE,       # weapon: impulse applied to enemy on hit (pixels/s)
	DODGE_CHANCE,          # character: % chance to completely evade incoming hit (0..1)
	ON_KILL_HEAL,          # character: HP healed on each kill
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

# If set, this GDScript path is loaded and instantiated as a passive ability
# node added to the player when the upgrade is applied.
@export var passive_script: String = ""
