extends Resource
class_name EnemyData

## Data resource defining an enemy type.

enum AIType {
	CHASER,          # beelines for nearest target
	RANGED,          # keeps distance, fires projectiles
	TANK,            # slow, high HP
	FAST,            # low HP, very fast
	EXPLODER,        # rushes then explodes on death
	ELITE,           # boss: chases and fires projectiles; phase 2 at 50% HP
	SENTINEL,        # stationary turret; fires rotating volley
	ELITE_RANGED,    # boss: kiting ranged attacker; phase 2 fires homing acid shots
	ELITE_SUMMONER,  # boss: summons minions periodically; phase 2 fires rotating volley
	ELITE_PHASE,     # boss: very slow tank in phase 1; becomes fast + fires homing in phase 2
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var sprite: Texture2D = null
@export var sprite_scale: Vector2 = Vector2.ONE

@export var ai_type: AIType = AIType.CHASER
@export var max_health: float = 30.0
@export var move_speed: float = 80.0
@export var contact_damage: float = 10.0  # damage dealt when touching player
@export var contact_damage_cooldown: float = 1.0  # seconds between contact hits
@export var armor: float = 0.0
@export var xp_drop: int = 5
@export var coin_drop_chance: float = 0.15  # 0-1 probability of dropping a coin
@export var coin_drop_amount: int = 1
@export var death_sfx: AudioStream = null

# Optional ranged attack configuration; null = use legacy hardcoded fire behavior
@export var ranged_attack: RangedAttackData = null
