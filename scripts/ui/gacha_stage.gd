extends Control
## Graphic summon animation of the Shop > Card Gacha stage: a rotating magic circle, particles flying into a charging orb, then a flash,
## a ring and rays in the colour of the best rarity pulled (rarer = longer charge, more rays, bigger burst).
## Drawn on top of the stage (mouse ignored). The pull is already decided by ShopSystem.pull_batch; `play()` only animates it.
## Pure drawing, no game rules. Nothing is drawn (and nothing redraws) while idle, which keeps low_processor_mode cheap.

const CHARGE_END := 0.60  # 0..CHARGE_END charge, then the burst, then fade
const BURST_END := 0.82
const DURATIONS := {"common": 1.1, "rare": 1.45, "epic": 1.85, "legendary": 2.4}
const RAY_COUNT := {"common": 8, "rare": 12, "epic": 16, "legendary": 24}
const NEUTRAL := Color("e8d9a0")
const PARTICLES := 28

var progress: float = 1.0  # 0..1 of the running animation (1 = idle: nothing drawn)
var rarity: String = "common"
var color: Color = Color("8fa3c8")
var duration: float = 1.1
var _tween: Tween
var _seeds: Array = []  # [angle, distance 0.6..1.3, spin, size] per particle; cosmetic only


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in range(PARTICLES):
		_seeds.append([rng.randf() * TAU, rng.randf_range(0.6, 1.3), rng.randf_range(0.6, 1.6), rng.randf_range(2.0, 4.5)])


## Seconds until the burst peaks: the cards should start to appear then.
func lead_time() -> float:
	return duration * BURST_END * 0.85


## Plays the summon for the best rarity of the batch. Awaitable. Lite effects mode: the caller simply does not call this.
func play(best_rarity: String, col: Color) -> void:
	rarity = best_rarity if DURATIONS.has(best_rarity) else "common"
	color = col
	duration = float(DURATIONS[rarity])
	progress = 0.0
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_progress, 0.0, 1.0, duration)
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
	var c := size * 0.5
	var R := minf(size.x, size.y) * 0.26
	var p := progress
	var fade := 1.0 - smoothstep(BURST_END, 1.0, p)  # everything fades out while the cards appear
	var tier := ["common", "rare", "epic", "legendary"].find(rarity)
	if p < BURST_END:
		var t := clampf(p / CHARGE_END, 0.0, 1.0)
		_draw_circle_magic(c, R, t, fade)
		_draw_particles(c, R, t, fade)
		_draw_orb(c, R, t, fade)
	if p >= CHARGE_END:
		var b := clampf((p - CHARGE_END) / (1.0 - CHARGE_END), 0.0, 1.0)
		_draw_burst(c, R, b, tier)


## Two counter-rotating dashed rings and a hexagram, fading in as the charge builds.
func _draw_circle_magic(c: Vector2, R: float, t: float, fade: float) -> void:
	var a := minf(t * 2.0, 1.0) * fade
	var col := NEUTRAL.lerp(color, smoothstep(0.35, 0.9, t))
	col.a = 0.85 * a
	var spin := t * TAU * (0.9 + 0.5 * float(["common", "rare", "epic", "legendary"].find(rarity)))
	var r1 := R * (1.25 + 0.1 * sin(t * 12.0))
	for k in range(10):
		var s := spin + float(k) * TAU / 10.0
		draw_arc(c, r1, s, s + TAU / 16.0, 8, col, 3.0)
	var r2 := R * 1.0
	for k in range(6):
		var s2 := -spin * 1.3 + float(k) * TAU / 6.0
		draw_arc(c, r2, s2, s2 + TAU / 9.0, 8, Color(col, col.a * 0.8), 2.0)
	for tri in range(2):  # hexagram = two triangles
		var pts := PackedVector2Array()
		for k in range(4):
			var ang := spin * 0.5 + TAU * float(k % 3) / 3.0 + PI * float(tri)
			pts.append(c + Vector2(cos(ang), sin(ang)) * r2)
		draw_polyline(pts, Color(col, col.a * 0.7), 2.0)


