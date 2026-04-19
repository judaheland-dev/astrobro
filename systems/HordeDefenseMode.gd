extends GameMode
class_name HordeDefenseMode

## HordeDefenseMode - like WaveSurvival but enemies also target a Base objective.
## Game ends immediately if the base is destroyed.

signal show_between_wave_ui(wave_number: int)

var base_objective: Node = null  # set by Game.tscn after setup

func setup(wm: WaveManager, player_list: Array[Player]) -> void:
	super.setup(wm, player_list)

func set_base(base: Node) -> void:
	base_objective = base
	if base.has_signal("destroyed"):
		base.destroyed.connect(_on_base_destroyed)
	# Register base as an additional target for enemies
	if wave_manager:
		var targets: Array[Node] = []
		for p in players:
			targets.append(p)
		if base_objective:
			targets.append(base_objective)
		wave_manager.register_targets(targets)

func _on_base_destroyed() -> void:
	_end_run(false)

func _on_wave_cleared(wave_number: int) -> void:
	show_between_wave_ui.emit(wave_number)
