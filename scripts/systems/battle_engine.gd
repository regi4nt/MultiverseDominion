class_name BattleEngine
extends RefCounted
## Deterministic auto-battle on the 8x8 grid. One step() = one tick (0.25 s at 1x speed).
## Side 0 starts on rows 4-7, side 1 on rows 0-3. No manual unit control.
##
## Unit behaviour: target priority by role, attack range (Chebyshev distance), movement
## (BFS, up to `move` cells per tick), skills, faction + role synergy bonuses, Support cards.
## The Champion (King) enters ONLY when every regular unit of its side has fallen (Last Stand),
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
## Role Synergy: 2+ units of one role = +8%, 4+ = +20%, 6+ = +35% of the stat that role is about (only for units of that role).
## Tank / Support: HP. Assassin / Mage / Marksman: ATK. Fighter / Controller: HP and ATK at ROLE_BOTH_FACTOR of the tier.
const ROLE_TIERS: Array = [[6, 0.35], [4, 0.20], [2, 0.08]]
const ROLE_FOCUS := {"Tank": "hp", "Support": "hp", "Assassin": "atk", "Mage": "atk", "Marksman": "atk", "Fighter": "both", "Controller": "both"}
const ROLE_BOTH_FACTOR := 0.6

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
var manual_king: Array = [false, false]  # true = that side's King skill is cast by hand (human); false = on entry (AI / tests)
var king_entry_tick: Array = [-1, -1]
var regulars_alive_at_entry: Array = [-1, -1]  # test hook: must always be 0
var hands: Array = [[], []]
var used_supports: Array = [[], []]
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
var walls: Dictionary = {}  # Vector2i -> tick when the wall expires (Forge Bastion)
var revive_pending: Array = [false, false]  # Guardian Angel family: number of revives left (bool-compatible)
var revive_hp_pct: Array = [50, 50]
var lifesteal: Array = [0.0, 0.0]
var haste_until: Array = [0, 0]
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
	free_supports = bool(cfg.get("free_supports", false))
	energy = [mini(int(GameData.b("energy_start", 2)), energy_max()), mini(int(GameData.b("energy_start", 2)), energy_max())]
	for side in range(2):
		var sc: Dictionary = cfg["sides"][side]
		king_data[side] = String(sc.get("champion", ""))
		king_star[side] = clampi(int(sc.get("champion_star", 1)), 1, CommanderSystem.max_star())
		side_passive[side] = GameData.king_passives.get(king_data[side], {})
		hands[side] = (sc.get("supports", []) as Array).duplicate()
		for sid in hands[side]:
			if PREP_SUPPORTS.has(String(CardDatabase.get_support(String(sid)).get("effect", ""))):
				(used_supports[side] as Array).append(sid)  # already applied in preparation
		var side_fac := _side_faction(side)
		var synergy := _synergy(sc["units"], side_fac)
		for fac in synergy:
			_log("Side %d faction synergy: %s +%d%%" % [side, String(fac).capitalize(), int(float(synergy[fac]) * 100.0)])
		var roles := role_counts(sc["units"])
		for r in roles:
			var rb := role_bonus(String(r), int(roles[r]))
			if float(rb["tier"]) > 0.0:
				_log("Side %d role synergy: %s x%d +%d%% %s" % [side, r, roles[r], int(round(maxf(float(rb["hp"]), float(rb["atk"])) * 100.0)), {"hp": "HP", "atk": "ATK", "both": "HP/ATK"}[String(ROLE_FOCUS.get(r, "both"))]])
		for e in sc["units"]:
			var fac := CardDatabase.effective_faction(CardDatabase.get_unit(e["card_id"]), side_fac)
			var role := String(CardDatabase.get_unit(e["card_id"]).get("role", ""))
			var rbn := role_bonus(role, int(roles.get(role, 0)))
			_spawn_unit(side, e["card_id"], int(e["stars"]), e["cell"], float(synergy.get(fac, 0.0)), float(rbn["hp"]), float(rbn["atk"]))
	for u in units:  # Queen of Machina: the side starts with shields
		if u.extra == "opening_shield":
			for a in units_of(u.side):
				a.shield += int(round(a.max_hp * u.extra_value))
	_log("Battle begins!")
	_check_king_entries()


