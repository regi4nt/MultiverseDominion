extends Node
## Dev helper: renders the Territory Board and the Battle Board of EVERY continent to /tmp/shots_skins.
## Needs a real renderer: xvfb-run godot --path . res://tests/skin_shots.tscn

const CONTS := ["aetherion", "arcanum", "machina", "sylvaris", "drakmor", "thalassia", "eclipsia"]


func _shot(vp: SubViewport, name: String, frames: int = 8) -> void:
	for i in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/shots_skins")
	vp.get_texture().get_image().save_png("/tmp/shots_skins/%s.png" % name)


func _ready() -> void:
	OS.low_processor_usage_mode = false
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	for cid in CONTS:
		GameSession.continent_id = cid
		GameSession.faction_id = String(GameData.get_continent(cid)["factions"][0]["id"])
		GameSession.resume_match = false
		GameSession.mode = "ffa_ai"
		var vp := SubViewport.new()
		vp.size = Vector2i(1280, 720)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
		vp.add_child(board)
		board.tick.stop()
		# give the land a few owners so owned tiles show too
		for i in range(board.ctrl.tiles.size()):
			if board.ctrl.tiles[i].is_territory() and i % 4 == 1:
				board.ctrl.tiles[i].owner_id = (i / 4) % 4
		board.board_view.queue_redraw()
		await _shot(vp, "territory_" + cid)
		vp.queue_free()
		await get_tree().process_frame
		var vp2 := SubViewport.new()
		vp2.size = Vector2i(1280, 720)
		vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp2)
		var b: Control = load("res://scenes/battle_board/battle_board.tscn").instantiate()
		vp2.add_child(b)
		await get_tree().process_frame
		for i in range(5):
			b._on_buy(i)
		b._on_auto()
		await _shot(vp2, "battle_prep_" + cid)
		b._on_start_battle()
		b.timer.stop()
		for i in range(14):
			b._on_tick()
		await _shot(vp2, "battle_fight_" + cid, 4)
		vp2.queue_free()
		await get_tree().process_frame
	get_tree().quit()
