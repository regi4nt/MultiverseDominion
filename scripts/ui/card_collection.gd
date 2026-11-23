extends Control
## Collection & Deck (one screen, two tabs).
## Collection tab: browse all unit and support cards, see star scaling and owned copies.
## Deck tab (Clash Royale style): your deck as a grid of card tiles on the left, the card collection on the right.
## Tap a collection card to add it (deck full: it is held, then tap a deck card to swap); tap a deck card to remove it.
## The unit cards come from the selected continent (its factions can be mixed freely); the King and the Support cards are not tied to a continent.
## Every unit type has 9 copies in the battle deck (15 x 9 = 135).

var _grid: HFlowContainer
var _detail: RichTextLabel
var _filter: String = "all"
var _selected_id: String = ""
var _views: Dictionary = {}

var deck: Deck
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
	var back_to := GameSession.collection_return if GameSession.collection_return != "" else "res://scenes/main_menu/main_menu.tscn"
	GameSession.collection_return = ""
	back.pressed.connect(func(): get_tree().change_scene_to_file(back_to))
	head.add_child(back)

	# Top-level tabs: Collection | Deck
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	root.add_child(modes)
	var mgroup := ButtonGroup.new()
	for spec in [["collection", "Collection"], ["deck", "Deck"]]:
		var mb := UiTheme.make_toggle(spec[1], mgroup, 52)
		mb.custom_minimum_size.x = 200
		mb.button_pressed = (spec[0] == ("deck" if GameSession.open_deck_tab else "collection"))
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
	if GameSession.open_deck_tab:
		_pool_tab = "king"  # coming from New Match ("Change faction"): show the faction list right away
	_deck_view = _build_deck_view()
	root.add_child(_deck_view)
	_show_tab("deck" if GameSession.open_deck_tab else "collection")
	GameSession.open_deck_tab = false
	_rebuild()


func _rebuild() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_views.clear()
	var entries: Array = []  # [card, is_support]
	var order: Array = _continents_active_first()
	if _filter != "support" and _filter != "king":
		var seen := {}  # the 8 Pawns exist on every continent: listed once (as the active continent's)
		for cid in order:
			for u in CardDatabase.units_of_continent(String(cid)):
				if seen.has(u["id"]):
					continue
				seen[u["id"]] = true
				if _filter == "all" or u["chess"] == _filter:
					entries.append([u, false])
	if _filter == "all" or _filter == "king":
		for cid in order:  # the King of every faction of every continent (Legendary); locked until the faction is open
			for f in GameData.get_continent(String(cid)).get("factions", []):
				var k := CardDatabase.king_card(String(f["champion"]))
				if not k.is_empty():
					entries.append([k, false])
	if _filter == "all" or _filter == "support":
		for s in CardDatabase.all_supports():
			entries.append([s, true])
	# owned cards first, locked / not owned ones at the bottom (order inside each group is kept)
	var owned_entries: Array = entries.filter(func(e): return _is_owned(e[0]))
	var locked_entries: Array = entries.filter(func(e): return not _is_owned(e[0]))
	for e in owned_entries + locked_entries:
		_add_card(e[0], e[1])


## The active continent first, then the others in their normal order (the collection shows every continent).
func _continents_active_first() -> Array:
	var out: Array = [CardDatabase.active_continent]
	for c in GameData.continents:
		if String(c["id"]) != CardDatabase.active_continent:
			out.append(String(c["id"]))
	return out


## A faction piece / King is only usable once its faction is open (its continent unlocked in Journey).
func _faction_open(c: Dictionary) -> bool:
	var id := String(c["id"])
	var fac := String(GameData.get_champion(id).get("faction", "")) if CardDatabase.is_king(id) else String(c.get("faction", ""))
	if fac == "" or fac == CardDatabase.SHARED:
		return true
	return SaveManager.can_use_faction(fac)


## Kings and unit pieces need their faction to be open; units and Support cards also need at least one copy.
func _is_owned(c: Dictionary) -> bool:
	var id := String(c["id"])
	if CardDatabase.is_king(id):
		return _faction_open(c)
	if not CardDatabase.is_support(id) and not _faction_open(c):
		return false
	return SaveManager.owned_count(id) > 0


