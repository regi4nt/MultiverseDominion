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
	_test_engine_ally()
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
	_land(c, 0, int(e0["tile"]))
	c.decide("fight")
	check(c.players[0].monster_id == String(e0["id"]), "winning the fight gives the Monster card")
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
	check(c.players[1].monster_id == String(e1["id"]), "second player wins a different monster")
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
			var st := MonsterSystem.stats(String(m["id"]), true)
			ok_stats = ok_stats and joined.max_hp == int(st["hp"]) and joined.card_id == String(m["id"])
		ok_entry = ok_entry and int(e.regulars_alive_at_entry[0]) <= 0 and e.finished
	check(ok_entry, "Monster card stays out until the King enters; Last Stand rule intact")
	check(ok_join == 2, "the Monster card joins the King in Last Stand")
	check(ok_stats, "allied monster has tamed stats (x monster_ally_stat_mult)")


func _test_save_resume() -> void:
	var c := _new_match("sylvaris", 23)
	c.players[1].monster_id = String(c.monsters[3]["id"])
	c.monsters[3]["taken"] = true
	c.state = MatchController.State.AWAIT_ROLL
	c.pending = {}
	var d := c.to_dict()
	check(not d.is_empty(), "match is saveable")
	var json := JSON.stringify(d)
	var back := MatchController.from_dict(JSON.parse_string(json))
	check(back.monsters == c.monsters, "monster lairs survive save / resume")
	check(back.players[1].monster_id == c.players[1].monster_id and back.players[0].monster_id == "", "Monster cards survive save / resume")
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
