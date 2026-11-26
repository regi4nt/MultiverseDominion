class_name TouchScroll
extends ScrollContainer
## Touch-friendly ScrollContainer (every scroll area in the game is made by UiTheme.make_scroll).
## Problem it solves: Buttons, Panels and RichTextLabels default to MOUSE_FILTER_STOP, so a swipe that STARTS on one of
## them never reaches the scroller and the list feels "stuck" (Deck, New Match, Shop, Settings, dialogs ...).
## 1. Every STOP control inside the area is switched to PASS (also controls added later, e.g. rebuilt card grids);
##    sliders, scrollbars and text inputs keep STOP because they need the drag themselves.
## 2. A swipe that began on a Button cancels that button's press once the finger moved past the dead zone, so
##    scrolling never "taps" the button you started on when you lift the finger.

var _tracking: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _pressed_btn: BaseButton = null
# Horizontal sliders keep STOP (they need the horizontal drag), but a mostly VERTICAL swipe that starts on one must
# scroll the page instead of being swallowed (sliders are full-width rows: Settings, Shop exchange, wager panel).
var _sl: HSlider = null
var _sl_val: float = 0.0
var _sl_press: Vector2 = Vector2.ZERO
var _sl_editable: bool = true
var _sl_scrolling: bool = false


func _init(deadzone: int = 12) -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_deadzone = deadzone
	gui_input.connect(_on_gui_input)


func _enter_tree() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _ready() -> void:
	_soften_children(self)


func _on_node_added(n: Node) -> void:
	if n is Control and n != self and is_ancestor_of(n):
		_soften(n as Control)


func _soften_children(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			_soften(c as Control)
		_soften_children(c)


func _soften(c: Control) -> void:
	if c is HSlider and not c.has_meta("ts_hooked"):
		c.set_meta("ts_hooked", true)
		c.gui_input.connect(_on_slider_input.bind(c as HSlider))
	if c.mouse_filter != Control.MOUSE_FILTER_STOP:
		return
	if c is Slider or c is ScrollBar or c is LineEdit or c is TextEdit or c is ScrollContainer or c is SpinBox:
		return  # these need the drag themselves
	c.mouse_filter = Control.MOUSE_FILTER_PASS


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_tracking = true
			_press_pos = event.global_position
			_pressed_btn = _button_at(event.global_position)
		else:
			_tracking = false
			_pressed_btn = null
	elif event is InputEventMouseMotion and _tracking and _pressed_btn != null:
		if event.global_position.distance_to(_press_pos) > float(scroll_deadzone):
			_cancel_press()


## The button under the finger, found by hit-testing the press position. gui_get_hovered_control() is NOT used: on a
## touchscreen there is no hover before the finger lands, so it returns the control of the PREVIOUS touch (or null),
## and a swipe would then tap the wrong button or none. Last match in tree order = the topmost one.
func _button_at(gpos: Vector2) -> BaseButton:
	var found: BaseButton = null
	for b in _buttons_under(self):
		if b.get_global_rect().has_point(gpos):
			found = b  # tree order = draw order, so the last hit is the topmost
	return found


func _buttons_under(n: Node) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for c in n.get_children():
		if c is BaseButton and (c as BaseButton).is_visible_in_tree() and not (c as BaseButton).disabled \
				and (c as BaseButton).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append(c as BaseButton)
		out.append_array(_buttons_under(c))
	return out


## The finger is scrolling, not tapping: drop the button's press (disable + enable in the same frame, nothing is drawn in between).
func _cancel_press() -> void:
	var b := _pressed_btn
	_pressed_btn = null
	if is_instance_valid(b) and not b.disabled:
		b.disabled = true
		b.disabled = false


## gui_input is emitted BEFORE the slider handles the event, so on press the value is still the old one.
func _on_slider_input(event: InputEvent, s: HSlider) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_sl = s
			_sl_val = s.value
			_sl_press = event.global_position
			_sl_editable = s.editable
			_sl_scrolling = false
		elif _sl == s:
			if _sl_scrolling:
				s.editable = _sl_editable  # re-enabled before the slider sees the release, so its drag state ends cleanly
			_sl = null
			_sl_scrolling = false
	elif event is InputEventMouseMotion and _sl == s and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if not _sl_scrolling:
			var d: Vector2 = event.global_position - _sl_press
			if absf(d.y) > float(scroll_deadzone) and absf(d.y) > absf(d.x) * 1.2:
				_sl_scrolling = true
				s.value = _sl_val  # undo the jump the press made
				s.editable = false  # the slider stops following the finger
				scroll_vertical -= int(d.y)
		else:
			scroll_vertical -= int(event.relative.y)
