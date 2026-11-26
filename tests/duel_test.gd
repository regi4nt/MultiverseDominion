extends Node
## Phase 5 test: Territory Encounter, Duel rules, Life, Conquest/Reward, full AI games.
## Run: godot --headless --path . res://tests/duel_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


## Player 1 owns a territory; player 0 (current) has just landed on it.
func encounter() -> MatchController:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 21, "all_ai": true})
	var tile: BoardTile = null
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY:
			tile = t
			break
	tile.owner_id = 1
	c.current = 0
	c.players[0].position = tile.index
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	return c


func _ready() -> void:
	_test_players_have_armies()
	_test_tax()
	_test_refuse()
	_test_duel_outcomes()
	_test_defender_life_rule()
	_test_elimination()
	_test_debt_choice()
	_test_chaos_mode()
	_test_full_games()
	print("DUEL TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_players_have_armies() -> void:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "elarion", "difficulty": "normal", "ai_count": 3, "seed": 3, "all_ai": true})
	var ok := true
	for p in c.players:
		ok = ok and p.roster.units.size() >= 1 and p.deck.card_list().size() == 151
	check(ok, "every player starts with a persistent army and a 151-card deck")


func _test_tax() -> void:
	var c := encounter()
	check(c.state == MatchController.State.AWAIT_DECISION and String(c.pending["type"]) == "encounter", "landing on a rival territory opens an Encounter")
	check(c.decision_actor().id == 1, "the OWNER (not the visitor) answers the Encounter")
	var opts := c.get_decision_options()
	check(opts.size() == 2 and opts[0]["id"] == "tax" and opts[1]["id"] == "duel", "owner can choose Tax or Duel")
	var g0 := c.players[0].gold
	var g1 := c.players[1].gold
	var rent := int(c.pending["rent"])
	c.decide("tax")
	check(c.players[0].gold == g0 - rent and c.players[1].gold == g1 + rent, "Tax: rent moves from visitor to owner (%d G)" % rent)
	check(c.state == MatchController.State.TURN_DONE, "turn can end after Tax")


func _test_refuse() -> void:
	var c := encounter()
	var g0 := c.players[0].gold
	var rent := int(c.pending["rent"])
	c.decide("duel")
	check(String(c.pending["type"]) == "duel_response" and c.decision_actor().id == 0, "owner picks Duel -> visitor must answer")
	c.decide("refuse")
	var penalty := int(GameData.b("refuse_duel_penalty"))
	check(c.players[0].gold == g0 - rent - penalty, "refusing costs rent + configurable penalty (%d + %d)" % [rent, penalty])
	check(c.state == MatchController.State.TURN_DONE and c.stats["refused"] == 1, "refusal ends the encounter")


func _test_duel_outcomes() -> void:
	# accepted duel -> AWAIT_DUEL
	var c := encounter()
	c.decide("duel")
	c.decide("accept")
	check(c.state == MatchController.State.AWAIT_DUEL, "accepting starts the duel")
	# defender wins -> attacker loses 1 Life, land stays
	var life := c.players[0].life
	c.finish_duel({"winner": 1})
	check(c.players[0].life == life - 1, "owner wins: attacker loses 1 Life")
	check(c.tiles[c.players[0].position].owner_id == 1, "owner wins: territory stays with the owner")
	check(c.state == MatchController.State.TURN_DONE, "turn continues after the duel")
	# draw -> defender wins
	var c2 := encounter()
	c2.decide("duel")
	c2.decide("accept")
	var l2 := c2.players[0].life
	c2.finish_duel({"winner": -1})
	check(c2.players[0].life == l2 - 1 and c2.tiles[c2.players[0].position].owner_id == 1, "draw goes to the defender")
	# attacker wins -> conquest
	var c3 := encounter()
	c3.decide("duel")
	c3.decide("accept")
	var l3 := c3.players[0].life
	var d_life := c3.players[1].life
	GameData.balance["defender_loses_life"] = false
	c3.finish_duel({"winner": 0})
	check(String(c3.pending["type"]) == "conquest" and c3.decision_actor().id == 0, "attacker wins: chooses Conquest or Victory Reward")
	check(c3.players[0].life == l3 and c3.players[1].life == d_life, "defender_loses_life=false: the defender keeps its Life")
	c3.decide("conquest")
	check(c3.tiles[c3.players[0].position].owner_id == 0, "Conquest transfers ownership")
	check(c3.state == MatchController.State.TURN_DONE, "turn continues after Conquest")
	# attacker wins -> reward
	var c4 := encounter()
	c4.decide("duel")
	c4.decide("accept")
	c4.finish_duel({"winner": 0})
	var g := c4.players[0].gold
	var reward := int(c4.pending["reward"])
	c4.decide("reward")
	check(c4.players[0].gold == g + reward and c4.tiles[c4.players[0].position].owner_id == 1, "Victory Reward gives gold, owner keeps the land (+%d G)" % reward)
	# upgrades: Conquest resets the level to 0, Victory Reward counts the upgrade value
	var c6 := encounter()
	var t6: BoardTile = c6.tiles[c6.players[0].position]
	t6.level = 2
	c6.decide("duel")
	c6.decide("accept")
	c6.finish_duel({"winner": 0})
	var want6 := int((t6.price + EconomySystem.upgrade_invested(t6)) * float(GameData.b("duel_reward_ratio")))
	check(int(c6.pending["reward"]) == want6 and want6 > int(t6.price * float(GameData.b("duel_reward_ratio"))), "Victory Reward includes the upgrade value")
	c6.decide("conquest")
	check(t6.owner_id == 0 and t6.level == 0, "Conquest resets the land to Level 0")
	var c7 := encounter()
	var t7: BoardTile = c7.tiles[c7.players[0].position]
	t7.level = 2
	c7.decide("duel")
	c7.decide("accept")
	c7.finish_duel({"winner": 0})
	c7.decide("reward")
	check(t7.owner_id == 1 and t7.level == 2, "Victory Reward keeps the owner and the level")
	# Fortune's Favor bonus gold goes to the winner
	var c5 := encounter()
	c5.decide("duel")
	c5.decide("accept")
	var g5 := c5.players[1].gold
	c5.finish_duel({"winner": 1, "bonus_gold": 50})
	check(c5.players[1].gold == g5 + 50, "bonus gold (Fortune's Favor) is paid to the winner")


func _test_defender_life_rule() -> void:
	GameData.balance["defender_loses_life"] = true
	var c := encounter()
	c.decide("duel")
	c.decide("accept")
	var d_life := c.players[1].life
	c.finish_duel({"winner": 0})
	check(c.players[1].life == d_life - 1, "defender_loses_life=true (default): the losing owner loses 1 Life")
	check(String(c.pending["type"]) == "conquest", "...and the attacker still chooses Conquest or Reward")
	GameData.balance["defender_loses_life"] = true


func _test_elimination() -> void:
	var c := encounter()
	c.players[0].life = 1
	c.decide("duel")
	c.decide("accept")
	c.finish_duel({"winner": 1})
	check(not c.players[0].alive, "losing the last Life eliminates the player")
	check(c.state == MatchController.State.TURN_DONE or c.state == MatchController.State.GAME_OVER, "game state stays consistent after elimination")


func _test_debt_choice() -> void:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 21})  # player 0 is human
	var p: PlayerState = c.players[0]
	var lands: Array[BoardTile] = []
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY and lands.size() < 2:
			lands.append(t)
	for t in lands:
		t.owner_id = 0
	lands[0].level = 2
	c.current = 0
	c.state = MatchController.State.ROLLED
	p.gold = 50
	p.life = 2
	var debt := 100  # more than the 50 G in hand, but within reach once both lands are sold
	c._pay_or_ask(p, debt, -1, "test")
	check(String(c.pending.get("type", "")) == "debt" and c.state == MatchController.State.AWAIT_DECISION, "a human who cannot pay is asked first (no automatic sale)")
	check(lands[0].owner_id == 0 and lands[1].owner_id == 0 and p.gold == 50, "nothing is sold until the player chooses")
	var ids: Array = []
	for o in c.get_decision_options():
		ids.append(o["id"])
	check(ids.has("pay") and ids.has("sell_%d" % lands[0].index) and ids.has("sell_%d" % lands[1].index) and ids.has("heal") and ids.has("bankrupt"), "options: pay, sell each land, buy a Life, settle")
	var before := p.gold
	var want := c._sell_value(lands[0])
	c.decide("sell_%d" % lands[0].index)
	check(lands[0].owner_id == -1 and lands[0].level == 0 and p.gold == before + want, "selling a land gives price + upgrades x sell ratio and resets its level")
	check(String(c.pending.get("type", "")) == "debt", "the player stays in the debt prompt after selling")
	c.decide("sell_%d" % lands[1].index)
	var life := p.life
	var hp := c.heal_price_for(p)
	p.gold = maxi(p.gold, hp + debt)  # land prices vary: make sure the Life purchase below is always exercised
	if p.life < p.max_life and p.gold >= hp + debt:
		c.decide("heal")
		check(p.life == life + 1 and p.gold >= debt, "a Life can be bought with the money raised")
	var gold := p.gold
	var life2 := p.life
	c.decide("pay")
	check(c.pending.is_empty() and p.gold == gold - debt and p.life == life2, "paying the debt closes the prompt without losing a Life")
	check(c.state == MatchController.State.TURN_DONE, "the turn continues after the debt is paid")
	# declining to sell: settle everything (old behaviour) -> bankrupt if still short
	var c2 := MatchController.new()
	c2.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 21})
	var p2: PlayerState = c2.players[0]
	for t in c2.tiles:
		if t.type == BoardTile.Type.TERRITORY:
			t.owner_id = 0
			break
	c2.current = 0
	c2.state = MatchController.State.ROLLED
	p2.gold = 0
	var l2 := p2.life
	c2._pay_or_ask(p2, 100000, -1, "test")
	c2.decide("bankrupt")
	check(c2.pending.is_empty() and p2.life == l2 - 1, "settling with too little loses 1 Life (bankruptcy)")
	# AI never gets a prompt
	var c3 := MatchController.new()
	c3.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 21, "all_ai": true})
	c3.players[0].gold = 0
	c3._pay_or_ask(c3.players[0], 100000, -1, "test")
	check(c3.pending.is_empty(), "AI debts are settled automatically")


