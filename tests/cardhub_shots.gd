extends Node
## Dev helper: renders the Card Hub (Info tab sections), the Main Menu button and the Territory Board button to /tmp/shots.
## Needs a real renderer: xvfb-run godot --path . res://tests/cardhub_shots.tscn

func _shot(vp: SubViewport, name: String) -> void:
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	vp.get_texture().get_image().save_png("/tmp/shots/%s.png" % name)


func _view(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	return vp


func _ready() -> void:
	OS.low_processor_usage_mode = false
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	GameSession.continent_id = "aetherion"
	GameSession.faction_id = "solvaris"
	var vp := _view(Vector2i(1280, 720))
	var menu: Control = load("res://scenes/main_menu/main_menu.tscn").instantiate()
	vp.add_child(menu)
	await _shot(vp, "01_main_menu")
	vp.queue_free()
	await get_tree().process_frame
	var vp2 := _view(Vector2i(1280, 720))
	var coll: Control = load("res://scenes/card_collection/card_collection.tscn").instantiate()
	vp2.add_child(coll)
	await _shot(vp2, "02_hub_collection_tab")
	coll._show_tab("info")
	for sec in coll.INFO_SECTIONS:
		coll._show_info(String(sec[0]))
		await _shot(vp2, "03_info_" + String(sec[0]))
	vp2.queue_free()
	await get_tree().process_frame
	var vp3 := _view(Vector2i(1280, 720))
	GameSession.resume_match = false
	var board: Control = load("res://scenes/territory_board/territory_board.tscn").instantiate()
	vp3.add_child(board)
	await _shot(vp3, "04_territory_board")
	board._open_hub()
	await get_tree().process_frame
	board._hub_node.get_child(0)._show_tab("info")
	await _shot(vp3, "05_territory_board_hub_overlay")
	get_tree().quit()
