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
	ensure_xp()
	ensure_collection()
	apply_settings()


func default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"profile": {"name": "Player", "level": 1, "xp": 0, "tutorial_done": false},
		"settings": {"master_volume": 0.8, "default_difficulty": "normal", "sfx": true, "check_updates": true, "skipped_update": "", "fullscreen": false, "effects": "pro"},
		"campaign": {"progress": 0},  # TODO (Phase 6): Story Campaign
		"unlocked_continents": ["aetherion"],
		"journey_wins": {},  # continent id -> ids of the factions that won a Journey match on it (all 4 of the last continent free the Journey difficulty)
		"unlocked_factions": ["solvaris", "nocthyr", "valdoria", "elarion"],
		"collection": {},  # TODO (Phase 3): Card Collection
		"decks": {},  # TODO (Phase 3): Deck Configuration
		"stats": {"matches_played": 0, "wins": 0, "losses": 0, "total_rounds": 0, "best_gold": 0},
		"wallet": {"coins": 600, "fragments": 0, "tickets": 0, "crystals": 0, "chips": 0},  # Aether Coins, Card Fragments (Gacha duplicates), Gacha Tickets, Crystals (buy cards), Chips: persistent Shop currencies (see ShopSystem)
		"shop": {"pity": 0, "pity_rare": 0, "pity_legendary": 0, "pulls": 0},
		"trading": {"pos": {}, "realized": 0},  # Shop > Trading (see TradeSystem): open positions per asset + total realized profit in Chips
		"chests": {"slots": [null, null, null, null], "opened": 0, "storage": [], "drops": 0, "limit_at": 0},  # Arena reward chests (see ChestSystem): 4 slots, each null or {grade, start, ready}
		"events": {},  # Missions + Achievements (see EventHub)
		"trophies": 0,  # Journey trophy road: a win raises it, a defeat lowers it; continents open at their unlock_trophies
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


const NAME_MAX := 16


## Profile name rules: no line breaks / control characters, runs of spaces collapse, 1..NAME_MAX characters. "" = not usable.
static func clean_name(raw: String) -> String:
	var out := ""
	for i in range(raw.length()):
		var ch := raw.substr(i, 1)
		if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127:
			ch = " "
		out += ch
	var parts := out.split(" ", false)
	return " ".join(parts).left(NAME_MAX).strip_edges()


## Renames the player's profile (shown on the Main Menu card, in the profile dialog and as the name in matches started afterwards).
## Returns false (nothing changed) when the cleaned name is empty.
func set_profile_name(raw: String) -> bool:
	var n := clean_name(raw)
	if n == "":
		return false
	data["profile"]["name"] = n
	save_game()
	return true


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
	_apply_fullscreen(fullscreen_wanted())


## Whether the game should be full screen: the Fullscreen setting, except on Android where immersive mode (hidden status / navigation
## bars) is the default until the player turns the toggle off themselves ("fullscreen_set").
func fullscreen_wanted() -> bool:
	var s: Dictionary = data["settings"]
	if OS.get_name() == "Android" and not bool(s.get("fullscreen_set", false)):
		return true
	return bool(s.get("fullscreen", false))


