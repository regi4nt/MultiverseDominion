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
	_test_lease()
	_test_commander()
	_test_bank_casino()
	_test_continent_flavor()
	_test_combos()
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
	check(c.get_decision_options().size() == 1 and String(c.get_decision_options()[0]["id"]) == "leave", "the Casino offers only Leave: the games are played in the Gamble panel")
	check(not bool(c.casino_play("coin", "heads", 7)["ok"]) and q.gold == 1000, "a bet that is not in casino_bets is refused")
	check(not bool(c.casino_play("roulette", "", 50)["ok"]) and q.gold == 1000, "an unknown game is refused")
	var drawn := String(c.pending["game"])
	check(drawn in ["coin", "dice", "slots"], "the Casino draws one of the three Gamble games")
	var other := "slots" if drawn != "slots" else "coin"
	check(not bool(c.casino_play(other, c.casino_default_choice(other), 50)["ok"]) and q.gold == 1000, "only the drawn game can be played")
	q.gold = 20
	check(not bool(c.casino_play(drawn, c.casino_default_choice(drawn), 50)["ok"]) and q.gold == 20, "a bet above the player's gold is refused")
	q.gold = 1000
	var cr := c.casino_play(drawn, c.casino_default_choice(drawn), 50)  # one round of the drawn game, paid in gold
	check(bool(cr["ok"]) and int(cr["net"]) == int(cr["payout"]) - 50, "Casino %s plays a round" % drawn)
	check(q.gold == 1000 + int(cr["net"]) and c.stats["bets"] == 1, "the round moves gold by the net result and counts as a bet")
	check(not bool(c.casino_play(drawn, c.casino_default_choice(drawn), 50)["ok"]) and q.gold == 1000 + int(cr["net"]), "only one round per Casino visit")
	q.gold = 1000
	var seen_games := {}
	for sd in range(1, 40):  # the game is random: over many visits all three show up
		var cg := new_match(sd)
		cg.players[1].gold = 1000
		land_on(cg, 1, BoardTile.Type.CASINO)
		seen_games[String(cg.pending["game"])] = true
	check(seen_games.size() == 3, "the Casino draws all three games over many visits")
	c.decide("leave")
	check(c.pending.is_empty(), "Leave closes the Casino")
	check(not bool(c.casino_play(drawn, c.casino_default_choice(drawn), 50)["ok"]), "no Casino rounds without an open Casino")
	land_on(c, 1, BoardTile.Type.CASINO)
	c.decide("bet")  # quick bet (AI / headless): one round of the drawn game at the lowest bet
	check(c.pending.is_empty() and c.stats["bets"] == 2, "the quick bet resolves in one step")
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
	cm._casino_free_chip(cm.players[2])
	check(cm.players[2].gold >= g1, "free chip costs nothing: it can only add gold")
	# Save / load keeps portfolio and market
	p.stock_value = 120
	p.stock_basis = 100
	c.market_change = 0.12
	c.state = MatchController.State.AWAIT_ROLL
	c.pending = {}
	var c2 := MatchController.from_dict(c.to_dict())
	check(c2.players[0].stock_value == 120 and c2.players[0].stock_basis == 100 and absf(c2.market_change - 0.12) < 0.001, "save / load keeps the bank state")


func _free_land(c: MatchController, region: int = 0) -> BoardTile:
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY and t.owner_id == -1 and t.region == region:
			return t
	return null


func _land_on_tile(c: MatchController, pid: int, t: BoardTile) -> void:
	c.current = pid
	c.players[pid].position = t.index
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[pid])


## Free land: Buy or Lease. A lease costs a share of the price, lasts "lease_rounds" rounds and can be bought out.
func _test_lease() -> void:
	var c := new_match(31)
	var t := _free_land(c)
	var p := c.players[0]
	p.gold = 5000
	_land_on_tile(c, 0, t)
	check(String(c.pending.get("type", "")) == "buy" and int(c.pending["lease"]) > 0, "free land offers Buy and Lease")
	var ids: Array = c.get_decision_options().map(func(o): return o["id"])
	check(ids == ["buy", "lease", "skip"], "options: Buy / Lease / Skip (%s)" % str(ids))
	var price := int(c.pending["price"])
	var lease := int(c.pending["lease"])
	check(lease < price and lease == EconomySystem.lease_cost(price), "a lease costs less than the price (%d vs %d G)" % [lease, price])
	var gold0 := p.gold
	c.decide("lease")
	check(t.owner_id == 0 and t.lease_left == int(GameData.b("lease_rounds")) and p.gold == gold0 - lease and c.pending.is_empty(), "leasing pays the lease and takes the land for a few rounds")
	check(t.is_leased() and EconomySystem.region_count(c.tiles, t.region, 0) == 0, "leased land does not count toward a region bonus")
	var nw_before := c.networth(p)
	check(nw_before == p.gold + p.stock_value, "leased land is not net worth")
	# rent is collected as usual
	var rent := EconomySystem.rent_of(t, c.tiles)
	check(rent > 0, "leased land still charges rent (%d G)" % rent)
	# own leased land offers a buy-out, not an upgrade
	_land_on_tile(c, 0, t)
	check(String(c.pending.get("type", "")) == "redeem" and int(c.pending["price"]) == t.price - lease, "own leased land offers a buy-out for the rest of the price")
	var g1 := p.gold
	c.decide("redeem")
	check(t.lease_left == 0 and t.owner_id == 0 and p.gold == g1 - (price - lease), "buying out makes the land permanent")
	check(c.networth(p) == p.gold + p.stock_value + t.price, "bought-out land counts as net worth again")
	# a lease ends after its rounds and the land is free again
	var t2 := _free_land(c)
	_land_on_tile(c, 0, t2)
	c.decide("lease")
	for i in range(int(GameData.b("lease_rounds"))):
		check(t2.owner_id == 0, "lease still running (round %d)" % i)
		c._tick_leases()
	check(t2.owner_id == -1 and t2.lease_left == 0 and t2.lease_paid == 0, "the lease ends: the land is free again")
	# forced sales never touch leased land
	var t3 := _free_land(c)
	_land_on_tile(c, 0, t3)
	c.decide("lease")
	var cheapest := c._cheapest_owned(p)
	check(cheapest != t3, "leased land is never force-sold")
	# a player who cannot afford the price can still lease
	var c2 := new_match(32)
	var t4 := _free_land(c2)
	c2.players[1].gold = EconomySystem.lease_cost(t4.price) + 5
	_land_on_tile(c2, 1, t4)
	var opts := c2.get_decision_options()
	check(String(c2.pending.get("type", "")) == "buy" and not opts[0]["enabled"] and opts[1]["enabled"], "too poor to buy: only Lease is enabled")
	c2.decide("buy")  # refused: stays pending
	check(not c2.pending.is_empty() and t4.owner_id == -1, "an unaffordable purchase is refused")
	c2.decide("skip")
	# save and resume keep the lease
	var c3 := new_match(33)
	var t5 := _free_land(c3)
	c3.players[0].gold = 5000
	_land_on_tile(c3, 0, t5)
	c3.decide("lease")
	t5.lease_left = 2
	var r := MatchController.from_dict(c3.to_dict())
	check(r != null and r.tiles[t5.index].lease_left == 2 and r.tiles[t5.index].lease_paid == t5.lease_paid and r.tiles[t5.index].owner_id == 0, "a saved match keeps its leases")
	# AI games with leases still finish
	var leases := 0
	for g in range(6):
		var ac := new_match(500 + g)
		var steps := 0
		while ac.state != MatchController.State.GAME_OVER and steps < 60000:
			AIController.step(ac)
			steps += 1
		check(ac.state == MatchController.State.GAME_OVER, "AI game %d with leases finishes" % g)
		leases += int(ac.stats.get("leases", 0))
	check(leases > 0, "AIs lease land in full games (%d leases in 6 games)" % leases)


