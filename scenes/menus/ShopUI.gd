extends CanvasLayer

## ShopUI - Mid-run weapon shop, appears after each wave's upgrade screen.
## Displays 3 random weapons; cost paid in Scrap (in-run currency).
## Shows ship-class affinity so players can see bonuses/penalties before buying.

signal ui_closed()

const WEAPON_OFFER_COUNT: int = 3
const WEAPON_CLASS_NAMES: Array[String] = ["RAPID", "PRECISION", "SPREAD", "HEAVY", "EXPLOSIVE"]

var _players: Array[Player] = []
var _current_player_index: int = 0
var _projectile_parent: Node2D = null
var _wave_number: int = 1

# Persistent offer state - regenerated per player, preserved across buy/sell/lock
var _offered_weapons: Array[WeaponData] = []
var _offered_modules: Array[UpgradeData] = []
var _locked_weapons: Array[bool] = []
var _locked_modules: Array[bool] = []
var _reroll_count: int = 0
var _selected_weapon_node: Node = null   # port-swap selection state

# Per-player offer state saved across waves (keyed by player index)
var _saved_weapon_offers: Dictionary = {}
var _saved_weapon_locks: Dictionary = {}
var _saved_module_offers: Dictionary = {}
var _saved_module_locks: Dictionary = {}

var _title_label: Label
var _scrap_label: Label
var _reroll_btn: Button
var _shop_container: HBoxContainer
var _module_container: HBoxContainer
var _loadout_control: Control
var _purchased_container: FlowContainer
var _stats_container: VBoxContainer
var _stats_overlay: PanelContainer
var _stats_toggle_btn: Button
var _popover: PanelContainer
var _popover_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20.0
	vbox.offset_top = 8.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -8.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var font := GameManager.kenney_font()
	if font:
		_title_label.add_theme_font_override("font", font)
		_title_label.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_title_label)

	_scrap_label = Label.new()
	_scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		_scrap_label.add_theme_font_override("font", font)
		_scrap_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_scrap_label)

	_reroll_btn = Button.new()
	_reroll_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_reroll_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if font:
		_reroll_btn.add_theme_font_override("font", font)
		_reroll_btn.add_theme_font_size_override("font_size", 15)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	vbox.add_child(_reroll_btn)

	_shop_container = HBoxContainer.new()
	_shop_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_shop_container.add_theme_constant_override("separation", 16)
	vbox.add_child(_shop_container)

	var modules_title := Label.new()
	modules_title.text = "-- Modules --"
	modules_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		modules_title.add_theme_font_override("font", font)
		modules_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(modules_title)

	_module_container = HBoxContainer.new()
	_module_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_module_container.add_theme_constant_override("separation", 16)
	vbox.add_child(_module_container)

	# Two-column bottom: left = spatial ship diagram, right = acquired upgrades + stats
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 12)
	bottom_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(bottom_hbox)

	# ---- LEFT COLUMN: Ship diagram ----
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(370.0, 0.0)
	left_col.add_theme_constant_override("separation", 4)
	bottom_hbox.add_child(left_col)

	var loadout_title := Label.new()
	loadout_title.text = "Current Loadout  (sell for 50% scrap refund)"
	loadout_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		loadout_title.add_theme_font_override("font", font)
		loadout_title.add_theme_font_size_override("font_size", 14)
	left_col.add_child(loadout_title)

	_loadout_control = Control.new()
	_loadout_control.custom_minimum_size = Vector2(360.0, 332.0)
	_loadout_control.clip_contents = true
	left_col.add_child(_loadout_control)

	# ---- RIGHT COLUMN: Acquired upgrades + stats toggle ----
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 6)
	bottom_hbox.add_child(right_col)

	var acquired_title := Label.new()
	acquired_title.text = "-- Acquired Upgrades --"
	acquired_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		acquired_title.add_theme_font_override("font", font)
		acquired_title.add_theme_font_size_override("font_size", 14)
	right_col.add_child(acquired_title)

	var purchased_scroll := ScrollContainer.new()
	purchased_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	purchased_scroll.custom_minimum_size = Vector2(0.0, 100.0)
	purchased_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	purchased_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_col.add_child(purchased_scroll)

	_purchased_container = FlowContainer.new()
	_purchased_container.add_theme_constant_override("h_separation", 6)
	_purchased_container.add_theme_constant_override("v_separation", 6)
	_purchased_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purchased_scroll.add_child(_purchased_container)

	# Stats toggle button (inline, in the right column)
	_stats_toggle_btn = Button.new()
	_stats_toggle_btn.text = "Ship Stats  v"
	_stats_toggle_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_stats_toggle_btn.pressed.connect(_on_stats_toggle)
	if font:
		_stats_toggle_btn.add_theme_font_override("font", font)
		_stats_toggle_btn.add_theme_font_size_override("font_size", 13)
	right_col.add_child(_stats_toggle_btn)

	var skip_btn := Button.new()
	skip_btn.text = "Continue"
	skip_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	skip_btn.pressed.connect(_on_skip_pressed)
	if font:
		skip_btn.add_theme_font_override("font", font)
		skip_btn.add_theme_font_size_override("font_size", 16)
	vbox.add_child(skip_btn)

	# Stats overlay and popover built last so they render on top of everything
	_stats_overlay = PanelContainer.new()
	_stats_overlay.visible = false
	_stats_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_overlay.z_index = 50
	_stats_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	var stats_ov_style := StyleBoxFlat.new()
	stats_ov_style.bg_color = Color(0.03, 0.03, 0.08, 0.95)
	stats_ov_style.border_color = Color(0.4, 0.5, 0.8)
	stats_ov_style.set_border_width_all(2)
	stats_ov_style.content_margin_left = 40.0
	stats_ov_style.content_margin_right = 40.0
	stats_ov_style.content_margin_top = 30.0
	stats_ov_style.content_margin_bottom = 30.0
	_stats_overlay.add_theme_stylebox_override("panel", stats_ov_style)

	var stats_ov_vbox := VBoxContainer.new()
	stats_ov_vbox.add_theme_constant_override("separation", 8)
	_stats_overlay.add_child(stats_ov_vbox)

	var stats_ov_header := HBoxContainer.new()
	stats_ov_header.add_theme_constant_override("separation", 12)
	stats_ov_vbox.add_child(stats_ov_header)

	var stats_ov_title := Label.new()
	stats_ov_title.text = "-- Ship Stats --"
	stats_ov_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		stats_ov_title.add_theme_font_override("font", font)
		stats_ov_title.add_theme_font_size_override("font_size", 22)
	stats_ov_header.add_child(stats_ov_title)

	var stats_ov_close := Button.new()
	stats_ov_close.text = "X  Close"
	stats_ov_close.process_mode = Node.PROCESS_MODE_ALWAYS
	stats_ov_close.pressed.connect(_on_stats_toggle)
	if font:
		stats_ov_close.add_theme_font_override("font", font)
		stats_ov_close.add_theme_font_size_override("font_size", 16)
	stats_ov_header.add_child(stats_ov_close)

	var stats_ov_scroll := ScrollContainer.new()
	stats_ov_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_ov_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stats_ov_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	stats_ov_vbox.add_child(stats_ov_scroll)

	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 4)
	stats_ov_scroll.add_child(_stats_container)

	add_child(_stats_overlay)

	_popover = PanelContainer.new()
	_popover.visible = false
	_popover.z_index = 100
	_popover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pop_style := StyleBoxFlat.new()
	pop_style.bg_color = Color(0.05, 0.05, 0.1, 0.96)
	pop_style.border_color = Color(0.6, 0.6, 0.6)
	pop_style.set_border_width_all(2)
	pop_style.set_corner_radius_all(6)
	pop_style.content_margin_left = 10.0
	pop_style.content_margin_right = 10.0
	pop_style.content_margin_top = 8.0
	pop_style.content_margin_bottom = 8.0
	_popover.add_theme_stylebox_override("panel", pop_style)
	_popover_label = Label.new()
	_popover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popover_label.custom_minimum_size = Vector2(220.0, 0.0)
	if font:
		_popover_label.add_theme_font_override("font", font)
		_popover_label.add_theme_font_size_override("font_size", 13)
	_popover.add_child(_popover_label)
	add_child(_popover)

func show_for_players(players: Array, projectile_parent: Node2D, wave_number: int = 1) -> void:
	_players.clear()
	for p in players:
		_players.append(p)
	_projectile_parent = projectile_parent
	_wave_number = wave_number
	_current_player_index = 0
	_reroll_count = 0
	_restore_player_state(0)
	visible = true
	_show_shop_for_player()

func _reset_offer_state() -> void:
	_offered_weapons.clear()
	_offered_modules.clear()
	_locked_weapons.clear()
	_locked_modules.clear()
	_reroll_count = 0

func _save_player_state(idx: int) -> void:
	_saved_weapon_offers[idx] = _offered_weapons.duplicate()
	_saved_weapon_locks[idx] = _locked_weapons.duplicate()
	_saved_module_offers[idx] = _offered_modules.duplicate()
	_saved_module_locks[idx] = _locked_modules.duplicate()

func _restore_player_state(idx: int) -> void:
	_offered_weapons.clear()
	_locked_weapons.clear()
	_offered_modules.clear()
	_locked_modules.clear()
	if not _saved_weapon_offers.has(idx):
		return
	for v in _saved_weapon_offers[idx]:
		_offered_weapons.append(v)
	for v in _saved_weapon_locks[idx]:
		_locked_weapons.append(v)
	for v in _saved_module_offers[idx]:
		_offered_modules.append(v)
	for v in _saved_module_locks[idx]:
		_locked_modules.append(v)

func _show_shop_for_player() -> void:
	var player := _players[_current_player_index]
	var slots := player.character_data.weapon_slots if player.character_data else 6
	_title_label.text = "Weapon Shop  -  Player %d  (Slots: %d / %d)" % [
		_current_player_index + 1,
		player.weapons.size(),
		slots,
	]
	_scrap_label.text = "Scrap: %d" % player.scrap
	# Refresh unlocked slots with new offers; locked slots are preserved.
	_generate_weapon_offers(player)
	_generate_module_offers(player)
	_update_reroll_btn(player)
	_render_shop(player)
	_render_modules(player)
	_populate_loadout(player)
	_populate_purchased(player)
	_populate_stats(player)

# Returns per-rarity weights [Common, Uncommon, Rare, Epic, Legendary]
func _get_rarity_weights(wave: int) -> Array[float]:
	var t := clampf(float(wave - 1) / 9.0, 0.0, 1.0)
	var weights: Array[float] = [
		lerpf(60.0, 25.0, t),   # COMMON
		lerpf(25.0, 28.0, t),   # UNCOMMON
		lerpf(12.0, 25.0, t),   # RARE
		lerpf(3.0,  15.0, t),   # EPIC
		lerpf(0.0,  7.0,  t),   # LEGENDARY
	]
	return weights

func _rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.55, 0.55, 0.55)   # COMMON - grey
		1: return Color(0.15, 0.75, 0.3)    # UNCOMMON - green
		2: return Color(0.2,  0.45, 0.95)   # RARE - blue
		3: return Color(0.65, 0.1,  0.95)   # EPIC - purple
		4: return Color(0.95, 0.7,  0.0)    # LEGENDARY - gold
		_: return Color(0.55, 0.55, 0.55)

func _rarity_name(rarity: int) -> String:
	match rarity:
		0: return "COMMON"
		1: return "UNCOMMON"
		2: return "RARE"
		3: return "EPIC"
		4: return "LEGENDARY"
		_: return "COMMON"

func _weighted_sample_weapons(pool: Array[WeaponData], weights: Array[float], count: int) -> Array[WeaponData]:
	var result: Array[WeaponData] = []
	var remaining := pool.duplicate()
	var attempts := 0
	while result.size() < count and remaining.size() > 0 and attempts < 1000:
		attempts += 1
		var total := 0.0
		for item in remaining:
			total += weights[int(item.rarity)]
		if total <= 0.0:
			break
		var roll := randf() * total
		var acc := 0.0
		for i in range(remaining.size()):
			acc += weights[int(remaining[i].rarity)]
			if roll <= acc:
				result.append(remaining[i])
				remaining.remove_at(i)
				break
	return result

func _weighted_sample_modules(pool: Array[UpgradeData], weights: Array[float], count: int) -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	var remaining := pool.duplicate()
	var attempts := 0
	while result.size() < count and remaining.size() > 0 and attempts < 1000:
		attempts += 1
		var total := 0.0
		for item in remaining:
			total += weights[int(item.rarity)]
		if total <= 0.0:
			break
		var roll := randf() * total
		var acc := 0.0
		for i in range(remaining.size()):
			acc += weights[int(remaining[i].rarity)]
			if roll <= acc:
				result.append(remaining[i])
				remaining.remove_at(i)
				break
	return result

func _generate_weapon_offers(_player: Player) -> void:
	# Pad arrays to full count
	while _offered_weapons.size() < WEAPON_OFFER_COUNT:
		_offered_weapons.append(null)
	while _locked_weapons.size() < WEAPON_OFFER_COUNT:
		_locked_weapons.append(false)
	# Determine which slots need new weapons (unlocked or empty)
	var slots_to_fill: Array[int] = []
	var exclude: Array[WeaponData] = []
	for i in range(WEAPON_OFFER_COUNT):
		if _locked_weapons[i] and _offered_weapons[i] != null:
			exclude.append(_offered_weapons[i])
		else:
			slots_to_fill.append(i)
	if slots_to_fill.is_empty():
		return
	var all_weapons := _load_all_weapons()
	var weights := _get_rarity_weights(_wave_number)
	var pool: Array[WeaponData] = []
	for w in all_weapons:
		if not exclude.has(w):
			pool.append(w)
	if pool.is_empty():
		pool = all_weapons
	var new_weapons := _weighted_sample_weapons(pool, weights, slots_to_fill.size())
	for i in range(slots_to_fill.size()):
		var slot := slots_to_fill[i]
		if i < new_weapons.size():
			_offered_weapons[slot] = new_weapons[i]
		elif all_weapons.size() > 0:
			_offered_weapons[slot] = all_weapons[0]
		_locked_weapons[slot] = false

