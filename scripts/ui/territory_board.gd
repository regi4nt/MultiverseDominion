extends Control
## Territory Board screen: board on the left, HUD on the right.
## All game rules live in MatchController; this script only displays and forwards input.

var ctrl: MatchController
var board_view: BoardView
var round_label: Label
var turn_label: Label
var dice_label: Label
var player_box: VBoxContainer
var action_box: HFlowContainer
var tile_info: Label
var log_view: RichTextLabel
var tick: Timer
var _leave_dialog: ConfirmationDialog
var _stats_saved := false
var _duel_node: Control = null
var _guide: TutorialGuide = null
var _new_card: String = ""
var _hint_panel: PanelContainer
var _hint_label: Label


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
	tick.wait_time = 0.8
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

	var arc := AspectRatioContainer.new()
	arc.ratio = 1.0
	arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arc.size_flags_stretch_ratio = 1.27  # 16:9 -> the board gets its full 696 px height; extra width goes to the HUD
	root.add_child(arc)
	board_view = BoardView.new()
	arc.add_child(board_view)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(500, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)

	var head := HBoxContainer.new()
	right.add_child(head)
	round_label = UiTheme.make_label("Round 1", 24, UiTheme.COL_GOLD)
	round_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(round_label)
	var menu := UiTheme.make_button("Menu", 44)
	menu.custom_minimum_size.x = 110
	menu.pressed.connect(func(): _leave_dialog.popup_centered(Vector2i(460, 160)))
	head.add_child(menu)
	_leave_dialog = ConfirmationDialog.new()
	_leave_dialog.dialog_text = "Leave to the main menu? The match is saved at the start of each of your turns and can be continued."
	_leave_dialog.confirmed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	add_child(_leave_dialog)

	var players_panel := PanelContainer.new()
	right.add_child(players_panel)
	player_box = VBoxContainer.new()
	player_box.add_theme_constant_override("separation", 4)
	players_panel.add_child(player_box)

	var turn_panel := PanelContainer.new()
	right.add_child(turn_panel)
	var tv := VBoxContainer.new()
	turn_panel.add_child(tv)
	turn_label = UiTheme.make_label("", 22)
	dice_label = UiTheme.make_label("Dice: -", 20, UiTheme.COL_MUTED)
	tv.add_child(turn_label)
	tv.add_child(dice_label)

	var action_panel := PanelContainer.new()
	action_panel.custom_minimum_size = Vector2(0, 76)
	right.add_child(action_panel)
	action_box = HFlowContainer.new()
	action_box.add_theme_constant_override("h_separation", 8)
	action_box.add_theme_constant_override("v_separation", 8)
	action_panel.add_child(action_box)

	var info_panel := PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(0, 84)
	right.add_child(info_panel)
	tile_info = UiTheme.make_label("Tap a tile on the board to inspect it.", 16, UiTheme.COL_MUTED)
	tile_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_panel.add_child(tile_info)

	_hint_panel = PanelContainer.new()  # Tutorial coach (hidden in normal matches)
	_hint_panel.visible = false
	_hint_panel.add_theme_stylebox_override("panel", UiTheme.make_box(Color("2a2150"), UiTheme.COL_GOLD, 2, 10))
	right.add_child(_hint_panel)
	var hv := HBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	_hint_panel.add_child(hv)
	_hint_label = UiTheme.make_label("", 15, UiTheme.COL_TEXT)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(_hint_label)
	var hide_btn := UiTheme.make_button("OK", 52)
	hide_btn.custom_minimum_size.x = 70
	hide_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hide_btn.pressed.connect(func(): _hint_panel.visible = false)
	hv.add_child(hide_btn)

	var log_panel := PanelContainer.new()
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(log_panel)
	log_view = RichTextLabel.new()
	log_view.scroll_following = true
	log_view.add_theme_font_size_override("normal_font_size", 15)
	log_panel.add_child(log_view)


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


func _on_dice(d1: int, d2: int) -> void:
	Sfx.play("dice")
	dice_label.text = "Dice: %d + %d = %d%s" % [d1, d2, d1 + d2, "  (DOUBLE)" if d1 == d2 else ""]


func _on_moved(pid: int, _from: int, to_i: int, _warped: bool) -> void:
	Sfx.play("portal" if _warped else "step")
	if pid == ctrl.current:
		board_view.selected_index = to_i
		tile_info.text = ctrl.describe_tile(to_i)


func _on_state_changed() -> void:
	round_label.text = "Round %d / %d" % [mini(ctrl.round_number, ctrl.round_limit), ctrl.round_limit]
	var p := ctrl.current_player()
	turn_label.text = "Turn: %s" % p.display_name
	turn_label.add_theme_color_override("font_color", p.color)
	_refresh_players()
	_rebuild_actions()
	board_view.queue_redraw()
	_maybe_open_duel()
	if ctrl.state == MatchController.State.AWAIT_ROLL and not ctrl.current_player().is_ai:
		_autosave()  # start of the human turn: a stable moment


func _refresh_players() -> void:
	for c in player_box.get_children():
		player_box.remove_child(c)
		c.queue_free()
	for p in ctrl.players:
		var row := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = p.color
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		var txt := "%s%s  %d G | Life %d | Lands %d | RR %d%s" % [">" if p.id == ctrl.current else " ", p.display_name, p.gold, p.life, ctrl.count_owned(p.id), p.reroll_tokens, (" | SD %d" % p.special_dice.size()) if not p.special_dice.is_empty() else ""]
		if not p.alive:
			txt = "  %s  OUT" % p.display_name
		var l := UiTheme.make_label(txt, 16, UiTheme.COL_TEXT if p.alive else UiTheme.COL_MUTED)
		row.add_child(l)
		row.add_theme_constant_override("separation", 8)
		player_box.add_child(row)


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
			prompt.custom_minimum_size.x = 470
			action_box.add_child(prompt)
		for opt in ctrl.get_decision_options():
			_add_action(opt["label"], ctrl.decide.bind(opt["id"]), not opt["enabled"])
		return
	if p.is_ai:
		action_box.add_child(UiTheme.make_label("%s is thinking..." % p.display_name, 18, UiTheme.COL_MUTED))
		return
	match ctrl.state:
		MatchController.State.AWAIT_ROLL:
			_add_action("Roll Dice", func(): ctrl.roll_dice())
			for i in range(p.special_dice.size()):
				var def := GameData.get_special_die(p.special_dice[i])
				_add_action("Use %s" % def["name"], ctrl.use_special_die.bind(i))
		MatchController.State.ROLLED:
			_add_action("Reroll Token (%d)" % p.reroll_tokens, func(): ctrl.reroll(), p.reroll_tokens <= 0)
			_add_action("Move", func(): ctrl.confirm_move())
		MatchController.State.TURN_DONE:
			_add_action("End Turn", func(): ctrl.end_turn())


func _add_action(text: String, cb: Callable, disabled: bool = false) -> void:
	var b := UiTheme.make_button(text, 56)
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
