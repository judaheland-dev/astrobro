extends Node
class_name PlayerPowerCalculator

## PlayerPowerCalculator
##
## Tracks player "power" each wave and feeds an adaptive pressure score back to
## WaveManager so it can counter the player's loadout and performance.
##
## Power score is a single float (~1.0 = average baseline).
## Values above 1.0 mean the player is strong → ramp pressure.
## Values below 1.0 mean the player is struggling → ease back slightly.
##
## Usage (called from WaveManager):
##   calculator.register_players(player_list)
##   calculator.begin_wave()                       # called when a wave starts
##   calculator.record_kill(wave_elapsed_sec)      # called from _on_enemy_died
##   calculator.record_damage_taken(amount)        # called from player.took_damage
##   var snap = calculator.end_wave(enemies_spawned, wave_elapsed_sec)
##   var pressure = calculator.pressure_score      # use this in wave gen

# ──────────────────────────────────────────────────────────────────────────────
# Signals
# ──────────────────────────────────────────────────────────────────────────────
signal power_updated(score: float)
## Fired when the player hits extreme dominance (score >= DOMINANCE_EXTREME).
signal dominance_spike(score: float)

# ──────────────────────────────────────────────────────────────────────────────
# Public state
# ──────────────────────────────────────────────────────────────────────────────

## Current combined pressure score.  WaveManager reads this to scale waves.
var pressure_score: float = 1.0

## How hard the player is dominating right now (0.0 = struggling, 1.0 = god-mode).
## Updated each wave end.  WaveManager uses this to compress spawns and bypass the cap.
var dominance_score: float = 0.0

## Enemy-cap that grows slowly every wave. WaveManager enforces this.
var concurrent_enemy_cap: int = 20

## Bias dict: maps EnemyData id → extra weight added to that enemy type.
## WaveManager uses this to over-represent counters to the player's build.
var enemy_bias: Dictionary = {}   # StringName -> float bonus weight

# ──────────────────────────────────────────────────────────────────────────────
# Internal tracking
# ──────────────────────────────────────────────────────────────────────────────
var _players: Array[Player] = []
var _wave_kills: int = 0
var _wave_damage_taken: float = 0.0
var _wave_start_health: float = 0.0  # total HP across all players at wave start
var _kill_times: Array[float] = []   # seconds at which each kill happened
var _wave_count: int = 0

# Running "health fraction" history for smoothing (last N waves)
var _perf_history: Array[float] = []
const HISTORY_LEN: int = 5

# Exponential weight applied to each older history entry.
# 0.70 means each wave one step older carries 70% of the previous weight,
# so the most recent wave always dominates but old waves still matter.
const HISTORY_WEIGHT: float = 0.70

# Maximum pressure-score change allowed in a single wave (rate limiter).
# Prevents a single outlier wave from spiking/cratering difficulty instantly.
const MAX_PRESSURE_DELTA_PER_WAVE: float = 0.20

# Consecutive waves completed without taking any damage.
# Used to escalate the perfect-round pressure bonus.
var _consecutive_perfect_rounds: int = 0

# ──────────────────────────────────────────────────────────────────────────────
# CAP GROWTH CONFIG
# ──────────────────────────────────────────────────────────────────────────────
## Base concurrent enemy cap at wave 0.
const BASE_CAP: int = 20
## Cap grows by this amount every wave (fractional — accumulates).
const CAP_GROWTH_PER_WAVE: float = 0.4
## Hard ceiling the cap will never exceed.
const MAX_CAP: int = 60

# ──────────────────────────────────────────────────────────────────────────────
# Dominance thresholds
# ──────────────────────────────────────────────────────────────────────────────
## Above this dominance_score: pressure reacts faster and spawns compress.
const DOMINANCE_STRONG: float  = 0.68
## Above this dominance_score: concurrent cap is bypassed and a surge begins.
const DOMINANCE_EXTREME: float = 0.88

# ──────────────────────────────────────────────────────────────────────────────
# Difficulty scaling tables
# ──────────────────────────────────────────────────────────────────────────────
## Per-difficulty multiplier applied to the final pressure score.
## Values < 1.0 dampen the ramp (easy modes); > 1.0 amplify it (hard modes).
const PRESSURE_MULT: Dictionary = {
	GameManager.Difficulty.SUPER_EASY: 0.40,
	GameManager.Difficulty.EASY:       0.70,
	GameManager.Difficulty.NORMAL:     1.00,
	GameManager.Difficulty.HARD:       1.15,
	GameManager.Difficulty.SUPER_HARD: 1.65,
}
## Per-difficulty cap-growth rate multiplier.
const CAP_GROWTH_MULT: Dictionary = {
	GameManager.Difficulty.SUPER_EASY: 0.40,
	GameManager.Difficulty.EASY:       0.65,
	GameManager.Difficulty.NORMAL:     1.00,
	GameManager.Difficulty.HARD:       1.15,
	GameManager.Difficulty.SUPER_HARD: 1.70,
}
## Per-difficulty clamp ranges [min, max] for pressure_score.
const PRESSURE_CLAMP: Dictionary = {
	GameManager.Difficulty.SUPER_EASY: [0.35, 1.1],
	GameManager.Difficulty.EASY:       [0.45, 1.4],
	GameManager.Difficulty.NORMAL:     [0.55, 2.2],
	GameManager.Difficulty.HARD:       [0.65, 2.4],
	GameManager.Difficulty.SUPER_HARD: [0.85, 3.5],
}

