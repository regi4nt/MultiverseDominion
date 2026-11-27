extends Node
## 28 different Kings + 28 "King+" Monsters: every King has its own active skill, battle buff, battle passive pair and Territory skill pair;
## every Monster has its own composed skill and a Plus trait. Also tests the new buff mechanics, the skill ops and the new Territory skills.
## Run: godot --headless --path . res://tests/kit_test.tscn   (-> KIT TEST RESULT: PASS)

var failures := 0
var NEW_BUFFS: Array[String] = CardDatabase.KING_BUFF_TYPES


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	_test_king_uniqueness()
	_test_monster_uniqueness()
	_test_skill_data()
	_test_every_skill_casts()
	_test_buff_mechanics()
	_test_territory_skills()
	print("KIT TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


# ------------------------------------------------------------------ data: all different

func _dup_free(values: Array) -> bool:
	var seen := {}
	for v in values:
		if seen.has(v):
			return false
		seen[v] = true
	return true


func _test_king_uniqueness() -> void:
	var skill_ids := []
	var skill_names := []
	var skill_fx := []
	var buff_types := []
	var buff_names := []
	var terr := []
	var terr_names := []
	var batt := []
	var batt_names := []
	for cid in GameData.champions:
		var c: Dictionary = GameData.champions[cid]
		skill_ids.append(String(c["skill_id"]))
		skill_names.append(String(c["active_name"]))
		skill_fx.append(JSON.stringify(GameData.skills[String(c["skill_id"])]["fx"]))
		var kb: Dictionary = GameData.king_buffs[cid]
		buff_types.append(String(kb["type"]))
		buff_names.append(String(kb["name"]))
		terr.append("%s:%s+%s:%s" % [c["passive"], c["passive_value"], c.get("passive2", ""), c.get("passive2_value", 0)])
		terr_names.append(String(c["passive_name"]))
		var kp: Dictionary = GameData.king_passives[cid]
		batt.append("%s:%s+%s:%s" % [kp["type"], kp["value"], kp.get("type2", ""), kp.get("value2", 0)])
		batt_names.append(String(kp["name"]))
		check(String(c.get("passive2", "")) != "" and String(c["passive2"]) != String(c["passive"]), "%s has two different Territory skills" % cid)
	check(GameData.champions.size() == 28, "28 Kings")
	check(_dup_free(skill_ids) and _dup_free(skill_names) and _dup_free(skill_fx), "28 different King active skills (id, name and effect list)")
	check(_dup_free(buff_types) and _dup_free(buff_names), "28 different King battle buffs (every buff type used once)")
	check(_dup_free(terr) and _dup_free(terr_names), "28 different Territory skill pairs and names")
	check(_dup_free(batt) and _dup_free(batt_names), "28 different battle passives (two effects each)")
	var all_buff_ok := true
	for cid in GameData.champions:
		var t := String(GameData.king_buffs[cid]["type"])
		all_buff_ok = all_buff_ok and (CardDatabase.BUFF_TYPES.has(t) or NEW_BUFFS.has(t))
	check(all_buff_ok, "every King buff type is implemented")


func _test_monster_uniqueness() -> void:
	var ids := []
	var names := []
	var skill_ids := []
	var skill_fx := []
	var pairs := []
	var plus_names := []
	var king_skills := {}
	for cid in GameData.champions:
		king_skills[String(GameData.champions[cid]["skill_id"])] = true
	var own_kit := true
	var count := 0
	for cont in GameData.monsters:
		for m in GameData.monsters[cont]:
			count += 1
			ids.append(String(m["id"]))
			names.append(String(m["name"]))
			skill_ids.append(String(m["skill_id"]))
			var fx: Array = GameData.skills[String(m["skill_id"])]["fx"]
			skill_fx.append(JSON.stringify(fx))
			own_kit = own_kit and not king_skills.has(String(m["skill_id"])) and fx.size() >= 2  # a King+ kit: 2-3 effects
			var plus: Dictionary = m["plus"]
			pairs.append("%s+%s" % [m["buff"]["type"], plus["type"]])
			plus_names.append(String(plus["name"]))
			own_kit = own_kit and NEW_BUFFS.has(String(plus["type"])) and String(plus["type"]) != String(m["buff"]["type"]) and String(plus["desc"]) != ""
	check(count == 28 and _dup_free(ids) and _dup_free(names), "28 different Monsters")
	check(_dup_free(skill_ids) and _dup_free(skill_fx), "28 different Monster skills (no two alike)")
	check(own_kit, "every Monster has a King+ kit: 2-3 skill effects (none shared with a King skill) and a Plus trait")
	check(_dup_free(pairs) and _dup_free(plus_names), "every Monster has its own buff + Plus combination")


func _test_skill_data() -> void:
	var ok := true
	var all_skills: Dictionary = GameData.skills
	for sid in all_skills:
		for op in all_skills[sid]["fx"]:
			ok = ok and BattleEngine.SKILL_OPS.has(String(op["op"]))
	check(ok and all_skills.size() == 56, "56 composed skills, every effect op is implemented")
	var used := {}
	for sid in all_skills:
		for op in all_skills[sid]["fx"]:
			used[String(op["op"])] = true
	check(used.size() == BattleEngine.SKILL_OPS.size(), "every effect op is used by at least one skill (%d / %d)" % [used.size(), BattleEngine.SKILL_OPS.size()])
	var desc_ok := true
	for cid in GameData.champions:
		desc_ok = desc_ok and String(GameData.champions[cid]["active_desc"]).begins_with("Manual, once:") and not String(GameData.champions[cid]["passive_desc"]).is_empty()
	check(desc_ok, "King skill and Territory texts are written")
	check(MonsterSystem.summary("crownstone_golem").contains("King+ - Keystone Plating") and MonsterSystem.summary("crownstone_golem").contains("Crownstone Bulwark"), "the Monster summary shows the King+ trait and the skill")


# ------------------------------------------------------------------ every skill really does something

func _arena(champion: String, monster: String = "") -> BattleEngine:
	var e := BattleEngine.new()
	var mine := []
	var foes := []
	var ids := ["pawn_royal_guard", "pawn_dusk_cutpurse", "pawn_iron_pikeman", "pawn_sun_squire"]
	for i in range(4):
		mine.append({"card_id": ids[i], "stars": 1, "cell": Vector2i(1 + i * 2, 6)})
		foes.append({"card_id": ids[i], "stars": 1, "cell": Vector2i(1 + i * 2, 1)})
	e.setup({"seed": 11, "ai_supports": [false, false], "free_supports": true, "manual_king": [true, true], "sides": [
		{"units": mine, "champion": champion, "supports": [], "monster": monster},
		{"units": foes, "champion": "", "supports": []}]})
	return e


## A fingerprint of everything a skill can change (HP, shields, statuses, positions, energy, who is alive).
func _state(e: BattleEngine) -> String:
	var parts := []
	for u in e.units:
		parts.append([u.hp, u.shield, u.alive, u.stun_until, u.slow_until, u.burn_until, u.mark_until, u.reduce_until, u.buff_until, u.cell])
	return JSON.stringify([parts, e.energy, e.haste_until]) if false else str(parts) + str(e.energy) + str(e.haste_until)


## Wounds everybody, stuns / slows the allies, kills one ally and gives the enemy some energy so that every kind of effect has something to act on.
func _prime(e: BattleEngine, caster: BattleUnit) -> void:
	for u in e.units:
		if u == caster:
			continue
		u.hp = maxi(1, int(u.max_hp * (0.3 if u.side == 1 else 0.5)))
		if u.side == caster.side:
			u.stun_until = e.tick + 6
			u.slow_until = e.tick + 6
			u.burn_until = e.tick + 6
	var victim: BattleUnit = null
	for u in e.units:
		if u.side == caster.side and not u.is_king and not u.is_monster:
			victim = u
	victim.hp = 0
	victim.alive = false
	e.grid.erase(victim.cell)
	e.energy = [0, 5]
	caster.hp = maxi(1, int(caster.max_hp * 0.5))
	e.tick = 5


func _test_every_skill_casts() -> void:
	var king_ok := true
	for cid in GameData.champions:
		var e := _arena(cid)
		e._enter_king(0)
		var k: BattleUnit = e.kings[0]
		_prime(e, k)
		var before := _state(e)
		e._cast_king_skill(0)
		var changed := _state(e) != before
		king_ok = king_ok and changed
		if not changed:
			push_error("King skill changed nothing: " + cid)
	check(king_ok, "all 28 King skills change the battle when cast")
	var mon_ok := true
	var n := 0
	for cont in GameData.monsters:
		for m in GameData.monsters[cont]:
			n += 1
			var e := _arena("champion_solvaris", String(m["id"]))
			e._enter_king(0)
			var mu: BattleUnit = e.monster_unit[0]
			_prime(e, mu)
			var before := _state(e)
			e._apply_active_skill(mu, 0, mu.active_id, mu.active_value)
			var changed := _state(e) != before
			mon_ok = mon_ok and changed
			if not changed:
				push_error("Monster skill changed nothing: " + String(m["id"]))
	check(mon_ok and n == 28, "all 28 Monster skills change the battle when cast")
	# the Monster carries its Plus trait on top of its own buff
	var e2 := _arena("champion_solvaris", "crownstone_golem")
	e2._enter_king(0)
	var golem: BattleUnit = e2.monster_unit[0]
	check(golem.extra == "armor" and e2._x(golem, "bastion") > 0.0, "a Monster fights with its buff AND its Plus trait")
	# the second battle passive stacks with the first
	var e3 := _arena("champion_solvaris")
	check(is_equal_approx(e3._sp(0, "team_atk"), 0.05) and is_equal_approx(e3._sp(0, "king_atk"), 0.08), "a King has two battle passives (Solvaris: +5% team ATK and +8% King ATK)")
	# each King skill is more than a renamed copy: spot-check a few specific effects
	var e4 := _arena("champion_eternis")
	e4._enter_king(0)
	_prime(e4, e4.kings[0])
	e4._cast_king_skill(0)
	var back := 0
	for u in e4.units_of(0):
		if not u.is_king and u.alive:
			back += 1
	check(back == 4, "Unending Cycle brings the fallen ally back")
	var e5 := _arena("champion_oblivion")
	e5._enter_king(0)
	_prime(e5, e5.kings[0])
	e5._cast_king_skill(0)
	check(int(e5.energy[1]) == 2 and e5.units_of(1).size() == 0, "Oblivion's Edict kills the wounded and drains energy")


# ------------------------------------------------------------------ the new battle buffs

func _duel(fx_a: Dictionary, atk_hp: int = 1000) -> Array:
	var e := BattleEngine.new()
	e.setup({"seed": 3, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 4)}, {"card_id": "pawn_sun_squire", "stars": 1, "cell": Vector2i(6, 6)}], "champion": "champion_ferrum", "supports": []},
		{"units": [{"card_id": "pawn_iron_pikeman", "stars": 1, "cell": Vector2i(3, 3)}, {"card_id": "pawn_dusk_cutpurse", "stars": 1, "cell": Vector2i(4, 3)}], "champion": "champion_ferrum", "supports": []}]})
	for u in e.units:
		u.fx = {}
		u.extra = ""
		u.extra_value = 0.0
	var a: BattleUnit = e.units_of(0)[0]
	var t: BattleUnit = e.units_of(1)[0]
	a.fx = fx_a
	a.max_hp = atk_hp
	a.hp = atk_hp
	t.max_hp = 100000
	t.hp = 100000
	return [e, a, t]


