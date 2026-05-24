extends CanvasLayer

## BetweenWaveUI - builds its own UI nodes. Shown after each wave for upgrade selection.

signal ui_closed()

const CHOICES_COUNT: int = 3

# Maps each StatKey to a short strategy path name used for build-path display and
# momentum weighting. Upgrades that boost these stats push the player down that path.
const _STAT_PATH: Dictionary = {
	UpgradeData.StatKey.MAX_HEALTH:          &"TANK",
	UpgradeData.StatKey.ARMOR:               &"TANK",
	UpgradeData.StatKey.DAMAGE_BLOCK_CHANCE: &"TANK",
	UpgradeData.StatKey.SHIELD_MAX:          &"SHIELD",
	UpgradeData.StatKey.SHIELD_REGEN_RATE:   &"SHIELD",
	UpgradeData.StatKey.MOVE_SPEED:          &"SPEED",
	UpgradeData.StatKey.DODGE_CHANCE:        &"SPEED",
	UpgradeData.StatKey.LIFESTEAL:           &"PREDATOR",
	UpgradeData.StatKey.ON_KILL_HEAL:        &"PREDATOR",
	UpgradeData.StatKey.HP_REGEN:            &"PREDATOR",
	UpgradeData.StatKey.INSTANT_HEAL:        &"PREDATOR",
	UpgradeData.StatKey.DAMAGE:              &"GUNSLINGER",
	UpgradeData.StatKey.FIRE_RATE:           &"GUNSLINGER",
	UpgradeData.StatKey.CRIT_CHANCE:         &"GUNSLINGER",
	UpgradeData.StatKey.CRIT_MULTIPLIER:     &"GUNSLINGER",
	UpgradeData.StatKey.ARMOR_PEN:           &"GUNSLINGER",
	UpgradeData.StatKey.KNOCKBACK_FORCE:     &"GUNSLINGER",
	UpgradeData.StatKey.PROJECTILE_SPEED:    &"SPECIALIST",
	UpgradeData.StatKey.RANGE:               &"SPECIALIST",
	UpgradeData.StatKey.SPREAD:              &"SPECIALIST",
	UpgradeData.StatKey.BOUNCE_COUNT:        &"SPECIALIST",
	UpgradeData.StatKey.CHAIN_COUNT:         &"SPECIALIST",
	UpgradeData.StatKey.FORK_COUNT:          &"SPECIALIST",
	UpgradeData.StatKey.XP_MULTIPLIER:       &"SCAVENGER",
	UpgradeData.StatKey.COIN_MULTIPLIER:     &"SCAVENGER",
	UpgradeData.StatKey.SCRAP_BONUS_CHANCE:  &"SCAVENGER",
}

# Accent color for each build path, used to tint card borders.
const _PATH_COLOR: Dictionary = {
	&"TANK":       Color(0.9, 0.55, 0.15),
	&"SHIELD":     Color(0.2, 0.7,  1.0),
	&"SPEED":      Color(0.3, 1.0,  0.5),
	&"PREDATOR":   Color(1.0, 0.25, 0.25),
	&"GUNSLINGER": Color(1.0, 0.9,  0.15),
	&"SPECIALIST": Color(0.75, 0.25, 1.0),
	&"SCAVENGER":  Color(0.25, 0.9,  0.9),
}

var _players: Array[Player] = []
var _current_player_index: int = 0
var _wave_number: int = 0
var _wave_manager: WaveManager = null
var _remaining_picks: int = 0
var _total_picks: int = 0

var _title_label: Label
var _power_label: Label
var _choices_container: HBoxContainer
var _continue_button: Button
var _scrap_label: Label
var _reroll_btn: Button
var _reroll_count: int = 0

func _ready() -> void:
	# Must keep processing while the game tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5

	# Root control fills the viewport so all children receive mouse input correctly.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -330.0
	vbox.offset_top = -210.0
	vbox.offset_right = 330.0
	vbox.offset_bottom = 240.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(vbox)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_font := GameManager.kenney_font()
	if title_font:
		_title_label.add_theme_font_override("font", title_font)
		_title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_title_label)

	_power_label = Label.new()
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.modulate = Color(1.0, 0.82, 0.2)
	if title_font:
		_power_label.add_theme_font_override("font", title_font)
		_power_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_power_label)

	_continue_button = Button.new()
	_continue_button.text = "Skip"
	_continue_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(_continue_button)

	_choices_container = HBoxContainer.new()
	_choices_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_choices_container.add_theme_constant_override("separation", 16)
	vbox.add_child(_choices_container)

	_scrap_label = Label.new()
	_scrap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scrap_label.modulate = Color(0.3, 0.9, 1.0)
	if title_font:
		_scrap_label.add_theme_font_override("font", title_font)
		_scrap_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_scrap_label)

	_reroll_btn = Button.new()
	_reroll_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	if title_font:
		_reroll_btn.add_theme_font_override("font", title_font)
		_reroll_btn.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_reroll_btn)