# ──────────────────────────────────────────────────────────────────────────────
# Setup
# ──────────────────────────────────────────────────────────────────────────────

func register_players(player_list: Array[Player]) -> void:
	_players = player_list

## Returns the effective concurrent enemy cap.
## When the player is dominating the cap grows beyond MAX_CAP;
## at extreme dominance it is fully bypassed (returns a very large number).
func effective_enemy_cap() -> int:
	if dominance_score < DOMINANCE_STRONG:
		return concurrent_enemy_cap
	# Between STRONG and max dominance: linearly expand up to 2× cap.
	# No full bypass — keeps concurrent pressure gradual even at extreme dominance.
	var over: float = clampf(
		(dominance_score - DOMINANCE_STRONG) / (1.0 - DOMINANCE_STRONG),
		0.0, 1.0
	)
	return concurrent_enemy_cap + int(over * float(concurrent_enemy_cap))

# ──────────────────────────────────────────────────────────────────────────────
# Wave lifecycle hooks (called by WaveManager)
# ──────────────────────────────────────────────────────────────────────────────

func begin_wave() -> void:
	_wave_kills = 0
	_wave_damage_taken = 0.0
	_kill_times.clear()
	_wave_start_health = 0.0
	for p in _players:
		if is_instance_valid(p) and p.is_physics_processing():
			_wave_start_health += p.current_health + p.current_shield

func record_kill(wave_elapsed_sec: float) -> void:
	_wave_kills += 1
	_kill_times.append(wave_elapsed_sec)

func record_damage_taken(amount: float) -> void:
	_wave_damage_taken += amount