func _lock_note(c: Dictionary) -> String:
	var id := String(c["id"])
	var fac := String(GameData.get_champion(id).get("faction", "")) if CardDatabase.is_king(id) else String(c.get("faction", ""))
	for cont in GameData.continents:
		for f in cont.get("factions", []):
			if String(f["id"]) == fac:
				return "\n\n[color=#ff7a7a]Locked - unlock %s in Journey to use this faction.[/color]" % cont["name"]
	return ""


func _add_card(c: Dictionary, support: bool) -> void:
	var v := CardView.new()
	var cnt := 0
	if _is_owned(c):
		cnt = 1 if CardDatabase.is_king(String(c["id"])) else SaveManager.owned_count(c["id"])  # a King is one card; 0 = drawn locked
	v.setup(c, support, cnt)
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
		var kc := CardDatabase.king_card(id)
		return _describe_king(id) + (_lock_note(kc) if not _is_owned(kc) else "")
	var owned := SaveManager.owned_count(id)
	if CardDatabase.is_support(id):
		var s := CardDatabase.get_support(id)
		return "[color=#d4af37][b]%s[/b][/color]\n%s - %s\nUses per battle: %d\n\n%s\n\n[color=#8d93ad]Effect '%s' is applied in battles (TODO Phase 4).[/color]\n\nOwned: %d" % [
			s["name"], s["category"], String(s["rarity"]).capitalize(), s["uses"], s["description"], s["effect"], owned]
	var u := CardDatabase.get_unit(id)
	var lock_note := ""
	if not CardDatabase.is_support(id) and not _faction_open(u):
		lock_note = _lock_note(u)
	var copies: Array = GameData.b("star_copies")
	var lines := ""
	for st in range(1, 4):
		var stt := CardDatabase.unit_stats(id, st)
		lines += "%d-star (%d cards): HP %d  ATK %d\n" % [st, copies[st - 1], stt["hp"], stt["atk"]]
	return "[color=#d4af37][b]%s[/b][/color]\n%s %s - %s - %s\nCapacity cost: %d\nRange %d   Movement %d\n\n%s\n\n[b]%s:[/b] %s%s\n\nOwned copies: %d / %d" % [
		u["name"], "All factions" if CardDatabase.is_shared(u) else String(u["faction"]).capitalize(), String(u["chess"]).capitalize(), u["role"], String(u["rarity"]).capitalize(),
		CardDatabase.capacity_cost(u["chess"]), u["range"], u["move"], lines, u["skill"]["name"], u["skill"]["desc"], _buff_text(id), owned if _faction_open(u) else 0, int(GameData.b("unit_copies"))] + lock_note



## King Buff paragraph: only works on the King's home continent (data/king_buffs.json).
func _king_buff_text(id: String) -> String:
	var out := ""
	var kp: Dictionary = GameData.king_passives.get(id, {})
	if not kp.is_empty():
		out += "\n[b]Battle Passive - %s:[/b] %s [color=#9aa0b5](every continent)[/color]" % [kp["name"], kp["desc"]]
	var kb := CardDatabase.king_buff(id, false)
	if not kb.is_empty():
		out += "\n[b]King Buff - %s:[/b] %s [color=#9aa0b5](home continent only)[/color]" % [kb["name"], kb["desc"]]
	return out


func _describe_king(id: String) -> String:
	var ch := GameData.get_champion(id)
	var fac := GameData.find_faction(String(ch.get("faction", "")))  # a King of any continent
	return "[color=#d4af37][b]%s[/b][/color]\n%s - King - %s\nCapacity cost: %d (enters only in Last Stand)\nHP %d (x%d in battle)   ATK %d\n\n[b]%s:[/b] %s\n[b]%s:[/b] %s%s\n\nPiece 8 of 8 of the %s faction." % [
		ch["name"], String(fac.get("name", ch.get("faction", ""))), String(ch.get("rarity", "legendary")).capitalize(), CardDatabase.capacity_cost("king"),
		int(ch["hp"]), int(GameData.b("champion_hp_mult")), int(ch["atk"]), ch["passive_name"], ch["passive_desc"], ch["active_name"], ch["active_desc"], _king_buff_text(id), String(fac.get("name", ""))]


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
		_tab_buttons[which].button_pressed = true


