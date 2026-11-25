class_name BoardView
extends Control
## Draws the 100-tile ring, ownership, active portals and player tokens with _draw()
## (no textures => tiny and fast on low-end Android). Tap a tile to inspect it.

signal tile_pressed(index: int)
signal speed_changed(mult: float)  # the Speed button: AI turns and pawn hops run faster

var ctrl: MatchController
var selected_index: int = -1

var _skin: Dictionary = {}  # territory section of the continent's MapSkin (palette + motif pattern), see _terr()
var _skin_id: String = "?"
var _visual_pos: Dictionary = {}  # player_id -> float tile position (animated)
var _busy: int = 0
var _cell: float = 10.0
var _origin: Vector2 = Vector2.ZERO

# Camera: the 26x26 ring is only ~27 px per tile when it fits a 720 px screen, so the view is zoomed and
# follows the moving pawn. Drag pans, pinch / +/- buttons zoom, "Fit" shows the whole board.
const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
static var speed_mult: float = 1.0  # kept between scenes; restored from the saved settings on first use
const HOP_TIME := 0.17  # seconds per tile while a pawn walks (one hop per tile)
const HOP_HEIGHT := 0.6  # hop apex, in tile sizes
const ZOOM_MIN := 1.0
const ZOOM_MAX := 4.0
static var zoom: float = 1.0  # kept between scenes (static) so a duel does not reset it
static var _zoom_for_grid: int = 0  # board size the current zoom was last defaulted for (see bind())
var _focus: Vector2 = Vector2(0.5, 0.5)  # board-space point (0..1) shown at the view centre
var _press_pos: Vector2 = Vector2.ZERO
var _pressing: bool = false
var _dragged: bool = false
var _pan_tw: Tween
var _roll_tw: Tween
## Explanation shown in the centre of the map, under the region counts (tile info / world modifier).
var info_text: String = "":
	set(v):
		info_text = v
		queue_redraw()
var _roll_t: float = 1.0  # dice tumble progress 0..1 (1 = settled on the real result)
var _roll_seed: int = 0
var _inertia_tw: Tween
var _user_cam: bool = false  # the player moved the camera: the pawn-follow camera must not fight the finger
var _touches: Dictionary = {}  # finger index -> position (to tell a pinch from a one-finger pan)
var _pinch_dist: float = 0.0
var _vel: Vector2 = Vector2.ZERO  # smoothed drag velocity (focus units / s) for the release glide
var _speed_btn: Button
var _zoom_btns: Array[Button] = []
var controls: VBoxContainer  # the +/-/Fit row and the Speed button; see take_controls()