## Called at wave end.  Returns a snapshot dict for debugging.
func end_wave(enemies_spawned: int, wave_elapsed_sec: float) -> Dictionary:
	_wave_count += 1

	# ── Grow concurrent enemy cap (scaled by difficulty) ─────────────────────
	var cap_mult: float = CAP_GROWTH_MULT.get(GameManager.current_difficulty, 1.0)
	concurrent_enemy_cap = mini(
		MAX_CAP,
		BASE_CAP + int(_wave_count * CAP_GROWTH_PER_WAVE * cap_mult)
	)

	# ── Build component scores ────────────────────────────────────────────────
	var loadout_score: float  = _calc_loadout_score()
	var perf_score: float     = _calc_performance_score(enemies_spawned, wave_elapsed_sec)
	var survival_score: float = _calc_survival_score()

	# Combine: loadout is baked in; performance & survival reflect this wave
	# Weighted average: loadout 35%, performance 40%, survival 25%
	var combined: float = (
		loadout_score  * 0.35 +
		perf_score     * 0.40 +
		survival_score * 0.25
	)

	# ── Dominance score ──────────────────────────────────────────────────────
	# Raw single-wave dominance: how one-sidedly the player is winning RIGHT NOW.
	# kill_fraction: did they kill everything?
	# kill_speed:    did they kill fast? (2+ kills/sec = 1.0)
	# damage_taken:  did they take almost no damage?
	var _kill_frac: float = clampf(float(_wave_kills) / float(maxi(enemies_spawned, 1)), 0.0, 1.0)
	var _kps_norm:  float = clampf(_wave_kills / maxf(wave_elapsed_sec, 1.0) / 2.0, 0.0, 1.0)
	var _dmg_frac:  float = clampf(_wave_damage_taken / maxf(_wave_start_health, 1.0), 0.0, 2.0)
	var _dom_raw: float = (
		_kill_frac * 0.40 +
		_kps_norm  * 0.35 +
		clampf(1.0 - _dmg_frac * 0.8, 0.0, 1.0) * 0.25
	)
	# Light exponential smoothing: new reading weighted heavily so it responds quickly
	dominance_score = clampf(dominance_score * 0.30 + _dom_raw * 0.70, 0.0, 1.0)
	if dominance_score >= DOMINANCE_EXTREME:
		dominance_spike.emit(dominance_score)

	# ── Effective history length: shrink when dominating so pressure reacts fast.
	# Interpolated continuously across the STRONG→EXTREME dominance range so
	# there are no hard jumps in behaviour.  Minimum of 2 prevents a single
	# outlier wave from fully controlling the score.
	var eff_hist_len: int = HISTORY_LEN
	if dominance_score >= DOMINANCE_STRONG:
		var dom_t: float = clampf(
			(dominance_score - DOMINANCE_STRONG) / (DOMINANCE_EXTREME - DOMINANCE_STRONG),
			0.0, 1.0
		)
		eff_hist_len = maxi(2, roundi(lerpf(float(HISTORY_LEN), 2.0, dom_t)))

	# Smooth with exponentially-weighted history so recent waves dominate
	# but older context still softens transient spikes.
	_perf_history.append(combined)
	while _perf_history.size() > eff_hist_len:
		_perf_history.pop_front()
	var smoothed: float = 0.0
	var total_weight: float = 0.0
	for i in _perf_history.size():
		var age: int = _perf_history.size() - 1 - i   # 0 = newest
		var w: float = pow(HISTORY_WEIGHT, age)
		smoothed += _perf_history[i] * w
		total_weight += w
	smoothed /= total_weight

	# At extreme dominance, nudge the smoothed score toward the raw combined value
	# so sustained dominance still escalates even with a short history.
	if dominance_score >= DOMINANCE_EXTREME:
		var dom_over: float = (dominance_score - DOMINANCE_EXTREME) / (1.0 - DOMINANCE_EXTREME)
		smoothed = lerpf(smoothed, combined * 1.40, dom_over * 0.65)

	# Apply per-difficulty pressure multiplier and per-difficulty clamp range
	var diff_mult: float = PRESSURE_MULT.get(GameManager.current_difficulty, 1.0)
	var clamp_range: Array = PRESSURE_CLAMP.get(GameManager.current_difficulty, [0.55, 2.2])
	var target_score: float = clampf(smoothed * diff_mult, clamp_range[0], clamp_range[1])

	# Rate limiter: cap how much pressure can move in a single wave so a lone
	# exceptional wave cannot spike or crater difficulty instantly.
	pressure_score = clampf(
		target_score,
		pressure_score - MAX_PRESSURE_DELTA_PER_WAVE,
		pressure_score + MAX_PRESSURE_DELTA_PER_WAVE
	)
	pressure_score = clampf(pressure_score, clamp_range[0], clamp_range[1])

	# Perfect-round bonus: no damage taken this wave.
	# Consecutive perfect rounds escalate the bonus up to 2.5× the base.
	if _wave_damage_taken == 0.0:
		_consecutive_perfect_rounds += 1
		var streak_mult: float = clampf(1.0 + (_consecutive_perfect_rounds - 1) * 0.30, 1.0, 2.5)
		pressure_score = clampf(
			pressure_score + PERFECT_ROUND_PRESSURE_BONUS * streak_mult,
			clamp_range[0], clamp_range[1]
		)
	else:
		_consecutive_perfect_rounds = 0

	power_updated.emit(pressure_score)

	# ── Update enemy bias ─────────────────────────────────────────────────────
	_update_enemy_bias(loadout_score)

	return {
		"wave": _wave_count,
		"loadout": loadout_score,
		"performance": perf_score,
		"survival": survival_score,
		"pressure": pressure_score,
		"dominance": dominance_score,
		"enemy_cap": concurrent_enemy_cap,
		"effective_cap": effective_enemy_cap(),
		"bias": enemy_bias,
		"perfect_round_bonus": _wave_damage_taken == 0.0,
		"consecutive_perfect_rounds": _consecutive_perfect_rounds,
	}

# ──────────────────────────────────────────────────────────────────────────────
# Loadout score
# ──────────────────────────────────────────────────────────────────────────────

func _calc_loadout_score() -> float:
	var score: float = 1.0
	for p in _players:
		if not is_instance_valid(p):
			continue
		score = maxf(score, _player_loadout_score(p))
	return score

