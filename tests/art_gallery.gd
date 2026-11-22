extends Control
## Renders every illustration into one image (/tmp/shots/gallery.png) so they can be inspected by eye.
## Run under a virtual display: xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/art_gallery.tscn

var portraits: Array[PortraitView] = []


func _ready() -> void:
	OS.low_processor_usage_mode = false
	custom_minimum_size = Vector2(1280, 720)
	var x := 20.0
	for id in GameData.champions.keys():
		if portraits.size() >= 14:
			break
		var pv := PortraitView.new()
		pv.size = Vector2(110, 130)
		pv.position = Vector2(20 + (portraits.size() % 7) * 130, 520 + int(portraits.size() / 7) * 0.0)
		pv.setup(id)
		add_child(pv)
		portraits.append(pv)
	await get_tree().process_frame
	queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	get_viewport().get_texture().get_image().save_png("/tmp/shots/gallery.png")
	print("gallery saved")
	get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("151c38"))
	var col := Color("f0e6c8")
	var det := Color("151c38")
	var kinds := ["pawn", "rook", "knight", "bishop", "queen", "king"]
	for i in range(kinds.size()):
		Art.draw_piece(self, kinds[i], Rect2(20 + i * 150, 20, 120, 120), col, det)
	var conts := ["aetherion", "arcanum", "machina", "sylvaris", "drakmor", "thalassia", "eclipsia"]
	for i in range(conts.size()):
		draw_rect(Rect2(20 + i * 130, 160, 110, 110), Color("26305a"))
		Art.draw_emblem(self, conts[i], Rect2(20 + i * 130, 160, 110, 110), Color("d4af37"), Color("26305a"))
	var cats := ["Creation", "Transformation", "Magic", "Artifact", "Skill", "Blessing", "Contract"]
	for i in range(cats.size()):
		draw_rect(Rect2(20 + i * 130, 290, 110, 110), Color("2a2f4a"))
		Art.draw_category(self, cats[i], Rect2(20 + i * 130, 290, 110, 110), Color("8fd0ff"), Color("2a2f4a"))
	# small sizes (battle tokens are ~50 px)
	for i in range(kinds.size()):
		draw_circle(Vector2(60 + i * 90, 450), 30, Color("2a4a30"))
		Art.draw_piece(self, kinds[i], Rect2(34 + i * 90, 424, 52, 52), col, det)
