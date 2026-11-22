extends Control
## Battle screen (Battle Practice): PREPARATION -> AUTO BATTLE -> RESULT.
## All rules live in BattlePrep / BattleEngine / BattleAI; this script only displays and forwards input.
## Two modes: Battle Practice (standalone) and DUEL (duel_context set by the Territory Board before
## add_child: {"human","opponent","tile","human_attacks"}). In duel mode the persistent armies and the
## real Dominion Gold are used and `battle_finished(result)` is emitted when the player continues.

signal battle_finished(result: Dictionary)

var duel_context: Dictionary = {}

var prep: BattlePrep
var engine: BattleEngine
var rng := RandomNumberGenerator.new()
var deck: Deck
var champion_id: String = ""
var hand: Array = []
var phase: String = "prep"
var selected: UnitInstance
var speed: float = 1.0

var grid: BattleGridView
var status_label: Label
var message_label: Label
var shop_box: VBoxContainer
var bench_grid: GridContainer
var sel_label: Label
var sell_btn: Button
var bench_btn: Button
var reroll_btn: Button
var level_btn: Button
var hand_label: Label
var hand_box: VBoxContainer
var synergy_box: VBoxContainer  # top-left: faction + role synergy of the deployed units
var prep_actions: VBoxContainer  # bottom of the right column (To Bench / Sell / Lock Formation), preparation only
var _own_faction: String = ""
var prep_panel: VBoxContainer  # right column, preparation part (buttons)
var prep_left: VBoxContainer  # left column, preparation part (shop + bench)
var battle_left: VBoxContainer  # left column, battle part (log)
var battle_panel: VBoxContainer
var battle_status: Label
var support_box: VBoxContainer
var king_box: VBoxContainer  # King passive (buff) + manual active skill
var king_btn: Button
var log_view: RichTextLabel
var timer: Timer
var _log_index: int = 0
var _enemy_champion: String = ""
var _enemy_hand: Array = []
var _result_shown := false
var _duel_msg: String = ""
var _tip_panel: PanelContainer = null
var _tip_label: Label = null
var _leave_dialog: UiDialog
var _start_dialog: UiDialog


func _ready() -> void:
	theme = UiTheme.get_theme()
	rng.randomize()
	if duel_context.is_empty():
		CardDatabase.set_continent(GameSession.continent_id)
		WorldMods.apply(GameData.get_continent(CardDatabase.active_continent))
		deck = SaveManager.get_deck(GameSession.continent_id)
		champion_id = deck.champion_id
		prep = BattlePrep.new(deck, rng, int(GameData.b("practice_gold")), int(GameData.b("practice_gold")), int(GameData.b("start_level")))
		hand = prep.hand
	else:
		var me: PlayerState = duel_context["human"]
		deck = me.deck
		champion_id = me.champion_id
		var budget := int(float(me.gold) * float(GameData.b("battle_budget_ratio")))
		prep = BattlePrep.new(deck, rng, me.gold, budget, me.level, me.roster, me.battle_deck, me.hand)
		hand = prep.hand
		prep.price_mult = me.battle_price_mult()  # Quartermaster passive (prices are computed on display)
	var own_faction := String(GameData.get_champion(champion_id).get("faction", ""))
	_own_faction = own_faction
	_build_ui()
	grid.own_faction = own_faction
	grid.show_prep(prep)
	grid.cell_pressed.connect(_on_cell)
	timer = Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(_on_tick)
	add_child(timer)
	if not duel_context.is_empty():
		var o: PlayerState = duel_context["opponent"]
		_duel_msg = "DUEL at %s - you %s %s." % [duel_context["tile"], "attack" if duel_context["human_attacks"] else "defend against", o.display_name]
	_msg("")
	if bool(duel_context.get("tutorial", false)):
		_build_tip()
		_set_tip(TutorialGuide.BATTLE["prep"])
	_refresh_prep()


## Tutorial tips are drawn over the empty ENEMY half of the board during preparation.
func _build_tip() -> void:
	_tip_panel = PanelContainer.new()
	_tip_panel.add_theme_stylebox_override("panel", UiTheme.make_box(Color(0.16, 0.12, 0.31, 0.95), UiTheme.COL_GOLD, 2, 10))
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(_tip_panel)
	_tip_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tip_panel.offset_left = 14
	_tip_panel.offset_right = -14
	_tip_panel.offset_top = 14
	_tip_label = UiTheme.make_label("", 17, UiTheme.COL_TEXT)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.add_child(_tip_label)


