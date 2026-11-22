extends Control
## Collection & Deck (one screen, two tabs).
## Collection tab: browse all unit and support cards, see star scaling and owned copies.
## Deck tab: 15 empty unit slots + 15 empty Support slots to fill, and the King. The unit cards come from the selected
## continent (factions of that continent can be mixed freely); the King and the Support cards are not tied to a continent.
## Every unit type has 9 copies in the battle deck (15 x 9 = 135).

var _grid: HFlowContainer
var _detail: RichTextLabel
var _filter: String = "all"
var _selected_id: String = ""
var _views: Dictionary = {}

var deck: Deck
var _summary: RichTextLabel
var _save_btn: Button
var _message: Label
var _collection_view: Control
var _deck_view: Control
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	theme = UiTheme.get_theme()
	CardDatabase.set_continent(GameSession.continent_id)  # cards show the factions of the selected continent
	deck = SaveManager.get_deck(CardDatabase.active_continent)
	if deck.unit_ids.is_empty():
		deck.unit_ids = deck.effective_unit_ids()  # an untouched deck starts with the default 15 types (editable)
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
	for f in ["all", "pawn", "rook", "knight", "bishop", "queen", "king", "support"]:
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
	if _filter != "support" and _filter != "king":
		for u in CardDatabase.all_units():
			if _filter == "all" or u["chess"] == _filter:
				_add_card(u, false)
	if _filter == "all" or _filter == "king":
		for k in CardDatabase.all_kings():  # the King of every faction of the continent (Legendary)
			_add_card(k, false)
	if _filter == "all" or _filter == "support":
		for s in CardDatabase.all_supports():
			_add_card(s, true)


func _add_card(c: Dictionary, support: bool) -> void:
	var v := CardView.new()
	v.setup(c, support, 1 if CardDatabase.is_king(String(c["id"])) else SaveManager.owned_count(c["id"]))  # every King can be picked as Champion
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
	if CardDatabase.is_king(id):
		return _describe_king(id)
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
	return "[color=#d4af37][b]%s[/b][/color]\n%s %s - %s - %s\nCapacity cost: %d\nRange %d   Movement %d\n\n%s\n\n[b]%s:[/b] %s%s\n\nOwned copies: %d / %d" % [
		u["name"], "All factions" if CardDatabase.is_shared(u) else String(u["faction"]).capitalize(), String(u["chess"]).capitalize(), u["role"], String(u["rarity"]).capitalize(),
		CardDatabase.capacity_cost(u["chess"]), u["range"], u["move"], lines, u["skill"]["name"], u["skill"]["desc"], _buff_text(id), owned, int(GameData.b("unit_copies"))]



func _describe_king(id: String) -> String:
	var ch := GameData.get_champion(id)
	var fac := GameData.get_faction(CardDatabase.active_continent, String(ch.get("faction", "")))
	return "[color=#d4af37][b]%s[/b][/color]\n%s - King - %s\nCapacity cost: %d (enters only in Last Stand)\nHP %d (x%d in battle)   ATK %d\n\n[b]%s:[/b] %s\n[b]%s:[/b] %s\n\nPiece 8 of 8 of the %s faction." % [
		ch["name"], String(fac.get("name", ch.get("faction", ""))), String(ch.get("rarity", "legendary")).capitalize(), CardDatabase.capacity_cost("king"),
		int(ch["hp"]), int(GameData.b("champion_hp_mult")), int(ch["atk"]), ch["passive_name"], ch["passive_desc"], ch["active_name"], ch["active_desc"], String(fac.get("name", ""))]


## "Continent buff" paragraph of a unit card (every unit card has one buff on its continent).
func _buff_text(id: String) -> String:
	var bf := CardDatabase.get_buff(id)
	if bf.is_empty():
		return ""
	return "\n\n[color=#d4af37][b]Buff - %s:[/b][/color] %s" % [bf["name"], bf["desc"]]


func _show_tab(which: String) -> void:
	_collection_view.visible = (which == "collection")
	_deck_view.visible = (which == "deck")
	if _tab_buttons.has(which):
		_tab_buttons[which].set_pressed_no_signal(true)


