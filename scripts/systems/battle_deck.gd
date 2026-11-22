class_name BattleDeck
extends RefCounted
## Runtime draw pile of the 135 unit cards used by the Battle Shop (5 cards per refresh).
## Unbought cards go back into the pile, so a unit type can never exceed its 9 copies.

## Support cards of the Deck also show up in the Battle Shop rolls (see draw_shop). Tests that count units switch this off.
static var supports_in_shop: bool = true

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


func draw_shop(count: int = -1) -> Array[String]:
	if count < 0:
		count = int(GameData.b("shop_size"))
	var out: Array[String] = []
	var chance := float(GameData.b("shop_support_chance"))
	for i in range(count):
		if supports_in_shop and not support_pool.is_empty() and _rng.randf() < chance:
			out.append(support_pool.pop_back())  # a Support card takes this slot
		elif not pool.is_empty():
			out.append(pool.pop_back())
	return out


func return_cards(ids: Array[String]) -> void:
	for id in ids:
		if CardDatabase.is_unit(id):
			pool.append(id)
		else:
			support_pool.append(id)
	_shuffle()
