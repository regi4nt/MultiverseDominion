extends Control
## Shop (one screen, two tabs). Gacha: pull Support cards with Aether Coins (duplicates turn into Card Fragments, pity timer).
## Cards: buy any locked Support card with coins, or exchange Card Fragments for it (rarer = more fragments). Coins are earned by playing matches (see SaveManager.record_match).

var _coin_label: Label
var _frag_label: Label
var _gacha_view: Control
var _buy_view: Control
var _tab_buttons: Dictionary = {}
var _rng := RandomNumberGenerator.new()

var _pull1: Button
var _pull10: Button
var _pity_label: Label
var _result_flow: HFlowContainer
var _result_text: RichTextLabel

var _buy_filter: String = "all"
var _buy_grid: HFlowContainer
var _buy_detail: RichTextLabel
var _buy_btn: Button
var _frag_btn: Button
var _buy_msg: Label
var _selected_id: String = ""
var _views: Dictionary = {}


func _ready() -> void:
	theme = UiTheme.get_theme()
	_rng.randomize()
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	var title := UiTheme.make_label("SHOP", 36, UiTheme.COL_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_coin_label = UiTheme.make_label("", 26, UiTheme.COL_GOLD)
	head.add_child(_coin_label)
	_frag_label = UiTheme.make_label("", 26, Color("a98be0"))
	head.add_child(_frag_label)
	var back := UiTheme.make_button("Back", 48)
	back.custom_minimum_size.x = 140
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	head.add_child(back)

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	root.add_child(modes)
	var group := ButtonGroup.new()
	for spec in [["gacha", "Gacha"], ["cards", "Buy Cards"]]:
		var mb := UiTheme.make_toggle(spec[1], group, 52)
		mb.custom_minimum_size.x = 200
		mb.button_pressed = (spec[0] == "gacha")
		mb.pressed.connect(_show_tab.bind(spec[0]))
		modes.add_child(mb)
		_tab_buttons[spec[0]] = mb

	_gacha_view = _build_gacha()
	root.add_child(_gacha_view)
	_buy_view = _build_buy()
	root.add_child(_buy_view)
	_show_tab("gacha")
	_refresh()


func _show_tab(which: String) -> void:
	_gacha_view.visible = (which == "gacha")
	_buy_view.visible = (which == "cards")
	if _tab_buttons.has(which):
		_tab_buttons[which].set_pressed_no_signal(true)
	if which == "cards":
		_rebuild_buy()


# ------------------------------------------------------------------ gacha

func _build_gacha() -> Control:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)

	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	body.add_child(left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 10)
	left.add_child(lbox)
	lbox.add_child(UiTheme.make_label("SUPPORT GACHA", 26, UiTheme.COL_GOLD))
	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.add_theme_font_size_override("normal_font_size", 17)
	info.text = "Pull Support cards you do not own yet.\n[color=#8d93ad]Common %d%%   Rare %d%%\nEpic %d%%   Legendary %d%%[/color]\nA duplicate turns into Card Fragments (Common %d, Rare %d, Epic %d, Legendary %d).\nExchange fragments for a locked card in Buy Cards: the rarer the card, the more it costs.\nThe 10-pull always holds at least one Rare." % [
		ShopSystem.RATES["common"], ShopSystem.RATES["rare"], ShopSystem.RATES["epic"], ShopSystem.RATES["legendary"],
		ShopSystem.DUPLICATE_FRAGMENTS["common"], ShopSystem.DUPLICATE_FRAGMENTS["rare"], ShopSystem.DUPLICATE_FRAGMENTS["epic"], ShopSystem.DUPLICATE_FRAGMENTS["legendary"]]
	lbox.add_child(info)
	_pity_label = UiTheme.make_label("", 17, UiTheme.COL_MUTED)
	_pity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbox.add_child(_pity_label)
	_pull1 = UiTheme.make_primary("Pull x1  (%d)" % ShopSystem.PULL_PRICE, 64)
	_pull1.pressed.connect(_on_pull.bind(1))
	lbox.add_child(_pull1)
	_pull10 = UiTheme.make_primary("Pull x10  (%d)" % ShopSystem.PULL10_PRICE, 64)
	_pull10.pressed.connect(_on_pull.bind(10))
	lbox.add_child(_pull10)

	var rpanel := PanelContainer.new()
	rpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rpanel)
	var rscroll := UiTheme.make_scroll()
	rpanel.add_child(rscroll)
	var rbox := VBoxContainer.new()
	rbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rbox.add_theme_constant_override("separation", 8)
	rscroll.add_child(rbox)
	_result_text = RichTextLabel.new()
	_result_text.bbcode_enabled = true
	_result_text.fit_content = true
	_result_text.add_theme_font_size_override("normal_font_size", 18)
	_result_text.text = "[color=#8d93ad]Your pulls appear here.[/color]"
	rbox.add_child(_result_text)
	_result_flow = HFlowContainer.new()
	_result_flow.add_theme_constant_override("h_separation", 10)
	_result_flow.add_theme_constant_override("v_separation", 10)
	rbox.add_child(_result_flow)
	return body


