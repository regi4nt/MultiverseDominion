extends Control
## Shop (one screen, six tabs): Card Gacha (Support + unit cards), Buy Card (Support + unit cards in one list), Auction (lelang), Gamble (judi), Trading (Chips market) and Exchange (penukaran).
## Gacha pulls cards with Aether Coins or Gacha Tickets (duplicates turn into Card Fragments, pity timer). Buy pays a locked card with
## Crystals, or exchanges Card Fragments for it. Exchange converts the currencies into each other (ShopSystem.EXCHANGES).
## Unit cards are locked at the start: the Shop sells the ones of the continents opened on the Journey trophy road.
## Coins are earned by playing matches (see SaveManager.record_match).

const GamblePanel := preload("res://scripts/ui/gamble_panel.gd")
const GachaStage := preload("res://scripts/ui/gacha_stage.gd")
const AuctionStage := preload("res://scripts/ui/auction_stage.gd")
const TradeChart := preload("res://scripts/ui/trade_chart.gd")
const TABS := [["gacha", "Card Gacha"], ["buy_card", "Buy Card"], ["auction", "Auction"], ["gamble", "Gamble"], ["trading", "Trading"], ["exchange", "Exchange"]]

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


## The Card Gacha (one pool: Support + unit + King cards). Pay with Gacha Tickets, pull x1 / x10, reveal the cards one by one.
class GachaPanel extends HBoxContainer:
	signal changed

	const RARITY_TITLES := {"common": "", "rare": "RARE PULL", "epic": "EPIC PULL!", "legendary": "LEGENDARY!!"}
	const RARITY_SFX := {"common": "click", "rare": "coin", "epic": "magic", "legendary": "victory"}

	const INFO := "Support cards, unit cards (Rare / Epic) and King cards (Legendary) in one pool. Units and Kings come from the continents you opened on the Journey trophy road. A duplicate King raises its B level (B2 = Battle Chess skill, B3 = territory skill); other duplicates become fragments. The 10-pull always holds a Rare."

	var title_label: Label
	var rng: RandomNumberGenerator
	var _chips: HFlowContainer
	var _info: Label
	var pull1: Button
	var pull10: Button
	var pity_labels: Dictionary = {}  # rarity -> Label
	var pity_bars: Dictionary = {}  # rarity -> ProgressBar
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
		lbox.add_theme_constant_override("separation", 8)  # compact: the left column must fit a 720 px high screen
		left.add_child(lbox)
		title_label = UiTheme.make_label("CARD GACHA", 26, UiTheme.COL_GOLD)
		lbox.add_child(title_label)
		_chips = HFlowContainer.new()
		_chips.add_theme_constant_override("h_separation", 6)
		_chips.add_theme_constant_override("v_separation", 6)
		lbox.add_child(_chips)
		_info = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
		_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(_info)
		for pr in ["rare", "epic", "legendary"]:  # one pity bar per rarity
			var pc := UiTheme.rarity_color(pr)
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(0, 14)
			bar.max_value = int(ShopSystem.PITY_LIMITS[pr])
			bar.add_theme_stylebox_override("fill", UiTheme.make_box(pc, pc, 0, 7))
			bar.add_theme_stylebox_override("background", UiTheme.make_box(Color("111629"), Color("2e3350"), 1, 7))
			lbox.add_child(bar)
			var pl := UiTheme.make_label("", 15, UiTheme.COL_MUTED)
			pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbox.add_child(pl)
			pity_bars[pr] = bar
			pity_labels[pr] = pl
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbox.add_child(sp)
		lbox.add_child(UiTheme.make_label("Costs Gacha Tickets (get them in Exchange or from chests and missions)", 15, UiTheme.COL_MUTED))
		pull1 = UiTheme.make_button("", 56)
		pull1.pressed.connect(_on_pull.bind(1))
		lbox.add_child(pull1)
		pull10 = UiTheme.make_primary("", 64)
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
		_setup_info()
		_show_idle()
		refresh()

	## Rate chips, info text and pity bar of the (single) pool.
	func _setup_info() -> void:
		for c in _chips.get_children():
			_chips.remove_child(c)
			c.queue_free()
		for rr in ShopSystem.RATES:
			var c := UiTheme.rarity_color(rr)
			var chip := UiTheme.make_label("%s %d%%" % [String(rr).capitalize(), ShopSystem.RATES[rr]], 16, c.lightened(0.35))
			var sb := UiTheme.make_box(Color(c, 0.16), c, 2, 8)
			sb.set_content_margin_all(5)
			chip.add_theme_stylebox_override("normal", sb)
			_chips.add_child(chip)
		_info.text = INFO

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
		var results := ShopSystem.pull_batch(count, rng)
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
		var tag_text := "NEW" if bool(r["new"]) else "+%d fragments" % int(r["fragments"])
		if int(r.get("king_b", 0)) > 0:  # a King card: the copies raise its B level
			tag_text = ("NEW  " if bool(r["new"]) else "") + ShopSystem.king_b_text(int(r["king_b"]))
		var tag := UiTheme.make_label(tag_text, 16,
			Color("59cd90") if (bool(r["new"]) or int(r.get("king_b", 0)) > 0) else Color("a98be0"))
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		pull1.text = "Pull x1  (%d ticket)" % ShopSystem.ticket_price(1)
		pull10.text = "Pull x10  (%d tickets)" % ShopSystem.ticket_price(10)
		pull1.disabled = tix < ShopSystem.ticket_price(1)
		pull10.disabled = tix < ShopSystem.ticket_price(10)
		for pr in ["rare", "epic", "legendary"]:
			var left := ShopSystem.pulls_to_pity(pr)
			(pity_bars[pr] as ProgressBar).value = ShopSystem.pity(pr)
			(pity_labels[pr] as Label).text = "%s+ guaranteed in %d pull%s" % [String(pr).capitalize(), left, "" if left == 1 else "s"]


