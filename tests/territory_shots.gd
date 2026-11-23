extends Node
## Dev helper: renders the Territory Board UI in several states and aspect ratios to /tmp/shots_territory.
## Needs a real renderer: xvfb-run godot --path . res://tests/territory_shots.tscn

func _shot(vp: SubViewport, name: String, frames: int = 6) -> void:
	for i in range(frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/shots_territory")
	vp.get_texture().get_image().save_png("/tmp/shots_territory/%s.png" % name)


func _ready() -> void:
	OS.low_processor_usage_mode = false
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	GameSession.continent_id = "aetherion"
	GameSession.faction_id = "solvaris"
	GameSession.resume_match = false
	var sizes := {"16x9": Vector2i(1280, 720), "20x9": Vector2i(1600, 720), "4x3": Vector2i(1280, 960)}
	for k in sizes:
		var vp := SubViewport.new()
		vp.size = sizes[k]
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
		vp.add_child(board)
		board.tick.stop()  # keep the AI quiet: we stage the states by hand
		await _shot(vp, "territory_start_" + k)
		if k == "16x9":
			board.ctrl.roll_dice()
			await _shot(vp, "territory_rolled_16x9", 60)  # dice animation + move
			board._open_hub()
			await get_tree().process_frame
			board._hub_node.get_child(0)._show_tab("info")
			board._hub_node.get_child(0)._show_info("roles")
			await _shot(vp, "territory_hub_info_16x9")
			board._close_hub()
			await get_tree().process_frame
		vp.queue_free()
		await get_tree().process_frame
	get_tree().quit()
