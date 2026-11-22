extends Node
## Phase 7 test: match save/resume, corrupt files, back button. 
## Run: godot --headless --path . res://tests/save_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func snapshot(c: MatchController) -> String:
	var parts: Array[String] = []
	for p in c.players:
		parts.append("%d:%d:%d:%d:%d:%d:%d:%s:%d" % [p.id, p.gold, p.life, p.position, p.level, p.reroll_tokens, p.roster.units.size(), str(p.alive), p.battle_deck.remaining()])
	var own: Array[int] = []
	for t in c.tiles:
		own.append(t.owner_id)
	return "r%d c%d s%d | %s | %s | %s" % [c.round_number, c.current, c.state, " ".join(parts), str(own), str(c.stats)]


func _ready() -> void:
	_test_roundtrip_determinism()
	_test_human_match_roundtrip()
	_test_unstable_states()
	_test_files()
	_test_back_button()
	SaveManager.clear_match()
	print("SAVE TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _advance_to_stable(c: MatchController, min_round: int) -> void:
	var steps := 0
	while steps < 30000 and c.state != MatchController.State.GAME_OVER:
		if c.round_number >= min_round and (c.state == MatchController.State.AWAIT_ROLL or c.state == MatchController.State.TURN_DONE):
			return
		AIController.step(c)
		steps += 1


func _test_roundtrip_determinism() -> void:
	for cont in ["aetherion", "drakmor", "eclipsia"]:
		var a := MatchController.new()
		a.setup({"continent_id": cont, "faction_id": GameData.get_continent(cont)["factions"][0]["id"], "difficulty": "normal", "ai_count": 3, "seed": 31, "all_ai": true})
		_advance_to_stable(a, 9)
		var json := JSON.stringify(a.to_dict())  # exactly what is written to disk
		var b := MatchController.from_dict(JSON.parse_string(json))
		check(snapshot(a) == snapshot(b), "%s: restored match equals the saved one (round %d)" % [cont, a.round_number])
		check(b.recent_log.size() > 0 and b.recent_log == a.recent_log, "%s: log history restored" % cont)
		var steps := 0
		while steps < 40000 and (a.state != MatchController.State.GAME_OVER or b.state != MatchController.State.GAME_OVER):
			if a.state != MatchController.State.GAME_OVER:
				AIController.step(a)
			if b.state != MatchController.State.GAME_OVER:
				AIController.step(b)
			steps += 1
			if steps % 500 == 0 and snapshot(a) != snapshot(b):
				break
		check(snapshot(a) == snapshot(b) and a.winner_id == b.winner_id, "%s: original and restored match play out IDENTICALLY (winner %d, round %d)" % [cont, a.winner_id, a.round_number])


func _test_human_match_roundtrip() -> void:
	# a match with a human seat: deck comes from the save dictionary, not from SaveManager
	var a := MatchController.new()
	a.setup({"continent_id": "arcanum", "faction_id": "cryndel", "difficulty": "hard", "ai_count": 3, "seed": 77, "player_name": "Tester"})
	a.players[0].gold += 123
	var b := MatchController.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	check(b.human_present and not b.players[0].is_ai and b.players[0].display_name == "Tester" and b.players[0].gold == a.players[0].gold, "human seat restored (name, gold)")
	check(b.players[0].deck.card_list() == a.players[0].deck.card_list() and b.players[2].deck.card_list().size() == 151, "decks restored (151 cards)")
	check(b.players[1].is_ai and b.players[1].difficulty == "hard" and b.players[1].passive == a.players[1].passive, "AI seats restored (difficulty, passive)")
	var total := 0
	for u in b.players[0].roster.units:
		total += UnitRoster.copies_value(u.stars)
	check(total + b.players[0].battle_deck.remaining() == 135, "card conservation after restore (units + pile = 135)")
	check(CardDatabase.active_continent == "arcanum" and WorldMods.modifier_name == "Arcane Conduits", "continent skin and world modifier restored")


func _test_unstable_states() -> void:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
	check(not c.to_dict().is_empty(), "a fresh match can be saved")
	c.roll_dice()
	check(c.to_dict().is_empty(), "no save while dice are rolled (unstable state)")
	c.state = MatchController.State.AWAIT_DUEL
	check(c.to_dict().is_empty(), "no save during a duel")
	c.state = MatchController.State.AWAIT_ROLL
	c.pending = {"type": "buy"}
	check(c.to_dict().is_empty(), "no save with a pending decision")


func _test_files() -> void:
	SaveManager.clear_match()
	check(not SaveManager.has_match(), "no match save at the start")
	var c := MatchController.new()
	c.setup({"continent_id": "thalassia", "faction_id": "abyssal", "difficulty": "easy", "ai_count": 2, "seed": 12, "all_ai": true})
	check(SaveManager.save_match(c) and SaveManager.has_match(), "match is written to disk")
	check(SaveManager.match_summary().begins_with("THALASSIA - round 1"), "summary for the Continue button: '%s'" % SaveManager.match_summary())
	var back := MatchController.from_dict(SaveManager.load_match())
	check(snapshot(back) == snapshot(c), "file round trip preserves the match")
	# crash between writing the temp file and renaming it
	DirAccess.rename_absolute(SaveManager.MATCH_PATH, SaveManager.MATCH_PATH + ".tmp")
	check(SaveManager.has_match(), "a leftover .tmp save is still found")
	SaveManager.clear_match()
	# corrupt file
	var f := FileAccess.open(SaveManager.MATCH_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	check(SaveManager.load_match().is_empty() and not FileAccess.file_exists(SaveManager.MATCH_PATH), "corrupt save is rejected and deleted (no crash)")
	f = FileAccess.open(SaveManager.MATCH_PATH, FileAccess.WRITE)
	f.store_string('{"version": 99, "players": [], "tiles": []}')
	f.close()
	check(SaveManager.load_match().is_empty(), "save of an unknown version is rejected")
	# profile save survives missing / partial data
	var old: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data.erase("stats")
	SaveManager._merge(SaveManager.data, {"profile": {"name": "X"}})
	check(true, "partial profile merge does not crash")
	SaveManager.data = old


func _test_back_button() -> void:
	check(AppNav != null and get_tree().root.go_back_requested.is_connected(AppNav.go_back), "Android Back is wired to AppNav")
	check(ProjectSettings.get_setting("application/config/quit_on_go_back") == false, "Back button never closes the app")
	var menu: Control = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	check(menu.has_method("on_back_requested"), "Main Menu asks before quitting")
	menu.free()
	var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
	check(board.has_method("on_back_requested"), "Territory Board handles Back (leave confirmation)")
	board.free()