func _ready() -> void:
	clip_contents = true
	var saved = SaveManager.get_setting("board_speed")
	if saved != null and SPEEDS.has(float(saved)):
		speed_mult = float(saved)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	controls = col
	col.anchor_left = 0.1  # fallback position (inside the board); the Territory Board moves it to the bottom-left of the screen
	col.anchor_right = 0.1
	col.anchor_top = 0.55
	col.anchor_bottom = 0.55
	col.offset_left = 0.0
	col.offset_right = 270.0
	col.offset_top = 0.0
	col.offset_bottom = 60.0
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	col.add_child(bar)
	for spec in [["+", 1.35], ["-", 1.0 / 1.35], ["Fit", 0.0]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(42, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.modulate = Color(1, 1, 1, 0.85)
		b.pressed.connect(_on_zoom_button.bind(float(spec[1])))
		bar.add_child(b)
		_zoom_btns.append(b)
	_speed_btn = Button.new()
	_speed_btn.custom_minimum_size = Vector2(100, 52)
	_speed_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_speed_btn.focus_mode = Control.FOCUS_NONE
	_speed_btn.modulate = Color(1, 1, 1, 0.85)
	_speed_btn.tooltip_text = "Game speed: AI turns and pawn movement"
	_speed_btn.pressed.connect(_cycle_speed)
	bar.add_child(_speed_btn)  # one row: + - Fit Speed
	_update_speed_label()
	resized.connect(queue_redraw)


## Hands the +/-/Fit/Speed buttons to the screen so it can place them (bottom-left corner); they stay wired to this view.
func take_controls() -> VBoxContainer:
	if controls.get_parent() == self:
		remove_child(controls)
	return controls


func _cycle_speed() -> void:
	speed_mult = SPEEDS[(SPEEDS.find(speed_mult) + 1) % SPEEDS.size()]
	SaveManager.set_setting("board_speed", speed_mult)
	_update_speed_label()
	speed_changed.emit(speed_mult)


func _update_speed_label() -> void:
	_speed_btn.text = "Speed %dx" % int(speed_mult)


## Zooms so the board point under `pos` (view space) stays under the finger / cursor.
## Zooming is only possible while the dice are NOT tumbling (the +/-/Fit buttons are disabled meanwhile).
func _zoom_locked() -> bool:
	return _roll_t < 1.0


func _update_zoom_lock() -> void:
	for b in _zoom_btns:
		b.disabled = _zoom_locked()


func _zoom_at(factor: float, pos: Vector2) -> void:
	if _zoom_locked():
		return
	_layout()
	var old_s := minf(size.x, size.y) * zoom
	var anchor := (pos - _origin) / old_s
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var new_s := minf(size.x, size.y) * zoom
	_focus = anchor - (pos - size * 0.5) / new_s
	queue_redraw()


func _kill_camera_tweens() -> void:
	for tw in [_pan_tw, _inertia_tw]:
		if tw != null and tw.is_valid():
			tw.kill()


func _on_zoom_button(factor: float) -> void:
	if _zoom_locked():
		return
	_kill_camera_tweens()
	if factor == 0.0:
		_user_cam = false
		if _fit_shows_default():  # at Fit on a big board: the same button goes back to the normal tile size, on the pawn
			zoom = default_zoom()
			var cur := ctrl.current_player() if ctrl != null else null
			_focus = Vector2(0.5, 0.5) if cur == null else (Vector2(BoardBuilder.grid_pos(cur.position)) + Vector2(0.5, 0.5)) / float(BoardBuilder.grid)
		else:
			zoom = ZOOM_MIN
			_focus = Vector2(0.5, 0.5)
		queue_redraw()
	else:
		_user_cam = true
		_zoom_at(factor, size * 0.5)


## Centres the camera on a tile (board space).
func focus_tile(i: int) -> void:
	_user_cam = false
	_kill_camera_tweens()
	var g := BoardBuilder.grid_pos(i)
	_focus = (Vector2(g.x, g.y) + Vector2(0.5, 0.5)) / float(BoardBuilder.grid)
	queue_redraw()


## Smoothly slides the camera to a tile (used at the start of every turn so you always see whose turn it is).
func pan_to_tile(i: int) -> void:
	_user_cam = false  # a new turn re-centres the camera on purpose
	var g := BoardBuilder.grid_pos(i)
	var target := (Vector2(g.x, g.y) + Vector2(0.5, 0.5)) / float(BoardBuilder.grid)
	_kill_camera_tweens()
	if not is_inside_tree() or _focus.distance_to(target) < 0.002:
		return
	if FxMode.is_lite():  # Lite: the camera jumps instead of gliding
		_set_focus(target)
		return
	_pan_tw = create_tween()
	_pan_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pan_tw.tween_method(_set_focus, _focus, target, 0.35 / speed_mult)


func _set_focus(v: Vector2) -> void:
	_focus = v
	queue_redraw()


## Zoom at which a tile is as big as on the 40-tile Chaos board (1.0 = Fit on that board).
static func default_zoom() -> float:
	return clampf(float(BoardBuilder.grid) / float(BoardBuilder.CHAOS_SIDE + 1), ZOOM_MIN, ZOOM_MAX)


func bind(c: MatchController) -> void:
	ctrl = c
	# The 100-tile board starts zoomed so a tile is as big as on the 40-tile Chaos board (the camera follows the pawn;
	# "Fit" still shows the whole ring). Only re-defaulted when the board size changes, so a duel or the Card Hub
	# does not reset the player's own zoom.
	if _zoom_for_grid != BoardBuilder.grid:
		_zoom_for_grid = BoardBuilder.grid
		zoom = default_zoom()
	for p in ctrl.players:
		_visual_pos[p.id] = float(p.position)
	ctrl.tiles_changed.connect(queue_redraw)
	ctrl.players_changed.connect(queue_redraw)
	ctrl.dice_rolled.connect(_on_dice_rolled)
	ctrl.player_moved.connect(_on_player_moved)
	var cur := ctrl.current_player()
	if cur != null:
		focus_tile(cur.position)
	queue_redraw()


## The dice tumble in the middle of the board (the Roll button itself lives in the left panel): they bounce, spin and
## flick through random faces, then settle on the real result. Rolling again (Reroll Token) simply restarts it.
func _on_dice_rolled(_a: int, _b: int) -> void:
	if _roll_tw != null and _roll_tw.is_valid():
		_roll_tw.kill()
	if not is_inside_tree() or FxMode.is_lite():  # Lite: the dice show the result at once, no tumble
		_roll_t = 1.0
		_update_zoom_lock()
		queue_redraw()
		return
	_roll_seed = randi()
	_roll_t = 0.0
	_update_zoom_lock()
	_roll_tw = create_tween()
	_roll_tw.tween_method(_set_roll, 0.0, 1.0, 0.65 / speed_mult)
	_roll_tw.finished.connect(_finish_roll)


func _finish_roll() -> void:
	_roll_t = 1.0
	_update_zoom_lock()
	queue_redraw()


func _set_roll(t: float) -> void:
	_roll_t = t
	queue_redraw()


func is_busy() -> bool:
	return _busy > 0


func _on_player_moved(pid: int, from_i: int, to_i: int, warped: bool) -> void:
	var steps := posmod(to_i - from_i, BoardBuilder.tiles_total)
	if warped or steps == 0 or steps > 14 or FxMode.is_lite():  # Lite: the pawn lands directly, no hopping
		_visual_pos[pid] = float(to_i)
		focus_tile(to_i)
		return
	_busy += 1
	var tw := create_tween()
	var per_hop := HOP_TIME if steps <= 6 else HOP_TIME * 0.75  # long walks hop a bit faster
	tw.tween_method(_set_vis.bind(pid), float(from_i), float(from_i + steps), per_hop * steps / speed_mult)
	tw.finished.connect(_anim_done.bind(pid, to_i))


func _set_vis(v: float, pid: int) -> void:
	_visual_pos[pid] = v
	if _user_cam:
		queue_redraw()
		return
	# The camera glides with the pawn (centre of the two tiles it is between) instead of snapping per tile.
	var i0 := floori(v)
	var a := BoardBuilder.grid_pos(posmod(i0, BoardBuilder.tiles_total))
	var b := BoardBuilder.grid_pos(posmod(i0 + 1, BoardBuilder.tiles_total))
	var gp := Vector2(a.x, a.y).lerp(Vector2(b.x, b.y), v - float(i0))
	_focus = (gp + Vector2(0.5, 0.5)) / float(BoardBuilder.grid)
	queue_redraw()


func _anim_done(pid: int, to_i: int) -> void:
	_visual_pos[pid] = float(to_i)
	_busy = maxi(_busy - 1, 0)
	queue_redraw()


## True when the Fit button would now return to the normal tile size ("1:1"): the whole board is shown and a larger
## default exists (the 100-tile board; on the 40-tile board Fit already is the normal size).
func _fit_shows_default() -> bool:
	return zoom <= ZOOM_MIN + 0.01 and default_zoom() > ZOOM_MIN + 0.01


func _layout() -> void:
	if _zoom_btns.size() > 2:
		var want := "1:1" if _fit_shows_default() else "Fit"
		if _zoom_btns[2].text != want:
			_zoom_btns[2].text = want
	var s := minf(size.x, size.y) * zoom
	_cell = s / float(BoardBuilder.grid)
	var o := size * 0.5 - _focus * s
	# Keep the board covering the view; when it is smaller than the view, centre it.
	o.x = (size.x - s) * 0.5 if s <= size.x else clampf(o.x, size.x - s, 0.0)
	o.y = (size.y - s) * 0.5 if s <= size.y else clampf(o.y, size.y - s, 0.0)
	_origin = o
	_focus = (size * 0.5 - o) / s  # write back the clamped focus


func tile_rect(i: int) -> Rect2:
	var g := BoardBuilder.grid_pos(i)
	return Rect2(_origin + Vector2(g.x, g.y) * _cell, Vector2(_cell, _cell))


func _gui_input(event: InputEvent) -> void:
	if ctrl == null:
		return
	# --- touch bookkeeping: two fingers = pinch (and never a pan or a tap)
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 2:
				_pinch_dist = _touch_dist()
				_pressing = false
				_dragged = true  # a pinch must never end in a tile tap
				_user_cam = true
				_kill_camera_tweens()
		else:
			_touches.erase(event.index)
			if _touches.size() < 2:
				_pinch_dist = 0.0
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index] = event.position
		if _touches.size() >= 2 and _pinch_dist > 1.0:
			var d := _touch_dist()
			var mid := Vector2.ZERO
			for k in _touches.keys():
				mid += _touches[k]
			mid /= float(_touches.size())
			_zoom_at(d / _pinch_dist, mid)
			_pinch_dist = d
		return
	if event is InputEventMagnifyGesture:
		if _touches.size() < 2:  # touchscreens zoom through the pinch code above (no double zoom)
			_user_cam = true
			_zoom_at(event.factor, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _touches.size() >= 2:
				return
			_kill_camera_tweens()  # touching the board stops any glide at once
			_pressing = true
			_dragged = false
			_press_pos = event.position
			_vel = Vector2.ZERO
		else:
			if _pressing and not _dragged:
				_select_at(event.position)
			elif _pressing and _dragged and _vel.length() > 0.15:
				_glide()
			_pressing = false
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_user_cam = true
		_zoom_at(1.15, event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_user_cam = true
		_zoom_at(1.0 / 1.15, event.position)
	elif event is InputEventMouseMotion and _pressing:
		if _touches.size() >= 2:
			return
		var s_px := minf(size.x, size.y) * zoom
		if not _dragged:
			if event.position.distance_to(_press_pos) <= 12.0:
				return
			_dragged = true
			_user_cam = true
			_kill_camera_tweens()  # the player took over the camera
			# start from where the finger went down, so the first 12 px are not "lost" (no jump / sticky start)
			_focus -= (event.position - _press_pos) / s_px
			queue_redraw()
			return
		var step: Vector2 = -event.relative / s_px
		_focus += step
		var dt := maxf(get_process_delta_time(), 0.001)
		_vel = _vel.lerp(step / dt, 0.35)  # low-pass so one noisy event does not fling the board
		queue_redraw()


func _touch_dist() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


## Short ease-out glide after releasing a fast drag (feels natural, stops dead on touch).
func _glide() -> void:
	var v := _vel.limit_length(3.0)
	_vel = Vector2.ZERO
	_kill_camera_tweens()
	if not is_inside_tree() or FxMode.is_lite():  # Lite: the board stops where the finger lifts
		return
	var target := _focus + v * 0.22
	_inertia_tw = create_tween()
	_inertia_tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_inertia_tw.tween_method(_set_focus, _focus, target, 0.45)


func _select_at(pos: Vector2) -> void:
	_layout()
	for i in range(BoardBuilder.tiles_total):
		if tile_rect(i).grow(1.0).has_point(pos):
			selected_index = i
			tile_pressed.emit(i)
			queue_redraw()
			return


func _tile_color(t: BoardTile) -> Color:
	var sk := _terr()
	var c := Color.GRAY
	match t.type:
		BoardTile.Type.CORNER: c = Color("3a2a6b")
		BoardTile.Type.TERRITORY: return sk["tile"] if t.index % 2 == 0 else sk["tile_alt"]
		BoardTile.Type.PORTAL: c = Color("1b1f3a")
		BoardTile.Type.SHOP: c = Color("1f4a4a")
		BoardTile.Type.EVENT: c = Color("4a3a1f")
		BoardTile.Type.AUCTION: c = Color("5a2f4a")
		BoardTile.Type.TAX: c = Color("5a2323")
		BoardTile.Type.SPECIAL: c = Color("2f3f6a")
		BoardTile.Type.BANK: c = Color("1f4a2f")
		BoardTile.Type.CASINO: c = Color("5a1a2a")
	return c.lerp(sk["tint"], float(sk["tint_amt"]))  # service tiles keep their meaning (colour family) but wear the continent's tint


## Which vector icon a tile shows ("" = none). Icons are drawn with _draw_icon (no textures, no font).
func _icon_kind(t: BoardTile) -> String:
	match t.type:
		BoardTile.Type.CORNER:
			return String(t.corner_kind)  # start | sanctuary | rift | crossroads
		BoardTile.Type.SHOP: return "shop"
		BoardTile.Type.EVENT: return "event"
		BoardTile.Type.AUCTION: return "auction"
		BoardTile.Type.TAX: return "tax"
		BoardTile.Type.SPECIAL: return "special"
		BoardTile.Type.BANK: return "bank"
		BoardTile.Type.CASINO: return "casino"
	return ""


func _icon_color(kind: String) -> Color:
	match kind:
		"shop": return Color("8be9d6")
		"event": return Color("f6cf72")
		"auction": return Color("f59cc8")
		"tax": return Color("ff8f86")
		"special": return Color("b4c4ff")
		"bank": return Color("8df0a0")
		"casino": return Color("ff6b7a")
		"start": return Color("e9d27a")
		"sanctuary": return Color("9ff0b4")
		"rift": return Color("c9a2ff")
		"crossroads": return Color("e8e4d4")
	return UiTheme.COL_TEXT


## Draws one icon centred on `c`; `u` is its half-size in px (about 30% of the tile width).
func _draw_icon(kind: String, c: Vector2, u: float, col: Color) -> void:
	var w := maxf(1.5, u * 0.26)  # stroke width scales with the tile
	var dark := Color(0, 0, 0, 0.35)
	match kind:
		"shop":  # shopping bag with a handle
			var body := PackedVector2Array([c + Vector2(-0.8, -0.3) * u, c + Vector2(0.8, -0.3) * u, c + Vector2(0.95, 0.9) * u, c + Vector2(-0.95, 0.9) * u])
			draw_colored_polygon(body, col)
			draw_arc(c + Vector2(0, -0.3) * u, u * 0.42, PI, TAU, 14, col, w)
			draw_line(c + Vector2(-0.55, 0.1) * u, c + Vector2(0.55, 0.1) * u, dark, maxf(1.0, w * 0.6))
		"event":  # question mark in a ring
			draw_arc(c, u * 1.05, 0.0, TAU, 28, col, maxf(1.0, w * 0.7))
			var hc := c + Vector2(0, -0.22) * u
			draw_arc(hc, u * 0.4, PI * 0.95, TAU + PI * 0.45, 14, col, w)
			draw_line(hc + Vector2(cos(PI * 0.45), sin(PI * 0.45)) * u * 0.4, c + Vector2(0, 0.3) * u, col, w)
			draw_circle(c + Vector2(0, 0.7) * u, w * 0.62, col)
		"auction":  # gavel + block
			draw_set_transform(c + Vector2(0, -0.1) * u, -0.62, Vector2.ONE)
			draw_rect(Rect2(Vector2(-0.62, -0.78) * u, Vector2(1.24, 0.56) * u), col)
			draw_line(Vector2(0, -0.22) * u, Vector2(0, 0.95) * u, col, w)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_rect(Rect2(c + Vector2(-0.8, 0.82) * u, Vector2(1.6, 0.3) * u), col)
		"tax":  # percent sign on a coin
			draw_circle(c, u * 1.02, Color(col, 0.22))
			draw_arc(c, u * 1.02, 0.0, TAU, 28, col, maxf(1.0, w * 0.7))
			draw_line(c + Vector2(-0.5, 0.58) * u, c + Vector2(0.5, -0.58) * u, col, w)
			draw_circle(c + Vector2(-0.42, -0.42) * u, u * 0.2, col)
			draw_circle(c + Vector2(0.42, 0.42) * u, u * 0.2, col)
		"special":  # four-point sparkle
			var pts := PackedVector2Array()
			for k in range(8):
				var a := float(k) * PI / 4.0 - PI / 2.0
				var rr := u * (1.1 if k % 2 == 0 else 0.38)
				pts.append(c + Vector2(cos(a), sin(a)) * rr)
			draw_colored_polygon(pts, col)
		"bank":  # rising chart line with an arrowhead
			draw_polyline(PackedVector2Array([c + Vector2(-0.95, 0.7) * u, c + Vector2(-0.3, 0.05) * u, c + Vector2(0.15, 0.4) * u, c + Vector2(0.85, -0.55) * u]), col, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(1.05, -0.8) * u, c + Vector2(0.4, -0.7) * u, c + Vector2(0.95, -0.12) * u]), col)
			draw_line(c + Vector2(-1.0, 0.98) * u, c + Vector2(1.0, 0.98) * u, Color(col, 0.6), maxf(1.0, w * 0.6))
		"casino":  # die with three pips on a diagonal
			draw_rect(Rect2(c + Vector2(-0.95, -0.95) * u, Vector2(1.9, 1.9) * u), col)
			for d in [Vector2(-0.5, -0.5), Vector2(0, 0), Vector2(0.5, 0.5)]:
				draw_circle(c + d * u, u * 0.2, Color(0, 0, 0, 0.7))
		"start":  # flag
			draw_line(c + Vector2(-0.55, -0.95) * u, c + Vector2(-0.55, 1.0) * u, col, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.55, -0.95) * u, c + Vector2(0.95, -0.4) * u, c + Vector2(-0.55, 0.15) * u]), col)
		"sanctuary":  # cross in a ring
			draw_arc(c, u * 1.05, 0.0, TAU, 28, col, maxf(1.0, w * 0.7))
			draw_line(c + Vector2(0, -0.6) * u, c + Vector2(0, 0.6) * u, col, w * 1.2)
			draw_line(c + Vector2(-0.6, 0) * u, c + Vector2(0.6, 0) * u, col, w * 1.2)
		"rift":  # lightning bolt
			draw_colored_polygon(PackedVector2Array([c + Vector2(0.2, -1.05) * u, c + Vector2(-0.6, 0.12) * u, c + Vector2(-0.05, 0.12) * u,
				c + Vector2(-0.25, 1.05) * u, c + Vector2(0.65, -0.22) * u, c + Vector2(0.08, -0.22) * u]), col)
		"crossroads":  # two crossing roads with round ends
			for d in [Vector2(1, 1), Vector2(1, -1)]:
				draw_line(c - d * u * 0.8, c + d * u * 0.8, col, w * 1.1)
				draw_circle(c - d * u * 0.8, w * 0.75, col)
				draw_circle(c + d * u * 0.8, w * 0.75, col)


