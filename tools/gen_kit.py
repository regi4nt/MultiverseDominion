#!/usr/bin/env python3
"""Regenerates the per-King and per-Monster kits so that all 28 Kings and all 28 Monsters differ.
Reads and rewrites: data/champions.json, data/king_buffs.json, data/king_passives.json, data/monsters.json, data/skills.json.
Run from the project root:  python3 tools/gen_kit.py   (idempotent; the Python tables below are the source of truth)."""
import json, os, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def load(p): return json.load(open(os.path.join(ROOT, p)))
def save(p, d): json.dump(d, open(os.path.join(ROOT, p), "w"), indent="\t", ensure_ascii=False); open(os.path.join(ROOT, p), "a").write("\n")
def pct(x): return "%d%%" % round(x * 100)

# ---------------------------------------------------------------- skill ops -> text
def describe(op):
    k = op["op"]; m = pct(op.get("m", 1.0)); t = op.get("t", 0)
    return {
        "dmg_all": lambda: "deals %s ATK to all enemies" % m,
        "dmg_rand": lambda: "hits %d random enemies for %s ATK" % (op["n"], m),
        "dmg_near": lambda: "enemies within %d cells take %s ATK" % (op["r"], m),
        "dmg_tough": lambda: "hits the toughest enemy for %s ATK%s" % (m, (" and heals %s of the damage" % pct(op["leech"])) if op.get("leech") else ""),
        "dmg_weak": lambda: ("teleports to the weakest enemy and hits it for %s ATK" if op.get("jump") else "hits the weakest enemy for %s ATK") % m,
        "dmg_low": lambda: "enemies below %s HP take %s ATK" % (pct(op["thr"]), m),
        "dmg_col": lambda: "enemies in its column take %s ATK" % m,
        "dmg_row": lambda: "enemies in its row take %s ATK" % m,
        "dmg_top": lambda: ("hits the %d highest-ATK enemies for %s ATK" % (op["n"], m)) if op["n"] > 1 else ("hits the highest-ATK enemy for %s ATK" % m),
        "stun_all": lambda: "stuns all enemies for %d ticks" % t,
        "stun_near": lambda: "stuns enemies within %d cells for %d ticks" % (op["r"], t),
        "stun_top": lambda: ("stuns the %d highest-ATK enemies for %d ticks" % (op["n"], t)) if op["n"] > 1 else ("stuns the highest-ATK enemy for %d ticks" % t),
        "slow_all": lambda: "slows all enemies for %d ticks" % t,
        "slow_near": lambda: "slows enemies within %d cells for %d ticks" % (op["r"], t),
        "burn_all": lambda: "burns all enemies for %s ATK every 4 ticks for %d ticks" % (pct(op["p"]), t),
        "mark_all": lambda: "enemies take %s more damage for %d ticks" % (pct(op["p"]), t),
        "drain_energy": lambda: "drains %d energy from the enemy side" % op["n"],
        "shield_self": lambda: "gains a shield worth %s of max HP" % pct(op["p"]),
        "shield_team": lambda: "every ally gains a shield worth %s of its max HP" % pct(op["p"]),
        "heal_self": lambda: "heals %s of its max HP" % pct(op["p"]),
        "heal_team": lambda: "heals every ally for %s of its max HP" % pct(op["p"]),
        "heal_low": lambda: "heals the most wounded ally for %s of its max HP" % pct(op["p"]),
        "reduce_self": lambda: "takes 50%% less damage for %d ticks" % t,
        "reduce_team": lambda: "every ally takes 50%% less damage for %d ticks" % t,
        "atk_self": lambda: "gains +%s ATK for %d ticks" % (pct(op["m"]), t),
        "atk_team": lambda: "every ally gains +%s ATK for %d ticks" % (pct(op["m"]), t),
        "cleanse": lambda: "cleanses allies of stun, slow and burn",
        "energy": lambda: "grants %d energy" % op["n"],
        "revive": lambda: "revives the last fallen ally at %s HP" % pct(op["p"]),
        "haste": lambda: "allies attack faster for %d ticks" % t,
    }[k]()