func _player_loadout_score(p: Player) -> float:
	var s: float = 1.0

	# ── Weapons DPS estimate ─────────────────────────────────────────────────
	var total_dps: float = 0.0
	var has_aoe: bool = false
	var has_laser: bool = false
	var has_rocket: bool = false
	var has_spread: bool = false
	var weapon_count: int = 0
	for w in p.weapons:
		if not is_instance_valid(w):
			continue
		var wd: WeaponData = w.get("weapon_data")
		if wd == null:
			continue
		var dmg: float   = w.get("damage") if w.get("damage") else wd.damage
		var rate: float  = w.get("fire_rate") if w.get("fire_rate") else wd.fire_rate
		var count: int   = wd.projectile_count
		var tier_bonus: float = 1.0 + (wd.tier - 1) * 0.25
		var is_mine: bool = wd.weapon_class == WeaponData.WeaponClass.TRAP
		# Mines are area-denial; their raw fire_rate * damage massively overstates
		# real DPS (arming delay, placement dependency, enemies must walk into them).
		# Use a 40% effectiveness discount and exclude from weapon-count / has_aoe.
		var dps_mult: float = 0.40 if is_mine else 1.0
		total_dps += dmg * rate * count * tier_bonus * dps_mult
		if not is_mine:
			weapon_count += 1  # only non-mine weapons count toward the slot bonus
			if wd.aoe_radius > 0.0:
				has_aoe = true
		match wd.ammo_type:
			WeaponData.AmmoType.LASER:  has_laser = true
			WeaponData.AmmoType.ROCKET: has_rocket = true
		if wd.weapon_class == WeaponData.WeaponClass.SPREAD:
			has_spread = true

	# Normalise DPS: 100 DPS ≈ baseline 1.0
	s += clampf((total_dps - 100.0) / 380.0, -0.3, 0.65)

	# Multi-weapon bonus (traps excluded from weapon_count above; count already correct)
	s += (weapon_count - 1) * 0.06

	# Diversity bonus (mixed types are stronger overall)
	var type_count: int = (1 if has_aoe else 0) + (1 if has_laser else 0) + (1 if has_rocket else 0) + (1 if has_spread else 0)
	s += type_count * 0.05

	# ── Defensive stats ──────────────────────────────────────────────────────
	# HP headroom above baseline 100 (power_level_bonus_hp excluded — no feedback loop)
	var max_hp: float = p.max_health + p.shield_max - p.power_level_bonus_hp
	s += clampf((max_hp - 100.0) / 400.0, -0.1, 0.30)

	# Armor (each point reduces damage; 8 armor is heavy)
	s += clampf(p.armor / 20.0, 0.0, 0.3)

	# Lifesteal
	s += clampf(p.lifesteal * 2.0, 0.0, 0.2)

	# ── Speed ────────────────────────────────────────────────────────────────
	# power_level_bonus_speed excluded — no feedback loop
	s += clampf((p.move_speed - p.power_level_bonus_speed - 200.0) / 400.0, -0.05, 0.15)

	# ── Level ────────────────────────────────────────────────────────────────
	s += clampf((p.level - 1) * 0.025, 0.0, 0.35)

	# ── Critical hits ────────────────────────────────────────────────────────
	# Effective crit multiplier: expected DPS bonus = crit_chance * (mult - 1)
	var eff_crit: float = p.crit_chance * (p.crit_multiplier - 1.0)
	s += clampf(eff_crit * 0.35, 0.0, 0.20)

	# ── Evasion ──────────────────────────────────────────────────────────────
	s += clampf(p.dodge_chance * 0.50, 0.0, 0.25)

	# ── Sustain ──────────────────────────────────────────────────────────────
	# On-kill healing (30 = cap → +0.15)
	s += clampf(p.on_kill_heal / 30.0 * 0.15, 0.0, 0.15)
	# Passive regen above the 0.35 hp/s baseline
	s += clampf((p.hp_regen - 0.35) / 4.65 * 0.12, 0.0, 0.12)

	# ── Shield quality ───────────────────────────────────────────────────────
	# Faster regen only matters if a shield exists
	if p.shield_max > 0.0:
		s += clampf((p.shield_regen_rate - 20.0) / 60.0 * 0.10, 0.0, 0.10)
	if p.reflective_shield:
		s += 0.10

	# ── Damage mitigation ────────────────────────────────────────────────────
	s += clampf(p.damage_block_chance * 0.20, 0.0, 0.15)

	# ── Upgrade breadth ──────────────────────────────────────────────────────
	# Each upgrade is a synergy node; depth of 20 upgrades ≈ +0.24
	s += clampf(p.acquired_upgrades.size() * 0.012, 0.0, 0.24)

	return maxf(s, 0.4)

# ──────────────────────────────────────────────────────────────────────────────
# Performance score (how fast / efficiently player killed enemies this wave)
# ──────────────────────────────────────────────────────────────────────────────

func _calc_performance_score(enemies_spawned: int, wave_elapsed_sec: float) -> float:
	if enemies_spawned <= 0 or wave_elapsed_sec <= 0.0:
		return 1.0

	# Kill rate: fraction of enemies killed
	var kill_fraction: float = clampf(float(_wave_kills) / float(enemies_spawned), 0.0, 1.0)

	# Speed score: kills-per-second relative to a "comfortable" rate of 1.5/s
	var kills_per_sec: float = _wave_kills / wave_elapsed_sec
	var speed_score: float = clampf(kills_per_sec / 1.5, 0.4, 2.0)

	# Early-kill bonus: if most kills happened before 60% of wave time, player is dominating
	var early_kills: int = 0
	var early_threshold: float = wave_elapsed_sec * 0.6
	for t in _kill_times:
		if t <= early_threshold:
			early_kills += 1
	var early_ratio: float = float(early_kills) / maxi(_wave_kills, 1)
	var early_bonus: float = clampf((early_ratio - 0.5) * 0.4, -0.1, 0.2)

	# Burst bonus: count 2-second windows that contain 3+ kills.
	# Each burst window reflects high-density AOE or weapon synergy.
	var burst_count: int = 0
	for i in _kill_times.size():
		var window_end: float = _kill_times[i] + 2.0
		var in_window: int = 1
		for j in range(i + 1, _kill_times.size()):
			if _kill_times[j] <= window_end:
				in_window += 1
			else:
				break
		if in_window >= 3:
			burst_count += 1
	var burst_bonus: float = clampf(burst_count * 0.025, 0.0, 0.25)

	return clampf(kill_fraction * speed_score + early_bonus + burst_bonus, 0.3, 2.0)

