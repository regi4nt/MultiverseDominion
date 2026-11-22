class_name UiTheme
extends RefCounted
## Dark navy + gold fantasy theme built in code (no external assets).

const COL_BG_DEEP := Color("070b17")
const COL_BG := Color("0b1020")
const COL_PANEL := Color("131a33")
const COL_PANEL_LIGHT := Color("1c2548")
const COL_GOLD := Color("d4af37")
const COL_GOLD_DIM := Color("8a7222")
const COL_TEXT := Color("e8e4d4")
const COL_MUTED := Color("8d93ad")
const COL_PURPLE := Color("6a3fb5")
const COL_DANGER := Color("c0392b")

static var _theme: Theme

## Smallest button height in logical px (1280x720 base): about 6 mm on a 6.5" phone.
const TOUCH_MIN := 52.0


static func make_box(bg: Color, border: Color, border_w: int = 2, radius: int = 12, shadow: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20
	# Buttons: rounded, soft shadow; a lighter fill on hover, pressed sinks (no shadow, 2 px lower).
	t.set_stylebox("normal", "Button", make_box(Color("222c57"), Color("6f6130"), 2, 12, 6))
	t.set_stylebox("hover", "Button", make_box(Color("2d3a73"), COL_GOLD, 2, 12, 8))
	var pressed := make_box(Color("4d2f8f"), COL_GOLD, 2, 12, 0)
	pressed.content_margin_top = 10
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", make_box(Color("111629"), Color("232842"), 2, 12, 0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("565c75"))
	t.set_stylebox("panel", "PanelContainer", make_box(Color(COL_PANEL, 0.94), Color("3b3a55"), 2, 16, 10))
	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("default_color", "RichTextLabel", COL_TEXT)
	_theme = t
	return t


static func make_button(text: String, min_h: float = 56.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, maxf(min_h, TOUCH_MIN))
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(Sfx.click)
	return b


## Call-to-action button (Roll Dice, Lock formation, ...): gold fill, dark text.
static func make_primary(text: String, min_h: float = 60.0) -> Button:
	var b := make_button(text, min_h)
	b.add_theme_stylebox_override("normal", make_box(Color("d9b440"), Color("fff0b0"), 2, 14, 8))
	b.add_theme_stylebox_override("hover", make_box(Color("f0cb55"), Color.WHITE, 2, 14, 10))
	var pr := make_box(Color("b8932c"), Color("fff0b0"), 2, 14, 0)
	pr.content_margin_top = 10
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("disabled", make_box(Color("4a432b"), Color("5e5538"), 2, 14, 0))
	b.add_theme_color_override("font_color", Color("1a1405"))
	b.add_theme_color_override("font_hover_color", Color("1a1405"))
	b.add_theme_color_override("font_pressed_color", Color("1a1405"))
	b.add_theme_color_override("font_disabled_color", Color("8a8160"))
	b.add_theme_font_size_override("font_size", 24)
	return b


## Destructive confirm button (Leave a battle, ...): red fill, light text.
static func make_danger(text: String, min_h: float = 60.0) -> Button:
	var b := make_button(text, min_h)
	b.add_theme_stylebox_override("normal", make_box(Color("b53a30"), Color("ff9a8f"), 2, 14, 8))
	b.add_theme_stylebox_override("hover", make_box(Color("cf4a3f"), Color.WHITE, 2, 14, 10))
	var pr := make_box(Color("8f2a22"), Color("ff9a8f"), 2, 14, 0)
	pr.content_margin_top = 10
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_font_size_override("font_size", 24)
	return b


## Player card: tinted with the player's colour, bright border when it is that player's turn.
static func player_card_box(color: Color, active: bool) -> StyleBoxFlat:
	var sb := make_box(Color(color.darkened(0.78), 0.9) if active else Color(COL_PANEL, 0.85), color if active else Color("2e3350"), 3 if active else 1, 12, 6 if active else 0)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func make_toggle(text: String, group: ButtonGroup, min_h: float = 48.0) -> Button:
	var b := make_button(text, min_h)
	b.toggle_mode = true
	b.button_group = group
	return b


## On/off switch. NOT in a ButtonGroup: a lone toggle inside a group behaves like a radio button and can never be
## switched off again (pressing the pressed button does nothing). Use make_toggle only for real either-or groups.
static func make_switch(text: String, min_h: float = 52.0) -> Button:
	var b := make_button(text, min_h)
	b.toggle_mode = true
	return b


static func make_label(text: String, font_size: int = 20, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## Soft radial gradient (lighter centre, dark vignette) instead of a flat fill.
static func make_background() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color("1a2350"))
	g.set_color(1, Color("060912"))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.45)
	tex.fill_to = Vector2(1.05, 1.0)
	tex.width = 256
	tex.height = 256
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Left / right insets (in UI units) that keep content clear of the camera cutout (notch / punch hole) and
## system bars in full-screen (immersive) mode. The background stays full-bleed; only the content is inset.
static func safe_insets() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	var vis := tree.root.get_visible_rect().size
	if win.x <= 0.0 or win.y <= 0.0 or vis.x <= 0.0:
		return Vector2.ZERO
	var scale := win.x / vis.x  # window pixels per UI unit (stretch mode canvas_items, aspect expand: uniform)
	var left := 0.0
	var right := 0.0
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x > 0.0 and safe.size.y > 0.0:
		left = maxf(0.0, safe.position.x)
		right = maxf(0.0, win.x - safe.end.x)
	# Cutouts that touch the left / right edge (landscape camera bezel), in case the safe area does not include them.
	for cut in DisplayServer.get_display_cutouts():
		var r := Rect2(cut)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		if r.position.x <= win.x * 0.25:
			left = maxf(left, r.end.x)
		elif r.end.x >= win.x * 0.75:
			right = maxf(right, win.x - r.position.x)
	# Older phones (e.g. OPPO A3s on Android 8.1, A11k) have a waterdrop notch but report no cutout / safe area.
	# On a long Android screen with no reported insets, assume the notch could sit on either short edge.
	if OS.get_name() == "Android" and left <= 0.0 and right <= 0.0 and win.x / win.y >= 1.9:
		left = win.y * 0.06
		right = win.y * 0.06
	# Manual extra margin from Settings ("Screen edge margin"), in UI units, for any device that still overlaps.
	var extra := 0.0
	var em: Variant = SaveManager.get_setting("edge_margin")
	if em != null:
		extra = clampf(float(em), 0.0, 120.0)
	# Cap: a bogus value must never squeeze the layout.
	return Vector2(minf(left / scale, 160.0) + extra, minf(right / scale, 160.0) + extra)


## Full-rect margin container. Left / right margins grow by the display's safe-area insets and follow
## window changes (rotation, fold, resize).
static func make_margin(px: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_top", px)
	m.add_theme_constant_override("margin_bottom", px)
	var apply := func() -> void:
		if not is_instance_valid(m):
			return
		var ins := safe_insets()
		m.add_theme_constant_override("margin_left", px + int(ceil(ins.x)))
		m.add_theme_constant_override("margin_right", px + int(ceil(ins.y)))
	apply.call()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.size_changed.connect(apply)
		m.tree_exited.connect(func() -> void:
			if tree.root.size_changed.is_connected(apply):
				tree.root.size_changed.disconnect(apply))
	return m


static func make_divider() -> ColorRect:
	var r := ColorRect.new()
	r.color = COL_GOLD
	r.custom_minimum_size = Vector2(0, 3)
	return r


## Touch-friendly ScrollContainer: a small finger wobble while tapping must not scroll the list, and a drag that
## starts on a button / card must still scroll it (children let the event bubble up, see `scroll_passthrough`).
static func make_scroll(deadzone: int = 12) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = deadzone
	return sc


## Call on every Button inside a ScrollContainer: PASS keeps the button working but lets the drag reach the scroller.
static func scroll_passthrough(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS
