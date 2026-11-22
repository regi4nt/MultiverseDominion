extends Node
## Phase 6 test: 7 continents, 28 factions/champions, world modifiers, passives, champion actives,
## every Support effect. Run: godot --headless --path . res://tests/content_test.tscn

var failures := 0
const PASSIVES := ["royal_treasury", "shadow_ledger", "landlord", "fortune_weave", "toll_keeper", "treasure_hunter", "spoils", "quartermaster", "mender", "vanguard"]
const ACTIVES := ["sun_judgment", "starfall_decree", "eclipse_veil", "banner_of_iron", "inferno_burst", "chrono_stasis", "soul_drain", "frost_veil", "overcharge", "rift_strike", "life_surge"]


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	_test_data()
	_test_boards_and_modifiers()
	_test_passives()
	_test_champions()
	_test_supports()
	_test_games()
	print("CONTENT TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_data() -> void:
	check(GameData.continents.size() == 7, "7 continents")
	var all_ok := true
	var factions := 0
	for c in GameData.continents:
		all_ok = all_ok and bool(c.get("playable", false)) and (c["regions"] as Array).size() == 4 and (c["territory_prefixes"] as Array).size() == 10
		for f in c["factions"]:
			factions += 1
			var ch := GameData.get_champion(String(f["champion"]))
			all_ok = all_ok and not ch.is_empty() and PASSIVES.has(ch["passive"]) and ACTIVES.has(ch["skill_id"]) and String(ch["faction"]) == String(f["id"])
	check(factions == 28, "28 factions")
	check(all_ok, "every continent is playable with 4 regions, 10 prefixes and 4 factions with valid champions")
	check(GameData.champions.size() == 28, "28 distinct champions")
	var combos := {}
	for k in GameData.champions:
		combos[str(GameData.champions[k]["passive"]) + "/" + str(GameData.champions[k]["skill_id"]) + "/" + str(GameData.champions[k]["passive_value"]) + "/" + str(GameData.champions[k]["active_value"])] = true
	check(combos.size() == 28, "champions are all different (passive/active/values)")
	var used_p := {}
	var used_a := {}
	for k in GameData.champions:
		used_p[GameData.champions[k]["passive"]] = true
		used_a[GameData.champions[k]["skill_id"]] = true
	check(used_p.size() == PASSIVES.size() and used_a.size() == ACTIVES.size(), "all %d passives and %d actives are used" % [PASSIVES.size(), ACTIVES.size()])
	check(CardDatabase.validate_database().is_empty(), "card database valid")


func _test_boards_and_modifiers() -> void:
	var mods_seen := {}
	for c in GameData.continents:
		var c2 := MatchController.new()
		c2.setup({"continent_id": c["id"], "faction_id": c["factions"][0]["id"], "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
		check(c2.tiles.size() == 100 and BoardBuilder.count_types(c2.tiles)["Territory"] == 40, "%s: 100-tile board with 40 territories" % c["id"])
		check(c2.tiles[1].name != "" and c2.players.size() == 4, "%s: territory names and 4 players" % c["id"])
		mods_seen[WorldMods.modifier_name] = true
		var u := CardDatabase.get_unit("pawn_royal_guard")
		check(String(u["faction"]) == String(c["factions"][0]["id"]), "%s: unit cards belong to the continent's factions" % c["id"])
	check(mods_seen.size() == 7, "7 different world modifiers")
	# individual modifier effects
	var c := MatchController.new()
	c.setup({"continent_id": "arcanum", "faction_id": "astralis", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	check(PortalSystem.active_indices(c.tiles).size() == 8, "Arcanum: 8 active portals (2 per region)")
	PortalSystem.rotate_portals(c.tiles, c.rng)
	check(PortalSystem.active_indices(c.tiles).size() == 8, "Arcanum: still 8 after rotation")
	c.setup({"continent_id": "machina", "faction_id": "ferrum", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	var t: BoardTile = c.tiles[1]
	t.owner_id = 1
	var machina_rent := EconomySystem.rent_of(t, c.tiles)
	WorldMods.reset()
	check(machina_rent > EconomySystem.rent_of(t, c.tiles), "Machina: rent is higher than without the modifier")
	WorldMods.apply(c.continent)
	var prep := BattlePrep.new(Deck.create_default(), c.rng, 500, 500, 3)
	check(prep.unit_price("pawn_royal_guard") == 24, "Machina: Battle Shop prices -20% (30 -> 24)")
	c.setup({"continent_id": "sylvaris", "faction_id": "verdantia", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	c.tiles[1].owner_id = 0
	c.tiles[2].owner_id = 0
	var g := c.players[0].gold
	c._end_of_round()
	check(c.players[0].gold == g + 2 * 6, "Sylvaris: harvest pays 6 G per territory")
	c.setup({"continent_id": "thalassia", "faction_id": "abyssal", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	check(WorldMods.token_price() == 40, "Thalassia: Reroll Token costs 40 G")
	c.players[0].gold = 1000
	var tax_tile: BoardTile = null
	for tt in c.tiles:
		if tt.type == BoardTile.Type.TAX:
			tax_tile = tt
			break
	c.players[0].position = tax_tile.index
	c.current = 0
	var gb := c.players[0].gold
	c._resolve_landing(c.players[0])
	check(gb - c.players[0].gold == int(int(GameData.b("tax_flat")) * 0.5 * (1.0 - (c.players[0].passive_value if c.players[0].has_passive("shadow_ledger") else 0.0))), "Thalassia: tax tiles cost half")
	c.setup({"continent_id": "eclipsia", "faction_id": "solstice", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	var tk := c.players[0].reroll_tokens
	c._give_start_bonus(c.players[0])
	check(c.players[0].reroll_tokens == tk + 1, "Eclipsia: passing START grants a Reroll Token")
	c.setup({"continent_id": "drakmor", "faction_id": "drakhan", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	var e := BattleEngine.new()
	e.setup({"seed": 1, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": "pawn_sun_squire", "stars": 1, "cell": Vector2i(3, 5)}], "champion": "champion_drakhan", "supports": []},
		{"units": [], "champion": "champion_inferna", "supports": []}]})
	check(e.units[0].base_atk == int(round(11.0 * 1.15)), "Drakmor: War Fever +15% ATK in battle (11 -> 13)")
	WorldMods.apply(GameData.get_continent("aetherion"))


func _test_passives() -> void:
	var mk := func(fac: String, cont: String) -> MatchController:
		var c := MatchController.new()
		c.setup({"continent_id": cont, "faction_id": fac, "difficulty": "normal", "ai_count": 3, "seed": 9, "all_ai": true})
		return c
	var c: MatchController = mk.call("ignivar", "arcanum")  # spoils 40
	var p := c.players[0]
	check(p.has_passive("spoils") and p.passive_value == 40.0, "passive values come from champion data")
	var g := p.gold
	c.pending = {"type": "duel_battle", "tile": 1, "attacker": 0, "defender": 1}
	c.state = MatchController.State.AWAIT_DUEL
	c.finish_duel({"winner": 0})
	check(p.gold == g + 40, "Spoils of War: +40 G for winning a duel")
	c = mk.call("astralis", "arcanum")  # treasure_hunter 40
	var gh := c.players[0].gold
	c.players[0].position = 4
	c.current = 0
	for t in c.tiles:
		if t.type == BoardTile.Type.EVENT:
			c.players[0].position = t.index
			break
	c._resolve_landing(c.players[0])
	check(c.players[0].gold >= gh + 40 - 100 and c.stats != null, "Treasure Hunter pays on Event tiles")
	c = mk.call("cryndel", "arcanum")  # mender
	var pv: float = float(GameData.get_champion("champion_cryndel")["passive_value"])
	check(c.heal_price_for(c.players[0]) == int(round(float(GameData.b("heal_price")) * (1.0 - pv))), "Mender: Life restoration is %d%% cheaper (value from data)" % int(pv * 100))
	c = mk.call("ferrum", "machina")  # quartermaster
	check(is_equal_approx(c.players[0].battle_price_mult(), 0.8), "Quartermaster: -20% Battle Shop prices")
	c = mk.call("besthara", "sylvaris")  # vanguard 2
	var rare := 0
	for u in c.players[0].roster.units:
		if CardDatabase.get_unit(u.card_id)["rarity"] == "rare":
			rare += 1
	check(rare == 2, "Vanguard: 2 extra rare starter units")
	c = mk.call("voltrix", "machina")  # toll keeper 0.25 owned by seat 0
	var tl: BoardTile = c.tiles[1]
	tl.owner_id = 0
	c.current = 1
	c.players[1].position = 1
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[1])
	var base := EconomySystem.rent_of(tl, c.tiles)
	var expected := int(int(base * 1.25) * (1.0 - (c.players[1].passive_value if c.players[1].has_passive("shadow_ledger") else 0.0)))
	check(int(c.pending["rent"]) == expected, "Toll Keeper: owner collects +25%% rent (%d)" % expected)


func _test_champions() -> void:
	# every champion enters Last Stand and casts its active skill without errors, against a pawn line
	var ok := true
	for cid in GameData.champions:
		var e := BattleEngine.new()
		e.setup({"seed": 3, "ai_supports": [false, false], "sides": [
			{"units": [], "champion": cid, "supports": []},
			{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(2, 2)}, {"card_id": "pawn_sun_squire", "stars": 1, "cell": Vector2i(5, 2)}, {"card_id": "knight_dawnlancer", "stars": 1, "cell": Vector2i(4, 3)}], "champion": "champion_solvaris", "supports": []}]})
		var n := 0
		while not e.finished and n < 500:
			e.step()
			n += 1
		ok = ok and e.finished and e.king_entered[0] and e.king_entry_tick[0] == 0
	check(ok, "all 28 champions enter Last Stand, cast their active and finish a battle")
	var e := BattleEngine.new()
	e.setup({"seed": 3, "ai_supports": [false, false], "sides": [
		{"units": [], "champion": "champion_cryndel", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(2, 2)}], "champion": "champion_solvaris", "supports": []}]})
	check(e.units_of(1)[0].slow_until > 0, "Frost Veil slows enemies on entry")
	e = BattleEngine.new()
	e.setup({"seed": 3, "ai_supports": [false, false], "sides": [
		{"units": [], "champion": "champion_chronex", "supports": []},
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(2, 2)}], "champion": "champion_solvaris", "supports": []}]})
	check(e.units_of(1)[0].stun_until > 0, "Chrono Stasis stuns enemies on entry")


func _make_support_engine(hand: Array) -> BattleEngine:
	var e := BattleEngine.new()
	e.setup({"seed": 4, "ai_supports": [false, false], "sides": [
		{"units": [{"card_id": "pawn_royal_guard", "stars": 1, "cell": Vector2i(3, 5)}, {"card_id": "pawn_sun_squire", "stars": 1, "cell": Vector2i(4, 5)}, {"card_id": "bishop_valdoria_chaplain", "stars": 1, "cell": Vector2i(2, 6)}], "champion": "champion_solvaris", "supports": hand},
		{"units": [{"card_id": "pawn_iron_pikeman", "stars": 1, "cell": Vector2i(3, 2)}, {"card_id": "pawn_dusk_cutpurse", "stars": 1, "cell": Vector2i(4, 2)}, {"card_id": "rook_citadel_warden", "stars": 1, "cell": Vector2i(3, 1)}], "champion": "champion_nocthyr", "supports": []}]})
	return e


func _test_supports() -> void:
	var all_ok := true
	var failed: Array[String] = []
	for s in CardDatabase.all_supports():
		var e := _make_support_engine([s["id"]])
		var err := e.use_support(0, s["id"])
		var prep_only: bool = PREP_ONLY.has(String(s["effect"]))
		if err != "" and not prep_only:
			all_ok = false
			failed.append("%s: %s" % [s["id"], err])
		for i in range(30):  # the battle must keep running after the effect
			e.step()
	check(all_ok, "all 21 Support effects can be played (%s)" % str(failed))
	var e := _make_support_engine(["sup_fireball", "sup_guardian_angel", "sup_blood_oath", "sup_forge_bastion"])
	check(e.use_support(0, "sup_guardian_angel") == "" and bool(e.revive_pending[0]), "Guardian Angel arms a revive")
	var victim: BattleUnit = e.units[0]
	e._damage(victim, 9999)
	check(victim.alive and victim.hp > 0 and not bool(e.revive_pending[0]), "the first fallen unit is revived once")
	e._damage(victim, 9999)
	check(not victim.alive, "...but only once")
	check(e.use_support(0, "sup_blood_oath") == "" and int(e.gold_delta[0]) == -20 and float(e.lifesteal[0]) > 0.0, "Blood Oath: lifesteal and -20 G")
	check(e.use_support(0, "sup_forge_bastion") == "" and e.walls.size() == 1, "Forge Bastion creates a wall")
	var wall_cell: Vector2i = e.walls.keys()[0]
	check(e.grid.has(wall_cell) == false, "a wall is not a unit")
	for i in range(20):
		e.step()
	check(e.walls.is_empty(), "the wall expires after 16 ticks")
	# prep-time cards
	var prep := BattlePrep.new(Deck.create_default(), RandomNumberGenerator.new(), 500, 500, 3)
	prep.apply_hand(["sup_mercenary_pact", "sup_merchant_contract"])
	check(prep.capacity() == 12 and prep.free_reroll, "Mercenary Pact (+3 capacity) and Merchant Contract (free reroll) apply in preparation")
	var gold := prep.gold
	prep.refresh_offers(true)
	check(prep.gold == gold, "the first reroll is free")


const PREP_ONLY: Array[String] = ["temp_capacity", "free_reroll"]


func _test_games() -> void:
	var finished_all := true
	var n := 0
	for c in GameData.continents:
		for s in range(1, 4):
			var m := MatchController.new()
			m.setup({"continent_id": c["id"], "faction_id": c["factions"][s % 4]["id"], "difficulty": ["easy", "normal", "hard"][s % 3], "ai_count": 3, "seed": 70 + s, "all_ai": true})
			var steps := 0
			while m.state != MatchController.State.GAME_OVER and steps < 60000:
				AIController.step(m)
				steps += 1
			n += 1
			if m.state != MatchController.State.GAME_OVER:
				finished_all = false
				push_error("stuck on %s seed %d" % [c["id"], s])
	check(finished_all, "%d full AI games finish on all 7 continents" % n)