def desc_of(fx):
    parts = [describe(o) for o in fx]
    return "Manual, once: " + ", ".join(parts[:-1]) + (", and " if len(parts) > 2 else " and ") * (len(parts) > 1) + parts[-1] + "." if len(parts) > 1 else "Manual, once: %s." % parts[0]
def main_value(fx):
    o = fx[0]
    for key in ("m", "p", "t", "n"):
        if key in o: return o[key]
    return 1.0
def O(op, **kw): d = {"op": op}; d.update(kw); return d

# ---------------------------------------------------------------- KING skills (28 different)
KING_SKILLS = {
 "solvaris":  ("dawnbreak_decree",   "Dawnbreak Decree",     [O("dmg_all", m=1.2), O("heal_team", p=0.10)]),
 "nocthyr":   ("umbral_pact",        "Umbral Pact",          [O("dmg_weak", m=2.2, jump=True), O("reduce_self", t=10)]),
 "valdoria":  ("ironbound_rampart",  "Ironbound Rampart",    [O("shield_team", p=0.20), O("shield_self", p=0.30)]),
 "elarion":   ("stardust_snare",     "Stardust Snare",       [O("dmg_rand", n=3, m=2.0), O("slow_all", t=8)]),
 "astralis":  ("starfall_execution", "Starfall Execution",   [O("dmg_low", thr=0.4, m=3.2)]),
 "ignivar":   ("emberlord_pyre",     "Emberlord's Pyre",     [O("burn_all", p=0.35, t=12), O("dmg_near", r=3, m=1.2)]),
 "cryndel":   ("absolute_zero",      "Absolute Zero",        [O("slow_all", t=12), O("mark_all", p=0.15, t=12)]),
 "umbrael":   ("hollow_communion",   "Hollow Communion",     [O("dmg_tough", m=2.0, leech=1.0), O("shield_self", p=0.15)]),
 "ferrum":    ("goliath_protocol",   "Goliath Protocol",     [O("shield_self", p=0.45), O("atk_self", m=0.30, t=12)]),
 "voltrix":   ("overload_pulse",     "Overload Pulse",       [O("dmg_row", m=1.8), O("stun_top", n=2, t=2)]),
 "chronex":   ("stasis_field",       "Stasis Field",         [O("stun_near", r=3, t=4), O("haste", t=10)]),
 "nexaris":   ("arbiters_verdict",   "Arbiter's Verdict",    [O("dmg_top", n=2, m=2.4), O("shield_team", p=0.10)]),
 "verdantia": ("verdant_renewal",    "Thornwarden's Renewal",[O("heal_team", p=0.20), O("cleanse")]),
 "besthara":  ("alphas_hunt",        "Alpha's Hunt",         [O("atk_self", m=0.50, t=12), O("dmg_weak", m=1.8, jump=True)]),
 "floralis":  ("bloom_sanctuary",    "Bloom Sanctuary",      [O("heal_low", p=0.60), O("reduce_team", t=8)]),
 "terragorn": ("mountains_wrath",    "Mountain's Wrath",     [O("dmg_near", r=2, m=1.6), O("shield_self", p=0.35)]),
 "drakhan":   ("dragonbreath",       "Dragonbreath",         [O("dmg_col", m=2.6), O("burn_all", p=0.25, t=8)]),
 "inferna":   ("hellbride_wedding",  "Hellbride's Wedding",  [O("dmg_all", m=1.3), O("burn_all", p=0.20, t=8)]),
 "bloodfang": ("blood_harvest",      "Blood Harvest",        [O("dmg_tough", m=2.6, leech=1.0), O("atk_self", m=0.25, t=12)]),
 "warborn":   ("warcry_of_krogg",    "Warcry of Krogg",      [O("atk_team", m=0.30, t=12), O("shield_self", p=0.20)]),
 "abyssal":   ("crushing_depths",    "Crushing Depths",      [O("slow_all", t=10), O("dmg_all", m=0.9)]),
 "pelagia":   ("tidemother_tide",    "Tidemother's Tide",    [O("heal_team", p=0.15), O("shield_team", p=0.10)]),
 "tempestra": ("storm_barrage",      "Storm Surge Barrage",  [O("dmg_rand", n=4, m=1.8), O("stun_top", n=1, t=2)]),
 "corsaria":  ("broadside_boarding", "Broadside Boarding",   [O("dmg_weak", m=2.8, jump=True), O("dmg_near", r=1, m=1.2)]),
 "solstice":  ("eclipse_corona",     "Eclipse Corona",       [O("dmg_all", m=1.1), O("atk_team", m=0.20, t=10)]),
 "paradox":   ("paradox_cascade",    "Paradox Cascade",      [O("dmg_weak", m=2.5, jump=True), O("energy", n=2)]),
 "eternis":   ("unending_cycle",     "Unending Cycle",       [O("heal_self", p=0.35), O("revive", p=0.40), O("cleanse")]),
 "oblivion":  ("oblivion_edict",     "Oblivion's Edict",     [O("dmg_low", thr=0.5, m=2.6), O("drain_energy", n=3)]),
}

