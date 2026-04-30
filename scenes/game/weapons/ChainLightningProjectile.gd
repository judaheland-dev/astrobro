extends BaseProjectile
class_name ChainLightningProjectile

## Chain-lightning projectile.  On hitting an enemy it searches for the nearest
## unvisited enemy within CHAIN_SEARCH_RADIUS and spawns a new link aimed at it,
## drawing a jagged Line2D arc between the two positions.  The `piercing` field
## (inherited from BaseProjectile / set via setup()) is used as the remaining
## jump count: each link decrements it by one.

const CHAIN_SEARCH_RADIUS: float = 400.0
const CHAIN_SPRITE_PATH: String  = "res://assets/sprites/laserBlue16.png"
const CHAIN_SPRITE_FALLBACK: String = "res://assets/sprites/laserBlue01.png"

var damage_falloff: float = 0.7
var _visited_enemies: Array[Node] = []

func _ready() -> void:
	super._ready()
	# Tint the auto-generated trail sprite to electric yellow
	var trail := get_node_or_null("Trail")
	if trail:
		trail.modulate = Color(1.0, 1.0, 0.3)

func _on_body_entered(body: Node) -> void:
	if body in _hit_entities:
		return
	_hit_entities.append(body)

	# Skip enemies already struck by this chain
	if body in _visited_enemies:
		return

	if not body.has_method("take_damage"):
		return

	_visited_enemies.append(body)

	var actual_damage := damage
	if shooter != null and "crit_chance" in shooter and shooter.crit_chance > 0.0:
		if randf() < shooter.crit_chance:
			actual_damage *= shooter.crit_multiplier
	body.take_damage(actual_damage)
	_spawn_impact_flash()
	if shooter != null and "lifesteal" in shooter and shooter.lifesteal > 0.0:
		if shooter.has_method("heal"):
			shooter.heal(actual_damage * shooter.lifesteal)

	if piercing > 0:
		_try_chain_jump()

	queue_free()

func _try_chain_jump() -> void:
	# Find nearest unvisited enemy within search radius
	var nearest: Node = null
	var nearest_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e in _visited_enemies:
			continue
		if not e.is_physics_processing():
			continue
		var d := global_position.distance_squared_to(e.global_position)
		if d < nearest_d and d <= CHAIN_SEARCH_RADIUS * CHAIN_SEARCH_RADIUS:
			nearest_d = d
			nearest = e

	if nearest == null:
		return

	var arc_start := global_position
	var arc_end   := nearest.global_position

	# Draw a jagged lightning arc between the two positions
	var scene_root := get_tree().current_scene
	var line := Line2D.new()
	line.add_point(arc_start)
	line.add_point(arc_start.lerp(arc_end, 0.33) + Vector2(randf_range(-22.0, 22.0), randf_range(-22.0, 22.0)))
	line.add_point(arc_start.lerp(arc_end, 0.66) + Vector2(randf_range(-22.0, 22.0), randf_range(-22.0, 22.0)))
	line.add_point(arc_end)
	line.width = 3.0
	line.default_color = Color(1.0, 1.0, 0.3, 1.0)
	line.z_index = 5
	scene_root.add_child(line)
	var line_tw := line.create_tween()
	line_tw.tween_property(line, "modulate:a", 0.0, 0.28)
	line_tw.tween_callback(line.queue_free)

	# Spawn the next link projectile
	var next_proj := ChainLightningProjectile.new()
	next_proj.collision_layer = 0
	next_proj.collision_mask  = 10
	next_proj.damage_falloff  = damage_falloff
	next_proj._visited_enemies = _visited_enemies   # shared reference
	next_proj.shooter = shooter

	var spr := Sprite2D.new()
	var spr_path := CHAIN_SPRITE_PATH if ResourceLoader.exists(CHAIN_SPRITE_PATH) else CHAIN_SPRITE_FALLBACK
	if ResourceLoader.exists(spr_path):
		spr.texture = load(spr_path)
		spr.rotation_degrees = 90.0
	spr.scale = Vector2(0.55, 0.55)
	spr.modulate = Color(1.0, 1.0, 0.3)
	next_proj.add_child(spr)

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12.0, 6.0)
	col.shape = shape
	next_proj.add_child(col)

	var dir := (arc_end - arc_start).normalized()
	var jump_range := arc_start.distance_to(arc_end) + 60.0

	scene_root.add_child(next_proj)
	next_proj.global_position = arc_start
	next_proj.setup(dir, damage * damage_falloff, 1500.0, jump_range, piercing - 1)
