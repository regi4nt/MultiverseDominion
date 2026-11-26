class_name BattleDeck
extends RefCounted
## Runtime draw pile of the 135 unit cards used by the Battle Shop (5 cards per refresh).
## Unbought cards go back into the pile, so a unit type can never exceed its 9 copies.

## Support cards of the Deck also show up in the Battle Shop rolls (see draw_shop). Tests that count units switch this off.
static var supports_in_shop: bool = true
## Battle Shop rarity follows the player's level (balance.json "shop_rarity_odds"). Tests that need a plain draw switch it off.
static var level_odds_enabled: bool = true

var pool: Array[String] = []
var support_pool: Array[String] = []  # the Deck's Support cards that are not owned right now (shop offers / hand are outside)
var _rng: RandomNumberGenerator


func _init(deck: Deck, rng: RandomNumberGenerator) -> void:
	_rng = rng
	for id in deck.card_list():
		if CardDatabase.is_unit(id):
			pool.append(id)
	for sid in deck.support_ids:
		support_pool.append(String(sid))
	_shuffle()


func _shuffle() -> void:
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	for i in range(support_pool.size() - 1, 0, -1):
		var j2 := _rng.randi_range(0, i)
		var tmp2 := support_pool[i]
		support_pool[i] = support_pool[j2]
		support_pool[j2] = tmp2


## Removes one copy of a card from the pile (used for starter units). False if none left.
func take_card(id: String) -> bool:
	var i := pool.find(id)
	if i < 0:
		return false
	pool.remove_at(i)
	return true


func remaining() -> int:
	return pool.size()


## Rarity odds (percent weights) of the Battle Shop at a player level: balance.json "shop_rarity_odds" keyed by level (a level
## between two keys uses the nearest lower one, below the first key the first one). Empty = no table (uniform draw, the old behaviour).
static func odds_for_level(level: int) -> Dictionary:
	var table: Dictionary = GameData.b("shop_rarity_odds", {})
	if table.is_empty():
		return {}
	var best := -1
	var first := 9999
	for k in table.keys():
		var lv := int(String(k))
		first = mini(first, lv)
		if lv <= level and lv > best:
			best = lv
	return table.get(str(best if best >= 0 else first), {})


## Draws `count` offers. With `level` >= 0 the rarity of every offer is rolled from the level's odds first (higher level = more Rare /
## Epic / Legendary cards, like a TFT shop); a rarity that is not left in the pile is skipped and the odds renormalised. Without a
## level (-1) every card of the pile is equally likely. Drawn cards leave the pile, so a unit type still never exceeds its 9 copies.
func draw_shop(count: int = -1, level: int = -1) -> Array[String]:
	if count < 0:
		count = int(GameData.b("shop_size"))
	var odds: Dictionary = odds_for_level(level) if (level >= 0 and level_odds_enabled) else {}
	var out: Array[String] = []
	var chance := float(GameData.b("shop_support_chance"))
	for i in range(count):
		if supports_in_shop and not support_pool.is_empty() and _rng.randf() < chance:
			out.append(_take(support_pool, odds, true))  # a Support card takes this slot
		elif not pool.is_empty():
			out.append(_take(pool, odds, false))
	return out


## Removes and returns one card of `pile`: its rarity is rolled from `odds` (only rarities present in the pile count), then a random
## card of that rarity. No odds = a random card of the pile.
func _take(pile: Array[String], odds: Dictionary, support: bool) -> String:
	var idx := -1
	if not odds.is_empty():
		var by_rarity: Dictionary = {}  # rarity -> indices in the pile
		for j in range(pile.size()):
			var card := CardDatabase.get_support(pile[j]) if support else CardDatabase.get_unit(pile[j])
			var r := String(card.get("rarity", "common"))
			if not by_rarity.has(r):
				by_rarity[r] = []
			(by_rarity[r] as Array).append(j)
		var total := 0.0
		for r in by_rarity.keys():
			total += float(odds.get(r, 0))
		if total > 0.0:
			var roll := _rng.randf() * total
			for r in by_rarity.keys():
				roll -= float(odds.get(r, 0))
				if roll < 0.0:
					var list: Array = by_rarity[r]
					idx = int(list[_rng.randi_range(0, list.size() - 1)])
					break
	if idx < 0:
		idx = pile.size() - 1 if odds.is_empty() else _rng.randi_range(0, pile.size() - 1)
	var id := pile[idx]
	pile.remove_at(idx)
	return id


func return_cards(ids: Array[String]) -> void:
	for id in ids:
		if CardDatabase.is_unit(id):
			pool.append(id)
		else:
			support_pool.append(id)
	_shuffle()
