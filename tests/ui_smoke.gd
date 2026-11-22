extends Node
## Loads the Territory Board scene and plays the human side automatically for a while.

func _ready() -> void:
	var scene: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var c: MatchController = scene.ctrl
	var frames := 0
	while c.state != MatchController.State.GAME_OVER and frames < 4000:
		await get_tree().process_frame
		frames += 1
		if scene._duel_node != null:
			var b: Control = scene._duel_node
			b._on_auto()
			b._on_start_battle()
			b.timer.stop()
			var n := 0
			while not b.engine.finished and n < 1000:
				b._on_tick()
				n += 1
			b._finish_duel()
			continue
		if c.state == MatchController.State.AWAIT_DECISION:
			# The scene timer answers for AI actors; the test answers for the human actor
			# (also when an AI is the current player and the human OWNS the land).
			if not c.decision_actor().is_ai:
				AIController.step(c)
		elif not c.current_player().is_ai and not scene.board_view.is_busy():
			match c.state:
				MatchController.State.AWAIT_ROLL: c.roll_dice()
				MatchController.State.ROLLED: c.confirm_move()
				MatchController.State.AWAIT_DECISION: AIController.step(c)
				MatchController.State.TURN_DONE: c.end_turn()
		scene.tick.wait_time = 0.02
	print("UI smoke: state=%d round=%d frames=%d" % [c.state, c.round_number, frames])
	get_tree().quit()