func _render_shop(player: Player) -> void:
	for child in _shop_container.get_children():
		child.queue_free()

	var font := GameManager.kenney_font()
	var slots := player.character_data.weapon_slots if player.character_data else 6
	var is_full := player.weapons.size() >= slots

	for slot_idx in range(_offered_weapons.size()):
		var wdata := _offered_weapons[slot_idx]
		var is_locked := _locked_weapons[slot_idx] if slot_idx < _locked_weapons.size() else false

		var class_idx: int = int(wdata.weapon_class)
		var class_name_str: String = WEAPON_CLASS_NAMES[class_idx] if class_idx < WEAPON_CLASS_NAMES.size() else "?"

		var bonus: float = 0.0
		if player.character_data:
			bonus = player.character_data.weapon_class_bonuses.get(class_idx, 0.0)
		var affinity_str: String
		if bonus > 0.001:
			affinity_str = " [+%d%%]" % int(bonus * 100.0)
		elif bonus < -0.001:
			affinity_str = " [%d%%]" % int(bonus * 100.0)
		else:
			affinity_str = ""

		var affinity_color := Color.WHITE
		if bonus > 0.001:
			affinity_color = Color(0.3, 1.0, 0.4)
		elif bonus < -0.001:
			affinity_color = Color(1.0, 0.35, 0.35)

		var rarity_col := _rarity_color(int(wdata.rarity))
		var border_col := Color(0.9, 0.75, 0.1) if is_locked else rarity_col
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(210.0, 180.0)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = rarity_col.darkened(0.6)
		card_style.border_color = border_col
		card_style.set_border_width_all(3 if is_locked else 2)
		card_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", card_style)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 5)
		card.add_child(card_vbox)

		if is_locked:
			var lock_badge := Label.new()
			lock_badge.text = "[LOCKED]"
			lock_badge.modulate = Color(0.9, 0.75, 0.1)
			lock_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if font:
				lock_badge.add_theme_font_override("font", font)
				lock_badge.add_theme_font_size_override("font_size", 11)
			card_vbox.add_child(lock_badge)

		var rarity_label := Label.new()
		rarity_label.text = "[%s]" % _rarity_name(int(wdata.rarity))
		rarity_label.modulate = rarity_col.lightened(0.2)
		rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if font:
			rarity_label.add_theme_font_override("font", font)
			rarity_label.add_theme_font_size_override("font_size", 12)
		card_vbox.add_child(rarity_label)

		var class_label := Label.new()
		class_label.text = "[%s]%s" % [class_name_str, affinity_str]
		class_label.modulate = affinity_color
		class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if font:
			class_label.add_theme_font_override("font", font)
			class_label.add_theme_font_size_override("font_size", 13)
		card_vbox.add_child(class_label)

		var shop_icon_tex := _get_weapon_icon_texture(wdata)
		if shop_icon_tex != null:
			var shop_icon_rect := TextureRect.new()
			shop_icon_rect.texture = shop_icon_tex
			shop_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			shop_icon_rect.custom_minimum_size = Vector2(40.0, 40.0)
			shop_icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			shop_icon_rect.modulate = rarity_col.lightened(0.15)
			shop_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_vbox.add_child(shop_icon_rect)

		var name_label := Label.new()
		name_label.text = wdata.display_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if font:
			name_label.add_theme_font_override("font", font)
			name_label.add_theme_font_size_override("font_size", 16)
		card_vbox.add_child(name_label)

		var desc_label := Label.new()
		desc_label.text = wdata.description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if font:
			desc_label.add_theme_font_override("font", font)
			desc_label.add_theme_font_size_override("font_size", 12)
		card_vbox.add_child(desc_label)

		var cost_label := Label.new()
		cost_label.text = "%d Scrap" % wdata.shop_cost
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if font:
			cost_label.add_theme_font_override("font", font)
			cost_label.add_theme_font_size_override("font_size", 14)
		card_vbox.add_child(cost_label)

		var can_buy := player.scrap >= wdata.shop_cost and not is_full
		var buy_btn := Button.new()
		if can_buy:
			buy_btn.text = "Buy"
		elif is_full:
			buy_btn.text = "Sell a weapon first"
		else:
			buy_btn.text = "Need Scrap"
		buy_btn.disabled = not can_buy
		buy_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		buy_btn.pressed.connect(_on_buy_pressed.bind(player, slot_idx))
		if font:
			buy_btn.add_theme_font_override("font", font)
			buy_btn.add_theme_font_size_override("font_size", 14)
		card_vbox.add_child(buy_btn)

		var lock_btn := Button.new()
		lock_btn.text = "Unlock" if is_locked else "Lock"
		lock_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		lock_btn.pressed.connect(_on_toggle_weapon_lock.bind(player, slot_idx))
		if font:
			lock_btn.add_theme_font_override("font", font)
			lock_btn.add_theme_font_size_override("font_size", 11)
		card_vbox.add_child(lock_btn)

		var shop_pop := "[%s] %s\n[%s]%s\n\n%s\n\nDMG: %.0f  |  Rate: %.1f/s\nRange: %.0f  |  Spread: %.2f\nShots: %d  |  Pierce: %d\nCost: %d scrap" % [
			_rarity_name(int(wdata.rarity)), wdata.display_name,
			class_name_str, affinity_str,
			wdata.description,
			wdata.damage, wdata.fire_rate,
			wdata.range, wdata.spread,
			wdata.projectile_count, wdata.piercing,
			wdata.shop_cost,
		]
		buy_btn.focus_entered.connect(_show_popover.bind(buy_btn, shop_pop, rarity_col))
		buy_btn.focus_exited.connect(_hide_popover)
		buy_btn.mouse_entered.connect(_show_popover.bind(buy_btn, shop_pop, rarity_col))
		buy_btn.mouse_exited.connect(_hide_popover)

		_shop_container.add_child(card)

	# Focus first available buy button for gamepad navigation
	for card in _shop_container.get_children():
		var vbox: VBoxContainer = card.get_child(0)
		if vbox:
			for i in range(vbox.get_child_count()):
				var child := vbox.get_child(i)
				if child is Button and not (child as Button).disabled and (child as Button).text == "Buy":
					(child as Button).grab_focus()
					break

func _load_all_weapons() -> Array[WeaponData]:
	var result: Array[WeaponData] = []
	for path in _get_all_weapon_paths():
		var wd: WeaponData = ResourceLoader.load(path)
		if wd != null and not wd.is_forge_only:
			result.append(wd)
	return result

func _get_all_weapon_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://resources/weapons")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres") or fname.ends_with(".tres.remap"):
				paths.append("res://resources/weapons/" + fname.trim_suffix(".remap"))
			fname = dir.get_next()
	return paths