# ──────────────────────────────────────────────────────────────────────────────
# Survival score (how much health/shield was lost)
# ──────────────────────────────────────────────────────────────────────────────

func _calc_survival_score() -> float:
	if _wave_start_health <= 0.0:
		return 1.0
	# Players who took very little damage score > 1; lots of damage < 1
	var damage_fraction: float = clampf(_wave_damage_taken / _wave_start_health, 0.0, 1.5)
	# Invert: 0 damage taken → score 1.4; full HP lost → score 0.5
	return clampf(1.4 - damage_fraction * 0.8, 0.4, 1.4)

# ──────────────────────────────────────────────────────────────────────────────
# Enemy bias — figure out what enemy types counter the player's build
# ──────────────────────────────────────────────────────────────────────────────

func _update_enemy_bias(loadout_score: float) -> void:
	enemy_bias.clear()
	if _players.is_empty():
		return

	var has_aoe: bool    = false
	var has_laser: bool  = false
	var has_ranged_only: bool = true
	var is_fast: bool    = false
	var is_tanky: bool   = false
	var total_armor: float = 0.0

	for p in _players:
		if not is_instance_valid(p):
			continue
		if p.move_speed > 260.0:
			is_fast = true
		if p.max_health + p.shield_max > 200.0 or p.armor > 4.0:
			is_tanky = true
		total_armor += p.armor
		for w in p.weapons:
			var wd: WeaponData = w.get("weapon_data")
			if wd == null:
				continue
			if wd.aoe_radius > 0.0:
				has_aoe = true
			if wd.ammo_type == WeaponData.AmmoType.LASER:
				has_laser = true

	# Player has AoE → spawn spread/fast enemies that dodge clusters
	if has_aoe:
		enemy_bias[&"speeder"]  = 0.5
		enemy_bias[&"tracker"]  = 0.4

	# Player has lasers → spawn enemies that dodge (speeder) or block (brute)
	if has_laser:
		enemy_bias[&"speeder"] = (enemy_bias.get(&"speeder", 0.0) as float) + 0.3
		enemy_bias[&"brute"]   = (enemy_bias.get(&"brute",   0.0) as float) + 0.3

	# Player is tanky → spam ranged enemies to whittle HP at range
	if is_tanky:
		enemy_bias[&"ranger"]       = (enemy_bias.get(&"ranger",       0.0) as float) + 0.4
		enemy_bias[&"heavy_ranger"] = (enemy_bias.get(&"heavy_ranger", 0.0) as float) + 0.3
		enemy_bias[&"acid_ranger"]  = (enemy_bias.get(&"acid_ranger",  0.0) as float) + 0.3

	# Player is fast → more snipers and sentinels to punish kiting
	if is_fast:
		enemy_bias[&"sniper"]   = (enemy_bias.get(&"sniper",   0.0) as float) + 0.4
		enemy_bias[&"sentinel"] = (enemy_bias.get(&"sentinel", 0.0) as float) + 0.3

	# High armor → acid damage ignores armor
	if total_armor > 6.0:
		enemy_bias[&"acid_ranger"]  = (enemy_bias.get(&"acid_ranger",  0.0) as float) + 0.5
		enemy_bias[&"corruptor"]    = (enemy_bias.get(&"corruptor",    0.0) as float) + 0.4

	# If player is extremely powerful, bias toward elites
	if loadout_score > 1.8:
		enemy_bias[&"corruptor"] = (enemy_bias.get(&"corruptor", 0.0) as float) + 0.5
		enemy_bias[&"brute"]     = (enemy_bias.get(&"brute",     0.0) as float) + 0.3

# ──────────────────────────────────────────────────────────────────────────────
# Display Power — for HUD bar and shop power delta previews
# ──────────────────────────────────────────────────────────────────────────────

## Step between Power Level 1→2 (in raw score units). Each subsequent level
## costs POWER_LEVEL_GROWTH× more than the previous, so higher levels require
## progressively more power to reach.
## Calibrated for 100 levels:
##   Lv 1  = 0.70  (baseline – any fresh player; weak chars floored to 0.4 → fallback Lv 1)
##   Lv 15 ≈ 1.21  (a couple of weapons acquired)
##   Lv 26 ≈ 1.76  (decent mid-game loadout)
##   Lv 41 ≈ 2.80  (strong loadout on Normal)
##   Lv 61 ≈ 4.94  (near practical max on Normal difficulty)
##   Lv 86 ≈ 9.65  (requires Super Hard + excellent play)
##   Lv 93 ≈ 11.59 (hard)
##   Lv 99 ≈ 13.53 (super hard)
##   Lv 100 ≈ 13.88 (impossible)
const POWER_LEVEL_STEP: float = 0.031
## Per-level cost growth factor. 1.025 = each level costs 2.5% more than the last.
## Gentle early curve keeps low levels easy; compound growth makes 86-100 unreachable.
const POWER_LEVEL_GROWTH: float = 1.025
## Raw score at which Power Level 1 begins (≈ a fresh player with 1 weak weapon).
const POWER_LEVEL_BASE: float = 0.70
## Maximum displayed power level.
const POWER_LEVEL_MAX: int = 100
## Pressure-score bonus applied when a wave is completed without taking any damage.
## Kept as a dedicated constant so it reads clearly at the call site.
const PERFECT_ROUND_PRESSURE_BONUS: float = 0.08

