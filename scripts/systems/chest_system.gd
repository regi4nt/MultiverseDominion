class_name ChestSystem
extends RefCounted
## Reward chests. Winning an Arena match drops a chest (grade Bronze / Silver / Gold, odds depend on the difficulty).
## A chest sits in one of SLOT_COUNT slots, must be unlocked by a real-time timer (one chest unlocks at a time, the timer
## keeps running while the game is closed) and is opened for a random bundle of coins, fragments, chips, tickets, crystals and XP.
## A Crystal skips the rest of a timer. All state lives in SaveManager.data["chests"]; every number is a constant here.

const SLOT_COUNT := 4
const GRADES: Array[String] = ["bronze", "silver", "gold"]
const SKIP_SECONDS_PER_CRYSTAL := 1800  # 1 Crystal per started half hour that is still left

## Odds (weights) of the grade of a dropped chest, by Arena difficulty.
const DROP_WEIGHTS := {
	"easy": {"bronze": 70, "silver": 25, "gold": 5},
	"normal": {"bronze": 55, "silver": 33, "gold": 12},
	"hard": {"bronze": 35, "silver": 45, "gold": 20},
}

## Per grade: name, colour, unlock time (seconds), coins paid instead when every slot is full, and the reward table.
## Each reward is [min, max, chance %]. `card_chance` = % to also unlock the next locked Support card.
const GRADE_DATA := {
	"bronze": {
		"name": "Bronze Chest", "color": Color("c98a4b"), "seconds": 900, "full_coins": 50, "card_chance": 0,
		"rewards": {"coins": [60, 120, 100], "fragments": [5, 15, 70], "chips": [50, 150, 40], "tickets": [1, 1, 10], "xp": [20, 40, 100]},
	},
	"silver": {
		"name": "Silver Chest", "color": Color("c4ccd8"), "seconds": 3600, "full_coins": 150, "card_chance": 0,
		"rewards": {"coins": [150, 300, 100], "fragments": [20, 45, 100], "chips": [150, 400, 70], "tickets": [1, 2, 40], "crystals": [1, 1, 20], "xp": [60, 110, 100]},
	},
	"gold": {
		"name": "Gold Chest", "color": Color("f2c230"), "seconds": 14400, "full_coins": 400, "card_chance": 25,
		"rewards": {"coins": [400, 800, 100], "fragments": [60, 140, 100], "chips": [500, 1200, 90], "tickets": [2, 4, 80], "crystals": [1, 3, 60], "xp": [150, 260, 100]},
	},
}

## Display order and names of the reward kinds.
const REWARD_ORDER: Array[String] = ["coins", "fragments", "crystals", "tickets", "chips", "xp"]
const REWARD_NAMES := {"coins": "Aether Coins", "fragments": "Fragments", "crystals": "Crystals", "tickets": "Gacha Tickets", "chips": "Chips", "xp": "XP"}

## Test hook: seconds added to the real clock.
static var time_offset: int = 0


static func now() -> int:
	return int(Time.get_unix_time_from_system()) + time_offset


static func grade_name(grade: String) -> String:
	return String(GRADE_DATA.get(grade, {}).get("name", grade.capitalize() + " Chest"))


static func grade_color(grade: String) -> Color:
	return GRADE_DATA.get(grade, {}).get("color", Color.GRAY)


static func grade_seconds(grade: String) -> int:
	return int(GRADE_DATA.get(grade, {}).get("seconds", 900))


## "15 min", "1 h", "4 h", "1 h 30 min".
static func duration_text(seconds: int) -> String:
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	if h > 0 and m > 0:
		return "%d h %d min" % [h, m]
	if h > 0:
		return "%d h" % h
	return "%d min" % m


## Countdown "1:05:09" / "04:09".
static func clock_text(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	var s := seconds % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]


## One-line description of what a grade can hold, e.g. "Coins 60-120, Fragments 5-15, ...".
static func reward_summary(grade: String) -> String:
	var parts: Array[String] = []
	var table: Dictionary = GRADE_DATA[grade]["rewards"]
	for k in REWARD_ORDER:
		if table.has(k):
			var r: Array = table[k]
			var rng_txt := str(r[0]) if r[0] == r[1] else "%d-%d" % [r[0], r[1]]
			parts.append("%s %s%s" % [REWARD_NAMES[k], rng_txt, "" if int(r[2]) >= 100 else " (%d%%)" % int(r[2])])
	if int(GRADE_DATA[grade]["card_chance"]) > 0:
		parts.append("Support card (%d%%)" % int(GRADE_DATA[grade]["card_chance"]))
	return ", ".join(parts)


# --- state ------------------------------------------------------------------

static func _store() -> Dictionary:
	var d: Dictionary = SaveManager.data
	if not d.has("chests") or not (d["chests"] is Dictionary):
		d["chests"] = {"slots": [], "opened": 0}
	var c: Dictionary = d["chests"]
	if not c.has("slots") or not (c["slots"] is Array):
		c["slots"] = []
	var slots: Array = c["slots"]
	while slots.size() < SLOT_COUNT:
		slots.append(null)
	while slots.size() > SLOT_COUNT:
		slots.pop_back()
	return c


## The slots: null (empty) or {"grade", "start" (0 = not unlocking yet), "ready" (unix time the timer ends)}.
static func slots() -> Array:
	return _store()["slots"]


static func opened_total() -> int:
	return int(_store().get("opened", 0))


static func is_valid_slot(i: int) -> bool:
	return i >= 0 and i < SLOT_COUNT


