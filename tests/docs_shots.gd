extends Node
## Dev helper: renders the screenshots in docs/screenshots/ that layout_test / newmatch_shots do not produce
## (Journey trophy unlock, Collection tab with locked Kings). Output: /tmp/shots.
## Needs a real renderer: xvfb-run godot --path . --rendering-driver opengl3 res://tests/docs_shots.tscn

func _shot(vp: SubViewport, name: String) -> void:
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	vp.get_texture().get_image().save_png("/tmp/shots/%s.png" % name)


func _view() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	return vp


func _ready() -> void:
	OS.low_processor_usage_mode = false
	# Journey: a win lifts the trophies over the next continent's threshold, which opens it
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	GameSession.continent_id = "aetherion"
	SaveManager.data["trophies"] = 130
	SaveManager.record_match(true, 10, 100, "aetherion", true, "solvaris")
	var vp := _view()
	var n: Control = load("res://scenes/match_setup/match_setup.tscn").instantiate()
	vp.add_child(n)
	n._show_setup("journey")
	await _shot(vp, "journey_unlock_16x9")
	vp.queue_free()
	await get_tree().process_frame
	# Collection tab, King filter: the Kings of locked continents are greyed out
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	var vp2 := _view()
	var coll: Control = load("res://scenes/card_collection/card_collection.tscn").instantiate()
	vp2.add_child(coll)
	coll._show_tab("collection")
	await get_tree().process_frame
	for b in coll.find_children("*", "Button", true, false):
		if (b as Button).text == "King":
			(b as Button).button_pressed = true
			(b as Button).pressed.emit()
			break
	await get_tree().process_frame
	await _shot(vp2, "collection_kings_locked_16x9")
	vp2.queue_free()
	await get_tree().process_frame
	# Territory Board with the whole board in view (Fit), at three aspect ratios
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	GameSession.continent_id = "aetherion"
	GameSession.faction_id = "solvaris"
	GameSession.resume_match = false
	var sizes := {"16x9": Vector2i(1280, 720), "20x9": Vector2i(1600, 720)}
	for k in sizes:
		var vp3 := _view()
		vp3.size = sizes[k]
		var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
		vp3.add_child(board)
		board.tick.stop()
		for i in range(30):  # the zoom buttons are locked while the start dice animation runs
			await get_tree().process_frame
		var bv = board.board_view
		bv._on_zoom_button(0.0)
		bv._user_cam = true  # an AI turn would otherwise pull the camera back onto its pawn
		bv.zoom = bv.ZOOM_MIN
		bv._focus = Vector2(0.5, 0.5)
		bv.queue_redraw()
		await _shot(vp3, "territory_board_" + k)
		vp3.queue_free()
		await get_tree().process_frame
	get_tree().quit()
