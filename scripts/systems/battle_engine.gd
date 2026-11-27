class_name BattleEngine
extends RefCounted
## Deterministic auto-battle on the 8x8 grid. One step() = one tick (0.25 s at 1x speed).
## Side 0 starts on rows 4-7, side 1 on rows 0-3. No manual unit control.
##
## Unit behaviour: target priority by role, attack range (Chebyshev distance), movement
## (BFS, up to `move` cells per tick), skills, faction + role synergy special effects, Support cards.
## The Champion (King) enters when every regular unit of its side has fallen (Last Stand), or earlier if the side pays `king_summon_energy`,
## casting its active skill on entry. A side loses when its Champion falls.

const COLS := 8
const ROWS := 8
const ATTACK_INTERVAL := 2
const MAX_TICKS := 400
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
## Support effects the engine can apply today. Others are TODO.
const IMPLEMENTED_SUPPORTS: Array[String] = [
	"area_damage", "heal_all", "team_atk", "shield_all", "summon_pawns", "gold_on_win",
	"summon_familiar", "create_wall", "promote_pawn", "polymorph_enemy", "ascend_unit", "freeze_area",
	"buff_atk", "buff_hp", "buff_move", "team_speed", "instant_skill", "revive_once", "lifesteal_pact",
	"temp_capacity", "free_reroll"]
## Support effects that act during preparation (see BattlePrep.apply_hand); marked as used at setup.
const PREP_SUPPORTS: Array[String] = ["temp_capacity", "free_reroll"]
var rng := RandomNumberGenerator.new()
var tick: int = 0
var units: Array[BattleUnit] = []
var grid: Dictionary = {}  # Vector2i -> BattleUnit
var kings: Array = [null, null]
var king_data: Array = ["", ""]
var king_star: Array = [1, 1]  # Commander stars of each side (multiply the King's HP / ATK)
var king_entered: Array = [false, false]
var side_passive: Array = [{}, {}]  # battle passive of each side's King (data/king_passives.json), active from the start on any continent
var king_skill_used: Array = [false, false]
var king_skill_locked: Array = [false, false]  # true = that side's King active skill is still locked (the human's King below B2)
var manual_king: Array = [false, false]  # true = that side's King skill is cast by hand (human); false = on entry (AI / tests)
var king_entry_tick: Array = [-1, -1]
var monster_unit: Array = [null, null]  # the allied Monster unit on the field (set when it joins the King)
var monster_skill_used: Array = [false, false]  # Monster card active skill, cast once per battle like the King skill (manual_king decides hand / auto)
var monster_star: Array = [1, 1]  # King level the Monster card was won at: its ally stats use those Commander star multipliers
var monster_card: Array = ["", ""]  # Monster card of each side: that monster joins the King when he enters Last Stand
var regulars_alive_at_entry: Array = [-1, -1]  # test hook: must always be 0
var hands: Array = [[], []]
var used_supports: Array = [[], []]
var kills: Array = [0, 0]  # regular units destroyed BY each side (Battle Chess Continent Mission)
## Support energy: fills by 1 every `energy_regen_ticks` ticks up to `energy_max` (overflow is wasted), each Support card costs energy by rarity.
var energy: Array = [0, 0]
var energy_timer: Array = [0, 0]
var free_supports: bool = false  # test hook: Support cards cost no energy
## Support combo: playing the same category again within `combo_window_ticks` of the last card extends the chain;
## chain length n refunds min(n-1, combo_refund_max) energy on that card. A different category or a late card restarts at 1.
var combo_category: Array = ["", ""]
var combo_count: Array = [0, 0]
var combo_last_tick: Array = [-9999, -9999]
var ai_supports: Array = [false, true]
var bonus_gold: Array = [0, 0]
var gold_delta: Array = [0, 0]  # gold gained/lost by Support cards (e.g. Blood Oath), applied after the duel
var terrain: Dictionary = {}  # Vector2i -> true: highland cells (see Terrain); empty = all plains
var walls: Dictionary = {}  # Vector2i -> tick when the wall expires (Forge Bastion)
var revive_pending: Array = [false, false]  # Guardian Angel family: number of revives left (bool-compatible)
var revive_hp_pct: Array = [50, 50]
var lifesteal: Array = [0.0, 0.0]
var haste_until: Array = [0, 0]
## "Check": a Champion in the arena that an enemy can hit is in check. The first check of a battle gives it a one-time shield
## (balance key check_shield_pct, share of max HP) so the side that is down still has a chance to turn it around.
var in_check: Array = [false, false]
var check_shield_used: Array = [false, false]
var last_piece_warned: Array = [false, false]
var finished: bool = false
var winner: int = -1  # 0, 1, or -1 = draw
var end_reason: String = ""
var events: Array = []  # visual events of the last tick
var log_lines: Array[String] = []
var _uid: int = 0
var _reflecting: bool = false  # guards Thorns against endless reflection
const BUFF_INTERVAL := 8


# ------------------------------------------------------------------ setup

## cfg = {"seed": int, "sides": [side_cfg, side_cfg], "ai_supports": [bool, bool]}
## side_cfg = {"units": [{card_id, stars, cell: Vector2i}], "champion": id, "supports": [ids]}
func setup(cfg: Dictionary) -> void:
	rng.seed = int(cfg.get("seed", 1))
	ai_supports = cfg.get("ai_supports", [false, true])
	manual_king = cfg.get("manual_king", [false, false])
	king_skill_locked = (cfg.get("king_skill_locked", [false, false]) as Array).duplicate()
	free_supports = bool(cfg.get("free_supports", false))
	terrain = cfg.get("terrain", {})
	energy = [mini(int(GameData.b("energy_start", 2)), energy_max()), mini(int(GameData.b("energy_start", 2)), energy_max())]
	for side in range(2):
		var sc: Dictionary = cfg["sides"][side]
		king_data[side] = String(sc.get("champion", ""))
		king_star[side] = clampi(int(sc.get("champion_star", 1)), 1, CommanderSystem.max_star())
		monster_card[side] = String(sc.get("monster", ""))
		monster_star[side] = clampi(int(sc.get("monster_star", 1)), 1, CommanderSystem.max_star())
		side_passive[side] = GameData.king_passives.get(king_data[side], {})
		hands[side] = (sc.get("supports", []) as Array).duplicate()
		for sid in hands[side]:
			if PREP_SUPPORTS.has(String(CardDatabase.get_support(String(sid)).get("effect", ""))):
				(used_supports[side] as Array).append(sid)  # already applied in preparation
		var side_fac := _side_faction(side)
		var synergy_counts := {}
		var synergy := _synergy(sc["units"], side_fac, synergy_counts)
		var ultra_fac := _ultra_faction(sc["units"], side_fac)
		for fac in synergy_counts:  # Faction Tier: banner bonus + faction trait in ONE log line per faction
			var ftier := ComboSystem.faction_tier(String(fac), int(synergy_counts[fac]), String(fac) == ultra_fac)
			if not ftier.is_empty():
				_log("Side %d Faction Tier: %s%s x%d (%s)" % [side, String(fac).capitalize(), " ULTRA" if bool(ftier["ultra"]) else "", int(ftier["count"]), ComboSystem.faction_tier_text(ftier)])
		var fac_army := _army_active(sc["units"], side_fac)  # Grand Army (Faction): the King's continent OR the played one, so a foreign King can have it too
		if fac_army:
			_log("Side %d synergy: %s (%s)" % [side, ComboSystem.FACTION_ARMY["name"], ComboSystem.effects_text(ComboSystem.FACTION_ARMY["effects"])])
		# Continent Alliance: a faction group of 2 units in EVERY continent gives every unit the bond effect of the continent of its King
		var bond := ComboSystem.bonds_for(_continent_best_faction(sc["units"], side_fac), GameData.continent_of_faction(side_fac) if side_fac != "" else "")
		if not bond.is_empty():
			_log("Side %d synergy: Continent Alliance - %s (%s)" % [side, ", ".join(PackedStringArray(bond["names"])), ComboSystem.effects_text(bond["effects"])])
		# Continent Specialties: 6 units of one faction of a continent + 6 units of its role (Arcanum faction + 6 Mages, ...) give the units of that role a special effect
		var cr_combos := ComboSystem.continent_role_active(_continent_role_counts(sc["units"], side_fac))
		for cc in cr_combos:
			_log("Side %d synergy: %s - %s %ss (%s)" % [side, cc["name"], String(cc["continent"]).capitalize(), cc["role"], ComboSystem.effects_text(cc["effects"])])
		# Continent Formation: 4 units of ONE faction of the King's continent give the units of that faction the effect of that continent
		var fac_all := _faction_unit_counts(sc["units"], side_fac)
		var king_cont := GameData.continent_of_faction(side_fac) if side_fac != "" else ""
		for fm in ComboSystem.formation_active(fac_all, king_cont):
			_log("Side %d synergy: %s - %s x%d (%s)" % [side, fm["name"], String(fm["faction"]).capitalize(), int(fm["count"]), ComboSystem.effects_text(fm["effects"])])
		var roles := role_counts(sc["units"])
		for a in ComboSystem.active(roles):
			_log("Side %d synergy: %s%s (%s)" % [side, a["name"], ((" x%d" % int(a["count"])) if String(a["kind"]) == "role" else "") + (" ULTRA" if bool(a.get("ultra", false)) else ""), ComboSystem.effects_text(a["effects"])])
		for e in sc["units"]:
			var fac := CardDatabase.effective_faction(CardDatabase.get_unit(e["card_id"]), side_fac)
			var role := String(CardDatabase.get_unit(e["card_id"]).get("role", ""))
			_spawn_unit(side, e["card_id"], int(e["stars"]), e["cell"], float(synergy.get(fac, 0.0)), ComboSystem.unit_mods(role, roles, String(fac), int(synergy_counts.get(fac, 0)), String(fac) == ultra_fac, fac_army, bond, cr_combos, GameData.continent_of_faction(String(fac)), ComboSystem.formation_effects_for(String(fac), int(fac_all.get(fac, 0)), king_cont)))
	for side in range(2):  # wild monsters ("foes"): they are the regular units of a side that has no King (monster hunt)
		var foes: Array = cfg["sides"][side].get("foes", [])
		for i in range(foes.size()):
			var fc := MonsterSystem.FOE_CELL + Vector2i(i, 0)
			if side == 0:
				fc = Vector2i(fc.x, 7 - fc.y)
			_spawn_monster(side, String(foes[i]), fc, clampi(int(cfg["sides"][side].get("foe_star", 1)), 1, CommanderSystem.max_star()))
	for u in units:  # Queen of Machina: the side starts with shields
		if u.extra == "opening_shield":
			for a in units_of(u.side):
				a.shield += int(round(a.max_hp * u.extra_value))
	_log("Battle begins!")
	_check_king_entries()


