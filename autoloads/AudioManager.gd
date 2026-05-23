extends Node

## AudioManager - music and SFX bus routing with pooled AudioStreamPlayers.

const MUSIC_BUS: StringName = &"Master"
const SFX_BUS: StringName = &"Master"
const CROSSFADE_DURATION: float = 2.5

# Two players A/B for crossfading; _active_player is the one currently audible.
var _player_a: AudioStreamPlayer = null
var _player_b: AudioStreamPlayer = null
var _active_player: AudioStreamPlayer = null   # the one playing the current track
var _inactive_player: AudioStreamPlayer = null # the one fading out / idle

var _music_loop: bool = false
var _stream_cache: Dictionary = {}     # path:String -> AudioStream
var _sfx_pool: Array[AudioStreamPlayer] = []
const SFX_POOL_SIZE: int = 16

var _crossfade_tween: Tween = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_player_a = AudioStreamPlayer.new()
	_player_a.bus = MUSIC_BUS
	_player_a.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player_a)
	_player_a.finished.connect(_on_music_finished.bind(_player_a))

	_player_b = AudioStreamPlayer.new()
	_player_b.bus = MUSIC_BUS
	_player_b.process_mode = Node.PROCESS_MODE_ALWAYS
	_player_b.volume_db = -80.0
	add_child(_player_b)
	_player_b.finished.connect(_on_music_finished.bind(_player_b))

	_active_player   = _player_a
	_inactive_player = _player_b

	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_sfx_pool.append(p)

func _current_music_player() -> AudioStreamPlayer:
	return _active_player

func play_music(stream: AudioStream, loop: bool = true, crossfade: bool = true) -> void:
	if stream == null:
		return
	if _active_player.stream == stream and _active_player.playing:
		return
	_music_loop = loop

	if crossfade and _active_player.playing:
		_crossfade_to(stream)
	else:
		# Instant switch (first play or when nothing is playing)
		if _crossfade_tween:
			_crossfade_tween.kill()
			_crossfade_tween = null
		_inactive_player.stop()
		_inactive_player.volume_db = -80.0
		_active_player.stream = stream
		_active_player.volume_db = 0.0
		_active_player.stream_paused = false
		_active_player.play(0.0)

func _crossfade_to(stream: AudioStream) -> void:
	# Kill any ongoing crossfade and immediately finish it
	if _crossfade_tween:
		_crossfade_tween.kill()
		_crossfade_tween = null
		# Snap both players to their destination volumes
		_active_player.volume_db = 0.0
		_inactive_player.stop()
		_inactive_player.volume_db = -80.0

	# The current active player becomes the one fading out.
	var fade_out: AudioStreamPlayer = _active_player
	var fade_in:  AudioStreamPlayer = _inactive_player

	# Swap roles
	_active_player   = fade_in
	_inactive_player = fade_out

	fade_in.stream = stream
	fade_in.volume_db = -80.0
	fade_in.stream_paused = false
	fade_in.play(0.0)

	_crossfade_tween = create_tween()
	_crossfade_tween.set_parallel(true)
	_crossfade_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_crossfade_tween.tween_property(fade_in,  "volume_db", 0.0,   CROSSFADE_DURATION).set_trans(Tween.TRANS_SINE)
	_crossfade_tween.tween_property(fade_out, "volume_db", -80.0, CROSSFADE_DURATION).set_trans(Tween.TRANS_SINE)
	_crossfade_tween.chain().tween_callback(func():
		fade_out.stop()
		fade_out.volume_db = -80.0
		_crossfade_tween = null
	)

func _on_music_finished(player: AudioStreamPlayer) -> void:
	if player == _active_player and _music_loop and player.stream != null:
		player.play(0.0)

func pause_music() -> void:
	_active_player.stream_paused = true
	_inactive_player.stream_paused = true

func resume_music() -> void:
	_active_player.stream_paused = false

func stop_music() -> void:
	_music_loop = false
	if _crossfade_tween:
		_crossfade_tween.kill()
		_crossfade_tween = null
	_player_a.stream_paused = false
	_player_a.stop()
	_player_a.volume_db = 0.0
	_player_b.stream_paused = false
	_player_b.stop()
	_player_b.volume_db = -80.0
	_active_player   = _player_a
	_inactive_player = _player_b

func play_music_from_path(path: String, loop: bool = true, crossfade: bool = true) -> void:
	if path.is_empty():
		return
	if not _stream_cache.has(path):
		if not ResourceLoader.exists(path):
			return
		_stream_cache[path] = load(path)
	play_music(_stream_cache[path], loop, crossfade)

func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale
			p.play()
			return
	# All slots busy - use slot 0 (oldest, overwrite is acceptable for SFX)
	_sfx_pool[0].stream = stream
	_sfx_pool[0].volume_db = volume_db
	_sfx_pool[0].pitch_scale = pitch_scale
	_sfx_pool[0].play()

func play_ui_click() -> void:
	var path := "res://assets/audio/sfx_twoTone.ogg"
	if ResourceLoader.exists(path):
		play_sfx(load(path), -4.0, 1.2)
