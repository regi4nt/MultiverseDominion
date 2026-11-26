extends Control
## Battle screen (Battle Chess): PREPARATION -> AUTO BATTLE -> RESULT.
## All rules live in BattlePrep / BattleEngine / BattleAI; this script only displays and forwards input.
## Two modes: Battle Chess (standalone, pays Aether Coins) and DUEL (duel_context set by the Territory Board before
## add_child: {"human","opponent","tile","human_attacks"}). In duel mode the persistent armies and the
## real Dominion Gold are used and `battle_finished(result)` is emitted when the player continues.

signal battle_finished(result: Dictionary)

var duel_context: Dictionary = {}

var prep: BattlePrep
var engine: BattleEngine
var rng := RandomNumberGenerator.new()
var terrain: Dictionary = {}  # highland cells of this duel: drawn at random every time the board opens
var deck: Deck
var champion_id: String = ""
var commander_star: int = 1  # Commander stars (duels use the player's; Battle Chess: raised by the faction missions of the run)
var _cmd: PlayerState = null  # Battle Chess run: holds the King's level and faction-mission progress (CommanderSystem.add_progress_battle)
var hand: Array = []
var phase: String = "prep"
var selected: UnitInstance
var selected_support: int = -1  # index in prep.hand of the Support card picked for selling (-1 = none)
var speed: float = 1.0

var grid: BattleGridView
var status_label: Label
var message_label: Label
var shop_box: VBoxContainer
var lineup_legend: Label  # "[Recommended]" key, shown only when the Support slots of the Lineup tab are filled
var bench_grid: GridContainer
var bench_gap: Control  # holds the bench row's height while the bench is hidden in battle, so the board keeps its size
var sel_label: Label
var sell_btn: Button
var reroll_btn: Button
var level_btn: Button
var hand_label: Label
var hand_box: VBoxContainer
var synergy_box: VBoxContainer  # top-left: faction + role synergy of the deployed units
var prep_actions: VBoxContainer  # bottom of the right column (Auto Deploy / Lock Formation), preparation only
var _own_faction: String = ""
var prep_panel: VBoxContainer  # right column, preparation part (buttons)
var prep_left: VBoxContainer  # left column, preparation part (shop + bench)
var battle_left: VBoxContainer  # left column, battle part (log)
var battle_panel: VBoxContainer
var battle_status: Label
var support_box: VBoxContainer
var energy_label: Label
var energy_bar: ProgressBar
var combo_label: Label
var king_box: VBoxContainer  # King passive (buff) + manual active skill
var king_btn: Button
var monster_btn: Button
var summon_btn: Button
var log_view: RichTextLabel
var timer: Timer
var _log_index: int = 0
var _enemy_champion: String = ""
var _enemy_hand: Array = []
var _result_shown := false
var _bm: Dictionary = {}  # Battle Chess Continent Mission of the played continent ({} in duels)
var _bm_done: bool = false
var _duel_msg: String = ""
var _tip_panel: PanelContainer = null
var _tip_label: Label = null
var _leave_dialog: UiDialog
var _start_dialog: UiDialog
var _wager: int = 0  # Battle Chess stake (already paid); a win pays stake x odds, a draw returns it
var _wager_odds: float = 2.0
var _series: String = "single"  # Battle Chess length (GameSession.battle_series): "single" | "ten" | "survival"
var _series_diff: String = "normal"  # difficulty of the run: sets the number of rounds of the multi-round run (Easy 5 / Normal 3 / Hard 1)
var _duel_rounds: int = 1  # rounds of a ruler duel inside a match: Easy 5 / Normal 3 / Hard 1 (1 = a single battle: monsters, tutorial)
var _duel_enemy_cfg: Dictionary = {}  # the enemy army of round 1, reused in the next rounds of the same duel
var _duel_bonus: Array = [0, 0]  # bonus gold of the rounds each side won
var _duel_delta: Array = [0, 0]  # gold the Support cards gave or took over all rounds
var _round: int = 1
var _wins: int = 0
var _losses: int = 0
var _draws: int = 0
var _series_coins: int = 0  # Aether Coins earned over the whole run (shown in the final summary)
var _forfeited: bool = false  # "End Run" in a 10-round run: the wager counts as lost
var _series_over: bool = false  # the run is finished (or was a single battle): the result screen offers New Battle / Main Menu
var _result_dim: ColorRect  # the result screen of the round that was just played


