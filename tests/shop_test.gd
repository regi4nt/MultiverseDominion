extends Node
## Shop: Aether Coins, Gacha (rates, pity, duplicates, 10-pull guarantee) and direct purchase.
## Run: godot --headless --path . res://tests/shop_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	var saved: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data["collection"].clear()
	SaveManager.ensure_collection()
	SaveManager.data["wallet"]["coins"] = ShopSystem.START_COINS
	SaveManager.data["shop"] = {"pity": 0, "pity_rare": 0, "pity_legendary": 0, "pulls": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# --- Arena random map: every playable continent has its own bonus, paid only on a win
	var all_have := true
	for cont in GameData.continents:
		if cont.get("playable", false) and ShopSystem.random_bonus(String(cont["id"])).is_empty():
			all_have = false
	check(all_have, "every playable continent has a random-map bonus")
	check(is_equal_approx(ShopSystem.wager_odds("arena", "ffa_ai", 3, "normal"), 2.5) and is_equal_approx(ShopSystem.wager_odds("arena", "team_2v2", 3, "normal"), 2.0), "wager odds: 4-player x2.5, 2v2 x2")
	check(ShopSystem.wager_odds("arena", "ffa_ai", 3, "normal", true) < ShopSystem.wager_odds("arena", "ffa_ai", 3, "normal"), "Chaos wager odds are lower than Arena's")
	check(SaveManager.clean_name("  Ari   Wijaya\n ") == "Ari Wijaya" and SaveManager.clean_name("\n\t ") == "" and SaveManager.clean_name("A".repeat(40)).length() == SaveManager.NAME_MAX, "profile name: trimmed, single spaces, no control chars, max length")
	var old_name := String(SaveManager.data["profile"]["name"])
	check(SaveManager.set_profile_name("Raja Baru") and String(SaveManager.data["profile"]["name"]) == "Raja Baru" and not SaveManager.set_profile_name("   ") and String(SaveManager.data["profile"]["name"]) == "Raja Baru", "set_profile_name renames, and an empty name changes nothing")
	SaveManager.set_profile_name(old_name)
	var rc0 := SaveManager.coins()
	SaveManager.record_match(true, 10, 1000, "aetherion", false, "solvaris", {}, "normal", 0.5)
	check(SaveManager.last_reward == int(round(ShopSystem.win_reward("normal") * 0.5)) and SaveManager.coins() >= rc0 + SaveManager.last_reward, "reward_mult 0.5 halves the coin reward (Chaos); level-up / event bonuses may add more")
	var c0 := SaveManager.coins()
	var f0 := SaveManager.fragments()
	var xp0 := SaveManager.profile_xp()
	var col0: Dictionary = SaveManager.data["collection"].duplicate(true)  # a win unlocks the next Support card: undo that below
	SaveManager.record_match(true, 5, 100, "arcanum", false, "", ShopSystem.random_bonus("arcanum"))
	check(SaveManager.profile_xp() == xp0 + XpSystem.match_xp(true, 5, "normal") + 20 and SaveManager.fragments() == f0 and SaveManager.last_bonus_text != "", "Arcanum bonus: +20 XP (no fragments) on a win")
	SaveManager.record_match(false, 5, 100, "arcanum", false, "", ShopSystem.random_bonus("arcanum"))
	check(SaveManager.profile_xp() == xp0 + XpSystem.match_xp(true, 5, "normal") + 20 + XpSystem.match_xp(false, 5, "normal") and SaveManager.last_bonus_text == "", "no random-map bonus on a loss")
	SaveManager.data["wallet"]["coins"] = c0
	SaveManager.data["wallet"]["fragments"] = f0
	SaveManager.data["profile"]["xp"] = xp0
	SaveManager.data["collection"] = col0
	# in-game bonus: human only, random map only
	var mc := MatchController.new()
	mc.setup({"mode": "custom_ai", "continent_id": "arcanum", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 3, "random_map": true})
	check(mc.players[0].reroll_tokens >= 2 and mc.players[1].reroll_tokens == 0, "random map (Arcanum): the human starts with 2 Reroll Tokens, the AI with none")
	var mc2 := MatchController.new()
	mc2.setup({"mode": "custom_ai", "continent_id": "arcanum", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 3})
	check(mc2.players[0].reroll_tokens == 0, "no random-map bonus without a random map")
	var mc3 := MatchController.from_dict(mc.to_dict())
	check(mc3.random_map and mc3.players[0].reroll_tokens == mc.players[0].reroll_tokens, "random map survives save and load without paying the gift twice")

	check(int(SaveManager.default_data()["wallet"]["coins"]) == 600 and ShopSystem.START_COINS == 600, "a new profile starts with 600 coins")
	SaveManager.data["wallet"]["coins"] = ShopSystem.START_COINS  # the matches above paid rewards: back to a new wallet
	check(SaveManager.spend_coins(100) and SaveManager.coins() == 500 and not SaveManager.spend_coins(501) and SaveManager.coins() == 500, "spending needs enough coins and never goes negative")
	SaveManager.add_coins(100)

	# --- direct purchase
	var locked := ShopSystem.locked_supports()
	check(locked.size() == 90, "90 Support cards are locked in a new profile (%d)" % locked.size())
	var cheap: Dictionary = {}
	var epic: Dictionary = {}
	for s in locked:
		if cheap.is_empty() and s["rarity"] == "common":
			cheap = s
		if epic.is_empty() and s["rarity"] == "epic":
			epic = s
	var before := SaveManager.coins()
	SaveManager.data["wallet"]["crystals"] = ShopSystem.crystal_price(cheap)
	check(ShopSystem.buy(String(cheap["id"])) == "" and SaveManager.owned_count(String(cheap["id"])) == 1 and SaveManager.crystals() == 0 and SaveManager.coins() == before, "buying a locked card unlocks it, charges crystals and never coins")
	SaveManager.data["wallet"]["crystals"] = 99
	check(ShopSystem.buy(String(cheap["id"])) != "" and SaveManager.crystals() == 99, "an owned card cannot be bought twice (no charge)")
	SaveManager.data["wallet"]["crystals"] = 0
	check(ShopSystem.buy(String(epic["id"])) == "Not enough Crystals." and SaveManager.owned_count(String(epic["id"])) == 0, "not enough crystals: the card stays locked (coins cannot buy cards)")
	check(ShopSystem.locked_supports().size() == 89, "the bought card leaves the locked list")
	check(ShopSystem.locked_supports("Magic").all(func(s): return s["category"] == "Magic"), "the category filter works")

	# --- gacha
	SaveManager.data["wallet"]["coins"] = 5000
	SaveManager.data["wallet"]["tickets"] = 5000
	var coins0 := SaveManager.coins()
	var tix0 := SaveManager.tickets()
	check(ShopSystem.pull_batch(1, rng).size() == 1 and SaveManager.coins() == coins0 and SaveManager.tickets() == tix0 - 1, "a single pull costs 1 ticket and no coins")
	SaveManager.data["wallet"]["tickets"] = 0
	check(ShopSystem.pull_batch(1, rng).is_empty() and SaveManager.coins() == coins0, "coins cannot pay a pull")
	SaveManager.data["wallet"]["tickets"] = 5000
	var pulls1 := ShopSystem.pull_batch(1, rng)
	check(SaveManager.owned_count(String(pulls1[0]["id"])) >= 1, "the pulled card is owned afterwards")
	tix0 = SaveManager.tickets()
	var pulls10 := ShopSystem.pull_batch(10, rng)
	var has_rare := false
	for r in pulls10:
		has_rare = has_rare or ShopSystem.RARITY_ORDER.find(String(r["rarity"])) >= 1
	check(pulls10.size() == 10 and SaveManager.tickets() == tix0 - ShopSystem.TICKET_PULL10, "ten pulls cost 9 tickets")
	check(has_rare, "a 10-pull always holds a Rare or better")
	SaveManager.data["wallet"]["tickets"] = 0
	check(ShopSystem.pull_batch(1, rng).is_empty() and SaveManager.tickets() == 0, "no pull without enough tickets")

	# --- fragments: a duplicate becomes fragments (more for a rarer card), fragments buy a locked card (rarer = more)
	check(SaveManager.fragments() >= 0, "the wallet holds fragments")
	var prev := 0
	var prev_price := 0
	for rar in ShopSystem.RARITY_ORDER:
		check(int(ShopSystem.DUPLICATE_FRAGMENTS[rar]) > prev, "duplicate fragments grow with rarity (%s)" % rar)
		check(int(ShopSystem.FRAGMENT_PRICE[rar]) > prev_price, "the fragment price grows with rarity (%s)" % rar)
		prev = int(ShopSystem.DUPLICATE_FRAGMENTS[rar])
		prev_price = int(ShopSystem.FRAGMENT_PRICE[rar])
	SaveManager.data["wallet"]["fragments"] = 0
	SaveManager.data["wallet"]["tickets"] = 1000000
	var dup_total := 0
	var dup_seen := 0
	for i in range(400):  # almost everything is owned by now, so duplicates are plentiful
		for r in ShopSystem.pull_batch(1, rng):
			if bool(r["new"]):
				check(int(r["fragments"]) == 0, "a new card gives no fragments")
			elif int(r.get("king_b", 0)) > 0:
				check(int(r["fragments"]) == 0, "a duplicate King raises its B level instead of giving fragments")
			else:
				check(int(r["fragments"]) == int(ShopSystem.DUPLICATE_FRAGMENTS[String(r["rarity"])]), "a duplicate gives the fragments of its rarity")
				dup_total += int(r["fragments"])
				dup_seen += 1
	check(dup_seen > 0 and SaveManager.fragments() == dup_total, "duplicates add up in the wallet (%d fragments)" % dup_total)
	SaveManager.data["collection"].erase(String(cheap["id"]))
	SaveManager.data["wallet"]["fragments"] = ShopSystem.fragment_price(cheap) - 1
	check(ShopSystem.exchange(String(cheap["id"])) != "" and SaveManager.owned_count(String(cheap["id"])) == 0, "not enough fragments: the card stays locked")
	SaveManager.add_fragments(1)
	check(ShopSystem.exchange(String(cheap["id"])) == "" and SaveManager.owned_count(String(cheap["id"])) == 1 and SaveManager.fragments() == 0, "exchanging fragments unlocks the card and charges its price")
	check(ShopSystem.exchange(String(cheap["id"])) != "", "an owned card cannot be exchanged")

	# --- pity
	SaveManager.data["wallet"]["tickets"] = 100000
	var worst := 0
	var streak := 0
	for i in range(600):
		var r: Dictionary = ShopSystem.pull_batch(1, rng)[0]
		if ShopSystem.RARITY_ORDER.find(String(r["rarity"])) >= 2:
			streak = 0
		else:
			streak += 1
			worst = maxi(worst, streak)
	check(worst < ShopSystem.PITY_LIMITS["epic"], "never %d pulls in a row without an Epic or better (worst streak %d)" % [ShopSystem.PITY_LIMITS["epic"], worst])
	check(ShopSystem.roll_rarity(rng, {"epic": ShopSystem.PITY_LIMITS["epic"] - 1}) in ["epic", "legendary"], "the Epic pity pull is Epic or Legendary")
	check(ShopSystem.roll_rarity(rng, {"rare": ShopSystem.PITY_LIMITS["rare"] - 1}) != "common", "the Rare pity pull is Rare or better")
	check(ShopSystem.roll_rarity(rng, {"legendary": ShopSystem.PITY_LIMITS["legendary"] - 1}) == "legendary", "the Legendary pity pull is Legendary")
	SaveManager.data["shop"] = {"pity": 5, "pity_rare": 5, "pity_legendary": 5, "pulls": 0}
	var plegs := 0
	for i in range(ShopSystem.PITY_LIMITS["legendary"]):
		var pr: Dictionary = ShopSystem.pull_batch(1, rng)[0]
		if String(pr["rarity"]) == "legendary":
			plegs += 1
			break
	check(plegs == 1, "a Legendary always drops within %d pulls" % ShopSystem.PITY_LIMITS["legendary"])
	var counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	for i in range(4000):
		counts[ShopSystem.roll_rarity(rng, {})] += 1
	check(counts["common"] > counts["rare"] and counts["rare"] > counts["epic"] and counts["epic"] > counts["legendary"] and counts["legendary"] > 0, "rarity frequencies follow the rates (%s)" % str(counts))
	check(ShopSystem.locked_supports().size() < 40, "600 pulls unlock most Support cards (%d left)" % ShopSystem.locked_supports().size())

	# --- match rewards
	SaveManager.data["wallet"]["coins"] = 0
	SaveManager.record_match(true, 10, 100, "")
	var level_bonus := SaveManager.last_level_coins  # a level-up in the same match pays extra coins on top of the reward
	check(SaveManager.coins() - level_bonus == ShopSystem.WIN_REWARD and SaveManager.last_reward == ShopSystem.WIN_REWARD, "a victory pays %d coins" % ShopSystem.WIN_REWARD)
	SaveManager.record_match(false, 10, 100, "")
	level_bonus += SaveManager.last_level_coins
	check(SaveManager.coins() - level_bonus == ShopSystem.WIN_REWARD + ShopSystem.LOSS_REWARD and SaveManager.last_reward == ShopSystem.LOSS_REWARD, "a defeat pays %d coins" % ShopSystem.LOSS_REWARD)

	# --- rewards by difficulty (easy < normal < hard)
	for d in ["easy", "normal", "hard"]:
		SaveManager.data["wallet"]["coins"] = 0
		SaveManager.record_match(true, 10, 100, "", false, "", {}, d)
		check(SaveManager.last_reward == ShopSystem.WIN_REWARD_BY_DIFF[d], "%s victory pays %d coins" % [d, ShopSystem.WIN_REWARD_BY_DIFF[d]])
		SaveManager.record_match(false, 10, 100, "", false, "", {}, d)
		check(SaveManager.last_reward == ShopSystem.LOSS_REWARD_BY_DIFF[d], "%s defeat pays %d coins" % [d, ShopSystem.LOSS_REWARD_BY_DIFF[d]])
	check(ShopSystem.win_reward("easy") < ShopSystem.win_reward("normal") and ShopSystem.win_reward("normal") < ShopSystem.win_reward("hard"), "win reward grows with difficulty")
	check(ShopSystem.win_reward("normal") == ShopSystem.WIN_REWARD and ShopSystem.loss_reward("normal") == ShopSystem.LOSS_REWARD, "normal keeps the standard reward")
	check(ShopSystem.practice_reward(true, "hard") > ShopSystem.practice_reward(true, "easy"), "Battle Chess pays more on hard")

	# --- unit cards are locked at the start: the starter set is the 8 Pawns + the 7 Solvaris pieces
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	var starter := SaveManager.starter_unit_ids()
	check(starter.size() == 15, "the starter set is exactly 15 unit types (%d)" % starter.size())
	var owned_units := 0
	for id in CardDatabase.all_unit_ids_any_continent():
		owned_units += 1 if SaveManager.owned_count(id) > 0 else 0
	check(owned_units == 15 and SaveManager.owned_count(starter[0]) == int(GameData.b("unit_copies")), "a new save owns only the starter units (x%d)" % int(GameData.b("unit_copies")))
	CardDatabase.set_continent("aetherion")
	var dk := SaveManager.get_deck("aetherion")
	check(dk.effective_unit_ids().size() == 15 and dk.validate(SaveManager.data["collection"]).is_empty(), "the default deck is valid with the starter units")
	var foreign := SaveManager.get_deck("arcanum")
	for id in foreign.effective_unit_ids():
		check(SaveManager.owned_count(id) > 0, "a deck never uses a locked unit card (%s)" % id)
		break
	# only continents opened on the trophy road are sold
	var for_sale := ShopSystem.shop_units("", true)
	var only_open := true
	for u in for_sale:
		only_open = only_open and SaveManager.is_continent_unlocked(String(CardDatabase.get_unit(String(u["id"])).get("continent", "aetherion")) if CardDatabase.get_unit(String(u["id"])).has("continent") else "aetherion")
	check(not for_sale.is_empty() and for_sale.all(func(u): return String(u["chess"]) != "pawn" and String(u["rarity"]) != "common"), "the Shop sells locked non-starter unit cards (%d)" % for_sale.size())
	var arc_unit := ""
	for u in CardDatabase.units_of_continent("arcanum"):
		if String(u["chess"]) != "pawn":
			arc_unit = String(u["id"])
			break
	check(arc_unit != "" and not ShopSystem.unit_for_sale(arc_unit) and ShopSystem.buy(arc_unit) != "", "a unit card of a locked continent is not sold")
	SaveManager.unlock_continent("arcanum")
	check(ShopSystem.unit_for_sale(arc_unit), "opening the continent adds its unit cards to the Shop")
	var uc := ShopSystem.card_by_id(arc_unit)
	check(ShopSystem.is_unit_card(uc) and ShopSystem.crystal_price(uc) > 0, "a unit card has its own price")
	SaveManager.data["wallet"]["coins"] = 100000
	SaveManager.data["wallet"]["crystals"] = 0
	check(ShopSystem.buy(arc_unit) == "Not enough Crystals." and SaveManager.owned_count(arc_unit) == 0, "coins never buy a unit")
	SaveManager.data["wallet"]["crystals"] = ShopSystem.crystal_price(uc)
	check(ShopSystem.buy(arc_unit) == "" and SaveManager.owned_count(arc_unit) == int(GameData.b("unit_copies")) and SaveManager.crystals() == 0, "buying a unit with crystals unlocks all its copies")
	check(ShopSystem.buy(arc_unit) == "You already own this card.", "an owned unit cannot be bought again")
	SaveManager.data["wallet"]["crystals"] = ShopSystem.crystal_price(uc) - 1
	var other := ""
	for u in CardDatabase.units_of_continent("arcanum"):
		if String(u["chess"]) != "pawn" and SaveManager.owned_count(String(u["id"])) == 0 and String(u["rarity"]) == String(uc["rarity"]):
			other = String(u["id"])
			break
	check(ShopSystem.buy(other) == "Not enough Crystals.", "a unit needs enough crystals")
	SaveManager.add_currency("crystals", 1)
	check(ShopSystem.buy(other) == "" and SaveManager.owned_count(other) > 0 and SaveManager.crystals() == 0, "crystals buy a unit")
	var fu := ""
	for u in ShopSystem.shop_units("", true):
		fu = String(u["id"])
		break
	SaveManager.data["wallet"]["fragments"] = ShopSystem.fragment_price(ShopSystem.card_by_id(fu)) - 1
	check(ShopSystem.exchange(fu) == "Not enough Card Fragments.", "fragments must cover the unit price")
	SaveManager.add_fragments(1)
	check(ShopSystem.exchange(fu) == "" and SaveManager.owned_count(fu) > 0, "fragments exchange for a unit")
	# a bought unit becomes usable in a custom deck of its continent
	var d2 := SaveManager.get_deck("arcanum")
	var still_locked := String(ShopSystem.shop_units("", true)[0]["id"])
	check(d2.is_owned(arc_unit) and not d2.is_owned(still_locked), "the deck sees which unit cards are owned")

	# --- Card Gacha: one pool (Support + unit + King cards)
	var urng := RandomNumberGenerator.new()
	urng.seed = 7
	SaveManager.data["wallet"]["tickets"] = 100000
	var units_open := ShopSystem.shop_units("", false)
	var before_units := ShopSystem.shop_units("", true).size()
	var saw_unit := false
	var saw_support := false
	var units_only_rare_epic := true
	var owned_ok := true
	for i in range(60):
		for r in ShopSystem.pull_batch(10, urng):
			var is_unit := ShopSystem.is_unit_card(ShopSystem.card_by_id(String(r["id"])))
			var is_king := ShopSystem.is_king_card(ShopSystem.card_by_id(String(r["id"])))
			saw_unit = saw_unit or (is_unit and not is_king)
			saw_support = saw_support or not is_unit
			units_only_rare_epic = units_only_rare_epic and (not is_unit or is_king or String(r["rarity"]) in ["rare", "epic"])
			owned_ok = owned_ok and SaveManager.owned_count(String(r["id"])) > 0
	check(saw_support and (saw_unit or units_open.is_empty()), "the Gacha gives Support cards and unit cards")
	check(units_only_rare_epic and owned_ok, "unit cards come only as Rare / Epic, and every pulled card is owned")
	check(ShopSystem.shop_units("", true).size() < before_units or before_units == 0, "new unit cards leave the locked list")
	# tickets pay a pull
	SaveManager.data["wallet"]["tickets"] = 0
	check(ShopSystem.pull_batch(1, urng).is_empty(), "a ticket pull without tickets fails")
	SaveManager.data["wallet"]["tickets"] = ShopSystem.TICKET_PULL10
	var coins_now := SaveManager.coins()
	check(ShopSystem.pull_batch(10, urng).size() == 10 and SaveManager.tickets() == 0 and SaveManager.coins() == coins_now, "a 10-pull costs 9 tickets and no coins")

	# --- Exchange (penukaran)
	SaveManager.data["wallet"] = {"coins": 1000, "fragments": 0, "tickets": 0, "crystals": 0, "chips": 0}
	check(ShopSystem.convert_currency("coins_ticket", 3) == "" and SaveManager.tickets() == 3 and SaveManager.coins() == 700, "coins -> tickets: 100 coins = 1 ticket")
	check(ShopSystem.convert_currency("ticket_crystal", 1) == "Unknown exchange." and SaveManager.crystals() == 0 and SaveManager.tickets() == 3, "tickets can no longer be exchanged for crystals")
	check(ShopSystem.convert_currency("coins_chip", 2) == "" and SaveManager.chips() == 200 and SaveManager.coins() == 500, "coins -> chips: 100 coins = 100 chips")
	check(ShopSystem.convert_currency("chip_coins", 2) == "" and SaveManager.chips() == 0 and SaveManager.coins() == 660, "chips -> coins: 100 chips = 80 coins (a round trip loses 20%)")
	check(ShopSystem.convert_currency("chip_coins", 1) == "Not enough Chips.", "no chips left")
	SaveManager.data["wallet"]["fragments"] = 25
	check(ShopSystem.convert_currency("fragment_coins", 2) == "" and SaveManager.fragments() == 5 and SaveManager.coins() == 700, "fragments -> coins: 10 fragments = 20 coins")
	check(ShopSystem.convert_currency("coins_fragment", 2) == "" and SaveManager.fragments() == 25 and SaveManager.coins() == 600, "coins -> fragments: 50 coins = 10 fragments")
	check(not ShopSystem.can_convert("coins_ticket", 7) and ShopSystem.can_convert("coins_ticket", 6), "can_convert follows the balance")
	var no_loop := true
	for e in ShopSystem.EXCHANGES:
		for back in ShopSystem.EXCHANGES:
			if String(back["from"]) == String(e["to"]) and String(back["to"]) == String(e["from"]):
				no_loop = no_loop and (float(e["to_n"]) / float(e["from_n"])) * (float(back["to_n"]) / float(back["from_n"])) < 1.0
	check(no_loop, "exchanging back and forth never makes money")
	var five := ["coins_ticket", "coins_fragment", "coins_chip", "fragment_coins", "chip_coins"]
	var ids: Array = ShopSystem.EXCHANGES.map(func(e): return String(e["id"]))
	check(ids == five, "the five exchanges in order: coins/ticket, coins/fragment, coins/chip, fragment/coins, chip/coins")

	# --- Gamble: chips only
	var grng := RandomNumberGenerator.new()
	grng.seed = 11
	SaveManager.data["wallet"] = {"coins": 500, "fragments": 0, "tickets": 0, "crystals": 0, "chips": 0}
	check(not bool(ShopSystem.gamble("coin", "heads", 100, grng)["ok"]) and SaveManager.coins() == 500, "gambling needs chips: coins are never used")
	SaveManager.data["wallet"]["chips"] = 50
	check(String(ShopSystem.gamble("coin", "heads", 100, grng)["error"]) == "Not enough Chips.", "a bet above your chips is refused")
	check(String(ShopSystem.gamble("coin", "", 100, grng)["error"]) != "" and String(ShopSystem.gamble("dice", "mid", 100, grng)["error"]) != "" and String(ShopSystem.gamble("coin", "heads", 123, grng)["error"]) != "", "bad picks / bets are refused without paying")
	check(SaveManager.chips() == 50, "a refused round costs nothing")
	# the simulated return matches the rules, and every game leaves the house a small edge
	for g in ["coin", "dice", "slots"]:
		var choice := {"coin": "heads", "dice": "high", "slots": ""}[g] as String
		var staked := 0
		var back := 0
		SaveManager.data["wallet"]["chips"] = 100000000
		var rounds := 20000
		for i in range(rounds):
			var r := ShopSystem.gamble(g, choice, 100, grng)
			staked += int(r["bet"])
			back += int(r["payout"])
			if i == 0:
				check(int(r["net"]) == int(r["payout"]) - 100, "%s: net = payout - bet" % g)
		var rtp := float(back) / float(staked)
		check(rtp > 0.85 and rtp < 1.02, "%s returns about %d%% over %d rounds (%.3f)" % [g, int(round(rtp * 100.0)), rounds, rtp])
	check(ShopSystem.SLOT_EXPECTED_RETURN < 1.0 and ShopSystem.COIN_WIN_CHANCE * 2.0 < 1.0 and 15.0 / 36.0 * float(ShopSystem.DICE_PAYOUT["high"]) < 1.0 and 6.0 / 36.0 * float(ShopSystem.DICE_PAYOUT["seven"]) < 1.0, "every game has a house edge")
	SaveManager.data["wallet"]["chips"] = 1000
	var w := ShopSystem.gamble("coin", "heads", 1000, grng)
	check(SaveManager.chips() == int(w["payout"]) and (int(w["payout"]) == 2000 or int(w["payout"]) == 0), "a coin flip pays double or nothing")

	# --- Trading: deterministic live market paid in Chips
	SaveManager.data["trading"] = {"pos": {}, "realized": 0}
	var t0 := 1800000000.0
	var all_pos := true
	var moves := true
	for a in TradeSystem.ASSETS:
		var aid := String(a["id"])
		all_pos = all_pos and TradeSystem.price(aid, t0) > 0.0 and TradeSystem.price(aid, t0) == TradeSystem.price(aid, t0)
		moves = moves and absf(TradeSystem.price(aid, t0 + 60.0) - TradeSystem.price(aid, t0)) > 0.0001
	check(all_pos and moves, "every trading asset has a positive, deterministic price that moves")
	var swing := 0.0
	for i in range(0, 7200, 30):
		swing = maxf(swing, absf(TradeSystem.price("eclp", t0 + float(i)) / TradeSystem.price("eclp", t0) - 1.0))
	check(swing > 0.03 and swing < 3.0, "prices swing visibly but stay sane (max %.0f%% in 2 h)" % (swing * 100.0))
	SaveManager.data["wallet"]["chips"] = 300
	var tb := TradeSystem.buy("aeth", 100, t0)
	check(bool(tb["ok"]) and SaveManager.chips() == 200 and int(TradeSystem.position("aeth")["cost"]) == 100, "buying spends Chips and opens a position")
	check(not bool(TradeSystem.buy("aeth", 5000, t0)["ok"]) and SaveManager.chips() == 200, "buying more than you own is refused and costs nothing")
	check(not bool(TradeSystem.buy("nope", 10, t0)["ok"]), "unknown asset is refused")
	TradeSystem.buy("aeth", 100, t0)
	check(int(TradeSystem.position("aeth")["cost"]) == 200 and SaveManager.chips() == 100, "buying again adds to the same position")
	var same := TradeSystem.sell("aeth", 1.0, t0)
	check(bool(same["ok"]) and int(same["payout"]) == int(floor(200.0 * (1.0 - TradeSystem.FEE))) and int(same["net"]) == int(same["payout"]) - 200, "selling at the same price loses only the fee")
	check(TradeSystem.position("aeth").is_empty() and SaveManager.chips() == 100 + int(same["payout"]), "a full sale closes the position and pays the Chips")
	check(not bool(TradeSystem.sell("aeth", 1.0, t0)["ok"]), "nothing to sell is refused")
	SaveManager.data["wallet"]["chips"] = 1000
	TradeSystem.buy("sylv", 400, t0)
	var half := TradeSystem.sell("sylv", 0.5, t0)
	check(bool(half["ok"]) and int(TradeSystem.position("sylv")["cost"]) == 200 and int(half["cost"]) == 200, "selling half keeps half of the cost")
	# a rising price pays a profit, a falling price a loss
	var best_t := t0
	var worst_t := t0
	for i in range(0, 5400, 10):
		var tt := t0 + float(i)
		if TradeSystem.price("sylv", tt) > TradeSystem.price("sylv", best_t):
			best_t = tt
		if TradeSystem.price("sylv", tt) < TradeSystem.price("sylv", worst_t):
			worst_t = tt
	var up := TradeSystem.sell("sylv", 0.5, best_t)
	check(TradeSystem.price("sylv", best_t) < TradeSystem.price("sylv", t0) * 1.03 or int(up["net"]) > 0, "selling near the top is a profit (net %d)" % int(up["net"]))
	SaveManager.data["wallet"]["chips"] = 1000
	TradeSystem.buy("drak", 500, best_t if TradeSystem.price("drak", best_t) > TradeSystem.price("drak", worst_t) else worst_t)
	check(TradeSystem.realized() == int(half["net"]) + int(up["net"]) + int(same["net"]), "realized profit adds up every sale")
	check(TradeSystem.portfolio_value(t0) >= 0, "portfolio value is readable")
	var snap := (SaveManager.data["trading"] as Dictionary).duplicate(true)
	SaveManager.data["trading"] = {}
	check(TradeSystem.position("drak").is_empty() and TradeSystem.realized() == 0, "an old save without trading data is repaired")
	SaveManager.data["trading"] = snap

	SaveManager.data = saved
	SaveManager.save_game()
	print("SHOP TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