## Buy Card tab: Support and unit cards in one list. Two filter rows: type (All / Unit / Support) and, under Unit or Support,
## the continents opened on the trophy road or the Support categories. A grid of locked cards, a detail panel, buy with crystals, or exchange fragments.
class BuyPanel extends VBoxContainer:
	signal changed

	const KIND_OPTIONS := [["all", "All"], ["unit", "Unit"], ["support", "Support"], ["king", "King"]]

	var kind: String = "all"  # type filter: "all" | "unit" | "support" | "king"
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
		crystal_btn = UiTheme.make_crystal("Buy with Crystals", 56)
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
		filter_row.visible = (kind != "all" and kind != "king")
		var valid := false
		for o in opts:
			valid = valid or String(o[0]) == filter
		if not valid:
			filter = "all"
		if kind == "all" or kind == "king":
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
		if kind == "all" or kind == "unit":
			out.append_array(ShopSystem.shop_units("" if (kind == "all" or filter == "all") else filter, true))
		if kind == "all" or kind == "king":  # Kings stay in the list until B3 (every copy raises the B level)
			out.append_array(ShopSystem.shop_kings(true))
		if kind == "all" or kind == "support":
			out.append_array(ShopSystem.locked_supports("all" if kind == "all" else filter))
		return out

	func _locked_continent_note() -> String:
		if kind == "support":
			return ""
		if kind == "king":
			return "King cards: every copy raises the B level. B2 unlocks the Battle Chess skill, B3 the territory skill. Kings of more continents join the Shop as you open them."
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
			v.setup(s, not ShopSystem.is_unit_card(s), SaveManager.king_b(String(s["id"])) if ShopSystem.is_king_card(s) else 0)
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
		if ShopSystem.is_king_card(s):
			return _king_text(s, cost)
		if not ShopSystem.is_unit_card(s):
			return "[color=#d4af37][b]%s[/b][/color]\n%s - %s\nUses per battle: %d\n\n%s\n\n%s" % [
				s["name"], s["category"], String(s["rarity"]).capitalize(), int(s["uses"]), s["description"], cost]
		var skill: Dictionary = s.get("skill", {})
		return "[color=#d4af37][b]%s[/b][/color]\n%s %s - %s\nHP %d   ATK %d   Range %d   Move %d\n\n[b]%s[/b]: %s\n\nAdds all %d copies to the deck pool.\n\n%s" % [
			s["name"], String(s["role"]), String(s["chess"]).capitalize(), String(s["rarity"]).capitalize(),
			int(s["hp"]), int(s["atk"]), int(s["range"]), int(s["move"]), String(skill.get("name", "")), String(skill.get("desc", "")),
			int(GameData.b("unit_copies")), cost]

	## King card detail: stats, the B level reached and what the next copy unlocks (the two King skills are locked behind B2 / B3).
	func _king_text(s: Dictionary, cost: String) -> String:
		var id := String(s["id"])
		var ch := GameData.get_champion(id)
		var b := SaveManager.king_b(id)
		var c_on := "#59cd90"
		var c_off := "#8d93ad"
		var t := "[color=#d4af37][b]%s[/b][/color]\nKing - %s\nHP %d   ATK %d\n\n" % [s["name"], String(s["rarity"]).capitalize(), int(s["hp"]), int(s["atk"])]
		t += "[b]Your copies:[/b] B%d / B%d\n" % [b, SaveManager.KING_MAX_COPIES] if b > 0 else "[b]Not owned yet[/b]\n"
		t += "[color=%s]B2 - Battle Chess skill: %s[/color] %s\n" % [c_on if b >= 2 else c_off, String(ch.get("active_name", "")), "" if b >= 2 else "(locked)"]
		t += "[color=%s]%s[/color]\n" % [c_on if b >= 2 else c_off, String(ch.get("active_desc", ""))]
		t += "[color=%s]B3 - Territory skill: %s[/color] %s\n" % [c_on if b >= 3 else c_off, String(ch.get("passive_name", "")), "" if b >= 3 else "(locked)"]
		t += "[color=%s]%s[/color]\n\n" % [c_on if b >= 3 else c_off, String(ch.get("passive_desc", ""))]
		t += "Each copy you buy adds +1 B level (max B%d).\n\n%s" % [SaveManager.KING_MAX_COPIES, cost]
		return t

	func refresh_detail() -> void:
		var what := "card"
		if kind == "support":
			what = "Support card"
		elif kind == "unit":
			what = "unit card"
		elif kind == "king":
			what = "King below B3"
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
		var was_king := ShopSystem.is_king_card(ShopSystem.card_by_id(selected_id))
		var king_line := ShopSystem.king_b_text(SaveManager.king_b(selected_id)) if was_king else ""
		selected_id = ""
		rebuild()
		msg.text = ""
		detail.text = "[color=#59cd90]%s[/color]\n\n%s" % [(bought + " - " + king_line) if was_king else (bought + " unlocked!"), detail.text]
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


