class_name ShopSystem
extends RefCounted
## Shop rules: Aether Coins (the persistent currency, earned by playing matches), the Support card Gacha, direct card purchase and Card Fragments (Gacha duplicates, exchanged for locked cards).
## All state lives in SaveManager.data ("wallet", "shop", "collection"). Every number the player can see is a constant here.

const START_COINS := 600  # mirrored by SaveManager.default_data()
const WIN_REWARD := 150
const PRACTICE_WIN_REWARD := 75    # Battle Chess (offline auto battle): Aether Coins for a win
const PRACTICE_LOSS_REWARD := 15  # ... for a loss or a draw
const LOSS_REWARD := 50
## Match rewards by difficulty (Journey / Arena): the harder the AI (and the fewer Life), the bigger the prize.
## "normal" equals WIN_REWARD / LOSS_REWARD. Battle Chess pays its own, smaller table.
const WIN_REWARD_BY_DIFF := {"easy": 100, "normal": 150, "hard": 300}
const LOSS_REWARD_BY_DIFF := {"easy": 25, "normal": 50, "hard": 75}
const PRACTICE_WIN_BY_DIFF := {"easy": 50, "normal": 75, "hard": 150}
const PRACTICE_LOSS_BY_DIFF := {"easy": 10, "normal": 15, "hard": 25}


static func win_reward(difficulty: String) -> int:
	return int(WIN_REWARD_BY_DIFF.get(difficulty, WIN_REWARD))


static func loss_reward(difficulty: String) -> int:
	return int(LOSS_REWARD_BY_DIFF.get(difficulty, LOSS_REWARD))


static func practice_reward(won: bool, difficulty: String) -> int:
	if won:
		return int(PRACTICE_WIN_BY_DIFF.get(difficulty, PRACTICE_WIN_REWARD))
	return int(PRACTICE_LOSS_BY_DIFF.get(difficulty, PRACTICE_LOSS_REWARD))
## Battle Chess series (1 round / 10 rounds / until you lose): rules shared by the screen and the tests.
const SERIES_IDS: Array[String] = ["single", "ten", "survival"]
const SERIES_TEN_ROUNDS := 10  # default length of the multi-round run when no difficulty is given (tests); in the game see SERIES_ROUNDS_BY_DIFF
const SERIES_ROUNDS_BY_DIFF := {"easy": 5, "normal": 3, "hard": 1}  # rounds of the multi-round run (series id "ten") per difficulty
const SERIES_SURVIVAL_TARGET := 5  # survival wager is won by winning at least this many rounds in a row
const SERIES_INCOME := 150  # gold the player earns between two rounds ...
const SERIES_INCOME_STEP := 25  # ... plus this much per round already played
const SERIES_ROUND_BONUS := 25  # extra Aether Coins for a round won, from round 2 on (x round number), on top of practice_reward


## Lives of a Battle Chess Survival run: Easy 5 / Normal 3 / Hard 1 (the match Life table, balance.json "life_by_difficulty").
## Every defeat costs one life and the run ends at 0. "" (no difficulty given: tests) = 1 life, the first defeat ends it.
static func series_lives(difficulty: String = "") -> int:
	return 1 if difficulty == "" else maxi(GameData.life_for(difficulty), 1)


## Rounds of the multi-round run for a difficulty: Easy 5 / Normal 3 / Hard 1 ("" or unknown = SERIES_TEN_ROUNDS).
static func series_rounds(difficulty: String = "") -> int:
	return int(SERIES_ROUNDS_BY_DIFF.get(difficulty, SERIES_TEN_ROUNDS))


## Gold earned after round `played` (1-based) to prepare the next one.
static func series_income(played: int) -> int:
	return SERIES_INCOME + SERIES_INCOME_STEP * (played - 1)


## Extra Aether Coins for winning round `round_no` of a 10-round / survival run (0 in a single battle and in round 1).
static func series_coin_bonus(id: String, round_no: int) -> int:
	return 0 if id == "single" or round_no < 2 else SERIES_ROUND_BONUS * round_no