# ------------------------------------------------------------------ deck editor

const UNIT_SLOTS := 15

var _deck_continent: String = ""
var _pool_tab: String = "units"  # units | supports | king
var _pool_faction: String = "all"
var _pool_cat: String = "Creation"
var _continent_row: HFlowContainer
var _king_btn: Button
var _unit_header: Label
var _support_header: Label
var _unit_slots_box: HFlowContainer
var _support_slots_box: HFlowContainer
var _pool_tabs: Dictionary = {}
var _pool_filter_row: HFlowContainer
var _pool_box: VBoxContainer
var _pool_buttons: Dictionary = {}  # card id -> Button (marks are updated in place so the list keeps its scroll position)


func _build_deck_view() -> Control:
	_deck_continent = CardDatabase.active_continent
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	# Continent of the unit cards
	_continent_row = HFlowContainer.new()
	_continent_row.add_theme_constant_override("h_separation", 6)
	col.add_child(_continent_row)
	var cgroup := ButtonGroup.new()
	for c in GameData.continents:
		var open: bool = c.get("playable", false) and SaveManager.is_continent_unlocked(c["id"])
		var cb := UiTheme.make_toggle(String(c["name"]) if open else "%s (locked)" % c["name"], cgroup, 44)
		cb.custom_minimum_size.x = 120
		cb.disabled = not open
		cb.button_pressed = (c["id"] == _deck_continent)
		cb.pressed.connect(_on_deck_continent.bind(String(c["id"])))
		_continent_row.add_child(cb)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)

	# Left: the slots
	var lpanel := PanelContainer.new()
	lpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(lpanel)
	var lscroll := UiTheme.make_scroll()
	lpanel.add_child(lscroll)
	var lbox := VBoxContainer.new()
	lbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbox.add_theme_constant_override("separation", 8)
	lscroll.add_child(lbox)
	lbox.add_child(UiTheme.make_label("KING  (any continent)", 20, UiTheme.COL_GOLD))
	_king_btn = UiTheme.make_button("", 64)
	_king_btn.pressed.connect(_set_pool_tab.bind("king"))
	UiTheme.scroll_passthrough(_king_btn)
	lbox.add_child(_king_btn)
	_unit_header = UiTheme.make_label("", 20, UiTheme.COL_GOLD)
	lbox.add_child(_unit_header)
	_unit_slots_box = HFlowContainer.new()
	_unit_slots_box.add_theme_constant_override("h_separation", 6)
	_unit_slots_box.add_theme_constant_override("v_separation", 6)
	lbox.add_child(_unit_slots_box)
	_support_header = UiTheme.make_label("", 20, UiTheme.COL_GOLD)
	lbox.add_child(_support_header)
	_support_slots_box = HFlowContainer.new()
	_support_slots_box.add_theme_constant_override("h_separation", 6)
	_support_slots_box.add_theme_constant_override("v_separation", 6)
	lbox.add_child(_support_slots_box)

	# Right: the card pool
	var rbox := VBoxContainer.new()
	rbox.custom_minimum_size = Vector2(440, 0)
	rbox.add_theme_constant_override("separation", 6)
	body.add_child(rbox)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	rbox.add_child(tabs)
	var tgroup := ButtonGroup.new()
	for spec in [["units", "Units"], ["supports", "Support"], ["king", "King"]]:
		var tb := UiTheme.make_toggle(spec[1], tgroup, 48)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.button_pressed = (spec[0] == _pool_tab)
		tb.pressed.connect(_set_pool_tab.bind(spec[0]))
		tabs.add_child(tb)
		_pool_tabs[spec[0]] = tb
	_pool_filter_row = HFlowContainer.new()
	_pool_filter_row.add_theme_constant_override("h_separation", 6)
	_pool_filter_row.add_theme_constant_override("v_separation", 6)
	rbox.add_child(_pool_filter_row)
	var ppanel := PanelContainer.new()
	ppanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rbox.add_child(ppanel)
	var pscroll := UiTheme.make_scroll()
	ppanel.add_child(pscroll)
	_pool_box = VBoxContainer.new()
	_pool_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pool_box.add_theme_constant_override("separation", 6)
	pscroll.add_child(_pool_box)

	# Footer: summary + Reset / Save
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	var sbox := VBoxContainer.new()
	sbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sbox)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.add_theme_font_size_override("normal_font_size", 16)
	sbox.add_child(_summary)
	_message = UiTheme.make_label("", 15, UiTheme.COL_DANGER)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sbox.add_child(_message)
	var reset := UiTheme.make_button("Reset to default", 56)
	reset.custom_minimum_size.x = 200
	reset.pressed.connect(_on_reset)
	foot.add_child(reset)
	_save_btn = UiTheme.make_primary("Save deck", 56)
	_save_btn.custom_minimum_size.x = 200
	_save_btn.pressed.connect(_on_save)
	foot.add_child(_save_btn)

	_rebuild_pool()
	_refresh()
	return col


