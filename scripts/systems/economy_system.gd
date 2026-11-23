class_name EconomySystem
extends RefCounted
## Rent / ownership maths. All numbers come from data/balance.json.


static func region_count(tiles: Array[BoardTile], region: int, owner_id: int) -> int:
	var n := 0
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY and t.region == region and t.owner_id == owner_id:
			n += 1
	return n


## Rent multiplier of an upgrade level (0 = plain land).
static func level_rent_mult(level: int) -> float:
	var mults: Array = GameData.b("upgrade_rent_mult")
	return float(mults[clampi(level, 0, mults.size() - 1)])


## Gold needed to take `t` to its next level; -1 when it is already a Landmark (or not a territory).
static func upgrade_cost(t: BoardTile) -> int:
	var max_level := int(GameData.b("max_tile_level"))
	if t.type != BoardTile.Type.TERRITORY or t.level >= max_level:
		return -1
	var ratios: Array = GameData.b("upgrade_cost_ratio")
	var ratio := float(ratios[clampi(t.level, 0, ratios.size() - 1)])
	return maxi(5, int(round(float(t.price) * ratio / 5.0)) * 5)


## Total gold already sunk into the upgrades of `t` (counts for net worth and forced sales).
static func upgrade_invested(t: BoardTile) -> int:
	var total := 0
	var probe := BoardTile.new()
	probe.type = t.type
	probe.price = t.price
	for lv in range(t.level):
		probe.level = lv
		var c := upgrade_cost(probe)
		if c > 0:
			total += c
	return total


## Rent (a.k.a. Tax) charged to a visitor of an owned territory.
## Majority of a region (>= 6/10), Regional Dominion (10/10) and upgrade levels multiply it.
static func rent_of(t: BoardTile, tiles: Array[BoardTile]) -> int:
	var rent := float(t.price) * float(GameData.b("rent_rate"))
	var owned := region_count(tiles, t.region, t.owner_id)
	if owned >= 10:
		rent *= float(GameData.b("dominion_rent_mult"))
	elif owned >= int(GameData.b("majority_threshold")):
		rent *= float(GameData.b("majority_rent_mult"))
	rent *= level_rent_mult(t.level)
	rent *= WorldMods.rent_mult
	return int(round(rent / 5.0)) * 5


static func networth(tiles: Array[BoardTile], p: PlayerState) -> int:
	var total := p.gold + p.stock_value
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY and t.owner_id == p.id:
			total += t.price + upgrade_invested(t)
	return total
