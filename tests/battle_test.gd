extends Node
## Headless test for Phase 4. Run: godot --headless --path . res://tests/battle_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func make_cfg(seed_v: int, diff: String, level: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var deck := Deck.create_default()
	var pa := BattleAI.build_enemy(diff, level, rng, deck)
	var pb := BattleAI.build_enemy(diff, level, rng, deck)
	# pa plays as side 0: mirror its cells from rows 3..0 to 4..7
	for u in pa.roster.units:
		if u.cell.x >= 0:
			u.cell = Vector2i(u.cell.x, 7 - u.cell.y)
	var champs := ["champion_solvaris", "champion_nocthyr"]
	return {"seed": seed_v, "ai_supports": [true, true], "sides": [
		pa.to_side_cfg(champs[seed_v % 2], BattleAI.pick_hand(deck, rng, 3)),
		pb.to_side_cfg(champs[(seed_v + 1) % 2], BattleAI.pick_hand(deck, rng, 3))]}


func _ready() -> void:
	_test_prep()
	_test_support()
	_test_last_stand_empty()
	_test_battles()
	print("BATTLE TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_prep() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var prep := BattlePrep.new(Deck.create_default(), rng, 500, 300, 3)
	check(prep.offers.size() == 5, "shop shows 5 offers")
	check(prep.buy(0) == "", "buy first offer")
	check(prep.gold < 500 and prep.budget_left < 300, "gold and budget are spent")
	check(prep.bench_units().size() == 1, "bought unit is on the bench")
	var u := prep.bench_units()[0]
	check(prep.deploy(u, Vector2i(3, 3)) != "", "cannot deploy outside own 4x8 area (row 3)")
	check(prep.deploy(u, Vector2i(3, 4)) == "", "deploy inside area")
	check(prep.deployed_units().size() == 1 and prep.bench_units().size() == 0, "unit moved bench -> board")
	check(prep.return_to_bench(u) == "" and prep.bench_units().size() == 1, "return unit to bench")
	# capacity: fill with queens-cost units via direct roster manipulation
	var p2 := BattlePrep.new(Deck.create_default(), rng, 9999, 9999, 3)
	for i in range(3):
		var q := UnitInstance.new("queen_aurelia")  # cost 4
		p2.roster.units.append(q)
	check(p2.deploy(p2.roster.units[0], Vector2i(0, 4)) == "", "queen #1 fits (4/9)")
	check(p2.deploy(p2.roster.units[1], Vector2i(1, 4)) == "", "queen #2 fits (8/9)")
	check(p2.deploy(p2.roster.units[2], Vector2i(2, 4)) != "", "queen #3 exceeds capacity 9")
	p2.level = 4
	check(p2.deploy(p2.roster.units[2], Vector2i(2, 4)) == "", "level 4 raises capacity to 12")
	check(p2.level_up() == "" and p2.level == 5 and p2.capacity() == 15, "level up -> capacity 15")
	# budget cap
	var p3 := BattlePrep.new(Deck.create_default(), rng, 1000, 40, 3)
	var bought := 0
	for i in range(5):
		if p3.buy(i) == "":
			bought += 1
	check(p3.budget_left >= 0 and p3.gold >= 960, "battle budget (40) caps spending")
	# sell returns cards to the pile: pool + offers + owned copies must always be 135
	var p4 := BattlePrep.new(Deck.create_default(), rng, 9999, 9999, 3)
	p4.buy(0)
	p4.buy(1)
	check(_card_total(p4) == 135, "after buying: pool + offers + owned = 135")
	var pool_before := p4.battle_deck.remaining()
	p4.sell(p4.roster.units[0])
	check(p4.battle_deck.remaining() == pool_before + 1 and _card_total(p4) == 135, "sold card returns to the draw pile")
	# bench limit 10 (merge-purchases are still allowed when full)
	var p5 := BattlePrep.new(Deck.create_default(), rng, 99999, 99999, 3)
	var ids: Array[String] = []
	for cu in CardDatabase.all_units():
		ids.append(cu["id"])
	for i in range(10):
		p5.roster.units.append(UnitInstance.new(ids[i]))
	p5.offers = [ids[10], ids[0], "", "", ""]
	check(p5.can_buy(0) != "", "bench full: new unit type cannot be bought")
	check(p5.can_buy(1) != "", "bench full: 2nd copy (no merge) cannot be bought")
	p5.roster.units.append(UnitInstance.new(ids[0]))
	p5.roster.units.pop_back()
	p5.roster.units[1] = UnitInstance.new(ids[0])  # now 2 copies of ids[0] on the bench
	check(p5.can_buy(1) == "", "bench full: purchase that completes a merge is allowed")


func _card_total(p: BattlePrep) -> int:
	var n := p.battle_deck.remaining()
	for o in p.offers:
		if o != "":
			n += 1
	for u in p.roster.units:
		n += UnitRoster.copies_value(u.stars)
	return n


func _test_support() -> void:
	var cfg := make_cfg(11, "normal", 4)
	cfg["ai_supports"] = [false, false]
	cfg["sides"][0]["supports"] = ["sup_fireball", "sup_mercenary_pact", "sup_battle_cry"]
	var e := BattleEngine.new()
	e.setup(cfg)
	var hp_before := e.total_hp(1)
	check(e.use_support(0, "sup_fireball") == "", "Fireball can be played")
	check(e.total_hp(1) < hp_before, "Fireball damaged enemies")
	check(e.use_support(0, "sup_fireball") != "", "support card is single-use")
	check(e.use_support(0, "sup_mercenary_pact") != "", "a preparation-time card cannot be played in battle")
	check(e.use_support(0, "sup_summon_recruits") != "", "card not in hand is refused")
	var n := e.regulars_alive(0)
	cfg["sides"][0]["supports"] = ["sup_summon_recruits"]
	var e2 := BattleEngine.new()
	e2.setup(cfg)
	var n2 := e2.regulars_alive(0)
	check(e2.use_support(0, "sup_summon_recruits") == "" and e2.regulars_alive(0) == n2 + 2, "Summon Recruits adds 2 pawns")


func _test_last_stand_empty() -> void:
	var e := BattleEngine.new()
	e.setup({"seed": 5, "ai_supports": [false, false], "sides": [
		{"units": [], "champion": "champion_valdoria", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 3)}], "champion": "champion_elarion", "supports": []}]})
	check(e.king_entered[0] and e.king_entry_tick[0] == 0, "side without units: Champion enters immediately")
	check(not e.king_entered[1], "side with units: Champion waits")
	var steps := 0
	while not e.finished and steps < 500:
		e.step()
		steps += 1
	check(e.finished, "lone Champion vs 1 pawn battle finishes")
	check(e.king_entry_tick[1] == -1 or e.regulars_alive_at_entry[1] == 0, "enemy Champion only entered after its pawn fell")