func _say(text: String, ok: bool = false) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", UiTheme.COL_GOLD if ok else UiTheme.COL_DANGER)


## Problems that stop the deck from being saved (Deck.validate + the editor needs all 15 unit slots filled).
func _deck_errors() -> Array[String]:
	var errors := deck.validate(SaveManager.data["collection"])
	if deck.unit_ids.size() != UNIT_SLOTS and not errors.any(func(e): return String(e).begins_with("Unit cards")):
		errors.append("Unit cards: %d / %d." % [deck.unit_ids.size(), UNIT_SLOTS])
	return errors


func _faction_color(u: Dictionary) -> Color:
	var f := GameData.get_faction(_deck_continent, String(u.get("faction", "")))
	return Color(String(f.get("color", "#ffffff"))).lightened(0.35)


func _faction_name(faction_id: String) -> String:
	return String(GameData.get_faction(_deck_continent, faction_id).get("name", faction_id.capitalize()))


func _on_deck_continent(cid: String) -> void:
	if cid == _deck_continent:
		return
	_deck_continent = cid
	CardDatabase.set_continent(cid)
	var keep_king := deck.champion_id  # King and Supports are shared by every continent
	var keep_supports: Array[String] = deck.support_ids.duplicate()
	deck = SaveManager.get_deck(cid)
	deck.champion_id = keep_king
	deck.support_ids = keep_supports
	if deck.unit_ids.is_empty():
		deck.unit_ids = deck.effective_unit_ids()
	_pool_faction = "all"
	_selected_id = ""
	_rebuild()  # the Collection tab shows the factions of this continent too
	_rebuild_pool()
	_refresh()
	_say("")


func _set_pool_tab(which: String) -> void:
	_pool_tab = which
	if _pool_tabs.has(which):
		_pool_tabs[which].set_pressed_no_signal(true)
	_rebuild_pool()


func _slot_button() -> Button:
	var b := UiTheme.make_button("", 76)
	b.custom_minimum_size = Vector2(124, 76)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 13)
	UiTheme.scroll_passthrough(b)
	return b


