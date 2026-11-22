class_name BattleGridView
extends Control
## Draws the 8x8 Battle Board with _draw(): deployment areas, units, HP bars, attack lines.

signal cell_pressed(cell: Vector2i)

const SIDE_COLORS: Array[Color] = [Color("3fa7d6"), Color("e5533d")]
const GLYPHS := {"pawn": "P", "rook": "R", "knight": "N", "bishop": "B", "queen": "Q", "king": "K"}

var prep: BattlePrep
var engine: BattleEngine
var selected: UnitInstance
var anim_speed: float = 1.0  # follows the battle speed buttons
var _vis: Dictionary = {}  # unit uid -> Vector2 (cell units): smoothly follows the unit's real cell
var _lunge: Dictionary = {}  # uid -> {"dir": Vector2, "t": float}: attack lunge
var _floaters: Array = []  # floating damage numbers {"cell": Vector2, "text": String, "t": float}
var _ghosts: Array = []  # fading rings where a unit fell
var _cell: float = 10.0
var _origin: Vector2 = Vector2.ZERO


func show_prep(p: BattlePrep) -> void:
	prep = p
	engine = null
	queue_redraw()


func show_engine(e: BattleEngine) -> void:
	engine = e
	prep = null
	_vis.clear()
	_lunge.clear()
	_floaters.clear()
	_ghosts.clear()
	for u in e.units:
		_vis[u.uid] = Vector2(u.cell)
	queue_redraw()


## Call after every engine step: starts the lunge / damage number / fall animations of this tick.
func notify_tick() -> void:
	if engine == null:
		return
	for ev in engine.events:
		match ev["type"]:
			"attack":
				var att: BattleUnit = engine.grid.get(ev["from"])
				if att != null:
					_lunge[att.uid] = {"dir": Vector2(ev["to"] - ev["from"]).normalized(), "t": 1.0}
				if int(ev["dmg"]) > 0:
					_floaters.append({"cell": Vector2(ev["to"]), "text": str(int(ev["dmg"])), "t": 0.0})
			"death":
				_ghosts.append({"cell": Vector2(ev["cell"]), "t": 0.0})
	set_process(true)


func _process(delta: float) -> void:
	if engine == null:
		set_process(false)
		return
	var k := maxf(anim_speed, 1.0)
	var busy := false
	for u in engine.units:
		if not u.alive:
			continue
		var target := Vector2(u.cell)
		var cur: Vector2 = _vis.get(u.uid, target)
		if cur.distance_to(target) > 5.5:
			cur = target  # teleports (Charge, Night Gallop, Rift Strike) are instant
		elif cur != target:
			cur = cur.move_toward(target, delta * 14.0 * k)
			busy = true
		_vis[u.uid] = cur
	for uid in _lunge.keys():
		_lunge[uid]["t"] = float(_lunge[uid]["t"]) - delta * 6.0 * k
		if float(_lunge[uid]["t"]) <= 0.0:
			_lunge.erase(uid)
		else:
			busy = true
	var keep: Array = []
	for f in _floaters:
		f["t"] = float(f["t"]) + delta * 1.6 * k
		if float(f["t"]) < 1.0:
			keep.append(f)
	_floaters = keep
	var keep_g: Array = []
	for g in _ghosts:
		g["t"] = float(g["t"]) + delta * 2.0 * k
		if float(g["t"]) < 1.0:
			keep_g.append(g)
	_ghosts = keep_g
	busy = busy or not _floaters.is_empty() or not _ghosts.is_empty()
	queue_redraw()
	if not busy:
		set_process(false)


func _visual_cell(u: BattleUnit) -> Vector2:
	var c: Vector2 = _vis.get(u.uid, Vector2(u.cell))
	if _lunge.has(u.uid):
		var t := float(_lunge[u.uid]["t"])
		c += (_lunge[u.uid]["dir"] as Vector2) * 0.28 * sin(PI * (1.0 - t))
	return c


func _layout() -> void:
	var s := minf(size.x, size.y)
	_cell = s / 8.0
	_origin = Vector2((size.x - s) * 0.5, (size.y - s) * 0.5)


func _center(c: Vector2) -> Vector2:
	return _origin + (Vector2(c.x, c.y) + Vector2(0.5, 0.5)) * _cell


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_layout()
		var p: Vector2 = (event.position - _origin) / _cell
		if p.x >= 0 and p.y >= 0 and p.x < 8 and p.y < 8:
			cell_pressed.emit(Vector2i(int(p.x), int(p.y)))


func _faction_color(faction: String) -> Color:
	var f := GameData.get_faction(CardDatabase.active_continent, faction)
	return Color(f.get("color", "#777788"))


