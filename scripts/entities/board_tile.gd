class_name BoardTile
extends RefCounted
## One of the 100 perimeter tiles of a Territory Board.

enum Type { CORNER, TERRITORY, PORTAL, SHOP, EVENT, AUCTION, TAX, SPECIAL, BANK, CASINO }

var index: int = 0
var type: Type = Type.TERRITORY
var name: String = ""
var region: int = -1  # 0 North, 1 East, 2 South, 3 West, -1 for corners
var region_order: int = -1  # 0..9 for territories
var price: int = 0
var owner_id: int = -1
var portal_active: bool = false
var corner_kind: String = ""  # start | sanctuary | rift | crossroads
var lease_left: int = 0  # > 0 = the owner only LEASES this land: rounds left until it is free again (see MatchController._do_lease)
var lease_paid: int = 0  # gold paid for the lease; it counts toward buying the land out
var level: int = 0  # 0 = plain land, 1..max_tile_level = upgraded; the last level is the Landmark


func type_name() -> String:
	return Type.keys()[type].capitalize()


func is_territory() -> bool:
	return type == Type.TERRITORY


func is_leased() -> bool:
	return type == Type.TERRITORY and owner_id >= 0 and lease_left > 0


func is_landmark() -> bool:
	return type == Type.TERRITORY and level >= int(GameData.b("max_tile_level"))


func level_label() -> String:
	if level <= 0:
		return ""
	return "Landmark" if is_landmark() else "Lv %d" % level
