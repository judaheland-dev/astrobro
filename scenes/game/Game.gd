extends Node2D

## Game - root scene. Builds itself entirely in code; no editor wiring needed.

const ARENA_HALF_W: float = 960.0
const ARENA_HALF_H: float = 600.0
const WALL_THICKNESS: float = 32.0

var _players_container: Node2D
var _enemies_container: Node2D
var _projectiles_container: Node2D
var _hud: CanvasLayer
var _between_wave_ui: CanvasLayer
var _shop_ui: CanvasLayer
var _game_over_ui: CanvasLayer
var _camera: Camera2D

var _players: Array[Player] = []
var _wave_manager: WaveManager = WaveManager.new()
var _game_mode: GameMode = null
var _current_wave_number: int = 1

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
	_build_camera()
	_build_hud()
	_build_between_wave_ui()
	_build_shop_ui()
	_build_game_over_ui()

	add_child(_wave_manager)
	_wave_manager.spawn_container = _enemies_container

	_spawn_players()
	_setup_wave_data()
	_setup_game_mode()
	_setup_terrain_events()
	_connect_hud()

	_between_wave_ui.connect("ui_closed", _on_between_wave_closed)
	_shop_ui.connect("ui_closed", _on_shop_closed)
	_wave_manager.enemy_spawned.connect(_on_enemy_spawned)
	_wave_manager.start_waves()
	GameManager.set_state(GameManager.GameState.PLAYING)
	var music_path := "res://assets/audio/music_game.ogg"
	if ResourceLoader.exists(music_path):
		AudioManager.play_music(load(music_path))

# ---------------------------------------------------------------------------
# Scene construction
# ---------------------------------------------------------------------------

func _build_arena() -> void:
	var arena := Node2D.new()
	arena.name = "ArenaMap"
	add_child(arena)

	# Background - tiled Kenney darkPurple space texture
	var bg_tex: Texture2D = load("res://assets/sprites/bg_darkPurple.png")
	if bg_tex:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.stretch_mode = TextureRect.STRETCH_TILE
		bg.size = Vector2(ARENA_HALF_W * 2.0, ARENA_HALF_H * 2.0)
		bg.position = Vector2(-ARENA_HALF_W, -ARENA_HALF_H)
		bg.z_index = -10
		arena.add_child(bg)
	else:
		var floor_rect := ColorRect.new()
		floor_rect.color = Color(0.05, 0.05, 0.15)
		floor_rect.size = Vector2(ARENA_HALF_W * 2.0, ARENA_HALF_H * 2.0)
		floor_rect.position = Vector2(-ARENA_HALF_W, -ARENA_HALF_H)
		floor_rect.z_index = -10
		arena.add_child(floor_rect)

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

func _build_containers() -> void:
	_projectiles_container = Node2D.new()
	_projectiles_container.name = "ProjectilesContainer"
	add_child(_projectiles_container)

	_players_container = Node2D.new()
	_players_container.name = "PlayersContainer"
	add_child(_players_container)

	_enemies_container = Node2D.new()
	_enemies_container.name = "EnemiesContainer"
	add_child(_enemies_container)

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

# ---------------------------------------------------------------------------
# Players
# ---------------------------------------------------------------------------

func _spawn_players() -> void:
	for i in GameManager.player_count:
		var p := Player.new()
		# Add required child nodes
		var sprite := Sprite2D.new()
		sprite.name = "Sprite2D"
		var ship_textures := [
			"res://assets/sprites/playerShip1_blue.png",
			"res://assets/sprites/playerShip2_orange.png",
			"res://assets/sprites/playerShip3_red.png",
		]
		var tex_path: String = ship_textures[i % ship_textures.size()]
		var ship_tex: Texture2D = load(tex_path)
		if ship_tex:
			sprite.texture = ship_tex
			# Ships face up in the sheet; rotate so they face right to match rotation=0
			sprite.rotation_degrees = 90.0
		else:
			var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.2, 0.6, 1.0) if i == 0 else Color(1.0, 0.4, 0.2))
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
		p.global_position = Vector2(i * 80.0 - 40.0, 0.0)
		_players.append(p)
		p.died.connect(_on_player_died)
		p.took_damage.connect(func(): _add_trauma(0.35))
		_equip_weapon(p)