## Number of regular units per role in a side's unit list.
static func role_counts(list: Array) -> Dictionary:
	var counts := {}
	for e in list:
		var r := String(CardDatabase.get_unit(e["card_id"]).get("role", ""))
		if r != "":
			counts[r] = int(counts.get(r, 0)) + 1
	return counts


## The faction a side fights for = the faction of its Champion.
func _side_faction(side: int) -> String:
	return String(GameData.get_champion(String(king_data[side])).get("faction", ""))


## The continent Grand Army (Faction) is judged against: the continent of the side's King (the played continent when it has no King).
static func _army_continent(side_fac: String) -> String:
	var cid := GameData.continent_of_faction(side_fac) if side_fac != "" else ""
	return cid if cid != "" else CardDatabase.active_continent


## Faction ids of the King's continent (Grand Army (Faction) needs units of EVERY one of them).
func _continent_faction_ids(side_fac: String = "", cont: String = "") -> Array:
	var out: Array = []
	var army_cont := cont if cont != "" else _army_continent(side_fac)
	for c in GameData.continents:
		if String(c.get("id", "")) == army_cont:
			for f in c.get("factions", []):
				out.append(String(f["id"]))
	return out


## Home-continent rule: card buffs (and Faction Tier) apply only if the side's faction belongs to the continent
## being played. A side without a Champion keeps them (no faction to be foreign).
func _home_bonus(side: int) -> bool:
	var fac := _side_faction(side)
	return fac == "" or GameData.is_home_faction(fac, CardDatabase.active_continent)


## Does a unit of faction `fac` count for the Faction Tier? Only when it is the SAME faction as the side's King (units of other factions get
## no Faction Tier), wherever it plays: a foreign faction is active together with its King (its shared pieces count for it).
static func _faction_counts(fac: String, side_fac: String) -> bool:
	return fac != "" and fac == side_fac


## Per continent the units of its best-staffed faction on the side (a Pawn / shared piece counts for the King's faction): what the Continent Alliance needs
## (2 units of one faction in EVERY continent). Units without a faction count for nobody.
func _continent_best_faction(list: Array, side_fac: String = "") -> Dictionary:
	var per_fac := {}
	for e in list:
		var fac := CardDatabase.effective_faction(CardDatabase.get_unit(e["card_id"]), side_fac)
		if fac != "":
			per_fac[fac] = int(per_fac.get(fac, 0)) + 1
	var best := {}
	for fac in per_fac:
		var cid := GameData.continent_of_faction(String(fac))
		if cid != "":
			best[cid] = maxi(int(best.get(cid, 0)), int(per_fac[fac]))
	return best


## Per continent-role pairing of a Continent Specialty ({"arcanum|Mage": {"faction": 6, "role": 6}, ...}, keys from ComboSystem.continent_role_key): what the combos need.
## "faction" = units of the best-staffed faction of that continent, "role" = units of that role (any faction). A Pawn / shared piece counts for the King's faction (like the Continent Alliance).
func _continent_role_counts(list: Array, side_fac: String = "") -> Dictionary:
	var best := _continent_best_faction(list, side_fac)
	var roles := role_counts(list)
	var counts := {}
	for c in ComboSystem.CONTINENT_ROLE_COMBOS:
		counts[ComboSystem.continent_role_key(String(c["continent"]), String(c["role"]))] = {"faction": int(best.get(String(c["continent"]), 0)), "role": int(roles.get(String(c["role"]), 0))}
	return counts


## Units per faction on the field, ANY faction (shared pieces and slot Pawns count for the King's faction): the count the Continent Formation needs (it then keeps the King's continent only).
func _faction_unit_counts(list: Array, side_fac: String = "") -> Dictionary:
	var counts := {}
	for e in list:
		var fac := CardDatabase.effective_faction(CardDatabase.get_unit(e["card_id"]), side_fac)
		if fac != "":
			counts[fac] = int(counts.get(fac, 0)) + 1
	return counts


## Grand Army (Faction): every faction of the King's continent OR of the continent being played fields 2+ units (a foreign King qualifies through the played continent).
func _army_active(list: Array, side_fac: String) -> bool:
	for cont in [_army_continent(side_fac), CardDatabase.active_continent]:
		if ComboSystem.faction_army_active(_continent_counts(list, side_fac, String(cont)), _continent_faction_ids(side_fac, String(cont))):
			return true
	return false


## Units per faction of the King's continent (any faction of it, the King's or not; shared pieces count for the King's faction): the count Grand Army (Faction) needs.
func _continent_counts(list: Array, side_fac: String = "", cont: String = "") -> Dictionary:
	var counts := {}
	var army_cont := cont if cont != "" else _army_continent(side_fac)
	for e in list:
		var fac := CardDatabase.effective_faction(CardDatabase.get_unit(e["card_id"]), side_fac)
		if fac != "" and GameData.is_home_faction(fac, army_cont):
			counts[fac] = int(counts.get(fac, 0)) + 1
	return counts


## Faction Tier, banner part (Faction Tier): tiers at 2 / 4 / 6 units; the flat HP/ATK banner bonus is 0 now, so this only returns counts (ComboSystem).
## Shared pieces (Rook, Knight, Bishop, Queen) count for the side's own faction; a side without a Champion has none.
func _synergy(list: Array, side_fac: String = "", out_counts: Dictionary = {}) -> Dictionary:
	var counts := {}
	for e in list:
		var fac := CardDatabase.effective_faction(CardDatabase.get_unit(e["card_id"]), side_fac)
		if not _faction_counts(fac, side_fac):
			continue
		counts[fac] = int(counts.get(fac, 0)) + 1
	var out := {}
	var ultra := _ultra_faction(list, side_fac)
	for fac in counts:
		var n: int = counts[fac]
		out_counts[fac] = n
		var bonus := ComboSystem.faction_bonus(n, String(fac) == ultra)
		if bonus > 0.0:
			out[fac] = bonus
	return out


## ULTRA Faction Tier: the faction when EVERY unit of the list is the King's own faction (8+ units), otherwise "" (ComboSystem.faction_ultra).
func _ultra_faction(list: Array, side_fac: String = "") -> String:
	var facs: Array = []
	for e in list:
		var fac := CardDatabase.effective_faction(CardDatabase.get_unit(e["card_id"]), side_fac)
		facs.append(fac if _faction_counts(fac, side_fac) else "")
	return ComboSystem.faction_ultra(facs)


## `mods` = ComboSystem.unit_mods of the unit: {"hp", "atk", "move", "shield", "range", "fx"}; the synergies only fill "fx" (special effects, see ComboSystem.FX_TYPES).
func _spawn_unit(side: int, card_id: String, stars: int, cell: Vector2i, bonus: float, mods: Dictionary = {}) -> BattleUnit:
	var role_hp := float(mods.get("hp", 0.0))
	var role_atk := float(mods.get("atk", 0.0))
	var card := CardDatabase.get_unit(card_id)
	var st := CardDatabase.unit_stats(card_id, stars)
	var u := BattleUnit.new()
	_uid += 1
	u.uid = _uid
	u.side = side
	u.card_id = card_id
	u.display_name = card["name"]
	u.chess = card["chess"]
	u.role = card["role"]
	u.faction = CardDatabase.effective_faction(card, _side_faction(side))
	u.stars = stars
	var sp_hp := _sp(side, "team_hp")
	var sp_atk := _sp(side, "team_atk")
	u.max_hp = int(round(float(st["hp"]) * (1.0 + bonus) * (1.0 + role_hp) * (1.0 + sp_hp)))
	u.hp = u.max_hp
	if _sp(side, "team_shield") > 0.0:
		u.shield += int(round(u.max_hp * _sp(side, "team_shield")))
	u.base_atk = int(round(float(st["atk"]) * (1.0 + bonus) * (1.0 + role_atk) * (1.0 + sp_atk) * WorldMods.atk_mult))
	u.atk_range = int(card["range"]) + int(mods.get("range", 0))
	u.move = int(card["move"]) + int(mods.get("move", 0))
	if float(mods.get("shield", 0.0)) > 0.0:
		u.shield += int(round(u.max_hp * float(mods["shield"])))  # combo / faction-trait opening shield (Frontline Shield, Guardian Aura, Arcane Ward, Dawn Ward, ...)
	u.skill_id = CardDatabase.skill_mechanic(card)  # themed continent skills map to a base mechanic
	u.cell = cell
	u.params = card["skill"].get("params", {})  # per-continent numbers of the skill (defaults = the Aetherion values)
	var bf := CardDatabase.get_buff(card_id)  # the card's buff of its continent (data/card_buffs.json)
	if not _home_bonus(side) or (String(card.get("continent", "")) != "" and String(card.get("continent", "")) != CardDatabase.active_continent):
		bf = {}  # a foreign faction (or a piece of another continent) fights without the continent card buffs of this map
	u.extra = String(bf.get("type", ""))
	u.extra_value = float(bf.get("value", 0.0))
	u.fx = (mods.get("fx", {}) as Dictionary).duplicate()  # special effects of the synergies (ComboSystem.unit_mods)
	u.next_skill_tick = _skill_interval(u)
	_init_buff(u)
	units.append(u)
	grid[cell] = u
	return u


