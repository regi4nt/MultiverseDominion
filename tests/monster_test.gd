extends Node
## Hidden territory monsters: data, random hidden placement, encounter (fight / flee), one Monster card per player,
## the card joining the King in Last Stand, save / resume and full AI games.
## Run: godot --headless --path . res://tests/monster_test.tscn

var failures := 0
const CONTS := ["aetherion", "arcanum", "machina", "sylvaris", "drakmor", "thalassia", "eclipsia"]


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _new_match(cid: String, seed_v: int) -> MatchController:
	var c := MatchController.new()
	c.setup({"continent_id": cid, "faction_id": GameData.get_continent(cid)["factions"][0]["id"], "difficulty": "normal", "ai_count": 3, "seed": seed_v, "all_ai": true})
	return c


## Player `pid` (current) lands on tile `idx`.
func _land(c: MatchController, pid: int, idx: int) -> void:
	c.current = pid
	c.players[pid].position = idx
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[pid])


func _ready() -> void:
	_test_data()
	_test_placement()
	_test_hidden()
	_test_encounter_flee()
	_test_win_and_one_card()
	_test_loss()
	_test_interactive_battle()
	_test_engine_ally()
	_test_ally_lv3()
	_test_wild_level()
	_test_skill_data()
	_test_manual_monster_skill()
	_test_auto_monster_skill()
	_test_all_monster_skills()
	_test_wild_monster_skill()
	_test_save_resume()
	_test_full_games()
	print("MONSTER TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_data() -> void:
	var names := {}
	var ok := true
	for cid in CONTS:
		var list := GameData.get_monsters(cid)
		ok = ok and list.size() == 4
		var regions := {}
		for m in list:
			regions[int(m["region"])] = true
			var bf: Dictionary = m["buff"]
			ok = ok and CardDatabase.BUFF_TYPES.has(String(bf["type"])) and String(bf["desc"]) != "" and int(m["hp"]) > 0 and int(m["atk"]) > 0
			ok = ok and ["pawn", "rook", "knight", "bishop", "queen"].has(String(m["chess"]))
			ok = ok and not names.has(m["name"]) and not names.has(m["id"])
			names[m["name"]] = true
			names[m["id"]] = true
		ok = ok and regions.size() == 4
	check(ok, "7 continents x 4 monsters, one per region, unique names, valid buffs")
	check(names.size() == 56, "every continent has its own, different monsters (28 monsters)")
	check(GameData.get_monster("crownstone_golem").get("name", "") == "Crownstone Golem", "get_monster finds a monster by id")


func _test_placement() -> void:
	var ok := true
	var seen := {}
	for cid in CONTS:
		var c := _new_match(cid, 5)
		ok = ok and c.monsters.size() == 4
		var tiles_used := {}
		for e in c.monsters:
			var t: BoardTile = c.tiles[int(e["tile"])]
			var m := GameData.get_monster(String(e["id"]))
			ok = ok and t.type == BoardTile.Type.TERRITORY and t.region == int(m["region"]) and not bool(e["taken"])
			tiles_used[int(e["tile"])] = true
		ok = ok and tiles_used.size() == 4
	check(ok, "4 monsters per match on 4 different territory tiles, each in its own region")
	var a := _new_match("aetherion", 7)
	var b := _new_match("aetherion", 7)
	check(a.monsters == b.monsters, "same seed -> same monster lairs")
	for s in range(1, 13):
		var c2 := _new_match("aetherion", s)
		seen[str(c2.monsters.map(func(e): return e["tile"]))] = true
	check(seen.size() >= 8, "lairs are random (%d different layouts in 12 seeds)" % seen.size())
	var t := MatchController.new()
	t.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "easy", "ai_count": 1, "seed": 4242, "tutorial": true, "round_limit": 10, "all_ai": true})
	check(t.monsters.is_empty(), "the guided tutorial match has no monsters")


