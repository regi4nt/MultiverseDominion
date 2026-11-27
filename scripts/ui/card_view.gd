class_name CardView
extends Control
## A card drawn with _draw() (no textures). Placeholder "illustration" = big glyph on faction colour.

signal pressed(card_id: String)

const RARITY_COLORS := {"common": Color("8d93ad"), "rare": Color("3f8fe0"), "epic": Color("a65cf0"), "legendary": Color("d4af37")}
const GLYPHS := {"pawn": "P", "rook": "R", "knight": "N", "bishop": "B", "queen": "Q", "king": "K"}

var card: Dictionary = {}
var is_support: bool = false
var owned: int = 0
var selected: bool = false
## Compact mode (deck editor): a small tile with cost badge, art, name and one info line.
var compact: bool = false
var empty: bool = false  # compact only: an empty deck slot
var dim: bool = false  # compact only: the card is already in the deck


var _press_pos: Vector2 = Vector2.ZERO
var _tracking: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(150, 206)
	mouse_filter = Control.MOUSE_FILTER_PASS  # a drag that starts on a card must still scroll the list behind it


func setup(c: Dictionary, support: bool, owned_count: int) -> void:
	card = c
	is_support = support
	owned = owned_count
	queue_redraw()


func setup_compact(c: Dictionary, support: bool, owned_count: int, h: float) -> void:
	compact = true
	empty = false
	custom_minimum_size = Vector2(0, h)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup(c, support, owned_count)


func setup_empty(h: float) -> void:
	compact = true
	empty = true
	custom_minimum_size = Vector2(0, h)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_redraw()


func set_state(is_dim: bool, is_selected: bool) -> void:
	dim = is_dim
	selected = is_selected
	queue_redraw()


func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Select on RELEASE and only if the finger did not travel: scrolling the grid no longer selects (and redraws)
	# every card it starts on. Global coordinates, because the card itself moves under the finger while scrolling.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_tracking = true
			_press_pos = event.global_position
		else:
			if _tracking and event.global_position.distance_to(_press_pos) <= 12.0:
				pressed.emit(String(card.get("vkey", card.get("id", ""))))
			_tracking = false


func _faction_color() -> Color:
	if card.has("color"):
		return Color(String(card["color"]))
	if not is_support and CardDatabase.is_shared(card):
		return Color("7d86ad")  # shared piece: neutral steel-blue, it takes the colour of whoever fields it
	var f := GameData.get_faction(String(card.get("continent", CardDatabase.active_continent)), String(card.get("faction", "")))
	return Color(f.get("color", "#555566"))


func _draw() -> void:
	if compact:
		_draw_compact()
		return
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
		Art.draw_emblem(self, String(card.get("continent", CardDatabase.active_continent)), sq, Color(base.lightened(0.5), 0.3), base.lightened(0.15))
		Art.draw_piece(self, String(card["chess"]), sq, Color("f0e6c8"), base.darkened(0.35))
	# info
	if is_support:
		draw_string(font, Vector2(8, 142), String(card["category"]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 15, UiTheme.COL_GOLD)
		draw_string(font, Vector2(8, 164), "Uses: %d" % int(card["uses"]), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 14, UiTheme.COL_TEXT)
	else:
		draw_string(font, Vector2(8, 142), "%s - %s" % [String(card["chess"]).capitalize(), card["role"]], HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 14, UiTheme.COL_GOLD)
		draw_string(font, Vector2(8, 164), "HP %d  ATK %d" % [int(card["hp"]), int(card["atk"])], HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 15, UiTheme.COL_TEXT)
		draw_string(font, Vector2(8, 184), ChessMove.tag(String(card["chess"])), HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 13, UiTheme.COL_MUTED)
	draw_string(font, Vector2(8, size.y - 8), "x%d" % owned, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 16, 14, UiTheme.COL_TEXT)
	if owned <= 0:
		draw_rect(rect, Color(0, 0, 0, 0.62))
		draw_string(font, Vector2(0, size.y * 0.55), "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, UiTheme.COL_MUTED)


## Shrinks the font until the text fits `max_w` (never below 9 px).
func _fit(text: String, max_w: float, fs: int) -> int:
	var font := ThemeDB.fallback_font
	while fs > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	return fs


func _draw_compact() -> void:
	var font := ThemeDB.fallback_font
	var rect := Rect2(Vector2.ZERO, size)
	if empty or card.is_empty():
		draw_rect(rect, Color(1, 1, 1, 0.04))
		draw_rect(rect, Color(UiTheme.COL_MUTED, 0.9 if selected else 0.45), false, 2.0)
		draw_string(font, Vector2(0, size.y * 0.5 + 11.0), "+", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color(UiTheme.COL_MUTED, 0.7))
		return
	var base := Color("2a2f4a") if is_support else _faction_color().darkened(0.55)
	var rar: Color = RARITY_COLORS.get(String(card.get("rarity", "common")), Color.GRAY)
	draw_rect(rect, base)
	var a := clampf(size.y - 40.0, 28.0, 46.0)
	var art := Rect2((size.x - a) * 0.5, 5.0, a, a)
	draw_rect(art, base.lightened(0.15))
	if is_support:
		Art.draw_category(self, String(card["category"]), art, rar.lightened(0.35), base.lightened(0.15))
	else:
		Art.draw_emblem(self, String(card.get("continent", CardDatabase.active_continent)), art, Color(base.lightened(0.5), 0.3), base.lightened(0.15))
		Art.draw_piece(self, String(card["chess"]), art, Color("f0e6c8"), base.darkened(0.35))
	if not is_support and card.get("badge", true):
		# cost badge (capacity cost of the piece)
		draw_circle(Vector2(15, 15), 11.0, Color("1a1405"))
		draw_arc(Vector2(15, 15), 11.0, 0.0, TAU, 20, UiTheme.COL_GOLD, 2.0)
		draw_string(font, Vector2(5, 20), str(CardDatabase.capacity_cost(String(card["chess"]))), HORIZONTAL_ALIGNMENT_CENTER, 20, 14, UiTheme.COL_GOLD)
	var cname := String(card["name"])
	var y := 5.0 + a + 15.0
	draw_string(font, Vector2(4, y), cname, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, _fit(cname, size.x - 8, 13), UiTheme.COL_TEXT)
	var sub := String(card["sub"]) if card.has("sub") else (String(card["category"]) if is_support else "%s - %s" % [String(card["chess"]).capitalize(), card["role"]])
	draw_string(font, Vector2(4, y + 13.0), sub, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, _fit(sub, size.x - 8, 11), UiTheme.COL_MUTED)
	if dim:
		draw_rect(rect, Color(0, 0, 0, 0.55))
	if owned <= 0:
		draw_rect(rect, Color(0, 0, 0, 0.62))
		draw_string(font, Vector2(0, size.y * 0.5 + 5.0), "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, UiTheme.COL_MUTED)
	var edge: Color = Color(String(card["color"])).lightened(0.3) if card.has("color") else rar  # faction tiles: faction colour (every King is Legendary)
	draw_rect(rect, UiTheme.COL_GOLD if selected else edge, false, 3.0 if selected else 2.0)
	if selected:
		draw_rect(rect.grow(-4.0), Color(1, 1, 1, 0.85), false, 1.5)
