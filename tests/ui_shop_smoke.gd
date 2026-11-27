extends Node
## Instantiates the Shop screen, pulls, buys, checks the Main Menu entry sits above Profile.

func _ready() -> void:
	var fails := 0
	var saved: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data["collection"].clear()
	SaveManager.ensure_collection()
	SaveManager.data["wallet"]["coins"] = 5000
	SaveManager.data["wallet"]["tickets"] = 500

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
	var gs: Control = shop._views["gacha"]
	var bs: Control = shop._views["buy_card"]  # one Buy Card tab: Support + unit cards
	var ex: Control = shop._views["exchange"]
	var tabs: Array = shop._tab_buttons.keys()
	if tabs != ["gacha", "buy_card", "auction", "gamble", "trading", "exchange"] or (shop._tab_buttons["gacha"] as Button).text != "Card Gacha" or (shop._tab_buttons["buy_card"] as Button).text != "Buy Card" \
			or (shop._tab_buttons["exchange"] as Button).text != "Exchange" or (shop._tab_buttons["auction"] as Button).text != "Auction" or (shop._tab_buttons["gamble"] as Button).text != "Gamble" or (shop._tab_buttons["trading"] as Button).text != "Trading":
		fails += 1
		push_error("tab order: Card Gacha, Buy Card, Auction, Gamble, Trading, Exchange (%s)" % str(tabs))
	if not gs.visible or bs.visible or gs.pull10.disabled:
		fails += 1
	gs._on_pull(10)
	await get_tree().process_frame
	if gs.result_flow.get_child_count() != 10:
		fails += 1
		push_error("10 pulls should show 10 cards")
	# --- Buy Card: "All" lists unit + Support cards together
	shop._show_tab("buy_card")
	await get_tree().process_frame
	var n_all: int = bs.grid.get_child_count()
	if bs.kind != "all" or n_all == 0 or n_all != ShopSystem.locked_supports().size() + ShopSystem.shop_units("", true).size() + ShopSystem.shop_kings(true).size():
		fails += 1
		push_error("the Buy Card tab (All) should list every locked Support and unit card plus the Kings below B3 (%d)" % n_all)
	# --- Buy Card: Support filter
	bs.kind = "support"
	bs.rebuild()
	var n: int = bs.grid.get_child_count()
	if n == 0 or n != ShopSystem.locked_supports().size():
		fails += 1
		push_error("the Buy Card tab (Support) should list every locked Support card (%d)" % n)
	var id := String(ShopSystem.locked_supports()[0]["id"])
	bs._on_card(id)
	SaveManager.data["wallet"]["crystals"] = 50
	shop._refresh()
	bs.refresh_buttons()
	if bs.crystal_btn.disabled:
		fails += 1
	var crystals := SaveManager.crystals()
	var coins := SaveManager.coins()
	bs._on_buy()
	await get_tree().process_frame
	if SaveManager.owned_count(id) != 1 or SaveManager.crystals() >= crystals or SaveManager.coins() != coins:
		fails += 1
		push_error("buying should unlock the card and cost crystals, never coins")
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
	bs._on_buy()
	if SaveManager.owned_count(id3) != 1 or SaveManager.crystals() >= 50:
		fails += 1
		push_error("crystals should buy a card")
	bs.kind = "support"
	bs.filter = "Magic"
	bs.rebuild()
	if bs.grid.get_child_count() != ShopSystem.locked_supports("Magic").size():
		fails += 1
	# --- Card Gacha: one pool
	shop._show_tab("gacha")
	SaveManager.data["wallet"]["tickets"] = 100
	shop._refresh()
	if not gs.visible or gs.pull10.disabled:
		fails += 1
		push_error("the Card Gacha tab opens with usable pull buttons")
	if gs.pity_bar == null or gs.pity_label.text == "" or not ShopSystem.PITY_LIMITS.values().has(int(gs.pity_bar.max_value)) or gs._chips.get_child_count() != ShopSystem.RATES.size():
		fails += 1
		push_error("the Card Gacha shows the rates and pity")
	gs._on_pull(10)
	await get_tree().process_frame
	if gs.result_flow.get_child_count() != 10:
		fails += 1
		push_error("10 mixed pulls should show 10 cards")
	# --- Buy Card: Unit filter
	shop._show_tab("buy_card")
	await get_tree().process_frame
	bs.kind = "unit"
	bs.filter = "all"
	bs.rebuild()
	if bs.grid.get_child_count() != ShopSystem.shop_units("", true).size() or bs.grid.get_child_count() == 0:
		fails += 1
		push_error("the Buy Card tab (Unit) should list every locked unit card of the open continents (%d)" % bs.grid.get_child_count())
	var uid := String(ShopSystem.shop_units("", true)[0]["id"])
	bs._on_card(uid)
	SaveManager.data["wallet"]["crystals"] = 50
	shop._refresh()
	bs._on_buy()
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
	if not (ex.rows["coins_ticket"]["convert"] as Button).disabled or (ex.rows["coins_ticket"]["slider"] as HSlider).editable:
		fails += 1
		push_error("Exchange row must be disabled without enough currency")
	# slider with - / + beside it picks the packs
	SaveManager.data["wallet"]["coins"] = 1000
	SaveManager.data["wallet"]["tickets"] = 0
	shop._refresh()
	var xs: HSlider = ex.rows["coins_ticket"]["slider"]
	if xs.max_value != 10 or not xs.editable:
		fails += 1
		push_error("Exchange slider: 1000 coins = at most 10 packs of 100")
	xs.value = 4
	(ex.rows["coins_ticket"]["plus"] as Button).pressed.emit()
	(ex.rows["coins_ticket"]["minus"] as Button).pressed.emit()
	(ex.rows["coins_ticket"]["plus"] as Button).pressed.emit()
	if int(xs.value) != 5:
		fails += 1
		push_error("Exchange + / - should move the slider by one pack")
	(ex.rows["coins_ticket"]["convert"] as Button).pressed.emit()
	if SaveManager.tickets() != 5 or SaveManager.coins() != 500:
		fails += 1
		push_error("Exchange button should convert the packs chosen on the slider")
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
		await gb._on_play()
		if gb.net_label.text == "" or SaveManager.coins() != 777:
			fails += 1
			push_error("Gamble %s should show a result and never touch coins" % g)
	SaveManager.data["wallet"]["coins"] = 5000  # coins alone must not enable a pull
	SaveManager.data["wallet"]["tickets"] = 0
	shop._show_tab("gacha")
	shop._refresh()
	if not gs.pull1.disabled or not gs.pull10.disabled:
		fails += 1
		push_error("pull buttons must be disabled without tickets (coins cannot pay)")
	SaveManager.data = saved
	SaveManager.save_game()
	print("UI SHOP SMOKE: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
