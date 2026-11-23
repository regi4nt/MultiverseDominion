extends Node
## Instantiates the Shop screen, pulls, buys, checks the Main Menu entry sits above Profile.

func _ready() -> void:
	var fails := 0
	var saved: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data["collection"].clear()
	SaveManager.ensure_collection()
	SaveManager.data["wallet"]["coins"] = 5000

	var menu: Control = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var names: Array[String] = []
	for b in menu.find_children("*", "Button", true, false):
		names.append((b as Button).text)
	# The profile is a card (not a button) on the home screen: Shop must sit under Card Hub and above Settings.
	if not names.has("Shop") or names.find("Shop") < names.find("Card Hub") or names.find("Shop") > names.find("Settings"):
		fails += 1
		push_error("Shop must be a menu entry between Card Hub and Settings (%s)" % str(names))
	menu.queue_free()
	await get_tree().process_frame

	var shop: Control = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	var gs: Control = shop._views["gacha_support"]
	var gu: Control = shop._views["gacha_unit"]
	var bs: Control = shop._views["buy_support"]
	var bu: Control = shop._views["buy_unit"]
	var ex: Control = shop._views["exchange"]
	var tabs: Array = shop._tab_buttons.keys()
	if tabs != ["gacha_support", "gacha_unit", "buy_support", "buy_unit", "exchange", "gamble"] or (shop._tab_buttons["buy_support"] as Button).text != "Buy Support" \
			or (shop._tab_buttons["buy_unit"] as Button).text != "Buy Unit" or (shop._tab_buttons["exchange"] as Button).text != "Exchange" or (shop._tab_buttons["gamble"] as Button).text != "Gamble":
		fails += 1
		push_error("tab order: Support Gacha, Unit Gacha, Buy Support, Buy Unit, Exchange (%s)" % str(tabs))
	if not gs.visible or bs.visible or gs.pull10.disabled:
		fails += 1
	gs._on_pull(10)
	await get_tree().process_frame
	if gs.result_flow.get_child_count() != 10:
		fails += 1
		push_error("10 pulls should show 10 cards")
	# --- Buy Support
	shop._show_tab("buy_support")
	await get_tree().process_frame
	var n: int = bs.grid.get_child_count()
	if n == 0 or n != ShopSystem.locked_supports().size():
		fails += 1
		push_error("the Buy Support tab should list every locked card (%d)" % n)
	var id := String(ShopSystem.locked_supports()[0]["id"])
	bs._on_card(id)
	if bs.buy_btn.disabled:
		fails += 1
	var coins := SaveManager.coins()
	bs._on_pay("coins")
	await get_tree().process_frame
	if SaveManager.owned_count(id) != 1 or SaveManager.coins() >= coins:
		fails += 1
		push_error("buying should unlock the card and cost coins")
	# --- exchange with fragments
	var id2 := String(ShopSystem.locked_supports()[0]["id"])
	bs._on_card(id2)
	var price2 := ShopSystem.fragment_price(CardDatabase.get_support(id2))
	SaveManager.data["wallet"]["fragments"] = price2 - 1
	shop._refresh()
	if not bs.frag_btn.disabled:
		fails += 1
		push_error("Exchange must be disabled without enough fragments")
	SaveManager.add_fragments(1)
	shop._refresh()
	if bs.frag_btn.disabled:
		fails += 1
	bs._on_exchange()
	await get_tree().process_frame
	if SaveManager.owned_count(id2) != 1 or SaveManager.fragments() != 0:
		fails += 1
		push_error("exchanging should unlock the card and cost its fragments")
	# --- crystals buy a Support card
	var id3 := String(ShopSystem.locked_supports()[0]["id"])
	bs._on_card(id3)
	SaveManager.data["wallet"]["crystals"] = 0
	shop._refresh()
	if not bs.crystal_btn.disabled:
		fails += 1
		push_error("Buy with Crystals must be disabled without crystals")
	SaveManager.add_currency("crystals", 50)
	shop._refresh()
	bs._on_pay("crystals")
	if SaveManager.owned_count(id3) != 1 or SaveManager.crystals() >= 50:
		fails += 1
		push_error("crystals should buy a card")
	bs.filter = "Magic"
	bs.rebuild()
	if bs.grid.get_child_count() != ShopSystem.locked_supports("Magic").size():
		fails += 1
	# --- Unit Gacha
	shop._show_tab("gacha_unit")
	await get_tree().process_frame
	if not gu.visible or gs.visible or gu.pull10.disabled:
		fails += 1
		push_error("the Unit Gacha tab opens with usable pull buttons")
	var locked_before := ShopSystem.shop_units("", true).size()
	gu._on_pull(10)
	await get_tree().process_frame
	if gu.result_flow.get_child_count() != 10:
		fails += 1
		push_error("10 unit pulls should show 10 cards")
	if ShopSystem.shop_units("", true).size() >= locked_before:
		fails += 1
		push_error("unit pulls should unlock unit cards")
	# --- Buy Unit
	shop._show_tab("buy_unit")
	await get_tree().process_frame
	if bu.grid.get_child_count() != ShopSystem.shop_units("", true).size() or bu.grid.get_child_count() == 0:
		fails += 1
		push_error("the Buy Unit tab should list every locked unit card of the open continents (%d)" % bu.grid.get_child_count())
	var uid := String(ShopSystem.shop_units("", true)[0]["id"])
	bu._on_card(uid)
	SaveManager.data["wallet"]["coins"] = 5000
	shop._refresh()
	bu._on_pay("coins")
	await get_tree().process_frame
	if SaveManager.owned_count(uid) != int(GameData.b("unit_copies")):
		fails += 1
		push_error("buying a unit card should own all its copies")
	# --- Exchange tab
	shop._show_tab("exchange")
	await get_tree().process_frame
	SaveManager.data["wallet"]["coins"] = 1000
	SaveManager.data["wallet"]["tickets"] = 0
	shop._refresh()
	ex._on_convert("coins_ticket", 5)
	if SaveManager.tickets() != 5 or SaveManager.coins() != 500:
		fails += 1
		push_error("Exchange tab: 500 coins should become 5 tickets")
	SaveManager.data["wallet"]["coins"] = 0
	shop._refresh()
	if not (ex.rows["coins_ticket"]["buttons"][0] as Button).disabled:
		fails += 1
		push_error("Exchange buttons must be disabled without enough currency")
	# --- Gamble tab: chips only
	var gb: Control = shop._views["gamble"]
	shop._show_tab("gamble")
	await get_tree().process_frame
	SaveManager.data["wallet"]["chips"] = 0
	shop._refresh()
	if not gb.visible or not gb.play_btn.disabled:
		fails += 1
		push_error("Gamble: Play must be disabled without chips")
	SaveManager.data["wallet"]["chips"] = 1000
	SaveManager.data["wallet"]["coins"] = 777
	shop._refresh()
	for g in ["coin", "dice", "slots"]:
		gb._pick_game(g)
		gb.bet = 100
		gb._on_play()
		if gb.net_label.text == "" or SaveManager.coins() != 777:
			fails += 1
			push_error("Gamble %s should show a result and never touch coins" % g)
	SaveManager.data["wallet"]["coins"] = 0
	shop._show_tab("gacha_support")
	shop._refresh()
	if not gs.pull1.disabled or not gs.pull10.disabled:
		fails += 1
		push_error("pull buttons must be disabled without coins")
	SaveManager.data = saved
	SaveManager.save_game()
	print("UI SHOP SMOKE: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
