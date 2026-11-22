class_name EconomySystem
extends RefCounted
## Rent / ownership maths. All numbers come from data/balance.json.


static func region_count(tiles: Array[BoardTile], region: int, owner_id: int) -> int:
	var n := 0
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY and t.region == region and t.owner_id == owner_id:
			n += 1
	return n


## Rent (a.k.a. Tax) charged to a visitor of an owned territory.
## Majority of a region (>= 6/10) and Regional Dominion (10/10) multiply it.
static func rent_of(t: BoardTile, tiles: Array[BoardTile]) -> int:
	var rent := float(t.price) * float(GameData.b("rent_rate"))
	var owned := region_count(tiles, t.region, t.owner_id)
	if owned >= 10:
		rent *= float(GameData.b("dominion_rent_mult"))
	elif owned >= int(GameData.b("majority_threshold")):
		rent *= float(GameData.b("majority_rent_mult"))
	rent *= WorldMods.rent_mult
	return int(round(rent / 5.0)) * 5


static func networth(tiles: Array[BoardTile], p: PlayerState) -> int:
	var total := p.gold
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY and t.owner_id == p.id:
			total += t.price
	return total
