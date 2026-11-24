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
const SERIES_TEN_ROUNDS := 10
const SERIES_SURVIVAL_TARGET := 5  # survival wager is won by winning at least this many rounds in a row
const SERIES_INCOME := 150  # gold the player earns between two rounds ...
const SERIES_INCOME_STEP := 25  # ... plus this much per round already played
const SERIES_ROUND_BONUS := 25  # extra Aether Coins for a round won, from round 2 on (x round number), on top of practice_reward


## Gold earned after round `played` (1-based) to prepare the next one.
static func series_income(played: int) -> int:
	return SERIES_INCOME + SERIES_INCOME_STEP * (played - 1)


## Extra Aether Coins for winning round `round_no` of a 10-round / survival run (0 in a single battle and in round 1).
static func series_coin_bonus(id: String, round_no: int) -> int:
	return 0 if id == "single" or round_no < 2 else SERIES_ROUND_BONUS * round_no


static func series_title(id: String) -> String:
	match id:
		"ten":
			return "10 Rounds"
		"survival":
			return "Survival"
	return "1 Round"


static func series_desc(id: String) -> String:
	match id:
		"ten":
			return "10 battles in a row with the same army. More wins than losses wins the series."
		"survival":
			return "Battle after battle, the enemy grows stronger. The run ends at your first defeat."
	return "A single battle."


## Does the series go on after this round? `round_no` is the round just played (1-based), `won`/`lost` count rounds incl. this one.
static func series_continues(id: String, round_no: int, lost: int) -> bool:
	match id:
		"ten":
			return round_no < SERIES_TEN_ROUNDS
		"survival":
			return lost == 0
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


## Win multiplier: 1 vs 1 / 2 vs 2 / Battle Chess x2, the 4 Player free-for-all x3, scaled by the AI difficulty.
static func wager_odds(kind: String, mode: String, _ai_count: int, difficulty: String) -> float:
	var base := 3.0 if (kind == "arena" and mode == "ffa_ai") else 2.0
	return base * float(WAGER_DIFFICULTY_MULT.get(difficulty, 1.0))


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
## Card Gacha with three pools (mode): "mix" = Support + unit cards together, "unit" = unit cards only, "support" = Support cards only.
## "mix" and "support" roll the rarity with RATES (one shared pity); the card then comes from the pool of that rarity: every Support card, plus
## (mix only, Rare / Epic) the unit cards of the continents opened on the trophy road (see shop_units). "unit" has its own rates and pity (UNIT_RATES).
const PITY_LIMIT := 30  # the 30th pull without an Epic or better is guaranteed to be one
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
## Unit pool of the Card Gacha: only Rare and Epic unit cards of the continents opened on the trophy road; its pity is separate.
const UNIT_RATES := {"rare": 85, "epic": 15}  # percent
const UNIT_PITY_LIMIT := 20  # the 20th pull without an Epic is guaranteed to be one
const GACHA_MODES: Array[String] = ["mix", "unit", "support"]  # Unit + Support (one pool) | Unit only | Support only
## What a pull costs: 1 Gacha Ticket per pull (the 10-pull costs 9 tickets).
const TICKET_PULL := 1
const TICKET_PULL10 := 9


## A unit card has a "chess" type, a Support card does not.
static func is_unit_card(card: Dictionary) -> bool:
	return card.has("chess")


static func fragment_price(card: Dictionary) -> int:
	var r := String(card.get("rarity", "common"))
	if is_unit_card(card):
		return int(UNIT_FRAGMENT_PRICE.get(r, 120))
	return int(FRAGMENT_PRICE.get(r, 50))


static func crystal_price(card: Dictionary) -> int:
	var r := String(card.get("rarity", "common"))
	if is_unit_card(card):
		return int(UNIT_CRYSTAL_PRICE.get(r, 2))
	return int(CRYSTAL_PRICE.get(r, 1))


## Any card by id (Support or unit).
static func card_by_id(card_id: String) -> Dictionary:
	var s := CardDatabase.get_support(card_id)
	if not s.is_empty():
		return s
	return CardDatabase.get_unit(card_id)


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


static func pity() -> int:
	return int(SaveManager.data["shop"].get("pity", 0))


## Pulls left until the guaranteed Epic or better.
static func pulls_to_pity() -> int:
	return maxi(PITY_LIMIT - pity(), 1)


