extends Node
## Continent skins of the Territory Board and the Battle Board: data, uniqueness, fallback, real drawing of the views.
## Run: godot --headless --path . res://tests/skin_test.tscn

var failures := 0
const CONTS := ["aetherion", "arcanum", "machina", "sylvaris", "drakmor", "thalassia", "eclipsia"]
const PATTERN_OF := {"aetherion": "marble", "arcanum": "runes", "machina": "gears", "sylvaris": "leaves", "drakmor": "embers", "thalassia": "waves", "eclipsia": "stars"}


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


## Draws every motif and watermark inside a real _draw() pass.
class Probe extends Control:
	var drawn := 0
	var cont := "aetherion"

	func _draw() -> void:
		for pat in MapSkin.PATTERNS:
			for i in range(3):
				MapSkin.draw_motif(self, pat, Rect2(Vector2(10, 10), Vector2(60, 60)), Color(1, 1, 1, 0.4), i)
				drawn += 1
		var sk: Dictionary = MapSkin.get_skin(cont)["territory"]
		MapSkin.draw_watermark(self, cont, Rect2(Vector2(100, 10), Vector2(200, 200)), sk, Color.BLACK)
		drawn += 1


func _ready() -> void:
	_test_data()
	_test_fallback()
	await _test_probe()
	await _test_views()
	print("SKIN TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(failures)


func _dist(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func _test_data() -> void:
	var ok := true
	var pats := {}
	var frames := {}
	var tiles := {}
	var skies := {}
	var radii := {}
	for cid in CONTS:
		var raw: Dictionary = GameData.get_map_skin(cid)
		ok = ok and raw.has("territory") and raw.has("battle") and raw.has("backdrop")
		var sk: Dictionary = MapSkin.get_skin(cid)
		var t: Dictionary = sk["territory"]
		var b: Dictionary = sk["battle"]
		ok = ok and String(t["pattern"]) == PATTERN_OF[cid] and String(b["pattern"]) == PATTERN_OF[cid]
		ok = ok and MapSkin.PATTERNS.has(String(t["pattern"]))
		ok = ok and float(t["motif_a"]) > 0.0 and float(b["motif_a"]) > 0.0 and float(t["emblem_a"]) > 0.0
		# your half and the enemy half must stay easy to tell apart on every skin
		ok = ok and _dist(b["mine_light"], b["foe_light"]) > 0.12 and _dist(b["mine_dark"], b["foe_dark"]) > 0.12
		# the text colour on the centre plate must stay readable
		ok = ok and (t["center_bg"] as Color).get_luminance() < 0.12 and (t["title"] as Color).get_luminance() > 0.25
		pats[t["pattern"]] = true
		frames[(t["frame"] as Color).to_html()] = true
		tiles[(t["tile"] as Color).to_html()] = true
		skies[(sk["backdrop"]["top"] as Color).to_html()] = true
		radii[snappedf(float(t["radius"]), 0.01)] = true
	check(ok, "7 continents have a complete skin (territory + battle + backdrop), own pattern, readable plates, both battle halves distinct")
	check(pats.size() == 7 and frames.size() == 7 and tiles.size() == 7 and skies.size() == 7, "every continent has its own pattern, frame, tile and sky colour")
	check(radii.size() >= 5, "tile shapes differ between continents (%d different corner radii)" % radii.size())
	check(MapSkin.get_skin("machina")["territory"]["radius"] < MapSkin.get_skin("sylvaris")["territory"]["radius"], "Machina is angular, Sylvaris is round")


func _test_fallback() -> void:
	var sk: Dictionary = MapSkin.get_skin("no_such_continent")
	check(String(sk["territory"]["pattern"]) == "" and (sk["territory"]["tile"] as Color).to_html(false) == "1a2342", "unknown continent falls back to the original Territory look")
	check((sk["battle"]["mine_light"] as Color).to_html(false) == "1b2c52" and (sk["backdrop"]["top"] as Color).to_html(false) == "1a2350", "unknown continent falls back to the original Battle look and sky")
	var bad: Dictionary = MapSkin._resolve(MapSkin.DEFAULT_TERRITORY, {"pattern": "nonsense", "radius": 0.3})
	check(String(bad["pattern"]) == "" and is_equal_approx(float(bad["radius"]), 0.3), "an unknown pattern name is ignored, other keys still apply")
	var bg := UiTheme.make_background("drakmor")
	var bg_ok := bg != null and bg.texture != null and UiTheme.backdrop_texture("") != null
	bg.free()
	check(bg_ok, "backgrounds build with and without a continent")
	var neutral := UiTheme.backdrop_texture("")
	var skinned := UiTheme.backdrop_texture("drakmor")
	check(neutral.gradient.get_color(0) != skinned.gradient.get_color(0), "a continent re-colours the screen backdrop")


func _test_probe() -> void:
	var pr := Probe.new()
	pr.size = Vector2(400, 300)
	add_child(pr)
	await get_tree().process_frame
	await get_tree().process_frame
	check(pr.drawn > 0, "all 7 motifs and the emblem watermark draw without errors (%d draw passes)" % pr.drawn)
	pr.queue_free()


func _test_views() -> void:
	var ok_board := true
	var ok_battle := true
	for cid in CONTS:
		# Territory Board
		var c := MatchController.new()
		c.setup({"continent_id": cid, "faction_id": GameData.get_continent(cid)["factions"][0]["id"], "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true})
		for i in range(c.tiles.size()):  # own some land so owned tiles are drawn too
			if c.tiles[i].is_territory() and i % 3 == 0:
				c.tiles[i].owner_id = i % 4
		var bv := BoardView.new()
		bv.custom_minimum_size = Vector2(700, 700)
		bv.size = Vector2(700, 700)
		add_child(bv)
		bv.bind(c)
		await get_tree().process_frame
		await get_tree().process_frame
		bv.selected_index = 3
		bv.queue_redraw()
		await get_tree().process_frame
		var tsk: Dictionary = bv._terr()
		ok_board = ok_board and String(tsk["pattern"]) == PATTERN_OF[cid] and bv._tile_color(c.tiles[2]) == tsk["tile"]
		bv.queue_free()
		# Battle Board (prep + a few battle ticks)
		CardDatabase.set_continent(cid)
		var gv := BattleGridView.new()
		gv.size = Vector2(640, 640)
		add_child(gv)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var p: PlayerState = c.players[0]
		var prep := BattlePrep.new(p.deck, rng, p.gold, 0, p.level, p.roster, p.battle_deck, p.hand)
		BattleAI.auto_deploy(prep, 0)
		prep.finish()
		gv.show_prep(prep)
		await get_tree().process_frame
		var e := BattleEngine.new()
		e.setup({"seed": 4, "ai_supports": [false, false], "terrain": prep.terrain, "sides": [prep.to_side_cfg(p.champion_id, [], p.commander_star), {"units": [], "champion": "", "supports": [], "foes": [GameData.get_monsters(cid)[0]["id"]]}]})
		gv.show_engine(e)
		for i in range(6):
			e.step()
			gv.notify_tick()
		await get_tree().process_frame
		await get_tree().process_frame
		ok_battle = ok_battle and String(gv._bskin()["pattern"]) == PATTERN_OF[cid]
		gv.queue_free()
	await get_tree().process_frame  # let the queued frees of the last views run before quitting
	check(ok_board, "the Territory Board of every continent draws with its own skin")
	check(ok_battle, "the Battle Board of every continent draws (prep and fight) with its own skin")
