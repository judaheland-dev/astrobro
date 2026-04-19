extends Node

## MetaProgression - persistent save data between runs.
## Backed by ResourceSaver/ResourceLoader to user://save.tres

const SAVE_PATH: String = "user://save.tres"

var _data: MetaSaveData = null

func _ready() -> void:
	_load()

func _load() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded = ResourceLoader.load(SAVE_PATH)
		if loaded is MetaSaveData:
			_data = loaded
			return
	_data = MetaSaveData.new()

func save() -> void:
	ResourceSaver.save(_data, SAVE_PATH)

# --- Coins ---

func get_coins() -> int:
	return _data.coins

func add_coins(amount: int) -> void:
	_data.coins += amount
	save()

func spend_coins(amount: int) -> bool:
	if _data.coins < amount:
		return false
	_data.coins -= amount
	save()
	return true

# --- Unlocks ---

func is_character_unlocked(id: StringName) -> bool:
	return id in _data.unlocked_characters

func unlock_character(id: StringName) -> void:
	if id not in _data.unlocked_characters:
		_data.unlocked_characters.append(id)
		save()

func is_weapon_unlocked(id: StringName) -> bool:
	return id in _data.unlocked_weapons

func unlock_weapon(id: StringName) -> void:
	if id not in _data.unlocked_weapons:
		_data.unlocked_weapons.append(id)
		save()

# --- Persistent stat upgrades ---

func get_persistent_stat(stat: StringName) -> float:
	return _data.persistent_stats.get(stat, 0.0)

func add_persistent_stat(stat: StringName, delta: float) -> void:
	_data.persistent_stats[stat] = _data.persistent_stats.get(stat, 0.0) + delta
	save()

func reset_all() -> void:
	_data = MetaSaveData.new()
	save()
