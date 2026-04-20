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

var _fire_cooldown: float = 0.0
var _projectile_parent: Node = null   # set by Game so projectiles don't rotate with player

func _ready() -> void:
	if weapon_data:
		damage           = weapon_data.damage
		fire_rate        = weapon_data.fire_rate
		projectile_speed = weapon_data.projectile_speed
		range            = weapon_data.range
		spread           = weapon_data.spread
		projectile_count = weapon_data.projectile_count
		piercing         = weapon_data.piercing

func _process(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

func try_fire(aim_dir: Vector2) -> void:
	if _fire_cooldown > 0.0 or weapon_data == null:
		return
	if aim_dir == Vector2.ZERO:
		return

	_fire_cooldown = 1.0 / fire_rate
	if weapon_data.fire_sfx:
		AudioManager.play_sfx(weapon_data.fire_sfx, -6.0, randf_range(0.9, 1.1))
	else:
		var sfx_path := "res://assets/audio/sfx_laser1.ogg"
		if ResourceLoader.exists(sfx_path):
			AudioManager.play_sfx(load(sfx_path), -6.0, randf_range(0.9, 1.1))
	_spawn_projectiles(aim_dir)

func _spawn_projectiles(base_dir: Vector2) -> void:
	var parent := _projectile_parent if _projectile_parent else get_tree().current_scene
	for i in projectile_count:
		var spread_angle := randf_range(-spread * 0.5, spread * 0.5)
		var dir := base_dir.rotated(spread_angle).normalized()

		var proj := BaseProjectile.new()
		proj.collision_layer = 0   # projectiles have no layer of their own
		proj.collision_mask  = 2   # only detect enemies on layer 2

		# Visible sprite - pick laser by ammo type, fall back to colored rect
		var sprite := Sprite2D.new()
		var laser_path := _laser_sprite_for_ammo_type()
		if ResourceLoader.exists(laser_path):
			sprite.texture = load(laser_path)
			# PNG is drawn pointing up; rotate 90° so it aligns with rightward travel (angle=0)
			sprite.rotation_degrees = 90.0
		else:
			var img := Image.create(12, 4, false, Image.FORMAT_RGBA8)
			img.fill(Color(1.0, 0.9, 0.3))
			sprite.texture = ImageTexture.create_from_image(img)
		proj.add_child(sprite)

		# Collision - rockets get a slightly larger hitbox
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		var is_rocket := weapon_data != null and weapon_data.ammo_type == WeaponData.AmmoType.ROCKET
		shape.size = Vector2(30.0, 8.0) if is_rocket else Vector2(10.0, 4.0)
		col.shape = shape
		proj.add_child(col)

		proj.shooter = get_parent()
		parent.add_child(proj)
		proj.global_position = global_position
		proj.setup(dir, damage, projectile_speed, range, piercing)

func apply_stat_delta(key: UpgradeData.StatKey, delta: float) -> void:
	match key:
		UpgradeData.StatKey.DAMAGE:          damage           += delta
		UpgradeData.StatKey.FIRE_RATE:       fire_rate        += delta
		UpgradeData.StatKey.PROJECTILE_SPEED: projectile_speed += delta
		UpgradeData.StatKey.RANGE:           range            += delta
		UpgradeData.StatKey.SPREAD:          spread            = maxf(0.0, spread + delta)

func _laser_sprite_for_ammo_type() -> String:
	if weapon_data == null:
		return "res://assets/sprites/laserBlue01.png"
	match weapon_data.ammo_type:
		WeaponData.AmmoType.LASER:  return "res://assets/sprites/laserGreen01.png"
		WeaponData.AmmoType.ROCKET: return "res://assets/sprites/laserRed01.png"
		_:                          return "res://assets/sprites/laserBlue01.png"
