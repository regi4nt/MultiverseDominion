extends Control
## Card Collection: browse all unit and support cards, see star scaling and owned copies.

var _grid: HFlowContainer
var _detail: RichTextLabel
var _filter: String = "all"
var _selected_id: String = ""
var _views: Dictionary = {}


func _ready() -> void:
	theme = UiTheme.get_theme()
	CardDatabase.set_continent(GameSession.continent_id)  # cards show the factions of the selected continent
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := UiTheme.make_label("CARD COLLECTION", 36, UiTheme.COL_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := UiTheme.make_button("Back", 48)
	back.custom_minimum_size.x = 140
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	head.add_child(back)

	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	root.add_child(tabs)
	var group := ButtonGroup.new()
	for f in ["all", "pawn", "rook", "knight", "bishop", "queen", "support"]:
		var b := UiTheme.make_toggle(f.capitalize(), group, 44)
		b.custom_minimum_size.x = 110
		b.button_pressed = (f == _filter)
		b.pressed.connect(func():
			_filter = f
			_rebuild())
		tabs.add_child(b)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	body.add_child(panel)
	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.add_theme_font_size_override("normal_font_size", 17)
	_detail.text = "Tap a card to see its details."
	panel.add_child(_detail)
	_rebuild()


func _rebuild() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_views.clear()
	if _filter != "support":
		for u in CardDatabase.all_units():
			if _filter == "all" or u["chess"] == _filter:
				_add_card(u, false)
	if _filter == "all" or _filter == "support":
		for s in CardDatabase.all_supports():
			_add_card(s, true)


func _add_card(c: Dictionary, support: bool) -> void:
	var v := CardView.new()
	v.setup(c, support, SaveManager.owned_count(c["id"]))
	v.pressed.connect(_on_card)
	v.set_selected(c["id"] == _selected_id)
	_grid.add_child(v)
	_views[c["id"]] = v


func _on_card(id: String) -> void:
	if _views.has(_selected_id):
		_views[_selected_id].set_selected(false)
	_selected_id = id
	_views[id].set_selected(true)
	_detail.text = _describe(id)


func _describe(id: String) -> String:
	var owned := SaveManager.owned_count(id)
	if CardDatabase.is_support(id):
		var s := CardDatabase.get_support(id)
		return "[color=#d4af37][b]%s[/b][/color]\n%s - %s\nUses per battle: %d\n\n%s\n\n[color=#8d93ad]Effect '%s' is applied in battles (TODO Phase 4).[/color]\n\nOwned: %d" % [
			s["name"], s["category"], String(s["rarity"]).capitalize(), s["uses"], s["description"], s["effect"], owned]
	var u := CardDatabase.get_unit(id)
	var copies: Array = GameData.b("star_copies")
	var lines := ""
	for st in range(1, 4):
		var stt := CardDatabase.unit_stats(id, st)
		lines += "%d-star (%d cards): HP %d  ATK %d\n" % [st, copies[st - 1], stt["hp"], stt["atk"]]
	return "[color=#d4af37][b]%s[/b][/color]\n%s %s - %s - %s\nCapacity cost: %d\nRange %d   Movement %d\n\n%s\n\n[b]%s:[/b] %s\n\nOwned copies: %d / %d" % [
		u["name"], String(u["faction"]).capitalize(), String(u["chess"]).capitalize(), u["role"], String(u["rarity"]).capitalize(),
		CardDatabase.capacity_cost(u["chess"]), u["range"], u["move"], lines, u["skill"]["name"], u["skill"]["desc"], owned, int(GameData.b("unit_copies"))]