# ------------------------------------------------------------------ deck editor

const UNIT_SLOTS := 15
const SLOT_H := 70.0   # tile height in the deck grid
const TILE_H := 92.0   # tile height in the collection grid

var _deck_continent: String = ""
var _pool_tab: String = "units"  # units | supports | king
var _pool_faction: String = "all"
var _pool_cat: String = "Creation"
var _continent_row: HFlowContainer
var _pool_tabs: Dictionary = {}
var _pool_filter_row: HFlowContainer
var _pool_box: VBoxContainer
var _pool_buttons: Dictionary = {}  # card id -> CardView tile; marks update in place
var _deck_panel: PanelContainer
var _deck_header: Label
var _slot_grid: GridContainer
var _king_box: VBoxContainer
var _king_portrait: PortraitView
var _king_detail: RichTextLabel
var _pending: String = ""  # a collection card waiting to replace a card of the full deck
var _note: String = ""
var _note_ok: bool = false


func _build_deck_view() -> Control:
	_deck_continent = CardDatabase.active_continent
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)

	# Sections: the label of each tab is also its counter.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	var tgroup := ButtonGroup.new()
	for spec in [["units", "Units"], ["supports", "Support"], ["king", "Faction"]]:
		var tb := UiTheme.make_toggle(spec[1], tgroup, 48)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.button_pressed = (spec[0] == _pool_tab)
		tb.pressed.connect(_set_pool_tab.bind(spec[0]))
		tabs.add_child(tb)
		_pool_tabs[spec[0]] = tb

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)

	# Left: your deck as card tiles (3 x 5)
	_deck_panel = PanelContainer.new()
	_deck_panel.custom_minimum_size = Vector2(450, 0)
	body.add_child(_deck_panel)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 8)
	_deck_panel.add_child(lbox)
	_deck_header = UiTheme.make_label("", 18, UiTheme.COL_GOLD)
	lbox.add_child(_deck_header)
	_slot_grid = GridContainer.new()
	_slot_grid.columns = 3
	_slot_grid.add_theme_constant_override("h_separation", 6)
	_slot_grid.add_theme_constant_override("v_separation", 6)
	lbox.add_child(_slot_grid)
	# Faction tab: the chosen King and what it does
	_king_box = VBoxContainer.new()
	_king_box.add_theme_constant_override("separation", 8)
	lbox.add_child(_king_box)
	_king_portrait = PortraitView.new()
	_king_portrait.custom_minimum_size = Vector2(110, 128)
	_king_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_king_box.add_child(_king_portrait)
	var kscroll := UiTheme.make_scroll()
	kscroll.custom_minimum_size = Vector2(0, 236)
	_king_box.add_child(kscroll)
	_king_detail = RichTextLabel.new()
	_king_detail.bbcode_enabled = true
	_king_detail.fit_content = true
	_king_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for fs in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		_king_detail.add_theme_font_size_override(fs, 15)
	kscroll.add_child(_king_detail)

	# Right: the collection (filters + list)
	var rbox := VBoxContainer.new()
	rbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rbox.add_theme_constant_override("separation", 8)
	body.add_child(rbox)
	_continent_row = HFlowContainer.new()
	_continent_row.add_theme_constant_override("h_separation", 6)
	rbox.add_child(_continent_row)
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
	_pool_box.add_theme_constant_override("separation", 8)
	pscroll.add_child(_pool_box)

	# Footer: one status line + Reset / Save
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_message = UiTheme.make_label("", 16, UiTheme.COL_MUTED)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.clip_text = true
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_message)
	var reset := UiTheme.make_button("Reset", 56)
	reset.custom_minimum_size.x = 140
	reset.pressed.connect(_on_reset)
	foot.add_child(reset)
	_save_btn = UiTheme.make_primary("Save deck", 56)
	_save_btn.custom_minimum_size.x = 200
	_save_btn.pressed.connect(_on_save)
	foot.add_child(_save_btn)

	_rebuild_pool()
	_refresh()
	return col


