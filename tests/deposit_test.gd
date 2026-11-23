extends Node
## Hidden territory deposits (treasures + mines): per-continent data, random hidden placement, finding by landing,
## one-time treasures, mines paying every round, save / resume and full AI games.
## Run: godot --headless --path . res://tests/deposit_test.tscn

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


## First deposit entry of the given kind in a match.
func _entry(c: MatchController, kind: String, nth: int = 0) -> Dictionary:
	var n := 0
	for e in c.deposits:
		if String(GameData.get_deposit(String(e["id"]))["kind"]) == kind:
			if n == nth:
				return e
			n += 1
	return {}


func _ready() -> void:
	_test_data()
	_test_placement()
	_test_hidden()
	_test_treasure()
	_test_mine()
	_test_save_resume()
	_test_full_games()
	print("DEPOSIT TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_data() -> void:
	var ok := true
	var names := {}
	var sigs := {}
	for cid in CONTS:
		var list := GameData.get_deposits(cid)
		ok = ok and list.size() == 4
		var tre := 0
		var mines := 0
		var sig := ""
		for d in list:
			ok = ok and not names.has(d["id"]) and not names.has(d["name"]) and String(d["lore"]) != ""
			names[d["id"]] = true
			names[d["name"]] = true
			if String(d["kind"]) == "treasure":
				tre += 1
				ok = ok and int(d["gold"]) > 0
				sig += "T%d/%d/%s;" % [int(d["gold"]), int(d["tokens"]), str(d["die"])]
			else:
				mines += 1
				ok = ok and int(d["income"]) > 0 and int(d["rounds"]) > 0
				sig += "M%d/%d/%d;" % [int(d["income"]), int(d["rounds"]), int(d["token_every"])]
		ok = ok and tre == 2 and mines == 2
		sigs[sig] = true
	check(ok, "7 continents x (2 treasures + 2 mines), valid values, unique ids and names (28 deposits)")
	check(sigs.size() == 7, "every continent has different rewards (no two continents share the same numbers)")
	check(GameData.get_deposit("dragons_hoard").get("name", "") == "Dragon's Hoard", "get_deposit finds a deposit by id")


func _test_placement() -> void:
	var ok := true
	for cid in CONTS:
		var c := _new_match(cid, 5)
		ok = ok and c.deposits.size() == 4
		var seen := {}
		var lairs: Array = c.monsters.map(func(e): return int(e["tile"]))
		for e in c.deposits:
			var t: BoardTile = c.tiles[int(e["tile"])]
			ok = ok and t.type == BoardTile.Type.TERRITORY and not seen.has(t.index) and not lairs.has(t.index)
			ok = ok and not bool(e["taken"]) and int(e["owner"]) == -1
			seen[t.index] = true
	check(ok, "4 deposits per match on 4 different territory tiles, never on a monster lair")
	var a := _new_match("machina", 77)
	var b := _new_match("machina", 77)
	check(a.deposits == b.deposits, "same seed -> same deposit spots")
	var regions := {}
	var variants := {}
	for s in range(1, 25):
		var c2 := _new_match("aetherion", s)
		variants[str(c2.deposits.map(func(e): return e["tile"]))] = true
		for e in c2.deposits:
			regions[c2.tiles[int(e["tile"])].region] = true
	check(variants.size() > 12, "spots change from match to match (%d layouts in 24 seeds)" % variants.size())
	check(regions.size() == 4, "deposits can lie in every region of the board")
	var with_off := MatchController.new()
	with_off.setup({"continent_id": "aetherion", "faction_id": "x", "difficulty": "normal", "ai_count": 3, "seed": 9, "all_ai": true, "deposits": false})
	check(with_off.deposits.is_empty(), "cfg deposits=false gives a match without deposits")
	var t := MatchController.new()
	t.setup({"continent_id": "aetherion", "faction_id": "x", "difficulty": "normal", "ai_count": 1, "seed": 9, "tutorial": true})
	check(t.deposits.is_empty(), "the guided tutorial match has no deposits")
	# the deposit generator must not disturb the main stream: monsters stay exactly as in a match with deposits off
	check(a.monsters == _new_match_no_dep("machina", 77).monsters, "deposits do not change the monster lairs or the main rng stream")


func _new_match_no_dep(cid: String, seed_v: int) -> MatchController:
	var c := MatchController.new()
	c.setup({"continent_id": cid, "faction_id": GameData.get_continent(cid)["factions"][0]["id"], "difficulty": "normal", "ai_count": 3, "seed": seed_v, "all_ai": true, "deposits": false})
	return c


func _test_hidden() -> void:
	var c := _new_match("sylvaris", 3)
	var leak := false
	for i in range(c.tiles.size()):
		var txt := c.describe_tile(i).to_lower()
		for e in c.deposits:
			if txt.contains(String(GameData.get_deposit(String(e["id"]))["name"]).to_lower()) or txt.contains("treasure") or txt.contains(" mine"):
				leak = true
	check(not leak, "tile descriptions never reveal a treasure or mine (not shown on the map)")


func _test_treasure() -> void:
	var c := _new_match("aetherion", 11)
	var e := _entry(c, "treasure", 1)  # Crown Jeweler's Cache: gold + 1 Reroll Token
	var d := GameData.get_deposit(String(e["id"]))
	var p: PlayerState = c.players[0]
	var gold := p.gold
	var tokens := p.reroll_tokens
	_land(c, 0, int(e["tile"]))
	check(p.gold >= gold + int(d["gold"]) and bool(e["taken"]), "landing on a treasure pays its gold and removes it")
	check(p.reroll_tokens == tokens + int(d["tokens"]), "a treasure can give Reroll Tokens")
	check(int(c.stats["treasures_found"]) == 1, "treasure statistics are counted")
	check(String(c.pending.get("type", "")) == "buy", "after the find the territory is resolved as usual (buy offer)")
	# a second visitor finds nothing
	var g1 := c.players[1].gold
	c.pending = {}
	_land(c, 1, int(e["tile"]))
	check(c.players[1].gold == g1 and int(c.stats["treasures_found"]) == 1, "a found treasure is gone for everyone else")
	# special die treasure
	var c2 := _new_match("arcanum", 4)
	var e2 := _entry(c2, "treasure", 0)  # Forgotten Grimoire Vault: gold + Special Die
	var dice := c2.players[0].special_dice.size()
	_land(c2, 0, int(e2["tile"]))
	check(c2.players[0].special_dice.size() == dice + 1, "a treasure can give a Special Die")
	# a full dice bag still collects the gold (no die lost, no crash)
	var c3 := _new_match("arcanum", 4)
	var e3 := _entry(c3, "treasure", 0)
	while c3.players[0].special_dice.size() < int(GameData.b("max_special_dice")):
		c3.players[0].special_dice.append("swift")
	var g3 := c3.players[0].gold
	_land(c3, 0, int(e3["tile"]))
	check(c3.players[0].gold > g3 and c3.players[0].special_dice.size() == int(GameData.b("max_special_dice")), "full dice bag: gold still paid, no extra die")


func _test_mine() -> void:
	var c := _new_match("machina", 8)
	var e := _entry(c, "mine", 1)  # Voltaic Ore Pit: 40 G x 8 rounds
	var d := GameData.get_deposit(String(e["id"]))
	var p: PlayerState = c.players[2]
	_land(c, 2, int(e["tile"]))
	check(bool(e["taken"]) and int(e["owner"]) == 2 and int(e["left"]) == int(d["rounds"]), "landing on a mine claims it for the finder")
	check(int(c.stats["mines_found"]) == 1, "mine statistics are counted")
	check(DepositSystem.income_of(c.deposits, 2) == int(d["income"]) and DepositSystem.income_of(c.deposits, 0) == 0, "income_of reports only the owner's mines")
	# another ruler walking over it gets nothing
	c.pending = {}
	var g0 := c.players[0].gold
	_land(c, 0, int(e["tile"]))
	check(c.players[0].gold == g0 and int(e["owner"]) == 2, "other rulers cannot take a found mine")
	# pays every round
	c.pending = {}
	var gold := p.gold
	c._end_of_round()
	check(p.gold == gold + int(d["income"]) and int(e["left"]) == int(d["rounds"]) - 1, "a mine pays its owner at the end of every round")
	check(int(c.stats["mine_income"]) == int(d["income"]), "mine income is counted")
	# runs dry
	for i in range(int(d["rounds"]) + 3):
		c._end_of_round()
	check(int(e["left"]) == 0 and int(e["paid"]) == int(d["rounds"]), "the mine pays exactly `rounds` times and then runs dry")
	check(DepositSystem.mines_of(c.deposits, 2).is_empty(), "an exhausted mine is no longer listed")
	# token mine
	var c2 := _new_match("eclipsia", 8)
	var e2 := _entry(c2, "mine", 1)  # Echo Ore Lode: a Reroll Token every 4 payouts
	var d2 := GameData.get_deposit(String(e2["id"]))
	_land(c2, 1, int(e2["tile"]))
	var tokens := c2.players[1].reroll_tokens
	for i in range(int(d2["token_every"])):
		c2._end_of_round()
	check(c2.players[1].reroll_tokens == tokens + 1, "a token mine gives a Reroll Token every %d payouts" % int(d2["token_every"]))
	# dead owner: nothing paid
	var c3 := _new_match("drakmor", 8)
	var e3 := _entry(c3, "mine", 0)
	_land(c3, 1, int(e3["tile"]))
	c3.players[1].alive = false
	var gd := c3.players[1].gold
	c3._end_of_round()
	check(c3.players[1].gold == gd and int(e3["left"]) == int(GameData.get_deposit(String(e3["id"]))["rounds"]), "an eliminated ruler's mine pays nothing")


func _test_save_resume() -> void:
	var c := _new_match("thalassia", 23)
	_land(c, 1, int(_entry(c, "mine", 0)["tile"]))
	c.pending = {}
	c.state = MatchController.State.AWAIT_ROLL
	c._end_of_round()
	_land(c, 2, int(_entry(c, "treasure", 0)["tile"]))
	c.pending = {}
	c.state = MatchController.State.AWAIT_ROLL
	var d := c.to_dict()
	check(not d.is_empty(), "match is saveable")
	var back := MatchController.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(back.deposits == c.deposits, "deposits (spots, finders, rounds left) survive save / resume")
	check(DepositSystem.income_of(back.deposits, 1) == DepositSystem.income_of(c.deposits, 1), "a resumed match keeps paying the mine")
	var old_d := d.duplicate(true)
	old_d.erase("deposits")
	var old := MatchController.from_dict(JSON.parse_string(JSON.stringify(old_d)))
	check(old.deposits.is_empty(), "older saves without deposits still load")


func _test_full_games() -> void:
	var ok := true
	var finds := 0
	var mines := 0
	var income := 0
	for cid in CONTS:
		for s in range(1, 4):
			var c := _new_match(cid, s)
			var steps := 0
			while c.state != MatchController.State.GAME_OVER and steps < 30000:
				AIController.step(c)
				steps += 1
			ok = ok and c.state == MatchController.State.GAME_OVER
			for e in c.deposits:
				ok = ok and int(e["left"]) >= 0 and (not bool(e["taken"]) or int(e["owner"]) >= -1)
			finds += int(c.stats["treasures_found"])
			mines += int(c.stats["mines_found"])
			income += int(c.stats["mine_income"])
	check(ok, "21 full AI games finish with consistent deposits")
	check(finds > 0 and mines > 0 and income > 0, "AI players find treasures and mines and earn income (%d treasures, %d mines, %d G)" % [finds, mines, income])
