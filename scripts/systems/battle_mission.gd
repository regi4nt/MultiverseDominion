class_name BattleMission
extends RefCounted
## Battle Chess Continent Mission: one mission per continent (data/continents.json "battle_mission"), played inside one battle.
## The reward is Gold for the preparation panel, paid at once when the mission completes (it carries into the next round of a run).
## Progress is read from the BattleEngine (side 0 = the human).


static func of(continent_id: String) -> Dictionary:
	return GameData.get_continent(continent_id).get("battle_mission", {})


static func text(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	return "%s: %s" % [String(m.get("name", "Mission")), String(m.get("description", "")).replace("{n}", str(int(m.get("target", 1))))]


static func reward_gold(m: Dictionary) -> int:
	return int((m.get("reward", {}) as Dictionary).get("gold", 0))


## Shown progress and the target it is compared with (for yes / no goals both are 0 or 1).
static func progress(m: Dictionary, e: BattleEngine) -> int:
	var won := e.finished and e.winner == 0
	match String(m.get("metric", "")):
		"kills":
			return int(e.kills[0])
		"supports":
			return (e.used_supports[0] as Array).size()
		"king_skill":
			return 1 if bool(e.king_skill_used[0]) else 0
		"survivors_win":
			return e.regulars_alive(0) if won else 0
		"flawless":
			return 1 if (won and int(e.kills[1]) == 0) else 0
		"fast_win":
			return 1 if (won and e.tick <= int(m.get("target", 150))) else 0
	return 0


## "fast_win" stores its tick limit in `target`; its goal itself is a single yes / no.
static func goal(m: Dictionary) -> int:
	return 1 if String(m.get("metric", "")) == "fast_win" else maxi(int(m.get("target", 1)), 1)


static func is_done(m: Dictionary, e: BattleEngine) -> bool:
	return not m.is_empty() and progress(m, e) >= goal(m)


static func status_line(m: Dictionary, e: BattleEngine, done: bool) -> String:
	if m.is_empty():
		return ""
	var g := goal(m)
	return "Mission %s  %s (%d / %d)  +%d G" % ["✓" if done else "★", String(m.get("name", "")), mini(progress(m, e), g), g, reward_gold(m)]