# ---------------------------------------------------------------- MONSTER skills ("King+": 2-3 effects each)
MON_SKILLS = {
 "crownstone_golem":   ("crownstone_bulwark",  "Crownstone Bulwark",   [O("shield_self", p=0.40), O("reduce_self", t=10), O("stun_near", r=1, t=2)]),
 "sunscorch_manticore":("sunfire_eruption",    "Sunfire Eruption",     [O("burn_all", p=0.30, t=12), O("dmg_near", r=3, m=1.6)]),
 "vale_thornstag":     ("thornstag_rut",       "Thornstag Rut",        [O("atk_self", m=0.50, t=12), O("dmg_near", r=1, m=1.4), O("shield_self", p=0.15)]),
 "keep_wraith":        ("wraith_siphon",       "Wraith Siphon",        [O("dmg_tough", m=2.2, leech=1.0), O("drain_energy", n=2)]),
 "spire_sentinel":     ("sentinel_ward_shroud","Sentinel Ward-Shroud", [O("reduce_team", t=10), O("heal_team", p=0.10), O("shield_self", p=0.20)]),
 "cinder_phoenix":     ("phoenix_rebirth",     "Phoenix Rebirth",      [O("revive", p=0.50), O("dmg_all", m=0.9), O("heal_self", p=0.15)]),
 "rimeclaw_yeti":      ("yeti_avalanche",      "Yeti Avalanche",       [O("slow_all", t=10), O("dmg_near", r=2, m=1.8), O("mark_all", p=0.10, t=10)]),
 "vault_shadehound":   ("shadehound_pounce",   "Shadehound Pounce",    [O("dmg_weak", m=2.8, jump=True), O("dmg_low", thr=0.3, m=1.6)]),
 "gearwork_behemoth":  ("behemoth_overclock",  "Behemoth Overclock",   [O("shield_self", p=0.50), O("atk_self", m=0.40, t=12), O("haste", t=10)]),
 "arc_hound":          ("arc_hound_storm",     "Arc Hound Storm",      [O("stun_top", n=3, t=2), O("dmg_row", m=1.5)]),
 "foundry_drone":      ("drone_swarm",         "Drone Swarm",          [O("dmg_rand", n=4, m=1.5), O("energy", n=2)]),
 "nexus_overseer":     ("overseer_lockdown",   "Overseer Lockdown",    [O("stun_all", t=2), O("mark_all", p=0.20, t=10)]),
 "canopy_treant":      ("treant_rooting",      "Treant Rooting",       [O("stun_near", r=2, t=3), O("heal_self", p=0.25), O("shield_self", p=0.15)]),
 "petal_dryad":        ("petal_storm",         "Petal Storm",          [O("dmg_all", m=0.8), O("heal_team", p=0.12), O("slow_all", t=6)]),
 "hollow_direbear":    ("direbear_maul",       "Direbear Maul",        [O("atk_self", m=0.60, t=12), O("dmg_tough", m=1.8, leech=0.5)]),
 "rootmaw_behemoth":   ("rootmaw_devour",      "Rootmaw Devour",       [O("dmg_col", m=2.0), O("heal_self", p=0.20), O("reduce_self", t=8)]),
 "spinewing_drake":    ("drake_strafe",        "Drake Strafe",         [O("dmg_col", m=2.2), O("burn_all", p=0.25, t=10), O("haste", t=8)]),
 "hellforge_infernal": ("hellforge_detonation","Hellforge Detonation", [O("dmg_all", m=1.1), O("dmg_near", r=2, m=1.0), O("burn_all", p=0.15, t=8)]),
 "pit_fiend":          ("pit_fiend_rend",      "Pit Fiend Rend",       [O("dmg_tough", m=2.8, leech=0.6), O("mark_all", p=0.15, t=10)]),
 "bastion_warlord":    ("warlord_charge",      "Warlord's Charge",     [O("dmg_weak", m=2.6, jump=True), O("atk_self", m=0.30, t=12), O("shield_self", p=0.20)]),
 "strait_leviathan":   ("leviathan_maelstrom", "Leviathan Maelstrom",  [O("slow_near", r=5, t=12), O("dmg_near", r=3, m=1.4), O("reduce_self", t=8)]),
 "atoll_hydra":        ("hydra_heads",         "Hydra Heads",          [O("dmg_rand", n=5, m=1.3), O("heal_self", p=0.15)]),
 "abyssal_kraken":     ("kraken_grasp",        "Kraken Grasp",         [O("stun_top", n=2, t=4), O("dmg_tough", m=1.6, leech=0.5)]),
 "cove_ghostcaptain":  ("ghostcaptain_boarding","Ghostcaptain's Boarding",[O("dmg_weak", m=2.4, jump=True), O("drain_energy", n=3), O("reduce_self", t=8)]),
 "solstice_chronowyrm":("chronowyrm_rewind",   "Chronowyrm Rewind",    [O("heal_team", p=0.12), O("cleanse"), O("stun_near", r=3, t=3)]),
 "paradox_stalker":    ("echo_stalk",          "Echo Stalk",           [O("dmg_weak", m=2.2, jump=True), O("dmg_low", thr=0.35, m=2.0), O("energy", n=1)]),
 "hour_sentinel":      ("hour_judgment",       "Hour Judgment",        [O("stun_all", t=2), O("shield_team", p=0.12), O("reduce_self", t=8)]),
 "rim_voidmaw":        ("voidmaw_devour",      "Voidmaw Devour",       [O("dmg_low", thr=0.45, m=3.0), O("heal_self", p=0.25), O("drain_energy", n=2)]),
}

