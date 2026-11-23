extends Node
## Autoload "GameData": read-only static data (balance, continents, champions, events).
## JSON is loaded through load() so it also works inside exported APKs
## (Godot imports .json as a JSON resource).

var balance: Dictionary = {}
var continents: Array = []
var champions: Dictionary = {}
var events: Array = []  # ACTIVE event deck of the continent being played (see apply_flavor)
var base_events: Array = []  # neutral deck from data/events.json
var continent_flavor: Dictionary = {}  # continent id -> {events: 12 cards, dice: 6 Special Dice}
var cards: Dictionary = {}
var card_buffs: Dictionary = {}  # continent id -> card id -> buff {name, type, value, desc}
var king_buffs: Dictionary = {}  # champion id -> buff {name, type, value, desc}; only active on the King's home continent
var king_passives: Dictionary = {}  # champion id -> battle passive {name, type, value, desc}; works on every continent
var special_dice: Array = []  # ACTIVE Special Dice of the continent being played (see apply_flavor)
var base_special_dice: Array = []  # neutral dice from data/special_dice.json
var monsters: Dictionary = {}  # continent id -> Array of 4 hidden territory monsters (data/monsters.json)
var map_skins: Dictionary = {}  # continent id -> {territory, battle, backdrop} look of the boards (data/map_skins.json, see MapSkin)
var deposits: Dictionary = {}  # continent id -> Array of 4 hidden deposits: 2 treasures + 2 mines (data/deposits.json)


func _ready() -> void:
	balance = _load_json("res://data/balance.json")
	continents = _load_json("res://data/continents.json").get("continents", [])
	champions = _load_json("res://data/champions.json")
	base_events = _load_json("res://data/events.json").get("events", [])
	continent_flavor = _load_json("res://data/continent_flavor.json").get("continents", {})
	cards = _load_json("res://data/cards.json")
	card_buffs = _load_json("res://data/card_buffs.json")
	king_buffs = _load_json("res://data/king_buffs.json")
	king_passives = _load_json("res://data/king_passives.json")
	base_special_dice = _load_json("res://data/special_dice.json").get("dice", [])
	monsters = _load_json("res://data/monsters.json").get("continents", {})
	deposits = _load_json("res://data/deposits.json").get("continents", {})
	map_skins = _load_json("res://data/map_skins.json").get("continents", {})
	apply_flavor("")


func _load_json(path: String) -> Dictionary:
	var res = load(path)
	if res is JSON and res.data is Dictionary:
		return res.data
	push_error("GameData: cannot load %s" % path)
	return {}


## The 4 monsters of a continent (one per region, index = region).
func get_monsters(continent_id: String) -> Array:
	return monsters.get(continent_id, [])


## A monster of ANY continent by id ({} if unknown).
func get_monster(monster_id: String) -> Dictionary:
	for cid in monsters:
		for m in monsters[cid]:
			if String(m["id"]) == monster_id:
				return m
	return {}


## Raw skin of a continent ({} = original look, see MapSkin.get_skin for the resolved one).
func get_map_skin(continent_id: String) -> Dictionary:
	return map_skins.get(continent_id, {})


## The hidden treasures and mines of a continent.
func get_deposits(continent_id: String) -> Array:
	return deposits.get(continent_id, [])


## A deposit of ANY continent by id ({} if unknown).
func get_deposit(deposit_id: String) -> Dictionary:
	for cid in deposits:
		for d in deposits[cid]:
			if String(d["id"]) == deposit_id:
				return d
	return {}


## Balance lookup. Every tunable number of the economy lives in data/balance.json.
func b(key: String, default_value: Variant = 0) -> Variant:
	return balance.get(key, default_value)


## Starting (= maximum) Life for a match difficulty: easy 5 / normal 3 / hard 1 (balance.json "life_by_difficulty").
func life_for(difficulty: String) -> int:
	var t: Dictionary = balance.get("life_by_difficulty", {})
	return int(t.get(difficulty, balance.get("start_life", 3)))


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


## Home-continent rule: a faction may be played on any continent (outside Journey), but its faction bonuses
## (Champion passive + Faction Synergy) only apply on the continent the faction belongs to.
func is_home_faction(faction_id: String, continent_id: String) -> bool:
	return faction_id != "" and not get_faction(continent_id, faction_id).is_empty()


## A faction of ANY continent (the player's faction comes from the Deck and can belong to another continent than the match).
func find_faction(faction_id: String) -> Dictionary:
	for c in continents:
		for f in c.get("factions", []):
			if f["id"] == faction_id:
				return f
	return {}


## Activates the event deck and the Special Dice of a continent (data/continent_flavor.json). Every continent has its OWN
## 12 event cards and 6 Special Dice (different names, effects and values). An unknown / empty id gives the neutral base sets.
func apply_flavor(continent_id: String) -> void:
	var fl: Dictionary = continent_flavor.get(continent_id, {})
	events = []
	for e in fl.get("events", base_events):
		events.append((e as Dictionary).duplicate(true))
	special_dice = []
	for d in fl.get("dice", base_special_dice):
		special_dice.append((d as Dictionary).duplicate(true))


func get_special_die(id: String) -> Dictionary:
	for d in special_dice:
		if d["id"] == id:
			return d
	return {}


func get_champion(id: String) -> Dictionary:
	return champions.get(id, {})
