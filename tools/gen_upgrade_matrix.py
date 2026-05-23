#!/usr/bin/env python3
"""
gen_upgrade_matrix.py
Parses all .tres upgrade files and writes tools/upgrade_matrix.csv.
Run from anywhere; paths are relative to the script's own location.
"""

import os, re, csv

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
UPGRADES_DIR = os.path.join(SCRIPT_DIR, "..", "resources", "upgrades")
OUT_PATH = os.path.join(SCRIPT_DIR, "upgrade_matrix.csv")

# StatKey enum (matches UpgradeData.gd)
STAT_NAMES = {
    0:  "MaxHP",
    1:  "MoveSpd",
    2:  "Armor",
    3:  "Damage",
    4:  "FireRate",
    5:  "ProjSpd",
    6:  "XP%",
    7:  "Coin%",
    8:  "Lifesteal",
    9:  "Range",
    10: "Spread",
    11: "Block%",
    12: "Scrap%",
    13: "InstHeal",
    14: "ShieldMax",
    15: "ShieldRegen",
    16: "CritChance",
    17: "CritMult",
    18: "Bounce",
    19: "Chain",
    20: "Fork",
    21: "ArmorPen",
    22: "Knockback",
    23: "Dodge",
    24: "OnKillHeal",
    25: "HPRegen",
}

RARITY_NAMES = {0:"Common", 1:"Uncommon", 2:"Rare", 3:"Epic", 4:"Legendary", 5:"Mythic"}
SCOPE_NAMES  = {0:"Character", 1:"Weapon", 2:"Passive"}

# Path inference: dominant stat key → path name (mirrors BetweenWaveUI._STAT_PATH)
STAT_PATH = {
    0:  "TANK",        # MAX_HEALTH
    2:  "TANK",        # ARMOR
    11: "TANK",        # DAMAGE_BLOCK_CHANCE
    14: "SHIELD",      # SHIELD_MAX
    15: "SHIELD",      # SHIELD_REGEN_RATE
    1:  "SPEED",       # MOVE_SPEED
    23: "SPEED",       # DODGE_CHANCE
    8:  "PREDATOR",    # LIFESTEAL
    24: "PREDATOR",    # ON_KILL_HEAL
    25: "PREDATOR",    # HP_REGEN
    13: "PREDATOR",    # INSTANT_HEAL
    3:  "GUNSLINGER",  # DAMAGE
    4:  "GUNSLINGER",  # FIRE_RATE
    16: "GUNSLINGER",  # CRIT_CHANCE
    17: "GUNSLINGER",  # CRIT_MULTIPLIER
    21: "GUNSLINGER",  # ARMOR_PEN
    22: "GUNSLINGER",  # KNOCKBACK_FORCE
    5:  "SPECIALIST",  # PROJECTILE_SPEED
    9:  "SPECIALIST",  # RANGE
    10: "SPECIALIST",  # SPREAD
    18: "SPECIALIST",  # BOUNCE_COUNT
    19: "SPECIALIST",  # CHAIN_COUNT
    20: "SPECIALIST",  # FORK_COUNT
    6:  "SCAVENGER",   # XP_MULTIPLIER
    7:  "SCAVENGER",   # COIN_MULTIPLIER
    12: "SCAVENGER",   # SCRAP_BONUS_CHANCE
}

SYNERGY_STAT_NAMES = {
    0:"MaxHP", 1:"MoveSpd", 2:"Armor", 3:"Damage", 4:"FireRate", 5:"ProjSpd",
    8:"Lifesteal", 14:"ShieldMax", 16:"CritChance", 23:"Dodge", 25:"HPRegen",
}

