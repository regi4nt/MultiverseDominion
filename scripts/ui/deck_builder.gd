extends Control
## Deck Builder. The 135 unit cards are fixed (15 types x 9). The player chooses the Champion
## and exactly 15 Support cards out of the owned ones. TODO: more unit variants to choose from.

var deck: Deck
var _support_buttons: Dictionary = {}
var _champion_buttons: Dictionary = {}
var _summary: RichTextLabel
var _save_btn: Button
var _message: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	deck = SaveManager.get_deck()
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := UiTheme.make_label("DECK BUILDER", 36, UiTheme.COL_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := UiTheme.make_button("Back", 48)
	back.custom_minimum_size.x = 140
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	head.add_child(back)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	# Champions
	var cpanel := PanelContainer.new()
	cpanel.custom_minimum_size = Vector2(280, 0)
	body.add_child(cpanel)
	var cscroll := ScrollContainer.new()
	cscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
		cbox.add_child(b)
		_champion_buttons[cid] = b

	# Supports
	var spanel := PanelContainer.new()
	spanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(spanel)
	var sscroll := ScrollContainer.new()
	sscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
