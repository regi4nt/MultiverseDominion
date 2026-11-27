extends Control
## Territory Board screen: board in the middle (dice + actions in its centre), log left, players right.
## All game rules live in MatchController; this script only displays and forwards input.

var ctrl: MatchController
var board_view: BoardView
var _centre: PanelContainer
var round_label: Label
var _mission_lines: Array[String] = []  # result-screen lines about the mission reward
var _mission_text: RichTextLabel  # ONE mission UI: the King mission line + the Continent mission line (Arena / Chaos)
var _mission_panel: PanelContainer
var turn_label: Label
var player_box: VBoxContainer
var action_box: HFlowContainer
var log_view: RichTextLabel
var tick: Timer
var _leave_dialog: UiDialog
var _wager_paid: int = 0  # coins paid out by the Arena wager at the end of the match
var _stats_saved := false
var _duel_node: Control = null
const GamblePanel := preload("res://scripts/ui/gamble_panel.gd")

var _casino_node: Control = null  # the Casino overlay (the Gamble games played with gold) while a human is at a Casino tile
var _hub_node: Control = null  # the Card Hub overlay (Collection / Deck / Info) while it is open
var _hub_prev_continent: String = ""
var _guide: TutorialGuide = null
var _new_card: String = ""
var _chest: Dictionary = {}  # reward chest of an Arena win (ChestSystem.award result), {} = none
var _journey_lines: Array[String] = []  # Journey trophies / opened continents shown on the result screen
var _hint_panel: PanelContainer
var _hint_label: Label
var _backdrop: TextureRect
var _pan_key: String = ""  # "round:player" of the last turn the camera was moved for


func _ready() -> void:
	theme = UiTheme.get_theme()
	_build_ui()
	ctrl = null
	if GameSession.resume_match:
		var saved := SaveManager.load_match()
		if not saved.is_empty():
			ctrl = MatchController.from_dict(saved)
		GameSession.resume_match = false
	if ctrl == null:
		ctrl = MatchController.new()
		ctrl.setup(GameSession.to_match_config())
		GameSession.wager = 0  # the stake now belongs to the match (Play Again starts without a wager)
	ctrl.monster_battles_interactive = true  # a monster fight is played in the Battle scene, like a Duel
	ctrl.log_added.connect(_on_log)
	ctrl.monster_event.connect(_on_monster_event)
	ctrl.deposit_event.connect(_on_deposit_event)
	ctrl.state_changed.connect(_on_state_changed)
	ctrl.players_changed.connect(_refresh_players)
	ctrl.dice_rolled.connect(_on_dice)
	ctrl.player_moved.connect(_on_moved)
	ctrl.game_over.connect(_on_game_over)
	board_view.bind(ctrl)
	_backdrop.texture = UiTheme.backdrop_texture(String(ctrl.continent.get("id", "")))  # the continent's own sky
	board_view.speed_changed.connect(_on_speed_changed)
	board_view.tile_pressed.connect(func(i: int): board_view.info_text = ctrl.describe_tile(i))
	for line in ctrl.recent_log:  # lines logged before the UI was connected (match start / resumed match)
		log_view.add_text(line + "\n")
	SaveManager.app_paused.connect(_autosave)
	_refresh_players()
	_on_state_changed()
	board_view.info_text = "Tap a tile to inspect it.  RR = reroll tokens, SD = special dice."
	if WorldMods.modifier_name != "":
		board_view.info_text = "World modifier - %s: %s" % [WorldMods.modifier_name, ctrl.continent["modifier"].get("description", "")]
	if ctrl.tutorial:
		_guide = TutorialGuide.new(ctrl)
		_guide.hint.connect(_on_hint)
		ctrl.state_changed.emit()  # let the coach see the first state
	tick = Timer.new()
	tick.wait_time = 0.8 / BoardView.speed_mult
	tick.timeout.connect(_on_tick)
	add_child(tick)
	tick.start()


