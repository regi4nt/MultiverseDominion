extends VBoxContainer
## Bet slider: one reusable "slide to set your stake" control for the Shop > Gamble tab, the Territory Casino and the Shop > Trading tab.
## Layout:  [Min] [25%] [50%] [75%] [Max]  quick buttons,  [ - ]  ----O-----------  [ + ],  big gold value + balance line.
## Two ways to define the steps (both end up as a list of allowed values the slider walks over by index):
##   - "values": Array of ints (e.g. the fixed Casino bets 50 / 100 / 250 / 500), or
##   - "min" / "max" / "step": a free range (e.g. Gamble 100..10000 step 100).
## The balance limits the slider: values above what the player can pay are not reachable (the track shortens, never lies).
## Config keys: "unit" (shown after the value), "balance" (Callable -> int, optional), "start" (initial value),
## "presets" (bool, default true), "font" (value label size), "accent" (Color of the filled track / handle).

signal value_changed(value: int)

var value: int = 0
var unit: String = "chips"
var values: Array[int] = []  # every allowed value, ascending
var accent: Color = UiTheme.COL_GOLD

var _balance_fn: Callable
var _slider: HSlider
var _minus: Button
var _plus: Button
var _value_label: Label
var _preset_row: HBoxContainer
var _preset_btns: Array = []  # [Button, fraction]
var _reach: int = 0  # how many entries of `values` are affordable right now
var _locked := false
var _quiet := false  # true while the code (not the player) moves the slider

static var _grabber_cache: Dictionary = {}  # color html -> {"n": Texture2D, "h": Texture2D}


func _init(cfg: Dictionary = {}) -> void:
	unit = String(cfg.get("unit", "chips"))
	accent = cfg.get("accent", UiTheme.COL_GOLD)
	_balance_fn = cfg.get("balance", Callable())
	if cfg.has("values"):
		for v in cfg["values"]:
			values.append(int(v))
		values.sort()
	else:
		var lo := int(cfg.get("min", 100))
		var hi := int(cfg.get("max", 1000))
		var st := maxi(int(cfg.get("step", 100)), 1)
		var v := lo
		while v <= hi:
			values.append(v)
			v += st
	if values.is_empty():
		values.append(1)
	value = int(cfg.get("start", values[0]))
	add_theme_constant_override("separation", 4)
	_build(bool(cfg.get("presets", true)), int(cfg.get("font", 34)))
	set_value(value)


func _build(presets: bool, font: int) -> void:
	# value + balance
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	_value_label = UiTheme.make_label("", font, accent)
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_value_label)
	if presets:  # quick buttons sit on the value row so the whole control stays two rows high
		_preset_row = HBoxContainer.new()
		_preset_row.add_theme_constant_override("separation", 4)
		head.add_child(_preset_row)
		for p in [["Min", 0.0], ["1/2", 0.5], ["Max", 1.0]]:
			var b := UiTheme.make_button(String(p[0]), 36)
			b.custom_minimum_size.x = 56
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.add_theme_font_size_override("font_size", 16)
			b.pressed.connect(_on_preset.bind(float(p[1])))
			_preset_row.add_child(b)
			_preset_btns.append([b, float(p[1])])
	# slider line
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	add_child(line)
	_minus = UiTheme.make_button("-", 48)
	_minus.custom_minimum_size.x = 52
	_minus.pressed.connect(func(): _nudge(-1))
	line.add_child(_minus)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = maxi(values.size() - 1, 1)
	_slider.step = 1
	_slider.rounded = true
	_slider.custom_minimum_size = Vector2(100, 40)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.scrollable = false  # the mouse wheel must scroll the page, not change the stake
	_style_slider()
	if values.size() <= 8 and values.size() > 1:  # a handful of fixed bets: show a tick for each
		_slider.tick_count = values.size()
		_slider.ticks_on_borders = true
	_slider.value_changed.connect(_on_slid)
	line.add_child(_slider)
	_plus = UiTheme.make_button("+", 48)
	_plus.custom_minimum_size.x = 52
	_plus.pressed.connect(func(): _nudge(1))
	line.add_child(_plus)


