extends CharacterBody2D
class_name Player

## Player - movement, health, XP, weapon management, and co-op device routing.

signal health_changed(current: float, maximum: float)
signal died()
signal took_damage()
signal xp_gained(new_xp: int, threshold: int)
signal leveled_up(new_level: int)
signal weapon_fired()
signal scrap_changed(amount: int)

@export var player_index: int = 0       # 0 = P1, 1 = P2
@export var character_data: CharacterData = null

# Runtime stats (may be modified by upgrades)
var max_health: float = 100.0
var current_health: float = 100.0
var move_speed: float = 200.0
var armor: float = 0.0
var xp_multiplier: float = 1.0
var coin_multiplier: float = 1.0
var lifesteal: float = 0.0

# In-run currency (resets each run; spent in weapon shop)
var scrap: int = 0
var scrap_bonus_chance: float = 0.0   # set by Rogue passive

# Damage blocking (Tank passive sets this)
var damage_block_chance: float = 0.0
var _block_cooldown: float = 0.0

# XP / leveling
var xp: int = 0
var level: int = 1
var xp_threshold: int = 100
var pending_upgrades: int = 0  # picks banked this wave; consumed by BetweenWaveUI

# Weapons
var weapons: Array[Node] = []           # BaseWeapon children
var active_weapon_index: int = 0

# Thrust bob
var _thrust_bob_time: float = 0.0
var _is_moving: bool = false

# Thruster animation
# Frame ranges reserved: 0-6 = base, 7-12 = boosted (speed upgrades), 13-19 = max (reserved)
var _thruster: Sprite2D = null
var _thruster_textures: Array = []
var _thruster_tick: float = 0.0
var _thruster_frame_idx: int = 0
const _THRUSTER_FPS: float = 12.0

# Damage overlay (set damage_sprite_set = 1/2/3 before adding to scene tree)
var damage_sprite_set: int = 1
var _damage_overlay: Sprite2D = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	collision_layer = 1   # player on layer 1
	collision_mask  = 3   # collide with layer 1 (walls) and layer 2 (enemies)
	if character_data:
		_apply_character_data()
	current_health = max_health
	health_changed.emit(current_health, max_health)
	_spawn_passive()
	sprite.rotation_degrees = 90.0
	_setup_thruster()
	_setup_damage_overlay()

func _apply_character_data() -> void:
	max_health      = character_data.max_health
	move_speed      = character_data.move_speed
	armor           = character_data.armor
	xp_multiplier   = character_data.xp_multiplier
	coin_multiplier = character_data.coin_multiplier
	if character_data.sprite:
		sprite.texture = character_data.sprite

func _spawn_passive() -> void:
	if not character_data:
		return
	var cid := str(character_data.id)
	var cap := cid[0].to_upper() + cid.substr(1)
	var path := "res://scenes/game/player/abilities/%sPassive.gd" % cap
	if ResourceLoader.exists(path):
		var script: Script = load(path)
		var passive: Node = script.new()
		add_child(passive)
		passive.call("setup", self)

func add_scrap(amount: int) -> void:
	var actual := amount
	if scrap_bonus_chance > 0.0 and randf() < scrap_bonus_chance:
		actual *= 2
	scrap += actual
	scrap_changed.emit(scrap)

func _physics_process(delta: float) -> void:
	var move_dir := InputManager.get_move_dir(player_index)
	velocity = move_dir * move_speed
	move_and_slide()

	var aim_dir := InputManager.get_aim_dir(player_index, global_position)
	if aim_dir != Vector2.ZERO:
		rotation = aim_dir.angle()

	if InputManager.is_firing(player_index):
		_fire_all_weapons(aim_dir)

	# Thrust bob: subtle sideways oscillation when moving
	_is_moving = velocity.length_squared() > 1.0
	if _is_moving:
		_thrust_bob_time += delta * 8.0
		sprite.position.y = sin(_thrust_bob_time) * 2.5
	else:
		_thrust_bob_time = 0.0
		sprite.position.y = move_toward(sprite.position.y, 0.0, delta * 20.0)

	_update_thruster(delta)

	if _block_cooldown > 0.0:
		_block_cooldown -= delta

