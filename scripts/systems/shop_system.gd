class_name ShopSystem
extends RefCounted
## Shop rules: Aether Coins (the persistent currency, earned by playing matches), the Support card Gacha, direct card purchase and Card Fragments (Gacha duplicates, exchanged for locked cards).
## All state lives in SaveManager.data ("wallet", "shop", "collection"). Every number the player can see is a constant here.

const START_COINS := 600  # mirrored by SaveManager.default_data()
const WIN_REWARD := 150
const PRACTICE_WIN_REWARD := 75    # Battle Chess (offline auto battle): Aether Coins for a win
const PRACTICE_LOSS_REWARD := 15  # ... for a loss or a draw
const LOSS_REWARD := 50
## Wager (Arena / Battle Chess): the stake is paid at the start; a win pays stake x odds (stake included).
const WAGER_STEPS := [50, 100, 250, 500, 1000]
const WAGER_DIFFICULTY_MULT := {"easy": 0.75, "normal": 1.0, "hard": 1.5}


## Win multiplier: 1 vs 1 / 2 vs 2 / Battle Chess x2, the 4 Player free-for-all x3, scaled by the AI difficulty.
static func wager_odds(kind: String, mode: String, _ai_count: int, difficulty: String) -> float:
	var base := 3.0 if (kind == "arena" and mode == "ffa_ai") else 2.0
	return base * float(WAGER_DIFFICULTY_MULT.get(difficulty, 1.0))


## Arena "Random map": a win on the drawn continent pays that continent's own bonus (data/continents.json "random_bonus":
## coins_pct, coins_flat, fragments, text). {} = none.
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
const PULL_PRICE := 100
const PULL10_PRICE := 900  # 10 pulls for the price of 9; the 10th is at least Rare
const PITY_LIMIT := 30  # the 30th pull without an Epic or better is guaranteed to be one
const RARITY_ORDER: Array[String] = ["common", "rare", "epic", "legendary"]
const RATES := {"common": 60, "rare": 28, "epic": 10, "legendary": 2}  # percent
## Direct purchase of a locked Support card (more expensive than the average Gacha pull: the card is guaranteed).
const BUY_PRICE := {"common": 200, "rare": 500, "epic": 1200, "legendary": 3000}
## A Gacha duplicate (card already owned) turns into Card Fragments: the rarer the card, the more fragments.
const DUPLICATE_FRAGMENTS := {"common": 10, "rare": 25, "epic": 60, "legendary": 150}
## Exchanging fragments for a locked Support card: the rarer the card, the more fragments it costs
## (5 / 6 / ~7 / ~7 duplicates of the same rarity).
const FRAGMENT_PRICE := {"common": 50, "rare": 150, "epic": 400, "legendary": 1000}


static func buy_price(card: Dictionary) -> int:
	return int(BUY_PRICE.get(String(card.get("rarity", "common")), 200))


static func fragment_price(card: Dictionary) -> int:
	return int(FRAGMENT_PRICE.get(String(card.get("rarity", "common")), 50))


## Support cards the player does not own yet, in database order (optionally one category only).
static func locked_supports(category: String = "all") -> Array:
	var out: Array = []
	for s in CardDatabase.all_supports():
		if SaveManager.owned_count(String(s["id"])) == 0 and (category == "all" or String(s["category"]) == category):
			out.append(s)
	return out


## Returns "" on success or the reason the purchase failed.
static func buy(card_id: String) -> String:
	var s := CardDatabase.get_support(card_id)
	if s.is_empty():
		return "Unknown card."
	if SaveManager.owned_count(card_id) > 0:
		return "You already own this card."
	if not SaveManager.spend_coins(buy_price(s)):
		return "Not enough Aether Coins."
	SaveManager.unlock_card(card_id)
	SaveManager.save_game()
	return ""


## Exchanges Card Fragments for a locked Support card. Returns "" on success or the reason it failed.
static func exchange(card_id: String) -> String:
	var s := CardDatabase.get_support(card_id)
	if s.is_empty():
		return "Unknown card."
	if SaveManager.owned_count(card_id) > 0:
		return "You already own this card."
	if not SaveManager.spend_fragments(fragment_price(s)):
		return "Not enough Card Fragments."
	SaveManager.unlock_card(card_id)
	SaveManager.save_game()
	return ""


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


## One pull WITHOUT charging (use pull_batch). Returns {id, rarity, new, fragments} (fragments > 0 for a duplicate).
static func _pull_one(rng: RandomNumberGenerator, min_index: int) -> Dictionary:
	var shop: Dictionary = SaveManager.data["shop"]
	var rarity := roll_rarity(rng, int(shop.get("pity", 0)), min_index)
	var pool: Array = []
	for s in CardDatabase.all_supports():
		if String(s["rarity"]) == rarity:
			pool.append(s)
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


static func batch_price(count: int) -> int:
	return PULL10_PRICE if count >= 10 else PULL_PRICE * count


## Pays and pulls `count` cards. [] when the player cannot pay. A batch of 10 always holds a Rare or better.
static func pull_batch(count: int, rng: RandomNumberGenerator) -> Array:
	if count < 1 or not SaveManager.spend_coins(batch_price(count)):
		return []
	var out: Array = []
	var got_rare := false
	for i in range(count):
		var min_index := 1 if (count >= 10 and i == count - 1 and not got_rare) else 0
		var r := _pull_one(rng, min_index)
		if RARITY_ORDER.find(String(r["rarity"])) >= 1:
			got_rare = true
		out.append(r)
	SaveManager.save_game()
	return out
