class_name CardDatabase
extends RefCounted
## Read-only access to data/cards.json (unit types + support cards).
## Deck composition (per player): 15 unit types x 9 copies = 135, 1 Champion (King, Legendary), 15 Support = 151.
## The 15 unit types of a deck = the 8 Pawns of the continent + the 7 own pieces (2 Rook, 2 Knight, 2 Bishop, Queen) of the player's faction.

const CHESS_ORDER: Array[String] = ["pawn", "rook", "knight", "bishop", "queen"]
const CAPACITY := {"king": 6, "queen": 4, "bishop": 2, "knight": 2, "rook": 2, "pawn": 1}
## Types of ONE faction's own pieces (the Pawns are counted per continent: 2 per faction, 8 in total).
const FACTION_PIECES := {"rook": 2, "knight": 2, "bishop": 2, "queen": 1}
const FACTION_PIECE_ORDER: Array[String] = ["rook", "rook", "knight", "knight", "bishop", "bishop", "queen"]
## Faction id of a piece that belongs to no faction. Unused by the current card set (every Rook/Knight/Bishop/Queen is
## unique to ONE faction), kept so that a card with this faction still counts for the side that fields it.
const SHARED := "common"
## Allowed deviation of a faction piece from the base values of its slot: HP / ATK (power = HP x ATK stays balanced).
const STAT_TOLERANCE := 0.16
const POWER_TOLERANCE := 0.08
## Per-piece-slot base values (hp, atk) and mechanic: the 7 slots of a faction's own pieces.
const SLOT_BASE := [
	{"chess": "rook", "role": "Tank", "hp": 220, "atk": 12, "range": 1, "move": 2, "mechanic": "bulwark"},
	{"chess": "rook", "role": "Marksman", "hp": 180, "atk": 16, "range": 2, "move": 2, "mechanic": "ballista_volley"},
	{"chess": "knight", "role": "Fighter", "hp": 150, "atk": 18, "range": 1, "move": 3, "mechanic": "charge"},
	{"chess": "knight", "role": "Assassin", "hp": 120, "atk": 22, "range": 1, "move": 3, "mechanic": "night_gallop"},
	{"chess": "bishop", "role": "Mage", "hp": 100, "atk": 20, "range": 4, "move": 2, "mechanic": "arcane_barrage"},
	{"chess": "bishop", "role": "Support", "hp": 110, "atk": 10, "range": 3, "move": 2, "mechanic": "blessed_mend"},
	{"chess": "queen", "role": "Fighter", "hp": 260, "atk": 26, "range": 2, "move": 4, "mechanic": "sovereign_decree"}]
## Per-continent skill numbers (skill.params) the engine reads, by base mechanic (see BattleEngine._p).
const PARAM_KEYS := {
	"bulwark": ["taunt_ticks"], "ballista_volley": ["interval", "targets"], "charge": ["stun_ticks"],
	"night_gallop": ["strike_bonus"], "arcane_barrage": ["every", "splash_pct"], "blessed_mend": ["interval", "heal_pct"]}
## Effect types of the card buffs (data/card_buffs.json); every unit card has one buff per continent. Implemented in BattleEngine.
const BUFF_TYPES: Array[String] = [
	"armor", "evade", "thorns", "execute", "frenzy", "aura_atk", "burn", "stun_proc", "ward", "splash", "lifesteal", "chill",
	"opener", "rage", "last_rites", "death_burst", "mend_self", "swift", "guard", "opening_shield", "regen", "second_life"]
const SUPPORT_CATEGORIES: Array[String] = ["Creation", "Transformation", "Magic", "Artifact", "Skill", "Blessing", "Contract"]


## Continent whose factions the unit cards currently belong to (set by MatchController.setup, menus).
static var active_continent: String = "aetherion"
static var _cache: Dictionary = {}  # continent_id -> {"list": Array, "map": Dictionary}
static var _global_map: Dictionary = {}  # card id -> raw unit of ANY continent (lookup fallback, save compatibility)


static func set_continent(id: String) -> void:
	if not GameData.get_continent(id).is_empty():
		active_continent = id


