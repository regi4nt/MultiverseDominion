class_name XpSystem
extends RefCounted
## Player profile progression: lifetime XP -> level -> title.
## XP is earned from Territory matches (SaveManager.record_match) and Battle Chess rounds (SaveManager.record_practice).
## The save keeps only the lifetime total (profile.xp); the level is derived from it, so tuning these numbers is safe.

const MAX_LEVEL := 60
const DIFFICULTY_MULT := {"easy": 0.75, "normal": 1.0, "hard": 1.5}
## [first level of the title, title]; the last row whose level <= the player's level applies.
const TITLES: Array = [
	[1, "Recruit"], [5, "Squire"], [10, "Knight"], [15, "Captain"], [20, "Warden"],
	[30, "Warlord"], [40, "Archon"], [50, "Overlord"], [60, "Dominion Lord"],
]


## XP needed to go from `level` to `level + 1`.
static func need_for(level: int) -> int:
	return 100 + 40 * (level - 1)


## {"level", "into" (xp inside the level), "need" (xp for the next level, 0 at max), "max"} for a lifetime XP total.
static func progress(total: int) -> Dictionary:
	var lvl := 1
	var left := maxi(total, 0)
	while lvl < MAX_LEVEL and left >= need_for(lvl):
		left -= need_for(lvl)
		lvl += 1
	var at_max := lvl >= MAX_LEVEL
	return {"level": lvl, "into": 0 if at_max else left, "need": 0 if at_max else need_for(lvl), "max": at_max}


static func level_of(total: int) -> int:
	return int(progress(total)["level"])


static func title(level: int) -> String:
	var t := String(TITLES[0][1])
	for row in TITLES:
		if level >= int(row[0]):
			t = String(row[1])
	return t


## Territory match (Journey / Arena): a win is worth far more than a loss; long matches add a little.
static func match_xp(won: bool, rounds: int, difficulty: String) -> int:
	var base := (100 if won else 30) + mini(maxi(rounds, 0), 30) * 2
	return int(round(float(base) * float(DIFFICULTY_MULT.get(difficulty, 1.0))))


## One Battle Chess battle (every round of a 10-round / survival run counts).
static func practice_xp(won: bool, difficulty: String) -> int:
	return int(round(float(40 if won else 10) * float(DIFFICULTY_MULT.get(difficulty, 1.0))))