## A monster of data/monsters.json as a battle unit at King level `star` (wild: the challenger's level, ally: the level it was won at); an ally = a tamed Monster card (stats = wild stats x the King level multipliers of `star`, see MonsterSystem.stats).
func _spawn_monster(side: int, monster_id: String, cell: Vector2i, star: int = 1) -> BattleUnit:
	var m := GameData.get_monster(monster_id)
	if m.is_empty():
		return null
	var st := MonsterSystem.stats(monster_id, star)
	var u := BattleUnit.new()
	_uid += 1
	u.uid = _uid
	u.side = side
	u.card_id = monster_id
	u.is_monster = true
	u.display_name = String(m["name"])
	u.chess = String(m.get("chess", "knight"))
	u.role = "Fighter"
	u.faction = ""
	u.stars = clampi(star, 1, CommanderSystem.max_star())  # the King level it fights at, shown like a unit's stars
	u.max_hp = int(st["hp"])
	u.hp = u.max_hp
	u.base_atk = int(round(float(st["atk"]) * WorldMods.atk_mult))
	u.atk_range = int(m.get("range", 1))
	u.move = int(m.get("move", 1))
	u.cell = cell
	var bf: Dictionary = m.get("buff", {})
	u.extra = String(bf.get("type", ""))
	u.extra_value = float(bf.get("value", 0.0))
	u.active_id = String(m.get("skill_id", ""))
	u.active_value = float(m.get("active_value", 0.0))
	var plus: Dictionary = m.get("plus", {})  # the "King+" trait: a second buff on top of the monster's own
	if not plus.is_empty():
		u.fx[String(plus.get("type", ""))] = float(plus.get("value", 0.0))
	_init_buff(u)
	if u.buff_next_tick != 0:
		u.buff_next_tick = tick + BUFF_INTERVAL
	units.append(u)
	grid[cell] = u
	_rally_cry(u)
	return u


## Strength of a King battle passive of `side` (data/king_passives.json: `type` / `value`, plus an optional second pair `type2` / `value2`); 0 = none.
func _sp(side: int, type: String) -> float:
	var kp: Dictionary = side_passive[side]
	var v := 0.0
	if String(kp.get("type", "")) == type:
		v += float(kp.get("value", 0.0))
	if String(kp.get("type2", "")) == type:
		v += float(kp.get("value2", 0.0))
	return v


## A numeric skill parameter of a unit (data: skill.params), falling back to the base value.
func _p(u: BattleUnit, key: String, default: Variant) -> Variant:
	return u.params.get(key, default)


## Strength of a special effect on a unit: its card buff (`extra`) and the synergy effects (`fx`) combined. 0 = the unit has none.
## Counts (evade, stun_proc) take the lowest N, chill the longest, second_life the biggest share, everything else adds up.
func _x(u: BattleUnit, type: String) -> float:
	var a := u.extra_value if u.extra == type else 0.0
	var b := float(u.fx.get(type, 0.0))
	if a == 0.0 or b == 0.0:
		return maxf(a, b)
	if ComboSystem.FX_COUNT.has(type):
		return minf(a, b)
	if ComboSystem.FX_TICKS.has(type) or type == "second_life":
		return maxf(a, b)
	return a + b


## Buff effects that change the unit when it is created.
func _init_buff(u: BattleUnit) -> void:
	if u.extra == "swift":
		u.move += int(u.extra_value)
	if u.extra == "ward":
		u.shield += int(round(u.max_hp * u.extra_value))
	if _x(u, "opener") > 0.0:
		u.strike_bonus = _x(u, "opener")
	if u.extra == "regen" or _x(u, "mend_self") > 0.0:
		u.buff_next_tick = BUFF_INTERVAL


## Periodic buff effects (their own timer, independent of the unit's skill).
func _buff_periodic(u: BattleUnit) -> void:
	if u.buff_next_tick == 0 or tick < u.buff_next_tick:
		return
	u.buff_next_tick = tick + BUFF_INTERVAL
	if u.extra == "regen":
		for a in units_of(u.side):
			_heal(a, int(round(a.max_hp * u.extra_value)))
	if _x(u, "mend_self") > 0.0:
		_heal(u, int(round(u.max_hp * _x(u, "mend_self"))))


func _skill_interval(u: BattleUnit) -> int:
	match u.skill_id:
		"rally_banner": return 8
		"blessed_mend": return int(_p(u, "interval", 10))
		"ballista_volley": return int(_p(u, "interval", 12))
		"dominion_bind": return int(_p(u, "interval", 12))
	return 0


# ------------------------------------------------------------------ queries

func units_of(side: int, include_dead: bool = false) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in units:
		if u.side == side and (u.alive or include_dead):
			out.append(u)
	return out


func regulars_alive(side: int) -> int:
	var n := 0
	for u in units:
		if u.side == side and u.alive and not u.is_king:
			n += 1
	return n


func total_hp(side: int) -> int:
	var n := 0
	for u in units:
		if u.side == side and u.alive:
			n += u.hp
	return n


func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _blocked(c: Vector2i) -> bool:
	return grid.has(c) or walls.has(c)


## Real-chess attack: can unit `u`, standing on `from`, hit the cell `to`? Slides are stopped by units and walls (its own start cell counts as free).
func _can_hit(u: BattleUnit, from: Vector2i, to: Vector2i) -> bool:
	var start := u.cell
	var blk := func(c: Vector2i) -> bool: return c != start and (grid.has(c) or walls.has(c))
	return ChessMove.can_capture(u.chess, from, to, u.side, blk)


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func atk_now(u: BattleUnit) -> int:
	var m := 1.0
	if terrain.has(u.cell) and Terrain.is_ranged(u.atk_range):
		m *= 1.0 + float(GameData.b("highland_atk_bonus", 0.15))  # ranged unit on a highland
	if u.buff_until > tick:
		m *= u.buff_mult
	if u.brace_active:
		m *= 1.3
	if u.hp * 2 < u.max_hp and _x(u, "rage") > 0.0:
		m *= 1.0 + _x(u, "rage")
	if _x(u, "frenzy") > 0.0:
		m *= 1.0 + _x(u, "frenzy") * mini(u.kills, 5)
	if _x(u, "momentum") > 0.0:
		m *= 1.0 + _x(u, "momentum") * mini(u.attacks_made, 8)  # Momentum: every attack adds ATK (max 8 stacks)
	var aura := 0.0
	for a in units:
		if a != u and a.side == u.side and a.alive and _dist(a.cell, u.cell) <= 1 and _x(a, "aura_atk") > 0.0:
			aura = maxf(aura, _x(a, "aura_atk"))
	m *= 1.0 + aura
	return int(round(float(u.base_atk) * m))