func _build_ui() -> void:
	_backdrop = UiTheme.make_background()  # re-skinned for the continent once the match exists
	add_child(_backdrop)
	var margin := UiTheme.make_margin(12)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# Three columns, Monopoly style: log | the board in the middle with the dice and actions | players and info (sides swapped).
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)

	var arc := AspectRatioContainer.new()
	arc.ratio = 1.0
	arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arc.size_flags_stretch_ratio = 2.6  # 16:9 -> the board gets its full height; extra width goes to the side columns
	root.add_child(arc)
	var holder := Control.new()  # square holder: the board fills it
	arc.add_child(holder)
	board_view = BoardView.new()
	board_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(board_view)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(230, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	# Layout (screen order left | board | right): LEFT = Card Hub + players, RIGHT = round / Menu with the history (log) below it.
	# Bottom-left corner = zoom + Speed, bottom-right corner = the action buttons (Roll Dice, ...).

	# --- right column (top): round + Menu
	var head := HBoxContainer.new()
	right.add_child(head)
	round_label = UiTheme.make_label("Round 1", 22, UiTheme.COL_GOLD)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(round_label)
	var menu := UiTheme.make_button("Menu", 44)
	menu.custom_minimum_size.x = 96
	menu.pressed.connect(func(): _leave_dialog.popup_centered(Vector2i(460, 160)))
	head.add_child(menu)
	_mission_panel = PanelContainer.new()  # under Menu: ONE box with the King mission and (Arena / Chaos) the continent mission
	_mission_panel.visible = false
	_mission_panel.add_theme_stylebox_override("panel", UiTheme.make_box(Color("2a2150"), UiTheme.COL_GOLD, 2, 10))
	right.add_child(_mission_panel)
	_mission_text = RichTextLabel.new()
	_mission_text.bbcode_enabled = true
	_mission_text.fit_content = true
	_mission_text.scroll_active = false
	_mission_text.mouse_filter = Control.MOUSE_FILTER_IGNORE  # drags and taps pass through; the tooltip sits on the panel
	_mission_text.add_theme_font_size_override("normal_font_size", 15)
	_mission_text.add_theme_font_size_override("bold_font_size", 15)
	_mission_panel.add_child(_mission_text)
	var hub_btn := UiTheme.make_button(GameSession.CARD_HUB_NAME, 48)  # Collection / Deck / Info without leaving the match
	hub_btn.pressed.connect(_open_hub)
	left.add_child(hub_btn)
	_leave_dialog = UiDialog.new()
	_leave_dialog.title = "Leave match?"
	_leave_dialog.dialog_text = "Leave to the main menu? The match is saved at the start of each of your turns and can be continued."
	_leave_dialog.ok_button_text = "Leave"
	_leave_dialog.cancel_button_text = "Stay"
	_leave_dialog.confirmed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	add_child(_leave_dialog)

	# The player cards live in a scroll area that takes the free height: when the floating action panel (bottom-right) grows,
	# the cards scroll instead of sliding under it.
	var players_scroll := UiTheme.make_scroll()
	players_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(players_scroll)
	player_box = VBoxContainer.new()
	player_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_box.add_theme_constant_override("separation", 8)
	players_scroll.add_child(player_box)

	_hint_panel = PanelContainer.new()  # Tutorial coach (hidden in normal matches)
	_hint_panel.visible = false
	_hint_panel.add_theme_stylebox_override("panel", UiTheme.make_box(Color("2a2150"), UiTheme.COL_GOLD, 2, 10))
	left.add_child(_hint_panel)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	_hint_panel.add_child(hv)
	_hint_label = UiTheme.make_label("", 15, UiTheme.COL_TEXT)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(_hint_label)
	var hide_btn := UiTheme.make_button("OK", 52)
	hide_btn.pressed.connect(func(): _hint_panel.visible = false)
	hv.add_child(hide_btn)

	# --- right column: history under the Menu
	var log_panel := PanelContainer.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(log_panel)
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", 15)
	log_panel.add_child(log_view)

	# --- bottom-RIGHT corner of the screen: whose turn it is + the action buttons (Roll Dice, Reroll, Move, End Turn, Buy, Tax / Duel, ...).
	# It floats over the corner of the log column (a spacer below keeps the log clear of it); the board itself stays
	# uncovered: only the dice ANIMATION is drawn inside the map (BoardView).
	var corner_gap := Control.new()
	corner_gap.custom_minimum_size = Vector2(0, 120)  # follows the real height of the action panel (see _centre.resized below)
	right.add_child(corner_gap)  # `right` is the column on the right (menu + log)
	_centre = PanelContainer.new()
	_centre.add_theme_stylebox_override("panel", UiTheme.make_box(Color(UiTheme.COL_PANEL, 0.96), UiTheme.COL_GOLD_DIM, 2, 10))
	add_child(_centre)
	_centre.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_centre.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_centre.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_centre.offset_left = -12
	_centre.offset_bottom = -12
	_centre.offset_right = -12
	_centre.offset_top = -12
	var centre := _centre  # bottom-right corner: clear of the camera bezel / system bar on the right edge
	UiTheme.follow_insets(centre, func(ins: Vector2) -> void:
		centre.offset_left = -12.0 - ins.y
		centre.offset_right = -12.0 - ins.y)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	_centre.add_child(cv)
	_centre.resized.connect(func(): corner_gap.custom_minimum_size.y = _centre.size.y + 8.0)
	turn_label = UiTheme.make_label("", 20)
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	turn_label.custom_minimum_size.x = 230
	cv.add_child(turn_label)
	action_box = HFlowContainer.new()
	action_box.alignment = FlowContainer.ALIGNMENT_BEGIN
	action_box.add_theme_constant_override("h_separation", 8)
	action_box.add_theme_constant_override("v_separation", 8)
	cv.add_child(action_box)

	# --- bottom-LEFT corner of the screen: zoom (+, -, Fit) and Speed, taken over from the board view.
	var map_controls := board_view.take_controls()
	var left_gap := Control.new()
	left_gap.custom_minimum_size = Vector2(0, 64)
	left.add_child(left_gap)  # `left` is the column on the left (Card Hub + players)
	add_child(map_controls)
	map_controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	map_controls.grow_horizontal = Control.GROW_DIRECTION_END
	map_controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_controls.offset_left = 12
	map_controls.offset_bottom = -12
	map_controls.offset_right = 12
	map_controls.offset_top = -12
	UiTheme.follow_insets(map_controls, func(ins: Vector2) -> void:  # bottom-left corner: clear of the bezel on the left edge
		map_controls.offset_left = 12.0 + ins.x
		map_controls.offset_right = 12.0 + ins.x)


# ------------------------------------------------------------------ signals

func _on_tick() -> void:
	if ctrl.state == MatchController.State.GAME_OVER or board_view.is_busy() or _duel_node != null or _hub_node != null:
		return  # the match waits while a duel or the Card Hub is open
	var p := ctrl.current_player()
	if ctrl.state == MatchController.State.AWAIT_DUEL:
		if not ctrl.is_human_duel() and not ctrl.is_monster_battle():
			AIController.step(ctrl)  # AI vs AI: resolved instantly
	elif ctrl.state == MatchController.State.AWAIT_DECISION:
		if ctrl.decision_actor().is_ai:
			AIController.step(ctrl)
	elif p.is_ai:
		AIController.step(ctrl)
	elif ctrl.state == MatchController.State.ROLLED and p.reroll_tokens <= 0:
		ctrl.confirm_move()  # nothing to decide: move automatically


func _on_log(text: String) -> void:
	if text.contains(" buys ") or text.contains("Victory Reward") or text.contains("passes the Dominion Gate") or text.begins_with("Hidden treasure!") or text.begins_with("Hidden mine!"):
		Sfx.play("coin")
	elif text.contains("loses 1 Life") or text.contains("BANKRUPT"):
		Sfx.play("error")
	log_view.add_text(text + "\n")


## A human ruler fought a hidden monster: show the outcome (the lair itself is never marked on the map).
func _on_monster_event(pid: int, result: String, monster_id: String) -> void:
	if result == "fled" or pid < 0 or pid >= ctrl.players.size() or ctrl.players[pid].is_ai:
		return
	var dlg := UiDialog.new()
	if result == "won":
		Sfx.play("victory")
		dlg.title = "Monster defeated!"
		dlg.dialog_text = "You won a Monster card.\n%s\n\nIt will fight beside your King when he enters Last Stand in a Duel. You can hold only one Monster card." % MonsterSystem.summary(monster_id, ctrl.players[pid].monster_star)
		dlg.tone = "info"
	else:
		Sfx.play("defeat")
		dlg.title = "Beaten by the monster"
		dlg.dialog_text = "The %s was too strong and you lost %d G. It stays in its lair - come back with a bigger army." % [GameData.get_monster(monster_id).get("name", "monster"), int(GameData.b("monster_defeat_gold"))]
		dlg.tone = "warn"
	dlg.show_cancel = false
	add_child(dlg)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered(Vector2i(520, 0))


## A human ruler found a hidden treasure or mine (the spot itself is never marked on the map).
func _on_deposit_event(pid: int, kind: String, deposit_id: String) -> void:
	if pid < 0 or pid >= ctrl.players.size() or ctrl.players[pid].is_ai:
		return
	var d := GameData.get_deposit(deposit_id)
	var dlg := UiDialog.new()
	Sfx.play("victory")
	if kind == "treasure":
		dlg.title = "Hidden treasure!"
		dlg.dialog_text = "%s\n\n%s\n\nIt is yours, and it is gone for everyone else." % [d.get("lore", ""), DepositSystem.summary(deposit_id)]
	else:
		dlg.title = "Hidden mine found!"
		dlg.dialog_text = "%s\n\n%s\n\nThe mine is yours: it pays at the end of every round until it runs dry." % [d.get("lore", ""), DepositSystem.summary(deposit_id)]
	dlg.tone = "info"
	dlg.show_cancel = false
	add_child(dlg)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered(Vector2i(520, 0))


func _on_dice(_d1: int, _d2: int) -> void:
	Sfx.play("dice")  # the result is shown by the dice animation in the middle of the board (no text line)


func _on_moved(pid: int, _from: int, to_i: int, _warped: bool) -> void:
	Sfx.play("portal" if _warped else "step")
	if pid == ctrl.current:
		board_view.selected_index = to_i
		board_view.info_text = ctrl.describe_tile(to_i)


func _on_speed_changed(mult: float) -> void:
	tick.wait_time = 0.8 / mult


func _on_state_changed() -> void:
	round_label.text = "Round %d / %d" % [mini(ctrl.round_number, ctrl.round_limit), ctrl.round_limit]
	var p := ctrl.current_player()
	turn_label.text = "Turn: %s" % p.display_name
	turn_label.add_theme_color_override("font_color", p.color)
	_refresh_players()
	_rebuild_actions()
	board_view.queue_redraw()
	_sync_casino()
	_maybe_open_duel()
	if ctrl.state == MatchController.State.AWAIT_ROLL:
		var key := "%d:%d" % [ctrl.round_number, ctrl.current]
		if key != _pan_key:  # a new turn: bring the HUMAN player's pawn into view (once, so manual panning is not undone); AI turns leave the camera alone
			_pan_key = key
			if not p.is_ai:
				board_view.pan_to_tile(p.position)
	if ctrl.state == MatchController.State.AWAIT_ROLL and not ctrl.current_player().is_ai:
		_autosave()  # start of the human turn: a stable moment


## ONE mission box under Menu, one line per mission: King (level-up mission of the human King, with progress) and, in Arena / Chaos,
## Continent (goal, progress, reward). A finished mission is green with a check mark.
func _refresh_mission() -> void:
	if _mission_panel == null or ctrl == null:
		return
	var human: PlayerState = null
	for p in ctrl.players:
		if not p.is_ai:
			human = p
			break
	var show_king := human != null and human.alive
	var show_cont := ctrl.has_mission()
	_mission_panel.visible = show_king or show_cont
	if not _mission_panel.visible:
		return
	var gold := "#" + UiTheme.COL_GOLD.to_html(false)
	var green := "#59cd90"
	var t := "[b][color=%s]MISSION[/color][/b]" % gold
	var tip: Array[String] = []
	if show_king:
		var mm := CommanderSystem.mission_of(human)
		var maxed := mm.is_empty()
		t += "\n[color=%s]%s King %s: %s[/color]" % [green if maxed else gold, "\u2713" if maxed else "\u2605", CommanderSystem.star_text(human.commander_star), CommanderSystem.mission_text(human)]
		tip.append("King mission: %s. Completing it gives your King its next level (more HP and ATK in Last Stand)." % (String(mm["name"]) if not maxed else "complete"))
	if show_cont:
		var done := ctrl.mission_done
		t += "\n[color=%s]%s Continent: %s  (%d / %d)  Reward: %s[/color]" % [green if done else gold, "\u2713" if done else "\u2605", ctrl.mission_text(), ctrl.mission_progress, ctrl.mission_target, ctrl.mission_reward_text()]
		tip.append("Continent mission: a special goal of this continent, paid when completed.")
	_mission_text.text = t
	_mission_panel.tooltip_text = "\n".join(tip)


func _refresh_players() -> void:
	_refresh_mission()
	for c in player_box.get_children():
		player_box.remove_child(c)
		c.queue_free()
	for p in ctrl.players:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.player_card_box(p.color, p.id == ctrl.current and p.alive))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		card.add_child(row)
		# round avatar with the player's initial
		var av := Label.new()
		av.text = String(p.display_name).substr(0, 1).to_upper()
		av.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		av.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		av.custom_minimum_size = Vector2(44, 44)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		av.add_theme_font_size_override("font_size", 22)
		av.add_theme_color_override("font_color", Color("10141f"))
		var avs := UiTheme.make_box(p.color if p.alive else Color("4a4f66"), p.color.lightened(0.5), 2, 22, 4)
		avs.content_margin_left = 0
		avs.content_margin_right = 0
		av.add_theme_stylebox_override("normal", avs)
		row.add_child(av)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var nm := String(p.display_name)
		if ctrl.team_mode:
			nm += "  [%s]" % ctrl.team_label(p)
		if p.alive:
			nm += "  " + CommanderSystem.star_text(p.commander_star)  # Commander level text only ("Lv 1".."Lv 3"), no star marks on the Territory board
		var name_l := UiTheme.make_label(nm, 17, UiTheme.COL_TEXT if p.alive else UiTheme.COL_MUTED)
		name_l.clip_text = true
		col.add_child(name_l)
		if p.alive:
			col.add_child(UiTheme.make_label("%d G" % p.gold, 22, UiTheme.COL_GOLD))
			var st := "Life %d  |  Land %d  |  RR %d" % [p.life, ctrl.count_owned(p.id), p.reroll_tokens]
			if not p.special_dice.is_empty():
				st += "  |  SD %d" % p.special_dice.size()
			var sl := UiTheme.make_label(st, 13, UiTheme.COL_MUTED)
			sl.tooltip_text = "Life | Land owned | RR = reroll tokens | SD = special dice"
			sl.clip_text = true
			col.add_child(sl)
			if p.monster_id != "":  # Monster card: fights beside this ruler's King in Duels
				var mon := GameData.get_monster(p.monster_id)
				var mon_l := UiTheme.make_label("Monster: %s" % mon.get("name", "?"), 13, UiTheme.COL_GOLD)
				mon_l.clip_text = true
				mon_l.tooltip_text = "Monster card - joins the King in Last Stand.\n" + MonsterSystem.summary(p.monster_id, p.monster_star)
				col.add_child(mon_l)
			var mines := DepositSystem.mines_of(ctrl.deposits, p.id)
			if not mines.is_empty():  # hidden mines found by this ruler: income every round
				var mine_l := UiTheme.make_label("Mines: %d  (+%d G / round)" % [mines.size(), DepositSystem.income_of(ctrl.deposits, p.id)], 13, UiTheme.COL_GOLD)
				mine_l.clip_text = true
				mine_l.tooltip_text = "\n".join(mines.map(func(e): return "%s (%d rounds left)" % [DepositSystem.summary(String(e["id"])), int(e["left"])]))
				col.add_child(mine_l)
		else:
			col.add_child(UiTheme.make_label("OUT", 18, UiTheme.COL_DANGER))
		player_box.add_child(card)


