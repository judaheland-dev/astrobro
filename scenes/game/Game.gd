extends Node2D

## Game - root scene. Builds itself entirely in code; no editor wiring needed.

const ARENA_HALF_W: float = 960.0
const ARENA_HALF_H: float = 600.0
const WALL_THICKNESS: float = 32.0

# Container for all game-world nodes (players, enemies, wave manager, etc.).
# Disabling this single node freezes gameplay without touching the UI subtree.
var _gameplay_root: Node

var _players_container: Node2D
var _enemies_container: Node2D
var _projectiles_container: Node2D
var _hud: CanvasLayer
var _between_wave_ui: CanvasLayer
var _shop_ui: CanvasLayer
var _game_over_ui: CanvasLayer
var _camera: Camera2D

var _players: Array[Player] = []
var _extra_targets: Array[Node] = []   # decoys and other non-player targets
var _wave_manager: WaveManager = WaveManager.new()
var _power_calculator: PlayerPowerCalculator = PlayerPowerCalculator.new()
var _game_mode: GameMode = null
var _current_wave_number: int = 1

# PVP Overlord mode nodes
var _overlord_controller: Node2D = null
var _overlord_hud: CanvasLayer = null
var _overlord_shop_ui: CanvasLayer = null

# ---------------------------------------------------------------------------
# Camera shake
# ---------------------------------------------------------------------------
var _shake_trauma: float = 0.0
const SHAKE_DECAY: float = 4.0
const SHAKE_MAX_OFFSET: float = 18.0

func _add_trauma(amount: float) -> void:
	_shake_trauma = minf(1.0, _shake_trauma + amount)

func _ready() -> void:
	_build_arena()
	_build_containers()

	# Tell GameManager to use _gameplay_root for pause instead of get_tree().paused,
	# so GUI picking (mouse hover/click) always works in every UI overlay.
	GameManager.register_gameplay_pause_callbacks(
		func(): _gameplay_root.process_mode = Node.PROCESS_MODE_DISABLED,
		func(): _gameplay_root.process_mode = Node.PROCESS_MODE_INHERIT
	)

	_build_camera()
	_build_hud()
	_build_between_wave_ui()
	_build_shop_ui()
	_build_game_over_ui()

	_gameplay_root.add_child(_wave_manager)
	_wave_manager.spawn_container = _enemies_container

	_gameplay_root.add_child(_power_calculator)
	_wave_manager.register_power_calculator(_power_calculator)

	_spawn_players()
	_setup_wave_data()
	_setup_game_mode()
	_setup_terrain_events()
	_connect_hud()

	_between_wave_ui.connect("ui_closed", _on_between_wave_closed)
	_shop_ui.connect("ui_closed", _on_shop_closed)
	_wave_manager.enemy_spawned.connect(_on_enemy_spawned)

	var is_pvp := GameManager.current_mode == GameManager.RunMode.PVP_OVERLORD
	if is_pvp:
		_build_overlord_ui()
		# PVP: Overlord controls spawning. Start with Overlord's first shop phase.
		_current_wave_number = 0
		GameManager.run_wave = 1
		GameManager.set_state(GameManager.GameState.BETWEEN_WAVES)
		_gameplay_root.process_mode = Node.PROCESS_MODE_DISABLED
		_overlord_shop_ui.call("show_shop", (_game_mode as OverlordMode).overlord_state, 0)
	else:
		# Debug: skip forward to the requested wave before starting.
		if GameManager.debug_start_wave > 1:
			_wave_manager.current_wave_index = GameManager.debug_start_wave - 2
		_wave_manager.start_waves()

	var overlay: Node = load("res://scenes/test/DebugOverlay.gd").new()
	overlay.name = "DebugOverlay"
	overlay._game = self
	overlay._wave_manager = _wave_manager
	overlay._players_ref = _players
	overlay._enemies_container = _enemies_container
	add_child(overlay)

	GameManager.set_state(GameManager.GameState.PLAYING if not is_pvp else GameManager.GameState.BETWEEN_WAVES)
	var music_path := _game_music_path()
	AudioManager.play_music_from_path(music_path)

