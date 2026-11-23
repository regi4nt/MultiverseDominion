class_name BattleAI
extends RefCounted
## Army building / formation for AI sides, duel decisions and the player's "Auto Deploy" button.

const COLUMN_ORDER: Array[int] = [3, 4, 2, 5, 1, 6, 0, 7]


static func power(u: UnitInstance) -> float:
	var s := u.stats()
	return float(s["hp"]) + float(s["atk"]) * 6.0


## Rough strength of a player's army if a duel started now (units that fit the capacity,
## the Champion, and a share of the gold that could still be spent in preparation).
static func army_power(p: PlayerState) -> float:
	var sorted: Array[UnitInstance] = p.roster.units.duplicate()
	sorted.sort_custom(func(a: UnitInstance, b: UnitInstance) -> bool: return power(a) > power(b))
	var used := 0
	var total := 0.0
	var cap := CapacitySystem.capacity_for_level(p.level)
	for u in sorted:
		var cost := CardDatabase.capacity_cost(u.chess())
		if used + cost <= cap:
			used += cost
			total += power(u)
	var ch := GameData.get_champion(p.champion_id)
	total += (float(ch.get("hp", 100)) * float(GameData.b("champion_hp_mult")) * CommanderSystem.hp_mult(p.commander_star) + float(ch.get("atk", 10)) * 6.0 * CommanderSystem.atk_mult(p.commander_star)) * 0.5
	return total + float(p.gold) * 0.4


## Rows from front to back for a side.
static func rows_for(side: int) -> Array[int]:
	if side == 0:
		return [4, 5, 6, 7]
	return [3, 2, 1, 0]


static func _preferred_rows(role: String, side: int) -> Array[int]:
	var r := rows_for(side)  # [front, mid, back1, back2]
	match role:
		"Tank":
			return [r[0], r[1], r[2], r[3]]
		"Fighter", "Assassin":
			return [r[1], r[0], r[2], r[3]]
	return [r[2], r[3], r[1], r[0]]


## Chooses the strongest units that fit the capacity and places them by role.
## `lineup` (player side only): the custom lineup of the Deck ({id, x, y} entries). Units of those types go to their cells first
## (strongest copy of a type first, while the capacity allows); the rest of the capacity is filled the usual way.
static func auto_deploy(prep: BattlePrep, side: int = 0, lineup: Array = []) -> void:
	var all: Array[UnitInstance] = prep.roster.units.duplicate()
	for u in all:
		u.cell = Vector2i(-1, -1)
	var taken := {}
	var used := 0
	if side == 0 and not lineup.is_empty():
		var entries: Array = lineup.duplicate()
		entries.sort_custom(func(a, b) -> bool: return _best_power(all, String(a["id"])) > _best_power(all, String(b["id"])))
		for e in entries:
			var cell := Vector2i(int(e["x"]), int(e["y"]))
			if taken.has(cell):
				continue
			var best: UnitInstance = null
			for u in all:
				if u.card_id == String(e["id"]) and u.cell.x < 0 and (best == null or power(u) > power(best)):
					best = u
			if best == null:
				continue
			var cost := CardDatabase.capacity_cost(best.chess())
			if used + cost > prep.capacity():
				continue
			if not Terrain.can_stand(prep.terrain, int(CardDatabase.get_unit(best.card_id)["range"]), cell):
				continue  # a melee unit cannot hold a highland of this duel
			best.cell = cell
			taken[cell] = true
			used += cost
		var rest: Array[UnitInstance] = []
		for u in all:
			if u.cell.x < 0:
				rest.append(u)
		all = rest
	all.sort_custom(func(a: UnitInstance, b: UnitInstance) -> bool: return power(a) > power(b))
	var chosen: Array[UnitInstance] = []
	for u in all:
		var cost := CardDatabase.capacity_cost(u.chess())
		if used + cost <= prep.capacity():
			chosen.append(u)
			used += cost
	for u in chosen:
		var placed := false
		var u_range := int(CardDatabase.get_unit(u.card_id)["range"])
		for row in _preferred_rows(String(CardDatabase.get_unit(u.card_id).get("role", "Fighter")), side):
			for col in COLUMN_ORDER:
				var c := Vector2i(col, row)
				if not taken.has(c) and Terrain.can_stand(prep.terrain, u_range, c):
					taken[c] = true
					u.cell = c
					placed = true
					break
			if placed:
				break


