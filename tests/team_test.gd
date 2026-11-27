extends Node
## 2vs2 team mode: teams, allied land, tribute, win conditions, save round trip, full AI games.
## Run: godot --headless --path . res://tests/team_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func new_match(seed_v: int = 11) -> MatchController:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "team_mode": true, "seed": seed_v, "all_ai": true})
	return c


func first_territory(c: MatchController) -> BoardTile:
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY:
			return t
	return null


func _ready() -> void:
	_test_teams()
	_test_allied_land()
	_test_tribute()
	_test_elimination()
	_test_round_limit()
	_test_save()
	_test_games()
	print("TEAM TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_teams() -> void:
	var c := new_match()
	check(c.team_mode and c.players.size() == 4, "2vs2 seats four rulers")
	check(c.players[0].team == 0 and c.players[1].team == 1 and c.players[2].team == 0 and c.players[3].team == 1, "turn order alternates Team A, B, A, B")
	check(c.is_ally(0, 2) and c.is_ally(1, 3), "seats 0+2 and 1+3 are allies")
	check(not c.is_ally(0, 1) and not c.is_ally(0, 3) and not c.is_ally(0, 0) and not c.is_ally(0, -1), "rivals, the same seat and no seat are not allies")
	check(c.players[2].display_name.contains("(Ally)") and c.players[1].display_name.contains("(AI)"), "seat 2 is named as the ally, the others as AI")
	var ffa := MatchController.new()
	ffa.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 11, "all_ai": true})
	check(not ffa.team_mode and not ffa.is_ally(0, 2) and ffa.players[0].team == -1, "a free-for-all has no teams and no allies")


func _test_allied_land() -> void:
	var c := new_match()
	var t := first_territory(c)
	t.owner_id = 2
	c.current = 0
	c.players[0].position = t.index
	var g := c.players[0].gold
	var g2 := c.players[2].gold
	c._resolve_landing(c.players[0])
	check(c.pending.is_empty() and c.players[0].gold == g and c.players[2].gold == g2, "landing on an ally's land: no encounter, no rent")
	t.owner_id = 1
	c.pending = {}
	c._resolve_landing(c.players[0])
	check(String(c.pending.get("type", "")) == "encounter" and int(c.pending["actor"]) == 1, "landing on an enemy's land still starts the Territory Encounter")


func _test_tribute() -> void:
	var c := new_match()
	var g: Array = []
	for p in c.players:
		g.append(p.gold)
	c._collect_from_rivals(c.players[0], 25, "tribute")
	check(c.players[2].gold == g[2], "tribute never charges the ally")
	check(c.players[1].gold == g[1] - 25 and c.players[3].gold == g[3] - 25 and c.players[0].gold == g[0] + 50, "tribute is paid by both rivals")


func _test_elimination() -> void:
	var c := new_match()
	c._eliminate(c.players[2])
	check(c.state != MatchController.State.GAME_OVER, "losing one ally does not end the match")
	c._eliminate(c.players[1])
	check(c.state != MatchController.State.GAME_OVER, "the match goes on while both teams have a ruler")
	c._eliminate(c.players[3])
	check(c.state == MatchController.State.GAME_OVER and c.winner_team == 0 and c.players[c.winner_id].team == 0, "eliminating a whole team ends the match; the other team wins")
	var c2 := new_match()
	c2._eliminate(c2.players[0])
	c2._eliminate(c2.players[2])
	check(c2.state == MatchController.State.GAME_OVER and c2.winner_team == 1, "Team B wins when Team A is wiped out")


func _test_round_limit() -> void:
	var c := new_match()
	c.round_limit = 1
	c.players[0].gold = 4000
	c.players[2].gold = 4000
	c._end_of_round()
	check(c.state == MatchController.State.GAME_OVER and c.winner_team == 0, "round limit: the richer team (A) wins")
	var c2 := new_match()
	c2.round_limit = 1
	c2.players[1].gold = 4000
	c2.players[3].gold = 4000
	c2._end_of_round()
	check(c2.state == MatchController.State.GAME_OVER and c2.winner_team == 1, "round limit: the richer team (B) wins")
	check(c2.team_networth(1) > c2.team_networth(0), "team net worth adds up both members")


func _test_save() -> void:
	var c := new_match(17)
	var d := c.to_dict()
	check(not d.is_empty() and bool(d["team_mode"]), "a 2vs2 match can be saved")
	var back := MatchController.from_dict(d)
	check(back.team_mode and back.players.size() == 4 and back.players[3].team == 1 and back.players[2].team == 0, "the teams survive a save / resume")
	check(back.is_ally(0, 2) and not back.is_ally(0, 1), "allies are still allies after resuming")
	d.erase("team_mode")
	var old := MatchController.from_dict(d)
	check(not old.team_mode, "a save without team data loads as a free-for-all")


func _test_games() -> void:
	var finished := true
	var winners := {}
	for s in range(1, 7):
		var m := MatchController.new()
		m.setup({"continent_id": ["aetherion", "sylvaris", "eclipsia"][s % 3], "faction_id": "solvaris", "difficulty": ["easy", "normal", "hard"][s % 3], "ai_count": 3, "team_mode": true, "seed": 60 + s, "all_ai": true})
		var steps := 0
		while m.state != MatchController.State.GAME_OVER and steps < 60000:
			AIController.step(m)
			steps += 1
		finished = finished and m.state == MatchController.State.GAME_OVER and (m.winner_team == 0 or m.winner_team == 1)
		winners[m.winner_team] = true
	check(finished, "full 2vs2 AI games finish with a winning team")