## Role Synergy bonus for `count` units of `role`: {"hp": fraction, "atk": fraction, "tier": fraction} (all 0.0 below 2 units).
static func role_bonus(role: String, count: int) -> Dictionary:
	var v := 0.0
	for t in ROLE_TIERS:
		if count >= int(t[0]):
			v = float(t[1])
			break
	var focus := String(ROLE_FOCUS.get(role, "both"))
	var f := ROLE_BOTH_FACTOR if focus == "both" else 1.0
	return {"hp": v * f if focus != "atk" else 0.0, "atk": v * f if focus != "hp" else 0.0, "tier": v}


## Units needed for the next Role Synergy tier (0 = already at the top tier).
static func role_next_tier(count: int) -> int:
	var nxt := 0
	for t in ROLE_TIERS:
		if count < int(t[0]):
			nxt = int(t[0])
	return nxt


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


## Home-continent rule: card buffs (and Faction Synergy) apply only if the side's faction belongs to the continent
## being played. A side without a Champion keeps them (no faction to be foreign).
func _home_bonus(side: int) -> bool:
	var fac := _side_faction(side)
	return fac == "" or GameData.is_home_faction(fac, CardDatabase.active_continent)


## Faction Synergy: 2+ units of one faction = +5%, 4+ = +15%, 6+ = +30% HP and ATK.
## Shared pieces (Rook, Knight, Bishop, Queen) count for the side's own faction; a side without a Champion has none.
func _synergy(list: Array, side_fac: String = "") -> Dictionary:
	var counts := {}
	for e in list:
		var fac := CardDatabase.effective_faction(CardDatabase.get_unit(e["card_id"]), side_fac)
		if fac == "" or not GameData.is_home_faction(fac, CardDatabase.active_continent):
			continue  # a faction playing outside its home continent gets no Faction Synergy
		counts[fac] = int(counts.get(fac, 0)) + 1
	var out := {}
	for fac in counts:
		var n: int = counts[fac]
		if n >= 6:
			out[fac] = 0.30
		elif n >= 4:
			out[fac] = 0.15
		elif n >= 2:
			out[fac] = 0.05
	return out


func _spawn_unit(side: int, card_id: String, stars: int, cell: Vector2i, bonus: float, role_hp: float = 0.0, role_atk: float = 0.0) -> BattleUnit:
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
	var sp: Dictionary = side_passive[side]
	var sp_hp := float(sp.get("value", 0.0)) if sp.get("type", "") == "team_hp" else 0.0
	var sp_atk := float(sp.get("value", 0.0)) if sp.get("type", "") == "team_atk" else 0.0
	u.max_hp = int(round(float(st["hp"]) * (1.0 + bonus) * (1.0 + role_hp) * (1.0 + sp_hp)))
	u.hp = u.max_hp
	if sp.get("type", "") == "team_shield":
		u.shield += int(round(u.max_hp * float(sp["value"])))
	u.base_atk = int(round(float(st["atk"]) * (1.0 + bonus) * (1.0 + role_atk) * (1.0 + sp_atk) * WorldMods.atk_mult))
	u.atk_range = int(card["range"])
	u.move = int(card["move"])
	u.skill_id = CardDatabase.skill_mechanic(card)  # themed continent skills map to a base mechanic
	u.cell = cell
	u.params = card["skill"].get("params", {})  # per-continent numbers of the skill (defaults = the Aetherion values)
	var bf := CardDatabase.get_buff(card_id)  # the card's buff of its continent (data/card_buffs.json)
	if not _home_bonus(side):
		bf = {}  # a foreign faction on this continent fights without the continent card buffs
	u.extra = String(bf.get("type", ""))
	u.extra_value = float(bf.get("value", 0.0))
	u.next_skill_tick = _skill_interval(u)
	_init_buff(u)
	units.append(u)
	grid[cell] = u
	return u