func _fire_all_weapons(aim_dir: Vector2) -> void:
	weapon_fired.emit()
	for weapon in weapons:
		if weapon.has_method("try_fire"):
			weapon.try_fire(aim_dir)

# --- Health ---

func take_damage(amount: float) -> void:
	if damage_block_chance > 0.0 and _block_cooldown <= 0.0 and randf() < damage_block_chance:
		_block_cooldown = 8.0
		_flash_damage()
		return
	var effective := maxf(0.0, amount - armor)
	current_health -= effective
	took_damage.emit()
	_flash_damage()
	var hurt_sfx := "res://assets/audio/sfx_lose.ogg"
	if ResourceLoader.exists(hurt_sfx):
		AudioManager.play_sfx(load(hurt_sfx), -4.0, 0.7)
	health_changed.emit(current_health, max_health)
	_update_damage_overlay(current_health / max_health)
	if current_health <= 0.0:
		_die()

func _flash_damage() -> void:
	# Red flash + scale punch + invincibility blink
	sprite.modulate = Color(3.0, 0.1, 0.1, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.35)
	tween.tween_property(self, "scale", Vector2.ONE * 1.18, 0.07).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_SINE)
	# Blink during invincibility window
	var blink := create_tween()
	blink.set_loops(3)
	blink.tween_property(sprite, "modulate:a", 0.2, 0.08)
	blink.tween_property(sprite, "modulate:a", 1.0, 0.08)

func heal(amount: float) -> void:
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)
	_update_damage_overlay(current_health / max_health)
	if amount > 2.0:
		var sfx := "res://assets/audio/sfx_heal.ogg"
		if ResourceLoader.exists(sfx):
			AudioManager.play_sfx(load(sfx), -6.0, randf_range(0.95, 1.05))