## "empty" | "locked" (waiting) | "unlocking" (timer running) | "ready" (timer over, can be opened).
static func state(i: int) -> String:
	if not is_valid_slot(i):
		return "empty"
	var s: Variant = slots()[i]
	if s == null:
		return "empty"
	if int(s.get("start", 0)) <= 0:
		return "locked"
	return "ready" if now() >= int(s.get("ready", 0)) else "unlocking"


static func grade_at(i: int) -> String:
	var s: Variant = slots()[i] if is_valid_slot(i) else null
	return "" if s == null else String(s.get("grade", ""))


## Seconds left on the timer (a locked chest shows its full time).
static func remaining(i: int) -> int:
	match state(i):
		"locked":
			return grade_seconds(grade_at(i))
		"unlocking":
			return maxi(0, int(slots()[i]["ready"]) - now())
	return 0


static func free_slots() -> int:
	var n := 0
	for i in range(SLOT_COUNT):
		if state(i) == "empty":
			n += 1
	return n


static func ready_count() -> int:
	var n := 0
	for i in range(SLOT_COUNT):
		if state(i) == "ready":
			n += 1
	return n


## Index of the chest whose timer is running (-1 = none). A ready chest does not count.
static func unlocking_slot() -> int:
	for i in range(SLOT_COUNT):
		if state(i) == "unlocking":
			return i
	return -1


# --- drop -------------------------------------------------------------------

static func roll_grade(difficulty: String, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = DROP_WEIGHTS.get(difficulty, DROP_WEIGHTS["normal"])
	var total := 0
	for g in GRADES:
		total += int(w[g])
	var r := rng.randi_range(1, total)
	for g in GRADES:
		r -= int(w[g])
		if r <= 0:
			return g
	return GRADES[0]


## The chest of an Arena victory. Goes into the first empty slot (waiting, not unlocking yet). With every slot full the chest
## turns into coins at once so a win never pays nothing. Returns {"status": "added"|"full", "grade", "slot" | "coins"}.
static func award(difficulty: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return award_grade(roll_grade(difficulty, rng))


static func award_grade(grade: String) -> Dictionary:
	var arr := slots()
	for i in range(SLOT_COUNT):
		if arr[i] == null:
			arr[i] = {"grade": grade, "start": 0, "ready": 0}
			SaveManager.save_game()
			return {"status": "added", "grade": grade, "slot": i}
	var coins := int(GRADE_DATA[grade]["full_coins"])
	SaveManager.add_coins(coins)
	SaveManager.save_game()
	return {"status": "full", "grade": grade, "coins": coins}


# --- timer ------------------------------------------------------------------

## Starts the timer of a waiting chest. Returns "" or the reason it failed.
static func start_unlock(i: int) -> String:
	if state(i) != "locked":
		return "This chest is not waiting."
	if unlocking_slot() >= 0:
		return "Another chest is already unlocking."
	var t := now()
	var s: Dictionary = slots()[i]
	s["start"] = t
	s["ready"] = t + grade_seconds(String(s["grade"]))
	SaveManager.save_game()
	return ""


## Crystals needed to open a chest at once (0 when it is ready or empty).
static func skip_cost(i: int) -> int:
	var left := remaining(i)
	if left <= 0 or state(i) == "empty":
		return 0
	return int(ceil(float(left) / float(SKIP_SECONDS_PER_CRYSTAL)))


## Pays Crystals to finish the timer now (works on a waiting chest too, and does not need the unlock slot to be free).
## Returns "" or the reason it failed.
static func skip(i: int) -> String:
	var st := state(i)
	if st != "locked" and st != "unlocking":
		return "Nothing to skip."
	var cost := skip_cost(i)
	if not SaveManager.spend_currency("crystals", cost):
		return "Not enough Crystals (%d needed)." % cost
	var s: Dictionary = slots()[i]
	var t := now()
	if int(s.get("start", 0)) <= 0:
		s["start"] = t
	s["ready"] = t
	SaveManager.save_game()
	return ""


# --- open -------------------------------------------------------------------

## Rolls the reward bundle of a grade without paying it. Keys: coins / fragments / crystals / tickets / chips / xp, and "card" (a Support card id) for a lucky Gold chest.
static func roll_rewards(grade: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var table: Dictionary = GRADE_DATA[grade]["rewards"]
	for k in REWARD_ORDER:
		if not table.has(k):
			continue
		var r: Array = table[k]
		if rng.randi_range(1, 100) <= int(r[2]):
			out[k] = rng.randi_range(int(r[0]), int(r[1]))
	if out.is_empty():
		out["coins"] = int((table["coins"] as Array)[0])
	return out


## Opens a ready chest, pays the rewards into the wallet and empties the slot. Returns
## {"ok": true, "grade", "rewards": {...}, "card": "" | id, "level_up": 0 | level} or {"ok": false, "error"}.
static func open(i: int, rng: RandomNumberGenerator = null) -> Dictionary:
	if state(i) != "ready":
		return {"ok": false, "error": "This chest is not ready yet."}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var grade := grade_at(i)
	var rewards := roll_rewards(grade, rng)
	var card := ""
	if rng.randi_range(1, 100) <= int(GRADE_DATA[grade]["card_chance"]):
		card = SaveManager.unlock_next_card()
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
	var level_up := SaveManager.last_level_up if rewards.has("xp") else 0
	EventHub.track("chests")
	if grade == "gold":
		EventHub.track("gold_chests")
	slots()[i] = null
	_store()["opened"] = opened_total() + 1
	SaveManager.save_game()
	return {"ok": true, "grade": grade, "rewards": rewards, "card": card, "level_up": level_up}


## "+120 Aether Coins" lines of a reward bundle, in display order.
static func reward_lines(rewards: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for k in REWARD_ORDER:
		if rewards.has(k):
			lines.append("+%d %s" % [int(rewards[k]), REWARD_NAMES[k]])
	return lines
