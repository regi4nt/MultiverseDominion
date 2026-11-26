extends Node
## Average AI shop level at the end of all-AI matches: Arena vs Chaos (and Journey). Usage: godot --headless --path . res://tests/level_sim.tscn -- 30


func _ready() -> void:
	var n := 30
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	for diff in ["easy", "normal", "hard"]:
		for cat in ["arena", "chaos"]:
			var lv_sum := 0.0
			var lv_max := 0
			var rounds_sum := 0
			var duels_total := 0
			for g in range(n):
				var m := MatchController.new()
				m.setup({"continent_id": ["aetherion", "drakmor", "eclipsia"][g % 3], "faction_id": "solvaris", "difficulty": diff, "ai_count": 1, "seed": 500 + g, "all_ai": true,
					"chaos": cat == "chaos", "round_limit": GameData.round_limit_for(cat, diff), "any_continent_enemies": true})
				var steps := 0
				while m.state != MatchController.State.GAME_OVER and steps < 60000:
					AIController.step(m)
					steps += 1
				var s := 0.0
				for p in m.players:
					s += float(p.level)
					lv_max = maxi(lv_max, p.level)
				lv_sum += s / float(m.players.size())
				rounds_sum += m.round_number
			print("%-7s %-6s  avg level %.2f  max %d  avg rounds %.1f  (limit %d)" % [diff, cat, lv_sum / n, lv_max, float(rounds_sum) / n, GameData.round_limit_for(cat, diff)])
	get_tree().quit(0)
