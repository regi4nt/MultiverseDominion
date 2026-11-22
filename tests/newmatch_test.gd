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
	check(SaveManager.journey_frontier() == "aetherion", "a new save starts the Journey on Aetherion")
	check(SaveManager.journey_picks_available() == 0 and not SaveManager.choose_continent("arcanum"), "no continent can be opened at the start")
	_win("aetherion", "solvaris", false)  # Arena win
	check(SaveManager.journey_won_factions("aetherion").is_empty(), "an Arena win counts for nothing")
	SaveManager.record_match(false, 10, 100, "aetherion", true, "solvaris")  # Journey defeat
	check(SaveManager.journey_won_factions("aetherion").is_empty(), "a Journey defeat counts for nothing")
	_win("aetherion", "solvaris")
	_win("aetherion", "solvaris")
	check(SaveManager.journey_won_factions("aetherion") == ["solvaris"], "a Journey win counts once per faction")
	_win("aetherion", "astralis")  # a faction of another continent
	check(SaveManager.journey_won_factions("aetherion") == ["solvaris"], "a faction of another continent does not count towards mastery")
	_win("aetherion", "nocthyr")
	_win("aetherion", "valdoria")
	check(not SaveManager.is_journey_cleared("aetherion") and SaveManager.journey_picks_available() == 0, "3 of 4 factions: not mastered, no unlock yet")
	_win("aetherion", "elarion")
	check(SaveManager.is_journey_cleared("aetherion"), "all 4 factions won: the continent is mastered")
	check(SaveManager.journey_picks_available() == 1, "a mastered continent earns one unlock")
	check(not SaveManager.is_continent_unlocked("arcanum"), "mastering does not open a continent by itself")
	check(not SaveManager.choose_continent("aetherion"), "an open continent cannot be 'chosen'")
	check(SaveManager.choose_continent("machina"), "the player can choose ANY locked continent")
	check(SaveManager.is_continent_unlocked("machina") and SaveManager.can_use_faction("ferrum"), "the chosen continent and its factions are open")
	check(not SaveManager.is_continent_unlocked("arcanum"), "the others stay locked")
	check(SaveManager.journey_picks_available() == 0 and not SaveManager.choose_continent("arcanum"), "one mastery = one unlock")
	check(SaveManager.journey_frontier() == "machina", "the Journey goal moves to the open continent that is not mastered")
	for f in ["ferrum", "voltrix", "chronex", "nexaris"]:
		_win("machina", f)
	check(SaveManager.journey_picks_available() == 1, "mastering the new continent earns the next unlock")
	check(SaveManager.choose_continent("eclipsia") and SaveManager.journey_picks_available() == 0, "and it can be spent on another continent")
	for c in GameData.continents:
		SaveManager.unlock_continent(String(c["id"]))
	check(SaveManager.journey_picks_available() == 0, "with everything open there is nothing left to pick")


func _test_config() -> void:
	GameSession.mode = "custom_ai"
	GameSession.ai_count = 1
	GameSession.category = "journey"
	var cfg := GameSession.to_match_config()
	check(cfg["journey"] == true and cfg["ai_count"] == 1 and cfg["team_mode"] == false, "Journey config: 1vs1, journey flag set")
	GameSession.category = "arena"
	check(GameSession.to_match_config()["journey"] == false, "Arena config: no journey flag")
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
	check(offline == ["Card_journey", "Card_arena", "Card_battle_chess", "Card_tutorial"], "Offline shows Journey, Arena, Battle Chess, Tutorial (%s)" % str(offline))
	for ch in n._cards_row.get_children():
		check(not (ch.get_node("Tap") as Button).disabled, "offline card %s is playable" % ch.name)
	n._set_tab("online")
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
	check(_find_button(n, "2.  ARCANUM") != null and _find_button(n, "2.  ARCANUM").disabled, "Journey: locked continents stay locked until one is earned")
	check(_find_button(n, "1.  AETHERION").text.find("0 / 4") >= 0, "the continent row shows the factions won")
	check(_find_button(n, "1 vs 1") == null, "Journey has no player-count choice")
	check(n._journey_hint.text.find("Solvaris") >= 0 and n._journey_hint.text.find("AETHERION") >= 0, "Journey hint names the faction that must win")
	# earn an unlock: win with all 4 Aetherion factions
	for f in ["solvaris", "nocthyr", "valdoria", "elarion"]:
		_win("aetherion", f)
	n._show_setup("journey")
	var arc := _find_button(n, "2.  ARCANUM")
	check(arc != null and not arc.disabled and arc.text.find("Tap to unlock") >= 0, "an earned unlock makes the locked continents choosable")
	check(_find_button(n, "5.  DRAKMOR").text.find("Tap to unlock") >= 0, "any locked continent can be chosen, not only the next one")
	arc.pressed.emit()
	var dlg: UiDialog = n.get_node("UnlockDialog")
	check(dlg != null and not SaveManager.is_continent_unlocked("arcanum"), "choosing asks for confirmation first")
	dlg.confirmed.emit()
	check(SaveManager.is_continent_unlocked("arcanum"), "confirming opens the chosen continent")
	check(_find_button(n, "3.  MACHINA").disabled and _find_button(n, "3.  MACHINA").text.find("Locked") >= 0, "the unlock is spent: the others are locked again")
	check(GameSession.continent_id == "arcanum", "the Journey now points at the new continent")
	check(n._journey_hint.text.find("does not count") >= 0, "a faction of another continent is explained as not counting")
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
	check(_find_button(n, "3.  MACHINA").disabled, "Arena: locked continents cannot be picked")
	check(n._champion_text.text.find("Nocthyr") >= 0 or n._champion_text.text.find("Solvaris") >= 0, "Arena shows the faction of the Deck")
	check(GameSession.faction_id == SaveManager.player_faction_id(), "the match faction is the Deck faction")
	check(_find_button(n, "Valdoria") == null and _find_button(n, "Elarion") == null, "New Match has no faction buttons")
	check(_find_button(n, "Change faction") != null, "New Match links to the Deck to change the faction")
	n.on_back_requested()
	n.queue_free()
	await get_tree().process_frame
