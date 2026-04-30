extends Node2D
class_name BaseWeapon

## BaseWeapon - fire-rate timer, projectile spawning, upgrade application.

@export var weapon_data: WeaponData = null

# Runtime stats (copied from weapon_data, modified by upgrades)
var damage: float = 10.0
var fire_rate: float = 2.0
var projectile_speed: float = 400.0
var range: float = 600.0
var spread: float = 0.0
var projectile_count: int = 1
var piercing: int = 0
var bounce_count: int = 0
var chain_count: int = 0
var chain_radius: float = 200.0
var fork_count: int = 0
var armor_pen: float = 0.0
var knockback_force: float = 0.0
var port_index: int = 0   # which hull port this weapon occupies (see Player.PORT_DATA)

var _fire_cooldown: float = 0.0
var _base_fire_rate: float = 2.0      # fire_rate at equip time, used for cap calculation
var _projectile_parent: Node = null   # set by Game so projectiles don't rotate with player

# Class bonus set at equip time (permanent this run)
var damage_multiplier: float = 1.0
# Passive ability modifier (temporary, set by passive scripts)
var passive_multiplier: float = 1.0

func _ready() -> void:
	if weapon_data:
		damage           = weapon_data.damage
		fire_rate        = weapon_data.fire_rate
		_base_fire_rate  = weapon_data.fire_rate
		projectile_speed = weapon_data.projectile_speed
		range            = weapon_data.range
		spread           = weapon_data.spread
		projectile_count = weapon_data.projectile_count
		piercing         = weapon_data.piercing
		bounce_count     = weapon_data.bounce_count
		chain_count      = weapon_data.chain_count
		chain_radius     = weapon_data.chain_radius
		fork_count       = weapon_data.fork_count
		armor_pen        = weapon_data.armor_pen
		knockback_force  = weapon_data.knockback_force

