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
var _pity_bar: ProgressBar
var _result_flow: HFlowContainer
var _result_banner: Label
var _stage: PanelContainer

const RARITY_TITLES := {"common": "", "rare": "RARE PULL", "epic": "EPIC PULL!", "legendary": "LEGENDARY!!"}
const RARITY_SFX := {"common": "click", "rare": "coin", "epic": "magic", "legendary": "victory"}


## Face-down card shown before the first pull.
class CardBack extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(110, 150)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color("1c2548"))
		draw_rect(r, Color(UiTheme.COL_GOLD_DIM, 0.8), false, 2.0)
		draw_rect(r.grow(-8), Color(UiTheme.COL_GOLD_DIM, 0.35), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.5 + 18.0), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 52, Color(UiTheme.COL_GOLD, 0.55))

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

	# Left: short info + pity bar + pull buttons.
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(340, 0)
	body.add_child(left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 10)
	left.add_child(lbox)
	lbox.add_child(UiTheme.make_label("SUPPORT GACHA", 26, UiTheme.COL_GOLD))
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	lbox.add_child(chips)
	for r in ShopSystem.RARITY_ORDER:
		var c := UiTheme.rarity_color(r)
		var chip := UiTheme.make_label("%s %d%%" % [String(r).capitalize(), ShopSystem.RATES[r]], 16, c.lightened(0.35))
		var sb := UiTheme.make_box(Color(c, 0.16), c, 2, 8)
		sb.set_content_margin_all(5)
		chip.add_theme_stylebox_override("normal", sb)
		chips.add_child(chip)
	var info := UiTheme.make_label("Duplicates become fragments. The 10-pull always holds a Rare.", 15, UiTheme.COL_MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbox.add_child(info)
	_pity_bar = ProgressBar.new()
	_pity_bar.max_value = ShopSystem.PITY_LIMIT
	_pity_bar.show_percentage = false
	_pity_bar.custom_minimum_size = Vector2(0, 14)
	var fill := UiTheme.make_box(Color("a65cf0"), Color("a65cf0"), 0, 7)
	var bg := UiTheme.make_box(Color("111629"), Color("2e3350"), 1, 7)
	_pity_bar.add_theme_stylebox_override("fill", fill)
	_pity_bar.add_theme_stylebox_override("background", bg)
	lbox.add_child(_pity_bar)
	_pity_label = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
	_pity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbox.add_child(_pity_label)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbox.add_child(sp)
	_pull1 = UiTheme.make_button("Pull x1  (%d)" % ShopSystem.PULL_PRICE, 60)
	_pull1.pressed.connect(_on_pull.bind(1))
	lbox.add_child(_pull1)
	_pull10 = UiTheme.make_primary("Pull x10  (%d)" % ShopSystem.PULL10_PRICE, 72)
	_pull10.pressed.connect(_on_pull.bind(10))
	lbox.add_child(_pull10)

	# Right: the "stage" where pulled cards are revealed one by one.
	_stage = PanelContainer.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_stage_color(UiTheme.COL_GOLD_DIM)
	body.add_child(_stage)
	var rscroll := UiTheme.make_scroll()
	_stage.add_child(rscroll)
	var rbox := VBoxContainer.new()
	rbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rbox.add_theme_constant_override("separation", 10)
	rscroll.add_child(rbox)
	_result_banner = UiTheme.make_label("", 28, UiTheme.COL_GOLD)
	_result_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_banner.resized.connect(func(): _result_banner.pivot_offset = _result_banner.size * 0.5)
	rbox.add_child(_result_banner)
	_result_flow = HFlowContainer.new()
	_result_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_result_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_flow.add_theme_constant_override("h_separation", 12)
	_result_flow.add_theme_constant_override("v_separation", 12)
	rbox.add_child(_result_flow)
	_show_idle()
	return body


func _set_stage_color(c: Color) -> void:
	_stage.add_theme_stylebox_override("panel", UiTheme.make_box(Color(c.darkened(0.8), 0.95), c, 2, 14))


func _clear_results() -> void:
	for c in _result_flow.get_children():
		_result_flow.remove_child(c)
		c.queue_free()


func _show_idle() -> void:
	_clear_results()
	_set_stage_color(UiTheme.COL_GOLD_DIM)
	_result_banner.text = "Pull to reveal cards"
	_result_banner.add_theme_color_override("font_color", UiTheme.COL_MUTED)
	for i in range(5):
		var back := CardBack.new()
		back.rotation_degrees = (i - 2) * 3.0  # a loose fan instead of a flat row
		_result_flow.add_child(back)


func _on_pull(count: int) -> void:
	var results := ShopSystem.pull_batch(count, _rng)
	if results.is_empty():
		Sfx.play("error")
		_clear_results()
		_result_banner.text = "Not enough Aether Coins."
		_result_banner.add_theme_color_override("font_color", UiTheme.COL_DANGER)
		return
	_clear_results()
	var best := 0
	var new_n := 0
	var frags := 0
	for i in range(results.size()):
		var r: Dictionary = results[i]
		var rarity := String(r["rarity"])
		best = maxi(best, ShopSystem.RARITY_ORDER.find(rarity))
		if bool(r["new"]):
			new_n += 1
		else:
			frags += int(r["fragments"])
		var slot := _make_slot(r)
		_result_flow.add_child(slot)
		_reveal(slot, i, rarity)
	var best_r: String = ShopSystem.RARITY_ORDER[best]
	var col := UiTheme.rarity_color(best_r)
	_set_stage_color(col)
	var title: String = RARITY_TITLES[best_r]
	var total_delay := 0.11 * results.size()
	_result_banner.text = "%s%d new  |  +%d fragments" % [title + "   " if title != "" else "", new_n, frags]
	_result_banner.add_theme_color_override("font_color", col.lightened(0.4))
	_result_banner.modulate.a = 0.0
	var bt := _result_banner.create_tween()
	bt.tween_interval(total_delay)  # the summary lands after the last card
	bt.tween_property(_result_banner, "modulate:a", 1.0, 0.2)
	if best >= 2:
		bt.tween_callback(func(): _result_banner.scale = Vector2(1.15, 1.15))
		bt.tween_property(_result_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh()


## One pulled card with a rarity-glow frame and a NEW / +fragments tag.
func _make_slot(r: Dictionary) -> Control:
	var rarity := String(r["rarity"])
	var col := UiTheme.rarity_color(rarity)
	var rank := ShopSystem.RARITY_ORDER.find(rarity)
	var frame := PanelContainer.new()
	var sb := UiTheme.make_box(Color(col.darkened(0.75), 0.9), col, 2 + rank, 12, 0)
	sb.set_content_margin_all(6)
	if rank >= 1:  # Rare and up glow in their own colour, stronger the rarer
		sb.shadow_color = Color(col, 0.35 + 0.15 * rank)
		sb.shadow_size = 6 + 6 * rank
		sb.shadow_offset = Vector2.ZERO
	frame.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	frame.add_child(v)
	var cv := CardView.new()
	cv.setup(CardDatabase.get_support(String(r["id"])), true, 1)
	v.add_child(cv)
	var tag := UiTheme.make_label("NEW" if bool(r["new"]) else "+%d fragments" % int(r["fragments"]), 16,
		Color("59cd90") if bool(r["new"]) else Color("a98be0"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)
	return frame


func _reveal(slot: Control, index: int, rarity: String) -> void:
	slot.modulate.a = 0.0
	slot.scale = Vector2(0.4, 0.4)
	slot.resized.connect(func(): slot.pivot_offset = slot.size * 0.5)
	var delay := 0.11 * index
	var t := slot.create_tween().set_parallel(true)  # bound to the slot: a new pull frees it and kills the tween
	t.tween_property(slot, "modulate:a", 1.0, 0.18).set_delay(delay)
	t.tween_property(slot, "scale", Vector2.ONE, 0.32).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): Sfx.play(RARITY_SFX.get(rarity, "click"))).set_delay(delay)


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
	_pity_bar.value = ShopSystem.pity()
	_pity_label.text = "Epic+ guaranteed in %d pull%s   |   Win +%d, lose +%d coins" % [
		ShopSystem.pulls_to_pity(), "" if ShopSystem.pulls_to_pity() == 1 else "s", ShopSystem.WIN_REWARD, ShopSystem.LOSS_REWARD]
	if _buy_btn != null and _selected_id != "":
		var sel := CardDatabase.get_support(_selected_id)
		_buy_btn.disabled = coins < ShopSystem.buy_price(sel)
		_frag_btn.disabled = SaveManager.fragments() < ShopSystem.fragment_price(sel)