func _populate_loadout(player: Player) -> void:
	for child in _loadout_control.get_children():
		child.queue_free()

	var font := GameManager.kenney_font()

	# Ship silhouette background (renders behind port cards)
	var sil := TextureRect.new()
	sil.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sil.size = Vector2(200.0, 200.0)
	sil.custom_minimum_size = Vector2(200.0, 200.0)
	var sil_path := "res://assets/sprites/playerShip1_blue.png"
	if ResourceLoader.exists(sil_path):
		sil.texture = load(sil_path)
	var ship_col := player.character_data.ship_color if player.character_data else Color.WHITE
	sil.modulate = Color(ship_col.r, ship_col.g, ship_col.b, 0.22)
	sil.position = Vector2(175.0 - 100.0, 180.0 - 100.0)
	sil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loadout_control.add_child(sil)

	# Build a lookup: port_index -> weapon_node
	var port_to_weapon: Dictionary = {}
	# Build weapon id count for forge detection
	var id_count: Dictionary = {}
	for w in player.weapons:
		var wd = w.get("weapon_data")
		if wd != null:
			var wid := str(wd.id)
			id_count[wid] = id_count.get(wid, 0) + 1
	for w in player.weapons:
		port_to_weapon[w.get("port_index")] = w

	for port_idx in 6:
		var port: Dictionary = player.PORT_DATA[port_idx]
		var port_label_str: String = port["label"]
		var is_rear: bool = port["is_rear"]
		var weapon_node: Node = port_to_weapon.get(port_idx, null)
		var is_selected: bool = (_selected_weapon_node != null and _selected_weapon_node == weapon_node)
		var is_swap_target: bool = (_selected_weapon_node != null and weapon_node != null and weapon_node != _selected_weapon_node)
		var is_empty_target: bool = (_selected_weapon_node != null and weapon_node == null)

		# Map port position to screen coordinates (nose points up, +Y down, +X right)
		# PORT_DATA: pos.x = forward axis, pos.y = starboard axis
		# Screen: screen_x = starboard, screen_y = -forward
		var port_pos: Vector2 = port["pos"]
		var screen_x: float = port_pos.y * 3.5 + 175.0
		var screen_y: float = -port_pos.x * 3.5 + 180.0
		var card_pos := Vector2(screen_x - 40.0, screen_y - 40.0)
		card_pos.x = clampf(card_pos.x, 0.0, 280.0)
		card_pos.y = clampf(card_pos.y, 0.0, 252.0)

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(80.0, 80.0)
		card.position = card_pos
		card.focus_mode = Control.FOCUS_ALL
		var card_style := StyleBoxFlat.new()
		if weapon_node != null:
			var wdata: WeaponData = weapon_node.get("weapon_data")
			var rarity_col := _rarity_color(int(wdata.rarity) if wdata else 0)
			card_style.bg_color = rarity_col.darkened(0.65)
			if is_selected:
				card_style.border_color = Color(1.0, 0.85, 0.1)
				card_style.set_border_width_all(3)
			elif is_swap_target:
				card_style.border_color = Color(0.3, 0.8, 1.0)
				card_style.set_border_width_all(2)
			else:
				card_style.border_color = rarity_col
				card_style.set_border_width_all(2)
		else:
			card_style.bg_color = Color(0.08, 0.08, 0.12)
			if is_empty_target:
				card_style.border_color = Color(0.3, 0.8, 1.0)
				card_style.set_border_width_all(2)
			else:
				card_style.border_color = Color(0.3, 0.3, 0.35)
				card_style.set_border_width_all(1)
		card_style.set_corner_radius_all(5)
		card.add_theme_stylebox_override("panel", card_style)

		var cvbox := VBoxContainer.new()
		cvbox.add_theme_constant_override("separation", 2)
		card.add_child(cvbox)

		# Port label (always shown)
		var port_lbl := Label.new()
		port_lbl.text = "%s [%s]" % [port_label_str, "R" if is_rear else "F"]
		port_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		port_lbl.modulate = Color(0.6, 0.9, 1.0) if is_rear else Color(0.9, 0.9, 0.9)
		if font:
			port_lbl.add_theme_font_override("font", font)
			port_lbl.add_theme_font_size_override("font_size", 9)
		cvbox.add_child(port_lbl)

		if weapon_node != null:
			var wdata: WeaponData = weapon_node.get("weapon_data")
			var sell_value: int = max(1, wdata.shop_cost / 2) if wdata else 1
			var rarity_col := _rarity_color(int(wdata.rarity) if wdata else 0)
			var class_idx: int = int(wdata.weapon_class) if wdata else 0
			var class_str: String = WEAPON_CLASS_NAMES[class_idx] if class_idx < WEAPON_CLASS_NAMES.size() else "?"

			# Weapon icon
			var icon_tex := _get_weapon_icon_texture(wdata)
			if icon_tex != null:
				var icon_rect := TextureRect.new()
				icon_rect.texture = icon_tex
				icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon_rect.custom_minimum_size = Vector2(28.0, 28.0)
				icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				icon_rect.modulate = rarity_col.lightened(0.2)
				icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cvbox.add_child(icon_rect)

			var name_lbl := Label.new()
			name_lbl.text = wdata.display_name if wdata else "?"
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if font:
				name_lbl.add_theme_font_override("font", font)
				name_lbl.add_theme_font_size_override("font_size", 10)
			cvbox.add_child(name_lbl)

			var btn_row := HBoxContainer.new()
			btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
			btn_row.add_theme_constant_override("separation", 3)
			cvbox.add_child(btn_row)

			# Select/swap button
			var move_btn := Button.new()
			move_btn.process_mode = Node.PROCESS_MODE_ALWAYS
			if is_selected:
				move_btn.text = "Cancel"
			elif _selected_weapon_node != null:
				move_btn.text = "Swap"
			else:
				move_btn.text = "Move"
			if font:
				move_btn.add_theme_font_override("font", font)
				move_btn.add_theme_font_size_override("font_size", 10)
			move_btn.pressed.connect(_on_port_select_pressed.bind(player, weapon_node, port_idx))
			btn_row.add_child(move_btn)

			# Sell button
			var sell_btn := Button.new()
			sell_btn.text = "Sell"
			sell_btn.disabled = player.weapons.size() <= 1
			sell_btn.process_mode = Node.PROCESS_MODE_ALWAYS
			if font:
				sell_btn.add_theme_font_override("font", font)
				sell_btn.add_theme_font_size_override("font_size", 10)
			sell_btn.pressed.connect(_on_sell_pressed.bind(player, weapon_node))
			btn_row.add_child(sell_btn)

			var effective_dmg: float = weapon_node.get("damage") * weapon_node.get("damage_multiplier") * weapon_node.get("passive_multiplier")
			var pop_lines := "[%s] %s\n[%s]\n\n%s\n\nDMG: %.0f  |  Rate: %.1f/s\nRange: %.0f  |  Spread: %.2f\nShots: %d  |  Pierce: %d\nSell: +%d scrap" % [
				_rarity_name(int(wdata.rarity) if wdata else 0), wdata.display_name if wdata else "?",
				class_str, wdata.description if wdata else "",
				effective_dmg, weapon_node.get("fire_rate"),
				weapon_node.get("range"), weapon_node.get("spread"),
				weapon_node.get("projectile_count"), weapon_node.get("piercing"),
				sell_value,
			]
			move_btn.focus_entered.connect(_show_popover.bind(move_btn, pop_lines, rarity_col))
			move_btn.focus_exited.connect(_hide_popover)
			move_btn.mouse_entered.connect(_show_popover.bind(move_btn, pop_lines, rarity_col))
			move_btn.mouse_exited.connect(_hide_popover)
			sell_btn.focus_entered.connect(_show_popover.bind(sell_btn, pop_lines, rarity_col))
			sell_btn.focus_exited.connect(_hide_popover)
			sell_btn.mouse_entered.connect(_show_popover.bind(sell_btn, pop_lines, rarity_col))
			sell_btn.mouse_exited.connect(_hide_popover)

			# Forge button: visible when two copies of this weapon are equipped
			if wdata != null and wdata.forged_weapon_id != &"" \
					and id_count.get(str(wdata.id), 0) >= 2:
				var forge_btn := Button.new()
				forge_btn.text = "FORGE"
				forge_btn.process_mode = Node.PROCESS_MODE_ALWAYS
				forge_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
				if font:
					forge_btn.add_theme_font_override("font", font)
					forge_btn.add_theme_font_size_override("font_size", 10)
				forge_btn.pressed.connect(_on_forge_pressed.bind(player, wdata.id, wdata.forged_weapon_id))
				cvbox.add_child(forge_btn)
		else:
			# Empty port
			var empty_lbl := Label.new()
			empty_lbl.text = "-- Empty --"
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.modulate = Color(0.4, 0.4, 0.45)
			if font:
				empty_lbl.add_theme_font_override("font", font)
				empty_lbl.add_theme_font_size_override("font_size", 10)
			cvbox.add_child(empty_lbl)

			if _selected_weapon_node != null:
				var here_btn := Button.new()
				here_btn.text = "Move Here"
				here_btn.process_mode = Node.PROCESS_MODE_ALWAYS
				if font:
					here_btn.add_theme_font_override("font", font)
					here_btn.add_theme_font_size_override("font_size", 10)
				here_btn.pressed.connect(_on_port_move_here_pressed.bind(player, port_idx))
				cvbox.add_child(here_btn)

		_loadout_control.add_child(card)

func _on_port_select_pressed(player: Player, weapon_node: Node, _port_idx: int) -> void:
	AudioManager.play_ui_click()
	if _selected_weapon_node == weapon_node:
		# Deselect
		_selected_weapon_node = null
	elif _selected_weapon_node != null:
		# Swap the two weapons
		player.reassign_port(_selected_weapon_node, weapon_node)
		_selected_weapon_node = null
	else:
		# Select this weapon
		_selected_weapon_node = weapon_node
	_populate_loadout(player)