func _test_commander() -> void:
	var seen_pairs := {}
	var mis_ok := true
	for cid in GameData.champions.keys():
		var ms: Array = CommanderSystem.missions_for(String(cid))
		mis_ok = mis_ok and ms.size() == 2 and String(ms[0]["id"]) != String(ms[1]["id"]) and int(ms[0]["target"]) > 0 and int(ms[0].get("bc_target", 0)) > 0 and String(ms[1].get("bc_metric", "")) != ""
		seen_pairs[String(ms[0]["metric"]) + "/" + String(ms[1]["metric"])] = true
	check(mis_ok and seen_pairs.size() == GameData.champions.size(), "every faction has its own pair of Commander missions (Territory + Battle Chess version)")
	var bcp := PlayerState.new()
	bcp.champion_id = "champion_solvaris"
	check(CommanderSystem.add_progress_battle(bcp, "bc_wins", 1) == false and bcp.mission_progress == 1 and CommanderSystem.add_progress_battle(bcp, "bc_wins", 1) and bcp.commander_star == 2, "Battle Chess: two won rounds level the King (Solvaris mission 1)")
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
		check(k.stars == star, "the King token carries its Commander stars like a unit (%d)" % star)
	var me := BattleEngine.new()
	me.setup({"seed": 5, "sides": [{"units": [], "champion": p.champion_id, "supports": []}, {"units": [], "champion": "", "supports": [], "foes": [String(GameData.get_monsters(String(c.continent["id"]))[0]["id"])], "foe_star": 3}]})
	var mons := me.units.filter(func(x): return x.is_monster)
	check(mons.size() > 0 and mons[0].stars == 3, "a wild Monster carries the King level it fights at as stars")
	check(CommanderSystem.stars_marks(1) == "" and CommanderSystem.stars_marks(3) == "***" and CommanderSystem.star_info(2).begins_with("Lv 2 **"), "King star text is written like a unit's")
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
	for i in range(5):
		var id := SaveManager.record_match(true, 10, 100, "")
		if id != "":
			got.append(id)
	var still_locked := 0
	for s in CardDatabase.all_supports():
		if SaveManager.owned_count(s["id"]) == 0:
			still_locked += 1
	check(got.is_empty() and still_locked == locked, "victories no longer unlock Support cards (%d locked before and after)" % locked)
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


