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
	for uid_ in d.card_list():
		if CardDatabase.is_unit(uid_):
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

	# Custom unit loadout: 15 unit types of ONE continent, factions mixed freely
	CardDatabase.set_continent("aetherion")
	var mix := Deck.create_default()
	mix.continent_id = "aetherion"
	mix.unit_ids = [] as Array[String]
	for u in CardDatabase.all_units():
		if mix.unit_ids.size() < 15 and (u["chess"] == "pawn" and mix.unit_ids.size() < 4 or u["chess"] != "pawn"):
			mix.unit_ids.append(String(u["id"]))
	var mix_factions := {}
	for uid in mix.unit_ids:
		mix_factions[CardDatabase.get_unit(uid)["faction"]] = true
	check(mix.unit_ids.size() == 15 and mix_factions.size() >= 2, "a custom loadout mixes factions of one continent (%d factions)" % mix_factions.size())
	check(mix.validate(SaveManager.data["collection"]).is_empty() and mix.card_list().size() == 151, "mixed-faction deck is valid: 15 x 9 + King + 15 Support = 151")
	var short := Deck.from_dict(mix.to_dict())
	short.unit_ids.pop_back()
	check(not short.validate().is_empty(), "14 unit types is invalid")
	var foreign := Deck.from_dict(mix.to_dict())
	var arc_ids := CardDatabase.continent_unit_ids("arcanum")
	foreign.unit_ids[14] = arc_ids[arc_ids.size() - 1]  # a piece of Arcanum in an Aetherion deck
	check(not foreign.validate().is_empty(), "a unit card of another continent is invalid")
	var dupu := Deck.from_dict(mix.to_dict())
	dupu.unit_ids[1] = dupu.unit_ids[0]
	check(not dupu.validate().is_empty(), "a duplicate unit card is invalid")
	check(Deck.from_dict(mix.to_dict()).card_list() == mix.card_list(), "custom loadout survives a dict round-trip")
	foreign.sanitize_units()
	check(foreign.unit_ids.is_empty(), "an invalid saved loadout falls back to the default")
	var saved_decks: Dictionary = SaveManager.data["decks"].duplicate(true)
	SaveManager.set_deck(mix)
	var back := SaveManager.get_deck("aetherion")
	check(back.unit_ids == mix.unit_ids and back.champion_id == mix.champion_id, "the loadout is saved per continent")
	check(SaveManager.get_deck("arcanum").unit_ids.is_empty(), "another continent keeps the default units")
	SaveManager.data["decks"] = saved_decks
	SaveManager.save_game()
	var king_other := Deck.create_default()
	king_other.champion_id = "champion_astralis"  # the King is not tied to the continent of the units
	check(king_other.validate().is_empty(), "any King can lead a deck of any continent")

	# Star upgrades: 3 copies -> 2 stars, 9 copies -> 3 stars
	var r := UnitRoster.new()
	var pid := "pawn_royal_guard"
	r.add_copy(pid)
	check(r.units.size() == 1 and r.units[0].stars == 1, "1 copy = B1")
	r.add_copy(pid)
	var ev := r.add_copy(pid)
	check(r.units.size() == 1 and r.units[0].stars == 2 and ev.size() == 1, "3 copies = one 2-star")
	for i in range(6):
		r.add_copy(pid)
	check(r.units.size() == 1 and r.units[0].stars == 3, "9 copies = one 3-star")
	var s1 := CardDatabase.unit_stats(pid, 1)
	var s3 := CardDatabase.unit_stats(pid, 3)
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
	BattleDeck.supports_in_shop = false  # this block counts unit cards only
	var bd := BattleDeck.new(d, rng)
	check(bd.remaining() == 135, "battle deck pool = 135")
	var shop := bd.draw_shop()
	check(shop.size() == 5 and bd.remaining() == 130, "shop draws 5")
	bd.return_cards(shop)
	check(bd.remaining() == 135, "unbought cards return to the pile")
	var all: Array[String] = []
	while bd.remaining() > 0:
		all.append_array(bd.draw_shop())
	BattleDeck.supports_in_shop = true
	var per := {}
	for c in all:
		per[c] = int(per.get(c, 0)) + 1
	var nine := true
	for c in per:
		nine = nine and per[c] == 9
	check(all.size() == 135 and per.size() == 15 and nine, "every unit type appears exactly 9 times")

	# Faction layout: every faction owns its 7 pieces (2 Rook, 2 Knight, 2 Bishop, Queen); the 8 Pawns (2 per faction) belong to the continent
	var pawn_fac := {}
	var piece_fac := {}
	for u in CardDatabase.all_units():
		check(not CardDatabase.is_shared(u), "%s: belongs to one faction" % u["id"])
		if u["chess"] == "pawn":
			pawn_fac[u["faction"]] = int(pawn_fac.get(u["faction"], 0)) + 1
		else:
			piece_fac[u["faction"]] = int(piece_fac.get(u["faction"], 0)) + 1
	check(pawn_fac.size() == 4 and pawn_fac.values().all(func(n): return n == 2), "each of the 4 factions has exactly 2 own Pawns (%s)" % str(pawn_fac))
	check(piece_fac.size() == 4 and piece_fac.values().all(func(n): return n == 7), "each of the 4 factions has exactly 7 own pieces (%s)" % str(piece_fac))
	var old_rook := CardDatabase.get_unit("rook_citadel_warden")  # legacy id of the old shared set
	check(not old_rook.is_empty() and old_rook["faction"] == "solvaris" and old_rook["chess"] == "rook", "an old shared-piece id still resolves (first faction's piece of that slot)")
	check(CardDatabase.effective_faction(CardDatabase.get_unit("pawn_dusk_cutpurse"), "elarion") == "nocthyr", "a Pawn keeps its own faction")
	check(CardDatabase.effective_faction({"faction": "common"}, "elarion") == "elarion", "a faction-less card fights for the faction of its side")
	# Faction decks: 8 Pawns + the faction's own 7 pieces = 15 types x 9 = 135, different for every faction
	var deck_sigs := {}
	var queen_names := {}
	var piece_names := {}
	for cid in GameData.continents.map(func(c): return c["id"]):
		CardDatabase.set_continent(cid)
		check(CardDatabase.all_units().size() == 36, "%s: 36 unit cards (8 Pawns + 4 factions x 7 pieces)" % cid)
		check(CardDatabase.validate_database().is_empty(), "%s: card database valid (%s)" % [cid, str(CardDatabase.validate_database())])
		for f in GameData.get_continent(cid)["factions"]:
			var dk := Deck.create_default()
			dk.champion_id = f["champion"]
			var types := {}
			for cid_ in dk.card_list():
				if CardDatabase.is_unit(cid_):
					types[cid_] = int(types.get(cid_, 0)) + 1
			check(types.size() == 15 and types.values().all(func(n): return n == 9) and dk.card_list().size() == 151, "%s: deck = 15 types x 9 + Champion + 15 Support (%d types)" % [f["id"], types.size()])
			var own := CardDatabase.faction_pieces(f["id"])
			check(own.size() == 7 and own.map(func(x): return x["chess"]) == ["rook", "rook", "knight", "knight", "bishop", "bishop", "queen"], "%s: own pieces 2R 2K 2B 1Q in slot order" % f["id"])
			deck_sigs[str(types.keys())] = true
			queen_names[own[6]["name"]] = true
			for x in own:
				piece_names[x["name"]] = true
	check(deck_sigs.size() == 28, "all 28 factions have a different deck (%d)" % deck_sigs.size())
	check(queen_names.size() == 28, "all 28 Queens are unique (%d)" % queen_names.size())
	check(piece_names.size() == 196, "all 196 faction pieces have their own name (%d)" % piece_names.size())
	var kings := 0
	for cid in GameData.continents.map(func(c): return c["id"]):
		for f in GameData.get_continent(cid)["factions"]:
			var kc := GameData.get_champion(String(f["champion"]))
			if String(kc.get("rarity", "")) == "legendary" and kc["faction"] == f["id"]:
				kings += 1
	check(kings == 28, "all 28 Kings are Legendary (%d)" % kings)
	var rosters_ok := true
	for cid in GameData.continents.map(func(c): return c["id"]):
		CardDatabase.set_continent(cid)
		rosters_ok = rosters_ok and CardDatabase.all_kings().size() == 4
		for f in GameData.get_continent(cid)["factions"]:
			var ro := CardDatabase.faction_roster(f["id"])
			rosters_ok = rosters_ok and ro.size() == 8 and ro[7]["chess"] == "king" and ro[7]["faction"] == f["id"] and ro[7]["id"] == f["champion"]
	check(rosters_ok, "every faction roster = 7 pieces + its King; every continent lists 4 Kings for the Collection")
	check(CardDatabase.validate_all_continents().is_empty(), "all continents: slots, balanced stats, mechanics, buffs (%s)" % str(CardDatabase.validate_all_continents()))
	CardDatabase.set_continent("machina")
	var wall: Dictionary = CardDatabase.faction_pieces("ferrum")[0]
	check(wall["name"] == "Ironclad Rampart" and CardDatabase.skill_mechanic(wall) == "bulwark", "Ferrum's tank Rook is themed but uses the Bulwark mechanic")
	var vwall: Dictionary = CardDatabase.faction_pieces("voltrix")[0]
	check(wall["hp"] != vwall["hp"] or wall["atk"] != vwall["atk"] or str(wall["skill"].get("params", {})) != str(vwall["skill"].get("params", {})), "factions of one continent differ in the same slot")
	check(CardDatabase.get_unit("queen_aurelia")["faction"] == "solvaris" and not CardDatabase.in_active_set("queen_aurelia"), "a card of another continent still resolves (old saves) but is not in the active set")
	var em := BattleEngine.new()
	em.setup({"seed": 1, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": wall["id"], "stars": 1, "cell": Vector2i(1, 5)}], "champion": "champion_ferrum", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(1, 2)}], "champion": "champion_voltrix", "supports": []}]})
	check(em.units[0].skill_id == "bulwark", "engine runs the base mechanic of a themed skill (%s)" % em.units[0].skill_id)
	# Every faction's pieces of one slot: the same mechanic with different numbers
	for slot in range(6):
		var seen := {}
		for cid in GameData.continents.map(func(c): return c["id"]):
			CardDatabase.set_continent(cid)
			for f in GameData.get_continent(cid)["factions"]:
				seen[str(CardDatabase.faction_pieces(f["id"])[slot]["skill"].get("params", {}))] = true
		check(seen.size() >= 4, "piece slot %d: skill numbers vary between factions (%d variants)" % [slot, seen.size()])
	# Every unit card has a buff on every continent (unique name per card; the Pawns differ per continent)
	var queen_types := {}
	for cid in GameData.continents.map(func(c): return c["id"]):
		CardDatabase.set_continent(cid)
		for u in CardDatabase.all_units():
			var bf := CardDatabase.get_buff(u["id"])
			check(not bf.is_empty() and CardDatabase.BUFF_TYPES.has(String(bf.get("type", ""))), "%s / %s has a buff (%s)" % [cid, u["id"], bf.get("name", "-")])
		for f in GameData.get_continent(cid)["factions"]:
			var qc: Dictionary = CardDatabase.faction_pieces(f["id"])[6]
			queen_types[String(CardDatabase.get_buff(qc["id"])["type"])] = true
			check(CardDatabase.skill_mechanic(qc) == "sovereign_decree", "%s: the Queen keeps the +15%% ATK aura" % f["id"])
	check(queen_types.size() >= 7, "the Queens use at least 7 different buff effects (%s)" % str(queen_types.keys()))
	var pawn_buffs := {}
	for cid in GameData.continents.map(func(c): return c["id"]):
		CardDatabase.set_continent(cid)
		pawn_buffs[String(CardDatabase.get_buff("pawn_royal_guard")["name"])] = true
	check(pawn_buffs.size() == 7, "the same Pawn has a different buff on each continent")
	CardDatabase.set_continent("aetherion")
	var eg := BattleEngine.new()
	eg.setup({"seed": 1, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": _piece_with_buff("guard", "queen"), "stars": 1, "cell": Vector2i(3, 5)}, {"card_id": "pawn_sun_squire", "stars": 1, "cell": Vector2i(4, 5)}, {"card_id": "pawn_sun_squire", "stars": 1, "cell": Vector2i(7, 7)}], "champion": "champion_solvaris", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 2)}], "champion": "champion_nocthyr", "supports": []}]})
	var near: BattleUnit = eg.units_of(0)[1]
	var far: BattleUnit = eg.units_of(0)[2]
	var near_hp := near.hp
	var far_hp := far.hp
	eg._damage(near, 50)
	eg._damage(far, 50)
	check(near_hp - near.hp < far_hp - far.hp, "Queen's guard: an ally next to her takes less damage (%d vs %d)" % [near_hp - near.hp, far_hp - far.hp])
	# Aetherion buffs in battle: armor, evade, thorns, ward, last rites
	CardDatabase.set_continent("aetherion")
	var eb := BattleEngine.new()
	eb.setup({"seed": 1, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(0, 5)}, {"card_id": "pawn_dusk_cutpurse", "stars": 1, "cell": Vector2i(2, 5)}, {"card_id": "pawn_iron_pikeman", "stars": 1, "cell": Vector2i(4, 5)},
			{"card_id": _piece_with_buff("ward", "rook"), "stars": 1, "cell": Vector2i(6, 5)}, {"card_id": _piece_with_buff("last_rites", "bishop"), "stars": 1, "cell": Vector2i(0, 7)}, {"card_id": "pawn_sun_squire", "stars": 1, "cell": Vector2i(1, 7)}], "champion": "champion_solvaris", "supports": []},
		{"units": [{"card_id": "pawn_sun_squire", "stars": 1, "cell": Vector2i(4, 4)}], "champion": "champion_nocthyr", "supports": []}]})
	var mine := eb.units_of(0)
	check(eb._damage(mine[0], 100) == 90, "Oath of the Crown: Royal Guard takes 10% less damage")
	var dodged := 0
	for i in range(4):
		if eb._damage(mine[1], 10) == 0:
			dodged += 1
	check(dodged == 1, "Slippery Fingers: every 4th hit is avoided (%d of 4)" % dodged)
	check(mine[3].shield == int(round(mine[3].max_hp * mine[3].extra_value)) and mine[3].shield > 0, "Ward: the Rook starts with a shield")
	var foe: BattleUnit = eb.units_of(1)[0]
	var foe_hp := foe.hp
	eb._attack(foe, mine[2])
	check(foe.hp < foe_hp, "Pike Wall: the Pikeman reflects damage (%d -> %d)" % [foe_hp, foe.hp])
	var sq: BattleUnit = mine[5]
	sq.hp = maxi(1, sq.max_hp - 40)
	var hp_before := sq.hp
	eb._damage(mine[4], 99999)
	check(not mine[4].alive and sq.hp > hp_before, "Last Rites: the fallen Bishop heals adjacent allies (%d -> %d)" % [hp_before, sq.hp])
	CardDatabase.set_continent("eclipsia")
	var q_ecl: String = _piece_with_buff("second_life", "queen")
	var eq := BattleEngine.new()
	eq.setup({"seed": 1, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": q_ecl, "stars": 1, "cell": Vector2i(3, 5)}], "champion": "champion_solstice", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 2)}], "champion": "champion_oblivion", "supports": []}]})
	var qu: BattleUnit = eq.units_of(0)[0]
	eq._damage(qu, 99999)
	check(qu.alive and qu.hp == maxi(1, int(qu.max_hp * qu.extra_value)), "a Queen with Second Life returns once with her HP share (hp %d)" % qu.hp)
	eq._damage(qu, 99999)
	check(not qu.alive, "Second Life is used only once")
	CardDatabase.set_continent("machina")
	var q_mac: String = _piece_with_buff("opening_shield", "queen")
	var em2 := BattleEngine.new()
	em2.setup({"seed": 1, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": q_mac, "stars": 1, "cell": Vector2i(3, 5)}, {"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(4, 5)}], "champion": "champion_ferrum", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 2)}], "champion": "champion_voltrix", "supports": []}]})
	var ally: BattleUnit = em2.units_of(0)[1]
	check(ally.shield == int(round(ally.max_hp * em2.units_of(0)[0].extra_value)) and ally.shield > 0, "a Queen with Opening Shield gives the side an opening shield (%d)" % ally.shield)
	CardDatabase.set_continent("sylvaris")
	var q_syl: String = _piece_with_buff("regen", "queen")
	var es := BattleEngine.new()
	es.setup({"seed": 1, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": q_syl, "stars": 1, "cell": Vector2i(3, 5)}], "champion": "champion_verdantia", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 2)}], "champion": "champion_besthara", "supports": []}]})
	check(es.units_of(0)[0].extra == "regen" and es.units_of(0)[0].buff_next_tick == 8, "a Queen with Regen heals allies every 8 ticks")
	CardDatabase.set_continent("aetherion")
	# Battle: a faction's own pieces count for that faction's Synergy
	var vp := CardDatabase.faction_pieces("valdoria")
	var ep := CardDatabase.faction_pieces("elarion")
	var e := BattleEngine.new()
	e.setup({"seed": 1, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": vp[0]["id"], "stars": 1, "cell": Vector2i(1, 5)}, {"card_id": vp[6]["id"], "stars": 1, "cell": Vector2i(2, 5)}], "champion": "champion_valdoria", "supports": []},
		{"units": [{"card_id": ep[2]["id"], "stars": 1, "cell": Vector2i(1, 2)}, {"card_id": ep[4]["id"], "stars": 1, "cell": Vector2i(2, 2)}], "champion": "champion_elarion", "supports": []}]})
	var f0 := []
	var f1 := []
	for bu in e.units:
		(f0 if bu.side == 0 else f1).append(bu.faction)
	check(f0 == ["valdoria", "valdoria"] and f1 == ["elarion", "elarion"], "faction pieces fight for their own faction (%s / %s)" % [str(f0), str(f1)])
	check(e.units[0].max_hp == int(round(float(CardDatabase.unit_stats(vp[0]["id"], 1)["hp"]) * 1.05)), "two own pieces give the side's Faction Synergy (+5%)")

	# Old saves only own the Aetherion set: ensure_collection adds the new continents' cards (9 copies each)
	var saved: Dictionary = SaveManager.data.duplicate(true)
	for id in CardDatabase.all_unit_ids_any_continent():
		if String(CardDatabase.get_unit(id).get("continent", "")) not in ["", "aetherion"]:
			SaveManager.data["collection"].erase(id)
	SaveManager.ensure_collection()
	var restored := true
	for id in CardDatabase.all_unit_ids_any_continent():
		restored = restored and SaveManager.owned_count(id) == int(GameData.b("unit_copies"))
	check(restored, "ensure_collection adds the per-continent cards to an old save")
	SaveManager.data = saved

	print("CARD TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


## A piece (Rook / Bishop / Queen ...) of any continent whose buff has the given effect type.
func _piece_with_buff(btype: String, chess: String) -> String:
	for u in GameData.cards["units"]:
		if u["chess"] == chess and u.has("continent") and String(CardDatabase.get_buff(u["id"]).get("type", "")) == btype:
			return String(u["id"])
	push_error("no %s with buff %s" % [chess, btype])
	return ""
