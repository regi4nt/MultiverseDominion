class_name BattlePrep
extends RefCounted
## Battle Preparation state of one side: Battle Shop (5 offers), 10-slot Preparation Area (bench),
## deployment on the 4x8 area (rows 4..7), capacity, budget. Gold is the single currency
## (Dominion Gold); "budget" is only a spending cap taken from the gold the player owns.

var terrain: Dictionary = {}  # highland cells of this duel (see Terrain)
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
var hand: Array = []  # owned Support cards (shared with PlayerState.hand in a match)


func _init(d: Deck, r: RandomNumberGenerator, start_gold: int, budget: int, start_level: int,
		existing_roster: UnitRoster = null, existing_pile: BattleDeck = null, existing_hand: Variant = null) -> void:
	deck = d
	rng = r
	gold = start_gold
	budget_left = mini(budget, start_gold)
	level = start_level
	if existing_hand != null:
		hand = existing_hand
	if existing_roster != null:
		roster = existing_roster  # persistent army: units survive between duels
	battle_deck = existing_pile if existing_pile != null else BattleDeck.new(d, r)
	refresh_offers(false)


## Starter units: gives `count` random Pawns of the deck for free. Each one is deducted from the copies in the draw pile, so a type
## never exceeds its 9 copies and the Battle Shop cannot offer those copies again. If the deck has no Pawn, any unit type is used. Returns the ids that were given.
func give_starter_pawns(count: int) -> Array[String]:
	var given: Array[String] = []
	var ids := deck.effective_unit_ids()
	var pawns: Array[String] = []
	for id in ids:
		if String(CardDatabase.get_unit(id).get("chess", "")) == "pawn":
			pawns.append(id)
	if pawns.is_empty():
		pawns = ids
	if pawns.is_empty():
		return given
	finish()  # the 5 offers go back to the pile first, so every copy of a Pawn can be deducted
	for i in range(count):
		var id := pawns[rng.randi() % pawns.size()]
		if battle_deck.take_card(id):  # each given Pawn is one copy less in the pile (and so in the Battle Shop)
			roster.add_copy(id)
			given.append(id)
	refresh_offers(false)  # deal the shop again from what is left
	return given


## Series (Battle Chess 10 rounds / survival): between two rounds the army, gold, level and hand stay; the player earns
## income, the shop is dealt again and the free rerolls come back.
func start_next_round(income: int) -> void:
	finish()
	gold += income
	budget_left += income
	free_reroll = false
	free_rerolls_left = 0
	refresh_offers(false)


## Ends preparation: unbought offers go back to the pile.
func finish() -> void:
	var back: Array[String] = []
	for o in offers:
		if o != "":
			back.append(o)
	battle_deck.return_cards(back)
	offers = []


static func is_support_id(id: String) -> bool:
	return id != "" and not CardDatabase.is_unit(id) and CardDatabase.is_support(id)


func support_price(id: String) -> int:
	var prices: Dictionary = GameData.b("support_price")
	var base := float(prices.get(CardDatabase.get_support(id).get("rarity", "common"), 40))
	return maxi(1, int(round(base * price_mult)))


## Level the side needs to buy (and so to play) a Support card of this rarity.
func support_level_req(id: String) -> int:
	var req: Dictionary = GameData.b("support_level_req")
	return int(req.get(CardDatabase.get_support(id).get("rarity", "common"), 3))


func offer_price(id: String) -> int:
	return support_price(id) if is_support_id(id) else unit_price(id)


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
	if is_support_id(offers[index]):
		if level < support_level_req(offers[index]):
			return "Needs level %d." % support_level_req(offers[index])
		if hand.size() >= int(GameData.b("hand_max")):
			return "Support hand is full."
		return _spend_ok(support_price(offers[index]))
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
	if is_support_id(id):
		var sprice := support_price(id)
		gold -= sprice
		budget_left -= sprice
		offers[index] = ""
		hand.append(id)
		merge_log = []
		apply_hand([id])  # Mercenary Pact / Merchant Contract take effect right away
		return ""
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
	offers = battle_deck.draw_shop(-1, level)  # the rarity of the offers follows the shop level
	return true