static func series_title(id: String, difficulty: String = "") -> String:
	match id:
		"ten":
			var n := series_rounds(difficulty)
			return "%d Round%s" % [n, "" if n == 1 else "s"]
		"survival":
			return "Survival"
	return "1 Round"


static func series_desc(id: String, difficulty: String = "") -> String:
	match id:
		"ten":
			var n := series_rounds(difficulty)
			return "%d battle%s in a row with the same army. More wins than losses wins the series." % [n, "" if n == 1 else "s"]
		"survival":
			if difficulty == "":
				return "Battle after battle, the enemy grows stronger. The run ends at your first defeat."
			var lv := series_lives(difficulty)
			return "Battle after battle, the enemy grows stronger. You have %d li%s (Easy 5 / Normal 3 / Hard 1): each defeat costs one and the run ends at 0." % [lv, "fe" if lv == 1 else "ves"]
	return "A single battle."


## Does the series go on after this round? `round_no` is the round just played (1-based), `won`/`lost` count rounds incl. this one.
static func series_continues(id: String, round_no: int, lost: int, difficulty: String = "") -> bool:
	match id:
		"ten":
			return round_no < series_rounds(difficulty)
		"survival":
			return lost < series_lives(difficulty)
	return false


## Series wager outcome: "win" / "draw" / "loss". single: the last round; ten: wins vs losses; survival: >= SERIES_SURVIVAL_TARGET wins.
static func series_outcome(id: String, wins: int, losses: int, last_round_winner: int) -> String:
	match id:
		"ten":
			return "win" if wins > losses else ("draw" if wins == losses else "loss")
		"survival":
			return "win" if wins >= SERIES_SURVIVAL_TARGET else "loss"
	return "win" if last_round_winner == 0 else ("draw" if last_round_winner < 0 else "loss")


## Enemy strength of round `round_no` (1 = unchanged): budget x, and extra shop levels.
static func series_budget_mult(round_no: int) -> float:
	return minf(1.0 + 0.12 * float(round_no - 1), 3.5)


## (No longer used by Battle Chess: the enemy's level now follows the player's level. Kept for the balance tests.)
static func series_level_bonus(round_no: int) -> int:
	return (round_no - 1) / 3


## King level (Commander stars) of BOTH Kings in a Battle Chess series: Lv 1 in rounds 1-3, Lv 2 in 4-6, Lv 3 from round 7 on
## (HP / ATK multipliers of CommanderSystem). A single battle stays at Lv 1.
static func series_king_star(id: String, round_no: int) -> int:
	if id == "single":
		return 1
	return clampi(1 + (round_no - 1) / 3, 1, CommanderSystem.max_star())


## Wager (Arena / Battle Chess): the stake is paid at the start; a win pays stake x odds (stake included).
const WAGER_STEP := 10  # the wager slider moves in multiples of this
const WAGER_MAX := 1000  # highest stake (0 = no wager)
const WAGER_DIFFICULTY_MULT := {"easy": 0.75, "normal": 1.0, "hard": 1.5}


const FFA_ODDS := 2.5  # 4 players: an even chance is 25% (x4), but a player beats the AI more often than that, so x2.5 breaks even at 40%
const CHAOS_ODDS_MULT := 0.75  # Chaos matches are short: smaller win multiplier than Arena


## Win multiplier: 1 vs 1 / 2 vs 2 / Battle Chess x2, the 4 Player free-for-all x2.5, scaled by the AI difficulty (x0.75 in Chaos).
static func wager_odds(kind: String, mode: String, _ai_count: int, difficulty: String, chaos: bool = false) -> float:
	var base := FFA_ODDS if (kind == "arena" and mode == "ffa_ai") else 2.0
	var odds := base * float(WAGER_DIFFICULTY_MULT.get(difficulty, 1.0))
	if chaos and kind == "arena":
		odds *= CHAOS_ODDS_MULT
	return snappedf(odds, 0.05)