func _equip_weapon(player: Player) -> void:
	var weapon_id: StringName = player.character_data.starting_weapon if player.character_data else &"pistol"
	var data_path := "res://resources/weapons/%s.tres" % weapon_id
	if not ResourceLoader.exists(data_path):
		return
	var weapon_data: WeaponData = ResourceLoader.load(data_path)
	if weapon_data == null:
		return
	# Override projectile_scene to use the code-built projectile
	var weapon := BaseWeapon.new()
	weapon.weapon_data = weapon_data
	weapon._projectile_parent = _projectiles_container
	player.add_weapon(weapon)

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
		if fname.ends_with(".tres"):
			var res = ResourceLoader.load(path + "/" + fname)
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
			add_child(mode)
			mode.setup(_wave_manager, _players)
			mode.show_between_wave_ui.connect(_show_between_wave_ui)
			var ws_targets: Array[Node] = []
			for p in _players:
				ws_targets.append(p)
			_wave_manager.register_targets(ws_targets)

		GameManager.RunMode.HORDE_DEFENSE:
			var mode := HordeDefenseMode.new()
			_game_mode = mode
			add_child(mode)
			mode.setup(_wave_manager, _players)
			var base := BaseObjective.new()
			add_child(base)
			base.global_position = Vector2.ZERO
			base.took_damage.connect(func(): _add_trauma(0.3))
			mode.set_base(base)
			mode.show_between_wave_ui.connect(_show_between_wave_ui)

	_game_mode.run_ended.connect(_on_run_ended)

# ---------------------------------------------------------------------------
# Terrain events
# ---------------------------------------------------------------------------

func _setup_terrain_events() -> void:
	var terrain := TerrainEventManager.new()
	terrain.players = _players
	terrain.enemies_container = _enemies_container
	terrain.wave_manager = _wave_manager
	add_child(terrain)
	_game_mode.run_ended.connect(func(_v: bool): GameManager.solar_flare_active = false)

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

	# Dynamic zoom: zoom out when co-op players are far apart
	if count >= 2:
		var p0: Vector2 = _players[0].global_position if _players[0].is_physics_processing() else _camera.global_position
		var p1: Vector2 = _players[1].global_position if _players[1].is_physics_processing() else _camera.global_position
		var dist := p0.distance_to(p1)
		# Map dist 0-800 to zoom 1.0-0.55 so both players stay in frame
		var target_zoom := clampf(1.0 - (dist / 800.0) * 0.45, 0.55, 1.0)
		_camera.zoom = _camera.zoom.lerp(Vector2(target_zoom, target_zoom), 0.05)
	else:
		_camera.zoom = _camera.zoom.lerp(Vector2(1.0, 1.0), 0.05)

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------

func _show_between_wave_ui(wave_number: int) -> void:
	_current_wave_number = wave_number
	GameManager.set_state(GameManager.GameState.BETWEEN_WAVES)
	get_tree().paused = true
	if _between_wave_ui.has_method("show_for_players"):
		_between_wave_ui.show_for_players(_players, wave_number, _wave_manager)

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
			if not p.is_physics_processing():
				p.revive()
				_spawn_floating_text("REVIVED  -%d Scrap" % Player.REVIVE_SCRAP_PENALTY, p.global_position, Color(0.4, 1.0, 0.6))
	get_tree().paused = false
	GameManager.set_state(GameManager.GameState.PLAYING)
	_wave_manager.next_wave()

func _on_player_died() -> void:
	pass  # GameMode handles multi-player death tracking

func _on_enemy_spawned(enemy: BaseEnemy) -> void:
	enemy.xp_dropped.connect(_on_xp_dropped)
	enemy.coin_dropped.connect(_on_coin_dropped)

func _on_xp_dropped(amount: int, world_pos: Vector2) -> void:
	# Distribute XP to all living players
	for p in _players:
		if p.is_physics_processing():
			p.gain_xp(amount)
	_spawn_floating_text("+%d XP" % amount, world_pos, Color(0.5, 1.0, 0.5))
	var sfx := "res://assets/audio/sfx_xp_pickup.ogg"
	if ResourceLoader.exists(sfx):
		AudioManager.play_sfx(load(sfx), -8.0, randf_range(1.0, 1.2))

func _on_coin_dropped(amount: int, world_pos: Vector2) -> void:
	GameManager.run_coins_earned += amount
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
		nearest.add_scrap(amount)
	_spawn_floating_text("Scrap +%d" % amount, world_pos, Color(0.3, 0.9, 1.0))
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
	get_tree().paused = true
	GameManager.set_state(GameManager.GameState.WIN if victory else GameManager.GameState.GAME_OVER)
	MetaProgression.add_coins(GameManager.run_coins_earned)
	# Always make visible first, then populate text via call() to avoid static-type issues
	_game_over_ui.visible = true
	_game_over_ui.call("show_result", victory)