func _test_combos() -> void:
	# role traits: tiers 2 / 4 / 6, every synergy is a special effect (no stat bonus)
	var fxof := func(role: String, counts: Dictionary, key: String) -> float: return float(ComboSystem.unit_mods(role, counts)["fx"].get(key, 0.0))
	check(is_equal_approx(fxof.call("Tank", {"Tank": 2}, "armor"), 0.05) and is_equal_approx(fxof.call("Tank", {"Tank": 4}, "armor"), 0.10) and is_equal_approx(fxof.call("Tank", {"Tank": 6}, "armor"), 0.15), "Iron Wall: Tank armor -5% / -10% / -15% damage taken")
	check(fxof.call("Tank", {"Tank": 2}, "thorns") == 0.0 and is_equal_approx(fxof.call("Tank", {"Tank": 4}, "thorns"), 0.10) and is_equal_approx(fxof.call("Tank", {"Tank": 6}, "thorns"), 0.20), "Iron Wall: thorns from 4 Tanks")
	check(fxof.call("Tank", {"Tank": 1}, "armor") == 0.0 and ComboSystem.active({"Tank": 1}).is_empty(), "one unit of a role is no combo")
	check(is_equal_approx(fxof.call("Marksman", {"Marksman": 2}, "chill"), 3.0) and is_equal_approx(fxof.call("Marksman", {"Marksman": 6}, "chill"), 6.0) and fxof.call("Marksman", {"Marksman": 2}, "frenzy") == 0.0 and fxof.call("Marksman", {"Marksman": 4}, "frenzy") > 0.0, "Pinning Shot: chill from 2 Marksmen, frenzy from 4")
	check(fxof.call("Mage", {"Support": 4}, "armor") > 0.0 and fxof.call("Mage", {"Support": 4}, "mend_self") == 0.0 and fxof.call("Support", {"Support": 4}, "mend_self") > 0.0, "Guardian Aura: only Supports mend, the whole army takes less damage from 4")
	check(fxof.call("Assassin", {"Assassin": 4}, "execute") > 0.0 and fxof.call("Assassin", {"Assassin": 4}, "opener") > 0.0 and fxof.call("Tank", {"Assassin": 4}, "execute") == 0.0, "Shadow Strike: execute + opener for Assassins only")
	check(fxof.call("Controller", {"Controller": 2}, "stun_proc") == 5.0 and fxof.call("Controller", {"Controller": 6}, "stun_proc") == 3.0 and fxof.call("Fighter", {"Controller": 6}, "stun_proc") == 0.0, "Tactician's Command: Controllers stun every 5th / 4th / 3rd attack")
	for r in ComboSystem.ROLES:
		var rm := ComboSystem.unit_mods(r, {r: 6})
		check(float(rm["hp"]) == 0.0 and float(rm["atk"]) == 0.0 and float(rm["shield"]) == 0.0 and int(rm["move"]) == 0 and int(rm["range"]) == 0 and not (rm["fx"] as Dictionary).is_empty(), "role trait %s is a pure special effect (no stat bonus)" % r)
	# role pacts fit their names
	var gc := ComboSystem.duo_mods("Assassin", {"Assassin": 6, "Mage": 6})
	check(float(gc["fx"].get("burn", 0.0)) > 0.0 and float(gc["fx"].get("death_burst", 0.0)) > 0.0 and ComboSystem.duo_mods("Tank", {"Assassin": 6, "Mage": 6})["fx"].is_empty(), "Glass Cannon: Assassin / Mage burn and explode on death, others unchanged")
	check(is_equal_approx(float(ComboSystem.duo_mods("Controller", {"Tank": 6, "Support": 6, "Controller": 6})["fx"].get("armor", 0.0)), 0.06), "Frontline Shield: every unit takes 6% less damage")
	check(float(ComboSystem.duo_mods("Fighter", {"Assassin": 6, "Fighter": 6})["fx"].get("stun_proc", 0.0)) == 4.0 and ComboSystem.duo_mods("Mage", {"Assassin": 6, "Fighter": 6})["fx"].is_empty(), "Pincer Strike: every 4th attack stuns, for Assassin and Fighter only")
	var all7 := {}
	for r in ComboSystem.ROLES:
		all7[r] = 2
	check(ComboSystem.active(all7).any(func(a): return a["name"] == "Grand Army (Role)") and float(ComboSystem.unit_mods("Controller", all7)["fx"].get("lifesteal", 0.0)) >= 0.05, "Grand Army (Role): all 7 roles (2 units each) give every unit armor and lifesteal")
	var all7_one := {}
	for r in ComboSystem.ROLES:
		all7_one[r] = 1
	check(not ComboSystem.active(all7_one).any(func(a): return a["name"] == "Grand Army (Role)"), "Grand Army (Role) needs 2 units of each role, 1 is not enough")
	check(ComboSystem.active({"Tank": 5, "Mage": 6}).all(func(x): return x["kind"] != "duo") and ComboSystem.active({"Tank": 1, "Mage": 1}).is_empty(), "pair role pacts need 6 units of EACH role")
	check(ComboSystem.active({"Tank": 6, "Mage": 6}).any(func(x): return x["name"] == "Spell Bastion"), "6 Tanks + 6 Mages: Spell Bastion")
	check(ComboSystem.missing_units(ComboSystem.DUO_COMBOS[0], {"Tank": 4}) == {"Tank": 2, "Support": 6}, "missing_units lists the units a role pact still lacks")
	check(ComboSystem.DUO_COMBOS.size() == 21, "21 role pacts: one per role pact (Grand Army is not one of them)")
	check(ComboSystem.ROLE_ARMY_UNITS == 2 and (ComboSystem.ROLE_ARMY["needs"] as Dictionary).size() == 7 and ComboSystem.ROLE_ARMY["needs"].values().all(func(n): return int(n) == ComboSystem.ROLE_ARMY_UNITS) and not ComboSystem.DUO_COMBOS.any(func(c): return c["id"] == "grand_army"), "Grand Army (Role) is its own constant: 7 roles x 2 units, not in DUO_COMBOS")
	check(ComboSystem.active(all7).any(func(a): return a["name"] == "Grand Army (Role)" and a["kind"] == "army") and not ComboSystem.active(all7).any(func(a): return a["kind"] == "duo") and ComboSystem.duo_mods("Controller", all7)["fx"].is_empty(), "Grand Army (Role) has its own kind \"army\" and is not counted as a role pact")
	var seen_ids := {}
	var seen_pairs := {}
	for dc in ComboSystem.DUO_COMBOS:
		check(not seen_ids.has(dc["id"]), "role pact id unique: %s" % dc["id"])
		seen_ids[dc["id"]] = true
		var keys: Array = dc["needs"].keys()
		keys.sort()
		check(not seen_pairs.has(str(keys)), "role pact role set unique: %s" % dc["id"])
		seen_pairs[str(keys)] = true
		for r in keys:
			check(ComboSystem.ROLES.has(r), "role pact uses a known role: %s" % dc["id"])
	for i in range(ComboSystem.ROLES.size()):
		for j in range(i + 1, ComboSystem.ROLES.size()):
			var pr := {ComboSystem.ROLES[i]: 6, ComboSystem.ROLES[j]: 6}
			check(ComboSystem.active(pr).any(func(a): return a["kind"] == "duo"), "every role pact has a role pact: %s + %s" % [ComboSystem.ROLES[i], ComboSystem.ROLES[j]])
	var dfx := func(role: String, counts: Dictionary, key: String) -> float: return float(ComboSystem.duo_mods(role, counts)["fx"].get(key, 0.0))
	check(is_equal_approx(dfx.call("Marksman", {"Marksman": 6, "Controller": 6}, "execute"), 0.20) and is_equal_approx(dfx.call("Assassin", {"Assassin": 6, "Support": 6}, "burn"), 0.20), "Target Painting / Alchemist's Fire values")
	check(is_equal_approx(dfx.call("Fighter", {"Tank": 6, "Fighter": 6}, "thorns"), 0.10) and is_equal_approx(dfx.call("Tank", {"Tank": 6, "Fighter": 6}, "guard"), 0.06) and dfx.call("Tank", {"Tank": 6, "Fighter": 6}, "thorns") == 0.0, "Vanguard Line: Fighters thorns, Tanks guard")
	check(is_equal_approx(dfx.call("Fighter", {"Support": 6, "Fighter": 6}, "mend_self"), 0.04) and dfx.call("Mage", {"Support": 6, "Fighter": 6}, "mend_self") == 0.0, "Field Medic: only Fighters mend")
	check(is_equal_approx(dfx.call("Assassin", {"Assassin": 6, "Controller": 6}, "opener"), 0.50) and dfx.call("Fighter", {"Assassin": 6, "Controller": 6}, "opener") == 0.0, "Ambush Plan: first strike for Assassins only")
	check(is_equal_approx(dfx.call("Tank", {"Support": 6, "Controller": 6}, "mend_self"), 0.02), "Supply Line: every unit mends 2% HP")
	for dc in ComboSystem.DUO_COMBOS:  # no role pact is a stat bonus any more
		for e in dc["effects"]:
			check(not (e.has("hp") or e.has("atk") or e.has("shield") or e.has("move") or e.has("range")), "role pact %s has no stat bonus" % dc["id"])
			check(ComboSystem.FX_TYPES.any(func(k): return e.has(k)), "role pact %s has a special effect" % dc["id"])
	var all_facs: Array = []
	for cont in GameData.continents:
		for f in cont.get("factions", []):
			all_facs.append(String(f["id"]))
	check(all_facs.size() == 28 and ComboSystem.FACTION_TRAITS.size() == 28, "28 factions, each with its own trait")
	for fid in all_facs:
		check(ComboSystem.FACTION_TRAITS.has(fid), "faction trait exists: %s" % fid)
		check(ComboSystem.faction_trait_effects(fid, 1).is_empty() and not ComboSystem.faction_trait_effects(fid, 2).is_empty(), "faction trait starts at 2 units: %s" % fid)
		for e in ComboSystem.FACTION_TRAITS[fid]["effects"]:
			for k in ComboSystem.STAT_KEYS:
				check(not e.has(k), "faction trait %s has no stat bonus (%s)" % [fid, k])
			var has_fx := false
			for k in ComboSystem.FX_TYPES:
				if e.has(k):
					has_fx = true
					check((e[k] as Array).size() == 3, "trait effect has 3 tiers: %s %s" % [fid, k])
			check(has_fx, "faction trait effect is a special effect: %s" % fid)
	var tfx := func(role: String, fac: String, n: int, key: String, ultra: bool = false) -> float: return float(ComboSystem.unit_mods(role, {}, fac, n, ultra)["fx"].get(key, 0.0))
	check(is_equal_approx(tfx.call("Fighter", "solvaris", 2, "mend_self"), 0.02) and is_equal_approx(tfx.call("Fighter", "solvaris", 6, "mend_self"), 0.04), "Dawn Ward scales with the tier: mend 2% at 2 units, 4% at 6")
	check(tfx.call("Tank", "nocthyr", 6, "opener") == 0.0 and is_equal_approx(tfx.call("Assassin", "nocthyr", 4, "opener"), 0.30), "Nightfall only gives Assassin / Marksman the opener")
	check(tfx.call("Marksman", "voltrix", 2, "stun_proc") == 6.0 and tfx.call("Marksman", "voltrix", 6, "stun_proc") == 4.0 and tfx.call("Marksman", "voltrix", 8, "stun_proc", true) == 3.0 and tfx.call("Tank", "voltrix", 8, "stun_proc", true) == 0.0, "Overcharge: Marksman stun every 6th / 4th attack, 3rd in Ultra (count / 1.5)")
	check(tfx.call("Mage", "inferna", 2, "death_burst") > 0.0 and tfx.call("Mage", "inferna", 2, "atk") == 0.0 and float(ComboSystem.unit_mods("Mage", {}, "inferna", 2)["hp"]) == 0.0, "Hellfire: a death burst, no stat change")
	check(tfx.call("Mage", "astralis", 4, "splash") == 0.0 and tfx.call("Mage", "astralis", 6, "splash") > 0.0, "Astral Drift: splash only at 6 units")
	check(is_equal_approx(float(ComboSystem.unit_mods("Tank", {"Tank": 2}, "terragorn", 2)["fx"]["armor"]), 0.05 + 0.04), "faction trait stacks with role traits")
	check(ComboSystem.unit_mods("Tank", {}, "", 6)["fx"].is_empty() and ComboSystem.faction_tier_index(1) == -1 and ComboSystem.faction_tier_index(2) == 0 and ComboSystem.faction_tier_index(4) == 1 and ComboSystem.faction_tier_index(7) == 2, "faction tier index")
	var eight_same: Array = []
	for _i in range(8):
		eight_same.append("solvaris")
	check(ComboSystem.faction_ultra(eight_same) == "solvaris" and ComboSystem.faction_ultra(eight_same.slice(0, 7)) == "", "Ultra faction needs 8+ units")
	var mixed := eight_same.duplicate()
	mixed[3] = "nocthyr"
	var with_none := eight_same.duplicate()
	with_none[0] = ""
	check(ComboSystem.faction_ultra(mixed) == "" and ComboSystem.faction_ultra(with_none) == "", "Ultra faction: every unit must share one home faction")
	check(ComboSystem.faction_bonus(8, true) == 0.0 and ComboSystem.faction_tier_name(8, true) == "Ultra" and ComboSystem.faction_bonus(6) == 0.0 and ComboSystem.faction_bonus(2) == 0.0, "no flat HP/ATK banner bonus in any Faction Tier or Ultra")
	check(is_equal_approx(tfx.call("Fighter", "solvaris", 8, "mend_self", true), 0.06), "Ultra scales the faction trait x1.5 (Dawn Ward 4% -> 6%)")
	check(tfx.call("Mage", "elarion", 6, "chill") == 4.0 and tfx.call("Mage", "elarion", 8, "chill", true) == 6.0, "Ultra lengthens a chill x1.5 (4 -> 6 ticks)")
	check(ComboSystem.role_ultra({"Tank": 8}) == "Tank" and ComboSystem.role_ultra({"Tank": 7}) == "" and ComboSystem.role_ultra({"Tank": 8, "Mage": 1}) == "", "Ultra role: all units one role, 8+")
	check(is_equal_approx(fxof.call("Tank", {"Tank": 8}, "armor"), 0.15 * 1.5) and is_equal_approx(fxof.call("Tank", {"Tank": 7, "Mage": 1}, "armor"), 0.15), "Ultra Iron Wall x1.5 only when ALL units are Tanks")
	# Ultra special effects (flat, only in Ultra)
	check(is_equal_approx(tfx.call("Fighter", "solvaris", 8, "lifesteal", true), 0.08) and is_equal_approx(tfx.call("Fighter", "solvaris", 8, "frenzy", true), 0.04) and tfx.call("Fighter", "solvaris", 6, "lifesteal") == 0.0, "Ultra: lifesteal + frenzy bonus only in Faction Ultra")
	check(String(ComboSystem.faction_tier("solvaris", 8, true)["special"]) == "Ultra" and String(ComboSystem.faction_tier("solvaris", 6)["special"]) == "" and ComboSystem.faction_tier_text(ComboSystem.faction_tier("solvaris", 8, true)).contains("; Ultra: "), "Faction Tier shows the Ultra special only in Ultra")
	check(is_equal_approx(fxof.call("Tank", {"Tank": 8}, "second_life"), 0.30) and fxof.call("Tank", {"Tank": 7, "Mage": 1}, "second_life") == 0.0, "Role Ultra special: Unbreakable (Tanks return once at 30% HP) only when ALL units are Tanks")
	check(fxof.call("Assassin", {"Assassin": 8}, "evade") == 3.0 and fxof.call("Mage", {"Mage": 8}, "burn") > 0.0 and fxof.call("Marksman", {"Marksman": 8}, "execute") > 0.0 and fxof.call("Controller", {"Controller": 8}, "stun_proc") == 3.0 and ComboSystem.scaled_fx_value("evade", 4.0, 1.5) == 3.0, "Role Ultra specials: Phantom Rush / Arcane Overreach / Deadeye Volley / Grand Strategy")
	for r in ComboSystem.ROLES:
		check(not ComboSystem.role_ultra_special(r).is_empty(), "every role has an Ultra special (%s)" % r)
	check(ComboSystem.faction_tier_name(2) == "Rally" and ComboSystem.faction_tier_name(4) == "Legion" and ComboSystem.faction_tier_name(6) == "Host" and ComboSystem.faction_bonus(6) == 0.0 and ComboSystem.faction_tier_name(1) == "", "Faction Banner tiers: Rally / Legion / Host")
	# Grand Army (Faction): every faction of the continent with 2+ units
	var cfacs: Array = ["solvaris", "nocthyr", "valdoria", "elarion"]
	check(ComboSystem.faction_army_active({"solvaris": 4, "nocthyr": 4, "valdoria": 3, "elarion": 3}, cfacs) and ComboSystem.faction_army_active({"solvaris": 2, "nocthyr": 2, "valdoria": 2, "elarion": 2}, cfacs) and ComboSystem.faction_army_active({"solvaris": 2, "nocthyr": 2, "valdoria": 2, "elarion": 8}, cfacs), "Grand Army (Faction): 2+ units of EVERY faction (8 units in all)")
	check(not ComboSystem.faction_army_active({"solvaris": 2, "nocthyr": 2, "valdoria": 2, "elarion": 1}, cfacs) and not ComboSystem.faction_army_active({"solvaris": 5, "nocthyr": 5, "valdoria": 4, "elarion": 1}, cfacs) and not ComboSystem.faction_army_active({"solvaris": 14}, cfacs) and not ComboSystem.faction_army_active({}, []), "Grand Army (Faction): one faction short or one faction only is not enough")
	check(ComboSystem.faction_army_missing({"solvaris": 2, "nocthyr": 1}, cfacs) == {"nocthyr": 1, "valdoria": 2, "elarion": 2}, "faction_army_missing lists the units still lacking per faction")
	check(ComboSystem.faction_army_lacking({"solvaris": 2, "nocthyr": 2, "valdoria": 2, "elarion": 2}, cfacs) == 0 and ComboSystem.faction_army_lacking({"solvaris": 5, "nocthyr": 5, "valdoria": 4, "elarion": 0}, cfacs) == 2 and ComboSystem.faction_army_lacking({"solvaris": 2, "nocthyr": 2, "valdoria": 1}, cfacs) == 3, "faction_army_lacking: the larger of the thin-faction gap and the 8-unit gap")
	var cb_ok := ComboSystem.CONTINENT_BONDS.size() == 7
	var realms := {}  # per continent: units of its best-staffed faction
	for cid in ["aetherion", "arcanum", "machina", "sylvaris", "drakmor", "thalassia", "eclipsia"]:
		cb_ok = cb_ok and not ComboSystem.continent_bond(cid).is_empty() and not ComboSystem.unit_mods("Tank", {}, "", 0, false, false, ComboSystem.continent_bond(cid))["fx"].is_empty()
		realms[cid] = 2
	# Continent Alliance: 2 units of one faction in EVERY continent; the effect is the one of the KING's continent only
	cb_ok = cb_ok and ComboSystem.bonds_for(realms, "drakmor").get("names", []) == ["War Fever"] and ComboSystem.bonds_for(realms, "eclipsia").get("names", []) == ["Time Slip"] and ComboSystem.bonds_for(realms, "aetherion").get("names", []) == ["Royal Standard"]
	var dr_fx: Dictionary = ComboSystem.unit_mods("Tank", {}, "", 0, false, false, ComboSystem.bonds_for(realms, "drakmor"))["fx"]
	cb_ok = cb_ok and dr_fx.size() == 1 and is_equal_approx(float(dr_fx.get("rage", 0.0)), 0.08)
	var six := realms.duplicate()
	six["machina"] = 1  # one faction group short
	cb_ok = cb_ok and ComboSystem.bonds_for(six, "drakmor").is_empty() and ComboSystem.bond_missing(six) == ["machina"] and ComboSystem.bonds_for({"arcanum": 9}, "arcanum").is_empty() and ComboSystem.bonds_for(realms, "").is_empty() and ComboSystem.bonds_for(realms, "unknown").is_empty() and ComboSystem.bond_missing(realms).is_empty()
	check(cb_ok and ComboSystem.unit_mods("Tank", {})["fx"].is_empty(), "Continent Alliance: 2 units of one faction in all 7 continents, the effect of the King's continent; one continent short is not enough")
	check(is_equal_approx(float(ComboSystem.unit_mods("Tank", {}, "", 0, false, true)["fx"]["last_rites"]), 0.10) and is_equal_approx(float(ComboSystem.unit_mods("Mage", {}, "", 0, false, true)["fx"]["mend_self"]), 0.03) and ComboSystem.unit_mods("Tank", {})["fx"].is_empty(), "Grand Army (Faction): last rites + mend for every unit")
	# Continent Specialties: 6 synergies, each pairs a continent with the role that fits it (6 units of ONE faction of the continent AND 6 units of the role; the effect reaches the units of that role)
	var cr_conts := {}
	var cr_roles := {}
	var cr_data_ok := ComboSystem.CONTINENT_ROLE_COMBOS.size() == 6 and ComboSystem.CONTINENT_ROLE_FACTION_UNITS == 6 and ComboSystem.CONTINENT_ROLE_UNITS == 6
	for cc in ComboSystem.CONTINENT_ROLE_COMBOS:
		cr_conts[String(cc["continent"])] = true
		cr_roles[String(cc["role"])] = true
		cr_data_ok = cr_data_ok and not GameData.get_continent(String(cc["continent"])).is_empty() and ComboSystem.ROLES.has(String(cc["role"])) and String(cc["blurb"]) != ""
		for ce in cc["effects"]:
			cr_data_ok = cr_data_ok and typeof(ce["to"]) == TYPE_ARRAY and (ce["to"] as Array).has(String(cc["role"])) and ComboSystem.FX_TYPES.any(func(k): return ce.has(k)) and not ComboSystem.STAT_KEYS.any(func(k): return ce.has(k))
	check(cr_data_ok and cr_conts.size() == 6 and cr_roles.size() == 6, "6 Continent Specialties: 6 different continents x 6 different roles, special effects only")
	var cr_pairs := {"aetherion": "Tank", "arcanum": "Mage", "machina": "Controller", "sylvaris": "Support", "drakmor": "Fighter", "eclipsia": "Assassin"}
	var cr_pair_ok := true
	for cid in cr_pairs:
		cr_pair_ok = cr_pair_ok and String(ComboSystem.continent_role_combo(String(cid), String(cr_pairs[cid])).get("role", "")) == String(cr_pairs[cid])
	check(cr_pair_ok and ComboSystem.continent_role_combo("arcanum", "Tank").is_empty() and ComboSystem.continent_role_combo("thalassia", "Marksman").is_empty(), "Continent Specialties: each continent is paired with the role that fits it")
	var cr_arc := {"arcanum|Mage": {"faction": 6, "role": 6}}
	var cr_act := ComboSystem.continent_role_active(cr_arc)
	check(cr_act.size() == 1 and String(cr_act[0]["name"]) == "Rune Cascade", "Continent Specialty: 6 units of one Arcanum faction + 6 Mages switch it on")
	check(ComboSystem.continent_role_active({"arcanum|Mage": {"faction": 5, "role": 6}}).is_empty() and ComboSystem.continent_role_active({"arcanum|Mage": {"faction": 6, "role": 5}}).is_empty() and ComboSystem.continent_role_active({"arcanum|Mage": {"faction": 12, "role": 0}}).is_empty() and ComboSystem.continent_role_active({"machina|Mage": {"faction": 9, "role": 9}, "arcanum|Tank": {"faction": 9, "role": 9}}).is_empty() and ComboSystem.continent_role_active({}).is_empty(), "Continent Specialty needs BOTH halves: 5 faction units or 5 role units, another continent / role pact do not switch it on")
	var cr_l1 := ComboSystem.continent_role_lacking(cr_act[0], {"arcanum|Mage": {"faction": 4, "role": 5}})
	var cr_l0 := ComboSystem.continent_role_lacking(cr_act[0], cr_arc)
	var cr_le := ComboSystem.continent_role_lacking(cr_act[0], {})
	check(int(cr_l1["faction"]) == 2 and int(cr_l1["role"]) == 1 and int(cr_l0["faction"]) == 0 and int(cr_l0["role"]) == 0 and int(cr_le["faction"]) == 6 and int(cr_le["role"]) == 6, "continent_role_lacking: units of the faction and of the role a Continent Specialty still needs")
	var cr_mage: Dictionary = ComboSystem.unit_mods("Mage", {}, "", 0, false, false, {}, cr_act, "arcanum")["fx"]
	check(is_equal_approx(float(cr_mage.get("splash", 0.0)), 0.20) and int(cr_mage.get("chill", 0)) == 2 and cr_mage.size() == 2, "Rune Cascade: Mages splash 20% and slow 2 ticks")
	check(not ComboSystem.unit_mods("Mage", {}, "", 0, false, false, {}, cr_act, "machina")["fx"].is_empty() and ComboSystem.unit_mods("Tank", {}, "", 0, false, false, {}, cr_act, "arcanum")["fx"].is_empty(), "Continent Specialty reaches the units of its ROLE (any faction), a Tank gets nothing from Rune Cascade")
	var cr_all: Array = []
	for cid in cr_pairs:
		cr_all.append(ComboSystem.continent_role_combo(String(cid), String(cr_pairs[cid])))
	var cr_each_ok := true
	for cid in cr_pairs:
		cr_each_ok = cr_each_ok and not ComboSystem.unit_mods(String(cr_pairs[cid]), {}, "", 0, false, false, {}, cr_all, String(cid))["fx"].is_empty()
	check(cr_each_ok and ComboSystem.unit_mods("Marksman", {}, "", 0, false, false, {}, cr_all, "thalassia")["fx"].is_empty(), "all 6 Continent Specialties give their units an effect; Marksmen get none (no combo)")
	check(is_equal_approx(float(ComboSystem.unit_mods("Tank", {"Tank": 2}, "", 0, false, false, {}, [ComboSystem.continent_role_combo("aetherion", "Tank")], "aetherion")["fx"].get("thorns", 0.0)), 0.08) and is_equal_approx(float(ComboSystem.unit_mods("Tank", {"Tank": 4}, "", 0, false, false, {}, [ComboSystem.continent_role_combo("aetherion", "Tank")], "aetherion")["fx"].get("thorns", 0.0)), 0.18), "Continent Specialty stacks with the role trait (Iron Wall thorns + Royal Bulwark thorns)")
	# Continent Formation: 4 units of ONE faction of the KING's continent give those units the effect of that continent
	var fm_act := ComboSystem.formation_active({"solvaris": 4, "drakhan": 5, "nocthyr": 4}, "aetherion")
	check(fm_act.size() == 2 and String(fm_act[0]["name"]) == "Crown Phalanx" and String(fm_act[1]["name"]) == "Crown Phalanx", "Continent Formation: only factions of the King's continent with 4+ units qualify (Drakhan of Drakmor does not)")
	check(ComboSystem.formation_active({"solvaris": 3}, "aetherion").is_empty() and ComboSystem.formation_active({}, "aetherion").is_empty() and ComboSystem.formation_active({"solvaris": 9}, "").is_empty() and ComboSystem.formation_active({"drakhan": 9}, "aetherion").is_empty(), "Continent Formation: 3 units, no King or a foreign continent do not switch it on")
	check(ComboSystem.formation_lacking(3) == 1 and ComboSystem.formation_lacking(4) == 0 and ComboSystem.formation_lacking(9) == 0, "Continent Formation: lacking counts down to 0")
	check(ComboSystem.formation_effects_for("solvaris", 3, "aetherion").is_empty() and not ComboSystem.formation_effects_for("solvaris", 4, "aetherion").is_empty() and ComboSystem.formation_effects_for("solvaris", 9, "drakmor").is_empty() and ComboSystem.formation_effects_for("solvaris", 9, "").is_empty() and ComboSystem.formation_effects_for("", 9, "aetherion").is_empty(), "Continent Formation: effects only from 4 units of a faction of the King's continent")
	var fm_all_ok := true
	for cid in ComboSystem.CONTINENT_BONDS:
		var fmd := ComboSystem.formation_of(String(cid))
		fm_all_ok = fm_all_ok and not fmd.is_empty() and not ComboSystem.unit_mods("Tank", {}, "", 0, false, false, {}, [], "", fmd["effects"])["fx"].is_empty()
	check(fm_all_ok and ComboSystem.CONTINENT_FORMATIONS.size() == ComboSystem.CONTINENT_BONDS.size() and ComboSystem.formation_of("nowhere").is_empty(), "Continent Formation: every continent has its own themed formation")
	var fm_dr: Dictionary = ComboSystem.unit_mods("Fighter", {}, "", 0, false, false, {}, [], "", ComboSystem.formation_effects_for("drakhan", 4, "drakmor"))["fx"]
	check(is_equal_approx(float(fm_dr.get("frenzy", 0.0)), 0.04) and is_equal_approx(float(fm_dr.get("rage", 0.0)), 0.06), "Warband Frenzy (Drakmor King, Drakhan units): +4% ATK per kill and +6% under half HP")
	var fm_stack: Dictionary = ComboSystem.unit_mods("Tank", {}, "solvaris", 4, false, false, {}, [], "", ComboSystem.formation_effects_for("solvaris", 4, "aetherion"))["fx"]
	check(is_equal_approx(float(fm_stack.get("armor", 0.0)), 0.04) and is_equal_approx(float(fm_stack.get("guard", 0.0)), 0.03) and float(fm_stack.get("mend_self", 0.0)) > 0.0, "Continent Formation stacks with, and does not replace, the faction trait")
	# Faction Tier: Faction Banner + faction trait fused into one tier (numbers unchanged)
	var ft_h := ComboSystem.faction_tier("solvaris", 6)
	check(ComboSystem.faction_tier("solvaris", 1).is_empty() and String(ft_h["name"]) == "Host" and is_equal_approx(float(ft_h["bonus"]), 0.0) and String(ft_h["trait"]) == "Dawn Ward" and not (ft_h["trait_effects"] as Array).is_empty(), "Faction Tier: 6 units = Dawn Ward at full tier, no banner bonus")
	check(ComboSystem.faction_tier_text(ft_h).begins_with("Dawn Ward:") and String(ComboSystem.faction_tier("solvaris", 8, true)["name"]) == "Ultra" and is_equal_approx(float(ComboSystem.faction_tier("solvaris", 8, true)["bonus"]), 0.0), "Faction Tier text and Ultra tier")
	check(int(ComboSystem.faction_tier("solvaris", 2)["next"]) == 4 and int(ft_h["next"]) == 0, "Faction Tier: units for the next tier")
	# the engine applies them: a full faction line-up gets the Frontline Shield, a lone unit does not
	CardDatabase.set_continent("aetherion")
	var pieces := CardDatabase.faction_pieces("solvaris")
	var full: Array = []
	for i in range(pieces.size()):
		full.append({"card_id": String(pieces[i]["id"]), "stars": 1, "cell": Vector2i(i, 7)})
	var champ := String(GameData.find_faction("solvaris").get("champion", ""))
	var e := BattleEngine.new()
	e.setup({"seed": 3, "sides": [{"units": full, "champion": champ, "supports": []}, {"units": [], "champion": champ, "supports": []}]})
	var fx_ok := e.units_of(0).size() > 0
	for u in e.units_of(0):
		if not u.is_king and u.fx.is_empty():
			fx_ok = false
	check(fx_ok, "the engine gives every unit of the line-up its synergy special effects")
	var lone := BattleEngine.new()
	lone.setup({"seed": 3, "sides": [{"units": [full[0]], "champion": champ, "supports": []}, {"units": [], "champion": champ, "supports": []}]})
	var lone_ok := true
	for u in lone.units_of(0):
		if not u.is_king and not u.fx.is_empty():
			lone_ok = false
	check(lone_ok, "a lone unit has no synergy effect")
	# Continent Alliance in the engine: 2 units of ONE faction in each of the 7 continents on one side (a mixed-continent line-up), King of Aetherion / Drakmor
	var fourteen: Array = []
	var thirteen: Array = []
	for ci in range(GameData.continents.size()):
		var cid := String(GameData.continents[ci]["id"])
		if not ComboSystem.CONTINENT_BONDS.has(cid):
			continue
		var fid := String((GameData.continents[ci]["factions"] as Array)[0]["id"])
		var taken := 0
		for cu in CardDatabase.units_of_continent(cid):
			if String(cu["chess"]) != "pawn" and String(cu["faction"]) == fid and taken < 2:
				taken += 1
				fourteen.append({"card_id": String(cu["id"]), "stars": 1, "cell": Vector2i(fourteen.size() & 7, 7 - (fourteen.size() >> 3))})
				if not (cid == "machina" and taken == 2):
					thirteen.append({"card_id": String(cu["id"]), "stars": 1, "cell": Vector2i(thirteen.size() & 7, 7 - (thirteen.size() >> 3))})
	var drak_champ := String(GameData.find_faction("drakhan").get("champion", ""))
	var se := BattleEngine.new()
	se.setup({"seed": 3, "sides": [{"units": fourteen, "champion": champ, "supports": []}, {"units": [], "champion": champ, "supports": []}]})
	check(fourteen.size() == 14 and se.log_lines.any(func(l): return String(l).contains("Continent Alliance - Royal Standard")), "Continent Alliance: 14 units (2 of one faction per continent) give every unit the effect of the Aetherion King")
	var sd := BattleEngine.new()
	sd.setup({"seed": 3, "sides": [{"units": fourteen, "champion": drak_champ, "supports": []}, {"units": [], "champion": champ, "supports": []}]})
	check(sd.log_lines.any(func(l): return String(l).contains("Continent Alliance - War Fever")) and not sd.log_lines.any(func(l): return String(l).contains("Royal Standard")), "Continent Alliance: a Drakmor King gets War Fever only (the effect follows the King's continent)")
	var s13 := BattleEngine.new()
	s13.setup({"seed": 3, "sides": [{"units": thirteen, "champion": champ, "supports": []}, {"units": [], "champion": champ, "supports": []}]})
	check(not s13.log_lines.any(func(l): return String(l).contains("Continent Alliance")), "Continent Alliance: one continent short (13 units) gives nothing")
	_test_continent_role_engine()
	_test_synergy_fx_engine()


