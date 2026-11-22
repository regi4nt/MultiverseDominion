class_name CapacitySystem
extends RefCounted
## Chess Capacity: Pawn 1, Rook/Knight/Bishop 2, Queen 4, King 6.
## Level 3 = 9 capacity, +3 per level, level 10 = 30.
## ASSUMPTION (to confirm in Phase 4): the King/Champion is NOT counted against deployment
## capacity because it only enters the arena as Last Stand; only regular units are counted.


static func capacity_for_level(level: int) -> int:
	var lv := clampi(level, int(GameData.b("start_level")), int(GameData.b("max_level")))
	return lv * int(GameData.b("capacity_per_level"))


static func used(units: Array[UnitInstance]) -> int:
	var total := 0
	for u in units:
		total += CardDatabase.capacity_cost(u.chess())
	return total


static func can_deploy(deployed: Array[UnitInstance], card_id: String, level: int) -> bool:
	var cost := CardDatabase.capacity_cost(CardDatabase.get_unit(card_id).get("chess", ""))
	return cost > 0 and used(deployed) + cost <= capacity_for_level(level)
