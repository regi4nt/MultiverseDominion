class_name UnitInstance
extends RefCounted
## A unit a player owns during a match (card + star level).

var card_id: String = ""
var stars: int = 1
var cell: Vector2i = Vector2i(-1, -1)  # (-1,-1) = on the bench / not deployed


func _init(id: String = "", s: int = 1) -> void:
	card_id = id
	stars = s


func chess() -> String:
	return CardDatabase.get_unit(card_id).get("chess", "pawn")


func stats() -> Dictionary:
	return CardDatabase.unit_stats(card_id, stars)