var _sb := StyleBoxFlat.new()  # one reusable rounded box for all drawing


## Rounded rectangle with optional border and soft shadow.
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


## Territory section of this continent's MapSkin (cached; the original look while no match is attached).
func _terr() -> Dictionary:
	var cid := String(ctrl.continent.get("id", "")) if ctrl != null else ""
	if _skin.is_empty() or cid != _skin_id:
		_skin_id = cid
		_skin = MapSkin.get_skin(cid)["territory"]
	return _skin


func _draw() -> void:
	_layout()
	var sk := _terr()
	var s := _cell * BoardBuilder.grid
	_rr(Rect2(_origin, Vector2(s, s)), sk["frame_bg"], _cell * 0.6, sk["frame"], 2.0, _cell * 0.5)
	if ctrl == null:
		return
	var font := ThemeDB.fallback_font
	for t in ctrl.tiles:
		_draw_tile(t, font)
	_draw_center(font)
	_draw_tokens()
	_draw_dice()


func _draw_tile(t: BoardTile, _font: Font) -> void:
	var gap := maxf(1.5, _cell * 0.07)
	var r := tile_rect(t.index).grow(-gap)
	var sk := _terr()
	var rad := _cell * float(sk["radius"])
	var base := _tile_color(t)
	var border := base.lightened(0.22)
	var bw := 1.0
	if t.type == BoardTile.Type.TERRITORY and t.owner_id >= 0:
		var oc: Color = ctrl.players[t.owner_id].color
		base = base.lerp(oc, 0.5)
		border = oc
		bw = 2.0
	_rr(r, base, rad, border, bw)
	if t.type == BoardTile.Type.TERRITORY:
		_sb.set_corner_radius_all(0)
		var band := Rect2(r.position + Vector2(bw, bw), Vector2(r.size.x - bw * 2.0, maxf(3.0, r.size.y * 0.26)))
		draw_rect(band, BoardBuilder.region_color(ctrl.continent, t.region))
		var body := Rect2(r.position + Vector2(0.0, band.size.y + bw), Vector2(r.size.x, r.size.y - band.size.y - bw))
		MapSkin.draw_motif(self, String(sk["pattern"]), body, MapSkin.motif_color(sk), t.index)  # the continent's own pattern on the ground
		if t.owner_id >= 0:
			var c: Color = ctrl.players[t.owner_id].color
			draw_circle(r.get_center() + Vector2(0, r.size.y * 0.12), _cell * 0.12, c.lightened(0.3))
			if t.level > 0:
				_draw_level_marks(t, r)
	var ik := _icon_kind(t)
	if ik != "":
		_draw_icon(ik, r.get_center(), minf(r.size.x, r.size.y) * (0.3 if t.type != BoardTile.Type.CORNER else 0.34), _icon_color(ik))
	if t.type == BoardTile.Type.PORTAL:
		var c := r.get_center()
		if t.portal_active:
			draw_circle(c, _cell * 0.3, UiTheme.COL_PURPLE)
			draw_arc(c, _cell * 0.34, 0.0, TAU, 20, UiTheme.COL_GOLD, 2.0)
		else:
			draw_arc(c, _cell * 0.26, 0.0, TAU, 16, Color("4a4f75"), 1.5)
	if t.index == selected_index:
		_rr(r.grow(1.5), Color(0, 0, 0, 0), rad, UiTheme.COL_GOLD, 3.0, _cell * 0.4)


