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
	BattleDeck.supports_in_shop = false  # unit-only shop for the unit / balance tests below
	_test_prep()
	_test_support()
	_test_energy()
	_test_combo()
	_test_last_stand_empty()
	_test_manual_king()
	_test_king_passive()
	_test_battles()
	BattleDeck.supports_in_shop = true
	_test_shop_supports()
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
	cfg["free_supports"] = true  # the energy rules have their own test (_test_energy)
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


func _test_energy() -> void:
	var cfg := make_cfg(11, "normal", 4)
	cfg["ai_supports"] = [false, false]
	cfg["sides"][0]["supports"] = ["sup_fireball", "sup_summon_recruits"]
	var e := BattleEngine.new()
	e.setup(cfg)
	var start := int(GameData.b("energy_start"))
	var cost := e.support_energy_cost("sup_fireball")
	check(int(e.energy[0]) == start and cost > start, "battle starts with %d energy; Fireball costs %d" % [start, cost])
	check(e.use_support(0, "sup_fireball") != "" and not (e.used_supports[0] as Array).has("sup_fireball"), "a card that costs more than the energy is refused and not spent")
	var regen := e.energy_regen_ticks()
	var ticks := 0
	while int(e.energy[0]) < cost and ticks < 1000:
		e.step()
		ticks += 1
	check(ticks == (cost - start) * regen, "energy fills 1 per %d ticks (%d ticks for %d points)" % [regen, ticks, cost - start])
	var before := int(e.energy[0])
	check(e.use_support(0, "sup_fireball") == "" and int(e.energy[0]) == before - cost, "playing a card pays its energy cost")
	var e2 := BattleEngine.new()
	e2.setup(cfg)
	for i in range(regen * (e2.energy_max() + 5)):
		e2.step()
		if e2.finished:
			break
	check(int(e2.energy[0]) <= e2.energy_max(), "energy never exceeds the maximum")
	var legendary := ""
	for sc in CardDatabase.all_supports():
		if String(sc["rarity"]) == "legendary":
			legendary = String(sc["id"])
			break
	check(legendary != "" and e.support_energy_cost(legendary) > cost and e.support_energy_cost(legendary) <= e.energy_max(), "a Legendary costs more than a Common but still fits in the bar")


func _test_combo() -> void:
	var cfg := make_cfg(11, "normal", 4)
	cfg["ai_supports"] = [false, false]
	var a := "sup_fireball"
	var cat := String(CardDatabase.get_support(a).get("category", ""))
	var same := ""
	var other := ""
	for sc in CardDatabase.all_supports():
		var id := String(sc["id"])
		if id == a or not BattleEngine.IMPLEMENTED_SUPPORTS.has(String(sc["effect"])) or BattleEngine.PREP_SUPPORTS.has(String(sc["effect"])):
			continue
		if same == "" and String(sc["category"]) == cat:
			same = id
		elif other == "" and String(sc["category"]) != cat:
			other = id
	cfg["sides"][0]["supports"] = [a, same, other]
	var e := BattleEngine.new()
	e.setup(cfg)
	e.energy[0] = e.energy_max()
	var cost_b := e.support_energy_cost(same)
	check(e.use_support(0, a) == "" and e.combo_active(0) == 1, "first card starts a chain of 1")
	var before := int(e.energy[0])
	check(e.use_support(0, same) == "" and e.combo_active(0) == 2, "same category right after extends the chain to 2")
	check(int(e.energy[0]) == before - cost_b + 1, "chain of 2 refunds 1 energy")
	e.energy[0] = e.energy_max()
	before = int(e.energy[0])
	var cost_o := e.support_energy_cost(other)
	check(e.use_support(0, other) == "" and e.combo_active(0) == 1 and int(e.energy[0]) == before - cost_o, "another category restarts the chain, no refund")
	var e2 := BattleEngine.new()
	e2.setup(cfg)
	e2.energy[0] = e2.energy_max()
	e2.use_support(0, a)
	e2.tick += e2.combo_window()
	check(e2.combo_active(0) == 1, "the chain is still alive at the end of the window")
	e2.tick += 1
	check(e2.combo_active(0) == 0, "the chain expires after the combo window")


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


