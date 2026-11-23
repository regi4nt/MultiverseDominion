extends Control
## Shop (one screen, six tabs): Support Gacha, Unit Gacha, Buy Support, Buy Unit, Exchange (penukaran) and Gamble (judi).
## Gacha pulls cards with Aether Coins or Gacha Tickets (duplicates turn into Card Fragments, pity timer). Buy pays a locked card with
## coins or Crystals, or exchanges Card Fragments for it. Exchange converts the currencies into each other (ShopSystem.EXCHANGES).
## Unit cards are locked at the start: the Shop sells the ones of the continents opened on the Journey trophy road.
## Coins are earned by playing matches (see SaveManager.record_match).

const TABS := [["gacha_support", "Support Gacha"], ["gacha_unit", "Unit Gacha"], ["buy_support", "Buy Support"], ["buy_unit", "Buy Unit"], ["exchange", "Exchange"], ["gamble", "Gamble"]]

var _wallet_labels: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _views: Dictionary = {}  # tab id -> Control
var _rng := RandomNumberGenerator.new()


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


## One Gacha: kind "support" or "unit". Pay with coins or tickets, pull x1 / x10, reveal the cards one by one.
class GachaPanel extends HBoxContainer:
	signal changed

	const RARITY_TITLES := {"common": "", "rare": "RARE PULL", "epic": "EPIC PULL!", "legendary": "LEGENDARY!!"}
	const RARITY_SFX := {"common": "click", "rare": "coin", "epic": "magic", "legendary": "victory"}

	var kind: String = "support"
	var rng: RandomNumberGenerator
	var pay: String = "coins"
	var pull1: Button
	var pull10: Button
	var pity_label: Label
	var pity_bar: ProgressBar
	var result_flow: HFlowContainer
	var result_banner: Label
	var stage: PanelContainer

	func _init(k: String, r: RandomNumberGenerator) -> void:
		kind = k
		rng = r
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 12)
		_build()

	func _build() -> void:
		# Left: short info + pity bar + payment + pull buttons.
		var left := PanelContainer.new()
		left.custom_minimum_size = Vector2(340, 0)
		add_child(left)
		var lbox := VBoxContainer.new()
		lbox.add_theme_constant_override("separation", 10)
		left.add_child(lbox)
		lbox.add_child(UiTheme.make_label("SUPPORT GACHA" if kind == "support" else "UNIT GACHA", 26, UiTheme.COL_GOLD))
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 6)
		lbox.add_child(chips)
		var rates: Dictionary = ShopSystem.RATES if kind == "support" else ShopSystem.UNIT_RATES
		for rr in rates:
			var c := UiTheme.rarity_color(rr)
			var chip := UiTheme.make_label("%s %d%%" % [String(rr).capitalize(), rates[rr]], 16, c.lightened(0.35))
			var sb := UiTheme.make_box(Color(c, 0.16), c, 2, 8)
			sb.set_content_margin_all(5)
			chip.add_theme_stylebox_override("normal", sb)
			chips.add_child(chip)
		var info_text := "Duplicates become fragments. The 10-pull always holds a Rare." if kind == "support" else \
			"Only unit cards of the continents you opened on the Journey trophy road. Duplicates become fragments."
		var info := UiTheme.make_label(info_text, 15, UiTheme.COL_MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(info)
		pity_bar = ProgressBar.new()
		pity_bar.max_value = ShopSystem.PITY_LIMIT if kind == "support" else ShopSystem.UNIT_PITY_LIMIT
		pity_bar.show_percentage = false
		pity_bar.custom_minimum_size = Vector2(0, 14)
		pity_bar.add_theme_stylebox_override("fill", UiTheme.make_box(Color("a65cf0"), Color("a65cf0"), 0, 7))
		pity_bar.add_theme_stylebox_override("background", UiTheme.make_box(Color("111629"), Color("2e3350"), 1, 7))
		lbox.add_child(pity_bar)
		pity_label = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
		pity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(pity_label)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbox.add_child(sp)
		lbox.add_child(UiTheme.make_label("Pay with", 16, UiTheme.COL_MUTED))
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 8)
		lbox.add_child(prow)
		var group := ButtonGroup.new()
		for spec in [["coins", "Coins"], ["tickets", "Tickets"]]:
			var pb := UiTheme.make_toggle(spec[1], group, 44)
			pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pb.button_pressed = (spec[0] == pay)
			pb.pressed.connect(func():
				pay = String(spec[0])
				refresh())
			prow.add_child(pb)
		pull1 = UiTheme.make_button("", 60)
		pull1.pressed.connect(_on_pull.bind(1))
		lbox.add_child(pull1)
		pull10 = UiTheme.make_primary("", 72)
		pull10.pressed.connect(_on_pull.bind(10))
		lbox.add_child(pull10)

		# Right: the "stage" where pulled cards are revealed one by one.
		stage = PanelContainer.new()
		stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_set_stage_color(UiTheme.COL_GOLD_DIM)
		add_child(stage)
		var rscroll := UiTheme.make_scroll()
		stage.add_child(rscroll)
		var rbox := VBoxContainer.new()
		rbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rbox.add_theme_constant_override("separation", 10)
		rscroll.add_child(rbox)
		result_banner = UiTheme.make_label("", 28, UiTheme.COL_GOLD)
		result_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		result_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result_banner.resized.connect(func(): result_banner.pivot_offset = result_banner.size * 0.5)
		rbox.add_child(result_banner)
		result_flow = HFlowContainer.new()
		result_flow.alignment = FlowContainer.ALIGNMENT_CENTER
		result_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		result_flow.add_theme_constant_override("h_separation", 12)
		result_flow.add_theme_constant_override("v_separation", 12)
		rbox.add_child(result_flow)
		_show_idle()

	func _set_stage_color(c: Color) -> void:
		stage.add_theme_stylebox_override("panel", UiTheme.make_box(Color(c.darkened(0.8), 0.95), c, 2, 14))

	func _clear_results() -> void:
		for c in result_flow.get_children():
			result_flow.remove_child(c)
			c.queue_free()

	func _show_idle() -> void:
		_clear_results()
		_set_stage_color(UiTheme.COL_GOLD_DIM)
		result_banner.text = "Pull to reveal cards"
		result_banner.add_theme_color_override("font_color", UiTheme.COL_MUTED)
		for i in range(5):
			var back := CardBack.new()
			back.rotation_degrees = (i - 2) * 3.0  # a loose fan instead of a flat row
			result_flow.add_child(back)

	func _fail(text: String) -> void:
		Sfx.play("error")
		_clear_results()
		result_banner.text = text
		result_banner.add_theme_color_override("font_color", UiTheme.COL_DANGER)

	func _on_pull(count: int) -> void:
		if kind == "unit" and not ShopSystem.unit_gacha_ready():
			_fail("No unit card is in the Shop yet.")
			return
		var results := ShopSystem.pull_batch(count, rng, kind, pay)
		if results.is_empty():
			_fail("Not enough Gacha Tickets." if pay == "tickets" else "Not enough Aether Coins.")
			return
		_clear_results()
		var best := 0
		var new_n := 0
		var frags := 0
		var order: Array = ShopSystem.RARITY_ORDER
		for i in range(results.size()):
			var r: Dictionary = results[i]
			var rarity := String(r["rarity"])
			best = maxi(best, order.find(rarity))
			if bool(r["new"]):
				new_n += 1
			else:
				frags += int(r["fragments"])
			var slot := _make_slot(r)
			result_flow.add_child(slot)
			_reveal(slot, i, rarity)
		var best_r: String = order[best]
		var col := UiTheme.rarity_color(best_r)
		_set_stage_color(col)
		var title: String = RARITY_TITLES[best_r]
		var total_delay := 0.11 * results.size()
		result_banner.text = "%s%d new  |  +%d fragments" % [title + "   " if title != "" else "", new_n, frags]
		result_banner.add_theme_color_override("font_color", col.lightened(0.4))
		if FxMode.is_lite():  # Lite: the summary shows at once
			result_banner.modulate.a = 1.0
			result_banner.scale = Vector2.ONE
			changed.emit()
			return
		result_banner.modulate.a = 0.0
		var bt := result_banner.create_tween()
		bt.tween_interval(total_delay)  # the summary lands after the last card
		bt.tween_property(result_banner, "modulate:a", 1.0, 0.2)
		if best >= 2:
			bt.tween_callback(func(): result_banner.scale = Vector2(1.15, 1.15))
			bt.tween_property(result_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		changed.emit()

	## One pulled card with a rarity-glow frame and a NEW / +fragments tag.
	func _make_slot(r: Dictionary) -> Control:
		var rarity := String(r["rarity"])
		var col := UiTheme.rarity_color(rarity)
		var rank: int = ShopSystem.RARITY_ORDER.find(rarity)
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
		cv.setup(ShopSystem.card_by_id(String(r["id"])), kind == "support", 1)
		v.add_child(cv)
		var tag := UiTheme.make_label("NEW" if bool(r["new"]) else "+%d fragments" % int(r["fragments"]), 16,
			Color("59cd90") if bool(r["new"]) else Color("a98be0"))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tag)
		return frame

	func _reveal(slot: Control, index: int, rarity: String) -> void:
		if FxMode.is_lite():  # Lite: cards appear instantly (the rarity sound still plays)
			if index == 0 or rarity != "common":  # no 10 clicks at once on a multi-pull
				Sfx.play(RARITY_SFX.get(rarity, "click"))
			return
		slot.modulate.a = 0.0
		slot.scale = Vector2(0.4, 0.4)
		slot.resized.connect(func(): slot.pivot_offset = slot.size * 0.5)
		var delay := 0.11 * index
		var t := slot.create_tween().set_parallel(true)  # bound to the slot: a new pull frees it and kills the tween
		t.tween_property(slot, "modulate:a", 1.0, 0.18).set_delay(delay)
		t.tween_property(slot, "scale", Vector2.ONE, 0.32).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_callback(func(): Sfx.play(RARITY_SFX.get(rarity, "click"))).set_delay(delay)

	func refresh() -> void:
		var coins := SaveManager.coins()
		var tix := SaveManager.tickets()
		var by_tickets := pay == "tickets"
		var ready_ok := kind == "support" or ShopSystem.unit_gacha_ready()
		pull1.text = "Pull x1  (%s)" % (("%d ticket" % ShopSystem.ticket_price(1)) if by_tickets else ("%d" % ShopSystem.batch_price(1)))
		pull10.text = "Pull x10  (%s)" % (("%d tickets" % ShopSystem.ticket_price(10)) if by_tickets else ("%d" % ShopSystem.batch_price(10)))
		pull1.disabled = not ready_ok or (tix < ShopSystem.ticket_price(1) if by_tickets else coins < ShopSystem.batch_price(1))
		pull10.disabled = not ready_ok or (tix < ShopSystem.ticket_price(10) if by_tickets else coins < ShopSystem.batch_price(10))
		if kind == "support":
			pity_bar.value = ShopSystem.pity()
			pity_label.text = "Epic+ guaranteed in %d pull%s" % [ShopSystem.pulls_to_pity(), "" if ShopSystem.pulls_to_pity() == 1 else "s"]
		else:
			pity_bar.value = ShopSystem.unit_pity()
			pity_label.text = "Epic guaranteed in %d pull%s   |   %d unit cards in the Shop" % [
				ShopSystem.unit_pulls_to_pity(), "" if ShopSystem.unit_pulls_to_pity() == 1 else "s", ShopSystem.shop_units("", false).size()]


