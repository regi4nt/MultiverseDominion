extends Control
## Graphic stage of the Shop > Gamble tab: a spinning coin, two tumbling dice with pips, or three slot reels with drawn symbols.
## The outcome is already decided by ShopSystem.gamble; `play()` only animates it (await it). Pure drawing, no game rules.

signal sound(name: String)

const SYMBOLS := ["7", "BAR", "BELL", "GEM", "CLOVER", "CHERRY"]  # same order as ShopSystem.SLOT_SYMBOLS
const GOLD := Color("d4af37")
const REEL_DURATIONS := [1.2, 1.75, 2.35]

var game: String = "coin"
var progress: float = 1.0  # 0..1 of the running animation (1 = finished / idle)
var coin_heads: bool = true  # face shown at the end
var dice_vals: Array = [5, 2]
var slot_targets: Array = [0, 1, 2]
var burst: float = 0.0  # 0..1 sparkle burst after a win
var burst_power: float = 1.0
var _rng := RandomNumberGenerator.new()  # cosmetic only
var _dice_faces: Array = [5, 2]
var _next_face_t := 0.0
var _reels: Array = []
var _reel_box: HBoxContainer
var _last_bounce := -1
var _last_flip := -1
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(0, 250)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = false
	_rng.randomize()
	_reel_box = HBoxContainer.new()
	_reel_box.add_theme_constant_override("separation", 14)
	_reel_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_reel_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_reel_box)
	for i in range(3):
		var r := ReelView.new()
		_reel_box.add_child(r)
		_reels.append(r)
	set_idle("coin")


func set_idle(g: String) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	game = g
	progress = 1.0
	burst = 0.0
	_reel_box.visible = (g == "slots")
	for i in range(3):
		_reels[i].pos = float(i * 2)  # 7 / BELL / CLOVER... a calm idle line
		_reels[i].glow = 0.0
		_reels[i].queue_redraw()
	queue_redraw()


## Plays the animation for `detail` (the dictionary ShopSystem.gamble returned). Awaitable.
func play(g: String, detail: Dictionary) -> void:
	game = g
	burst = 0.0
	_reel_box.visible = (g == "slots")
	_last_bounce = -1
	_last_flip = -1
	var duration := 1.8
	match g:
		"coin":
			coin_heads = String(detail["landed"]) == "heads"
		"dice":
			dice_vals = [int(detail["dice"][0]), int(detail["dice"][1])]
			_dice_faces = [_rng.randi_range(1, 6), _rng.randi_range(1, 6)]
			_next_face_t = 0.0
			duration = 1.7
		"slots":
			slot_targets = detail["reels"].duplicate()
			duration = float(REEL_DURATIONS[2]) + 0.15
			for i in range(3):
				_reels[i].glow = 0.0
				_reels[i].stopped = false
				_reels[i].start_pos = _reels[i].pos
	progress = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_progress, 0.0, 1.0, duration)
	await _tween.finished


## Sparkles + glow after a win (jackpot = stronger).
func celebrate(win: bool, jackpot: bool) -> void:
	if game == "slots":
		for r in _reels:
			r.glow = 1.0 if win else 0.0
			r.queue_redraw()
	if not win:
		return
	burst_power = 1.8 if jackpot else 1.0
	burst = 0.0
	var tw := create_tween()
	tw.tween_method(func(v: float): burst = v; queue_redraw(), 0.0, 1.0, 0.9 if jackpot else 0.6)


func _set_progress(p: float) -> void:
	progress = p
	if game == "slots":
		for i in range(3):
			var r: ReelView = _reels[i]
			var d: float = float(REEL_DURATIONS[i])
			var tt: float = clampf(p * (float(REEL_DURATIONS[2]) + 0.15) / d, 0.0, 1.0)
			var final_pos := float(6 * (5 + 2 * i) + int(slot_targets[i]))
			var base := float(int(r.start_pos) % 6)
			r.pos = r.start_pos + (final_pos - base) * (1.0 - pow(1.0 - tt, 3.0))
			if tt >= 1.0 and not r.stopped:
				r.stopped = true
				r.pos = r.start_pos + (final_pos - base)
				sound.emit("coin")
			r.queue_redraw()
	elif game == "coin":
		var fl := int(p * 7.0)
		if fl != _last_flip:
			_last_flip = fl
			sound.emit("click")
	elif game == "dice":
		var b := int(p * 4.0)
		if b != _last_bounce:
			_last_bounce = b
			sound.emit("click")
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	match game:
		"coin":
			_draw_coin(c)
		"dice":
			_draw_dice(c)
	if burst > 0.0 and burst < 1.0:
		_draw_burst(c)


