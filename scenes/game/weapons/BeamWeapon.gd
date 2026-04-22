extends BaseWeapon
class_name BeamWeapon

## BeamWeapon - persistent auto-aiming laser beam.
## Finds the nearest enemy within range, locks on, and deals continuous DPS.
## Does not fire projectiles; try_fire() is a no-op.

var _target: Node = null
var _beam_line: Line2D = null
var _glow_line: Line2D = null
var _sfx_player: AudioStreamPlayer = null
var _damage_accum: float = 0.0
const _DAMAGE_TICK: float = 0.08   # apply damage every N seconds of beam contact

# Track beam contact time for visual pulse
var _beam_active: bool = false

func _ready() -> void:
	super._ready()
	# Main beam line
	_beam_line = Line2D.new()
	_beam_line.width = 5.0
	_beam_line.default_color = weapon_data.projectile_modulate if weapon_data else Color(0.2, 1.0, 0.8, 1.0)
	_beam_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_beam_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_beam_line.add_point(Vector2.ZERO)
	_beam_line.add_point(Vector2.ZERO)
	_beam_line.visible = false
	_beam_line.z_index = 3
	add_child(_beam_line)

	# Glow overlay (wider, low alpha)
	_glow_line = Line2D.new()
	_glow_line.width = 14.0
	var glow_color := weapon_data.projectile_modulate if weapon_data else Color(0.2, 1.0, 0.8, 1.0)
	glow_color.a = 0.2
	_glow_line.default_color = glow_color
	_glow_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_glow_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_glow_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_glow_line.add_point(Vector2.ZERO)
	_glow_line.add_point(Vector2.ZERO)
	_glow_line.visible = false
	_glow_line.z_index = 2
	add_child(_glow_line)

	# Looping SFX player
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "Master"
	_sfx_player.volume_db = -14.0
	var hum_path := "res://assets/audio/sfx_beam_hum.ogg"
	if ResourceLoader.exists(hum_path):
		_sfx_player.stream = load(hum_path)
	add_child(_sfx_player)

func _process(delta: float) -> void:
	# BaseWeapon._process handles _fire_cooldown; no need to call try_fire.
	_update_beam(delta)

func _update_beam(delta: float) -> void:
	# Find nearest valid enemy within weapon range
	var nearest: Node = null
	var nearest_d := INF
	var beam_range := range if weapon_data == null else weapon_data.range

	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.is_physics_processing():
			continue
		var d := global_position.distance_to(e.global_position)
		if d < beam_range and d < nearest_d:
			nearest_d = d
			nearest = e

	if nearest == null or not is_instance_valid(nearest):
		_deactivate_beam()
		return

	_target = nearest

	# Update line endpoints in local space (point 0 = weapon origin, point 1 = target)
	var local_end := to_local(_target.global_position)
	_beam_line.set_point_position(0, Vector2.ZERO)
	_beam_line.set_point_position(1, local_end)
	_glow_line.set_point_position(0, Vector2.ZERO)
	_glow_line.set_point_position(1, local_end)
	_beam_line.visible = true
	_glow_line.visible = true

	# Visual pulse: vary beam width slightly each frame for "energy" feel
	var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.015)
	_beam_line.width = 5.0 * pulse
	_glow_line.width = 14.0 * pulse

	# Looping SFX
	if not _sfx_player.playing and _sfx_player.stream != null:
		_sfx_player.play()

	# Damage accumulation
	var dmg_per_sec := damage * damage_multiplier * passive_multiplier
	_damage_accum += dmg_per_sec * delta
	if _damage_accum >= dmg_per_sec * _DAMAGE_TICK:
		if is_instance_valid(_target) and _target.has_method("take_damage"):
			_target.take_damage(_damage_accum)
			# Lifesteal
			var shooter_node := get_parent()
			if shooter_node != null and "lifesteal" in shooter_node and shooter_node.lifesteal > 0.0:
				if shooter_node.has_method("heal"):
					shooter_node.heal(_damage_accum * shooter_node.lifesteal)
		_damage_accum = 0.0

	_beam_active = true

func _deactivate_beam() -> void:
	if _beam_active:
		_beam_active = false
		_damage_accum = 0.0
	if _beam_line:
		_beam_line.visible = false
	if _glow_line:
		_glow_line.visible = false
	if _sfx_player and _sfx_player.playing:
		_sfx_player.stop()
	_target = null

# Beam weapon fires automatically; override try_fire to be a no-op.
func try_fire(_aim_dir: Vector2) -> void:
	pass
