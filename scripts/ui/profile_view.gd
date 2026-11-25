class_name ProfileView
extends RefCounted
## Player profile. `build_card()` is the always-visible card on the Main Menu (avatar, name, title, level, EXP bar, record);
## `build()` is the full card in a UiDialog (MainMenu._show_profile, opened by tapping the home card).
## Built from SaveManager data only: name, title / level / EXP, tutorial status, win/loss record and the six lifetime stats.

const COL_WIN := Color("6fcf8f")
const COL_LOSS := Color("e0705f")


static func build(on_rename: Callable = Callable()) -> Control:
	var p: Dictionary = SaveManager.data["profile"]
	var s: Dictionary = SaveManager.data["stats"]
	var matches := int(s.get("matches_played", 0))
	var wins := int(s.get("wins", 0))
	var losses := int(s.get("losses", 0))
	var pname := String(p.get("name", "Player")).strip_edges()
	if pname == "":
		pname = "Player"

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)

	# --- header: avatar + name + tutorial chip
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	col.add_child(head)
	head.add_child(_avatar(pname.left(1).to_upper()))
	var who := VBoxContainer.new()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 8)
	head.add_child(who)
	if on_rename.is_valid():
		var rb := UiTheme.make_button("Rename", 52)
		rb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		rb.pressed.connect(func(): on_rename.call())
		head.add_child(rb)
	var name_lbl := UiTheme.make_label(pname, 36, UiTheme.COL_GOLD)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(name_lbl)
	var done := bool(p.get("tutorial_done", false))
	var chip_holder := HBoxContainer.new()
	who.add_child(chip_holder)
	chip_holder.add_child(_chip(SaveManager.profile_title(), UiTheme.COL_GOLD))
	chip_holder.add_child(_chip("Tutorial complete" if done else "Tutorial not played yet", COL_WIN if done else UiTheme.COL_MUTED))

	col.add_child(UiTheme.make_divider())
	col.add_child(_exp_block(20))

	# --- win / loss bar
	var rec := VBoxContainer.new()
	rec.add_theme_constant_override("separation", 8)
	col.add_child(rec)
	rec.add_child(UiTheme.make_label("RECORD", 16, UiTheme.COL_MUTED))
	rec.add_child(_record_bar(wins, losses))

	# --- stat tiles
	var rate := "-" if matches <= 0 else "%d%%" % int(round(100.0 * wins / matches))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	grid.add_child(_tile("Matches", str(matches), UiTheme.COL_TEXT))
	grid.add_child(_tile("Wins", str(wins), COL_WIN))
	grid.add_child(_tile("Losses", str(losses), COL_LOSS))
	grid.add_child(_tile("Win rate", rate, UiTheme.COL_GOLD))
	grid.add_child(_tile("Rounds played", str(int(s.get("total_rounds", 0))), UiTheme.COL_TEXT))
	grid.add_child(_tile("Best gold", str(int(s.get("best_gold", 0))), UiTheme.COL_GOLD))

	if matches <= 0:
		var hint := UiTheme.make_label("No matches yet. Start a NEW MATCH to build your record.", 18, UiTheme.COL_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(hint)
	return col


static func _avatar(letter: String, size: float = 88.0) -> Control:
	if letter == "":
		letter = "P"
	var av := PanelContainer.new()
	av.custom_minimum_size = Vector2(size, size)
	# A row stretches its children to the row height, which turned the avatar into an oval: keep it an exact circle.
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := UiTheme.make_box(Color("2a2150"), UiTheme.COL_GOLD, 3, int(size * 0.5), 8)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	av.add_theme_stylebox_override("panel", sb)
	var c := CenterContainer.new()
	av.add_child(c)
	c.add_child(UiTheme.make_label(letter, int(size * 0.52), UiTheme.COL_GOLD))
	return av


static func _chip(text: String, color: Color) -> Control:
	var chip := PanelContainer.new()
	var sb := UiTheme.make_box(Color(color, 0.14), Color(color, 0.7), 1, 14, 0)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	chip.add_theme_stylebox_override("panel", sb)
	chip.add_child(UiTheme.make_label(text, 16, color))
	return chip


## Two proportional segments (wins green, losses red); a muted empty track while there is no result yet.
static func _record_bar(wins: int, losses: int) -> Control:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.add_theme_constant_override("separation", 4)
	if wins + losses <= 0:
		bar.add_child(_segment(Color("2e3350"), 1.0))
		return bar
	if wins > 0:
		bar.add_child(_segment(COL_WIN, float(wins)))
	if losses > 0:
		bar.add_child(_segment(COL_LOSS, float(losses)))
	return bar


static func _segment(color: Color, ratio: float) -> Control:
	var seg := PanelContainer.new()
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_stretch_ratio = ratio
	var sb := UiTheme.make_box(color, color.lightened(0.25), 0, 8, 0)
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	seg.add_theme_stylebox_override("panel", sb)
	return seg


static func _tile(caption: String, value: String, color: Color) -> Control:
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiTheme.make_box(Color(UiTheme.COL_PANEL_LIGHT, 0.55), Color("2e3350"), 1, 14, 0)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	tile.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	tile.add_child(v)
	var num := UiTheme.make_label(value, 36, color)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(num)
	var cap := UiTheme.make_label(caption.to_upper(), 14, UiTheme.COL_MUTED)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cap)
	return tile