func _on_port_move_here_pressed(player: Player, port_idx: int) -> void:
	if _selected_weapon_node == null:
		return
	AudioManager.play_ui_click()
	player.move_to_empty_port(_selected_weapon_node, port_idx)
	_selected_weapon_node = null
	_populate_loadout(player)

func _on_sell_pressed(player: Player, weapon_node: Node) -> void:
	if player.weapons.size() <= 1:
		return
	AudioManager.play_ui_click()
	var wdata: WeaponData = weapon_node.get("weapon_data")
	var sell_value: int = 1
	if wdata != null:
		sell_value = max(1, wdata.shop_cost / 2)
	if _selected_weapon_node == weapon_node:
		_selected_weapon_node = null
	player.weapons.erase(weapon_node)
	weapon_node.queue_free()
	player.call("_update_weapon_visuals")
	player.scrap += sell_value
	player.scrap_changed.emit(player.scrap)
	# Re-render only - shop offers are unchanged after a sell
	_scrap_label.text = "Scrap: %d" % player.scrap
	_update_reroll_btn(player)
	_render_shop(player)
	_render_modules(player)
	_populate_loadout(player)
	_populate_stats(player)
	_update_title(player)

func _on_forge_pressed(player: Player, base_id: StringName, forged_id: StringName) -> void:
	# Collect the first two weapons with the matching base id
	var to_remove: Array[Node] = []
	for w in player.weapons:
		var wd: WeaponData = w.get("weapon_data")
		if wd != null and wd.id == base_id:
			to_remove.append(w)
		if to_remove.size() >= 2:
			break
	if to_remove.size() < 2:
		return
	AudioManager.play_ui_click()
	# Remove both source weapons
	for w in to_remove:
		if _selected_weapon_node == w:
			_selected_weapon_node = null
		player.weapons.erase(w)
		w.queue_free()
	# Load and equip the forged weapon
	var forged_path := "res://resources/weapons/%s.tres" % forged_id
	if not ResourceLoader.exists(forged_path):
		push_error("Forge: missing resource %s" % forged_path)
		return
	var forged_data: WeaponData = ResourceLoader.load(forged_path)
	var new_weapon := _make_weapon_node(forged_data)
	new_weapon._projectile_parent = _projectile_parent
	player.add_weapon(new_weapon)
	var sfx := "res://assets/audio/sfx_levelup.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -3.0, 1.1)
	_scrap_label.text = "Scrap: %d" % player.scrap
	_update_reroll_btn(player)
	_render_shop(player)
	_render_modules(player)
	_populate_loadout(player)
	_populate_stats(player)
	_update_title(player)

func _make_weapon_node(wdata: WeaponData) -> BaseWeapon:
	var weapon: BaseWeapon
	if wdata.ammo_type == WeaponData.AmmoType.BEAM:
		weapon = load("res://scenes/game/weapons/BeamWeapon.gd").new()
	else:
		weapon = BaseWeapon.new()
	weapon.weapon_data = wdata
	return weapon

func _on_buy_pressed(player: Player, slot_idx: int) -> void:
	if slot_idx >= _offered_weapons.size():
		return
	var wdata := _offered_weapons[slot_idx]
	var max_slots := player.character_data.weapon_slots if player.character_data else 6
	if player.weapons.size() >= max_slots:
		return
	AudioManager.play_ui_click()
	if player.scrap < wdata.shop_cost:
		return
	player.scrap -= wdata.shop_cost
	player.scrap_changed.emit(player.scrap)
	var weapon := _make_weapon_node(wdata)
	weapon._projectile_parent = _projectile_parent
	player.add_weapon(weapon)
	# Replace only the purchased slot with a fresh item
	_replace_weapon_offer(slot_idx)
	_scrap_label.text = "Scrap: %d" % player.scrap
	_update_reroll_btn(player)
	_render_shop(player)
	_render_modules(player)
	_populate_loadout(player)
	_populate_stats(player)
	_update_title(player)

func _on_skip_pressed() -> void:
	AudioManager.play_ui_click()
	_save_player_state(_current_player_index)
	_current_player_index += 1
	if _current_player_index < _players.size():
		_reroll_count = 0
		_restore_player_state(_current_player_index)
		_show_shop_for_player()
	else:
		_close()

func _generate_module_offers(player: Player) -> void:
	var all_modules := _load_all_modules()
	var available := _filter_modules_for_player(all_modules, player)
	var weights := _get_rarity_weights(_wave_number)
	# Pad arrays to full count
	while _offered_modules.size() < 3:
		_offered_modules.append(null)
	while _locked_modules.size() < 3:
		_locked_modules.append(false)
	# Determine which slots need new modules (unlocked or empty)
	var slots_to_fill: Array[int] = []
	var exclude: Array[UpgradeData] = []
	for i in range(3):
		if _locked_modules[i] and _offered_modules[i] != null:
			exclude.append(_offered_modules[i])
		else:
			slots_to_fill.append(i)
	if slots_to_fill.is_empty():
		return
	var pool: Array[UpgradeData] = []
	for m in available:
		if not exclude.has(m):
			pool.append(m)
	if pool.is_empty():
		pool = available
	var new_modules := _weighted_sample_modules(pool, weights, slots_to_fill.size())
	for i in range(slots_to_fill.size()):
		var slot := slots_to_fill[i]
		if i < new_modules.size():
			_offered_modules[slot] = new_modules[i]
		elif available.size() > 0:
			_offered_modules[slot] = available[0]
		_locked_modules[slot] = false

func _filter_modules_for_player(pool: Array[UpgradeData], player: Player) -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	for item in pool:
		if item.max_stacks == -1 or player.count_upgrade(item.id) < item.max_stacks:
			result.append(item)
	if result.is_empty():
		return pool
	return result

func _render_modules(player: Player) -> void:
	for child in _module_container.get_children():
		child.queue_free()

	var font := GameManager.kenney_font()

	for slot_idx in range(_offered_modules.size()):
		var item := _offered_modules[slot_idx]
		var is_locked := _locked_modules[slot_idx] if slot_idx < _locked_modules.size() else false

		var rarity_col := _rarity_color(int(item.rarity))
		var border_col := Color(0.9, 0.75, 0.1) if is_locked else rarity_col
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(200.0, 150.0)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = rarity_col.darkened(0.6)
		card_style.border_color = border_col
		card_style.set_border_width_all(3 if is_locked else 2)
		card_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", card_style)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 5)
		card.add_child(card_vbox)

		if is_locked:
			var lock_badge := Label.new()
			lock_badge.text = "[LOCKED]"
			lock_badge.modulate = Color(0.9, 0.75, 0.1)
			lock_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if font:
				lock_badge.add_theme_font_override("font", font)
				lock_badge.add_theme_font_size_override("font_size", 11)
			card_vbox.add_child(lock_badge)

		var rarity_label := Label.new()
		rarity_label.text = "[%s]" % _rarity_name(int(item.rarity))
		rarity_label.modulate = rarity_col.lightened(0.2)
		rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if font:
			rarity_label.add_theme_font_override("font", font)
			rarity_label.add_theme_font_size_override("font_size", 12)
		card_vbox.add_child(rarity_label)

		var name_label := Label.new()
		var stack_count := player.count_upgrade(item.id)
		var stack_str := " (%d/%d)" % [stack_count, item.max_stacks] if item.max_stacks != -1 else ""
		name_label.text = item.display_name + stack_str
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if font:
			name_label.add_theme_font_override("font", font)
			name_label.add_theme_font_size_override("font_size", 15)
		card_vbox.add_child(name_label)

		var desc_label := Label.new()
		desc_label.text = item.description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if font:
			desc_label.add_theme_font_override("font", font)
			desc_label.add_theme_font_size_override("font_size", 12)
		card_vbox.add_child(desc_label)

		var cost_label := Label.new()
		cost_label.text = "%d Scrap" % item.shop_price
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if font:
			cost_label.add_theme_font_override("font", font)
			cost_label.add_theme_font_size_override("font_size", 13)
		card_vbox.add_child(cost_label)

		var at_cap := item.max_stacks != -1 and player.count_upgrade(item.id) >= item.max_stacks
		var can_buy := player.scrap >= item.shop_price and not at_cap
		var buy_btn := Button.new()
		if at_cap:
			buy_btn.text = "MAXED"
		elif can_buy:
			buy_btn.text = "Buy"
		else:
			buy_btn.text = "Need Scrap"
		buy_btn.disabled = not can_buy
		buy_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		buy_btn.pressed.connect(_on_buy_module_pressed.bind(player, slot_idx))
		if font:
			buy_btn.add_theme_font_override("font", font)
			buy_btn.add_theme_font_size_override("font_size", 13)
		card_vbox.add_child(buy_btn)

		var lock_btn := Button.new()
		lock_btn.text = "Unlock" if is_locked else "Lock"
		lock_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		lock_btn.pressed.connect(_on_toggle_module_lock.bind(player, slot_idx))
		if font:
			lock_btn.add_theme_font_override("font", font)
			lock_btn.add_theme_font_size_override("font_size", 11)
		card_vbox.add_child(lock_btn)

		var mod_pop := "[%s] %s\n\n%s\n\n%sCost: %d scrap" % [
			_rarity_name(int(item.rarity)), item.display_name,
			item.description,
			_upgrade_delta_summary(item) + ("\n\n" if not item.stat_deltas.is_empty() else ""),
			item.shop_price,
		]
		buy_btn.focus_entered.connect(_show_popover.bind(buy_btn, mod_pop, rarity_col))
		buy_btn.focus_exited.connect(_hide_popover)
		buy_btn.mouse_entered.connect(_show_popover.bind(buy_btn, mod_pop, rarity_col))
		buy_btn.mouse_exited.connect(_hide_popover)

		_module_container.add_child(card)

