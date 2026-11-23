class_name BattleGridView
extends Control
## Draws the 8x8 Battle Board with _draw(): deployment areas, units, HP bars, attack lines.

signal cell_pressed(cell: Vector2i)

const SIDE_COLORS: Array[Color] = [Color("3fa7d6"), Color("e5533d")]
const GLYPHS := {"pawn": "P", "rook": "R", "knight": "N", "bishop": "B", "queen": "Q", "king": "K"}

var prep: BattlePrep
var engine: BattleEngine
var selected: UnitInstance
var own_faction: String = ""  # faction of the human side (its Champion's): shared pieces are drawn in its colour in preparation
var anim_speed: float = 1.0  # follows the battle speed buttons
var _vis: Dictionary = {}  # unit uid -> Vector2 (cell units): smoothly follows the unit's real cell
var _lunge: Dictionary = {}  # uid -> {"dir": Vector2, "t": float}: attack lunge
var _floaters: Array = []  # floating damage numbers {"cell": Vector2, "text": String, "t": float}
var _ghosts: Array = []  # fading rings where a unit fell
var _banner: Dictionary = {}  # {"text", "color", "t"}: big centre text (LAST STAND / CHECK / CHECKMATE / LAST PIECE)
var terrain: Dictionary = {}  # highland cells (Terrain); drawn as raised peak tiles
var inspect_unit: BattleUnit  # battle: the unit whose move / attack area is shown (tap a unit)
var _cell: float = 10.0
var _origin: Vector2 = Vector2.ZERO
var _skin: Dictionary = {}  # battle section of the active continent's MapSkin, see _bskin()
var _skin_id: String = "?"


func show_prep(p: BattlePrep) -> void:
	prep = p
	terrain = p.terrain
	inspect_unit = null
	engine = null
	queue_redraw()


func show_engine(e: BattleEngine) -> void:
	engine = e
	prep = null
	terrain = e.terrain
	inspect_unit = null
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
	var pro := FxMode.is_pro()  # Lite: no attack lunge and no fall rings (damage numbers and banners stay: they carry information)
	for ev in engine.events:
		match ev["type"]:
			"attack":
				var att: BattleUnit = engine.grid.get(ev["from"])
				if att != null and pro:
					_lunge[att.uid] = {"dir": Vector2(ev["to"] - ev["from"]).normalized(), "t": 1.0}
				if int(ev["dmg"]) > 0:
					_floaters.append({"cell": Vector2(ev["to"]), "text": str(int(ev["dmg"])), "t": 0.0})
			"death":
				if pro:
					_ghosts.append({"cell": Vector2(ev["cell"]), "t": 0.0})
			"last_stand":
				_show_banner("LAST STAND" if int(ev["side"]) == 0 else "ENEMY LAST STAND", Color("ff8a3d"))
			"last_piece":
				if int(ev["side"]) == 0:
					_show_banner("LAST PIECE", Color("e8c547"))
			"check":
				_show_banner("CHECK!", Color("ff4a4a") if int(ev["side"]) == 0 else Color("ffd35a"))
			"mate":
				_show_banner("CHECKMATE", Color("ff4a4a") if int(ev["side"]) == 0 else Color("59cd90"))
	set_process(true)


func _show_banner(text: String, col: Color) -> void:
	if not _banner.is_empty() and String(_banner["text"]) == "CHECKMATE":
		return
	_banner = {"text": text, "color": col, "t": 0.0}


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
		if cur.distance_to(target) > 5.5 or FxMode.is_lite():
			cur = target  # teleports (Charge, Night Gallop, Rift Strike) are instant; Lite: every move is
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
	if not _banner.is_empty():
		var hold := String(_banner["text"]) == "CHECKMATE"  # checkmate stays until the result screen opens
		_banner["t"] = float(_banner["t"]) + delta * 0.8 * k
		if float(_banner["t"]) >= 1.0:
			if hold:
				_banner["t"] = 0.5
			else:
				_banner = {}
	busy = busy or not _floaters.is_empty() or not _ghosts.is_empty() or not _banner.is_empty() or _any_check()
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


var _sb := StyleBoxFlat.new()