## One line-up for the engine tests: cards laid out on rows 7 and 6 (8 per row).
func _cr_line(cards: Array) -> Array:
	var line: Array = []
	for i in range(cards.size()):
		line.append({"card_id": String(cards[i]["id"]), "stars": 1, "cell": Vector2i(i % 8, 7 - i / 8)})
	return line


## Continent Specialties in the engine: 6 units of one faction of the continent + 6 units of its role switch it on (and only the units of that role get the effect),
## 5 of either half do not, and every pair fires for its own continent.
func _test_continent_role_engine() -> void:
	CardDatabase.set_continent("arcanum")
	var fac := "astralis"
	var champ := String(GameData.find_faction(fac).get("champion", ""))
	var foes := {"units": [], "champion": champ, "supports": []}
	var pieces: Array = CardDatabase.faction_pieces(fac)  # the 7 pieces of the faction, one per role
	var non_mage: Array = []
	for p in pieces:
		if String(p["role"]) != "Mage":
			non_mage.append(p)
	var faction_six: Array = []  # 6 units of Astralis (no Mage among them: the role half comes from the other factions)
	for i in range(6):
		faction_six.append(non_mage[i % non_mage.size()])
	var mages: Array = []  # Arcanum Mages of the OTHER factions (the role half can come from any faction)
	for cu in CardDatabase.units_of_continent("arcanum"):
		if String(cu["chess"]) != "pawn" and String(cu["role"]) == "Mage" and String(cu["faction"]) != fac:
			mages.append(cu)
	var mage_six: Array = []
	for i in range(6):
		mage_six.append(mages[i % mages.size()])
	var line: Array = faction_six + mage_six
	var en := BattleEngine.new()
	en.setup({"seed": 3, "sides": [{"units": _cr_line(line), "champion": champ, "supports": []}, foes]})
	var mage_ok := true
	for u in en.units_of(0):
		if not u.is_king and u.role == "Mage":
			mage_ok = mage_ok and int(u.fx.get("chill", 0)) >= 2 and float(u.fx.get("splash", 0.0)) >= 0.20 - 0.0001
	check(mage_ok and en.log_lines.any(func(l): return String(l).contains("synergy: Rune Cascade")), "Continent Specialty in the engine: 6 Astralis units + 6 Mages give the Mages Rune Cascade (splash + slow)")
	var no5f := BattleEngine.new()  # only 5 units of the faction
	no5f.setup({"seed": 3, "sides": [{"units": _cr_line(faction_six.slice(0, 5) + mage_six), "champion": champ, "supports": []}, foes]})
	check(not no5f.log_lines.any(func(l): return String(l).contains("Rune Cascade")), "Continent Specialty in the engine: 5 units of the faction + 6 Mages are not enough")
	var no5r := BattleEngine.new()  # only 5 Mages
	no5r.setup({"seed": 3, "sides": [{"units": _cr_line(faction_six + mage_six.slice(0, 5)), "champion": champ, "supports": []}, foes]})
	check(not no5r.log_lines.any(func(l): return String(l).contains("Rune Cascade")), "Continent Specialty in the engine: 6 units of the faction + 5 Mages are not enough")
	var no_f := BattleEngine.new()  # 6 Mages of mixed factions and nothing else: the faction half is missing
	no_f.setup({"seed": 3, "sides": [{"units": _cr_line(mage_six), "champion": champ, "supports": []}, foes]})
	check(not no_f.log_lines.any(func(l): return String(l).contains("Rune Cascade")), "Continent Specialty in the engine: 6 Mages without 6 units of one faction are not enough")
	# Continent Formation in the engine: 4 units of one faction of the KING's continent give THOSE units its effect (King Astralis = Arcanum: Runic Circle)
	var fm4 := BattleEngine.new()
	fm4.setup({"seed": 3, "sides": [{"units": _cr_line(faction_six.slice(0, 4)), "champion": champ, "supports": []}, foes]})
	var fm_ok := true
	for u in fm4.units_of(0):
		if not u.is_king:
			fm_ok = fm_ok and float(u.fx.get("splash", 0.0)) >= 0.12 - 0.0001 and float(u.fx.get("burn", 0.0)) >= 0.05 - 0.0001
	check(fm_ok and fm4.log_lines.any(func(l): return String(l).contains("synergy: Runic Circle")), "Continent Formation in the engine: 4 Astralis units under an Arcanum King get Runic Circle (splash + burn)")
	var fm3 := BattleEngine.new()
	fm3.setup({"seed": 3, "sides": [{"units": _cr_line(faction_six.slice(0, 3)), "champion": champ, "supports": []}, foes]})
	check(not fm3.log_lines.any(func(l): return String(l).contains("Runic Circle")), "Continent Formation in the engine: 3 units of a faction are not enough")
	var drakhan_units: Array = []
	for cu in CardDatabase.units_of_continent("drakmor"):
		if String(cu["chess"]) != "pawn" and String(cu["faction"]) == "drakhan":
			drakhan_units.append(cu)
	var fmf := BattleEngine.new()  # 4 Drakhan units (a foreign continent) under an Arcanum King: no formation, no Warband Frenzy
	fmf.setup({"seed": 3, "sides": [{"units": _cr_line(drakhan_units.slice(0, 4)), "champion": champ, "supports": []}, foes]})
	var fm_none := true
	for u in fmf.units_of(0):
		fm_none = fm_none and float(u.fx.get("frenzy", 0.0)) == 0.0 and float(u.fx.get("burn", 0.0)) == 0.0
	check(fm_none and not fmf.log_lines.any(func(l): return String(l).contains("Warband Frenzy") or String(l).contains("Runic Circle")), "Continent Formation in the engine: 4 units of a faction of ANOTHER continent get nothing")
	var other_arc := ""
	for f in GameData.get_continent("arcanum").get("factions", []):
		if String(f["id"]) != fac:
			other_arc = String(f["id"])
			break
	var oa_units: Array = []
	for cu in CardDatabase.units_of_continent("arcanum"):
		if String(cu["chess"]) != "pawn" and String(cu["faction"]) == other_arc:
			oa_units.append(cu)
	var fmo := BattleEngine.new()  # 4 units of ANOTHER faction of the King's continent qualify too
	fmo.setup({"seed": 3, "sides": [{"units": _cr_line(oa_units.slice(0, 4)), "champion": champ, "supports": []}, foes]})
	check(fmo.log_lines.any(func(l): return String(l).contains("synergy: Runic Circle")), "Continent Formation in the engine: 4 units of another faction of the King's continent qualify")
	# every pair switches on in the engine: 6 units of one faction of its continent + 6 units of its role
	var all_ok := true
	for c in ComboSystem.CONTINENT_ROLE_COMBOS:
		var cid := String(c["continent"])
		var role := String(c["role"])
		CardDatabase.set_continent(cid)
		var f_id := String(GameData.get_continent(cid)["factions"][0]["id"])
		var f_champ := String(GameData.find_faction(f_id).get("champion", ""))
		var f_cards: Array = []
		for p in CardDatabase.faction_pieces(f_id):
			if String(p["role"]) != role:
				f_cards.append(p)
		var r_cards: Array = []
		for cu in CardDatabase.units_of_continent(cid):
			if String(cu["chess"]) != "pawn" and String(cu["role"]) == role and String(cu["faction"]) != f_id:
				r_cards.append(cu)
		var ln: Array = []
		for i in range(6):
			ln.append(f_cards[i % f_cards.size()])
		for i in range(6):
			ln.append(r_cards[i % r_cards.size()])
		var eg := BattleEngine.new()
		eg.setup({"seed": 3, "sides": [{"units": _cr_line(ln), "champion": f_champ, "supports": []}, {"units": [], "champion": f_champ, "supports": []}]})
		all_ok = all_ok and not f_cards.is_empty() and not r_cards.is_empty() and eg.log_lines.any(func(l): return String(l).contains("synergy: " + String(c["name"])))
	check(all_ok, "Continent Specialties in the engine: every one of the 6 pairs switches on with 6 units of one faction + 6 units of its role")
	CardDatabase.set_continent("aetherion")