func _load_all_modules() -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	for path in _get_all_module_paths():
		var item: UpgradeData = ResourceLoader.load(path)
		if item != null:
			result.append(item)
	return result

func _get_all_module_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://resources/shop_items")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres") or fname.ends_with(".tres.remap"):
				paths.append("res://resources/shop_items/" + fname.trim_suffix(".remap"))
			fname = dir.get_next()
	return paths

func _on_buy_module_pressed(player: Player, slot_idx: int) -> void:
	if slot_idx >= _offered_modules.size():
		return
	var item := _offered_modules[slot_idx]
	AudioManager.play_ui_click()
	if player.scrap < item.shop_price:
		return
	player.scrap -= item.shop_price
	player.scrap_changed.emit(player.scrap)
	player.apply_upgrade(item)
	# Replace only the purchased module slot with a fresh item
	_replace_module_offer(slot_idx, player)
	_scrap_label.text = "Scrap: %d" % player.scrap
	_update_reroll_btn(player)
	_render_shop(player)
	_render_modules(player)
	_populate_purchased(player)
	_populate_stats(player)
	_update_title(player)

func _update_title(player: Player) -> void:
	var slots := player.character_data.weapon_slots if player.character_data else 6
	_title_label.text = "Weapon Shop  -  Player %d  (Slots: %d / %d)" % [
		_current_player_index + 1,
		player.weapons.size(),
		slots,
	]

func _reroll_cost() -> int:
	return 60 + (_wave_number * 10) + (_reroll_count * 80)

func _update_reroll_btn(player: Player) -> void:
	var cost := _reroll_cost()
	_reroll_btn.text = "Re-roll  [%d Scrap]" % cost
	_reroll_btn.disabled = player.scrap < cost

func _replace_weapon_offer(slot_idx: int) -> void:
	_offered_weapons.remove_at(slot_idx)
	_locked_weapons.remove_at(slot_idx)
	var pool := _load_all_weapons()
	var exclude: Array[WeaponData] = []
	for w in _offered_weapons:
		exclude.append(w)
	var filtered: Array[WeaponData] = []
	for w in pool:
		if not exclude.has(w):
			filtered.append(w)
	if filtered.is_empty():
		filtered = pool
	var weights := _get_rarity_weights(_wave_number)
	var replacement := _weighted_sample_weapons(filtered, weights, 1)
	if replacement.size() > 0:
		_offered_weapons.insert(slot_idx, replacement[0])
	elif pool.size() > 0:
		_offered_weapons.insert(slot_idx, pool[0])
	else:
		_offered_weapons.insert(slot_idx, _offered_weapons[0] if _offered_weapons.size() > 0 else null)
	_locked_weapons.insert(slot_idx, false)

func _replace_module_offer(slot_idx: int, player: Player) -> void:
	_offered_modules.remove_at(slot_idx)
	_locked_modules.remove_at(slot_idx)
	var pool := _filter_modules_for_player(_load_all_modules(), player)
	var exclude: Array[UpgradeData] = []
	for m in _offered_modules:
		exclude.append(m)
	var filtered: Array[UpgradeData] = []
	for m in pool:
		if not exclude.has(m):
			filtered.append(m)
	if filtered.is_empty():
		filtered = pool
	var weights := _get_rarity_weights(_wave_number)
	var replacement := _weighted_sample_modules(filtered, weights, 1)
	if replacement.size() > 0:
		_offered_modules.insert(slot_idx, replacement[0])
	elif pool.size() > 0:
		_offered_modules.insert(slot_idx, pool[0])
	else:
		_offered_modules.insert(slot_idx, _offered_modules[0] if _offered_modules.size() > 0 else null)
	_locked_modules.insert(slot_idx, false)

func _on_toggle_weapon_lock(player: Player, slot_idx: int) -> void:
	AudioManager.play_ui_click()
	if slot_idx < _locked_weapons.size():
		_locked_weapons[slot_idx] = not _locked_weapons[slot_idx]
	_render_shop(player)

func _on_toggle_module_lock(player: Player, slot_idx: int) -> void:
	AudioManager.play_ui_click()
	if slot_idx < _locked_modules.size():
		_locked_modules[slot_idx] = not _locked_modules[slot_idx]
	_render_modules(player)

func _on_reroll_pressed() -> void:
	if _players.is_empty() or _current_player_index >= _players.size():
		return
	var player := _players[_current_player_index]
	var cost := _reroll_cost()
	if player.scrap < cost:
		return
	AudioManager.play_ui_click()
	player.scrap -= cost
	player.scrap_changed.emit(player.scrap)
	_reroll_count += 1

	# Re-sample all unlocked weapon slots
	var pool_w := _load_all_weapons()
	var weights := _get_rarity_weights(_wave_number)
	for i in range(_offered_weapons.size()):
		if _locked_weapons[i]:
			continue
		# Build exclude list: locked offers
		var excl: Array[WeaponData] = []
		for j in range(_offered_weapons.size()):
			if j != i and _locked_weapons[j]:
				excl.append(_offered_weapons[j])
		var filtered: Array[WeaponData] = []
		for w in pool_w:
			if not excl.has(w):
				filtered.append(w)
		if filtered.is_empty():
			filtered = pool_w
		var rep := _weighted_sample_weapons(filtered, weights, 1)
		if rep.size() > 0:
			_offered_weapons[i] = rep[0]

	# Re-sample all unlocked module slots
	var pool_m := _filter_modules_for_player(_load_all_modules(), player)
	for i in range(_offered_modules.size()):
		if _locked_modules[i]:
			continue
		var excl_m: Array[UpgradeData] = []
		for j in range(_offered_modules.size()):
			if j != i and _locked_modules[j]:
				excl_m.append(_offered_modules[j])
		var filtered_m: Array[UpgradeData] = []
		for m in pool_m:
			if not excl_m.has(m):
				filtered_m.append(m)
		if filtered_m.is_empty():
			filtered_m = pool_m
		var rep_m := _weighted_sample_modules(filtered_m, weights, 1)
		if rep_m.size() > 0:
			_offered_modules[i] = rep_m[0]

	_scrap_label.text = "Scrap: %d" % player.scrap
	_update_reroll_btn(player)
	_render_shop(player)
	_render_modules(player)

