class_name MonsterSystem
extends RefCounted
## Hidden territory monsters.
## Every continent has 4 monsters of its own (data/monsters.json), one per region, each lurking on a RANDOM territory
## tile of that region. They are never drawn on the map: a player only finds one by landing on its tile.
## Landing there starts a fight (the player may flee instead). Winning gives the player a Monster card (max ONE per
## player): when that player's King enters Last Stand in a Duel the monster fights beside the King
## (BattleEngine side config key "monster"). Monster stats scale with a King level (CommanderSystem multipliers): a wild monster takes the level of the King that challenges it (side config `foe_star`), an allied Monster the level the player had when the card was won (PlayerState.monster_star).

const FOE_CELL := Vector2i(3, 1)  # the wild monster stands in the enemy half, in front of its (empty) back rows


## One entry per monster: {"tile": territory index, "id": monster id, "taken": bool}. Consumes rng.
static func place(tiles: Array[BoardTile], continent_id: String, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for m in GameData.get_monsters(continent_id):
		var cands: Array[int] = []
		for t in tiles:
			if t.type == BoardTile.Type.TERRITORY and t.region == int(m.get("region", 0)):
				cands.append(t.index)
		if cands.is_empty():
			continue
		out.append({"tile": cands[rng.randi() % cands.size()], "id": String(m["id"]), "taken": false})
	return out


## The monster entry waiting on `tile_index` (empty dictionary if none / already taken).
static func entry_at(entries: Array, tile_index: int) -> Dictionary:
	for e in entries:
		if int(e["tile"]) == tile_index and not bool(e["taken"]):
			return e
	return {}


## Rough strength, same scale as BattleAI.power (HP + 6 x ATK), at King level `star`.
static func power(monster_id: String, star: int = 1) -> float:
	var s := stats(monster_id, star)
	return float(s.get("hp", 0)) + float(s.get("atk", 0)) * 6.0


## Monster stats at King level `star`: the data stats x the Commander star HP / ATK multipliers (CommanderSystem).
## A wild monster takes the level of the King that challenges it; an allied Monster card keeps the King level the
## player had when it was won (PlayerState.monster_star). Lv 1 = the plain data stats.
static func stats(monster_id: String, star: int = 1) -> Dictionary:
	var m := GameData.get_monster(monster_id)
	if m.is_empty():
		return {}
	var s := clampi(star, 1, CommanderSystem.max_star())
	return {"hp": maxi(1, int(round(float(m["hp"]) * CommanderSystem.hp_mult(s)))), "atk": maxi(1, int(round(float(m["atk"]) * CommanderSystem.atk_mult(s))))}


## Description for logs / UI: "Name (Lv 2, HP 780, ATK 17) - Buff: text" plus a "Skill - name: text" line (the active skill).
static func summary(monster_id: String, star: int = 1) -> String:
	var m := GameData.get_monster(monster_id)
	if m.is_empty():
		return ""
	var s := stats(monster_id, star)
	var bf: Dictionary = m.get("buff", {})
	var line := "%s (Lv %d, HP %d, ATK %d) - %s: %s" % [m["name"], clampi(star, 1, CommanderSystem.max_star()), int(s["hp"]), int(s["atk"]), bf.get("name", ""), bf.get("desc", "")]
	if String(m.get("skill_id", "")) != "":
		line += "\nSkill - %s: %s" % [m.get("active_name", ""), m.get("active_desc", "")]
	return line


## Fights the wild monster with the player's CURRENT army (auto-deployed, nothing is bought, Support cards stay in hand).
## Returns {"won": bool, "ticks": int, "reason": String}. Does not change the player's state.
static func fight(p: PlayerState, monster_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var prep := BattlePrep.new(p.deck, rng, p.gold, 0, p.level, p.roster, p.battle_deck, p.hand)
	prep.price_mult = p.battle_price_mult()
	BattleAI.auto_deploy(prep, 0)
	prep.finish()
	var side0 := prep.to_side_cfg(p.champion_id, [], p.commander_star)
	var side1 := {"units": [], "champion": "", "supports": [], "foes": [monster_id], "foe_star": p.commander_star}  # the wild monster has the challenger's King level
	var e := BattleEngine.new()
	e.setup({"seed": rng.randi(), "ai_supports": [false, false], "terrain": {}, "sides": [side0, side1]})
	var guard := 0
	while not e.finished and guard < BattleEngine.MAX_TICKS + 5:
		e.step()
		guard += 1
	return {"won": e.winner == 0, "ticks": e.tick, "reason": e.end_reason}
