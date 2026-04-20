extends Resource
class_name MetaSaveData

## Serializable resource that holds all persistent meta-progression data.

@export var coins: int = 0
@export var unlocked_characters: Array[StringName] = [&"scout", &"sniper"]
@export var unlocked_weapons: Array[StringName] = [&"pistol"]
