extends Node
## Continent Mission (Arena / Chaos): one mission per continent, human-only progress, bonus reward, save / resume.
## Run: godot --headless --path . res://tests/mission_test.tscn

var failures := 0
const CONTS := ["aetherion", "arcanum", "machina", "sylvaris", "drakmor", "thalassia", "eclipsia"]


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _new_match(cid: String, extra: Dictionary = {}) -> MatchController:
	var cfg := {"continent_id": cid, "faction_id": GameData.get_continent(cid)["factions"][0]["id"], "difficulty": "normal", "ai_count": 3, "seed": 11}
	cfg.merge(extra, true)
	var c := MatchController.new()
	c.setup(cfg)
	return c


func _ready() -> void:
	for cid in CONTS:
		var m: Dictionary = GameData.get_continent(cid).get("mission", {})
		check(not m.is_empty() and int(m.get("target", 0)) > 0 and int(m.get("target_chaos", 0)) > 0 and not (m.get("reward", {}) as Dictionary).is_empty(), "%s has one mission with targets and a reward" % cid)

	var j := _new_match("machina", {"journey": true})
	check(not j.has_mission(), "no mission in Journey")
	var t := _new_match("machina", {"tutorial": true})
	check(not t.has_mission(), "no mission in the tutorial")
	var ai := _new_match("machina", {"all_ai": true})
	check(not ai.has_mission(), "no mission without a human seat")

	var a := _new_match("machina")
	check(a.has_mission() and a.mission_target == 4 and a.mission_progress == 0 and not a.mission_done, "Arena: Machina mission starts at 0 / 4")
	var ch := _new_match("machina", {"chaos": true})
	check(ch.has_mission() and ch.mission_target == 3, "Chaos: lower target (3)")

	# progress counts only the human's events
	var g0: int = a.players[0].gold
	var sd0: int = a.players[0].special_dice.size()
	a._mission_event(a.players[1], "upgrades")
	check(a.mission_progress == 0, "an AI's upgrade does not count")
	a._mission_event(a.players[0], "duel_wins")
	check(a.mission_progress == 0, "another metric does not count")
	for i in 3:
		a._mission_event(a.players[0], "upgrades")
	check(a.mission_progress == 3 and not a.mission_done, "3 / 4 is not complete")
	a._mission_event(a.players[0], "upgrades")
	check(a.mission_done and a.mission_progress == 4, "4 / 4 completes the mission")
	check(a.players[0].gold == g0 + int(a.mission_reward().get("gold", 0)) and a.players[0].special_dice.size() == sd0 + 1, "completing pays the in-game reward (gold + Special Die) at once")
	var g1 := a.players[0].gold
	a._mission_event(a.players[0], "upgrades")
	check(a.players[0].gold == g1, "the in-game reward is paid only once")
	a._mission_event(a.players[0], "upgrades")
	check(a.mission_progress == 4, "progress is capped at the target")

	# state missions: territories (Sylvaris) and Regional Dominion (Aetherion)
	var s := _new_match("sylvaris")
	var n := 0
	for tl in s.tiles:
		if tl.type == BoardTile.Type.TERRITORY and n < s.mission_target:
			tl.owner_id = 0
			n += 1
	s._mission_check_state()
	check(s.mission_done, "owning %d territories completes Great Grove" % s.mission_target)
	var d := _new_match("aetherion")
	var region := -1
	for tl in d.tiles:
		if tl.type == BoardTile.Type.TERRITORY:
			region = tl.region
			break
	for tl in d.tiles:
		if tl.type == BoardTile.Type.TERRITORY and tl.region == region:
			tl.owner_id = 0
	d._mission_check_state()
	check(d.mission_done, "a whole region completes Crown Dominion")

	# save / resume keeps the progress
	var b := _new_match("drakmor")
	b._mission_event(b.players[0], "duel_wins")
	var r := MatchController.from_dict(b.to_dict())
	check(r.has_mission() and r.mission_progress == 1 and not r.mission_done and r.mission_target == b.mission_target, "save / resume keeps mission progress")
	b._mission_event(b.players[0], "duel_wins", 5)
	var r2 := MatchController.from_dict(b.to_dict())
	check(r2.mission_done, "save / resume keeps a completed mission")
	# every continent pays something and the rewards vary
	var kinds := {}
	for cid in CONTS:
		var rw: Dictionary = GameData.get_continent(cid)["mission"]["reward"]
		check(not rw.is_empty() and not rw.has("coins") and not rw.has("crystals"), "%s: in-game reward only (no post-match coins / crystals)" % cid)
		for k in rw:
			kinds[k] = true
	check(kinds.size() >= 4, "rewards vary: gold, tokens, die, life")
	# Life reward at full Life turns into gold
	var e := _new_match("eclipsia")
	var gold_e: int = e.players[0].gold
	var life_e: int = e.players[0].life
	e._mission_event(e.players[0], "monsters_won")
	check(e.mission_done and e.players[0].reroll_tokens >= 3 and e.players[0].life == life_e and e.players[0].gold == gold_e + 100, "full Life: the Life reward becomes +100 G")

	# --- Battle Chess mission (one per continent, read from the engine, Gold reward)
	for cid in CONTS:
		var bm := BattleMission.of(cid)
		check(not bm.is_empty() and BattleMission.reward_gold(bm) > 0 and BattleMission.goal(bm) >= 1, "%s has a Battle Chess mission paying gold" % cid)
	var e2 := BattleEngine.new()
	var kill_m := BattleMission.of("machina")
	check(not BattleMission.is_done(kill_m, e2), "Battle mission starts incomplete")
	e2.kills[0] = int(kill_m["target"])
	check(BattleMission.is_done(kill_m, e2), "kills reach the target -> done")
	var sup_m := BattleMission.of("arcanum")
	(e2.used_supports[0] as Array).append("a")
	check(not BattleMission.is_done(sup_m, e2), "1 / 2 Support cards is not done")
	(e2.used_supports[0] as Array).append("b")
	check(BattleMission.is_done(sup_m, e2), "2 Support cards -> done")
	var ks_m := BattleMission.of("eclipsia")
	e2.king_skill_used[0] = true
	check(BattleMission.is_done(ks_m, e2), "casting the King skill -> done")
	var fl_m := BattleMission.of("sylvaris")
	check(not BattleMission.is_done(fl_m, e2), "flawless needs a finished, won battle")
	e2.finished = true
	e2.winner = 0
	e2.kills[1] = 0
	check(BattleMission.is_done(fl_m, e2), "won without losing a unit -> flawless done")
	e2.kills[1] = 1
	check(not BattleMission.is_done(fl_m, e2), "losing a unit breaks flawless")
	var fw_m := BattleMission.of("thalassia")
	e2.tick = int(fw_m["target"])
	check(BattleMission.is_done(fw_m, e2), "winning within the tick limit -> fast win done")
	e2.tick = int(fw_m["target"]) + 1
	check(not BattleMission.is_done(fw_m, e2), "winning too late -> not done")

	print("mission_test: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