# ------------------------------------------------------------------ coin
func _draw_coin(c: Vector2) -> void:
	var r := minf(size.y * 0.30, 80.0)
	var p := progress
	var half_turns := 8 if coin_heads else 7  # even = heads, odd = tails
	var ang := PI * float(half_turns) * (1.0 - pow(1.0 - p, 2.2))
	var jump := sin(clampf(p, 0.0, 1.0) * PI) * r * 1.5 if p < 1.0 else 0.0
	var sy := absf(cos(ang))
	var heads := cos(ang) >= 0.0
	var pos := c + Vector2(0, r * 0.4 - jump)
	# shadow on the ground
	draw_set_transform(c + Vector2(0, r * 1.15), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, r * (1.0 - 0.25 * (jump / (r * 1.5 + 0.001))), Color(0, 0, 0, 0.35))
	draw_set_transform(pos, 0.0, Vector2(1.0, maxf(sy, 0.04)))
	draw_circle(Vector2.ZERO, r, Color("8a6a12"))  # rim
	draw_circle(Vector2.ZERO, r * 0.93, GOLD)
	draw_circle(Vector2.ZERO, r * 0.78, Color("b8921f"))
	draw_circle(Vector2.ZERO, r * 0.72, Color("e8c860"))
	if heads:  # a crown
		var k := r * 0.5
		var pts := PackedVector2Array([Vector2(-k, k * 0.55), Vector2(-k, -k * 0.2), Vector2(-k * 0.5, k * 0.15), Vector2(0, -k * 0.65),
			Vector2(k * 0.5, k * 0.15), Vector2(k, -k * 0.2), Vector2(k, k * 0.55)])
		draw_colored_polygon(pts, Color("8a6a12"))
		for x in [-k, 0.0, k]:
			draw_circle(Vector2(x, -k * (0.2 if x != 0.0 else 0.65)), k * 0.12, Color("8a6a12"))
	else:  # a star
		var pts2 := PackedVector2Array()
		for i in range(10):
			var rr := r * (0.5 if i % 2 == 0 else 0.22)
			var a := -PI / 2.0 + TAU * float(i) / 10.0
			pts2.append(Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(pts2, Color("8a6a12"))
	# shine
	draw_arc(Vector2.ZERO, r * 0.86, deg_to_rad(200), deg_to_rad(260), 12, Color(1, 1, 1, 0.55), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ dice
func _draw_dice(c: Vector2) -> void:
	var s := minf(size.y * 0.34, 84.0)
	var p := progress
	var gap := s * 0.95
	for i in range(2):
		var cx := c.x + (-1.0 if i == 0 else 1.0) * gap
		var phase := p * 3.0 + float(i) * 0.37
		var bounce := absf(sin(phase * PI)) * s * 1.1 * (1.0 - p) if p < 1.0 else 0.0
		var rot := sin(p * 17.0 + float(i)) * 0.45 * (1.0 - p) if p < 1.0 else 0.0
		var face: int = int(dice_vals[i])
		if p < 0.85:
			var step := int(p * (14.0 - 6.0 * p) * 3.0) + i * 5  # slows down as it settles
			face = ((step * 7 + i * 3) % 6) + 1
		var center := Vector2(cx, c.y + s * 0.25 - bounce)
		draw_set_transform(Vector2(cx, c.y + s * 0.9), 0.0, Vector2(1.0, 0.2))
		draw_circle(Vector2.ZERO, s * 0.55 * (1.0 - bounce / (s * 3.0)), Color(0, 0, 0, 0.35))
		draw_set_transform(center, rot, Vector2.ONE)
		var box := StyleBoxFlat.new()
		box.bg_color = Color("f4efe0")
		box.set_corner_radius_all(int(s * 0.18))
		box.border_color = Color("b9b09a")
		box.set_border_width_all(3)
		draw_style_box(box, Rect2(Vector2(-s * 0.5, -s * 0.5), Vector2(s, s)))
		for pip in _pips(face):
			draw_circle(pip * s * 0.27, s * 0.085, Color("20243d"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _pips(n: int) -> Array:
	match n:
		1: return [Vector2(0, 0)]
		2: return [Vector2(-1, -1), Vector2(1, 1)]
		3: return [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)]
		4: return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		5: return [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)]
	return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)]


func _draw_burst(c: Vector2) -> void:
	var n := 18
	var maxr := minf(size.x, size.y) * 0.5 * burst_power
	for i in range(n):
		var a := TAU * float(i) / float(n) + 0.3
		var d := maxr * (0.25 + 0.75 * burst)
		var col := Color("ffe27a") if i % 2 == 0 else Color("ffffff")
		col.a = 1.0 - burst
		draw_circle(c + Vector2(cos(a), sin(a)) * d, (5.0 + 3.0 * burst_power) * (1.0 - burst * 0.6), col)