## Comprehensive display power score for a player, scaled by difficulty.
## Easier modes dampen the score so the bar levels up more slowly and
## everything contributes less power. Harder modes are neutral or slightly generous.
static func calc_display_power(player: Player) -> float:
	return _static_loadout_score(player) * _difficulty_power_scale()

## Per-difficulty multiplier on the display power score.
## < 1.0 = bar levels up more slowly and items give less power.
static func _difficulty_power_scale() -> float:
	match GameManager.current_difficulty:
		GameManager.Difficulty.SUPER_EASY: return 0.45
		GameManager.Difficulty.EASY:       return 0.65
		GameManager.Difficulty.HARD:       return 1.10
		GameManager.Difficulty.SUPER_HARD: return 1.20
		_:                                 return 1.00  # NORMAL

## Maps a display power score to an integer Power Level (1–20).
static func power_to_level(score: float) -> int:
	for lv in range(POWER_LEVEL_MAX, 0, -1):
		if score >= _power_threshold_for_level(lv):
			return lv
	return 1

## Returns fractional progress (0.0–1.0) within the current power level.
static func power_level_progress(score: float) -> float:
	var lv := power_to_level(score)
	var lv_start := _power_threshold_for_level(lv)
	var lv_end   := _power_threshold_for_level(lv + 1)
	return clampf((score - lv_start) / (lv_end - lv_start), 0.0, 1.0)

## Returns the minimum raw score required to enter the given power level (1-based).
## Uses a geometric series: the cost of each level is POWER_LEVEL_GROWTH× the previous.
## threshold(1) = BASE; threshold(N) = BASE + STEP*(GROWTH^(N-1) − 1)/(GROWTH − 1)
static func _power_threshold_for_level(lv: int) -> float:
	if lv <= 1:
		return POWER_LEVEL_BASE
	return POWER_LEVEL_BASE + POWER_LEVEL_STEP * (pow(POWER_LEVEL_GROWTH, lv - 1) - 1.0) / (POWER_LEVEL_GROWTH - 1.0)

## Estimates the power score increase from buying a weapon.
static func weapon_power_delta(wdata: WeaponData, player: Player) -> float:
	var cur_dps := _static_player_dps(player)
	var tier_b := 1.0 + (wdata.tier - 1) * 0.25
	var w_dmg := wdata.damage
	if player.character_data:
		var cb := float(player.character_data.weapon_class_bonuses.get(int(wdata.weapon_class), 0.0))
		w_dmg *= (1.0 + cb)
	var is_trap := wdata.weapon_class == WeaponData.WeaponClass.TRAP
	var dps_eff_mult := 0.40 if is_trap else 1.0
	var added_dps := w_dmg * wdata.fire_rate * wdata.projectile_count * tier_b * dps_eff_mult
	var new_dps := cur_dps + added_dps
	var dps_delta := clampf((new_dps - 100.0) / 380.0, -0.20, 0.75) \
		- clampf((cur_dps - 100.0) / 380.0, -0.20, 0.75)
	# Traps don't add a firing-slot bonus; they're supplemental area denial.
	var count_bonus := 0.0 if is_trap else 0.06
	var div_delta := _static_diversity_delta(wdata, player)
	return maxf(0.0, dps_delta + count_bonus + div_delta) * _difficulty_power_scale()