## "Lv 5" + EXP bar + "120 / 300 EXP" (or "MAX LEVEL"): shared by the home card and the profile dialog.
static func _exp_block(font: int) -> Control:
	var pr := XpSystem.progress(SaveManager.profile_xp())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	box.add_child(row)
	var lv := UiTheme.make_label("Lv %d" % int(pr["level"]), font, UiTheme.COL_GOLD)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lv)
	var txt := "MAX LEVEL" if bool(pr["max"]) else "%d / %d EXP" % [int(pr["into"]), int(pr["need"])]
	row.add_child(UiTheme.make_label(txt, maxi(font - 4, 12), UiTheme.COL_MUTED))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0, 12)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0 if bool(pr["max"]) else float(pr["into"]) / float(maxi(int(pr["need"]), 1))
	bar.add_theme_stylebox_override("background", UiTheme.make_box(Color("2e3350"), Color("2e3350"), 0, 6, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.make_box(UiTheme.COL_GOLD, UiTheme.COL_GOLD, 0, 6, 0))
	box.add_child(bar)
	return box


## The Main Menu card: always on screen, no button. Tapping it calls `on_open` (the full profile dialog).
static func build_card(on_open: Callable) -> Control:
	var p: Dictionary = SaveManager.data["profile"]
	var s: Dictionary = SaveManager.data["stats"]
	var pname := String(p.get("name", "Player")).strip_edges()
	if pname == "":
		pname = "Player"
	var card := PanelContainer.new()
	card.name = "ProfileCard"
	card.custom_minimum_size = Vector2(380, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "Tap for your full profile"
	card.add_theme_stylebox_override("panel", UiTheme.make_box(Color(UiTheme.COL_PANEL, 0.92), UiTheme.COL_GOLD_DIM, 2, 14, 0))
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			on_open.call())
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pad.add_child(row)
	var av := _avatar(pname.left(1).to_upper(), 72.0)
	av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # top-aligned with the name
	row.add_child(av)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var name_lbl := UiTheme.make_label(pname, 28, UiTheme.COL_GOLD)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_lbl)
	col.add_child(UiTheme.make_label(SaveManager.profile_title(), 18, UiTheme.COL_TEXT))
	col.add_child(_exp_block(18))
	var matches := int(s.get("matches_played", 0))
	col.add_child(UiTheme.make_label("%d matches  |  %d W  |  %d L" % [matches, int(s.get("wins", 0)), int(s.get("losses", 0))], 14, UiTheme.COL_MUTED))
	return card


## "Change name" dialog: a text field (max SaveManager.NAME_MAX characters). `on_closed(changed: bool)` runs when it closes.
static func open_rename(host: Node, on_closed: Callable) -> void:
	var dlg := UiDialog.new()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.add_child(UiTheme.make_label("Change name", 30, UiTheme.COL_GOLD))
	var le := LineEdit.new()
	le.text = String(SaveManager.data["profile"].get("name", "Player"))
	le.max_length = SaveManager.NAME_MAX
	le.placeholder_text = "Your name"
	le.select_all_on_focus = true
	le.custom_minimum_size = Vector2(0, 68)
	le.add_theme_font_size_override("font_size", 28)
	body.add_child(le)
	body.add_child(UiTheme.make_label("1 to %d characters." % SaveManager.NAME_MAX, 16, UiTheme.COL_MUTED))
	dlg.body_node = body
	dlg.ok_button_text = "Save"
	dlg.cancel_button_text = "Cancel"
	var changed := [false]
	dlg.confirmed.connect(func():
		changed[0] = SaveManager.set_profile_name(le.text)
		dlg.queue_free()
		if on_closed.is_valid():
			on_closed.call(changed[0]))
	dlg.canceled.connect(func():
		dlg.queue_free()
		if on_closed.is_valid():
			on_closed.call(false))
	le.text_submitted.connect(func(_t: String): dlg._confirm())
	host.add_child(dlg)
	dlg.popup_centered(Vector2i(560, 0))
	le.grab_focus.call_deferred()
