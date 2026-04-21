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

var _title_label: Label
var _scrap_label: Label
var _shop_container: HBoxContainer
var _module_container: HBoxContainer
var _loadout_container: HBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -430.0
	vbox.offset_top = -330.0
	vbox.offset_right = 430.0
	vbox.offset_bottom = 330.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
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

	var loadout_title := Label.new()
	loadout_title.text = "Current Loadout  (sell for 50% scrap refund)"
	loadout_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font:
		loadout_title.add_theme_font_override("font", font)
		loadout_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(loadout_title)

	var loadout_scroll := ScrollContainer.new()
	loadout_scroll.custom_minimum_size = Vector2(0.0, 90.0)
	loadout_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	loadout_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(loadout_scroll)

	_loadout_container = HBoxContainer.new()
	_loadout_container.add_theme_constant_override("separation", 10)
	loadout_scroll.add_child(_loadout_container)

	var skip_btn := Button.new()
	skip_btn.text = "Continue"
	skip_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	skip_btn.pressed.connect(_on_skip_pressed)
	if font:
		skip_btn.add_theme_font_override("font", font)
		skip_btn.add_theme_font_size_override("font_size", 16)
	vbox.add_child(skip_btn)

func show_for_players(players: Array, projectile_parent: Node2D) -> void:
	_players.clear()
	for p in players:
		_players.append(p)
	_projectile_parent = projectile_parent
	_current_player_index = 0
	visible = true
	_show_shop_for_player()

func _show_shop_for_player() -> void:
	var player := _players[_current_player_index]
	var slots := player.character_data.weapon_slots if player.character_data else 2
	_title_label.text = "Weapon Shop  -  Player %d  (Slots: %d / %d)" % [
		_current_player_index + 1,
		player.weapons.size(),
		slots,
	]
	_scrap_label.text = "Scrap: %d" % player.scrap
	_populate_shop(player)
	_populate_modules(player)
	_populate_loadout(player)

func _populate_shop(player: Player) -> void:
	for child in _shop_container.get_children():
		child.queue_free()

	var font := GameManager.kenney_font()
	var all_paths := _get_all_weapon_paths()
	all_paths.shuffle()
	var offered := all_paths.slice(0, WEAPON_OFFER_COUNT)

	for path in offered:
		var wdata: WeaponData = ResourceLoader.load(path)
		if wdata == null:
			continue

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

		# Card panel
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(210.0, 170.0)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 6)
		card.add_child(card_vbox)

		var class_label := Label.new()
		class_label.text = "[%s]%s" % [class_name_str, affinity_str]
		class_label.modulate = affinity_color
		class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if font:
			class_label.add_theme_font_override("font", font)
			class_label.add_theme_font_size_override("font_size", 13)
		card_vbox.add_child(class_label)

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

		var slots := player.character_data.weapon_slots if player.character_data else 2
		var is_full := player.weapons.size() >= slots
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
		buy_btn.pressed.connect(_on_buy_pressed.bind(player, wdata))
		if font:
			buy_btn.add_theme_font_override("font", font)
			buy_btn.add_theme_font_size_override("font_size", 14)
		card_vbox.add_child(buy_btn)

		_shop_container.add_child(card)

func _get_all_weapon_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://resources/weapons")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				paths.append("res://resources/weapons/" + fname)
			fname = dir.get_next()
	return paths

func _populate_loadout(player: Player) -> void:
	for child in _loadout_container.get_children():
		child.queue_free()

	var font := GameManager.kenney_font()
	for weapon_node in player.weapons:
		var wdata: WeaponData = weapon_node.get("weapon_data")
		if wdata == null:
			continue
		var sell_value: int = max(1, wdata.shop_cost / 2)

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(150.0, 80.0)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 4)
		card.add_child(card_vbox)

		var name_label := Label.new()
		name_label.text = wdata.display_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if font:
			name_label.add_theme_font_override("font", font)
			name_label.add_theme_font_size_override("font_size", 13)
		card_vbox.add_child(name_label)

		var sell_btn := Button.new()
		sell_btn.text = "Sell +%d" % sell_value
		sell_btn.disabled = player.weapons.size() <= 1
		sell_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		sell_btn.pressed.connect(_on_sell_pressed.bind(player, weapon_node))
		if font:
			sell_btn.add_theme_font_override("font", font)
			sell_btn.add_theme_font_size_override("font_size", 13)
		card_vbox.add_child(sell_btn)

		_loadout_container.add_child(card)

func _on_sell_pressed(player: Player, weapon_node: Node) -> void:
	if player.weapons.size() <= 1:
		return
	AudioManager.play_ui_click()
	var wdata: WeaponData = weapon_node.get("weapon_data")
	var sell_value: int = 1
	if wdata != null:
		sell_value = max(1, wdata.shop_cost / 2)
	player.weapons.erase(weapon_node)
	weapon_node.queue_free()
	player.scrap += sell_value
	player.scrap_changed.emit(player.scrap)
	_show_shop_for_player()

func _on_buy_pressed(player: Player, wdata: WeaponData) -> void:
	AudioManager.play_ui_click()
	if player.scrap < wdata.shop_cost:
		return
	player.scrap -= wdata.shop_cost
	player.scrap_changed.emit(player.scrap)
	var weapon := BaseWeapon.new()
	weapon.weapon_data = wdata
	weapon._projectile_parent = _projectile_parent
	player.add_weapon(weapon)
	# Refresh this player's shop view so slot count and scrap are updated
	_show_shop_for_player()

func _on_skip_pressed() -> void:
	AudioManager.play_ui_click()
	_current_player_index += 1
	if _current_player_index < _players.size():
		_show_shop_for_player()
	else:
		_close()

func _populate_modules(player: Player) -> void:
	for child in _module_container.get_children():
		child.queue_free()

	var font := GameManager.kenney_font()
	var all_paths := _get_all_module_paths()
	all_paths.shuffle()
	var offered := all_paths.slice(0, 3)

	for path in offered:
		var item: UpgradeData = ResourceLoader.load(path)
		if item == null:
			continue

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(200.0, 140.0)
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.04, 0.18, 0.22)
		card_style.border_color = Color(0.2, 0.7, 0.8)
		card_style.set_border_width_all(2)
		card_style.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", card_style)

		var card_vbox := VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 5)
		card.add_child(card_vbox)

		var name_label := Label.new()
		name_label.text = item.display_name
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

		var can_buy := player.scrap >= item.shop_price
		var buy_btn := Button.new()
		buy_btn.text = "Buy" if can_buy else "Need Scrap"
		buy_btn.disabled = not can_buy
		buy_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		buy_btn.pressed.connect(_on_buy_module_pressed.bind(player, item))
		if font:
			buy_btn.add_theme_font_override("font", font)
			buy_btn.add_theme_font_size_override("font_size", 13)
		card_vbox.add_child(buy_btn)

		_module_container.add_child(card)

func _get_all_module_paths() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://resources/shop_items")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres"):
				paths.append("res://resources/shop_items/" + fname)
			fname = dir.get_next()
	return paths

func _on_buy_module_pressed(player: Player, item: UpgradeData) -> void:
	AudioManager.play_ui_click()
	if player.scrap < item.shop_price:
		return
	player.scrap -= item.shop_price
	player.scrap_changed.emit(player.scrap)
	player.apply_upgrade(item)
	_show_shop_for_player()

func _close() -> void:
	visible = false
	ui_closed.emit()