static func roll_rarity(rng: RandomNumberGenerator, pity_count: int, min_index: int = 0) -> String:
	var lo := min_index
	if pity_count + 1 >= PITY_LIMIT:
		lo = maxi(lo, 2)
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
static func _pull_one(rng: RandomNumberGenerator, min_index: int, mode: String = "mix") -> Dictionary:
	var shop: Dictionary = SaveManager.data["shop"]
	var rarity := roll_rarity(rng, int(shop.get("pity", 0)), min_index)
	var pool: Array = []
	for s in CardDatabase.all_supports():
		if String(s["rarity"]) == rarity:
			pool.append(s)
	if mode == "mix":
		for u in shop_units("", false):  # unit cards (Rare / Epic of the open continents) share the pool
			if String(u["rarity"]) == rarity:
				pool.append(u)
	if pool.is_empty():
		pool = CardDatabase.all_supports()
	var card: Dictionary = pool[rng.randi() % pool.size()]
	shop["pity"] = 0 if RARITY_ORDER.find(rarity) >= 2 else int(shop.get("pity", 0)) + 1
	shop["pulls"] = int(shop.get("pulls", 0)) + 1
	var id := String(card["id"])
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


# ------------------------------------------------------------------ Unit pool

static func unit_pity() -> int:
	return int(SaveManager.data["shop"].get("unit_pity", 0))


static func unit_pulls_to_pity() -> int:
	return maxi(UNIT_PITY_LIMIT - unit_pity(), 1)


## Rare or Epic (UNIT_RATES); the pity pull is always Epic.
static func roll_unit_rarity(rng: RandomNumberGenerator, pity_count: int) -> String:
	if pity_count + 1 >= UNIT_PITY_LIMIT:
		return "epic"
	var r := rng.randi() % (int(UNIT_RATES["rare"]) + int(UNIT_RATES["epic"]))
	return "rare" if r < int(UNIT_RATES["rare"]) else "epic"


## The unit pool can only pull cards of continents the trophy road has opened.
static func unit_gacha_ready() -> bool:
	return not shop_units("", false).is_empty()


## One unit-only pull WITHOUT charging. Same result shape as _pull_one (a duplicate turns into fragments).
static func _pull_unit(rng: RandomNumberGenerator) -> Dictionary:
	var shop: Dictionary = SaveManager.data["shop"]
	var rarity := roll_unit_rarity(rng, int(shop.get("unit_pity", 0)))
	var all_units := shop_units("", false)
	var pool: Array = all_units.filter(func(u): return String(u["rarity"]) == rarity)
	if pool.is_empty():
		pool = all_units
	var card: Dictionary = pool[rng.randi() % pool.size()]
	rarity = String(card["rarity"])
	shop["unit_pity"] = 0 if rarity == "epic" else int(shop.get("unit_pity", 0)) + 1
	shop["unit_pulls"] = int(shop.get("unit_pulls", 0)) + 1
	var id := String(card["id"])
	var is_new := SaveManager.owned_count(id) == 0
	var fragments := 0
	if is_new:
		SaveManager.unlock_card(id)
	else:
		fragments = int(DUPLICATE_FRAGMENTS[rarity])
		SaveManager.add_fragments(fragments)
	return {"id": id, "rarity": rarity, "new": is_new, "fragments": fragments}


## Pays and pulls `count` cards from the pool `mode` ("mix" | "unit" | "support"). [] when the player cannot pay (or, for "unit", no unit card
## is in the Shop yet). Paid with Gacha Tickets only. A mix / support batch of 10 always holds a Rare or better.
static func pull_batch(count: int, rng: RandomNumberGenerator, mode: String = "mix") -> Array:
	if count < 1 or not GACHA_MODES.has(mode) or (mode == "unit" and not unit_gacha_ready()):
		return []
	if not SaveManager.spend_currency("tickets", ticket_price(count)):  # the Gacha only takes Gacha Tickets
		return []
	var out: Array = []
	var got_rare := false
	for i in range(count):
		if mode == "unit":
			out.append(_pull_unit(rng))
			continue
		var min_index := 1 if (count >= 10 and i == count - 1 and not got_rare) else 0
		var r := _pull_one(rng, min_index, mode)
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


## Plays one round. Returns {"ok": bool, "error": String, "win": bool, "payout": int (chips back, stake included), "net": int,
## "bet": int, "game": String, "detail": Dictionary}. Nothing is paid when ok is false.
static func gamble(game: String, choice: String, bet: int, rng: RandomNumberGenerator) -> Dictionary:
	var res := {"ok": false, "error": "", "win": false, "payout": 0, "net": 0, "bet": bet, "game": game, "detail": {}}
	if not GAMBLE_GAMES.has(game):
		res["error"] = "Unknown game."
		return res
	if not GAMBLE_BETS.has(bet):
		res["error"] = "Pick a bet."
		return res
	if game == "coin" and choice not in ["heads", "tails"]:
		res["error"] = "Pick heads or tails."
		return res
	if game == "dice" and not DICE_PAYOUT.has(choice):
		res["error"] = "Pick Low, Seven or High."
		return res
	if not SaveManager.spend_currency("chips", bet):
		res["error"] = "Not enough Chips."
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
	if payout > 0:
		SaveManager.add_currency("chips", payout)
	SaveManager.save_game()
	res["ok"] = true
	res["payout"] = payout
	res["net"] = payout - bet
	res["win"] = payout > bet
	return res