func show_for_players(players: Array[Player], wave_number: int, wave_manager: WaveManager) -> void:
	_players = players
	_wave_number = wave_number
	_wave_manager = wave_manager
	_current_player_index = 0
	# If no player earned any level-ups this wave, skip the UI entirely.
	var any_picks := false
	for p in _players:
		if p.pending_upgrades > 0:
			any_picks = true
			break
	if not any_picks:
		_close()
		return
	visible = true
	_show_level_up_for_player()

func _show_level_up_for_player() -> void:
	# Advance past any players who earned zero level-ups this wave.
	while _current_player_index < _players.size() and _players[_current_player_index].pending_upgrades == 0:
		_current_player_index += 1
	if _current_player_index >= _players.size():
		_close()
		return
	var player := _players[_current_player_index]
	_remaining_picks = player.pending_upgrades
	_total_picks = _remaining_picks
	player.pending_upgrades = 0
	var pick_text := ""
	if _total_picks > 1:
		pick_text = " (Pick 1 of %d)" % _total_picks
	_title_label.text = "Wave %d cleared!\nPlayer %d - Choose an upgrade:%s" % [_wave_number, _current_player_index + 1, pick_text]
	var pw_score := PlayerPowerCalculator.calc_display_power(player)
	var pw_lv    := PlayerPowerCalculator.power_to_level(pw_score)
	var pw_prog  := PlayerPowerCalculator.power_level_progress(pw_score)
	var path_counts := _player_path_counts(player)
	var dom_path := _dominant_path(path_counts)
	var path_suffix := ""
	if dom_path != &"":
		var dom_cnt: int = path_counts[dom_path]
		path_suffix = "  |  %s ×%d" % [str(dom_path), dom_cnt]
	_power_label.text = "Power Level %d  (%.0f%% to Lv %d)%s" % [pw_lv, pw_prog * 100.0, pw_lv + 1, path_suffix]
	_reroll_count = 0
	_populate_choices(player)

## Infer the primary build-path of an upgrade from its stat_deltas (or explicit build_path).
func _infer_path(data: UpgradeData) -> StringName:
	if data.build_path != &"":
		return data.build_path
	# Pick the stat key with the largest absolute delta.
	var best_key: int = -1
	var best_mag: float = 0.0
	for key in data.stat_deltas:
		var mag: float = absf(float(data.stat_deltas[key]))
		if mag > best_mag:
			best_mag = mag
			best_key = key
	if best_key >= 0 and _STAT_PATH.has(best_key):
		return _STAT_PATH[best_key]
	# Passive-only: use synergy_source if applicable.
	if data.synergy_scale != 0.0 and _STAT_PATH.has(data.synergy_source):
		return _STAT_PATH[data.synergy_source]
	return &""

## Returns {path_name: count} for all upgrades the player has already acquired.
func _player_path_counts(player: Player) -> Dictionary:
	var counts: Dictionary = {}
	for upgrade in player.acquired_upgrades:
		var path := _infer_path(upgrade)
		if path != &"":
			counts[path] = counts.get(path, 0) + 1
	return counts

## Returns the name of the player's most-invested path (empty string if no upgrades yet).
func _dominant_path(path_counts: Dictionary) -> StringName:
	var best: StringName = &""
	var best_cnt: int = 0
	for path in path_counts:
		if path_counts[path] > best_cnt:
			best_cnt = path_counts[path]
			best = path
	return best

## True if this upgrade has a synergy that will scale with the player's already-built stats.
func _has_active_synergy(data: UpgradeData, player: Player) -> bool:
	if data.synergy_scale == 0.0:
		return false
	for u in player.acquired_upgrades:
		if u.stat_deltas.has(data.synergy_source):
			return true
	return false

