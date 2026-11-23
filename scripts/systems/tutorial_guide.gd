class_name TutorialGuide
extends RefCounted
## Contextual coach for the Tutorial match: each rule is explained the first time it appears.
## Pure logic (no UI): it watches a MatchController and emits `hint(id, text)`.
## Shown ids are stored in ctrl.tutorial_seen, so they survive Save/Continue.

signal hint(id: String, text: String)

const HINTS := {
	"welcome": "Welcome, ruler! Win by being the last ruler standing, or by having the highest net worth after 10 rounds. Each rule is explained the first time it appears. Tap ROLL DICE: two dice move your Champion clockwise around the 100-tile board.",
	"roll": "Your turn: tap ROLL DICE.",
	"rolled": "Dice rolled. Tap MOVE. (A Reroll Token lets you roll again first; doubles give a bonus roll.)",
	"buy": "Free territory! Buy it with Dominion Gold: rivals landing on it pay you rent. Owning 6 of the 10 lands of a region raises rent; all 10 give Regional Dominion.",
	"upgrade": "Your own land! Pay gold to upgrade it (Level 1-3, the last level is a Landmark): every level raises the rent rivals pay you.",
	"auction": "Auction House: a free territory is sold to the highest bidder. Bid, or pass. Every ruler can join.",
	"portal": "An active portal (purple)! Warp to another active portal. Portals move every round.",
	"shop": "Territory Shop: buy Reroll Tokens, a Special Die, or restore a lost Life.",
	"tile_event": "Event tile: a random card gives gold, moves you, or grants tokens.",
	"tile_tax": "Tax tile: the bank takes gold. Keep a reserve for taxes and rent.",
	"tile_special": "Special tile: a random bonus such as a gift, a teleport or tribute from rivals.",
	"tile_corner": "Corner tile: the Dominion Gate pays a bonus every lap, the Sanctuary pays gold, the Rift skips your next turn and the Crossroads warps you.",
	"encounter_wait": "You landed on a rival's territory. The OWNER chooses: collect Tax, or challenge you to a Duel.",
	"encounter_owner": "A rival landed on YOUR territory. Collect Tax, or challenge them to a Duel: the loser of a duel loses 1 Life.",
	"duel_response": "You were challenged to a Duel! Accept to fight (defeat costs 1 Life), or refuse and pay rent plus a penalty.",
	"duel_start": "DUEL! The armies fight on an 8x8 board. First prepare: buy units, deploy them on your half and lock the formation.",
	"conquest": "You won the Duel! Choose Conquest to take the land, or a Victory Reward for gold.",
	"special_die": "You received a Special Die! Before rolling you may use it: Swift boosts your move, Fortune gives gold, Warp teleports you, Order bends the turn order.",
	"life": "A Life was lost. At 0 Life a ruler is eliminated; you can restore Life in the Territory Shop.",
	"round": "A new round begins: the active portals shift. Round limit: the richest ruler wins.",
	"finish": "Tutorial complete! You know the core rules. Try a full match from NEW MATCH, or practise in Battle Practice.",
}

## Texts shown inside the Battle scene during a tutorial duel.
const BATTLE := {
	"prep": "Buy units with the gold you may spend (Budget). Tap a unit, then a cell on the BLUE half. Capacity limits how many fit; Level Up raises it. Auto Deploy picks a good formation. Then LOCK FORMATION.",
	"fight": "Units fight on their own. Your Champion joins only when all your units have fallen (Last Stand). Support cards cost Energy, which refills over time - tap a card to play it when you can afford it (the King skill uses Energy too). Same-category cards played back to back give energy back (combo).",
	"result": "Win: the attacker may take the land. Lose: -1 Life. A draw goes to the defender.",
}

var ctrl: MatchController


func _init(c: MatchController) -> void:
	ctrl = c
	ctrl.state_changed.connect(_on_state)
	ctrl.log_added.connect(_on_log)
	ctrl.game_over.connect(_on_game_over)  # a method, not a lambda: lambdas keep `self` alive (reference cycle)


func _on_game_over(_winner: int) -> void:
	_show("finish")


## Disconnect from the match (the UI calls this when the board is closed).
func detach() -> void:
	for pair in [[ctrl.state_changed, _on_state], [ctrl.log_added, _on_log], [ctrl.game_over, _on_game_over]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


func _show(id: String) -> void:
	if ctrl.tutorial_seen.has(id):
		return
	ctrl.tutorial_seen.append(id)
	hint.emit(id, String(HINTS[id]))


func _human_actor() -> bool:
	return not ctrl.decision_actor().is_ai


func _on_state() -> void:
	var p := ctrl.current_player()
	match ctrl.state:
		MatchController.State.AWAIT_ROLL:
			if not p.is_ai:
				_show("welcome" if not ctrl.tutorial_seen.has("welcome") else "roll")
		MatchController.State.ROLLED:
			if not p.is_ai:
				_show("rolled")
		MatchController.State.AWAIT_DECISION:
			_on_decision(p)
		MatchController.State.AWAIT_DUEL:
			if ctrl.is_human_duel():
				_show("duel_start")
		MatchController.State.TURN_DONE:
			if not p.is_ai:
				_on_tile(ctrl.tiles[p.position])


func _on_decision(p: PlayerState) -> void:
	match String(ctrl.pending.get("type", "")):
		"buy":
			if _human_actor():
				_show("buy")
		"upgrade":
			if _human_actor():
				_show("upgrade")
		"auction":
			if _human_actor():
				_show("auction")
		"portal":
			if _human_actor():
				_show("portal")
		"shop":
			if _human_actor():
				_show("shop")
		"encounter":
			_show("encounter_owner" if _human_actor() else "encounter_wait")
		"duel_response":
			if _human_actor():
				_show("duel_response")
		"conquest":
			if _human_actor():
				_show("conquest")


func _on_tile(t: BoardTile) -> void:
	match t.type:
		BoardTile.Type.EVENT:
			_show("tile_event")
		BoardTile.Type.TAX:
			_show("tile_tax")
		BoardTile.Type.SPECIAL:
			_show("tile_special")
		BoardTile.Type.CORNER:
			_show("tile_corner")


func _on_log(line: String) -> void:
	if line.contains("loses 1 Life"):
		_show("life")
	elif line.contains("receives a Special Die") and line.begins_with(ctrl.players[0].display_name):
		_show("special_die")
	elif line.begins_with("--- Round"):
		_show("round")
