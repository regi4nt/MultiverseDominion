extends Control
## Mode -> Continent -> Faction -> Champion -> Difficulty -> Start. The bottom bar also holds Tutorial and Battle Practice.

var _faction_box: VBoxContainer
var _champion_text: RichTextLabel
var _portrait: PortraitView
var _continent_text: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	GameSession.difficulty = String(SaveManager.get_setting("default_difficulty"))
	if GameSession.mode == "tutorial":  # a normal match must not inherit the tutorial config
		GameSession.mode = "ffa_ai"
		GameSession.ai_count = 3
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	root.add_child(UiTheme.make_label("NEW MATCH", 40, UiTheme.COL_GOLD))
	root.add_child(UiTheme.make_divider())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# Column 1: mode + difficulty
	var c1 := _column(cols, "Game Mode")
	var mode_group := ButtonGroup.new()
	var modes := [["4 Player FFA (vs 3 AI)", "ffa_ai", 3], ["Custom vs 2 AI", "custom_ai", 2], ["Custom vs 1 AI", "custom_ai", 1]]
	for m in modes:
		var b := UiTheme.make_toggle(m[0], mode_group)
		b.button_pressed = (GameSession.mode == m[1] and GameSession.ai_count == m[2])
		b.pressed.connect(func():
			GameSession.mode = m[1]
			GameSession.ai_count = m[2])
		UiTheme.scroll_passthrough(b)
		c1.add_child(b)
	c1.add_child(UiTheme.make_label("AI Difficulty", 22, UiTheme.COL_GOLD))
	var diff_group := ButtonGroup.new()
	for d in ["easy", "normal", "hard"]:
		var b := UiTheme.make_toggle(d.capitalize(), diff_group)
		b.button_pressed = (GameSession.difficulty == d)
		b.pressed.connect(func(): GameSession.difficulty = d)
		UiTheme.scroll_passthrough(b)
		c1.add_child(b)

	# Column 2: continent + faction
	var c2 := _column(cols, "Continent")
	var cont_group := ButtonGroup.new()
	for c in GameData.continents:
		var playable: bool = c.get("playable", false) and SaveManager.is_continent_unlocked(c["id"])
		var b := UiTheme.make_toggle(c["name"] if playable else "%s (locked)" % c["name"], cont_group, 44)
		b.disabled = not playable
		b.button_pressed = (GameSession.continent_id == c["id"])
		b.pressed.connect(func():
			GameSession.continent_id = c["id"]
			_refresh_factions())
		UiTheme.scroll_passthrough(b)
		c2.add_child(b)

	# Column 3: faction + champion + start
	var c3 := _column(cols, "Faction & Champion")
	_continent_text = UiTheme.make_label("", 16, UiTheme.COL_MUTED)
	_continent_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c3.add_child(_continent_text)
	_faction_box = VBoxContainer.new()
	_faction_box.add_theme_constant_override("separation", 6)
	c3.add_child(_faction_box)
	var champ_row := HBoxContainer.new()
	champ_row.add_theme_constant_override("separation", 8)
	c3.add_child(champ_row)
	_portrait = PortraitView.new()
	_portrait.custom_minimum_size = Vector2(84, 98)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	champ_row.add_child(_portrait)
	_champion_text = RichTextLabel.new()
	_champion_text.bbcode_enabled = true
	_champion_text.fit_content = true
	_champion_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_champion_text.add_theme_font_size_override("normal_font_size", 16)
	champ_row.add_child(_champion_text)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	root.add_child(bottom)
	var back := UiTheme.make_button("Back", 60)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	bottom.add_child(back)
	var tut := UiTheme.make_button("TUTORIAL  (done)" if SaveManager.data["profile"].get("tutorial_done", false) else "TUTORIAL", 60)
	tut.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut.pressed.connect(func():
		SaveManager.clear_match()  # the tutorial replaces the saved match, like START MATCH
		GameSession.start_tutorial()
		get_tree().change_scene_to_file("res://scenes/territory_board/territory_board.tscn"))
	bottom.add_child(tut)
	var practice := UiTheme.make_button("BATTLE PRACTICE", 60)
	practice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/battle_board/battle_board.tscn"))
	bottom.add_child(practice)
	var start := UiTheme.make_button("START MATCH", 60)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.pressed.connect(func():
		SaveManager.clear_match()  # a new match replaces the saved one
		GameSession.resume_match = false
		get_tree().change_scene_to_file("res://scenes/territory_board/territory_board.tscn"))
	bottom.add_child(start)

	_refresh_factions()


func _column(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var scroll := UiTheme.make_scroll()
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	v.add_child(UiTheme.make_label(title, 24, UiTheme.COL_GOLD))
	return v


func _refresh_factions() -> void:
	for ch in _faction_box.get_children():
		_faction_box.remove_child(ch)
		ch.queue_free()
	var cont := GameData.get_continent(GameSession.continent_id)
	_continent_text.text = "%s: %s" % [cont["modifier"]["name"], cont["modifier"]["description"]]
	_continent_text.add_theme_font_size_override("font_size", 14)
	_continent_text.tooltip_text = String(cont.get("theme", ""))
	var group := ButtonGroup.new()
	var valid := false
	for f in cont.get("factions", []):
		if f["id"] == GameSession.faction_id:
			valid = true
	if not valid:
		GameSession.faction_id = cont["factions"][0]["id"]
	for f in cont.get("factions", []):
		var unlocked: bool = SaveManager.is_faction_unlocked(f["id"]) and f.get("champion", "") != ""
		var b := UiTheme.make_toggle(f["name"] if unlocked else "%s (TODO)" % f["name"], group, 44)
		b.disabled = not unlocked
		b.button_pressed = (GameSession.faction_id == f["id"])
		b.pressed.connect(func():
			GameSession.faction_id = f["id"]
			_refresh_champion())
		UiTheme.scroll_passthrough(b)
		_faction_box.add_child(b)
	_refresh_champion()


func _refresh_champion() -> void:
	var fac := GameData.get_faction(GameSession.continent_id, GameSession.faction_id)
	var ch := GameData.get_champion(fac.get("champion", ""))
	if ch.is_empty():
		_champion_text.text = ""
		_portrait.setup("")
		return
	_portrait.setup(String(fac.get("champion", "")))
	_champion_text.text = "[color=#d4af37][b]%s[/b][/color]\n[color=#d4af37]%s King - Last Stand[/color]\nHP %d   ATK %d   Capacity %d\n[b]%s:[/b] %s\n[b]%s:[/b] %s" % [
		ch["name"], String(ch.get("rarity", "legendary")).capitalize(), ch["hp"], ch["atk"], ch["capacity"], ch["passive_name"], ch["passive_desc"], ch["active_name"], ch["active_desc"]]
