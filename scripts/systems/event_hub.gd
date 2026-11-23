class_name EventHub
extends RefCounted
## Events screen rules: daily Missions (4 per day, drawn from a pool, reset at local midnight) and permanent Achievements.
## Progress is counted by `track(metric, n)` calls from the game (matches, chests, gacha ...). Rewards are claimed by hand.
## State: SaveManager.data["events"] = {"day", "daily": {metric: n}, "claimed": [mission ids], "life": {metric: n}, "ach_claimed": [ids]}.

const DAILY_COUNT := 4

## Daily mission pool. `metric` is a tracked counter, `target` the amount, `reward` a wallet bundle (ChestSystem reward keys).
const MISSION_POOL := [
	{"id": "m_play", "name": "Warm-up", "desc": "Play 2 Arena or Journey matches", "metric": "matches", "target": 2, "reward": {"coins": 80, "xp": 30}},
	{"id": "m_win", "name": "Victor", "desc": "Win 1 match", "metric": "wins", "target": 1, "reward": {"coins": 120, "xp": 50}},
	{"id": "m_arena", "name": "Arena Contender", "desc": "Win 1 Arena match", "metric": "arena_wins", "target": 1, "reward": {"coins": 150, "tickets": 1}},
	{"id": "m_win3", "name": "Winning Streak", "desc": "Win 3 matches", "metric": "wins", "target": 3, "reward": {"coins": 250, "crystals": 1}},
	{"id": "m_chess", "name": "Board Games", "desc": "Play 2 Battle Chess battles", "metric": "chess_played", "target": 2, "reward": {"coins": 80, "chips": 100}},
	{"id": "m_chess_win", "name": "Grandmaster", "desc": "Win 1 Battle Chess battle", "metric": "chess_wins", "target": 1, "reward": {"coins": 100, "fragments": 15}},
	{"id": "m_chest", "name": "Treasure Hunter", "desc": "Open 1 chest", "metric": "chests", "target": 1, "reward": {"fragments": 20, "chips": 100}},
	{"id": "m_pull", "name": "Lucky Draw", "desc": "Make 3 Gacha pulls", "metric": "pulls", "target": 3, "reward": {"coins": 60, "fragments": 10}},
]

## Achievements. Metrics: wins / matches (stats), arena_wins / chess_wins / chests / gold_chests (tracked), pulls (Shop), level, trophies, coins.
const ACHIEVEMENTS := [
	{"id": "a_win1", "name": "First Blood", "desc": "Win 1 match", "metric": "wins", "target": 1, "reward": {"coins": 100}},
	{"id": "a_win10", "name": "Veteran", "desc": "Win 10 matches", "metric": "wins", "target": 10, "reward": {"coins": 400, "tickets": 2}},
	{"id": "a_win50", "name": "Warlord", "desc": "Win 50 matches", "metric": "wins", "target": 50, "reward": {"coins": 1500, "crystals": 5}},
	{"id": "a_play25", "name": "Seasoned", "desc": "Play 25 matches", "metric": "matches", "target": 25, "reward": {"coins": 300, "fragments": 50}},
	{"id": "a_arena5", "name": "Arena Regular", "desc": "Win 5 Arena matches", "metric": "arena_wins", "target": 5, "reward": {"coins": 300, "chips": 300}},
	{"id": "a_arena25", "name": "Arena Champion", "desc": "Win 25 Arena matches", "metric": "arena_wins", "target": 25, "reward": {"coins": 1200, "crystals": 3}},
	{"id": "a_chess10", "name": "Tactician", "desc": "Win 10 Battle Chess battles", "metric": "chess_wins", "target": 10, "reward": {"coins": 500, "fragments": 60}},
	{"id": "a_chest5", "name": "Chest Collector", "desc": "Open 5 chests", "metric": "chests", "target": 5, "reward": {"coins": 250, "tickets": 2}},
	{"id": "a_chest25", "name": "Treasure Baron", "desc": "Open 25 chests", "metric": "chests", "target": 25, "reward": {"coins": 1000, "crystals": 3}},
	{"id": "a_gold", "name": "Golden Touch", "desc": "Open a Gold Chest", "metric": "gold_chests", "target": 1, "reward": {"coins": 300, "crystals": 1}},
	{"id": "a_pull10", "name": "Gambler's Start", "desc": "Make 10 Gacha pulls", "metric": "pulls", "target": 10, "reward": {"coins": 200, "tickets": 1}},
	{"id": "a_pull50", "name": "Gacha Addict", "desc": "Make 50 Gacha pulls", "metric": "pulls", "target": 50, "reward": {"fragments": 150, "crystals": 2}},
	{"id": "a_lv5", "name": "Rising Ruler", "desc": "Reach profile level 5", "metric": "level", "target": 5, "reward": {"coins": 300, "chips": 200}},
	{"id": "a_lv10", "name": "Sovereign", "desc": "Reach profile level 10", "metric": "level", "target": 10, "reward": {"coins": 800, "crystals": 3}},
	{"id": "a_trophy500", "name": "Trophy Hunter", "desc": "Reach 500 Journey trophies", "metric": "trophies", "target": 500, "reward": {"coins": 600, "tickets": 3}},
	{"id": "a_rich", "name": "Treasury", "desc": "Hold 5000 Aether Coins", "metric": "coins", "target": 5000, "reward": {"crystals": 2, "chips": 500}},
]