func _free_cell_near(c: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999
	for y in range(ROWS):
		for x in range(COLS):
			var p := Vector2i(x, y)
			if _blocked(p) or terrain.has(p):  # summons / entering Champions are melee: plains only
				continue
			var d := _dist(p, c) * 10 + absi(p.x - c.x) + absi(p.y - c.y)
			if d < best_d:
				best_d = d
				best = p
	return best


func _free_adjacent(c: Vector2i, prefer: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999
	for d in DIRS:
		var p := c + d
		if _in_bounds(p) and not _blocked(p) and not terrain.has(p):  # teleports land on plains only
			var dd := _dist(p, prefer)
			if dd < best_d:
				best_d = dd
				best = p
	return best


# ------------------------------------------------------------------ tick

func step() -> void:
	if finished:
		return
	tick += 1
	events.clear()
	_regen_energy()
	for wc in walls.keys():
		if int(walls[wc]) <= tick:
			walls.erase(wc)
	if tick % 4 == 0:  # burning units take damage over time
		for u in units:
			if u.alive and u.burn_until > tick:
				_damage(u, u.burn_amount)
	var order: Array[BattleUnit] = []
	for u in units:
		if u.alive:
			order.append(u)
	for u in order:
		if u.alive:
			_act(u)
	for side in range(2):
		_auto_king_skill(side)
		_auto_monster_skill(side)
	_auto_wild_skills()
	if ai_supports[0] or ai_supports[1]:
		_ai_use_supports()
	_check_king_entries()
	_update_check()
	_check_end()
	if not finished and tick >= MAX_TICKS:
		var a := total_hp(0)
		var b := total_hp(1)
		if a == b:
			_finish(-1, "Time limit: equal HP")
		else:
			_finish(0 if a > b else 1, "Time limit: more total HP")


func _act(u: BattleUnit) -> void:
	if u.stun_until > tick:
		return
	if u.slow_until > tick and tick % 2 == 1:
		return
	_periodic_skill(u)
	_buff_periodic(u)
	if not u.opened:
		u.opened = true
		if _opening_skill(u):
			return
	var target := _pick_target(u)
	if target == null:
		return
	if _can_hit(u, u.cell, target.cell):
		if tick >= u.next_attack_tick:
			_attack(u, target)
			u.next_attack_tick = tick if u.refresh_attack else tick + _attack_interval(u)
			u.refresh_attack = false
	else:
		_move_toward(u, target)


func _pick_target(u: BattleUnit) -> BattleUnit:
	if u.taunt_until > tick:
		for e in units:
			if e.uid == u.taunt_uid and e.alive:
				return e
	var enemies := units_of(1 - u.side)
	if enemies.is_empty():
		return null
	var best: BattleUnit = null
	var best_key := 1.0e9
	for e in enemies:
		var d := float(_dist(u.cell, e.cell))
		var key := d * 1000.0 + float(e.uid)  # nearest, ties by uid
		match u.role:
			"Assassin":
				key = float(e.hp) * 10.0 + d  # weakest first
			"Marksman", "Mage":
				if _can_hit(u, u.cell, e.cell):
					key = float(e.hp) + d  # weakest enemy already in range
				else:
					key = 100000.0 + d * 1000.0 + float(e.uid)
		if key < best_key:
			best_key = key
			best = e
	return best


func _move_toward(u: BattleUnit, target: BattleUnit) -> void:
	# Chess movement (see ChessMove): breadth-first search over whole moves (a rook slide, a knight jump, ...),
	# so the unit takes the first move of the shortest route to any cell from which it can hit the target.
	var start := u.cell
	var rng_u := u.atk_range
	var blocked := func(c: Vector2i) -> bool: return _blocked(c) or not Terrain.can_stand(terrain, rng_u, c)  # highland: ranged only
	var first := {start: start}  # cell -> the first-move destination that leads to it
	var queue: Array[Vector2i] = [start]
	var goal := Vector2i(-1, -1)
	var qi := 0
	while qi < queue.size() and goal.x < 0:
		var c: Vector2i = queue[qi]
		qi += 1
		for n in ChessMove.move_cells(u.chess, c, ChessMove.steps_for(u.chess, u.move, u.moved or c != start), u.side, blocked):
			if first.has(n):
				continue
			first[n] = n if c == start else first[c]
			if _can_hit(u, n, target.cell):
				goal = n
				break
			queue.append(n)
	if goal.x >= 0:
		_move_unit(u, first[goal])
		return
	# No route (walled in): take the legal move that gets closest, if any.
	var best := Vector2i(-1, -1)
	var best_d := _dist(start, target.cell)
	for n in ChessMove.move_cells(u.chess, start, ChessMove.steps_for(u.chess, u.move, u.moved), u.side, blocked):
		if _dist(n, target.cell) < best_d:
			best_d = _dist(n, target.cell)
			best = n
	if best.x >= 0:
		_move_unit(u, best)


func _move_unit(u: BattleUnit, c: Vector2i) -> void:
	grid.erase(u.cell)
	u.moved = true
	u.cell = c
	grid[c] = u


# ------------------------------------------------------------------ combat

func _attack(u: BattleUnit, t: BattleUnit) -> void:
	var dmg := float(atk_now(u))
	u.attacks_made += 1
	if u.strike_bonus > 0.0:  # Knight (Assassin): the first attack after the teleport hits harder
		dmg *= 1.0 + u.strike_bonus
		u.strike_bonus = 0.0
	if _x(u, "execute") > 0.0 and t.hp * 10 < t.max_hp * 3:
		dmg *= 1.0 + _x(u, "execute")
	if _x(u, "crit") > 0.0 and u.attacks_made % 3 == 0:
		dmg *= 1.0 + _x(u, "crit")  # Crit: every 3rd attack hits harder
	if _x(u, "shatter") > 0.0 and t.shield > 0:
		dmg *= 1.0 + _x(u, "shatter")  # Shatter: bonus damage to shielded targets
	match u.skill_id:
		"radiant_strike":
			if u.attacks_made % 3 == 0:
				dmg *= 1.5
		"backstab":
			if u.attacks_made == 1:
				dmg *= 2.0
		"shadow_arrow":
			dmg *= 1.2
		"moon_chill":
			t.slow_until = tick + 6
	var amount := int(round(dmg))
	var tcell := t.cell
	var dealt := _damage(t, amount)
	if not t.alive:
		u.kills += 1
		if _x(u, "feast") > 0.0:
			_heal(u, int(round(u.max_hp * _x(u, "feast"))))  # Feast: a kill heals
		if _x(u, "quickkill") > 0.0:
			u.refresh_attack = true  # Quick Kill: the next attack comes at once
	events.append({"type": "attack", "from": u.cell, "to": tcell, "dmg": dealt})
	if float(lifesteal[u.side]) > 0.0:
		_heal(u, int(round(dealt * float(lifesteal[u.side]))))
	if u.skill_id == "star_bolt":
		for e in units_of(1 - u.side):
			if e != t and _dist(e.cell, tcell) <= 1:
				_damage(e, int(round(amount * 0.25)))
	elif u.skill_id == "arcane_barrage" and u.attacks_made % int(_p(u, "every", 6)) == 0:
		for e in units_of(1 - u.side):
			if e != t and _dist(e.cell, tcell) <= 2:
				_damage(e, int(round(amount * float(_p(u, "splash_pct", 0.5)))))
		_log("%s unleashes Arcane Barrage!" % u.display_name)
	# Special effects: the continent card buff (Queen etc.) and the synergies (ComboSystem) share one code path via _x()
	if _x(u, "splash") > 0.0:
		for e in units_of(1 - u.side):
			if e != t and _dist(e.cell, tcell) <= 1:
				_damage(e, int(round(amount * _x(u, "splash"))))
	if _x(u, "lifesteal") > 0.0:
		_heal(u, int(round(dealt * _x(u, "lifesteal"))))
	if _x(u, "chill") > 0.0:
		t.slow_until = maxi(t.slow_until, tick + int(_x(u, "chill")))
	if _x(u, "burn") > 0.0 and t.alive:
		var burning := t.burn_until > tick  # a stronger burn replaces a weaker one, never the other way round
		t.burn_until = tick + 12
		t.burn_amount = maxi(t.burn_amount if burning else 0, maxi(1, int(round(u.base_atk * _x(u, "burn")))))
	if _x(u, "weaken") > 0.0 and t.alive:
		t.mark_until = tick + 8  # Weaken: the target takes extra damage from everyone for a while
		t.mark_mult = maxf(t.mark_mult if t.mark_until > tick else 0.0, _x(u, "weaken"))
	if _x(u, "chain") > 0.0:
		var arc: BattleUnit = null  # Chain: the hit arcs to the nearest other enemy within 2 cells
		for e in units_of(1 - u.side):
			if e != t and _dist(e.cell, tcell) <= 2 and (arc == null or _dist(e.cell, tcell) < _dist(arc.cell, tcell)):
				arc = e
		if arc != null:
			_damage(arc, int(round(amount * _x(u, "chain"))))
	if _x(u, "siphon") > 0.0 and u.attacks_made % 3 == 0:
		energy[u.side] = mini(energy_max(), int(energy[u.side]) + int(_x(u, "siphon")))  # Siphon: every 3rd attack feeds the energy bar
	if _x(u, "stun_proc") > 0.0 and t.alive and u.attacks_made % int(_x(u, "stun_proc")) == 0:
		t.stun_until = maxi(t.stun_until, tick + 2)
	if _x(t, "thorns") > 0.0 and t.alive and u.alive and dealt > 0 and not _reflecting:
		_reflecting = true
		_damage(u, maxi(1, int(round(dealt * _x(t, "thorns")))))
		_reflecting = false


## Rally (team_speed): every 3rd attack comes a tick sooner (about +20% attack speed).
func _attack_interval(u: BattleUnit) -> int:
	if int(haste_until[u.side]) > tick and u.attacks_made % 3 == 0:
		return ATTACK_INTERVAL - 1
	return ATTACK_INTERVAL


func _damage(t: BattleUnit, amount: int) -> int:
	if not t.alive:
		return 0
	var evade_n := int(_x(t, "evade"))
	if evade_n > 0 and (t.hits_taken + 1) % evade_n == 0:
		t.hits_taken += 1  # every Nth hit is avoided
		return 0
	var dmg := float(amount)
	if _x(t, "armor") > 0.0:
		dmg *= 1.0 - minf(_x(t, "armor"), float(ComboSystem.FX_CAP["armor"]))
	if t.skill_id == "shield_wall":
		for a in units_of(t.side):
			if a != t and _dist(a.cell, t.cell) <= 1:
				dmg *= 0.8
				break
	var guard := 0.0  # Queen of Aetherion / guard synergies: allies within 2 cells (and the guard herself) take less damage (the best guard counts)
	for a in units:
		if a.side == t.side and a.alive and _dist(a.cell, t.cell) <= 2:
			guard = maxf(guard, _x(a, "guard"))
	if guard > 0.0:
		dmg *= 1.0 - minf(guard, float(ComboSystem.FX_CAP["guard"]))
	if _sp(t.side, "team_armor") > 0.0:
		dmg *= 1.0 - _sp(t.side, "team_armor")  # King passive of the target's side
	if t.mark_until > tick:
		dmg *= 1.0 + t.mark_mult  # Weaken / Mark
	if t.reduce_until > tick:
		dmg *= 0.5
	var d := int(round(dmg))
	if _x(t, "bastion") > 0.0:
		d = mini(d, maxi(1, int(round(t.max_hp * _x(t, "bastion")))))  # Bastion: no single hit takes more than a share of max HP
	if t.shield > 0:
		var absorbed := mini(t.shield, d)
		t.shield -= absorbed
		d -= absorbed
	t.hp -= d
	t.hits_taken += 1
	if t.skill_id == "brace" and t.hits_taken >= 2 and not t.brace_active:
		t.brace_active = true
	if t.hp <= 0:
		_kill(t)
	return d


func _kill(t: BattleUnit) -> void:
	if int(revive_pending[t.side]) > 0 and not t.is_king:
		revive_pending[t.side] = int(revive_pending[t.side]) - 1  # Guardian Angel: the first fallen unit(s) return with a share of HP
		t.hp = maxi(1, int(t.max_hp * float(revive_hp_pct[t.side]) / 100.0))
		t.shield = 0
		events.append({"type": "fx", "cells": [t.cell]})
		_log("%s is revived by a Guardian Angel!" % t.display_name)
		return
	if _x(t, "undying") > 0.0 and not t.undying_used:
		t.undying_used = true  # Undying: one lethal hit is survived at a share of max HP (Kings too)
		t.hp = maxi(1, int(round(t.max_hp * _x(t, "undying"))))
		t.shield = 0
		events.append({"type": "fx", "cells": [t.cell]})
		_log("%s refuses to fall (Undying)!" % t.display_name)
		return
	if _x(t, "second_life") > 0.0 and not t.second_life_used and not t.is_king:
		t.second_life_used = true  # Queen of Eclipsia / second-life synergies: returns once at a share of max HP
		t.hp = maxi(1, int(t.max_hp * _x(t, "second_life")))
		t.shield = 0
		events.append({"type": "fx", "cells": [t.cell]})
		_log("%s returns for a second life!" % t.display_name)
		return
	t.hp = 0
	t.alive = false
	if not t.is_king:
		kills[1 - t.side] = int(kills[1 - t.side]) + 1
	grid.erase(t.cell)
	events.append({"type": "death", "cell": t.cell})
	_log("%s (side %d) falls." % [t.display_name, t.side])
	for a in units_of(t.side):  # Vengeance: the fall of an ally fires up the avengers
		if a != t and _x(a, "vengeance") > 0.0:
			a.buff_mult = maxf(a.buff_mult if a.buff_until > tick else 1.0, 1.0 + _x(a, "vengeance"))
			a.buff_until = tick + 8
	if _x(t, "last_rites") > 0.0:
		for a in units_of(t.side):
			if _dist(a.cell, t.cell) <= 1:
				_heal(a, int(round(a.max_hp * _x(t, "last_rites"))))
	if _x(t, "death_burst") > 0.0:
		for e in units_of(1 - t.side):
			if _dist(e.cell, t.cell) <= 1:
				_damage(e, int(round(t.base_atk * _x(t, "death_burst"))))


func _heal(t: BattleUnit, amount: int) -> void:
	if t.alive:
		t.hp = mini(t.max_hp, t.hp + amount)


func _periodic_skill(u: BattleUnit) -> void:
	if u.next_skill_tick == 0 or tick < u.next_skill_tick:
		return
	u.next_skill_tick = tick + _skill_interval(u)
	match u.skill_id:
		"rally_banner":
			var low: BattleUnit = null
			for a in units_of(u.side):
				if a.hp < a.max_hp and (low == null or float(a.hp) / a.max_hp < float(low.hp) / low.max_hp):
					low = a
			if low != null:
				_heal(low, 15)
		"blessed_mend":
			for a in units_of(u.side):
				_heal(a, int(round(a.max_hp * float(_p(u, "heal_pct", 0.1)))))
		"ballista_volley":
			var list := units_of(1 - u.side)
			list.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return _dist(u.cell, a.cell) < _dist(u.cell, b.cell))
			for i in range(mini(int(_p(u, "targets", 3)), list.size())):
				var dealt := _damage(list[i], atk_now(u))
				events.append({"type": "attack", "from": u.cell, "to": list[i].cell, "dmg": dealt})
		"dominion_bind":
			# Controller: crowd control. Stuns the highest-ATK enemies (the biggest threats) on the whole field.
			var foes := units_of(1 - u.side)
			foes.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
				var aa := atk_now(a)
				var bb := atk_now(b)
				if aa != bb:
					return aa > bb
				return a.uid < b.uid)
			var bound := 0
			for i in range(mini(int(_p(u, "targets", 2)), foes.size())):
				foes[i].stun_until = maxi(foes[i].stun_until, tick + int(_p(u, "stun_ticks", 2)) + 1)
				bound += 1
			if bound > 0:
				_log("%s binds %d enem%s!" % [u.display_name, bound, "y" if bound == 1 else "ies"])


