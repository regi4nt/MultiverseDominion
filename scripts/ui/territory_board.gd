extends Control
## Territory Board screen: board in the middle (dice + actions in its centre), log left, players right.
## All game rules live in MatchController; this script only displays and forwards input.

var ctrl: MatchController
var board_view: BoardView
var _centre: PanelContainer
var round_label: Label
var turn_label: Label
var player_box: VBoxContainer
var action_box: HFlowContainer
var tile_info: Label
var log_view: RichTextLabel
var tick: Timer
var _leave_dialog: UiDialog
var _stats_saved := false
var _duel_node: Control = null
var _guide: TutorialGuide = null
var _new_card: String = ""
var _hint_panel: PanelContainer
var _hint_label: Label
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
	ctrl.log_added.connect(_on_log)
	ctrl.state_changed.connect(_on_state_changed)
	ctrl.players_changed.connect(_refresh_players)
	ctrl.dice_rolled.connect(_on_dice)
	ctrl.player_moved.connect(_on_moved)
	ctrl.game_over.connect(_on_game_over)
	board_view.bind(ctrl)
	board_view.speed_changed.connect(_on_speed_changed)
	board_view.tile_pressed.connect(func(i: int): tile_info.text = ctrl.describe_tile(i))
	for line in ctrl.recent_log:  # lines logged before the UI was connected (match start / resumed match)
		log_view.add_text(line + "\n")
	SaveManager.app_paused.connect(_autosave)
	_refresh_players()
	_on_state_changed()
	if WorldMods.modifier_name != "":
		tile_info.text = "World modifier - %s: %s" % [WorldMods.modifier_name, ctrl.continent["modifier"].get("description", "")]
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
	add_child(UiTheme.make_background())
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
	# Sides swapped: the `right` column is shown on the LEFT and the `left` column on the RIGHT (order: right | board | left).
	root.move_child(right, 0)
	root.move_child(left, root.get_child_count() - 1)

	# --- left column
	var head := HBoxContainer.new()
	left.add_child(head)
	round_label = UiTheme.make_label("Round 1", 22, UiTheme.COL_GOLD)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(round_label)
	var menu := UiTheme.make_button("Menu", 44)
	menu.custom_minimum_size.x = 96
	menu.pressed.connect(func(): _leave_dialog.popup_centered(Vector2i(460, 160)))
	head.add_child(menu)
	_leave_dialog = UiDialog.new()
	_leave_dialog.title = "Leave match?"
	_leave_dialog.dialog_text = "Leave to the main menu? The match is saved at the start of each of your turns and can be continued."
	_leave_dialog.ok_button_text = "Leave"
	_leave_dialog.cancel_button_text = "Stay"
	_leave_dialog.confirmed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	add_child(_leave_dialog)

	var players_panel := PanelContainer.new()
	players_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	left.add_child(players_panel)
	player_box = VBoxContainer.new()
	player_box.add_theme_constant_override("separation", 8)
	players_panel.add_child(player_box)

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

	# --- right column
	var info_panel := PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(0, 84)
	right.add_child(info_panel)
	tile_info = UiTheme.make_label("Tap a tile to inspect it.  RR = reroll tokens, SD = special dice.", 16, UiTheme.COL_MUTED)
	tile_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_panel.add_child(tile_info)

	var log_panel := PanelContainer.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(log_panel)
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", 15)
	log_panel.add_child(log_view)

	# --- bottom of the screen's LEFT column (below the log): whose turn it is + the action buttons
	# (Roll Dice, Reroll, Move, End Turn, Buy, Tax / Duel, ...). It never floats over the board: only the dice ANIMATION
	# is drawn inside the map (BoardView).
	_centre = PanelContainer.new()
	_centre.add_theme_stylebox_override("panel", UiTheme.make_box(Color(UiTheme.COL_PANEL, 0.96), UiTheme.COL_GOLD_DIM, 2, 10))
	right.add_child(_centre)  # `right` is the column shown on the left (sides swapped, see above)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	_centre.add_child(cv)
	turn_label = UiTheme.make_label("", 20)
	turn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(turn_label)
	action_box = HFlowContainer.new()
	action_box.alignment = FlowContainer.ALIGNMENT_BEGIN
	action_box.add_theme_constant_override("h_separation", 8)
	action_box.add_theme_constant_override("v_separation", 8)
	cv.add_child(action_box)


# ------------------------------------------------------------------ signals