func _test_chaos_mode() -> void:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true, "chaos": true})
	var counts := BoardBuilder.count_types(c.tiles)
	check(c.chaos and c.tiles.size() == 40 and BoardBuilder.tiles_total == 40, "Chaos Mode: the board has 40 tiles")
	check(int(counts["Territory"]) == 20 and int(counts.get("Portal", 0)) == 0 and int(counts["Corner"]) == 4, "Chaos Mode: 20 territories, no portals, 4 corners")
	var per_region := [0, 0, 0, 0]
	var portals := [0, 0, 0, 0]
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY:
			per_region[t.region] += 1
		elif t.type == BoardTile.Type.PORTAL:
			portals[t.region] += 1
	check(per_region == [5, 5, 5, 5] and portals == [0, 0, 0, 0], "Chaos Mode: 5 territories and no portal in every region")
	var seen := {}
	var ring_ok := true
	for i in range(40):
		var g := BoardBuilder.grid_pos(i)
		var nx := BoardBuilder.grid_pos((i + 1) % 40)
		seen[g] = true
		ring_ok = ring_ok and g.x >= 0 and g.y >= 0 and g.x < BoardBuilder.grid and g.y < BoardBuilder.grid and absi(g.x - nx.x) + absi(g.y - nx.y) == 1
	check(seen.size() == 40 and ring_ok and BoardBuilder.grid == 11, "Chaos Mode: the 40 tiles form a closed 11x11 ring")
	# region bonuses scale with the region size
	var t0: BoardTile = null
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY and t.region == 0:
			t0 = t
			break
	var region_tiles: Array[BoardTile] = []
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY and t.region == 0:
			region_tiles.append(t)
	t0.owner_id = 1
	var rent1 := EconomySystem.rent_of(t0, c.tiles)
	for i in range(3):
		region_tiles[i].owner_id = 1
	var rent3 := EconomySystem.rent_of(t0, c.tiles)
	region_tiles[3].owner_id = 1
	region_tiles[4].owner_id = 1
	var rent5 := EconomySystem.rent_of(t0, c.tiles)
	check(BoardBuilder.majority_needed() == 3 and rent3 > rent1 and rent5 > rent3, "Chaos Mode: majority at 3 of 5, Regional Dominion at 5 of 5")
	# movement wraps at 40 and the Gate pays on every lap
	var p: PlayerState = c.players[0]
	p.position = 38
	var gold := p.gold
	var chaos_world_extra := WorldMods.start_bonus_extra  # static: the matches created below replace it
	c._move_player(p, 5)
	check(p.position == 3 and p.gold > gold, "Chaos Mode: walking past tile 39 wraps to the start and pays the Gate")
	# hidden finds are thinned out so they do not cover half of the 20 territories
	check(c.monsters.size() == int(GameData.b("arena_monster_count_multi")) and c.deposits.size() == int(GameData.b("chaos_deposit_count")), "Chaos Mode, 4 rulers: %d monsters + %d deposits" % [c.monsters.size(), c.deposits.size()])
	var c1 := MatchController.new()
	c1.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 5, "all_ai": true, "chaos": true})
	var c2 := MatchController.new()
	c2.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true, "chaos": true, "team_mode": true})
	var a1 := MatchController.new()
	a1.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 5, "all_ai": true})
	var j1 := MatchController.new()
	j1.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 5, "all_ai": true, "journey": true})
	check(a1.monsters.size() == 2 and j1.monsters.size() == 4, "Arena 1v1: 2 monsters; Journey keeps 4")
	check(c1.monsters.size() == int(GameData.b("arena_monster_count_duel")) and c2.monsters.size() == 4, "Chaos Mode: 2 monsters in 1v1, 4 in 2vs2")
	var kinds := c.deposits.map(func(e): return String(GameData.get_deposit(String(e["id"])).get("kind", "")))
	check(kinds.has("treasure") and kinds.has("mine"), "Chaos Mode: one treasure and one mine")
	var mine_d: Dictionary = GameData.get_deposit("")
	for e in c.deposits:
		var dd := GameData.get_deposit(String(e["id"]))
		if String(dd.get("kind", "")) == "mine":
			mine_d = dd
	BoardBuilder.configure(true)  # the matches above (a1, j1) reset the static Chaos flag
	check(DepositSystem.rounds_of(int(mine_d["rounds"])) < int(mine_d["rounds"]) and DepositSystem.gold_of(int(mine_d["income"])) > int(mine_d["income"]), "Chaos Mode: mines run fewer rounds and pay more per round")
	var wp: PlayerState = c.players[1]
	wp.position = 5
	var wd := c._random_warp_dest(wp)
	check(wd >= 0 and wd != 5 and c.tiles[wd].type != BoardTile.Type.CORNER, "Chaos Mode: no portals, so a warp goes to a random non-corner place")
	check(c.first_seat == 0, "default matches still open with seat 0")
	var rf := MatchController.new()
	rf.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 11, "all_ai": true, "random_first": true})
	var turns := [0, 0, 0, 0]
	var r0 := rf.round_number
	for _i in range(4):
		turns[rf.current] += 1
		rf._advance_turn()
	check(rf.current == rf.first_seat and rf.round_number == r0 + 1 and turns == [1, 1, 1, 1], "random first seat: a round is 4 turns, one per seat, and ends back at the opening seat")
	var seen_first := {}
	for sd in range(1, 25):
		var tm := MatchController.new()
		tm.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": sd, "all_ai": true, "team_mode": true, "random_first": true})
		seen_first[tm.first_seat] = true
		var t_ok := tm.current == tm.first_seat
		for i in range(4):
			t_ok = t_ok and tm.players[i].team == i % 2
		check(t_ok, "2v2 random first seat (seed %d): teams still alternate A, B, A, B" % sd)
	check(seen_first.size() > 1, "2v2: the opening seat varies between matches")
	var gate_pay: int = int(GameData.b("chaos_start_bonus")) + chaos_world_extra
	if p.has_passive("royal_treasury"):  # Solvaris: Royal Treasury raises what the Gate pays
		gate_pay = int(gate_pay * (1.0 + p.passive_value))
	check(p.gold - gold == gate_pay, "Chaos Mode: the Gate pays the reduced Chaos bonus (%d)" % (p.gold - gold))
	var first_lot: BoardTile = c.tiles[1]
	check(first_lot.type == BoardTile.Type.TERRITORY and first_lot.price == int(round(float(int(GameData.b("territory_base_price"))) * float(GameData.b("chaos_price_mult")))), "Chaos Mode: Territory prices are scaled up")
	check(GameData.round_limit_for("chaos", "normal") < GameData.round_limit_for("arena", "normal"), "Chaos Mode: the round limit is shorter than Arena's")
	# save / resume keeps the mode
	c.state = MatchController.State.AWAIT_ROLL
	c.pending = {}
	var d := c.to_dict()
	BoardBuilder.configure(false)
	var r := MatchController.from_dict(d)
	check(r.chaos and r.tiles.size() == 40 and BoardBuilder.tiles_total == 40, "a saved Chaos match resumes as a 40-tile board")
	# a normal match afterwards is back to 100 tiles
	var n := MatchController.new()
	n.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	check(not n.chaos and n.tiles.size() == 100 and BoardBuilder.grid == 26 and BoardBuilder.majority_needed() == int(GameData.b("majority_threshold")), "a normal match is still 100 tiles")
	# AI games finish on the Chaos board
	var all_done := true
	for s in range(1, 5):
		var g := MatchController.new()
		g.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": s, "all_ai": true, "chaos": true})
		var steps := 0
		while g.state != MatchController.State.GAME_OVER and steps < 40000:
			AIController.step(g)
			steps += 1
		all_done = all_done and g.state == MatchController.State.GAME_OVER
	check(all_done, "AI games finish on the Chaos board")
	BoardBuilder.configure(false)


