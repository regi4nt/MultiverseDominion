class_name PieceIcon
extends Control
## Chess-piece silhouette (procedural, see Art) tinted with a rarity colour. Used inside the bench buttons
## so that a unit is shown by its piece + rarity instead of text (shop offers are plain text).

var kind: String = "pawn"  # pawn | rook | knight | bishop | queen | king
var tint: Color = Color("8d93ad")


func _init(p_kind: String = "pawn", p_tint: Color = Color("8d93ad")) -> void:
	kind = p_kind
	tint = p_tint
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := Rect2(c - Vector2(s, s) * 0.58, Vector2(s, s) * 1.16)  # Art pieces fill ~60-70% of their rect
	Art.draw_piece(self, kind, r, tint.lightened(0.35), tint.darkened(0.65))