func _close() -> void:
	visible = false
	ui_closed.emit()

# ---------------------------------------------------------------------------
# Popover helpers
# ---------------------------------------------------------------------------

func _show_popover(anchor: Control, text: String, rarity_col: Color) -> void:
	var pop_style := StyleBoxFlat.new()
	pop_style.bg_color = Color(0.05, 0.05, 0.1, 0.96)
	pop_style.border_color = rarity_col
	pop_style.set_border_width_all(2)
	pop_style.set_corner_radius_all(6)
	pop_style.content_margin_left = 10.0
	pop_style.content_margin_right = 10.0
	pop_style.content_margin_top = 8.0
	pop_style.content_margin_bottom = 8.0
	_popover.add_theme_stylebox_override("panel", pop_style)
	_popover_label.text = text
	_popover.visible = true
	# Position above the anchor; we need one frame for size to be measured,
	# but we can set an approximate position immediately.
	await get_tree().process_frame
	if not _popover.visible or not is_instance_valid(anchor):
		return
	var vp_size := get_viewport().get_visible_rect().size
	var anchor_rect := anchor.get_global_rect()
	var pop_size := _popover.size
	var px := anchor_rect.position.x + anchor_rect.size.x * 0.5 - pop_size.x * 0.5
	var py := anchor_rect.position.y - pop_size.y - 6.0
	px = clampf(px, 4.0, vp_size.x - pop_size.x - 4.0)
	py = clampf(py, 4.0, vp_size.y - pop_size.y - 4.0)
	_popover.position = Vector2(px, py)

func _hide_popover() -> void:
	_popover.visible = false

# ---------------------------------------------------------------------------
# Acquired upgrades section
# ---------------------------------------------------------------------------

func _populate_purchased(player: Player) -> void:
	for child in _purchased_container.get_children():
		child.queue_free()

	var font := GameManager.kenney_font()
	if player.acquired_upgrades.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(none yet)"
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		if font:
			empty_lbl.add_theme_font_override("font", font)
			empty_lbl.add_theme_font_size_override("font_size", 12)
		_purchased_container.add_child(empty_lbl)
		return

	# Deduplicate: count stacks per id, preserve first-seen order
	var seen_order: Array[StringName] = []
	var stack_map: Dictionary = {}  # StringName id -> int count
	var item_map: Dictionary = {}   # StringName id -> UpgradeData
	for item in player.acquired_upgrades:
		if not stack_map.has(item.id):
			seen_order.append(item.id)
			item_map[item.id] = item
			stack_map[item.id] = 1
		else:
			stack_map[item.id] += 1

	var rarity_letters: Array[String] = ["C", "U", "R", "E", "L"]
	for uid in seen_order:
		var item: UpgradeData = item_map[uid]
		var stack_count: int = stack_map[uid]
		var rarity_col := _rarity_color(int(item.rarity))
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(64.0, 64.0)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = rarity_col.darkened(0.65)
		card_style.border_color = rarity_col
		card_style.set_border_width_all(2)
		card_style.set_corner_radius_all(4)
		card_style.content_margin_left = 2.0
		card_style.content_margin_right = 2.0
		card_style.content_margin_top = 2.0
		card_style.content_margin_bottom = 2.0
		card.add_theme_stylebox_override("panel", card_style)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 1)
		card.add_child(card_vbox)

		# Top row: rarity letter + stack count (if > 1)
		var top_row := HBoxContainer.new()
		top_row.add_theme_constant_override("separation", 2)
		card_vbox.add_child(top_row)

		var rar_lbl := Label.new()
		rar_lbl.text = rarity_letters[int(item.rarity)] if int(item.rarity) < rarity_letters.size() else "?"
		rar_lbl.modulate = rarity_col.lightened(0.3)
		rar_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if font:
			rar_lbl.add_theme_font_override("font", font)
			rar_lbl.add_theme_font_size_override("font_size", 9)
		top_row.add_child(rar_lbl)

		if stack_count > 1:
			var count_lbl := Label.new()
			count_lbl.text = "x%d" % stack_count
			count_lbl.modulate = Color(1.0, 0.9, 0.3)
			count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if font:
				count_lbl.add_theme_font_override("font", font)
				count_lbl.add_theme_font_size_override("font_size", 9)
			top_row.add_child(count_lbl)

		# Icon or colored placeholder
		if item.icon != null:
			var icon_rect := TextureRect.new()
			icon_rect.texture = item.icon
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = Vector2(32.0, 32.0)
			icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_vbox.add_child(icon_rect)
		else:
			var ph := ColorRect.new()
			ph.custom_minimum_size = Vector2(32.0, 32.0)
			ph.color = rarity_col.darkened(0.2)
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_vbox.add_child(ph)

		# Short name (clipped to card width)
		var name_lbl := Label.new()
		name_lbl.text = item.display_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.clip_text = true
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if font:
			name_lbl.add_theme_font_override("font", font)
			name_lbl.add_theme_font_size_override("font_size", 8)
		card_vbox.add_child(name_lbl)

		# Invisible focus button for keyboard popover
		var focus_btn := Button.new()
		focus_btn.text = ""
		focus_btn.flat = true
		focus_btn.custom_minimum_size = Vector2(0.0, 1.0)
		focus_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		if font:
			focus_btn.add_theme_font_override("font", font)
			focus_btn.add_theme_font_size_override("font_size", 1)
		card_vbox.add_child(focus_btn)

		var stack_str := " (x%d)" % stack_count if stack_count > 1 else ""
		var pop_lines := "[%s] %s%s\n\n%s\n\n%s" % [
			_rarity_name(int(item.rarity)), item.display_name, stack_str,
			item.description,
			_upgrade_delta_summary(item),
		]
		card.mouse_entered.connect(_show_popover.bind(card, pop_lines, rarity_col))
		card.mouse_exited.connect(_hide_popover)
		focus_btn.focus_entered.connect(_show_popover.bind(focus_btn, pop_lines, rarity_col))
		focus_btn.focus_exited.connect(_hide_popover)

		_purchased_container.add_child(card)

func _upgrade_delta_summary(item: UpgradeData) -> String:
	if item.stat_deltas.is_empty():
		return ""
	var stat_names := {
		UpgradeData.StatKey.MAX_HEALTH:         "Max HP",
		UpgradeData.StatKey.MOVE_SPEED:         "Move Spd",
		UpgradeData.StatKey.ARMOR:              "Armor",
		UpgradeData.StatKey.DAMAGE:             "Damage",
		UpgradeData.StatKey.FIRE_RATE:          "Fire Rate",
		UpgradeData.StatKey.PROJECTILE_SPEED:   "Proj Spd",
		UpgradeData.StatKey.XP_MULTIPLIER:      "XP Mult",
		UpgradeData.StatKey.COIN_MULTIPLIER:    "Coin Mult",
		UpgradeData.StatKey.LIFESTEAL:          "Lifesteal",
		UpgradeData.StatKey.RANGE:              "Range",
		UpgradeData.StatKey.SPREAD:             "Spread",
		UpgradeData.StatKey.DAMAGE_BLOCK_CHANCE: "Block Chance",
		UpgradeData.StatKey.SCRAP_BONUS_CHANCE: "Scrap Bonus",
		UpgradeData.StatKey.INSTANT_HEAL:       "Instant Heal",
	}
	var parts: Array[String] = []
	for key in item.stat_deltas:
		var delta: float = item.stat_deltas[key]
		var label: String = stat_names.get(key, "Stat %d" % key)
		var sign_str := "+" if delta >= 0.0 else ""
		var entry := "%s: %s%.4g" % [label, sign_str, delta]
		if delta < 0.0:
			entry = "(-) " + entry
		parts.append(entry)
	return "\n".join(parts)

