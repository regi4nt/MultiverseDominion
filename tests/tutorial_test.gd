extends Node
## Tutorial test. Run: godot --headless --path . res://tests/tutorial_test.tscn

var failures := 0
var seen_hints: Array[String] = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func new_tutorial() -> MatchController:
	GameSession.start_tutorial()
	var c := MatchController.new()
	c.setup(GameSession.to_match_config())
	return c


func _ready() -> void:
	var c := new_tutorial()
	check(c.tutorial and c.players.size() == 2 and c.round_limit == 10 and c.players[1].difficulty == "easy", "tutorial: 1v1 vs an easy AI, 10 rounds")
	var owned := 0
	for i in [2, 4, 6, 8]:
		if c.tiles[i].owner_id == 1:
			owned += 1
	check(owned == 4, "scripted start: the AI already owns the lands in front of the player")
	GameSession.mode = "ffa_ai"

	var g := TutorialGuide.new(c)
	g.hint.connect(func(id: String, _t: String): seen_hints.append(id))
	c.state_changed.emit()
	check(seen_hints == ["welcome"], "first state: welcome (with the roll instruction)")
	c.state_changed.emit()
	check(seen_hints == ["welcome", "roll"], "second time at the roll: short 'roll' hint")
	c.state_changed.emit()
	check(seen_hints.size() == 2, "a hint is never repeated")
	c.roll_dice()
	check(seen_hints.back() == "rolled", "after rolling: explains Move / Reroll / doubles")

	# every contextual hint, by crafting the situation
	var h := func(id: String) -> bool: return seen_hints.has(id)
	c.state = MatchController.State.AWAIT_DECISION
	c.pending = {"type": "buy", "tile": 1, "price": 100, "actor": 0}
	c.state_changed.emit()
	check(h.call("buy"), "unowned land: explains buying, rent and Regional Dominion")
	c.pending = {"type": "encounter", "actor": 1, "tile": 2, "rent": 30, "attacker": 0}
	c.state_changed.emit()
	check(h.call("encounter_wait"), "visitor sees that the OWNER decides")
	c.pending = {"type": "duel_response", "actor": 0, "tile": 2, "rent": 30, "owner": 1}
	c.state_changed.emit()
	check(h.call("duel_response"), "challenged to a duel: explains accept / refuse")
	c.pending = {"type": "conquest", "actor": 0, "tile": 2, "reward": 50}
	c.state_changed.emit()
	check(h.call("conquest"), "duel won: explains Conquest vs Victory Reward")
	c.pending = {"type": "portal", "actor": 0, "options": [3]}
	c.state_changed.emit()
	check(h.call("portal"), "portal hint")
	c.pending = {"type": "shop", "actor": 0}
	c.state_changed.emit()
	check(h.call("shop"), "shop hint")
	c.pending = {"type": "auction", "actor": 0, "tile": 1}
	c.state_changed.emit()
	check(h.call("auction"), "auction hint")
	c.pending = {"type": "duel_battle", "tile": 2, "attacker": 0, "defender": 1}
	c.state = MatchController.State.AWAIT_DUEL
	c.state_changed.emit()
	check(h.call("duel_start"), "duel with the human: preparation explained")
	c.pending = {}
	c.state = MatchController.State.TURN_DONE
	for kind in [BoardTile.Type.EVENT, BoardTile.Type.TAX, BoardTile.Type.SPECIAL, BoardTile.Type.CORNER]:
		for t in c.tiles:
			if t.type == kind:
				c.players[0].position = t.index
				break
		c.state_changed.emit()
	check(h.call("tile_event") and h.call("tile_tax") and h.call("tile_special") and h.call("tile_corner"), "tile hints: event, tax, special, corner")
	c.pending = {"type": "encounter", "actor": 0, "tile": 2, "rent": 30, "attacker": 1}
	c.state = MatchController.State.AWAIT_DECISION
	c.state_changed.emit()
	check(h.call("encounter_owner"), "owner sees that THEY choose Tax or Duel")
	c.pending = {}
	c._lose_life(c.players[0], "lost the duel")
	check(h.call("life"), "losing a Life is explained")
	c._end_of_round()
	check(h.call("round"), "new round: portals shift")
	c._end_game(0)
	check(h.call("finish"), "game over: completion message")
	check(c.tutorial_seen.size() == seen_hints.size(), "seen hints are stored in the match (%d)" % seen_hints.size())

	# forced first duel
	var c2 := new_tutorial()
	GameSession.mode = "ffa_ai"
	c2.tiles[2].owner_id = 1
	c2.current = 0
	c2.players[0].position = 2
	c2.state = MatchController.State.ROLLED
	c2._resolve_landing(c2.players[0])
	AIController.step(c2)
	check(String(c2.pending.get("type", "")) == "duel_response", "the first encounter of the tutorial is always a duel offer")
	var tax := 0
	for i in range(60):
		var c3 := new_tutorial()
		GameSession.mode = "ffa_ai"
		c3.stats["duels_offered"] = 1
		c3.tiles[2].owner_id = 1
		c3.current = 0
		c3.players[0].position = 2
		c3.state = MatchController.State.ROLLED
		c3._resolve_landing(c3.players[0])
		AIController.step(c3)
		if String(c3.pending.get("type", "")) != "duel_response" and c3.state != MatchController.State.AWAIT_DECISION:
			tax += 1
		elif String(c3.pending.get("type", "")) != "duel_response":
			tax += 1
	check(tax > 0, "later encounters are normal again (Tax chosen %d/60)" % tax)

	# save/resume keeps the tutorial
	var c4 := new_tutorial()
	GameSession.mode = "ffa_ai"
	c4.tutorial_seen.append("welcome")
	var r := MatchController.from_dict(JSON.parse_string(JSON.stringify(c4.to_dict())))
	check(r.tutorial and r.round_limit == 10 and r.tutorial_seen == ["welcome"], "a saved tutorial resumes with its seen hints")

	# the round limit ends a tutorial game
	GameSession.start_tutorial()
	var cfg := GameSession.to_match_config()
	GameSession.mode = "ffa_ai"
	cfg["all_ai"] = true
	var c5 := MatchController.new()
	c5.setup(cfg)
	var steps := 0
	while c5.state != MatchController.State.GAME_OVER and steps < 20000:
		AIController.step(c5)
		steps += 1
	check(c5.state == MatchController.State.GAME_OVER and c5.round_number <= 11, "tutorial ends by round 10 (round %d)" % c5.round_number)

	# normal matches are not affected
	var c6 := MatchController.new()
	c6.setup({"continent_id": "aetherion", "faction_id": "solvaris", "difficulty": "normal", "ai_count": 3, "seed": 3, "all_ai": true})
	check(not c6.tutorial and c6.round_limit == int(GameData.b("max_rounds")), "normal match: no tutorial, normal round limit")
	# no reference cycle between the match and its coach
	for i in range(3):
		var w := new_tutorial()
		var wg := TutorialGuide.new(w)
		wg.detach()
	GameSession.mode = "ffa_ai"
	var before := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	for i in range(40):
		var w2 := new_tutorial()
		var wg2 := TutorialGuide.new(w2)
		w2.state_changed.emit()
		wg2.detach()
	GameSession.mode = "ffa_ai"
	var after := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	check(after - before < 20, "tutorial matches are freed (objects %+d after 40 matches)" % (after - before))
	print("TUTORIAL TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
