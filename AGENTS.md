# Space Roguelite — Agent Instructions

This is a **Godot 4 / GDScript** project. Every scene node is built entirely in `_ready()` in code — there are no `.tscn` files to edit, and no Godot editor is required.

See **[GAMEPAD.md](GAMEPAD.md)** for gamepad input architecture, SDL2 button remapping gotchas, and known controller mappings.

## Project Structure

```
autoloads/          GameManager, MetaProgression, AudioManager, InputManager
scenes/
  game/             Game.gd (root), Player.gd, HUD.gd
  game/enemies/     BaseEnemy.gd
  game/weapons/     BaseWeapon.gd, BaseProjectile.gd
  menus/            MainMenu, CharacterSelect, BetweenWaveUI, GameOverUI, MetaMenu
systems/            WaveManager.gd, GameMode.gd, WaveSurvivalMode.gd, HordeDefenseMode.gd
resources/          .tres data files (CharacterData, EnemyData, WaveData, WeaponData, UpgradeData)
assets/sprites/     Kenney Space Shooter Remastered PNGs
assets/fonts/       kenvector_future.ttf
assets/audio/       .ogg sound effect files
```

## Critical GDScript Rules

- **Typed arrays are invariant.** `Array[Player]` cannot be passed where `Array[Node]` is expected. Build explicitly:
  ```gdscript
  var targets: Array[Node] = []
  for p in _players:
      targets.append(p)
  ```
- **`Array.all()` does not exist in GDScript.** Use a `for` loop instead.
- **`GameMode` is both a class name and was an enum name** — the enum in `GameManager.gd` is named `RunMode` to avoid the clash.
- **Pause-safe UI nodes** must set `process_mode = Node.PROCESS_MODE_ALWAYS` in `_ready()` so they respond to input while `get_tree().paused = true`. Set it on the **CanvasLayer AND on individual Buttons** — the button's own process_mode matters for click events.
- **`@onready` vars** (`$NodeName`) only work when the node is already in the scene tree. When building nodes in code, add children *before* calling `add_child(parent)`, or wire signals after `parent.add_child(enemy_node)`.
- **Em-dashes (`—`) in GDScript** cause parse errors. Always use a hyphen-minus (`-`).
- **Calling methods on a statically-typed `CanvasLayer` variable will fail** if the method is defined in a script attached at runtime. Use `.call("method_name", args)` instead:
  ```gdscript
  # BAD  - static type doesn't know about show_result()
  _game_over_ui.show_result(victory)
  # GOOD
  _game_over_ui.call("show_result", victory)
  ```
- **`ColorRect` backgrounds block mouse events by default** (`MOUSE_FILTER_STOP`). Any purely-visual background behind buttons must use:
  ```gdscript
  bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
  ```

## CanvasLayer Render Order

Set `layer` explicitly; default is 1 for everything and order is undefined:

| CanvasLayer | layer value |
|---|---|
| HUD | 1 (default) |
| BetweenWaveUI | 5 |
| GameOverUI | 20 |

## Input Handling While Paused

Global key handling (Esc, pause) belongs in **`GameManager._input()`** — it's an autoload with `process_mode = ALWAYS` and is guaranteed to be active. Don't rely on `_input()` in CanvasLayer scripts because their execution depends on layer visibility and process_mode propagation.

## Collision Layers

| Layer | Who uses it |
|-------|-------------|
| 1     | Players (layer + mask) |
| 2     | Enemies (layer + mask) |
| 0     | Projectiles and enemy contact areas (no layer, mask only) |

- Projectiles: `collision_layer=0`, `collision_mask=2` (hit enemies only)
- Enemy contact Area2D: `collision_layer=0`, `collision_mask=1` (detect players only)

## Sprite Conventions

Kenney PNG orientations (rotation offset needed):

| Asset | Faces | Fix |
|-------|-------|-----|
| Player ships (`playerShip*.png`) | Up (−Y) | `sprite.rotation_degrees = 90.0` on the Sprite2D |
| Enemy ships (`enemyRed*.png`, etc.) | Down (+Y) | `sprite.rotation = velocity.angle() - PI * 0.5` each frame |
| Lasers (`laserBlue01.png`, etc.) | Up (−Y) | `sprite.rotation_degrees = 90.0` on the Sprite2D |

