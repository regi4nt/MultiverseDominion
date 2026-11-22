extends Node
## Tutorial through the real scenes (run under a virtual display to also capture screenshots):
## xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/ui_tutorial_smoke.tscn -- shots

func shot(name: String) -> void:
	if "shots" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("/tmp/shots")
		get_viewport().get_texture().get_image().save_png("/tmp/shots/%s.png" % name)


func _ready() -> void:
	OS.low_processor_usage_mode = false
	var fails := 0
	SaveManager.data["profile"]["tutorial_done"] = false
	SaveManager.clear_match()
	GameSession.start_tutorial()
	var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
	add_child(board)
	await get_tree().process_frame
	board.tick.stop()
	var c: MatchController = board.ctrl
	if not c.tutorial or not board._hint_panel.visible or not board._hint_label.text.begins_with("Welcome"):
		fails += 1
		push_error("welcome hint not shown")
	print("hint: ", board._hint_label.text.substr(0, 60), "...")
	await shot("tutorial_board")
	# force the first encounter -> duel offer -> acceptance -> overlay with tips
	c.tiles[2].owner_id = 1
	c.current = 0
	c.players[0].position = 2
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	c.state_changed.emit()
	await get_tree().process_frame
	AIController.step(c)  # the AI owner's forced duel offer
	await get_tree().process_frame
	if not board._hint_label.text.begins_with("You were challenged"):
		fails += 1
		push_error("duel_response hint missing: " + board._hint_label.text)
	c.decide("accept")
	await get_tree().process_frame
	var b: Control = board._duel_node
	if b == null or b._tip_label == null or not b._tip_label.text.begins_with("TUTORIAL"):
		fails += 1
		push_error("battle tip missing")
	else:
		print("battle tip: ", b._tip_label.text.substr(0, 70), "...")
		await shot("tutorial_battle_prep")
		b._on_auto()
		b._on_start_battle()
		b.timer.stop()
		if not b._tip_label.text.contains("Last Stand"):
			fails += 1
		var n := 0
		while not b.engine.finished and n < 1000:
			b._on_tick()
			n += 1
		b._finish_duel()
		await get_tree().process_frame
	# finishing the tutorial records completion but no ranked result
	var stats_before: int = SaveManager.data["stats"]["matches_played"]
	c._end_game(0)
	await get_tree().process_frame
	if not SaveManager.data["profile"]["tutorial_done"] or SaveManager.data["stats"]["matches_played"] != stats_before:
		fails += 1
		push_error("tutorial completion bookkeeping wrong")
	await shot("tutorial_end")
	board.queue_free()
	GameSession.mode = "ffa_ai"
	SaveManager.clear_match()
	print("UI TUTORIAL SMOKE: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
