extends Node
## Autoload "GameData": read-only static data (balance, continents, champions, events).
## JSON is loaded through load() so it also works inside exported APKs
## (Godot imports .json as a JSON resource).

var balance: Dictionary = {}
var continents: Array = []
var champions: Dictionary = {}
var events: Array = []
var cards: Dictionary = {}
var card_buffs: Dictionary = {}  # continent id -> card id -> buff {name, type, value, desc}
var special_dice: Array = []


func _ready() -> void:
	balance = _load_json("res://data/balance.json")
	continents = _load_json("res://data/continents.json").get("continents", [])
	champions = _load_json("res://data/champions.json")
	events = _load_json("res://data/events.json").get("events", [])
	cards = _load_json("res://data/cards.json")
	card_buffs = _load_json("res://data/card_buffs.json")
	special_dice = _load_json("res://data/special_dice.json").get("dice", [])


func _load_json(path: String) -> Dictionary:
	var res = load(path)
	if res is JSON and res.data is Dictionary:
		return res.data
	push_error("GameData: cannot load %s" % path)
	return {}


## Balance lookup. Every tunable number of the economy lives in data/balance.json.
func b(key: String, default_value: Variant = 0) -> Variant:
	return balance.get(key, default_value)


func get_continent(id: String) -> Dictionary:
	for c in continents:
		if c["id"] == id:
			return c
	return {}


func get_faction(continent_id: String, faction_id: String) -> Dictionary:
	for f in get_continent(continent_id).get("factions", []):
		if f["id"] == faction_id:
			return f
	return {}


func get_special_die(id: String) -> Dictionary:
	for d in special_dice:
		if d["id"] == id:
			return d
	return {}


func get_champion(id: String) -> Dictionary:
	return champions.get(id, {})
