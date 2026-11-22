extends Node
## Instantiates the merged Collection & Deck screen, clicks through both tabs, checks results.

func _ready() -> void:
	var fails := 0
	var coll: Control = load("res://scenes/card_collection/card_collection.tscn").instantiate()
	add_child(coll)
	await get_tree().process_frame
	for f in ["pawn", "queen", "support", "all"]:
		coll._filter = f
		coll._rebuild()
		await get_tree().process_frame
	coll._on_card("queen_aurelia")
	print("collection cards shown (all): ", coll._grid.get_child_count(), " detail: ", coll._detail.text.substr(0, 40).replace("\n", " "))
	if coll._grid.get_child_count() != 36:
		fails += 1
	if not coll._collection_view.visible or coll._deck_view.visible:
		fails += 1
	coll._show_tab("deck")
	await get_tree().process_frame
	if coll._collection_view.visible or not coll._deck_view.visible:
		fails += 1
	var db: Control = coll  # the deck editor is the second tab of the same screen
	if db._save_btn.disabled:
		fails += 1
	db._support_buttons["sup_summon_recruits"].button_pressed = false
	await get_tree().process_frame
	print("after removing one support: size=", db.deck.support_ids.size(), " save disabled=", db._save_btn.disabled)
	if not db._save_btn.disabled:
		fails += 1
	db._support_buttons["sup_summon_recruits"].button_pressed = true
	db._support_buttons["sup_spawn_familiar"].disabled = false  # locked card, force-test the 15 cap
	db._support_buttons["sup_spawn_familiar"].button_pressed = true
	await get_tree().process_frame
	print("cap respected: size=", db.deck.support_ids.size())
	if db.deck.support_ids.size() != 15:
		fails += 1
	print("UI CARDS SMOKE: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(fails)