## Returns true if the opening skill consumed this unit's action.
func _opening_skill(u: BattleUnit) -> bool:
	match u.skill_id:
		"bulwark":
			for e in units_of(1 - u.side):
				if _dist(e.cell, u.cell) <= 1:
					e.taunt_uid = u.uid
					e.taunt_until = tick + int(_p(u, "taunt_ticks", 6))
			return false
		"charge":
			var far := _extreme_enemy(u, true)
			if far != null:
				var c := _free_adjacent(far.cell, u.cell)
				if c.x >= 0:
					_move_unit(u, c)
					far.stun_until = tick + int(_p(u, "stun_ticks", 2)) + 1
					_log("%s charges %s!" % [u.display_name, far.display_name])
					return true
		"night_gallop":
			var weak: BattleUnit = null
			for e in units_of(1 - u.side):
				if weak == null or e.hp < weak.hp:
					weak = e
			if weak != null:
				var c := _free_adjacent(weak.cell, Vector2i(weak.cell.x, 3 if u.side == 0 else 4))
				if c.x >= 0:
					_move_unit(u, c)
					u.strike_bonus = float(_p(u, "strike_bonus", 0.0))
					_log("%s teleports behind %s." % [u.display_name, weak.display_name])
					return true
	return false


func _extreme_enemy(u: BattleUnit, furthest: bool) -> BattleUnit:
	var best: BattleUnit = null
	var best_d := -1 if furthest else 999
	for e in units_of(1 - u.side):
		var d := _dist(u.cell, e.cell)
		if (furthest and d > best_d) or (not furthest and d < best_d):
			best_d = d
			best = e
	return best


# ------------------------------------------------------------------ champion (Last Stand)

func _check_king_entries() -> void:
	for side in range(2):
		if king_entered[side] or king_data[side] == "":
			continue
		if regulars_alive(side) == 0:
			_enter_king(side)


## Living enemies that can hit this side's Champion right now (empty = no check).
func king_threats(side: int) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	var k: BattleUnit = kings[side]
	if k == null or not k.alive:
		return out
	for e in units_of(1 - side):
		if _can_hit(e, e.cell, k.cell):
			out.append(e)
	return out


func _update_check() -> void:
	for side in range(2):
		if king_data[side] == "":
			continue
		if not king_entered[side]:
			# warning: the last regular piece is all that keeps the Champion out of the arena
			if not last_piece_warned[side] and regulars_alive(side) == 1:
				last_piece_warned[side] = true
				events.append({"type": "last_piece", "side": side})
				_log("Last piece! Side %d has one unit left before its Champion must step in." % side)
			continue
		var k: BattleUnit = kings[side]
		var threats := king_threats(side)
		if threats.is_empty():
			in_check[side] = false
			continue
		if not in_check[side]:
			in_check[side] = true
			var cells: Array = []
			for t in threats:
				cells.append(t.cell)
			events.append({"type": "check", "side": side, "cells": cells})
			_log("CHECK! %s (side %d) is under attack." % [k.display_name, side])
			if not check_shield_used[side]:
				check_shield_used[side] = true
				var sh := int(round(k.max_hp * float(GameData.b("check_shield_pct", 0.15))))
				k.shield += sh
				events.append({"type": "fx", "cells": [k.cell]})
				_log("%s braces: +%d shield." % [k.display_name, sh])


func _enter_king(side: int) -> void:
	var ch := GameData.get_champion(king_data[side])
	var u := BattleUnit.new()
	_uid += 1
	u.uid = _uid
	u.side = side
	u.card_id = king_data[side]
	u.is_king = true
	u.stars = clampi(int(king_star[side]), 1, CommanderSystem.max_star())  # Commander stars show on the token like a unit's
	u.display_name = String(ch["name"])
	u.chess = "king"
	u.role = "Fighter"
	u.faction = String(ch["faction"])
	var kp_hp := _sp(side, "king_hp")
	var kp_atk := _sp(side, "king_atk")
	u.max_hp = int(round(float(ch["hp"]) * float(GameData.b("champion_hp_mult")) * (1.0 + kp_hp) * CommanderSystem.hp_mult(int(king_star[side]))))
	u.hp = u.max_hp
	u.base_atk = int(round(float(ch["atk"]) * (1.0 + kp_atk) * WorldMods.atk_mult * CommanderSystem.atk_mult(int(king_star[side]))))
	u.atk_range = 1
	u.move = 2
	u.skill_id = String(ch.get("skill_id", ""))
	u.skill_value = float(ch.get("active_value", 0.0))
	if bool(king_skill_locked[side]):  # B1 King: the active skill is locked until the second copy (B2)
		u.skill_id = ""
		u.skill_value = 0.0
	u.cell = _free_cell_near(Vector2i(3, 7) if side == 0 else Vector2i(4, 0))
	var kb := CardDatabase.king_buff(king_data[side])  # home-continent King buff (data/king_buffs.json)
	u.extra = String(kb.get("type", ""))
	u.extra_value = float(kb.get("value", 0.0))
	_init_buff(u)
	if u.buff_next_tick != 0:
		u.buff_next_tick = tick + BUFF_INTERVAL
	units.append(u)
	grid[u.cell] = u
	_rally_cry(u)
	kings[side] = u
	king_entered[side] = true
	king_entry_tick[side] = tick
	regulars_alive_at_entry[side] = regulars_alive(side)
	if monster_card[side] != "":  # the Monster card answers the King's call and fights beside him
		var mc := _free_cell_near(u.cell)
		if mc.x >= 0:
			var mu := _spawn_monster(side, String(monster_card[side]), mc, int(monster_star[side]))
			if mu != null:
				monster_unit[side] = mu
				events.append({"type": "fx", "cells": [mc]})
				_log("%s joins %s!" % [mu.display_name, u.display_name])
	_log("LAST STAND! %s enters the arena (side %d)." % [u.display_name, side])
	events.append({"type": "last_stand", "side": side})
	events.append({"type": "fx", "cells": [u.cell]})
	if bool(king_skill_locked[side]):
		_log("%s has no active skill yet (unlocks at B2: a second copy of the King card)." % u.display_name)
	elif manual_king[side]:
		_log("%s waits for the King skill (%s)." % [u.display_name, String(ch.get("active_name", "skill"))])
	else:
		_auto_king_skill(side)  # AI / auto sides cast it on entry, or as soon as they can pay for it