Always load assets with a fallback:
```gdscript
if ResourceLoader.exists(path):
    sprite.texture = load(path)
else:
    # create placeholder ImageTexture
```

## Arena & Navigation

- Arena: `ARENA_HALF_W = 960`, `ARENA_HALF_H = 600`, walls are `StaticBody2D` 32px thick.
- `NavigationPolygon` is baked in code covering the inner playable area.
- **Enemy spawn positions must be inside the nav mesh** — use `hw=900`, `hh=560` as safe bounds. Spawning outside (e.g. ±720 on a ±960 arena) leaves `NavigationAgent2D` with no path and enemies stand still.

## Audio

`AudioManager` is an autoload with a 16-slot pooled SFX system and a single music player.

- **`AudioManager.play_sfx(stream, volume_db, pitch_scale)`** — plays a one-shot sound on the Master bus.
- **`AudioManager.play_ui_click()`** — convenience helper for menu button sounds (uses `sfx_twoTone.ogg` at 1.2 pitch).
- **`AudioManager.play_music(stream)`** / **`stop_music()`** — looping background music. Looping is handled via the `finished` signal in `AudioManager`, **not** by the `.import` file's `loop` param (which stays `false`).

Always guard asset loads with `ResourceLoader.exists(path)`. Available SFX files:

| File | Used for | Kenney source |
|------|----------|---------------|
| `assets/audio/sfx_laser1.ogg` | Default weapon fire (fallback) | kenney_sci-fi-sounds `laserSmall_000.ogg` |
| `assets/audio/sfx_laser2.ogg` | Enemy hit (non-death), base hit | kenney_sci-fi-sounds `impactMetal_002.ogg` |
| `assets/audio/sfx_twoTone.ogg` | UI button clicks | kenney_ui-audio `click2.ogg` |
| `assets/audio/sfx_enemy_death.ogg` | Enemy death (all enemy .tres `death_sfx`) | kenney_sci-fi-sounds `laserRetro_000.ogg` |
| `assets/audio/sfx_ability_activate.ogg` | Ability activation (all 7 character abilities) | kenney_interface-sounds `maximize_006.ogg` |
| `assets/audio/sfx_victory.ogg` | Victory screen | kenney_interface-sounds `confirmation_002.ogg` |
| `assets/audio/sfx_lose.ogg` | Player hurt (pitch 0.7), game over loss | kenney_sci-fi-sounds `lowFrequency_explosion_000.ogg` |
| `assets/audio/sfx_explosion.ogg` | Exploder enemy AoE death, base destroyed | kenney_sci-fi-sounds `explosionCrunch_002.ogg` |
| `assets/audio/sfx_rocket_fire.ogg` | Rocket weapon fire | kenney_sci-fi-sounds `thrusterFire_002.ogg` |
| `assets/audio/sfx_shotgun.ogg` | Shotgun weapon fire | kenney_sci-fi-sounds `laserLarge_000.ogg` |
| `assets/audio/sfx_sniper.ogg` | Sniper rifle / spread laser fire | kenney_sci-fi-sounds `laserLarge_002.ogg` |
| `assets/audio/sfx_levelup.ogg` | Player level-up | kenney_interface-sounds `maximize_001.ogg` |
| `assets/audio/sfx_xp_pickup.ogg` | XP orb collected | kenney_interface-sounds `pluck_001.ogg` |
| `assets/audio/sfx_coin_pickup.ogg` | Coin collected | kenney_rpg-audio `handleCoins.ogg` |
| `assets/audio/sfx_player_death.ogg` | Player death | kenney_sci-fi-sounds `lowFrequency_explosion_001.ogg` |
| `assets/audio/sfx_heal.ogg` | Player healed (> 2 HP, to avoid lifesteal spam) | kenney_interface-sounds `select_002.ogg` |
| `assets/audio/sfx_wave_start.ogg` | Wave begins | kenney_sci-fi-sounds `forceField_000.ogg` |
| `assets/audio/sfx_wave_clear.ogg` | Wave cleared | kenney_interface-sounds `confirmation_001.ogg` |
| `assets/audio/sfx_pause.ogg` | Game paused/unpaused | kenney_interface-sounds `switch_001.ogg` |
| `assets/audio/sfx_beam_hum.ogg` | Beam weapon hum (looping) | kenney_sci-fi-sounds `engineCircular_002.ogg` |