func _rebuild_actions() -> void:
	for c in action_box.get_children():
		action_box.remove_child(c)
		c.queue_free()
	if ctrl.state == MatchController.State.GAME_OVER:
		return
	var p := ctrl.current_player()
	if ctrl.state == MatchController.State.AWAIT_DUEL:
		action_box.add_child(UiTheme.make_label("Monster battle in progress..." if ctrl.is_monster_battle() else "Duel in progress...", 18, UiTheme.COL_GOLD))
		return
	if ctrl.state == MatchController.State.AWAIT_DECISION:
		var actor := ctrl.decision_actor()
		if actor.is_ai:
			action_box.add_child(UiTheme.make_label("%s is deciding..." % actor.display_name, 18, UiTheme.COL_MUTED))
			return
		var prompt_text := ctrl.get_decision_prompt()
		if prompt_text != "":
			var prompt := UiTheme.make_label(prompt_text, 16, UiTheme.COL_GOLD)
			prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			prompt.custom_minimum_size.x = 230
			action_box.add_child(prompt)
		for opt in ctrl.get_decision_options():
			_add_action(opt["label"], ctrl.decide.bind(opt["id"]), not opt["enabled"])
		return
	if p.is_ai:
		action_box.add_child(UiTheme.make_label("%s is thinking..." % p.display_name, 18, UiTheme.COL_MUTED))
		return
	match ctrl.state:
		MatchController.State.AWAIT_ROLL:
			_add_action("Roll Dice", func(): ctrl.roll_dice(), false, true)
			for i in range(p.special_dice.size()):
				var def := GameData.get_special_die(p.special_dice[i])
				_add_action("Use %s" % def["name"], ctrl.use_special_die.bind(i))
		MatchController.State.ROLLED:
			_add_action("Reroll Token (%d)" % p.reroll_tokens, func(): ctrl.reroll(), p.reroll_tokens <= 0)
			_add_action("Move", func(): ctrl.confirm_move(), false, true)
		MatchController.State.TURN_DONE:
			_add_action("End Turn", func(): ctrl.end_turn(), false, true)