## Arena "Random map": a win on the drawn continent pays that continent's own bonus (data/continents.json "random_bonus":
## coins_pct, coins_flat, xp, text). {} = none.
static func random_bonus(continent_id: String) -> Dictionary:
	return GameData.get_continent(continent_id).get("random_bonus", {})


## Menu line: the win reward and the in-game bonus of a continent.
static func random_bonus_lines(continent_id: String) -> String:
	var b := random_bonus(continent_id)
	if b.is_empty():
		return "-"
	return "Win: %s\nGame: %s" % [String(b.get("text", "-")), String(b.get("ingame_text", "-"))]


static func wager_payout(stake: int, odds: float) -> int:
	return int(round(float(stake) * odds))
## Card Gacha: ONE pool. The rarity is rolled with RATES (one pity); the card then comes from the pool of that rarity: every Support card, plus
## (Rare / Epic) the unit cards and (Legendary) the King cards of the continents opened on the trophy road (see shop_units / shop_kings).
## Pity per rarity: the Nth pull without that rarity (or better) is guaranteed to be it. Each rarity has its own counter, saved in the shop data
## (Rare "pity_rare", Epic "pity", Legendary "pity_legendary"). A counter resets when its rarity or a better one drops.
const PITY_LIMITS := {"rare": 10, "epic": 30, "legendary": 90}
const PITY_KEYS := {"rare": "pity_rare", "epic": "pity", "legendary": "pity_legendary"}
const RARITY_ORDER: Array[String] = ["common", "rare", "epic", "legendary"]
const RATES := {"common": 60, "rare": 28, "epic": 10, "legendary": 2}  # percent
## Direct purchase of a locked card: with Crystals, or Card Fragments (no coins).
## A Gacha duplicate (card already owned) turns into Card Fragments: the rarer the card, the more fragments.
const DUPLICATE_FRAGMENTS := {"common": 10, "rare": 25, "epic": 60, "legendary": 150}
## Exchanging fragments for a locked Support card: the rarer the card, the more fragments it costs
## (5 / 6 / ~7 / ~7 duplicates of the same rarity).
const FRAGMENT_PRICE := {"common": 50, "rare": 150, "epic": 400, "legendary": 1000}
## Crystals buy cards too (instead of coins): Support cards / unit cards, by rarity.
const CRYSTAL_PRICE := {"common": 1, "rare": 2, "epic": 4, "legendary": 10}
## Unit cards (the Shop sells every unit card except the starter ones): coins / fragments by rarity. Pawns are starter cards.
const UNIT_FRAGMENT_PRICE := {"rare": 120, "epic": 300}
const UNIT_CRYSTAL_PRICE := {"rare": 2, "epic": 4}
## What a pull costs: 1 Gacha Ticket per pull (the 10-pull costs 9 tickets).
const TICKET_PULL := 1
const TICKET_PULL10 := 9


## A unit card has a "chess" type, a Support card does not.
static func is_unit_card(card: Dictionary) -> bool:
	return card.has("chess")


## A King card (CardDatabase.king_card): collected like a card, its copies are its B level (B1 / B2 / B3, SaveManager.king_b).
static func is_king_card(card: Dictionary) -> bool:
	return bool(card.get("is_king", false))


static func fragment_price(card: Dictionary) -> int:
	var r := String(card.get("rarity", "common"))
	if is_unit_card(card) and not is_king_card(card):
		return int(UNIT_FRAGMENT_PRICE.get(r, 120))
	return int(FRAGMENT_PRICE.get(r, 50))


static func crystal_price(card: Dictionary) -> int:
	var r := String(card.get("rarity", "common"))
	if is_unit_card(card) and not is_king_card(card):
		return int(UNIT_CRYSTAL_PRICE.get(r, 2))
	return int(CRYSTAL_PRICE.get(r, 1))


## Any card by id (Support or unit).
static func card_by_id(card_id: String) -> Dictionary:
	var s := CardDatabase.get_support(card_id)
	if not s.is_empty():
		return s
	if CardDatabase.is_king(card_id):
		return CardDatabase.king_card(card_id)
	return CardDatabase.get_unit(card_id)