## Trading tab: a live market paid in Chips (TradeSystem). Pick an asset, watch the animated chart, buy with Chips, sell half / all.
class TradingPanel extends HBoxContainer:
	signal changed

	var asset_id: String = "aeth"
	var amount: int = 100
	var range_sec: float = 60.0
	var asset_group: ButtonGroup
	var asset_buttons: Dictionary = {}
	var buy_btn: Button
	var half_btn: Button
	var all_btn: Button
	var amount_row: HFlowContainer
	var hold_label: Label
	var msg: Label
	var title_label: Label
	var price_label: Label
	var change_label: Label
	var folio_label: Label
	var chart: Control
	var stage: PanelContainer
	var _acc: float = 0.0
	var _last_price: float = 0.0

	func _init() -> void:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 12)
		_build()

	func _build() -> void:
		var left := PanelContainer.new()
		left.custom_minimum_size = Vector2(400, 0)
		add_child(left)
		var lbox := VBoxContainer.new()
		lbox.add_theme_constant_override("separation", 8)
		left.add_child(lbox)
		lbox.add_child(UiTheme.make_label("TRADING", 26, UiTheme.COL_GOLD))
		var hint := UiTheme.make_label("A live market paid in Chips. Buy low, sell high: prices move all the time, even while the game is closed. Selling costs a %d%% fee." % int(TradeSystem.FEE * 100.0), 14, UiTheme.COL_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(hint)
		var scroll := UiTheme.make_scroll()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		lbox.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 5)
		scroll.add_child(list)
		asset_group = ButtonGroup.new()
		for a in TradeSystem.ASSETS:
			var b := UiTheme.make_toggle("", asset_group, 48)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.button_pressed = (String(a["id"]) == asset_id)
			b.pressed.connect(_pick_asset.bind(String(a["id"])))
			list.add_child(b)
			asset_buttons[String(a["id"])] = b
		lbox.add_child(UiTheme.make_label("Amount (chips)", 15, UiTheme.COL_MUTED))
		amount_row = HFlowContainer.new()
		amount_row.add_theme_constant_override("h_separation", 6)
		lbox.add_child(amount_row)
		var ag := ButtonGroup.new()
		for n in TradeSystem.BUYS:
			var ab := UiTheme.make_toggle(str(n), ag, 44)
			ab.custom_minimum_size.x = 76
			ab.button_pressed = (n == amount)
			ab.pressed.connect(func():
				amount = int(n)
				refresh())
			amount_row.add_child(ab)
		hold_label = UiTheme.make_label("", 15, UiTheme.COL_TEXT)
		hold_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(hold_label)
		msg = UiTheme.make_label("", 15, UiTheme.COL_DANGER)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(msg)
		buy_btn = UiTheme.make_primary("Buy", 60)
		buy_btn.pressed.connect(_on_buy)
		lbox.add_child(buy_btn)
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		lbox.add_child(srow)
		half_btn = UiTheme.make_button("Sell half", 54)
		half_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		half_btn.pressed.connect(_on_sell.bind(0.5))
		srow.add_child(half_btn)
		all_btn = UiTheme.make_danger("Sell all", 54)
		all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		all_btn.pressed.connect(_on_sell.bind(1.0))
		srow.add_child(all_btn)

		stage = PanelContainer.new()
		stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage.add_theme_stylebox_override("panel", UiTheme.make_box(Color(UiTheme.COL_GOLD_DIM.darkened(0.8), 0.95), UiTheme.COL_GOLD_DIM, 2, 14))
		add_child(stage)
		var sbox := VBoxContainer.new()
		sbox.add_theme_constant_override("separation", 8)
		stage.add_child(sbox)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 12)
		sbox.add_child(top)
		title_label = UiTheme.make_label("", 26, UiTheme.COL_GOLD)
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(title_label)
		var rg := ButtonGroup.new()
		for rr in TradeSystem.RANGES:
			var rb := UiTheme.make_toggle(String(rr[0]), rg, 40)
			rb.custom_minimum_size.x = 62
			rb.button_pressed = (float(rr[1]) == range_sec)
			rb.pressed.connect(func():
				range_sec = float(rr[1])
				chart.set_range(range_sec))
			top.add_child(rb)
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 14)
		sbox.add_child(prow)
		price_label = UiTheme.make_label("", 44, UiTheme.COL_TEXT)
		prow.add_child(price_label)
		change_label = UiTheme.make_label("", 24, UiTheme.COL_MUTED)
		change_label.size_flags_vertical = Control.SIZE_SHRINK_END
		prow.add_child(change_label)
		chart = TradeChart.new()
		sbox.add_child(chart)
		folio_label = UiTheme.make_label("", 17, UiTheme.COL_MUTED)
		sbox.add_child(folio_label)
		chart.set_asset(asset_id)
		_update_prices(true)
		refresh()

	func _pick_asset(id: String) -> void:
		asset_id = id
		msg.text = ""
		chart.set_asset(id)
		_last_price = 0.0
		Sfx.play("click")
		_update_prices(true)
		refresh()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_acc += delta
		if _acc >= 0.5:
			_acc = 0.0
			_update_prices(false)

	## Prices, % change and the position's live profit; the big price flashes green / red when it ticks.
	func _update_prices(force: bool) -> void:
		var t := TradeSystem.now()
		for a in TradeSystem.ASSETS:
			var id := String(a["id"])
			var pct := TradeSystem.change_pct(id, t)
			var b: Button = asset_buttons[id]
			b.text = "%s   %s   %.2f   %s%.2f%%%s" % [a["tag"], String(a["name"]), TradeSystem.price(id, t), "+" if pct >= 0.0 else "", pct, "   [held]" if not TradeSystem.position(id).is_empty() else ""]
			b.add_theme_color_override("font_color", Color("59cd90") if pct >= 0.0 else Color("ef5b4f"))
		var cur := TradeSystem.asset(asset_id)
		var p := TradeSystem.price(asset_id, t)
		var pct1 := TradeSystem.change_pct(asset_id, t, range_sec)
		title_label.text = "%s  -  %s" % [cur["tag"], cur["name"]]
		price_label.text = "%.2f" % p
		change_label.text = "%s%.2f%%  (%s)" % ["+" if pct1 >= 0.0 else "", pct1, "%dm" % int(range_sec / 60.0)]
		var col := Color("59cd90") if pct1 >= 0.0 else Color("ef5b4f")
		change_label.add_theme_color_override("font_color", col)
		if force or _last_price == 0.0:
			price_label.add_theme_color_override("font_color", UiTheme.COL_TEXT)
		elif absf(p - _last_price) > 0.0001 and not FxMode.is_lite():
			var tick_col := Color("59cd90") if p > _last_price else Color("ef5b4f")
			price_label.add_theme_color_override("font_color", tick_col)
			price_label.create_tween().tween_method(func(k: float): price_label.add_theme_color_override("font_color", tick_col.lerp(UiTheme.COL_TEXT, k)), 0.0, 1.0, 0.45)
		_last_price = p
		_update_holding(t)

	func _update_holding(t: float) -> void:
		var pos := TradeSystem.position(asset_id)
		if pos.is_empty():
			hold_label.text = "No position in %s." % TradeSystem.asset(asset_id)["tag"]
			hold_label.add_theme_color_override("font_color", UiTheme.COL_MUTED)
			chart.set_entry(-1.0)
		else:
			var cost := int(pos["cost"])
			var worth := TradeSystem.sell_value(asset_id, t)
			var pl := worth - cost
			hold_label.text = "Position: %d chips in  |  worth %d (after fee)  |  %s%d  (%s%.1f%%)" % [cost, worth, "+" if pl >= 0 else "", pl, "+" if pl >= 0 else "", float(pl) / float(maxi(cost, 1)) * 100.0]
			hold_label.add_theme_color_override("font_color", Color("59cd90") if pl >= 0 else Color("ef5b4f"))
			chart.set_entry(cost / float(pos["units"]) if float(pos["units"]) > 0.0 else -1.0)
		var real := TradeSystem.realized()
		folio_label.text = "Portfolio %d chips   |   Realized %s%d chips" % [TradeSystem.portfolio_value(t), "+" if real >= 0 else "", real]
		half_btn.disabled = pos.is_empty()
		all_btn.disabled = pos.is_empty()

	func _on_buy() -> void:
		var r := TradeSystem.buy(asset_id, amount)
		if not bool(r["ok"]):
			Sfx.play("error")
			msg.text = String(r["error"])
			return
		msg.text = ""
		Sfx.play("coin")
		chart.play_fx("buy", amount)
		_update_prices(true)
		refresh()
		changed.emit()

	func _on_sell(fraction: float) -> void:
		var r := TradeSystem.sell(asset_id, fraction)
		if not bool(r["ok"]):
			Sfx.play("error")
			msg.text = String(r["error"])
			return
		msg.text = ""
		var net := int(r["net"])
		Sfx.play("victory" if net > 0 else ("coin" if net == 0 else "error"))
		chart.play_fx("win" if net > 0 else ("flat" if net == 0 else "loss"), net)
		_update_prices(true)
		refresh()
		changed.emit()

	func refresh() -> void:
		buy_btn.text = "Buy  (%d chips)" % amount
		buy_btn.disabled = SaveManager.chips() < amount
		_update_holding(TradeSystem.now())


