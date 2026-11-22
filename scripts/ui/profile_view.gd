class_name ProfileView
extends RefCounted
## Player profile card, shown inside a UiDialog (see MainMenu._show_profile). Built from SaveManager data only:
## name, tutorial status, win/loss record and the six lifetime stats.

const COL_WIN := Color("6fcf8f")
const COL_LOSS := Color("e0705f")


static func build() -> Control:
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
	var name_lbl := UiTheme.make_label(pname, 36, UiTheme.COL_GOLD)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(name_lbl)
	var done := bool(p.get("tutorial_done", false))
	var chip_holder := HBoxContainer.new()
	who.add_child(chip_holder)
	chip_holder.add_child(_chip("Tutorial complete" if done else "Tutorial not played yet", COL_WIN if done else UiTheme.COL_MUTED))

	col.add_child(UiTheme.make_divider())

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


static func _avatar(letter: String) -> Control:
	if letter == "":
		letter = "P"
	var av := PanelContainer.new()
	av.custom_minimum_size = Vector2(88, 88)
	var sb := UiTheme.make_box(Color("2a2150"), UiTheme.COL_GOLD, 3, 44, 8)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	av.add_theme_stylebox_override("panel", sb)
	var c := CenterContainer.new()
	av.add_child(c)
	c.add_child(UiTheme.make_label(letter, 46, UiTheme.COL_GOLD))
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
