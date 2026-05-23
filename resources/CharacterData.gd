extends Resource
class_name CharacterData

## Data resource defining a playable character.

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var sprite: Texture2D = null

# Base stats
@export var max_health: float = 100.0
@export var move_speed: float = 200.0
@export var armor: float = 0.0          # flat damage reduction
@export var xp_multiplier: float = 1.0
@export var coin_multiplier: float = 1.0

# Cosmetic ship color tint (applied to sprite.modulate in-game)
@export var ship_color: Color = Color.WHITE

# Starting weapon id (StringName matching WeaponData.id)
@export var starting_weapon: StringName = &"pistol"

# Unlock cost in meta Credits (0 = free/default)
@export var unlock_cost: int = 0

# Weapon slot limit for this ship
@export var weapon_slots: int = 2

# UpgradeData ids that get 3x weight in between-wave offers
@export var preferred_upgrades: Array[StringName] = []

# UpgradeData ids that are never offered to this character (between-wave or shop)
@export var excluded_upgrades: Array[StringName] = []

# If non-empty, only weapons whose id is in this list can be equipped by this character.
# Other weapons will be blocked in add_weapon() and appear rarely in the shop.
@export var allowed_weapon_ids: Array[StringName] = []

# WeaponData.WeaponClass int -> damage multiplier delta (e.g. 0.2 = +20%, -0.15 = -15%)
@export var weapon_class_bonuses: Dictionary = {}

# Passive HP regeneration
@export var hp_regen: float = 0.35             # HP/s recovered passively at all times

# Rechargeable shield
@export var shield_max: float = 0.0           # 0 = no shield
@export var shield_regen_rate: float = 20.0    # HP/s while recharging
@export var shield_regen_delay: float = 3.0    # seconds after last hit before regen starts

# Offensive starting stats
@export var lifesteal: float = 0.0            # fraction of damage dealt returned as HP
@export var crit_chance: float = 0.0          # additive probability of a critical hit (0–1)
@export var crit_multiplier: float = 2.0      # damage multiplier on a crit (default 2.0)
@export var emp_radius: float = 0.0           # AoE stun radius on kill (pixels)

# Defensive starting stats
@export var dodge_chance: float = 0.0         # chance to fully evade an incoming hit (0–1)
@export var damage_block_chance: float = 0.0  # chance to completely negate an incoming hit (0–1)
@export var on_kill_heal: float = 0.0         # HP healed on each kill

# Economy starting stats
@export var scrap_bonus_chance: float = 0.0   # additive chance to double scrap drops (0–1)

# Weapon performance starting stats
@export var fire_rate_bonus: float = 0.0      # additive fire-rate multiplier applied to all weapons (+0.2 = +20%)
@export var damage_bonus: float = 0.0         # additive damage multiplier applied to all weapons (+0.2 = +20%)

# Per-ship stat caps — override the global defaults in Player.STAT_CAPS_DEFAULT.
# Keys match the string names used by Player._stat_cap() (e.g. "max_health", "move_speed").
# Leave empty to use global defaults for all stats.
@export var stat_caps: Dictionary = {}

# Per-ship upgrade efficiency multipliers. Maps UpgradeData.StatKey (int) -> float.
# 0.7 = this ship receives 70% of the normal stat_delta for that key.
# Discrete keys (BOUNCE_COUNT, CHAIN_COUNT, FORK_COUNT) are unaffected.
@export var upgrade_efficiency: Dictionary = {}