func _ready() -> void:
	theme = UiTheme.get_theme()
	rng.randomize()
	if duel_context.is_empty():  # Battle Chess wager: the stake was paid in New Match, the battle owns it from now on
		_wager = GameSession.wager
		_wager_odds = GameSession.wager_odds
		GameSession.wager = 0
		_series = "survival"  # every Battle Chess run is Survival; the difficulty only sets the lives
		_series_diff = String(GameSession.difficulty)
	if duel_context.is_empty():
		CardDatabase.set_continent(GameSession.continent_id)
		WorldMods.apply(GameData.get_continent(CardDatabase.active_continent))
		_bm = BattleMission.of(GameSession.continent_id)
		var deck_cont := GameSession.battle_deck_continent if GameSession.battle_deck_continent != "" else GameSession.continent_id
		GameSession.battle_deck_continent = ""
		deck = SaveManager.get_deck(deck_cont)
		champion_id = deck.champion_id
		_cmd = PlayerState.new()
		_cmd.champion_id = champion_id
		prep = BattlePrep.new(deck, rng, int(GameData.b("practice_gold")), int(GameData.b("practice_gold")), int(GameData.b("start_level")))
		prep.give_starter_pawns(int(GameData.b("starter_units")))  # Battle Chess: 3 random Pawns of the deck right at the start
		hand = prep.hand
	else:
		var me: PlayerState = duel_context["human"]
		deck = me.deck
		champion_id = me.champion_id
		commander_star = me.commander_star
		var budget := int(float(me.gold) * float(GameData.b("battle_budget_ratio")))
		prep = BattlePrep.new(deck, rng, me.gold, budget, me.level, me.roster, me.battle_deck, me.hand)
		hand = prep.hand
		prep.price_mult = me.battle_price_mult()  # Quartermaster passive (prices are computed on display)
		if not duel_context.has("monster") and not bool(duel_context.get("tutorial", false)) and duel_context.has("difficulty"):
			_duel_rounds = ShopSystem.series_rounds(String(duel_context["difficulty"]))
	terrain = Terrain.generate(rng)
	prep.set_terrain(terrain)
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
		if duel_context.has("monster"):  # monster hunt: the enemy is a wild monster, not a ruler
			_duel_msg = "MONSTER at %s - %s" % [duel_context["tile"], MonsterSystem.summary(String(duel_context["monster"]), commander_star)]
		else:
			var o: PlayerState = duel_context["opponent"]
			_duel_msg = "DUEL at %s - you %s %s." % [duel_context["tile"], "attack" if duel_context["human_attacks"] else "defend against", o.display_name]
		if _own_monster_id() != "":
			_duel_msg += "  Monster card: %s joins your King in Last Stand." % GameData.get_monster(_own_monster_id()).get("name", "?")
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
	add_child(UiTheme.make_background(CardDatabase.active_continent))  # the continent being played has its own sky and board
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
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 2.6  # 16:9 -> the board gets its full height; extra width goes to the side columns
	center.add_theme_constant_override("separation", 6)
	root.add_child(center)
	var arc := AspectRatioContainer.new()
	arc.ratio = 1.0
	arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(arc)
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
	status_label = UiTheme.make_label("", 15, UiTheme.COL_GOLD)  # 15 px so both prep lines fit the narrow column at 16:9 and 4:3
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
	sel_label = UiTheme.make_label("Select a unit from the bench, then tap a cell in your area. Tap a unit on the board, then another unit to swap places, or the preparation area to take it back.", 14, UiTheme.COL_MUTED)
	sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sel_label.max_lines_visible = 5
	sel_label.custom_minimum_size.y = 90
	prep_panel.add_child(sel_label)
	reroll_btn = UiTheme.make_button("Reroll", 46)
	reroll_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll_btn.pressed.connect(_on_reroll)
	var auto_btn := UiTheme.make_button("Auto Deploy", 46)
	auto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_btn.pressed.connect(_on_auto)
	hand_label = UiTheme.make_label("", 14, UiTheme.COL_MUTED)
	hand_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prep_panel.add_child(hand_label)
	hand_box = VBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 2)
	prep_panel.add_child(hand_box)
	bench_grid = GridContainer.new()  # the preparation bench sits directly below the board
	bench_grid.columns = int(GameData.b("prep_slots"))
	bench_grid.add_theme_constant_override("h_separation", 4)
	bench_grid.add_theme_constant_override("v_separation", 3)
	bench_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(bench_grid)
	bench_gap = Control.new()
	bench_gap.visible = false
	center.add_child(bench_gap)
	grid.resized.connect(func(): bench_grid.custom_minimum_size.x = grid.size.x)  # bench row is exactly as wide as the board
	var push := Control.new()  # pushes Auto Deploy + Level Up to the bottom
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prep_panel.add_child(push)
	prep_panel.add_child(reroll_btn)  # above Level Up
	level_btn = UiTheme.make_button("Level Up", 46)
	level_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_btn.pressed.connect(_on_level_up)
	prep_panel.add_child(level_btn)

	# ---- right column: shop + bench on top, Sell / Lock Formation in the bottom-right corner
	prep_left = VBoxContainer.new()
	prep_left.add_theme_constant_override("separation", 4)
	prep_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(prep_left)
	var legend := HBoxContainer.new()  # rarity colour key for the shop / bench borders
	legend.add_theme_constant_override("separation", 8)
	for r in ["common", "rare", "epic", "legendary"]:
		var ll := UiTheme.make_label("\u25A0 %s" % String(r).capitalize(), 12, UiTheme.rarity_color(r))
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		legend.add_child(ll)
	lineup_legend = UiTheme.make_label("[Recommended]", 12, UiTheme.COL_GOLD)
	lineup_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lineup_legend.tooltip_text = "Support cards that belong to the Support slots you set in the Lineup tab of the Card Hub"
	lineup_legend.visible = false
	legend.add_child(lineup_legend)
	prep_left.add_child(legend)
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
	prep_left.add_child(row2)  # Sell sits directly below the unit offers
	sell_btn = UiTheme.make_button("Sell", 44)
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.pressed.connect(_on_sell)
	row2.add_child(sell_btn)
	var start := UiTheme.make_primary("LOCK FORMATION\n& FIGHT", 72)
	start.pressed.connect(_on_start_pressed)
	prep_actions.add_child(auto_btn)  # Auto Deploy: bottom-right corner, above Lock Formation
	prep_actions.add_child(start)

	# ---- battle panel
	battle_panel = VBoxContainer.new()
	battle_panel.add_theme_constant_override("separation", 6)
	battle_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_panel.visible = false
	right.add_child(battle_panel)
	var speeds := HBoxContainer.new()  # Pause / 1x / 2x / 4x: bottom-left corner, under the King / Support hand
	speeds.add_theme_constant_override("separation", 6)
	var sg := ButtonGroup.new()
	for s in [["Pause", 0.0], ["1x", 1.0], ["2x", 2.0], ["4x", 4.0]]:
		var b := UiTheme.make_toggle(s[0], sg, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = (s[1] == 1.0)
		b.pressed.connect(func(): _set_speed(s[1]))
		speeds.add_child(b)
	battle_panel.add_child(UiTheme.make_label("King  %s" % CommanderSystem.star_info(commander_star), 16, UiTheme.COL_GOLD))
	king_box = VBoxContainer.new()
	king_box.add_theme_constant_override("separation", 4)
	battle_panel.add_child(king_box)
	battle_panel.add_child(UiTheme.make_label("Support hand (tap to play)", 16, UiTheme.COL_GOLD))
	support_box = VBoxContainer.new()
	support_box.add_theme_constant_override("separation", 4)
	battle_panel.add_child(support_box)
	var speed_gap := Control.new()  # pushes the speed buttons to the bottom-left corner
	speed_gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_panel.add_child(speed_gap)
	battle_panel.add_child(speeds)
	battle_left = VBoxContainer.new()
	battle_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_left.visible = false
	left.add_child(battle_left)
	# Info block (combo, energy bar, player/enemy status) sits above the history; it is NOT part of the history panel.
	combo_label = UiTheme.make_label("", 14, UiTheme.COL_GOLD)
	combo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_left.add_child(combo_label)
	energy_label = UiTheme.make_label("Energy", 15)
	battle_left.add_child(energy_label)
	energy_bar = ProgressBar.new()  # fills while the next energy point charges; a full bar wastes time
	energy_bar.custom_minimum_size = Vector2(0, 14)
	energy_bar.min_value = 0.0
	energy_bar.max_value = 1.0
	energy_bar.show_percentage = false
	battle_left.add_child(energy_bar)
	battle_status = UiTheme.make_label("", 16)
	battle_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long HP totals must not clip at the panel edge
	battle_left.add_child(battle_status)
	battle_left.move_child(battle_status, 0)  # You / Enemy status on top, the combo hint below the energy bar
	battle_left.move_child(combo_label, battle_left.get_child_count() - 1)
	var lp := PanelContainer.new()  # history panel (log only)
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_left.add_child(lp)
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", 14)
	lp.add_child(log_view)

	_leave_dialog = UiDialog.new()
	_leave_dialog.title = "Leave battle?"
	_leave_dialog.tone = "danger"
	_leave_dialog.dialog_text = ("Leave Battle Chess? This battle will be lost, pays no coins and your wager of %d coins is forfeited." % _wager) if _wager > 0 else "Leave Battle Chess? This battle will be lost and pays no coins."
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


## "Round 3 / 10  W2 L0 D1\n" (10 rounds), "Round 4  W3 L0 D1\n" (survival), "" for a single battle or a duel.
func _round_line() -> String:
	if not duel_context.is_empty():
		if _duel_rounds <= 1:
			return ""
		return "Duel round %d / %d  W%d L%d D%d\n" % [_round, _duel_rounds, _wins, _losses, _draws]
	if _series == "single":
		return ""
	var of_txt := " / %d" % ShopSystem.series_rounds(_series_diff) if _series == "ten" else ""
	var mis := ("\nKing mission: " + CommanderSystem.mission_text_battle(_cmd)) if _cmd != null else ""
	var lives_txt := "  Lives %d/%d" % [_lives_left(), ShopSystem.series_lives(_series_diff)] if _series == "survival" else ""
	return "Round %d%s  W%d L%d D%d%s%s\n" % [_round, of_txt, _wins, _losses, _draws, lives_txt, mis]


## Lives left in a Battle Chess Survival run (Easy 5 / Normal 3 / Hard 1 at the start; every defeat costs one).
func _lives_left() -> int:
	return maxi(ShopSystem.series_lives(_series_diff) - _losses, 0)


## Menu button / Android Back in Battle Chess: ask first, unless the run is already over.
func _request_leave() -> void:
	if _result_shown and _series_over:
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
		return
	var txt := "Leave Battle Chess? This battle will be lost and pays no coins."
	if _series != "single":
		txt = "Leave the run? The coins you already earned stay."
		if _wager > 0:
			txt += " Your wager of %d coins is forfeited." % _wager
	elif _wager > 0:
		txt = "Leave Battle Chess? This battle will be lost, pays no coins and your wager of %d coins is forfeited." % _wager
	_leave_dialog.dialog_text = txt
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
	status_label.text = "%sGold %d | Budget %d\nLevel %d | Capacity %d/%d" % [_round_line(), prep.gold, prep.budget_left, prep.level, prep.used_capacity(), prep.capacity()]
	if not _bm.is_empty() and duel_context.is_empty():
		status_label.text += "\nMission: %s  (+%d G)" % [BattleMission.text(_bm), BattleMission.reward_gold(_bm)]
	lineup_legend.visible = deck != null and deck.has_support_lineup()
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
				b.text = "%s  [%s Support %s, Lv %d]  %d\u00A0G\n%s" % [sc["name"], String(sc.get("rarity", "common")).capitalize(), String(sc["category"]), prep.support_level_req(id), prep.support_price(id), sc["description"]]
				b.add_theme_font_size_override("font_size", 13)
				UiTheme.apply_rarity(b, String(sc.get("rarity", "common")))
			else:
				var card := CardDatabase.get_unit(id)
				b.text = "%s  [%s %s %s]  %d\u00A0G" % [card["name"], String(card["rarity"]).capitalize(), String(card["chess"]).capitalize(), card["role"], prep.unit_price(id)]
				UiTheme.apply_rarity(b, String(card["rarity"]))
			b.disabled = prep.can_buy(i) != ""
			# Recommendation from the Lineup tab: Support offers that sit in the player's Support slots get a gold "Recommended" tag
			# with their slot number (not for a card already in the hand; units are never recommended).
			var pick := deck.is_lineup_pick(id) and not hand.has(id)
			if pick:
				b.text = "[Recommended #%d] " % (deck.support_slot_of(id) + 1) + b.text
				b.tooltip_text = deck.lineup_hint(id)
				for col_name in ["font_color", "font_hover_color", "font_pressed_color"]:
					b.add_theme_color_override(col_name, UiTheme.COL_GOLD)
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
		b.custom_minimum_size = Vector2(40, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		if i < bench.size():
			var u := bench[i]
			var ucard := CardDatabase.get_unit(u.card_id)
			b.tooltip_text = "%s (%s)" % [ucard["name"], String(ucard["rarity"]).capitalize()]
			UiTheme.apply_rarity(b, String(ucard["rarity"]))
			var bic := PieceIcon.new(u.chess(), UiTheme.rarity_color(String(ucard["rarity"])))
			bic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bic.offset_left = 4.0
			bic.offset_right = -4.0
			bic.offset_top = 6.0
			bic.offset_bottom = -4.0
			b.add_child(bic)
			if u.stars > 1:
				var st_l := UiTheme.make_label("*".repeat(u.stars), 13, UiTheme.COL_GOLD)
				st_l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				st_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				st_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
				st_l.offset_top = -2.0
				st_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(st_l)
			b.toggle_mode = true
			b.button_pressed = (u == selected)
			b.pressed.connect(_on_select.bind(u))
		else:
			b.text = "-"
			b.disabled = selected == null or selected.cell.x < 0  # an empty slot is a drop target while a deployed unit is selected
			b.pressed.connect(_on_bench_slot)
		bench_grid.add_child(b)
	if selected != null and not prep.roster.units.has(selected):
		selected = null
	if selected == null:
		sel_label.text = "Select a unit from the bench, then tap a cell in your area (rows below the gold line). Tap a unit on the board, then another unit to swap places, or the preparation area to take it back.\nHighland (peak tiles): ranged units only, +%d%% ATK. Plains: any unit." % int(float(GameData.b("highland_atk_bonus", 0.15)) * 100.0)
		sel_label.add_theme_color_override("font_color", UiTheme.COL_MUTED)
	else:
		var card := CardDatabase.get_unit(selected.card_id)
		var st := selected.stats()
		sel_label.add_theme_color_override("font_color", UiTheme.rarity_color(String(card["rarity"])))
		sel_label.text = "[%s] %s %s | HP %d ATK %d | Rng %d Mov %d | cost %d | %s: %s" % [String(card["rarity"]).capitalize(), card["name"], "*".repeat(selected.stars), st["hp"], st["atk"], card["range"], card["move"], CardDatabase.capacity_cost(selected.chess()), card["skill"]["name"], card["skill"]["desc"]] + _buff_line(selected.card_id) + "\n" + ChessMove.describe(selected.chess())
	if selected_support >= prep.hand.size() or (selected_support >= 0 and not prep.can_sell_support(prep.hand[selected_support])):
		selected_support = -1
	if selected_support >= 0:
		selected = null  # one thing is selected at a time: a unit OR a Support card
		var sid: String = prep.hand[selected_support]
		var ssc := CardDatabase.get_support(sid)
		sel_label.add_theme_color_override("font_color", UiTheme.rarity_color(String(ssc.get("rarity", "common"))))
		sel_label.text = "[%s] %s | %s" % [String(ssc.get("rarity", "common")).capitalize(), ssc["name"], ssc["description"]]
		sell_btn.text = "Sell (+%d G)" % int(prep.support_price(sid) * float(GameData.b("sell_ratio")))
	else:
		sell_btn.text = "Sell"
	sell_btn.disabled = selected == null and selected_support < 0
	hand_label.text = "Support hand (%d/%d) - tap a card, then Sell:" % [prep.hand.size(), int(GameData.b("hand_max"))]
	for c in hand_box.get_children():
		hand_box.remove_child(c)
		c.queue_free()
	for i in range(prep.hand.size()):
		var id: String = prep.hand[i]
		var hs := CardDatabase.get_support(id)
		var sellable := prep.can_sell_support(id)
		var hb := UiTheme.make_button("%s%s" % [hs["name"], "" if sellable else "  (used now)"], 34)
		hb.custom_minimum_size.y = 34
		hb.add_theme_font_size_override("font_size", 13)
		hb.tooltip_text = String(hs["description"])
		UiTheme.apply_rarity(hb, String(hs.get("rarity", "common")))
		hb.disabled = not sellable
		hb.toggle_mode = true
		hb.button_pressed = (i == selected_support)
		hb.pressed.connect(_on_select_support.bind(i))
		hand_box.add_child(hb)
	_refresh_synergy()
	grid.selected = selected
	grid.queue_redraw()


## Top-left panel: the named combos of the deployed units (ComboSystem): Faction Tier (unnamed tiers at 2 / 4 / 6 units: banner bonus + the faction's own trait in one row),
## Continent Specialties (Royal Bulwark, Rune Cascade, ...; 6 units of one faction of a continent + 6 units of its role), role traits (Iron Wall, Guardian Aura, ...) and role pacts (Frontline Shield, Glass Cannon, ...; 6 units of each of the two roles). Tap-and-hold a row for its effect.
func _refresh_synergy() -> void:
	for c in synergy_box.get_children():
		synergy_box.remove_child(c)
		c.queue_free()
	synergy_box.add_child(UiTheme.make_label("SYNERGIES", 14, UiTheme.COL_GOLD))
	var deployed := prep.deployed_units()
	if deployed.is_empty():
		synergy_box.add_child(UiTheme.make_label("Deploy units to see synergies.", 12, UiTheme.COL_MUTED))
		return
	var fac_counts := {}
	var bond_fac_counts := {}  # units per faction, any faction (Continent Alliance: 2 units of one faction in every continent)
	var role_counts := {}
	var unit_facs: Array = []  # home faction of every deployed unit ("" = none): ULTRA needs them all to be the same
	for u in deployed:
		var card := CardDatabase.get_unit(u.card_id)
		var fac := CardDatabase.effective_faction(card, _own_faction)
		if fac != "":
			bond_fac_counts[fac] = int(bond_fac_counts.get(fac, 0)) + 1
		var home := fac != "" and (fac == _own_faction or GameData.is_home_faction(fac, CardDatabase.active_continent) or (_own_faction != "" and GameData.is_home_faction(fac, GameData.continent_of_faction(_own_faction))))  # the King's own faction counts anywhere; so do the factions of the King's continent (Grand Army (Faction))
		unit_facs.append(fac if (fac != "" and fac == _own_faction) else "")  # Faction Tier / Ultra: only the King's own faction counts
		if home:
			fac_counts[fac] = int(fac_counts.get(fac, 0)) + 1
		var role := String(card.get("role", ""))
		if role != "":
			role_counts[role] = int(role_counts.get(role, 0)) + 1
	var ultra_fac := ComboSystem.faction_ultra(unit_facs)
	var inactive: Array[String] = []  # groups without a bonus yet share one muted line (keeps the panel short)
	var facs: Array = fac_counts.keys()
	facs.sort_custom(func(x, y): return int(fac_counts[x]) > int(fac_counts[y]))
	for fac in facs:
		if String(fac) != _own_faction:
			continue  # a faction different from the King's gets no Faction Tier (its units still count for Grand Army (Faction))
		var n: int = fac_counts[fac]
		var fname := String(GameData.get_faction(CardDatabase.active_continent, fac).get("name", String(fac).capitalize()))
		var is_ultra := String(fac) == ultra_fac
		var tier := ComboSystem.faction_tier_name(n, is_ultra)
		if tier == "":
			inactive.append("%s x%d" % [fname, n])
			continue
		var ftier := ComboSystem.faction_tier(String(fac), n, is_ultra)  # Faction Tier: banner bonus + faction trait in ONE row
		var nxt := int(ftier["next"])
		var fl := _synergy_row("%s%s x%d  %s%s" % ["Ultra: " if is_ultra else "", fname, n, ComboSystem.faction_tier_text(ftier), ("  (next at %d)" % nxt) if nxt > 0 and not is_ultra else ""])
		fl.tooltip_text = "Faction Tier: the faction trait for the whole faction, stronger at 2 / 4 / 6 units. %s%s" % [String(ftier["trait_blurb"]), "  ULTRA: every unit is of this faction, the faction trait is x%s, special %s: %s" % [str(ComboSystem.ULTRA_SCALE), ComboSystem.ULTRA_FACTION_SPECIAL["name"], ComboSystem.ULTRA_FACTION_SPECIAL["blurb"]] if is_ultra else "  ULTRA: field %d+ units that are ALL of this faction." % ComboSystem.ULTRA_MIN]
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl.clip_text = false
	var army_conts: Array = []  # Grand Army (Faction): the King's continent OR the played one (the closer one is shown)
	var king_cont := GameData.continent_of_faction(_own_faction) if _own_faction != "" else ""
	for ac in [king_cont, CardDatabase.active_continent]:
		if String(ac) != "" and not army_conts.has(ac):
			army_conts.append(ac)
	var cont_facs: Array = []
	for ac in army_conts:
		var ids: Array = []
		for cn in GameData.continents:
			if String(cn.get("id", "")) == String(ac):
				for cf in cn.get("factions", []):
					ids.append(String(cf["id"]))
		if cont_facs.is_empty() or ComboSystem.faction_army_lacking(fac_counts, ids) < ComboSystem.faction_army_lacking(fac_counts, cont_facs):
			cont_facs = ids
	var army_lack := ComboSystem.faction_army_missing(fac_counts, cont_facs)
	if ComboSystem.faction_army_active(fac_counts, cont_facs):
		var al := _synergy_row("%s  %s" % [ComboSystem.FACTION_ARMY["name"], ComboSystem.effects_text(ComboSystem.FACTION_ARMY["effects"])])
		al.tooltip_text = String(ComboSystem.FACTION_ARMY["blurb"])
	var bond_best := {}  # per continent: units of its best-staffed faction (Continent Alliance)
	for bf in bond_fac_counts:
		var bcid := GameData.continent_of_faction(String(bf))
		if bcid != "":
			bond_best[bcid] = maxi(int(bond_best.get(bcid, 0)), int(bond_fac_counts[bf]))
	var bond_king := GameData.continent_of_faction(_own_faction) if _own_faction != "" else ""
	var bond := ComboSystem.bonds_for(bond_best, bond_king)  # Continent Alliance: 2 units of one faction in EVERY continent, the effect of the King's continent
	if not bond.is_empty():
		var bl := _synergy_row("Continent Alliance: %s  %s" % [", ".join(PackedStringArray(bond["names"])), ComboSystem.effects_text(bond["effects"])])
		bl.tooltip_text = String(bond.get("names", [""])[0]) + ": " + String(ComboSystem.continent_bond(bond_king).get("blurb", ""))
	else:
		var have := ComboSystem.CONTINENT_BONDS.size() - ComboSystem.bond_missing(bond_best).size()
		if have >= 2:
			var pl := _synergy_row("%s: %d / %d continents" % [ComboSystem.BOND_NAME, have, ComboSystem.CONTINENT_BONDS.size()], false)
			pl.tooltip_text = "Continent Alliance: field %d units of one faction in EVERY continent. Every unit then gains the bond effect of your King's continent." % ComboSystem.BOND_FACTION_UNITS
	var cr_near: Array = []  # Continent Specialties that lack at most 3 units (and have progress in both halves): [units lacking, text]
	var cr_counts := {}  # per continent-role pairing: {"faction": units of the continent's best faction (bond_best), "role": units of that role}
	for cc in ComboSystem.CONTINENT_ROLE_COMBOS:
		cr_counts[ComboSystem.continent_role_key(String(cc["continent"]), String(cc["role"]))] = {"faction": int(bond_best.get(String(cc["continent"]), 0)), "role": int(role_counts.get(String(cc["role"]), 0))}
	for cc in ComboSystem.CONTINENT_ROLE_COMBOS:
		var crh := ComboSystem.continent_role_have(cc, cr_counts)
		var cr_lack := ComboSystem.continent_role_lacking(cc, cr_counts)
		var cr_cont := String(cc["continent"]).capitalize()
		if int(cr_lack["faction"]) == 0 and int(cr_lack["role"]) == 0:
			var crl := _synergy_row("%s  %s x%d + %s x%d  %s" % [cc["name"], cr_cont, int(crh["faction"]), cc["role"], int(crh["role"]), ComboSystem.effects_text(cc["effects"])])
			crl.tooltip_text = "Continent Specialty (%s + %s): %d units of one %s faction AND %d %ss. %s" % [cr_cont, cc["role"], ComboSystem.CONTINENT_ROLE_FACTION_UNITS, cr_cont, ComboSystem.CONTINENT_ROLE_UNITS, cc["role"], cc["blurb"]]
			crl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			crl.clip_text = false
		elif int(crh["faction"]) > 0 and int(crh["role"]) > 0 and int(cr_lack["faction"]) + int(cr_lack["role"]) <= 3:
			var cr_parts: Array[String] = []
			if int(cr_lack["faction"]) > 0:
				cr_parts.append("%d %s faction" % [int(cr_lack["faction"]), cr_cont])
			if int(cr_lack["role"]) > 0:
				cr_parts.append("%d %s" % [int(cr_lack["role"]), cc["role"]])
			cr_near.append([int(cr_lack["faction"]) + int(cr_lack["role"]), "%s (add %s)" % [cc["name"], ", ".join(PackedStringArray(cr_parts))]])
	for c in ComboSystem.ROLE_TRAITS:
		var rn := int(role_counts.get(c["role"], 0))
		if rn <= 0:
			continue
		var ti := ComboSystem.role_tier_index(c, rn)
		if ti < 0:
			inactive.append("%s x%d" % [c["name"], rn])
			continue
		var nt := ComboSystem.role_next_tier(c, rn)
		var is_role_ultra := ComboSystem.role_ultra(role_counts) == String(c["role"])
		var rl := _synergy_row("%s%s x%d  %s%s" % [c["name"], " ULTRA" if is_role_ultra else "", rn, ComboSystem.effects_text(ComboSystem.role_effects(c, rn, role_counts)), ("  (next at %d)" % nt) if nt > 0 else ""])
		var sp := ComboSystem.role_ultra_special(String(c["role"]))
		rl.tooltip_text = String(c["blurb"]) + (("  ULTRA special - %s: %s" % [sp.get("name", ""), sp.get("blurb", "")]) if is_role_ultra else "  ULTRA: field %d+ units that ALL have this role (special: %s)." % [ComboSystem.ULTRA_MIN, sp.get("name", "")])
	var near: Array = []  # role pacts (and Grand Army (Role)) that lack at most 3 units: [units lacking, text]
	for c in ComboSystem.DUO_COMBOS + [ComboSystem.ROLE_ARMY]:  # Grand Army (Role) belongs to the Grand Army family, listed after the 21 role pacts
		var lack := ComboSystem.missing_units(c, role_counts)
		if lack.is_empty():
			var dl := _synergy_row("%s  %s" % [c["name"], ComboSystem.effects_text(c["effects"])])
			dl.tooltip_text = String(c["blurb"])
			continue
		var total := 0
		var parts: Array[String] = []
		for r in lack:
			total += int(lack[r])
			parts.append("%d %s" % [int(lack[r]), r])
		if total <= 3:
			near.append([total, "%s (add %s)" % [c["name"], ", ".join(parts)]])
	var army_total := ComboSystem.faction_army_lacking(fac_counts, cont_facs)  # Grand Army (Faction) close to active: at most 3 units lacking and one faction fielded
	var army_parts: Array[String] = []
	for af in army_lack:
		army_parts.append("%d %s" % [int(army_lack[af]), String(GameData.get_faction(CardDatabase.active_continent, String(af)).get("name", String(af).capitalize()))])
	if army_parts.is_empty():
		army_parts.append("%d of any faction" % army_total)
	if army_total > 0 and army_total <= 3 and not fac_counts.is_empty():
		near.append([army_total, "%s (add %s)" % [ComboSystem.FACTION_ARMY["name"], ", ".join(army_parts)]])
	near.append_array(cr_near)
	near.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	var near_text: Array[String] = []
	for nr in near:
		near_text.append(String(nr[1]))
	if not inactive.is_empty():
		var il := _synergy_row("Needs 2 units: " + ", ".join(inactive), false)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		il.clip_text = false
	if not near_text.is_empty():
		var nl := _synergy_row("Close: " + ", ".join(near_text.slice(0, 3)), false)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.clip_text = false


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


## Tapping a Support card in the hand only selects it (tap again to deselect); the Sell button sells it.
func _on_select_support(i: int) -> void:
	selected_support = -1 if selected_support == i else i
	if selected_support >= 0:
		selected = null
	_refresh_prep()


func _on_reroll() -> void:
	_msg("" if prep.refresh_offers(true) else "Cannot afford a reroll.")
	_refresh_prep()


func _on_level_up() -> void:
	_msg(prep.level_up())
	_refresh_prep()


func _on_auto() -> void:
	BattleAI.auto_deploy(prep, 0, deck.valid_lineup())  # follows the custom Lineup of the Deck (if any)
	selected = null
	_msg("")
	_refresh_prep()


## Tapping the preparation area while a unit on the board is selected sends that unit back (replaces the "To Bench" button).
func _on_bench_slot() -> void:
	if selected != null and selected.cell.x >= 0:
		var err := prep.return_to_bench(selected)
		_msg(err)
		if err == "":
			selected = null
		_refresh_prep()


func _on_select(u: UnitInstance) -> void:
	if selected != null and selected.cell.x >= 0 and u != selected:
		var serr := prep.swap_units(selected, u)  # a deployed unit is selected: it trades places with the tapped bench unit
		_msg(serr)
		if serr == "":
			selected = null
		_refresh_prep()
		return
	selected = u
	selected_support = -1
	_refresh_prep()


func _on_sell() -> void:
	if selected_support >= 0 and selected_support < prep.hand.size():
		prep.sell_support(prep.hand[selected_support])
		selected_support = -1
		_msg("")
		_refresh_prep()
		return
	if selected != null:
		prep.sell(selected)
		selected = null
		_msg("")
		_refresh_prep()


func _on_cell(cell: Vector2i) -> void:
	if phase == "battle" and engine != null:
		# tap a unit to see its chess move area and attack area; tap it again (or an empty cell) to hide them
		var tapped: BattleUnit = engine.grid.get(cell)
		grid.inspect_unit = null if tapped == null or tapped == grid.inspect_unit else tapped
		grid.queue_redraw()
		return
	if phase != "prep":
		return
	for u in prep.deployed_units():
		if u.cell == cell:
			if selected != null and selected != u and selected.cell.x >= 0:  # a unit on the board is selected: swap the two
				var serr := prep.swap_units(selected, u)
				_msg(serr)
				if serr == "":
					selected = null
				_refresh_prep()
				return
			selected = u  # tapping a deployed unit selects it; tap the preparation area to send it back
			selected_support = -1
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
		var enemy_level := prep.level  # the enemy's level (shop level / capacity) follows OURS, not the King level; it grows only through its budget
		# The AI follows the MAP continent (King of that continent + its units); only the player's army is the personal Card Hub deck.
		_enemy_champion = BattleAI.pick_continent_champion(rng, CardDatabase.active_continent, champion_id)
		var enemy_deck := BattleAI.continent_deck(CardDatabase.active_continent, _enemy_champion)
		var enemy_prep := BattleAI.build_enemy(diff, enemy_level, rng, enemy_deck, terrain, ShopSystem.series_budget_mult(_round))
		_enemy_hand = BattleAI.pick_hand(enemy_deck, rng, 2)
		commander_star = _cmd.commander_star if _cmd != null else 1  # YOUR King levels up through its faction missions
		var enemy_star := ShopSystem.series_king_star(_series, _round)  # the enemy King levels up as the rounds go on (Lv 2 from round 4, Lv 3 from round 7)
		enemy_cfg = enemy_prep.to_side_cfg(_enemy_champion, _enemy_hand, enemy_star)
	else:
		var me: PlayerState = duel_context["human"]
		prep.finish()  # unbought offers go back to the pile; spending is permanent
		me.gold = prep.gold
		me.level = prep.level
		me.capacity = prep.capacity()
		if duel_context.has("monster"):
			enemy_cfg = {"units": [], "champion": "", "supports": [], "foes": [String(duel_context["monster"])], "foe_star": commander_star}  # same side config as MonsterSystem.fight
		elif _round > 1 and not _duel_enemy_cfg.is_empty():
			enemy_cfg = _duel_enemy_cfg.duplicate(true)  # later rounds of the duel: the same enemy army (the AI does not shop again)
		else:
			enemy_cfg = BattleAI.prepare_ai_army(duel_context["opponent"], rng, 1, terrain)
			_duel_enemy_cfg = enemy_cfg.duplicate(true)
	_bm_done = false
	engine = BattleEngine.new()
	engine.setup({"seed": rng.randi(), "ai_supports": [false, true], "manual_king": [true, false], "king_skill_locked": [_king_skill_locked(), false], "terrain": terrain, "sides": [
		prep.to_side_cfg(champion_id, hand, commander_star, _own_monster_id(), _own_monster_star()), enemy_cfg]})
	phase = "battle"
	_set_tip(TutorialGuide.BATTLE["fight"])
	prep_panel.visible = false
	prep_left.visible = false
	bench_gap.custom_minimum_size.y = bench_grid.get_combined_minimum_size().y  # keep the bench row's space: the board must not grow ("zoom") when the fight starts
	bench_gap.visible = true
	bench_grid.visible = false
	prep_actions.visible = false
	battle_panel.visible = true
	battle_left.visible = true
	grid.show_engine(engine)
	_log_index = 0
	_rebuild_supports()
	_rebuild_king()
	_set_speed(speed if _round > 1 else 1.0)  # later rounds keep the speed the player picked


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
			"last_stand":
				Sfx.play("portal")
			"check":
				Sfx.play("error")
			"mate":
				Sfx.play("defeat" if int(ev["side"]) == 0 else "victory")
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
	_check_battle_mission()
	_battle_sounds()
	_update_battle_ui()
	if engine.finished:
		timer.stop()
		for ev in engine.events:
			if ev["type"] == "mate":  # let the CHECKMATE banner be seen before the result screen covers it
				await get_tree().create_timer(1.4).timeout
				break
		_show_result()


## Battle Chess mission: completes live (or when the battle ends); the Gold goes straight to the preparation panel.
func _check_battle_mission() -> void:
	if _bm.is_empty() or _bm_done or not duel_context.is_empty() or not BattleMission.is_done(_bm, engine):
		return
	_bm_done = true
	var g := BattleMission.reward_gold(_bm)
	prep.gold += g
	prep.budget_left += g
	log_view.add_text("MISSION COMPLETE! %s: +%d gold.\n" % [String(_bm.get("name", "")), g])


func _update_battle_ui() -> void:
	while _log_index < engine.log_lines.size():
		log_view.add_text(engine.log_lines[_log_index] + "\n")
		_log_index += 1
	status_label.text = "%sTick %d / %d" % [_round_line(), engine.tick, BattleEngine.MAX_TICKS]
	battle_status.text = "You: %d units, HP %d\nEnemy: %d units, HP %d" % [engine.regulars_alive(0), engine.total_hp(0), engine.regulars_alive(1), engine.total_hp(1)]
	if not _bm.is_empty() and duel_context.is_empty():
		battle_status.text += "\n" + BattleMission.status_line(_bm, engine, _bm_done)
	_refresh_king_btn()
	_refresh_energy()
	grid.queue_redraw()


## King level the human duelist's Monster card was won at (its ally stats).
func _own_monster_star() -> int:
	if duel_context.is_empty():
		return 1
	return (duel_context["human"] as PlayerState).monster_star


## Monster card of the human duelist ("" in Battle Chess or when none was won): it joins the King in Last Stand.
func _own_monster_id() -> String:
	if duel_context.is_empty():
		return ""
	return (duel_context["human"] as PlayerState).monster_id


## King panel: Passive (every continent), Buff (home continent only) and the active skill, cast by hand once the King is in the arena.
func _rebuild_king() -> void:
	for c in king_box.get_children():
		king_box.remove_child(c)
		c.queue_free()
	king_btn = null
	monster_btn = null
	summon_btn = null
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
	var mid := _own_monster_id()
	if mid != "":
		var ml := UiTheme.make_label("Monster card - %s\nJoins your King when he enters Last Stand; its skill is cast by hand below." % MonsterSystem.summary(mid, _own_monster_star()), 13, UiTheme.COL_GOLD)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		king_box.add_child(ml)
	summon_btn = UiTheme.make_button("", 56)
	summon_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summon_btn.add_theme_font_size_override("font_size", 14)
	summon_btn.pressed.connect(_on_summon_king)
	king_box.add_child(summon_btn)
	king_btn = UiTheme.make_button("", 64)
	king_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	king_btn.add_theme_font_size_override("font_size", 14)
	king_btn.pressed.connect(_on_king_skill)
	king_box.add_child(king_btn)
	if mid != "":  # the Monster card has its own active skill, cast like the King skill
		monster_btn = UiTheme.make_button("", 64)
		monster_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		monster_btn.add_theme_font_size_override("font_size", 14)
		monster_btn.pressed.connect(_on_monster_skill)
		king_box.add_child(monster_btn)
	_refresh_king_btn()


func _refresh_king_btn() -> void:
	if king_btn == null:
		return
	if summon_btn != null:
		var cost := engine.king_summon_cost()
		summon_btn.visible = not bool(engine.king_entered[0])
		summon_btn.text = "[%d E] SUMMON KING now\n(skip waiting for Last Stand; %d/%d energy)" % [cost, int(engine.energy[0]), cost]
		summon_btn.disabled = not engine.can_summon_king(0)
	var ch := GameData.get_champion(champion_id)
	var base := "[%d E] %s - %s" % [engine.king_energy_cost(), ch.get("active_name", "King skill"), ch.get("active_desc", "")]
	if bool(engine.king_skill_locked[0]):
		king_btn.text = "%s\n(LOCKED: needs B2, a second copy of this King card)" % ch.get("active_name", "King skill")
	elif bool(engine.king_skill_used[0]):
		king_btn.text = "%s (used)" % ch.get("active_name", "King skill")
	elif not bool(engine.king_entered[0]):
		king_btn.text = "%s\n(available once the King enters in Last Stand)" % base
	elif int(engine.energy[0]) < engine.king_energy_cost():
		king_btn.text = "%s\n(not enough energy: %d/%d)" % [base, int(engine.energy[0]), engine.king_energy_cost()]
	else:
		king_btn.text = "USE: %s" % base
	king_btn.disabled = not engine.can_use_king_skill(0)
	_refresh_monster_btn()


func _refresh_monster_btn() -> void:
	if monster_btn == null:
		return
	var m := GameData.get_monster(_own_monster_id())
	var cost := engine.monster_energy_cost()
	var base := "[%d E] %s - %s" % [cost, m.get("active_name", "Monster skill"), m.get("active_desc", "")]
	if bool(engine.monster_skill_used[0]):
		monster_btn.text = "%s (used)" % m.get("active_name", "Monster skill")
	elif engine.monster_unit[0] == null:
		monster_btn.text = "%s\n(available once the Monster joins the King)" % base
	elif engine.ally_monster(0) == null:
		monster_btn.text = "%s\n(the Monster has fallen)" % base
	elif int(engine.energy[0]) < cost:
		monster_btn.text = "%s\n(not enough energy: %d/%d)" % [base, int(engine.energy[0]), cost]
	else:
		monster_btn.text = "USE: %s" % base
	monster_btn.disabled = not engine.can_use_monster_skill(0)


func _on_summon_king() -> void:
	var err := engine.summon_king(0)
	if err != "":
		log_view.add_text(err + "\n")
		Sfx.play("error")
	grid.notify_tick()
	_battle_sounds()
	_update_battle_ui()


func _on_king_skill() -> void:
	var err := engine.use_king_skill(0)
	if err != "":
		log_view.add_text(err + "\n")
		Sfx.play("error")
	grid.notify_tick()
	_battle_sounds()
	_update_battle_ui()


func _on_monster_skill() -> void:
	var err := engine.use_monster_skill(0)
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
	for id in deck.order_hand(hand):  # follows the Support slots of the Lineup tab
		var s := CardDatabase.get_support(id)
		var b := UiTheme.make_button("[%d E] %s - %s" % [engine.support_energy_cost(id), s["name"], s["description"]], 64)
		b.set_meta("sid", id)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 14)
		var used := (engine.used_supports[0] as Array).has(id)
		var ok := engine.is_support_implemented(id)
		if not ok:
			b.text = "%s (effect TODO)" % s["name"]
		b.disabled = used or not ok or engine.finished or int(engine.energy[0]) < engine.support_energy_cost(id)
		b.pressed.connect(_on_support.bind(id))
		support_box.add_child(b)
	_refresh_energy()


## Energy bar + label, and which Support cards are affordable right now (called every tick).
func _refresh_energy() -> void:
	if energy_label == null or engine == null:
		return
	var e := int(engine.energy[0])
	energy_label.text = "Energy %d / %d%s" % [e, engine.energy_max(), "  (full - use it!)" if e >= engine.energy_max() else ""]
	energy_bar.value = engine.energy_progress(0)
	var chain := engine.combo_active(0)
	if chain > 0:
		var left := maxf(0.0, float(engine.combo_window() - (engine.tick - int(engine.combo_last_tick[0]))) * 0.25)
		combo_label.text = "Combo x%d (%s): play another %s card within %.1fs for +%d energy back" % [chain, String(engine.combo_category[0]).capitalize(), String(engine.combo_category[0]).capitalize(), left, mini(chain, int(GameData.b("combo_refund_max", 2)))]
	else:
		combo_label.text = "Combo: play Support cards of the same category back to back to get energy back"
	for b in support_box.get_children():
		if b is Button and b.has_meta("sid"):
			var sid := String(b.get_meta("sid"))
			var used := (engine.used_supports[0] as Array).has(sid)
			b.disabled = used or not engine.is_support_implemented(sid) or engine.finished or e < engine.support_energy_cost(sid)


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
	if duel_context.is_empty():
		if not _bm.is_empty():
			_check_battle_mission()  # end-of-battle goals (win with survivors, flawless, fast win) are decided now
			var done_txt := "Mission complete: %s  +%d gold%s" % [String(_bm.get("name", "")), BattleMission.reward_gold(_bm), " (kept for the next round)" if _series != "single" else ""]
			var fail_txt := "Mission failed: %s" % BattleMission.text(_bm)
			v.add_child(UiTheme.make_label(done_txt if _bm_done else fail_txt, 18, Color("59cd90") if _bm_done else UiTheme.COL_MUTED))
		_result_dim = dim
		_result_rewards(v, won)
	else:
		if duel_context.has("monster"):
			var mt := "You win the Monster card: it fights beside your King in Duels." if won else "The monster holds its lair and you lose %d G." % int(GameData.b("monster_defeat_gold"))
			var ml := UiTheme.make_label(mt, 16, UiTheme.COL_GOLD if won else UiTheme.COL_DANGER)
			ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(ml)
		if _duel_rounds > 1 and not duel_context.has("monster"):
			_tally_duel_round()  # once per round: _result_shown guards this screen
			var opp_name := String((duel_context["opponent"] as PlayerState).display_name)
			v.add_child(UiTheme.make_label("Duel round %d / %d  |  Won %d  Lost %d  Drawn %d" % [_round, _duel_rounds, _wins, _losses, _draws], 20, UiTheme.COL_TEXT))
			if _round < _duel_rounds:
				var nxt_d := UiTheme.make_button("Next Round", 60)
				nxt_d.pressed.connect(_next_round)
				v.add_child(nxt_d)
				return
			var verdict := "You win the duel against %s." % opp_name if _wins > _losses else ("You lose the duel against %s." % opp_name if _losses > _wins else "The duel against %s ends in a draw." % opp_name)
			var vl := UiTheme.make_label(verdict, 18, UiTheme.COL_GOLD if _wins > _losses else UiTheme.COL_DANGER)
			vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(vl)
		var cont := UiTheme.make_button("Continue", 60)
		cont.pressed.connect(_finish_duel)
		v.add_child(cont)


## Battle Chess run (10 rounds / Survival): counts this round for the King's faction mission (CommanderSystem, "bc_*" metrics:
## rounds won, enemy units destroyed, King skill used, survivors of won rounds). A new level applies from the next round.
## Returns the line shown on the result screen ("" for a single battle: there is no next round to level up for).
func _bc_mission_update(won: bool) -> String:
	if _cmd == null or _series == "single":
		return ""
	var before := _cmd.commander_star
	var counts := [["bc_wins", 1 if won else 0], ["bc_kills", int(engine.kills[0])], ["bc_king_skill", 1 if bool(engine.king_skill_used[0]) else 0], ["bc_survivors", engine.regulars_alive(0) if won else 0]]
	for cnt in counts:
		CommanderSystem.add_progress_battle(_cmd, String(cnt[0]), int(cnt[1]))
	commander_star = _cmd.commander_star
	var line := "King mission: " + CommanderSystem.mission_text_battle(_cmd)
	if _cmd.commander_star > before:
		line = "COMMANDER UP! Your King reaches %s from the next round.  " % CommanderSystem.star_text(_cmd.commander_star) + line
	return line


## Battle Chess result: coins of this round, then either "Next Round" (the run goes on) or the final summary + wager.
func _result_rewards(v: VBoxContainer, won: bool) -> void:
	var draw := engine.winner < 0
	if won:
		_wins += 1
	elif draw:
		_draws += 1
	else:
		_losses += 1
	var coins := SaveManager.record_practice(won, String(GameSession.difficulty))  # once per round: _result_shown guards this screen
	var bonus := ShopSystem.series_coin_bonus(_series, _round) if won else 0
	if bonus > 0:
		SaveManager.add_coins(bonus)
		SaveManager.save_game()
	coins += bonus
	_series_coins += coins
	var cmd_line := _bc_mission_update(won)
	v.add_child(UiTheme.make_label(SaveManager.xp_line(), 18, UiTheme.COL_GOLD))
	var goes_on := ShopSystem.series_continues(_series, _round, _losses, _series_diff)
	_series_over = not goes_on
	if _series != "single":
		var lives_part := "  |  Lives %d/%d" % [_lives_left(), ShopSystem.series_lives(_series_diff)] if _series == "survival" else ""
		v.add_child(UiTheme.make_label("Round %d%s  |  Won %d  Lost %d  Drawn %d%s" % [_round, " / %d" % ShopSystem.series_rounds(_series_diff) if _series == "ten" else "", _wins, _losses, _draws, lives_part], 20, UiTheme.COL_TEXT))
		if _series == "survival" and not won and not draw and goes_on:
			v.add_child(UiTheme.make_label("You lose a life. The run goes on.", 16, UiTheme.COL_DANGER))
	if bonus > 0:
		v.add_child(UiTheme.make_label("Aether Coins: +%d  (round bonus +%d, total %d)" % [coins, bonus, SaveManager.coins()], 20, UiTheme.COL_GOLD))
	else:
		v.add_child(UiTheme.make_label("Aether Coins: +%d  (total %d)" % [coins, SaveManager.coins()], 20, UiTheme.COL_GOLD))
	if goes_on:
		var income := ShopSystem.series_income(_round)
		var next_star := ShopSystem.series_king_star(_series, _round + 1)
		var king_up := "  The enemy King reaches %s." % CommanderSystem.star_text(next_star) if next_star > ShopSystem.series_king_star(_series, _round) else ""
		v.add_child(UiTheme.make_label("Next: round %d. You get +%d gold and keep your army; the enemy grows stronger.%s" % [_round + 1, income, king_up], 16, UiTheme.COL_MUTED))
		if cmd_line != "":
			var ml := UiTheme.make_label(cmd_line, 16, UiTheme.COL_GOLD)
			ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(ml)
		var nxt := UiTheme.make_button("Next Round", 60)
		nxt.pressed.connect(_next_round)
		v.add_child(nxt)
		var quit := UiTheme.make_button("End Run", 52)
		quit.pressed.connect(func(): _end_run_early(v, nxt, quit))
		v.add_child(quit)
		return
	_finish_series(v, won)


## The run is over (single battle done, 10 rounds played, or the survival run ended): summary, wager, buttons.
func _finish_series(v: VBoxContainer, won: bool) -> void:
	var outcome := "loss" if _forfeited else ShopSystem.series_outcome(_series, _wins, _losses, 0 if won else (-1 if engine.winner < 0 else 1))
	if _series != "single":
		var head := "RUN COMPLETE" if _series == "ten" else "RUN ENDED"
		v.add_child(UiTheme.make_label("%s: %s  |  %d won, %d lost, %d drawn  |  %d coins earned" % [head, ShopSystem.series_title(_series, _series_diff), _wins, _losses, _draws, _series_coins], 20, UiTheme.COL_GOLD))
	if _wager > 0:
		var paid := SaveManager.settle_wager(_wager, outcome, _wager_odds)
		match outcome:
			"win":
				v.add_child(UiTheme.make_label("Wager won: +%d coins (stake %d, x%s)" % [paid, _wager, str(snappedf(_wager_odds, 0.01))], 20, UiTheme.COL_GOLD))
			"draw":
				v.add_child(UiTheme.make_label("Draw: wager of %d coins returned" % paid, 20, UiTheme.COL_GOLD))
			_:
				v.add_child(UiTheme.make_label("Wager lost: -%d coins" % _wager, 20, UiTheme.COL_DANGER))
		_wager = 0  # settled once
	var again := UiTheme.make_button("New Battle", 56)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	v.add_child(again)
	var menu := UiTheme.make_button("Main Menu", 56)
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	v.add_child(menu)


## "End Run" between two rounds: the run stops now. 10 Rounds: a stake is forfeited (no cashing out after a good start);
## Survival: the wager is judged by the rounds cleared so far.
func _end_run_early(v: VBoxContainer, nxt: Button, quit: Button) -> void:
	nxt.queue_free()
	quit.queue_free()
	_series_over = true
	if _series == "ten" and _wager > 0:
		v.add_child(UiTheme.make_label("Run ended early: the wager is forfeited.", 18, UiTheme.COL_DANGER))
		_forfeited = true
	_finish_series(v, true)


## Next round of a run: same army, gold + income, new shop, new ground; back to preparation.
func _next_round() -> void:
	var played := _round
	_round += 1
	prep.start_next_round(ShopSystem.series_income(played) if duel_context.is_empty() else 0)  # a duel gives no income: the real Dominion Gold is used
	prep.capacity_bonus = 0  # Mercenary Pact lasts one battle
	terrain = Terrain.generate(rng)
	prep.set_terrain(terrain)
	if _result_dim != null:
		_result_dim.queue_free()
		_result_dim = null
	_result_shown = false
	engine = null
	phase = "prep"
	selected = null
	selected_support = -1
	log_view.clear()
	_log_index = 0
	battle_panel.visible = false
	battle_left.visible = false
	prep_panel.visible = true
	prep_left.visible = true
	bench_gap.visible = false
	bench_grid.visible = true
	prep_actions.visible = true
	grid.show_prep(prep)
	_msg("")
	_refresh_prep()


## Multi-round duel: adds the round that was just fought to the score and to the gold totals.
func _tally_duel_round() -> void:
	if engine.winner == 0:
		_wins += 1
		_duel_bonus[0] += int(engine.bonus_gold[0])
	elif engine.winner == 1:
		_losses += 1
		_duel_bonus[1] += int(engine.bonus_gold[1])
	else:
		_draws += 1
	_duel_delta[0] += int(engine.gold_delta[0])
	_duel_delta[1] += int(engine.gold_delta[1])


## Duel mode: report the result to the Territory Board (winner is a PLAYER id, -1 = draw).
func _finish_duel() -> void:
	var me: PlayerState = duel_context["human"]
	if duel_context.has("monster"):  # monster hunt: only a victory counts (a draw / timeout = the monster holds its lair)
		battle_finished.emit({"monster": true, "won": engine.winner == 0, "ticks": engine.tick, "gold_delta": int(engine.gold_delta[0])})
		return
	var opp: PlayerState = duel_context["opponent"]
	var winner_pid := -1
	var bonus := 0
	if _duel_rounds > 1:  # multi-round duel: more rounds won than lost wins it, equal = draw (the defender keeps the tile)
		if _wins > _losses:
			winner_pid = me.id
			bonus = int(_duel_bonus[0])
		elif _losses > _wins:
			winner_pid = opp.id
			bonus = int(_duel_bonus[1])
		battle_finished.emit({"winner": winner_pid, "bonus_gold": bonus,
			"gold_delta": {me.id: int(_duel_delta[0]), opp.id: int(_duel_delta[1])}})
		return
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


## The King's active skill is locked while the player's King is below B2 (a second copy of the King card). The tutorial has no lock.
func _king_skill_locked() -> bool:
	return GameSession.mode != "tutorial" and not SaveManager.king_battle_skill_unlocked(champion_id)
