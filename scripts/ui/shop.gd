extends Control
## Shop (one screen, four tabs): Card Gacha (Support + unit cards), Buy Card (Support + unit cards in one list), Gamble (judi) and Exchange (penukaran).
## Gacha pulls cards with Aether Coins or Gacha Tickets (duplicates turn into Card Fragments, pity timer). Buy pays a locked card with
## Crystals, or exchanges Card Fragments for it. Exchange converts the currencies into each other (ShopSystem.EXCHANGES).
## Unit cards are locked at the start: the Shop sells the ones of the continents opened on the Journey trophy road.
## Coins are earned by playing matches (see SaveManager.record_match).

const GambleStage := preload("res://scripts/ui/gamble_stage.gd")
const GachaStage := preload("res://scripts/ui/gacha_stage.gd")
const TABS := [["gacha", "Card Gacha"], ["buy_card", "Buy Card"], ["gamble", "Gamble"], ["exchange", "Exchange"]]

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


## The Card Gacha with 3 pools (Unit + Support, Unit, Support; see `mode`). Pay with Gacha Tickets, pull x1 / x10, reveal the cards one by one.
class GachaPanel extends HBoxContainer:
	signal changed

	const RARITY_TITLES := {"common": "", "rare": "RARE PULL", "epic": "EPIC PULL!", "legendary": "LEGENDARY!!"}
	const RARITY_SFX := {"common": "click", "rare": "coin", "epic": "magic", "legendary": "victory"}

	const MODE_TITLES := {"mix": "Unit + Support", "unit": "Unit", "support": "Support"}
	const MODE_INFO := {
		"mix": "Support cards and unit cards in one pool (units: Rare / Epic of the continents you opened on the Journey trophy road). Duplicates become fragments. The 10-pull always holds a Rare.",
		"unit": "Only unit cards of the continents you opened on the Journey trophy road (Rare / Epic). Duplicates become fragments.",
		"support": "Only Support cards. Duplicates become fragments. The 10-pull always holds a Rare.",
	}

	var mode: String = "mix"  # pool: "mix" (Unit + Support) | "unit" | "support"
	var rng: RandomNumberGenerator
	var _mode_buttons: Dictionary = {}
	var _chips: HFlowContainer
	var _info: Label
	var pull1: Button
	var pull10: Button
	var pity_label: Label
	var pity_bar: ProgressBar
	var result_flow: HFlowContainer
	var result_banner: Label
	var stage: PanelContainer
	var fx: Control  # GachaStage: the summon animation drawn over the stage

	func _init(r: RandomNumberGenerator) -> void:
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
		lbox.add_child(UiTheme.make_label("CARD GACHA", 26, UiTheme.COL_GOLD))
		var group := ButtonGroup.new()
		var mode_row := HFlowContainer.new()
		mode_row.add_theme_constant_override("h_separation", 6)
		mode_row.add_theme_constant_override("v_separation", 6)
		lbox.add_child(mode_row)
		for m in ShopSystem.GACHA_MODES:
			var mb := UiTheme.make_toggle(String(MODE_TITLES[m]), group, 44)
			mb.button_pressed = (m == mode)
			mb.pressed.connect(set_mode.bind(m))
			mode_row.add_child(mb)
			_mode_buttons[m] = mb
		_chips = HFlowContainer.new()
		_chips.add_theme_constant_override("h_separation", 6)
		_chips.add_theme_constant_override("v_separation", 6)
		lbox.add_child(_chips)
		_info = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
		_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(_info)
		pity_bar = ProgressBar.new()
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
		lbox.add_child(UiTheme.make_label("Costs Gacha Tickets (get them in Exchange or from chests and missions)", 15, UiTheme.COL_MUTED))
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
		fx = GachaStage.new()  # last child of the stage = drawn on top of the cards
		stage.add_child(fx)
		set_mode(mode)

	## Switches the pool (Unit + Support / Unit / Support): rate chips, info text and pity follow, the stage is cleared.
	func set_mode(m: String) -> void:
		if not ShopSystem.GACHA_MODES.has(m):
			return
		mode = m
		for id in _mode_buttons:
			(_mode_buttons[id] as Button).set_pressed_no_signal(id == m)
		for c in _chips.get_children():
			_chips.remove_child(c)
			c.queue_free()
		var rates: Dictionary = ShopSystem.UNIT_RATES if m == "unit" else ShopSystem.RATES
		for rr in rates:
			var c := UiTheme.rarity_color(rr)
			var chip := UiTheme.make_label("%s %d%%" % [String(rr).capitalize(), rates[rr]], 16, c.lightened(0.35))
			var sb := UiTheme.make_box(Color(c, 0.16), c, 2, 8)
			sb.set_content_margin_all(5)
			chip.add_theme_stylebox_override("normal", sb)
			_chips.add_child(chip)
		_info.text = String(MODE_INFO[m])
		pity_bar.max_value = ShopSystem.UNIT_PITY_LIMIT if m == "unit" else ShopSystem.PITY_LIMIT
		_show_idle()
		refresh()

	func _set_stage_color(c: Color) -> void:
		stage.add_theme_stylebox_override("panel", UiTheme.make_box(Color(c.darkened(0.8), 0.95), c, 2, 14))

	func _clear_results() -> void:
		for c in result_flow.get_children():
			result_flow.remove_child(c)
			c.queue_free()

	func _show_idle() -> void:
		if fx != null:
			fx.stop()
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
		if mode == "unit" and not ShopSystem.unit_gacha_ready():
			_fail("No unit card is in the Shop yet.")
			return
		var results := ShopSystem.pull_batch(count, rng, mode)
		if results.is_empty():
			_fail("Not enough Gacha Tickets.")
			return
		_clear_results()
		var best := 0
		var new_n := 0
		var frags := 0
		var order: Array = ShopSystem.RARITY_ORDER
		for r in results:
			best = maxi(best, order.find(String(r["rarity"])))
			if bool(r["new"]):
				new_n += 1
			else:
				frags += int(r["fragments"])
		var best_r: String = order[best]
		var col := UiTheme.rarity_color(best_r)
		var lite := FxMode.is_lite()
		# Pro: a graphic summon (magic circle, charging orb, burst in the rarity colour) plays first; the cards appear as it bursts.
		var lead := 0.0
		if not lite:
			fx.play(best_r, col)  # not awaited: the cards are created at once, only revealed after `lead`
			lead = fx.lead_time()
			if best >= 1:
				Sfx.play("magic")
			else:
				Sfx.play("click")
		for i in range(results.size()):
			var r: Dictionary = results[i]
			var slot := _make_slot(r)
			result_flow.add_child(slot)
			_reveal(slot, i, String(r["rarity"]), lead)
		var title: String = RARITY_TITLES[best_r]
		var total_delay := 0.11 * results.size()
		var final_text := "%s%d new  |  +%d fragments" % [title + "   " if title != "" else "", new_n, frags]
		var final_col := col.lightened(0.4)
		if lite:  # Lite: the summary shows at once
			_set_stage_color(col)
			result_banner.text = final_text
			result_banner.add_theme_color_override("font_color", final_col)
			result_banner.modulate.a = 1.0
			result_banner.scale = Vector2.ONE
			changed.emit()
			return
		_set_stage_color(UiTheme.COL_GOLD_DIM)
		result_banner.text = "Summoning..."
		result_banner.add_theme_color_override("font_color", UiTheme.COL_MUTED)
		result_banner.modulate.a = 1.0
		result_banner.scale = Vector2.ONE
		var bt := result_banner.create_tween()
		bt.tween_interval(lead)
		bt.tween_callback(func():  # the burst: the stage frame and the summary take the rarity colour
			_set_stage_color(col)
			result_banner.text = final_text
			result_banner.add_theme_color_override("font_color", final_col)
			result_banner.modulate.a = 0.0)
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
		var card := ShopSystem.card_by_id(String(r["id"]))
		cv.setup(card, not ShopSystem.is_unit_card(card), 1)
		v.add_child(cv)
		var tag := UiTheme.make_label("NEW" if bool(r["new"]) else "+%d fragments" % int(r["fragments"]), 16,
			Color("59cd90") if bool(r["new"]) else Color("a98be0"))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(tag)
		return frame

	func _reveal(slot: Control, index: int, rarity: String, lead: float = 0.0) -> void:
		if FxMode.is_lite():  # Lite: cards appear instantly (the rarity sound still plays)
			if index == 0 or rarity != "common":  # no 10 clicks at once on a multi-pull
				Sfx.play(RARITY_SFX.get(rarity, "click"))
			return
		slot.modulate.a = 0.0
		slot.scale = Vector2(0.4, 0.4)
		slot.resized.connect(func(): slot.pivot_offset = slot.size * 0.5)
		var delay := lead + 0.11 * index
		var t := slot.create_tween().set_parallel(true)  # bound to the slot: a new pull frees it and kills the tween
		t.tween_property(slot, "modulate:a", 1.0, 0.18).set_delay(delay)
		t.tween_property(slot, "scale", Vector2.ONE, 0.32).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_callback(func(): Sfx.play(RARITY_SFX.get(rarity, "click"))).set_delay(delay)

	func refresh() -> void:
		var tix := SaveManager.tickets()
		var ready_ok := mode != "unit" or ShopSystem.unit_gacha_ready()
		pull1.text = "Pull x1  (%d ticket)" % ShopSystem.ticket_price(1)
		pull10.text = "Pull x10  (%d tickets)" % ShopSystem.ticket_price(10)
		pull1.disabled = not ready_ok or tix < ShopSystem.ticket_price(1)
		pull10.disabled = not ready_ok or tix < ShopSystem.ticket_price(10)
		var units := ShopSystem.shop_units("", false).size()
		if mode == "unit":
			pity_bar.value = ShopSystem.unit_pity()
			pity_label.text = "Epic guaranteed in %d pull%s   |   %d unit cards in the pool" % [ShopSystem.unit_pulls_to_pity(), "" if ShopSystem.unit_pulls_to_pity() == 1 else "s", units]
		else:
			pity_bar.value = ShopSystem.pity()
			pity_label.text = "Epic+ guaranteed in %d pull%s%s" % [ShopSystem.pulls_to_pity(), "" if ShopSystem.pulls_to_pity() == 1 else "s", "   |   %d unit cards in the pool" % units if mode == "mix" else ""]


