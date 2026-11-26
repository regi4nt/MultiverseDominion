extends Node
## Dev helper: renders the Battle Chess board (prep, a selected unit, mid-battle) to /tmp/shots.
## xvfb-run godot --path . res://tests/battle_shot.tscn

func _shot(vp: SubViewport, name: String) -> void:
	for i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	vp.get_texture().get_image().save_png("/tmp/shots/%s.png" % name)


func _ready() -> void:
	OS.low_processor_usage_mode = false
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	GameSession.continent_id = "aetherion"
	GameSession.faction_id = "solvaris"
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var b: Control = load("res://scenes/battle_board/battle_board.tscn").instantiate()
	vp.add_child(b)
	await _shot(vp, "b1_prep")
	if not b.prep.roster.units.is_empty():
		b._on_select(b.prep.roster.units[0])
	await _shot(vp, "b2_selected")
	b._on_auto()
	b._on_start_battle()
	for i in range(40):
		await get_tree().process_frame
	await _shot(vp, "b3_battle")
	get_tree().quit()