## Gold track (filled part), dark rail, round handle that grows on hover. Everything is drawn in code, no assets.
func _style_slider() -> void:
	var rail := UiTheme.make_box(Color(UiTheme.COL_BG_DEEP, 0.9), Color("2a3158"), 1, 8)
	rail.content_margin_top = 6
	rail.content_margin_bottom = 6
	var fill := UiTheme.make_box(accent.darkened(0.15), accent.lightened(0.2), 1, 8)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	var fill_hl := UiTheme.make_box(accent, accent.lightened(0.4), 1, 8)
	fill_hl.content_margin_top = 6
	fill_hl.content_margin_bottom = 6
	_slider.add_theme_stylebox_override("slider", rail)
	_slider.add_theme_stylebox_override("grabber_area", fill)
	_slider.add_theme_stylebox_override("grabber_area_highlight", fill_hl)
	var tex := _grabber_textures(accent)
	_slider.add_theme_icon_override("grabber", tex["n"])
	_slider.add_theme_icon_override("grabber_highlight", tex["h"])
	_slider.add_theme_icon_override("grabber_disabled", tex["d"])
	_slider.add_theme_icon_override("tick", _tick_texture())


static func _disc(d: int, fill: Color, ring: Color, ring_w: float) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c := (d - 1) * 0.5
	var r := d * 0.5 - 1.0
	for y in range(d):
		for x in range(d):
			var dist := Vector2(x - c, y - c).length()
			var a := clampf(r - dist + 0.5, 0.0, 1.0)  # soft edge
			var col := ring if dist > r - ring_w else fill
			img.set_pixel(x, y, Color(col, col.a * a))
	return ImageTexture.create_from_image(img)


static func _grabber_textures(c: Color) -> Dictionary:
	var key := c.to_html()
	if _grabber_cache.has(key):
		return _grabber_cache[key]
	var dark := Color("1a1405")
	var out := {
		"n": _disc(34, c, dark, 4.0),
		"h": _disc(40, c.lightened(0.3), dark, 4.0),
		"d": _disc(34, Color("565c75"), Color("232842"), 4.0),
	}
	_grabber_cache[key] = out
	return out


static func _tick_texture() -> ImageTexture:
	return _disc(6, Color(UiTheme.COL_TEXT, 0.55), Color(UiTheme.COL_TEXT, 0.55), 1.0)


# ------------------------------------------------------------------ public

## Sets the stake (snapped down to the nearest allowed value, never above what the balance allows).
func set_value(v: int, emit: bool = false) -> void:
	_recount()
	var idx := 0
	for i in range(maxi(_reach, 1)):
		if values[i] <= v:
			idx = i
	_apply(idx, emit)


## Re-reads the balance: shortens / lengthens the track and keeps the stake inside it. Call after every payout.
func refresh() -> void:
	var before := value
	_recount()
	var idx := _index_of(value)
	idx = clampi(idx, 0, maxi(_reach - 1, 0))
	_apply(idx, false)
	if value != before:
		value_changed.emit(value)


## True when the player can pay at least the smallest stake.
func can_bet() -> bool:
	return _reach > 0


## Stops the player from touching the slider (animation running / round over).
func set_locked(b: bool) -> void:
	_locked = b
	_update_ui()


func balance() -> int:
	return int(_balance_fn.call()) if _balance_fn.is_valid() else values[values.size() - 1]


# ------------------------------------------------------------------ internals

func _recount() -> void:
	var bal := balance()
	_reach = 0
	for v in values:
		if v <= bal:
			_reach += 1


func _index_of(v: int) -> int:
	var idx := 0
	for i in range(values.size()):
		if values[i] <= v:
			idx = i
	return idx


func _apply(idx: int, emit: bool) -> void:
	idx = clampi(idx, 0, maxi(_reach - 1, 0))
	var changed := values[idx] != value
	value = values[idx]
	_update_ui()
	if emit and changed:
		value_changed.emit(value)


func _on_slid(v: float) -> void:
	if _quiet:
		return
	_apply(int(v), true)


func _nudge(dir: int) -> void:
	_apply(_index_of(value) + dir, true)


func _on_preset(fraction: float) -> void:
	if _reach <= 0:
		return
	_apply(int(round(float(_reach - 1) * fraction)), true)


func _update_ui() -> void:
	if _slider == null:
		return
	var idx := _index_of(value)
	var can := _reach > 0 and not _locked
	_quiet = true
	_slider.max_value = maxi(values.size() - 1, 1)
	_slider.set_value_no_signal(idx)
	_quiet = false
	_slider.editable = can and _reach > 1
	_minus.disabled = not can or idx <= 0
	_plus.disabled = not can or idx >= _reach - 1
	for pb in _preset_btns:
		(pb[0] as Button).disabled = not can or _reach <= 1
	_value_label.text = _fmt(value) + " " + unit if _reach > 0 else "Not enough " + unit
	_value_label.add_theme_color_override("font_color", accent if _reach > 0 else UiTheme.COL_DANGER)
	modulate.a = 0.6 if _locked else 1.0


static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