## Buy Card tab: Support and unit cards in one list. Two filter rows: type (All / Unit / Support) and, under Unit or Support,
## the continents opened on the trophy road or the Support categories. A grid of locked cards, a detail panel, buy with crystals, or exchange fragments.
class BuyPanel extends VBoxContainer:
	signal changed

	const KIND_OPTIONS := [["all", "All"], ["unit", "Unit"], ["support", "Support"]]

	var kind: String = "all"  # type filter: "all" | "unit" | "support"
	var filter: String = "all"  # sub filter: continent id (kind unit) or Support category (kind support)
	var grid: HFlowContainer
	var detail: RichTextLabel
	var crystal_btn: Button
	var frag_btn: Button
	var msg: Label
	var note: Label
	var selected_id: String = ""
	var card_views: Dictionary = {}
	var kind_row: HFlowContainer
	var filter_row: HFlowContainer
	var kind_group: ButtonGroup
	var filter_group: ButtonGroup

	func _init() -> void:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 8)
		_build()

	func _build() -> void:
		kind_row = HFlowContainer.new()
		kind_row.add_theme_constant_override("h_separation", 6)
		add_child(kind_row)
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
		crystal_btn = UiTheme.make_primary("Buy with Crystals", 56)
		crystal_btn.add_theme_color_override("font_color", Color("7fd8ff"))
		crystal_btn.pressed.connect(_on_buy)
		pbox.add_child(crystal_btn)
		frag_btn = UiTheme.make_button("Exchange fragments", 56)
		frag_btn.add_theme_color_override("font_color", Color("cdb8ff"))
		frag_btn.pressed.connect(_on_exchange)
		pbox.add_child(frag_btn)

	## Type chips (All / Unit / Support).
	func _build_kind_row() -> void:
		for c in kind_row.get_children():
			kind_row.remove_child(c)
			c.queue_free()
		kind_group = ButtonGroup.new()
		for o in KIND_OPTIONS:
			var b := UiTheme.make_toggle(String(o[1]), kind_group, 44)
			b.custom_minimum_size.x = 110
			b.button_pressed = (String(o[0]) == kind)
			b.pressed.connect(func():
				kind = String(o[0])
				filter = "all"
				msg.text = ""
				rebuild())
			kind_row.add_child(b)

	## Sub filter chips: unit = the continents opened on the trophy road, Support = categories. Hidden under "All".
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
		elif kind == "unit":
			for cont in GameData.continents:
				if cont.get("playable", false) and SaveManager.is_continent_unlocked(String(cont["id"])):
					opts.append([String(cont["id"]), String(cont["name"]).capitalize()])
		filter_row.visible = (kind != "all")
		var valid := false
		for o in opts:
			valid = valid or String(o[0]) == filter
		if not valid:
			filter = "all"
		if kind == "all":
			return
		for o in opts:
			var b := UiTheme.make_toggle(String(o[1]), filter_group, 44)
			b.custom_minimum_size.x = 110
			b.button_pressed = (String(o[0]) == filter)
			b.pressed.connect(func():
				filter = String(o[0])
				rebuild())
			filter_row.add_child(b)

	## Locked cards of the current view: unit cards first, then Support cards.
	func _listed() -> Array:
		var out: Array = []
		if kind != "support":
			out.append_array(ShopSystem.shop_units("" if (kind == "all" or filter == "all") else filter, true))
		if kind != "unit":
			out.append_array(ShopSystem.locked_supports("all" if kind == "all" else filter))
		return out

	func _locked_continent_note() -> String:
		if kind == "support":
			return ""
		var next := SaveManager.next_continent_goal()
		if next == "":
			return "Every continent is open: all of its unit cards are in the Shop."
		return "Journey trophies: %d. Reach %d to open %s and add its unit cards to the Shop." % [
			SaveManager.trophies(), SaveManager.continent_trophies(next), String(GameData.get_continent(next)["name"]).capitalize()]

	func rebuild() -> void:
		_build_kind_row()
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
			v.setup(s, not ShopSystem.is_unit_card(s), 0)
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
		var cost := "Price: %d crystals\nor %d fragments" % [ShopSystem.crystal_price(s), ShopSystem.fragment_price(s)]
		if not ShopSystem.is_unit_card(s):
			return "[color=#d4af37][b]%s[/b][/color]\n%s - %s\nUses per battle: %d\n\n%s\n\n%s" % [
				s["name"], s["category"], String(s["rarity"]).capitalize(), int(s["uses"]), s["description"], cost]
		var skill: Dictionary = s.get("skill", {})
		return "[color=#d4af37][b]%s[/b][/color]\n%s %s - %s\nHP %d   ATK %d   Range %d   Move %d\n\n[b]%s[/b]: %s\n\nAdds all %d copies to the deck pool.\n\n%s" % [
			s["name"], String(s["role"]), String(s["chess"]).capitalize(), String(s["rarity"]).capitalize(),
			int(s["hp"]), int(s["atk"]), int(s["range"]), int(s["move"]), String(skill.get("name", "")), String(skill.get("desc", "")),
			int(GameData.b("unit_copies")), cost]

	func refresh_detail() -> void:
		var what := "card"
		if kind == "support":
			what = "Support card"
		elif kind == "unit":
			what = "unit card"
		if selected_id == "":
			if card_views.is_empty():
				detail.text = "[color=#59cd90]Every %s of this view is unlocked.[/color]" % what
			else:
				detail.text = "Tap a locked card to see its details and price.\n\n[color=#8d93ad]%d %s%s still locked in this view.[/color]" % [
					card_views.size(), what, "" if card_views.size() == 1 else "s"]
			crystal_btn.disabled = true
			crystal_btn.text = "Buy with Crystals"
			frag_btn.disabled = true
			frag_btn.text = "Exchange fragments"
			return
		var s := ShopSystem.card_by_id(selected_id)
		detail.text = _card_text(s)
		crystal_btn.text = "Buy  (%d crystals)" % ShopSystem.crystal_price(s)
		frag_btn.text = "Exchange  (%d fragments)" % ShopSystem.fragment_price(s)
		refresh_buttons()

	func refresh_buttons() -> void:
		if selected_id == "":
			return
		var s := ShopSystem.card_by_id(selected_id)
		crystal_btn.disabled = SaveManager.crystals() < ShopSystem.crystal_price(s)
		frag_btn.disabled = SaveManager.fragments() < ShopSystem.fragment_price(s)

	func _on_buy() -> void:
		_done(ShopSystem.buy(selected_id) if selected_id != "" else "-")

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


