#!/usr/bin/env python3
"""
Rescale weapon stats so T3 (Rare/good) is the 'normal' baseline.
New power curve:
  T1 Common    (bad)     = T3 × 0.50
  T2 Uncommon  (normal)  = T3 × 0.72
  T3 Rare      (good)    = T3 × 1.00  ← unchanged
  T4 Epic      (awesome) = T3 × 1.45
  T5 Legendary (super)   = T3 × 2.00

Stats that scale: damage, fire_rate, projectile_speed, range, aoe_radius,
                  armor_pen, knockback_force, on_hit_dot_dps, homing_strength

Stats that do NOT scale (game-mechanic flags/counts, kept per-tier as-is
and defined by hand in the overrides dict below):
  piercing, projectile_count, bounce_count, chain_count, fork_count,
  on_hit_dot_ticks, spread, tier, rarity

spread: generally improves (decreases) with tier; handled as override.
"""

import re, os, copy
from pathlib import Path

WEAPONS_DIR = Path(__file__).parent.parent / "resources" / "weapons"

# Multipliers relative to T3 baseline
MULT = {1: 0.50, 2: 0.72, 3: 1.00, 4: 1.45, 5: 2.00}
RARITIES = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4}  # UpgradeData.Rarity enum

SCALE_STATS = [
    "damage",
    "fire_rate",
    "projectile_speed",
    "range",
    "aoe_radius",
    "armor_pen",
    "knockback_force",
    "on_hit_dot_dps",
    "homing_strength",
]

FLOAT_RE = re.compile(r"^(-?\d+(?:\.\d+)?)$")


def parse_float(v: str):
    m = FLOAT_RE.match(v.strip())
    return float(m.group(1)) if m else None


def read_tres(path: Path) -> dict:
    """Return a dict of key->value strings for the [resource] section."""
    data = {}
    in_resource = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip() == "[resource]":
            in_resource = True
            continue
        if in_resource and "=" in line:
            k, _, v = line.partition("=")
            data[k.strip()] = v.strip()
    return data


def write_tres(path: Path, new_values: dict[str, str]):
    """Overwrite specific key = value pairs in [resource] section."""
    lines = path.read_text(encoding="utf-8").splitlines()
    in_resource = False
    result = []
    for line in lines:
        if line.strip() == "[resource]":
            in_resource = True
            result.append(line)
            continue
        if in_resource and "=" in line:
            k, _, _ = line.partition("=")
            k = k.strip()
            if k in new_values:
                result.append(f"{k} = {new_values[k]}")
                continue
        result.append(line)
    path.write_text("\n".join(result) + "\n", encoding="utf-8")


def fmt(v: float) -> str:
    """Format a float value for a .tres file."""
    if v == int(v):
        return f"{int(v)}.0"
    return f"{round(v, 4)}"


# Weapon families
families = sorted(set(
    p.stem.replace("_t2", "").replace("_t3", "").replace("_t4", "").replace("_t5", "")
    for p in WEAPONS_DIR.glob("*.tres")
    if not re.search(r"_t[2-5]$", p.stem) or re.search(r"_t[2-5]$", p.stem)
))
# Deduplicate to only base names
base_names = sorted(set(
    re.sub(r"_t[2-5]$", "", p.stem)
    for p in WEAPONS_DIR.glob("*.tres")
))

for base in base_names:
    files = {
        1: WEAPONS_DIR / f"{base}.tres",
        2: WEAPONS_DIR / f"{base}_t2.tres",
        3: WEAPONS_DIR / f"{base}_t3.tres",
        4: WEAPONS_DIR / f"{base}_t4.tres",
        5: WEAPONS_DIR / f"{base}_t5.tres",
    }
    # Verify all 5 tiers exist
    if not all(f.exists() for f in files.values()):
        print(f"SKIP {base} (missing tiers)")
        continue

    # Read T3 as baseline
    t3 = read_tres(files[3])

    for tier_num, path in files.items():
        if tier_num == 3:
            # Still update rarity to be consistent
            write_tres(path, {"rarity": str(RARITIES[3])})
            continue

        mult = MULT[tier_num]
        updates: dict[str, str] = {}
        updates["rarity"] = str(RARITIES[tier_num])

        for stat in SCALE_STATS:
            if stat not in t3:
                continue
            base_val = parse_float(t3[stat])
            if base_val is None or base_val == 0.0:
                continue
            new_val = base_val * mult
            updates[stat] = fmt(new_val)

        write_tres(path, updates)
        print(f"  Updated {path.name}  (mult={mult})")

print("Done.")