func _process(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

func try_fire(aim_dir: Vector2) -> void:
	if _fire_cooldown > 0.0 or weapon_data == null:
		return
	if aim_dir == Vector2.ZERO:
		return
	# Strong solar flare (intensity 2.0) jams laser weapons; weaker tiers boost them instead
	if weapon_data.ammo_type == WeaponData.AmmoType.LASER and GameManager.solar_flare_intensity >= 2.0:
		return

	_fire_cooldown = 1.0 / fire_rate
	if weapon_data.fire_sfx:
		AudioManager.play_sfx(weapon_data.fire_sfx, -6.0, randf_range(0.9, 1.1))
	else:
		var sfx_path := _sfx_for_weapon()
		if ResourceLoader.exists(sfx_path):
			AudioManager.play_sfx(load(sfx_path), -6.0, randf_range(0.9, 1.1))
	# Apply fire arc offset (e.g. PI = rear-facing weapon / mine)
	var fire_dir := aim_dir
	if weapon_data.fire_arc_offset != 0.0:
		fire_dir = aim_dir.rotated(weapon_data.fire_arc_offset)
	# Mines are stationary; spawn a single mine at player position, skip the projectile loop
	if weapon_data.ammo_type == WeaponData.AmmoType.MINE:
		_spawn_mine(fire_dir)
		return
	_spawn_projectiles(fire_dir, weapon_data.ammo_type == WeaponData.AmmoType.CHAIN)

func _spawn_projectiles(base_dir: Vector2, is_chain: bool = false) -> void:
	var parent := _projectile_parent if _projectile_parent else get_tree().current_scene
	var chain_script: Script = null
	if is_chain:
		var cp := "res://scenes/game/weapons/ChainLightningProjectile.gd"
		if ResourceLoader.exists(cp):
			chain_script = load(cp)
	for i in projectile_count:
		var spread_angle := randf_range(-spread * 0.5, spread * 0.5)
		var dir := base_dir.rotated(spread_angle).normalized()

		var proj: BaseProjectile = chain_script.new() if chain_script != null else BaseProjectile.new()
		proj.collision_layer = 0   # projectiles have no layer of their own
		proj.collision_mask  = 10  # enemies (layer 2) + interceptable missiles (layer 4)

		# Visible sprite - use weapon-specific sprite, fall back to ammo-type default
		var sprite := Sprite2D.new()
		if weapon_data != null and weapon_data.projectile_sprite != null:
			sprite.texture = weapon_data.projectile_sprite
			sprite.rotation_degrees = 90.0
		else:
			var laser_path := _laser_sprite_for_ammo_type()
			if ResourceLoader.exists(laser_path):
				sprite.texture = load(laser_path)
				# PNG is drawn pointing up; rotate 90° so it aligns with rightward travel (angle=0)
				sprite.rotation_degrees = 90.0
			else:
				var img := Image.create(12, 4, false, Image.FORMAT_RGBA8)
				img.fill(Color(1.0, 0.9, 0.3))
				sprite.texture = ImageTexture.create_from_image(img)

		# Apply per-weapon visual overrides
		if weapon_data != null:
			sprite.scale = weapon_data.projectile_scale
			sprite.modulate = weapon_data.projectile_modulate
		proj.add_child(sprite)

		# Collision - use per-weapon hitbox size from WeaponData
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		if weapon_data != null:
			shape.size = weapon_data.projectile_hitbox_size
		else:
			shape.size = Vector2(10.0, 4.0)
		col.shape = shape
		proj.add_child(col)

		proj.shooter = get_parent()
		if weapon_data != null:
			proj.aoe_radius = weapon_data.aoe_radius
			proj.explode_on_expiry = weapon_data.explode_on_expiry
			proj.emit_exhaust_trail = weapon_data.emit_exhaust_trail
			proj.projectile_color = weapon_data.projectile_modulate
			if weapon_data.on_hit_dot_dps > 0.0:
				proj.on_hit_dot_dps = weapon_data.on_hit_dot_dps
				proj.on_hit_dot_ticks = weapon_data.on_hit_dot_ticks if weapon_data.on_hit_dot_ticks > 0 else 6
			# Homing toward enemies (player homing missiles)
			if weapon_data.is_homing:
				proj.enemy_homing_strength = weapon_data.homing_strength
			# New mechanics
			proj.bounce_count    = bounce_count
			proj.chain_count     = chain_count
			proj.chain_radius    = chain_radius
			proj.fork_count      = fork_count
			proj.armor_pen       = armor_pen
			proj.knockback_force = knockback_force
		parent.add_child(proj)
		# Tint the procedural trail to match the projectile colour
		var trail := proj.get_node_or_null("Trail")
		if trail and weapon_data != null:
			trail.modulate = weapon_data.projectile_modulate
		proj.global_position = global_position
		var flare_mult := GameManager.solar_flare_intensity if weapon_data != null and weapon_data.ammo_type == WeaponData.AmmoType.LASER else 1.0
		proj.setup(dir, damage * damage_multiplier * passive_multiplier * flare_mult, projectile_speed, range, piercing)

func _spawn_mine(_fire_dir: Vector2) -> void:
	var parent := _projectile_parent if _projectile_parent else get_tree().current_scene
	var mine_script_path := "res://scenes/game/weapons/MineProjectile.gd"
	if not ResourceLoader.exists(mine_script_path):
		return
	var mine_script: Script = load(mine_script_path)
	var mine: Node = mine_script.new()
	parent.add_child(mine)
	mine.global_position = global_position
	mine.call("setup", damage * damage_multiplier * passive_multiplier, 80.0, get_parent())

func apply_stat_delta(key: UpgradeData.StatKey, delta: float) -> void:
	match key:
		UpgradeData.StatKey.DAMAGE:          damage           += delta
		UpgradeData.StatKey.FIRE_RATE:
			fire_rate += delta
			fire_rate  = minf(fire_rate, _base_fire_rate * 3.0)
		UpgradeData.StatKey.PROJECTILE_SPEED: projectile_speed += delta
		UpgradeData.StatKey.RANGE:           range            += delta
		UpgradeData.StatKey.SPREAD:          spread            = maxf(0.0, spread + delta)
		UpgradeData.StatKey.BOUNCE_COUNT:    bounce_count      = maxi(0, bounce_count + int(delta))
		UpgradeData.StatKey.CHAIN_COUNT:     chain_count       = maxi(0, chain_count + int(delta))
		UpgradeData.StatKey.FORK_COUNT:      fork_count        = maxi(0, fork_count + int(delta))
		UpgradeData.StatKey.ARMOR_PEN:       armor_pen         += delta
		UpgradeData.StatKey.KNOCKBACK_FORCE: knockback_force   += delta

func _sfx_for_weapon() -> String:
	if weapon_data == null:
		return "res://assets/audio/sfx_laser1.ogg"
	if weapon_data.ammo_type == WeaponData.AmmoType.ROCKET:
		return "res://assets/audio/sfx_rocket_fire.ogg"
	if weapon_data.weapon_class == WeaponData.WeaponClass.SPREAD:
		return "res://assets/audio/sfx_shotgun.ogg"
	if weapon_data.ammo_type == WeaponData.AmmoType.CHAIN:
		return "res://assets/audio/sfx_sniper.ogg"
	if weapon_data.weapon_class == WeaponData.WeaponClass.PRECISION \
			or weapon_data.ammo_type == WeaponData.AmmoType.LASER:
		return "res://assets/audio/sfx_sniper.ogg"
	return "res://assets/audio/sfx_laser1.ogg"

func _laser_sprite_for_ammo_type() -> String:
	if weapon_data == null:
		return "res://assets/sprites/laserBlue01.png"
	match weapon_data.ammo_type:
		WeaponData.AmmoType.LASER:  return "res://assets/sprites/laserGreen01.png"
		WeaponData.AmmoType.ROCKET: return "res://assets/sprites/laserRed01.png"
		_:                          return "res://assets/sprites/laserBlue01.png"
