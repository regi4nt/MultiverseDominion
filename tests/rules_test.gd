extends Node
## Auction, Special Dice and card unlocks. Run: godot --headless --path . res://tests/rules_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


## Match on the neutral base Special Dice / events (swift, warp, order, destiny, thief, broker), whatever the continent.
func new_base_match(seed_v: int = 11) -> MatchController:
	var c := new_match(seed_v)
	GameData.apply_flavor("")
	return c


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
	_test_life_by_difficulty()
	_test_dice()
	_test_unlocks()
	_test_upgrades()
	_test_commander()
	_test_bank_casino()
	_test_continent_flavor()
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


## First free territory of a region, handed to `pid`.
func give_land(c: MatchController, pid: int, region: int = 0) -> BoardTile:
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY and t.owner_id == -1 and t.region == region:
			t.owner_id = pid
			return t
	return null


func _test_upgrades() -> void:
	var c := new_match(21)
	var t := give_land(c, 0)
	var base := EconomySystem.rent_of(t, c.tiles)
	var max_level := int(GameData.b("max_tile_level"))
	check(t.level == 0 and EconomySystem.upgrade_cost(t) > 0, "a fresh land is level 0 and can be upgraded (%d G)" % EconomySystem.upgrade_cost(t))
	# landing on own land opens the upgrade decision
	c.current = 0
	c.players[0].position = t.index
	c.players[0].gold = 5000
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	check(String(c.pending.get("type", "")) == "upgrade", "visiting your own land offers an upgrade")
	var opts := c.get_decision_options()
	check(opts.size() == 2 and opts[0]["id"] == "upgrade" and opts[1]["id"] == "skip", "options: Upgrade / Not now")
	var gold0 := c.players[0].gold
	var cost1 := int(c.pending["price"])
	c.decide("upgrade")
	check(t.level == 1 and c.players[0].gold == gold0 - cost1 and c.pending.is_empty(), "upgrade costs gold and raises the level")
	var r1 := EconomySystem.rent_of(t, c.tiles)
	check(r1 > base, "level 1 rent (%d G) is higher than plain rent (%d G)" % [r1, base])
	# declining keeps the level
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	c.decide("skip")
	check(t.level == 1, "'Not now' leaves the level unchanged")
	# climb to the Landmark
	while t.level < max_level:
		c.state = MatchController.State.ROLLED
		c._resolve_landing(c.players[0])
		c.decide("upgrade")
	check(t.is_landmark() and t.level_label() == "Landmark", "the last level is the Landmark")
	check(EconomySystem.rent_of(t, c.tiles) > r1, "Landmark rent is the highest")
	check(EconomySystem.upgrade_cost(t) == -1, "a Landmark cannot be upgraded further")
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	check(c.pending.is_empty(), "visiting your own Landmark opens no decision")
	# too poor: no prompt
	var t2 := give_land(c, 0)
	c.players[0].position = t2.index
	c.players[0].gold = 0
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	check(c.pending.is_empty() and t2.level == 0, "no upgrade prompt when the owner cannot pay")
	# net worth counts the investment
	var nw := c.networth(c.players[0])
	check(nw >= t.price + EconomySystem.upgrade_invested(t) + t2.price, "net worth includes gold sunk into upgrades")
	# save / resume keeps levels
	c.state = MatchController.State.AWAIT_ROLL
	c.pending = {}
	var d := c.to_dict()
	var r := MatchController.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(r.tiles[t.index].level == max_level and r.tiles[t2.index].level == 0, "tile levels survive save / resume")
	# forced sale refunds the investment and resets the level
	var c2 := new_match(22)
	var a := give_land(c2, 1)
	a.level = 2
	var refund := int((a.price + EconomySystem.upgrade_invested(a)) * float(GameData.b("sell_ratio")))
	c2.players[1].gold = 0
	c2._pay(c2.players[1], 10, -1, "test")
	check(a.owner_id == -1 and a.level == 0, "a forced sale frees the land and resets its level")
	check(c2.players[1].gold == refund - 10, "the forced sale refunds the upgrades too (%d G)" % refund)
	# the AI upgrades only while a gold cushion remains
	var ai := c2.players[1]
	ai.difficulty = "normal"
	var reserve := int((GameData.b("ai_upgrade_reserve") as Dictionary)["normal"])
	ai.gold = reserve + 100
	check(AIController._wants_to_upgrade(ai, 100), "AI upgrades when a cushion remains after paying")
	ai.gold = reserve + 99
	check(not AIController._wants_to_upgrade(ai, 100), "AI does not upgrade when it would dip into its reserve")