func _test_manual_king() -> void:
	var cfg := {"seed": 5, "ai_supports": [false, false], "manual_king": [true, false], "sides": [
		{"units": [], "champion": "champion_solvaris", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 3)}], "champion": "champion_nocthyr", "supports": []}]}
	var e := BattleEngine.new()
	e.setup(cfg)
	var cost := e.king_energy_cost()
	check(e.king_entered[0] and not e.king_skill_used[0], "manual King enters but waits for the skill")
	check(cost > int(e.energy[0]) and not e.can_use_king_skill(0), "the King skill needs energy: %d needed, %d available" % [cost, int(e.energy[0])])
	check(e.use_king_skill(0) != "" and not e.king_skill_used[0] and int(e.energy[0]) == int(GameData.b("energy_start")), "an unaffordable King skill is refused and nothing is spent")
	e.energy[0] = e.energy_max()
	check(e.can_use_king_skill(0), "with enough energy the King skill can be cast")
	var hp_before := e.total_hp(1)
	e.step()
	check(not e.king_skill_used[0], "manual King skill is not cast by itself")
	var en_before := int(e.energy[0])
	check(e.use_king_skill(0) == "" and e.king_skill_used[0], "manual King skill can be cast once")
	check(int(e.energy[0]) <= en_before - cost + 1, "casting the King skill pays its energy cost")
	check(e.use_king_skill(0) != "", "manual King skill cannot be cast twice")
	check(e.total_hp(1) < hp_before, "Sun Judgment damages the enemy when cast")
	check(e.use_king_skill(1) != "", "a King that has not entered cannot cast")
	var e2 := BattleEngine.new()
	e2.setup({"seed": 5, "ai_supports": [false, false], "sides": cfg["sides"]})
	check(not e2.king_skill_used[0], "an auto King waits until it can pay for its skill")
	e2.energy[0] = cost
	e2.step()
	check(e2.king_skill_used[0], "an auto King casts as soon as it has the energy (AI / old behaviour)")
	var e3 := BattleEngine.new()
	e3.setup({"seed": 5, "ai_supports": [false, false], "free_supports": true, "sides": cfg["sides"]})
	check(e3.king_skill_used[0], "with free_supports the auto King still casts on entry")


func _test_king_passive() -> void:
	var units := [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 6)}]
	var base := BattleEngine.new()
	base.setup({"seed": 5, "ai_supports": [false, false], "sides": [{"units": units, "champion": "", "supports": []}, {"units": [], "champion": "champion_nocthyr", "supports": []}]})
	var hp := BattleEngine.new()
	hp.setup({"seed": 5, "ai_supports": [false, false], "sides": [{"units": units, "champion": "champion_valdoria", "supports": []}, {"units": [], "champion": "champion_nocthyr", "supports": []}]})
	check(hp.units_of(0)[0].max_hp > base.units_of(0)[0].max_hp, "Valdoria's Iron Discipline raises unit HP")
	var ok28 := true
	for cid in GameData.champions:
		var p: Dictionary = GameData.king_passives.get(cid, {})
		ok28 = ok28 and ["team_hp", "team_atk", "team_armor", "team_shield", "king_hp", "king_atk"].has(String(p.get("type", "")))
	check(ok28, "every King has a valid battle passive")


func _test_shop_supports() -> void:
	BattleDeck.supports_in_shop = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var deck := Deck.create_default()
	var bd := BattleDeck.new(deck, rng)
	var saw := false
	for i in range(40):
		var shop := bd.draw_shop()
		for id in shop:
			if BattlePrep.is_support_id(id):
				saw = true
		bd.return_cards(shop)
	check(saw, "Support cards appear in Battle Shop rolls")
	check(bd.remaining() == 135 and bd.support_pool.size() == deck.support_ids.size(), "returning offers keeps units and supports in their own piles")
	var prep := BattlePrep.new(deck, rng, 2000, 2000, 3)
	var sid := String(deck.support_ids[0])
	for sup in deck.support_ids:  # find a rarity that the level gate blocks
		if prep.support_level_req(String(sup)) > prep.level:
			sid = String(sup)
			break
	prep.offers = [sid, "", "", "", ""]
	check(prep.can_buy(0).begins_with("Needs level"), "a Support above the player's level cannot be bought")
	prep.level = 10
	var gold_before := prep.gold
	check(prep.buy(0) == "" and prep.hand.has(sid) and prep.gold == gold_before - prep.support_price(sid), "a Support is bought into the hand")
	prep.consume_used([sid])
	check(not prep.hand.has(sid) and bd.support_pool.has(sid), "a played Support is spent and returns to the pile")


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