func _populate_choices(player: Player) -> void:
	for child in _choices_container.get_children():
		child.queue_free()

	var all_upgrades := _load_all_upgrades()
	var weights := _get_rarity_weights(_wave_number)
	var preferred: Array[StringName] = []
	var excluded: Array[StringName] = []
	if player.character_data:
		preferred = player.character_data.preferred_upgrades
		excluded = player.character_data.excluded_upgrades
	if excluded.size() > 0:
		all_upgrades = all_upgrades.filter(func(u: UpgradeData) -> bool: return u.id not in excluded)
	var path_counts := _player_path_counts(player)
	var offered := _weighted_sample(all_upgrades, weights, CHOICES_COUNT, preferred, path_counts)

	var card_font := GameManager.kenney_font()
	for data in offered:
		var pw_d := PlayerPowerCalculator.module_power_delta(data, player)
		var pw_suffix := ("\n+%.2f power" % pw_d) if pw_d >= 0.01 else ""

		var path := _infer_path(data)
		var path_cnt: int = path_counts.get(path, 0) if path != &"" else 0
		var has_syn := _has_active_synergy(data, player)

		# Build the tag line appended below the description.
		var tag_parts: Array[String] = []
		if path != &"":
			tag_parts.append("▶ " + str(path))
		if has_syn:
			tag_parts.append("⚡ SYNERGY")
		var tag_line := ("\n─────────────────\n" + "  ".join(tag_parts)) if not tag_parts.is_empty() else ""

		var btn := Button.new()
		btn.text = "[%s]\n%s\n%s%s%s" % [_rarity_name(data.rarity), data.display_name, data.description, pw_suffix, tag_line]
		btn.custom_minimum_size = Vector2(180.0, 130.0)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if card_font:
			btn.add_theme_font_override("font", card_font)
			btn.add_theme_font_size_override("font_size", 14)

		var rarity_col := _rarity_color(data.rarity)
		# Tint card toward path color when player has momentum (2+ upgrades on path).
		var border_col := rarity_col
		var bg_col     := rarity_col.darkened(0.55)
		var border_w   := 2
		if path != &"" and path_cnt >= 2 and _PATH_COLOR.has(path):
			var pcol: Color = _PATH_COLOR[path]
			bg_col     = bg_col.lerp(pcol.darkened(0.6), 0.35)
			border_col = border_col.lerp(pcol, 0.5)
			border_w   = 3
		if has_syn:
			# Cyan rim indicates an active synergy bonus.
			border_col = border_col.lerp(Color(0.25, 1.0, 1.0), 0.45)
			border_w   = maxi(border_w, 3)

		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color     = bg_col
		normal_style.border_color = border_col
		normal_style.set_border_width_all(border_w)
		normal_style.set_corner_radius_all(6)
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color     = rarity_col.darkened(0.3)
		hover_style.border_color = border_col.lightened(0.3)
		hover_style.set_border_width_all(border_w)
		hover_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", normal_style)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", hover_style)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)

		btn.pressed.connect(_on_upgrade_chosen.bind(player, data))
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		_choices_container.add_child(btn)

	# Update scrap and reroll button
	_update_scrap_display(player)
	_update_reroll_btn(player)

	# Explicitly wire left/right focus neighbors so joystick navigation is reliable
	var btns := _choices_container.get_children()
	for i in btns.size():
		btns[i].focus_neighbor_left   = btns[(i - 1 + btns.size()) % btns.size()].get_path()
		btns[i].focus_neighbor_right  = btns[(i + 1) % btns.size()].get_path()
		btns[i].focus_neighbor_top    = _continue_button.get_path()
		btns[i].focus_neighbor_bottom = _reroll_btn.get_path()
	if btns.size() > 0:
		_continue_button.focus_neighbor_top    = _reroll_btn.get_path()
		_continue_button.focus_neighbor_bottom = btns[0].get_path()
		_reroll_btn.focus_neighbor_top    = btns[0].get_path()
		_reroll_btn.focus_neighbor_bottom = _continue_button.get_path()

	# Give focus to the first card so gamepad can navigate immediately
	if btns.size() > 0:
		btns[0].grab_focus()

# Returns per-rarity weights [Common, Uncommon, Rare, Epic, Legendary]
# linearly scaled by wave progress so higher rarities become more likely over time.
func _get_rarity_weights(wave: int) -> Array[float]:
	var t := clampf(float(wave - 1) / 9.0, 0.0, 1.0)
	var t2 := clampf((float(wave) - 12.0) / 6.0, 0.0, 1.0)  # for mythic, starts wave 12
	var weights: Array[float] = [
		lerpf(60.0, 25.0, t),   # COMMON
		lerpf(25.0, 28.0, t),   # UNCOMMON
		lerpf(12.0, 25.0, t),   # RARE
		lerpf(3.0,  15.0, t),   # EPIC
		lerpf(0.0,  5.0,  t),   # LEGENDARY
		lerpf(0.0,  3.0,  t2),  # MYTHIC - only after wave 12
	]
	return weights

