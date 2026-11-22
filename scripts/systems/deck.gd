class_name Deck
extends RefCounted
## Battle Deck configuration: fixed 15 unit types x 9 copies + 1 Champion + 15 chosen Support cards.

var champion_id: String = "champion_solvaris"
var support_ids: Array[String] = []


static func create_default() -> Deck:
	var d := Deck.new()
	d.support_ids = CardDatabase.default_support_ids()
	return d


func card_list() -> Array[String]:
	var out: Array[String] = []
	var copies := int(GameData.b("unit_copies"))
	for u in CardDatabase.all_units():
		for i in range(copies):
			out.append(u["id"])
	out.append(champion_id)
	out.append_array(support_ids)
	return out


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
	if card_list().size() != int(GameData.b("deck_total")):
		errors.append("Deck must contain %d cards (has %d)." % [int(GameData.b("deck_total")), card_list().size()])
	return errors


func to_dict() -> Dictionary:
	return {"champion": champion_id, "supports": support_ids.duplicate()}


static func from_dict(d: Dictionary) -> Deck:
	var deck := Deck.new()
	deck.champion_id = String(d.get("champion", "champion_solvaris"))
	for id in d.get("supports", []):
		deck.support_ids.append(String(id))
	return deck