func _on_tick() -> void:
	if ctrl.state == MatchController.State.GAME_OVER or board_view.is_busy() or _duel_node != null:
		return
	var p := ctrl.current_player()
	if ctrl.state == MatchController.State.AWAIT_DUEL:
		if not ctrl.is_human_duel():
			AIController.step(ctrl)  # AI vs AI: resolved instantly
	elif ctrl.state == MatchController.State.AWAIT_DECISION:
		if ctrl.decision_actor().is_ai:
			AIController.step(ctrl)
	elif p.is_ai:
		AIController.step(ctrl)
	elif ctrl.state == MatchController.State.ROLLED and p.reroll_tokens <= 0:
		ctrl.confirm_move()  # nothing to decide: move automatically


func _on_log(text: String) -> void:
	if text.contains(" buys ") or text.contains("Victory Reward") or text.contains("passes the Dominion Gate"):
		Sfx.play("coin")
	elif text.contains("loses 1 Life") or text.contains("BANKRUPT"):
		Sfx.play("error")
	log_view.add_text(text + "\n")


func _on_dice(_d1: int, _d2: int) -> void:
	Sfx.play("dice")  # the result is shown by the dice animation in the middle of the board (no text line)


func _on_moved(pid: int, _from: int, to_i: int, _warped: bool) -> void:
	Sfx.play("portal" if _warped else "step")
	if pid == ctrl.current:
		board_view.selected_index = to_i
		tile_info.text = ctrl.describe_tile(to_i)


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
	_maybe_open_duel()
	if ctrl.state == MatchController.State.AWAIT_ROLL:
		var key := "%d:%d" % [ctrl.round_number, ctrl.current]
		if key != _pan_key:  # a new turn: bring that player's pawn into view (once, so manual panning is not undone)
			_pan_key = key
			board_view.pan_to_tile(p.position)
	if ctrl.state == MatchController.State.AWAIT_ROLL and not ctrl.current_player().is_ai:
		_autosave()  # start of the human turn: a stable moment


func _refresh_players() -> void:
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
		action_box.add_child(UiTheme.make_label("Duel in progress...", 18, UiTheme.COL_GOLD))
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


## Android Back button. A duel cannot be abandoned.
func on_back_requested() -> void:
	if _duel_node != null or ctrl.state == MatchController.State.GAME_OVER:
		return
	_leave_dialog.popup_centered(Vector2i(520, 200))


func _on_game_over(winner: int) -> void:
	SaveManager.clear_match()
	Sfx.play("victory" if ctrl.human_present and winner == 0 else "defeat")
	var human_won := ctrl.human_present and winner == 0
	if ctrl.tutorial:
		SaveManager.data["profile"]["tutorial_done"] = true
		SaveManager.save_game()
	if ctrl.human_present and not _stats_saved and not ctrl.tutorial:  # the tutorial does not count as a ranked result
		_stats_saved = true
		_new_card = SaveManager.record_match(human_won, ctrl.round_number, ctrl.players[0].gold, String(ctrl.continent["id"]))
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
	var title := "VICTORY" if human_won else "DEFEAT"
	v.add_child(UiTheme.make_label(title, 48, UiTheme.COL_GOLD if human_won else UiTheme.COL_DANGER))
	v.add_child(UiTheme.make_divider())
	for p in ctrl.ranking():
		v.add_child(UiTheme.make_label("%s - net worth %d G%s" % [p.display_name, ctrl.networth(p), "  (OUT)" if not p.alive else ""], 20, p.color))
	if _new_card != "":
		v.add_child(UiTheme.make_label("New card unlocked: %s" % CardDatabase.get_support(_new_card)["name"], 20, UiTheme.COL_GOLD))
	if _stats_saved:
		v.add_child(UiTheme.make_label("+%d Aether Coins" % SaveManager.last_reward, 20, UiTheme.COL_GOLD))
	var again := UiTheme.make_button("Play Again", 56)
	again.pressed.connect(func(): get_tree().reload_current_scene())
	v.add_child(again)
	var menu := UiTheme.make_button("Main Menu", 56)
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	v.add_child(menu)


## A duel involving the human is fought in the Battle scene, shown as a full-screen overlay.
func _maybe_open_duel() -> void:
	if ctrl.state != MatchController.State.AWAIT_DUEL or not ctrl.is_human_duel() or _duel_node != null:
		return
	var parts := ctrl.duel_participants()
	var node: Control = load("res://scenes/battle_board/battle_board.tscn").instantiate()
	node.duel_context = {
		"human": parts["human"], "opponent": parts["opponent"],
		"human_attacks": parts["human_attacks"], "tutorial": ctrl.tutorial, "tile": ctrl.tiles[int(ctrl.pending["tile"])].name}
	node.battle_finished.connect(_on_duel_finished)
	_duel_node = node
	add_child(node)


func _on_duel_finished(result: Dictionary) -> void:
	if _duel_node != null:
		_duel_node.queue_free()
		_duel_node = null
	ctrl.finish_duel(result)