## The 15 unit archetypes exist on every continent. Each Pawn has a faction "slot" (0..3);
## on another continent the Pawn belongs to that continent's faction in the same slot and its
## name is prefixed with the faction.
## The 7 other pieces (Rook x2, Knight x2, Bishop x2, Queen) have slot -1 and belong to ONE faction of ONE continent
## (fields "faction" and "continent"): every faction has its own 7 (own names, skills, skill numbers, buffs and
## slightly different HP / ATK around the base values of SLOT_BASE). A card without "continent" (the Pawns) exists on every continent.
static func _resolved(continent_id: String) -> Dictionary:
	if _cache.has(continent_id):
		return _cache[continent_id]
	var list: Array = []
	var map := {}
	var cont := GameData.get_continent(continent_id)
	var facs: Array = cont.get("factions", [])
	for raw in GameData.cards.get("units", []):
		if not _on_continent(raw, continent_id):
			continue
		var u: Dictionary = raw
		if continent_id != "aetherion" and facs.size() == 4 and int(raw.get("slot", 0)) >= 0:
			u = raw.duplicate(true)
			var f: Dictionary = facs[int(raw.get("slot", 0))]
			u["faction"] = f["id"]
			u["base_name"] = raw["name"]
			u["name"] = "%s %s" % [f["name"], raw["name"]]
		list.append(u)
		map[u["id"]] = u
	_cache[continent_id] = {"list": list, "map": map}
	return _cache[continent_id]


## True when the raw card is part of the given continent's card set (cards without "continent" belong to all).
static func _on_continent(raw: Dictionary, continent_id: String) -> bool:
	var c := String(raw.get("continent", ""))
	return c == "" or c == continent_id


## Raw units of every continent by id. Used to resolve a card id that belongs to another continent
## (an old save, a card shown outside its continent).
## Cards of the old "shared pieces" set (before every faction got its own pieces) resolve to the first faction's
## piece of the same continent and slot ("legacy_ids" in data/cards.json): an old save / match in progress keeps working.
static func canonical_id(id: String) -> String:
	return String((GameData.cards.get("legacy_ids", {}) as Dictionary).get(id, id))


static func _all_raw() -> Dictionary:
	if _global_map.is_empty():
		for raw in GameData.cards.get("units", []):
			_global_map[raw["id"]] = raw
	return _global_map


## Every unit card id of every continent (15 per continent; the 8 Pawns are counted once).
static func all_unit_ids_any_continent() -> Array[String]:
	var out: Array[String] = []
	for raw in GameData.cards.get("units", []):
		out.append(String(raw["id"]))
	return out


static func is_shared(card: Dictionary) -> bool:
	return String(card.get("faction", "")) == SHARED


## The faction a unit fights for: a Pawn its own, a shared piece the faction of its side (the Champion's faction).
static func effective_faction(card: Dictionary, side_faction: String) -> String:
	return side_faction if is_shared(card) else String(card.get("faction", ""))


static func all_units() -> Array:
	return _resolved(active_continent)["list"]


static func all_supports() -> Array:
	return GameData.cards.get("supports", [])


static func get_unit(id: String) -> Dictionary:
	id = canonical_id(id)
	var u: Dictionary = _resolved(active_continent)["map"].get(id, {})
	if u.is_empty():
		return _all_raw().get(id, {})  # a piece of another continent keeps its own data
	return u


## The buff of a unit card: its own continent for a continent-specific piece, else the active continent
## (the 8 Pawns exist on every continent, with a different buff on each). {} if there is none.
static func get_buff(id: String) -> Dictionary:
	id = canonical_id(id)
	var cont := String(_all_raw().get(id, {}).get("continent", active_continent))
	return GameData.card_buffs.get(cont, {}).get(id, {})


## The King's own buff ({} if none). `home_only`: {} unless the King's faction belongs to the ACTIVE continent.
static func king_buff(champion_id: String, home_only: bool = true) -> Dictionary:
	var bf: Dictionary = GameData.king_buffs.get(champion_id, {})
	if bf.is_empty() or not home_only:
		return bf
	var fac := String(GameData.get_champion(champion_id).get("faction", ""))
	return bf if GameData.is_home_faction(fac, active_continent) else {}


## True if the card id is part of the ACTIVE continent's 15 unit cards (get_unit also answers for other continents).
static func in_active_set(id: String) -> bool:
	return _resolved(active_continent)["map"].has(canonical_id(id))


## The 15 unit types of a faction's deck in the active continent: the 8 Pawns + the faction's own 7 pieces.
## An unknown faction (or one of another continent) yields the Pawns only.
static func faction_units(faction_id: String) -> Array:
	var out: Array = []
	for u in all_units():
		if u["chess"] == "pawn" or String(u["faction"]) == faction_id:
			out.append(u)
	return out


## Every unit card of one continent (8 Pawns + the 28 pieces of its 4 factions), whatever the active continent is.
static func units_of_continent(continent_id: String) -> Array:
	return _resolved(continent_id)["list"]