## Rally Cry: a King / Monster with the buff inspires every ally when it enters the arena.
func _rally_cry(u: BattleUnit) -> void:
	var v := _x(u, "rally_cry")
	if v <= 0.0:
		return
	for a in units_of(u.side):
		if a != u:
			a.buff_mult = maxf(a.buff_mult if a.buff_until > tick else 1.0, 1.0 + v)
			a.buff_until = tick + 12
	u.buff_mult = maxf(u.buff_mult if u.buff_until > tick else 1.0, 1.0 + v)
	u.buff_until = tick + 12


## Early summon: a side with enough energy may call its King into the arena while regular units are still alive
## (cost `king_summon_energy`). Last Stand stays free: the King still enters by himself once the last regular falls.
func can_summon_king(side: int) -> bool:
	return not finished and king_data[side] != "" and not bool(king_entered[side]) and regulars_alive(side) > 0 \
			and int(energy[side]) >= king_summon_cost()


## Returns "" on success or the reason it failed.
func summon_king(side: int) -> String:
	if finished:
		return "The battle is over."
	if king_data[side] == "":
		return "This side has no King."
	if king_entered[side]:
		return "The King is already in the arena."
	var cost := king_summon_cost()
	if int(energy[side]) < cost:
		return "Not enough energy to summon the King (%d/%d)." % [int(energy[side]), cost]
	energy[side] = int(energy[side]) - cost
	_log("Side %d spends %d energy to summon its King early." % [side, cost])
	_enter_king(side)
	return ""


## Energy needed to summon the King before Last Stand (data/balance.json `king_summon_energy`).
func king_summon_cost() -> int:
	return 0 if free_supports else clampi(int(GameData.b("king_summon_energy", 8)), 0, energy_max())


func _auto_king_skill(side: int) -> void:
	if not _king_waiting(side):
		return
	var cost := king_energy_cost()
	if int(energy[side]) < cost:
		return
	energy[side] = int(energy[side]) - cost
	_cast_king_skill(side)


## King active skill, used once. Human sides cast it by hand (use_king_skill); AI sides cast it on entry.
func _cast_king_skill(side: int) -> void:
	var u: BattleUnit = kings[side]
	king_skill_used[side] = true
	_log("King skill: %s (side %d)." % [String(GameData.get_champion(king_data[side]).get("active_name", u.skill_id)), side])
	_apply_active_skill(u, side, u.skill_id, u.skill_value)


## The effect of an active skill (King skill or Monster skill): `u` is the caster, `skill_id` / `v` its mechanic and strength.
func _apply_active_skill(u: BattleUnit, side: int, skill_id: String, v: float) -> void:
	events.append({"type": "fx", "cells": [u.cell]})
	var def: Dictionary = GameData.skills.get(skill_id, {})
	if not def.is_empty():  # a composed skill (data/skills.json): a list of effect ops
		_run_skill_fx(u, side, def.get("fx", []))
		return
	var foes := units_of(1 - side)
	match skill_id:
		"sun_judgment":  # damage to all enemies
			for e in foes:
				_damage(e, int(round(u.base_atk * v)))
		"starfall_decree":  # 3 random enemies
			var pool := foes.duplicate()
			for i in range(mini(3, pool.size())):
				var e: BattleUnit = pool.pop_at(rng.randi() % pool.size())
				_damage(e, int(round(u.base_atk * v)))
		"eclipse_veil":  # damage reduction + heal
			u.reduce_until = tick + 12
			_heal(u, int(round(u.max_hp * v)))
		"banner_of_iron":  # shield
			u.shield += int(round(u.max_hp * v))
		"inferno_burst":  # enemies within 3 cells
			for e in foes:
				if _dist(e.cell, u.cell) <= 3:
					_damage(e, int(round(u.base_atk * v)))
		"chrono_stasis":  # stun everyone
			for e in foes:
				e.stun_until = tick + int(v) + 1
		"soul_drain":  # hit the toughest enemy and heal
			var tough: BattleUnit = null
			for e in foes:
				if tough == null or e.hp > tough.hp:
					tough = e
			if tough != null:
				_heal(u, _damage(tough, int(round(u.base_atk * v))))
		"frost_veil":  # slow everyone
			for e in foes:
				e.slow_until = tick + int(v)
		"overcharge":  # attack buff
			u.buff_mult = 1.0 + v
			u.buff_until = tick + 12
		"rift_strike":  # teleport to the weakest enemy and hit
			var weak: BattleUnit = null
			for e in foes:
				if weak == null or e.hp < weak.hp:
					weak = e
			if weak != null:
				var c := _free_adjacent(weak.cell, u.cell)
				if c.x >= 0:
					_move_unit(u, c)
				_damage(weak, int(round(u.base_atk * v)))
		"life_surge":  # heal + attack buff
			_heal(u, int(round(u.max_hp * v)))
			u.buff_mult = 1.25
			u.buff_until = tick + 16


## Effect ops that a composed skill (data/skills.json) is made of. Every King and every Monster has its own list, so no two skills are alike.
const SKILL_OPS: Array[String] = [
	"dmg_all", "dmg_rand", "dmg_near", "dmg_tough", "dmg_weak", "dmg_low", "dmg_col", "dmg_row", "dmg_top",
	"stun_all", "stun_near", "stun_top", "slow_all", "slow_near", "burn_all", "mark_all", "drain_energy",
	"shield_self", "shield_team", "heal_self", "heal_team", "heal_low", "reduce_self", "reduce_team",
	"atk_self", "atk_team", "cleanse", "energy", "revive", "haste"]


func _run_skill_fx(u: BattleUnit, side: int, fx: Array) -> void:
	for op in fx:
		var o: Dictionary = op
		var foes := units_of(1 - side)  # re-read for every op: an earlier op may have killed somebody
		var allies := units_of(side)
		var m := float(o.get("m", 1.0))
		var dmg := int(round(u.base_atk * m))
		match String(o.get("op", "")):
			"dmg_all":
				for e in foes:
					_damage(e, dmg)
			"dmg_rand":
				var pool := foes.duplicate()
				for i in range(mini(int(o.get("n", 3)), pool.size())):
					_damage(pool.pop_at(rng.randi() % pool.size()), dmg)
			"dmg_near":
				for e in foes:
					if _dist(e.cell, u.cell) <= int(o.get("r", 3)):
						_damage(e, dmg)
			"dmg_tough":
				var tough: BattleUnit = null
				for e in foes:
					if tough == null or e.hp > tough.hp:
						tough = e
				if tough != null:
					var dealt := _damage(tough, dmg)
					if float(o.get("leech", 0.0)) > 0.0:
						_heal(u, int(round(dealt * float(o["leech"]))))
			"dmg_weak":
				var weak: BattleUnit = null
				for e in foes:
					if weak == null or e.hp < weak.hp:
						weak = e
				if weak != null:
					if bool(o.get("jump", false)):
						var c := _free_adjacent(weak.cell, u.cell)
						if c.x >= 0:
							_move_unit(u, c)
					_damage(weak, dmg)
			"dmg_low":
				for e in foes:
					if float(e.hp) <= float(e.max_hp) * float(o.get("thr", 0.4)):
						_damage(e, dmg)
			"dmg_col":
				for e in foes:
					if e.cell.x == u.cell.x:
						_damage(e, dmg)
			"dmg_row":
				for e in foes:
					if e.cell.y == u.cell.y:
						_damage(e, dmg)
			"dmg_top":  # the n enemies with the highest ATK
				var list := foes.duplicate()
				list.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return a.base_atk > b.base_atk)
				for i in range(mini(int(o.get("n", 2)), list.size())):
					_damage(list[i], dmg)
			"stun_all":
				for e in foes:
					e.stun_until = maxi(e.stun_until, tick + int(o.get("t", 2)) + 1)
			"stun_near":
				for e in foes:
					if _dist(e.cell, u.cell) <= int(o.get("r", 2)):
						e.stun_until = maxi(e.stun_until, tick + int(o.get("t", 2)) + 1)
			"stun_top":
				var list2 := foes.duplicate()
				list2.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return a.base_atk > b.base_atk)
				for i in range(mini(int(o.get("n", 2)), list2.size())):
					list2[i].stun_until = maxi(list2[i].stun_until, tick + int(o.get("t", 2)) + 1)
			"slow_all":
				for e in foes:
					e.slow_until = maxi(e.slow_until, tick + int(o.get("t", 8)))
			"slow_near":
				for e in foes:
					if _dist(e.cell, u.cell) <= int(o.get("r", 3)):
						e.slow_until = maxi(e.slow_until, tick + int(o.get("t", 8)))
			"burn_all":
				for e in foes:
					e.burn_until = tick + int(o.get("t", 12))
					e.burn_amount = maxi(e.burn_amount if e.burn_until > tick else 0, maxi(1, int(round(u.base_atk * float(o.get("p", 0.25))))))
			"mark_all":
				for e in foes:
					e.mark_until = tick + int(o.get("t", 10))
					e.mark_mult = maxf(e.mark_mult if e.mark_until > tick else 0.0, float(o.get("p", 0.15)))
			"drain_energy":
				energy[1 - side] = maxi(0, int(energy[1 - side]) - int(o.get("n", 2)))
			"shield_self":
				u.shield += int(round(u.max_hp * float(o.get("p", 0.3))))
			"shield_team":
				for a in allies:
					a.shield += int(round(a.max_hp * float(o.get("p", 0.1))))
			"heal_self":
				_heal(u, int(round(u.max_hp * float(o.get("p", 0.2)))))
			"heal_team":
				for a in allies:
					_heal(a, int(round(a.max_hp * float(o.get("p", 0.15)))))
			"heal_low":
				var low: BattleUnit = null
				for a in allies:
					if low == null or float(a.hp) / a.max_hp < float(low.hp) / low.max_hp:
						low = a
				if low != null:
					_heal(low, int(round(low.max_hp * float(o.get("p", 0.5)))))
			"reduce_self":
				u.reduce_until = maxi(u.reduce_until, tick + int(o.get("t", 10)))
			"reduce_team":
				for a in allies:
					a.reduce_until = maxi(a.reduce_until, tick + int(o.get("t", 8)))
			"atk_self":
				u.buff_mult = 1.0 + float(o.get("m", 0.3))
				u.buff_until = tick + int(o.get("t", 12))
			"atk_team":
				for a in allies:
					a.buff_mult = maxf(a.buff_mult if a.buff_until > tick else 1.0, 1.0 + float(o.get("m", 0.2)))
					a.buff_until = tick + int(o.get("t", 10))
			"cleanse":
				for a in allies:
					a.stun_until = 0
					a.slow_until = 0
					a.burn_until = 0
			"energy":
				energy[side] = mini(energy_max(), int(energy[side]) + int(o.get("n", 2)))
			"revive":  # the last fallen regular comes back at a share of its HP
				var fallen: BattleUnit = null
				for d in units:
					if d.side == side and not d.alive and not d.is_king and not d.is_monster:
						fallen = d
				if fallen != null:
					var cell := _free_cell_near(u.cell)
					if cell.x >= 0:
						fallen.alive = true
						fallen.hp = maxi(1, int(round(fallen.max_hp * float(o.get("p", 0.4)))))
						fallen.shield = 0
						fallen.cell = cell
						grid[cell] = fallen
						kills[1 - side] = maxi(0, int(kills[1 - side]) - 1)
						events.append({"type": "fx", "cells": [cell]})
						_log("%s is called back from the dead!" % fallen.display_name)
			"haste":
				haste_until[side] = tick + int(o.get("t", 10))


