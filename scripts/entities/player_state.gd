class_name PlayerState
extends RefCounted
## Runtime state of one participant (human or AI) in a match.

var id: int = 0
var display_name: String = ""
var is_ai: bool = true
var difficulty: String = "normal"
var faction_id: String = ""
var champion_id: String = ""
var passive: String = ""
var passive_value: float = 0.0
var passive2: String = ""  # the King's second Territory skill (data/champions.json passive2): every King has a different pair
var passive2_value: float = 0.0
var color: Color = Color.WHITE

var position: int = 0
var gold: int = 0
var life: int = 3
var max_life: int = 3  # starting Life of the match difficulty (easy 5 / normal 3 / hard 1): the cap for every heal
var level: int = 3  # Chess Capacity data is prepared; used from Phase 4.
var capacity: int = 9
var reroll_tokens: int = 0
var extra_price_mult: float = 1.0  # Arena random map (Machina): extra Battle Shop discount, on top of the passive
var skip_turns: int = 0
var alive: bool = true
var team: int = -1  # 2vs2: 0 = Team A, 1 = Team B; -1 = free-for-all (no team)
var special_dice: Array[String] = []  # ids from data/special_dice.json, used before rolling
var stock_value: int = 0  # gold currently invested at the Bank (moves with the market every round)
var stock_basis: int = 0  # gold put in (for the profit / loss display)
var move_bonus: int = 0  # Swift Die: added to the next move
var commander_star: int = 1  # Commander stars 1..3, raised by missions (see CommanderSystem)
var mission_progress: int = 0  # progress of the ACTIVE Commander mission
var monster_star: int = 1  # King level (Commander star) when the Monster card was won: the ally keeps that level
var monster_id: String = ""  # Monster card won on a hidden territory monster (max one); it joins the King in a Duel

# Persistent army (Phase 5): units bought with Dominion Gold stay between duels.
var deck: Deck
var battle_deck: BattleDeck
var roster: UnitRoster
var hand: Array = []  # Support cards bought in the Battle Shop, kept until played in a battle


## Support cards played in a battle are consumed and go back into the shop pile.
func consume_supports(used: Array) -> void:
	for id in used:
		if hand.has(id):
			hand.erase(id)
			battle_deck.return_cards([String(id)])


func has_passive(passive_id: String) -> bool:
	return passive_id != "" and (passive == passive_id or passive2 == passive_id)


## Strength of a Territory skill of this King (0 when he does not have it).
func pv(passive_id: String) -> float:
	if passive_id == "":
		return 0.0
	if passive == passive_id:
		return passive_value
	if passive2 == passive_id:
		return passive2_value
	return 0.0


## Quartermaster passive: Battle Shop discount.
func battle_price_mult() -> float:
	return (1.0 - pv("quartermaster")) * extra_price_mult