static func _store() -> Dictionary:
	var d: Dictionary = SaveManager.data
	if not d.has("events") or not (d["events"] is Dictionary):
		d["events"] = {}
	var e: Dictionary = d["events"]
	for k in ["daily", "life"]:
		if not e.has(k) or not (e[k] is Dictionary):
			e[k] = {}
	for k in ["claimed", "ach_claimed"]:
		if not e.has(k) or not (e[k] is Array):
			e[k] = []
	_roll_day(e)
	return e


## "2026-11-24" in the player's local time (ChestSystem.time_offset moves it in tests).
static func today() -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_date_string_from_unix_time(ChestSystem.now() + bias)


## Seconds until the next daily reset.
static func seconds_to_reset() -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := ChestSystem.now() + bias
	return 86400 - (t % 86400)


static func _roll_day(e: Dictionary) -> void:
	var day := today()
	if String(e.get("day", "")) != day:
		e["day"] = day
		e["daily"] = {}
		e["claimed"] = []


## Today's missions (a day-seeded draw from the pool: same list all day, a new one tomorrow).
static func daily_missions() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(today())
	var idx: Array = range(MISSION_POOL.size())
	for i in range(idx.size() - 1, 0, -1):  # Fisher-Yates with the day seed
		var j := rng.randi_range(0, i)
		var tmp = idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	var out: Array = []
	for i in range(mini(DAILY_COUNT, idx.size())):
		out.append(MISSION_POOL[idx[i]])
	return out


## Counts an event for today's missions and the lifetime counters.
static func track(metric: String, n: int = 1) -> void:
	if n <= 0:
		return
	var e := _store()
	e["daily"][metric] = int(e["daily"].get(metric, 0)) + n
	e["life"][metric] = int(e["life"].get(metric, 0)) + n


static func metric_value(metric: String, daily: bool) -> int:
	var e := _store()
	if daily:
		return int(e["daily"].get(metric, 0))
	match metric:
		"wins":
			return int(SaveManager.data["stats"].get("wins", 0))
		"matches":
			return int(SaveManager.data["stats"].get("matches_played", 0))
		"pulls":
			return int(SaveManager.data["shop"].get("pulls", 0)) + int(SaveManager.data["shop"].get("unit_pulls", 0))
		"chests":
			return maxi(ChestSystem.opened_total(), int(e["life"].get("chests", 0)))
		"level":
			return SaveManager.profile_level()
		"trophies":
			return SaveManager.trophies()
		"coins":
			return SaveManager.coins()
	return int(e["life"].get(metric, 0))


static func progress(def: Dictionary, daily: bool) -> int:
	return mini(metric_value(String(def["metric"]), daily), int(def["target"]))


static func is_done(def: Dictionary, daily: bool) -> bool:
	return metric_value(String(def["metric"]), daily) >= int(def["target"])


static func is_claimed(id: String, daily: bool) -> bool:
	return (_store()["claimed" if daily else "ach_claimed"] as Array).has(id)


static func can_claim(def: Dictionary, daily: bool) -> bool:
	return is_done(def, daily) and not is_claimed(String(def["id"]), daily)


## Pays the reward of a finished, unclaimed mission / achievement. Returns {"ok", "rewards", "error"}.
static func claim(id: String, daily: bool) -> Dictionary:
	var def := find(id, daily)
	if def.is_empty() or not can_claim(def, daily):
		return {"ok": false, "error": "Nothing to claim."}
	(_store()["claimed" if daily else "ach_claimed"] as Array).append(id)
	var rewards: Dictionary = def["reward"]
	for k in rewards:
		var n := int(rewards[k])
		match String(k):
			"coins":
				SaveManager.add_coins(n)
			"fragments":
				SaveManager.add_fragments(n)
			"xp":
				SaveManager.add_xp(n)
			_:
				SaveManager.add_currency(String(k), n)
	SaveManager.save_game()
	return {"ok": true, "rewards": rewards}


static func find(id: String, daily: bool) -> Dictionary:
	for d in (daily_missions() if daily else ACHIEVEMENTS):
		if String(d["id"]) == id:
			return d
	return {}


## Number of finished-but-unclaimed entries (menu badge).
static func claimable_count() -> int:
	var n := 0
	for d in daily_missions():
		if can_claim(d, true):
			n += 1
	for a in ACHIEVEMENTS:
		if can_claim(a, false):
			n += 1
	return n


static func claimable_count_in(daily: bool) -> int:
	var n := 0
	for d in (daily_missions() if daily else ACHIEVEMENTS):
		if can_claim(d, daily):
			n += 1
	return n
