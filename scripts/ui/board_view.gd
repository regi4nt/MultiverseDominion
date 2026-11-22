class_name BoardView
extends Control
## Draws the 100-tile ring, ownership, active portals and player tokens with _draw()
## (no textures => tiny and fast on low-end Android). Tap a tile to inspect it.

signal tile_pressed(index: int)

var ctrl: MatchController
var selected_index: int = -1

var _visual_pos: Dictionary = {}  # player_id -> float tile position (animated)
var _busy: int = 0
var _cell: float = 10.0
var _origin: Vector2 = Vector2.ZERO


func bind(c: MatchController) -> void:
	ctrl = c
	for p in ctrl.players:
		_visual_pos[p.id] = float(p.position)
	ctrl.tiles_changed.connect(queue_redraw)
	ctrl.players_changed.connect(queue_redraw)
	ctrl.dice_rolled.connect(func(_a: int, _b: int): queue_redraw())
	ctrl.player_moved.connect(_on_player_moved)
	queue_redraw()


func is_busy() -> bool:
	return _busy > 0


func _on_player_moved(pid: int, from_i: int, to_i: int, warped: bool) -> void:
	var steps := posmod(to_i - from_i, BoardBuilder.TILES_TOTAL)
	if warped or steps == 0 or steps > 14:
		_visual_pos[pid] = float(to_i)
		queue_redraw()
		return
	_busy += 1
	var tw := create_tween()
	tw.tween_method(_set_vis.bind(pid), float(from_i), float(from_i + steps), 0.07 * steps)
	tw.finished.connect(_anim_done.bind(pid, to_i))


func _set_vis(v: float, pid: int) -> void:
	_visual_pos[pid] = v
	queue_redraw()


func _anim_done(pid: int, to_i: int) -> void:
	_visual_pos[pid] = float(to_i)
	_busy = maxi(_busy - 1, 0)
	queue_redraw()


func _layout() -> void:
	var s := minf(size.x, size.y)
	_cell = s / float(BoardBuilder.GRID)
	_origin = Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)


func tile_rect(i: int) -> Rect2:
	var g := BoardBuilder.grid_pos(i)
	return Rect2(_origin + Vector2(g.x, g.y) * _cell, Vector2(_cell, _cell))


func _gui_input(event: InputEvent) -> void:
	if ctrl == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_layout()
		for i in range(BoardBuilder.TILES_TOTAL):
			if tile_rect(i).grow(1.0).has_point(event.position):
				selected_index = i
				tile_pressed.emit(i)
				queue_redraw()
				return


func _tile_color(t: BoardTile) -> Color:
	match t.type:
		BoardTile.Type.CORNER: return Color("3a2a6b")
		BoardTile.Type.TERRITORY: return Color("1a2342")
		BoardTile.Type.PORTAL: return Color("1b1f3a")
		BoardTile.Type.SHOP: return Color("1f4a4a")
		BoardTile.Type.EVENT: return Color("4a3a1f")
		BoardTile.Type.AUCTION: return Color("5a2f4a")
		BoardTile.Type.TAX: return Color("5a2323")
		BoardTile.Type.SPECIAL: return Color("2f3f6a")
	return Color.GRAY


func _glyph(t: BoardTile) -> String:
	match t.type:
		BoardTile.Type.CORNER:
			return {"start": "GO", "sanctuary": "+", "rift": "R", "crossroads": "X"}.get(t.corner_kind, "")
		BoardTile.Type.SHOP: return "$"
		BoardTile.Type.EVENT: return "?"
		BoardTile.Type.AUCTION: return "A"
		BoardTile.Type.TAX: return "-"
		BoardTile.Type.SPECIAL: return "*"
	return ""


func _draw() -> void:
	_layout()
	var s := _cell * BoardBuilder.GRID
	draw_rect(Rect2(_origin, Vector2(s, s)), UiTheme.COL_BG_DEEP)
	if ctrl == null:
		return
	var font := ThemeDB.fallback_font
	for t in ctrl.tiles:
		_draw_tile(t, font)
	_draw_center(font)
	_draw_tokens()


