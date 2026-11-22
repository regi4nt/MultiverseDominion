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


static func make_box(bg: Color, border: Color, border_w: int = 2, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
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
	t.set_stylebox("normal", "Button", make_box(COL_PANEL_LIGHT, COL_GOLD_DIM))
	t.set_stylebox("hover", "Button", make_box(Color("27336a"), COL_GOLD))
	t.set_stylebox("pressed", "Button", make_box(COL_PURPLE, COL_GOLD))
	t.set_stylebox("disabled", "Button", make_box(Color("101528"), Color("2a2f45")))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("565c75"))
	t.set_stylebox("panel", "PanelContainer", make_box(COL_PANEL, COL_GOLD_DIM, 2, 10))
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


static func make_toggle(text: String, group: ButtonGroup, min_h: float = 48.0) -> Button:
	var b := make_button(text, min_h)
	b.toggle_mode = true
	b.button_group = group
	return b


static func make_label(text: String, font_size: int = 20, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func make_background() -> ColorRect:
	var r := ColorRect.new()
	r.color = COL_BG
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func make_margin(px: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px)
	return m


static func make_divider() -> ColorRect:
	var r := ColorRect.new()
	r.color = COL_GOLD
	r.custom_minimum_size = Vector2(0, 3)
	return r