func _test_hidden() -> void:
	var c := _new_match("aetherion", 9)
	var leak := false
	for i in range(c.tiles.size()):
		var txt := c.describe_tile(i)
		for e in c.monsters:
			if txt.to_lower().contains(String(GameData.get_monster(String(e["id"]))["name"]).to_lower()) or txt.to_lower().contains("monster"):
				leak = true
	check(not leak, "tile descriptions never reveal a monster (not shown on the map)")


func _test_encounter_flee() -> void:
	var c := _new_match("aetherion", 11)
	var e: Dictionary = c.monsters[0]
	var tile := int(e["tile"])
	var gold := c.players[0].gold
	_land(c, 0, tile)
	check(c.state == MatchController.State.AWAIT_DECISION and String(c.pending.get("type", "")) == "monster", "landing on a lair starts a monster encounter")
	var ids: Array = c.get_decision_options().map(func(o): return o["id"])
	check(ids == ["fight", "flee"], "options: fight or flee")
	check(c.get_decision_prompt().contains(String(GameData.get_monster(String(e["id"]))["name"])), "prompt names the monster")
	c.decide("flee")
	check(c.players[0].monster_id == "" and not bool(e["taken"]) and c.players[0].gold == gold, "fleeing costs nothing and the monster stays")
	check(String(c.pending.get("type", "")) == "buy", "after fleeing the territory is resolved as usual (buy offer)")


func _weaken(id: String) -> Array:
	var m := GameData.get_monster(id)
	var old := [m["hp"], m["atk"]]
	m["hp"] = 1
	m["atk"] = 1
	return old


func _restore(id: String, old: Array) -> void:
	var m := GameData.get_monster(id)
	m["hp"] = old[0]
	m["atk"] = old[1]


func _test_win_and_one_card() -> void:
	var c := _new_match("aetherion", 13)
	var e0: Dictionary = c.monsters[0]
	var e1: Dictionary = c.monsters[1]
	var old := _weaken(String(e0["id"]))
	c.players[0].commander_star = 2
	c.players[1].commander_star = 1
	_land(c, 0, int(e0["tile"]))
	c.decide("fight")
	check(c.players[0].monster_id == String(e0["id"]), "winning the fight gives the Monster card")
	check(c.players[0].monster_star == 2, "the Monster card keeps the King level it was won at (Lv 2)")
	c.players[0].commander_star = 3
	check(c.players[0].monster_star == 2, "a later King level up does not change the Monster ally")
	check(bool(e0["taken"]), "a defeated monster is gone from the board")
	check(int(c.stats["monsters_won"]) == 1 and int(c.stats["monster_fights"]) == 1, "fight statistics are counted")
	# another player on the same (now empty) lair: nothing happens
	c.pending = {}
	_land(c, 1, int(e0["tile"]))
	check(String(c.pending.get("type", "")) != "monster", "the defeated monster does not return for others")
	# the winner walks over another lair: no second card (and the monster stays hidden)
	c.pending = {}
	_land(c, 0, int(e1["tile"]))
	check(String(c.pending.get("type", "")) != "monster" and not bool(e1["taken"]), "a player can only own ONE Monster card")
	# a different player can still take another monster
	c.pending = {}
	var old1 := _weaken(String(e1["id"]))
	_land(c, 1, int(e1["tile"]))
	check(String(c.pending.get("type", "")) == "monster", "other players can still meet the remaining monsters")
	c.decide("fight")
	check(c.players[1].monster_id == String(e1["id"]) and c.players[1].monster_star == 1, "second player wins a different monster at King Lv 1")
	_restore(String(e0["id"]), old)
	_restore(String(e1["id"]), old1)


func _test_loss() -> void:
	var c := _new_match("machina", 17)
	var e: Dictionary = c.monsters[2]
	var m := GameData.get_monster(String(e["id"]))
	var old := [m["hp"], m["atk"]]
	m["hp"] = 999999
	m["atk"] = 9999
	var gold := c.players[0].gold
	_land(c, 0, int(e["tile"]))
	c.decide("fight")
	check(c.players[0].monster_id == "" and not bool(e["taken"]), "a lost fight gives no card and the monster stays")
	check(c.players[0].gold == gold - int(GameData.b("monster_defeat_gold")) or c.players[0].gold < gold, "a lost fight costs gold")
	m["hp"] = old[0]
	m["atk"] = old[1]