func _draw_tile(t: BoardTile, font: Font) -> void:
	var r := tile_rect(t.index).grow(-1.0)
	draw_rect(r, _tile_color(t))
	if t.type == BoardTile.Type.TERRITORY:
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.28)), BoardBuilder.region_color(ctrl.continent, t.region))
		if t.owner_id >= 0:
			var oc: Color = ctrl.players[t.owner_id].color
			draw_rect(r, Color(oc, 0.45))
			draw_rect(r, oc, false, 2.0)
	var g := _glyph(t)
	if g != "":
		draw_string(font, Vector2(r.position.x, r.position.y + r.size.y * 0.72), g,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(_cell * 0.42), UiTheme.COL_TEXT)
	if t.type == BoardTile.Type.PORTAL:
		var c := r.get_center()
		if t.portal_active:
			draw_circle(c, _cell * 0.3, UiTheme.COL_PURPLE)
			draw_arc(c, _cell * 0.34, 0.0, TAU, 20, UiTheme.COL_GOLD, 2.0)
		else:
			draw_arc(c, _cell * 0.26, 0.0, TAU, 16, Color("4a4f75"), 1.5)
	if t.index == selected_index:
		draw_rect(r, UiTheme.COL_GOLD, false, 3.0)


func _draw_center(font: Font) -> void:
	var inner := Rect2(_origin + Vector2(_cell * 2, _cell * 2), Vector2(_cell * 22, _cell * 22))
	draw_rect(inner, Color(UiTheme.COL_PANEL, 0.9))
	draw_rect(inner, UiTheme.COL_GOLD_DIM, false, 2.0)
	draw_string(font, Vector2(inner.position.x, inner.position.y + _cell * 3), String(ctrl.continent.get("name", "")),
		HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, int(_cell * 1.6), UiTheme.COL_GOLD)
	var names := BoardBuilder.DEFAULT_REGION_NAMES
	for r in range(4):
		var counts: Array[String] = []
		for p in ctrl.players:
			counts.append(str(EconomySystem.region_count(ctrl.tiles, r, p.id)))
		var y := inner.position.y + _cell * (6.0 + r * 1.6)
		draw_rect(Rect2(inner.position.x + _cell, y - _cell * 0.8, _cell * 0.8, _cell * 0.8), BoardBuilder.region_color(ctrl.continent, r))
		var rname: String = ctrl.continent["regions"][r]["name"] if ctrl.continent.has("regions") else names[r]
		draw_string(font, Vector2(inner.position.x + _cell * 2.2, y), "%s - %s: %s" % [names[r], rname, " | ".join(counts)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(_cell * 0.7), UiTheme.COL_TEXT)
	# Dice faces
	if ctrl.last_dice.x > 0:
		for i in range(2):
			var v := ctrl.last_dice.x if i == 0 else ctrl.last_dice.y
			var dr := Rect2(inner.position + Vector2(inner.size.x * 0.5 - _cell * 3.2 + i * _cell * 3.4, _cell * 13), Vector2(_cell * 3, _cell * 3))
			draw_rect(dr, Color("e8e4d4"))
			draw_rect(dr, UiTheme.COL_GOLD, false, 2.0)
			draw_string(font, Vector2(dr.position.x, dr.position.y + _cell * 2.3), str(v),
				HORIZONTAL_ALIGNMENT_CENTER, dr.size.x, int(_cell * 2.0), Color("0b1020"))


func _draw_tokens() -> void:
	var offs: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for p in ctrl.players:
		if not p.alive:
			continue
		var idx := posmod(int(round(float(_visual_pos.get(p.id, p.position)))), BoardBuilder.TILES_TOTAL)
		var c := tile_rect(idx).get_center() + offs[p.id % 4] * _cell * 0.2
		draw_circle(c, _cell * 0.24, p.color)
		var ring := UiTheme.COL_GOLD if p.id == ctrl.current else Color.BLACK
		draw_arc(c, _cell * 0.24, 0.0, TAU, 16, ring, 2.5 if p.id == ctrl.current else 1.5)
