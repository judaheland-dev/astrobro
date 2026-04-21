extends Resource
class_name WeaponData

## Data resource defining a weapon's behaviour and stats.

enum AmmoType {
	BULLET,
	LASER,
	ROCKET,
	MINE,
	ORBITAL,
}

enum WeaponClass {
	RAPID,       # fast-firing, lower damage per shot
	PRECISION,   # slow, high damage, long range
	SPREAD,      # wide-angle burst or multi-shot
	HEAVY,       # high damage, slow, tankier projectiles
	EXPLOSIVE,  # AoE / piercing, slow fire rate
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D = null

@export var ammo_type: AmmoType = AmmoType.BULLET
@export var weapon_class: WeaponClass = WeaponClass.RAPID
@export var shop_cost: int = 50
@export var damage: float = 10.0
@export var fire_rate: float = 2.0        # shots per second
@export var projectile_speed: float = 400.0
@export var range: float = 600.0          # pixels before projectile expires
@export var spread: float = 0.0           # radians of random spread per shot
@export var projectile_count: int = 1     # bullets per shot (for shotgun-style)
@export var piercing: int = 0             # how many enemies a projectile passes through

# Scene to instance as the projectile (must extend BaseProjectile)
@export var projectile_scene: PackedScene = null

# Optional custom fire sound; if null BaseWeapon falls back to sfx_laser1.ogg
@export var fire_sfx: AudioStream = null

# Unlock cost in meta coins (0 = free/default)
@export var unlock_cost: int = 0

# Rarity tier - controls how early in a run this weapon can appear in the shop
@export var rarity: UpgradeData.Rarity = UpgradeData.Rarity.COMMON

# Optional custom projectile sprite; if null BaseWeapon falls back to ammo-type default
@export var projectile_sprite: Texture2D = null
