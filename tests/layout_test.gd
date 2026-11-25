extends Node
## Phase 7 layout audit. Project stretch: canvas_items + aspect expand on a 1280x720 base, so the
## logical viewport of a device is 1280x720 grown along its longer/shorter axis. Each scene is
## rendered in a SubViewport of that logical size; every visible control must lie inside it, and
## buttons are checked for touch size. Run: godot --headless --path . res://tests/layout_test.tscn

const SIZES := {
	"16:9 1920x1080": Vector2i(1280, 720), "18:9 2160x1080": Vector2i(1440, 720), "20:9 2400x1080": Vector2i(1600, 720),
	"21:9 2520x1080": Vector2i(1680, 720), "4:3 tablet 2048x1536": Vector2i(1280, 960), "16:10 1920x1200": Vector2i(1280, 800),
	"5:3 800x480 low-end": Vector2i(1280, 768)}
const SCENES := ["main_menu/main_menu", "match_setup/match_setup", "settings/settings", "territory_board/territory_board",
	"battle_board/battle_board", "card_collection/card_collection", "shop/shop"]
const MIN_TOUCH := 48.0  # logical px; ~5.5 mm on a typical 6.5" phone

var overflow: Array[String] = []
var small: Dictionary = {}  # "scene: text" -> height


func _ready() -> void:
	OS.low_processor_usage_mode = false  # the project enables it for battery life; screenshots need real frames
	for c in GameData.continents:  # tests need every continent open (the game has no unlock-all feature)
		SaveManager.unlock_continent(c["id"])
	for label in SIZES:
		var sz: Vector2i = SIZES[label]
		for sc in SCENES:
			var vp := SubViewport.new()
			vp.size = sz
			add_child(vp)
			var node: Control = load("res://scenes/%s.tscn" % sc).instantiate()
			vp.add_child(node)
			for i in range(4):
				await get_tree().process_frame
			_audit(node, Rect2(Vector2.ZERO, Vector2(sz)), "%s @ %s" % [sc.get_file(), label], sc.get_file())
			if "shots" in OS.get_cmdline_user_args() and label in ["16:9 1920x1080", "20:9 2400x1080", "4:3 tablet 2048x1536"]:
				if sc.get_file() == "territory_board":  # the start camera is zoomed in on the pawn: show the whole board in the screenshot
					for i in range(30):  # the zoom buttons are locked while the start dice animation runs
						await get_tree().process_frame
					var bv = node.board_view
					bv._on_zoom_button(0.0)
					bv._user_cam = true  # an AI turn would otherwise pull the camera back onto its pawn
					bv.zoom = bv.ZOOM_MIN
					bv._focus = Vector2(0.5, 0.5)
					bv.queue_redraw()
				vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("/tmp/shots")
				vp.get_texture().get_image().save_png("/tmp/shots/%s_%s.png" % [sc.get_file(), label.split(" ")[0].replace(":", "x")])
			if sc.get_file() == "battle_board":  # second pass: the fight phase (supports panel, log)
				var prep_rect: Rect2 = node.grid.get_global_rect()
				node._on_auto()
				node._on_start_battle()
				node.timer.stop()
				for i in range(3):
					await get_tree().process_frame
				if not node.grid.get_global_rect().is_equal_approx(prep_rect):  # the board must not grow / move when the fight starts
					overflow.append("battle_board @ %s: the board changed from %s to %s when the fight started" % [label, str(prep_rect), str(node.grid.get_global_rect())])
				_audit(node, Rect2(Vector2.ZERO, Vector2(sz)), "battle_board(fight) @ %s" % label, "battle_board(fight)")
				if "shots" in OS.get_cmdline_user_args() and label == "16:9 1920x1080":
					for i in range(9):
						node._on_tick()
					vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					vp.get_texture().get_image().save_png("/tmp/shots/battle_fight_16x9.png")
			if sc.get_file() == "card_collection":  # second pass: the Deck tab
				node._show_tab("deck")
				for i in range(3):
					await get_tree().process_frame
				_audit(node, Rect2(Vector2.ZERO, Vector2(sz)), "card_collection(deck) @ %s" % label, "card_collection(deck)")
			if sc.get_file() == "match_setup":  # extra passes: Online tab, Arena setup, Journey setup
				node._set_tab("online")
				for i in range(3):
					await get_tree().process_frame
				_audit(node, Rect2(Vector2.ZERO, Vector2(sz)), "match_setup(online) @ %s" % label, "match_setup(online)")
				for kind in ["arena", "journey"]:
					node._show_setup(kind)
					for i in range(3):
						await get_tree().process_frame
					_audit(node, Rect2(Vector2.ZERO, Vector2(sz)), "match_setup(%s) @ %s" % [kind, label], "match_setup(%s)" % kind)
			vp.queue_free()
			await get_tree().process_frame
	print("overflowing controls: ", overflow.size())
	for o in overflow.slice(0, 25):
		print("   ", o)
	var heights := {}
	for k in small:
		heights[k] = small[k]
	print("buttons below %d px: %d" % [int(MIN_TOUCH), heights.size()])
	for k in heights:
		print("   %s -> %d px" % [k, int(heights[k])])
	var strict := "strict" in OS.get_cmdline_user_args()
	print("LAYOUT TEST RESULT: ", "PASS" if overflow.is_empty() and (small.is_empty() or not strict) else "FAIL")
	get_tree().quit(0 if overflow.is_empty() and (small.is_empty() or not strict) else 1)


func _audit(n: Node, view: Rect2, tag: String, scene: String) -> void:
	if n is Window or (n is CanvasItem and not (n as CanvasItem).visible):
		return
	if n is Control:
		var c := n as Control
		if c.size.x > 0 and c.size.y > 0 and not (c is ColorRect) and not (c is AspectRatioContainer):
			var r := c.get_global_rect()
			if r.position.x < view.position.x - 1 or r.position.y < view.position.y - 1 or r.end.x > view.end.x + 1 or r.end.y > view.end.y + 1:
				overflow.append("%s: %s '%s' rect %s" % [tag, c.get_class(), _name(c), str(r)])
		if c is Button and not (c as Button).disabled:
			if c.size.y < MIN_TOUCH and c.size.y > 0:
				small["%s: '%s'" % [scene, _name(c)]] = c.size.y
	if n is ScrollContainer:
		return  # content scrolls, only the container itself is audited above
	for ch in n.get_children():
		_audit(ch, view, tag, scene)


func _name(c: Control) -> String:
	if c is Button:
		return (c as Button).text.substr(0, 26)
	if c is Label:
		return (c as Label).text.substr(0, 26)
	return c.name