Available music files:

| File | Used for |
|------|----------|
| `assets/audio/music_menu.ogg` | Main menu / character select (72 BPM ambient, ~60 s) |
| `assets/audio/music_game.ogg` | In-round (138 BPM electronic, ~56 s) |

When assigning `death_sfx` in an enemy `.tres`, or `fire_sfx` in a weapon `.tres`, add an `ext_resource` entry and increment `load_steps`:
```
[ext_resource type="AudioStream" path="res://assets/audio/sfx_enemy_death.ogg" id="2"]
...
death_sfx = ExtResource("2")
```

## Generating new SFX

New sounds are generated procedurally via `tools/gen_sfx.py` (pure Python stdlib + ffmpeg). To add a sound:

1. Add a `make_mysound()` function in the script using `sine()`, `noise()`, and `adsr()` helpers.
2. Append `('sfx_mysound', make_mysound())` to the `sounds` list at the bottom.
3. Run `python3 tools/gen_sfx.py` from the project root — files are written to `assets/audio/`.
4. Preview with `ffplay -nodisp -autoexit assets/audio/sfx_mysound.ogg`.

The encoder is OGG Vorbis (`-strict experimental -c:a vorbis`). **Do not use `libopus`** — Godot's `oggvorbisstr` importer rejects Opus-encoded `.ogg` files with `valid=false` and silent audio at runtime. After regenerating SFX, delete the old `.import` files and run `godot --headless --import` to force a clean reimport.

## Generating new music

Music is generated procedurally via `tools/gen_music.py` (pure Python stdlib + ffmpeg, ~7 s runtime). It uses sample rate 22050 Hz internally but upsamples to 44100 Hz stereo on encode.

**Critical: music files must be OGG Vorbis, not OGG Opus.**
Godot's `oggvorbisstr` importer rejects Opus-encoded `.ogg` files with `valid=false` in the `.import` file and a runtime `Failed loading resource` error. The ffmpeg command must be:
```
ffmpeg -ar 44100 -ac 2 -strict experimental -c:a vorbis output.ogg
```
(`libvorbis` is not available in a typical Homebrew ffmpeg build; use the built-in `vorbis` encoder with `-strict experimental`.)

After generating new music files, Godot must import them before they can be loaded at runtime:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --import
```
This creates `assets/audio/music_*.ogg.import` and `.godot/imported/music_*.oggvorbisstr`. Without this step `ResourceLoader.exists()` returns `false`.

To add a new music track:
1. Add a `make_mytrack()` function in `tools/gen_music.py`.
2. Append `('music_mytrack', make_mytrack)` to the `tracks` list at the bottom.
3. Run `python3 tools/gen_music.py` from the project root.
4. Run `godot --headless --import` to produce the `.import` file.
5. Preview with `ffplay -nodisp -autoexit assets/audio/music_mytrack.ogg`.
6. Play it in GDScript: `AudioManager.play_music(load("res://assets/audio/music_mytrack.ogg"))`.

Where music is started/stopped:
- `MainMenu._ready()` — starts `music_menu.ogg`
- `Game._ready()` — starts `music_game.ogg`
- `GameOverUI.show_result()` — calls `stop_music()` before playing the win/lose SFX

## Font

Use `GameManager.kenney_font()` to get the Kenney font and apply it:
```gdscript
var font := GameManager.kenney_font()
if font:
    label.add_theme_font_override("font", font)
    label.add_theme_font_size_override("font_size", 22)
