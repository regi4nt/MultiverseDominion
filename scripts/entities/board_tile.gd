class_name BoardTile
extends RefCounted
## One of the 100 perimeter tiles of a Territory Board.

enum Type { CORNER, TERRITORY, PORTAL, SHOP, EVENT, AUCTION, TAX, SPECIAL }

var index: int = 0
var type: Type = Type.TERRITORY
var name: String = ""
var region: int = -1  # 0 North, 1 East, 2 South, 3 West, -1 for corners
var region_order: int = -1  # 0..9 for territories
var price: int = 0
var owner_id: int = -1
var portal_active: bool = false
var corner_kind: String = ""  # start | sanctuary | rift | crossroads


func type_name() -> String:
	return Type.keys()[type].capitalize()


func is_territory() -> bool:
	return type == Type.TERRITORY
