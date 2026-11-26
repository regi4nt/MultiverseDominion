extends Node
## Battle Shop rarity odds by player level (balance.json "shop_rarity_odds").
## Run: godot --headless --path . res://tests/shop_odds_test.tscn   -> "SHOP ODDS TEST RESULT: PASS"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


## Share of each rarity over `rolls` shops of 5 offers at `level` (units only, the pile is refilled after every roll).
func _rates(level: int, rolls: int, seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var bd := BattleDeck.new(Deck.create_default(), rng)
	var counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	var total := 0
	for i in range(rolls):
		var shop := bd.draw_shop(-1, level)
		for id in shop:
			var r := String(CardDatabase.get_unit(id).get("rarity", "common"))
			counts[r] = int(counts[r]) + 1
			total += 1
		bd.return_cards(shop)
	var out := {}
	for r in counts.keys():
		out[r] = float(counts[r]) / float(maxi(total, 1))
	return out


func _ready() -> void:
	BattleDeck.supports_in_shop = false  # unit cards only: their rarities are common / rare / epic
	for lv in range(3, 11):
		var o := BattleDeck.odds_for_level(lv)
		var sum := 0
		for r in o.keys():
			sum += int(o[r])
		check(sum == 100, "level %d odds add up to 100%% (%d)" % [lv, sum])
	check(BattleDeck.odds_for_level(2) == BattleDeck.odds_for_level(3) and BattleDeck.odds_for_level(11) == BattleDeck.odds_for_level(10), "levels outside the table use the nearest key")
	var low := _rates(3, 400, 1)
	var mid := _rates(6, 400, 2)
	var high := _rates(10, 400, 3)
	check(float(low["epic"]) == 0.0, "level 3 never offers an Epic card")
	check(float(low["common"]) > float(mid["common"]) and float(mid["common"]) > float(high["common"]), "the Common share falls as the level rises (%.2f > %.2f > %.2f)" % [low["common"], mid["common"], high["common"]])
	check(float(high["epic"]) > float(mid["epic"]) and float(mid["epic"]) > float(low["epic"]), "the Epic share rises as the level rises (%.2f < %.2f < %.2f)" % [low["epic"], mid["epic"], high["epic"]])
	check(absf(float(low["common"]) - 0.75) < 0.07, "level 3: about 75%% Common (%.2f)" % low["common"])
	# copies are conserved: drawing by rarity still empties the pile exactly and never gives more than 9 of a unit
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var bd := BattleDeck.new(Deck.create_default(), rng)
	var seen := {}
	var drawn := 0
	while bd.remaining() > 0:
		for id in bd.draw_shop(-1, 8):
			seen[id] = int(seen.get(id, 0)) + 1
			drawn += 1
	var max_copies := 0
	for id in seen.keys():
		max_copies = maxi(max_copies, int(seen[id]))
	check(drawn == 135 and max_copies <= 9, "level draws empty the 135-card pile with at most 9 copies of a unit (%d, max %d)" % [drawn, max_copies])
	# a rarity that is gone from the pile is skipped (renormalised): the shop still fills
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 4
	var bd2 := BattleDeck.new(Deck.create_default(), rng2)
	var shop2: Array[String] = []
	while bd2.remaining() > 5:
		shop2 = bd2.draw_shop(-1, 10)
	check(shop2.size() == 5 or shop2.size() > 0, "the shop still fills when a rarity runs out")
	BattleDeck.supports_in_shop = true
	# Supports follow the same table
	var rng3 := RandomNumberGenerator.new()
	rng3.seed = 21
	var deck := Deck.create_default()
	var bd3 := BattleDeck.new(deck, rng3)
	var got_support := false
	for i in range(60):
		var shop3 := bd3.draw_shop(-1, 6)
		for id in shop3:
			if BattlePrep.is_support_id(id):
				got_support = true
		bd3.return_cards(shop3)
	check(got_support and bd3.remaining() == 135 and bd3.support_pool.size() == deck.support_ids.size(), "Supports still appear and piles stay whole with level odds")
	# the prep passes its level
	var prep := BattlePrep.new(deck, rng3, 2000, 2000, 10)
	check(prep.offers.size() == int(GameData.b("shop_size")), "a Battle Prep at level 10 deals a full shop")
	var rare_plus := 0
	for i in range(80):
		prep.refresh_offers(false)
		for id in prep.offers:
			if not BattlePrep.is_support_id(id) and String(CardDatabase.get_unit(id).get("rarity", "common")) != "common":
				rare_plus += 1
	check(rare_plus > 80 * 5 * 0.5 * 0.7, "level 10 shop is mostly Rare or better (%d of %d offers)" % [rare_plus, 80 * 5])
	# AI rulers shop at the level of the human player
	var ai := PlayerState.new()
	ai.deck = Deck.create_default()
	ai.roster = UnitRoster.new()
	ai.battle_deck = BattleDeck.new(ai.deck, rng3)
	ai.champion_id = "champion_nocthyr"
	ai.difficulty = "normal"
	ai.gold = 3000
	ai.level = 3
	BattleAI.prepare_ai_army(ai, rng3, 1, {}, 8)
	check(ai.level == 8 and ai.capacity >= CapacitySystem.capacity_for_level(8), "the AI ruler shops at the human's level (3 -> 8) with at least that capacity (lv %d, cap %d)" % [ai.level, ai.capacity])
	ai.level = 3
	BattleAI.prepare_ai_army(ai, rng3, 1, {}, 0)
	check(ai.level <= 4, "without a human to follow the AI keeps its own slow level-up (%d)" % ai.level)
	var mc := MatchController.new()
	mc.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 3})
	mc.players[0].level = 6
	check(mc.human_level() == 6, "human_level() is the level of the human player")
	var mc2 := MatchController.new()
	mc2.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 3, "all_ai": true})
	check(mc2.human_level() == 0, "human_level() is 0 in an all-AI match")
	print("SHOP ODDS TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