## Upgrade marks along the bottom of an owned land: one gold pip per level, a gold diamond for the Landmark.
func _draw_level_marks(t: BoardTile, r: Rect2) -> void:
	var y := r.end.y - maxf(3.0, r.size.y * 0.14)
	var cx := r.get_center().x
	if t.is_landmark():
		var d := maxf(3.0, _cell * 0.16)
		draw_colored_polygon(PackedVector2Array([Vector2(cx, y - d), Vector2(cx + d, y), Vector2(cx, y + d), Vector2(cx - d, y)]), UiTheme.COL_GOLD)
		return
	var pr := maxf(1.5, _cell * 0.07)
	var step := pr * 2.8
	var x0 := cx - step * (t.level - 1) * 0.5
	for i in range(t.level):
		draw_circle(Vector2(x0 + step * i, y), pr, UiTheme.COL_GOLD)


## The centre panel of the ring: a 2-tile margin on the 100-tile board, 1.4 on the 40-tile Chaos board.
func _inner_rect() -> Rect2:
	var m := 2.0 if BoardBuilder.grid >= 26 else 1.5
	return Rect2(_origin + Vector2(_cell * m, _cell * m), Vector2(_cell * (BoardBuilder.grid - m * 2.0), _cell * (BoardBuilder.grid - m * 2.0)))


