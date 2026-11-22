extends Node
## Phase 5 test: Territory Encounter, Duel rules, Life, Conquest/Reward, full AI games.
## Run: godot --headless --path . res://tests/duel_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


## Player 1 owns a territory; player 0 (current) has just landed on it.
func encounter() -> MatchController:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 21, "all_ai": true})
	var tile: BoardTile = null
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY:
			tile = t
			break
	tile.owner_id = 1
	c.current = 0
	c.players[0].position = tile.index
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	return c


func _ready() -> void:
	_test_players_have_armies()
	_test_tax()
	_test_refuse()
	_test_duel_outcomes()
	_test_defender_life_rule()
	_test_elimination()
	_test_full_games()
	print("DUEL TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _test_players_have_armies() -> void:
	var c := MatchController.new()
	c.setup({"continent_id": "aetherion", "faction_id": "elarion", "difficulty": "normal", "ai_count": 3, "seed": 3, "all_ai": true})
	var ok := true
	for p in c.players:
		ok = ok and p.roster.units.size() >= 1 and p.deck.card_list().size() == 151
	check(ok, "every player starts with a persistent army and a 151-card deck")


func _test_tax() -> void:
	var c := encounter()
	check(c.state == MatchController.State.AWAIT_DECISION and String(c.pending["type"]) == "encounter", "landing on a rival territory opens an Encounter")
	check(c.decision_actor().id == 1, "the OWNER (not the visitor) answers the Encounter")
	var opts := c.get_decision_options()
	check(opts.size() == 2 and opts[0]["id"] == "tax" and opts[1]["id"] == "duel", "owner can choose Tax or Duel")
	var g0 := c.players[0].gold
	var g1 := c.players[1].gold
	var rent := int(c.pending["rent"])
	c.decide("tax")
	check(c.players[0].gold == g0 - rent and c.players[1].gold == g1 + rent, "Tax: rent moves from visitor to owner (%d G)" % rent)
	check(c.state == MatchController.State.TURN_DONE, "turn can end after Tax")


func _test_refuse() -> void:
	var c := encounter()
	var g0 := c.players[0].gold
	var rent := int(c.pending["rent"])
	c.decide("duel")
	check(String(c.pending["type"]) == "duel_response" and c.decision_actor().id == 0, "owner picks Duel -> visitor must answer")
	c.decide("refuse")
	var penalty := int(GameData.b("refuse_duel_penalty"))
	check(c.players[0].gold == g0 - rent - penalty, "refusing costs rent + configurable penalty (%d + %d)" % [rent, penalty])
	check(c.state == MatchController.State.TURN_DONE and c.stats["refused"] == 1, "refusal ends the encounter")


func _test_duel_outcomes() -> void:
	# accepted duel -> AWAIT_DUEL
	var c := encounter()
	c.decide("duel")
	c.decide("accept")
	check(c.state == MatchController.State.AWAIT_DUEL, "accepting starts the duel")
	# defender wins -> attacker loses 1 Life, land stays
	var life := c.players[0].life
	c.finish_duel({"winner": 1})
	check(c.players[0].life == life - 1, "owner wins: attacker loses 1 Life")
	check(c.tiles[c.players[0].position].owner_id == 1, "owner wins: territory stays with the owner")
	check(c.state == MatchController.State.TURN_DONE, "turn continues after the duel")
	# draw -> defender wins
	var c2 := encounter()
	c2.decide("duel")
	c2.decide("accept")
	var l2 := c2.players[0].life
	c2.finish_duel({"winner": -1})
	check(c2.players[0].life == l2 - 1 and c2.tiles[c2.players[0].position].owner_id == 1, "draw goes to the defender")
	# attacker wins -> conquest
	var c3 := encounter()
	c3.decide("duel")
	c3.decide("accept")
	var l3 := c3.players[0].life
	var d_life := c3.players[1].life
	GameData.balance["defender_loses_life"] = false
	c3.finish_duel({"winner": 0})
	check(String(c3.pending["type"]) == "conquest" and c3.decision_actor().id == 0, "attacker wins: chooses Conquest or Victory Reward")
	check(c3.players[0].life == l3 and c3.players[1].life == d_life, "defender_loses_life=false: the defender keeps its Life")
	c3.decide("conquest")
	check(c3.tiles[c3.players[0].position].owner_id == 0, "Conquest transfers ownership")
	check(c3.state == MatchController.State.TURN_DONE, "turn continues after Conquest")
	# attacker wins -> reward
	var c4 := encounter()
	c4.decide("duel")
	c4.decide("accept")
	c4.finish_duel({"winner": 0})
	var g := c4.players[0].gold
	var reward := int(c4.pending["reward"])
	c4.decide("reward")
	check(c4.players[0].gold == g + reward and c4.tiles[c4.players[0].position].owner_id == 1, "Victory Reward gives gold, owner keeps the land (+%d G)" % reward)
	# Fortune's Favor bonus gold goes to the winner
	var c5 := encounter()
	c5.decide("duel")
	c5.decide("accept")
	var g5 := c5.players[1].gold
	c5.finish_duel({"winner": 1, "bonus_gold": 50})
	check(c5.players[1].gold == g5 + 50, "bonus gold (Fortune's Favor) is paid to the winner")


func _test_defender_life_rule() -> void:
	GameData.balance["defender_loses_life"] = true
	var c := encounter()
	c.decide("duel")
	c.decide("accept")
	var d_life := c.players[1].life
	c.finish_duel({"winner": 0})
	check(c.players[1].life == d_life - 1, "defender_loses_life=true (default): the losing owner loses 1 Life")
	check(String(c.pending["type"]) == "conquest", "...and the attacker still chooses Conquest or Reward")
	GameData.balance["defender_loses_life"] = true


func _test_elimination() -> void:
	var c := encounter()
	c.players[0].life = 1
	c.decide("duel")
	c.decide("accept")
	c.finish_duel({"winner": 1})
	check(not c.players[0].alive, "losing the last Life eliminates the player")
	check(c.state == MatchController.State.TURN_DONE or c.state == MatchController.State.GAME_OVER, "game state stays consistent after elimination")


func _test_full_games() -> void:
	var finished_all := true
	var totals := {"duels": 0, "tax": 0, "refused": 0, "conquests": 0, "rewards": 0, "attacker_wins": 0, "defender_wins": 0}
	var by_elim := 0
	var rounds_sum := 0
	var n := 0
	for diff in ["easy", "normal", "hard"]:
		for s in range(1, 9):
			var c := MatchController.new()
			c.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": diff, "ai_count": 3, "seed": s, "all_ai": true})
			var steps := 0
			while c.state != MatchController.State.GAME_OVER and steps < 40000:
				AIController.step(c)
				steps += 1
			if c.state != MatchController.State.GAME_OVER:
				finished_all = false
				push_error("stuck: %s seed %d state %d pending %s" % [diff, s, c.state, str(c.pending)])
			for k in totals:
				totals[k] += int(c.stats[k])
			if c.alive_players().size() == 1:
				by_elim += 1
			rounds_sum += c.round_number
			n += 1
	check(finished_all, "all %d AI games finish with the duel system active" % n)
	print("   totals over %d games: %s" % [n, str(totals)])
	print("   games ended by elimination: %d / %d, avg rounds %.1f" % [by_elim, n, float(rounds_sum) / n])
	check(int(totals["duels"]) > 0 and int(totals["tax"]) > 0, "both Tax and Duel are chosen by AI owners")
	var resolved := int(totals["conquests"]) + int(totals["rewards"])
	check(resolved <= int(totals["attacker_wins"]) and int(totals["attacker_wins"]) - resolved <= n, "attacker wins end in Conquest/Reward (unless the last defender's Life ended the game)")
	check(int(totals["attacker_wins"]) + int(totals["defender_wins"]) == int(totals["duels"]), "duel statistics are consistent")
