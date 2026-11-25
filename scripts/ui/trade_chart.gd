extends Control
## Live price chart of the Shop > Trading tab: the line scrolls with the real clock, the head pulses, the area glows green / red,
## your entry price is a gold dashed line. Buying flies chips into the head, a profitable sale bursts sparkles and floats "+N",
## a loss falls red and shakes the chart. Pure drawing: prices come from TradeSystem. Lite effects mode skips particles and redraws twice a second.

const UP := Color("59cd90")
const DOWN := Color("ef5b4f")
const GOLD := Color("d4af37")
const POINTS := 120

var asset_id: String = "aeth"
var range_sec: float = 60.0
var entry_price: float = -1.0  # average entry of the open position, -1 = none

var _prices := PackedFloat32Array()
var _lo := 0.0
var _hi := 1.0
var _have_range := false
var _first := 0.0
var _last := 0.0
var _parts: Array = []  # particles: {kind, pos, from, to, vel, life, max, delay, col, r}
var _texts: Array = []  # floating texts: {text, pos, life, max, col, size}
var _shake := 0.0
var _flash := 0.0
var _flash_col := Color.WHITE
var _pulse := 0.0
var _acc := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	custom_minimum_size = Vector2(0, 300)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_rng.randomize()
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	_sample()


func set_asset(id: String) -> void:
	asset_id = id
	_have_range = false
	_parts.clear()
	_texts.clear()
	_sample()
	queue_redraw()


func set_range(sec: float) -> void:
	range_sec = sec
	_have_range = false
	_sample()
	queue_redraw()


func set_entry(p: float) -> void:
	entry_price = p
	queue_redraw()


func last_price() -> float:
	return _last


func _sample() -> void:
	var t := TradeSystem.now()
	_prices.resize(POINTS)
	var lo := INF
	var hi := -INF
	for i in range(POINTS):
		var p := TradeSystem.price(asset_id, t - range_sec + range_sec * float(i) / float(POINTS - 1))
		_prices[i] = p
		lo = minf(lo, p)
		hi = maxf(hi, p)
	if entry_price > 0.0:
		lo = minf(lo, entry_price)
		hi = maxf(hi, entry_price)
	var pad := (hi - lo) * 0.14 + 0.05
	lo -= pad
	hi += pad
	if not _have_range:
		_lo = lo
		_hi = hi
		_have_range = true
	else:  # the scale glides instead of jumping
		_lo = lerpf(_lo, lo, 0.12)
		_hi = lerpf(_hi, hi, 0.12)
	_first = _prices[0]
	_last = _prices[POINTS - 1]


func _plot() -> Rect2:
	return Rect2(12.0, 18.0, maxf(size.x - 112.0, 50.0), maxf(size.y - 44.0, 50.0))


func _pt(i: int, r: Rect2) -> Vector2:
	var y := r.end.y - (float(_prices[i]) - _lo) / maxf(_hi - _lo, 0.0001) * r.size.y
	return Vector2(r.position.x + r.size.x * float(i) / float(POINTS - 1), y)


func _y_of(p: float, r: Rect2) -> float:
	return r.end.y - (p - _lo) / maxf(_hi - _lo, 0.0001) * r.size.y


func head_pos() -> Vector2:
	return _pt(POINTS - 1, _plot())


