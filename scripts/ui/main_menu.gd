extends Control
## Main Menu. Entries for later phases are visible but disabled and marked TODO.


var _quit_dialog: ConfirmationDialog


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
	var coll := UiTheme.make_button("Collection & Deck")
	coll.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/card_collection/card_collection.tscn"))
	right.add_child(coll)
	var profile := UiTheme.make_button("Profile")
	profile.pressed.connect(_show_profile)
	right.add_child(profile)
	var settings := UiTheme.make_button("Settings")
	settings.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/settings/settings.tscn"))
	right.add_child(settings)
	var quit := UiTheme.make_button("Quit")
	quit.pressed.connect(func(): _quit_dialog.popup_centered(Vector2i(460, 160)))
	right.add_child(quit)
	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.dialog_text = "Quit Multiverse Dominion?"
	_quit_dialog.ok_button_text = "Quit"
	_quit_dialog.cancel_button_text = "Stay"
	_quit_dialog.confirmed.connect(func(): get_tree().quit())
	add_child(_quit_dialog)
	left.add_child(UiTheme.make_label("v" + UpdateCheck.current_version(), 18, UiTheme.COL_MUTED))
	if SaveManager.get_setting("check_updates") != false and not GameSession.update_checked and OS.get_name() == "Android":
		GameSession.update_checked = true
		var uc := UpdateCheck.new()
		add_child(uc)
		uc.update_available.connect(_on_update_available)
		uc.check()


func _on_update_available(version: String, apk_url: String, notes: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Update available"
	dlg.dialog_text = "Version %s is available (you have %s).\nDownload it now? Open the downloaded file to install.\n\n%s" % [
		version, UpdateCheck.current_version(), notes.left(300)]
	dlg.ok_button_text = "Download"
	dlg.cancel_button_text = "Later"
	dlg.confirmed.connect(func(): OS.shell_open(apk_url))
	add_child(dlg)
	dlg.popup_centered(Vector2i(560, 320))


func _show_profile() -> void:
	var s: Dictionary = SaveManager.data["stats"]
	var dlg := AcceptDialog.new()
	dlg.title = "Profile"
	dlg.dialog_text = "%s\nMatches: %d   Wins: %d   Losses: %d\nRounds played: %d\nBest gold: %d" % [
		SaveManager.data["profile"]["name"], s["matches_played"], s["wins"], s["losses"], s["total_rounds"], s["best_gold"]]
	add_child(dlg)
	dlg.popup_centered(Vector2i(520, 240))