## Estimates the power score increase from buying a module.
static func module_power_delta(item: UpgradeData, player: Player) -> float:
	var d := 0.0
	# HP / Shield
	var hp_d := float(item.stat_deltas.get(UpgradeData.StatKey.MAX_HEALTH, 0.0))
	var sh_d := float(item.stat_deltas.get(UpgradeData.StatKey.SHIELD_MAX, 0.0))
	if hp_d != 0.0 or sh_d != 0.0:
		var cur := player.max_health + player.shield_max
		var nxt := cur + hp_d + sh_d
		d += clampf((nxt - 100.0) / 300.0, -0.1, 0.4) - clampf((cur - 100.0) / 300.0, -0.1, 0.4)
	# Armor
	var arm_d := float(item.stat_deltas.get(UpgradeData.StatKey.ARMOR, 0.0))
	if arm_d != 0.0:
		d += clampf((player.armor + arm_d) / 20.0, 0.0, 0.3) - clampf(player.armor / 20.0, 0.0, 0.3)
	# Lifesteal
	var ls_d := float(item.stat_deltas.get(UpgradeData.StatKey.LIFESTEAL, 0.0))
	if ls_d != 0.0:
		d += clampf((player.lifesteal + ls_d) * 2.0, 0.0, 0.2) - clampf(player.lifesteal * 2.0, 0.0, 0.2)
	# Move speed
	var spd_d := float(item.stat_deltas.get(UpgradeData.StatKey.MOVE_SPEED, 0.0))
	if spd_d != 0.0:
		d += clampf((player.move_speed + spd_d - 200.0) / 400.0, -0.05, 0.15) \
		   - clampf((player.move_speed - 200.0) / 400.0, -0.05, 0.15)
	# Damage / fire-rate modify weapon DPS
	var dmg_d := float(item.stat_deltas.get(UpgradeData.StatKey.DAMAGE, 0.0))
	var fr_d  := float(item.stat_deltas.get(UpgradeData.StatKey.FIRE_RATE, 0.0))
	if dmg_d != 0.0 or fr_d != 0.0:
		var cur_dps := _static_player_dps(player)
		var new_dps := _static_player_dps_with_mods(player, dmg_d, fr_d)
		d += clampf((new_dps - 100.0) / 380.0, -0.20, 0.75) - clampf((cur_dps - 100.0) / 380.0, -0.20, 0.75)
	# Crit chance
	var crit_ch_d := float(item.stat_deltas.get(UpgradeData.StatKey.CRIT_CHANCE, 0.0))
	if crit_ch_d != 0.0:
		var new_eff := (player.crit_chance + crit_ch_d) * (player.crit_multiplier - 1.0)
		var old_eff := player.crit_chance * (player.crit_multiplier - 1.0)
		d += clampf(new_eff * 0.50, 0.0, 0.35) - clampf(old_eff * 0.50, 0.0, 0.35)
	# Dodge chance
	var dodge_d := float(item.stat_deltas.get(UpgradeData.StatKey.DODGE_CHANCE, 0.0))
	if dodge_d != 0.0:
		d += clampf((player.dodge_chance + dodge_d) * 0.50, 0.0, 0.25) \
		   - clampf(player.dodge_chance * 0.50, 0.0, 0.25)
	# On-kill heal
	var okh_d := float(item.stat_deltas.get(UpgradeData.StatKey.ON_KILL_HEAL, 0.0))
	if okh_d != 0.0:
		d += clampf((player.on_kill_heal + okh_d) / 30.0 * 0.15, 0.0, 0.15) \
		   - clampf(player.on_kill_heal / 30.0 * 0.15, 0.0, 0.15)
	# HP regen
	var regen_d := float(item.stat_deltas.get(UpgradeData.StatKey.HP_REGEN, 0.0))
	if regen_d != 0.0:
		d += clampf((player.hp_regen + regen_d - 0.35) / 4.65 * 0.12, 0.0, 0.12) \
		   - clampf((player.hp_regen - 0.35) / 4.65 * 0.12, 0.0, 0.12)
	# Shield regen rate (only meaningful if the player has a shield)
	var srr_d := float(item.stat_deltas.get(UpgradeData.StatKey.SHIELD_REGEN_RATE, 0.0))
	if srr_d != 0.0 and player.shield_max > 0.0:
		d += clampf((player.shield_regen_rate + srr_d - 20.0) / 60.0 * 0.10, 0.0, 0.10) \
		   - clampf((player.shield_regen_rate - 20.0) / 60.0 * 0.10, 0.0, 0.10)
	# Each new upgrade adds upgrade-depth score (+0.012 per upgrade, capped at 0.24)
	# A module purchase adds exactly one upgrade to the list.
	var upgrades_after: int = player.acquired_upgrades.size() + 1
	d += clampf(upgrades_after * 0.012, 0.0, 0.24) \
	   - clampf(player.acquired_upgrades.size() * 0.012, 0.0, 0.24)
	return maxf(0.0, d) * _difficulty_power_scale()

# ── Private static helpers ────────────────────────────────────────────────────