static func _best_power(units: Array[UnitInstance], card_id: String) -> float:
	var best := -1.0
	for u in units:
		if u.card_id == card_id:
			best = maxf(best, power(u))
	return best


static func _shop_loop(prep: BattlePrep, difficulty: String, rng: RandomNumberGenerator) -> void:
	var rarity_weight := {"common": 0.0, "rare": 25.0, "epic": 60.0}
	var tries := 0
	while tries < 60 and prep.budget_left >= 25:
		tries += 1
		var best := -1
		var best_score := -1.0
		for i in range(prep.offers.size()):
			if prep.can_buy(i) != "":
				continue
			var id := prep.offers[i]
			var score := rng.randf() * 10.0
			if BattlePrep.is_support_id(id):  # Support cards rank below units; "easy" AIs rarely buy them
				if difficulty == "easy" and rng.randf() < 0.7:
					continue
				score += float(rarity_weight.get(CardDatabase.get_support(id).get("rarity", "common"), 0.0)) - 15.0
				if score > best_score:
					best_score = score
					best = i
				continue
			if difficulty != "easy":
				score += float(rarity_weight.get(CardDatabase.get_unit(id).get("rarity", "common"), 0.0))
				score += float(prep.roster.count_of(id)) * 40.0  # go for star upgrades
			if score > best_score:
				best_score = score
				best = i
		if best >= 0:
			prep.buy(best)
		else:
			prep.refresh_offers(false)


## Standalone AI army (Battle Chess, tests).
static func build_enemy(difficulty: String, level: int, rng: RandomNumberGenerator, deck: Deck, terrain: Dictionary = {}) -> BattlePrep:
	var budget_table: Dictionary = GameData.b("enemy_budget")
	var budget := int(budget_table.get(difficulty, 450))
	var prep := BattlePrep.new(deck, rng, budget, budget, level)
	prep.terrain = terrain
	_shop_loop(prep, difficulty, rng)
	auto_deploy(prep, 1)
	return prep


## AI player prepares for a duel with its PERSISTENT army: spends part of its real gold,
## may level up, deploys, and returns the side config for BattleEngine.setup().
static func prepare_ai_army(p: PlayerState, rng: RandomNumberGenerator, side: int, terrain: Dictionary = {}) -> Dictionary:
	var ratios: Dictionary = GameData.b("ai_battle_budget_ratio")
	var budget := int(float(p.gold) * float(ratios.get(p.difficulty, 0.35)))
	var prep := BattlePrep.new(p.deck, rng, p.gold, budget, p.level, p.roster, p.battle_deck, p.hand)
	prep.price_mult = p.battle_price_mult()
	prep.terrain = terrain
	if p.difficulty != "easy":
		var total_cost := 0
		for u in p.roster.units:
			total_cost += CardDatabase.capacity_cost(u.chess())
		if total_cost >= prep.capacity() - 1 and prep.level < 7 and prep.budget_left >= prep.level_up_cost() + 50:
			prep.level_up()
	_shop_loop(prep, p.difficulty, rng)
	auto_deploy(prep, side)
	prep.finish()
	p.gold = prep.gold
	p.level = prep.level
	p.capacity = prep.capacity()
	return prep.to_side_cfg(p.champion_id, p.hand, p.commander_star, p.monster_id)


static func pick_champion(rng: RandomNumberGenerator, exclude: String = "") -> String:
	var ids: Array = GameData.champions.keys()
	ids.erase(exclude)
	return String(ids[rng.randi() % ids.size()])


static func pick_hand(deck: Deck, rng: RandomNumberGenerator, count: int) -> Array:
	var pool: Array = deck.support_ids.duplicate()
	var out: Array = []
	while out.size() < count and not pool.is_empty():
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return out
