extends Node
## New Match: Journey vs Arena rules (only Journey unlocks continents), match config / save round trip,
## and the hub + setup views of match_setup.
## Run: godot --headless --path . res://tests/newmatch_test.tscn   -> "NEW MATCH TEST RESULT: PASS"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	var backup: Dictionary = SaveManager.data.duplicate(true)
	_test_unlock_rules()
	_test_config()
	_test_faction_rules()
	await _test_deck_ui()
	await _test_ui()
	SaveManager.data = backup
	SaveManager.save_game()
	print("NEW MATCH TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _fresh_save() -> void:
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()


func _win(cid: String, fid: String, journey: bool = true) -> void:
	SaveManager.record_match(true, 10, 100, cid, journey, fid)


func _test_unlock_rules() -> void:
	_fresh_save()
	check(SaveManager.journey_frontier() == "aetherion" and SaveManager.trophies() == 0, "a new save starts the Journey on Aetherion with 0 trophies")
	check(SaveManager.next_continent_goal() == "arcanum" and SaveManager.continent_trophies("arcanum") == 150, "the next goal is Arcanum at 150 trophies")
	_win("aetherion", "solvaris", false)  # Arena win
	check(SaveManager.trophies() == 0, "an Arena win earns no trophies")
	SaveManager.record_match(false, 10, 100, "aetherion", true, "solvaris")  # Journey defeat at the floor
	check(SaveManager.trophies() == 0 and SaveManager.last_trophy_delta == 0, "trophies never drop below the floor (0 at the start)")
	SaveManager.record_match(true, 10, 100, "aetherion", true, "solvaris", {}, "normal")
	check(SaveManager.trophies() == 30 and SaveManager.last_trophy_delta == 30, "a Journey win on Normal gives +30 trophies")
	SaveManager.record_match(false, 10, 100, "aetherion", true, "solvaris", {}, "normal")
	check(SaveManager.trophies() == 10, "a Journey defeat on Normal takes 20 trophies")
	SaveManager.record_match(true, 10, 100, "aetherion", true, "solvaris", {}, "hard")
	SaveManager.record_match(true, 10, 100, "aetherion", true, "solvaris", {}, "easy")
	check(SaveManager.trophies() == 10 + 40 + 20, "Hard wins give +40, Easy wins +20")
	SaveManager.record_match(false, 10, 100, "aetherion", true, "solvaris", {}, "easy")
	SaveManager.record_match(false, 10, 100, "aetherion", true, "solvaris", {}, "hard")
	check(SaveManager.trophies() == 70 - 30 - 10, "Easy defeats take 30, Hard defeats only 10")
	# climb to the Arcanum threshold: the continent opens by itself, only its cards are opened for the Shop
	_fresh_save()
	var wins := 0
	while not SaveManager.is_continent_unlocked("arcanum") and wins < 20:
		SaveManager.record_match(true, 10, 100, "aetherion", true, "solvaris", {}, "normal")
		wins += 1
	check(wins == 5 and SaveManager.trophies() == 150, "5 Normal wins reach 150 trophies and open Arcanum")
	check(SaveManager.last_opened_continents == ["arcanum"], "the result reports the newly opened continent")
	check(SaveManager.can_use_faction("astralis"), "the opened continent's factions can be used")
	check(not SaveManager.is_continent_unlocked("machina"), "the next continent stays locked")
	check(SaveManager.journey_frontier() == "arcanum", "the Journey continent moves to the newest open one")
	check(SaveManager.trophy_floor() == 150, "the trophy floor is the threshold of the highest open continent")
	SaveManager.record_match(false, 10, 100, "arcanum", true, "astralis", {}, "easy")
	check(SaveManager.trophies() == 150 and SaveManager.is_continent_unlocked("arcanum"), "a defeat cannot take you below the floor or close a continent")
	for c in GameData.continents:
		SaveManager.unlock_continent(String(c["id"]))
	check(SaveManager.next_continent_goal() == "", "with everything open there is no next goal")
	# an older save: every unit owned, factions-based Journey -> keeps the units, trophies start at the floor of the open continents
	var old := SaveManager.default_data()
	old["collection"] = {}
	for id in CardDatabase.all_unit_ids_any_continent():
		old["collection"][id] = 9
	old["unlocked_continents"] = ["aetherion", "machina"]
	old.erase("unit_cards_v")
	SaveManager.data = old
	SaveManager.ensure_collection()
	check(SaveManager.data["unit_cards_v"] == 2, "an old save is migrated once")
	check(SaveManager.trophies() == 400, "an old save starts the trophy road at its highest open continent")
	var all_owned := true
	for id in CardDatabase.all_unit_ids_any_continent():
		all_owned = all_owned and SaveManager.owned_count(id) > 0
	check(all_owned, "an old save keeps every unit card it owned")


func _test_config() -> void:
	GameSession.mode = "custom_ai"
	GameSession.ai_count = 1
	GameSession.category = "journey"
	var cfg := GameSession.to_match_config()
	check(cfg["journey"] == true and cfg["ai_count"] == 1 and cfg["team_mode"] == false, "Journey config: 1vs1, journey flag set")
	GameSession.category = "arena"
	check(GameSession.to_match_config()["journey"] == false, "Arena config: no journey flag")
	check(GameSession.to_match_config()["any_continent_enemies"] == true and cfg["any_continent_enemies"] == false, "Arena draws enemies from every continent, Journey does not")
	var foreign := false
	var own_only := true
	for sd in range(1, 13):  # Arena opponents: factions of every continent (more than just the map's own four), never the player's faction
		var mc := MatchController.new()
		mc.setup({"continent_id": "aetherion", "faction_id": "solvaris", "ai_count": 3, "seed": sd, "any_continent_enemies": true})
		for pl in mc.players:
			if pl.is_ai and GameData.get_faction("aetherion", pl.faction_id).is_empty():
				foreign = true
			if pl.is_ai and pl.faction_id == "solvaris":
				own_only = false
		var mj := MatchController.new()
		mj.setup({"continent_id": "aetherion", "faction_id": "solvaris", "ai_count": 3, "seed": sd})
		for pl in mj.players:
			if GameData.get_faction("aetherion", pl.faction_id).is_empty():
				own_only = false
	var gold_ok := true
	for dd in [["easy", 2000], ["normal", 1500], ["hard", 1000]]:
		var mg := MatchController.new()
		mg.setup({"continent_id": "aetherion", "faction_id": "solvaris", "ai_count": 1, "seed": 5, "difficulty": dd[0]})
		for pl in mg.players:
			gold_ok = gold_ok and pl.gold == int(dd[1])
	check(gold_ok, "starting gold follows the difficulty: Easy 2000 / Normal 1500 / Hard 1000 (every seat)")
	check(foreign and own_only, "Arena AI rulers can come from other continents; without the flag they stay on the map's continent")
	GameSession.start_tutorial()
	check(not GameSession.to_match_config().has("journey") or GameSession.to_match_config()["journey"] == false, "the tutorial is never a Journey match")
	GameSession.mode = "ffa_ai"
	GameSession.ai_count = 3
	GameSession.category = "journey"
	var cfg2 := GameSession.to_match_config()
	cfg2["seed"] = 99
	var m := MatchController.new()
	m.setup(cfg2)
	check(m.journey, "MatchController reads the journey flag")
	var back := MatchController.from_dict(m.to_dict())
	check(back.journey, "the journey flag survives save / resume")
	var plain := MatchController.new()
	var cfg3 := GameSession.to_match_config()
	cfg3["journey"] = false
	cfg3["seed"] = 99
	plain.setup(cfg3)
	check(not plain.journey and not MatchController.from_dict(plain.to_dict()).journey, "an Arena match stays non-journey after resume")
	GameSession.category = "arena"


func _test_faction_rules() -> void:
	_fresh_save()
	check(SaveManager.can_use_faction("solvaris") and not SaveManager.can_use_faction("astralis"), "factions of locked continents cannot be used")
	check(SaveManager.player_faction_id() == "solvaris", "a new save plays Solvaris")
	SaveManager.data["decks"]["main"]["champion"] = "champion_astralis"  # older save: King of a locked faction
	check(SaveManager.player_champion_id() == "champion_solvaris", "a King of a locked faction falls back to an open one")
	check(SaveManager.get_deck("aetherion").champion_id == "champion_solvaris", "the saved deck never leads with a locked King")
	SaveManager.unlock_continent("arcanum")
	check(SaveManager.player_faction_id() == "astralis", "once its continent is open the faction can be used")
	check(SaveManager.get_deck("aetherion").champion_id == "champion_astralis", "the Deck King is the same on every continent")
	# a match on another continent with the Deck's faction
	var m := MatchController.new()
	m.setup({"continent_id": "aetherion", "faction_id": "astralis", "difficulty": "normal", "ai_count": 3, "seed": 5, "player_name": "T"})
	var p0: PlayerState = m.players[0]
	check(p0.faction_id == "astralis" and p0.champion_id == "champion_astralis", "the human plays the Deck's faction on any continent")
	check(p0.passive != "", "the King passive works on every continent")
	var mh := MatchController.new()
	mh.setup({"continent_id": "arcanum", "faction_id": "astralis", "difficulty": "normal", "ai_count": 1, "seed": 5, "player_name": "T"})
	check(GameData.is_home_faction("astralis", "arcanum") and not GameData.is_home_faction("astralis", "aetherion"), "is_home_faction follows the faction's continent")
	CardDatabase.set_continent("aetherion")
	var eng := BattleEngine.new()
	eng.king_data = ["champion_astralis", "champion_solvaris"]
	check(not eng._home_bonus(0) and eng._home_bonus(1), "unit buffs are off for a foreign King and on for a home King")
	check(CardDatabase.king_buff("champion_astralis").is_empty(), "the King buff is off outside the King's home continent")
	CardDatabase.set_continent("arcanum")
	check(not CardDatabase.king_buff("champion_astralis").is_empty(), "the King buff is on at the King's home continent")
	var ok28 := true
	for cid in GameData.champions:
		ok28 = ok28 and CardDatabase.BUFF_TYPES.has(String(GameData.king_buffs.get(cid, {}).get("type", "")))
	check(ok28, "every King has a valid buff")
	CardDatabase.set_continent("aetherion")
	var all_ok := m.players.size() == 4
	for p in m.players:
		all_ok = all_ok and p.champion_id != ""
	check(all_ok, "every seat has a champion")
	var back := MatchController.from_dict(m.to_dict())
	check(back.players[0].faction_id == "astralis" and back.players[0].champion_id == "champion_astralis", "the foreign faction survives save / resume")
	var m2 := MatchController.new()
	m2.setup({"continent_id": "aetherion", "faction_id": "no_such_faction", "difficulty": "normal", "ai_count": 1, "seed": 5})
	check(m2.players[0].champion_id != "", "an unknown faction falls back to the continent's first one")


func _test_deck_ui() -> void:
	_fresh_save()
	GameSession.open_deck_tab = true
	var coll: Control = load("res://scenes/card_collection/card_collection.tscn").instantiate()
	add_child(coll)
	await get_tree().process_frame
	check(coll._deck_view.visible and coll._pool_tab == "king", "Change faction opens the Deck tab on the Faction list")
	check(not GameSession.open_deck_tab, "the open-deck flag is consumed")
	check(coll._pool_buttons.size() == 28, "the Faction list shows all 28 factions")
	check((coll._pool_buttons["champion_drakhan"] as CardView).owned <= 0, "a faction of a locked continent is locked")
	check(String((coll._pool_buttons["champion_drakhan"] as CardView).tooltip_text).find("Locked") >= 0, "a locked faction says it is locked")
	check((coll._pool_buttons["champion_nocthyr"] as CardView).owned > 0, "a faction of an open continent can be picked")
	coll._set_king("champion_drakhan")
	check(coll.deck.champion_id == "champion_solvaris", "picking a locked faction does nothing")
	coll._set_king("champion_nocthyr")
	check(coll.deck.champion_id == "champion_nocthyr", "picking an open faction sets the King")
	coll._on_save()
	check(SaveManager.player_faction_id() == "nocthyr", "the saved Deck faction is the faction of every match")
	coll.queue_free()
	await get_tree().process_frame


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).text.begins_with(prefix):
		return n as Button
	for ch in n.get_children():
		var f := _find_button(ch, prefix)
		if f != null:
			return f
	return null


