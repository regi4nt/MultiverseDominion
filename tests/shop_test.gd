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
	SaveManager.data["shop"] = {"pity": 0, "pulls": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	check(SaveManager.coins() == 600, "a new profile starts with 600 coins")
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
	check(ShopSystem.buy(String(cheap["id"])) == "" and SaveManager.owned_count(String(cheap["id"])) == 1 and SaveManager.coins() == before - ShopSystem.buy_price(cheap), "buying a locked card unlocks it and charges its price")
	check(ShopSystem.buy(String(cheap["id"])) != "" and SaveManager.coins() == before - ShopSystem.buy_price(cheap), "an owned card cannot be bought twice (no charge)")
	check(ShopSystem.buy(String(epic["id"])) != "" and SaveManager.owned_count(String(epic["id"])) == 0, "not enough coins: the card stays locked")
	check(ShopSystem.locked_supports().size() == 89, "the bought card leaves the locked list")
	check(ShopSystem.locked_supports("Magic").all(func(s): return s["category"] == "Magic"), "the category filter works")

	# --- gacha
	SaveManager.data["wallet"]["coins"] = 5000
	var coins0 := SaveManager.coins()
	var pulls1 := ShopSystem.pull_batch(1, rng)
	check(pulls1.size() == 1 and SaveManager.coins() == coins0 - 100 + int(pulls1[0]["refund"]), "a single pull costs 100")
	check(SaveManager.owned_count(String(pulls1[0]["id"])) >= 1, "the pulled card is owned afterwards")
	coins0 = SaveManager.coins()
	var pulls10 := ShopSystem.pull_batch(10, rng)
	var refunds := 0
	var has_rare := false
	for r in pulls10:
		refunds += int(r["refund"])
		has_rare = has_rare or ShopSystem.RARITY_ORDER.find(String(r["rarity"])) >= 1
	check(pulls10.size() == 10 and SaveManager.coins() == coins0 - 900 + refunds, "ten pulls cost 900 (duplicates refunded)")
	check(has_rare, "a 10-pull always holds a Rare or better")
	SaveManager.data["wallet"]["coins"] = 50
	check(ShopSystem.pull_batch(1, rng).is_empty() and SaveManager.coins() == 50, "no pull without enough coins")

	# --- pity
	SaveManager.data["wallet"]["coins"] = 100000
	var worst := 0
	var streak := 0
	for i in range(600):
		var r: Dictionary = ShopSystem.pull_batch(1, rng)[0]
		if ShopSystem.RARITY_ORDER.find(String(r["rarity"])) >= 2:
			streak = 0
		else:
			streak += 1
			worst = maxi(worst, streak)
	check(worst < ShopSystem.PITY_LIMIT, "never %d pulls in a row without an Epic or better (worst streak %d)" % [ShopSystem.PITY_LIMIT, worst])
	check(ShopSystem.roll_rarity(rng, ShopSystem.PITY_LIMIT - 1) in ["epic", "legendary"], "the pity pull is Epic or Legendary")
	var counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	for i in range(4000):
		counts[ShopSystem.roll_rarity(rng, 0)] += 1
	check(counts["common"] > counts["rare"] and counts["rare"] > counts["epic"] and counts["epic"] > counts["legendary"] and counts["legendary"] > 0, "rarity frequencies follow the rates (%s)" % str(counts))
	check(ShopSystem.locked_supports().size() < 40, "600 pulls unlock most Support cards (%d left)" % ShopSystem.locked_supports().size())

	# --- match rewards
	SaveManager.data["wallet"]["coins"] = 0
	SaveManager.record_match(true, 10, 100, "")
	check(SaveManager.coins() == ShopSystem.WIN_REWARD and SaveManager.last_reward == ShopSystem.WIN_REWARD, "a victory pays %d coins" % ShopSystem.WIN_REWARD)
	SaveManager.record_match(false, 10, 100, "")
	check(SaveManager.coins() == ShopSystem.WIN_REWARD + ShopSystem.LOSS_REWARD, "a defeat pays %d coins" % ShopSystem.LOSS_REWARD)

	SaveManager.data = saved
	SaveManager.save_game()
	print("SHOP TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
