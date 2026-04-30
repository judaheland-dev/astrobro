extends Node
class_name LaserRingPassive

## Passive ability: a rotating energy ring that deals contact damage to nearby enemies.
## Two stacks spawn rings at different radii, each dealing damage independently.

const RING_DAMAGE: float = 10.0
const RING_TICK_RATE: float = 0.5
const RING_ROTATION_SPEED: float = 1.05  # radians/sec (~60 deg/s)
const RING_BASE_RADIUS: float = 90.0
const RING_RADIUS_STEP: float = 40.0     # each additional ring is further out

var _player: Node = null
var _ring_visual: Node2D = null
var _area: Area2D = null
var _tick_timer: float = 0.0

func setup(player: Node) -> void:
	_player = player
	# Determine index (0-based) among already-present LaserRingPassive siblings
	var ring_index := 0
	for child in player.get_children():
		if child is LaserRingPassive and child != self:
			ring_index += 1
	var radius := RING_BASE_RADIUS + ring_index * RING_RADIUS_STEP
	_build_ring(radius)

func _build_ring(radius: float) -> void:
	# --- Visual: rotating sprite ---
	_ring_visual = Node2D.new()
	_ring_visual.name = "LaserRingVisual"
	_player.add_child(_ring_visual)

	var spr := Sprite2D.new()
	var spr_path := "res://assets/sprites/shield2.png"
	if not ResourceLoader.exists(spr_path):
		spr_path = "res://assets/sprites/shield1.png"
	if ResourceLoader.exists(spr_path):
		spr.texture = load(spr_path)
	var scale_factor := radius / 50.0
	spr.scale = Vector2(scale_factor, scale_factor)
	spr.modulate = Color(1.0, 0.35, 0.05, 0.6)
	_ring_visual.add_child(spr)

	# --- Damage area ---
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask  = 2   # enemies only (layer 2)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	col.shape = shape
	_area.add_child(col)
	_player.add_child(_area)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# Rotate the visual ring
	if is_instance_valid(_ring_visual):
		_ring_visual.rotation += RING_ROTATION_SPEED * delta

	# Damage tick
	_tick_timer += delta
	if _tick_timer >= RING_TICK_RATE:
		_tick_timer = 0.0
		_deal_damage()

func _deal_damage() -> void:
	if not is_instance_valid(_area):
		return
	var hit_any := false
	for body in _area.get_overlapping_bodies():
		if is_instance_valid(body) and body.has_method("take_damage"):
			body.take_damage(RING_DAMAGE)
			hit_any = true
	if hit_any:
		_pulse_ring()

func _pulse_ring() -> void:
	if not is_instance_valid(_ring_visual) or _ring_visual.get_child_count() == 0:
		return
	var spr := _ring_visual.get_child(0)
	if not spr is Sprite2D:
		return
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 1.0, 0.05)
	tw.tween_property(spr, "modulate:a", 0.6, 0.2)