## Exchange tab: one row per ShopSystem.EXCHANGES entry. The number of packs to convert is picked with a slider, with - / + beside it.
class ExchangePanel extends VBoxContainer:
	signal changed

	var rows: Dictionary = {}  # exchange id -> {"slider", "minus", "plus", "convert", "summary"}
	var msg: Label

	func _init() -> void:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 8)
		var hint := UiTheme.make_label("Exchange your currencies. Drag the slider or use - / + to choose how many packs; going back and forth always costs a little.", 16, UiTheme.COL_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(hint)
		var scroll := UiTheme.make_scroll()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
		var id := String(e["id"])
		var panel := PanelContainer.new()
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		panel.add_child(col)
		var from_name: String = ShopSystem.CURRENCY_NAMES[String(e["from"])]
		var to_name: String = ShopSystem.CURRENCY_NAMES[String(e["to"])]
		var label := UiTheme.make_label("%s x%d   >   %s x%d   (1 pack)" % [from_name, int(e["from_n"]), to_name, int(e["to_n"])], 20, UiTheme.COL_TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(label)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		col.add_child(line)
		var minus := UiTheme.make_button("-", 52)
		minus.custom_minimum_size.x = 64
		line.add_child(minus)
		var slider := HSlider.new()
		slider.min_value = 1
		slider.max_value = 1
		slider.step = 1
		slider.value = 1
		slider.custom_minimum_size = Vector2(160, 40)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.scrollable = false  # the mouse wheel must scroll the page, not change the value
		line.add_child(slider)
		var plus := UiTheme.make_button("+", 52)
		plus.custom_minimum_size.x = 64
		line.add_child(plus)
		var summary := UiTheme.make_label("", 18, UiTheme.COL_GOLD)
		summary.custom_minimum_size.x = 250
		summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(summary)
		var convert := UiTheme.make_primary("Exchange", 52)
		convert.custom_minimum_size.x = 150
		line.add_child(convert)
		minus.pressed.connect(func(): slider.value -= 1)
		plus.pressed.connect(func(): slider.value += 1)
		slider.value_changed.connect(func(_v: float): _update_row(id))
		convert.pressed.connect(func(): _on_convert(id, int(slider.value)))
		rows[id] = {"slider": slider, "minus": minus, "plus": plus, "convert": convert, "summary": summary}
		_update_row(id)
		return panel

	## Packs the player can pay right now (0 = none).
	func _max_packs(id: String) -> int:
		var e := ShopSystem.exchange_spec(id)
		return SaveManager.currency(String(e["from"])) / int(e["from_n"])

	## Slider range, - / + / Exchange state and the "pay > get" text of one row.
	func _update_row(id: String) -> void:
		var e := ShopSystem.exchange_spec(id)
		var r: Dictionary = rows[id]
		var slider: HSlider = r["slider"]
		var most := _max_packs(id)
		slider.max_value = maxi(most, 1)
		slider.editable = most >= 1
		var n := int(slider.value)
		(r["minus"] as Button).disabled = most < 1 or n <= 1
		(r["plus"] as Button).disabled = most < 1 or n >= most
		(r["convert"] as Button).disabled = most < 1
		(r["summary"] as Label).text = "x%d:  %d  >  %d" % [n, int(e["from_n"]) * n, int(e["to_n"]) * n] if most >= 1 else "Not enough %s" % ShopSystem.CURRENCY_NAMES[String(e["from"])]

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
			_update_row(String(id))


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
	var busy := false
	var gfx: Control  # GambleStage: the drawn coin / dice / reels

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
			bb.custom_minimum_size.x = 68
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
		gfx = GambleStage.new()
		gfx.sound.connect(func(n: String): Sfx.play(n))
		sbox.add_child(gfx)
		detail = UiTheme.make_label("", 22, UiTheme.COL_TEXT)
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
		gfx.set_idle(g)
		headline.text = "Place your bet"
		headline.add_theme_color_override("font_color", UiTheme.COL_GOLD)
		detail.text = ""
		net_label.text = ""
		_set_stage_color(UiTheme.COL_GOLD_DIM)
		refresh()

	## Locks / unlocks the pickers while an animation plays.
	func _set_busy(b: bool) -> void:
		busy = b
		for row in [game_row, choice_row, bet_row]:
			for c in row.get_children():
				(c as Button).disabled = b
		if b:
			play_btn.disabled = true
		else:
			refresh()

	func _wait(sec: float) -> void:
		await get_tree().create_timer(sec).timeout

	## Suspense before the result: the graphic stage flips the coin, tumbles the dice or spins the reels. The outcome is already
	## decided (ShopSystem.gamble); this only plays it back. Lite effects mode skips it.
	func _animate(r: Dictionary) -> void:
		headline.text = {"coin": "Flipping...", "dice": "Rolling...", "slots": "Spinning..."}[game]
		headline.add_theme_color_override("font_color", UiTheme.COL_MUTED)
		net_label.text = ""
		detail.text = ""
		_set_stage_color(UiTheme.COL_GOLD_DIM)
		if game == "dice":
			Sfx.play("dice")
		await gfx.play(game, r["detail"])

	## Pop for a win (bigger for a jackpot), shake for a loss.
	func _celebrate(net: int, jackpot: bool) -> void:
		headline.pivot_offset = headline.size * 0.5
		var tw := create_tween()
		if net > 0:
			headline.scale = Vector2(0.6, 0.6)
			tw.tween_property(headline, "scale", Vector2(1.25 if jackpot else 1.12, 1.25 if jackpot else 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(headline, "scale", Vector2.ONE, 0.15)
			if jackpot:
				var fl := create_tween()
				fl.tween_property(stage, "modulate", Color(1.6, 1.5, 1.0), 0.12)
				fl.tween_property(stage, "modulate", Color.WHITE, 0.35)
		elif net < 0:
			for dx in [10.0, -10.0, 6.0, -6.0, 0.0]:
				tw.tween_property(headline, "position:x", dx, 0.04).as_relative()
			tw.tween_callback(func(): headline.scale = Vector2.ONE)

	func _on_play() -> void:
		if busy:
			return
		var r := ShopSystem.gamble(game, choice, bet, rng)
		if not bool(r["ok"]):
			Sfx.play("error")
			headline.text = String(r["error"])
			headline.add_theme_color_override("font_color", UiTheme.COL_DANGER)
			return
		_set_busy(true)
		if not FxMode.is_lite():
			await _animate(r)
			if not is_inside_tree():
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
		if not FxMode.is_lite():
			_celebrate(net, String(d.get("kind", "")) == "jackpot")
			gfx.celebrate(net > 0, String(d.get("kind", "")) == "jackpot")
		_set_busy(false)
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
		mb.button_pressed = (spec[0] == "gacha")
		mb.pressed.connect(_show_tab.bind(spec[0]))
		modes.add_child(mb)
		_tab_buttons[spec[0]] = mb

	var gs := GachaPanel.new(_rng)
	var bc := BuyPanel.new()
	var ex := ExchangePanel.new()
	var gb := GamblePanel.new(_rng)
	_views = {"gacha": gs, "buy_card": bc, "gamble": gb, "exchange": ex}
	for id in _views:
		root.add_child(_views[id])
		_views[id].changed.connect(_refresh)
	_show_tab("gacha")
	_refresh()


func _show_tab(which: String) -> void:
	for id in _views:
		_views[id].visible = (id == which)
	if _tab_buttons.has(which):
		_tab_buttons[which].set_pressed_no_signal(true)
	if which == "buy_card":
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
