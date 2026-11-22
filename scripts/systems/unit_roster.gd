class_name UnitRoster
extends RefCounted
## Units owned in a match with automatic star upgrade (auto-chess merge):
##   B1 = 1 card, B2 = 3 identical B1 cards, B3 = 9 identical cards (3 x B2).

var units: Array[UnitInstance] = []


## Adds one 1-star copy and merges. Returns human-readable merge events.
func add_copy(card_id: String) -> Array[String]:
	units.append(UnitInstance.new(card_id, 1))
	var events: Array[String] = []
	var merged := true
	while merged:
		merged = false
		for stars in [1, 2]:
			var same: Array[UnitInstance] = []
			for u in units:
				if u.card_id == card_id and u.stars == stars:
					same.append(u)
			if same.size() >= 3:
				var keep_cell := Vector2i(-1, -1)
				for i in range(3):
					if keep_cell.x < 0 and same[i].cell.x >= 0:
						keep_cell = same[i].cell
					units.erase(same[i])
				var up := UnitInstance.new(card_id, stars + 1)
				up.cell = keep_cell  # the upgraded unit stays where a merged copy was deployed
				units.append(up)
				events.append("%s upgraded to %d stars!" % [CardDatabase.get_unit(card_id).get("name", card_id), stars + 1])
				merged = true
				break
	return events


func remove_unit(u: UnitInstance) -> void:
	units.erase(u)


## Number of 1-star-equivalent cards this unit is worth (1 / 3 / 9) - used for sell refunds.
static func copies_value(stars: int) -> int:
	var table: Array = GameData.b("star_copies")
	return int(table[clampi(stars, 1, 3) - 1])


func count_of(card_id: String) -> int:
	var n := 0
	for u in units:
		if u.card_id == card_id:
			n += 1
	return n
