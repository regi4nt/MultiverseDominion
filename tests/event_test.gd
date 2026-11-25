extends Node
## Events: daily missions (draw, tracking, claim, reset), achievements, hooks, screen, menu button order.
## Run: godot --headless --path . res://tests/event_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	var saved: Dictionary = SaveManager.data.duplicate(true)
	ChestSystem.time_offset = 0
	SaveManager.data["events"] = {}
	SaveManager.data["wallet"] = {"coins": 0, "fragments": 0, "tickets": 0, "crystals": 0, "chips": 0}

	var ms := EventHub.daily_missions()
	check(ms.size() == 4, "4 daily missions")
	var ids := {}
	for m in ms:
		ids[m["id"]] = true
	check(ids.size() == 4, "no duplicate missions in a day")
	check(str(EventHub.daily_missions().map(func(m): return m["id"])) == str(ms.map(func(m): return m["id"])), "same missions all day")
	var ok_pool := true
	for m in EventHub.MISSION_POOL:
		if not (m["reward"] is Dictionary) or int(m["target"]) < 1:
			ok_pool = false
	check(ok_pool, "pool entries valid")

	# tracking + claim
	var m0: Dictionary = ms[0]
	check(not EventHub.can_claim(m0, true), "not claimable at 0 progress")
	EventHub.track(String(m0["metric"]), int(m0["target"]))
	check(EventHub.is_done(m0, true) and EventHub.can_claim(m0, true), "claimable once the target is reached")
	check(EventHub.claimable_count() >= 1, "badge counts it")
	var r := EventHub.claim(String(m0["id"]), true)
	check(r["ok"] and not EventHub.can_claim(m0, true), "claim pays once")
	var paid := 0
	for k in m0["reward"]:
		if k == "coins":
			paid = int(m0["reward"][k])
	check(SaveManager.coins() == paid, "coins paid")
	check(EventHub.claim(String(m0["id"]), true)["ok"] == false, "no double claim")

	# next day: reset
	ChestSystem.time_offset = 86400
	check(EventHub.metric_value(String(m0["metric"]), true) == 0 and not EventHub.is_claimed(String(m0["id"]), true), "daily progress and claims reset the next day")
	check(EventHub.seconds_to_reset() > 0 and EventHub.seconds_to_reset() <= 86400, "reset countdown")
	ChestSystem.time_offset = 0

	# hooks
	SaveManager.data["events"] = {}
	var w0 := int(SaveManager.data["stats"]["wins"])
	SaveManager.record_match(true, 5, 100, "aetherion", false)
	check(EventHub.metric_value("arena_wins", true) == 1 and EventHub.metric_value("wins", true) == 1 and EventHub.metric_value("matches", true) == 1, "Arena win is tracked")
	SaveManager.record_match(true, 5, 100, "aetherion", true)
	check(EventHub.metric_value("arena_wins", true) == 1 and EventHub.metric_value("wins", true) == 2, "Journey win is not an Arena win")
	SaveManager.record_practice(true, "normal")
	check(EventHub.metric_value("chess_wins", true) == 1 and EventHub.metric_value("chess_played", true) == 1, "Battle Chess is tracked")
	ChestSystem.slots()[0] = {"grade": "gold", "start": 1, "ready": 1}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	ChestSystem.open(0, rng)
	check(EventHub.metric_value("chests", true) == 1 and EventHub.metric_value("gold_chests", false) >= 1, "opening a chest is tracked")
	SaveManager.data["wallet"]["tickets"] = 50
	SaveManager.data["shop"] = {"pity": 0, "pity_rare": 0, "pity_legendary": 0, "pulls": 0}
	var col0: Dictionary = SaveManager.data["collection"].duplicate(true)
	ShopSystem.pull_batch(3, rng)
	check(EventHub.metric_value("pulls", true) == 3, "gacha pulls are tracked")
	SaveManager.data["collection"] = col0

	# achievements
	var a := EventHub.find("a_win1", false)
	check(EventHub.is_done(a, false), "First Blood done after a win (stats based)")
	var cb := SaveManager.coins()
	check(EventHub.claim("a_win1", false)["ok"] and SaveManager.coins() == cb + 100 and EventHub.is_claimed("a_win1", false), "achievement claim pays and sticks")
	check(EventHub.claim("a_win1", false)["ok"] == false, "achievement claimed once")
	SaveManager.data["wallet"]["coins"] = 6000
	check(EventHub.is_done(EventHub.find("a_rich", false), false), "coin threshold achievement reads the wallet")
	check(EventHub.progress(EventHub.find("a_win50", false), false) < 50, "progress is capped at the target")
	var seen := {}
	var dup := false
	for x in EventHub.ACHIEVEMENTS:
		if seen.has(x["id"]):
			dup = true
		seen[x["id"]] = true
	check(not dup, "unique achievement ids")

	# JSON round trip
	var back: Dictionary = JSON.parse_string(JSON.stringify(SaveManager.data))
	SaveManager.data["events"] = back["events"]
	check(EventHub.is_claimed("a_win1", false), "events survive save and load")

	# screen
	var screen: Control = load("res://scenes/events/events.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	check(screen._tab_buttons.keys() == ["mission", "achievement", "chest"], "three tabs: Mission, Achievement, Chests")
	check(screen._lists["mission"].get_child_count() == 4, "Mission tab lists 4 missions")
	screen._show_tab("achievement")
	await get_tree().process_frame
	check(screen._lists["achievement"].get_child_count() == EventHub.ACHIEVEMENTS.size() and screen._lists["achievement"].get_parent().visible and not screen._lists["mission"].get_parent().visible, "Achievement tab lists all achievements")
	var before := SaveManager.coins()
	screen._on_claim("a_rich", false)
	check(EventHub.is_claimed("a_rich", false) and SaveManager.currency("crystals") >= 2, "claiming from the screen works")
	screen.queue_free()
	await get_tree().process_frame

	# menu: Events sits right above Settings
	var menu: Control = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var names: Array[String] = []
	for b in menu.find_children("*", "Button", true, false):
		names.append((b as Button).text)
	var ei := -1
	for i in range(names.size()):
		if names[i].begins_with("Events"):
			ei = i
	check(ei >= 0 and names[ei + 1] == "Settings", "Events button sits directly above Settings (%s)" % str(names))
	menu.queue_free()

	ChestSystem.time_offset = 0
	SaveManager.data = saved
	SaveManager.save_game()
	print("EVENT TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