## Buy tab for one kind of card ("support" or "unit"): a grid of locked cards, a detail panel, buy with coins / crystals, or exchange fragments.
class BuyPanel extends VBoxContainer:
	signal changed

	var kind: String = "support"
	var filter: String = "all"
	var grid: HFlowContainer
	var detail: RichTextLabel
	var buy_btn: Button
	var crystal_btn: Button
	var frag_btn: Button
	var msg: Label
	var note: Label
	var selected_id: String = ""
	var card_views: Dictionary = {}
	var filter_row: HFlowContainer
	var filter_group: ButtonGroup

	func _init(k: String) -> void:
		kind = k
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 8)
		_build()

	func _build() -> void:
		filter_row = HFlowContainer.new()
		filter_row.add_theme_constant_override("h_separation", 6)
		add_child(filter_row)
		note = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(note)
		var body := HBoxContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 12)
		add_child(body)
		var scroll := UiTheme.make_scroll()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(scroll)
		grid = HFlowContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		scroll.add_child(grid)

		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(400, 0)
		body.add_child(panel)
		var pbox := VBoxContainer.new()
		pbox.add_theme_constant_override("separation", 8)
		panel.add_child(pbox)
		detail = RichTextLabel.new()
		detail.bbcode_enabled = true
		detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
		detail.add_theme_font_size_override("normal_font_size", 17)
		pbox.add_child(detail)
		msg = UiTheme.make_label("", 15, UiTheme.COL_DANGER)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pbox.add_child(msg)
		buy_btn = UiTheme.make_primary("Buy", 56)
		buy_btn.pressed.connect(_on_pay.bind("coins"))
		pbox.add_child(buy_btn)
		crystal_btn = UiTheme.make_button("Buy with Crystals", 56)
		crystal_btn.add_theme_color_override("font_color", Color("7fd8ff"))
		crystal_btn.pressed.connect(_on_pay.bind("crystals"))
		pbox.add_child(crystal_btn)
		frag_btn = UiTheme.make_button("Exchange fragments", 56)
		frag_btn.add_theme_color_override("font_color", Color("cdb8ff"))
		frag_btn.pressed.connect(_on_exchange)
		pbox.add_child(frag_btn)

	## Filter chips: Support = categories, unit = the continents opened on the trophy road.
	func _build_filters() -> void:
		for c in filter_row.get_children():
			filter_row.remove_child(c)
			c.queue_free()
		filter_group = ButtonGroup.new()
		var opts: Array = []  # [id, label]
		opts.append(["all", "All"])
		if kind == "support":
			for cat in CardDatabase.SUPPORT_CATEGORIES:
				opts.append([String(cat), String(cat).capitalize()])
		else:
			for cont in GameData.continents:
				if cont.get("playable", false) and SaveManager.is_continent_unlocked(String(cont["id"])):
					opts.append([String(cont["id"]), String(cont["name"]).capitalize()])
		var valid := false
		for o in opts:
			valid = valid or String(o[0]) == filter
		if not valid:
			filter = "all"
		for o in opts:
			var b := UiTheme.make_toggle(String(o[1]), filter_group, 44)
			b.custom_minimum_size.x = 110
			b.button_pressed = (String(o[0]) == filter)
			b.pressed.connect(func():
				filter = String(o[0])
				rebuild())
			filter_row.add_child(b)

	func _listed() -> Array:
		if kind == "support":
			return ShopSystem.locked_supports(filter)
		return ShopSystem.shop_units("" if filter == "all" else filter, true)

	func _locked_continent_note() -> String:
		if kind != "unit":
			return ""
		var next := SaveManager.next_continent_goal()
		if next == "":
			return "Every continent is open: all of its unit cards are in the Shop."
		return "Journey trophies: %d. Reach %d to open %s and add its unit cards to the Shop." % [
			SaveManager.trophies(), SaveManager.continent_trophies(next), String(GameData.get_continent(next)["name"]).capitalize()]

	func rebuild() -> void:
		_build_filters()
		note.text = _locked_continent_note()
		for c in grid.get_children():
			grid.remove_child(c)
			c.queue_free()
		card_views.clear()
		var list := _listed()
		var still_listed := false
		for s in list:
			var v := CardView.new()
			v.setup(s, kind == "support", 0)
			v.pressed.connect(_on_card)
			v.set_selected(String(s["id"]) == selected_id)
			grid.add_child(v)
			card_views[String(s["id"])] = v
			still_listed = still_listed or String(s["id"]) == selected_id
		if not still_listed:
			selected_id = ""
		refresh_detail()

	func _on_card(id: String) -> void:
		if card_views.has(selected_id):
			card_views[selected_id].set_selected(false)
		selected_id = id
		card_views[id].set_selected(true)
		msg.text = ""
		refresh_detail()

	func _card_text(s: Dictionary) -> String:
		var price := ShopSystem.buy_price(s)
		var cost := "Price: %d coins\nor %d crystals\nor %d fragments" % [price, ShopSystem.crystal_price(s), ShopSystem.fragment_price(s)]
		if kind == "support":
			return "[color=#d4af37][b]%s[/b][/color]\n%s - %s\nUses per battle: %d\n\n%s\n\n%s" % [
				s["name"], s["category"], String(s["rarity"]).capitalize(), int(s["uses"]), s["description"], cost]
		var skill: Dictionary = s.get("skill", {})
		return "[color=#d4af37][b]%s[/b][/color]\n%s %s - %s\nHP %d   ATK %d   Range %d   Move %d\n\n[b]%s[/b]: %s\n\nAdds all %d copies to the deck pool.\n\n%s" % [
			s["name"], String(s["role"]), String(s["chess"]).capitalize(), String(s["rarity"]).capitalize(),
			int(s["hp"]), int(s["atk"]), int(s["range"]), int(s["move"]), String(skill.get("name", "")), String(skill.get("desc", "")),
			int(GameData.b("unit_copies")), cost]

	func refresh_detail() -> void:
		var what := "Support card" if kind == "support" else "unit card"
		if selected_id == "":
			if card_views.is_empty():
				detail.text = "[color=#59cd90]Every %s of this view is unlocked.[/color]" % what
			else:
				detail.text = "Tap a locked card to see its details and price.\n\n[color=#8d93ad]%d %s%s still locked in this view.[/color]" % [
					card_views.size(), what, "" if card_views.size() == 1 else "s"]
			buy_btn.disabled = true
			buy_btn.text = "Buy"
			crystal_btn.disabled = true
			crystal_btn.text = "Buy with Crystals"
			frag_btn.disabled = true
			frag_btn.text = "Exchange fragments"
			return
		var s := ShopSystem.card_by_id(selected_id)
		detail.text = _card_text(s)
		buy_btn.text = "Buy  (%d coins)" % ShopSystem.buy_price(s)
		crystal_btn.text = "Buy  (%d crystals)" % ShopSystem.crystal_price(s)
		frag_btn.text = "Exchange  (%d fragments)" % ShopSystem.fragment_price(s)
		refresh_buttons()

	func refresh_buttons() -> void:
		if selected_id == "":
			return
		var s := ShopSystem.card_by_id(selected_id)
		buy_btn.disabled = SaveManager.coins() < ShopSystem.buy_price(s)
		crystal_btn.disabled = SaveManager.crystals() < ShopSystem.crystal_price(s)
		frag_btn.disabled = SaveManager.fragments() < ShopSystem.fragment_price(s)

	func _on_pay(pay: String) -> void:
		_done(ShopSystem.buy(selected_id, pay) if selected_id != "" else "-")

	func _on_exchange() -> void:
		_done(ShopSystem.exchange(selected_id) if selected_id != "" else "-")

	## Shared end of a purchase / exchange: `err` is "" on success, "-" when nothing is selected.
	func _done(err: String) -> void:
		if err == "-":
			return
		if err != "":
			msg.text = err
			return
		var bought := String(ShopSystem.card_by_id(selected_id)["name"])
		selected_id = ""
		rebuild()
		msg.text = ""
		detail.text = "[color=#59cd90]%s unlocked![/color]\n\n%s" % [bought, detail.text]
		changed.emit()