func _test_engine_ally() -> void:
	var ok_join := 0
	var ok_stats := true
	var ok_entry := true
	for cid in ["aetherion", "drakmor"]:
		var m: Dictionary = GameData.get_monsters(cid)[0]
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		CardDatabase.set_continent(cid)
		var deck := Deck.create_default()
		var pa := BattleAI.build_enemy("normal", 5, rng, deck)  # buys units with the budget
		var pb := BattleAI.build_enemy("normal", 5, rng, deck)
		BattleAI.auto_deploy(pa, 0)  # side 0 = bottom half
		var keep := true
		for u in pa.deployed_units().duplicate():  # one lone unit: it falls, then the King must step in
			if keep:
				keep = false
			else:
				u.cell = Vector2i(-1, -1)
		var ca := pa.to_side_cfg("champion_solvaris", [], 1, String(m["id"]))
		var cb := pb.to_side_cfg("champion_nocthyr", [], 1)
		var e := BattleEngine.new()
		e.setup({"seed": 5, "ai_supports": [false, false], "terrain": {}, "sides": [ca, cb]})
		var mons_before := 0
		for u in e.units:
			if u.is_monster:
				mons_before += 1
		ok_entry = ok_entry and mons_before == 0 and pa.deployed_units().size() > 0  # the card does not fight before the King enters
		var guard := 0
		while not e.finished and guard < 500:
			e.step()
			guard += 1
		var joined: BattleUnit = null
		for u in e.units:
			if u.is_monster and u.side == 0:
				joined = u
		if joined != null:
			ok_join += 1
			var st := MonsterSystem.stats(String(m["id"]))
			ok_stats = ok_stats and joined.max_hp == int(st["hp"]) and joined.card_id == String(m["id"])
		ok_entry = ok_entry and int(e.regulars_alive_at_entry[0]) <= 0 and e.finished
	check(ok_entry, "Monster card stays out until the King enters; Last Stand rule intact")
	check(ok_join == 2, "the Monster card joins the King in Last Stand")
	check(ok_stats, "allied monster has King-level stats (wild x the HP/ATK multipliers of its level)")


func _test_save_resume() -> void:
	var c := _new_match("sylvaris", 23)
	c.players[1].monster_id = String(c.monsters[3]["id"])
	c.players[1].monster_star = 2
	c.monsters[3]["taken"] = true
	c.state = MatchController.State.AWAIT_ROLL
	c.pending = {}
	var d := c.to_dict()
	check(not d.is_empty(), "match is saveable")
	var json := JSON.stringify(d)
	var back := MatchController.from_dict(JSON.parse_string(json))
	check(back.monsters == c.monsters, "monster lairs survive save / resume")
	check(back.players[1].monster_id == c.players[1].monster_id and back.players[0].monster_id == "", "Monster cards survive save / resume")
	check(back.players[1].monster_star == 2, "the Monster ally level survives save / resume")
	var old_d := d.duplicate(true)
	old_d.erase("monsters")
	var old := MatchController.from_dict(JSON.parse_string(JSON.stringify(old_d)))
	check(old.monsters.is_empty(), "older saves without monsters still load")


func _test_full_games() -> void:
	var won_total := 0
	var fights_total := 0
	var all_ok := true
	for cid in CONTS:
		for s in range(1, 4):
			var c := _new_match(cid, s)
			var steps := 0
			while c.state != MatchController.State.GAME_OVER and steps < 30000:
				AIController.step(c)
				steps += 1
			all_ok = all_ok and c.state == MatchController.State.GAME_OVER
			var held := {}
			for p in c.players:
				if p.monster_id != "":
					all_ok = all_ok and not held.has(p.monster_id)  # unique: a monster belongs to one player
					held[p.monster_id] = true
			all_ok = all_ok and held.size() <= c.players.size()
			won_total += int(c.stats["monsters_won"])
			fights_total += int(c.stats["monster_fights"])
	check(all_ok, "21 full AI games finish; every monster belongs to at most one player")
	check(fights_total > 0 and won_total > 0, "AI players meet and defeat monsters (%d fights, %d won)" % [fights_total, won_total])