## Auction (lelang) tab: a few locked cards are up for bids. Open at 40% of the value, raise 10% each time; a hidden rival bidder
## answers every raise until their limit. Pass to give up a lot. The winner pays Aether Coins (ShopSystem.auction_*).
class AuctionPanel extends HBoxContainer:
	signal changed

	var rng: RandomNumberGenerator
	var lots: Array = []  # {"id", "bid", "limit", "state": "open" | "won" | "lost"}
	var day: int = -1
	var selected: int = -1
	var list_box: VBoxContainer
	var detail: RichTextLabel
	var msg: Label
	var bid_btn: Button
	var pass_btn: Button
	var hint: Label
	var fx: Control  # AuctionStage: paddles and gavel drawn over the detail panel
	var busy: bool = false

	func _init(r: RandomNumberGenerator) -> void:
		rng = r
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_theme_constant_override("separation", 12)
		_build()

	func _build() -> void:
		var left := PanelContainer.new()
		left.custom_minimum_size = Vector2(420, 0)
		add_child(left)
		var lbox := VBoxContainer.new()
		lbox.add_theme_constant_override("separation", 8)
		left.add_child(lbox)
		lbox.add_child(UiTheme.make_label("AUCTION (LELANG)", 26, UiTheme.COL_GOLD))
		hint = UiTheme.make_label("Locked cards go to the highest bidder. Bids start at 40% of the value and rise 10% per raise. A rival bids against you; their limit is hidden. Pay with Aether Coins. New lots every day.", 15, UiTheme.COL_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbox.add_child(hint)
		var scroll := UiTheme.make_scroll()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		lbox.add_child(scroll)
		list_box = VBoxContainer.new()
		list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_box.add_theme_constant_override("separation", 8)
		scroll.add_child(list_box)

		var right := PanelContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(right)
		var rbox := VBoxContainer.new()
		rbox.add_theme_constant_override("separation", 8)
		right.add_child(rbox)
		detail = RichTextLabel.new()
		detail.bbcode_enabled = true
		detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
		detail.add_theme_font_size_override("normal_font_size", 18)
		rbox.add_child(detail)
		msg = UiTheme.make_label("", 16, UiTheme.COL_DANGER)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rbox.add_child(msg)
		bid_btn = UiTheme.make_primary("Bid", 64)
		bid_btn.pressed.connect(_on_bid)
		rbox.add_child(bid_btn)
		pass_btn = UiTheme.make_button("Pass (give up this lot)", 52)
		pass_btn.pressed.connect(_on_pass)
		rbox.add_child(pass_btn)
		fx = AuctionStage.new()  # last child of the panel = drawn on top
		right.add_child(fx)

	## Starts the day's lots (once per day, and again after the day changes). Lots won earlier are not offered again (they are owned).
	func rebuild() -> void:
		var today := int(Time.get_unix_time_from_system() / 86400.0)
		if today != day or lots.is_empty():
			day = today
			lots.clear()
			selected = -1
			for id in ShopSystem.auction_lots(day):
				var card := ShopSystem.card_by_id(String(id))
				lots.append({"id": id, "bid": 0, "limit": ShopSystem.auction_rival_limit(card, rng), "state": "open"})
		else:
			for l in lots:
				if String(l["state"]) == "won" and SaveManager.owned_count(String(l["id"])) == 0:
					l["state"] = "open"
		if selected < 0 and not lots.is_empty():
			selected = 0
		_build_list()
		_update_detail()

	func _build_list() -> void:
		for c in list_box.get_children():
			list_box.remove_child(c)
			c.queue_free()
		if lots.is_empty():
			list_box.add_child(UiTheme.make_label("No cards on offer. You own everything the Auction sells.", 17, UiTheme.COL_MUTED))
			return
		var group := ButtonGroup.new()
		for i in lots.size():
			var l: Dictionary = lots[i]
			var card := ShopSystem.card_by_id(String(l["id"]))
			var tag := ""
			match String(l["state"]):
				"won":
					tag = "  [WON]"
				"lost":
					tag = "  [GONE]"
			var b := UiTheme.make_toggle("%s  (%s)  from %d%s" % [String(card["name"]), String(card.get("rarity", "")).capitalize(), ShopSystem.auction_open(card), tag], group, 60)
			b.button_pressed = (i == selected)
			b.pressed.connect(func():
				selected = i
				msg.text = ""
				_update_detail())
			list_box.add_child(b)

	func _current() -> Dictionary:
		return lots[selected] if selected >= 0 and selected < lots.size() else {}

	func _update_detail() -> void:
		var l := _current()
		if l.is_empty():
			detail.text = "Nothing on offer."
			bid_btn.disabled = true
			pass_btn.disabled = true
			return
		var card := ShopSystem.card_by_id(String(l["id"]))
		var kind := "Unit card" if ShopSystem.is_unit_card(card) else "Support card"
		var t := "[b][font_size=26]%s[/font_size][/b]\n%s, %s\n\n" % [String(card["name"]), kind, String(card.get("rarity", "")).capitalize()]
		t += "Value: [color=#d4af37]%d coins[/color]\nStep: %d coins per raise\n\n" % [ShopSystem.auction_value(card), ShopSystem.auction_step(card)]
		match String(l["state"]):
			"won":
				t += "[color=#59cd90]You won this lot for %d coins.[/color]" % int(l["bid"])
			"lost":
				t += "[color=#ff7b7b]A rival took this lot.[/color]"
			_:
				if int(l["bid"]) == 0:
					t += "No bids yet. Opening bid: %d coins." % ShopSystem.auction_open(card)
				else:
					t += "Rival leads with [color=#ff9f5a]%d coins[/color]. Raise to %d coins to stay in." % [int(l["bid"]), int(l["bid"]) + ShopSystem.auction_step(card)]
		detail.text = t
		var open := String(l["state"]) == "open"
		pass_btn.disabled = not open
		bid_btn.disabled = not open or SaveManager.coins() < _next_bid(l)
		bid_btn.text = "Bid  (%d coins)" % _next_bid(l) if open else "Closed"

	func _next_bid(l: Dictionary) -> int:
		var card := ShopSystem.card_by_id(String(l["id"]))
		return ShopSystem.auction_open(card) if int(l["bid"]) == 0 else int(l["bid"]) + ShopSystem.auction_step(card)

	func _on_bid() -> void:
		var l := _current()
		if busy or l.is_empty() or String(l["state"]) != "open":
			return
		var card := ShopSystem.card_by_id(String(l["id"]))
		var mine := _next_bid(l)
		if SaveManager.coins() < mine:
			msg.text = "Not enough Aether Coins."
			Sfx.play("error")
			return
		msg.text = ""
		var reply := ShopSystem.auction_rival_reply(card, mine, int(l["limit"]))
		var lite := FxMode.is_lite()
		_set_busy(true)
		Sfx.play("click")
		if not lite:
			await fx.play("bid", str(mine))
		if reply == 0:
			var err := ShopSystem.auction_win(String(l["id"]), mine)
			if err != "":
				msg.text = err
				_set_busy(false)
				return
			l["bid"] = mine
			l["state"] = "won"
			Sfx.play("victory")
			changed.emit()
			_build_list()
			_update_detail()
			if not lite:
				await fx.play("sold")
		else:
			l["bid"] = reply
			if not lite:
				Sfx.play("coin")
				await fx.play("rival", str(reply))
			_build_list()
			_update_detail()
		_set_busy(false)

	func _on_pass() -> void:
		var l := _current()
		if busy or l.is_empty() or String(l["state"]) != "open":
			return
		l["state"] = "lost"
		msg.text = ""
		Sfx.play("error")
		_build_list()
		_update_detail()
		if not FxMode.is_lite():
			_set_busy(true)
			await fx.play("gone")
			_set_busy(false)

	## While an animation plays the buttons stay locked (a second bid would overlap it).
	func _set_busy(b: bool) -> void:
		busy = b
		if b:
			bid_btn.disabled = true
			pass_btn.disabled = true
		else:
			_update_detail()

	func refresh() -> void:
		if not busy:
			_update_detail()


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
	var au := AuctionPanel.new(_rng)
	var gb := GamblePanel.new(_rng)
	var tr := TradingPanel.new()
	_views = {"gacha": gs, "buy_card": bc, "auction": au, "gamble": gb, "trading": tr, "exchange": ex}
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
	if which == "buy_card" or which == "auction":
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
		elif v is AuctionPanel:
			(v as AuctionPanel).refresh()
		elif v is GamblePanel:
			(v as GamblePanel).refresh()
		elif v is TradingPanel:
			(v as TradingPanel).refresh()