func _rr(r: Rect2, fill: Color, radius: float, border: Color = Color(0, 0, 0, 0), bw: float = 0.0, shadow: float = 0.0) -> void:
	_sb.bg_color = fill
	_sb.set_corner_radius_all(int(radius))
	_sb.set_border_width_all(int(bw))
	_sb.border_color = border
	_sb.anti_aliasing = true
	_sb.shadow_size = int(shadow)
	_sb.shadow_color = Color(0, 0, 0, 0.5)
	_sb.shadow_offset = Vector2(0, shadow * 0.4)
	draw_style_box(_sb, r)


## Battle section of the MapSkin of the continent being played (cached).
func _bskin() -> Dictionary:
	if _skin.is_empty() or CardDatabase.active_continent != _skin_id:
		_skin_id = CardDatabase.active_continent
		_skin = MapSkin.get_skin(_skin_id)["battle"]
	return _skin


func _draw() -> void:
	_layout()
	var font := ThemeDB.fallback_font
	var sk := _bskin()
	var crad := _cell * float(sk["radius"])
	_rr(Rect2(_origin, Vector2(_cell * 8, _cell * 8)).grow(_cell * 0.06), sk["frame_bg"], _cell * 0.22, sk["frame"], 2.0, _cell * 0.3)
	var gap := maxf(1.5, _cell * 0.03)
	var motif := MapSkin.motif_color(sk)
	for y in range(8):
		for x in range(8):
			var r := Rect2(_origin + Vector2(x, y) * _cell, Vector2(_cell, _cell)).grow(-gap)
			var light := (x + y) % 2 == 0
			var base: Color
			if y >= 4:
				base = sk["mine_light"] if light else sk["mine_dark"]  # your half: cool tones of the continent
			else:
				base = sk["foe_light"] if light else sk["foe_dark"]  # enemy half: warm red-violet tones
			_rr(r, base, crad, base.lightened(0.12), 1.0)
			MapSkin.draw_motif(self, String(sk["pattern"]), r, motif, x * 8 + y)
			if terrain.has(Vector2i(x, y)):
				_draw_highland(r)
	MapSkin.draw_watermark(self, CardDatabase.active_continent, Rect2(_origin + Vector2(_cell * 1.5, _cell * 1.5), Vector2(_cell * 5.0, _cell * 5.0)), sk, sk["frame_bg"])
	# deploy line: dashed gold
	var ly := _origin.y + _cell * 4.0
	var dash := _cell * 0.3
	var dx := 0.0
	while dx < _cell * 8:
		draw_line(Vector2(_origin.x + dx, ly), Vector2(_origin.x + minf(dx + dash, _cell * 8), ly), sk["line"], 3.0)
		dx += dash * 1.8
	_draw_areas(font, gap)
	_draw_check(gap)
	if engine != null:
		for wc in engine.walls:
			var wr := Rect2(_origin + Vector2(wc.x, wc.y) * _cell, Vector2(_cell, _cell)).grow(-gap - _cell * 0.06)
			_rr(wr, sk["wall"], _cell * 0.14, sk["wall_rim"], 2.0, _cell * 0.1)
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
		_draw_banner(font)
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
			_draw_token(font, Vector2(u.cell), 0, u.chess(), CardDatabase.effective_faction(card, own_faction), u.stars, int(st["hp"]), int(st["hp"]), 0, false, u == selected)


