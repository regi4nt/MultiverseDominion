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
		"settings": {"master_volume": 0.8, "default_difficulty": "normal", "sfx": true, "check_updates": true, "skipped_update": "", "fullscreen": false},
		"campaign": {"progress": 0},  # TODO (Phase 6): Story Campaign
		"unlocked_continents": ["aetherion"],
		"journey_wins": {},  # continent id -> ids of the factions that won a Journey match on it
		"unlocked_factions": ["solvaris", "nocthyr", "valdoria", "elarion"],
		"collection": {},  # TODO (Phase 3): Card Collection
		"decks": {},  # TODO (Phase 3): Deck Configuration
		"stats": {"matches_played": 0, "wins": 0, "losses": 0, "total_rounds": 0, "best_gold": 0},
		"wallet": {"coins": 600, "fragments": 0},  # Aether Coins + Card Fragments (Gacha duplicates): persistent Shop currencies (see ShopSystem)
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
	_apply_fullscreen(bool(data["settings"].get("fullscreen", false)))


## Default OFF. Skipped in headless runs (tests).
func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


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


## Journey progress. Only the first continent is open at the start. Winning a Journey match on a continent with each of ITS
## 4 factions masters it, and every mastered continent earns one pick: the player chooses which locked continent to open.
func journey_won_factions(continent_id: String) -> Array:
	var out: Array = []
	var won: Array = (data.get("journey_wins", {}) as Dictionary).get(continent_id, [])
	for f in GameData.get_continent(continent_id).get("factions", []):
		if won.has(f["id"]):
			out.append(f["id"])
	return out


func journey_faction_total(continent_id: String) -> int:
	var n := 0
	for f in GameData.get_continent(continent_id).get("factions", []):
		if String(f.get("champion", "")) != "":
			n += 1
	return n


## Mastered: won on this continent with every one of its factions.
func is_journey_cleared(id: String) -> bool:
	var total := journey_faction_total(id)
	return total > 0 and journey_won_factions(id).size() >= total


## Continent picks the player has earned and not spent yet (mastered continents minus continents opened after the first).
func journey_picks_available() -> int:
	var mastered := 0
	for c in GameData.continents:
		if is_continent_unlocked(String(c["id"])) and is_journey_cleared(String(c["id"])):
			mastered += 1
	return maxi(0, mastered - maxi(0, (data["unlocked_continents"] as Array).size() - 1))


## Spends one pick to open a locked continent (and its factions). False when no pick is left or the continent cannot be opened.
func choose_continent(id: String) -> bool:
	var c := GameData.get_continent(id)
	if c.is_empty() or not c.get("playable", false) or is_continent_unlocked(id) or journey_picks_available() < 1:
		return false
	unlock_continent(id)
	save_game()
	return true


## The Journey goal: the first open continent that is not mastered yet (the last open one when all are mastered).
func journey_frontier() -> String:
	var last := ""
	for c in GameData.continents:
		var id := String(c["id"])
		if c.get("playable", false) and is_continent_unlocked(id):
			last = id
			if not is_journey_cleared(id):
				return id
	return last if last != "" else String(GameData.continents[0]["id"])


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


## Card Fragments: what a Gacha duplicate turns into. Exchanged for a locked Support card (ShopSystem.exchange).
func fragments() -> int:
	return int(data["wallet"].get("fragments", 0))


func add_fragments(n: int) -> void:
	data["wallet"]["fragments"] = maxi(0, fragments() + n)


## Pays `n` fragments; false (and nothing paid) when the player has less.
func spend_fragments(n: int) -> bool:
	if n < 0 or fragments() < n:
		return false
	data["wallet"]["fragments"] = fragments() - n
	return true


## Adds one copy of a card to the collection if it is not owned yet. Returns true when it was new.
func unlock_card(card_id: String) -> bool:
	if owned_count(card_id) > 0:
		return false
	data["collection"][card_id] = 1
	return true


## Coins earned by the last record_match (shown on the result screen).
var last_reward: int = 0
var last_bonus_text: String = ""  # Arena random-map bonus paid with the last win ("" = none)


## Every victory unlocks the next locked Support card. Returns its id ("" when everything is unlocked).
func unlock_next_card() -> String:
	for s in CardDatabase.all_supports():
		if owned_count(s["id"]) == 0:
			data["collection"][s["id"]] = 1
			return String(s["id"])
	return ""


