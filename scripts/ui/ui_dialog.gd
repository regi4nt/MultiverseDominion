class_name UiDialog
extends CanvasLayer
## Themed modal dialog: a drop-in replacement for ConfirmationDialog / AcceptDialog.
## The built-in dialogs are plain OS-style windows that ignore the game theme and have tiny buttons; this one is an
## overlay on its own CanvasLayer (always on top, covers the whole screen), with a dimmed backdrop, a tone badge,
## and full-width touch-size buttons.
##
## Same API as ConfirmationDialog for the properties the game uses:
##   title, dialog_text, ok_button_text, cancel_button_text, popup_centered(size_hint), visible, hide(),
##   signals confirmed / canceled, add_button(text, right, action) + custom_action.
## Extras:
##   tone         "info" (purple, "?"), "warn" (gold, "!"), "danger" (red, "!": the confirm button turns red too)
##   show_cancel  false for a single-button dialog (e.g. the profile card)
##   body_node    custom content instead of dialog_text (consumed by the dialog; build a fresh one per dialog)
## Android Back / Esc dismiss the open dialog first (see AppNav.go_back), the same as tapping Cancel or the backdrop.

signal confirmed
signal canceled
signal custom_action(action: StringName)

const BODY_MAX_RATIO := 0.5  # the text area never takes more than half of the screen height (it scrolls instead)

var title := ""
var dialog_text := ""
var ok_button_text := "OK"
var cancel_button_text := "Cancel"
var tone := "info"
var show_cancel := true
var body_node: Control = null
var dismiss_on_backdrop := true

var _extra: Array = []  # [{"text": String, "action": StringName}]
var _root: Control = null


func _init() -> void:
	layer = 60  # above every scene UI
	visible = false


func _ready() -> void:
	add_to_group("ui_dialog")


## Same signature as AcceptDialog.add_button (`right` is ignored: extra buttons always sit left of Cancel).
func add_button(text: String, _right: bool = false, action: String = "") -> void:
	_extra.append({"text": text, "action": StringName(action)})


## `size_hint.x` is the wanted panel width (like the old window size); the height always follows the content.
func popup_centered(size_hint: Vector2i = Vector2i.ZERO) -> void:
	if not is_inside_tree():
		push_warning("UiDialog: add it to the tree before popup_centered()")
		return
	_build(float(size_hint.x))
	show()
	if FxMode.is_lite():  # Lite: no fade-in
		_root.modulate.a = 1.0
		return
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.12)


## Cancel path (Cancel button, backdrop tap, Android Back).
func dismiss() -> void:
	canceled.emit()
	hide()


func _confirm() -> void:
	confirmed.emit()
	hide()


func _on_backdrop_input(event: InputEvent) -> void:
	if not dismiss_on_backdrop:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		dismiss()
	elif event is InputEventScreenTouch and event.pressed:
		dismiss()


# ------------------------------------------------------------------ building

func _tone_color() -> Color:
	match tone:
		"danger":
			return UiTheme.COL_DANGER
		"warn":
			return UiTheme.COL_GOLD
		_:
			return Color("8a63d6")


func _build(width_hint: float) -> void:
	if _root != null:
		# Keep a custom body alive if the dialog is opened twice; everything else is rebuilt.
		if body_node != null and is_instance_valid(body_node) and body_node.get_parent() != null:
			body_node.get_parent().remove_child(body_node)
		remove_child(_root)
		_root.queue_free()
	var vp := get_viewport().get_visible_rect().size
	var panel_w := clampf(maxf(width_hint, 540.0), 320.0, vp.x - 48.0)

	_root = Control.new()
	_root.theme = UiTheme.get_theme()  # a CanvasLayer does not pass the scene's theme down
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.08, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks the scene underneath
	dim.gui_input.connect(_on_backdrop_input)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var accent := _tone_color()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(panel_w, 0)
	var border := accent if tone != "info" else UiTheme.COL_GOLD_DIM
	var sb := UiTheme.make_box(Color("141b36"), border, 2, 20, 28)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 26
	sb.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	panel.add_child(col)

	var inner_w := panel_w - 56.0
	var text_lbl: Label = null
	var scroll: ScrollContainer = null
	if body_node != null:
		col.add_child(body_node)
	else:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 20)
		col.add_child(head)
		head.add_child(_make_badge(accent))

		var text_col := VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_col.add_theme_constant_override("separation", 10)
		head.add_child(text_col)
		if title != "":
			var t := UiTheme.make_label(title, 30, UiTheme.COL_GOLD if tone != "danger" else Color("ff8f84"))
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t.custom_minimum_size.x = inner_w - 84.0
			text_col.add_child(t)
		if dialog_text != "":
			scroll = UiTheme.make_scroll()
			text_col.add_child(scroll)
			text_lbl = UiTheme.make_label(dialog_text, 21, UiTheme.COL_TEXT)
			text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text_lbl.custom_minimum_size.x = inner_w - 84.0 - 4.0
			scroll.add_child(text_lbl)

	col.add_child(_make_buttons())
	# The text area takes the height of its text (measured, so no extra frame is needed) up to half the screen;
	# a long text (update notes) scrolls inside it instead of pushing the buttons off screen.
	if scroll != null and text_lbl != null:
		var font := text_lbl.get_theme_font("font")
		var fs := text_lbl.get_theme_font_size("font_size")
		var need := font.get_multiline_string_size(dialog_text, HORIZONTAL_ALIGNMENT_LEFT, text_lbl.custom_minimum_size.x, fs).y
		scroll.custom_minimum_size.y = minf(ceilf(need) + 6.0, vp.y * BODY_MAX_RATIO)


func _make_badge(accent: Color) -> Control:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(64, 64)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := UiTheme.make_box(Color(accent, 0.18), accent, 3, 32, 0)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	badge.add_theme_stylebox_override("panel", sb)
	var c := CenterContainer.new()
	badge.add_child(c)
	var glyph := "?" if tone == "info" else "!"
	c.add_child(UiTheme.make_label(glyph, 38, accent.lightened(0.35)))
	return badge


func _make_buttons() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	for e in _extra:
		var xb := UiTheme.make_button(String(e["text"]), 58)
		xb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var action: StringName = e["action"]
		xb.pressed.connect(func():
			custom_action.emit(action)
			hide())
		row.add_child(xb)
	if show_cancel:
		var cb := UiTheme.make_button(cancel_button_text, 58)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.pressed.connect(dismiss)
		row.add_child(cb)
	var ok: Button = UiTheme.make_danger(ok_button_text, 58) if tone == "danger" else UiTheme.make_primary(ok_button_text, 58)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok.size_flags_stretch_ratio = 1.25
	ok.pressed.connect(_confirm)
	row.add_child(ok)
	return row
