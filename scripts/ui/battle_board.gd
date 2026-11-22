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
var prep_panel: VBoxContainer  # right column, preparation part (buttons)
var prep_left: VBoxContainer  # left column, preparation part (shop + bench)
var battle_left: VBoxContainer  # left column, battle part (log)
var battle_panel: VBoxContainer
var battle_status: Label
var support_box: VBoxContainer
var log_view: RichTextLabel
var timer: Timer
var _log_index: int = 0
var _enemy_champion: String = ""
var _enemy_hand: Array = []
var _result_shown := false
var _duel_msg: String = ""
var _tip_panel: PanelContainer = null
var _tip_label: Label = null
var _leave_dialog: ConfirmationDialog
var _start_dialog: ConfirmationDialog


func _ready() -> void:
	theme = UiTheme.get_theme()
	rng.randomize()
	if duel_context.is_empty():
		CardDatabase.set_continent(GameSession.continent_id)
		WorldMods.apply(GameData.get_continent(CardDatabase.active_continent))
		deck = SaveManager.get_deck()
		champion_id = deck.champion_id
		hand = BattleAI.pick_hand(deck, rng, 3)
		prep = BattlePrep.new(deck, rng, int(GameData.b("practice_gold")), int(GameData.b("practice_gold")), int(GameData.b("start_level")))
	else:
		var me: PlayerState = duel_context["human"]
		deck = me.deck
		champion_id = me.champion_id
		hand = BattleAI.pick_hand(deck, rng, 3)
		var budget := int(float(me.gold) * float(GameData.b("battle_budget_ratio")))
		prep = BattlePrep.new(deck, rng, me.gold, budget, me.level, me.roster, me.battle_deck)
		prep.price_mult = me.battle_price_mult()  # Quartermaster passive (prices are computed on display)
	prep.apply_hand(hand)  # Mercenary Pact / Merchant Contract act during preparation
	_build_ui()
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
	# Three columns, like the Territory Board: shop and army | the board in the middle | actions / support cards.
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

	# ---- preparation panel
	prep_left = VBoxContainer.new()
	prep_left.add_theme_constant_override("separation", 4)
	prep_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(prep_left)
	prep_panel = VBoxContainer.new()
	prep_panel.add_theme_constant_override("separation", 4)
	prep_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(prep_panel)
	shop_box = VBoxContainer.new()
	shop_box.add_theme_constant_override("separation", 3)
	prep_left.add_child(shop_box)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	prep_panel.add_child(row)
	reroll_btn = UiTheme.make_button("Reroll", 46)
	reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_btn.pressed.connect(_on_reroll)
	row.add_child(reroll_btn)
	level_btn = UiTheme.make_button("Level Up", 46)
	level_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_btn.pressed.connect(_on_level_up)
	row.add_child(level_btn)
	var auto := UiTheme.make_button("Auto Deploy", 46)
	auto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto.pressed.connect(_on_auto)
	row.add_child(auto)
	bench_grid = GridContainer.new()
	bench_grid.columns = 3
	bench_grid.add_theme_constant_override("h_separation", 4)
	bench_grid.add_theme_constant_override("v_separation", 3)
	prep_left.add_child(bench_grid)
	sel_label = UiTheme.make_label("Select a unit (bench or board), then tap a cell in your area.", 14, UiTheme.COL_MUTED)
	sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_label.max_lines_visible = 5
	sel_label.custom_minimum_size.y = 40
	sel_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prep_panel.add_child(sel_label)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	prep_panel.add_child(row2)
	bench_btn = UiTheme.make_button("To Bench", 44)
	bench_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bench_btn.pressed.connect(_on_to_bench)
	row2.add_child(bench_btn)
	sell_btn = UiTheme.make_button("Sell", 44)
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.pressed.connect(_on_sell)
	row2.add_child(sell_btn)
	hand_label = UiTheme.make_label("", 14, UiTheme.COL_MUTED)
	hand_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prep_panel.add_child(hand_label)
	message_label = UiTheme.make_label("", 14, UiTheme.COL_DANGER)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size.y = 22
	prep_panel.add_child(message_label)
	var start := UiTheme.make_primary("LOCK FORMATION\n& FIGHT", 72)
	start.pressed.connect(_on_start_pressed)
	prep_panel.add_child(start)

	# ---- battle panel
	battle_panel = VBoxContainer.new()
	battle_panel.add_theme_constant_override("separation", 6)
	battle_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_panel.visible = false
	right.add_child(battle_panel)
	battle_status = UiTheme.make_label("", 17)
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

	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.dialog_text = "Leave Battle Practice? This battle will be lost."
	_leave_dialog.ok_button_text = "Leave"
	_leave_dialog.cancel_button_text = "Stay"
	_leave_dialog.confirmed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	add_child(_leave_dialog)
	_start_dialog = ConfirmationDialog.new()
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
	status_label.text = "Gold %d | Budget %d | Level %d | Capacity %d/%d" % [prep.gold, prep.budget_left, prep.level, prep.used_capacity(), prep.capacity()]
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
			var card := CardDatabase.get_unit(id)
			b.text = "%s  [%s %s]  %d G" % [card["name"], String(card["chess"]).capitalize(), card["role"], prep.unit_price(id)]
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
		b.custom_minimum_size = Vector2(72, 48)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		if i < bench.size():
			var u := bench[i]
			b.text = "%s %s" % [String(CardDatabase.get_unit(u.card_id)["name"]).substr(0, 9), "*".repeat(u.stars)]
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
		sel_label.text = "%s %s | HP %d ATK %d | Rng %d Mov %d | cost %d | %s: %s" % [card["name"], "*".repeat(selected.stars), st["hp"], st["atk"], card["range"], card["move"], CardDatabase.capacity_cost(selected.chess()), card["skill"]["name"], card["skill"]["desc"]]
	sell_btn.disabled = selected == null
	bench_btn.disabled = selected == null or selected.cell.x < 0
	var names: Array[String] = []
	for id in hand:
		names.append(String(CardDatabase.get_support(id)["name"]))
	hand_label.text = "Hand: %s" % ", ".join(names)
	grid.selected = selected
	grid.queue_redraw()


## Errors in red; with no error the line shows the duel information (if any).
func _msg(text: String) -> void:
	message_label.text = text if text != "" else _duel_msg
	message_label.add_theme_color_override("font_color", UiTheme.COL_DANGER if text != "" else UiTheme.COL_GOLD)


func _on_buy(i: int) -> void:
	var err := prep.buy(i)
	_msg(err if err != "" else (" ".join(prep.merge_log)))
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
	engine.setup({"seed": rng.randi(), "ai_supports": [false, true], "sides": [
		prep.to_side_cfg(champion_id, hand), enemy_cfg]})
	phase = "battle"
	_set_tip(TutorialGuide.BATTLE["fight"])
	prep_panel.visible = false
	prep_left.visible = false
	battle_panel.visible = true
	battle_left.visible = true
	grid.show_engine(engine)
	_log_index = 0
	_rebuild_supports()
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
	battle_status.text = "You: %d units, HP %d   |   Enemy: %d units, HP %d" % [engine.regulars_alive(0), engine.total_hp(0), engine.regulars_alive(1), engine.total_hp(1)]
	grid.queue_redraw()


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
	_rebuild_supports()
	var won := engine.winner == 0
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	dim.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
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
