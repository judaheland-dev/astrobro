extends Resource
class_name RangedAttackData

## Data sub-resource that defines how a ranged enemy fires projectiles.
## Attach to EnemyData.ranged_attack. All fields optional - sensible defaults apply.

enum FireMode {
	SINGLE,           # one projectile aimed at target
	SPREAD,           # multiple projectiles fanned around aim direction
	ROTATING_VOLLEY,  # 4 projectiles evenly spaced in all directions (ignores target dir)
	BURST_3,          # 3 shots fired with a short delay between each
}

# --- Fire pattern ---
@export var fire_mode: FireMode = FireMode.SINGLE
@export var fire_cooldown: float = 2.5       # seconds between attacks (overrides RANGED_COOLDOWN)
@export var projectile_count: int = 3        # used by SPREAD: total projectiles per shot
@export var spread_angle_deg: float = 40.0   # total arc for SPREAD fan (degrees)
@export var burst_interval: float = 0.12     # seconds between shots in BURST_3

# --- Projectile behavior ---
@export var projectile_speed: float = 280.0
@export var damage_multiplier: float = 0.6   # scales contact_damage; same default as old hardcoded value
@export var homing_strength: float = 0.0     # turn rate toward nearest player (rad/s); 0 = straight
@export var homing_lifetime: float = 0.0     # seconds before homing disengages; 0 = never

# --- On-hit status effects ---
@export var on_hit_slow_factor: float = 0.0    # player move_speed multiplied by this; 0 = no slow
@export var on_hit_slow_duration: float = 2.0
@export var on_hit_dot_dps: float = 0.0        # damage per second as acid/burn ticks; 0 = none
@export var on_hit_dot_ticks: int = 6          # how many 0.5s ticks to apply