func land_on(c: MatchController, pid: int, type: int) -> void:
	for t in c.tiles:
		if t.type == type:
			c.current = pid
			c.players[pid].position = t.index
			break
	c.state = MatchController.State.ROLLED
	c.pending = {}
	c._resolve_landing(c.players[pid])


func _test_bank_casino() -> void:
	var c := new_match(5)
	for side in range(4):
		var n := 0
		for t in c.tiles:
			if t.type == BoardTile.Type.PORTAL and t.region == side:
				n += 1
		check(n == 1, "side %d has exactly 1 portal" % side)
	check(PortalSystem.active_indices(c.tiles).size() == 4, "all 4 portals are active")
	# Bank
	var p := c.players[0]
	p.gold = 1000
	land_on(c, 0, BoardTile.Type.BANK)
	check(String(c.pending.get("type", "")) == "bank", "landing on a Bank opens the bank decision")
	c.decide("invest_250")
	check(p.gold == 750 and p.stock_value == 250 and p.stock_basis == 250, "invest 250 G moves gold into the portfolio")
	check(String(c.pending.get("type", "")) == "bank", "the bank stays open for more actions")
	check(EconomySystem.networth(c.tiles, p) == 1000, "stocks count toward net worth")
	c._update_market()
	check(p.stock_value == int(round(250.0 * (1.0 + c.market_change))), "market round moves the portfolio")
	check(c.market_change >= -0.2001 and c.market_change <= 0.3001, "market change stays within bounds")
	var v := p.stock_value
	c.decide("withdraw")
	check(p.stock_value == 0 and p.gold == 750 + v, "selling returns the portfolio to gold")
	c.decide("leave")
	check(c.pending.is_empty(), "leave closes the bank")
	# forced cash-out when paying a debt
	p.gold = 0
	p.stock_value = 300
	p.stock_basis = 300
	c._pay(p, 200, -1, "test")
	check(p.stock_value == 0 and p.gold == 100 and p.alive and p.life == 3, "debt is paid from stocks before land is sold")
	# Casino
	var q := c.players[1]
	q.gold = 1000
	land_on(c, 1, BoardTile.Type.CASINO)
	check(String(c.pending.get("type", "")) == "casino", "landing on the Casino opens a bet offer")
	var pot0 := c.casino_pot
	c.decide("bet")
	check(c.pending.is_empty() and c.stats["bets"] == 1, "bet resolves in one step")
	check(q.gold != 1000 or c.casino_pot != pot0, "bet was paid")
	var q2 := c.players[2]
	q2.gold = 10
	land_on(c, 2, BoardTile.Type.CASINO)
	check(c.pending.is_empty(), "no bet offer when broke")
	# Destiny Die uses the Fate faces
	var dest_seen := {}
	for sd in range(1, 60):
		var cd := new_base_match(sd)
		var dp := cd.players[0]
		dp.gold = 1000
		dp.special_dice.append("destiny")
		var dg := dp.gold
		var dt := dp.reroll_tokens
		cd.current = 0
		var used := cd.use_special_die(0)
		if sd == 1:
			check(used == "" and dp.special_dice.is_empty(), "Destiny Die is consumed")
		if dp.reroll_tokens > dt:
			dest_seen["six"] = true
		elif dp.gold > dg:
			dest_seen["win"] = true
		elif dp.gold < dg:
			dest_seen["lose"] = true
		else:
			dest_seen["detour"] = true
	check(dest_seen.has("six") and dest_seen.has("win") and dest_seen.has("lose"), "Destiny Die can give a token, win gold, or take gold")
	# Event cards: market up / down and the free chip
	check(GameData.base_events.size() == 12, "12 base event cards")
	var cm := new_match(9)
	cm.players[0].stock_value = 1000
	cm.players[1].stock_value = 500
	cm._shift_market(0.2)
	check(cm.players[0].stock_value == 1200 and cm.players[1].stock_value == 600, "Bull Market raises every portfolio")
	cm._shift_market(-0.2)
	check(cm.players[0].stock_value == 960, "Market Crash lowers every portfolio")
	var g1 := cm.players[2].gold
	var pot1 := cm.casino_pot
	cm._casino_draw(cm.players[2], true)
	check(cm.players[2].gold >= g1 and cm.casino_pot <= pot1, "free chip costs nothing and adds nothing to the pot")
	# Save / load keeps portfolio, market and pot
	p.stock_value = 120
	p.stock_basis = 100
	c.market_change = 0.12
	c.casino_pot = 777
	c.state = MatchController.State.AWAIT_ROLL
	c.pending = {}
	var c2 := MatchController.from_dict(c.to_dict())
	check(c2.players[0].stock_value == 120 and c2.players[0].stock_basis == 100 and absf(c2.market_change - 0.12) < 0.001 and c2.casino_pot == 777, "save / load keeps bank + casino state")


