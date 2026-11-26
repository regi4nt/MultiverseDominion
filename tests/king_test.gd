extends Node
## King cards: collected in Card Gacha / Buy Card, B1 / B2 / B3 = copies owned.
## B2 unlocks the active skill of Battle Chess, B3 unlocks the territory skill.
## Run: godot --headless --path . res://tests/king_test.tscn   -> "KING TEST RESULT: PASS"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _fresh() -> void:
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()


func _ready() -> void:
	var backup: Dictionary = SaveManager.data.duplicate(true)
	_test_collection()
	_test_shop()
	_test_gacha()
	_test_battle_lock()
	_test_territory_lock()
	_test_old_save()
	SaveManager.data = backup
	SaveManager.save_game()
	print("KING TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_collection() -> void:
	_fresh()
	check(SaveManager.king_b("champion_solvaris") == 1 and SaveManager.owns_king("champion_solvaris"), "a new save owns only the default King, at B1")
	check(not SaveManager.owns_king("champion_nocthyr") and not SaveManager.can_use_king("champion_nocthyr"), "the other Kings are cards to collect")
	check(SaveManager.player_champion_id() == "champion_solvaris", "the deck King is an owned King")
	check(not SaveManager.king_battle_skill_unlocked("champion_solvaris") and not SaveManager.king_territory_skill_unlocked("champion_solvaris"), "B1: both King skills are locked")
	check(SaveManager.add_king_copy("champion_solvaris") == 2 and SaveManager.king_battle_skill_unlocked("champion_solvaris") and not SaveManager.king_territory_skill_unlocked("champion_solvaris"), "B2 unlocks the Battle Chess skill only")
	check(SaveManager.add_king_copy("champion_solvaris") == 3 and SaveManager.king_territory_skill_unlocked("champion_solvaris"), "B3 unlocks the territory skill")
	check(SaveManager.add_king_copy("champion_solvaris") == 0 and SaveManager.king_b("champion_solvaris") == 3, "B3 is the top level")
	SaveManager.data["decks"]["main"]["champion"] = "champion_nocthyr"
	check(SaveManager.player_champion_id() == "champion_solvaris", "a King that is not owned cannot lead the deck")


func _test_shop() -> void:
	_fresh()
	var kings := ShopSystem.shop_kings(true)
	check(kings.size() == 4, "the Shop sells the 4 Kings of the open continent (%d)" % kings.size())
	var k := ShopSystem.card_by_id("champion_nocthyr")
	check(ShopSystem.is_king_card(k) and ShopSystem.crystal_price(k) == 10 and ShopSystem.fragment_price(k) == 1000, "a King is priced as a Legendary card (10 crystals / 1000 fragments)")
	check(ShopSystem.buy("champion_nocthyr") == "Not enough Crystals.", "buying a King needs Crystals")
	SaveManager.data["wallet"]["crystals"] = 30
	check(ShopSystem.buy("champion_nocthyr") == "" and SaveManager.king_b("champion_nocthyr") == 1, "buying a new King gives B1")
	check(ShopSystem.buy("champion_nocthyr") == "" and SaveManager.king_b("champion_nocthyr") == 2, "buying it again gives B2")
	check(ShopSystem.buy("champion_nocthyr") == "" and SaveManager.king_b("champion_nocthyr") == 3, "and B3")
	check(ShopSystem.buy("champion_nocthyr") != "" and SaveManager.crystals() == 0, "a B3 King cannot be bought again (no crystals lost)")
	check(not ShopSystem.shop_kings(true).any(func(c): return String(c["id"]) == "champion_nocthyr"), "a B3 King leaves the Buy Card list")
	SaveManager.data["wallet"]["fragments"] = 1000
	check(ShopSystem.exchange("champion_valdoria") == "" and SaveManager.king_b("champion_valdoria") == 1 and SaveManager.fragments() == 0, "fragments buy a King copy too")
	check(ShopSystem.buy("champion_astralis") != "", "a King of a locked continent is not for sale")


func _test_gacha() -> void:
	_fresh()
	SaveManager.data["wallet"]["tickets"] = 100000
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seen_king := false
	var raised := false
	for i in range(300):
		for r in ShopSystem.pull_batch(10, rng):
			if ShopSystem.is_king_card(ShopSystem.card_by_id(String(r["id"]))):
				seen_king = true
				check(String(r["rarity"]) == "legendary", "a King is a Legendary pull")
				raised = raised or (not bool(r["new"]) and int(r.get("king_b", 0)) >= 2)
		if seen_king and raised:
			break
	check(seen_king, "Kings drop from the Card Gacha")
	check(raised, "a duplicate King raises its B level instead of turning into fragments")
	for id in ["champion_solvaris", "champion_nocthyr", "champion_valdoria", "champion_elarion"]:
		check(SaveManager.king_b(id) <= 3, "%s never goes past B3" % id)


func _battle_cfg(locked: bool) -> Dictionary:
	var prep := BattlePrep.new(Deck.create_default(), RandomNumberGenerator.new(), 0, 0, 1)
	return {"seed": 5, "ai_supports": [false, false], "manual_king": [true, false], "king_skill_locked": [locked, false], "sides": [
		prep.to_side_cfg("champion_solvaris", []), prep.to_side_cfg("champion_nocthyr", [])]}


func _test_battle_lock() -> void:
	var locked := BattleEngine.new()
	locked.setup(_battle_cfg(true))
	locked._enter_king(0)
	check((locked.kings[0] as BattleUnit).skill_id == "", "B1 King: no active skill in Battle Chess")
	locked.energy[0] = locked.energy_max()
	check(not locked.can_use_king_skill(0) and locked.use_king_skill(0) != "" and not bool(locked.king_skill_used[0]), "B1 King: the King skill cannot be used")
	var open := BattleEngine.new()
	open.setup(_battle_cfg(false))
	open._enter_king(0)
	check((open.kings[0] as BattleUnit).skill_id != "", "B2 King: the active skill is there")
	open.energy[0] = open.energy_max()
	check(open.can_use_king_skill(0) and open.use_king_skill(0) == "" and bool(open.king_skill_used[0]), "B2 King: the King skill works once")
	var ai := BattleEngine.new()
	ai.setup(_battle_cfg(true))
	ai._enter_king(1)
	check((ai.kings[1] as BattleUnit).skill_id != "", "an AI King is never locked")


func _test_territory_lock() -> void:
	var base := {"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 1, "seed": 5, "player_name": "T"}
	var m1 := MatchController.new()
	m1.setup(base.merged({"king_b": 1}))
	check(m1.players[0].passive == "" and m1.players[0].passive_value == 0.0, "B1 King: no territory skill")
	var m2 := MatchController.new()
	m2.setup(base.merged({"king_b": 2}))
	check(m2.players[0].passive == "", "B2 King: the territory skill is still locked")
	var m3 := MatchController.new()
	m3.setup(base.merged({"king_b": 3}))
	check(m3.players[0].passive != "", "B3 King: the territory skill works")
	check(m3.players[1].passive != "" and m1.players[1].passive != "", "an AI ruler always has its territory skill")
	var m0 := MatchController.new()
	m0.setup(base)
	check(m0.players[0].passive != "", "no King level in the config (tests, tutorial) = unlocked")


func _test_old_save() -> void:
	_fresh()
	var d := SaveManager.default_data()
	d["collection"] = {"card_x": 1}  # an older save: collection filled, no King cards yet
	d["unit_cards_v"] = 2
	SaveManager.data = d
	SaveManager.ensure_collection()
	var kept := true
	for id in ["champion_solvaris", "champion_nocthyr", "champion_valdoria", "champion_elarion"]:
		kept = kept and SaveManager.king_b(id) == 1
	check(kept, "an older save keeps the Kings of its open factions as B1 cards")
	check(not SaveManager.owns_king("champion_astralis"), "and gets none of the locked factions")
