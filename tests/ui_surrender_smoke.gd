extends Node
## Surrender button: a duel of a match (Journey / Arena / Chaos) shows it where Battle Chess has the Menu button.
## Run: godot --headless --path . res://tests/ui_surrender_smoke.tscn   -> "UI SURRENDER SMOKE: PASS"

var fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text and (n as Button).is_visible_in_tree():
		return n as Button
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null


func _ready() -> void:
	# Battle Chess (standalone): the Menu button stays, there is no Surrender
	var chess: Control = load("res://scenes/battle_board/battle_board.tscn").instantiate()
	add_child(chess)
	await get_tree().process_frame
	check(_find_button(chess, "Menu") != null and _find_button(chess, "Surrender") == null, "Battle Chess shows Menu and no Surrender")
	chess.visible = false  # left in the tree: freeing it mid-test only prints a lambda warning of the test itself

	# Duel inside a match: Surrender replaces Menu
	var scene: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene.tick.stop()
	var c: MatchController = scene.ctrl
	var tile: BoardTile = null
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY:
			tile = t
			break
	c.monsters = []
	c.deposits = []
	tile.owner_id = 1
	c.players[0].position = tile.index
	c.current = 0
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	await get_tree().process_frame
	c.decide("duel")  # the AI owner challenges the human
	await get_tree().process_frame
	c.decide("accept")
	await get_tree().process_frame
	var duel: Control = scene._duel_node
	check(duel != null, "the duel overlay opens")
	if duel == null:
		print("UI SURRENDER SMOKE: FAIL")
		get_tree().quit(1)
		return
	check(_find_button(duel, "Surrender") != null and _find_button(duel, "Menu") == null, "the duel shows Surrender and no Menu")
	# asking opens the confirmation, nothing is reported yet
	duel._request_surrender()
	await get_tree().process_frame
	check(duel._surrender_dialog.visible and c.state == MatchController.State.AWAIT_DUEL, "Surrender asks first and the duel is still on")
	duel._surrender_dialog.hide()
	# buy something in the prep, then surrender: the spending must stay (the units stay in the roster)
	var gold_before: int = duel.prep.gold
	duel._on_buy(0)
	var spent: bool = duel.prep.gold < gold_before
	var duels_before: int = int(c.stats["duels"])
	var def_wins_before: int = int(c.stats["defender_wins"])
	var life_before: int = c.players[0].life
	var gold_after_buy: int = duel.prep.gold
	duel._do_surrender()
	await get_tree().process_frame
	check(scene._duel_node == null and c.state != MatchController.State.AWAIT_DUEL, "confirmed Surrender closes the duel")
	check(int(c.stats["duels"]) == duels_before + 1 and int(c.stats["defender_wins"]) == def_wins_before + 1, "the opponent (tile owner) wins the duel: a defeat")
	check(c.players[0].life == life_before - 1 or c.players[0].life < life_before, "a surrendered attack costs a life like any lost duel (%d -> %d)" % [life_before, c.players[0].life])
	check(not spent or c.players[0].gold <= gold_after_buy + 0, "gold spent in the prep stays spent (%d)" % c.players[0].gold)
	print("UI SURRENDER SMOKE: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	get_tree().quit(fails)