func _die() -> void:
	died.emit()
	set_physics_process(false)
	var death_sfx := "res://assets/audio/sfx_player_death.ogg"
	if ResourceLoader.exists(death_sfx):
		AudioManager.play_sfx(load(death_sfx), 0.0, 0.9)
	# Death: spin out and fade
	var tween := create_tween()
	tween.set_parallel(true)
	sprite.modulate = Color(2.0, 0.8, 0.1, 1.0)
	tween.tween_property(sprite, "modulate", Color(1.0, 0.2, 0.0, 0.0), 0.6)
	tween.tween_property(sprite, "rotation", sprite.rotation + TAU, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(hide)

# --- XP ---

func gain_xp(amount: int) -> void:
	var gained := int(amount * xp_multiplier)
	xp += gained
	xp_gained.emit(xp, xp_threshold)
	while xp >= xp_threshold:
		xp -= xp_threshold
		level += 1
		xp_threshold = int(xp_threshold * 1.4)
		pending_upgrades += 1
		leveled_up.emit(level)
		var sfx := "res://assets/audio/sfx_levelup.ogg"
		if ResourceLoader.exists(sfx):
			AudioManager.play_sfx(load(sfx), 0.0, 1.0)

# --- Upgrades ---

func apply_upgrade(data: UpgradeData) -> void:
	for key in data.stat_deltas:
		var delta: float = data.stat_deltas[key]
		match key:
			UpgradeData.StatKey.MAX_HEALTH:
				max_health += delta
				current_health = minf(current_health + delta, max_health)
			UpgradeData.StatKey.MOVE_SPEED:
				move_speed += delta
			UpgradeData.StatKey.ARMOR:
				armor += delta
			UpgradeData.StatKey.XP_MULTIPLIER:
				xp_multiplier += delta
			UpgradeData.StatKey.COIN_MULTIPLIER:
				coin_multiplier += delta
			UpgradeData.StatKey.LIFESTEAL:
				lifesteal += delta
			UpgradeData.StatKey.DAMAGE_BLOCK_CHANCE:
				damage_block_chance += delta
			UpgradeData.StatKey.SCRAP_BONUS_CHANCE:
				scrap_bonus_chance += delta
			UpgradeData.StatKey.INSTANT_HEAL:
				heal(delta)
			UpgradeData.StatKey.DAMAGE, UpgradeData.StatKey.FIRE_RATE, \
			UpgradeData.StatKey.PROJECTILE_SPEED, UpgradeData.StatKey.RANGE, \
			UpgradeData.StatKey.SPREAD:
				for weapon in weapons:
					if weapon.has_method("apply_stat_delta"):
						weapon.apply_stat_delta(key, delta)
	if data.passive_script != "":
		if ResourceLoader.exists(data.passive_script):
			var passive_scr: Script = load(data.passive_script)
			var passive_node: Node = passive_scr.new()
			add_child(passive_node)
			if passive_node.has_method("setup"):
				passive_node.call("setup", self)
# --- Weapons ---

func add_weapon(weapon_node: Node) -> void:
	var slots := character_data.weapon_slots if character_data else 2
	if weapons.size() >= slots:
		return
	var wdata = weapon_node.get("weapon_data")
	if character_data and wdata != null:
		var bonus: float = character_data.weapon_class_bonuses.get(int(wdata.weapon_class), 0.0)
		weapon_node.set("damage_multiplier", 1.0 + bonus)
	weapons.append(weapon_node)
	add_child(weapon_node)

func get_weapon_count() -> int:
	return weapons.size()

func _setup_thruster() -> void:
	for i in 20:
		var p := "res://assets/sprites/fire%02d.png" % i
		_thruster_textures.append(load(p) if ResourceLoader.exists(p) else null)
	_thruster = Sprite2D.new()
	# position at engine (~50px behind ship center); offset moves flame pivot to its base
	# so the flame extends fully behind the hull
	_thruster.position = Vector2(-50.0, 0.0)
	_thruster.offset = Vector2(0.0, 20.0)  # pivot at base of flame, tip trails behind
	_thruster.rotation_degrees = -90.0
	_thruster.scale = Vector2(0.9, 0.9)
	_thruster.z_index = -1
	_thruster.visible = false
	add_child(_thruster)
	if _thruster_textures.size() > 0 and _thruster_textures[0] != null:
		_thruster.texture = _thruster_textures[0]

func _setup_damage_overlay() -> void:
	var ship_num := clampi(damage_sprite_set, 1, 3)
	_damage_overlay = Sprite2D.new()
	_damage_overlay.rotation_degrees = 90.0
	_damage_overlay.z_index = 1
	_damage_overlay.visible = false
	add_child(_damage_overlay)
	# Pre-load damage textures into metadata for quick access
	var textures: Array = []
	for lvl in [1, 2, 3]:
		var p := "res://assets/sprites/playerShip%d_damage%d.png" % [ship_num, lvl]
		textures.append(load(p) if ResourceLoader.exists(p) else null)
	_damage_overlay.set_meta("textures", textures)

func _update_damage_overlay(hp_frac: float) -> void:
	if _damage_overlay == null:
		return
	var textures: Array = _damage_overlay.get_meta("textures", [])
	if textures.is_empty():
		return
	if hp_frac > 0.66:
		_damage_overlay.visible = false
	elif hp_frac > 0.33:
		_damage_overlay.texture = textures[0]
		_damage_overlay.visible = textures[0] != null
	elif hp_frac > 0.10:
		_damage_overlay.texture = textures[1]
		_damage_overlay.visible = textures[1] != null
	else:
		_damage_overlay.texture = textures[2]
		_damage_overlay.visible = textures[2] != null

func _update_thruster(delta: float) -> void:
	if _thruster == null:
		return
	_thruster.visible = _is_moving
	if not _is_moving:
		return
	_thruster_tick += delta
	if _thruster_tick < 1.0 / _THRUSTER_FPS:
		return
	_thruster_tick -= 1.0 / _THRUSTER_FPS
	# Auto-select frame tier based on current move_speed
	var t_start: int
	var t_end: int
	if move_speed >= 320.0:
		t_start = 13; t_end = 19
	elif move_speed >= 250.0:
		t_start = 7; t_end = 12
	else:
		t_start = 0; t_end = 6
	if _thruster_frame_idx < t_start or _thruster_frame_idx > t_end:
		_thruster_frame_idx = t_start
	else:
		_thruster_frame_idx += 1
		if _thruster_frame_idx > t_end:
			_thruster_frame_idx = t_start
	var tex = _thruster_textures[_thruster_frame_idx] if _thruster_textures.size() > _thruster_frame_idx else null
	if tex != null:
		_thruster.texture = tex