# ---------------------------------------------------------------------------
# Scene construction
# ---------------------------------------------------------------------------

func _build_arena() -> void:
	var arena := Node2D.new()
	arena.name = "ArenaMap"
	add_child(arena)

	# Background - layered space scene
	_build_space_background(arena)

	# Boundary walls (StaticBody2D x4)
	var walls_data := [
		# [center_x, center_y, width, height]
		[0.0, -ARENA_HALF_H - WALL_THICKNESS * 0.5, ARENA_HALF_W * 2.0 + WALL_THICKNESS * 2.0, WALL_THICKNESS],
		[0.0,  ARENA_HALF_H + WALL_THICKNESS * 0.5, ARENA_HALF_W * 2.0 + WALL_THICKNESS * 2.0, WALL_THICKNESS],
		[-ARENA_HALF_W - WALL_THICKNESS * 0.5, 0.0, WALL_THICKNESS, ARENA_HALF_H * 2.0],
		[ ARENA_HALF_W + WALL_THICKNESS * 0.5, 0.0, WALL_THICKNESS, ARENA_HALF_H * 2.0],
	]
	for wd in walls_data:
		var wall := StaticBody2D.new()
		wall.position = Vector2(wd[0], wd[1])
		wall.collision_layer = 4  # layer 3 - walls (distinct from player layer 1)
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(wd[2], wd[3])
		col.shape = shape
		wall.add_child(col)
		arena.add_child(wall)

	# Navigation polygon covering the playable area
	var nav_region := NavigationRegion2D.new()
	var nav_poly := NavigationPolygon.new()
	var outline := PackedVector2Array([
		Vector2(-ARENA_HALF_W + 4.0, -ARENA_HALF_H + 4.0),
		Vector2( ARENA_HALF_W - 4.0, -ARENA_HALF_H + 4.0),
		Vector2( ARENA_HALF_W - 4.0,  ARENA_HALF_H - 4.0),
		Vector2(-ARENA_HALF_W + 4.0,  ARENA_HALF_H - 4.0),
	])
	nav_poly.add_outline(outline)
	nav_poly.agent_radius = 10.0
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, NavigationMeshSourceGeometryData2D.new())
	nav_region.navigation_polygon = nav_poly
	arena.add_child(nav_region)

