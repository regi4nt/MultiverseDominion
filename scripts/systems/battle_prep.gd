class_name BattlePrep
extends RefCounted
## Battle Preparation state of one side: Battle Shop (5 offers), 10-slot Preparation Area (bench),
## deployment on the 4x8 area (rows 4..7), capacity, budget. Gold is the single currency
## (Dominion Gold); "budget" is only a spending cap taken from the gold the player owns.

const AREA_MIN_ROW := 4
const AREA_MAX_ROW := 7

var rng: RandomNumberGenerator
var deck: Deck
var battle_deck: BattleDeck
var roster := UnitRoster.new()
var gold: int = 0
var budget_left: int = 0
var level: int = 3
var offers: Array[String] = []
var free_reroll: bool = false  # true while at least one free Battle Shop reroll is left
var free_rerolls_left: int = 0
var merge_log: Array[String] = []
var price_mult: float = 1.0  # Quartermaster passive
var capacity_bonus: int = 0  # Mercenary Pact (Support card applied during preparation)


func _init(d: Deck, r: RandomNumberGenerator, start_gold: int, budget: int, start_level: int,
		existing_roster: UnitRoster = null, existing_pile: BattleDeck = null) -> void:
	deck = d
	rng = r
	gold = start_gold
	budget_left = mini(budget, start_gold)
	level = start_level
	if existing_roster != null:
		roster = existing_roster  # persistent army: units survive between duels
	battle_deck = existing_pile if existing_pile != null else BattleDeck.new(d, r)
	refresh_offers(false)


## Ends preparation: unbought offers go back to the pile.
func finish() -> void:
	var back: Array[String] = []
	for o in offers:
		if o != "":
			back.append(o)
	battle_deck.return_cards(back)
	offers = []


func unit_price(card_id: String) -> int:
	var prices: Dictionary = GameData.b("unit_price")
	var base := float(prices.get(CardDatabase.get_unit(card_id).get("rarity", "common"), 30))
	return maxi(1, int(round(base * price_mult * WorldMods.unit_price_mult)))


func capacity() -> int:
	return CapacitySystem.capacity_for_level(level) + capacity_bonus


## Support cards that act during preparation (the engine marks them as used).
func apply_hand(hand: Array) -> void:
	for id in hand:
		var s := CardDatabase.get_support(String(id))
		match String(s.get("effect", "")):
			"temp_capacity":
				capacity_bonus += int(s.get("value", 0))
			"free_reroll":
				free_rerolls_left += maxi(int(s.get("value", 1)), 1)
				free_reroll = true


func deployed_units() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	for u in roster.units:
		if u.cell.x >= 0:
			out.append(u)
	return out


func bench_units() -> Array[UnitInstance]:
	var out: Array[UnitInstance] = []
	for u in roster.units:
		if u.cell.x < 0:
			out.append(u)
	return out


func used_capacity() -> int:
	return CapacitySystem.used(deployed_units())


func _spend_ok(price: int) -> String:
	if gold < price:
		return "Not enough gold."
	if budget_left < price:
		return "Battle budget exceeded."
	return ""


func _would_merge(card_id: String) -> bool:
	var tmp := UnitRoster.new()
	for u in roster.units:
		tmp.units.append(UnitInstance.new(u.card_id, u.stars))
	var before := tmp.units.size()
	tmp.add_copy(card_id)
	return tmp.units.size() < before + 1


## "" = can buy, otherwise the reason.
func can_buy(index: int) -> String:
	if index < 0 or index >= offers.size() or offers[index] == "":
		return "Empty slot."
	var err := _spend_ok(unit_price(offers[index]))
	if err != "":
		return err
	if bench_units().size() >= int(GameData.b("prep_slots")) and not _would_merge(offers[index]):
		return "Preparation Area is full."
	return ""


func buy(index: int) -> String:
	var err := can_buy(index)
	if err != "":
		return err
	var id := offers[index]
	var price := unit_price(id)
	gold -= price
	budget_left -= price
	offers[index] = ""
	merge_log = roster.add_copy(id)
	return ""


func refresh_offers(paid: bool) -> bool:
	if paid:
		var cost := 0 if free_reroll else int(GameData.b("battle_reroll_price"))
		if _spend_ok(cost) != "":
			return false
		gold -= cost
		budget_left -= cost
		if free_reroll:
			free_rerolls_left -= 1
			free_reroll = free_rerolls_left > 0
	var back: Array[String] = []
	for o in offers:
		if o != "":
			back.append(o)
	battle_deck.return_cards(back)
	offers = battle_deck.draw_shop()
	return true


func sell(u: UnitInstance) -> void:
	var copies := UnitRoster.copies_value(u.stars)
	var refund := int(unit_price(u.card_id) * copies * float(GameData.b("sell_ratio")))
	gold += refund
	budget_left += refund
	var back: Array[String] = []
	for i in range(copies):
		back.append(u.card_id)
	battle_deck.return_cards(back)  # cards return to the pile: a type never exceeds 9 copies
	roster.remove_unit(u)


func deploy(u: UnitInstance, cell: Vector2i) -> String:
	if cell.x < 0 or cell.x >= BattleEngine.COLS or cell.y < AREA_MIN_ROW or cell.y > AREA_MAX_ROW:
		return "Outside your deployment area."
	for o in roster.units:
		if o != u and o.cell == cell:
			return "Cell is occupied."
	if u.cell.x < 0:
		if used_capacity() + CardDatabase.capacity_cost(u.chess()) > capacity():
			return "Not enough capacity (%d/%d)." % [used_capacity(), capacity()]
	u.cell = cell
	return ""


func return_to_bench(u: UnitInstance) -> String:
	if u.cell.x < 0:
		return ""
	if bench_units().size() >= int(GameData.b("prep_slots")):
		return "Preparation Area is full."
	u.cell = Vector2i(-1, -1)
	return ""


func level_up_cost() -> int:
	return int(GameData.b("level_up_base")) * (level - 2)


func level_up() -> String:
	if level >= int(GameData.b("max_level")):
		return "Maximum level."
	var err := _spend_ok(level_up_cost())
	if err != "":
		return err
	gold -= level_up_cost()
	budget_left -= level_up_cost()
	level += 1
	return ""


func to_side_cfg(champion_id: String, supports: Array) -> Dictionary:
	var list: Array = []
	for u in deployed_units():
		list.append({"card_id": u.card_id, "stars": u.stars, "cell": u.cell})
	return {"units": list, "champion": champion_id, "supports": supports}
