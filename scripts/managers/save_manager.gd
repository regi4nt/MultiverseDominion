extends Node
## Autoload "SaveManager": local JSON save (user://save.json).

signal saved
signal app_paused  # Android: the app goes to the background -> screens autosave

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const MATCH_PATH := "user://match.json"

var data: Dictionary = {}


func _ready() -> void:
	load_game()
	ensure_collection()
	apply_settings()


func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"profile": {"name": "Player", "level": 1, "xp": 0, "tutorial_done": false},
		"settings": {"master_volume": 0.8, "default_difficulty": "normal", "sfx": true, "check_updates": true, "skipped_update": ""},
		"campaign": {"progress": 0},  # TODO (Phase 6): Story Campaign
		"unlocked_continents": ["aetherion"],
		"unlocked_factions": ["solvaris", "nocthyr", "valdoria", "elarion"],
		"collection": {},  # TODO (Phase 3): Card Collection
		"decks": {},  # TODO (Phase 3): Deck Configuration
		"stats": {"matches_played": 0, "wins": 0, "losses": 0, "total_rounds": 0, "best_gold": 0},
		"wallet": {"coins": 600},  # Aether Coins: persistent Shop currency (see ShopSystem)
		"shop": {"pity": 0, "pulls": 0},
	}


func load_game() -> void:
	data = default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		save_game()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("SaveManager: cannot open save file")
		return
	var parsed = _parse(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_merge(data, parsed)
	else:
		push_warning("SaveManager: corrupt save, using defaults")


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write save file")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	saved.emit()


## JSON.parse_string logs an engine error for broken text; this returns null silently.
func _parse(text: String) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


## Recursively copies saved values over the defaults (keeps new default keys after updates).
func _merge(base: Dictionary, incoming: Dictionary) -> void:
	for k in incoming.keys():
		if base.has(k) and base[k] is Dictionary and incoming[k] is Dictionary:
			_merge(base[k], incoming[k])
		else:
			base[k] = incoming[k]


func get_setting(key: String) -> Variant:
	return data["settings"].get(key)


func set_setting(key: String, value: Variant, persist: bool = true) -> void:
	data["settings"][key] = value
	apply_settings()
	if persist:
		save_game()


func apply_settings() -> void:
	var v: float = clampf(float(data["settings"].get("master_volume", 0.8)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))


func is_continent_unlocked(id: String) -> bool:
	return (data["unlocked_continents"] as Array).has(id)


func is_faction_unlocked(id: String) -> bool:
	return (data["unlocked_factions"] as Array).has(id)


func unlock_continent(id: String) -> void:
	if not (data["unlocked_continents"] as Array).has(id):
		data["unlocked_continents"].append(id)
	for f in GameData.get_continent(id).get("factions", []):
		if not (data["unlocked_factions"] as Array).has(f["id"]):
			data["unlocked_factions"].append(f["id"])


## Winning a match on a continent unlocks the next one in the list (Story Campaign is a TODO).
## Aether Coins (Shop currency).
func coins() -> int:
	return int(data["wallet"].get("coins", 0))


func add_coins(n: int) -> void:
	data["wallet"]["coins"] = maxi(0, coins() + n)


## Pays `n` coins; false (and nothing paid) when the player has less.
func spend_coins(n: int) -> bool:
	if n < 0 or coins() < n:
		return false
	data["wallet"]["coins"] = coins() - n
	return true


## Adds one copy of a card to the collection if it is not owned yet. Returns true when it was new.
func unlock_card(card_id: String) -> bool:
	if owned_count(card_id) > 0:
		return false
	data["collection"][card_id] = 1
	return true


## Coins earned by the last record_match (shown on the result screen).
var last_reward: int = 0


## Every victory unlocks the next locked Support card. Returns its id ("" when everything is unlocked).
func unlock_next_card() -> String:
	for s in CardDatabase.all_supports():
		if owned_count(s["id"]) == 0:
			data["collection"][s["id"]] = 1
			return String(s["id"])
	return ""


## Returns the id of the card unlocked by this result ("" if none).
func record_match(won: bool, rounds: int, final_gold: int, continent_id: String = "") -> String:
	var s: Dictionary = data["stats"]
	s["matches_played"] += 1
	s["total_rounds"] += rounds
	if won:
		s["wins"] += 1
	else:
		s["losses"] += 1
	s["best_gold"] = maxi(int(s["best_gold"]), final_gold)
	if won and continent_id != "":
		for i in range(GameData.continents.size() - 1):
			if GameData.continents[i]["id"] == continent_id:
				unlock_continent(GameData.continents[i + 1]["id"])
	last_reward = ShopSystem.WIN_REWARD if won else ShopSystem.LOSS_REWARD
	add_coins(last_reward)
	var card := unlock_next_card() if won else ""
	save_game()
	return card


## Fills the starter collection (all unit cards of every continent x 9, 15 default Support cards) and main deck.
func ensure_collection() -> void:
	var changed := false
	var col: Dictionary = data["collection"]
	if col.is_empty():
		for id in CardDatabase.all_unit_ids_any_continent():
			col[id] = int(GameData.b("unit_copies"))
		for s in CardDatabase.all_supports():
			if s.get("owned_default", false):
				col[s["id"]] = 1
		changed = true
	else:  # older saves: add the unit cards of continents that did not exist yet (per-continent Rook/Knight/Bishop/Queen)
		for id in CardDatabase.all_unit_ids_any_continent():
			if not col.has(id):
				col[id] = int(GameData.b("unit_copies"))
				changed = true
	if not (data["decks"] as Dictionary).has("main"):
		data["decks"]["main"] = Deck.create_default().to_dict()
		changed = true
	for cid in (data["unlocked_continents"] as Array).duplicate():
		unlock_continent(cid)
	if changed:
		save_game()


func owned_count(card_id: String) -> int:
	return int(data["collection"].get(card_id, 0))


## The player's deck for a continent. King and Support cards are shared by every continent; the 15 unit types are saved per
## continent ("units_by_continent"). No saved list (or an invalid one) = the default units of the King's faction.
func get_deck(continent_id: String = "") -> Deck:
	var cid := continent_id if continent_id != "" else CardDatabase.active_continent
	var main: Dictionary = data["decks"].get("main", {})
	var ubc: Dictionary = main.get("units_by_continent", {})
	var deck := Deck.from_dict({"champion": main.get("champion", "champion_solvaris"), "supports": main.get("supports", []),
		"continent": cid, "units": ubc.get(cid, [])})
	deck.sanitize_units()
	return deck


func set_deck(deck: Deck) -> void:
	var main: Dictionary = data["decks"].get("main", {})
	var ubc: Dictionary = main.get("units_by_continent", {})
	ubc[deck.deck_continent()] = deck.unit_ids.duplicate() if deck.unit_ids.size() == Deck.UNIT_SLOTS else []
	data["decks"]["main"] = {"champion": deck.champion_id, "supports": deck.support_ids.duplicate(), "units_by_continent": ubc}
	save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		save_game()
		app_paused.emit()


# ------------------------------------------------------------------ match save (resume after the OS kills the app)

## Saves a match at a stable moment only (start of a turn / end of a turn). Returns false otherwise.
func save_match(ctrl: MatchController) -> bool:
	var d := ctrl.to_dict()
	if d.is_empty():
		return false
	var tmp := MATCH_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot write match save")
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	if FileAccess.file_exists(MATCH_PATH):
		DirAccess.remove_absolute(MATCH_PATH)
	DirAccess.rename_absolute(tmp, MATCH_PATH)
	return true


## Returns {} when there is no (valid) saved match. A corrupt file is deleted.
func load_match() -> Dictionary:
	var path := MATCH_PATH
	if not FileAccess.file_exists(path) and FileAccess.file_exists(MATCH_PATH + ".tmp"):
		path = MATCH_PATH + ".tmp"  # the app died between writing and renaming
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = _parse(f.get_as_text())
	f.close()
	if parsed is Dictionary and int(parsed.get("version", 0)) == MatchController.SAVE_FORMAT and parsed.has("players") and parsed.has("tiles"):
		return parsed
	push_warning("SaveManager: corrupt match save removed")
	clear_match()
	return {}


func has_match() -> bool:
	return not load_match().is_empty()


func clear_match() -> void:
	for p in [MATCH_PATH, MATCH_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func match_summary() -> String:
	var d := load_match()
	if d.is_empty():
		return ""
	return "%s - round %d" % [String(GameData.get_continent(String(d["continent_id"])).get("name", "?")), int(d["round"])]