func _test_buff_mechanics() -> void:
	# bastion: no hit takes more than 25% of max HP
	var r := _duel({})
	var e: BattleEngine = r[0]
	var t: BattleUnit = r[2]
	t.fx = {"bastion": 0.25}
	t.max_hp = 400
	t.hp = 400
	check(e._damage(t, 10000) == 100, "Bastion: a huge hit is capped at 25% of max HP")
	# weaken: the target takes more damage afterwards
	r = _duel({"weaken": 0.5})
	e = r[0]
	var a: BattleUnit = r[1]
	t = r[2]
	var plain := e._damage(r[0].units_of(1)[1], 100)
	e._attack(a, t)
	check(t.mark_until > e.tick and is_equal_approx(t.mark_mult, 0.5), "Weaken: an attack marks the target")
	var marked := e._damage(t, 100)
	check(marked == 150 and plain == 100, "Weaken: a marked target takes +50%% damage (%d vs %d)" % [marked, plain])
	# crit: every 3rd attack hits harder
	r = _duel({"crit": 1.0})
	e = r[0]
	a = r[1]
	t = r[2]
	var losses := []
	for i in range(3):
		var h := t.hp
		e._attack(a, t)
		losses.append(h - t.hp)
	check(losses[2] >= int(losses[0] * 1.9) and losses[1] == losses[0], "Crit: the 3rd attack deals double damage (%s)" % str(losses))
	# chain: the hit arcs to a second enemy
	r = _duel({"chain": 0.5})
	e = r[0]
	a = r[1]
	t = r[2]
	var other: BattleUnit = e.units_of(1)[1]
	other.max_hp = 100000
	other.hp = 100000
	e._attack(a, t)
	check(other.hp < 100000, "Chain: the attack arcs to another enemy")
	# feast + quickkill: a kill heals and refreshes the attack
	r = _duel({"feast": 0.2, "quickkill": 1.0})
	e = r[0]
	a = r[1]
	t = r[2]
	a.hp = 500
	t.hp = 1
	e._attack(a, t)
	check(not t.alive and a.hp == 700, "Feast: a kill heals 20%% max HP (%d)" % a.hp)
	check(a.refresh_attack, "Quick Kill: a kill refreshes the attack")
	# undying: one lethal hit is survived
	r = _duel({})
	e = r[0]
	t = r[2]
	t.fx = {"undying": 0.25}
	t.max_hp = 200
	t.hp = 200
	e._damage(t, 5000)
	check(t.alive and t.hp == 50, "Undying: survives the first lethal hit at 25% HP")
	e._damage(t, 5000)
	check(not t.alive, "Undying: only once")
	# shatter: more damage to shielded targets
	r = _duel({"shatter": 1.0})
	e = r[0]
	a = r[1]
	t = r[2]
	var t2: BattleUnit = e.units_of(1)[1]
	t2.max_hp = 100000
	t2.hp = 100000
	t.shield = 1000
	var s0 := t.shield + t.hp
	e._attack(a, t)
	var shielded_loss := s0 - (t.shield + t.hp)
	a.attacks_made = 0
	var h2 := t2.hp
	e._attack(a, t2)
	check(shielded_loss == (h2 - t2.hp) * 2, "Shatter: +100%% damage to a shielded target (%d vs %d)" % [shielded_loss, h2 - t2.hp])
	# momentum: each attack adds ATK
	r = _duel({"momentum": 0.1})
	e = r[0]
	a = r[1]
	var base := e.atk_now(a)
	a.attacks_made = 4
	check(e.atk_now(a) == int(round(a.base_atk * 1.4)) and e.atk_now(a) > base, "Momentum: +10% ATK per attack made")
	a.attacks_made = 40
	check(e.atk_now(a) == int(round(a.base_atk * 1.8)), "Momentum: capped at 8 stacks")
	# vengeance: an ally's fall fires up the avenger
	r = _duel({})
	e = r[0]
	var avenger: BattleUnit = e.units_of(0)[0]
	var friend: BattleUnit = e.units_of(0)[1]
	avenger.fx = {"vengeance": 0.3}
	friend.hp = 1
	e._damage(friend, 100)
	check(not friend.alive and avenger.buff_until > e.tick and is_equal_approx(avenger.buff_mult, 1.3), "Vengeance: +30% ATK after an ally falls")
	# siphon: attacks feed the energy bar
	r = _duel({"siphon": 2.0})
	e = r[0]
	a = r[1]
	t = r[2]
	e.energy = [0, 0]
	for i in range(3):
		e._attack(a, t)
	check(int(e.energy[0]) == 2, "Siphon: every 3rd attack restores energy (%d)" % int(e.energy[0]))
	# rally cry: entering the arena inspires the allies
	CardDatabase.set_continent("thalassia")  # King buffs only work on the King's home continent
	var e6 := _arena("champion_pelagia")
	e6._enter_king(0)
	var inspired := true
	for u in e6.units_of(0):
		inspired = inspired and u.buff_until > e6.tick and u.buff_mult > 1.0
	check(inspired, "Rally Cry: Tidemother's Call inspires every ally on entry")
	CardDatabase.set_continent("aetherion")


