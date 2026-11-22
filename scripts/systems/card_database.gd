class_name CardDatabase
extends RefCounted
## Read-only access to data/cards.json (unit types + support cards).
## Deck composition (per player): 15 unit types x 9 copies = 135, 1 Champion (King), 15 Support = 151.

const CHESS_ORDER: Array[String] = ["pawn", "rook", "knight", "bishop", "queen"]
const CAPACITY := {"king": 6, "queen": 4, "bishop": 2, "knight": 2, "rook": 2, "pawn": 1}
const EXPECTED_TYPES := {"pawn": 8, "rook": 2, "knight": 2, "bishop": 2, "queen": 1}
const SUPPORT_CATEGORIES: Array[String] = ["Creation", "Transformation", "Magic", "Artifact", "Skill", "Blessing", "Contract"]


## Continent whose factions the unit cards currently belong to (set by MatchController.setup, menus).
static var active_continent: String = "aetherion"
static var _cache: Dictionary = {}  # continent_id -> {"list": Array, "map": Dictionary}


static func set_continent(id: String) -> void:
	if not GameData.get_continent(id).is_empty():
		active_continent = id


## The 15 unit archetypes are shared by all continents. Each card has a faction "slot" (0..3);
## on another continent the card belongs to that continent's faction in the same slot and its
## name is prefixed with the faction (TODO: unique names and art per continent).
static func _resolved(continent_id: String) -> Dictionary:
	if _cache.has(continent_id):
		return _cache[continent_id]
	var list: Array = []
	var map := {}
	var cont := GameData.get_continent(continent_id)
	var facs: Array = cont.get("factions", [])
	for raw in GameData.cards.get("units", []):
		var u: Dictionary = raw
		if continent_id != "aetherion" and facs.size() == 4:
			u = raw.duplicate(true)
			var f: Dictionary = facs[int(raw.get("slot", 0))]
			u["faction"] = f["id"]
			u["base_name"] = raw["name"]
			u["name"] = "%s %s" % [f["name"], raw["name"]]
		list.append(u)
		map[u["id"]] = u
	_cache[continent_id] = {"list": list, "map": map}
	return _cache[continent_id]


static func all_units() -> Array:
	return _resolved(active_continent)["list"]


static func all_supports() -> Array:
	return GameData.cards.get("supports", [])


static func get_unit(id: String) -> Dictionary:
	return _resolved(active_continent)["map"].get(id, {})


static func get_support(id: String) -> Dictionary:
	for s in all_supports():
		if s["id"] == id:
			return s
	return {}


static func is_unit(id: String) -> bool:
	return not get_unit(id).is_empty()


static func is_support(id: String) -> bool:
	return not get_support(id).is_empty()


static func units_of_chess(chess: String) -> Array:
	var out: Array = []
	for u in all_units():
		if u["chess"] == chess:
			out.append(u)
	return out


static func capacity_cost(chess: String) -> int:
	return int(CAPACITY.get(chess, 0))


## HP / ATK of a unit at a star level (1..3).
static func unit_stats(id: String, stars: int) -> Dictionary:
	var u := get_unit(id)
	if u.is_empty():
		return {}
	var i := clampi(stars, 1, 3) - 1
	var hp_mult: Array = GameData.b("star_hp_mult")
	var atk_mult: Array = GameData.b("star_atk_mult")
	return {
		"hp": int(round(float(u["hp"]) * float(hp_mult[i]))),
		"atk": int(round(float(u["atk"]) * float(atk_mult[i]))),
	}


static func default_support_ids() -> Array[String]:
	var out: Array[String] = []
	for s in all_supports():
		if s.get("owned_default", false):
			out.append(s["id"])
	return out


## Returns a list of problems with the card database (empty = OK).
static func validate_database() -> Array[String]:
	var errors: Array[String] = []
	var counts := {}
	var seen := {}
	for u in all_units():
		counts[u["chess"]] = int(counts.get(u["chess"], 0)) + 1
		if seen.has(u["id"]):
			errors.append("duplicate id " + u["id"])
		seen[u["id"]] = true
		for k in ["name", "faction", "slot", "role", "rarity", "hp", "atk", "range", "move", "skill"]:
			if not u.has(k):
				errors.append("%s missing %s" % [u["id"], k])
	for k in EXPECTED_TYPES:
		if int(counts.get(k, 0)) != int(EXPECTED_TYPES[k]):
			errors.append("expected %d %s types, found %d" % [EXPECTED_TYPES[k], k, counts.get(k, 0)])
	var cats := {}
	for s in all_supports():
		cats[s["category"]] = true
		if seen.has(s["id"]):
			errors.append("duplicate id " + s["id"])
		seen[s["id"]] = true
	for c in SUPPORT_CATEGORIES:
		if not cats.has(c):
			errors.append("no support in category " + c)
	return errors