func _set_tip(text: String) -> void:
	if _tip_label != null:
		_tip_label.text = "TUTORIAL: " + text


func _build_ui() -> void:
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(12)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	# Three columns, like the Territory Board: actions / support cards | the board in the middle | shop and army (sides swapped).
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	var arc := AspectRatioContainer.new()
	arc.ratio = 1.0
	arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arc.size_flags_stretch_ratio = 2.6  # 16:9 -> the board gets its full height; extra width goes to the side columns
	root.add_child(arc)
	grid = BattleGridView.new()
	arc.add_child(grid)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(230, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	root.add_child(right)
	# Sides swapped: the `right` column is shown on the LEFT and the `left` column on the RIGHT (order: right | board | left).
	root.move_child(right, 0)
	root.move_child(left, root.get_child_count() - 1)
	var head := HBoxContainer.new()
	left.add_child(head)
	status_label = UiTheme.make_label("", 17, UiTheme.COL_GOLD)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(status_label)
	var menu := UiTheme.make_button("Menu", 44)
	menu.custom_minimum_size.x = 90
	menu.visible = duel_context.is_empty()  # a duel cannot be abandoned
	menu.pressed.connect(_request_leave)
	head.add_child(menu)

	# ---- left column (top -> bottom): synergy combos | selected unit + Reroll | ... | Auto Deploy + Level Up (bottom-left corner)
	var syn_panel := PanelContainer.new()
	right.add_child(syn_panel)
	synergy_box = VBoxContainer.new()
	synergy_box.add_theme_constant_override("separation", 0)
	syn_panel.add_child(synergy_box)
	prep_panel = VBoxContainer.new()
	prep_panel.add_theme_constant_override("separation", 6)
	prep_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(prep_panel)
	sel_label = UiTheme.make_label("Select a unit (bench or board), then tap a cell in your area.", 14, UiTheme.COL_MUTED)
	sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_label.max_lines_visible = 5
	sel_label.custom_minimum_size.y = 90
	prep_panel.add_child(sel_label)
	reroll_btn = UiTheme.make_button("Reroll", 46)
	reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_btn.pressed.connect(_on_reroll)
	prep_panel.add_child(reroll_btn)  # directly below the selected-unit text
	hand_label = UiTheme.make_label("", 14, UiTheme.COL_MUTED)
	hand_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prep_panel.add_child(hand_label)
	hand_box = VBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 2)
	prep_panel.add_child(hand_box)
	bench_grid = GridContainer.new()
	bench_grid.columns = 4
	bench_grid.add_theme_constant_override("h_separation", 4)
	bench_grid.add_theme_constant_override("v_separation", 3)
	prep_panel.add_child(bench_grid)
	var push := Control.new()  # pushes Auto Deploy + Level Up to the bottom
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prep_panel.add_child(push)
	var auto := UiTheme.make_button("Auto Deploy", 46)
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto.pressed.connect(_on_auto)
	prep_panel.add_child(auto)  # above Level Up
	level_btn = UiTheme.make_button("Level Up", 46)
	level_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_btn.pressed.connect(_on_level_up)
	prep_panel.add_child(level_btn)

	# ---- right column: shop + bench on top, To Bench / Sell / Lock Formation in the bottom-right corner
	prep_left = VBoxContainer.new()
	prep_left.add_theme_constant_override("separation", 4)
	prep_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(prep_left)
	shop_box = VBoxContainer.new()
	shop_box.add_theme_constant_override("separation", 3)
	prep_left.add_child(shop_box)
	prep_actions = VBoxContainer.new()
	prep_actions.add_theme_constant_override("separation", 6)
	left.add_child(prep_actions)
	message_label = UiTheme.make_label("", 14, UiTheme.COL_DANGER)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size.y = 22
	prep_actions.add_child(message_label)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	prep_actions.add_child(row2)
	bench_btn = UiTheme.make_button("To Bench", 44)
	bench_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bench_btn.pressed.connect(_on_to_bench)
	row2.add_child(bench_btn)
	sell_btn = UiTheme.make_button("Sell", 44)
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.pressed.connect(_on_sell)
	row2.add_child(sell_btn)
	var start := UiTheme.make_primary("LOCK FORMATION\n& FIGHT", 72)
	start.pressed.connect(_on_start_pressed)
	prep_actions.add_child(start)

	# ---- battle panel
	battle_panel = VBoxContainer.new()
	battle_panel.add_theme_constant_override("separation", 6)
	battle_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_panel.visible = false
	right.add_child(battle_panel)
	battle_status = UiTheme.make_label("", 17)
	battle_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long HP totals must not clip at the panel edge
	battle_panel.add_child(battle_status)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 6)
	battle_panel.add_child(speeds)
	var sg := ButtonGroup.new()
	for s in [["Pause", 0.0], ["1x", 1.0], ["2x", 2.0], ["4x", 4.0]]:
		var b := UiTheme.make_toggle(s[0], sg, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = (s[1] == 1.0)
		b.pressed.connect(func(): _set_speed(s[1]))
		speeds.add_child(b)
	battle_panel.add_child(UiTheme.make_label("King", 16, UiTheme.COL_GOLD))
	king_box = VBoxContainer.new()
	king_box.add_theme_constant_override("separation", 4)
	battle_panel.add_child(king_box)
	battle_panel.add_child(UiTheme.make_label("Support hand (tap to play)", 16, UiTheme.COL_GOLD))
	support_box = VBoxContainer.new()
	support_box.add_theme_constant_override("separation", 4)
	battle_panel.add_child(support_box)
	battle_left = VBoxContainer.new()
	battle_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_left.visible = false
	left.add_child(battle_left)
	var lp := PanelContainer.new()
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_left.add_child(lp)
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", 14)
	lp.add_child(log_view)

	_leave_dialog = UiDialog.new()
	_leave_dialog.title = "Leave battle?"
	_leave_dialog.tone = "danger"
	_leave_dialog.dialog_text = "Leave Battle Practice? This battle will be lost."
	_leave_dialog.ok_button_text = "Leave"
	_leave_dialog.cancel_button_text = "Stay"
	_leave_dialog.confirmed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	add_child(_leave_dialog)
	_start_dialog = UiDialog.new()
	_start_dialog.title = "No units deployed"
	_start_dialog.tone = "warn"
	_start_dialog.dialog_text = "No units are deployed, so your Champion will fight alone. Start the battle anyway?"
	_start_dialog.ok_button_text = "Fight"
	_start_dialog.cancel_button_text = "Back"
	_start_dialog.confirmed.connect(_on_start_battle)
	add_child(_start_dialog)


## Menu button / Android Back in Battle Practice: ask first, unless the battle is already over.
func _request_leave() -> void:
	if _result_shown:
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	else:
		_leave_dialog.popup_centered(Vector2i(460, 170))


func on_back_requested() -> void:
	if duel_context.is_empty():
		_request_leave()


## "Lock formation & fight": an empty formation needs a confirmation (it used to start silently).
func _on_start_pressed() -> void:
	if prep.deployed_units().is_empty():
		_start_dialog.popup_centered(Vector2i(480, 190))
	else:
		_on_start_battle()


# ------------------------------------------------------------------ preparation

func _refresh_prep() -> void:
	status_label.text = "Gold %d  |  Budget %d\nLevel %d  |  Capacity %d/%d" % [prep.gold, prep.budget_left, prep.level, prep.used_capacity(), prep.capacity()]
	for c in shop_box.get_children():
		shop_box.remove_child(c)
		c.queue_free()
	for i in range(prep.offers.size()):
		var id := prep.offers[i]
		var b := UiTheme.make_button("", 48)
		b.custom_minimum_size.y = 48  # compact: the preparation panel must fit a 720 px high screen
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # the side column is narrow: long names wrap
		b.add_theme_font_size_override("font_size", 15)
		if id == "":
			b.text = "- sold -"
			b.disabled = true
		else:
			if BattlePrep.is_support_id(id):
				var sc := CardDatabase.get_support(id)
				b.text = "%s  [Support %s, Lv %d]  %d\u00A0G\n%s" % [sc["name"], String(sc["category"]), prep.support_level_req(id), prep.support_price(id), sc["description"]]
				b.add_theme_font_size_override("font_size", 13)
			else:
				var card := CardDatabase.get_unit(id)
				b.text = "%s  [%s %s]  %d\u00A0G" % [card["name"], String(card["chess"]).capitalize(), card["role"], prep.unit_price(id)]
			b.disabled = prep.can_buy(i) != ""
		b.pressed.connect(_on_buy.bind(i))
		shop_box.add_child(b)
	reroll_btn.text = "Reroll (%d G)" % (0 if prep.free_reroll else int(GameData.b("battle_reroll_price")))
	level_btn.text = "Level Up (%d G)" % prep.level_up_cost() if prep.level < int(GameData.b("max_level")) else "Max level"
	for c in bench_grid.get_children():
		bench_grid.remove_child(c)
		c.queue_free()
	var bench := prep.bench_units()
	for i in range(int(GameData.b("prep_slots"))):
		var b := UiTheme.make_button("", 48)
		b.custom_minimum_size = Vector2(62, 48)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		if i < bench.size():
			var u := bench[i]
			b.text = "%s %s" % [String(CardDatabase.get_unit(u.card_id)["name"]).substr(0, 7), "*".repeat(u.stars)]
			b.toggle_mode = true
			b.button_pressed = (u == selected)
			b.pressed.connect(_on_select.bind(u))
		else:
			b.text = "-"
			b.disabled = true
		bench_grid.add_child(b)
	if selected != null and not prep.roster.units.has(selected):
		selected = null
	if selected == null:
		sel_label.text = "Select a unit (bench or board), then tap a cell in your area (rows below the gold line)."
	else:
		var card := CardDatabase.get_unit(selected.card_id)
		var st := selected.stats()
		sel_label.text = "%s %s | HP %d ATK %d | Rng %d Mov %d | cost %d | %s: %s" % [card["name"], "*".repeat(selected.stars), st["hp"], st["atk"], card["range"], card["move"], CardDatabase.capacity_cost(selected.chess()), card["skill"]["name"], card["skill"]["desc"]] + _buff_line(selected.card_id)
	sell_btn.disabled = selected == null
	bench_btn.disabled = selected == null or selected.cell.x < 0
	hand_label.text = "Support hand (%d/%d) - tap to sell:" % [prep.hand.size(), int(GameData.b("hand_max"))]
	for c in hand_box.get_children():
		hand_box.remove_child(c)
		c.queue_free()
	for id in prep.hand:
		var hs := CardDatabase.get_support(id)
		var sellable := prep.can_sell_support(id)
		var hb := UiTheme.make_button("%s%s" % [hs["name"], ("  (sell %d G)" % int(prep.support_price(id) * float(GameData.b("sell_ratio")))) if sellable else "  (used now)"], 34)
		hb.custom_minimum_size.y = 34
		hb.add_theme_font_size_override("font_size", 13)
		hb.tooltip_text = String(hs["description"])
		hb.disabled = not sellable
		hb.pressed.connect(_on_sell_support.bind(id))
		hand_box.add_child(hb)
	_refresh_synergy()
	grid.selected = selected
	grid.queue_redraw()


## Top-left panel: faction synergy (same tiers as BattleEngine._synergy: 2 = +5%, 4 = +15%, 6 = +30% HP and ATK)
## and role synergy (BattleEngine.role_bonus: 2 = +8%, 4 = +20%, 6 = +35% of the role's stat) of the deployed units.
func _refresh_synergy() -> void:
	for c in synergy_box.get_children():
		synergy_box.remove_child(c)
		c.queue_free()
	synergy_box.add_child(UiTheme.make_label("SYNERGY", 14, UiTheme.COL_GOLD))
	var deployed := prep.deployed_units()
	if deployed.is_empty():
		synergy_box.add_child(UiTheme.make_label("Deploy units to see combos.", 12, UiTheme.COL_MUTED))
		return
	var fac_counts := {}
	var role_counts := {}
	for u in deployed:
		var card := CardDatabase.get_unit(u.card_id)
		var fac := CardDatabase.effective_faction(card, _own_faction)
		if fac != "" and GameData.is_home_faction(fac, CardDatabase.active_continent):
			fac_counts[fac] = int(fac_counts.get(fac, 0)) + 1
		var role := String(card.get("role", ""))
		if role != "":
			role_counts[role] = int(role_counts.get(role, 0)) + 1
	var inactive: Array[String] = []  # groups without a bonus yet share one muted line (keeps the panel short)
	var facs: Array = fac_counts.keys()
	facs.sort_custom(func(x, y): return int(fac_counts[x]) > int(fac_counts[y]))
	for fac in facs:
		var n: int = fac_counts[fac]
		var fname := String(GameData.get_faction(CardDatabase.active_continent, fac).get("name", String(fac).capitalize()))
		var bonus := 30 if n >= 6 else (15 if n >= 4 else (5 if n >= 2 else 0))
		if bonus == 0:
			inactive.append("%s x%d" % [fname, n])
			continue
		var nxt := "" if n >= 6 else "  (next at %d)" % (6 if n >= 4 else 4)
		_synergy_row("%s x%d  +%d%% HP/ATK%s" % [fname, n, bonus, nxt])
	var roles: Array = role_counts.keys()
	roles.sort_custom(func(x, y): return int(role_counts[x]) > int(role_counts[y]))
	for r in roles:
		var n: int = role_counts[r]
		var rb := BattleEngine.role_bonus(String(r), n)
		var pct := int(round(maxf(float(rb["hp"]), float(rb["atk"])) * 100.0))
		if pct == 0:
			inactive.append("%s x%d" % [r, n])
			continue
		var focus := String(BattleEngine.ROLE_FOCUS.get(r, "both"))
		var stat := "HP" if focus == "hp" else ("ATK" if focus == "atk" else "HP/ATK")
		var nt := BattleEngine.role_next_tier(n)
		_synergy_row("%s x%d  +%d%% %s%s" % [r, n, pct, stat, ("  (next at %d)" % nt) if nt > 0 else ""])
	if not inactive.is_empty():
		var il := _synergy_row("No bonus yet: " + ", ".join(inactive), false)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		il.clip_text = false


func _synergy_row(text: String, active: bool = true) -> Label:
	var l := UiTheme.make_label(text, 12, UiTheme.COL_GOLD if active else UiTheme.COL_MUTED)
	l.clip_text = true
	synergy_box.add_child(l)
	return l


## Errors in red; with no error the line shows the duel information (if any).
func _msg(text: String) -> void:
	message_label.text = text if text != "" else _duel_msg
	message_label.add_theme_color_override("font_color", UiTheme.COL_DANGER if text != "" else UiTheme.COL_GOLD)


func _on_buy(i: int) -> void:
	var err := prep.buy(i)
	_msg(err if err != "" else (" ".join(prep.merge_log)))
	_refresh_prep()


func _on_sell_support(id: String) -> void:
	prep.sell_support(id)
	_refresh_prep()


func _on_reroll() -> void:
	_msg("" if prep.refresh_offers(true) else "Cannot afford a reroll.")
	_refresh_prep()


func _on_level_up() -> void:
	_msg(prep.level_up())
	_refresh_prep()


func _on_auto() -> void:
	BattleAI.auto_deploy(prep, 0)
	selected = null
	_msg("")
	_refresh_prep()


func _on_select(u: UnitInstance) -> void:
	selected = u
	_refresh_prep()


func _on_to_bench() -> void:
	if selected != null:
		_msg(prep.return_to_bench(selected))
		_refresh_prep()


func _on_sell() -> void:
	if selected != null:
		prep.sell(selected)
		selected = null
		_msg("")
		_refresh_prep()


func _on_cell(cell: Vector2i) -> void:
	if phase != "prep":
		return
	for u in prep.deployed_units():
		if u.cell == cell:
			selected = u  # tapping a deployed unit selects it
			_refresh_prep()
			return
	if selected != null:
		_msg(prep.deploy(selected, cell))
		_refresh_prep()


# ------------------------------------------------------------------ battle

func _on_start_battle() -> void:
	var enemy_cfg: Dictionary
	if duel_context.is_empty():
		var diff := String(GameSession.difficulty)
		var enemy_prep := BattleAI.build_enemy(diff, prep.level + (1 if diff == "hard" else 0), rng, deck)
		_enemy_champion = BattleAI.pick_champion(rng, champion_id)
		_enemy_hand = BattleAI.pick_hand(deck, rng, 2)
		enemy_cfg = enemy_prep.to_side_cfg(_enemy_champion, _enemy_hand)
	else:
		var me: PlayerState = duel_context["human"]
		prep.finish()  # unbought offers go back to the pile; spending is permanent
		me.gold = prep.gold
		me.level = prep.level
		me.capacity = prep.capacity()
		enemy_cfg = BattleAI.prepare_ai_army(duel_context["opponent"], rng, 1)
	engine = BattleEngine.new()
	engine.setup({"seed": rng.randi(), "ai_supports": [false, true], "manual_king": [true, false], "sides": [
		prep.to_side_cfg(champion_id, hand), enemy_cfg]})
	phase = "battle"
	_set_tip(TutorialGuide.BATTLE["fight"])
	prep_panel.visible = false
	prep_left.visible = false
	prep_actions.visible = false
	battle_panel.visible = true
	battle_left.visible = true
	grid.show_engine(engine)
	_log_index = 0
	_rebuild_supports()
	_rebuild_king()
	_set_speed(1.0)


func _battle_sounds() -> void:
	var hit := false
	var fell := false
	var fx := false
	for ev in engine.events:
		match ev["type"]:
			"attack":
				hit = true
			"death":
				fell = true
			"fx":
				fx = true
	if fell:
		Sfx.play("death")
	elif hit:
		Sfx.play("hit")
	if fx:
		Sfx.play("magic")


func _set_speed(s: float) -> void:
	speed = s
	grid.anim_speed = s
	if s <= 0.0:
		timer.stop()
	else:
		timer.wait_time = 0.25 / s
		timer.start()


func _on_tick() -> void:
	if phase != "battle" or engine.finished:
		return
	engine.step()
	grid.notify_tick()
	_battle_sounds()
	_update_battle_ui()
	if engine.finished:
		timer.stop()
		_show_result()


func _update_battle_ui() -> void:
	while _log_index < engine.log_lines.size():
		log_view.add_text(engine.log_lines[_log_index] + "\n")
		_log_index += 1
	status_label.text = "Tick %d / %d" % [engine.tick, BattleEngine.MAX_TICKS]
	battle_status.text = "You: %d units, HP %d\nEnemy: %d units, HP %d" % [engine.regulars_alive(0), engine.total_hp(0), engine.regulars_alive(1), engine.total_hp(1)]
	_refresh_king_btn()
	grid.queue_redraw()


## King panel: Passive (every continent), Buff (home continent only) and the active skill, cast by hand once the King is in the arena.
func _rebuild_king() -> void:
	for c in king_box.get_children():
		king_box.remove_child(c)
		c.queue_free()
	king_btn = null
	var ch := GameData.get_champion(champion_id)
	if ch.is_empty():
		return
	var kp: Dictionary = GameData.king_passives.get(champion_id, {})
	if not kp.is_empty():
		var ppl := UiTheme.make_label("Passive - %s: %s" % [kp["name"], kp["desc"]], 13, UiTheme.COL_GOLD)
		ppl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		king_box.add_child(ppl)
	var kb := CardDatabase.king_buff(champion_id, false)
	if not kb.is_empty():
		var home := not CardDatabase.king_buff(champion_id).is_empty()
		var pl := UiTheme.make_label("Buff - %s: %s%s" % [kb["name"], kb["desc"], "" if home else " (inactive: foreign faction)"], 13, UiTheme.COL_GOLD if home else UiTheme.COL_MUTED)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		king_box.add_child(pl)
	king_btn = UiTheme.make_button("", 64)
	king_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	king_btn.add_theme_font_size_override("font_size", 14)
	king_btn.pressed.connect(_on_king_skill)
	king_box.add_child(king_btn)
	_refresh_king_btn()


func _refresh_king_btn() -> void:
	if king_btn == null:
		return
	var ch := GameData.get_champion(champion_id)
	var base := "%s - %s" % [ch.get("active_name", "King skill"), ch.get("active_desc", "")]
	if bool(engine.king_skill_used[0]):
		king_btn.text = "%s (used)" % ch.get("active_name", "King skill")
	elif not bool(engine.king_entered[0]):
		king_btn.text = "%s\n(available once the King enters in Last Stand)" % base
	else:
		king_btn.text = "USE: %s" % base
	king_btn.disabled = not engine.can_use_king_skill(0)


func _on_king_skill() -> void:
	var err := engine.use_king_skill(0)
	if err != "":
		log_view.add_text(err + "\n")
		Sfx.play("error")
	grid.notify_tick()
	_battle_sounds()
	_update_battle_ui()


func _rebuild_supports() -> void:
	for c in support_box.get_children():
		support_box.remove_child(c)
		c.queue_free()
	for id in hand:
		var s := CardDatabase.get_support(id)
		var b := UiTheme.make_button("%s - %s" % [s["name"], s["description"]], 64)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 14)
		var used := (engine.used_supports[0] as Array).has(id)
		var ok := engine.is_support_implemented(id)
		if not ok:
			b.text = "%s (effect TODO)" % s["name"]
		b.disabled = used or not ok or engine.finished
		b.pressed.connect(_on_support.bind(id))
		support_box.add_child(b)


