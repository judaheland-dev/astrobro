extends CharacterBody2D
class_name Player

## Player - movement, health, XP, weapon management, and co-op device routing.

signal health_changed(current: float, maximum: float)
signal shield_changed(current: float, maximum: float)
signal died()
signal took_damage()
signal xp_gained(new_xp: int, threshold: int)
signal leveled_up(new_level: int)
signal weapon_fired()
signal scrap_changed(amount: int)
signal ability_cooldown_changed(ratio: float)

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

# All upgrades acquired this run (level-up picks + shop modules)
var acquired_upgrades: Array[UpgradeData] = []

# Rechargeable shield
var shield_max: float = 0.0
var current_shield: float = 0.0
var shield_regen_rate: float = 20.0
var shield_regen_delay: float = 3.0
var _shield_regen_timer: float = 0.0
var _shield_ring: Sprite2D = null

# Damage blocking (Tank passive sets this)
var damage_block_chance: float = 0.0
var _block_cooldown: float = 0.0

# Critical hits and EMP
var crit_chance: float = 0.0
var crit_multiplier: float = 2.0
var emp_radius: float = 0.0

# Afterburner
var boost_factor: float = 0.0         # speed multiplier while boosting (0 = no boost)
var boost_duration: float = 0.7       # seconds per burst
var _boost_timer: float = 0.0
var _boost_cooldown: float = 0.0
var boost_recharge: float = 6.0

# Reflective shield
var reflective_shield: bool = false

# Status effects from enemy projectiles
var _slow_factor: float = 1.0
var _slow_timer: float = 0.0
var _base_move_speed: float = 0.0
var _dot_dps: float = 0.0
var _dot_ticks_left: int = 0
var _dot_timer: float = 0.0

# XP / leveling
var xp: int = 0
var level: int = 1
var xp_threshold: int = 100
var pending_upgrades: int = 0  # picks banked this wave; consumed by BetweenWaveUI

# Weapons
# Port positions in player-local space (player faces +X; wings along Y).
# Index order chosen so first weapon goes to the nose (centered).
const PORT_DATA: Array = [
	{"pos": Vector2(10.0,  -34.0), "mount_rot":  90.0, "is_rear": false, "label": "Port Fwd"},
	{"pos": Vector2(10.0,   34.0), "mount_rot":  90.0, "is_rear": false, "label": "Stbd Fwd"},
	{"pos": Vector2(32.0,    0.0), "mount_rot":  90.0, "is_rear": false, "label": "Nose"},
	{"pos": Vector2(-30.0,   0.0), "mount_rot": -90.0, "is_rear": true,  "label": "Tail"},
	{"pos": Vector2(-18.0, -28.0), "mount_rot": -90.0, "is_rear": true,  "label": "Port Rear"},
	{"pos": Vector2(-18.0,  28.0), "mount_rot": -90.0, "is_rear": true,  "label": "Stbd Rear"},
]
# Default assignment sequence: Nose first, then wings, then rear ports.
const _DEFAULT_PORT_ORDER: Array = [2, 0, 1, 3, 4, 5]

var weapons: Array[Node] = []           # BaseWeapon children
var active_weapon_index: int = 0
var _weapon_visuals: Array[Sprite2D] = []  # wing-mounted hull sprites

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
	collision_mask  = 10  # collide with layer 1 (walls), layer 2 (enemies), layer 4 (interceptable missiles)
	if character_data:
		_apply_character_data()
	current_health = max_health
	health_changed.emit(current_health, max_health)
	_spawn_passive()
	_spawn_active()
	sprite.rotation_degrees = 90.0
	_setup_thruster()
	_setup_damage_overlay()
	_setup_shield_ring()

func _apply_character_data() -> void:
	max_health         = character_data.max_health
	move_speed         = character_data.move_speed
	armor              = character_data.armor
	xp_multiplier      = character_data.xp_multiplier
	coin_multiplier    = character_data.coin_multiplier
	shield_max         = character_data.shield_max
	shield_regen_rate  = character_data.shield_regen_rate
	shield_regen_delay = character_data.shield_regen_delay
	current_shield     = shield_max
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

func _spawn_active() -> void:
	if not character_data:
		return
	var cid := str(character_data.id)
	var cap := cid[0].to_upper() + cid.substr(1)
	var path := "res://scenes/game/player/abilities/%sActive.gd" % cap
	if ResourceLoader.exists(path):
		var script: Script = load(path)
		var active: Node = script.new()
		add_child(active)
		active.call("setup", self)

func add_scrap(amount: int) -> void:
	var actual := amount
	if scrap_bonus_chance > 0.0 and randf() < scrap_bonus_chance:
		actual *= 2
	scrap += actual
	scrap_changed.emit(scrap)