func _test_full_games() -> void:
	var finished_all := true
	var totals := {"duels": 0, "tax": 0, "refused": 0, "conquests": 0, "rewards": 0, "attacker_wins": 0, "defender_wins": 0}
	var by_elim := 0
	var rounds_sum := 0
	var n := 0
	for diff in ["easy", "normal", "hard"]:
		for s in range(1, 9):
			var c := MatchController.new()
			c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": diff, "ai_count": 3, "seed": s, "all_ai": true})
			var steps := 0
			while c.state != MatchController.State.GAME_OVER and steps < 40000:
				AIController.step(c)
				steps += 1
			if c.state != MatchController.State.GAME_OVER:
				finished_all = false
				push_error("stuck: %s seed %d state %d pending %s" % [diff, s, c.state, str(c.pending)])
			for k in totals:
				totals[k] += int(c.stats[k])
			if c.alive_players().size() == 1:
				by_elim += 1
			rounds_sum += c.round_number
			n += 1
	check(finished_all, "all %d AI games finish with the duel system active" % n)
	print("   totals over %d games: %s" % [n, str(totals)])
	print("   games ended by elimination: %d / %d, avg rounds %.1f" % [by_elim, n, float(rounds_sum) / n])
	check(int(totals["duels"]) > 0 and int(totals["tax"]) > 0, "both Tax and Duel are chosen by AI owners")
	var resolved := int(totals["conquests"]) + int(totals["rewards"])
	check(resolved <= int(totals["attacker_wins"]) and int(totals["attacker_wins"]) - resolved <= n, "attacker wins end in Conquest/Reward (unless the last defender's Life ended the game)")
	check(int(totals["attacker_wins"]) + int(totals["defender_wins"]) == int(totals["duels"]), "duel statistics are consistent")