## Exchange tab: one row per ShopSystem.EXCHANGES entry with x1 / x5 / x10 packs.
class ExchangePanel extends VBoxContainer:
	signal changed

	const PACKS := [1, 5, 10]
	var rows: Dictionary = {}  # exchange id -> {"buttons": Array[Button]}
	var msg: Label

	func _init() -> void:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 8)
		var hint := UiTheme.make_label("Exchange your currencies. Each pack converts the amount shown; going back and forth always costs a little.", 16, UiTheme.COL_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(hint)
		var scroll := UiTheme.make_scroll()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
		for e in ShopSystem.EXCHANGES:
			list.add_child(_make_row(e))
		msg = UiTheme.make_label("", 18, UiTheme.COL_GOLD)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(msg)

	func _make_row(e: Dictionary) -> Control:
		var panel := PanelContainer.new()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var from_name: String = ShopSystem.CURRENCY_NAMES[String(e["from"])]
		var to_name: String = ShopSystem.CURRENCY_NAMES[String(e["to"])]
		var label := UiTheme.make_label("%s x%d   >   %s x%d" % [from_name, int(e["from_n"]), to_name, int(e["to_n"])], 20, UiTheme.COL_TEXT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var buttons: Array[Button] = []
		for n in PACKS:
			var b := UiTheme.make_button("x%d" % n, 52)
			b.custom_minimum_size.x = 84
			b.pressed.connect(_on_convert.bind(String(e["id"]), int(n)))
			row.add_child(b)
			buttons.append(b)
		rows[String(e["id"])] = {"buttons": buttons}
		return panel

	func _on_convert(exchange_id: String, packs: int) -> void:
		var e := ShopSystem.exchange_spec(exchange_id)
		var err := ShopSystem.convert_currency(exchange_id, packs)
		if err != "":
			Sfx.play("error")
			msg.text = err
			msg.add_theme_color_override("font_color", UiTheme.COL_DANGER)
			return
		Sfx.play("coin")
		msg.text = "%s x%d  >  %s x%d" % [ShopSystem.CURRENCY_NAMES[String(e["from"])], int(e["from_n"]) * packs, ShopSystem.CURRENCY_NAMES[String(e["to"])], int(e["to_n"]) * packs]
		msg.add_theme_color_override("font_color", UiTheme.COL_GOLD)
		changed.emit()

	func refresh() -> void:
		for id in rows:
			var buttons: Array = rows[id]["buttons"]
			for i in range(buttons.size()):
				buttons[i].disabled = not ShopSystem.can_convert(String(id), int(PACKS[i]))


## Gamble tab: quick mini games (Coin Flip, Dice, Slots) played with Chips only. Winnings come back as Chips (Exchange turns them into coins).
class GamblePanel extends HBoxContainer:
	signal changed

	var rng: RandomNumberGenerator
	var game: String = "coin"
	var choice: String = "heads"
	var bet: int = 100
	var game_row: HBoxContainer
	var choice_row: HFlowContainer
	var bet_row: HFlowContainer
	var rules: Label
	var play_btn: Button
	var stage: PanelContainer
	var headline: Label
	var detail: Label
	var net_label: Label

	const GAME_NAMES := {"coin": "Coin Flip", "dice": "Dice", "slots": "Slots"}
	const CHOICES := {
		"coin": [["heads", "Heads"], ["tails", "Tails"]],
		"dice": [["low", "Low 2-6"], ["seven", "Seven"], ["high", "High 8-12"]],
		"slots": [],
	}

	func _init(r: RandomNumberGenerator) -> void:
		rng = r
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 12)
		_build()

	func _build() -> void:
		var left := PanelContainer.new()
		left.custom_minimum_size = Vector2(380, 0)
		add_child(left)
		var lbox := VBoxContainer.new()
		lbox.add_theme_constant_override("separation", 10)
		left.add_child(lbox)
		lbox.add_child(UiTheme.make_label("GAMBLE", 26, UiTheme.COL_GOLD))
		var hint := UiTheme.make_label("Fast money, real risk. Bets and winnings are Chips only: get Chips in the Exchange tab and turn winnings back into coins there.", 15, UiTheme.COL_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(hint)
		lbox.add_child(UiTheme.make_label("Game", 16, UiTheme.COL_MUTED))
		game_row = HBoxContainer.new()
		game_row.add_theme_constant_override("separation", 6)
		lbox.add_child(game_row)
		var gg := ButtonGroup.new()
		for g in ShopSystem.GAMBLE_GAMES:
			var b := UiTheme.make_toggle(String(GAME_NAMES[g]), gg, 46)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.button_pressed = (g == game)
			b.pressed.connect(_pick_game.bind(String(g)))
			game_row.add_child(b)
		rules = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
		rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(rules)
		lbox.add_child(UiTheme.make_label("Your pick", 16, UiTheme.COL_MUTED))
		choice_row = HFlowContainer.new()
		choice_row.add_theme_constant_override("h_separation", 6)
		lbox.add_child(choice_row)
		lbox.add_child(UiTheme.make_label("Bet (chips)", 16, UiTheme.COL_MUTED))
		bet_row = HFlowContainer.new()
		bet_row.add_theme_constant_override("h_separation", 6)
		lbox.add_child(bet_row)
		var bg := ButtonGroup.new()
		for amount in ShopSystem.GAMBLE_BETS:
			var bb := UiTheme.make_toggle(str(amount), bg, 46)
			bb.custom_minimum_size.x = 84
			bb.button_pressed = (amount == bet)
			bb.pressed.connect(func():
				bet = int(amount)
				refresh())
			bet_row.add_child(bb)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbox.add_child(sp)
		play_btn = UiTheme.make_primary("Play", 72)
		play_btn.pressed.connect(_on_play)
		lbox.add_child(play_btn)

		stage = PanelContainer.new()
		stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_set_stage_color(UiTheme.COL_GOLD_DIM)
		add_child(stage)
		var sbox := VBoxContainer.new()
		sbox.alignment = BoxContainer.ALIGNMENT_CENTER
		sbox.add_theme_constant_override("separation", 14)
		stage.add_child(sbox)
		headline = UiTheme.make_label("Place your bet", 40, UiTheme.COL_GOLD)
		headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sbox.add_child(headline)
		detail = UiTheme.make_label("", 30, UiTheme.COL_TEXT)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sbox.add_child(detail)
		net_label = UiTheme.make_label("", 28, UiTheme.COL_MUTED)
		net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sbox.add_child(net_label)
		_pick_game(game)

	func _set_stage_color(c: Color) -> void:
		stage.add_theme_stylebox_override("panel", UiTheme.make_box(Color(c.darkened(0.8), 0.95), c, 2, 14))

	func _pick_game(g: String) -> void:
		game = g
		var opts: Array = CHOICES[g]
		choice = String(opts[0][0]) if not opts.is_empty() else ""
		for c in choice_row.get_children():
			choice_row.remove_child(c)
			c.queue_free()
		var cg := ButtonGroup.new()
		for o in opts:
			var cb := UiTheme.make_toggle(String(o[1]), cg, 46)
			cb.custom_minimum_size.x = 110
			cb.button_pressed = (String(o[0]) == choice)
			cb.pressed.connect(func(): choice = String(o[0]))
			choice_row.add_child(cb)
		match g:
			"coin":
				rules.text = "Heads or tails. Win and you get double your bet (48% chance)."
			"dice":
				rules.text = "Two dice. Low (2-6) or High (8-12) pays x%.1f, exactly Seven pays x%.1f." % [ShopSystem.DICE_PAYOUT["low"], ShopSystem.DICE_PAYOUT["seven"]]
			"slots":
				rules.text = "Three reels. Three 7s pay x%d, any other three alike x%d, two alike x%.1f." % [int(ShopSystem.SLOT_JACKPOT), int(ShopSystem.SLOT_TRIPLE), ShopSystem.SLOT_PAIR]
		headline.text = "Place your bet"
		headline.add_theme_color_override("font_color", UiTheme.COL_GOLD)
		detail.text = ""
		net_label.text = ""
		_set_stage_color(UiTheme.COL_GOLD_DIM)
		refresh()

	func _on_play() -> void:
		var r := ShopSystem.gamble(game, choice, bet, rng)
		if not bool(r["ok"]):
			Sfx.play("error")
			headline.text = String(r["error"])
			headline.add_theme_color_override("font_color", UiTheme.COL_DANGER)
			return
		var d: Dictionary = r["detail"]
		match game:
			"coin":
				detail.text = "It landed on %s" % String(d["landed"]).to_upper()
			"dice":
				detail.text = "%d + %d = %d  (%s)" % [int(d["dice"][0]), int(d["dice"][1]), int(d["total"]), String(d["outcome"]).to_upper()]
			"slots":
				detail.text = "[ %s ]" % "  |  ".join(d["symbols"])
		var net := int(r["net"])
		var col: Color
		if net > 0:
			col = Color("59cd90")
			headline.text = "JACKPOT!" if String(d.get("kind", "")) == "jackpot" else "YOU WIN!"
			Sfx.play("victory" if String(d.get("kind", "")) == "jackpot" else "coin")
		elif net == 0:
			col = UiTheme.COL_GOLD
			headline.text = "PUSH"
		else:
			col = UiTheme.COL_DANGER
			headline.text = "YOU LOSE"
			Sfx.play("error")
		headline.add_theme_color_override("font_color", col)
		net_label.text = "%s%d chips" % ["+" if net > 0 else "", net]
		net_label.add_theme_color_override("font_color", col)
		_set_stage_color(col)
		for l in [headline, detail, net_label]:
			if FxMode.is_lite():
				l.modulate.a = 1.0
				continue
			l.modulate.a = 0.0
			l.create_tween().tween_property(l, "modulate:a", 1.0, 0.25)
		changed.emit()

	func refresh() -> void:
		play_btn.text = "Play  (%d chips)" % bet
		play_btn.disabled = SaveManager.chips() < bet


# ------------------------------------------------------------------ screen

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
	head.add_child(title)
	var wallet := HFlowContainer.new()  # every currency of the wallet
	wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wallet.alignment = FlowContainer.ALIGNMENT_END
	wallet.add_theme_constant_override("h_separation", 14)
	head.add_child(wallet)
	for spec in [["coins", Color("d4af37"), "coins"], ["fragments", Color("a98be0"), "fragments"], ["tickets", Color("ff9f5a"), "tickets"],
			["crystals", Color("7fd8ff"), "crystals"], ["chips", Color("59cd90"), "chips"]]:
		var l := UiTheme.make_label("", 22, spec[1])
		wallet.add_child(l)
		_wallet_labels[spec[0]] = [l, spec[2]]
	var back := UiTheme.make_button("Back", 48)
	back.custom_minimum_size.x = 140
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	head.add_child(back)

	var modes := HFlowContainer.new()
	modes.add_theme_constant_override("h_separation", 8)
	root.add_child(modes)
	var group := ButtonGroup.new()
	for spec in TABS:
		var mb := UiTheme.make_toggle(spec[1], group, 52)
		mb.custom_minimum_size.x = 176
		mb.button_pressed = (spec[0] == "gacha_support")
		mb.pressed.connect(_show_tab.bind(spec[0]))
		modes.add_child(mb)
		_tab_buttons[spec[0]] = mb

	var gs := GachaPanel.new("support", _rng)
	var gu := GachaPanel.new("unit", _rng)
	var bs := BuyPanel.new("support")
	var bu := BuyPanel.new("unit")
	var ex := ExchangePanel.new()
	var gb := GamblePanel.new(_rng)
	_views = {"gacha_support": gs, "gacha_unit": gu, "buy_support": bs, "buy_unit": bu, "exchange": ex, "gamble": gb}
	for id in _views:
		root.add_child(_views[id])
		_views[id].changed.connect(_refresh)
	_show_tab("gacha_support")
	_refresh()


func _show_tab(which: String) -> void:
	for id in _views:
		_views[id].visible = (id == which)
	if _tab_buttons.has(which):
		_tab_buttons[which].set_pressed_no_signal(true)
	if which == "buy_support" or which == "buy_unit":
		_views[which].rebuild()
	_refresh()


func _refresh() -> void:
	for key in _wallet_labels:
		var pair: Array = _wallet_labels[key]
		(pair[0] as Label).text = "%d %s" % [SaveManager.currency(String(key)), pair[1]]
	for id in _views:
		var v: Control = _views[id]
		if v is GachaPanel:
			(v as GachaPanel).refresh()
		elif v is BuyPanel:
			(v as BuyPanel).refresh_buttons()
		elif v is ExchangePanel:
			(v as ExchangePanel).refresh()
		elif v is GamblePanel:
			(v as GamblePanel).refresh()
