extends Node
## Instantiates the merged Card Hub screen, clicks through its tabs, checks results.

func _ready() -> void:
	var fails := 0
	var coll: Control = load("res://scenes/card_collection/card_collection.tscn").instantiate()
	add_child(coll)
	await get_tree().process_frame
	# The Card Hub opens on the Lineup tab (first tab), not on the Collection.
	if not coll._lineup_view.visible or coll._collection_view.visible or coll._deck_view.visible or not coll._tab_buttons["lineup"].button_pressed:
		fails += 1
		push_error("the Card Hub should open on the Lineup tab")
	coll._show_tab("collection")
	await get_tree().process_frame
	for f in ["pawn", "queen", "king", "support", "all"]:
		coll._filter = f
		coll._rebuild()
		await get_tree().process_frame
	coll._on_card(String(CardDatabase.units_of_chess("queen")[0]["id"]))
	print("collection cards shown (all): ", coll._grid.get_child_count(), " detail: ", coll._detail.text.substr(0, 40).replace("\n", " "))
	# The collection lists the units and Kings of EVERY continent (locked until the faction opens); the 8 Pawns once PER continent
	# (each continent has its own Pawn faction names and lock state).
	var unit_total := 0
	var king_total := 0
	for c in GameData.continents:
		for u in CardDatabase.units_of_continent(String(c["id"])):
			unit_total += 1
		king_total += c.get("factions", []).size()
	if coll._grid.get_child_count() != unit_total + king_total + CardDatabase.all_supports().size():
		fails += 1
		push_error("collection should show every continent's cards: %d" % coll._grid.get_child_count())
	coll._filter = "king"
	coll._rebuild()
	coll._on_card(String(CardDatabase.all_kings()[0]["id"]))
	if coll._grid.get_child_count() != king_total or not coll._detail.text.contains("King"):
		fails += 1
	if not coll._collection_view.visible or coll._deck_view.visible:
		fails += 1
	coll._show_tab("info")
	await get_tree().process_frame
	if coll._collection_view.visible or coll._deck_view.visible or not coll._info_view.visible or not coll._tab_buttons["info"].button_pressed:
		fails += 1
		push_error("the Info tab should be the only visible view")
	for sec in coll.INFO_SECTIONS:
		coll._show_info(String(sec[0]))
		if coll._info_text.text.length() < 100 or not coll._info_buttons[sec[0]].button_pressed:
			fails += 1
			push_error("Info section '%s' is empty" % sec[0])
	coll._show_info("roles")
	if not coll._info_text.text.contains("Controller") or not coll._info_text.text.contains("stuns"):
		fails += 1
		push_error("the Roles section should describe the Controller's crowd-control skill")
	coll._show_info("territory")
	for word in ["Tax", "Duel", "Conquest", "Regional Dominion", "Sanctuary", "How to win"]:
		if not coll._info_text.text.contains(word):
			fails += 1
			push_error("the Territory section should explain '%s'" % word)
	if not coll._info_text.text.contains("Easy %d G" % GameData.gold_for("easy")) or coll._info_text.text.contains("%s"):
		fails += 1
		push_error("the Territory section should show live numbers from balance.json")
	coll._show_info("synergy")
	if not coll._info_text.text.contains("reflect 20% damage") or not coll._info_text.text.contains("Dawn Ward"):
		fails += 1
		push_error("the Synergy section should list the faction and role tiers")
	if GameSession.CARD_HUB_NAME == "Collection & Deck":
		fails += 1
		push_error("the screen should have been renamed")
	coll._show_tab("deck")
	await get_tree().process_frame
	if coll._collection_view.visible or not coll._deck_view.visible or coll._info_view.visible:
		fails += 1
	var db: Control = coll  # the deck editor is the second tab of the same screen
	if db.deck.unit_ids.size() != 15 or db.deck.support_ids.size() != 15 or not db._pool_tabs["units"].text.contains("15 / 15") or not db._pool_tabs["supports"].text.contains("15 / 15"):
		fails += 1
		push_error("the editor tabs show 15 / 15 units and 15 / 15 supports, filled with the default deck")
	if db._save_btn.disabled:
		fails += 1
	# --- unit slots: free one -> invalid, refill with a piece of ANOTHER faction of the same continent -> valid, mixed factions
	var first_faction := String(CardDatabase.get_unit(db.deck.unit_ids[db.deck.unit_ids.size() - 1])["faction"])
	db._toggle_unit(db.deck.unit_ids[db.deck.unit_ids.size() - 1])
	await get_tree().process_frame
	if not db._save_btn.disabled or db.deck.unit_ids.size() != 14 or not db._pool_tabs["units"].text.contains("14 / 15"):
		fails += 1
		push_error("14 unit cards must disable Save and show 14 / 15 on the Units tab")
	var other_id := ""
	for u in CardDatabase.all_units():
		if String(u["chess"]) != "pawn" and String(u["faction"]) != first_faction and SaveManager.owned_count(String(u["id"])) >= 1:  # only owned cards can join the deck
			other_id = String(u["id"])
			break
	if other_id == "":  # a fresh profile owns no piece of another faction: grant one so the mixed-faction rule is what gets tested
		for u in CardDatabase.all_units():
			if String(u["chess"]) != "pawn" and String(u["faction"]) != first_faction:
				other_id = String(u["id"])
				SaveManager.data["collection"][other_id] = 1
				break
	db._toggle_unit(other_id)
	await get_tree().process_frame
	var factions := {}
	for uid in db.deck.unit_ids:
		factions[CardDatabase.get_unit(uid)["faction"]] = true
	print("units: ", db.deck.unit_ids.size(), " factions in the deck: ", factions.size(), " save disabled=", db._save_btn.disabled)
	if db.deck.unit_ids.size() != 15 or factions.size() < 3 or db._save_btn.disabled:
		fails += 1
		push_error("a deck mixing factions of one continent must be valid")
	db._toggle_unit(String(CardDatabase.all_units()[0]["id"]) if not db.deck.unit_ids.has(String(CardDatabase.all_units()[0]["id"])) else other_id)
	if db.deck.unit_ids.size() > 15:
		fails += 1
		push_error("never more than 15 unit cards")
	# --- supports
	db._toggle_support(db.deck.support_ids[0])
	await get_tree().process_frame
	print("after removing one support: size=", db.deck.support_ids.size(), " save disabled=", db._save_btn.disabled)
	if not db._save_btn.disabled or not db._pool_tabs["supports"].text.contains("14 / 15"):
		fails += 1
	db._toggle_support("sup_summon_recruits")
	SaveManager.data["collection"]["sup_spawn_familiar"] = 1  # unlock a card only to test the 15 cap
	db._toggle_support("sup_spawn_familiar")
	await get_tree().process_frame
	SaveManager.data["collection"].erase("sup_spawn_familiar")
	print("cap respected: size=", db.deck.support_ids.size())
	if db.deck.support_ids.size() != 15:
		fails += 1
	# --- King: any King of any continent
	SaveManager.unlock_continent("arcanum")  # the King / faction of a locked continent cannot be picked
	db._set_pool_tab("king")
	db._set_king("champion_astralis")
	await get_tree().process_frame
	if db.deck.champion_id != "champion_astralis" or db._pool_buttons.size() != 28:
		fails += 1
		push_error("the King tab lists the 28 Kings and any of them can be chosen")
	# --- another continent: its own unit cards, the King and Supports stay
	db._set_pool_tab("units")
	if SaveManager.is_continent_unlocked("arcanum"):
		db._on_deck_continent("arcanum")
		await get_tree().process_frame
		var all_arc := CardDatabase.continent_unit_ids("arcanum")
		if not db.deck.unit_ids.all(func(id): return all_arc.has(id)) or db.deck.champion_id != "champion_astralis" or db.deck.support_ids.size() != 15:
			fails += 1
			push_error("switching continent loads that continent's units and keeps King + Supports")
	print("UI CARDS SMOKE: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(fails)
