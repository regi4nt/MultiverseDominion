extends Control


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(40)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	box.add_child(UiTheme.make_label("SETTINGS", 44, UiTheme.COL_GOLD))
	box.add_child(UiTheme.make_divider())

	box.add_child(UiTheme.make_label("Master volume"))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(SaveManager.get_setting("master_volume"))
	slider.custom_minimum_size = Vector2(0, 40)
	slider.value_changed.connect(func(v: float): SaveManager.set_setting("master_volume", v))
	box.add_child(slider)

	var sfx_btn := UiTheme.make_toggle("Sound effects: ON" if SaveManager.get_setting("sfx") else "Sound effects: OFF", ButtonGroup.new(), 52)
	sfx_btn.button_pressed = bool(SaveManager.get_setting("sfx"))
	sfx_btn.toggled.connect(func(on: bool):
		SaveManager.set_setting("sfx", on)
		sfx_btn.text = "Sound effects: ON" if on else "Sound effects: OFF"
		if on:
			Sfx.play("coin"))
	box.add_child(sfx_btn)

	var upd_btn := UiTheme.make_toggle("", ButtonGroup.new(), 52)
	var upd_on: bool = SaveManager.get_setting("check_updates") != false
	upd_btn.button_pressed = upd_on
	upd_btn.text = "Check for updates at start: ON" if upd_on else "Check for updates at start: OFF"
	upd_btn.toggled.connect(func(on: bool):
		SaveManager.set_setting("check_updates", on)
		upd_btn.text = "Check for updates at start: ON" if on else "Check for updates at start: OFF")
	box.add_child(upd_btn)

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

	var unlock := UiTheme.make_button("Unlock all continents & factions (testing)", 52)
	unlock.pressed.connect(func():
		SaveManager.unlock_all()
		unlock.text = "All content unlocked")
	box.add_child(unlock)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var back := UiTheme.make_button("Back", 60)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	box.add_child(back)
