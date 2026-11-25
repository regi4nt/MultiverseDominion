extends Control
## Graphic animation of the Shop > Auction stage: your bidding paddle shoots up, the rival's paddle answers from the other side,
## and when the lot closes the gavel strikes with a shockwave and "SOLD!" (or "GONE" when a rival takes it).
## Drawn on top of the stage (mouse ignored). The auction is already decided by ShopSystem.auction_*; `play()` only animates it.
## Pure drawing, no game rules. Nothing is drawn (and nothing redraws) while idle, which keeps low_processor_mode cheap.

const DURATIONS := {"bid": 0.55, "rival": 0.65, "sold": 1.5, "gone": 1.2}
const GOLD := Color("d4af37")
const MINE := Color("59cd90")
const RIVAL := Color("ff7b5a")
const WOOD := Color("8a5a2b")

var progress: float = 1.0  # 0..1 of the running animation (1 = idle: nothing drawn)
var kind: String = "bid"
var label: String = ""
var _tween: Tween
var _seeds: Array = []  # [angle, speed, size] per spark; cosmetic only


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 4321
	for i in range(26):
		_seeds.append([rng.randf() * TAU, rng.randf_range(0.5, 1.3), rng.randf_range(2.0, 4.5)])


## Plays one effect: "bid" (your paddle), "rival" (their paddle), "sold" (you won) or "gone" (a rival won). `text` is the short
## caption drawn with it (for example the bid). Awaitable. Lite effects mode: the caller simply does not call this.
func play(what: String, text: String = "") -> void:
	kind = what if DURATIONS.has(what) else "bid"
	label = text
	progress = 0.0
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_progress, 0.0, 1.0, float(DURATIONS[kind]))
	await _tween.finished
	stop()


func stop() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	progress = 1.0
	visible = false
	queue_redraw()


func _set_progress(p: float) -> void:
	progress = p
	queue_redraw()


func _draw() -> void:
	if progress >= 1.0:
		return
	var R := minf(size.x, size.y) * 0.22
	match kind:
		"bid":
			_draw_paddle(Vector2(size.x * 0.3, size.y * 0.5), R, MINE, progress, -1.0)
		"rival":
			_draw_paddle(Vector2(size.x * 0.7, size.y * 0.5), R, RIVAL, progress, 1.0)
		_:
			_draw_gavel_hit(size * 0.5, R, progress, kind == "sold")