func _draw_center(font: Font) -> void:
	var inner := _inner_rect()
	var cu := inner.size.x / 22.0  # the centre panel is laid out for 22 units; on the small Chaos board a unit is smaller than a tile
	var sk := _terr()
	var plate: Color = Color(sk["center_bg"], 0.96)
	_rr(inner, plate, cu * 0.9, sk["center_border"], 2.0)
	MapSkin.draw_watermark(self, String(ctrl.continent.get("id", "")), Rect2(inner.get_center() - Vector2(cu * 8.5, cu * 8.5), Vector2(cu * 17.0, cu * 17.0)), sk, plate)
	var title := String(ctrl.continent.get("name", "")).to_upper()
	var ty := inner.position.y + cu * 3.2
	draw_string_outline(font, Vector2(inner.position.x, ty), title, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, int(cu * 1.6), 8, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(inner.position.x, ty), title, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, int(cu * 1.6), sk["title"])
	draw_rect(Rect2(inner.position.x + inner.size.x * 0.3, ty + cu * 0.6, inner.size.x * 0.4, 2.0), sk["title_dim"])
	var names := BoardBuilder.DEFAULT_REGION_NAMES
	var fs := int(cu * 0.66)
	for r in range(4):
		var y := inner.position.y + cu * (6.2 + r * 1.7)
		var row := Rect2(inner.position.x + cu * 1.2, y - cu * 0.95, inner.size.x - cu * 2.4, cu * 1.4)
		_rr(row, Color(1, 1, 1, 0.045), cu * 0.3)
		_rr(Rect2(row.position + Vector2(cu * 0.25, cu * 0.25), Vector2(cu * 0.9, cu * 0.9)), BoardBuilder.region_color(ctrl.continent, r), cu * 0.2)
		var rname: String = ctrl.continent["regions"][r]["name"] if ctrl.continent.has("regions") else names[r]
		draw_string(font, Vector2(row.position.x + cu * 1.6, y), "%s - %s" % [names[r], rname], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.COL_TEXT)
		# one coloured count per player, right aligned
		var x := row.end.x - cu * 0.4
		for pi in range(ctrl.players.size() - 1, -1, -1):
			var p = ctrl.players[pi]
			var txt := str(EconomySystem.region_count(ctrl.tiles, r, p.id))
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(x - w, y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, p.color.lightened(0.25))
			x -= w + cu * 0.9
	_draw_info(font, inner)


