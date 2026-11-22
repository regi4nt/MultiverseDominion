extends Node
## Balance harness. Plays N all-AI games and prints metrics.
## Usage: godot --headless --path . res://tools/balance_report.tscn -- games=30 rent_rate=0.35 tax_flat=120
## Any numeric/bool key of data/balance.json can be overridden for the run (not saved).

func _ready() -> void:
	var games := 24
	var mode := "mixed"
	var seed_base := 1000
	var continent := "aetherion"
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=")
		if kv.size() != 2:
			continue
		if kv[0] == "games":
			games = int(kv[1])
		elif kv[0] == "seed_base":
			seed_base = int(kv[1])
		elif kv[0] == "continent":
			continent = kv[1]
		elif kv[0] == "mode":
			mode = kv[1]
		elif "." in kv[0]:  # nested key, e.g. ai_battle_budget_ratio.normal=0.15
			var parts := kv[0].split(".")
			GameData.balance[parts[0]][parts[1]] = float(kv[1])
		elif kv[1] == "true" or kv[1] == "false":
			GameData.balance[kv[0]] = (kv[1] == "true")
		else:
			GameData.balance[kv[0]] = float(kv[1]) if "." in kv[1] else int(kv[1])
	var t0 := Time.get_ticks_msec()
	var elim := 0
	var rounds := 0
	var totals := {"duels": 0, "tax": 0, "duels_offered": 0, "refused": 0, "attacker_wins": 0, "defender_wins": 0, "conquests": 0, "rewards": 0, "bankrupt": 0, "heals": 0}
	var seat_wins := [0, 0, 0, 0]
	var fac_wins := {}
	var fac_games := {}
	var elim_round_sum := 0
	var stuck := 0
	var gold_sum := 0
	var lands_sum := 0
	var life_sum := 0
	var alive_n := 0
	for g in range(games):
		var c := MatchController.new()
		var diffs: Array = []
		if mode == "skill":  # seat 0 hard vs three easy AIs
			diffs = ["hard", "easy", "easy", "easy"]
		elif mode == "skill_rev":  # seat 0 easy vs three hard AIs
			diffs = ["easy", "hard", "hard", "hard"]
		c.setup({"continent_id": continent, "faction_id": GameData.get_continent(continent)["factions"][g % 4]["id"], "difficulty": "normal",
			"difficulties": diffs, "ai_count": 3, "seed": seed_base + g, "all_ai": true})
		var steps := 0
		while c.state != MatchController.State.GAME_OVER and steps < 60000:
			AIController.step(c)
			steps += 1
		if c.state != MatchController.State.GAME_OVER:
			stuck += 1
			continue
		for k in totals:
			totals[k] += int(c.stats[k])
		if c.alive_players().size() == 1:
			elim += 1
			elim_round_sum += c.round_number
		rounds += c.round_number
		for p in c.players:
			gold_sum += p.gold
			lands_sum += c.count_owned(p.id)
			life_sum += maxi(p.life, 0)
			alive_n += 1
		if c.winner_id >= 0:
			seat_wins[c.winner_id] += 1
		for p in c.players:
			fac_games[p.faction_id] = int(fac_games.get(p.faction_id, 0)) + 1
		if c.winner_id >= 0:
			var wf: String = c.players[c.winner_id].faction_id
			fac_wins[wf] = int(fac_wins.get(wf, 0)) + 1
	var n := games - stuck
	var enc := int(totals["tax"]) + int(totals["duels_offered"])
	print("BALANCE games=%d stuck=%d secs=%.1f" % [games, stuck, (Time.get_ticks_msec() - t0) / 1000.0])
	print("  elimination endings: %d/%d (%.0f%%), avg rounds %.1f, avg round of elimination-end %.1f" % [elim, n, 100.0 * elim / maxi(n, 1), float(rounds) / maxi(n, 1), float(elim_round_sum) / maxi(elim, 1)])
	print("  encounters/game %.1f | owner picks duel %.0f%% | visitor refuses %.0f%% | duels/game %.1f | attacker wins %.0f%% | conquest %d reward %d" % [
		float(enc) / maxi(n, 1), 100.0 * totals["duels_offered"] / maxi(enc, 1), 100.0 * totals["refused"] / maxi(totals["duels_offered"], 1),
		float(totals["duels"]) / maxi(n, 1), 100.0 * totals["attacker_wins"] / maxi(totals["duels"], 1), totals["conquests"], totals["rewards"]])
	print("  per player at end: gold %d, lands %.1f, life %.2f | bankruptcies/game %.2f, heals/game %.2f" % [
		gold_sum / maxi(alive_n, 1), float(lands_sum) / maxi(alive_n, 1), float(life_sum) / maxi(alive_n, 1),
		float(totals["bankrupt"]) / maxi(n, 1), float(totals["heals"]) / maxi(n, 1)])
	print("  wins by seat (turn order): ", seat_wins)
	var fw := []
	for f in fac_games:
		fw.append("%s %.0f%%" % [f, 100.0 * int(fac_wins.get(f, 0)) / int(fac_games[f])])
	print("  win rate by faction (fair = 25%): ", ", ".join(fw))
	get_tree().quit()
