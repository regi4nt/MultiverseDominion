extends Node
## Phase 7: CPU cost and memory stability (leak check). Numbers are for THIS machine; a low-end phone is
## typically 5-10x slower, so the thresholds leave a wide margin.
## Run: godot --headless --path . res://tests/perf_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	_cpu()
	_leaks()
	print("PERF TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _cpu() -> void:
	# 1. battle ticks with a full army on both sides
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var deck := Deck.create_default()
	var worst_tick := 0.0
	var total_ticks := 0
	var t_all := Time.get_ticks_usec()
	for s in range(30):
		var pa := BattleAI.build_enemy("hard", 7, rng, deck)
		var pb := BattleAI.build_enemy("hard", 7, rng, deck)
		for u in pa.roster.units:
			if u.cell.x >= 0:
				u.cell = Vector2i(u.cell.x, 7 - u.cell.y)
		var e := BattleEngine.new()
		e.setup({"seed": s, "ai_supports": [true, true], "sides": [pa.to_side_cfg("champion_solvaris", BattleAI.pick_hand(deck, rng, 3)), pb.to_side_cfg("champion_nocthyr", BattleAI.pick_hand(deck, rng, 3))]})
		while not e.finished:
			var t0 := Time.get_ticks_usec()
			e.step()
			worst_tick = maxf(worst_tick, (Time.get_ticks_usec() - t0) / 1000.0)
			total_ticks += 1
	var avg_tick := (Time.get_ticks_usec() - t_all) / 1000.0 / maxi(total_ticks, 1)
	print("   battle: %d ticks, avg %.3f ms incl. army building, worst single tick %.2f ms" % [total_ticks, avg_tick, worst_tick])
	check(worst_tick < 15.0, "worst battle tick %.2f ms (< 15 ms desktop; the timer ticks every 250 ms)" % worst_tick)
	# 2. an AI-vs-AI duel (army prep + battle) and a whole AI game
	var m := MatchController.new()
	m.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "hard", "ai_count": 3, "seed": 9, "all_ai": true})
	var t1 := Time.get_ticks_usec()
	var steps := 0
	var worst_step := 0.0
	while m.state != MatchController.State.GAME_OVER and steps < 40000:
		var ts := Time.get_ticks_usec()
		AIController.step(m)
		worst_step = maxf(worst_step, (Time.get_ticks_usec() - ts) / 1000.0)
		steps += 1
	print("   whole AI game: %d steps in %.0f ms, worst single step %.1f ms (an AI-vs-AI duel is one step)" % [steps, (Time.get_ticks_usec() - t1) / 1000.0, worst_step])
	check(worst_step < 80.0, "worst AI step %.1f ms (< 80 ms desktop; instant duels never freeze the UI long)" % worst_step)


func _leaks() -> void:
	# a long series of matches must not grow memory or leave objects behind
	var run := func(n: int) -> void:
		for g in range(n):
			var m := MatchController.new()
			m.setup({"continent_id": ["aetherion", "drakmor", "eclipsia"][g % 3], "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 100 + g, "all_ai": true})
			var steps := 0
			while m.state != MatchController.State.GAME_OVER and steps < 40000:
				AIController.step(m)
				steps += 1
	run.call(6)  # warm-up (caches, static data)
	var mem0 := OS.get_static_memory_usage()
	var obj0 := Performance.get_monitor(Performance.OBJECT_COUNT)
	run.call(40)
	var mem1 := OS.get_static_memory_usage()
	var obj1 := Performance.get_monitor(Performance.OBJECT_COUNT)
	print("   after 40 more games: memory %+.2f MB, objects %+d, orphan nodes %d" % [(mem1 - mem0) / 1048576.0, int(obj1 - obj0), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
	check((mem1 - mem0) / 1048576.0 < 8.0, "no memory growth over 40 full games (%+.2f MB)" % ((mem1 - mem0) / 1048576.0))
	check(int(obj1 - obj0) < 500, "no object leak over 40 full games (%+d objects)" % int(obj1 - obj0))
	print("   current memory in use: %.1f MB" % (mem1 / 1048576.0))