# ---------------------------------------------------------------------------
# Ship & weapon stats panel
# ---------------------------------------------------------------------------

func _populate_stats(player: Player) -> void:
	for child in _stats_container.get_children():
		child.queue_free()

	var font := GameManager.kenney_font()
	var base := player.character_data

	# Helper to add a single stat row
	var _add_row := func(label: String, base_val: float, cur_val: float, fmt: String) -> void:
		var lbl := Label.new()
		var cur_str  := fmt % cur_val
		var buffed := cur_val > base_val + 0.001
		if buffed:
			lbl.text = "%s: %s  (base: %s)" % [label, cur_str, fmt % base_val]
			lbl.modulate = Color(0.6, 1.0, 0.6)
		else:
			lbl.text = "%s: %s" % [label, cur_str]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		if font:
			lbl.add_theme_font_override("font", font)
			lbl.add_theme_font_size_override("font_size", 12)
		_stats_container.add_child(lbl)

	# Ship stats
	var header := Label.new()
	header.text = "Ship"
	header.modulate = Color(0.8, 0.8, 1.0)
	if font:
		header.add_theme_font_override("font", font)
		header.add_theme_font_size_override("font_size", 13)
	_stats_container.add_child(header)

	var base_hp   := base.max_health if base else 100.0
	var base_spd  := base.move_speed if base else 200.0
	var base_arm  := base.armor if base else 0.0
	var base_xp   := base.xp_multiplier if base else 1.0
	var base_coin := base.coin_multiplier if base else 1.0

	# HP shown as cur/max rather than base comparison
	var hp_lbl := Label.new()
	var hp_buffed := player.max_health > base_hp + 0.001
	if hp_buffed:
		hp_lbl.text = "HP: %.0f / %.0f  (base: %.0f)" % [player.current_health, player.max_health, base_hp]
		hp_lbl.modulate = Color(0.6, 1.0, 0.6)
	else:
		hp_lbl.text = "HP: %.0f / %.0f" % [player.current_health, player.max_health]
	if font:
		hp_lbl.add_theme_font_override("font", font)
		hp_lbl.add_theme_font_size_override("font_size", 12)
	_stats_container.add_child(hp_lbl)

	_add_row.call("Move Spd", base_spd, player.move_speed, "%.0f")
	_add_row.call("Armor",    base_arm,  player.armor,      "%.1f")
	_add_row.call("XP Mult",  base_xp,   player.xp_multiplier, "%.2f")
	_add_row.call("Coin Mult", base_coin, player.coin_multiplier, "%.2f")
	if player.lifesteal > 0.001:
		_add_row.call("Lifesteal", 0.0, player.lifesteal, "%.1f%%")
	if player.damage_block_chance > 0.001:
		_add_row.call("Block", 0.0, player.damage_block_chance * 100.0, "%.0f%%")
	if player.scrap_bonus_chance > 0.001:
		_add_row.call("Scrap Bonus", 0.0, player.scrap_bonus_chance * 100.0, "%.0f%%")

	# Per-weapon stats
	for weapon_node in player.weapons:
		var wdata: WeaponData = weapon_node.get("weapon_data")
		if wdata == null:
			continue
		var rarity_col := _rarity_color(int(wdata.rarity))
		var class_idx: int = int(wdata.weapon_class)
		var class_str: String = WEAPON_CLASS_NAMES[class_idx] if class_idx < WEAPON_CLASS_NAMES.size() else "?"

		var sep := Label.new()
		sep.text = ""
		sep.custom_minimum_size = Vector2(0.0, 4.0)
		_stats_container.add_child(sep)

		var w_header := Label.new()
		w_header.text = "%s  [%s]" % [wdata.display_name, class_str]
		w_header.modulate = rarity_col.lightened(0.15)
		if font:
			w_header.add_theme_font_override("font", font)
			w_header.add_theme_font_size_override("font_size", 13)
		_stats_container.add_child(w_header)

		var dmg_mult: float = weapon_node.get("damage_multiplier") * weapon_node.get("passive_multiplier")
		var eff_dmg: float   = weapon_node.get("damage") * dmg_mult
		var base_dmg: float  = wdata.damage

		# Damage row: shows base and effective with multiplier note
		var dmg_lbl := Label.new()
		if absf(eff_dmg - base_dmg) > 0.5 or absf(dmg_mult - 1.0) > 0.01:
			dmg_lbl.text = "DMG: %.0f -> %.0f (x%.2f)" % [base_dmg, eff_dmg, dmg_mult]
			dmg_lbl.modulate = Color(0.6, 1.0, 0.6)
		else:
			dmg_lbl.text = "DMG: %.0f" % base_dmg
		if font:
			dmg_lbl.add_theme_font_override("font", font)
			dmg_lbl.add_theme_font_size_override("font_size", 12)
		_stats_container.add_child(dmg_lbl)

		# Generic weapon stat rows
		var w_add_row := func(label: String, base_v: float, cur_v: float, fmt: String) -> void:
			var wlbl := Label.new()
			var buffed := cur_v > base_v + 0.001
			var nerfed := cur_v < base_v - 0.001
			if buffed:
				wlbl.text = "%s: %s -> %s" % [label, fmt % base_v, fmt % cur_v]
				wlbl.modulate = Color(0.6, 1.0, 0.6)
			elif nerfed:
				wlbl.text = "%s: %s -> %s" % [label, fmt % base_v, fmt % cur_v]
				wlbl.modulate = Color(1.0, 0.6, 0.6)
			else:
				wlbl.text = "%s: %s" % [label, fmt % cur_v]
			if font:
				wlbl.add_theme_font_override("font", font)
				wlbl.add_theme_font_size_override("font_size", 12)
			_stats_container.add_child(wlbl)

		w_add_row.call("Rate",   wdata.fire_rate,       weapon_node.get("fire_rate"),       "%.1f/s")
		w_add_row.call("Range",  wdata.range,           weapon_node.get("range"),           "%.0f")
		w_add_row.call("Spread", wdata.spread,          weapon_node.get("spread"),          "%.2f")
		w_add_row.call("Shots",  float(wdata.projectile_count), float(weapon_node.get("projectile_count")), "%.0f")

# ---------------------------------------------------------------------------
# Weapon icon helper
# ---------------------------------------------------------------------------

func _get_weapon_icon_texture(wdata: WeaponData) -> Texture2D:
	if wdata == null:
		return null
	if wdata.icon != null:
		return wdata.icon
	var ammo_to_gun: Dictionary = {
		WeaponData.AmmoType.BULLET:  "gun01.png",
		WeaponData.AmmoType.LASER:   "gun05.png",
		WeaponData.AmmoType.ROCKET:  "gun09.png",
		WeaponData.AmmoType.MINE:    "gun07.png",
		WeaponData.AmmoType.ORBITAL: "gun06.png",
		WeaponData.AmmoType.BEAM:    "gun04.png",
	}
	var fname: String = ammo_to_gun.get(wdata.ammo_type, "gun01.png")
	var path := "res://assets/sprites/" + fname
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null

# ---------------------------------------------------------------------------
# Stats panel toggle
# ---------------------------------------------------------------------------

func _on_stats_toggle() -> void:
	_stats_overlay.visible = not _stats_overlay.visible
	_stats_toggle_btn.text = "Ship Stats  ^" if _stats_overlay.visible else "Ship Stats  v"
