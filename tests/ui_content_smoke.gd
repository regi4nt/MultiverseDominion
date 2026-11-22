extends Node
## Opens Match Setup, Card Collection and the Territory Board for every continent and plays turns.

func _ready() -> void:
	var fails := 0
	for c in GameData.continents:  # tests need every continent open (the game has no unlock-all feature)
		SaveManager.unlock_continent(c["id"])
	for c in GameData.continents:
		GameSession.continent_id = c["id"]
		GameSession.faction_id = c["factions"][1]["id"]
		GameSession.difficulty = "normal"
		GameSession.ai_count = 3
		var setup: Control = load("res://scenes/match_setup/match_setup.tscn").instantiate()
		add_child(setup)
		await get_tree().process_frame
		var champ_text: String = setup._champion_text.text
		if champ_text.find(c["factions"][1]["name"]) < 0 and champ_text.find(GameData.get_champion(c["factions"][1]["champion"])["name"]) < 0:
			fails += 1
			push_error("setup shows no champion for " + c["id"])
		setup.queue_free()
		var coll: Control = load("res://scenes/card_collection/card_collection.tscn").instantiate()
		add_child(coll)
		await get_tree().process_frame
		var first_card: CardView = coll._grid.get_child(0)
		if not String(first_card.card["name"]).begins_with(String(c["factions"][0]["name"])) and c["id"] != "aetherion":
			fails += 1
			push_error("collection not reskinned for " + c["id"])
		coll.queue_free()
		var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
		add_child(board)
		await get_tree().process_frame
		board.tick.wait_time = 0.02
		var m: MatchController = board.ctrl
		var frames := 0
		while frames < 700 and m.state != MatchController.State.GAME_OVER:
			await get_tree().process_frame
			frames += 1
			if board._duel_node != null:
				var b: Control = board._duel_node
				b._on_auto()
				b._on_start_battle()
				b.timer.stop()
				var n := 0
				while not b.engine.finished and n < 1000:
					b._on_tick()
					n += 1
				b._finish_duel()
			elif m.state == MatchController.State.AWAIT_DECISION and not m.decision_actor().is_ai:
				AIController.step(m)
			elif not m.current_player().is_ai and m.state != MatchController.State.AWAIT_DECISION and not board.board_view.is_busy():
				AIController.step(m)
		print("%-10s modifier=%-18s round=%d duels=%d tile_info='%s'" % [c["id"], WorldMods.modifier_name, m.round_number, m.stats["duels"], board.tile_info.text.substr(0, 28).replace("\n", " ")])
		if m.round_number < 2:
			fails += 1
		board.queue_free()
		await get_tree().process_frame
	print("UI CONTENT SMOKE: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