func _test_ui() -> void:
	_fresh_save()
	GameSession.mode = "ffa_ai"
	GameSession.ai_count = 3
	var n: Control = load("res://scenes/match_setup/match_setup.tscn").instantiate()
	add_child(n)
	await get_tree().process_frame
	check(n._view == "hub", "New Match opens on the mode hub")
	var offline: Array[String] = []
	for ch in n._cards_row.get_children():
		offline.append(String(ch.name))
	check(offline == ["Card_journey", "Card_arena", "Card_chaos", "Card_battle_chess", "Card_tutorial"], "Offline shows Journey, Arena, Chaos (right of Arena), Battle Chess, Tutorial (%s)" % str(offline))
	for ch in n._cards_row.get_children():
		check(not (ch.get_node("Tap") as Button).disabled, "offline card %s is playable" % ch.name)
	await get_tree().process_frame
	var sc: ScrollContainer = n._cards_scroll
	var first: Control = n._cards_row.get_child(0)
	check(sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO and sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "the mode cards row scrolls sideways")
	check(n._cards_row.get_child_count() == 5, "offline has 5 mode cards, one more than the 4 shown at once")
	check(absf(first.custom_minimum_size.x * 4.0 + 14.0 * 3.0 - sc.size.x) < 2.0, "4 mode cards fill the row width; the rest is a swipe away")
	var th := UiTheme.get_theme()
	var themed := true
	for kind in ["VScrollBar", "HScrollBar"]:
		for part in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
			themed = themed and th.has_stylebox(part, kind) and th.get_stylebox(part, kind) is StyleBoxFlat
	check(themed, "every scroll bar is styled by the app theme (navy track, gold handle)")
	check(UiTheme.scrollbar_thickness() in [8, 12] and (th.get_stylebox("scroll", "VScrollBar") as StyleBoxFlat).get_minimum_size().x >= float(UiTheme.scrollbar_thickness()) - 1.0, "scroll bar thickness adapts to touch / pointer devices")
	n._set_tab("online")
	await get_tree().process_frame
	check(n._cards_row.get_child(0).custom_minimum_size.x == 0.0, "3 online cards just share the row (no sideways scrolling)")
	var online: Array[String] = []
	for ch in n._cards_row.get_children():
		online.append(String(ch.name))
		check((ch.get_node("Tap") as Button).disabled, "online card %s is disabled (coming soon)" % ch.name)
	check(online == ["Card_classic", "Card_ranked", "Card_online_chess"], "Online shows Classic, Ranked, Battle Chess (%s)" % str(online))
	n._set_tab("offline")

	# Journey
	(n._cards_row.get_node("Card_journey/Tap") as Button).pressed.emit()
	check(n._view == "setup" and n._kind == "journey", "tapping Journey opens its setup")
	check(GameSession.category == "journey" and GameSession.mode == "custom_ai" and GameSession.ai_count == 1, "Journey is always 1 vs 1")
	check(GameSession.continent_id == "aetherion", "Journey preselects the continent to master")
	check(_find_button(n, "2.  ARCANUM") != null and _find_button(n, "2.  ARCANUM").disabled, "Journey: locked continents stay locked until the trophies are reached")
	check(_find_button(n, "2.  ARCANUM").text.find("150 trophies") >= 0, "a locked continent row shows the trophies it needs")
	check(_find_button(n, "1.  AETHERION").text.find("Open") >= 0, "an open continent row says Open")
	check(_find_button(n, "1 vs 1") == null, "Journey has no player-count choice")
	check(n._journey_hint.text.find("Solvaris") >= 0 and n._journey_hint.text.find("AETHERION") >= 0, "Journey hint names the faction that must win")
	# climb the trophy road: the continent opens by itself
	for i in range(5):
		SaveManager.record_match(true, 10, 100, "aetherion", true, "solvaris", {}, "normal")
	n._show_setup("journey")
	var arc := _find_button(n, "2.  ARCANUM")
	check(arc != null and not arc.disabled and arc.text.find("Open") >= 0, "reaching the trophies opens the continent")
	check(_find_button(n, "3.  MACHINA").disabled and _find_button(n, "3.  MACHINA").text.find("400 trophies") >= 0, "the next continent stays locked")
	check(GameSession.continent_id == "arcanum", "the Journey now points at the new continent")
	check(n._journey_hint.text.find("not a faction of") >= 0, "a faction of another continent is explained as not counting")
	n.on_back_requested()
	check(n._view == "hub", "Back from setup returns to the hub")

	# Arena
	(n._cards_row.get_node("Card_arena/Tap") as Button).pressed.emit()
	check(n._view == "setup" and n._kind == "arena" and GameSession.category == "arena", "tapping Arena opens its setup")
	var two := _find_button(n, "2 vs 2")
	check(two != null, "Arena offers 2 vs 2")
	two.button_pressed = true
	two.pressed.emit()
	check(GameSession.mode == "team_2v2" and GameSession.ai_count == 3, "Arena 2 vs 2 sets the team mode")
	var one := _find_button(n, "1 vs 1")
	one.pressed.emit()
	check(GameSession.mode == "custom_ai" and GameSession.ai_count == 1, "Arena 1 vs 1 sets a duel")
	_find_button(n, "4 Player").pressed.emit()
	check(GameSession.mode == "ffa_ai" and GameSession.ai_count == 3, "Arena 4 Player sets the free-for-all")
	var mach := _find_button(n, "3.  MACHINA")
	check(mach != null and not mach.disabled and mach.text.find("King & Pawn stay locked") >= 0, "Arena: every playable continent can be picked, its King and Pawn stay locked")
	check(not SaveManager.is_continent_unlocked("machina") and not SaveManager.is_faction_unlocked("ferrum"), "Arena never unlocks the continent or its factions")
	check(n._champion_text.text.find("Nocthyr") >= 0 or n._champion_text.text.find("Solvaris") >= 0, "Arena shows the faction of the Deck")
	check(GameSession.faction_id == SaveManager.player_faction_id(), "the match faction is the Deck faction")
	check(_find_button(n, "Valdoria") == null and _find_button(n, "Elarion") == null, "New Match has no faction buttons")
	check(_find_button(n, "Change faction") != null, "New Match links to the Deck to change the faction")
	n.on_back_requested()
	check(not GameSession.chaos_mode and not GameSession.to_match_config().get("chaos", false), "Arena is a normal 100-tile match")
	# Chaos: its own card, an Arena setup on the 40-tile board
	(n._cards_row.get_node("Card_chaos/Tap") as Button).pressed.emit()
	check(n._view == "setup" and n._kind == "arena" and GameSession.category == "arena" and GameSession.chaos_mode, "tapping Chaos opens the Arena setup in Chaos Mode")
	check(bool(GameSession.to_match_config().get("chaos", false)), "a Chaos match is configured with the 40-tile board")
	n.on_back_requested()
	(n._cards_row.get_node("Card_arena/Tap") as Button).pressed.emit()
	check(not GameSession.chaos_mode, "choosing Arena again switches Chaos off")
	n.queue_free()
	await get_tree().process_frame
