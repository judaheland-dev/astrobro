extends Node
class_name GameMode

## GameMode - abstract base class for game modes.
## Subclasses override the virtual methods below.

var wave_manager: WaveManager = null
var players: Array[Player] = []
var is_finished: bool = false

signal run_ended(victory: bool)

func setup(wm: WaveManager, player_list: Array[Player]) -> void:
	wave_manager = wm
	players = player_list
	wm.wave_cleared.connect(_on_wave_cleared)
	wm.all_waves_cleared.connect(_on_all_waves_cleared)
	for p in players:
		p.died.connect(_on_player_died.bind(p))

# Called when a wave finishes. Override to add mode-specific behaviour.
func _on_wave_cleared(_wave_number: int) -> void:
	pass

# Called when all waves in the list are done.
func _on_all_waves_cleared() -> void:
	_end_run(true)

# Called when a player dies.
func _on_player_died(_player: Player) -> void:
	var all_dead := true
	for p in players:
		if p.is_physics_processing():
			all_dead = false
			break
	if all_dead:
		_end_run(false)

func _end_run(victory: bool) -> void:
	if is_finished:
		return
	is_finished = true
	run_ended.emit(victory)