func _add_action(text: String, cb: Callable, disabled: bool = false, primary: bool = false) -> void:
	var b := UiTheme.make_primary(text, 56) if primary else UiTheme.make_button(text, 56)
	b.custom_minimum_size.x = 230
	b.disabled = disabled
	b.pressed.connect(cb)
	action_box.add_child(b)


func _exit_tree() -> void:
	if _guide != null:
		_guide.detach()


func _on_hint(_id: String, text: String) -> void:
	_hint_label.text = text
	_hint_panel.visible = true


func _autosave() -> void:
	if ctrl != null and ctrl.state != MatchController.State.GAME_OVER:
		SaveManager.save_match(ctrl)


## The Casino: while a human stands on a Casino tile the same games as the Shop > Gamble tab open in an overlay, played with Dominion Gold.
## The overlay closes when the player leaves (the pending decision ends) or the match moves on.
func _sync_casino() -> void:
	var want := ctrl.state == MatchController.State.AWAIT_DECISION and String(ctrl.pending.get("type", "")) == "casino" and not ctrl.decision_actor().is_ai
	if not want:
		if _casino_node != null:
			_casino_node.queue_free()
			_casino_node = null
		return
	if _casino_node != null or _hub_node != null:
		return
	var actor := ctrl.decision_actor()
	# Simple floating card: a light dim behind it, one small centred panel, everything inside it.
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks the board behind the card
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(center)
	add_child(wrap)
	var panel := GamblePanel.new(ctrl.rng, {
		"compact": true, "unit": "G", "bets": ctrl.casino_bets(), "games": [String(ctrl.pending.get("game", "coin"))], "title": "CASINO",
		"balance": func() -> int: return actor.gold,
		"play": func(g: String, c: String, b: int) -> Dictionary: return ctrl.casino_play(g, c, b)})
	var leave := UiTheme.make_button("Leave casino", 48)
	panel.round_done.connect(func(r: Dictionary):
		ctrl.casino_report(actor, r)
		panel.lock()  # one round per visit
		leave.text = "Continue")
	panel.footer.add_child(leave)
	leave.pressed.connect(func():
		if not panel.busy:  # wait for the animation so the round is always reported
			ctrl.decide("leave"))
	center.add_child(panel)
	_casino_node = wrap