func _rebuild_slots() -> void:
	for box in [_unit_slots_box, _support_slots_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	for i in range(UNIT_SLOTS):
		var b := _slot_button()
		if i < deck.unit_ids.size():
			var u := CardDatabase.get_unit(deck.unit_ids[i])
			b.text = "%s\n%s" % [u.get("name", "?"), String(u.get("chess", "")).capitalize()]
			b.add_theme_color_override("font_color", _faction_color(u))
			b.tooltip_text = "Tap to remove"
			b.pressed.connect(_remove_unit.bind(i))
		else:
			b.text = "+\nEmpty"
			b.modulate = Color(1, 1, 1, 0.55)
			b.pressed.connect(_set_pool_tab.bind("units"))
		_unit_slots_box.add_child(b)
	var need := int(GameData.b("deck_support"))
	for i in range(need):
		var b := _slot_button()
		if i < deck.support_ids.size():
			var s := CardDatabase.get_support(deck.support_ids[i])
			b.text = "%s\n%s" % [s.get("name", "?"), s.get("category", "")]
			b.add_theme_color_override("font_color", CardView.RARITY_COLORS.get(String(s.get("rarity", "common")), UiTheme.COL_TEXT).lightened(0.3))
			b.tooltip_text = String(s.get("description", ""))
			b.pressed.connect(_remove_support.bind(i))
		else:
			b.text = "+\nEmpty"
			b.modulate = Color(1, 1, 1, 0.55)
			b.pressed.connect(_set_pool_tab.bind("supports"))
		_support_slots_box.add_child(b)


func _rebuild_pool() -> void:
	for box in [_pool_filter_row, _pool_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_pool_buttons.clear()
	match _pool_tab:
		"units":
			_pool_units()
		"supports":
			_pool_supports()
		_:
			_pool_kings()
	_update_marks()


func _filter_chip(label: String, current: bool, on_press: Callable, group: ButtonGroup) -> void:
	var cb := UiTheme.make_toggle(label, group, 40)
	cb.button_pressed = current
	cb.pressed.connect(on_press)
	_pool_filter_row.add_child(cb)


func _pool_units() -> void:
	var group := ButtonGroup.new()
	_filter_chip("All", _pool_faction == "all", _on_pool_faction.bind("all"), group)
	for f in GameData.get_continent(_deck_continent).get("factions", []):
		_filter_chip(String(f["name"]), _pool_faction == String(f["id"]), _on_pool_faction.bind(String(f["id"])), group)
	for u in CardDatabase.all_units():
		if _pool_faction != "all" and String(u["faction"]) != _pool_faction:
			continue
		var b := UiTheme.make_button("%s\n%s %s  -  %s" % [u["name"], String(u["chess"]).capitalize(), u["role"], _faction_name(String(u["faction"]))], 60)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("base", b.text)
		b.pressed.connect(_toggle_unit.bind(String(u["id"])))
		UiTheme.scroll_passthrough(b)
		_pool_box.add_child(b)
		_pool_buttons[String(u["id"])] = b


func _on_pool_faction(fid: String) -> void:
	_pool_faction = fid
	_rebuild_pool()


func _pool_supports() -> void:
	var group := ButtonGroup.new()
	for cat in CardDatabase.SUPPORT_CATEGORIES:
		_filter_chip(String(cat), _pool_cat == cat, _on_pool_cat.bind(String(cat)), group)
	for s in CardDatabase.all_supports():
		if String(s["category"]) != _pool_cat:
			continue
		var owned := SaveManager.owned_count(String(s["id"])) > 0
		var b := UiTheme.make_button("%s  (%s)\n%s" % [s["name"], String(s["rarity"]).capitalize(), s["description"] if owned else "Locked - unlock it in the Shop"], 60)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.disabled = not owned
		b.set_meta("base", b.text)
		b.pressed.connect(_toggle_support.bind(String(s["id"])))
		UiTheme.scroll_passthrough(b)
		_pool_box.add_child(b)
		_pool_buttons[String(s["id"])] = b


func _on_pool_cat(cat: String) -> void:
	_pool_cat = cat
	_rebuild_pool()


func _pool_kings() -> void:
	for cont in GameData.continents:
		_pool_box.add_child(UiTheme.make_label(String(cont["name"]), 16, UiTheme.COL_MUTED))
		for f in cont.get("factions", []):
			var ch := GameData.get_champion(String(f.get("champion", "")))
			if ch.is_empty():
				continue
			var b := UiTheme.make_button("%s\n%s King  -  %s" % [ch["name"], f["name"], ch["passive_name"]], 60)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.tooltip_text = "%s: %s\n%s: %s" % [ch["passive_name"], ch["passive_desc"], ch["active_name"], ch["active_desc"]]
			b.set_meta("base", b.text)
			b.pressed.connect(_set_king.bind(String(f["champion"])))
			UiTheme.scroll_passthrough(b)
			_pool_box.add_child(b)
			_pool_buttons[String(f["champion"])] = b


## Marks the pool buttons that are in the deck (in place: the list keeps its scroll position).
func _update_marks() -> void:
	for id in _pool_buttons:
		var b: Button = _pool_buttons[id]
		var inside := false
		var tag := "IN DECK"
		match _pool_tab:
			"units":
				inside = deck.unit_ids.has(id)
			"supports":
				inside = deck.support_ids.has(id)
			_:
				inside = (id == deck.champion_id)
				tag = "SELECTED"
		b.text = String(b.get_meta("base")) + ("   [%s]" % tag if inside else "")
		if inside:
			b.add_theme_color_override("font_color", UiTheme.COL_GOLD)
		else:
			b.remove_theme_color_override("font_color")


func _toggle_unit(id: String) -> void:
	if deck.unit_ids.has(id):
		deck.unit_ids.erase(id)
	elif deck.unit_ids.size() >= UNIT_SLOTS:
		_say("All %d unit slots are full. Tap a filled slot to free it." % UNIT_SLOTS)
		return
	else:
		deck.unit_ids.append(id)
	_refresh()


func _remove_unit(index: int) -> void:
	if index >= 0 and index < deck.unit_ids.size():
		deck.unit_ids.remove_at(index)
	_refresh()


func _toggle_support(id: String) -> void:
	if deck.support_ids.has(id):
		deck.support_ids.erase(id)
	elif SaveManager.owned_count(id) < 1:
		_say("That card is locked.")
		return
	elif deck.support_ids.size() >= int(GameData.b("deck_support")):
		_say("Deck already has %d Support cards. Tap a filled slot to free it." % int(GameData.b("deck_support")))
		return
	else:
		deck.support_ids.append(id)
	_refresh()


func _remove_support(index: int) -> void:
	if index >= 0 and index < deck.support_ids.size():
		deck.support_ids.remove_at(index)
	_refresh()


func _set_king(id: String) -> void:
	deck.champion_id = id
	_refresh()


func _on_reset() -> void:
	var d := Deck.create_default()
	d.champion_id = deck.champion_id
	d.continent_id = _deck_continent
	d.unit_ids = d.effective_unit_ids()
	deck = d
	_refresh()
	_say("")


func _on_save() -> void:
	var errors := _deck_errors()
	if not errors.is_empty():
		_say("\n".join(errors))
		return
	SaveManager.set_deck(deck)
	_say("Deck saved for %s." % String(GameData.get_continent(_deck_continent).get("name", "")), true)


func _refresh() -> void:
	var errors := _deck_errors()
	_rebuild_slots()
	_update_marks()
	var ch := GameData.get_champion(deck.champion_id)
	var fac := GameData.get_faction(String(ch.get("continent", "")), String(ch.get("faction", "")))
	_king_btn.text = "%s\n%s King  -  %s" % [ch.get("name", "?"), fac.get("name", "?"), String(ch.get("rarity", "legendary")).capitalize()]
	_unit_header.text = "UNIT CARDS  %d / %d   (%s)" % [deck.unit_ids.size(), UNIT_SLOTS, String(GameData.get_continent(_deck_continent).get("name", ""))]
	_support_header.text = "SUPPORT CARDS  %d / %d" % [deck.support_ids.size(), int(GameData.b("deck_support"))]
	var total := deck.unit_ids.size() * int(GameData.b("unit_copies")) + 1 + deck.support_ids.size()
	_summary.text = "[color=#d4af37][b]Battle Deck[/b][/color]   King: %s   Units: %d types x %d   Support: %d / %d   Total: %d / %d" % [
		ch.get("name", "?"), deck.unit_ids.size(), int(GameData.b("unit_copies")), deck.support_ids.size(), int(GameData.b("deck_support")), total, int(GameData.b("deck_total"))]
	_save_btn.disabled = not errors.is_empty()
	if not errors.is_empty():
		_say("\n".join(errors))
	elif _message.text.begins_with("Unit cards") or _message.text.begins_with("Support cards") or _message.text.begins_with("Deck must"):
		_say("")
