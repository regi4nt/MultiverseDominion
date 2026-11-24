extends Node
## Battle Chess series (1 round / 10 rounds / survival): rules, scaling, next-round preparation.
## Run: godot --headless --path . res://tests/series_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	# --- when does a run go on
	check(not ShopSystem.series_continues("single", 1, 0), "single: ends after the first battle")
	check(ShopSystem.series_continues("ten", 1, 1) and ShopSystem.series_continues("ten", 9, 5), "ten: goes on after a defeat until round 10")
	check(not ShopSystem.series_continues("ten", 10, 0), "ten: over after round 10")
	check(ShopSystem.series_continues("survival", 7, 0), "survival: goes on while unbeaten")
	check(not ShopSystem.series_continues("survival", 3, 1), "survival: the first defeat ends it")

	# --- outcomes (wager)
	check(ShopSystem.series_outcome("single", 1, 0, 0) == "win" and ShopSystem.series_outcome("single", 0, 0, -1) == "draw" and ShopSystem.series_outcome("single", 0, 1, 1) == "loss", "single: outcome follows the battle")
	check(ShopSystem.series_outcome("ten", 6, 4, 0) == "win", "ten: more wins than losses = win")
	check(ShopSystem.series_outcome("ten", 5, 5, 0) == "draw", "ten: equal = draw")
	check(ShopSystem.series_outcome("ten", 3, 7, 1) == "loss", "ten: fewer wins = loss")
	check(ShopSystem.series_outcome("survival", ShopSystem.SERIES_SURVIVAL_TARGET, 1, 1) == "win", "survival: target reached = win")
	check(ShopSystem.series_outcome("survival", ShopSystem.SERIES_SURVIVAL_TARGET - 1, 1, 1) == "loss", "survival: below the target = loss")

	# --- scaling and rewards
	check(is_equal_approx(ShopSystem.series_budget_mult(1), 1.0), "round 1 enemy is unchanged")
	check(ShopSystem.series_budget_mult(5) > ShopSystem.series_budget_mult(2), "later rounds are stronger")
	check(ShopSystem.series_budget_mult(500) <= 3.5, "enemy budget multiplier is capped")
	check(ShopSystem.series_level_bonus(1) == 0 and ShopSystem.series_level_bonus(4) == 1 and ShopSystem.series_level_bonus(7) == 2, "enemy gains a shop level every 3 rounds")
	check(ShopSystem.series_king_star("ten", 1) == 1 and ShopSystem.series_king_star("ten", 3) == 1 and ShopSystem.series_king_star("ten", 4) == 2 \
			and ShopSystem.series_king_star("survival", 7) == 3 and ShopSystem.series_king_star("survival", 20) == CommanderSystem.max_star() and ShopSystem.series_king_star("single", 9) == 1, \
			"the Battle Chess Kings are Lv 1 (rounds 1-3), Lv 2 (4-6), Lv 3 (7+); a single battle stays Lv 1")
	check(ShopSystem.series_coin_bonus("single", 5) == 0 and ShopSystem.series_coin_bonus("ten", 1) == 0 and ShopSystem.series_coin_bonus("ten", 3) > 0, "round bonus only in runs, from round 2")
	check(ShopSystem.series_income(2) > ShopSystem.series_income(1), "gold income grows with the round")

	# --- next round keeps the army and refreshes the shop
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var deck := Deck.create_default()
	var prep := BattlePrep.new(deck, rng, 500, 500, 3)
	check(prep.buy(0) == "", "bought a unit")
	var units_before := prep.roster.units.size()
	var gold_before := prep.gold
	prep.start_next_round(ShopSystem.series_income(1))
	check(prep.roster.units.size() == units_before, "next round: the army stays")
	check(prep.gold == gold_before + ShopSystem.series_income(1), "next round: income is paid")
	check(prep.budget_left >= ShopSystem.series_income(1), "next round: budget grows with the income")
	check(prep.offers.size() > 0, "next round: the shop is dealt again")

	# --- enemy is built for any round without errors, and gets a bigger army
	var e1 := BattleAI.build_enemy("normal", 3, rng, deck, {}, ShopSystem.series_budget_mult(1))
	var e9 := BattleAI.build_enemy("normal", 3 + ShopSystem.series_level_bonus(9), rng, deck, {}, ShopSystem.series_budget_mult(9))
	check(e9.deployed_units().size() >= e1.deployed_units().size(), "round 9 enemy fields at least as many units as round 1")
	print("series_test: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
