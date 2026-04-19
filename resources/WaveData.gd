extends Resource
class_name WaveData

## Data resource defining a single wave's composition.

@export_category("Wave Config")
@export var wave_number: int = 1
@export var is_boss_wave: bool = false

# Array of enemy resource paths and their counts
@export var enemy_pool: Array[EnemyData] = []
@export var enemy_counts: Array[int] = []   # parallel to enemy_pool

# Spawn timing
@export var spawn_interval: float = 0.5     # seconds between each spawn
@export var initial_delay: float = 1.0      # delay before first spawn

# Duration cap for wave (0 = wait until all enemies dead)
@export var time_limit: float = 0.0

# Rewards on wave clear
@export var bonus_coins: int = 0
@export var bonus_xp: int = 0