func _draw() -> void:
	_layout()
	var font := ThemeDB.fallback_font
	for y in range(8):
		for x in range(8):
			var r := Rect2(_origin + Vector2(x, y) * _cell, Vector2(_cell, _cell))
			var base := Color("151c38") if (x + y) % 2 == 0 else Color("1a2342")
			var tint := Color(0.25, 0.65, 0.85, 0.10) if y >= 4 else Color(0.9, 0.3, 0.25, 0.10)
			draw_rect(r, base)
			draw_rect(r, tint)
			draw_rect(r, Color("2a3358"), false, 1.0)
	draw_line(_origin + Vector2(0, _cell * 4), _origin + Vector2(_cell * 8, _cell * 4), UiTheme.COL_GOLD_DIM, 3.0)
	if engine != null:
		for wc in engine.walls:
			var wr := Rect2(_origin + Vector2(wc.x, wc.y) * _cell, Vector2(_cell, _cell)).grow(-3.0)
			draw_rect(wr, Color("6b6f86"))
			draw_rect(wr, Color("b8bcd0"), false, 2.0)
		for u in engine.units:
			if u.alive:
				_draw_token(font, _visual_cell(u), u.side, u.chess, u.faction, u.stars, u.hp, u.max_hp, u.shield, u.is_king, false)
		for ev in engine.events:
			match ev["type"]:
				"attack":
					draw_line(_center(ev["from"]), _center(ev["to"]), Color(1, 0.95, 0.5, 0.9), 3.0)
					draw_circle(_center(ev["to"]), _cell * 0.18, Color(1, 0.3, 0.2, 0.8))
				"death":
					draw_circle(_center(ev["cell"]), _cell * 0.3, Color(1, 0.2, 0.2, 0.35))
				"fx":
					for c in ev["cells"]:
						draw_rect(Rect2(_origin + Vector2(c.x, c.y) * _cell, Vector2(_cell, _cell)), Color(1, 0.6, 0.1, 0.45))
		for g in _ghosts:
			var gt := float(g["t"])
			draw_arc(_center(g["cell"]), _cell * (0.25 + 0.35 * gt), 0.0, TAU, 24, Color(1, 0.3, 0.25, 1.0 - gt), 4.0)
		for f in _floaters:
			var ft := float(f["t"])
			var fp := _center(f["cell"]) + Vector2(-_cell * 0.3, -_cell * 0.3 - _cell * 0.55 * ft)
			draw_string_outline(font, fp, String(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, _cell * 0.6, int(_cell * 0.34), 4, Color(0, 0, 0, 1.0 - ft))
			draw_string(font, fp, String(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, _cell * 0.6, int(_cell * 0.34), Color(1.0, 0.92, 0.5, 1.0 - ft))
	elif prep != null:
		for u in prep.deployed_units():
			var card := CardDatabase.get_unit(u.card_id)
			var st := u.stats()
			_draw_token(font, Vector2(u.cell), 0, u.chess(), String(card["faction"]), u.stars, int(st["hp"]), int(st["hp"]), 0, false, u == selected)


func _draw_token(font: Font, c: Vector2, side: int, chess: String, faction: String, stars: int, hp: int, max_hp: int, shield: int, king: bool, selected_flag: bool) -> void:
	var ctr := _center(c)
	var radius := _cell * 0.36
	draw_circle(ctr, radius, _faction_color(faction).darkened(0.35))
	draw_arc(ctr, radius, 0.0, TAU, 24, SIDE_COLORS[side], 4.0 if not king else 6.0)
	if selected_flag:
		draw_arc(ctr, radius + 5, 0.0, TAU, 24, UiTheme.COL_GOLD, 3.0)
	Art.draw_piece(self, chess, Rect2(ctr - Vector2(radius, radius) * 0.92, Vector2(radius, radius) * 1.84), Color("f0e6c8"), _faction_color(faction).darkened(0.5))
	if stars > 1:
		draw_string(font, Vector2(ctr.x - radius, ctr.y - radius - 2), "*".repeat(stars), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(_cell * 0.3), UiTheme.COL_GOLD)
	var bar := Rect2(ctr.x - radius, ctr.y + radius + 3, radius * 2.0, 5)
	draw_rect(bar, Color(0, 0, 0, 0.7))
	var frac := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Color("59cd90") if frac > 0.5 else (Color("e8c547") if frac > 0.25 else Color("e5533d")))
	if shield > 0:
		draw_rect(Rect2(bar.position + Vector2(0, -3), Vector2(bar.size.x, 2)), Color("8fd0ff"))
