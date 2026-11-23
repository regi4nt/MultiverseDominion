class_name Deck
extends RefCounted
## Battle Deck configuration: 15 unit types x 9 copies + 1 Champion (King) + 15 chosen Support cards.
## The 15 unit types are chosen by the player from the unit cards of ONE continent (8 Pawns + the pieces of all 4 of its
## factions, factions can be mixed freely); the King and the Support cards are not tied to a continent.
## Without a custom list (`unit_ids` empty) the unit types are the default of the King's faction:
## the 8 Pawns of the continent + the 7 own pieces (2 Rook, 2 Knight, 2 Bishop, Queen).

const UNIT_SLOTS := 15

var champion_id: String = "champion_solvaris"
var support_ids: Array[String] = []
var continent_id: String = ""  # continent whose unit cards `unit_ids` come from ("" = the active continent)
var unit_ids: Array[String] = []  # the 15 chosen unit types; empty = default of the King's faction
## Custom lineup (Lineup tab): where each unit type stands on the deployment area; Auto Deploy follows it.
## Entries: {"id": unit card id, "x": column 0..7, "y": row 4..7}. Empty = the default AI formation.
var lineup: Array = []
## The player's collection (card id -> copies), set by SaveManager.get_deck: unit cards that are not owned (they come from the
## Shop) are never used. Empty = no restriction (AI decks, tests).
var owned_filter: Dictionary = {}


static func create_default() -> Deck:
	var d := Deck.new()
	d.support_ids = CardDatabase.default_support_ids()
	d.continent_id = CardDatabase.active_continent
	return d


func deck_continent() -> String:
	return continent_id if continent_id != "" else CardDatabase.active_continent


## Faction whose own pieces the DEFAULT unit list contains: the Champion's. A Champion of another continent than the active one
## (e.g. the default deck of a menu) falls back to the first faction of the active continent.
func faction_id() -> String:
	var ch := GameData.get_champion(champion_id)
	if String(ch.get("continent", "")) == CardDatabase.active_continent:
		return String(ch.get("faction", ""))
	var facs: Array = GameData.get_continent(CardDatabase.active_continent).get("factions", [])
	return String(facs[0]["id"]) if not facs.is_empty() else String(ch.get("faction", ""))


## The unit types of this deck: the custom list, or the default of the King's faction.
func effective_unit_ids() -> Array[String]:
	if not unit_ids.is_empty():
		return unit_ids.duplicate()
	var out: Array[String] = []
	for u in CardDatabase.faction_units(faction_id()):
		if is_owned(String(u["id"])):
			out.append(String(u["id"]))
	return out


func is_owned(id: String) -> bool:
	return owned_filter.is_empty() or int(owned_filter.get(id, 0)) > 0


## A custom unit list that holds a card the player does not own (any more) goes back to the default (owned) types.
func sanitize_owned() -> void:
	for id in unit_ids:
		if not is_owned(id):
			unit_ids = [] as Array[String]
			lineup = []
			return


func card_list() -> Array[String]:
	var out: Array[String] = []
	var copies := int(GameData.b("unit_copies"))
	for id in effective_unit_ids():
		for i in range(copies):
			out.append(id)
	out.append(champion_id)
	out.append_array(support_ids)
	return out


## Drops unit cards that do not belong to the deck's continent; a list that no longer has exactly 15 types goes back to the default.
func sanitize_units() -> void:
	if unit_ids.is_empty():
		return
	var valid := CardDatabase.continent_unit_ids(deck_continent())
	var clean: Array[String] = []
	for id in unit_ids:
		if valid.has(id) and not clean.has(id):
			clean.append(id)
	unit_ids = clean if clean.size() == UNIT_SLOTS else ([] as Array[String])


## Returns a list of problems (empty = valid). `collection` (card_id -> count) is optional.
func validate(collection: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	if GameData.get_champion(champion_id).is_empty():
		errors.append("Unknown champion.")
	var need := int(GameData.b("deck_support"))
	if support_ids.size() != need:
		errors.append("Support cards: %d / %d." % [support_ids.size(), need])
	var seen := {}
	for id in support_ids:
		if seen.has(id):
			errors.append("Duplicate support card: " + id)
		seen[id] = true
		if not CardDatabase.is_support(id):
			errors.append("Unknown support card: " + id)
		elif not collection.is_empty() and int(collection.get(id, 0)) < 1:
			errors.append("Support card not owned: " + id)
	if not unit_ids.is_empty():
		if unit_ids.size() != UNIT_SLOTS:
			errors.append("Unit cards: %d / %d." % [unit_ids.size(), UNIT_SLOTS])
		var valid := CardDatabase.continent_unit_ids(deck_continent())
		var seen_u := {}
		for id in unit_ids:
			if seen_u.has(id):
				errors.append("Duplicate unit card: " + id)
			seen_u[id] = true
			if not valid.has(id):
				errors.append("Unit card from another continent: " + id)
			elif not collection.is_empty() and int(collection.get(id, 0)) < 1:
				errors.append("Unit card not owned: " + id)
	if card_list().size() != int(GameData.b("deck_total")):
		errors.append("Deck must contain %d cards (has %d)." % [int(GameData.b("deck_total")), card_list().size()])
	return errors


## Lineup entries that are still usable: the unit type is in this deck, the cell is on the deployment area, one unit per cell.
func valid_lineup() -> Array:
	var types := effective_unit_ids()
	var seen := {}
	var out: Array = []
	for e in lineup:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id := String(e.get("id", ""))
		var cell := Vector2i(int(e.get("x", -1)), int(e.get("y", -1)))
		if not types.has(id) or cell.x < 0 or cell.x >= 8 or cell.y < 4 or cell.y > 7 or seen.has(cell):
			continue
		seen[cell] = true
		out.append({"id": id, "x": cell.x, "y": cell.y})
	return out


func to_dict() -> Dictionary:
	return {"champion": champion_id, "supports": support_ids.duplicate(), "continent": continent_id, "units": unit_ids.duplicate(), "lineup": lineup.duplicate(true)}


static func from_dict(d: Dictionary) -> Deck:
	var deck := Deck.new()
	deck.champion_id = String(d.get("champion", "champion_solvaris"))
	for id in d.get("supports", []):
		deck.support_ids.append(String(id))
	deck.continent_id = String(d.get("continent", ""))
	for id in d.get("units", []):
		deck.unit_ids.append(String(id))
	for e in d.get("lineup", []):
		if typeof(e) == TYPE_DICTIONARY:
			deck.lineup.append({"id": String(e.get("id", "")), "x": int(e.get("x", -1)), "y": int(e.get("y", -1))})
	return deck