func _draw_token(font: Font, c: Vector2, side: int, chess: String, faction: String, stars: int, hp: int, max_hp: int, shield: int, king: bool, selected_flag: bool) -> void:
	var ctr := _center(c)
	var radius := _cell * 0.36
	draw_circle(ctr + Vector2(0, _cell * 0.07), radius, Color(0, 0, 0, 0.4))  # shadow
	draw_circle(ctr, radius, _faction_color(faction).darkened(0.35))
	draw_circle(ctr - Vector2(radius * 0.3, radius * 0.35), radius * 0.45, Color(1, 1, 1, 0.08))  # soft highlight
	draw_arc(ctr, radius, 0.0, TAU, 28, SIDE_COLORS[side], 4.0 if not king else 6.0)
	if king:
		draw_arc(ctr, radius + 4, 0.0, TAU, 28, Color(UiTheme.COL_GOLD, 0.7), 2.0)
	if selected_flag:
		draw_circle(ctr, radius + 8, Color(UiTheme.COL_GOLD, 0.18))
		draw_arc(ctr, radius + 6, 0.0, TAU, 28, UiTheme.COL_GOLD, 3.0)
	Art.draw_piece(self, chess, Rect2(ctr - Vector2(radius, radius) * 0.92, Vector2(radius, radius) * 1.84), Color("f0e6c8"), _faction_color(faction).darkened(0.5))
	if stars > 1:
		draw_string_outline(font, Vector2(ctr.x - radius, ctr.y - radius - 2), "*".repeat(stars), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(_cell * 0.32), 4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(ctr.x - radius, ctr.y - radius - 2), "*".repeat(stars), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, int(_cell * 0.32), UiTheme.COL_GOLD)
	# rounded HP bar
	var bar := Rect2(ctr.x - radius, ctr.y + radius + 4, radius * 2.0, maxf(6.0, _cell * 0.09))
	_rr(bar.grow(1.0), Color(0, 0, 0, 0.75), bar.size.y)
	var frac := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	if frac > 0.0:
		var hc := Color("59cd90") if frac > 0.5 else (Color("e8c547") if frac > 0.25 else Color("e5533d"))
		_rr(Rect2(bar.position, Vector2(maxf(bar.size.y, bar.size.x * frac), bar.size.y)), hc, bar.size.y)
	if shield > 0:
		_rr(Rect2(bar.position + Vector2(0, -4), Vector2(bar.size.x, 3)), Color("8fd0ff"), 2.0)


## Move area (blue dots / tint) and attack area (red tint + border) of the selected piece, under the tokens.
func _draw_areas(font: Font, gap: float) -> void:
	var chess := ""
	var from := Vector2i(-1, -1)
	var mv := 1
	var rng := 1
	var side := 0
	var blocked: Callable
	if engine != null and inspect_unit != null and inspect_unit.alive:
		var u := inspect_unit
		chess = u.chess
		from = u.cell
		mv = u.move
		rng = u.atk_range
		side = u.side
		var ur := u.atk_range
		blocked = func(c: Vector2i) -> bool: return engine.grid.has(c) or engine.walls.has(c) or not Terrain.can_stand(terrain, ur, c)
	elif prep != null and selected != null and selected.cell.x >= 0:
		chess = selected.chess()
		from = selected.cell
		mv = int(CardDatabase.get_unit(selected.card_id)["move"])
		rng = int(CardDatabase.get_unit(selected.card_id)["range"])
		var occupied := {}
		for o in prep.deployed_units():
			occupied[o.cell] = true
		blocked = func(c: Vector2i) -> bool: return occupied.has(c) or not Terrain.can_stand(terrain, rng, c)
	else:
		return
	var atk_col := Color("ff5a4a")
	var mov_col := Color("4fd6ff")
	for c in ChessMove.attack_cells(from, rng):
		var r := Rect2(_origin + Vector2(c.x, c.y) * _cell, Vector2(_cell, _cell)).grow(-gap)
		_rr(r, Color(atk_col, 0.16), _cell * 0.12, Color(atk_col, 0.55), 2.0)
	for c in ChessMove.move_cells(chess, from, mv, side, blocked):
		var r2 := Rect2(_origin + Vector2(c.x, c.y) * _cell, Vector2(_cell, _cell)).grow(-gap)
		_rr(r2, Color(mov_col, 0.28), _cell * 0.12, Color(mov_col, 0.9), 2.0)
		draw_circle(_center(Vector2(c)), _cell * 0.1, Color(mov_col, 0.95))
	draw_arc(_center(Vector2(from)), _cell * 0.44, 0.0, TAU, 28, UiTheme.COL_GOLD, 3.0)
	# legend
	var lw := _cell * 3.4
	var lr := Rect2(_origin + Vector2((_cell * 8 - lw) * 0.5, _cell * 8 + 4.0), Vector2(lw, _cell * 0.42))
	if lr.end.y > size.y:
		lr.position.y = _origin.y + _cell * 8 - lr.size.y - 2.0
	_rr(lr, Color(0, 0, 0, 0.6), 6.0)
	var fs := int(_cell * 0.26)
	draw_circle(lr.position + Vector2(_cell * 0.22, lr.size.y * 0.5), _cell * 0.09, mov_col)
	draw_string(font, lr.position + Vector2(_cell * 0.38, lr.size.y * 0.5 + fs * 0.35), "Move", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.COL_TEXT)
	_rr(Rect2(lr.position + Vector2(_cell * 1.75, lr.size.y * 0.5 - _cell * 0.09), Vector2(_cell * 0.18, _cell * 0.18)), Color(atk_col, 0.5), 2.0, atk_col, 1.5)
	draw_string(font, lr.position + Vector2(_cell * 2.0, lr.size.y * 0.5 + fs * 0.35), "Attack", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.COL_TEXT)


