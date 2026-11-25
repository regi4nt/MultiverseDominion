class_name Deck
extends RefCounted
## Battle Deck configuration: 15 unit types x 9 copies + 1 Champion (King) + 15 chosen Support cards.
## The 15 unit types are chosen by the player from the unit cards of ANY continent (the 8 Pawns + the pieces of all 28 factions,
## continents and factions can be mixed freely; a line-up with units of all 7 continents switches on the Continent Bond); the King and the Support cards are not tied to a continent.
## Without a custom list (`unit_ids` empty) the unit types are the default of the King's faction:
## the 8 Pawns of the continent + the 7 own pieces (2 Rook, 2 Knight, 2 Bishop, Queen).

const UNIT_SLOTS := 15

var champion_id: String = "champion_solvaris"
var support_ids: Array[String] = []
var continent_id: String = ""  # continent this deck belongs to (save key, Pawn faction slots); `unit_ids` may hold cards of any continent ("" = the active continent)
var unit_ids: Array[String] = []  # the 15 chosen unit types; empty = default of the King's faction
## Custom lineup (Lineup tab): where each unit type stands on the deployment area; Auto Deploy follows it.
## Entries: {"id": unit card id, "x": column 0..7, "y": row 4..7}. Empty = the default AI formation.
var lineup: Array = []
## Support lineup (Lineup tab): the Support cards of the deck in the order they are listed in battle (slot 0 first).
## One String per slot, "" = empty slot; a card can sit in one slot only.
var support_lineup: Array = []
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
	if String(ch.get("continent", "")) == deck_continent():
		return String(ch.get("faction", ""))
	var facs: Array = GameData.get_continent(deck_continent()).get("factions", [])
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


## Drops unknown unit cards (cards of any continent are fine); a list that no longer has exactly 15 types goes back to the default.
func sanitize_units() -> void:
	if unit_ids.is_empty():
		return
	var valid := CardDatabase.any_unit_ids()
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
		var valid := CardDatabase.any_unit_ids()
		var seen_u := {}
		for id in unit_ids:
			if seen_u.has(id):
				errors.append("Duplicate unit card: " + id)
			seen_u[id] = true
			if not valid.has(id):
				errors.append("Unknown unit card: " + id)
			elif not collection.is_empty() and int(collection.get(id, 0)) < 1:
				errors.append("Unit card not owned: " + id)
	if card_list().size() != int(GameData.b("deck_total")):
		errors.append("Deck must contain %d cards (has %d)." % [int(GameData.b("deck_total")), card_list().size()])
	return errors


## Lineup entries that are still usable: the unit type is in this deck, the cell is on the deployment area, one unit per cell.
func valid_lineup() -> Array:
	var types := effective_unit_ids()
	var seen := {}
	var used_ids := {}  # each unit may be placed only once: copies of a unit are dropped
	var out: Array = []
	for e in lineup:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var id := String(e.get("id", ""))
		var cell := Vector2i(int(e.get("x", -1)), int(e.get("y", -1)))
		if not types.has(id) or cell.x < 0 or cell.x >= 8 or cell.y < 4 or cell.y > 7 or seen.has(cell) or used_ids.has(id):
			continue
		seen[cell] = true
		used_ids[id] = true
		out.append({"id": id, "x": cell.x, "y": cell.y})
	return out


## The support lineup with only Support cards of the deck, no copies, one slot per card of the battle hand (`hand_max`, "" = empty).
func valid_support_lineup() -> Array:
	var slots := maxi(int(GameData.b("hand_max")), 1)
	var out: Array = []
	var used := {}
	for i in range(slots):
		var id := String(support_lineup[i]) if i < support_lineup.size() else ""
		if id != "" and (not support_ids.has(id) or used.has(id)):
			id = ""
		if id != "":
			used[id] = true
		out.append(id)
	return out


## True when the player filled the Lineup tab (any unit on the grid or any Support card in the slots).
func has_lineup() -> bool:
	if not valid_lineup().is_empty():
		return true
	for id in valid_support_lineup():
		if String(id) != "":
			return true
	return false


## Where a unit card stands in the Lineup grid: Vector2i(column, row 4..7), or Vector2i(-1, -1) when it is not in the lineup.
func lineup_cell_of(id: String) -> Vector2i:
	for e in valid_lineup():
		if String(e["id"]) == id:
			return Vector2i(int(e["x"]), int(e["y"]))
	return Vector2i(-1, -1)


## Slot (0-based) of a Support card in the Support lineup, -1 when it is not in the lineup.
func support_slot_of(id: String) -> int:
	return valid_support_lineup().find(id) if id != "" else -1


## True when at least one Support slot of the Lineup tab is filled.
func has_support_lineup() -> bool:
	for id in valid_support_lineup():
		if String(id) != "":
			return true
	return false


## A Battle Shop offer the Lineup recommends: only Support cards, those placed in the Support slots of the Lineup tab.
## Nothing is recommended while the Support slots are empty (units are never recommended).
func is_lineup_pick(id: String) -> bool:
	if id == "" or not BattlePrep.is_support_id(id) or not has_support_lineup():
		return false
	return support_slot_of(id) >= 0


## Tooltip / hint of a recommended offer ("" = not recommended).
func lineup_hint(id: String) -> String:
	if not is_lineup_pick(id):
		return ""
	return "Recommended by your lineup: Support slot %d." % (support_slot_of(id) + 1)


## A hand in battle order: cards of the support lineup first (slot order), then the rest in their own order.
func order_hand(hand: Array) -> Array:
	var out: Array = []
	var rest: Array = hand.duplicate()
	for id in valid_support_lineup():
		if id != "" and rest.has(id):
			out.append(id)
			rest.erase(id)
	out.append_array(rest)
	return out


func to_dict() -> Dictionary:
	return {"champion": champion_id, "supports": support_ids.duplicate(), "continent": continent_id, "units": unit_ids.duplicate(), "lineup": lineup.duplicate(true), "support_lineup": support_lineup.duplicate()}


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
	for id in d.get("support_lineup", []):
		deck.support_lineup.append(String(id))
	return deck