func _on_pull(count: int) -> void:
	var results := ShopSystem.pull_batch(count, _rng)
	if results.is_empty():
		_result_text.text = "[color=#e0705f]Not enough Aether Coins.[/color]"
		return
	for c in _result_flow.get_children():
		_result_flow.remove_child(c)
		c.queue_free()
	var new_n := 0
	var frags := 0
	var lines := ""
	for r in results:
		var card := CardDatabase.get_support(String(r["id"]))
		var v := CardView.new()
		v.setup(card, true, 1)
		_result_flow.add_child(v)
		if bool(r["new"]):
			new_n += 1
			lines += "[color=#59cd90]NEW[/color]  %s [color=#8d93ad](%s)[/color]\n" % [card["name"], String(r["rarity"]).capitalize()]
		else:
			frags += int(r["fragments"])
			lines += "[color=#a98be0]Duplicate[/color]  %s  [color=#a98be0]+%d fragments[/color]\n" % [card["name"], int(r["fragments"])]
	_result_text.text = "[color=#d4af37][b]%d new card%s[/b][/color]   [color=#a98be0]duplicates +%d fragments[/color]\n%s" % [new_n, "" if new_n == 1 else "s", frags, lines]
	_refresh()


# ------------------------------------------------------------------ buy cards

func _build_buy() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	col.add_child(tabs)
	var group := ButtonGroup.new()
	var cats: Array = ["all"]
	cats.append_array(CardDatabase.SUPPORT_CATEGORIES)
	for f in cats:
		var b := UiTheme.make_toggle(String(f).capitalize(), group, 44)
		b.custom_minimum_size.x = 110
		b.button_pressed = (f == _buy_filter)
		b.pressed.connect(func():
			_buy_filter = String(f)
			_rebuild_buy())
		tabs.add_child(b)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)
	var scroll := UiTheme.make_scroll()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_buy_grid = HFlowContainer.new()
	_buy_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_grid.add_theme_constant_override("h_separation", 10)
	_buy_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_buy_grid)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	body.add_child(panel)
	var pbox := VBoxContainer.new()
	pbox.add_theme_constant_override("separation", 8)
	panel.add_child(pbox)
	_buy_detail = RichTextLabel.new()
	_buy_detail.bbcode_enabled = true
	_buy_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_buy_detail.add_theme_font_size_override("normal_font_size", 17)
	pbox.add_child(_buy_detail)
	_buy_msg = UiTheme.make_label("", 15, UiTheme.COL_DANGER)
	_buy_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pbox.add_child(_buy_msg)
	_buy_btn = UiTheme.make_primary("Buy", 60)
	_buy_btn.pressed.connect(_on_buy)
	pbox.add_child(_buy_btn)
	_frag_btn = UiTheme.make_button("Exchange fragments", 60)
	_frag_btn.add_theme_color_override("font_color", Color("cdb8ff"))
	_frag_btn.pressed.connect(_on_exchange)
	pbox.add_child(_frag_btn)
	return col


