extends Node
## UX behaviours: empty-formation confirmation, leave confirmation, board speed button, camera pan on a new turn.

func _ready() -> void:
	var fails := 0
	# --- Battle Practice
	var b: Control = load("res://scenes/battle_board/battle_board.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	b._on_start_pressed()  # nothing deployed -> must ask, must NOT start
	if b.phase != "prep" or not b._start_dialog.visible:
		fails += 1
		push_error("empty formation should ask for confirmation")
	b._start_dialog.hide()
	for i in range(5):
		b._on_buy(i)
	b._on_auto()
	b._on_start_pressed()  # something deployed -> starts directly
	if b.phase != "battle":
		fails += 1
		push_error("a deployed formation should start directly")
	if not b.has_method("on_back_requested"):
		fails += 1
	b.on_back_requested()
	if not b._leave_dialog.visible:
		fails += 1
		push_error("Back in practice should ask before leaving")
	b.queue_free()
	await get_tree().process_frame

	# --- Territory Board
	GameSession.mode = "ffa_ai"
	GameSession.resume_match = false
	var t: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
	add_child(t)
	await get_tree().process_frame
	BoardView.speed_mult = 1.0
	t.board_view._cycle_speed()
	if BoardView.speed_mult != 2.0 or absf(t.tick.wait_time - 0.4) > 0.001:
		fails += 1
		push_error("speed button should halve the tick (%s)" % t.tick.wait_time)
	t.board_view._cycle_speed()
	t.board_view._cycle_speed()  # 4x -> back to 1x
	if BoardView.speed_mult != 1.0 or absf(t.tick.wait_time - 0.8) > 0.001:
		fails += 1
		push_error("speed should cycle back to 1x")
	if t._pan_key == "":
		fails += 1
		push_error("the camera should pan at the start of a turn")
	t.queue_free()
	await get_tree().process_frame
	print("UI UX SMOKE: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
