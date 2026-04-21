extends GameMode
class_name WaveSurvivalMode

## WaveSurvivalMode - survive all waves. Between each wave show level-up / shop.

signal show_between_wave_ui(wave_number: int)

func _on_wave_cleared(wave_number: int) -> void:
	super._on_wave_cleared(wave_number)
	# Pause spawning and surface the between-wave UI
	show_between_wave_ui.emit(wave_number)
