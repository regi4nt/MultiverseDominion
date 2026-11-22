class_name ModeIcon
extends Control
## Round badge with a chess-piece silhouette (procedural, see Art). Used on the New Match mode cards.

var kind: String = "pawn"  # pawn | rook | knight | bishop | queen | king
var accent: Color = Color("d4af37")


func _init(p_kind: String = "pawn", p_accent: Color = Color("d4af37")) -> void:
	kind = p_kind
	accent = p_accent
	custom_minimum_size = Vector2(84, 84)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	draw_circle(c, s * 0.5, accent.darkened(0.7))
	draw_arc(c, s * 0.48, 0.0, TAU, 48, accent.darkened(0.2), 2.0, true)
	var r := Rect2(c - Vector2(s, s) * 0.36, Vector2(s, s) * 0.72)
	Art.draw_piece(self, kind, r, accent.lightened(0.3), accent.darkened(0.6))
