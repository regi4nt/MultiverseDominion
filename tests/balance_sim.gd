extends Node
## Balance simulation (informational, always exits 0): many AI-only games per mode, win rate per seat / opening seat / faction.
## Run:  godot --headless --path . res://tests/balance_sim.tscn -- 200
## The number after "--" is the games per mode (default 100). Fair FFA = 25% per seat (2v2: 50% per team).

const MODES := [
	{"name": "Arena 100 tiles", "chaos": false, "team": false},
	{"name": "Chaos 40 tiles", "chaos": true, "team": false},
	{"name": "Arena 2v2", "chaos": false, "team": true},
	{"name": "Chaos 2v2", "chaos": true, "team": true},
]


func _ready() -> void:
	var n := 100
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and String(args[0]).is_valid_int():
		n = maxi(int(args[0]), 8)
	var factions: Array = []
	for c in GameData.continents:
		if c.get("playable", false):
			for f in c.get("factions", []):
				factions.append([String(c["id"]), String(f["id"])])
	for diff in ["normal"]:
		for m in MODES:
			_run_mode(m, diff, n, factions)
	print("TEST RESULT: PASS (informational)")
	get_tree().quit(0)


func _run_mode(m: Dictionary, diff: String, n: int, factions: Array) -> void:
	var seat_wins := [0, 0, 0, 0]
	var opener_wins := 0
	var team_wins := [0, 0]
	var limit_end := 0
	var unfinished := 0
	var rounds_sum := 0
	var fac_games := {}
	var fac_wins := {}
	var done := 0
	for s in range(1, n + 1):
		var pick: Array = factions[s % factions.size()]
		var c := MatchController.new()
		c.setup({"continent_id": pick[0], "faction_id": pick[1], "difficulty": diff, "ai_count": 3, "seed": s, "all_ai": true,
			"chaos": bool(m["chaos"]), "team_mode": bool(m["team"]), "random_first": true, "any_continent_enemies": true,
			"round_limit": GameData.round_limit_for("chaos" if bool(m["chaos"]) else "arena", diff)})
		var steps := 0
		while c.state != MatchController.State.GAME_OVER and steps < 60000:
			AIController.step(c)
			steps += 1
		if c.state != MatchController.State.GAME_OVER:
			unfinished += 1
			continue
		done += 1
		rounds_sum += c.round_number
		if c.round_number > c.round_limit:
			limit_end += 1
		for p in c.players:
			var fid := String(p.faction_id)
			fac_games[fid] = int(fac_games.get(fid, 0)) + 1
		var w: int = c.winner_id
		if bool(m["team"]):
			team_wins[c.winner_team if c.winner_team in [0, 1] else 0] += 1
		if w >= 0 and w < 4:
			seat_wins[w] += 1
			if w == c.first_seat:
				opener_wins += 1
			var wf := String(c.players[w].faction_id)
			fac_wins[wf] = int(fac_wins.get(wf, 0)) + 1
	var d := float(maxi(done, 1))
	print("=== %s (%s, %d games, %d unfinished) ===" % [m["name"], diff, done, unfinished])
	print("  avg rounds %.1f | ended by round limit %.0f%%" % [float(rounds_sum) / d, 100.0 * limit_end / d])
	print("  win rate by seat: %s" % ", ".join(seat_wins.map(func(x): return "%.0f%%" % (100.0 * x / d))))
	print("  opening seat won %.0f%% (fair 25%%)" % (100.0 * opener_wins / d))
	if bool(m["team"]):
		print("  team A (seats 0+2) %.0f%% | team B (seats 1+3) %.0f%%" % [100.0 * team_wins[0] / d, 100.0 * team_wins[1] / d])
	var rows: Array = []
	for fid in fac_games.keys():
		var g := int(fac_games[fid])
		if g >= 8:
			rows.append([100.0 * float(fac_wins.get(fid, 0)) / float(g), String(fid), g])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("  factions (win rate per seat taken, fair 25%%): top %s | bottom %s" % [_fmt(rows.slice(0, 3)), _fmt(rows.slice(maxi(rows.size() - 3, 0)))])
	for sv in seat_wins:
		if 100.0 * sv / d > 35.0 or 100.0 * sv / d < 15.0:
			if not bool(m["team"]):
				print("  WARNING: a seat is outside 15-35%%: rebalance %s" % m["name"])
				break


func _fmt(rows: Array) -> String:
	return ", ".join(rows.map(func(r): return "%s %.0f%% (%d)" % [r[1], r[0], r[2]]))
