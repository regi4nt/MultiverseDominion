extends Control
## Collection & Deck (one screen, two tabs).
## Collection tab: browse all unit and support cards, see star scaling and owned copies.
## Deck tab: the 135 unit cards are fixed (15 types x 9); the player chooses the Champion and exactly
## 15 Support cards out of the owned ones. TODO: more unit variants to choose from.

var _grid: HFlowContainer
var _detail: RichTextLabel
var _filter: String = "all"
var _selected_id: String = ""
var _views: Dictionary = {}

var deck: Deck
var _support_buttons: Dictionary = {}
var _champion_buttons: Dictionary = {}
var _summary: RichTextLabel
var _save_btn: Button
var _message: Label
var _collection_view: Control
var _deck_view: Control
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	theme = UiTheme.get_theme()
	CardDatabase.set_continent(GameSession.continent_id)  # cards show the factions of the selected continent
	deck = SaveManager.get_deck()
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := UiTheme.make_label("COLLECTION & DECK", 36, UiTheme.COL_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := UiTheme.make_button("Back", 48)
	back.custom_minimum_size.x = 140
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	head.add_child(back)

	# Top-level tabs: Collection | Deck
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	root.add_child(modes)
	var mgroup := ButtonGroup.new()
	for spec in [["collection", "Collection"], ["deck", "Deck"]]:
		var mb := UiTheme.make_toggle(spec[1], mgroup, 52)
		mb.custom_minimum_size.x = 200
		mb.button_pressed = (spec[0] == "collection")
		mb.pressed.connect(_show_tab.bind(spec[0]))
		modes.add_child(mb)
		_tab_buttons[spec[0]] = mb

	_collection_view = VBoxContainer.new()
	_collection_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_collection_view.add_theme_constant_override("separation", 8)
	root.add_child(_collection_view)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	_collection_view.add_child(tabs)
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
	_collection_view.add_child(body)

	var scroll := UiTheme.make_scroll()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_deck_view = _build_deck_view()
	root.add_child(_deck_view)
	_show_tab("collection")
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



func _show_tab(which: String) -> void:
	_collection_view.visible = (which == "collection")
	_deck_view.visible = (which == "deck")
	if _tab_buttons.has(which):
		_tab_buttons[which].set_pressed_no_signal(true)


func _build_deck_view() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)

	# Champions
	var cpanel := PanelContainer.new()
	cpanel.custom_minimum_size = Vector2(280, 0)
	body.add_child(cpanel)
	var cscroll := UiTheme.make_scroll()
	cpanel.add_child(cscroll)
	var cbox := VBoxContainer.new()
	cbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbox.add_theme_constant_override("separation", 6)
	cscroll.add_child(cbox)
	cbox.add_child(UiTheme.make_label("Champion (King)", 22, UiTheme.COL_GOLD))
	var cgroup := ButtonGroup.new()
	for cid in GameData.champions.keys():
		var ch: Dictionary = GameData.champions[cid]
		var b := UiTheme.make_toggle(String(ch["name"]), cgroup, 56)
		b.button_pressed = (cid == deck.champion_id)
		b.pressed.connect(func():
			deck.champion_id = cid
			_refresh())
		UiTheme.scroll_passthrough(b)
		cbox.add_child(b)
		_champion_buttons[cid] = b

	# Supports
	var spanel := PanelContainer.new()
	spanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(spanel)
	var sscroll := UiTheme.make_scroll()
	spanel.add_child(sscroll)
	var sbox := VBoxContainer.new()
	sbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sbox.add_theme_constant_override("separation", 6)
	sscroll.add_child(sbox)
	sbox.add_child(UiTheme.make_label("Support cards (choose 15)", 22, UiTheme.COL_GOLD))
	for cat in CardDatabase.SUPPORT_CATEGORIES:
		sbox.add_child(UiTheme.make_label(cat, 16, UiTheme.COL_MUTED))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		sbox.add_child(flow)
		for s in CardDatabase.all_supports():
			if s["category"] != cat:
				continue
			var owned := SaveManager.owned_count(s["id"]) > 0
			var b := UiTheme.make_button(String(s["name"]) if owned else "%s (locked)" % s["name"], 48)
			b.custom_minimum_size.x = 210
			b.toggle_mode = true
			b.disabled = not owned
			b.tooltip_text = String(s["description"])
			b.button_pressed = deck.support_ids.has(s["id"])
			b.toggled.connect(_on_support_toggled.bind(s["id"]))
			UiTheme.scroll_passthrough(b)
			flow.add_child(b)
			_support_buttons[s["id"]] = b

	# Summary
	var rpanel := PanelContainer.new()
	rpanel.custom_minimum_size = Vector2(320, 0)
	body.add_child(rpanel)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 8)
	rpanel.add_child(rbox)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_font_size_override("normal_font_size", 17)
	rbox.add_child(_summary)
	_message = UiTheme.make_label("", 15, UiTheme.COL_DANGER)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rbox.add_child(_message)
	var reset := UiTheme.make_button("Reset to default", 52)
	reset.pressed.connect(_on_reset)
	rbox.add_child(reset)
	_save_btn = UiTheme.make_button("Save deck", 60)
	_save_btn.pressed.connect(_on_save)
	rbox.add_child(_save_btn)
	_refresh()
	return body


func _on_support_toggled(pressed: bool, id: String) -> void:
	if pressed:
		if deck.support_ids.size() >= int(GameData.b("deck_support")):
			_support_buttons[id].set_pressed_no_signal(false)
			_message.text = "Deck already has 15 Support cards. Remove one first."
			return
		deck.support_ids.append(id)
	else:
		deck.support_ids.erase(id)
	_refresh()


func _on_reset() -> void:
	deck = Deck.create_default()
	for id in _support_buttons:
		_support_buttons[id].set_pressed_no_signal(deck.support_ids.has(id))
	for cid in _champion_buttons:
		_champion_buttons[cid].set_pressed_no_signal(cid == deck.champion_id)
	_refresh()


func _on_save() -> void:
	if deck.validate(SaveManager.data["collection"]).is_empty():
		SaveManager.set_deck(deck)
		_message.text = ""
		_summary.text += "\n[color=#59cd90]Deck saved.[/color]"


func _refresh() -> void:
	var errors := deck.validate(SaveManager.data["collection"])
	var ch := GameData.get_champion(deck.champion_id)
	_summary.text = "[color=#d4af37][b]Battle Deck[/b][/color]\nChampion: %s\nUnit cards: 135 (15 types x 9, fixed)\nSupport: %d / %d\nTotal: %d / %d" % [
		ch.get("name", "?"), deck.support_ids.size(), int(GameData.b("deck_support")), deck.card_list().size(), int(GameData.b("deck_total"))]
	_save_btn.disabled = not errors.is_empty()
	_message.text = "\n".join(errors)