static func continent_unit_ids(continent_id: String) -> Array[String]:
	var out: Array[String] = []
	for u in units_of_continent(continent_id):
		out.append(String(u["id"]))
	return out


## The own pieces (Rook, Knight, Bishop, Queen) of a faction in the active continent, in slot order.
static func faction_pieces(faction_id: String) -> Array:
	var out: Array = []
	for u in all_units():
		if u["chess"] != "pawn" and String(u["faction"]) == faction_id:
			out.append(u)
	return out


## The King (Champion) of a faction as a card: it belongs to the faction like its 7 other pieces (8 pieces per faction).
## Same fields as a unit card so the Collection can draw it; its real battle stats live in data/champions.json.
static func king_card(champion_id: String) -> Dictionary:
	var ch := GameData.get_champion(champion_id)
	if ch.is_empty():
		return {}
	return {
		"id": champion_id, "name": ch["name"], "faction": ch["faction"], "continent": ch.get("continent", ""),
		"chess": "king", "role": "King", "slot": -1, "rarity": ch.get("rarity", "legendary"), "is_king": true,
		"hp": int(ch["hp"]), "atk": int(ch["atk"]), "range": 1, "move": 2,
		"skill": {"name": ch.get("active_name", ""), "desc": ch.get("active_desc", "")}}


## The King of one faction of the active continent ({} if unknown).
static func faction_king(faction_id: String) -> Dictionary:
	var f := GameData.get_faction(active_continent, faction_id)
	return king_card(String(f.get("champion", ""))) if not f.is_empty() else {}


## The 4 Kings (one per faction) of the active continent, in faction order.
static func all_kings() -> Array:
	var out: Array = []
	for f in GameData.get_continent(active_continent).get("factions", []):
		var k := king_card(String(f["champion"]))
		if not k.is_empty():
			out.append(k)
	return out


## Every own piece of a faction: Rook x2, Knight x2, Bishop x2, Queen and the King (8 pieces).
static func faction_roster(faction_id: String) -> Array:
	var out := faction_pieces(faction_id)
	var k := faction_king(faction_id)
	if not k.is_empty():
		out.append(k)
	return out


static func is_king(id: String) -> bool:
	return GameData.champions.has(id)


static func get_support(id: String) -> Dictionary:
	for s in all_supports():
		if s["id"] == id:
			return s
	return {}


static func is_unit(id: String) -> bool:
	return not get_unit(id).is_empty()


## Engine mechanic of a unit's skill: themed continent skills point at one of the base mechanics ("mechanic");
## the original cards use their own skill id.
static func skill_mechanic(card: Dictionary) -> String:
	var sk: Dictionary = card.get("skill", {})
	return String(sk.get("mechanic", sk.get("id", "")))


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


## Returns a list of problems with the card database of the ACTIVE continent (empty = OK).
static func validate_database() -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	var facs: Array = GameData.get_continent(active_continent).get("factions", [])
	var fac_ids: Array[String] = []
	for f in facs:
		fac_ids.append(String(f["id"]))
	for u in all_units():
		if seen.has(u["id"]):
			errors.append("duplicate id " + u["id"])
		seen[u["id"]] = true
		for k in ["name", "faction", "slot", "role", "rarity", "hp", "atk", "range", "move", "skill"]:
			if not u.has(k):
				errors.append("%s missing %s" % [u["id"], k])
		if not fac_ids.has(String(u.get("faction", ""))):
			errors.append("%s: faction %s is not a faction of %s" % [u["id"], u.get("faction", ""), active_continent])
	for fid in fac_ids:
		var pawn_n := 0
		var counts := {}
		for u in all_units():
			if String(u["faction"]) != fid:
				continue
			if u["chess"] == "pawn":
				pawn_n += 1
			else:
				counts[u["chess"]] = int(counts.get(u["chess"], 0)) + 1
		if pawn_n != 2:
			errors.append("faction %s has %d Pawn types, expected 2" % [fid, pawn_n])
		for k in FACTION_PIECES:
			if int(counts.get(k, 0)) != int(FACTION_PIECES[k]):
				errors.append("faction %s: expected %d %s, found %d" % [fid, FACTION_PIECES[k], k, counts.get(k, 0)])
	for u in all_units():
		if u["chess"] == "pawn" and is_shared(u):
			errors.append("%s: a Pawn must belong to one faction" % u["id"])
		elif u["chess"] != "pawn" and is_shared(u):
			errors.append("%s: Rook/Knight/Bishop/Queen must belong to ONE faction" % u["id"])
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


