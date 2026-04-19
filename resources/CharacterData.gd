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

# Starting weapon id (StringName matching WeaponData.id)
@export var starting_weapon: StringName = &"pistol"

# Unlock cost in meta coins (0 = free/default)
@export var unlock_cost: int = 0

# Passive ability scene (can be null for no ability)
@export var ability_scene: PackedScene = null