func _physics_process(delta: float) -> void:
	var move_dir := InputManager.get_move_dir(player_index)
	velocity = move_dir * move_speed
	# Afterburner velocity scale
	if _boost_timer > 0.0:
		velocity *= boost_factor
	move_and_slide()

	# Tick slow timer
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_factor = 1.0
			move_speed = _base_move_speed
			sprite.modulate = Color.WHITE

	# Tick acid/burn DoT
	if _dot_ticks_left > 0:
		_dot_timer -= delta
		if _dot_timer <= 0.0:
			_dot_timer = 0.5
			_dot_ticks_left -= 1
			take_damage(_dot_dps * 0.5)
			if _dot_ticks_left <= 0:
				_dot_dps = 0.0
				sprite.modulate = Color.WHITE if _slow_timer <= 0.0 else Color(0.5, 0.9, 1.0)

	var aim_dir := InputManager.get_aim_dir(player_index, global_position)
	if aim_dir != Vector2.ZERO:
		rotation = aim_dir.angle()

	if InputManager.is_firing(player_index):
		_fire_all_weapons(aim_dir)

	if InputManager.is_boosting(player_index):
		activate_boost()

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

	# Shield regeneration
	if shield_max > 0.0:
		if _shield_regen_timer > 0.0:
			_shield_regen_timer -= delta
		elif current_shield < shield_max:
			current_shield = minf(current_shield + shield_regen_rate * delta, shield_max)
			shield_changed.emit(current_shield, shield_max)
			_update_shield_ring()

	# Afterburner
	if _boost_timer > 0.0:
		_boost_timer -= delta
	if _boost_cooldown > 0.0:
		_boost_cooldown -= delta

func apply_slow(factor: float, duration: float) -> void:
	## Apply a movement slow. Only takes effect if worse than current slow (worst-case cap).
	if factor >= _slow_factor and _slow_timer > 0.0:
		return  # existing slow is equal or more severe
	if _slow_timer <= 0.0:
		_base_move_speed = move_speed  # record clean speed before any slow
	_slow_factor = factor
	_slow_timer = duration
	move_speed = _base_move_speed * factor
	sprite.modulate = Color(0.5, 0.9, 1.0, 1.0)  # icy blue tint

func apply_dot(dps: float, ticks: int) -> void:
	## Apply an acid/burn DoT. Only takes effect if more damaging than current DoT (worst-case cap).
	if dps <= _dot_dps and _dot_ticks_left > 0:
		return
	_dot_dps = dps
	_dot_ticks_left = ticks
	_dot_timer = 0.5
	sprite.modulate = Color(0.5, 1.0, 0.3, 1.0)  # acid green tint

func _fire_all_weapons(aim_dir: Vector2) -> void:
	weapon_fired.emit()
	for weapon in weapons:
		if weapon.has_method("try_fire"):
			var pidx: int = weapon.get("port_index")
			var fire_dir := -aim_dir if PORT_DATA[pidx]["is_rear"] else aim_dir
			weapon.try_fire(fire_dir)

func activate_boost() -> void:
	## Called by InputManager handler or passive to trigger an afterburner burst.
	if boost_factor <= 0.0 or _boost_cooldown > 0.0:
		return
	_boost_timer = boost_duration
	_boost_cooldown = boost_recharge
	# Briefly brighten thruster
	if _thruster:
		_thruster.modulate = Color(2.0, 1.5, 0.5)
		var t := create_tween()
		t.tween_property(_thruster, "modulate", Color.WHITE, boost_duration)
	var sfx := "res://assets/audio/sfx_rocket_fire.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -3.0, 1.1)

# --- Health ---

func take_damage(amount: float) -> void:
	if damage_block_chance > 0.0 and _block_cooldown <= 0.0 and randf() < damage_block_chance:
		_block_cooldown = 8.0
		_flash_damage()
		return
	_shield_regen_timer = shield_regen_delay  # reset regen delay on any hit
	var effective := maxf(0.0, amount - armor)
	if current_shield > 0.0:
		var absorbed := minf(current_shield, effective)
		current_shield -= absorbed
		effective -= absorbed
		shield_changed.emit(current_shield, shield_max)
		_update_shield_ring()
		if effective <= 0.0:
			_flash_shield_hit()
			return
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

const REVIVE_SCRAP_PENALTY: int = 50

func revive() -> void:
	# Restore to half max health and re-enable physics
	current_health = max_health * 0.5
	set_physics_process(true)
	show()
	scale = Vector2.ONE
	sprite.modulate = Color.WHITE
	sprite.rotation = 0.0
	health_changed.emit(current_health, max_health)
	_update_damage_overlay(current_health / max_health)
	# Scrap penalty - take as much as the player has, up to the cap
	var penalty := mini(scrap, REVIVE_SCRAP_PENALTY)
	if penalty > 0:
		scrap -= penalty
		scrap_changed.emit(scrap)
	# Pop-in animation
	scale = Vector2.ZERO
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE * 1.2, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, 0.1)

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
			UpgradeData.StatKey.SHIELD_MAX:
				shield_max += delta
				current_shield = minf(current_shield + delta, shield_max)
				shield_changed.emit(current_shield, shield_max)
				_update_shield_ring()
			UpgradeData.StatKey.SHIELD_REGEN_RATE:
				shield_regen_rate += delta
			UpgradeData.StatKey.CRIT_CHANCE:
				crit_chance += delta
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
	acquired_upgrades.append(data)