func _build_space_background(arena: Node2D) -> void:
	# 1. Deep-space base — pitch black with a hint of navy
	var base := ColorRect.new()
	base.color = Color(0.01, 0.01, 0.06)
	base.size = Vector2(ARENA_HALF_W * 2.0 + 400.0, ARENA_HALF_H * 2.0 + 400.0)
	base.position = Vector2(-ARENA_HALF_W - 200.0, -ARENA_HALF_H - 200.0)
	base.z_index = -15
	arena.add_child(base)

	# 2. Nebula blobs — large semi-transparent coloured rectangles
	var nebulae: Array = [
		{"pos": Vector2(-320.0, -180.0), "size": Vector2(900.0, 700.0), "color": Color(0.15, 0.04, 0.30, 0.10)},
		{"pos": Vector2( 350.0,  200.0), "size": Vector2(700.0, 550.0), "color": Color(0.04, 0.08, 0.28, 0.09)},
		{"pos": Vector2(  60.0,   80.0), "size": Vector2(1000.0, 800.0),"color": Color(0.10, 0.02, 0.18, 0.07)},
		{"pos": Vector2( 480.0, -260.0), "size": Vector2(500.0, 420.0), "color": Color(0.02, 0.12, 0.24, 0.08)},
	]
	for nd: Dictionary in nebulae:
		var nb := ColorRect.new()
		nb.color = nd["color"]
		nb.size = nd["size"]
		nb.position = nd["pos"] - nd["size"] * 0.5
		nb.z_index = -14
		arena.add_child(nb)

	# 3. Starfield — three depth layers using star1/2/3 sprites
	var star_textures: Array[Texture2D] = []
	for i: int in range(1, 4):
		var p := "res://assets/sprites/star%d.png" % i
		if ResourceLoader.exists(p):
			star_textures.append(load(p) as Texture2D)

	if not star_textures.is_empty():
		var layers: Array = [
			# {seed, count, z_idx, scale_min, scale_max, alpha_min, alpha_max, tints}
			{
				"seed": 11111, "count": 160, "z": -13,
				"smin": 0.25, "smax": 0.55, "amin": 0.20, "amax": 0.50,
				"tints": [Color(0.70, 0.72, 0.95), Color(0.80, 0.82, 1.00)],
			},
			{
				"seed": 22222, "count": 70, "z": -12,
				"smin": 0.45, "smax": 0.85, "amin": 0.55, "amax": 0.85,
				"tints": [Color(0.90, 0.92, 1.00), Color(1.00, 0.96, 0.82)],
			},
			{
				"seed": 33333, "count": 28, "z": -11,
				"smin": 0.75, "smax": 1.40, "amin": 0.80, "amax": 1.00,
				"tints": [Color(1.00, 1.00, 1.00), Color(0.80, 0.90, 1.00),
						  Color(1.00, 1.00, 0.80), Color(0.90, 0.80, 1.00)],
			},
		]
		var rng := RandomNumberGenerator.new()
		for lc: Dictionary in layers:
			rng.seed = lc["seed"]
			var layer := Node2D.new()
			layer.z_index = lc["z"]
			arena.add_child(layer)
			for _i: int in lc["count"]:
				var star := Sprite2D.new()
				star.texture = star_textures[rng.randi() % star_textures.size()]
				star.position = Vector2(
					rng.randf_range(-ARENA_HALF_W, ARENA_HALF_W),
					rng.randf_range(-ARENA_HALF_H, ARENA_HALF_H)
				)
				var sc := rng.randf_range(lc["smin"], lc["smax"])
				star.scale = Vector2(sc, sc)
				var tints: Array = lc["tints"]
				var tint: Color = tints[rng.randi() % tints.size()]
				tint.a = rng.randf_range(lc["amin"], lc["amax"])
				star.modulate = tint
				layer.add_child(star)

	# 4. Twinkling particle layer
	var twinkle := CPUParticles2D.new()
	twinkle.name = "TwinkleParticles"
	twinkle.amount = 50
	twinkle.lifetime = 3.0
	twinkle.randomness = 1.0
	twinkle.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	twinkle.emission_rect_extents = Vector2(ARENA_HALF_W, ARENA_HALF_H)
	twinkle.direction = Vector2.ZERO
	twinkle.gravity = Vector2.ZERO
	twinkle.initial_velocity_min = 0.0
	twinkle.initial_velocity_max = 0.0
	twinkle.scale_amount_min = 1.5
	twinkle.scale_amount_max = 4.0
	twinkle.scale_amount_curve = null
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.85), Color(1.0, 1.0, 1.0, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	twinkle.color_ramp = grad
	twinkle.z_index = -10
	arena.add_child(twinkle)

func _build_containers() -> void:
	_gameplay_root = Node.new()
	_gameplay_root.name = "GameplayRoot"
	add_child(_gameplay_root)

	_projectiles_container = Node2D.new()
	_projectiles_container.name = "ProjectilesContainer"
	_gameplay_root.add_child(_projectiles_container)

	_players_container = Node2D.new()
	_players_container.name = "PlayersContainer"
	_gameplay_root.add_child(_players_container)

	_enemies_container = Node2D.new()
	_enemies_container.name = "EnemiesContainer"
	_gameplay_root.add_child(_enemies_container)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	add_child(_camera)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.set_script(load("res://scenes/game/hud/HUD.gd"))
	add_child(_hud)

func _build_between_wave_ui() -> void:
	_between_wave_ui = CanvasLayer.new()
	_between_wave_ui.name = "BetweenWaveUI"
	_between_wave_ui.set_script(load("res://scenes/menus/BetweenWaveUI.gd"))
	_between_wave_ui.visible = false
	add_child(_between_wave_ui)

func _build_game_over_ui() -> void:
	_game_over_ui = CanvasLayer.new()
	_game_over_ui.name = "GameOverUI"
	_game_over_ui.set_script(load("res://scenes/menus/GameOverUI.gd"))
	_game_over_ui.visible = false
	add_child(_game_over_ui)

func _build_shop_ui() -> void:
	_shop_ui = CanvasLayer.new()
	_shop_ui.name = "ShopUI"
	_shop_ui.set_script(load("res://scenes/menus/ShopUI.gd"))
	_shop_ui.visible = false
	add_child(_shop_ui)

func _build_overlord_ui() -> void:
	## Build PVP Overlord nodes: controller, HUD overlay, and shop UI.
	var mode: OverlordMode = _game_mode as OverlordMode

	# Overlord Controller (cursor + deployment)
	_overlord_controller = OverlordController.new()
	_overlord_controller.name = "OverlordController"
	_overlord_controller.overlord_mode = mode
	_overlord_controller.overlord_state = mode.overlord_state
	_overlord_controller.enemies_container = _enemies_container
	var oc_targets: Array[Node] = []
	for p in _players:
		oc_targets.append(p)
	_overlord_controller.targets = oc_targets
	_gameplay_root.add_child(_overlord_controller)
	_overlord_controller.enemy_spawned_by_overlord.connect(_on_enemy_spawned)

	# Overlord HUD
	_overlord_hud = CanvasLayer.new()
	_overlord_hud.name = "OverlordHUD"
	_overlord_hud.set_script(load("res://scenes/game/hud/OverlordHUD.gd"))
	add_child(_overlord_hud)
	_overlord_hud.call("setup", _overlord_controller, mode.overlord_state, mode)

	# Overlord Shop UI
	_overlord_shop_ui = CanvasLayer.new()
	_overlord_shop_ui.name = "OverlordShopUI"
	_overlord_shop_ui.set_script(load("res://scenes/menus/OverlordShopUI.gd"))
	_overlord_shop_ui.visible = false
	add_child(_overlord_shop_ui)
	_overlord_shop_ui.connect("ui_closed", _on_overlord_shop_closed)

# ---------------------------------------------------------------------------
# Players
# ---------------------------------------------------------------------------

func _spawn_players() -> void:
	for i in GameManager.player_count:
		var p := Player.new()
		# Add required child nodes
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		var base_tex_path := "res://assets/sprites/playerShip1_blue.png"
		if ResourceLoader.exists(base_tex_path):
			sprite.texture = load(base_tex_path)
			# Ships face up in the sheet; rotate so they face right to match rotation=0
			sprite.rotation_degrees = 90.0
		else:
			var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.2, 0.6, 1.0))
			sprite.texture = ImageTexture.create_from_image(img)
		p.add_child(sprite)

		var col := CollisionShape2D.new()
		col.name = "CollisionShape2D"
		var cap := CapsuleShape2D.new()
		cap.radius = 12.0
		cap.height = 24.0
		col.shape = cap
		p.add_child(col)

		p.player_index = i
		p.damage_sprite_set = i % 3 + 1
		var char_id := GameManager.selected_characters[i] if i < GameManager.selected_characters.size() else &"scout"
		var data_path := "res://resources/characters/%s.tres" % char_id
		if ResourceLoader.exists(data_path):
			p.character_data = ResourceLoader.load(data_path)

		_players_container.add_child(p)
		if GameManager.player_count > 1:
			var indicator := Label.new()
			indicator.text = "P%d" % (i + 1)
			indicator.position = Vector2(-10.0, -38.0)
			var p_colors: Array[Color] = [Color(0.5, 0.8, 1.0), Color(1.0, 0.65, 0.2)]
			indicator.add_theme_color_override("font_color", p_colors[i % p_colors.size()])
			var pfont := GameManager.kenney_font()
			if pfont:
				indicator.add_theme_font_override("font", pfont)
				indicator.add_theme_font_size_override("font_size", 12)
			p.add_child(indicator)
		p.global_position = Vector2(i * 80.0 - 40.0, 0.0)
		_players.append(p)
		p.died.connect(_on_player_died)
		p.took_damage.connect(func(): _add_trauma(0.35))
		# Track damage taken via health_changed: store previous health to compute delta
		var prev_hp: Array[float] = [100.0]
		p.health_changed.connect(func(cur: float, _max: float):
			var delta := prev_hp[0] - cur
			if delta > 0.0:
				_power_calculator.record_damage_taken(delta)
			prev_hp[0] = cur
		)
		_equip_weapon(p)

	# Register all players with the power calculator
	_power_calculator.register_players(_players)