## Card Hub as an overlay: the match is not saved or reloaded, it just pauses. The hub may switch the active continent
## (Deck tab), so the continent of the match is restored when it closes. A deck saved there applies to the next match.
func _open_hub() -> void:
	if _hub_node != null or _duel_node != null or ctrl.state == MatchController.State.GAME_OVER:
		return
	_hub_prev_continent = CardDatabase.active_continent
	var hub: Control = load("res://scenes/card_collection/card_collection.tscn").instantiate()
	hub.embedded_close = _close_hub
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(wrap)
	wrap.add_child(hub)
	hub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hub_node = wrap


func _close_hub() -> void:
	if _hub_node == null:
		return
	CardDatabase.set_continent(_hub_prev_continent)
	_hub_node.queue_free()
	_hub_node = null


## Android Back button. A duel cannot be abandoned.
func on_back_requested() -> void:
	if _hub_node != null:
		_close_hub()
		return
	if _duel_node != null or ctrl.state == MatchController.State.GAME_OVER:
		return
	_leave_dialog.popup_centered(Vector2i(520, 200))


func _on_game_over(_winner: int) -> void:
	SaveManager.clear_match()
	var human_won := ctrl.human_won()
	Sfx.play("victory" if human_won else "defeat")
	if ctrl.tutorial:
		SaveManager.data["profile"]["tutorial_done"] = true
		SaveManager.save_game()
	if ctrl.human_present and not _stats_saved and not ctrl.tutorial:  # the tutorial does not count as a ranked result
		_stats_saved = true
		var cid := String(ctrl.continent["id"])
		if ctrl.wager > 0 and not ctrl.wager_settled:  # Arena wager: paid at the start, settled once
			ctrl.wager_settled = true
			_wager_paid = SaveManager.settle_wager(ctrl.wager, "win" if human_won else "loss", ctrl.wager_odds)
		_new_card = SaveManager.record_match(human_won, ctrl.round_number, ctrl.players[0].gold, cid, ctrl.journey, String(ctrl.players[0].faction_id),
			ShopSystem.random_bonus(cid) if ctrl.random_map and not ctrl.journey else {}, ctrl.match_difficulty,
			float(GameData.b("chaos_reward_mult", 1.0)) if ctrl.chaos else 1.0)
		if ctrl.mission_done:  # the reward was already paid in the match, when the mission completed
			_mission_lines.append("Mission complete: %s (%s)" % [String(ctrl.mission.get("name", "")), ctrl.mission_reward_text()])
		elif ctrl.has_mission():
			_mission_lines.append("Mission failed: %s (%d / %d)" % [String(ctrl.mission.get("name", "")), ctrl.mission_progress, ctrl.mission_target])
		if human_won and not ctrl.journey:  # Arena victory: a reward chest (Bronze / Silver / Gold) for the Chests screen
			_chest = ChestSystem.award(_chest_difficulty(ctrl))
		if ctrl.journey:
			_journey_lines.append("Trophies %s%d  (total %d)" % ["+" if SaveManager.last_trophy_delta >= 0 else "", SaveManager.last_trophy_delta, SaveManager.trophies()])
			for oid in SaveManager.last_opened_continents:
				_journey_lines.append("%s opened! Its unit cards are now in the Shop and its Kings are yours (B1)." % String(GameData.get_continent(oid).get("name", oid)))
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
	var title := "VICTORY" if human_won else "DEFEAT"
	v.add_child(UiTheme.make_label(title, 48, UiTheme.COL_GOLD if human_won else UiTheme.COL_DANGER))
	v.add_child(UiTheme.make_divider())
	if ctrl.team_mode:
		for team in [0, 1]:
			var line := "Team %s - %d G%s" % ["A" if team == 0 else "B", ctrl.team_networth(team), "  (WINNER)" if ctrl.winner_team == team else ""]
			v.add_child(UiTheme.make_label(line, 24, UiTheme.COL_GOLD))
	for p in ctrl.ranking():
		var tag := ("  [%s]" % ctrl.team_label(p)) if ctrl.team_mode else ""
		v.add_child(UiTheme.make_label("%s%s - net worth %d G%s" % [p.display_name, tag, ctrl.networth(p), "  (OUT)" if not p.alive else ""], 20, p.color))
	for line in _journey_lines:
		v.add_child(UiTheme.make_label(line, 20, UiTheme.COL_GOLD))
	for line in _mission_lines:
		v.add_child(UiTheme.make_label(line, 20, UiTheme.COL_MUTED if line.begins_with("Mission failed") else Color("59cd90")))
	if _new_card != "":
		v.add_child(UiTheme.make_label("New card unlocked: %s" % CardDatabase.get_support(_new_card)["name"], 20, UiTheme.COL_GOLD))
	if not _chest.is_empty():
		if _chest["status"] == "limit":
			v.add_child(UiTheme.make_label("Chest limit reached (%d). Refreshes in %s" % [ChestSystem.DROP_LIMIT, ChestSystem.clock_text(int(_chest["wait"]))], 20, UiTheme.COL_MUTED))
		else:
			var cg := String(_chest["grade"])
			if _chest["status"] == "added":
				v.add_child(UiTheme.make_label("Chest earned: %s  (slot %d)" % [ChestSystem.grade_name(cg), int(_chest["slot"]) + 1], 22, ChestSystem.grade_color(cg)))
			elif _chest["status"] == "stored":
				v.add_child(UiTheme.make_label("%s - slots full, sent to the Storage  (%d/%d)" % [ChestSystem.grade_name(cg), ChestSystem.storage_count(), ChestSystem.STORAGE_CAPACITY], 20, ChestSystem.grade_color(cg)))
			else:
				v.add_child(UiTheme.make_label("%s - chest slots and Storage full, +%d coins instead" % [ChestSystem.grade_name(cg), int(_chest["coins"])], 20, ChestSystem.grade_color(cg)))
	if _stats_saved:
		v.add_child(UiTheme.make_label(SaveManager.xp_line(), 20, UiTheme.COL_GOLD))
		v.add_child(UiTheme.make_label("+%d Aether Coins (%s)%s" % [SaveManager.last_reward, ctrl.match_difficulty.capitalize(), ("  (random map: %s)" % SaveManager.last_bonus_text) if SaveManager.last_bonus_text != "" else ""], 20, UiTheme.COL_GOLD))
		if ctrl.wager > 0:
			if _wager_paid > 0:
				v.add_child(UiTheme.make_label("Wager won: +%d coins (stake %d, x%s)" % [_wager_paid, ctrl.wager, str(snappedf(ctrl.wager_odds, 0.01))], 20, UiTheme.COL_GOLD))
			else:
				v.add_child(UiTheme.make_label("Wager lost: -%d coins" % ctrl.wager, 20, UiTheme.COL_DANGER))
	var again := UiTheme.make_button("Play Again", 56)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	v.add_child(again)
	var menu := UiTheme.make_button("Main Menu", 56)
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	v.add_child(menu)