## King cards the Shop sells: the Kings of the continents opened on the trophy road. `only_incomplete`: only those below B3.
static func shop_kings(only_incomplete: bool = true) -> Array:
	var out: Array = []
	for c in GameData.continents:
		var cid := String(c["id"])
		if not c.get("playable", false) or not SaveManager.is_continent_unlocked(cid):
			continue
		for f in c.get("factions", []):
			var k := CardDatabase.king_card(String(f.get("champion", "")))
			if k.is_empty():
				continue
			if only_incomplete and SaveManager.king_b(String(k["id"])) >= SaveManager.KING_MAX_COPIES:
				continue
			out.append(k)
	return out


static func king_for_sale(card_id: String) -> bool:
	for k in shop_kings(false):
		if String(k["id"]) == card_id:
			return true
	return false


## What reaching a B level of a King gives (shown in the Gacha / Buy Card).
static func king_b_text(b: int) -> String:
	match b:
		1:
			return "B1: King card"
		2:
			return "B2: Battle Chess skill unlocked"
		3:
			return "B3: Territory skill unlocked"
	return ""


## Gives the player one copy of a King (first copy = B1). Returns the new B level, or 0 at B3 already.
static func _give_king_copy(card_id: String) -> int:
	if SaveManager.owned_count(card_id) == 0:
		SaveManager.unlock_card(card_id)
		return 1
	return SaveManager.add_king_copy(card_id)


## Unit cards the Shop can sell right now: not a starter card (Pawns, Solvaris), from a continent opened on the trophy road.
## Optionally one continent only. Not owned yet = locked.
static func shop_units(continent_id: String = "", only_locked: bool = true) -> Array:
	var out: Array = []
	for c in GameData.continents:
		var cid := String(c["id"])
		if not c.get("playable", false) or not SaveManager.is_continent_unlocked(cid):
			continue
		if continent_id != "" and continent_id != cid:
			continue
		for u in CardDatabase.units_of_continent(cid):
			if String(u["chess"]) == "pawn" or String(u["rarity"]) == "common":
				continue
			if only_locked and SaveManager.owned_count(String(u["id"])) > 0:
				continue
			out.append(u)
	return out


## Support cards the player does not own yet, in database order (optionally one category only).
static func locked_supports(category: String = "all") -> Array:
	var out: Array = []
	for s in CardDatabase.all_supports():
		if SaveManager.owned_count(String(s["id"])) == 0 and (category == "all" or String(s["category"]) == category):
			out.append(s)
	return out


## Buys a locked card with Crystals (cards can no longer be bought with coins). Returns "" on success or the reason it failed.
## Works for Support and unit cards.
static func buy(card_id: String) -> String:
	var s := card_by_id(card_id)
	if s.is_empty():
		return "Unknown card."
	if is_king_card(s):
		if not king_for_sale(card_id):
			return "This King is not in the Shop yet."
		if SaveManager.king_b(card_id) >= SaveManager.KING_MAX_COPIES:
			return "This King is already at B3."
		if not SaveManager.spend_currency("crystals", crystal_price(s)):
			return "Not enough Crystals."
		_give_king_copy(card_id)
		SaveManager.save_game()
		return ""
	if SaveManager.owned_count(card_id) > 0:
		return "You already own this card."
	if is_unit_card(s) and not unit_for_sale(card_id):
		return "This unit card is not in the Shop yet."
	if not SaveManager.spend_currency("crystals", crystal_price(s)):
		return "Not enough Crystals."
	SaveManager.unlock_card(card_id)
	SaveManager.save_game()
	return ""