# ---------------------------------------------------------------- King buffs (battle buff on its home continent): 10 Kings get a NEW type so all 28 differ
NEW_KING_BUFFS = {
 "bloodfang": ("feast", 0.12, "Reaver's Feast", "Heals 12% max HP for every enemy it defeats."),
 "warborn":   ("bastion", 0.25, "Warband Bastion", "No single hit can take more than 25% of max HP."),
 "abyssal":   ("weaken", 0.15, "Abyssal Pressure", "Attacks mark the target: it takes 15% more damage for 8 ticks."),
 "pelagia":   ("rally_cry", 0.12, "Tidemother's Call", "On entering the arena, all allies gain +12% ATK for 12 ticks."),
 "tempestra": ("chain", 0.4, "Chain Lightning", "Attacks arc to the nearest other enemy within 2 cells for 40% damage."),
 "corsaria":  ("crit", 0.6, "Broadside Volley", "Every 3rd attack deals +60% damage."),
 "solstice":  ("momentum", 0.03, "Solar Crescendo", "Each attack adds +3% ATK (up to 8 times)."),
 "paradox":   ("quickkill", 1, "Time Skip", "After defeating an enemy, attacks again at once."),
 "eternis":   ("undying", 0.25, "Unending", "Survives one lethal hit and returns with 25% max HP."),
 "oblivion":  ("shatter", 0.4, "Unmaking Strike", "Deals 40% more damage to shielded targets."),
}