## A duel involving the human is fought in the Battle scene, shown as a full-screen overlay.
func _maybe_open_duel() -> void:
	if ctrl.state != MatchController.State.AWAIT_DUEL or _duel_node != null or not (ctrl.is_human_duel() or ctrl.is_monster_battle()):
		return
	var node: Control = load("res://scenes/battle_board/battle_board.tscn").instantiate()
	if ctrl.is_monster_battle():  # the wild monster is the enemy: same Battle scene, same preparation as a Duel
		node.duel_context = {
			"human": ctrl.players[int(ctrl.pending["actor"])], "monster": String(ctrl.pending["monster"]),
			"human_attacks": true, "tutorial": false, "tile": ctrl.tiles[int(ctrl.pending["tile"])].name}
	else:
		var parts := ctrl.duel_participants()
		node.duel_context = {
			"human": parts["human"], "opponent": parts["opponent"],
			"human_attacks": parts["human_attacks"], "tutorial": ctrl.tutorial, "difficulty": ctrl.match_difficulty, "tile": ctrl.tiles[int(ctrl.pending["tile"])].name}
	node.battle_finished.connect(_on_duel_finished)
	_duel_node = node
	add_child(node)


func _on_duel_finished(result: Dictionary) -> void:
	if _duel_node != null:
		_duel_node.queue_free()
		_duel_node = null
	if bool(result.get("monster", false)):
		ctrl.finish_monster_battle(result)
	else:
		ctrl.finish_duel(result)


## Chaos is a short match: its chest comes from one difficulty tier lower (hard -> normal -> easy).
func _chest_difficulty(c: MatchController) -> String:
	if not c.chaos:
		return c.match_difficulty
	return {"hard": "normal", "normal": "easy", "easy": "easy"}.get(c.match_difficulty, "easy")
