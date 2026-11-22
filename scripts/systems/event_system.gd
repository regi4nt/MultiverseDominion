class_name EventSystem
extends RefCounted
## Event deck (data/events.json). Effects are applied by MatchController.


static func draw(rng: RandomNumberGenerator) -> Dictionary:
	var deck: Array = GameData.events
	if deck.is_empty():
		return {"title": "Quiet Day", "effect": "none", "value": 0}
	return deck[rng.randi() % deck.size()]
