extends Node
## Reward chests: drop odds, slots, timer (one unlocking at a time), crystal skip, rewards, save/load, Chests screen.
## Run: godot --headless --path . res://tests/chest_test.tscn

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
	SaveManager.data["chests"] = {"slots": [null, null, null, null], "opened": 0}
	SaveManager.data["wallet"] = {"coins": 0, "fragments": 0, "tickets": 0, "crystals": 0, "chips": 0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 11

	# --- grades and odds
	check(ChestSystem.GRADES.size() == 3, "three chest grades")
	for d in ChestSystem.DROP_WEIGHTS:
		var counts := {"bronze": 0, "silver": 0, "gold": 0}
		for i in range(6000):
			counts[ChestSystem.roll_grade(d, rng)] += 1
		check(counts["bronze"] > 0 and counts["silver"] > 0 and counts["gold"] > 0, "%s drops every grade" % d)
		if d == "hard":
			check(counts["gold"] > 0 and float(counts["gold"]) / 6000.0 > 0.15, "hard drops many gold chests")
		if d == "easy":
			check(counts["bronze"] > counts["silver"] and counts["silver"] > counts["gold"], "easy: bronze > silver > gold")
	var t := {"bronze": ChestSystem.grade_seconds("bronze"), "silver": ChestSystem.grade_seconds("silver"), "gold": ChestSystem.grade_seconds("gold")}
	check(t["bronze"] < t["silver"] and t["silver"] < t["gold"], "better chests take longer")

	# --- grades pay differently
	var avg := {}
	for g in ChestSystem.GRADES:
		var sum := 0
		var kinds := {}
		for i in range(300):
			var r := ChestSystem.roll_rewards(g, rng)
			sum += int(r.get("coins", 0))
			for k in r:
				kinds[k] = true
		avg[g] = sum / 300
		check(kinds.has("coins") and kinds.has("fragments") and kinds.has("chips") and kinds.has("xp"), "%s can hold coins, fragments, chips and xp" % g)
	check(avg["bronze"] < avg["silver"] and avg["silver"] < avg["gold"], "average coins grow with the grade (%s)" % str(avg))
	var gold_kinds := {}
	var bronze_crystal := false
	for i in range(400):
		for k in ChestSystem.roll_rewards("gold", rng):
			gold_kinds[k] = true
		if ChestSystem.roll_rewards("bronze", rng).has("crystals"):
			bronze_crystal = true
	check(gold_kinds.has("crystals") and gold_kinds.has("tickets"), "gold can hold crystals and tickets")
	check(not bronze_crystal, "bronze never holds crystals")

	# --- slots
	check(ChestSystem.free_slots() == 4 and ChestSystem.ready_count() == 0, "starts with 4 empty slots")
	var a := ChestSystem.award_grade("silver")
	check(a["status"] == "added" and a["slot"] == 0 and ChestSystem.state(0) == "locked", "a chest lands in the first slot, waiting")
	ChestSystem.award_grade("bronze")
	ChestSystem.award_grade("gold")
	ChestSystem.award_grade("bronze")
	var stored := ChestSystem.award_grade("gold")
	check(stored["status"] == "stored" and stored["storage"] == 0 and ChestSystem.storage_count() == 1 and SaveManager.coins() == 0, "all slots full: the chest goes to the Storage")
	check(ChestSystem.move_to_slot(0) != "" and ChestSystem.storage_count() == 1, "no free slot: moving out of the Storage is refused")
	for i in range(ChestSystem.STORAGE_CAPACITY - 1):
		ChestSystem.award_grade("bronze")
	check(ChestSystem.storage_count() == ChestSystem.STORAGE_CAPACITY, "the Storage fills up to its capacity")
	var full := ChestSystem.award_grade("gold")
	check(full["status"] == "full" and SaveManager.coins() == int(full["coins"]) and int(full["coins"]) > 0, "slots and Storage full: the chest becomes coins")
	SaveManager.data["wallet"]["coins"] = 0
	var freed := ChestSystem.slots()[3]
	ChestSystem.slots()[3] = null
	check(ChestSystem.move_to_slot(0) == "" and ChestSystem.grade_at(3) == "gold" and ChestSystem.state(3) == "locked" and ChestSystem.storage_count() == ChestSystem.STORAGE_CAPACITY - 1, "a stored chest moves into a free slot, waiting")
	check(ChestSystem.move_to_slot(99) != "", "bad Storage index is refused")
	ChestSystem.slots()[3] = freed
	ChestSystem.storage().clear()

	# --- drop limit: DROP_LIMIT chests, then 1 hour of waiting, then the allowance refreshes
	var rng_l := RandomNumberGenerator.new()
	rng_l.seed = 7
	SaveManager.data["chests"] = {"slots": [null, null, null, null], "opened": 0}
	ChestSystem.time_offset = 0
	for i in range(ChestSystem.DROP_LIMIT):
		check(ChestSystem.award("normal", rng_l)["status"] != "limit", "drop %d of the allowance is given" % (i + 1))
	check(ChestSystem.drops_used() == ChestSystem.DROP_LIMIT and ChestSystem.limit_seconds_left() > 3500, "limit reached: about an hour to wait")
	var blocked := ChestSystem.award("normal", rng_l)
	check(blocked["status"] == "limit" and int(blocked["wait"]) > 0, "over the limit: no chest drops")
	ChestSystem.time_offset = ChestSystem.DROP_REFRESH_SECONDS - 60
	check(ChestSystem.award("normal", rng_l)["status"] == "limit", "still limited just before the hour is over")
	ChestSystem.time_offset = ChestSystem.DROP_REFRESH_SECONDS + 5
	check(ChestSystem.limit_seconds_left() == 0 and ChestSystem.award("normal", rng_l)["status"] != "limit" and ChestSystem.drops_used() == 1, "after the hour the allowance is refreshed")
	ChestSystem.time_offset = 0
	SaveManager.data["chests"] = {"slots": [null, null, null, null], "opened": 0, "storage": []}
	SaveManager.data["wallet"]["coins"] = 0

	# --- timer
	check(ChestSystem.open(0)["ok"] == false, "a waiting chest cannot be opened")
	check(ChestSystem.start_unlock(0) == "" and ChestSystem.state(0) == "unlocking", "start unlocking slot 0")
	check(ChestSystem.start_unlock(1) != "" and ChestSystem.state(1) == "locked", "only one chest unlocks at a time")
	check(ChestSystem.remaining(0) > 3500 and ChestSystem.remaining(0) <= 3600, "silver timer is about 1 hour")
	ChestSystem.time_offset = 1800
	check(ChestSystem.state(0) == "unlocking" and ChestSystem.remaining(0) <= 1800, "timer counts down with the clock")
	check(ChestSystem.skip_cost(0) == 1, "half an hour left costs 1 crystal")
	check(ChestSystem.skip(0) != "" and ChestSystem.state(0) == "unlocking", "skip fails without crystals")
	SaveManager.data["wallet"]["crystals"] = 5
	check(ChestSystem.skip(0) == "" and ChestSystem.state(0) == "ready" and SaveManager.crystals() == 4, "skip pays crystals and finishes the timer")
	ChestSystem.time_offset = 3600
	check(ChestSystem.start_unlock(1) == "" , "after the first chest is ready the next one can start")
	ChestSystem.time_offset = 3600 + ChestSystem.grade_seconds("bronze")
	check(ChestSystem.state(1) == "ready" and ChestSystem.ready_count() == 2, "a timer finishes by itself")

	# --- persistence of the timer (JSON round trip)
	var json := JSON.stringify(SaveManager.data)
	var back: Dictionary = JSON.parse_string(json)
	SaveManager.data["chests"] = back["chests"]
	check(ChestSystem.state(0) == "ready" and ChestSystem.state(1) == "ready" and ChestSystem.state(2) == "locked", "chests survive save and load")

	# --- opening
	var coins0 := SaveManager.coins()
	var frag0 := SaveManager.fragments()
	var xp0 := SaveManager.profile_xp()
	var res := ChestSystem.open(0, rng)
	check(res["ok"] and res["grade"] == "silver" and ChestSystem.state(0) == "empty", "open pays out and empties the slot")
	check(SaveManager.coins() == coins0 + int(res["rewards"]["coins"]) and SaveManager.coins() >= 150, "silver coins paid into the wallet")
	check(SaveManager.fragments() == frag0 + int(res["rewards"].get("fragments", 0)), "fragments paid")
	check(SaveManager.profile_xp() == xp0 + int(res["rewards"].get("xp", 0)) and int(res["rewards"].get("xp", 0)) >= 60, "xp paid")
	check(ChestSystem.opened_total() == 1, "opened counter")
	check(ChestSystem.open(0)["ok"] == false, "an empty slot cannot be opened twice")

	# --- no chest unlocks a card anymore
	var got_card := false
	for i in range(80):
		ChestSystem.slots()[3] = {"grade": "gold", "start": 1, "ready": 1}
		if String(ChestSystem.open(3, rng)["card"]) != "":
			got_card = true
			break
	check(not got_card, "a gold chest no longer unlocks a Support card")

	# --- Chests screen
	ChestSystem.time_offset = 0
	SaveManager.data["chests"] = {"slots": [null, null, null, null], "opened": 0, "storage": ["silver", "bronze"]}
	ChestSystem.award_grade("gold")
	ChestSystem.award_grade("bronze")
	ChestSystem.slots()[1] = {"grade": "bronze", "start": 1, "ready": 1}
	SaveManager.data["wallet"]["crystals"] = 10
	var events_screen: Control = load("res://scenes/events/events.tscn").instantiate()
	add_child(events_screen)
	events_screen._show_tab("chest")
	await get_tree().process_frame
	check(events_screen._chest_panel.visible, "Events has a visible Chests tab")
	var screen: ChestsPanel = events_screen._chest_panel
	check(screen._cards.size() == 4, "screen shows 4 slots")
	check((screen._cards[0].unlock_btn as Button).visible and not (screen._cards[0].open_btn as Button).visible, "waiting chest shows Unlock")
	check((screen._cards[1].open_btn as Button).visible, "ready chest shows OPEN")
	check(not (screen._cards[2].unlock_btn as Button).visible and not (screen._cards[2].open_btn as Button).visible, "empty slot has no buttons")
	screen._on_unlock(0)
	check(ChestSystem.state(0) == "unlocking" and (screen._cards[0].skip_btn as Button).visible, "Unlock starts the timer on screen")
	check(screen._storage_list.get_child_count() == 2, "Storage beside the slots lists its 2 chests")
	screen._on_open(1)
	await get_tree().process_frame
	check(ChestSystem.state(1) == "empty" and ChestSystem.opened_total() >= 1, "OPEN on screen empties the slot")
	screen._on_move(0)
	await get_tree().process_frame
	check(ChestSystem.grade_at(1) == "silver" and screen._storage_list.get_child_count() == 1, "To slot moves a stored chest into the free slot")
	events_screen.queue_free()
	await get_tree().process_frame

	# --- Arena victory drops a chest, a Journey win / an Arena defeat does not
	var saved_slots: Array = ChestSystem.slots().duplicate(true)
	for scenario in [["arena_win", "arena", 0, 1], ["arena_loss", "arena", 1, 0], ["journey_win", "journey", 0, 0]]:
		SaveManager.data["chests"] = {"slots": [null, null, null, null], "opened": 0}
		GameSession.category = scenario[1]
		GameSession.mode = "custom_ai"
		GameSession.ai_count = 1
		GameSession.difficulty = "normal"
		GameSession.resume_match = false
		SaveManager.clear_match()
		var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
		add_child(board)
		await get_tree().process_frame
		board.ctrl.winner_id = int(scenario[2])
		board._on_game_over(int(scenario[2]))
		await get_tree().process_frame
		check(4 - ChestSystem.free_slots() == int(scenario[3]), "%s: %d chest(s) dropped" % [scenario[0], scenario[3]])
		if int(scenario[3]) == 1:
			var has_label := false
			for l in board.find_children("*", "Label", true, false):
				if (l as Label).text.begins_with("Chest earned"):
					has_label = true
			check(has_label, "result screen announces the chest")
		board.queue_free()
		await get_tree().process_frame
	SaveManager.clear_match()
	SaveManager.data["chests"] = {"slots": saved_slots, "opened": 0}

	# --- main menu badge
	ChestSystem.slots()[2] = {"grade": "silver", "start": 1, "ready": 1}
	var menu: Control = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var found := false
	for b in menu.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Chests") and (b as Button).text.contains("ready"):
			found = true
	check(found, "main menu has a Chests button that shows ready chests")
	menu.queue_free()

	ChestSystem.time_offset = 0
	SaveManager.data = saved
	SaveManager.save_game()
	print("CHEST TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)