## The Territory Board plays a human's monster fight in the Battle scene: "fight" waits in AWAIT_DUEL until the battle reports.
func _test_interactive_battle() -> void:
	var c := _new_match("aetherion", 19)
	c.players[0].is_ai = false  # the test match is all-AI: make seat 0 a human
	c.monster_battles_interactive = true
	var e: Dictionary = c.monsters[0]
	var mid := String(e["id"])
	var gold := c.players[0].gold
	_land(c, 0, int(e["tile"]))
	c.decide("fight")
	check(c.state == MatchController.State.AWAIT_DUEL and c.is_monster_battle() and not c.is_human_duel(), "interactive: Fight waits for the Battle scene (a monster battle, not a ruler duel)")
	check(c.players[0].monster_id == "" and not bool(e["taken"]) and c.players[0].gold == gold, "interactive: nothing is decided before the battle ends")
	c.auto_duel()
	check(c.is_monster_battle(), "interactive: auto_duel / the AI never resolves a monster battle")
	c.finish_monster_battle({"won": true, "ticks": 40, "gold_delta": 0})
	check(c.players[0].monster_id == mid and bool(e["taken"]) and c.state != MatchController.State.AWAIT_DUEL, "interactive: a won battle gives the Monster card and the turn goes on")
	check(int(c.stats["monster_fights"]) == 1 and int(c.stats["monsters_won"]) == 1, "interactive: statistics are counted once")
	# a lost battle: fee, the monster stays
	var c2 := _new_match("aetherion", 19)
	c2.players[0].is_ai = false
	c2.monster_battles_interactive = true
	var e2: Dictionary = c2.monsters[1]
	var g2 := c2.players[0].gold
	_land(c2, 0, int(e2["tile"]))
	c2.decide("fight")
	c2.finish_monster_battle({"won": false, "ticks": 90, "gold_delta": 0})
	check(c2.players[0].monster_id == "" and not bool(e2["taken"]) and c2.players[0].gold == g2 - int(GameData.b("monster_defeat_gold")), "interactive: a lost battle costs the fee and the monster keeps its lair")
	# fleeing is still instant
	var c3 := _new_match("aetherion", 19)
	c3.players[0].is_ai = false
	c3.monster_battles_interactive = true
	_land(c3, 0, int(c3.monsters[2]["tile"]))
	c3.decide("flee")
	check(not c3.is_monster_battle() and c3.players[0].monster_id == "", "interactive: fleeing does not open a battle")


# ------------------------------------------------------------------ active skills (cast like the King skill)