func _on_support(id: String) -> void:
	var err := engine.use_support(0, id)
	if err != "":
		log_view.add_text(err + "\n")
		Sfx.play("error")
	grid.notify_tick()
	_battle_sounds()
	_rebuild_supports()
	_update_battle_ui()


func _show_result() -> void:
	if _result_shown:
		return
	_result_shown = true
	prep.consume_used(engine.used_supports[0])  # played Support cards are spent (they return to the shop pile)
	_rebuild_supports()
	var won := engine.winner == 0
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var cc := CenterContainer.new()  # keeps the panel exactly in the middle of the screen whatever its size
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	Sfx.play("victory" if won else "defeat")
	var title := "VICTORY" if won else ("DRAW" if engine.winner < 0 else "DEFEAT")
	v.add_child(UiTheme.make_label(title, 48, UiTheme.COL_GOLD if won else UiTheme.COL_DANGER))
	v.add_child(UiTheme.make_divider())
	v.add_child(UiTheme.make_label(engine.end_reason, 18, UiTheme.COL_MUTED))
	if _tip_label != null:
		var tl := UiTheme.make_label(TutorialGuide.BATTLE["result"], 15, UiTheme.COL_GOLD)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(tl)
	v.add_child(UiTheme.make_label("Ticks: %d | Your survivors: %d | Enemy survivors: %d" % [engine.tick, engine.regulars_alive(0), engine.regulars_alive(1)], 18))
	if won and duel_context.is_empty():
		var reward := int(GameData.b("victory_gold")) + int(engine.bonus_gold[0])
		v.add_child(UiTheme.make_label("Victory reward: +%d Dominion Gold (practice: not saved)" % reward, 18, UiTheme.COL_GOLD))
	if duel_context.is_empty():
		var again := UiTheme.make_button("New Practice Battle", 56)
		again.pressed.connect(func(): get_tree().reload_current_scene())
		v.add_child(again)
		var menu := UiTheme.make_button("Main Menu", 56)
		menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
		v.add_child(menu)
	else:
		var cont := UiTheme.make_button("Continue", 60)
		cont.pressed.connect(_finish_duel)
		v.add_child(cont)


## Duel mode: report the result to the Territory Board (winner is a PLAYER id, -1 = draw).
func _finish_duel() -> void:
	var me: PlayerState = duel_context["human"]
	var opp: PlayerState = duel_context["opponent"]
	var winner_pid := -1
	var bonus := 0
	if engine.winner == 0:
		winner_pid = me.id
		bonus = int(engine.bonus_gold[0])
	elif engine.winner == 1:
		winner_pid = opp.id
		bonus = int(engine.bonus_gold[1])
	battle_finished.emit({"winner": winner_pid, "bonus_gold": bonus,
		"gold_delta": {me.id: int(engine.gold_delta[0]), opp.id: int(engine.gold_delta[1])}})


## " | Buff: name - desc" of a unit card (continent buff), "" if it has none.
func _buff_line(card_id: String) -> String:
	var bf := CardDatabase.get_buff(card_id)
	if bf.is_empty():
		return ""
	var off := "" if _own_faction == "" or GameData.is_home_faction(_own_faction, CardDatabase.active_continent) else " (inactive: foreign faction)"
	return " | Buff %s: %s%s" % [bf["name"], bf["desc"], off]