## Shows a message in the footer until the next change to the deck.
func _say(text: String, ok: bool = false) -> void:
	_note = text
	_note_ok = ok
	_message.text = text
	_message.add_theme_color_override("font_color", UiTheme.COL_GOLD if ok else UiTheme.COL_DANGER)


## Problems that stop the deck from being saved (Deck.validate + the editor needs all 15 unit slots filled).
func _deck_errors() -> Array[String]:
	var errors := deck.validate(SaveManager.data["collection"])
	if deck.unit_ids.size() != UNIT_SLOTS and not errors.any(func(e): return String(e).begins_with("Unit cards")):
		errors.append("Unit cards: %d / %d." % [deck.unit_ids.size(), UNIT_SLOTS])
	return errors


func _faction_name(faction_id: String) -> String:
	return String(GameData.get_faction(_deck_continent, faction_id).get("name", faction_id.capitalize()))


## The card list of the current section (units or supports).
func _section_ids() -> Array[String]:
	return deck.unit_ids if _pool_tab == "units" else deck.support_ids


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
	_pending = ""
	_note = ""
	_rebuild()  # the Collection tab shows the factions of this continent too
	_rebuild_pool()
	_refresh()


func _set_pool_tab(which: String) -> void:
	_pool_tab = which
	_pending = ""
	if _pool_tabs.has(which):
		_pool_tabs[which].button_pressed = true
	_rebuild_pool()
	_refresh()


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _rebuild_pool() -> void:
	_clear(_continent_row)
	_clear(_pool_filter_row)
	_clear(_pool_box)
	_pool_buttons.clear()
	_continent_row.visible = false
	match _pool_tab:
		"units":
			_pool_continents()
			_pool_units()
		"supports":
			_pool_supports()
		_:
			_pool_kings()
	_pool_filter_row.visible = _pool_filter_row.get_child_count() > 0
	_update_marks()


func _filter_chip(parent: Control, label: String, current: bool, on_press: Callable, group: ButtonGroup) -> void:
	var cb := UiTheme.make_toggle(label, group, 44)
	cb.button_pressed = current
	cb.pressed.connect(on_press)
	parent.add_child(cb)


