extends Node
## Gunship active - Overclock: forces supercritical heat (+80% damage) for 4 s. 10 s cooldown.
## Overrides GunshipPassive's heat curve with a higher ceiling and adds orbiting fire embers
## for the duration. Screen shake and orange rings on activation.

const DURATION: float = 4.0
const COOLDOWN: float = 10.0
const OVERCLOCK_MULT: float = 1.8   # supercritical: 80% bonus vs normal max of 30%

var _player: Player
var _active: bool = false
var _duration_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _was_on_cooldown: bool = false
var _embers: Array = []
var _ember_angle: float = 0.0

func setup(player: Player) -> void:
	_player = player
	player.ability_cooldown_changed.emit(0.0)

func _exit_tree() -> void:
	for em in _embers:
		if is_instance_valid(em):
			em.queue_free()
	_embers.clear()

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	if InputManager.is_boosting(_player.player_index) and not _active and _cooldown_timer <= 0.0:
		_activate()

	if _active:
		_duration_timer -= delta
		_ember_angle += 2.8 * delta
		_update_embers()
		if _duration_timer > 0.0:
			_set_multiplier(OVERCLOCK_MULT)
		else:
			_active = false
			_cooldown_timer = COOLDOWN
			_clear_embers()
	elif _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
		var ratio := _cooldown_timer / COOLDOWN
		_player.ability_cooldown_changed.emit(ratio)
		if _was_on_cooldown and _cooldown_timer <= 0.0:
			_play_ready_sfx()

	_was_on_cooldown = _cooldown_timer > 0.0 or _active

func _activate() -> void:
	_clear_embers()  # safety clear
	_active = true
	_duration_timer = DURATION
	_set_multiplier(OVERCLOCK_MULT)
	_add_trauma(0.20)
	# Orange-hot ship flash
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(3.0, 1.2, 0.05), 0.0)
	t.tween_property(_player.sprite, "modulate", _player.base_sprite_color, 0.5)
	# Fire rings
	_spawn_ring(Color(1.0, 0.55, 0.0, 0.75), 52.0, 0.38)
	_spawn_ring(Color(1.0, 0.35, 0.0, 0.45), 52.0, 0.55)
	# Spawn orbiting embers
	_spawn_embers()
	var sfx := "res://assets/audio/sfx_levelup.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -4.0, 1.2)
	_player.ability_cooldown_changed.emit(1.0)

func _spawn_embers() -> void:
	const EM_SZ := 12
	for i in 3:
		var img := Image.create(EM_SZ, EM_SZ, false, Image.FORMAT_RGBA8)
		var cx := EM_SZ * 0.5
		for y in EM_SZ:
			for x in EM_SZ:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, cx))
				if d < EM_SZ * 0.45:
					var alpha := 1.0 - d / (EM_SZ * 0.45) * 0.4
					img.set_pixel(x, y, Color(1.0, 0.4 + i * 0.1, 0.05, alpha))
		var em := Sprite2D.new()
		em.texture = ImageTexture.create_from_image(img)
		em.z_index = _player.z_index + 1
		if is_inside_tree():
			get_tree().current_scene.add_child(em)
		_embers.append(em)

func _update_embers() -> void:
	if not is_instance_valid(_player):
		return
	var count := _embers.size()
	for i in count:
		if is_instance_valid(_embers[i]):
			var angle := _ember_angle + i * TAU / count
			_embers[i].global_position = _player.global_position + Vector2(cos(angle), sin(angle)) * 55.0

func _clear_embers() -> void:
	for em in _embers:
		if is_instance_valid(em):
			var t := em.create_tween()
			t.tween_property(em, "modulate:a", 0.0, 0.25)
			t.tween_callback(em.queue_free)
	_embers.clear()

func _set_multiplier(mult: float) -> void:
	for w in _player.weapons:
		if w.has_method("try_fire"):
			w.set("passive_multiplier", mult)

func _spawn_ring(color: Color, radius: float, duration: float) -> void:
	if not is_inside_tree() or not is_instance_valid(_player):
		return
	var ring := ColorRect.new()
	ring.color = color
	var sz := radius * 2.0
	ring.size = Vector2(sz, sz)
	ring.pivot_offset = ring.size * 0.5
	ring.position = _player.global_position - ring.size * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(ring)
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(3.5, 3.5), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, duration)
	rt.chain().tween_callback(ring.queue_free)

func _play_ready_sfx() -> void:
	var sfx := "res://assets/audio/sfx_ability_activate.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -8.0, 0.9)

func _add_trauma(amount: float) -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene and scene.has_method("_add_trauma"):
		scene._add_trauma(amount)