# ---------------------------------------------------------------- King battle passive: second pair (type2, value2)
BP2 = {
 "solvaris": ("king_atk", .08), "nocthyr": ("king_atk", .15), "valdoria": ("king_hp", .12), "elarion": ("team_atk", .03),
 "astralis": ("king_hp", .15), "ignivar": ("team_hp", .04), "cryndel": ("team_shield", .05), "umbrael": ("team_armor", .03),
 "ferrum": ("king_atk", .10), "voltrix": ("team_shield", .03), "chronex": ("team_hp", .04), "nexaris": ("team_atk", .04),
 "verdantia": ("king_hp", .15), "besthara": ("team_armor", .03), "floralis": ("team_hp", .05), "terragorn": ("team_armor", .02),
 "drakhan": ("team_hp", .05), "inferna": ("king_atk", .10), "bloodfang": ("team_atk", .03), "warborn": ("team_atk", .03),
 "abyssal": ("team_hp", .04), "pelagia": ("team_armor", .03), "tempestra": ("team_shield", .04), "corsaria": ("king_atk", .10),
 "solstice": ("team_atk", .03), "paradox": ("team_shield", .04), "eternis": ("team_hp", .04), "oblivion": ("team_atk", .04),
}
BP_TEXT = {"team_atk": "all units gain +%s ATK", "team_hp": "all units gain +%s max HP", "team_armor": "all units take %s less damage",
           "team_shield": "all units start with a shield of %s max HP", "king_hp": "the King enters with +%s max HP", "king_atk": "the King enters with +%s ATK"}

# ---------------------------------------------------------------- Territory skills: (primary name) + second skill (id, value)
TERR_NAMES = {
 "solvaris": "Dawn Tithe", "nocthyr": "Shadow Ledger", "valdoria": "Landlord", "elarion": "Fortune Weave", "astralis": "Treasure Hunter",
 "ignivar": "Spoils of War", "cryndel": "Frostweaver's Mercy", "umbrael": "Hollow Accounts", "ferrum": "Quartermaster", "voltrix": "Toll Keeper",
 "chronex": "Chrono Treasury", "nexaris": "Vanguard", "verdantia": "Thornwarden's Mercy", "besthara": "Pack Vanguard", "floralis": "Bloom Bounty",
 "terragorn": "Rootholder", "drakhan": "Dragon Hoard", "inferna": "Hellbride's Toll", "bloodfang": "Reaver's Armory", "warborn": "Warlord's Wager",
 "abyssal": "Tidal Contracts", "pelagia": "Tidemother's Mercy", "tempestra": "Storm Salvage", "corsaria": "Plunder Rights", "solstice": "Solar Treasury",
 "paradox": "Paradox Gambit", "eternis": "Eternal Ledger", "oblivion": "Void Plunder"}
TERR2 = {
 "solvaris": ("interest", .03), "nocthyr": ("war_chest", 60), "valdoria": ("upgrader", .15), "elarion": ("treasure_hunter", 10),
 "astralis": ("fortune_weave", 1), "ignivar": ("quartermaster", .10), "cryndel": ("tax_cut", .10), "umbrael": ("spoils", 15),
 "ferrum": ("upgrader", .10), "voltrix": ("interest", .02), "chronex": ("fortune_weave", 1), "nexaris": ("quartermaster", .10),
 "verdantia": ("rent_cut", .10), "besthara": ("spoils", 15), "floralis": ("mender", .20), "terragorn": ("rent_cut", .10),
 "drakhan": ("war_chest", 80), "inferna": ("spoils", 10), "bloodfang": ("vanguard", 1), "warborn": ("landlord", .05),
 "abyssal": ("interest", .02), "pelagia": ("treasure_hunter", 10), "tempestra": ("toll_keeper", .10), "corsaria": ("war_chest", 60),
 "solstice": ("upgrader", .10), "paradox": ("interest", .02), "eternis": ("mender", .25), "oblivion": ("tax_cut", .15)}
