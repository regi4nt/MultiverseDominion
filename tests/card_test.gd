extends Node
## Headless test for Phase 3 (card database, deck, roster merge, capacity, battle deck).
## Run: godot --headless --path . res://tests/card_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	check(CardDatabase.validate_database().is_empty(), "card database valid: %s" % str(CardDatabase.validate_database()))
	var d := Deck.create_default()
	check(d.card_list().size() == 151, "default deck has 151 cards (%d)" % d.card_list().size())
	check(d.validate(SaveManager.data["collection"]).is_empty(), "default deck valid against collection")
	var units := 0
	for id in d.card_list():
		if CardDatabase.is_unit(id):
			units += 1
	check(units == 135, "135 unit cards (%d)" % units)
	check(d.support_ids.size() == 15, "15 support cards")

	var bad := Deck.create_default()
	bad.support_ids.pop_back()
	check(not bad.validate().is_empty(), "deck with 14 supports is invalid")
	var dup := Deck.create_default()
	dup.support_ids[1] = dup.support_ids[0]
	check(not dup.validate().is_empty(), "deck with duplicate support is invalid")
	var rt := Deck.from_dict(d.to_dict())
	check(rt.card_list() == d.card_list(), "deck dict round-trip")

	# Star upgrades: 3 copies -> 2 stars, 9 copies -> 3 stars
	var r := UnitRoster.new()
	var id := "pawn_royal_guard"
	r.add_copy(id)
	check(r.units.size() == 1 and r.units[0].stars == 1, "1 copy = B1")
	r.add_copy(id)
	var ev := r.add_copy(id)
	check(r.units.size() == 1 and r.units[0].stars == 2 and ev.size() == 1, "3 copies = one 2-star")
	for i in range(6):
		r.add_copy(id)
	check(r.units.size() == 1 and r.units[0].stars == 3, "9 copies = one 3-star")
	var s1 := CardDatabase.unit_stats(id, 1)
	var s3 := CardDatabase.unit_stats(id, 3)
	check(s3["hp"] > s1["hp"] and s3["atk"] > s1["atk"], "3-star stronger than 1-star (%s vs %s)" % [s1, s3])

	# Capacity table
	var expected := {3: 9, 4: 12, 5: 15, 6: 18, 7: 21, 8: 24, 9: 27, 10: 30}
	var ok := true
	for lv in expected:
		ok = ok and CapacitySystem.capacity_for_level(lv) == expected[lv]
	check(ok, "capacity table level 3..10 = 9..30")
	var dep: Array[UnitInstance] = []
	for i in range(4):
		dep.append(UnitInstance.new("knight_dawnlancer"))  # cost 2 each = 8
	check(CapacitySystem.used(dep) == 8, "4 knights use 8 capacity")
	check(CapacitySystem.can_deploy(dep, "pawn_sun_squire", 3), "pawn fits in 9 (8+1)")
	check(not CapacitySystem.can_deploy(dep, "queen_aurelia", 3), "queen (4) does not fit 8+4>9")
	check(CapacitySystem.can_deploy(dep, "queen_aurelia", 4), "queen fits at level 4 (12)")

	# Battle deck: 135 cards, shop of 5, copies never exceed 9
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bd := BattleDeck.new(d, rng)
	check(bd.remaining() == 135, "battle deck pool = 135")
	var shop := bd.draw_shop()
	check(shop.size() == 5 and bd.remaining() == 130, "shop draws 5")
	bd.return_cards(shop)
	check(bd.remaining() == 135, "unbought cards return to the pile")
	var all: Array[String] = []
	while bd.remaining() > 0:
		all.append_array(bd.draw_shop())
	var per := {}
	for c in all:
		per[c] = int(per.get(c, 0)) + 1
	var nine := true
	for c in per:
		nine = nine and per[c] == 9
	check(all.size() == 135 and per.size() == 15 and nine, "every unit type appears exactly 9 times")

	print("CARD TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
