class_name BattleDeck
extends RefCounted
## Runtime draw pile of the 135 unit cards used by the Battle Shop (5 cards per refresh).
## Unbought cards go back into the pile, so a unit type can never exceed its 9 copies.

var pool: Array[String] = []
var _rng: RandomNumberGenerator


func _init(deck: Deck, rng: RandomNumberGenerator) -> void:
	_rng = rng
	for id in deck.card_list():
		if CardDatabase.is_unit(id):
			pool.append(id)
	_shuffle()


func _shuffle() -> void:
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp


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
	for i in range(mini(count, pool.size())):
		out.append(pool.pop_back())
	return out


func return_cards(ids: Array[String]) -> void:
	pool.append_array(ids)
	_shuffle()