# ------------------------------------------------------------------ slot reel
class ReelView extends Control:
	var pos: float = 0.0  # in symbols; the symbol at index round(pos) % 6 sits in the window centre
	var start_pos: float = 0.0
	var glow: float = 0.0
	var stopped: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(122, 200)
		clip_contents = true

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cell := h / 2.2
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color("f4efe0")
		bg.set_corner_radius_all(14)
		bg.border_color = GOLD if glow > 0.0 else Color("6c5a2a")
		bg.set_border_width_all(5 if glow > 0.0 else 3)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var base := int(floor(pos))
		var frac := pos - float(base)
		for k in range(-2, 3):
			var idx := posmod(base + k, 6)
			var y := h * 0.5 + (float(k) - frac) * cell
			_draw_symbol(idx, Vector2(w * 0.5, y), cell * 0.78)
		# shading top / bottom, like a reel in a cabinet
		draw_rect(Rect2(0, 0, w, h * 0.22), Color(0, 0, 0, 0.18))
		draw_rect(Rect2(0, h * 0.78, w, h * 0.22), Color(0, 0, 0, 0.18))
		draw_line(Vector2(0, h * 0.5), Vector2(w, h * 0.5), Color(0.8, 0.1, 0.1, 0.35), 2.0)

	func _draw_symbol(idx: int, c: Vector2, s: float) -> void:
		var font := get_theme_default_font()
		match idx:
			0:  # lucky 7
				var fs := int(s * 1.25)
				var txt := "7"
				var tsz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				var origin := Vector2(c.x - tsz.x * 0.5, c.y + fs * 0.34)
				draw_string_outline(font, origin, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color("5a0d0d"))
				draw_string(font, origin, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("e8332b"))
			1:  # BAR
				var r := Rect2(c - Vector2(s * 0.46, s * 0.26), Vector2(s * 0.92, s * 0.52))
				draw_rect(r, Color("1a1d33"))
				draw_rect(r, GOLD, false, 3.0)
				var fs2 := int(s * 0.34)
				var t2 := "BAR"
				var sz2 := font.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
				draw_string(font, Vector2(c.x - sz2.x * 0.5, c.y + fs2 * 0.34), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color("f4efe0"))
			2:  # bell
				var pts := PackedVector2Array([Vector2(-s * 0.42, s * 0.28), Vector2(-s * 0.3, -s * 0.05), Vector2(-s * 0.18, -s * 0.34),
					Vector2(0, -s * 0.42), Vector2(s * 0.18, -s * 0.34), Vector2(s * 0.3, -s * 0.05), Vector2(s * 0.42, s * 0.28)])
				for i in range(pts.size()):
					pts[i] += c
				draw_colored_polygon(pts, Color("e8b923"))
				draw_polyline(pts, Color("8a6a12"), 3.0)
				draw_circle(c + Vector2(0, s * 0.36), s * 0.1, Color("8a6a12"))
			3:  # gem
				var gp := PackedVector2Array([Vector2(-s * 0.4, -s * 0.12), Vector2(-s * 0.22, -s * 0.38), Vector2(s * 0.22, -s * 0.38),
					Vector2(s * 0.4, -s * 0.12), Vector2(0, s * 0.42)])
				for i in range(gp.size()):
					gp[i] += c
				draw_colored_polygon(gp, Color("3fc1e8"))
				draw_polyline(PackedVector2Array([gp[0], gp[1], gp[2], gp[3], gp[4], gp[0]]), Color("14607a"), 3.0)
				draw_line(gp[0], gp[3], Color("14607a"), 2.0)
				draw_line(gp[1], gp[4], Color(1, 1, 1, 0.6), 2.0)
				draw_line(gp[2], gp[4], Color(1, 1, 1, 0.6), 2.0)
			4:  # four-leaf clover
				for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					draw_circle(c + d * s * 0.17, s * 0.19, Color("3fae5a"))
				draw_line(c, c + Vector2(s * 0.1, s * 0.45), Color("1f6b34"), 5.0)
			5:  # cherries
				draw_line(c + Vector2(-s * 0.2, s * 0.15), c + Vector2(0, -s * 0.4), Color("2f7a3a"), 3.0)
				draw_line(c + Vector2(s * 0.2, s * 0.2), c + Vector2(0, -s * 0.4), Color("2f7a3a"), 3.0)
				draw_circle(c + Vector2(-s * 0.2, s * 0.22), s * 0.2, Color("d62839"))
				draw_circle(c + Vector2(s * 0.2, s * 0.26), s * 0.2, Color("d62839"))
				draw_circle(c + Vector2(-s * 0.26, s * 0.15), s * 0.05, Color(1, 1, 1, 0.7))
				draw_circle(c + Vector2(s * 0.14, s * 0.19), s * 0.05, Color(1, 1, 1, 0.7))