```

## Key Signals

| Signal | Emitter | Receiver |
|--------|---------|----------|
| `enemy_spawned(enemy)` | WaveManager | Game.gd — wires xp/coin signals |
| `xp_dropped(amount, pos)` | BaseEnemy | Game.gd |
| `coin_dropped(amount, pos)` | BaseEnemy | Game.gd |
| `wave_cleared(n)` | WaveManager | GameMode base class |
| `all_waves_cleared()` | WaveManager | GameMode |
| `health_changed(cur, max)` | Player | HUD |
| `took_damage()` | Player | Game.gd — triggers camera shake |

## Animation Patterns

All animation is done with `Tween` — no `AnimationPlayer` nodes required.

- **Spawn pop-in:** `scale` 0 → 1.2 → 1 with `TRANS_BACK / EASE_OUT`.
- **Hit flash:** set `sprite.modulate` to overbright white/color instantly, tween back to `Color.WHITE`.
- **Scale punch:** tween `scale` to ~1.15× then back; chain after the flash tween.
- **Death:** parallel tween `modulate:a` → 0, `scale` → small, `rotation` += `TAU`; `chain().tween_callback(queue_free)`.
- **Floating text:** add a `Label` to the scene root at `world_pos`, tween `position.y` up and `modulate:a` to 0, then `queue_free`.
- **Camera shake:** maintain a `_shake_trauma: float`; each frame decay it and set `_camera.offset` to `randf_range * MAX_OFFSET * trauma²`. Add trauma with `_add_trauma(amount)`.
- **Debris:** spawn `Sprite2D` children directly into `get_tree().current_scene`, tween outward and fade, then `queue_free`.
- **`set_parallel(true)`** on a tween lets all `tween_property` calls run simultaneously; use `.chain()` to sequence steps after.

## Do Not

- Do not edit `.tscn` files (there are none).
- Do not call `NavigationServer2D.bake_from_source_geometry_data()` from outside `_ready()` — baking must happen after `NavigationRegion2D` is in the tree.
- Do not use `get_tree().paused = true` without setting `process_mode = ALWAYS` on any UI that needs to respond to input.
- Do not define two `func _process(...)` in the same file. **Before adding `_process`, `_physics_process`, or `_ready` to any file, grep for an existing definition and merge new logic into it.**
- Do not add new lifecycle functions without first checking the file — Game.gd already has `_process` (camera tracking + shake) and `_physics_process` is used per-node.
- **After any multi-line `replace_string_in_file` that appends new functions**, verify the boundary between the old and new code. A stray character from the last token of the replaced block (e.g. the `d` in `d.queue_free`) can be injected onto the start of the next line, producing a parser error like `Unexpected identifier "d" in class body`. Use `hexdump` or `sed -n 'Np'` to inspect the exact bytes if the error seems to point at a valid-looking line.

## Exporting the Game

To build a macOS release:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --export-release "macOS"
```
The output path is set in `export_presets.cfg` (`export_path`). Current target: `~/Desktop/AstroBro.zip`.

**`.tres.remap` in exported builds:** Godot's export process converts every `.tres` file to a `.tres.remap` stub inside the `.pck`. Any code that uses `DirAccess` to scan a directory for `.tres` files will find nothing in an exported build unless it also handles `.tres.remap`. Pattern to use everywhere:
```gdscript
if fname.ends_with(".tres") or fname.ends_with(".tres.remap"):
    var res = ResourceLoader.load(base_path + "/" + fname.trim_suffix(".remap"))
```
Affected files (already fixed): `Game.gd` (`_load_waves_from_dir`), `ShopUI.gd` (`_get_all_weapon_paths`, `_get_all_module_paths`), `BetweenWaveUI.gd` (upgrade scan).

**Gatekeeper (unsigned app):** Recipients must right-click → Open → Open on first launch, or run:
```bash
xattr -rd com.apple.quarantine /path/to/AstroBro.app
```

**ETC2 ASTC required:** The `universal`/`arm64` macOS preset requires `textures/vram_compression/import_etc2_astc=true` in `project.godot`. Already set.
