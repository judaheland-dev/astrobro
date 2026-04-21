extends Node
## DecoyDronePassive - spawns a fake ship at 150 px from the player that draws
## enemy aggro. Has 60 HP. Auto-respawns after 10 s when destroyed.

const DECOY_HP: float = 60.0
const RESPAWN_DELAY: float = 10.0
const ORBIT_OFFSET: float = 150.0

var _player: Player
var _decoy: Node2D = null

func setup(player: Player) -> void:
	_player = player
	player.died.connect(_on_player_died)
	_spawn_decoy()

func _exit_tree() -> void:
	if is_instance_valid(_decoy):
		_game().call("unregister_extra_target", _decoy)
		_decoy.queue_free()

func _spawn_decoy() -> void:
	if not is_instance_valid(_player):
		return
	var game := _game()
	if game == null:
		return
	var decoy := _DecoyNode.new(_player, self)
	get_tree().current_scene.add_child(decoy)
	decoy.global_position = _player.global_position + Vector2(ORBIT_OFFSET, 0.0)
	_decoy = decoy
	game.call("register_extra_target", decoy)

func _on_decoy_destroyed() -> void:
	if is_instance_valid(_decoy):
		_game().call("unregister_extra_target", _decoy)
	_decoy = null
	# Respawn after delay
	var t := get_tree().create_timer(RESPAWN_DELAY)
	t.timeout.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			_spawn_decoy()
	)

func _on_player_died() -> void:
	if is_instance_valid(_decoy):
		_game().call("unregister_extra_target", _decoy)
		_decoy.queue_free()
		_decoy = null

func _game() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene


## Inner class: the actual decoy node placed in the world.
class _DecoyNode extends Node2D:
	var current_health: float = DECOY_HP
	var _sprite: Sprite2D
	var _passive: Node

	func _init(player: Player, passive: Node) -> void:
		_passive = passive
		# Build a simple triangular sprite resembling a small ship
		const SZ: int = 24
		var img := Image.create(SZ, SZ, false, Image.FORMAT_RGBA8)
		for y in SZ:
			for x in SZ:
				# Triangle pointing right
				var nx := float(x) / SZ
				var ny := float(y) / SZ - 0.5
				if nx > 0.1 and abs(ny) < nx * 0.45:
					img.set_pixel(x, y, Color(0.7, 0.7, 0.85, 1.0))
		_sprite = Sprite2D.new()
		_sprite.texture = ImageTexture.create_from_image(img)
		_sprite.z_index = 2
		add_child(_sprite)

	func take_damage(amount: float) -> void:
		current_health -= amount
		# Hit flash
		_sprite.modulate = Color(3.0, 0.4, 0.4, 1.0)
		var t := create_tween()
		t.tween_property(_sprite, "modulate", Color.WHITE, 0.2)
		if current_health <= 0.0:
			_die()

	func _die() -> void:
		_sprite.modulate = Color(2.0, 1.0, 0.2, 1.0)
		var t := create_tween()
		t.tween_property(_sprite, "modulate:a", 0.0, 0.3)
		t.tween_callback(queue_free)
		if is_instance_valid(_passive) and _passive.has_method("_on_decoy_destroyed"):
			_passive.call("_on_decoy_destroyed")
