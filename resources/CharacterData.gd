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

# WeaponData.WeaponClass int -> damage multiplier delta (e.g. 0.2 = +20%, -0.15 = -15%)
@export var weapon_class_bonuses: Dictionary = {}

# Rechargeable shield
@export var shield_max: float = 0.0           # 0 = no shield
@export var shield_regen_rate: float = 20.0    # HP/s while recharging
@export var shield_regen_delay: float = 3.0    # seconds after last hit before regen starts
