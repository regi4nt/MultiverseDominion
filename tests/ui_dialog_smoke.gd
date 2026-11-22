extends Node
## UiDialog (themed confirm / profile dialogs): confirm, cancel, backdrop, Android Back, profile card content.

var fails := 0
var _confirmed := 0
var _canceled := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		push_error("FAIL: " + msg)


func _ready() -> void:
	var host := Control.new()
	add_child(host)

	# --- confirm
	var d := UiDialog.new()
	d.title = "Leave?"
	d.dialog_text = "Really leave?"
	d.ok_button_text = "Leave"
	d.cancel_button_text = "Stay"
	d.tone = "danger"
	d.confirmed.connect(func(): _confirmed += 1)
	d.canceled.connect(func(): _canceled += 1)
	host.add_child(d)
	check(not d.visible, "a new dialog is hidden")
	d.popup_centered(Vector2i(460, 160))
	check(d.visible, "popup_centered shows the dialog")
	var buttons := _buttons(d)
	check(buttons.size() == 2, "confirm dialog has Stay + Leave (%d buttons)" % buttons.size())
	for b in buttons:
		check(b.custom_minimum_size.y >= UiTheme.TOUCH_MIN, "dialog buttons are touch size")
	_press(buttons, "Leave")
	check(_confirmed == 1 and not d.visible, "Leave emits confirmed and closes")
	d.popup_centered()
	_press(_buttons(d), "Stay")
	check(_canceled == 1 and not d.visible, "Stay emits canceled and closes")

	# --- Android Back closes the open dialog before the scene reacts
	d.popup_centered()
	AppNav.go_back()
	check(_canceled == 2 and not d.visible, "Back dismisses the open dialog")

	# --- backdrop tap = cancel; dismiss_on_backdrop = false ignores it
	d.popup_centered()
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	d._root.get_child(0).gui_input.emit(tap)
	check(_canceled == 3 and not d.visible, "tapping the backdrop cancels")
	d.dismiss_on_backdrop = false
	d.popup_centered()
	d._root.get_child(0).gui_input.emit(tap)
	check(d.visible, "backdrop tap is ignored when dismiss_on_backdrop = false")
	d.hide()

	# --- custom action button (update dialog: "Skip this version")
	var u := UiDialog.new()
	u.dialog_text = "x"
	var got := []
	u.add_button("Skip", false, "skip")
	u.custom_action.connect(func(a: StringName): got.append(a))
	host.add_child(u)
	u.popup_centered()
	_press(_buttons(u), "Skip")
	check(got == [&"skip"] and not u.visible, "custom action is emitted and closes")

	# --- long text scrolls instead of growing past half the screen
	var l := UiDialog.new()
	l.dialog_text = "line\n".repeat(80)
	host.add_child(l)
	l.popup_centered(Vector2i(600, 0))
	var vp_h := host.get_viewport().get_visible_rect().size.y
	var panel: Control = l._root.get_child(1).get_child(0)
	check(panel.get_combined_minimum_size().y <= vp_h, "a very long text still fits the screen (%s > %s)" % [panel.get_combined_minimum_size().y, vp_h])
	l.hide()

	# --- profile card: with a record and with a fresh profile
	SaveManager.data["stats"] = {"matches_played": 0, "wins": 0, "losses": 0, "total_rounds": 0, "best_gold": 0}
	SaveManager.data["profile"]["name"] = "Zed"
	var empty := ProfileView.build()
	var texts := _texts(empty)
	check("Zed" in texts and "Z" in texts, "profile shows the name and its initial")
	check("-" in texts and "No matches yet. Start a NEW MATCH to build your record." in texts, "fresh profile: no win rate, shows the empty hint")
	empty.free()
	SaveManager.data["stats"] = {"matches_played": 4, "wins": 3, "losses": 1, "total_rounds": 60, "best_gold": 900}
	var full := ProfileView.build()
	texts = _texts(full)
	check("75%" in texts and "900" in texts and "60" in texts, "profile shows win rate, best gold and rounds")
	check(not ("No matches yet. Start a NEW MATCH to build your record." in texts), "no empty hint once matches were played")
	full.free()

	# --- Main Menu opens the profile as a UiDialog and frees it on Close
	var menu: Control = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu._show_profile()
	var opened := get_tree().get_nodes_in_group("ui_dialog").filter(func(n): return n.visible)
	check(opened.size() == 1, "Profile opens one dialog")
	if opened.size() == 1:
		_press(_buttons(opened[0]), "Close")
		await get_tree().process_frame
		await get_tree().process_frame
		check(get_tree().get_nodes_in_group("ui_dialog").filter(func(n): return n.visible).is_empty(), "Close hides the profile")
	menu.queue_free()
	await get_tree().process_frame
	print("UI DIALOG SMOKE: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)


func _buttons(d: UiDialog) -> Array:
	var out := []
	_collect(d._root, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _press(buttons: Array, text: String) -> void:
	for b in buttons:
		if b.text == text:
			b.pressed.emit()
			return
	check(false, "no button '%s'" % text)


func _texts(n: Node) -> Array:
	var out := []
	if n is Label:
		out.append(n.text)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out
