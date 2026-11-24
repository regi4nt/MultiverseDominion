extends Control
## Main Menu. Entries for later phases are visible but disabled and marked TODO.


var _quit_dialog: UiDialog


## Android Back button: ask before leaving the game.
func on_back_requested() -> void:
	_quit_dialog.popup_centered(Vector2i(460, 160))


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(40)
	add_child(margin)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 48)
	margin.add_child(hbox)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(left)
	left.add_child(UiTheme.make_label("MULTIVERSE", 72, UiTheme.COL_GOLD))
	left.add_child(UiTheme.make_label("DOMINION", 72))
	left.add_child(UiTheme.make_divider())
	var tag := UiTheme.make_label("Conquer the Land. Command the Army. Shape the Fate.", 24, UiTheme.COL_MUTED)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(tag)
	# Profile (name, title, level, EXP) sits in the top-left corner of the home screen; tap it for details.
	var card := ProfileView.build_card(_show_profile)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(card)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 10)
	hbox.add_child(right)

	var cont := UiTheme.make_button("CONTINUE MATCH", 68)
	var summary := SaveManager.match_summary()
	cont.disabled = summary == ""
	if summary != "":
		cont.text = "CONTINUE  (%s)" % summary
	cont.pressed.connect(func():
		GameSession.resume_match = true
		get_tree().change_scene_to_file("res://scenes/territory_board/territory_board.tscn"))
	right.add_child(cont)
	var play := UiTheme.make_button("NEW MATCH", 68)
	play.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/match_setup/match_setup.tscn"))
	right.add_child(play)
	var coll := UiTheme.make_button(GameSession.CARD_HUB_NAME)
	coll.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/card_collection/card_collection.tscn"))
	right.add_child(coll)
	var shop := UiTheme.make_button("Shop")
	shop.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/shop/shop.tscn"))
	right.add_child(shop)
	var events := UiTheme.make_button("Events")
	if EventHub.badge_count() > 0:
		events.text = "Events  (%d to claim!)" % EventHub.badge_count()
	events.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/events/events.tscn"))
	right.add_child(events)
	var settings := UiTheme.make_button("Settings")
	settings.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/settings/settings.tscn"))
	right.add_child(settings)
	var quit := UiTheme.make_button("Quit")
	quit.pressed.connect(func(): _quit_dialog.popup_centered(Vector2i(460, 160)))
	right.add_child(quit)
	_quit_dialog = UiDialog.new()
	_quit_dialog.title = "Quit game?"
	_quit_dialog.dialog_text = "Multiverse Dominion will close. A match in progress is saved at the start of each of your turns."
	_quit_dialog.ok_button_text = "Quit"
	_quit_dialog.cancel_button_text = "Stay"
	_quit_dialog.confirmed.connect(func(): get_tree().quit())
	add_child(_quit_dialog)
	left.add_child(UiTheme.make_label("v" + UpdateCheck.current_version(), 18, UiTheme.COL_MUTED))
	if SaveManager.get_setting("check_updates") != false and not GameSession.update_checked and OS.get_name() == "Android":
		var uc := UpdateCheck.new()
		add_child(uc)
		# Only a conclusive answer counts as "checked": after an offline start the next visit to the menu tries again.
		uc.check_finished.connect(func(status: String, info: Dictionary):
			if status == "error":
				return
			GameSession.update_checked = true
			if status == "available" and not UpdateCheck.is_skipped(String(info["version"])):
				UpdateCheck.show_dialog(self, info, true))
		uc.check()


func _show_profile() -> void:
	var dlg := UiDialog.new()
	dlg.body_node = ProfileView.build()
	dlg.show_cancel = false
	dlg.ok_button_text = "Close"
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(640, 0))