## The explanation (inspected tile / world modifier) sits in the centre of the map, right under the four region rows.
## The dice plate (drawn in view space, bottom-centre of the map) stays below it.
func _draw_info(font: Font, inner: Rect2) -> void:
	var cu := inner.size.x / 22.0
	if info_text == "":
		return
	var box := Rect2(inner.position.x + cu * 1.2, inner.position.y + cu * 12.4, inner.size.x - cu * 2.4, cu * 5.3)
	_rr(box, Color(1, 1, 1, 0.045), cu * 0.3)
	var fs := int(cu * 0.6)
	var line_h := font.get_height(fs)
	var pad := cu * 0.5
	var lines := maxi(1, int(floor((box.size.y - pad * 1.2) / line_h)))
	draw_multiline_string(font, Vector2(box.position.x + pad, box.position.y + pad + font.get_ascent(fs)), info_text,
		HORIZONTAL_ALIGNMENT_LEFT, box.size.x - pad * 2.0, fs, lines, UiTheme.COL_TEXT)


## The dice are drawn in VIEW space (fixed at the bottom-centre of the map, above the bottom tile row), not on the board, so they stay visible
## wherever the camera is panned or zoomed (the camera follows the pawn, which used to carry the board centre off-screen).
func _draw_dice() -> void:
	if ctrl.last_dice.x <= 0:
		return
	var d := clampf(minf(size.x, size.y) * (0.09 if BoardBuilder.grid >= 26 else 0.07), 44.0, 96.0)
	var gap := d * 0.28
	# bottom of the plate: 2.4 fitted cells above the board's bottom edge = inside the centre panel when the board is fitted
	var fit_cell := minf(size.x, size.y) / float(BoardBuilder.grid)
	var plate_bottom := minf(size.y * 0.5 + minf(size.x, size.y) * 0.5 - fit_cell * (2.4 if BoardBuilder.grid >= 26 else 1.9), size.y - 8.0)
	var top := Vector2(size.x * 0.5 - d - gap * 0.5, plate_bottom - d * 1.3)
	var rolling := _roll_t < 1.0
	var decay := 1.0 - _roll_t
	# a soft plate so the dice read against any tile colour
	_rr(Rect2(top - Vector2(d * 0.3, d * 0.3), Vector2(d * 2.0 + gap + d * 0.6, d * 1.6)), Color(0.04, 0.06, 0.13, 0.72), d * 0.25, Color("3d3822"), 1.5)
	for i in range(2):
		var v := ctrl.last_dice.x if i == 0 else ctrl.last_dice.y
		var dr := Rect2(top + Vector2(i * (d + gap), 0), Vector2(d, d))
		if not rolling:
			_rr(dr, Color("f1ead4"), d * 0.2, Color("b8962e"), 2.0, d * 0.13)
			_draw_pips(dr, v)
			continue
		v = 1 + posmod(int(_roll_t * 16.0) * 5 + i * 3 + _roll_seed, 6)  # a new random face ~16 times, never the same twice in a row
		var bounce := absf(sin(_roll_t * PI * 3.0)) * decay  # three hops that die out
		var sway := sin(_roll_t * 21.0 + float(i) * 2.1) * decay * 0.35
		var spin := decay * decay * TAU * (1.0 + 0.5 * float(i)) * (1.0 if i == 0 else -1.0)
		draw_circle(dr.get_center() + Vector2(0, d * 0.55), d * (0.5 - 0.15 * bounce), Color(0, 0, 0, 0.28 * (1.0 - 0.6 * bounce)))
		draw_set_transform(dr.get_center() + Vector2(sway * d * 0.33, -bounce * d * 0.37), spin, Vector2.ONE * (1.0 + 0.12 * bounce))
		var local := Rect2(Vector2(-d, -d) * 0.5, Vector2(d, d))
		_rr(local, Color("f1ead4"), d * 0.2, Color("b8962e"), 2.0, d * 0.13)
		_draw_pips(local, v)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pips(dr: Rect2, v: int) -> void:
	var o := dr.size.x * 0.27
	var c := dr.get_center()
	var pr := dr.size.x * 0.085
	var pts := {
		1: [Vector2(0, 0)],
		2: [Vector2(-1, -1), Vector2(1, 1)],
		3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
		6: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(1, 1)],
	}
	for q in pts.get(clampi(v, 1, 6), []):
		draw_circle(c + q * o, pr, Color("141a33"))