## Exchanges Card Fragments for a locked card (Support or unit). Returns "" on success or the reason it failed.
static func exchange(card_id: String) -> String:
	var s := card_by_id(card_id)
	if s.is_empty():
		return "Unknown card."
	if is_king_card(s):
		if not king_for_sale(card_id):
			return "This King is not in the Shop yet."
		if SaveManager.king_b(card_id) >= SaveManager.KING_MAX_COPIES:
			return "This King is already at B3."
		if not SaveManager.spend_fragments(fragment_price(s)):
			return "Not enough Card Fragments."
		_give_king_copy(card_id)
		SaveManager.save_game()
		return ""
	if SaveManager.owned_count(card_id) > 0:
		return "You already own this card."
	if is_unit_card(s) and not unit_for_sale(card_id):
		return "This unit card is not in the Shop yet."
	if not SaveManager.spend_fragments(fragment_price(s)):
		return "Not enough Card Fragments."
	SaveManager.unlock_card(card_id)
	SaveManager.save_game()
	return ""


## True when the unit card is sold: its continent is open and it is not a starter / common card.
static func unit_for_sale(card_id: String) -> bool:
	for u in shop_units("", false):
		if String(u["id"]) == card_id:
			return true
	return false


## Pulls since the last `rarity` or better (rarity: "rare" | "epic" | "legendary").
static func pity(rarity: String = "epic") -> int:
	return int(SaveManager.data["shop"].get(String(PITY_KEYS[rarity]), 0))


## Pulls left until the guaranteed `rarity` or better.
static func pulls_to_pity(rarity: String = "epic") -> int:
	return maxi(int(PITY_LIMITS[rarity]) - pity(rarity), 1)


## `counters`: {"rare": n, "epic": n, "legendary": n} = pulls since the last Rare+ / Epic+ / Legendary.
## A reached Legendary pity wins over Epic, which wins over Rare.
static func roll_rarity(rng: RandomNumberGenerator, counters: Dictionary, min_index: int = 0) -> String:
	if int(counters.get("legendary", 0)) + 1 >= int(PITY_LIMITS["legendary"]):
		return "legendary"
	var lo := min_index
	if int(counters.get("epic", 0)) + 1 >= int(PITY_LIMITS["epic"]):
		lo = maxi(lo, 2)
	elif int(counters.get("rare", 0)) + 1 >= int(PITY_LIMITS["rare"]):
		lo = maxi(lo, 1)
	var total := 0
	for i in range(lo, RARITY_ORDER.size()):
		total += int(RATES[RARITY_ORDER[i]])
	var r := rng.randi() % total
	for i in range(lo, RARITY_ORDER.size()):
		r -= int(RATES[RARITY_ORDER[i]])
		if r < 0:
			return RARITY_ORDER[i]
	return RARITY_ORDER[RARITY_ORDER.size() - 1]


## One pull WITHOUT charging (use pull_batch). Returns {id, rarity, new, fragments} (fragments > 0 for a duplicate). The card may be a Support or a unit card.
static func _pull_one(rng: RandomNumberGenerator, min_index: int) -> Dictionary:
	var shop: Dictionary = SaveManager.data["shop"]
	var rarity := roll_rarity(rng, {"rare": pity("rare"), "epic": pity("epic"), "legendary": pity("legendary")}, min_index)
	var pool: Array = []
	for s in CardDatabase.all_supports():
		if String(s["rarity"]) == rarity:
			pool.append(s)
	for u in shop_units("", false):  # unit cards (Rare / Epic of the open continents) share the pool
		if String(u["rarity"]) == rarity:
			pool.append(u)
	for k in shop_kings(true):  # King cards (Legendary, Kings of the open continents below B3) share the pool too
		if String(k["rarity"]) == rarity:
			pool.append(k)
	if pool.is_empty():
		pool = CardDatabase.all_supports()
	var card: Dictionary = pool[rng.randi() % pool.size()]
	var rank := RARITY_ORDER.find(rarity)
	for pr in ["rare", "epic", "legendary"]:  # every counter resets when its rarity or better drops
		var key := String(PITY_KEYS[pr])
		shop[key] = 0 if rank >= RARITY_ORDER.find(pr) else int(shop.get(key, 0)) + 1
	shop["pulls"] = int(shop.get("pulls", 0)) + 1
	var id := String(card["id"])
	if is_king_card(card):  # a duplicate King raises its B level (B2 / B3); only past B3 does it turn into fragments
		var was_new := SaveManager.owned_count(id) == 0
		var b := _give_king_copy(id)
		if b > 0:
			return {"id": id, "rarity": String(card["rarity"]), "new": was_new, "fragments": 0, "king_b": b}
		var kf := int(DUPLICATE_FRAGMENTS[String(card["rarity"])])
		SaveManager.add_fragments(kf)
		return {"id": id, "rarity": String(card["rarity"]), "new": false, "fragments": kf, "king_b": 0}
	var is_new := SaveManager.owned_count(id) == 0
	var fragments := 0
	if is_new:
		SaveManager.unlock_card(id)
	else:
		fragments = int(DUPLICATE_FRAGMENTS[String(card["rarity"])])
		SaveManager.add_fragments(fragments)
	return {"id": id, "rarity": String(card["rarity"]), "new": is_new, "fragments": fragments}


