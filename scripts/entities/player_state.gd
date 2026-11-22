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
var color: Color = Color.WHITE

var position: int = 0
var gold: int = 0
var life: int = 3
var level: int = 3  # Chess Capacity data is prepared; used from Phase 4.
var capacity: int = 9
var reroll_tokens: int = 0
var skip_turns: int = 0
var alive: bool = true
var special_dice: Array[String] = []  # ids from data/special_dice.json, used before rolling
var move_bonus: int = 0  # Swift Die: added to the next move

# Persistent army (Phase 5): units bought with Dominion Gold stay between duels.
var deck: Deck
var battle_deck: BattleDeck
var roster: UnitRoster


func has_passive(passive_id: String) -> bool:
	return passive == passive_id


## Quartermaster passive: Battle Shop discount.
func battle_price_mult() -> float:
	return 1.0 - passive_value if passive == "quartermaster" else 1.0
