extends Node
## Mine Layer passive: drops a proximity mine at the player's position every
## MINE_INTERVAL seconds. Mines arm after 1.5 s then detonate on enemy contact.

const MINE_INTERVAL: float = 5.0
const MINE_DAMAGE: float = 55.0
const MINE_AOE_RADIUS: float = 80.0

var _player: Player
var _fire_timer: float = MINE_INTERVAL * 0.4  # first mine comes a bit sooner

func setup(player: Player) -> void:
	_player = player

func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.is_physics_processing():
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = MINE_INTERVAL
		_drop_mine()

func _drop_mine() -> void:
	var mine_path := "res://scenes/game/weapons/MineProjectile.gd"
	if not ResourceLoader.exists(mine_path):
		return
	var mine_scr: Script = load(mine_path)
	var mine: Area2D = mine_scr.new() as Area2D
	if mine == null:
		return
	get_tree().current_scene.add_child(mine)
	mine.call("setup", MINE_DAMAGE, MINE_AOE_RADIUS, _player)
	mine.global_position = _player.global_position