## Default OFF on desktop, ON on Android. Skipped in headless runs (tests).
## `force` re-applies the mode even when it already matches: Android shows the system bars again after the keyboard, a system dialog
## or a switch of apps, and only a fresh request hides them.
func _apply_fullscreen(on: bool, force: bool = false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	if force or DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## Android: bring the immersive mode back when the app returns to the front (after a frame, once the window has focus).
func _reapply_immersive() -> void:
	if OS.get_name() != "Android" or not fullscreen_wanted():
		return
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout  # some devices only hide the bars after the window is focused
	_apply_fullscreen(true, true)


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


## Journey gives the Kings of a continent for free as B1 cards (a King already owned keeps its level), so the player can win with
## each faction of it (the faction gate of the next continent). Returns the ids of the Kings that were added.
func grant_continent_kings(id: String) -> Array[String]:
	var added: Array[String] = []
	if not data.has("collection") or not (data["collection"] is Dictionary):
		return added
	for f in GameData.get_continent(id).get("factions", []):
		var kid := String(f.get("champion", ""))
		if kid != "" and CardDatabase.is_king(kid) and owned_count(kid) == 0:
			data["collection"][kid] = 1
			added.append(kid)
	return added


## The Journey continent to play by default: the newest open one (highest unlock_trophies).
func journey_frontier() -> String:
	var last := ""
	for c in GameData.continents:
		var id := String(c["id"])
		if c.get("playable", false) and is_continent_unlocked(id):
			if last == "" or continent_trophies(id) >= continent_trophies(last):
				last = id
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


## Gacha Tickets / Crystals / Chips (wallet keys "tickets", "crystals", "chips").
func currency(key: String) -> int:
	return int(data["wallet"].get(key, 0))


func add_currency(key: String, n: int) -> void:
	data["wallet"][key] = maxi(0, currency(key) + n)


## Pays `n` of a wallet currency; false (and nothing paid) when the player has less.
func spend_currency(key: String, n: int) -> bool:
	if n < 0 or currency(key) < n:
		return false
	data["wallet"][key] = currency(key) - n
	return true


func tickets() -> int:
	return currency("tickets")


func crystals() -> int:
	return currency("crystals")


func chips() -> int:
	return currency("chips")


## Adds a card to the collection if it is not owned yet (a unit card = all its `unit_copies`, a Support card = 1).
## Returns true when it was new.
func unlock_card(card_id: String) -> bool:
	if owned_count(card_id) > 0:
		return false
	data["collection"][card_id] = 1 if (CardDatabase.is_support(card_id) or CardDatabase.is_king(card_id)) else int(GameData.b("unit_copies"))
	return true


# ------------------------------------------------------------------ King cards (B1 / B2 / B3)
# A King is a collectible card (Card Gacha / Buy Card). The number of copies owned is its B level (max 3):
#   B1 = the King card itself (stats, battle passive, King buff)
#   B2 = unlocks the active skill of Battle Chess (the manual "King skill")
#   B3 = unlocks the territory skill (the passive of the Territory Board: Royal Treasury, Shadow Ledger ...)

const KING_MAX_COPIES := 3


func owns_king(champion_id: String) -> bool:
	return owned_count(champion_id) > 0


## 0 = not owned, 1..3 = B level (copies owned, capped at KING_MAX_COPIES).
func king_b(champion_id: String) -> int:
	return clampi(owned_count(champion_id), 0, KING_MAX_COPIES)


func king_battle_skill_unlocked(champion_id: String) -> bool:
	return king_b(champion_id) >= 2


func king_territory_skill_unlocked(champion_id: String) -> bool:
	return king_b(champion_id) >= 3


## A King can be played when its faction is open AND the King card is owned.
func can_use_king(champion_id: String) -> bool:
	var ch := GameData.get_champion(champion_id)
	return not ch.is_empty() and owns_king(champion_id) and can_use_faction(String(ch.get("faction", "")))


## Adds one copy of a King card. Returns the new B level, or 0 when it is unknown or already at B3 (the caller turns it into fragments).
func add_king_copy(champion_id: String) -> int:
	if not CardDatabase.is_king(champion_id) or owned_count(champion_id) >= KING_MAX_COPIES:
		return 0
	data["collection"][champion_id] = owned_count(champion_id) + 1
	return owned_count(champion_id)


## The unit cards a new player owns: the 8 Pawns and the 7 pieces of Solvaris (the default King), i.e. exactly the 15 types of
## the default deck. Every other unit card comes from the Shop (Card Gacha / Buy Card).
func starter_unit_ids() -> Array[String]:
	var out: Array[String] = []
	for raw in GameData.cards.get("units", []):
		if String(raw["chess"]) == "pawn" or String(raw["faction"]) == "solvaris":
			out.append(String(raw["id"]))
	return out


# ------------------------------------------------------------------ Journey trophy road

func trophies() -> int:
	return int(data.get("trophies", 0))


## Trophies needed to open a continent (data/continents.json "unlock_trophies").
func continent_trophies(id: String) -> int:
	return int(GameData.get_continent(id).get("unlock_trophies", 0))


## Highest unlock_trophies among the open continents: trophies never drop below it (like a Clash Royale arena floor).
func trophy_floor() -> int:
	var best := 0
	for c in GameData.continents:
		if is_continent_unlocked(String(c["id"])):
			best = maxi(best, continent_trophies(String(c["id"])))
	return best


## Trophy band of the Journey continent that `t` trophies put you on: {"id", "from", "to"}. "from" = its unlock_trophies, "to" = the
## unlock_trophies of the next continent (the last continent uses balance.json "journey_last_continent_span").
static func journey_band(t: int) -> Dictionary:
	var cur := ""
	var cur_at := -1
	var next_at := -1
	for c in GameData.continents:
		if not c.get("playable", false):
			continue
		var at := int(c.get("unlock_trophies", 0))
		if at <= t and at > cur_at:
			cur = String(c["id"])
			cur_at = at
	for c in GameData.continents:
		if not c.get("playable", false):
			continue
		var at2 := int(c.get("unlock_trophies", 0))
		if at2 > cur_at and (next_at == -1 or at2 < next_at):
			next_at = at2
	if next_at == -1:
		next_at = cur_at + int(GameData.b("journey_last_continent_span", 600))
	return {"id": cur, "from": maxi(cur_at, 0), "to": next_at}


## Journey has no difficulty choice: EVERY continent has all 3 levels. Its trophy range (from its own unlock_trophies up to the
## next continent's) is split in three equal parts: Easy first, Normal in the middle, Hard last, then the next continent opens
## and starts Easy again. Losing never drops you below the continent's floor, so each continent always starts on Easy.
## (Past the last continent's range and with all its 4 factions won, the player chooses the level freely: see journey_difficulty_free.)
static func difficulty_for_trophies(t: int) -> String:
	var band := journey_band(t)
	var span := maxi(int(band["to"]) - int(band["from"]), 1)
	var tier := clampi((3 * (t - int(band["from"]))) / span, 0, 2)
	return ["easy", "normal", "hard"][tier]


## Trophies at which the 3 levels start inside the band of `t`: [easy_from, normal_from, hard_from].
static func journey_tier_starts(t: int) -> Array:
	var band := journey_band(t)
	var a := int(band["from"])
	var span := int(band["to"]) - a
	return [a, a + int(ceil(span / 3.0)), a + int(ceil(2.0 * span / 3.0))]


func journey_difficulty() -> String:
	return difficulty_for_trophies(trophies())


## The whole trophy ladder, one row per playable continent: {"id", "name", "easy": [lo, hi], "normal": [lo, hi], "hard": [lo, hi]}
## (inclusive trophy ranges; the Hard range ends right before the next continent opens). Shown as a table in the Journey setup.
static func journey_ladder() -> Array:
	var rows: Array = []
	for c in GameData.continents:
		if not c.get("playable", false):
			continue
		var a := int(c.get("unlock_trophies", 0))
		var band := journey_band(a)
		var st := journey_tier_starts(a)
		rows.append({"id": String(c["id"]), "name": String(c.get("name", c["id"])),
			"easy": [int(st[0]), int(st[1]) - 1], "normal": [int(st[1]), int(st[2]) - 1], "hard": [int(st[2]), int(band["to"]) - 1]})
	rows.sort_custom(func(x, y): return int(x["easy"][0]) < int(y["easy"][0]))
	return rows


## The Journey continent that ends the road: the playable one with the highest unlock_trophies (Eclipsia).
func journey_last_continent() -> String:
	var best := ""
	for c in GameData.continents:
		if c.get("playable", false) and (best == "" or continent_trophies(String(c["id"])) > continent_trophies(best)):
			best = String(c["id"])
	return best


## Ids of the factions that have won a Journey match on `continent_id` (key "journey_wins").
func journey_won_factions(continent_id: String) -> Array:
	var all: Dictionary = data.get("journey_wins", {})
	return (all.get(continent_id, []) as Array).duplicate()


## The factions of the last continent that still have to win there (4 of them) before the difficulty is free.
func journey_final_missing() -> Array:
	var last := journey_last_continent()
	var won := journey_won_factions(last)
	var out: Array = []
	for f in GameData.get_continent(last).get("factions", []):
		if not won.has(String(f["id"])):
			out.append(String(f["id"]))
	return out


## Trophies that finish the road: the end of the last continent's trophy range (Eclipsia 2200-2799 -> 2800), i.e. its Hard tier is done.
func journey_final_trophy_goal() -> int:
	var last := journey_last_continent()
	return int(journey_band(continent_trophies(last))["to"])


## True once the road is finished: the last continent is open, the trophies reached the end of its range (its Easy / Normal / Hard
## tiers are all behind you) AND every one of its factions has won a Journey match on it.
func journey_final_cleared() -> bool:
	var last := journey_last_continent()
	return last != "" and is_continent_unlocked(last) and trophies() >= journey_final_trophy_goal() and journey_final_missing().is_empty()


func _note_journey_win(continent_id: String, faction_id: String) -> void:
	if continent_id == "" or faction_id == "":
		return
	if not data.has("journey_wins") or not (data["journey_wins"] is Dictionary):
		data["journey_wins"] = {}
	var all: Dictionary = data["journey_wins"]
	var list: Array = all.get(continent_id, [])
	if not list.has(faction_id):
		list.append(faction_id)
	all[continent_id] = list


## The Journey AI level is only free to choose after the road is FINISHED: the trophies are past the whole range of the last continent
## (Eclipsia, 2800+) and the player has won there with each of its 4 factions. Until then it follows the trophies (see difficulty_for_trophies). The player then picks
## Easy / Normal / Hard in the Journey setup, like in Arena.
func journey_difficulty_free() -> bool:
	return journey_final_cleared()


## Trophy change of a Journey result: the harder the AI, the more a win gives and the less a defeat takes.
static func trophy_delta(won: bool, difficulty: String) -> int:
	var table: Dictionary = GameData.b("trophy_win", {}) if won else GameData.b("trophy_loss", {})
	return int(table.get(difficulty, 30 if won else -20))


## The playable continent right before `id` on the trophy road (the highest unlock_trophies below it); "" for the first continent.
func journey_prev_continent(id: String) -> String:
	var at := continent_trophies(id)
	var best := ""
	for c in GameData.continents:
		if not c.get("playable", false):
			continue
		var cid := String(c["id"])
		var cat := continent_trophies(cid)
		if cat < at and (best == "" or cat > continent_trophies(best)):
			best = cid
	return best


## Factions of the PREVIOUS continent that still have to win a Journey match before `id` can open (same rule as the last
## continent: win with each of its factions). Empty = the faction gate of `id` is cleared (the first continent has none).
func journey_gate_missing(id: String) -> Array:
	var prev := journey_prev_continent(id)
	var out: Array = []
	if prev == "":
		return out
	var won := journey_won_factions(prev)
	for f in GameData.get_continent(prev).get("factions", []):
		if not won.has(String(f["id"])):
			out.append(String(f["id"]))
	return out


## A locked continent opens only when its trophies are reached AND every faction of the previous continent has won there.
func can_unlock_continent(id: String) -> bool:
	return trophies() >= continent_trophies(id) and journey_gate_missing(id).is_empty()


## Continents (ids) that the current trophies AND the faction wins have opened but are still locked: opens them.
## Returns the newly opened ids. Opens at most one continent per call chain step (the next one needs its own faction wins).
func unlock_by_trophies() -> Array[String]:
	var opened: Array[String] = []
	var changed := true
	while changed:
		changed = false
		for c in GameData.continents:
			var id := String(c["id"])
			if c.get("playable", false) and not is_continent_unlocked(id) and can_unlock_continent(id):
				unlock_continent(id)
				grant_continent_kings(id)  # the new continent's Kings are a gift of the road (B1)
				opened.append(id)
				changed = true
	return opened


## Trophy ceiling while the next continent is locked by its faction gate: one below its unlock_trophies, so the AI level stays on
## the Hard tier of the current continent until every faction has won. -1 = no ceiling (nothing locked, or the gate is cleared).
func journey_trophy_cap() -> int:
	var next := next_continent_goal()
	if next == "" or journey_gate_missing(next).is_empty():
		return -1
	return continent_trophies(next) - 1


## The next locked playable continent in trophy order ("" when everything is open).
func next_continent_goal() -> String:
	var best := ""
	for c in GameData.continents:
		var id := String(c["id"])
		if c.get("playable", false) and not is_continent_unlocked(id):
			if best == "" or continent_trophies(id) < continent_trophies(best):
				best = id
	return best


## Trophy change and newly opened continents of the last Journey result (shown on the result screen).
var last_trophy_delta: int = 0
var last_opened_continents: Array[String] = []


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


## Always returns "" (kept for the caller's signature): a match result no longer unlocks a Support card.
func record_match(won: bool, rounds: int, final_gold: int, continent_id: String = "", journey: bool = true, faction_id: String = "", reward_bonus: Dictionary = {}, difficulty: String = "normal", reward_mult: float = 1.0) -> String:
	var s: Dictionary = data["stats"]
	s["matches_played"] += 1
	s["total_rounds"] += rounds
	if won:
		s["wins"] += 1
	else:
		s["losses"] += 1
	s["best_gold"] = maxi(int(s["best_gold"]), final_gold)
	last_trophy_delta = 0
	last_opened_continents = []
	EventHub.track("matches")
	if won:
		EventHub.track("wins")
		if not journey:
			EventHub.track("arena_wins")
	if journey:  # Journey only: the trophy road. A win raises the score, a defeat lowers it (never below the floor of the open continents)
		var before := trophies()
		if won:
			_note_journey_win(continent_id, faction_id)  # per-faction wins: every continent needs all its factions to open the next one (the last one frees the difficulty)
		last_trophy_delta = trophy_delta(won, difficulty)
		var new_t := maxi(before + last_trophy_delta, trophy_floor())
		var cap := journey_trophy_cap()  # faction gate not cleared: trophies wait one below the next continent
		if cap >= 0 and new_t > cap:
			new_t = maxi(cap, before)
		data["trophies"] = new_t
		last_trophy_delta = trophies() - before
		last_opened_continents = unlock_by_trophies()
	last_reward = ShopSystem.win_reward(difficulty) if won else ShopSystem.loss_reward(difficulty)
	last_bonus_text = ""
	var bonus_xp := 0
	if won and not reward_bonus.is_empty():  # Arena random map: the drawn continent's own bonus
		last_reward += int(round(ShopSystem.win_reward(difficulty) * float(reward_bonus.get("coins_pct", 0)) / 100.0)) + int(reward_bonus.get("coins_flat", 0))
		bonus_xp = int(reward_bonus.get("xp", 0))
		last_bonus_text = String(reward_bonus.get("text", ""))
	last_reward = int(round(float(last_reward) * reward_mult))  # Chaos pays less (balance.json chaos_reward_mult)
	add_coins(last_reward)
	_award_xp(int(round(float(XpSystem.match_xp(won, rounds, difficulty) + bonus_xp) * reward_mult)))  # one award, so the level-up line covers the bonus XP too
	save_game()
	return ""  # no Support card is unlocked by a match result anymore (only Gold chests / the Shop give cards)


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
func record_practice(won: bool, difficulty: String = "normal") -> int:
	var reward := ShopSystem.practice_reward(won, difficulty)
	EventHub.track("chess_played")
	if won:
		EventHub.track("chess_wins")
	add_coins(reward)
	_award_xp(XpSystem.practice_xp(won, difficulty))
	save_game()
	return reward


## Profile XP (see XpSystem). `last_xp` / `last_level_up` describe the last award, for the result screens.
var last_xp: int = 0
var last_level_up: int = 0  # the new level when the last award levelled the player up, else 0
var last_level_coins: int = 0  # Aether Coins paid by the level-up(s) of the last award (chests that overflowed into coins included)
var last_level_chests: Array = []  # grades of the chests the level-up(s) of the last award gave


func profile_xp() -> int:
	return int(data["profile"].get("xp", 0))


func profile_level() -> int:
	return XpSystem.level_of(profile_xp())


func profile_title() -> String:
	return XpSystem.title(profile_level())


## Public XP award (reward chests).
func add_xp(amount: int) -> void:
	_award_xp(amount)


func _award_xp(amount: int) -> void:
	var before := profile_level()
	data["profile"]["xp"] = profile_xp() + maxi(amount, 0)
	data["profile"]["level"] = profile_level()
	last_xp = maxi(amount, 0)
	last_level_up = profile_level() if profile_level() > before else 0
	last_level_coins = 0
	last_level_chests = []
	for lvl in range(before + 1, profile_level() + 1):  # every level gained pays coins and a chest (also when several at once)
		var coins := XpSystem.level_up_coins(lvl)
		add_coins(coins)
		last_level_coins += coins
		var chest := ChestSystem.award_grade(XpSystem.level_up_chest(lvl))
		last_level_chests.append(String(chest["grade"]))
		if String(chest["status"]) == "full":  # slots and Storage full: the chest was paid out as coins already
			last_level_coins += int(chest["coins"])


## "+120 XP" or "+120 XP   LEVEL UP! Lv 4 - Recruit" for the result screens.
func xp_line() -> String:
	var t := "+%d XP" % last_xp
	if last_level_up > 0:
		t += "   LEVEL UP!  Lv %d - %s" % [last_level_up, XpSystem.title(last_level_up)]
		t += "\n" + level_reward_line()
	return t


## "Level reward: +120 coins + Bronze Chest" for the last level-up ("" when the last award did not level up).
func level_reward_line() -> String:
	if last_level_up <= 0:
		return ""
	var names: Array[String] = []
	for g in last_level_chests:
		names.append(ChestSystem.grade_name(String(g)))
	return "Level reward: +%d coins%s" % [last_level_coins, (" + " + " + ".join(names)) if not names.is_empty() else ""]


## Older saves had no XP: start them from their record (win 100, loss 30), once.
func ensure_xp() -> void:
	var p: Dictionary = data["profile"]
	if not p.has("xp_v"):
		var s: Dictionary = data["stats"]
		p["xp"] = maxi(int(p.get("xp", 0)), int(s.get("wins", 0)) * 100 + int(s.get("losses", 0)) * 30)
		p["xp_v"] = 1
		save_game()
	p["level"] = XpSystem.level_of(int(p.get("xp", 0)))


## Fills the starter collection (all unit cards of every continent x 9, 15 default Support cards) and main deck.
func ensure_collection() -> void:
	var changed := false
	var col: Dictionary = data["collection"]
	if col.is_empty():
		for id in starter_unit_ids():  # unit cards are locked: only the starter units are owned, the rest comes from the Shop
			col[id] = int(GameData.b("unit_copies"))
		for s in CardDatabase.all_supports():
			if s.get("owned_default", false):
				col[s["id"]] = 1
		data["unit_cards_v"] = 2  # 2 = unit cards are locked (starter units only) and come from the Shop; a save without it owns every unit
		col["champion_solvaris"] = 1  # Kings are cards too: the Kings of the open continents are owned (Journey hands out the rest), extra copies come from the Shop
		data["king_cards_v"] = 2
		for cid0 in (data["unlocked_continents"] as Array):
			grant_continent_kings(String(cid0))
		changed = true
	elif int(data.get("unit_cards_v", 1)) < 2:
		# older save (every unit owned): keep what the player has, add the unit cards of continents that did not exist yet
		for id in CardDatabase.all_unit_ids_any_continent():
			if not col.has(id):
				col[id] = int(GameData.b("unit_copies"))
		# Journey used to be factions-won based: start the trophy road at the floor of the continents already open
		var floor_t := 0
		for cid in (data["unlocked_continents"] as Array):
			floor_t = maxi(floor_t, continent_trophies(String(cid)))
		data["trophies"] = maxi(trophies(), floor_t)
		data["unit_cards_v"] = 2
		changed = true
	if not (data["decks"] as Dictionary).has("main"):
		data["decks"]["main"] = Deck.create_default().to_dict()
		changed = true
	for cid in (data["unlocked_continents"] as Array).duplicate():
		unlock_continent(cid)
	if int(data.get("king_cards_v", 0)) < 1:
		# older save: every King of an open faction was playable, so the player keeps it as a B1 card (skills now need duplicates)
		for champ_id in GameData.champions:
			var champ_fac := String(GameData.get_champion(String(champ_id)).get("faction", ""))
			if not col.has(champ_id) and can_use_faction(champ_fac):
				col[champ_id] = 1
		col["champion_solvaris"] = maxi(int(col.get("champion_solvaris", 0)), 1)
		data["king_cards_v"] = 1
		changed = true
	if int(data.get("king_cards_v", 0)) < 2:
		# faction gate: every continent already open hands its Kings over as B1 (an owned King keeps its level)
		for cid1 in (data["unlocked_continents"] as Array):
			grant_continent_kings(String(cid1))
		data["king_cards_v"] = 2
		changed = true
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
	if not ch.is_empty() and can_use_king(id):
		return id
	for c in GameData.continents:
		for f in c.get("factions", []):
			if can_use_king(String(f.get("champion", ""))):
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
	var lbc: Dictionary = main.get("lineups_by_continent", {})
	# A continent with no saved deck of its own uses the deck the player saved last in the Card Hub (so Battle Chess / Arena match it).
	var src := cid
	if (ubc.get(cid, []) as Array).is_empty():
		var last := String(main.get("last_units_continent", ""))
		if last != "" and not (ubc.get(last, []) as Array).is_empty():
			src = last
	var deck := Deck.from_dict({"champion": main.get("champion", "champion_solvaris"), "supports": main.get("supports", []),
		"continent": cid, "units": ubc.get(src, []), "lineup": lbc.get(cid, lbc.get(src, [])),
		"support_lineup": main.get("support_lineup", [])})
	deck.owned_filter = data["collection"]
	deck.sanitize_units()
	deck.sanitize_owned()
	deck.lineup = deck.valid_lineup()
	deck.support_lineup = deck.valid_support_lineup()
	deck.champion_id = player_champion_id()  # never a King of a locked faction
	return deck


## Continent whose deck Battle Chess uses. The map of a Battle Chess run is random, so the deck must NOT follow it:
## the deck saved last in the Card Hub, else the continent of the player's King (its faction's default 15 units), else Aetherion.
func battle_deck_continent() -> String:
	var last := last_deck_continent()
	if last != "":
		return last
	var home := String(GameData.get_champion(player_champion_id()).get("continent", ""))
	if home != "" and GameData.get_continent(home).get("playable", false):
		return home
	return "aetherion"


## Continent of the deck the player saved last in the Card Hub ("" = none saved yet). Battle Chess plays on it so it matches that deck.
func last_deck_continent() -> String:
	var main: Dictionary = data["decks"].get("main", {})
	var last := String(main.get("last_units_continent", ""))
	if last != "" and GameData.get_continent(last).get("playable", false):
		return last
	return ""


func set_deck(deck: Deck) -> void:
	var main: Dictionary = data["decks"].get("main", {})
	var ubc: Dictionary = main.get("units_by_continent", {})
	ubc[deck.deck_continent()] = deck.unit_ids.duplicate() if deck.unit_ids.size() == Deck.UNIT_SLOTS else []
	data["decks"]["main"] = {"champion": deck.champion_id, "supports": deck.support_ids.duplicate(), "units_by_continent": ubc,
		"last_units_continent": deck.deck_continent() if deck.unit_ids.size() == Deck.UNIT_SLOTS else String(main.get("last_units_continent", "")),
		"lineups_by_continent": main.get("lineups_by_continent", {}),
		"support_lineup": main.get("support_lineup", [])}  # the lineups are saved separately (set_lineup, set_support_lineup)
	save_game()


## Saves the custom lineup (unit type -> cell on the deployment area) of a continent's deck. Empty = back to the default formation.
func set_lineup(continent_id: String, entries: Array) -> void:
	var main: Dictionary = data["decks"].get("main", {})
	var lbc: Dictionary = main.get("lineups_by_continent", {})
	lbc[continent_id] = entries.duplicate(true)
	main["lineups_by_continent"] = lbc
	data["decks"]["main"] = main
	save_game()


## Saves the Support lineup (Support card per slot, "" = empty; shared by every continent like the Support cards). All empty = no order.
func set_support_lineup(slots: Array) -> void:
	var main: Dictionary = data["decks"].get("main", {})
	var any := false
	for id in slots:
		any = any or String(id) != ""
	main["support_lineup"] = slots.duplicate() if any else []
	data["decks"]["main"] = main
	save_game()


# Camera-bezel watcher. Turning the phone 180 degrees (landscape <-> reverse landscape) keeps the window size, so the
# root's size_changed never fires while the cutout jumps to the other edge; the safe area is also often reported a moment
# late. Poll the display's safe area / cutouts / orientation and re-emit size_changed (what every inset follower listens
# to, see UiTheme.follow_insets) as soon as any of them changes.
var _inset_sig: String = ""
var _inset_clock: float = 0.0


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	_inset_clock += delta
	if _inset_clock < 0.1:
		return
	_inset_clock = 0.0
	var sig := "%s|%s|%s|%s" % [DisplayServer.get_display_safe_area(), DisplayServer.get_display_cutouts(), DisplayServer.window_get_size(), DisplayServer.screen_get_orientation()]
	if _inset_sig != "" and sig != _inset_sig:
		get_tree().root.size_changed.emit()
	_inset_sig = sig


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		save_game()
		app_paused.emit()
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_reapply_immersive()


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
