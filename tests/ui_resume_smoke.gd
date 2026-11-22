extends Node
## UI flow of Phase 7: autosave at the start of the human turn -> app "killed" -> Continue Match restores
## the same match; game over clears the save; scenes can be created/freed repeatedly without leaking.

func snap(c: MatchController) -> String:
	var parts: Array[String] = []
	for p in c.players:
		parts.append("%d/%d/%d/%d" % [p.gold, p.life, p.position, p.roster.units.size()])
	return "r%d c%d %s" % [c.round_number, c.current, " ".join(parts)]


func _ready() -> void:
	var fails := 0
	SaveManager.clear_match()
	GameSession.continent_id = "sylvaris"
	GameSession.faction_id = "floralis"
	GameSession.difficulty = "normal"
	GameSession.ai_count = 3
	GameSession.resume_match = false
	var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	var c: MatchController = board.ctrl
	check_eq(SaveManager.has_match(), true, "autosave written at the start of the human turn", fails)
	# play a few of our own turns so that the saved match is not the initial one
	board.tick.wait_time = 0.02
	var turns := 0
	var frames := 0
	while turns < 3 and frames < 3000 and c.state != MatchController.State.GAME_OVER:
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
		elif c.state == MatchController.State.AWAIT_DECISION and not c.decision_actor().is_ai:
			AIController.step(c)
		elif not c.current_player().is_ai and not board.board_view.is_busy():
			if c.state == MatchController.State.TURN_DONE:
				turns += 1
			AIController.step(c)
	await get_tree().process_frame
	# the OS pauses the app: the same hook SaveManager uses on Android
	SaveManager.app_paused.emit()
	var stable := c.state == MatchController.State.AWAIT_ROLL or c.state == MatchController.State.TURN_DONE
	var before := snap(c)
	var round_before := c.round_number
	board.queue_free()
	await get_tree().process_frame
	# "relaunch": main menu offers Continue, which resumes
	var menu: Control = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var cont_btn: Button = null
	for b in _buttons(menu):
		if b.text.begins_with("CONTINUE"):
			cont_btn = b
	check_eq(cont_btn != null and not cont_btn.disabled, true, "Main Menu shows an enabled Continue button: '%s'" % (cont_btn.text if cont_btn else "-"), fails)
	menu.queue_free()
	GameSession.resume_match = true
	var board2: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
	add_child(board2)
	await get_tree().process_frame
	var c2: MatchController = board2.ctrl
	print("   saved at round %d (stable=%s) -> resumed at round %d, continent %s" % [round_before, str(stable), c2.round_number, c2.continent["id"]])
	check_eq(c2.continent["id"], "sylvaris", "resumed on the same continent", fails)
	check_eq(c2.round_number >= 1 and c2.players.size() == 4, true, "resumed match has 4 players", fails)
	check_eq(board2.log_view.get_parsed_text().length() > 20, true, "log history shown after resuming", fails)
	check_eq(WorldMods.modifier_name, "Bountiful Harvest", "world modifier active after resuming", fails)
	if stable:
		check_eq(snap(c2) == before or c2.state == MatchController.State.AWAIT_ROLL, true, "state restored (%s)" % snap(c2), fails)
	# game over clears the save
	c2.state = MatchController.State.AWAIT_ROLL
	c2._end_game(0)
	await get_tree().process_frame
	check_eq(SaveManager.has_match(), false, "finished match leaves no save", fails)
	board2.queue_free()
	await get_tree().process_frame
	# churn: build and free the heavy scenes repeatedly
	var objs0 := 0
	for i in range(30):
		for path in ["res://scenes/territory_board/territory_board.tscn", "res://scenes/battle_board/battle_board.tscn", "res://scenes/card_collection/card_collection.tscn"]:
			var n: Control = load(path).instantiate()
			add_child(n)
			await get_tree().process_frame
			n.queue_free()
			await get_tree().process_frame
		if i == 4:
			objs0 = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	SaveManager.clear_match()
	var growth := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - objs0
	print("   scene churn: objects %+d after 25 more rounds of create/free, orphan nodes %d" % [growth, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	check_eq(growth < 200, true, "no object growth when scenes are created and freed repeatedly", fails)
	print("UI RESUME SMOKE: ", "PASS" if _fails_ref == 0 else "FAIL")
	get_tree().quit(_fails_ref)


var _fails_ref := 0


func check_eq(a: Variant, b: Variant, msg: String, _f: int) -> void:
	if a != b:
		_fails_ref += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button:
		out.append(n)
	for ch in n.get_children():
		out.append_array(_buttons(ch))
	return out