func _rebuild_buy() -> void:
	for c in _buy_grid.get_children():
		_buy_grid.remove_child(c)
		c.queue_free()
	_views.clear()
	var list := ShopSystem.locked_supports(_buy_filter)
	var still_listed := false
	for s in list:
		var v := CardView.new()
		v.setup(s, true, 0)
		v.pressed.connect(_on_card)
		v.set_selected(String(s["id"]) == _selected_id)
		_buy_grid.add_child(v)
		_views[String(s["id"])] = v
		still_listed = still_listed or String(s["id"]) == _selected_id
	if not still_listed:
		_selected_id = ""
	_refresh_buy_detail()


func _on_card(id: String) -> void:
	if _views.has(_selected_id):
		_views[_selected_id].set_selected(false)
	_selected_id = id
	_views[id].set_selected(true)
	_buy_msg.text = ""
	_refresh_buy_detail()


func _refresh_buy_detail() -> void:
	if _selected_id == "":
		_buy_detail.text = "Tap a locked card to see its details and price.\n\n[color=#8d93ad]%d Support card%s still locked in this view.[/color]" % [
			_views.size(), "" if _views.size() == 1 else "s"] if not _views.is_empty() else "[color=#59cd90]Every Support card of this category is unlocked.[/color]"
		_buy_btn.disabled = true
		_buy_btn.text = "Buy"
		_frag_btn.disabled = true
		_frag_btn.text = "Exchange fragments"
		return
	var s := CardDatabase.get_support(_selected_id)
	var price := ShopSystem.buy_price(s)
	_buy_detail.text = "[color=#d4af37][b]%s[/b][/color]\n%s - %s\nUses per battle: %d\n\n%s\n\nPrice: %d coins\nor %d fragments" % [
		s["name"], s["category"], String(s["rarity"]).capitalize(), int(s["uses"]), s["description"], price, ShopSystem.fragment_price(s)]
	_buy_btn.text = "Buy  (%d coins)" % price
	_buy_btn.disabled = SaveManager.coins() < price
	_frag_btn.text = "Exchange  (%d fragments)" % ShopSystem.fragment_price(s)
	_frag_btn.disabled = SaveManager.fragments() < ShopSystem.fragment_price(s)


func _on_buy() -> void:
	_unlock_selected(ShopSystem.buy(_selected_id) if _selected_id != "" else "-")


func _on_exchange() -> void:
	_unlock_selected(ShopSystem.exchange(_selected_id) if _selected_id != "" else "-")


## Shared end of a purchase / exchange: `err` is "" on success, "-" when nothing is selected.
func _unlock_selected(err: String) -> void:
	if err == "-":
		return
	if err != "":
		_buy_msg.text = err
		return
	var bought := String(CardDatabase.get_support(_selected_id)["name"])
	_selected_id = ""
	_rebuild_buy()
	_buy_msg.text = ""
	_buy_detail.text = "[color=#59cd90]%s unlocked![/color]\n\n%s" % [bought, _buy_detail.text]
	_refresh()


func _refresh() -> void:
	var coins := SaveManager.coins()
	_coin_label.text = "%d coins" % coins
	_frag_label.text = "%d fragments" % SaveManager.fragments()
	_pull1.disabled = coins < ShopSystem.PULL_PRICE
	_pull10.disabled = coins < ShopSystem.PULL10_PRICE
	_pity_label.text = "Epic or better is guaranteed within %d pull%s.\nWin a match +%d coins, lose +%d." % [
		ShopSystem.pulls_to_pity(), "" if ShopSystem.pulls_to_pity() == 1 else "s", ShopSystem.WIN_REWARD, ShopSystem.LOSS_REWARD]
	if _buy_btn != null and _selected_id != "":
		var sel := CardDatabase.get_support(_selected_id)
		_buy_btn.disabled = coins < ShopSystem.buy_price(sel)
		_frag_btn.disabled = SaveManager.fragments() < ShopSystem.fragment_price(sel)
