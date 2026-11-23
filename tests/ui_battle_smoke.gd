extends Node
## Drives the Battle scene like a player: buy, deploy by tapping, auto deploy, fight, support, result.

func _ready() -> void:
	var fails := 0
	var scene: Control = load("res://scenes/battle_board/battle_board.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	for i in range(5):
		scene._on_buy(i)
	await get_tree().process_frame
	var bench: Array = scene.prep.bench_units()
	print("bought units: ", bench.size(), " gold left: ", scene.prep.gold)
	if bench.is_empty():
		fails += 1
	scene._on_select(bench[0])
	scene._on_cell(Vector2i(3, 5))  # tap a cell like a player
	if scene.prep.deployed_units().size() != 1:
		fails += 1
	scene._on_cell(Vector2i(3, 1))  # enemy half: must be refused
	print("refusal message: ", scene.message_label.text)
	if scene.prep.deployed_units().size() != 1 or scene.message_label.text == "":
		fails += 1
	scene._on_auto()
	print("deployed after auto: ", scene.prep.deployed_units().size(), " capacity ", scene.prep.used_capacity(), "/", scene.prep.capacity())
	if scene.prep.used_capacity() > scene.prep.capacity():
		fails += 1
	scene._on_start_battle()
	scene.timer.stop()
	for id in scene.hand:
		if scene.engine.is_support_implemented(id):
			scene._on_support(id)
			break
	var frames := 0
	while not scene.engine.finished and frames < 1000:
		scene._on_tick()
		frames += 1
		if frames % 20 == 0:
			await get_tree().process_frame
	await get_tree().process_frame
	var waited := 0.0  # a checkmate delays the result screen by ~1.4 s so the CHECKMATE banner can be seen
	while not scene._result_shown and waited < 5.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	print("battle finished=", scene.engine.finished, " winner=", scene.engine.winner, " ticks=", scene.engine.tick, " result shown=", scene._result_shown)
	if not scene.engine.finished or not scene._result_shown:
		fails += 1
	print("UI BATTLE SMOKE: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(fails)
