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
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	box.add_child(UiTheme.make_label("SETTINGS", 44, UiTheme.COL_GOLD))
	box.add_child(UiTheme.make_divider())

	box.add_child(UiTheme.make_label("Master volume"))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(SaveManager.get_setting("master_volume"))
	slider.custom_minimum_size = Vector2(0, 40)
	slider.scrollable = false  # the mouse wheel must scroll the page, not change the volume
	# Live volume while dragging, but the save file is written once (on release / leaving), not on every 0.05 step.
	slider.value_changed.connect(func(v: float): SaveManager.set_setting("master_volume", v, false))
	slider.drag_ended.connect(func(_changed: bool): SaveManager.save_game())
	slider.tree_exiting.connect(func(): SaveManager.save_game())
	box.add_child(slider)

	var sfx_btn := UiTheme.make_switch("Sound effects: ON" if SaveManager.get_setting("sfx") else "Sound effects: OFF")
	sfx_btn.button_pressed = bool(SaveManager.get_setting("sfx"))
	sfx_btn.toggled.connect(func(on: bool):
		SaveManager.set_setting("sfx", on)
		sfx_btn.text = "Sound effects: ON" if on else "Sound effects: OFF"
		if on:
			Sfx.play("coin"))
	box.add_child(sfx_btn)

	var fs_on: bool = SaveManager.get_setting("fullscreen") == true  # default OFF
	var fs_btn := UiTheme.make_switch("Fullscreen: ON" if fs_on else "Fullscreen: OFF")
	fs_btn.button_pressed = fs_on
	fs_btn.toggled.connect(func(on: bool):
		SaveManager.set_setting("fullscreen", on)
		fs_btn.text = "Fullscreen: ON" if on else "Fullscreen: OFF")
	box.add_child(fs_btn)

	var upd_btn := UiTheme.make_switch("")
	var upd_on: bool = SaveManager.get_setting("check_updates") != false
	upd_btn.button_pressed = upd_on
	upd_btn.text = "Check for updates at start: ON" if upd_on else "Check for updates at start: OFF"
	upd_btn.toggled.connect(func(on: bool):
		SaveManager.set_setting("check_updates", on)
		upd_btn.text = "Check for updates at start: ON" if on else "Check for updates at start: OFF")
	box.add_child(upd_btn)

	# Manual check: ignores "skip this version" and always tells the player what happened.
	_chk_btn = UiTheme.make_button("Check for updates now  (v%s)" % UpdateCheck.current_version(), 52)
	_chk_btn.pressed.connect(_on_check_pressed)
	box.add_child(_chk_btn)

	box.add_child(UiTheme.make_label("Default AI difficulty"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var group := ButtonGroup.new()
	for d in ["easy", "normal", "hard"]:
		var b := UiTheme.make_toggle(d.capitalize(), group)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = (SaveManager.get_setting("default_difficulty") == d)
		b.pressed.connect(func(): SaveManager.set_setting("default_difficulty", d))
		row.add_child(b)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var back := UiTheme.make_button("Back", 60)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	box.add_child(back)


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
