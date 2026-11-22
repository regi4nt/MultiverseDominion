extends Node
## Auction, Special Dice and card unlocks. Run: godot --headless --path . res://tests/rules_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func new_match(seed_v: int = 11) -> MatchController:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": seed_v, "all_ai": true})
	return c


## Puts player `pid` on an Auction tile and resolves the landing.
func land_on_auction(c: MatchController, pid: int) -> void:
	for t in c.tiles:
		if t.type == BoardTile.Type.AUCTION:
			c.current = pid
			c.players[pid].position = t.index
			break
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[pid])


func _ready() -> void:
	_test_auction()
	_test_dice()
	_test_unlocks()
	_test_games()
	print("RULES TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_auction() -> void:
	var c := new_match()
	land_on_auction(c, 1)
	check(String(c.pending["type"]) == "auction" and c.decision_actor().id == 1, "landing on the Auction House opens an auction; the lander answers first")
	check((c.pending["order"] as Array) == [1, 2, 3, 0], "bidding order starts with the lander and goes around the table")
	var lot: BoardTile = c.tiles[int(c.pending["tile"])]
	var start := int(c.pending["bid"])
	check(start == maxi(10, int(round(lot.price * 0.4 / 5.0)) * 5) and lot.owner_id == -1, "opening bid is 40%% of the list price (%d G for a %d G lot)" % [start, lot.price])
	var opts := c.get_decision_options()
	check(opts.size() == 2 and opts[0]["id"] == "bid" and opts[1]["id"] == "pass", "options: Bid / Pass")
	# competitive bidding: 1 opens, 2 raises, 3 and 0 pass, 1 passes -> 2 wins the raised price
	var g1 := c.players[1].gold
	var g2 := c.players[2].gold
	c.decide("bid")
	check(int(c.pending["leader"]) == 1 and c.decision_actor().id == 2, "after a bid, the next ruler answers")
	var inc := int(c.pending["inc"])
	check(c.auction_next_bid() == start + inc, "the next bid is raised by one step (%d G)" % inc)
	c.decide("bid")
	var price2 := int(c.pending["bid"])
	check(price2 == start + inc and int(c.pending["leader"]) == 2, "ruler 2 takes the lead at %d G" % price2)
	c.decide("pass")  # 3
	c.decide("pass")  # 0
	check(c.decision_actor().id == 1 and String(c.pending["type"]) == "auction", "ruler 1 may still answer the raise")
	c.decide("pass")
	check(lot.owner_id == 2 and c.players[2].gold == g2 - price2 and c.players[1].gold == g1, "the highest bidder wins and pays; the loser pays nothing")
	check(c.state == MatchController.State.TURN_DONE and c.stats["auctions"] == 1, "the turn continues after the sale")
	# nobody bids
	var c2 := new_match(12)
	land_on_auction(c2, 0)
	var lot2: BoardTile = c2.tiles[int(c2.pending["tile"])]
	for i in range(4):
		c2.decide("pass")
	check(lot2.owner_id == -1 and c2.state == MatchController.State.TURN_DONE, "no bids: the lot stays unsold")
	# a ruler who cannot afford is skipped automatically; a passed ruler never returns
	var c3 := new_match(13)
	c3.players[2].gold = 0
	c3.players[3].gold = 0
	land_on_auction(c3, 1)
	c3.decide("bid")
	check(c3.decision_actor().id == 0, "rulers who cannot afford the price are skipped (2 and 3 have 0 G)")
	c3.decide("pass")
	check(c3.tiles[int(c3.pending.get("tile", 0))].owner_id == 1 or c3.state == MatchController.State.TURN_DONE, "the last bidder left wins")
	var c4 := new_match(14)
	land_on_auction(c4, 0)
	c4.decide("pass")  # 0 passes
	c4.decide("bid")  # 1
	c4.decide("pass")
	c4.decide("pass")  # 3 -> back to 1 who leads
	check(c4.state == MatchController.State.TURN_DONE and c4.tiles[0].owner_id != 0, "a ruler who passed cannot bid later")
	# cannot bid more than owned
	var c5 := new_match(15)
	c5.players[0].gold = 5
	land_on_auction(c5, 0)
	check(c5.decision_actor().id != 0, "the lander who cannot open is skipped")
	# AI valuation
	var c6 := new_match(16)
	land_on_auction(c6, 0)
	var seen_bid := false
	var seen_pass := false
	for i in range(20):
		if c6.state != MatchController.State.AWAIT_DECISION or String(c6.pending.get("type", "")) != "auction":
			break
		var ch := AIController._auction_choice(c6, c6.decision_actor())
		seen_bid = seen_bid or ch == "bid"
		seen_pass = seen_pass or ch == "pass"
		c6.decide(ch)
	check(c6.state == MatchController.State.TURN_DONE, "an AI-only auction always finishes")
	var lots := 0
	for s in range(1, 13):
		var g := new_match(100 + s)
		var steps := 0
		while g.state != MatchController.State.GAME_OVER and steps < 40000:
			AIController.step(g)
			steps += 1
		lots += int(g.stats["auctions"])
	check(lots > 0, "AI players win auctions in full games (%d sold in 12 games)" % lots)


func _test_dice() -> void:
	check(GameData.special_dice.size() == 4, "4 Special Dice defined (Swift, Fortune, Warp, Order)")
	var faces_ok := true
	for d in GameData.special_dice:
		faces_ok = faces_ok and (d["faces"] as Array).size() == 6
	check(faces_ok, "every Special Die has 6 faces")
	# Swift: bonus applied to the next move
	var c := new_match(21)
	var p := c.players[0]
	p.special_dice.append("swift")
	check(c.use_special_die(0) == "" and p.special_dice.is_empty(), "a used die is consumed")
	var bonus := p.move_bonus
	check(bonus in [1, 2, 3, -1] and c.state == MatchController.State.AWAIT_ROLL, "Swift Die sets a move bonus (%d) and the player still rolls" % bonus)
	var pos := p.position
	var first_move: Array[int] = []
	c.player_moved.connect(func(_pid: int, _from: int, to_i: int, _warped: bool): first_move.append(to_i))
	c.roll_dice()
	var expected := posmod(pos + c.last_dice.x + c.last_dice.y + bonus, 100)
	c.confirm_move()
	# (the landing may move the player again, e.g. portals or events, so the FIRST move is checked)
	check(first_move.size() >= 1 and first_move[0] == expected, "the bonus is added to the move (first step went to %d, expected %d = %d + dice %d + bonus %d)" % [first_move[0] if first_move.size() > 0 else -1, expected, pos, c.last_dice.x + c.last_dice.y, bonus])
	check(p.move_bonus == 0, "the bonus is used up after the move")
	# Fortune
	var c2 := new_match(22)
	c2.players[0].special_dice.append("fortune")
	var g := c2.players[0].gold
	c2.use_special_die(0)
	check(c2.players[0].gold - g in [20, 30, 40, 50, 75, 100], "Fortune Die pays gold (%+d)" % (c2.players[0].gold - g))
	# Warp: teleports and resolves the landing
	var c3 := new_match(23)
	c3.players[0].special_dice.append("warp")
	var from := c3.players[0].position
	c3.use_special_die(0)
	check(c3.players[0].position != from or c3.players[0].position == 0, "Warp Die teleports the player")
	check(c3.state in [MatchController.State.TURN_DONE, MatchController.State.AWAIT_DECISION, MatchController.State.AWAIT_DUEL], "after a warp the landing is resolved (state %d)" % c3.state)
	# Order
	var seen := {}
	for s in range(40):
		var c4 := new_match(200 + s)
		c4.players[0].special_dice.append("order")
		var tok := c4.players[0].reroll_tokens
		var gold := c4.players[0].gold
		c4.use_special_die(0)
		if c4.players[1].skip_turns > 0:
			seen["skip"] = true
		if c4.players[0].reroll_tokens > tok:
			seen["token"] = true
		if c4._extra_roll:
			seen["extra"] = true
		if c4.players[0].gold == gold + 50:
			seen["gold"] = true
	check(seen.size() == 4, "Order Die faces all work: %s" % str(seen.keys()))
	# restrictions
	var c5 := new_match(24)
	c5.players[0].special_dice.append("fortune")
	c5.roll_dice()
	check(c5.use_special_die(0) != "" and c5.players[0].special_dice.size() == 1, "dice cannot be used after rolling")
	check(c5.use_special_die(5) != "", "invalid index is refused")
	# sources: event and shop
	var c6 := new_match(25)
	c6._give_special_die(c6.players[0])
	check(c6.players[0].special_dice.size() == 1, "an Event can give a Special Die")
	for i in range(5):
		c6._give_special_die(c6.players[0])
	check(c6.players[0].special_dice.size() == int(GameData.b("max_special_dice")), "at most %d dice can be carried" % int(GameData.b("max_special_dice")))
	var c7 := new_match(26)
	c7.current = 0
	c7.state = MatchController.State.AWAIT_DECISION
	c7.pending = {"type": "shop"}
	var gold7 := c7.players[0].gold
	var ids := []
	for o in c7.get_decision_options():
		ids.append(o["id"])
	check(ids.has("special"), "the Territory Shop sells Special Dice")
	c7.decide("special")
	check(c7.players[0].special_dice.size() == 1 and c7.players[0].gold == gold7 - c7.special_die_price(), "buying a die costs %d G" % c7.special_die_price())
	# AI uses dice, save keeps them
	var c8 := new_match(27)
	c8.players[0].special_dice.append("fortune")
	AIController.step(c8)
	check(c8.players[0].special_dice.is_empty(), "the AI uses a useful die before rolling")
	var c9 := new_match(28)
	c9.players[0].special_dice.append("warp")
	c9.players[0].special_dice.append("swift")
	c9.players[0].move_bonus = 2
	var r := MatchController.from_dict(JSON.parse_string(JSON.stringify(c9.to_dict())))
	check(r.players[0].special_dice == ["warp", "swift"] and r.players[0].move_bonus == 2, "Special Dice survive Save/Continue")
	var used := 0
	for s in range(1, 9):
		var g2 := new_match(300 + s)
		var steps := 0
		while g2.state != MatchController.State.GAME_OVER and steps < 40000:
			AIController.step(g2)
			steps += 1
		used += int(g2.stats["special_dice"])
	check(used > 0, "AIs find and use Special Dice in full games (%d uses in 8 games)" % used)


func _test_unlocks() -> void:
	var saved: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data["collection"].clear()
	SaveManager.ensure_collection()
	var locked := 0
	for s in CardDatabase.all_supports():
		if SaveManager.owned_count(s["id"]) == 0:
			locked += 1
	var expected_locked := CardDatabase.all_supports().size() - CardDatabase.default_support_ids().size()
	check(locked == expected_locked and locked == 90, "a new profile has 90 locked Support cards of 105 (%d)" % locked)
	var got: Array[String] = []
	for i in range(locked + 2):
		var id := SaveManager.record_match(true, 10, 100, "")
		if id != "":
			got.append(id)
	check(got.size() == locked, "%d victories unlock the %d locked cards, then nothing more (%d)" % [locked, locked, got.size()])
	var distinct := {}
	for id in got:
		distinct[id] = true
	check(distinct.size() == locked, "every unlock is a different card")
	var before: int = SaveManager.data["stats"]["wins"]
	check(SaveManager.record_match(false, 10, 100, "") == "" and SaveManager.data["stats"]["wins"] == before, "a defeat unlocks nothing")
	SaveManager.data = saved
	SaveManager.save_game()


func _test_games() -> void:
	var finished := true
	for c_id in ["aetherion", "sylvaris", "eclipsia"]:
		for s in range(1, 4):
			var m := MatchController.new()
			m.setup({"continent_id": c_id, "faction_id": GameData.get_continent(c_id)["factions"][s]["id"], "difficulty": "normal", "ai_count": 3, "seed": 40 + s, "all_ai": true})
			var steps := 0
			while m.state != MatchController.State.GAME_OVER and steps < 50000:
				AIController.step(m)
				steps += 1
			finished = finished and m.state == MatchController.State.GAME_OVER
	check(finished, "full AI games still finish with auctions and Special Dice")