# Draws `count` unique upgrades from pool, weighted by each item's rarity weight.
# Items whose id appears in `preferred` get 3x weight.
# Items whose build path matches a path the player has already invested in get
# extra "momentum" weight: 1 prior upgrade → 1.5x, 2 → 2.5x, 3+ → 4x.
func _weighted_sample(pool: Array[UpgradeData], weights: Array[float], count: int, preferred: Array[StringName] = [], path_counts: Dictionary = {}) -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	var remaining := pool.duplicate()
	var attempts := 0
	while result.size() < count and remaining.size() > 0 and attempts < 1000:
		attempts += 1
		var total := 0.0
		for item in remaining:
			total += _item_weight(item, weights, preferred, path_counts)
		if total <= 0.0:
			break
		var roll := randf() * total
		var acc := 0.0
		for i in range(remaining.size()):
			acc += _item_weight(remaining[i], weights, preferred, path_counts)
			if roll <= acc:
				result.append(remaining[i])
				remaining.remove_at(i)
				break
	return result

func _item_weight(item: UpgradeData, weights: Array[float], preferred: Array[StringName], path_counts: Dictionary) -> float:
	var path := _infer_path(item)
	var path_cnt: int = path_counts.get(path, 0) if path != &"" else 0
	var path_mult: float
	if path_cnt >= 3:   path_mult = 4.0
	elif path_cnt >= 2: path_mult = 2.5
	elif path_cnt >= 1: path_mult = 1.5
	else:               path_mult = 1.0
	return weights[item.rarity] * (3.0 if item.id in preferred else 1.0) * path_mult

func _rarity_color(rarity: int) -> Color:
	match rarity:
		0: return Color(0.55, 0.55, 0.55)   # COMMON - grey
		1: return Color(0.15, 0.75, 0.3)    # UNCOMMON - green
		2: return Color(0.2,  0.45, 0.95)   # RARE - blue
		3: return Color(0.65, 0.1,  0.95)   # EPIC - purple
		4: return Color(0.95, 0.7,  0.0)    # LEGENDARY - gold
		5: return Color(1.0,  0.1,  0.8)    # MYTHIC - hot magenta
		_: return Color(0.55, 0.55, 0.55)

func _rarity_name(rarity: int) -> String:
	match rarity:
		0: return "COMMON"
		1: return "UNCOMMON"
		2: return "RARE"
		3: return "EPIC"
		4: return "LEGENDARY"
		5: return "MYTHIC"
		_: return "COMMON"

func _load_all_upgrades() -> Array[UpgradeData]:
	var upgrades: Array[UpgradeData] = []
	var dir := DirAccess.open("res://resources/upgrades")
	if dir:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if fname.ends_with(".tres") or fname.ends_with(".tres.remap"):
				var res = ResourceLoader.load("res://resources/upgrades/" + fname.trim_suffix(".remap"))
				if res is UpgradeData:
					upgrades.append(res)
			fname = dir.get_next()
	return upgrades

func _reroll_cost(player: Player) -> int:
	var power_level := PlayerPowerCalculator.power_to_level(PlayerPowerCalculator.calc_display_power(player))
	return 15 + (power_level - 1) * 2 + _reroll_count * 20

func _update_scrap_display(player: Player) -> void:
	if is_instance_valid(_scrap_label):
		_scrap_label.text = "Scrap: %d" % player.scrap

func _update_reroll_btn(player: Player) -> void:
	if not is_instance_valid(_reroll_btn):
		return
	var cost := _reroll_cost(player)
	_reroll_btn.text = "Reroll Choices  [%d Scrap]" % cost
	_reroll_btn.disabled = player.scrap < cost

func _on_reroll_pressed() -> void:
	if _current_player_index >= _players.size():
		return
	var player := _players[_current_player_index]
	var cost := _reroll_cost(player)
	if player.scrap < cost:
		return
	AudioManager.play_ui_click()
	player.scrap -= cost
	player.scrap_changed.emit(player.scrap)
	_reroll_count += 1
	_populate_choices(player)

func _on_upgrade_chosen(player: Player, data: UpgradeData) -> void:
	AudioManager.play_ui_click()
	player.apply_upgrade(data)
	_remaining_picks -= 1
	if _remaining_picks > 0:
		var pick_num := _total_picks - _remaining_picks + 1
		_title_label.text = "Wave %d cleared!\nPlayer %d - Choose an upgrade: (Pick %d of %d)" % [
			_wave_number, _current_player_index + 1, pick_num, _total_picks
		]
		_populate_choices(player)
	else:
		_current_player_index += 1
		_show_level_up_for_player()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_continue_pressed()

func _on_continue_pressed() -> void:
	AudioManager.play_ui_click()
	# Skip all remaining picks for the current player.
	_remaining_picks = 0
	_current_player_index += 1
	_show_level_up_for_player()

func _close() -> void:
	visible = false
	ui_closed.emit()
