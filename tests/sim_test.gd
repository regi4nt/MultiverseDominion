extends Node
## Headless regression test: board layout + full AI-only games.
## Run:  godot --headless --path . res://tests/sim_test.tscn


func _ready() -> void:
	var failures := 0
	var cont := GameData.get_continent("aetherion")
	var tiles := BoardBuilder.build(cont)
	var counts := BoardBuilder.count_types(tiles)
	print("Tile counts: ", counts)
	var expect := {"Corner": 4, "Territory": 40, "Portal": 4, "Bank": 8, "Casino": 4, "Shop": 8, "Event": 12, "Auction": 4, "Tax": 8, "Special": 8}
	if tiles.size() != 100 or counts != expect:
		push_error("FAIL: board layout")
		failures += 1
	PortalSystem.randomize_portals(tiles, RandomNumberGenerator.new())
	if PortalSystem.active_indices(tiles).size() != 4:
		push_error("FAIL: active portals")
		failures += 1

	for diff in ["easy", "normal", "hard"]:
		for s in range(1, 21):
			var c := MatchController.new()
			c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": diff, "ai_count": 3, "seed": s, "all_ai": true})
			var steps := 0
			while c.state != MatchController.State.GAME_OVER and steps < 30000:
				AIController.step(c)
				steps += 1
			if c.state != MatchController.State.GAME_OVER:
				push_error("FAIL: %s seed %d did not finish" % [diff, s])
				failures += 1
			elif s <= 3:
				print("%s seed %d: winner %s after %d rounds, %d steps" % [diff, s, c.players[c.winner_id].display_name, c.round_number, steps])
	print("TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