func _test_commander() -> void:
	var c := new_match(31)
	var p := c.players[0]
	check(p.commander_star == 1 and p.mission_progress == 0, "the Commander starts at 1 star")
	var m1 := CommanderSystem.mission_of(p)
	var m2: Dictionary = (GameData.b("commander_missions") as Array)[1]
	check(String(m1["metric"]) == "duel_wins" and String(m2["metric"]) == "landmarks" and m1["id"] != m2["id"], "each upgrade has a different mission")
	# a Landmark does not count while the duel mission is active
	var t := give_land(c, 0)
	t.level = int(GameData.b("max_tile_level")) - 1
	p.gold = 5000
	c._do_upgrade(p, t, 10)
	check(p.commander_star == 1 and p.mission_progress == 0, "progress only counts for the ACTIVE mission")
	# two duel wins (attacker wins) -> 2 stars
	for i in range(2):
		c.state = MatchController.State.AWAIT_DUEL
		c.pending = {"type": "duel_battle", "tile": t.index, "attacker": 0, "defender": 1}
		c.finish_duel({"winner": 0, "bonus_gold": 0, "gold_delta": {}})
		c.pending = {}
		if i == 0:
			check(p.commander_star == 1 and p.mission_progress == 1, "one duel win: mission 1/2")
	check(p.commander_star == 2 and p.mission_progress == 0, "2 duel wins: the Commander reaches 2 stars, progress resets")
	# a lost duel does not count
	c.state = MatchController.State.AWAIT_DUEL
	c.pending = {"type": "duel_battle", "tile": t.index, "attacker": 0, "defender": 1}
	c.finish_duel({"winner": 1, "bonus_gold": 0, "gold_delta": {}})
	c.pending = {}
	check(p.commander_star == 2 and p.mission_progress == 0, "a lost duel gives no progress")
	# the second mission: raise a Landmark -> 3 stars
	var t2 := give_land(c, 0)
	t2.level = int(GameData.b("max_tile_level")) - 1
	c._do_upgrade(p, t2, 10)
	check(p.commander_star == 3, "raising a Landmark: the Commander reaches 3 stars")
	check(CommanderSystem.mission_of(p).is_empty() and CommanderSystem.mission_text(p) == "Commander at max level", "no mission is left at Lv 3")
	var t3 := give_land(c, 0)
	t3.level = int(GameData.b("max_tile_level")) - 1
	c._do_upgrade(p, t3, 10)
	check(p.commander_star == 3, "the Commander never goes past 3 stars")
	# the AI earns stars the same way
	check(c.players[1].commander_star == 1, "other players keep their own progress")
	# save / resume
	c.state = MatchController.State.AWAIT_ROLL
	c.pending = {}
	var r := MatchController.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(r.players[0].commander_star == 3 and r.players[1].commander_star == 1, "Commander stars survive save / resume")
	# stars make the King stronger in Last Stand
	var hp: Array = []
	var atk: Array = []
	for star in [1, 2, 3]:
		var e := BattleEngine.new()
		var cfg := {"units": [], "champion": p.champion_id, "supports": [], "champion_star": star}
		e.setup({"seed": 5, "sides": [cfg, {"units": [], "champion": c.players[1].champion_id, "supports": []}]})
		e.step()
		var k: BattleUnit = e.kings[0]
		hp.append(k.max_hp)
		atk.append(k.base_atk)
	check(hp[0] < hp[1] and hp[1] < hp[2] and atk[0] < atk[1] and atk[1] < atk[2], "King HP / ATK grow with stars (HP %s, ATK %s)" % [str(hp), str(atk)])
	# the AI power estimate counts the stars too
	var a1 := BattleAI.army_power(c.players[0])
	c.players[0].commander_star = 1
	check(a1 > BattleAI.army_power(c.players[0]), "army power rises with Commander stars")


