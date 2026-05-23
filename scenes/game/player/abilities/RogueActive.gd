extends Node
## Rogue active - Vanish: 1.5x speed for 3 s with guaranteed double scrap. 10 s cooldown.
## Vanish upgrades: 90% dodge chance while active (near-untouchable), a dark stealth-field
## overlay on the ship, and a purple ring on both entry and exit.

const BOOST_FACTOR: float = 1.5
const BOOST_DURATION: float = 3.0
const BOOST_RECHARGE: float = 10.0
const ROGUE_BASE_SCRAP_CHANCE: float = 0.3   # matches RoguePassive
const VANISH_DODGE: float = 0.9              # near-untouchable during vanish

var _player: Player
var _was_on_cooldown: bool = false
var _prev_boost_active: bool = false
var _saved_dodge: float = 0.0
var _vanish_dodge_active: bool = false
var _vanish_overlay: Node2D = null

func setup(player: Player) -> void:
	_player = player
	player.boost_factor   = BOOST_FACTOR
	player.boost_duration = BOOST_DURATION
	player.boost_recharge = BOOST_RECHARGE
	player.ability_cooldown_changed.emit(0.0)

func _exit_tree() -> void:
	if _vanish_overlay != null and is_instance_valid(_vanish_overlay):
		_vanish_overlay.queue_free()

func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return

	var boost_active := _player._boost_timer > 0.0

	# Detect state transitions
	if not _prev_boost_active and boost_active:
		_on_vanish_start()
	elif _prev_boost_active and not boost_active:
		_on_vanish_end()

	_prev_boost_active = boost_active

	# Per-frame effects while vanishing
	if boost_active:
		_player.scrap_bonus_chance = 1.0
		_player.dodge_chance = VANISH_DODGE
	else:
		_player.scrap_bonus_chance = ROGUE_BASE_SCRAP_CHANCE
		if _vanish_dodge_active:
			_player.dodge_chance = _saved_dodge
			_vanish_dodge_active = false

	var ratio := _player._boost_cooldown / BOOST_RECHARGE
	_player.ability_cooldown_changed.emit(ratio)
	if _was_on_cooldown and ratio <= 0.0:
		_play_ready_sfx()
	_was_on_cooldown = ratio > 0.0

func _on_vanish_start() -> void:
	_add_trauma(0.15)
	# Dark purple entry ring
	_spawn_ring(Color(0.2, 0.0, 0.5, 0.75), 55.0, 0.40)
	# Save and override dodge
	_saved_dodge = _player.dodge_chance
	_player.dodge_chance = VANISH_DODGE
	_vanish_dodge_active = true
	# Spawn stealth-field overlay on the ship
	_spawn_vanish_overlay()

func _on_vanish_end() -> void:
	# Restore dodge
	if _vanish_dodge_active:
		_player.dodge_chance = _saved_dodge
		_vanish_dodge_active = false
	# Dismiss stealth overlay
	_dismiss_vanish_overlay()
	# Re-appearance flash (bright pop then settle)
	var t := _player.create_tween()
	t.tween_property(_player.sprite, "modulate", Color(_player.base_sprite_color.r * 2.0,
		_player.base_sprite_color.g * 1.5, _player.base_sprite_color.b * 3.0, 1.0), 0.0)
	t.tween_property(_player.sprite, "modulate", _player.base_sprite_color, 0.3)
	_spawn_ring(Color(0.5, 0.2, 1.0, 0.55), 55.0, 0.35)
	_add_trauma(0.10)

func _spawn_vanish_overlay() -> void:
	if _vanish_overlay != null and is_instance_valid(_vanish_overlay):
		_vanish_overlay.queue_free()
	_vanish_overlay = Node2D.new()
	_player.add_child(_vanish_overlay)
	# Soft purple bubble
	const SZ := 100
	var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
	var ctr := SZ * 0.5
	for y in SZ:
		for x in SZ:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(ctr, ctr))
			if d < SZ * 0.46:
				var alpha := (1.0 - d / (SZ * 0.46)) * 0.22
				img.set_pixel(x, y, Color(0.35, 0.0, 0.75, alpha))
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	_vanish_overlay.add_child(spr)
	# Fade in
	_vanish_overlay.modulate = Color(1, 1, 1, 0)
	var t := _vanish_overlay.create_tween()
	t.tween_property(_vanish_overlay, "modulate:a", 1.0, 0.25)
	# Gentle pulse
	var pt := spr.create_tween()
	pt.set_loops()
	pt.tween_property(spr, "modulate:a", 0.6, 0.5).set_trans(Tween.TRANS_SINE)
	pt.tween_property(spr, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)

func _dismiss_vanish_overlay() -> void:
	if _vanish_overlay != null and is_instance_valid(_vanish_overlay):
		var node := _vanish_overlay
		_vanish_overlay = null
		var t := node.create_tween()
		t.tween_property(node, "modulate:a", 0.0, 0.3)
		t.tween_callback(node.queue_free)

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