## Checks every continent's card set at once (empty = OK): 15 unit types per faction deck, every faction piece
## on its slot (role / range / move / mechanic, HP and ATK close to the slot base with a balanced HP x ATK),
## valid skill parameters, one valid and globally uniquely named buff per unit card, legacy ids resolve.
static func validate_all_continents() -> Array[String]:
	var errors: Array[String] = []
	var ids := {}
	for raw in GameData.cards.get("units", []):
		if ids.has(raw["id"]):
			errors.append("duplicate id " + String(raw["id"]))
		ids[raw["id"]] = true
	var buff_names := {}
	var piece_sigs := {}  # faction -> signature of its stats, to prove the factions really differ
	var prev := active_continent
	for cont in GameData.continents:
		active_continent = String(cont["id"])
		for f in cont["factions"]:
			var fid := String(f["id"])
			var deck_types := faction_units(fid)
			if deck_types.size() != 15:
				errors.append("%s: %d unit types in the deck, expected 15" % [fid, deck_types.size()])
			var pieces := faction_pieces(fid)
			if pieces.size() != 7:
				errors.append("%s: %d own pieces, expected 7" % [fid, pieces.size()])
				continue
			var sig := []
			for i in range(7):
				var u: Dictionary = pieces[i]
				var b: Dictionary = SLOT_BASE[i]
				if u["chess"] != b["chess"] or u["role"] != b["role"] or int(u["range"]) != int(b["range"]) or int(u["move"]) != int(b["move"]) or skill_mechanic(u) != b["mechanic"]:
					errors.append("%s: not the %s %s of its slot (chess/role/range/move/mechanic)" % [u["id"], b["role"], b["chess"]])
				var hp_r := float(u["hp"]) / float(b["hp"])
				var atk_r := float(u["atk"]) / float(b["atk"])
				if absf(hp_r - 1.0) > STAT_TOLERANCE or absf(atk_r - 1.0) > STAT_TOLERANCE or absf(hp_r * atk_r - 1.0) > POWER_TOLERANCE:
					errors.append("%s: HP/ATK out of balance (%d/%d vs base %d/%d)" % [u["id"], u["hp"], u["atk"], b["hp"], b["atk"]])
				sig.append([u["hp"], u["atk"], str(u["skill"].get("params", {}))])
			if piece_sigs.has(str(sig)):
				errors.append("%s: pieces identical to those of %s" % [fid, piece_sigs[str(sig)]])
			piece_sigs[str(sig)] = fid
		for u in all_units():
			var pr: Dictionary = u["skill"].get("params", {})
			var allowed: Array = PARAM_KEYS.get(skill_mechanic(u), [])
			for k in pr:
				if not allowed.has(k):
					errors.append("%s: unknown skill parameter '%s'" % [u["id"], k])
			var bf := get_buff(u["id"])
			if bf.is_empty() or not BUFF_TYPES.has(String(bf.get("type", ""))) or String(bf.get("name", "")) == "" or String(bf.get("desc", "")) == "":
				errors.append("%s: missing or invalid buff on %s" % [u["id"], cont["id"]])
			elif buff_names.has(bf["name"]):
				errors.append("duplicate buff name " + String(bf["name"]))
			else:
				buff_names[bf["name"]] = true
		errors.append_array(validate_database())
	active_continent = prev
	for cont in GameData.continents:  # every faction's King is a Legendary card
		for f in cont["factions"]:
			var ch := GameData.get_champion(String(f["champion"]))
			if ch.is_empty() or String(ch.get("rarity", "")) != "legendary" or String(ch.get("faction", "")) != String(f["id"]):
				errors.append("%s: the King must exist and be legendary" % f["champion"])
	prev = active_continent
	for cont in GameData.continents:  # the King is the 8th piece of its faction's roster
		active_continent = String(cont["id"])
		for f in cont["factions"]:
			var roster := faction_roster(String(f["id"]))
			if roster.size() != 8 or String(roster[7].get("chess", "")) != "king" or String(roster[7].get("faction", "")) != String(f["id"]):
				errors.append("%s: roster must be 7 pieces + its King" % f["id"])
	active_continent = prev
	for old in (GameData.cards.get("legacy_ids", {}) as Dictionary):
		if not ids.has(String(GameData.cards["legacy_ids"][old])):
			errors.append("legacy id %s points at an unknown card" % old)
	return errors
