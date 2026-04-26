extends GameMode
class_name OverlordMode

## OverlordMode - asymmetric PVP. Player 1 controls a ship, Player 2 (the
## Overlord) purchases and deploys enemies. Endless waves until ship dies.

signal show_between_wave_ui(wave_number: int)
signal show_overlord_shop(wave_number: int)

var overlord_state: OverlordState = OverlordState.new()
var _wave_timer: float = 0.0
var _wave_time_limit: float = 90.0
var _wave_active: bool = false
var _current_wave: int = 0
var active_overlord_enemies: int = 0
var _wave_grace_timer: float = 0.0  # prevents instant wave-end before Overlord deploys

func setup(wm: WaveManager, player_list: Array[Player]) -> void:
	wave_manager = wm
	players = player_list
	# We do NOT connect wave_cleared from WaveManager because the Overlord
	# controls spawning, not WaveManager. We track completion ourselves.
	for p in players:
		p.died.connect(_on_player_died.bind(p))

func start_wave(wave_number: int) -> void:
	_current_wave = wave_number
	_wave_active = true
	_wave_timer = _wave_time_limit
	_wave_grace_timer = 5.0  # 5s grace before wave can end from empty loadout
	active_overlord_enemies = 0
	overlord_state.start_wave()
	var sfx := "res://assets/audio/sfx_wave_start.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -4.0, 1.0)

func on_overlord_enemy_died() -> void:
	active_overlord_enemies -= 1
	if active_overlord_enemies < 0:
		active_overlord_enemies = 0
	_check_wave_complete()

func _check_wave_complete() -> void:
	if not _wave_active:
		return
	if _wave_grace_timer > 0.0:
		return
	# Wave ends when all deployed enemies are dead AND no more to deploy
	if active_overlord_enemies <= 0 and overlord_state.get_total_remaining() <= 0:
		_finish_wave()

func process_wave(delta: float) -> void:
	## Called from OverlordController._process each frame during active wave.
	if not _wave_active:
		return
	_wave_timer -= delta
	if _wave_grace_timer > 0.0:
		_wave_grace_timer -= delta
	if _wave_timer <= 0.0:
		_finish_wave()
		return
	# Also check if all enemies are dead and none left to deploy
	_check_wave_complete()

func get_wave_timer() -> float:
	return maxf(0.0, _wave_timer)

func _finish_wave() -> void:
	if not _wave_active:
		return
	_wave_active = false
	var sfx := "res://assets/audio/sfx_wave_clear.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), 0.0, 1.0)
	# Award wave-clear scrap to ship player
	var bonus: int = 20 + _current_wave * 5
	for p in players:
		p.add_scrap(bonus)
	overlord_state.end_wave(_current_wave)
	# Show Overlord shop first, then ship player gets their turn
	show_overlord_shop.emit(_current_wave)

func is_wave_active() -> bool:
	return _wave_active

func get_wave_multiplier() -> float:
	return 1.0 + (_current_wave * 0.15)

func get_speed_multiplier() -> float:
	return 1.0 + (_current_wave * 0.02)