func count_upgrade(id: StringName) -> int:
	var n := 0
	for item in acquired_upgrades:
		if item.id == id:
			n += 1
	return n

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
	# Assign to the first unoccupied port in the default order.
	# Do NOT use weapons.size()-1 as the index — the size reflects adds/removes
	# and the slot at that index may already be taken after a sell/forge/move.
	var occupied: Array = []
	for w in weapons:
		if w != weapon_node:
			occupied.append(w.get("port_index"))
	var port_idx: int = _DEFAULT_PORT_ORDER[PORT_DATA.size() - 1]  # fallback
	for p in _DEFAULT_PORT_ORDER:
		if p not in occupied:
			port_idx = p
			break
	weapon_node.set("port_index", port_idx)
	weapon_node.position = PORT_DATA[port_idx]["pos"]
	add_child(weapon_node)
	_update_weapon_visuals()

func get_weapon_count() -> int:
	return weapons.size()

# Swap the port assignments of two equipped weapons.
func reassign_port(wa: Node, wb: Node) -> void:
	var tmp_idx: int = wa.get("port_index")
	var tmp_pos: Vector2 = wa.position
	wa.set("port_index", wb.get("port_index"))
	wa.position = wb.position
	wb.set("port_index", tmp_idx)
	wb.position = tmp_pos
	_update_weapon_visuals()

# Move a weapon to an unoccupied port.
func move_to_empty_port(weapon_node: Node, port_idx: int) -> void:
	weapon_node.set("port_index", port_idx)
	weapon_node.position = PORT_DATA[port_idx]["pos"]
	_update_weapon_visuals()

# Rebuild wing-mount sprites to match currently equipped weapons.
# Only renders sprites for occupied ports; empty ports show nothing.
func _update_weapon_visuals() -> void:
	for v in _weapon_visuals:
		if is_instance_valid(v):
			v.queue_free()
	_weapon_visuals.clear()
	for w in weapons:
		var pidx: int = w.get("port_index")
		var port: Dictionary = PORT_DATA[pidx]
		var wdata = w.get("weapon_data")
		var wclass: int = int(wdata.weapon_class) if wdata != null else -1
		_add_mount_sprite(wclass, port["pos"], port["mount_rot"])

func _add_mount_sprite(weapon_class: int, pos: Vector2, mount_rot: float) -> void:
	if weapon_class < 0:
		return
	# WeaponClass: RAPID=0, PRECISION=1, SPREAD=2, HEAVY=3, EXPLOSIVE=4
	var path: String
	var scale_factor := 1.0
	match weapon_class:
		0: path = "res://assets/sprites/spaceParts_092.png" # small barrel
		1: path = "res://assets/sprites/spaceParts_095.png" # long cannon
		2: path = "res://assets/sprites/spaceParts_093.png" # double barrel
		3: path = "res://assets/sprites/spaceParts_094.png" # heavy cannon
		4: # missile pod
			path = "res://assets/sprites/spaceMissiles_001.png"
			scale_factor = 0.8
		_: return
	if not ResourceLoader.exists(path):
		return
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.rotation_degrees = mount_rot
	spr.position = pos
	spr.scale = Vector2(scale_factor, scale_factor)
	spr.z_index = 1
	add_child(spr)
	_weapon_visuals.append(spr)

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

func _setup_shield_ring() -> void:
	## Builds a procedural blue circle Sprite2D as the shield visual ring.
	if shield_max <= 0.0:
		return
	const RING_SIZE: int = 64
	var img := Image.create(RING_SIZE, RING_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(RING_SIZE * 0.5, RING_SIZE * 0.5)
	var outer := RING_SIZE * 0.5
	var inner := outer - 4.0
	for y in RING_SIZE:
		for x in RING_SIZE:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if d <= outer and d >= inner:
				var edge := minf((d - inner) / 2.0, (outer - d) / 2.0)
				img.set_pixel(x, y, Color(0.2, 0.6, 1.0, clampf(edge, 0.0, 1.0)))
	_shield_ring = Sprite2D.new()
	_shield_ring.texture = ImageTexture.create_from_image(img)
	_shield_ring.scale = Vector2(1.3, 1.3)
	_shield_ring.z_index = 3
	add_child(_shield_ring)
	_update_shield_ring()

func _update_shield_ring() -> void:
	if _shield_ring == null:
		return
	if shield_max <= 0.0:
		_shield_ring.visible = false
		return
	var frac := current_shield / shield_max
	_shield_ring.visible = frac > 0.0
	_shield_ring.modulate = Color(0.2, 0.6, 1.0, frac)

func _flash_shield_hit() -> void:
	## Blue flash when a hit is fully absorbed by the shield.
	if _shield_ring == null:
		return
	var tween := create_tween()
	tween.tween_property(_shield_ring, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.04)
	tween.tween_property(_shield_ring, "modulate", Color(0.2, 0.6, 1.0, current_shield / shield_max), 0.15)
