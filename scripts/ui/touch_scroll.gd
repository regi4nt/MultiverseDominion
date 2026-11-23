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
			var h := get_viewport().gui_get_hovered_control()
			_pressed_btn = h as BaseButton if (h is BaseButton and not (h as BaseButton).disabled and is_ancestor_of(h)) else null
		else:
			_tracking = false
			_pressed_btn = null
	elif event is InputEventMouseMotion and _tracking and _pressed_btn != null:
		if event.global_position.distance_to(_press_pos) > float(scroll_deadzone):
			_cancel_press()


## The finger is scrolling, not tapping: drop the button's press (disable + enable in the same frame, nothing is drawn in between).
func _cancel_press() -> void:
	var b := _pressed_btn
	_pressed_btn = null
	if is_instance_valid(b) and not b.disabled:
		b.disabled = true
		b.disabled = false