static func ticket_price(count: int) -> int:
	return TICKET_PULL10 if count >= 10 else TICKET_PULL * count


## Pays and pulls `count` cards from the Gacha. [] when the player cannot pay. Paid with Gacha Tickets only. A batch of 10 always holds a Rare or better.
static func pull_batch(count: int, rng: RandomNumberGenerator) -> Array:
	if count < 1:
		return []
	if not SaveManager.spend_currency("tickets", ticket_price(count)):  # the Gacha only takes Gacha Tickets
		return []
	var out: Array = []
	var got_rare := false
	for i in range(count):
		var min_index := 1 if (count >= 10 and i == count - 1 and not got_rare) else 0
		var r := _pull_one(rng, min_index)
		if RARITY_ORDER.find(String(r["rarity"])) >= 1:
			got_rare = true
		out.append(r)
	EventHub.track("pulls", count)
	SaveManager.save_game()
	return out


# ------------------------------------------------------------------ Exchange (penukaran)

## Currency exchanges: `from_n` of `from` become `to_n` of `to` per pack. Coins <-> chips and fragments <-> coins lose a little on the
## round trip, so exchanging back and forth never makes money. Currency keys are the wallet keys.
const EXCHANGES := [
	{"id": "coins_ticket", "from": "coins", "from_n": 100, "to": "tickets", "to_n": 1},
	{"id": "coins_fragment", "from": "coins", "from_n": 50, "to": "fragments", "to_n": 10},
	{"id": "coins_chip", "from": "coins", "from_n": 100, "to": "chips", "to_n": 100},
	{"id": "fragment_coins", "from": "fragments", "from_n": 10, "to": "coins", "to_n": 20},
	{"id": "chip_coins", "from": "chips", "from_n": 100, "to": "coins", "to_n": 80},
]
const CURRENCY_NAMES := {"coins": "Aether Coins", "fragments": "Fragments", "tickets": "Gacha Tickets", "crystals": "Crystals", "chips": "Chips"}


static func exchange_spec(exchange_id: String) -> Dictionary:
	for e in EXCHANGES:
		if String(e["id"]) == exchange_id:
			return e
	return {}


## Whether `packs` packs of the exchange can be paid.
static func can_convert(exchange_id: String, packs: int) -> bool:
	var e := exchange_spec(exchange_id)
	return not e.is_empty() and packs >= 1 and SaveManager.currency(String(e["from"])) >= int(e["from_n"]) * packs


## Converts `packs` packs. Returns "" on success or the reason it failed.
static func convert_currency(exchange_id: String, packs: int) -> String:
	var e := exchange_spec(exchange_id)
	if e.is_empty() or packs < 1:
		return "Unknown exchange."
	if not SaveManager.spend_currency(String(e["from"]), int(e["from_n"]) * packs):
		return "Not enough %s." % String(CURRENCY_NAMES[String(e["from"])])
	SaveManager.add_currency(String(e["to"]), int(e["to_n"]) * packs)
	SaveManager.save_game()
	return ""


