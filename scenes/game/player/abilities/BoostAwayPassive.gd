extends Node
## Boost Away! passive — one-shot instant upgrade triggered on pickup.
##
## Condition: all weapon slots must be filled with the same base weapon type
## (e.g. six Needlers of any tier).
##
## Effect:
##   - Tier 1–4 weapons are replaced with their Legendary (t5) counterpart.
##   - Tier 5 (Legendary) weapons are duplicated with a +20% Mythic stat boost
##     (damage, fire rate, range) and their rarity is set to MYTHIC.
##
## If the condition is not met when the upgrade is picked up, nothing happens.

const MYTHIC_BONUS: float = 0.20

func setup(player: Player) -> void:
	var slots: int = player.character_data.weapon_slots if player.character_data else 6

	# Condition 1: all weapon slots must be occupied.
	if player.weapons.size() < slots:
		return

	# Condition 2: every weapon must share the same base type.
	var first_base: String = ""
	for w in player.weapons:
		var wd: WeaponData = w.get("weapon_data")
		if wd == null:
			return
		var bid := _base_id(str(wd.id))
		if first_base.is_empty():
			first_base = bid
		elif bid != first_base:
			return  # Mixed weapon types — condition not met.

	# All conditions met — upgrade every weapon.
	var snapshot := player.weapons.duplicate()
	for old_weapon in snapshot:
		_upgrade_weapon(player, old_weapon, first_base)

	player._update_weapon_visuals()

	var sfx := "res://assets/audio/sfx_levelup.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), 0.0, 1.15)


## Strips the tier suffix (_t2 … _t5) from a weapon id to get its base family name.
func _base_id(weapon_id: String) -> String:
	for i in [5, 4, 3, 2]:
		var suffix := "_t%d" % i
		if weapon_id.ends_with(suffix):
			return weapon_id.left(weapon_id.length() - suffix.length())
	return weapon_id


## Replaces one weapon node with an upgraded version, preserving its port slot.
func _upgrade_weapon(player: Player, old_weapon: Node, base_id: String) -> void:
	var old_wd: WeaponData = old_weapon.get("weapon_data")
	if old_wd == null:
		return

	# Save positional and runtime state from the outgoing weapon.
	var old_port_idx: int    = old_weapon.get("port_index")
	var old_pos: Vector2     = old_weapon.position
	var old_proj_parent: Node = old_weapon.get("_projectile_parent") as Node
	var old_mult: float      = old_weapon.get("damage_multiplier") if old_weapon.get("damage_multiplier") != null else 1.0

	var new_wd: WeaponData
	if old_wd.tier < 5:
		# Upgrade to Legendary (t5).
		var t5_path := "res://resources/weapons/%s_t5.tres" % base_id
		if not ResourceLoader.exists(t5_path):
			return
		new_wd = ResourceLoader.load(t5_path)
	else:
		# Already Legendary → Mythic boost.
		new_wd = old_wd.duplicate()
		new_wd.rarity          = 5  # UpgradeData.Rarity.MYTHIC
		new_wd.display_name    = "[M] " + old_wd.display_name
		new_wd.damage          *= (1.0 + MYTHIC_BONUS)
		new_wd.fire_rate       *= (1.0 + MYTHIC_BONUS)
		new_wd.range           *= (1.0 + MYTHIC_BONUS * 0.5)

	# Build the replacement weapon node (respecting BEAM weapons).
	var new_weapon: BaseWeapon
	if new_wd.ammo_type == WeaponData.AmmoType.BEAM:
		new_weapon = load("res://scenes/game/weapons/BeamWeapon.gd").new()
	else:
		new_weapon = BaseWeapon.new()

	new_weapon.weapon_data       = new_wd
	new_weapon.damage_multiplier = old_mult
	new_weapon._projectile_parent = old_proj_parent
	new_weapon.set("port_index", old_port_idx)
	new_weapon.position          = old_pos

	# Swap out in the player's weapon list and scene tree.
	player.weapons.erase(old_weapon)
	old_weapon.queue_free()

	player.weapons.append(new_weapon)
	player.add_child(new_weapon)
