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
	if not names.has("Shop") or not names.has("Profile") or names.find("Shop") > names.find("Profile"):
		fails += 1
		push_error("Shop must be a menu entry placed above Profile (%s)" % str(names))
	menu.queue_free()
	await get_tree().process_frame

	var shop: Control = load("res://scenes/shop/shop.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	if not shop._gacha_view.visible or shop._buy_view.visible or shop._pull10.disabled:
		fails += 1
	shop._on_pull(10)
	await get_tree().process_frame
	if shop._result_flow.get_child_count() != 10:
		fails += 1
		push_error("10 pulls should show 10 cards")
	shop._show_tab("cards")
	await get_tree().process_frame
	var n := shop._buy_grid.get_child_count()
	if n == 0 or n != ShopSystem.locked_supports().size():
		fails += 1
		push_error("the Buy tab should list every locked card (%d)" % n)
	var id := String(ShopSystem.locked_supports()[0]["id"])
	shop._on_card(id)
	if shop._buy_btn.disabled:
		fails += 1
	var coins := SaveManager.coins()
	shop._on_buy()
	await get_tree().process_frame
	if SaveManager.owned_count(id) != 1 or SaveManager.coins() >= coins:
		fails += 1
		push_error("buying should unlock the card and cost coins")
	shop._buy_filter = "Magic"
	shop._rebuild_buy()
	if shop._buy_grid.get_child_count() != ShopSystem.locked_supports("Magic").size():
		fails += 1
	SaveManager.data["wallet"]["coins"] = 0
	shop._refresh()
	if not shop._pull1.disabled or not shop._pull10.disabled:
		fails += 1
		push_error("pull buttons must be disabled without coins")
	SaveManager.data = saved
	SaveManager.save_game()
	print("UI SHOP SMOKE: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