## True while the side's King is in the arena and its active skill is still unused.
func can_use_king_skill(side: int) -> bool:
	return not bool(king_skill_locked[side]) and not finished and bool(king_entered[side]) and not bool(king_skill_used[side]) and (kings[side] as BattleUnit).alive \
			and int(energy[side]) >= king_energy_cost()


## Manual King skill. Returns "" on success or the reason it failed.
func use_king_skill(side: int) -> String:
	if finished:
		return "The battle is over."
	if bool(king_skill_locked[side]):
		return "King skill locked: get a second copy of this King card (B2)."
	if not king_entered[side]:
		return "The King enters only in Last Stand."
	if king_skill_used[side]:
		return "The King skill was already used."
	if not (kings[side] as BattleUnit).alive:
		return "The King has fallen."
	var cost := king_energy_cost()
	if int(energy[side]) < cost:
		return "Not enough energy for the King skill (%d/%d)." % [int(energy[side]), cost]
	energy[side] = int(energy[side]) - cost
	_cast_king_skill(side)
	return ""


## Energy the Monster card's active skill costs (data/balance.json `monster_skill_energy`).
func monster_energy_cost() -> int:
	return 0 if free_supports else clampi(int(GameData.b("monster_skill_energy", 5)), 0, energy_max())


## The allied Monster of a side if it is in the arena and alive, else null.
func ally_monster(side: int) -> BattleUnit:
	var mu: BattleUnit = monster_unit[side]
	if mu != null and mu.alive:
		return mu
	return null


## True while the side's Monster card is in the arena, alive, and its active skill is still unused.
func can_use_monster_skill(side: int) -> bool:
	var mu := ally_monster(side)
	return not finished and mu != null and mu.active_id != "" and not bool(monster_skill_used[side]) \
			and int(energy[side]) >= monster_energy_cost()


## Manual Monster skill (same rules as the King skill: once, costs energy). Returns "" on success or the reason it failed.
func use_monster_skill(side: int) -> String:
	if finished:
		return "The battle is over."
	if monster_unit[side] == null:
		return "There is no Monster in the arena."
	if bool(monster_skill_used[side]):
		return "The Monster skill was already used."
	var mu := ally_monster(side)
	if mu == null:
		return "The Monster has fallen."
	if mu.active_id == "":
		return "This Monster has no active skill."
	var cost := monster_energy_cost()
	if int(energy[side]) < cost:
		return "Not enough energy for the Monster skill (%d/%d)." % [int(energy[side]), cost]
	energy[side] = int(energy[side]) - cost
	_cast_monster_skill(side, mu)
	return ""


func _cast_monster_skill(side: int, mu: BattleUnit) -> void:
	monster_skill_used[side] = true
	mu.active_used = true
	_log("Monster skill: %s - %s (side %d)." % [mu.display_name, String(GameData.get_monster(mu.card_id).get("active_name", mu.active_id)), side])
	_apply_active_skill(mu, side, mu.active_id, mu.active_value)


## An auto (AI) side's Monster casts its skill once the King skill is done (or the King is gone) and the energy is there.
func _auto_monster_skill(side: int) -> void:
	if manual_king[side] or bool(monster_skill_used[side]) or not bool(king_entered[side]):
		return
	var mu := ally_monster(side)
	if mu == null or mu.active_id == "":
		return
	if _king_waiting(side):
		return  # the King's skill gets the energy first
	var cost := monster_energy_cost()
	if int(energy[side]) < cost:
		return
	energy[side] = int(energy[side]) - cost
	_cast_monster_skill(side, mu)


## A Monster card that is still waiting for energy (auto side), so Support cards do not drain the bar.
func _monster_waiting(side: int) -> bool:
	return not manual_king[side] and bool(king_entered[side]) and not bool(monster_skill_used[side]) and ally_monster(side) != null


## Wild monsters (a side without a King) cast their skill once, for free, when an enemy comes within 3 cells.
func _auto_wild_skills() -> void:
	if not bool(GameData.b("wild_monster_skill", true)):
		return
	for u in units:
		if not u.alive or not u.is_monster or u.active_used or u.active_id == "" or king_data[u.side] != "":
			continue
		for e in units_of(1 - u.side):
			if _dist(e.cell, u.cell) <= 3:
				u.active_used = true
				_log("Wild monster skill: %s - %s." % [u.display_name, String(GameData.get_monster(u.card_id).get("active_name", u.active_id))])
				_apply_active_skill(u, u.side, u.active_id, u.active_value)
				break


func _check_end() -> void:
	var lost := [false, false]
	for s in range(2):
		if king_entered[s]:
			lost[s] = not (kings[s] as BattleUnit).alive
		elif king_data[s] == "":
			lost[s] = regulars_alive(s) == 0
	for s2 in range(2):
		if lost[s2] and king_entered[s2]:
			events.append({"type": "mate", "side": s2})
	if lost[0] and lost[1]:
		_finish(-1, "Both Champions fell")
	elif lost[0]:
		_finish(1, "Champion of side 0 fell")
	elif lost[1]:
		_finish(0, "Champion of side 1 fell")


func _finish(w: int, reason: String) -> void:
	if finished:
		return
	finished = true
	winner = w
	end_reason = reason
	_log("=== BATTLE OVER: %s ===" % ("Side %d wins" % w if w >= 0 else "Draw"))


# ------------------------------------------------------------------ support cards

func energy_max() -> int:
	return maxi(1, int(GameData.b("energy_max", 10)))


func energy_regen_ticks() -> int:
	return maxi(1, int(GameData.b("energy_regen_ticks", 8)))


## Energy a Support card costs to play (by rarity, data/balance.json `support_energy_cost`).
func support_energy_cost(support_id: String) -> int:
	if free_supports:
		return 0
	var costs: Dictionary = GameData.b("support_energy_cost", {})
	return int(costs.get(String(CardDatabase.get_support(support_id).get("rarity", "common")), 3))


## 0..1: how far the next energy point is (1.0 while the bar is full).
func energy_progress(side: int) -> float:
	if int(energy[side]) >= energy_max():
		return 1.0
	return float(int(energy_timer[side])) / float(energy_regen_ticks())


func combo_window() -> int:
	return maxi(1, int(GameData.b("combo_window_ticks", 20)))


## Current chain length of a side (0 if the window has run out).
func combo_active(side: int) -> int:
	if int(combo_count[side]) > 0 and tick - int(combo_last_tick[side]) <= combo_window():
		return int(combo_count[side])
	return 0


## Energy the King's active skill costs (data/balance.json `king_skill_energy`).
func king_energy_cost() -> int:
	return 0 if free_supports else clampi(int(GameData.b("king_skill_energy", 6)), 0, energy_max())


## An auto (AI) King that has entered but is still saving energy for its skill.
func _king_waiting(side: int) -> bool:
	return not bool(king_skill_locked[side]) and not manual_king[side] and bool(king_entered[side]) and not bool(king_skill_used[side]) and (kings[side] as BattleUnit).alive


func _regen_energy() -> void:
	for side in range(2):
		if int(energy[side]) >= energy_max():
			energy_timer[side] = 0  # a full bar wastes time: use it or lose it
			continue
		energy_timer[side] = int(energy_timer[side]) + 1
		if int(energy_timer[side]) >= energy_regen_ticks():
			energy_timer[side] = 0
			energy[side] = int(energy[side]) + 1


func available_supports(side: int) -> Array:
	var out: Array = []
	for id in hands[side]:
		if not (used_supports[side] as Array).has(id):
			out.append(id)
	return out


func is_support_implemented(support_id: String) -> bool:
	return IMPLEMENTED_SUPPORTS.has(String(CardDatabase.get_support(support_id).get("effect", "")))