## A numeric skill parameter of a unit (data: skill.params), falling back to the base value.
func _p(u: BattleUnit, key: String, default: Variant) -> Variant:
	return u.params.get(key, default)


## Buff effects that change the unit when it is created.
func _init_buff(u: BattleUnit) -> void:
	match u.extra:
		"swift":
			u.move += int(u.extra_value)
		"opener":
			u.strike_bonus = u.extra_value
		"ward":
			u.shield += int(round(u.max_hp * u.extra_value))
		"regen", "mend_self":
			u.buff_next_tick = BUFF_INTERVAL


## Periodic buff effects (their own timer, independent of the unit's skill).
func _buff_periodic(u: BattleUnit) -> void:
	if u.buff_next_tick == 0 or tick < u.buff_next_tick:
		return
	u.buff_next_tick = tick + BUFF_INTERVAL
	match u.extra:
		"regen":
			for a in units_of(u.side):
				_heal(a, int(round(a.max_hp * u.extra_value)))
		"mend_self":
			_heal(u, int(round(u.max_hp * u.extra_value)))


func _skill_interval(u: BattleUnit) -> int:
	match u.skill_id:
		"rally_banner": return 8
		"blessed_mend": return int(_p(u, "interval", 10))
		"ballista_volley": return int(_p(u, "interval", 12))
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


func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


func atk_now(u: BattleUnit) -> int:
	var m := 1.0
	if u.buff_until > tick:
		m *= u.buff_mult
	if u.brace_active:
		m *= 1.3
	for a in units:
		if a.side == u.side and a.alive and a.skill_id == "sovereign_decree":
			m *= 1.15
			break
	if u.extra == "rage" and u.hp * 2 < u.max_hp:
		m *= 1.0 + u.extra_value
	elif u.extra == "frenzy":
		m *= 1.0 + u.extra_value * mini(u.kills, 5)
	var aura := 0.0
	for a in units:
		if a != u and a.side == u.side and a.alive and a.extra == "aura_atk" and _dist(a.cell, u.cell) <= 1:
			aura = maxf(aura, a.extra_value)
	m *= 1.0 + aura
	return int(round(float(u.base_atk) * m))