def parse_tres(path):
    text = open(path, encoding="utf-8").read()

    def get(key, default=""):
        m = re.search(r'^\s*' + key + r'\s*=\s*(.+)', text, re.MULTILINE)
        return m.group(1).strip() if m else default

    uid_raw  = get("id", "").strip('"&')
    name     = get("display_name").strip('"')
    desc     = get("description").strip('"')
    rarity   = int(get("rarity", "0"))
    scope    = int(get("scope",  "0"))
    price    = int(get("shop_price", "0"))
    stacks   = int(get("max_stacks", "-1"))

    # stat_deltas: e.g. {3: 25.0, 4: 2.0}  or  {}
    deltas = {}
    m = re.search(r'stat_deltas\s*=\s*\{([^}]*)\}', text)
    if m and m.group(1).strip():
        for part in m.group(1).split(","):
            part = part.strip()
            kv = re.match(r'(\d+)\s*:\s*(-?[\d.]+)', part)
            if kv:
                deltas[int(kv.group(1))] = float(kv.group(2))

    # synergy fields
    syn_source  = get("synergy_source",  "")
    syn_target  = get("synergy_target",  "")
    syn_scale   = get("synergy_scale",   "0.0")
    syn_divisor = get("synergy_divisor", "10.0")
    has_synergy = float(syn_scale) != 0.0

    # manual override for stat-less passives
    MANUAL_PATH = {
        "afterburner":    "SPEED",
        "decoy_drone":    "TANK",
        "emp_module":     "GUNSLINGER",
        "orbital_turret": "GUNSLINGER",
        "reflective_shield": "SHIELD",
    }
    file_id = os.path.splitext(os.path.basename(path))[0]

    # Explicit build_path set in the .tres overrides everything
    raw_build_path = get("build_path", "").strip().lstrip("&").strip('"')

    # infer path
    path = raw_build_path or MANUAL_PATH.get(file_id, "")
    if not path and has_synergy and not deltas:
        # synergy-only upgrade: use synergy_source to pick path
        src_key = int(syn_source) if syn_source.isdigit() else -1
        path = STAT_PATH.get(src_key, "")
    if not path and deltas:
        best_key = max(deltas, key=lambda k: abs(deltas[k]))
        path = STAT_PATH.get(best_key, "")

    # synergy note
    syn_note = ""
    if has_synergy:
        s_name = SYNERGY_STAT_NAMES.get(int(syn_source) if syn_source.isdigit() else -1, syn_source)
        t_name = SYNERGY_STAT_NAMES.get(int(syn_target) if syn_target.isdigit() else -1, syn_target)
        syn_note = f"{s_name}→{t_name} ×{syn_scale} per {syn_divisor}"

    row = {
        "id":         uid_raw or file_id,
        "Name":       name,
        "Path":       path,
        "Rarity":     RARITY_NAMES.get(rarity, str(rarity)),
        "Scope":      SCOPE_NAMES.get(scope, str(scope)),
        "ShopPrice":  price,
        "MaxStacks":  stacks,
        "Description": desc,
        "Synergy":    syn_note,
    }
    for k, col in STAT_NAMES.items():
        row[col] = deltas.get(k, "")
    return row

COLUMNS = (
    ["id", "Name", "Path", "Rarity", "Scope", "ShopPrice", "MaxStacks"] +
    list(STAT_NAMES.values()) +
    ["Synergy", "Description"]
)

rows = []
for fname in sorted(os.listdir(UPGRADES_DIR)):
    if fname.endswith(".tres"):
        fpath = os.path.join(UPGRADES_DIR, fname)
        try:
            rows.append(parse_tres(fpath))
        except Exception as e:
            print(f"WARNING: failed to parse {fname}: {e}")

# Sort: Path → Rarity (ascending) → Name
RARITY_ORDER = {"Common":0, "Uncommon":1, "Rare":2, "Epic":3, "Legendary":4, "Mythic":5}
rows.sort(key=lambda r: (r["Path"] or "ZZZ", RARITY_ORDER.get(r["Rarity"], 9), r["Name"]))

with open(OUT_PATH, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
    w.writeheader()
    w.writerows(rows)

print(f"Written {len(rows)} upgrades → {OUT_PATH}")
