extends Node

## GameManager - global run state, scene transitions, mode config.
## Persists between scenes. All other systems read from this.

const FONT_PATH := "res://assets/fonts/kenvector_future.ttf"

# Returns the Kenney font if available, otherwise null (Godot uses default).
static func kenney_font() -> FontFile:
	if ResourceLoader.exists(FONT_PATH):
		return load(FONT_PATH)
	return null

enum RunMode {
	WAVE_SURVIVAL,
	HORDE_DEFENSE,
	PVP_OVERLORD,
}

enum Difficulty {
	SUPER_EASY,
	EASY,
	NORMAL,
	HARD,
	SUPER_HARD,
}

enum GameState {
	MENU,
	PLAYING,
	BETWEEN_WAVES,
	PAUSED,
	GAME_OVER,
	WIN,
}

var current_mode: RunMode = RunMode.WAVE_SURVIVAL
var current_state: GameState = GameState.MENU
var current_difficulty: Difficulty = Difficulty.NORMAL
var player_count: int = 1
var selected_characters: Array[StringName] = []

# Run stats (reset each run)
var run_wave: int = 0
var run_coins_earned: int = 0

# Banned enemy IDs (e.g. Epic Neutralizer suppresses brutes)
var banned_enemy_ids: Array[StringName] = []

# Terrain event flags
var solar_flare_active: bool = false
var solar_flare_intensity: float = 1.0  # 1.0=inactive, 1.3/1.5/2.0 for weak/medium/strong
var ion_storm_active: bool = false

# Debug / test harness flags (set by TestHarness; cleared after Game loads)
var debug_mode: bool = false
var debug_start_wave: int = 1   # 1 = normal start from wave 1
var debug_god_mode: bool = false

signal state_changed(new_state: GameState)

# Callbacks registered by Game.gd so GameManager can pause/unpause gameplay
# without ever touching get_tree().paused (which breaks GUI picking in Godot 4).
var _gameplay_pause_cb: Callable = Callable()
var _gameplay_unpause_cb: Callable = Callable()

func register_gameplay_pause_callbacks(on_pause: Callable, on_unpause: Callable) -> void:
	_gameplay_pause_cb = on_pause
	_gameplay_unpause_cb = on_unpause

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_state(new_state: GameState) -> void:
	current_state = new_state
	state_changed.emit(new_state)

func start_run(mode: RunMode, characters: Array[StringName], players: int) -> void:
	current_mode = mode
	selected_characters = characters
	player_count = players
	run_wave = 0
	run_coins_earned = 0
	banned_enemy_ids.clear()
	solar_flare_active = false
	solar_flare_intensity = 1.0
	ion_storm_active = false
	set_state(GameState.PLAYING)
	get_tree().change_scene_to_file("res://scenes/game/Game.tscn")

func go_to_main_menu() -> void:
	set_state(GameState.MENU)
	get_tree().change_scene_to_file("res://scenes/main_menu/MainMenu.tscn")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var sfx := "res://assets/audio/sfx_pause.ogg"
		if ResourceLoader.exists(sfx):
			AudioManager.play_sfx(load(sfx), -4.0, 1.0)
		match current_state:
			GameState.PLAYING:
				set_state(GameState.PAUSED)
				if _gameplay_pause_cb.is_valid():
					_gameplay_pause_cb.call()
			GameState.PAUSED:
				set_state(GameState.PLAYING)
				if _gameplay_unpause_cb.is_valid():
					_gameplay_unpause_cb.call()
			GameState.GAME_OVER, GameState.WIN:
				go_to_main_menu()
