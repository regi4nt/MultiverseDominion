class_name CommanderSystem
extends RefCounted
## Commander (Champion) stars: every player's Commander starts at 1 star and reaches 2 and then 3 stars by
## completing a DIFFERENT mission for each upgrade. Missions live in data/balance.json ("commander_missions"):
## mission[0] upgrades 1 -> 2 stars, mission[1] upgrades 2 -> 3 stars. Progress only counts while that
## mission is active (it starts from 0 after the previous upgrade).


static func max_star() -> int:
	return int(GameData.b("commander_max_star"))


## The mission that upgrades `p` to the next star; {} when the Commander is already at the top star.
static func mission_of(p: PlayerState) -> Dictionary:
	var list: Array = GameData.b("commander_missions")
	var i := p.commander_star - 1
	if p.commander_star >= max_star() or i < 0 or i >= list.size():
		return {}
	return list[i]


## "Win 2 Duels. (1/2)" for the player's active mission, or "Commander at MAX" when finished.
static func mission_text(p: PlayerState) -> String:
	var m := mission_of(p)
	if m.is_empty():
		return "Commander at max level"
	return "%s (%d/%d)" % [m["desc"], p.mission_progress, int(m["target"])]


## Commander/King level label ("Lv 1".."Lv 3"); the level is the Commander star count.
static func star_text(star: int) -> String:
	return "Lv %d" % clampi(star, 1, max_star())


static func hp_mult(star: int) -> float:
	var a: Array = GameData.b("commander_star_hp_mult")
	return float(a[clampi(star - 1, 0, a.size() - 1)])


static func atk_mult(star: int) -> float:
	var a: Array = GameData.b("commander_star_atk_mult")
	return float(a[clampi(star - 1, 0, a.size() - 1)])


## Adds `amount` to the player's active mission when it tracks `metric`.
## Returns true when this completed the mission and the Commander gained a star.
static func add_progress(p: PlayerState, metric: String, amount: int = 1) -> bool:
	var m := mission_of(p)
	if m.is_empty() or String(m["metric"]) != metric:
		return false
	p.mission_progress += amount
	if p.mission_progress >= int(m["target"]):
		p.commander_star += 1
		p.mission_progress = 0
		return true
	return false