# ------------------------------------------------------------------ Auction (lelang): bid for locked cards with Crystals

const AUCTION_LOTS := 4  # cards on offer at the same time
const AUCTION_VALUE_MULT := 1  # market value in Crystals = the Crystal price of the card x this (Crystal prices are small: 1 / 2 / 4 / 10)
const AUCTION_OPEN := 0.4  # the first bid is 40% of the value (same as the Auction on the board)
const AUCTION_STEP := 0.10  # every raise is 10% of the value
const AUCTION_RIVAL_MIN := 0.6  # a rival's hidden limit is between 60% ...
const AUCTION_RIVAL_MAX := 1.3  # ... and 130% of the value


## What a card is worth at the Auction, in Crystals (its Buy-with-Crystals price: a lucky auction beats it, a bad one costs more).
static func auction_value(card: Dictionary) -> int:
	return crystal_price(card) * AUCTION_VALUE_MULT


static func auction_open(card: Dictionary) -> int:
	return maxi(1, roundi(float(auction_value(card)) * AUCTION_OPEN))


static func auction_step(card: Dictionary) -> int:
	return maxi(1, roundi(float(auction_value(card)) * AUCTION_STEP))


## The auction slot of now: the unix HOUR. The lots change every hour (the same for the whole hour).
static func auction_slot() -> int:
	return int(Time.get_unix_time_from_system() / 3600.0)


## Seconds until the lots change.
static func auction_seconds_left() -> int:
	return 3600 - (int(Time.get_unix_time_from_system()) % 3600)


## The lots of one hour (ids): random locked Support cards and unit cards the Shop sells, never Common. Same lots for the whole
## hour (`slot` = unix hour, see auction_slot), a new random set every hour.
static func auction_lots(slot: int) -> Array:
	var pool: Array = []
	for s in locked_supports():
		if String(s.get("rarity", "common")) != "common":
			pool.append(String(s["id"]))
	for u in shop_units():
		pool.append(String(u["id"]))
	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("auction_%d" % slot)
	var out: Array = []
	while out.size() < AUCTION_LOTS and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


## The hidden most a rival bidder will pay for this card.
static func auction_rival_limit(card: Dictionary, rng: RandomNumberGenerator) -> int:
	return roundi(float(auction_value(card)) * rng.randf_range(AUCTION_RIVAL_MIN, AUCTION_RIVAL_MAX))


## The rival's answer to the player's bid: the new bid, or 0 when the rival gives up (the player wins at `bid`).
static func auction_rival_reply(card: Dictionary, bid: int, limit: int) -> int:
	var next := bid + auction_step(card)
	return next if next <= limit else 0


## The player wins the lot at `price`. Returns "" on success or the reason it failed.
static func auction_win(card_id: String, price: int) -> String:
	var s := card_by_id(card_id)
	if s.is_empty():
		return "Unknown card."
	if SaveManager.owned_count(card_id) > 0:
		return "You already own this card."
	if not SaveManager.spend_currency("crystals", price):
		return "Not enough Crystals."
	SaveManager.unlock_card(card_id)
	SaveManager.save_game()
	return ""


# ------------------------------------------------------------------ Gamble (judi): quick mini games, Chips only

## Bets are paid and won in Chips only (turn winnings into coins with the Exchange tab). Every game has a small house edge
## (expected return a little under 100%), so it is fast money with real risk.
const GAMBLE_BETS := [100, 500, 1000, 5000]
const GAMBLE_GAMES := ["coin", "dice", "slots"]
const COIN_WIN_CHANCE := 0.48  # pays 2x the bet: expected return 96%
const DICE_PAYOUT := {"low": 2.3, "high": 2.3, "seven": 5.5}  # two dice: Low 2-6 / High 8-12 (15/36 each), Seven (6/36)
const SLOT_SYMBOLS := ["7", "BAR", "BELL", "GEM", "CLOVER", "CHERRY"]  # 3 reels, the 6 symbols are equally likely
const SLOT_JACKPOT := 30.0  # three 7s
const SLOT_TRIPLE := 8.0  # any other three of a kind
const SLOT_PAIR := 1.5  # exactly two alike
const SLOT_EXPECTED_RETURN := (SLOT_JACKPOT + 5.0 * SLOT_TRIPLE) / 216.0 + 90.0 / 216.0 * SLOT_PAIR  # about 95%