## Returns "" on success or the reason it failed.
func use_support(side: int, support_id: String) -> String:
	if finished:
		return "The battle is over."
	if not (hands[side] as Array).has(support_id):
		return "Card is not in hand."
	if (used_supports[side] as Array).has(support_id):
		return "Card already used."
	var s := CardDatabase.get_support(support_id)
	var cost := support_energy_cost(support_id)
	if int(energy[side]) < cost:
		return "Not enough energy (%d/%d)." % [int(energy[side]), cost]
	var value := int(s.get("value", 0))
	var enemy_side := 1 - side
	match String(s.get("effect", "")):
		"area_damage":
			var foes := units_of(enemy_side)
			if foes.is_empty():
				return "No target."
			var center: BattleUnit = foes[0]
			var best_n := -1
			for f in foes:
				var n := 0
				for g in foes:
					if _dist(f.cell, g.cell) <= 1:
						n += 1
				if n > best_n:
					best_n = n
					center = f
			var hit_cells: Array = []
			for g in foes:
				if _dist(center.cell, g.cell) <= 1:
					hit_cells.append(g.cell)
					_damage(g, value)
			events.append({"type": "fx", "cells": hit_cells})
		"heal_all":
			for a in units_of(side):
				_heal(a, int(round(a.max_hp * value / 100.0)))
		"team_atk":
			for a in units_of(side):
				a.buff_mult = 1.0 + value / 100.0
				a.buff_until = tick + 24
		"shield_all":
			for a in units_of(side):
				a.shield += value
		"summon_pawns":
			var made := 0
			for i in range(value):
				var c := _free_cell_near(Vector2i(3, 6) if side == 0 else Vector2i(4, 1))
				if c.x >= 0:
					_spawn_unit(side, "pawn_royal_guard", 1, c, 0.0)
					made += 1
			if made == 0:
				return "No free cell."
		"gold_on_win":
			bonus_gold[side] += value
		"summon_familiar":
			var fam_made := 0
			for i in range(maxi(value, 1)):  # value = number of familiars
				var fc := _free_cell_near(Vector2i(3, 6) if side == 0 else Vector2i(4, 1))
				if fc.x < 0:
					break
				_spawn_unit(side, "pawn_starling_initiate", 1, fc, 0.0)
				fam_made += 1
			if fam_made == 0:
				return "No free cell."
		"create_wall":
			var wc := _wall_cell(side)
			if wc.x < 0:
				return "No place for a wall."
			walls[wc] = tick + 16 * maxi(value, 1)
			events.append({"type": "fx", "cells": [wc]})
		"promote_pawn":
			var promoted := 0
			for i in range(maxi(value, 1)):  # value = number of Pawns promoted
				var pawn: BattleUnit = null
				for a in units_of(side):
					if a.chess == "pawn" and (pawn == null or a.hp > pawn.hp):
						pawn = a
				if pawn == null:
					break
				pawn.chess = "knight"
				pawn.move = 3
				pawn.max_hp = int(pawn.max_hp * 1.5)
				pawn.hp = int(pawn.hp * 1.5)
				pawn.base_atk = int(pawn.base_atk * 1.3)
				promoted += 1
			if promoted == 0:
				return "No Pawn to promote."
		"polymorph_enemy":
			var poly_skip: Array = []
			for i in range(maxi(value, 1)):  # value = number of enemies turned into weak creatures (strongest first)
				var strong := _best_unit(enemy_side, "atk", false, poly_skip)
				if strong == null:
					break
				poly_skip.append(strong)
				strong.buff_mult = 0.2
				strong.buff_until = tick + 16
				strong.slow_until = tick + 16
			if poly_skip.is_empty():
				return "No target."
		"ascend_unit":
			var asc_skip: Array = []
			for i in range(maxi(value, 1)):  # value = number of different units that gain +1 star
				var up := _best_unit(side, "power", true, asc_skip)
				if up == null:
					break
				asc_skip.append(up)
				var now := CardDatabase.unit_stats(up.card_id, up.stars)
				var nxt := CardDatabase.unit_stats(up.card_id, up.stars + 1)
				up.max_hp += int(nxt["hp"]) - int(now["hp"])
				up.hp += int(nxt["hp"]) - int(now["hp"])
				up.base_atk += int(nxt["atk"]) - int(now["atk"])
				up.stars += 1
			if asc_skip.is_empty():
				return "No unit can ascend."
		"freeze_area":
			var foes2 := units_of(enemy_side)
			if foes2.is_empty():
				return "No target."
			var center2: BattleUnit = foes2[0]
			var best2 := -1
			for f in foes2:
				var n2 := 0
				for g in foes2:
					if _dist(f.cell, g.cell) <= 1:
						n2 += 1
				if n2 > best2:
					best2 = n2
					center2 = f
			var cells2: Array = []
			for g in foes2:
				if _dist(center2.cell, g.cell) <= 1:
					g.stun_until = tick + value * 4 + 1  # value seconds = value*4 ticks
					cells2.append(g.cell)
			events.append({"type": "fx", "cells": cells2})
		"buff_atk":  # auto-targets the strongest attacker (TODO: manual targeting)
			var ba := _best_unit(side, "atk")
			if ba == null:
				return "No unit."
			ba.base_atk = int(round(ba.base_atk * (1.0 + value / 100.0)))
		"buff_hp":  # auto-targets the toughest unit
			var bh := _best_unit(side, "hp")
			if bh == null:
				return "No unit."
			var extra := int(round(bh.max_hp * value / 100.0))
			bh.max_hp += extra
			bh.hp += extra
		"buff_move":
			var bm := _best_unit(side, "atk")
			if bm == null:
				return "No unit."
			bm.move += value
		"team_speed":
			haste_until[side] = tick + int(round(24.0 * float(maxi(value, 1)) / 15.0))  # value 15 = 6 s; the duration scales with value
		"instant_skill":
			var cast_skip: Array = []
			for i in range(maxi(value, 1)):  # value = number of different units that cast at once
				var err := _instant_skill(side, cast_skip)
				if err != "":
					if cast_skip.is_empty():
						return err
					break
		"revive_once":
			revive_pending[side] = maxi(value, 1)  # value = number of revives, "hp_pct" = HP they return with
			revive_hp_pct[side] = int(s.get("hp_pct", 50))
		"lifesteal_pact":
			lifesteal[side] = value / 100.0
			gold_delta[side] -= int(s.get("cost", 20))  # "cost" (gold) defaults to 20
		"temp_capacity", "free_reroll":
			return "This card applies automatically during preparation."
		_:
			return "Effect '%s' is not implemented yet (TODO)." % s.get("effect", "?")
	var category := String(s.get("category", ""))
	var chain := 1
	if combo_active(side) > 0 and String(combo_category[side]) == category:
		chain = int(combo_count[side]) + 1
	combo_category[side] = category
	combo_count[side] = chain
	combo_last_tick[side] = tick
	var refund := mini(chain - 1, int(GameData.b("combo_refund_max", 2))) if cost > 0 else 0
	energy[side] = mini(int(energy[side]) - cost + refund, energy_max())
	(used_supports[side] as Array).append(support_id)
	if refund > 0:
		_log("Side %d plays %s (-%d energy). %s combo x%d: +%d energy back!" % [side, s["name"], cost, category.capitalize(), chain, refund])
	else:
		_log("Side %d plays %s (-%d energy)." % [side, s["name"], cost])
	return ""


func _ai_use_supports() -> void:
	if tick % 30 != 0:
		return
	for side in range(2):
		if not ai_supports[side] or _king_waiting(side) or _monster_waiting(side):
			continue  # a King (then its Monster) that is waiting for its skill gets the energy first
		# The AI plays the most expensive card it can afford right now (so it does not waste the bar).
		var best := ""
		var chain_cat := String(combo_category[side]) if combo_active(side) > 0 else ""
		for id in available_supports(side):
			if not is_support_implemented(id) or support_energy_cost(id) > int(energy[side]):
				continue
			var on_chain := chain_cat != "" and String(CardDatabase.get_support(id).get("category", "")) == chain_cat
			var best_on_chain := best != "" and chain_cat != "" and String(CardDatabase.get_support(best).get("category", "")) == chain_cat
			if best == "" or (on_chain and not best_on_chain) or (on_chain == best_on_chain and support_energy_cost(id) > support_energy_cost(best)):
				best = id
		if best != "":
			use_support(side, best)


func _log(text: String) -> void:
	log_lines.append(text)


## Auto-targeting helper: the best own/enemy unit by "atk", "hp" or "power" (hp + 6*atk).
func _best_unit(side: int, kind: String, only_upgradable: bool = false, skip: Array = []) -> BattleUnit:
	var best: BattleUnit = null
	var best_v := -1.0
	for u in units_of(side):
		if only_upgradable and (u.is_king or u.stars >= 3):
			continue
		if skip.has(u):
			continue
		var v := float(u.base_atk)
		if kind == "hp":
			v = float(u.max_hp)
		elif kind == "power":
			v = float(u.max_hp) + float(u.base_atk) * 6.0
		if v > best_v:
			best_v = v
			best = u
	return best


## Forge Bastion: a free cell next to the enemy closest to our units.
func _wall_cell(side: int) -> Vector2i:
	var foes := units_of(1 - side)
	if foes.is_empty():
		return Vector2i(-1, -1)
	var allies := units_of(side)
	var ref := Vector2i(3, 7) if side == 0 else Vector2i(4, 0)
	if not allies.is_empty():
		ref = allies[0].cell
	var nearest := foes[0]
	for f in foes:
		if _dist(f.cell, ref) < _dist(nearest.cell, ref):
			nearest = f
	return _free_adjacent(nearest.cell, ref)


## Focus: one unit uses its skill right now (periodic skills fire; proc skills proc on the next attack).
func _instant_skill(side: int, skip: Array = []) -> String:
	var cands := units_of(side)
	cands.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool: return a.base_atk > b.base_atk)
	for u in cands:
		if skip.has(u):
			continue
		if _skill_interval(u) > 0:
			u.next_skill_tick = tick
			_periodic_skill(u)
			skip.append(u)
			return ""
	for u in cands:
		if skip.has(u):
			continue
		if u.skill_id == "radiant_strike":
			u.attacks_made = 2
			u.next_attack_tick = tick
			skip.append(u)
			return ""
		if u.skill_id == "arcane_barrage":
			u.attacks_made = int(_p(u, "every", 6)) - 1
			u.next_attack_tick = tick
			skip.append(u)
			return ""
	return "No unit with a castable skill."