func _test_battles() -> void:
	var finished_all := true
	var champion_rule := true
	var grid_ok := true
	var results := {0: 0, 1: 0, -1: 0}
	var longest := 0
	for diff in ["easy", "normal", "hard"]:
		for s in range(1, 31):
			var e := BattleEngine.new()
			e.setup(make_cfg(s, diff, 3 + (s % 4)))
			var guard := 0
			while not e.finished and guard < 1000:
				e.step()
				guard += 1
				# invariants every tick
				var seen := {}
				for u in e.units:
					if not u.alive:
						continue
					if u.cell.x < 0 or u.cell.x >= 8 or u.cell.y < 0 or u.cell.y >= 8 or seen.has(u.cell) or e.grid.get(u.cell) != u:
						grid_ok = false
					seen[u.cell] = true
			if not e.finished:
				finished_all = false
			longest = maxi(longest, e.tick)
			results[e.winner] = int(results[e.winner]) + 1
			for side in range(2):
				if e.king_entered[side] and e.regulars_alive_at_entry[side] != 0:
					champion_rule = false
	check(finished_all, "all 90 AI-vs-AI battles finish (longest %d ticks)" % longest)
	check(grid_ok, "grid invariants hold every tick (no overlap / out of bounds)")
	check(champion_rule, "Champion never enters while regular units are alive")
	print("   winners side0/side1/draw: ", results[0], "/", results[1], "/", results[-1])
	check(int(results[0]) > 20 and int(results[1]) > 20, "no side dominates (side bias check)")
	# determinism
	var a := BattleEngine.new()
	a.setup(make_cfg(42, "normal", 5))
	var b := BattleEngine.new()
	b.setup(make_cfg(42, "normal", 5))
	while not a.finished:
		a.step()
	while not b.finished:
		b.step()
	check(a.winner == b.winner and a.tick == b.tick and a.log_lines == b.log_lines, "same seed -> identical battle")