## "" when `game` and `choice` are valid, otherwise what is wrong with them.
static func gamble_pick_error(game: String, choice: String) -> String:
	if not GAMBLE_GAMES.has(game):
		return "Unknown game."
	if game == "coin" and choice not in ["heads", "tails"]:
		return "Pick heads or tails."
	if game == "dice" and not DICE_PAYOUT.has(choice):
		return "Pick Low, Seven or High."
	return ""


## One round of a Gamble game with `bet` of any currency, nothing is paid here. Shared by the Shop > Gamble tab (Chips) and the
## Territory Casino (Dominion Gold). Returns {"ok", "error", "win", "payout" (stake included), "net", "bet", "game", "detail"}.
static func gamble_round(game: String, choice: String, bet: int, rng: RandomNumberGenerator) -> Dictionary:
	var res := {"ok": false, "error": "", "win": false, "payout": 0, "net": 0, "bet": bet, "game": game, "detail": {}}
	res["error"] = gamble_pick_error(game, choice)
	if res["error"] == "" and bet < 1:
		res["error"] = "Pick a bet."
	if res["error"] != "":
		return res
	var payout := 0
	match game:
		"coin":
			var wins := rng.randf() < COIN_WIN_CHANCE
			var landed: String = choice if wins else ("tails" if choice == "heads" else "heads")
			res["detail"] = {"landed": landed}
			payout = bet * 2 if wins else 0
		"dice":
			var a := rng.randi_range(1, 6)
			var b := rng.randi_range(1, 6)
			var total := a + b
			var outcome := "low" if total < 7 else ("high" if total > 7 else "seven")
			res["detail"] = {"dice": [a, b], "total": total, "outcome": outcome}
			payout = int(floor(float(bet) * float(DICE_PAYOUT[choice]))) if outcome == choice else 0
		"slots":
			var reels: Array = []
			for i in range(3):
				reels.append(rng.randi() % SLOT_SYMBOLS.size())
			var kind := "none"
			if reels[0] == reels[1] and reels[1] == reels[2]:
				kind = "jackpot" if reels[0] == 0 else "triple"
				payout = int(floor(float(bet) * (SLOT_JACKPOT if reels[0] == 0 else SLOT_TRIPLE)))
			elif reels[0] == reels[1] or reels[1] == reels[2] or reels[0] == reels[2]:
				kind = "pair"
				payout = int(floor(float(bet) * SLOT_PAIR))
			res["detail"] = {"reels": reels, "symbols": reels.map(func(i): return SLOT_SYMBOLS[i]), "kind": kind}
	res["ok"] = true
	res["payout"] = payout
	res["net"] = payout - bet
	res["win"] = payout > bet
	return res


## Plays one round of the Shop > Gamble tab. Bets are paid and won in Chips; nothing is paid when ok is false.
static func gamble(game: String, choice: String, bet: int, rng: RandomNumberGenerator) -> Dictionary:
	var res := {"ok": false, "error": gamble_pick_error(game, choice), "win": false, "payout": 0, "net": 0, "bet": bet, "game": game, "detail": {}}
	if res["error"] == "" and not GAMBLE_BETS.has(bet):
		res["error"] = "Pick a bet."
	if res["error"] == "" and not SaveManager.spend_currency("chips", bet):
		res["error"] = "Not enough Chips."
	if res["error"] != "":
		return res
	res = gamble_round(game, choice, bet, rng)
	if int(res["payout"]) > 0:
		SaveManager.add_currency("chips", int(res["payout"]))
	SaveManager.save_game()
	return res