func _test_continent_flavor() -> void:
	var title_sets := {}
	var die_sets := {}
	for cont in GameData.continents:
		var cid := String(cont["id"])
		check(GameData.continent_flavor.has(cid), "%s has its own events and dice" % cid)
		GameData.apply_flavor(cid)
		check(GameData.events.size() == 12, "%s: 12 event cards" % cid)
		check(GameData.special_dice.size() == 6, "%s: 6 Special Dice" % cid)
		var ids := {}
		var effects := {}
		for e in GameData.events:
			ids[e["id"]] = true
			effects[e["effect"]] = true
		check(ids.size() == 12, "%s: event ids are unique" % cid)
		check(effects.size() >= 8, "%s: the deck mixes at least 8 different effects" % cid)
		var dkinds := {}
		var dids := {}
		for d in GameData.special_dice:
			dids[d["id"]] = true
			dkinds[d["kind"]] = true
			check((d["faces"] as Array).size() == 6, "%s: %s has 6 faces" % [cid, d["name"]])
		check(dids.size() == 6 and dkinds.size() >= 5, "%s: 6 distinct dice over at least 5 kinds" % cid)
		title_sets[cid] = ",".join(GameData.events.map(func(e): return str(e["title"]) + str(e["effect"]) + str(e["value"])))
		die_sets[cid] = ",".join(GameData.special_dice.map(func(d): return str(d["name"]) + str(d["faces"])))
	var uniq_e := {}
	var uniq_d := {}
	for k in title_sets:
		uniq_e[title_sets[k]] = true
		uniq_d[die_sets[k]] = true
	check(uniq_e.size() == GameData.continents.size() and uniq_d.size() == GameData.continents.size(), "every continent has a different event deck and Special Dice set")
	# unique die kinds work
	var cs := MatchController.new()
	cs.setup({"continent_id": "sylvaris", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	var sp := cs.players[0]
	var n := 0
	for t in cs.tiles:
		if t.type == BoardTile.Type.TERRITORY and n < 2:
			t.owner_id = sp.id
			n += 1
	check(cs._owned_land_count(sp) == 2, "owned land counter")
	var gold_before := sp.gold
	sp.special_dice.append("harvest")
	cs.current = 0
	cs.state = MatchController.State.AWAIT_ROLL
	check(cs.use_special_die(0) == "" and sp.gold >= gold_before + 5 * 2, "Harvest Die pays per owned territory")
	sp.life = 1
	sp.special_dice.append("springdie")
	var life0 := sp.life
	cs.state = MatchController.State.AWAIT_ROLL
	cs.use_special_die(0)
	check(sp.life >= life0 and sp.life <= int(GameData.b("start_life")), "Healing die never exceeds the maximum Life")
	# event effects
	var cm := new_match(41)
	var mp := cm.players[0]
	var owned := 0
	for t in cm.tiles:
		if t.type == BoardTile.Type.TERRITORY and owned < 3:
			t.owner_id = mp.id
			owned += 1
	cm.current = 0
	var hunter := int(mp.passive_value) if mp.has_passive("treasure_hunter") else 0
	var rich := cm.players[1]
	mp.gold = 1000
	rich.gold = 2000
	GameData.events = [{"id": "t", "title": "t", "description": "t", "effect": "gain_per_land", "value": 10}]
	cm._resolve_event(mp)
	check(mp.gold == 1000 + 30 + hunter, "gain_per_land pays per territory")
	mp.gold = 1000
	GameData.events = [{"id": "t", "title": "t", "description": "t", "effect": "lose_per_land", "value": 10}]
	cm._resolve_event(mp)
	check(mp.gold == 1000 - 30 + hunter, "lose_per_land charges per territory")
	mp.gold = 1000
	GameData.events = [{"id": "t", "title": "t", "description": "t", "effect": "steal_richest", "value": 50}]
	cm._resolve_event(mp)
	check(mp.gold == 1000 + 50 + hunter and rich.gold == 1950, "steal_richest takes gold from the richest rival")
	GameData.events = [{"id": "t", "title": "t", "description": "t", "effect": "skip_turn", "value": 1}]
	var sk := mp.skip_turns
	cm._resolve_event(mp)
	check(mp.skip_turns == sk + 1, "skip_turn costs a turn")
	GameData.apply_flavor("aetherion")


func _test_dice() -> void:
	check(GameData.base_special_dice.size() == 6, "6 base Special Dice defined (Swift, Warp, Order, Destiny, Thief, Broker)")
	var faces_ok := true
	for d in GameData.special_dice:
		faces_ok = faces_ok and (d["faces"] as Array).size() == 6
	check(faces_ok, "every Special Die has 6 faces")
	# Swift: bonus applied to the next move
	var c := new_base_match(21)
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
	# Broker: free stake when empty, then the face moves the portfolio
	var c2 := new_base_match(22)
	c2.players[0].special_dice.append("broker")
	c2.use_special_die(0)
	check(c2.players[0].stock_basis == 100 and c2.players[0].stock_value in [90, 100, 110, 120, 130, 150], "Broker Die gives a 100 G stake and moves it (%d)" % c2.players[0].stock_value)
	# Thief: steals from the richest rival, or pays a fine
	var thief_seen := {}
	for ts in range(60):
		var ct := new_base_match(500 + ts)
		ct.players[0].special_dice.append("thief")
		ct.players[2].gold = 3000
		var mg := ct.players[0].gold
		var rg := ct.players[2].gold
		ct.use_special_die(0)
		if ct.players[0].gold > mg and ct.players[2].gold == rg - (ct.players[0].gold - mg):
			thief_seen["steal"] = true
		elif ct.players[0].gold == mg - 30:
			thief_seen["caught"] = true
	check(thief_seen.size() == 2, "Thief Die steals from the richest rival or pays a fine")
	# Warp: teleports and resolves the landing
	var c3 := new_base_match(23)
	c3.players[0].special_dice.append("warp")
	var from := c3.players[0].position
	c3.use_special_die(0)
	check(c3.players[0].position != from or c3.players[0].position == 0, "Warp Die teleports the player")
	check(c3.state in [MatchController.State.TURN_DONE, MatchController.State.AWAIT_DECISION, MatchController.State.AWAIT_DUEL], "after a warp the landing is resolved (state %d)" % c3.state)
	# Order
	var seen := {}
	for s in range(40):
		var c4 := new_base_match(200 + s)
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
	var c5 := new_base_match(24)
	c5.players[0].special_dice.append("broker")
	c5.roll_dice()
	check(c5.use_special_die(0) != "" and c5.players[0].special_dice.size() == 1, "dice cannot be used after rolling")
	check(c5.use_special_die(5) != "", "invalid index is refused")
	# sources: event and shop
	var c6 := new_base_match(25)
	c6._give_special_die(c6.players[0])
	check(c6.players[0].special_dice.size() == 1, "an Event can give a Special Die")
	for i in range(5):
		c6._give_special_die(c6.players[0])
	check(c6.players[0].special_dice.size() == int(GameData.b("max_special_dice")), "at most %d dice can be carried" % int(GameData.b("max_special_dice")))
	var c7 := new_base_match(26)
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
	var c8 := new_base_match(27)
	c8.players[0].special_dice.append("broker")
	AIController.step(c8)
	check(c8.players[0].special_dice.is_empty(), "the AI uses a useful die before rolling")
	var c9 := new_base_match(28)
	c9.players[0].special_dice.append("warp")
	c9.players[0].special_dice.append("swift")
	c9.players[0].move_bonus = 2
	var r := MatchController.from_dict(JSON.parse_string(JSON.stringify(c9.to_dict())))
	check(r.players[0].special_dice == ["warp", "swift"] and r.players[0].move_bonus == 2, "Special Dice survive Save/Continue")
	var used := 0
	for s in range(1, 9):
		var g2 := new_base_match(300 + s)
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


## Life by difficulty: easy 5 / normal 3 / hard 1 (heals are capped at it); the tutorial keeps 3; it survives save/resume.
func _test_life_by_difficulty() -> void:
	var want := {"easy": 5, "normal": 3, "hard": 1}
	for d in want:
		var c := MatchController.new()
		c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": d, "ai_count": 3, "seed": 7, "all_ai": true})
		var ok := true
		for p in c.players:
			ok = ok and p.life == int(want[d]) and p.max_life == int(want[d])
		check(ok, "%s: every ruler starts with %d Life" % [d, int(want[d])])
		var back := MatchController.from_dict(c.to_dict())
		check(back.players[0].max_life == int(want[d]) and back.match_difficulty == d, "%s: Life cap and difficulty survive a save" % d)
	var t := MatchController.new()
	t.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 4242, "tutorial": true, "round_limit": 10})
	check(t.players[0].life == 3, "the tutorial keeps 3 Life")


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