func _free_cell_near(c: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 999
	for y in range(ROWS):
		for x in range(COLS):
			var p := Vector2i(x, y)
			if _blocked(p):
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
		if _in_bounds(p) and not _blocked(p):
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
	if ai_supports[0] or ai_supports[1]:
		_ai_use_supports()
	_check_king_entries()
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
	if _dist(u.cell, target.cell) <= u.atk_range:
		if tick >= u.next_attack_tick:
			_attack(u, target)
			u.next_attack_tick = tick + _attack_interval(u)
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
				if d <= float(u.atk_range):
					key = float(e.hp) + d  # weakest enemy already in range
				else:
					key = 100000.0 + d * 1000.0 + float(e.uid)
		if key < best_key:
			best_key = key
			best = e
	return best


func _move_toward(u: BattleUnit, target: BattleUnit) -> void:
	var start := u.cell
	var prev := {start: start}
	var queue: Array[Vector2i] = [start]
	var goal := Vector2i(-1, -1)
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		if c != start and _dist(c, target.cell) <= u.atk_range:
			goal = c
			break
		for d in DIRS:
			var n := c + d
			if not _in_bounds(n) or prev.has(n) or _blocked(n):
				continue
			prev[n] = c
			queue.append(n)
	if goal.x < 0:
		# Path blocked: step to the free neighbour that gets closest.
		var best := Vector2i(-1, -1)
		var best_d := _dist(u.cell, target.cell)
		for d in DIRS:
			var n := u.cell + d
			if _in_bounds(n) and not _blocked(n) and _dist(n, target.cell) < best_d:
				best_d = _dist(n, target.cell)
				best = n
		if best.x >= 0:
			_move_unit(u, best)
		return
	var path: Array[Vector2i] = []
	var cur := goal
	while cur != start:
		path.push_front(cur)
		cur = prev[cur]
	_move_unit(u, path[mini(u.move, path.size()) - 1])


func _move_unit(u: BattleUnit, c: Vector2i) -> void:
	grid.erase(u.cell)
	u.cell = c
	grid[c] = u


# ------------------------------------------------------------------ combat

func _attack(u: BattleUnit, t: BattleUnit) -> void:
	var dmg := float(atk_now(u))
	u.attacks_made += 1
	if u.strike_bonus > 0.0:  # Knight (Assassin): the first attack after the teleport hits harder
		dmg *= 1.0 + u.strike_bonus
		u.strike_bonus = 0.0
	if u.extra == "execute" and t.hp * 10 < t.max_hp * 3:
		dmg *= 1.0 + u.extra_value
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
	match u.extra:  # Queen: continent-specific additional effect
		"splash":
			for e in units_of(1 - u.side):
				if e != t and _dist(e.cell, tcell) <= 1:
					_damage(e, int(round(amount * u.extra_value)))
		"lifesteal":
			_heal(u, int(round(dealt * u.extra_value)))
		"chill":
			t.slow_until = tick + int(u.extra_value)
		"burn":
			if t.alive:
				t.burn_until = tick + 12
				t.burn_amount = maxi(1, int(round(u.base_atk * u.extra_value)))
		"stun_proc":
			if t.alive and u.attacks_made % int(u.extra_value) == 0:
				t.stun_until = tick + 2
	if t.extra == "thorns" and t.alive and u.alive and dealt > 0 and not _reflecting:
		_reflecting = true
		_damage(u, maxi(1, int(round(dealt * t.extra_value))))
		_reflecting = false


## Rally (team_speed): every 3rd attack comes a tick sooner (about +20% attack speed).
func _attack_interval(u: BattleUnit) -> int:
	if int(haste_until[u.side]) > tick and u.attacks_made % 3 == 0:
		return ATTACK_INTERVAL - 1
	return ATTACK_INTERVAL


func _damage(t: BattleUnit, amount: int) -> int:
	if not t.alive:
		return 0
	if t.extra == "evade" and (t.hits_taken + 1) % int(t.extra_value) == 0:
		t.hits_taken += 1  # every Nth hit is avoided
		return 0
	var dmg := float(amount)
	if t.extra == "armor":
		dmg *= 1.0 - t.extra_value
	if t.skill_id == "shield_wall":
		for a in units_of(t.side):
			if a != t and _dist(a.cell, t.cell) <= 1:
				dmg *= 0.8
				break
	for a in units:  # Queen of Aetherion: allies within 2 cells (and she herself) take less damage
		if a.side == t.side and a.alive and a.extra == "guard" and _dist(a.cell, t.cell) <= 2:
			dmg *= 1.0 - a.extra_value
			break
	var tp: Dictionary = side_passive[t.side]
	if tp.get("type", "") == "team_armor":
		dmg *= 1.0 - float(tp["value"])  # King passive of the target's side
	if t.reduce_until > tick:
		dmg *= 0.5
	var d := int(round(dmg))
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
	if t.extra == "second_life" and not t.second_life_used and not t.is_king:
		t.second_life_used = true  # Queen of Eclipsia: returns once at a share of her max HP
		t.hp = maxi(1, int(t.max_hp * t.extra_value))
		t.shield = 0
		events.append({"type": "fx", "cells": [t.cell]})
		_log("%s returns for a second life!" % t.display_name)
		return
	t.hp = 0
	t.alive = false
	grid.erase(t.cell)
	events.append({"type": "death", "cell": t.cell})
	_log("%s (side %d) falls." % [t.display_name, t.side])
	match t.extra:
		"last_rites":
			for a in units_of(t.side):
				if _dist(a.cell, t.cell) <= 1:
					_heal(a, int(round(a.max_hp * t.extra_value)))
		"death_burst":
			for e in units_of(1 - t.side):
				if _dist(e.cell, t.cell) <= 1:
					_damage(e, int(round(t.base_atk * t.extra_value)))


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


func _enter_king(side: int) -> void:
	var ch := GameData.get_champion(king_data[side])
	var u := BattleUnit.new()
	_uid += 1
	u.uid = _uid
	u.side = side
	u.card_id = king_data[side]
	u.is_king = true
	u.display_name = String(ch["name"])
	u.chess = "king"
	u.role = "Fighter"
	u.faction = String(ch["faction"])
	var kp: Dictionary = side_passive[side]
	var kp_hp := float(kp.get("value", 0.0)) if kp.get("type", "") == "king_hp" else 0.0
	var kp_atk := float(kp.get("value", 0.0)) if kp.get("type", "") == "king_atk" else 0.0
	u.max_hp = int(round(float(ch["hp"]) * float(GameData.b("champion_hp_mult")) * (1.0 + kp_hp) * CommanderSystem.hp_mult(int(king_star[side]))))
	u.hp = u.max_hp
	u.base_atk = int(round(float(ch["atk"]) * (1.0 + kp_atk) * WorldMods.atk_mult * CommanderSystem.atk_mult(int(king_star[side]))))
	u.atk_range = 1
	u.move = 2
	u.skill_id = String(ch.get("skill_id", ""))
	u.skill_value = float(ch.get("active_value", 0.0))
	u.cell = _free_cell_near(Vector2i(3, 7) if side == 0 else Vector2i(4, 0))
	var kb := CardDatabase.king_buff(king_data[side])  # home-continent King buff (data/king_buffs.json)
	u.extra = String(kb.get("type", ""))
	u.extra_value = float(kb.get("value", 0.0))
	_init_buff(u)
	if u.buff_next_tick != 0:
		u.buff_next_tick = tick + BUFF_INTERVAL
	units.append(u)
	grid[u.cell] = u
	kings[side] = u
	king_entered[side] = true
	king_entry_tick[side] = tick
	regulars_alive_at_entry[side] = regulars_alive(side)
	_log("LAST STAND! %s enters the arena (side %d)." % [u.display_name, side])
	events.append({"type": "fx", "cells": [u.cell]})
	if manual_king[side]:
		_log("%s waits for the King skill (%s)." % [u.display_name, String(ch.get("active_name", "skill"))])
	else:
		_auto_king_skill(side)  # AI / auto sides cast it on entry, or as soon as they can pay for it


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
	events.append({"type": "fx", "cells": [u.cell]})
	var v := u.skill_value
	var foes := units_of(1 - side)
	match u.skill_id:
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


## True while the side's King is in the arena and its active skill is still unused.
func can_use_king_skill(side: int) -> bool:
	return not finished and bool(king_entered[side]) and not bool(king_skill_used[side]) and (kings[side] as BattleUnit).alive \
			and int(energy[side]) >= king_energy_cost()


## Manual King skill. Returns "" on success or the reason it failed.
func use_king_skill(side: int) -> String:
	if finished:
		return "The battle is over."
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


func _check_end() -> void:
	var lost := [false, false]
	for s in range(2):
		if king_entered[s]:
			lost[s] = not (kings[s] as BattleUnit).alive
		elif king_data[s] == "":
			lost[s] = regulars_alive(s) == 0
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
	return not manual_king[side] and bool(king_entered[side]) and not bool(king_skill_used[side]) and (kings[side] as BattleUnit).alive


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
		if not ai_supports[side] or _king_waiting(side):
			continue  # a King that is waiting for its skill gets the energy first
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