## The engine really applies each synergy special effect in a fight (unit.fx -> _x() in the attack / damage / death hooks).
func _test_synergy_fx_engine() -> void:
	CardDatabase.set_continent("aetherion")
	var pieces := CardDatabase.faction_pieces("solvaris")
	var champ := String(GameData.find_faction("solvaris").get("champion", ""))
	var mk := func() -> BattleEngine:
		var en := BattleEngine.new()
		en.setup({"seed": 5, "sides": [{"units": [{"card_id": String(pieces[0]["id"]), "stars": 1, "cell": Vector2i(0, 7)}, {"card_id": String(pieces[1]["id"]), "stars": 1, "cell": Vector2i(1, 7)}], "champion": champ, "supports": []},
			{"units": [{"card_id": String(pieces[0]["id"]), "stars": 1, "cell": Vector2i(0, 0)}, {"card_id": String(pieces[1]["id"]), "stars": 1, "cell": Vector2i(1, 0)}], "champion": champ, "supports": []}]})
		return en
	var en: BattleEngine = mk.call()
	var a: BattleUnit = en.units_of(0).filter(func(x): return not x.is_king)[0]
	var b: BattleUnit = en.units_of(1).filter(func(x): return not x.is_king)[0]
	a.fx = {}
	a.extra = ""
	b.fx = {}
	b.extra = ""
	b.shield = 0
	# armor: the target takes less damage
	var plain := en._damage(b, 100)
	b.hp = b.max_hp
	b.fx = {"armor": 0.3}
	var armored := en._damage(b, 100)
	check(armored < plain and armored == 70, "synergy fx armor: -30%% damage taken (%d vs %d)" % [armored, plain])
	# evade: every 2nd hit is avoided
	b.hp = b.max_hp
	b.fx = {"evade": 2}
	b.hits_taken = 0
	var h1 := en._damage(b, 50)
	var h2 := en._damage(b, 50)
	check(h1 > 0 and h2 == 0, "synergy fx evade: every 2nd hit is avoided")
	# burn / chill / stun_proc / lifesteal / thorns come from the attacker's / target's fx
	b.hp = b.max_hp
	b.fx = {"thorns": 0.5}
	a.fx = {"burn": 0.2, "chill": 3, "stun_proc": 1, "lifesteal": 0.5}
	a.hp = maxi(1, a.max_hp - 50)
	var hp_a := a.hp
	en._attack(a, b)
	check(b.burn_until > en.tick and b.burn_amount > 0, "synergy fx burn sets the target ablaze")
	check(b.slow_until > en.tick and b.stun_until > en.tick, "synergy fx chill slows and stun_proc stuns the target")
	check(a.hp != hp_a, "synergy fx lifesteal / thorns change the attacker's HP")
	# execute / opener
	en = mk.call()
	a = en.units_of(0).filter(func(x): return not x.is_king)[0]
	b = en.units_of(1).filter(func(x): return not x.is_king)[0]
	a.fx = {"execute": 1.0}
	a.extra = ""
	b.hp = maxi(1, int(b.max_hp * 0.2))
	var base := en.atk_now(a)
	var before := b.hp
	b.shield = 0
	en._attack(a, b)
	check(before - maxi(b.hp, 0) >= base, "synergy fx execute: bonus damage against a wounded target")
	# frenzy / rage / aura_atk feed atk_now
	a.fx = {"frenzy": 0.1, "rage": 0.5}
	a.kills = 3
	a.hp = a.max_hp / 4
	check(en.atk_now(a) > int(round(a.base_atk * 1.3)), "synergy fx frenzy + rage raise ATK")
	# second_life / last_rites / death_burst on death
	en = mk.call()
	a = en.units_of(0).filter(func(x): return not x.is_king)[0]
	a.fx = {"second_life": 0.4}
	a.extra = ""
	a.shield = 0
	en._kill(a)
	check(a.alive and a.hp == maxi(1, int(a.max_hp * 0.4)), "synergy fx second_life: returns once")
	en._kill(a)
	check(not a.alive, "second_life only works once")
