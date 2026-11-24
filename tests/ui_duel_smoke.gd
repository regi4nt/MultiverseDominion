extends Node
## Territory Board with a human visitor: Encounter -> Duel -> Battle overlay -> result -> Conquest/Reward.

func play_overlay(scene: Control) -> bool:  # false = the Monster skill button is missing
	var b: Control = scene._duel_node
	b._on_auto()
	b._on_start_battle()
	b.timer.stop()
	var has_btn: bool = b.monster_btn != null
	if has_btn:  # Monster card owner: the Monster skill button exists and can be pressed at any time without errors
		b.engine.energy[0] = b.engine.energy_max()
		b._on_monster_skill()
		b._refresh_monster_btn()
		print("monster skill button: ", b.monster_btn.text.replace("\n", " | "))
	var n := 0
	while not b.engine.finished and n < 1000:
		b._on_tick()
		n += 1
	b._finish_duel()
	return has_btn


func _ready() -> void:
	var fails := 0
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
	c.monsters = []  # hidden monsters / deposits are placed at random: keep the scripted landing deterministic
	c.deposits = []
	tile.owner_id = 1
	c.players[0].position = tile.index
	c.current = 0
	c.state = MatchController.State.ROLLED
	c._resolve_landing(c.players[0])
	await get_tree().process_frame
	print("encounter actor: ", c.decision_actor().display_name, " | buttons: ", scene.action_box.get_child_count())
	c.decide("duel")  # AI owner challenges the human
	await get_tree().process_frame
	var labels: Array[String] = []
	for ch in scene.action_box.get_children():
		if ch is Button:
			labels.append(ch.text)
	print("human sees: ", labels)
	if labels.size() != 2:
		fails += 1
	c.players[0].monster_id = "crownstone_golem"  # the human owns a Monster card: the Battle panel gets a Monster skill button
	c.decide("accept")
	await get_tree().process_frame
	print("overlay open: ", scene._duel_node != null, " state=", c.state)
	if scene._duel_node == null:
		fails += 1
	else:
		var gold_before: int = c.players[0].gold
		if not play_overlay(scene):
			print("FAIL: no Monster skill button for a Monster card owner")
			fails += 1
		await get_tree().process_frame
		print("overlay closed: ", scene._duel_node == null, " pending=", c.pending.get("type", "none"), " state=", c.state, " gold ", gold_before, "->", c.players[0].gold)
		if scene._duel_node != null or c.state == MatchController.State.AWAIT_DUEL:
			fails += 1
		if c.state == MatchController.State.AWAIT_DECISION and String(c.pending["type"]) == "conquest":
			c.decide("conquest")
			print("conquered: owner=", tile.owner_id)
			if tile.owner_id != 0:
				fails += 1
	print("UI DUEL SMOKE: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(fails)