func _draw_tokens() -> void:
	var offs: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	var current_last: Array = []
	for p in ctrl.players:
		if not p.alive:
			continue
		# Fractional position = mid-walk: interpolate between the two tiles and lift the pawn in an arc (a hop).
		var v := float(_visual_pos.get(p.id, p.position))
		var i0 := floori(v)
		var f := v - float(i0)
		var c0 := tile_rect(posmod(i0, BoardBuilder.tiles_total)).get_center()
		var c1 := tile_rect(posmod(i0 + 1, BoardBuilder.tiles_total)).get_center()
		var lift := sin(PI * f) * _cell * HOP_HEIGHT if f > 0.0001 else 0.0
		var c := c0.lerp(c1, f) + offs[p.id % 4] * _cell * 0.2
		if p.id == ctrl.current:
			current_last = [c, p, lift]  # draw the active pawn last so it is on top
			continue
		_draw_pawn(c, p.color, false, lift)
	if not current_last.is_empty():
		_draw_pawn(current_last[0], current_last[1].color, true, current_last[2])


## `lift` raises the pawn off its (fixed) ground shadow; the shadow shrinks and fades as the pawn rises.
func _draw_pawn(c: Vector2, col: Color, active: bool, lift: float = 0.0) -> void:
	var rad := _cell * (0.3 if active else 0.25)
	var h := clampf(lift / (_cell * HOP_HEIGHT), 0.0, 1.0)
	draw_circle(c + Vector2(0, _cell * 0.07), rad * (1.0 - 0.35 * h), Color(0, 0, 0, 0.4 * (1.0 - 0.5 * h)))  # ground shadow
	c.y -= lift
	if active:
		draw_circle(c, rad + _cell * 0.16, Color(UiTheme.COL_GOLD, 0.25))  # glow
		draw_arc(c, rad + _cell * 0.1, 0.0, TAU, 28, UiTheme.COL_GOLD, 2.5)
	draw_circle(c, rad, col)
	draw_circle(c - Vector2(rad * 0.3, rad * 0.3), rad * 0.38, Color(1, 1, 1, 0.3))  # highlight
	draw_arc(c, rad, 0.0, TAU, 24, Color.WHITE if active else Color(1, 1, 1, 0.7), 2.0)