## Preparation Supports (capacity / free rerolls) are spent the moment they are bought and cannot be sold.
func can_sell_support(id: String) -> bool:
	var eff := String(CardDatabase.get_support(id).get("effect", ""))
	return hand.has(id) and eff != "temp_capacity" and eff != "free_reroll"


func sell_support(id: String) -> void:
	if not can_sell_support(id):
		return
	var refund := int(support_price(id) * float(GameData.b("sell_ratio")))
	gold += refund
	budget_left += refund
	hand.erase(id)
	battle_deck.return_cards([id])


## After a battle: the Support cards that were played are consumed and return to the shop pile.
func consume_used(used: Array) -> void:
	for id in used:
		if hand.has(id):
			hand.erase(id)
			battle_deck.return_cards([String(id)])


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
	if not Terrain.can_stand(terrain, int(CardDatabase.get_unit(u.card_id)["range"]), cell):
		return "Highland: ranged roles only (Marksman, Mage, Support, Controller)."
	if u.cell.x < 0:
		if used_capacity() + CardDatabase.capacity_cost(u.chess()) > capacity():
			return "Not enough capacity (%d/%d)." % [used_capacity(), capacity()]
	u.cell = cell
	return ""


## Swaps the positions of two units: both on the board (cells exchanged) or one on the board and one on the bench
## (the bench unit takes the cell, the other goes back to the bench). Returns "" or the reason it is not allowed.
func swap_units(a: UnitInstance, b: UnitInstance) -> String:
	if a == b or a.cell.x < 0 and b.cell.x < 0:
		return ""
	if a.cell.x < 0:  # keep `a` as the unit that is on the board
		var t := a
		a = b
		b = t
	var ca := a.cell
	if not Terrain.can_stand(terrain, int(CardDatabase.get_unit(b.card_id)["range"]), ca):
		return "Highland: ranged roles only (Marksman, Mage, Support, Controller)."
	if b.cell.x >= 0:
		if not Terrain.can_stand(terrain, int(CardDatabase.get_unit(a.card_id)["range"]), b.cell):
			return "Highland: ranged roles only (Marksman, Mage, Support, Controller)."
		a.cell = b.cell
		b.cell = ca
		return ""
	if used_capacity() - CardDatabase.capacity_cost(a.chess()) + CardDatabase.capacity_cost(b.chess()) > capacity():
		return "Not enough capacity (%d/%d)." % [used_capacity(), capacity()]
	b.cell = ca
	a.cell = Vector2i(-1, -1)
	return ""


## A new duel brings new ground: sets the terrain and moves deployed melee units that now stand on a highland to a free plains cell.
func set_terrain(t: Dictionary) -> void:
	terrain = t
	for u in deployed_units():
		if Terrain.can_stand(terrain, int(CardDatabase.get_unit(u.card_id)["range"]), u.cell):
			continue
		var moved := false
		for row in range(AREA_MAX_ROW, AREA_MIN_ROW - 1, -1):
			for col in range(BattleEngine.COLS):
				var c := Vector2i(col, row)
				var free := not terrain.has(c)
				for o in roster.units:
					if o != u and o.cell == c:
						free = false
				if free:
					u.cell = c
					moved = true
					break
			if moved:
				break


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


func to_side_cfg(champion_id: String, supports: Array, champion_star: int = 1, monster_id: String = "", monster_star: int = 1) -> Dictionary:
	var list: Array = []
	for u in deployed_units():
		list.append({"card_id": u.card_id, "stars": u.stars, "cell": u.cell})
	return {"units": list, "champion": champion_id, "supports": supports, "champion_star": champion_star, "monster": monster_id, "monster_star": monster_star}