func _equip_weapon(player: Player) -> void:
	var weapon_id: StringName = player.character_data.starting_weapon if player.character_data else &"pistol"
	var data_path := "res://resources/weapons/%s.tres" % weapon_id
	if not ResourceLoader.exists(data_path):
		return
	var weapon_data: WeaponData = ResourceLoader.load(data_path)
	if weapon_data == null:
		return
	# Override projectile_scene to use the code-built projectile
	var weapon := _make_weapon_node(weapon_data)
	weapon._projectile_parent = _projectiles_container
	player.add_weapon(weapon)

func _make_weapon_node(wdata: WeaponData) -> BaseWeapon:
	var weapon: BaseWeapon
	if wdata.ammo_type == WeaponData.AmmoType.BEAM:
		weapon = load("res://scenes/game/weapons/BeamWeapon.gd").new()
	else:
		weapon = BaseWeapon.new()
	weapon.weapon_data = wdata
	return weapon

# ---------------------------------------------------------------------------
# Wave data - loaded dynamically from res://resources/waves/
# ---------------------------------------------------------------------------

func _load_waves_from_dir(path: String) -> Array[WaveData]:
	var result: Array[WaveData] = []
	var dir := DirAccess.open(path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") or fname.ends_with(".tres.remap"):
			var res = ResourceLoader.load(path + "/" + fname.trim_suffix(".remap"))
			if res is WaveData:
				result.append(res)
		fname = dir.get_next()
	result.sort_custom(func(a, b): return a.wave_number < b.wave_number)
	return result

func _setup_wave_data() -> void:
	_wave_manager.wave_data_list = _load_waves_from_dir("res://resources/waves")

# ---------------------------------------------------------------------------
# Game mode
# ---------------------------------------------------------------------------

func _setup_game_mode() -> void:
	match GameManager.current_mode:
		GameManager.RunMode.WAVE_SURVIVAL:
			var mode := WaveSurvivalMode.new()
			_game_mode = mode
			_gameplay_root.add_child(mode)
			mode.setup(_wave_manager, _players)
			mode.show_between_wave_ui.connect(_show_between_wave_ui)
			var ws_targets: Array[Node] = []
			for p in _players:
				ws_targets.append(p)
			_wave_manager.register_targets(ws_targets)

		GameManager.RunMode.HORDE_DEFENSE:
			var mode := HordeDefenseMode.new()
			_game_mode = mode
			_gameplay_root.add_child(mode)
			mode.setup(_wave_manager, _players)
			var base := BaseObjective.new()
			_gameplay_root.add_child(base)
			base.global_position = Vector2.ZERO
			base.took_damage.connect(func(): _add_trauma(0.3))
			mode.set_base(base)
			mode.show_between_wave_ui.connect(_show_between_wave_ui)

		GameManager.RunMode.PVP_OVERLORD:
			var mode := OverlordMode.new()
			_game_mode = mode
			_gameplay_root.add_child(mode)
			mode.setup(_wave_manager, _players)
			mode.show_overlord_shop.connect(_show_overlord_shop)
			mode.show_between_wave_ui.connect(_show_between_wave_ui)
			# Disable WaveManager auto-spawning; Overlord handles spawning
			_wave_manager.wave_data_list.clear()
			_wave_manager.is_stopped = true
			var pvp_targets: Array[Node] = []
			for p in _players:
				pvp_targets.append(p)
			_wave_manager.register_targets(pvp_targets)

	_game_mode.run_ended.connect(_on_run_ended)

# ---------------------------------------------------------------------------
# Terrain events
# ---------------------------------------------------------------------------

func _setup_terrain_events() -> void:
	var terrain := TerrainEventManager.new()
	terrain.players = _players
	terrain.enemies_container = _enemies_container
	terrain.wave_manager = _wave_manager
	terrain.hud = _hud
	_gameplay_root.add_child(terrain)
	_game_mode.run_ended.connect(func(_v: bool):
		GameManager.solar_flare_active = false
		GameManager.solar_flare_intensity = 1.0
		GameManager.ion_storm_active = false
	)

	var special := SpecialEnemyEventManager.new()
	special.players = _players
	special.wave_manager = _wave_manager
	special.hud = _hud
	_gameplay_root.add_child(special)
	special.special_xp_dropped.connect(_on_xp_dropped)
	special.special_coin_dropped.connect(_on_coin_dropped)
	_game_mode.run_ended.connect(func(_v: bool): special.stop())

# ---------------------------------------------------------------------------
# HUD
# ---------------------------------------------------------------------------

func _connect_hud() -> void:
	for player in _players:
		if _hud.has_method("register_player"):
			_hud.register_player(player)
	_wave_manager.wave_started.connect(
		func(w: int, t: int) -> void:
			if _hud.has_method("update_wave"):
				_hud.update_wave(w, t)
			var sfx := "res://assets/audio/sfx_wave_start.ogg"
			if ResourceLoader.exists(sfx):
				AudioManager.play_sfx(load(sfx), -4.0, 1.0)
	)
	_wave_manager.wave_timer_updated.connect(
		func(r: float) -> void:
			_hud.call("update_timer", r)
	)

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Camera shake
	if _shake_trauma > 0.0:
		_shake_trauma = maxf(0.0, _shake_trauma - SHAKE_DECAY * delta)
		var power := _shake_trauma * _shake_trauma
		_camera.offset = Vector2(
			randf_range(-1.0, 1.0) * SHAKE_MAX_OFFSET * power,
			randf_range(-1.0, 1.0) * SHAKE_MAX_OFFSET * power
		)
	else:
		_camera.offset = Vector2.ZERO

	var sum := Vector2.ZERO
	var count := 0
	for p in _players:
		if p.is_physics_processing():
			sum += p.global_position
			count += 1
	if count == 0:
		return
	_camera.global_position = sum / count

	# Dynamic zoom: zoom out when co-op players are far apart, or to include Overlord cursor
	var _zoom_second_pos: Vector2 = _camera.global_position
	var _has_second := false
	if count >= 2:
		var p0: Vector2 = _players[0].global_position if _players[0].is_physics_processing() else _camera.global_position
		var p1: Vector2 = _players[1].global_position if _players[1].is_physics_processing() else _camera.global_position
		_zoom_second_pos = p1 if _players[0].is_physics_processing() else p0
		_has_second = true
	elif _overlord_controller and is_instance_valid(_overlord_controller):
		_zoom_second_pos = _overlord_controller._cursor_pos
		_has_second = true
	if _has_second:
		var dist := _camera.global_position.distance_to(_zoom_second_pos)
		# Map dist 0-800 to zoom 1.0-0.55 so both points stay in frame
		var target_zoom := clampf(1.0 - (dist / 800.0) * 0.45, 0.55, 1.0)
		_camera.zoom = _camera.zoom.lerp(Vector2(target_zoom, target_zoom), 0.05)
	else:
		_camera.zoom = _camera.zoom.lerp(Vector2(1.0, 1.0), 0.05)

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

func _show_between_wave_ui(wave_number: int) -> void:
	_current_wave_number = wave_number
	get_tree().paused = false  # Safety: clear any lingering pause before showing UI
	GameManager.set_state(GameManager.GameState.BETWEEN_WAVES)
	AudioManager.play_music_from_path("res://assets/audio/music_betweenwaves.mp3")
	_gameplay_root.process_mode = Node.PROCESS_MODE_DISABLED
	if _between_wave_ui.has_method("show_for_players"):
		_between_wave_ui.call("show_for_players", _players, wave_number, _wave_manager)

func _on_between_wave_closed() -> void:
	if _shop_ui.has_method("show_for_players"):
		var arr: Array = []
		for p in _players:
			arr.append(p)
		_shop_ui.call("show_for_players", arr, _projectiles_container, _current_wave_number)

func _on_shop_closed() -> void:
	# Revive any dead co-op players before the next wave
	if _players.size() > 1:
		for p in _players:
			if p.current_health <= 0.0:
				p.revive()
				_spawn_floating_text("REVIVED  -%d Scrap" % Player.REVIVE_SCRAP_PENALTY, p.global_position, Color(0.4, 1.0, 0.6))
	AudioManager.play_music_from_path(_game_music_path())
	_gameplay_root.process_mode = Node.PROCESS_MODE_INHERIT
	GameManager.set_state(GameManager.GameState.PLAYING)
	if GameManager.current_mode == GameManager.RunMode.PVP_OVERLORD:
		_start_pvp_wave()
	else:
		_wave_manager.next_wave()

func _game_music_path() -> String:
	var preferred: String
	match GameManager.current_difficulty:
		GameManager.Difficulty.EASY:
			preferred = "res://assets/audio/music_game_easy.ogg"
		GameManager.Difficulty.HARD:
			preferred = "res://assets/audio/music_game_hard.mp3"
		GameManager.Difficulty.SUPER_HARD:
			preferred = "res://assets/audio/music_game_super_hard.mp3"
		_:
			return "res://assets/audio/music_game.mp3"
	# Fall back to normal game music if the variant isn't in the exported PCK
	if ResourceLoader.exists(preferred):
		return preferred
	return "res://assets/audio/music_game.mp3"

func _on_player_died() -> void:
	pass  # GameMode handles multi-player death tracking

# ---------------------------------------------------------------------------
# PVP Overlord helpers
# ---------------------------------------------------------------------------

func _show_overlord_shop(wave_number: int) -> void:
	## Called by OverlordMode when a wave ends. Show Overlord's shop first.
	_current_wave_number = wave_number
	GameManager.set_state(GameManager.GameState.BETWEEN_WAVES)
	_gameplay_root.process_mode = Node.PROCESS_MODE_DISABLED
	if _overlord_controller:
		_overlord_controller.call("hide_cursor")
	if _overlord_shop_ui:
		var mode: OverlordMode = _game_mode as OverlordMode
		_overlord_shop_ui.call("show_shop", mode.overlord_state, wave_number)

func _on_overlord_shop_closed() -> void:
	## After Overlord finishes shopping, show ship player's between-wave UI.
	if _between_wave_ui.has_method("show_for_players"):
		_between_wave_ui.call("show_for_players", _players, _current_wave_number, _wave_manager)

func _start_pvp_wave() -> void:
	## Begin a new PVP wave. Overlord can now deploy enemies.
	var mode: OverlordMode = _game_mode as OverlordMode
	_current_wave_number += 1
	GameManager.run_wave = _current_wave_number
	mode.start_wave(_current_wave_number)
	if _overlord_hud:
		_overlord_hud.call("show_hud")

func register_extra_target(node: Node) -> void:
	## Add a decoy or other non-player node to the enemy target list.
	if node not in _extra_targets:
		_extra_targets.append(node)
	_refresh_all_targets()

func unregister_extra_target(node: Node) -> void:
	_extra_targets.erase(node)
	_refresh_all_targets()

func _refresh_all_targets() -> void:
	var targets: Array[Node] = []
	for p in _players:
		targets.append(p)
	for t in _extra_targets:
		if is_instance_valid(t):
			targets.append(t)
	_wave_manager.register_targets(targets)
	# Update all currently-living enemies
	for enemy in _enemies_container.get_children():
		if enemy.has_method("register_targets"):
			enemy.register_targets(targets)

func _on_enemy_spawned(enemy: BaseEnemy) -> void:
	enemy.xp_dropped.connect(_on_xp_dropped)
	enemy.coin_dropped.connect(_on_coin_dropped)

func _on_xp_dropped(amount: int, world_pos: Vector2) -> void:
	# Apply difficulty modifier to XP drops.
	# Overall XP is reduced so leveling up takes longer; easier modes ease up slightly.
	var adj_xp := amount
	match GameManager.current_difficulty:
		GameManager.Difficulty.SUPER_EASY: adj_xp = maxi(1, int(amount * 0.85))
		GameManager.Difficulty.EASY:       adj_xp = maxi(1, int(amount * 0.75))
		GameManager.Difficulty.NORMAL:     adj_xp = maxi(1, int(amount * 0.60))
		GameManager.Difficulty.HARD:       adj_xp = maxi(1, int(amount * 0.50))
		GameManager.Difficulty.SUPER_HARD: adj_xp = maxi(1, int(amount * 0.40))
	# Distribute XP to all living players
	for p in _players:
		if p.is_physics_processing():
			p.gain_xp(adj_xp)
	_spawn_floating_text("+%d XP" % adj_xp, world_pos, Color(0.5, 1.0, 0.5))
	var sfx := "res://assets/audio/sfx_xp_pickup.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -8.0, randf_range(1.0, 1.2))

func _on_coin_dropped(amount: int, world_pos: Vector2) -> void:
	# Apply difficulty modifier to combat coin drops.
	# Easier modes reward more scrap; harder modes reward less.
	# Anchor: grunt (base 5) gives 3 scrap on Super Hard.
	var adj_amount := amount
	match GameManager.current_difficulty:
		GameManager.Difficulty.SUPER_EASY:
			adj_amount = maxi(1, int(amount * 1.4))  # ~7 for grunt
		GameManager.Difficulty.EASY:
			adj_amount = maxi(1, int(amount * 1.2))  # ~6 for grunt
		GameManager.Difficulty.NORMAL:
			adj_amount = amount                       # 5 for grunt (baseline)
		GameManager.Difficulty.HARD:
			adj_amount = maxi(1, int(amount * 0.9))  # ~4-5 for grunt
		GameManager.Difficulty.SUPER_HARD:
			adj_amount = maxi(1, int(amount * 0.75))  # ~3-4 for grunt
	GameManager.run_coins_earned += adj_amount
	# Award Scrap to nearest living player
	var nearest: Player = null
	var best_dist := INF
	for p in _players:
		if p.is_physics_processing():
			var d := p.global_position.distance_squared_to(world_pos)
			if d < best_dist:
				best_dist = d
				nearest = p
	if nearest:
		nearest.add_scrap(adj_amount)
	if adj_amount > 0:
		_spawn_floating_text("Scrap +%d" % adj_amount, world_pos, Color(0.3, 0.9, 1.0))
	var sfx := "res://assets/audio/sfx_coin_pickup.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -6.0, randf_range(1.1, 1.3))

func _spawn_floating_text(text: String, world_pos: Vector2, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	var font := GameManager.kenney_font()
	if font:
		lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", 18)
	lbl.z_index = 20
	add_child(lbl)
	lbl.global_position = world_pos + Vector2(-20.0, -10.0)
	var t := lbl.create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y - 48.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(lbl.queue_free)

func _on_run_ended(victory: bool) -> void:
	_gameplay_root.process_mode = Node.PROCESS_MODE_DISABLED
	GameManager.set_state(GameManager.GameState.WIN if victory else GameManager.GameState.GAME_OVER)
	MetaProgression.add_coins(GameManager.run_coins_earned)
	# Always make visible first, then populate text via call() to avoid static-type issues
	_game_over_ui.visible = true
	_game_over_ui.call("show_result", victory)