static func _static_loadout_score(p: Player) -> float:
	var s: float = 1.0
	var total_dps: float = 0.0
	var has_aoe: bool = false
	var has_laser: bool = false
	var has_rocket: bool = false
	var has_spread: bool = false
	var weapon_count: int = 0
	for w in p.weapons:
		if not is_instance_valid(w):
			continue
		var wd: WeaponData = w.get("weapon_data")
		if wd == null:
			continue
		var dmg: float  = w.get("damage") if w.get("damage") else wd.damage
		var rate: float = w.get("fire_rate") if w.get("fire_rate") else wd.fire_rate
		var cnt: int    = wd.projectile_count
		var tier_b: float = 1.0 + (wd.tier - 1) * 0.25
		var is_mine_s: bool = wd.weapon_class == WeaponData.WeaponClass.TRAP
		var dps_mult_s: float = 0.40 if is_mine_s else 1.0
		total_dps += dmg * rate * cnt * tier_b * dps_mult_s
		if not is_mine_s:
			weapon_count += 1
			if wd.aoe_radius > 0.0:
				has_aoe = true
		match wd.ammo_type:
			WeaponData.AmmoType.LASER:  has_laser = true
			WeaponData.AmmoType.ROCKET: has_rocket = true
		if wd.weapon_class == WeaponData.WeaponClass.SPREAD:
			has_spread = true
	s += clampf((total_dps - 100.0) / 380.0, -0.20, 0.75)
	s += (weapon_count - 1) * 0.06
	var type_count: int = (1 if has_aoe else 0) + (1 if has_laser else 0) \
		+ (1 if has_rocket else 0) + (1 if has_spread else 0)
	s += type_count * 0.05
	# power_level_bonus_hp / power_level_bonus_speed excluded — no feedback loop
	var max_hp: float = p.max_health + p.shield_max - p.power_level_bonus_hp
	s += clampf((max_hp - 100.0) / 300.0, -0.1, 0.4)
	s += clampf(p.armor / 20.0, 0.0, 0.3)
	s += clampf(p.lifesteal * 2.0, 0.0, 0.2)
	s += clampf((p.move_speed - p.power_level_bonus_speed - 200.0) / 400.0, -0.05, 0.15)
	s += clampf((p.level - 1) * 0.04, 0.0, 0.5)
	s += clampf(float(p.xp) / float(maxi(p.xp_threshold, 1)) * 0.04, 0.0, 0.04)
	# Current scrap wallet: hoarding large amounts = "wealth" = minor power.
	# No contribution below 50 scrap; ramps to 0.15 at ~250 scrap.
	var scrap_over := maxf(0.0, float(p.scrap) - 50.0)
	s += clampf(scrap_over / 200.0 * 0.15, 0.0, 0.15)
	# Critical hits
	var eff_crit: float = p.crit_chance * (p.crit_multiplier - 1.0)
	s += clampf(eff_crit * 0.50, 0.0, 0.35)
	# Evasion
	s += clampf(p.dodge_chance * 0.50, 0.0, 0.25)
	# Sustain
	s += clampf(p.on_kill_heal / 30.0 * 0.15, 0.0, 0.15)
	s += clampf((p.hp_regen - 0.35) / 4.65 * 0.12, 0.0, 0.12)
	# Shield quality
	if p.shield_max > 0.0:
		s += clampf((p.shield_regen_rate - 20.0) / 60.0 * 0.10, 0.0, 0.10)
	if p.reflective_shield:
		s += 0.10
	# Damage mitigation
	s += clampf(p.damage_block_chance * 0.20, 0.0, 0.15)
	# Upgrade breadth
	s += clampf(p.acquired_upgrades.size() * 0.012, 0.0, 0.24)
	# Flat power bonus accumulated via Evasion free rerolls
	s += p.flat_power_bonus
	return maxf(s, 0.4)

static func _static_player_dps(p: Player) -> float:
	var total := 0.0
	for w in p.weapons:
		if not is_instance_valid(w):
			continue
		var wd: WeaponData = w.get("weapon_data")
		if wd == null:
			continue
		var dmg: float  = w.get("damage") if w.get("damage") else wd.damage
		var rate: float = w.get("fire_rate") if w.get("fire_rate") else wd.fire_rate
		var tier_b: float = 1.0 + (wd.tier - 1) * 0.25
		total += dmg * rate * wd.projectile_count * tier_b
	return total

static func _static_player_dps_with_mods(p: Player, dmg_mod: float, fr_mod: float) -> float:
	var total := 0.0
	for w in p.weapons:
		if not is_instance_valid(w):
			continue
		var wd: WeaponData = w.get("weapon_data")
		if wd == null:
			continue
		var dmg: float  = maxf(0.0, (w.get("damage") if w.get("damage") else wd.damage) + dmg_mod)
		var rate: float = maxf(0.0, (w.get("fire_rate") if w.get("fire_rate") else wd.fire_rate) + fr_mod)
		var tier_b: float = 1.0 + (wd.tier - 1) * 0.25
		total += dmg * rate * wd.projectile_count * tier_b
	return total

static func _static_diversity_delta(wdata: WeaponData, p: Player) -> float:
	var has_aoe := false
	var has_laser := false
	var has_rocket := false
	var has_spread := false
	for w in p.weapons:
		if not is_instance_valid(w):
			continue
		var wd: WeaponData = w.get("weapon_data")
		if wd == null:
			continue
		if wd.aoe_radius > 0.0:                              has_aoe = true
		if wd.ammo_type == WeaponData.AmmoType.LASER:         has_laser = true
		if wd.ammo_type == WeaponData.AmmoType.ROCKET:        has_rocket = true
		if wd.weapon_class == WeaponData.WeaponClass.SPREAD:  has_spread = true
	var cur_types := (1 if has_aoe else 0) + (1 if has_laser else 0) \
		+ (1 if has_rocket else 0) + (1 if has_spread else 0)
	if wdata.aoe_radius > 0.0:                              has_aoe = true
	if wdata.ammo_type == WeaponData.AmmoType.LASER:         has_laser = true
	if wdata.ammo_type == WeaponData.AmmoType.ROCKET:        has_rocket = true
	if wdata.weapon_class == WeaponData.WeaponClass.SPREAD:  has_spread = true
	var new_types := (1 if has_aoe else 0) + (1 if has_laser else 0) \
		+ (1 if has_rocket else 0) + (1 if has_spread else 0)
	return (new_types - cur_types) * 0.05