## Sparkles spiral into the centre.
func _draw_particles(c: Vector2, R: float, t: float, fade: float) -> void:
	for s in _seeds:
		var ang: float = float(s[0]) + t * float(s[2]) * 3.0
		var dist: float = float(s[1]) * R * 2.0 * pow(1.0 - t, 1.6)
		var pos := c + Vector2(cos(ang), sin(ang)) * dist
		var col := NEUTRAL.lerp(color, t)
		col.a = clampf(t * 3.0, 0.0, 1.0) * clampf(dist / (R * 0.5), 0.0, 1.0) * fade
		draw_circle(pos, float(s[3]) * (0.6 + 0.6 * t), col)


## The orb grows, pulses faster and takes the colour of the rarity (the colour is the suspense: it shows what is coming).
func _draw_orb(c: Vector2, R: float, t: float, fade: float) -> void:
	var pulse := 1.0 + 0.08 * sin(t * 40.0 * (0.5 + t))
	var r := R * (0.2 + 0.4 * t) * pulse
	var col := NEUTRAL.lerp(color, smoothstep(0.3, 0.95, t))
	for i in range(5):  # soft glow
		var gr := r * (1.0 + 0.55 * float(i))
		draw_circle(c, gr, Color(col, 0.10 * fade * (1.0 - 0.15 * float(i))))
	draw_circle(c, r, Color(col, 0.95 * fade))
	draw_circle(c, r * 0.55, Color(1, 1, 1, 0.9 * fade))
	draw_arc(c, r * 0.8, deg_to_rad(200), deg_to_rad(260), 10, Color(1, 1, 1, 0.6 * fade), 3.0)


## Flash, an expanding ring and rays; rarer = more rays and a bigger bang. b is 0..1 since the burst began.
func _draw_burst(c: Vector2, R: float, b: float, tier: int) -> void:
	var a := 1.0 - smoothstep(0.45, 1.0, b)
	var reach := minf(size.x, size.y) * (0.45 + 0.12 * float(tier))
	var flash := 1.0 - smoothstep(0.0, 0.35, b)  # white flash at the very start
	if flash > 0.0:
		draw_circle(c, R * (0.8 + 2.2 * b), Color(1, 1, 1, 0.85 * flash))
	var ring := R * 0.6 + reach * pow(b, 0.6)
	draw_arc(c, ring, 0.0, TAU, 48, Color(color, a), 6.0 * (1.0 - b) + 1.0)
	if tier >= 2:  # a second, slower ring for Epic and Legendary
		draw_arc(c, ring * 0.7, 0.0, TAU, 40, Color(color.lightened(0.4), a * 0.8), 3.0)
	var n: int = int(RAY_COUNT[rarity])
	for i in range(n):
		var ang := TAU * float(i) / float(n) + 0.2 + b * 0.35
		var d0 := R * 0.4 + reach * 0.25 * b
		var d1 := R * 0.6 + reach * (0.5 + 0.5 * float(i % 2)) * pow(b, 0.5)
		var col := color.lightened(0.45) if i % 2 == 0 else Color(1, 1, 1)
		draw_line(c + Vector2(cos(ang), sin(ang)) * d0, c + Vector2(cos(ang), sin(ang)) * d1, Color(col, a), 3.0 + float(tier))
	for i in range(10 + 8 * tier):  # confetti sparks
		var ang2 := float(_seeds[i % PARTICLES][0]) + float(i) * 0.7
		var dist := reach * (0.3 + 0.7 * pow(b, 0.7)) * float(_seeds[i % PARTICLES][1]) * 0.8
		draw_circle(c + Vector2(cos(ang2), sin(ang2)) * dist, float(_seeds[i % PARTICLES][3]) * (1.0 - b * 0.7), Color(color.lightened(0.5), a))