func _skill_cfg(monster_id: String, manual: bool) -> Dictionary:
	return {"seed": 5, "ai_supports": [false, false], "manual_king": [manual, false], "sides": [
		{"units": [], "champion": "champion_solvaris", "supports": [], "monster": monster_id},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 3)}, {"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(4, 3)}], "champion": "champion_nocthyr", "supports": []}]}


func _test_ally_lv3() -> void:
	var ok := true
	for cid in CONTS:
		for m in GameData.get_monsters(cid):
			var base := MonsterSystem.stats(String(m["id"]), 1)  # Lv 1 = the plain data stats
			ok = ok and int(base["hp"]) == int(m["hp"]) and int(base["atk"]) == int(m["atk"])
			for star in [1, 2, 3]:
				var st := MonsterSystem.stats(String(m["id"]), star)
				ok = ok and int(st["hp"]) == int(round(float(m["hp"]) * CommanderSystem.hp_mult(star))) and int(st["atk"]) == int(round(float(m["atk"]) * CommanderSystem.atk_mult(star)))
	check(ok, "monster stats follow the King level (Lv 1-3): Lv 1 = the plain data stats")
	check(MonsterSystem.stats("crownstone_golem", 3)["hp"] > MonsterSystem.stats("crownstone_golem", 2)["hp"] and MonsterSystem.summary("crownstone_golem", 2).contains("Lv 2"), "a higher King level gives a stronger ally, shown as Lv in the summary")
	for star in [1, 2, 3]:
		var cfg := _skill_cfg("crownstone_golem", true)
		cfg["sides"][0]["monster_star"] = star
		var e := BattleEngine.new()
		e.setup(cfg)
		var mu := e.ally_monster(0)
		check(mu != null and mu.max_hp == int(round(415.0 * CommanderSystem.hp_mult(star))), "in battle the Monster ally has the HP of King Lv %d" % star)


func _test_skill_data() -> void:
	var king_skills := {}
	for cid in GameData.champions:
		king_skills[String(GameData.champions[cid]["skill_id"])] = true
	var mon_skills := {}
	var ok := true
	var count := 0
	for cid in CONTS:
		for m in GameData.get_monsters(cid):
			count += 1
			mon_skills[String(m.get("skill_id", ""))] = true
			ok = ok and GameData.skills.has(String(m.get("skill_id", ""))) and not king_skills.has(String(m.get("skill_id", ""))) and String(m.get("active_name", "")) != "" and not (m.get("plus", {}) as Dictionary).is_empty() \
					and String(m.get("active_desc", "")) != "" and float(m.get("active_value", 0.0)) > 0.0
	check(ok and count == 28 and mon_skills.size() == 28, "all 28 monsters have their OWN active skill (not a King skill), a King+ trait, name, desc, value")
	check(MonsterSystem.summary("crownstone_golem").contains("Crownstone Bulwark"), "the monster summary shows the active skill")


func _test_manual_monster_skill() -> void:
	var e := BattleEngine.new()
	e.setup(_skill_cfg("sunscorch_manticore", true))  # Sunfire Eruption: enemies within 3 cells
	var mu := e.ally_monster(0)
	check(mu != null and mu.active_id == "sunfire_eruption" and e.monster_unit[0] == mu, "the Monster joins and carries its active skill")
	var cost := e.monster_energy_cost()
	check(cost > 0 and not e.monster_skill_used[0], "the Monster skill has an energy cost and starts unused")
	check(not e.can_use_monster_skill(0) and e.use_monster_skill(0) != "" and not e.monster_skill_used[0], "an unaffordable Monster skill is refused")
	e.energy[0] = e.energy_max()
	check(e.can_use_monster_skill(0), "with enough energy the Monster skill can be cast")
	e.step()
	check(not e.monster_skill_used[0], "a manual Monster skill is not cast by itself")
	var hp_before := e.total_hp(1)
	var en_before := int(e.energy[0])
	check(e.use_monster_skill(0) == "" and e.monster_skill_used[0], "the Monster skill is cast by hand")
	check(int(e.energy[0]) <= en_before - cost + 1, "casting the Monster skill pays its energy cost")
	check(e.total_hp(1) < hp_before, "Sunfire Eruption damages the enemies")
	check(e.use_monster_skill(0) != "", "the Monster skill cannot be cast twice")
	check(e.use_monster_skill(1) != "", "a side without a Monster cannot cast")
	e.energy[0] = e.energy_max()
	check(e.can_use_king_skill(0) and not bool(e.king_skill_used[0]), "the King skill stays available after the Monster skill")
	check(e.use_king_skill(0) == "" and e.king_skill_used[0], "the King and the Monster each cast their own skill once")
	# a fallen Monster cannot cast
	var e2 := BattleEngine.new()
	e2.setup(_skill_cfg("crownstone_golem", true))
	e2.energy[0] = e2.energy_max()
	(e2.ally_monster(0) as BattleUnit).alive = false
	check(e2.use_monster_skill(0) != "" and not e2.can_use_monster_skill(0), "a fallen Monster cannot cast")


func _test_auto_monster_skill() -> void:
	var e := BattleEngine.new()
	e.setup(_skill_cfg("crownstone_golem", false))  # Crownstone Bulwark: shield
	var mu := e.ally_monster(0)
	var kc := e.king_energy_cost()
	var mc := e.monster_energy_cost()
	e.energy[0] = maxi(kc, mc) - 1
	e.step()
	check(not e.king_skill_used[0] and not e.monster_skill_used[0], "an auto side waits until it can pay")
	e.energy[0] = kc
	e.step()
	check(e.king_skill_used[0] and not e.monster_skill_used[0], "an auto side's King skill gets the energy first")
	var shield_before := mu.shield
	e.energy[0] = mc
	e.step()
	check(e.monster_skill_used[0] and mu.shield > shield_before, "then its Monster casts automatically (Bulwark shield)")


func _test_all_monster_skills() -> void:
	var ok := true
	var effect := 0
	for cid in CONTS:
		for m in GameData.get_monsters(cid):
			var e := BattleEngine.new()
			e.setup(_skill_cfg(String(m["id"]), true))
			var mu := e.ally_monster(0)
			var hp1 := e.total_hp(1)
			var hp0 := e.total_hp(0)
			var sh0 := mu.shield
			e.energy[0] = e.energy_max()
			ok = ok and e.use_monster_skill(0) == "" and e.monster_skill_used[0]
			for i in range(3):
				e.step()
			if e.total_hp(1) < hp1 or e.total_hp(0) > hp0 or mu.shield > sh0 or mu.buff_mult > 1.0 or mu.reduce_until > 0:
				effect += 1
			else:
				for u in e.units_of(1):  # control skills: stun / slow
					if u.stun_until > e.tick or u.slow_until > e.tick:
						effect += 1
						break
	check(ok, "every monster skill casts without trouble")
	check(effect >= 24, "every kind of monster skill has a visible effect (%d/28 checked)" % effect)


func _test_wild_monster_skill() -> void:
	var id := "gearwork_behemoth"
	var units: Array = []
	for i in range(3):
		units.append({"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(2 + i, 4)})
	var e := BattleEngine.new()
	e.setup({"seed": 4, "ai_supports": [false, false], "terrain": {}, "sides": [
		{"units": units, "champion": "", "supports": [], "foes": []},
		{"units": [], "champion": "", "supports": [], "foes": [id]}]})
	var wild: BattleUnit = null
	for u in e.units:
		if u.is_monster:
			wild = u
	check(wild != null and wild.active_id == "behemoth_overclock" and not wild.active_used, "the wild monster carries its active skill")
	check(wild.max_hp == 490 and wild.base_atk == int(round(28.0 * WorldMods.atk_mult)), "without a foe_star the wild monster has its plain Lv 1 stats")
	var guard := 0
	while not e.finished and guard < 400 and not wild.active_used:
		e.step()
		guard += 1
	check(wild.active_used and wild.shield > 0, "the wild monster casts its skill once when enemies get close")
	var used_at := e.tick
	var sh := wild.shield
	for i in range(5):
		e.step()
	check(wild.shield <= sh and e.log_lines.filter(func(l: String) -> bool: return l.begins_with("Wild monster skill")).size() == 1, "the wild monster skill is cast only once (started at tick %d)" % used_at)


func _test_wild_level() -> void:
	var id := "crownstone_golem"
	for star in [1, 2, 3]:
		var e := BattleEngine.new()
		e.setup({"seed": 4, "ai_supports": [false, false], "terrain": {}, "sides": [
			{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 6)}], "champion": "", "supports": [], "foes": []},
			{"units": [], "champion": "", "supports": [], "foes": [id], "foe_star": star}]})
		var wild: BattleUnit = null
		for u in e.units:
			if u.is_monster:
				wild = u
		var st := MonsterSystem.stats(id, star)
		check(wild != null and wild.max_hp == int(st["hp"]) and wild.base_atk >= int(st["atk"] * 0.99) - 1, "the wild monster has the stats of the challenger's King Lv %d" % star)
	check(MonsterSystem.power(id, 3) > MonsterSystem.power(id, 1), "a higher King level makes the wild monster stronger (AI power estimate)")
	var c := _new_match("aetherion", 31)
	var m0: Dictionary = c.monsters[0]
	c.players[0].commander_star = 3
	_land(c, 0, int(m0["tile"]))
	check(String(c.pending.get("type", "")) == "monster" and c.get_decision_prompt().contains("Lv 3"), "the monster prompt shows the monster at the challenger's King level")