func _new_grid(parent: Control, columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	parent.add_child(g)
	return g


## Continent of the unit cards: only shown once a second continent is open.
func _pool_continents() -> void:
	var open: Array = GameData.continents.filter(func(c): return c.get("playable", false) and SaveManager.is_continent_unlocked(c["id"]))
	if open.size() < 2:
		return
	_continent_row.visible = true
	var group := ButtonGroup.new()
	for c in open:
		_filter_chip(_continent_row, String(c["name"]), c["id"] == _deck_continent, _on_deck_continent.bind(String(c["id"])), group)


func _pool_units() -> void:
	var group := ButtonGroup.new()
	_filter_chip(_pool_filter_row, "All", _pool_faction == "all", _on_pool_faction.bind("all"), group)
	for f in GameData.get_continent(_deck_continent).get("factions", []):
		_filter_chip(_pool_filter_row, String(f["name"]), _pool_faction == String(f["id"]), _on_pool_faction.bind(String(f["id"])), group)
	var grid := _new_grid(_pool_box, 5)
	var units: Array = CardDatabase.all_units().filter(func(u): return _pool_faction == "all" or String(u["faction"]) == _pool_faction)
	units = units.filter(func(u): return _is_owned(u)) + units.filter(func(u): return not _is_owned(u))  # owned first
	for u in units:
		var v := CardView.new()
		v.setup_compact(u, false, SaveManager.owned_count(String(u["id"])), TILE_H)
		v.tooltip_text = "%s  (%s)\n%s: %s" % [u["name"], _faction_name(String(u["faction"])), u["skill"]["name"], u["skill"]["desc"]]
		v.pressed.connect(_toggle_unit)
		grid.add_child(v)
		_pool_buttons[String(u["id"])] = v


func _on_pool_faction(fid: String) -> void:
	_pool_faction = fid
	_rebuild_pool()


func _pool_supports() -> void:
	var group := ButtonGroup.new()
	for cat in CardDatabase.SUPPORT_CATEGORIES:
		_filter_chip(_pool_filter_row, String(cat), _pool_cat == cat, _on_pool_cat.bind(String(cat)), group)
	var grid := _new_grid(_pool_box, 5)
	var sups: Array = CardDatabase.all_supports().filter(func(x): return String(x["category"]) == _pool_cat)
	sups = sups.filter(func(x): return _is_owned(x)) + sups.filter(func(x): return not _is_owned(x))  # owned first
	for s in sups:
		var v := CardView.new()
		v.setup_compact(s, true, SaveManager.owned_count(String(s["id"])), TILE_H)
		v.tooltip_text = "%s  (%s)\n%s" % [s["name"], String(s["rarity"]).capitalize(), s["description"]]
		v.pressed.connect(_toggle_support)
		grid.add_child(v)
		_pool_buttons[String(s["id"])] = v


func _on_pool_cat(cat: String) -> void:
	_pool_cat = cat
	_rebuild_pool()


func _pool_kings() -> void:
	var hint := UiTheme.make_label("Your faction decides your King in every match. Locked factions open with their continent (Journey).", 15, UiTheme.COL_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pool_box.add_child(hint)
	var conts: Array = GameData.continents.filter(func(c): return SaveManager.is_continent_unlocked(String(c["id"])))
	conts += GameData.continents.filter(func(c): return not SaveManager.is_continent_unlocked(String(c["id"])))  # open continents first
	for cont in conts:
		var cont_open: bool = SaveManager.is_continent_unlocked(String(cont["id"]))
		_pool_box.add_child(UiTheme.make_label(String(cont["name"]) if cont_open else "%s  (locked)" % cont["name"], 17, UiTheme.COL_GOLD if cont_open else UiTheme.COL_MUTED))
		var grid := _new_grid(_pool_box, 5)
		var facs: Array = cont.get("factions", [])
		facs = facs.filter(func(f): return SaveManager.can_use_faction(String(f["id"]))) + facs.filter(func(f): return not SaveManager.can_use_faction(String(f["id"])))
		for f in facs:
			var champ_id := String(f.get("champion", ""))
			var ch := GameData.get_champion(champ_id)
			if ch.is_empty():
				continue
			var open := SaveManager.can_use_faction(String(f["id"]))
			var tile := {"id": champ_id, "name": String(f["name"]), "rarity": String(ch.get("rarity", "legendary")), "chess": "king", "faction": String(f["id"]),
				"continent": String(cont["id"]), "color": String(f.get("color", "#555566")), "sub": String(ch["name"]), "badge": false}
			var v := CardView.new()
			v.setup_compact(tile, false, 1 if open else 0, TILE_H)
			v.tooltip_text = ("%s: %s\n%s: %s" % [ch["passive_name"], ch["passive_desc"], ch["active_name"], ch["active_desc"]]) if open else "Locked - unlock %s in Journey" % cont["name"]
			v.pressed.connect(_set_king)
			grid.add_child(v)
			_pool_buttons[champ_id] = v


## Your deck as tiles: filled slots first, then empty ones. While a card is held (full deck) the filled slots light up.
func _rebuild_slots() -> void:
	_clear(_slot_grid)
	_slot_grid.visible = (_pool_tab != "king")
	_king_box.visible = (_pool_tab == "king")
	if _pool_tab == "king":
		_deck_header.text = "YOUR KING"
		_king_portrait.setup(deck.champion_id)
		_king_detail.text = _describe_king(deck.champion_id)
		return
	var units := (_pool_tab == "units")
	var ids := _section_ids()
	var total := UNIT_SLOTS if units else int(GameData.b("deck_support"))
	for i in range(total):
		var v := CardView.new()
		if i < ids.size():
			var id := String(ids[i])
			var c := CardDatabase.get_unit(id) if units else CardDatabase.get_support(id)
			v.setup_compact(c, not units, SaveManager.owned_count(id), SLOT_H)
			v.tooltip_text = String(c.get("name", "")) if units else "%s\n%s" % [c.get("name", ""), c.get("description", "")]
			v.selected = (_pending != "")
		else:
			v.setup_empty(SLOT_H)
		v.pressed.connect(_on_slot.bind(i))
		_slot_grid.add_child(v)
	if units:
		var sum := 0
		for id in ids:
			sum += CardDatabase.capacity_cost(String(CardDatabase.get_unit(id).get("chess", "pawn")))
		_deck_header.text = "YOUR DECK   avg cost %.1f" % (float(sum) / ids.size() if ids.size() > 0 else 0.0)
	else:
		_deck_header.text = "YOUR SUPPORT CARDS"


## Marks the collection cards that are already in the deck (dimmed) and the held one (gold), in place.
func _update_marks() -> void:
	for id in _pool_buttons:
		var v := _pool_buttons[id] as CardView
		if _pool_tab == "king":
			v.set_state(false, id == deck.champion_id)
		else:
			v.set_state(_section_ids().has(id), id == _pending)


## Tap a collection card: in the deck -> remove; free slot -> add; deck full -> hold it, then tap a deck card to swap.
func _toggle_unit(id: String) -> void:
	if deck.unit_ids.has(id):
		deck.unit_ids.erase(id)
	elif deck.unit_ids.size() >= UNIT_SLOTS:
		_pending = id
		_say("Deck is full. Tap a card in your deck to swap it out.", true)
		_update_marks()
		_rebuild_slots()
		return
	else:
		deck.unit_ids.append(id)
	_pending = ""
	_note = ""
	_refresh()


func _toggle_support(id: String) -> void:
	var need := int(GameData.b("deck_support"))
	if deck.support_ids.has(id):
		deck.support_ids.erase(id)
	elif SaveManager.owned_count(id) < 1:
		_say("That card is locked.")
		return
	elif deck.support_ids.size() >= need:
		_pending = id
		_say("Deck is full. Tap a card in your deck to swap it out.", true)
		_update_marks()
		_rebuild_slots()
		return
	else:
		deck.support_ids.append(id)
	_pending = ""
	_note = ""
	_refresh()


## Tap a deck tile: swap in the held card, otherwise remove the card.
func _on_slot(_card_id: String, index: int) -> void:
	var ids := _section_ids()
	if index >= ids.size():
		_say("Tap a card on the right to add it.", true)
		return
	if _pending != "":
		ids[index] = _pending
	else:
		ids.remove_at(index)
	_pending = ""
	_note = ""
	_refresh()


func _set_king(id: String) -> void:
	if not SaveManager.can_use_faction(String(GameData.get_champion(id).get("faction", ""))):
		_say("That faction is locked. Win its continent in Journey to unlock it.")
		return
	deck.champion_id = id
	_note = ""
	_refresh()


func _on_reset() -> void:
	var d := Deck.create_default()
	d.champion_id = deck.champion_id
	d.continent_id = _deck_continent
	d.unit_ids = d.effective_unit_ids()
	deck = d
	_pending = ""
	_note = ""
	_refresh()


func _on_save() -> void:
	var errors := _deck_errors()
	if not errors.is_empty():
		_say(String(errors[0]))
		return
	SaveManager.set_deck(deck)
	_refresh()
	_say("Deck saved for %s." % String(GameData.get_continent(_deck_continent).get("name", "")), true)


func _refresh() -> void:
	var errors := _deck_errors()
	_rebuild_slots()
	_update_marks()
	var ch := GameData.get_champion(deck.champion_id)
	var fac := GameData.get_faction(String(ch.get("continent", "")), String(ch.get("faction", "")))
	_pool_tabs["king"].text = "Faction  -  %s" % fac.get("name", "?")
	_pool_tabs["units"].text = "Units  %d / %d" % [deck.unit_ids.size(), UNIT_SLOTS]
	_pool_tabs["supports"].text = "Support  %d / %d" % [deck.support_ids.size(), int(GameData.b("deck_support"))]
	_save_btn.disabled = not errors.is_empty()
	if not errors.is_empty():
		_message.text = String(errors[0])
		_message.add_theme_color_override("font_color", UiTheme.COL_DANGER)
	elif _note != "":
		_message.text = _note
		_message.add_theme_color_override("font_color", UiTheme.COL_GOLD if _note_ok else UiTheme.COL_DANGER)
	else:
		_message.text = "Battle deck: %d cards. Tap a card to add or remove it." % (deck.unit_ids.size() * int(GameData.b("unit_copies")) + 1 + deck.support_ids.size())
		_message.add_theme_color_override("font_color", UiTheme.COL_MUTED)