func _any_check() -> bool:
	return engine != null and (engine.in_check[0] or engine.in_check[1]) and not engine.finished


## "Check": the threatened Champion pulses red, a red line runs from every enemy that can hit it, and the board edge glows.
func _draw_check(gap: float) -> void:
	if engine == null or engine.finished:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
	for side in range(2):
		if not engine.in_check[side]:
			continue
		var k: BattleUnit = engine.kings[side]
		if k == null or not k.alive:
			continue
		var kc := _visual_cell(k)
		var red := Color("ff3b30")
		var kr := Rect2(_origin + Vector2(kc.x, kc.y) * _cell, Vector2(_cell, _cell)).grow(-gap)
		_rr(kr, Color(red, 0.18 + 0.22 * pulse), _cell * 0.12, Color(red, 0.9), 3.0)
		for t in engine.king_threats(side):
			var tc := _visual_cell(t)
			var a := _center(tc)
			var b := _center(kc)
			var dir := (b - a).normalized()
			var dist := a.distance_to(b)
			var d := 0.0
			while d < dist:  # dashed line threatener -> Champion
				draw_line(a + dir * d, a + dir * minf(d + _cell * 0.16, dist), Color(red, 0.85), 2.5)
				d += _cell * 0.3
			draw_arc(a, _cell * 0.42, 0.0, TAU, 24, Color(red, 0.8), 2.5)
		if side == 0:  # your Champion: glowing red board edge
			var br := Rect2(_origin, Vector2(_cell * 8, _cell * 8))
			draw_rect(br, Color(red, 0.25 + 0.45 * pulse), false, 4.0)


func _draw_banner(font: Font) -> void:
	if _banner.is_empty():
		return
	var t := float(_banner["t"])
	var col: Color = _banner["color"]
	var mate := String(_banner["text"]) == "CHECKMATE"
	var a := 1.0 if mate else clampf(minf(t * 6.0, (1.0 - t) * 3.0), 0.0, 1.0)  # quick fade in, fade out near the end
	var board := Rect2(_origin, Vector2(_cell * 8, _cell * 8))
	draw_rect(board, Color(0, 0, 0, 0.38 * a))  # dim the board behind the text
	var h := _cell * 1.3
	var band := Rect2(board.position.x, board.position.y + (board.size.y - h) * 0.5, board.size.x, h)
	draw_rect(band, Color(col.darkened(0.75), 0.82 * a))
	draw_rect(Rect2(band.position, Vector2(band.size.x, 3)), Color(col, a))
	draw_rect(Rect2(band.position + Vector2(0, band.size.y - 3), Vector2(band.size.x, 3)), Color(col, a))
	var fs := int(_cell * (0.78 + 0.12 * (1.0 - minf(t * 5.0, 1.0))))  # a small "pop" on entry
	var txt := String(_banner["text"])
	var p := Vector2(band.position.x, band.position.y + band.size.y * 0.5 + fs * 0.35)
	draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, band.size.x, fs, 6, Color(0, 0, 0, a))
	draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_CENTER, band.size.x, fs, Color(col.lightened(0.25), a))


## Highland: a raised, lighter tile with two small peaks and a bright rim.
func _draw_highland(r: Rect2) -> void:
	var sk := _bskin()
	var rim: Color = sk["highland_rim"]
	_rr(r, Color(sk["highland"], 0.30), _cell * float(sk["radius"]), Color(rim, 0.85), 2.0, _cell * 0.1)
	var cx := r.position.x + r.size.x * 0.5
	var by := r.position.y + r.size.y * 0.72
	var w := r.size.x * 0.34
	draw_colored_polygon(PackedVector2Array([Vector2(cx - w * 1.1, by), Vector2(cx - w * 0.35, by - r.size.y * 0.34), Vector2(cx + w * 0.2, by)]), Color(rim, 0.55))
	draw_colored_polygon(PackedVector2Array([Vector2(cx - w * 0.2, by), Vector2(cx + w * 0.5, by - r.size.y * 0.46), Vector2(cx + w * 1.2, by)]), Color(rim, 0.8))