## Returns the id of the card unlocked by this result ("" if none).
func record_match(won: bool, rounds: int, final_gold: int, continent_id: String = "", journey: bool = true, faction_id: String = "", reward_bonus: Dictionary = {}) -> String:
	var s: Dictionary = data["stats"]
	s["matches_played"] += 1
	s["total_rounds"] += rounds
	if won:
		s["wins"] += 1
	else:
		s["losses"] += 1
	s["best_gold"] = maxi(int(s["best_gold"]), final_gold)
	if won and journey and continent_id != "" and faction_id != "":  # Journey only: it counts the faction that won (see journey_picks_available)
		var wins: Dictionary = data["journey_wins"]
		var won_with: Array = wins.get(continent_id, [])
		if not won_with.has(faction_id):
			won_with.append(faction_id)
		wins[continent_id] = won_with
	last_reward = ShopSystem.WIN_REWARD if won else ShopSystem.LOSS_REWARD
	last_bonus_text = ""
	if won and not reward_bonus.is_empty():  # Arena random map: the drawn continent's own bonus
		last_reward += int(round(ShopSystem.WIN_REWARD * float(reward_bonus.get("coins_pct", 0)) / 100.0)) + int(reward_bonus.get("coins_flat", 0))
		add_fragments(int(reward_bonus.get("fragments", 0)))
		last_bonus_text = String(reward_bonus.get("text", ""))
	add_coins(last_reward)
	var card := unlock_next_card() if won else ""
	save_game()
	return card


## Pays the stake of a wager (coins are taken at the start of the match). false = not enough coins, nothing paid.
func place_wager(stake: int) -> bool:
	if stake <= 0:
		return true
	if not spend_coins(stake):
		return false
	save_game()
	return true


## Settles a wager: outcome "win" pays stake x odds (stake included), "draw" returns the stake, "loss" pays nothing.
## Returns the coins paid out.
func settle_wager(stake: int, outcome: String, odds: float) -> int:
	if stake <= 0:
		return 0
	var paid := 0
	match outcome:
		"win":
			paid = ShopSystem.wager_payout(stake, odds)
		"draw":
			paid = stake
	if paid > 0:
		add_coins(paid)
	save_game()
	return paid


## Battle Chess (offline auto battle): pays Aether Coins only - no stats, no Journey progress, no card unlock.
## Returns the coins paid.
func record_practice(won: bool) -> int:
	var reward := ShopSystem.PRACTICE_WIN_REWARD if won else ShopSystem.PRACTICE_LOSS_REWARD
	add_coins(reward)
	save_game()
	return reward


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


## True when the faction can be played: its continent was unlocked in Journey (the starting factions are always open).
func can_use_faction(faction_id: String) -> bool:
	var f := GameData.find_faction(faction_id)
	return not f.is_empty() and String(f.get("champion", "")) != "" and is_faction_unlocked(faction_id)


## The King chosen in the Deck. A King of a locked faction (older saves) falls back to the first faction that is open.
func player_champion_id() -> String:
	var main: Dictionary = data["decks"].get("main", {})
	var id := String(main.get("champion", "champion_solvaris"))
	var ch := GameData.get_champion(id)
	if not ch.is_empty() and can_use_faction(String(ch.get("faction", ""))):
		return id
	for c in GameData.continents:
		for f in c.get("factions", []):
			if can_use_faction(String(f["id"])):
				return String(f["champion"])
	return "champion_solvaris"


## The faction the player fights for in every match: the faction of the Deck's King. New Match has no faction choice.
func player_faction_id() -> String:
	return String(GameData.get_champion(player_champion_id()).get("faction", "solvaris"))


## The player's deck for a continent. King and Support cards are shared by every continent; the 15 unit types are saved per
## continent ("units_by_continent"). No saved list (or an invalid one) = the default units of the King's faction.
func get_deck(continent_id: String = "") -> Deck:
	var cid := continent_id if continent_id != "" else CardDatabase.active_continent
	var main: Dictionary = data["decks"].get("main", {})
	var ubc: Dictionary = main.get("units_by_continent", {})
	var deck := Deck.from_dict({"champion": main.get("champion", "champion_solvaris"), "supports": main.get("supports", []),
		"continent": cid, "units": ubc.get(cid, []), "lineup": (main.get("lineups_by_continent", {}) as Dictionary).get(cid, [])})
	deck.sanitize_units()
	deck.lineup = deck.valid_lineup()
	deck.champion_id = player_champion_id()  # never a King of a locked faction
	return deck


func set_deck(deck: Deck) -> void:
	var main: Dictionary = data["decks"].get("main", {})
	var ubc: Dictionary = main.get("units_by_continent", {})
	ubc[deck.deck_continent()] = deck.unit_ids.duplicate() if deck.unit_ids.size() == Deck.UNIT_SLOTS else []
	data["decks"]["main"] = {"champion": deck.champion_id, "supports": deck.support_ids.duplicate(), "units_by_continent": ubc,
		"lineups_by_continent": main.get("lineups_by_continent", {})}  # the lineup is saved separately (set_lineup)
	save_game()


## Saves the custom lineup (unit type -> cell on the deployment area) of a continent's deck. Empty = back to the default formation.
func set_lineup(continent_id: String, entries: Array) -> void:
	var main: Dictionary = data["decks"].get("main", {})
	var lbc: Dictionary = main.get("lineups_by_continent", {})
	lbc[continent_id] = entries.duplicate(true)
	main["lineups_by_continent"] = lbc
	data["decks"]["main"] = main
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