TERR_TEXT = {
 "royal_treasury": "+%s Dominion Gold from passing START", "shadow_ledger": "Pay %s less Tax and territory rent", "landlord": "Territories cost %s less to buy",
 "fortune_weave": "Start with %d Reroll Token(s)", "treasure_hunter": "Event tiles pay +%d G", "spoils": "+%d G for every Duel won or defended",
 "quartermaster": "Battle Shop prices are %s lower", "toll_keeper": "Rent collected on your land is %s higher", "mender": "Healing costs %s less",
 "vanguard": "Start with %d extra Rare unit(s)", "interest": "Passing START also pays %s interest on your gold (max 120 G)",
 "war_chest": "Start the match with +%d G", "rent_cut": "Pay %s less territory rent", "tax_cut": "Pay %s less Tax", "upgrader": "Territory upgrades cost %s less"}
INT_TYPES = {"fortune_weave", "treasure_hunter", "spoils", "vanguard", "war_chest"}
def terr_text(t, v): return TERR_TEXT[t] % (int(v) if t in INT_TYPES else pct(v))

# ---------------------------------------------------------------- Monster "Plus" trait (a second buff on top of the monster's own): (type, value, name, desc)
PLUS = {
 "crownstone_golem": ("bastion", .20, "Keystone Plating", "No single hit can take more than 20% of max HP."),
 "sunscorch_manticore": ("crit", .50, "Scorpion Sting", "Every 3rd attack deals +50% damage."),
 "vale_thornstag": ("vengeance", .20, "Stag's Wrath", "When an ally falls, gains +20% ATK for 8 ticks."),
 "keep_wraith": ("feast", .10, "Garrison Feast", "Heals 10% max HP for every enemy it defeats."),
 "spire_sentinel": ("siphon", 1, "Arcane Siphon", "Every 3rd attack restores 1 energy to its side."),
 "cinder_phoenix": ("momentum", .03, "Rising Flame", "Each attack adds +3% ATK (up to 8 times)."),
 "rimeclaw_yeti": ("weaken", .12, "Rime Mark", "Attacks mark the target: it takes 12% more damage for 8 ticks."),
 "vault_shadehound": ("quickkill", 1, "Hunter's Pace", "After defeating an enemy, attacks again at once."),
 "gearwork_behemoth": ("shatter", .35, "Piston Breaker", "Deals 35% more damage to shielded targets."),
 "arc_hound": ("chain", .40, "Arc Chain", "Attacks arc to the nearest other enemy within 2 cells for 40% damage."),
 "foundry_drone": ("rally_cry", .10, "Hive Signal", "On entering the arena, all allies gain +10% ATK for 12 ticks."),
 "nexus_overseer": ("siphon", 2, "Grid Tap", "Every 3rd attack restores 2 energy to its side."),
 "canopy_treant": ("bastion", .25, "Heartwood Bark", "No single hit can take more than 25% of max HP."),
 "petal_dryad": ("vengeance", .15, "Petal Vengeance", "When an ally falls, gains +15% ATK for 8 ticks."),
 "hollow_direbear": ("feast", .12, "Maw Feast", "Heals 12% max HP for every enemy it defeats."),
 "rootmaw_behemoth": ("undying", .20, "Rootbound", "Survives one lethal hit and returns with 20% max HP."),
 "spinewing_drake": ("momentum", .04, "Strafing Speed", "Each attack adds +4% ATK (up to 8 times)."),
 "hellforge_infernal": ("crit", .60, "Forge Hammer", "Every 3rd attack deals +60% damage."),
 "pit_fiend": ("weaken", .15, "Fiend's Mark", "Attacks mark the target: it takes 15% more damage for 8 ticks."),
 "bastion_warlord": ("shatter", .40, "Siege Breaker", "Deals 40% more damage to shielded targets."),
 "strait_leviathan": ("rally_cry", .08, "Leviathan's Roar", "On entering the arena, all allies gain +8% ATK for 12 ticks."),
 "atoll_hydra": ("chain", .30, "Hydra Lash", "Attacks arc to the nearest other enemy within 2 cells for 30% damage."),
 "abyssal_kraken": ("quickkill", 1, "Tentacle Frenzy", "After defeating an enemy, attacks again at once."),
 "cove_ghostcaptain": ("undying", .25, "Ghost Ship", "Survives one lethal hit and returns with 25% max HP."),
 "solstice_chronowyrm": ("siphon", 1, "Time Siphon", "Every 3rd attack restores 1 energy to its side."),
 "paradox_stalker": ("momentum", .035, "Echo Momentum", "Each attack adds +3.5% ATK (up to 8 times)."),
 "hour_sentinel": ("weaken", .10, "Hourglass Mark", "Attacks mark the target: it takes 10% more damage for 8 ticks."),
 "rim_voidmaw": ("vengeance", .25, "Voidmaw Hunger", "When an ally falls, gains +25% ATK for 8 ticks."),
}

