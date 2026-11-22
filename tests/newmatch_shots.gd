extends Node
## Dev helper: renders the New Match views to /tmp/shots (needs a real renderer: xvfb-run godot --path . res://tests/newmatch_shots.tscn).

func _ready() -> void:
	OS.low_processor_usage_mode = false
	SaveManager.data = SaveManager.default_data()  # screenshots of a fresh save
	SaveManager.ensure_collection()
	GameSession.continent_id = "aetherion"
	var sizes := {"16x9": Vector2i(1280, 720), "20x9": Vector2i(1600, 720), "4x3": Vector2i(1280, 960)}
	for k in sizes:
		var vp := SubViewport.new()
		vp.size = sizes[k]
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var n: Control = load("res://scenes/match_setup/match_setup.tscn").instantiate()
		vp.add_child(n)
		await _shot(vp, "hub_offline_" + k)
		n._set_tab("online")
		await _shot(vp, "hub_online_" + k)
		n._show_setup("arena")
		await _shot(vp, "setup_arena_" + k)
		n._show_setup("journey")
		await _shot(vp, "setup_journey_" + k)
		vp.queue_free()
		await get_tree().process_frame
	# Deck tab: faction list with locked factions (fresh save: only Aetherion is open)
	GameSession.continent_id = "aetherion"
	GameSession.open_deck_tab = true
	var vp2 := SubViewport.new()
	vp2.size = Vector2i(1280, 720)
	vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp2)
	var coll: Control = load("res://scenes/card_collection/card_collection.tscn").instantiate()
	vp2.add_child(coll)
	await _shot(vp2, "deck_factions_16x9")
	(coll._pool_box.get_parent() as ScrollContainer).scroll_vertical = 330  # the locked continents
	await _shot(vp2, "deck_factions_locked_16x9")
	# Journey with a continent unlock ready (all 4 Aetherion factions won)
	SaveManager.data = SaveManager.default_data()
	SaveManager.ensure_collection()
	for f in ["solvaris", "nocthyr", "valdoria"]:
		SaveManager.record_match(true, 10, 100, "aetherion", true, f)
	var vp3 := SubViewport.new()
	vp3.size = Vector2i(1280, 720)
	vp3.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp3)
	var n3: Control = load("res://scenes/match_setup/match_setup.tscn").instantiate()
	vp3.add_child(n3)
	n3._show_setup("journey")
	await _shot(vp3, "setup_journey_progress_16x9")
	SaveManager.record_match(true, 10, 100, "aetherion", true, "elarion")
	n3._show_setup("journey")
	await _shot(vp3, "setup_journey_unlock_16x9")
	get_tree().quit()

func _shot(vp: SubViewport, name: String) -> void:
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("/tmp/shots/%s.png" % name)