# ------------------------------------------------------------------ the Territory skills

func _match(fac: String, cont: String) -> MatchController:
	var c := MatchController.new()
	c.setup({"continent_id": cont, "faction_id": fac, "difficulty": "normal", "ai_count": 3, "seed": 9, "all_ai": true})
	return c


func _test_territory_skills() -> void:
	var p := PlayerState.new()
	p.passive = "spoils"
	p.passive_value = 40.0
	p.passive2 = "interest"
	p.passive2_value = 0.03
	check(p.has_passive("spoils") and p.has_passive("interest") and not p.has_passive("") and p.pv("interest") == 0.03 and p.pv("spoils") == 40.0 and p.pv("landlord") == 0.0, "a King holds two Territory skills (has_passive / pv)")
	# war_chest (Vesper Nightcrown: Shadow Ledger + war chest 60)
	var c := _match("nocthyr", "aetherion")
	check(c.players[0].gold == GameData.gold_for("normal") + 60, "War Chest: +60 G at the start (%d)" % c.players[0].gold)
	# interest (Aurelian: Dawn Tithe + 3% interest)
	c = _match("solvaris", "aetherion")
	var sp := c.players[0]
	sp.gold = 2000
	var royal := int((int(GameData.b("start_bonus")) + WorldMods.start_bonus_extra) * 1.25)
	c._give_start_bonus(sp)
	check(sp.gold == 2000 + royal + 60, "Interest: START pays 3%% of the gold in hand (%d)" % (sp.gold - 2000 - royal))
	sp.gold = 100000
	c._give_start_bonus(sp)
	check(sp.gold == 100000 + royal + int(GameData.b("interest_cap", 120)), "Interest is capped")
	# tax_cut / rent_cut (Cryndel: Mender + 10% less Tax; Verdantia: Mender + 10% less rent)
	c = _match("cryndel", "arcanum")
	check(c._apply_tax_passive(c.players[0], 100) == 90 and c._apply_tax_passive(c.players[0], 100, true) == 100, "Tax Cut: only Tax is cheaper, rent is not")
	c = _match("verdantia", "sylvaris")
	check(c._apply_tax_passive(c.players[0], 100) == 100 and c._apply_tax_passive(c.players[0], 100, true) == 90, "Rent Cut: only rent is cheaper, Tax is not")
	c = _match("nocthyr", "aetherion")
	check(c._apply_tax_passive(c.players[0], 100) == 65 and c._apply_tax_passive(c.players[0], 100, true) == 65, "Shadow Ledger still cuts both (35%)")
	# upgrader (Valdoria: Landlord + 15% cheaper upgrades)
	c = _match("valdoria", "aetherion")
	var up := c.players[0]
	up.gold = 5000
	var tile: BoardTile = null
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY:
			tile = t
			break
	tile.owner_id = up.id
	tile.level = 0
	tile.lease_left = 0
	var full := EconomySystem.upgrade_cost(tile)
	c._resolve_territory(up, tile)
	var cheap := int(c.pending.get("price", -1))
	check(cheap < full and cheap >= int(full * 0.8) - 5, "Upgrader: upgrades are cheaper (%d vs %d)" % [cheap, full])
	# a human King below B3 has neither of his Territory skills
	var h := MatchController.new()
	h.setup({"continent_id": "aetherion", "faction_id": "nocthyr", "difficulty": "normal", "ai_count": 1, "seed": 9, "king_b": 1})
	check(h.players[0].passive == "" and h.players[0].passive2 == "" and h.players[0].gold == GameData.gold_for("normal"), "below B3 neither Territory skill is active")
	# save / resume keeps the second skill
	var c2 := _match("tempestra", "thalassia")
	var back := MatchController.from_dict(c2.to_dict())
	check(back.players[0].passive2 == "toll_keeper" and back.players[0].passive2_value == 0.10, "the second Territory skill survives save / resume")