def main():
    ch = load("data/champions.json"); kb = load("data/king_buffs.json"); kp = load("data/king_passives.json"); mons = load("data/monsters.json")
    skills = {}
    for fac, (sid, name, fx) in KING_SKILLS.items():
        k = "champion_" + fac; c = ch[k]
        # keep the ORIGINAL primary Territory skill (type / value) and give it a unique name + the second skill
        c["skill_id"] = sid; c["active_name"] = name; c["active_value"] = main_value(fx); c["active_desc"] = desc_of(fx)
        t2, v2 = TERR2[fac]
        c["passive_name"] = TERR_NAMES[fac]; c["passive2"] = t2; c["passive2_value"] = v2
        c["passive_desc"] = terr_text(c["passive"], c["passive_value"]) + ". " + terr_text(t2, v2) + "."
        skills[sid] = {"name": name, "desc": c["active_desc"], "fx": fx}
        if fac in NEW_KING_BUFFS:
            ty, v, n, d = NEW_KING_BUFFS[fac]; kb[k] = {"name": n, "type": ty, "value": v, "desc": d}
        t2b, v2b = BP2[fac]; p = kp[k]; p["type2"] = t2b; p["value2"] = v2b
        base = p.get("desc_base") or p["desc"]; p["desc_base"] = base
        first = {"team_atk": "All your units gain +%s ATK", "team_hp": "All your units gain +%s max HP", "team_armor": "All your units take %s less damage",
                 "team_shield": "All your units start with a shield worth %s of max HP", "king_hp": "The King enters with +%s max HP", "king_atk": "The King enters with +%s ATK"}[p["type"]]
        p["desc"] = (first % pct(p["value"])) + "; " + (BP_TEXT[t2b] % pct(v2b)) + "."
    for cid, lst in mons["continents"].items():
        for m in lst:
            sid, name, fx = MON_SKILLS[m["id"]]
            m["skill_id"] = sid; m["active_name"] = name; m["active_value"] = main_value(fx); m["active_desc"] = desc_of(fx)
            ty, v, n, d = PLUS[m["id"]]; m["plus"] = {"type": ty, "value": v, "name": n, "desc": d}
            skills[sid] = {"name": name, "desc": m["active_desc"], "fx": fx}
    for k, v in kp.items():
        v.pop("desc_base", None)
    # sanity: everything must be unique
    sigs = [json.dumps(s["fx"], sort_keys=True) for s in skills.values()]
    assert len(sigs) == len(set(sigs)) == 56, "skills not unique"
    save("data/champions.json", ch); save("data/king_buffs.json", kb); save("data/king_passives.json", kp); save("data/monsters.json", mons)
    save("data/skills.json", {"_doc": "Composed active skills of the 28 Kings and 28 Monsters: each has its own list of effect ops (BattleEngine.SKILL_OPS / _run_skill_fx). Generated by tools/gen_kit.py.", "skills": skills})
    print("ok:", len(skills), "skills")
main()
