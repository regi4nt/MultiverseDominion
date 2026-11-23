extends Node
## Profile XP / level / title (XpSystem + SaveManager) and the home profile card.
## Run: godot --headless --path . res://tests/xp_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	check(XpSystem.progress(0)["level"] == 1 and XpSystem.progress(0)["into"] == 0, "0 XP = level 1")
	var need1 := XpSystem.need_for(1)
	check(XpSystem.progress(need1 - 1)["level"] == 1, "just below the threshold stays level 1")
	check(XpSystem.progress(need1)["level"] == 2 and XpSystem.progress(need1)["into"] == 0, "the threshold gives level 2")
	check(XpSystem.progress(need1 + 10)["into"] == 10, "XP inside a level is the remainder")
	check(XpSystem.progress(99999999)["level"] == XpSystem.MAX_LEVEL and bool(XpSystem.progress(99999999)["max"]), "level is capped")
	check(XpSystem.title(1) == "Recruit" and XpSystem.title(4) == "Recruit" and XpSystem.title(5) == "Squire", "titles change at their level")
	check(XpSystem.title(XpSystem.MAX_LEVEL) == "Dominion Lord", "top title at the max level")
	check(XpSystem.match_xp(true, 10, "normal") > XpSystem.match_xp(false, 10, "normal"), "a match win gives more XP than a loss")
	check(XpSystem.match_xp(true, 10, "hard") > XpSystem.match_xp(true, 10, "easy"), "harder difficulty gives more XP")
	check(XpSystem.practice_xp(true, "normal") > XpSystem.practice_xp(false, "normal"), "a Battle Chess win gives more XP than a loss")

	# SaveManager: awarding, level-up flag, persistence in the data dictionary
	var backup: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data["profile"]["xp"] = 0
	SaveManager.data["profile"]["level"] = 1
	SaveManager._award_xp(XpSystem.need_for(1) + 5)
	check(SaveManager.profile_level() == 2 and SaveManager.last_level_up == 2, "an award that crosses a threshold levels up")
	check("LEVEL UP" in SaveManager.xp_line(), "the result line announces the level up")
	SaveManager._award_xp(5)
	check(SaveManager.last_level_up == 0 and "LEVEL UP" not in SaveManager.xp_line(), "no level-up flag without a level-up")
	check(int(SaveManager.data["profile"]["level"]) == SaveManager.profile_level(), "profile.level follows the XP")

	# migration: an old save (no xp_v) starts from its record
	SaveManager.data["profile"].erase("xp_v")
	SaveManager.data["profile"]["xp"] = 0
	SaveManager.data["stats"] = {"matches_played": 5, "wins": 3, "losses": 2, "total_rounds": 50, "best_gold": 100}
	SaveManager.ensure_xp()
	check(SaveManager.profile_xp() == 3 * 100 + 2 * 30, "old save: XP is estimated from wins and losses")
	var again := SaveManager.profile_xp()
	SaveManager.ensure_xp()
	check(SaveManager.profile_xp() == again, "migration runs only once")

	# home card: shows name, title, level and EXP, and no Profile button on the menu
	SaveManager.data["profile"]["name"] = "Zed"
	var card := ProfileView.build_card(func(): pass)
	add_child(card)
	var texts := _texts(card)
	check("Zed" in texts and SaveManager.profile_title() in texts, "home card shows name and title")
	check("Lv %d" % SaveManager.profile_level() in texts, "home card shows the level")
	check(texts.any(func(t): return String(t).ends_with("EXP")), "home card shows the EXP progress")
	card.queue_free()
	var menu: Control = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	check(menu.find_child("ProfileCard", true, false) != null, "the Main Menu shows the profile card")
	var has_profile_btn := false
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text == "Profile":
			has_profile_btn = true
	check(not has_profile_btn, "the Main Menu has no Profile button")
	menu.queue_free()

	SaveManager.data = backup
	print("xp_test: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _texts(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		out.append_array(_texts(c))
	return out