## A paddle on a stick rises from the bottom, wobbles, then drops out of sight. `side` leans it (-1 left / +1 right).
func _draw_paddle(base: Vector2, R: float, col: Color, p: float, side: float) -> void:
	var rise := sin(clampf(p / 0.55, 0.0, 1.0) * PI * 0.5)
	var drop := smoothstep(0.78, 1.0, p)
	var alpha := 1.0 - drop
	var lift := (rise - drop * 0.6) * R * 2.2
	var wobble := sin(p * 24.0) * 0.12 * (1.0 - p)
	var head := base + Vector2(side * R * 0.2, R * 1.4 - lift)
	var tilt := side * 0.18 + wobble
	var dir := Vector2(sin(tilt), cos(tilt))  # the stick goes from the head down
	var foot := head + dir * R * 2.2
	draw_line(head, foot, Color(WOOD, alpha), maxf(6.0, R * 0.14))
	draw_circle(head, R * 0.62, Color(col.darkened(0.55), alpha))
	draw_circle(head, R * 0.62, Color(col, alpha * 0.9), false, 4.0)
	draw_circle(head, R * 0.46, Color(col, alpha * 0.25))
	if label != "":
		var fs := int(R * 0.42)
		draw_string(ThemeDB.fallback_font, head + Vector2(-R, fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, R * 2.0, fs, Color(1, 1, 1, alpha))
	# little "ping" rings when the paddle peaks
	var ping := clampf((p - 0.3) / 0.5, 0.0, 1.0)
	if ping > 0.0 and ping < 1.0:
		draw_arc(head, R * (0.7 + ping * 0.9), 0.0, TAU, 36, Color(col, (1.0 - ping) * 0.8), 3.0)


## The gavel swings up and strikes the block, then a shockwave, sparks and the caption burst out.
func _draw_gavel_hit(c: Vector2, R: float, p: float, won: bool) -> void:
	var col := GOLD if won else RIVAL
	var fade := 1.0 - smoothstep(0.82, 1.0, p)
	var hit := 0.3  # the strike moment
	var block := Rect2(c + Vector2(-R * 1.0, R * 0.55), Vector2(R * 2.0, R * 0.38))
	draw_rect(block, Color(WOOD.darkened(0.25), fade))
	draw_rect(block, Color(col, fade * 0.7), false, 2.0)
	# gavel angle: raised (-80 deg) -> strikes (0 deg) at `hit`, small bounce after
	var ang: float
	if p < hit:
		ang = lerpf(deg_to_rad(-80.0), 0.0, pow(p / hit, 2.2))
	else:
		ang = -deg_to_rad(10.0) * sin((p - hit) * 18.0) * exp(-(p - hit) * 7.0)
	var pivot := c + Vector2(R * 0.9, R * 0.5)  # the handle end rests on the right
	var handle_len := R * 1.5
	var head_c := pivot + Vector2(-cos(ang), sin(ang)) * handle_len
	draw_line(pivot, head_c, Color(WOOD, fade), maxf(7.0, R * 0.16))
	var perp := Vector2(-(head_c - pivot).y, (head_c - pivot).x).normalized() * R * 0.34
	var along := (head_c - pivot).normalized() * R * 0.28
	var poly := PackedVector2Array([head_c + perp - along, head_c + perp + along, head_c - perp + along, head_c - perp - along])
	draw_colored_polygon(poly, Color(WOOD.lightened(0.15), fade))
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(col, fade), 2.5)
	if p < hit:
		return
	var b := clampf((p - hit) / (1.0 - hit), 0.0, 1.0)
	var impact := c + Vector2(0, R * 0.55)
	# shockwave rings
	for i in range(3):
		var rb := clampf(b * 1.3 - float(i) * 0.14, 0.0, 1.0)
		if rb > 0.0 and rb < 1.0:
			draw_arc(impact, R * (0.4 + rb * 2.6), PI, TAU, 40, Color(col, (1.0 - rb) * 0.85 * fade), 5.0 - 3.0 * rb)
	# sparks (a bigger shower when you win)
	var count := _seeds.size() if won else 10
	for i in range(count):
		var s: Array = _seeds[i]
		var a := PI + float(s[0]) * 0.5  # the upper half only
		var d := float(s[1]) * R * 2.2 * (1.0 - pow(1.0 - b, 2.0))
		var pos := impact + Vector2(cos(a), sin(a)) * d + Vector2(0, b * b * R * 0.8)
		draw_circle(pos, float(s[2]) * (1.0 - 0.5 * b), Color(col.lightened(0.3), (1.0 - b) * fade))
	if won:  # golden rays behind the caption
		for i in range(10):
			var ra := PI + (float(i) + 0.5) * PI / 10.0
			var p0 := impact + Vector2(cos(ra), sin(ra)) * R * 0.9
			var p1 := impact + Vector2(cos(ra), sin(ra)) * R * (1.2 + 1.4 * b)
			draw_line(p0, p1, Color(GOLD, (1.0 - b) * 0.6 * fade), 3.0)
	# caption pops in with an overshoot
	var text := "SOLD!" if won else "GONE"
	var pop := clampf(b / 0.25, 0.0, 1.0)
	var pop_scale := (1.0 + 0.35 * sin(pop * PI)) * pop
	var fs := int(R * 0.9 * maxf(pop_scale, 0.01))
	if fs > 4:
		var pos2 := c + Vector2(-R * 2.0, -R * 0.9)
		draw_string(ThemeDB.fallback_font, pos2 + Vector2(2, 3), text, HORIZONTAL_ALIGNMENT_CENTER, R * 4.0, fs, Color(0, 0, 0, 0.6 * fade))
		draw_string(ThemeDB.fallback_font, pos2, text, HORIZONTAL_ALIGNMENT_CENTER, R * 4.0, fs, Color(col.lightened(0.15), fade))