## kind: "buy" (chips fly into the head), "win" (sparkle burst + "+N"), "loss" (red fall + shake + "-N"), "flat".
func play_fx(kind: String, amount: int) -> void:
	var r := _plot()
	var head := head_pos()
	_flash = 1.0
	match kind:
		"buy":
			_flash_col = GOLD
			for i in range(8):
				_parts.append({"kind": "chip", "from": Vector2(r.position.x + 10.0, r.end.y - 8.0), "to": head, "pos": Vector2.ZERO, "vel": Vector2.ZERO,
					"life": 0.75, "max": 0.75, "delay": 0.07 * float(i), "col": GOLD, "r": 9.0})
			_texts.append({"text": "-%d chips" % amount, "pos": head + Vector2(-70, 24), "life": 1.4, "max": 1.4, "col": GOLD, "size": 24})
		"win":
			_flash_col = UP
			for i in range(30):
				var a := _rng.randf() * TAU
				var sp := _rng.randf_range(90.0, 330.0)
				_parts.append({"kind": "spark", "pos": head, "vel": Vector2(cos(a), sin(a)) * sp, "life": _rng.randf_range(0.6, 1.1), "max": 1.1, "delay": 0.0,
					"col": UP.lightened(_rng.randf() * 0.5), "r": _rng.randf_range(2.0, 5.0)})
			for i in range(10):
				_parts.append({"kind": "chip", "from": head, "to": Vector2(r.end.x + 60.0, 8.0), "pos": Vector2.ZERO, "vel": Vector2.ZERO,
					"life": 0.8, "max": 0.8, "delay": 0.05 * float(i), "col": GOLD, "r": 8.0})
			_texts.append({"text": "+%d" % amount, "pos": head + Vector2(-50, -30), "life": 1.8, "max": 1.8, "col": UP, "size": 38})
		"loss":
			_flash_col = DOWN
			_shake = 0.4
			for i in range(18):
				_parts.append({"kind": "spark", "pos": head, "vel": Vector2(_rng.randf_range(-120.0, 120.0), _rng.randf_range(40.0, 260.0)), "life": _rng.randf_range(0.6, 1.0),
					"max": 1.0, "delay": 0.0, "col": DOWN, "r": _rng.randf_range(2.0, 4.5)})
			_texts.append({"text": "%d" % amount, "pos": head + Vector2(-50, -20), "life": 1.8, "max": 1.8, "col": DOWN, "size": 36})
		_:
			_flash_col = GOLD
			_texts.append({"text": "+0", "pos": head + Vector2(-30, -24), "life": 1.2, "max": 1.2, "col": GOLD, "size": 28})
	if FxMode.is_lite():
		_parts.clear()
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	_acc += delta
	var lite := FxMode.is_lite()
	if lite:
		if _acc >= 0.5:
			_acc = 0.0
			_sample()
			queue_redraw()
		return
	_acc = 0.0
	_sample()
	_flash = maxf(_flash - delta * 2.2, 0.0)
	_shake = maxf(_shake - delta, 0.0)
	var r := _plot()
	var head := _pt(POINTS - 1, r)
	for p in _parts:
		if float(p["delay"]) > 0.0:
			p["delay"] = float(p["delay"]) - delta
			continue
		p["life"] = float(p["life"]) - delta
		if String(p["kind"]) == "chip":
			var k := 1.0 - clampf(float(p["life"]) / float(p["max"]), 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var to: Vector2 = p["to"]
			if to.x < r.end.x and to.y > 20.0:  # chips flying INTO the head follow it as it scrolls
				to = head
			p["pos"] = (p["from"] as Vector2).lerp(to, e) + Vector2(0.0, -sin(PI * e) * 70.0)
		else:
			var v: Vector2 = p["vel"]
			v.y += 420.0 * delta
			p["vel"] = v
			p["pos"] = (p["pos"] as Vector2) + v * delta
	_parts = _parts.filter(func(p): return float(p["life"]) > 0.0)
	for t in _texts:
		t["life"] = float(t["life"]) - delta
		t["pos"] = (t["pos"] as Vector2) + Vector2(0.0, -34.0 * delta)
	_texts = _texts.filter(func(t): return float(t["life"]) > 0.0)
	queue_redraw()


func _dashed(a: Vector2, b: Vector2, col: Color, dash: float = 8.0) -> void:
	var dist := a.distance_to(b)
	var dir := (b - a) / maxf(dist, 0.001)
	var d := 0.0
	while d < dist:
		draw_line(a + dir * d, a + dir * minf(d + dash, len), col, 1.5)
		d += dash * 2.0


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var r := _plot()
	if _shake > 0.0:
		draw_set_transform(Vector2(sin(_pulse * 90.0) * 7.0 * _shake / 0.4, 0.0), 0.0, Vector2.ONE)
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1329"))
	var up := _last >= _first
	var col := UP if up else DOWN
	# grid + price scale
	for i in range(5):
		var gy := r.position.y + r.size.y * float(i) / 4.0
		draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), Color(1, 1, 1, 0.06), 1.0)
		var pv := _hi - (_hi - _lo) * float(i) / 4.0
		draw_string(font, Vector2(r.end.x + 8.0, gy + 5.0), "%.2f" % pv, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UiTheme.COL_MUTED, 0.9))
	draw_string(font, Vector2(r.position.x, size.y - 10.0), "-%s" % _range_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.COL_MUTED)
	draw_string(font, Vector2(r.end.x - 30.0, size.y - 10.0), "now", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.COL_MUTED)
	# area + line
	var line := PackedVector2Array()
	for i in range(POINTS):
		line.append(_pt(i, r))
	var poly := PackedVector2Array(line)
	poly.append(Vector2(r.end.x, r.end.y))
	poly.append(Vector2(r.position.x, r.end.y))
	var cols := PackedColorArray()
	for i in range(POINTS):
		cols.append(Color(col, 0.34))
	cols.append(Color(col, 0.02))
	cols.append(Color(col, 0.02))
	draw_polygon(poly, cols)
	draw_polyline(line, col, 3.0, true)
	# entry line
	if entry_price > 0.0:
		var ey := _y_of(entry_price, r)
		_dashed(Vector2(r.position.x, ey), Vector2(r.end.x, ey), Color(GOLD, 0.85))
		draw_rect(Rect2(r.end.x + 4.0, ey - 11.0, 92.0, 22.0), Color(GOLD, 0.2))
		draw_string(font, Vector2(r.end.x + 8.0, ey + 5.0), "ENTRY %.2f" % entry_price, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
	# last price line + tag
	var head := line[POINTS - 1]
	_dashed(Vector2(r.position.x, head.y), head, Color(col, 0.45), 5.0)
	draw_rect(Rect2(r.end.x + 4.0, head.y - 12.0, 92.0, 24.0), col)
	draw_string(font, Vector2(r.end.x + 10.0, head.y + 6.0), "%.2f" % _last, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("0b1020"))
	# pulsing head
	var pr := 12.0 + 4.0 * sin(_pulse * 4.0)
	draw_circle(head, pr + 8.0, Color(col, 0.10))
	draw_circle(head, pr, Color(col, 0.22))
	draw_circle(head, 6.0, col)
	draw_circle(head, 2.5, Color.WHITE)
	# particles
	for p in _parts:
		if float(p["delay"]) > 0.0:
			continue
		var a := clampf(float(p["life"]) / float(p["max"]), 0.0, 1.0)
		if String(p["kind"]) == "chip":
			var cp: Vector2 = p["pos"]
			var rr := float(p["r"])
			draw_circle(cp, rr, Color("8a7222"))
			draw_circle(cp, rr - 2.0, Color("f0cb55"))
			draw_arc(cp, rr - 4.0, 0.0, TAU, 14, Color("8a7222"), 1.5)
		else:
			draw_circle(p["pos"], float(p["r"]) * (0.4 + a), Color(p["col"], a))
	for t in _texts:
		var ta := clampf(float(t["life"]) / float(t["max"]), 0.0, 1.0)
		var tp: Vector2 = t["pos"]
		draw_string(font, tp + Vector2(2, 2), String(t["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(t["size"]), Color(0, 0, 0, ta * 0.6))
		draw_string(font, tp, String(t["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(t["size"]), Color(t["col"], minf(ta * 1.5, 1.0)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_col, 0.45 * _flash), false, 4.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_col, 0.07 * _flash))
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.COL_GOLD_DIM, 0.6), false, 2.0)


func _range_text() -> String:
	return "%dm" % int(range_sec / 60.0) if range_sec >= 60.0 else "%ds" % int(range_sec)
