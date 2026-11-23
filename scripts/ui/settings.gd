extends Control

var _chk_btn: Button

func _ready() -> void:
	theme = UiTheme.get_theme()
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(40)
	add_child(margin)
	var scroll := UiTheme.make_scroll()
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL  # Back stays at the bottom when everything fits
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)
	box.add_child(UiTheme.make_label("SETTINGS", 44, UiTheme.COL_GOLD))

	# One simple card: "label ........ control" rows, no ON/OFF text, no long captions.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.make_box(UiTheme.COL_PANEL, UiTheme.COL_GOLD_DIM, 2, 14))
	box.add_child(panel)
	var pm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pm.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(pm)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	pm.add_child(rows)

	# Volume
	var slider := _make_slider(0.0, 1.0, 0.05, float(SaveManager.get_setting("master_volume")))
	# Live volume while dragging, but the save file is written once (on release / leaving), not on every 0.05 step.
	slider.value_changed.connect(func(v: float): SaveManager.set_setting("master_volume", v, false))
	slider.drag_ended.connect(func(_changed: bool): SaveManager.save_game())
	slider.tree_exiting.connect(func(): SaveManager.save_game())
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(_row("Volume", slider))

	# Toggles
	var sfx := _make_toggle(bool(SaveManager.get_setting("sfx")))
	sfx.toggled.connect(func(on: bool):
		SaveManager.set_setting("sfx", on)
		if on:
			Sfx.play("coin"))
	rows.add_child(_row("Sound effects", sfx))

	var fs := _make_toggle(SaveManager.get_setting("fullscreen") == true)  # default OFF
	fs.toggled.connect(func(on: bool): SaveManager.set_setting("fullscreen", on))
	rows.add_child(_row("Fullscreen", fs))

	rows.add_child(_thin_line())

	# Effects: Pro = all animations, Lite = instant results (lighter for weak devices).
	var fx_row := HBoxContainer.new()
	fx_row.add_theme_constant_override("separation", 8)
	var fx_group := ButtonGroup.new()
	for m in [[FxMode.LITE, "Lite"], [FxMode.PRO, "Pro"]]:
		var fb := UiTheme.make_toggle(m[1], fx_group, 44.0)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.button_pressed = (FxMode.mode() == m[0])
		var mode_id: String = m[0]
		fb.pressed.connect(func(): SaveManager.set_setting("effects", mode_id))
		fx_row.add_child(fb)
	rows.add_child(_row("Effects", fx_row, true))
	rows.add_child(UiTheme.make_label("Pro: all animations.  Lite: instant, lighter on weak devices.", 16, UiTheme.COL_MUTED))

	rows.add_child(_thin_line())

	# Difficulty
	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for d in ["easy", "normal", "hard"]:
		var b := UiTheme.make_toggle(d.capitalize(), group, 44.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = (SaveManager.get_setting("default_difficulty") == d)
		b.pressed.connect(func(): SaveManager.set_setting("default_difficulty", d))
		diff_row.add_child(b)
	rows.add_child(_row("Difficulty", diff_row, true))

	rows.add_child(_thin_line())

	# Updates: auto-check switch + manual check (ignores "skip this version" and always tells the player what happened).
	var upd := _make_toggle(SaveManager.get_setting("check_updates") != false)
	upd.toggled.connect(func(on: bool): SaveManager.set_setting("check_updates", on))
	rows.add_child(_row("Auto-check updates", upd))
	_chk_btn = UiTheme.make_button("Check now  (v%s)" % UpdateCheck.current_version(), 44)
	_chk_btn.pressed.connect(_on_check_pressed)
	rows.add_child(_chk_btn)

	# Camera-notch margin: rarely needed, so kept as one small row at the bottom of the card.
	var em_cur = SaveManager.get_setting("edge_margin")
	var em_slider := _make_slider(0, 120, 4, float(em_cur) if em_cur != null else 0.0)
	em_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var em_val := UiTheme.make_label(str(int(em_slider.value)), 20, UiTheme.COL_MUTED)
	em_val.custom_minimum_size = Vector2(44, 0)
	em_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	em_slider.value_changed.connect(func(v: float):
		SaveManager.set_setting("edge_margin", int(v), false)
		em_val.text = str(int(v))
		get_tree().root.size_changed.emit())  # every margin container re-reads the insets
	em_slider.drag_ended.connect(func(_changed: bool): SaveManager.save_game())
	em_slider.tree_exiting.connect(func(): SaveManager.save_game())
	var em_box := HBoxContainer.new()
	em_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	em_box.add_theme_constant_override("separation", 8)
	em_box.add_child(em_slider)
	em_box.add_child(em_val)
	rows.add_child(_row("Notch margin", em_box))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var back := UiTheme.make_button("Back", 60)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	box.add_child(back)


## "Label .......... control" on one line (stacked when `wide`, for controls that need the full width).
func _row(text: String, control: Control, wide: bool = false) -> Control:
	var lbl := UiTheme.make_label(text)
	if wide:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.add_child(lbl)
		v.add_child(control)
		return v
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size = Vector2(160, 0)
	h.add_child(lbl)
	h.add_child(control)
	return h


func _thin_line() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(UiTheme.COL_MUTED, 0.25)
	r.custom_minimum_size = Vector2(0, 1)
	return r


func _make_slider(min_v: float, max_v: float, step_v: float, value_v: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.value = value_v
	s.custom_minimum_size = Vector2(220, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.scrollable = false  # the mouse wheel must scroll the page, not change the value
	return s


func _make_toggle(on: bool) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	return c


func _on_check_pressed() -> void:
	_chk_btn.disabled = true
	_chk_btn.text = "Checking..."
	var uc := UpdateCheck.new()
	add_child(uc)
	uc.check_finished.connect(_on_check_finished)
	uc.check()


func _on_check_finished(status: String, info: Dictionary) -> void:
	_chk_btn.disabled = false
	if status == "available":
		_chk_btn.text = "Update available: v%s" % info["version"]
		UpdateCheck.show_dialog(self, info, false)
	elif status == "current":
		_chk_btn.text = "You are up to date (v%s)" % UpdateCheck.current_version()
	else:
		_chk_btn.text = "Could not check (offline?). Tap to retry"
