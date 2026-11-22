class_name CardView
extends Control
## A card drawn with _draw() (no textures). Placeholder "illustration" = big glyph on faction colour.

signal pressed(card_id: String)

const RARITY_COLORS := {"common": Color("8d93ad"), "rare": Color("3f8fe0"), "epic": Color("a65cf0"), "legendary": Color("d4af37")}
const GLYPHS := {"pawn": "P", "rook": "R", "knight": "N", "bishop": "B", "queen": "Q"}

var card: Dictionary = {}
var is_support: bool = false
var owned: int = 0
var selected: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(150, 206)


func setup(c: Dictionary, support: bool, owned_count: int) -> void:
	card = c
	is_support = support
	owned = owned_count
	queue_redraw()


func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(String(card.get("id", "")))


func _faction_color() -> Color:
	var f := GameData.get_faction(CardDatabase.active_continent, String(card.get("faction", "")))
	return Color(f.get("color", "#555566"))


func _draw() -> void:
	if card.is_empty():
		return
	var font := ThemeDB.fallback_font
	var rect := Rect2(Vector2.ZERO, size)
	var base := Color("2a2f4a") if is_support else _faction_color().darkened(0.55)
	draw_rect(rect, base)
	var rar: Color = RARITY_COLORS.get(String(card.get("rarity", "common")), Color.GRAY)
	draw_rect(rect, UiTheme.COL_GOLD if selected else rar, false, 4.0 if selected else 3.0)
	# name
	draw_multiline_string(font, Vector2(8, 22), String(card["name"]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 15, 2, UiTheme.COL_TEXT)
	# illustration: procedural (see Art): faint continent emblem behind a chess-piece silhouette / category icon
	var art := Rect2(14, 50, size.x - 28, 72)
	draw_rect(art, base.lightened(0.15))
	var sq := Rect2(art.position.x + (art.size.x - 68.0) * 0.5, art.position.y + 2.0, 68.0, 68.0)
	if is_support:
		Art.draw_category(self, String(card["category"]), sq, rar.lightened(0.35), base.lightened(0.15))
	else:
		Art.draw_emblem(self, CardDatabase.active_continent, sq, Color(base.lightened(0.5), 0.3), base.lightened(0.15))
		Art.draw_piece(self, String(card["chess"]), sq, Color("f0e6c8"), base.darkened(0.35))
	# info
	if is_support:
		draw_string(font, Vector2(8, 142), String(card["category"]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 15, UiTheme.COL_GOLD)
		draw_string(font, Vector2(8, 164), "Uses: %d" % int(card["uses"]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 14, UiTheme.COL_TEXT)
	else:
		draw_string(font, Vector2(8, 142), "%s - %s" % [String(card["chess"]).capitalize(), card["role"]], HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 14, UiTheme.COL_GOLD)
		draw_string(font, Vector2(8, 164), "HP %d  ATK %d" % [int(card["hp"]), int(card["atk"])], HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 15, UiTheme.COL_TEXT)
		draw_string(font, Vector2(8, 184), "Rng %d  Mov %d" % [int(card["range"]), int(card["move"])], HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 13, UiTheme.COL_MUTED)
	draw_string(font, Vector2(8, size.y - 8), "x%d" % owned, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 16, 14, UiTheme.COL_TEXT)
	if owned <= 0:
		draw_rect(rect, Color(0, 0, 0, 0.62))
		draw_string(font, Vector2(0, size.y * 0.55), "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, UiTheme.COL_MUTED)
