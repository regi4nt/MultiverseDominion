extends Control
## New Match. Two views in one scene:
##  - HUB: OFFLINE tab (Journey, Arena, Chaos, Battle Chess, Tutorial; 4 cards show at once, swipe the row for the rest) and ONLINE tab (Classic, Ranked, Battle Chess: coming soon).
##  - SETUP (Journey / Arena): players -> difficulty -> continent -> START MATCH. There is no faction choice here: the
##    faction (and its King) is chosen in Card Hub -> Deck -> Faction; locked factions cannot be picked.
## Journey = 1vs1 story path: win on a continent with each of its 4 factions to master it; every mastered continent lets the
## player CHOOSE one locked continent to open. Chaos = the same free match on the 40-tile board (it is an Arena setup with GameSession.chaos_mode).
## Arena = free match (1vs1, 2vs2, 4 player) on open continents, unlocks nothing.
## Battle Chess opens the 8x8 auto-battle (pays Aether Coins); Tutorial starts the guided match.

const BOARD_SCENE := "res://scenes/territory_board/territory_board.tscn"
const BATTLE_SCENE := "res://scenes/battle_board/battle_board.tscn"
const MENU_SCENE := "res://scenes/main_menu/main_menu.tscn"
const CARD_MAX_H := 470.0
const CARDS_VISIBLE := 4  # mode cards on screen at once; the rest is reached by swiping the row sideways  # on tall screens (tablets) the mode cards stop growing and are centred instead

const ACCENT := {
	"journey": Color("e0b64a"), "arena": Color("e0644f"), "chaos": Color("d94fa3"), "battle_chess": Color("3fb5a3"), "tutorial": Color("69c46d"),
	"classic": Color("6f8fd6"), "ranked": Color("b07ad6"), "online_chess": Color("5fa8c8"),
}

## Arena player formats: label, caption, GameSession.mode, number of AI opponents.
const ARENA_MODES := [
	{"label": "1 vs 1", "sub": "You vs 1 AI", "mode": "custom_ai", "ai": 1},
	{"label": "2 vs 2", "sub": "You + 1 AI vs 2 AI", "mode": "team_2v2", "ai": 3},
	{"label": "4 Player", "sub": "Free-for-all vs 3 AI", "mode": "ffa_ai", "ai": 3},
]

var _view: String = "hub"  # "hub" | "setup"
var _tab: String = "offline"  # hub tab: "offline" | "online"
var _kind: String = "arena"  # setup kind: "journey" | "arena"

var _margin: MarginContainer
var _root: VBoxContainer
var _cards_holder: VBoxContainer
var _cards_row: HBoxContainer
var _cards_scroll: ScrollContainer  # the row scrolls sideways when it has more than CARDS_VISIBLE cards
var _tab_note: Label
var _tab_buttons: Dictionary = {}
var _champion_text: RichTextLabel
var _portrait: PortraitView
var _continent_text: Label
var _journey_hint: Label
var _trophy_note: Label
var _wager_panel: WagerPanel
var _difficulty_note: Label
var _arena_difficulty: String = ""  # Journey has no difficulty choice (always Normal): the Arena choice is kept here meanwhile
var _start_btn: Button
var _home_note: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	# Coming back from the Card Hub ("Change faction in Deck"): reopen the Journey / Arena setup the player left, with its choices.
	var back_kind := GameSession.setup_return
	GameSession.setup_return = ""
	if back_kind != "journey" and back_kind != "arena":
		back_kind = ""
		GameSession.difficulty = String(SaveManager.get_setting("default_difficulty"))
		GameSession.wager = 0  # a wager is chosen per match; nothing carries over
		GameSession.chaos_mode = false
	if GameSession.mode == "tutorial":  # a normal match must not inherit the tutorial config
		GameSession.mode = "ffa_ai"
		GameSession.ai_count = 3
	add_child(UiTheme.make_background())
	_margin = UiTheme.make_margin(24)
	add_child(_margin)
	if back_kind != "":
		_show_setup(back_kind)
	else:
		_show_hub()


## Android Back / Esc: from the setup view go back to the mode hub, from the hub leave to the Main Menu.
func on_back_requested() -> void:
	if _view == "setup":
		_show_hub()
	else:
		get_tree().change_scene_to_file(MENU_SCENE)


func _reset_root() -> void:
	if _root != null:
		_margin.remove_child(_root)
		_root.queue_free()
	_cards_holder = null
	_cards_row = null
	_tab_note = null
	_tab_buttons = {}
	_champion_text = null
	_portrait = null
	_continent_text = null
	_journey_hint = null
	_trophy_note = null
	_start_btn = null
	_home_note = null
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 10)
	_margin.add_child(_root)


# ============================================================ HUB

func _show_hub() -> void:
	_view = "hub"
	_reset_root()
	_root.add_theme_constant_override("separation", 6)  # tighter: the tallest mode card + header must fit 720 px (layout_test)
	_root.add_child(UiTheme.make_label("NEW MATCH", 40, UiTheme.COL_GOLD))
	_root.add_child(UiTheme.make_divider())

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	_root.add_child(tabs)
	var group := ButtonGroup.new()
	for t in [["offline", "OFFLINE"], ["online", "ONLINE  -  COMING SOON"]]:
		var b := UiTheme.make_toggle(t[1], group, 60)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 24)
		b.button_pressed = (_tab == t[0])
		var id: String = t[0]
		b.pressed.connect(func(): _set_tab(id))
		tabs.add_child(b)
		_tab_buttons[id] = b

	_tab_note = UiTheme.make_label("", 17, UiTheme.COL_MUTED)
	_root.add_child(_tab_note)

	_cards_holder = VBoxContainer.new()
	_cards_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_cards_holder)
	_cards_scroll = UiTheme.make_scroll()  # swipes that start on a card scroll the row
	_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_cards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cards_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_scroll.name = "CardsScroll"
	_cards_holder.add_child(_cards_scroll)
	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 14)
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_scroll.add_child(_cards_row)
	_root.resized.connect(_cap_cards)
	_cards_scroll.resized.connect(_size_cards)

	var bottom := HBoxContainer.new()
	_root.add_child(bottom)
	var back := UiTheme.make_button("Back", 60)
	back.custom_minimum_size.x = 260
	back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	bottom.add_child(back)
	_fill_cards()
	_cap_cards.call_deferred()


## Cards fill the free height on phones; on tall screens they are capped at CARD_MAX_H and centred.
func _cap_cards() -> void:
	if _root == null or _cards_row == null or _cards_holder == null or _cards_scroll == null:
		return
	var fixed := 0.0
	for ch in _root.get_children():
		if ch != _cards_holder:
			fixed += (ch as Control).get_combined_minimum_size().y + 10.0
	if _root.size.y - fixed > CARD_MAX_H:
		_cards_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_cards_scroll.custom_minimum_size.y = CARD_MAX_H
	else:
		_cards_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_cards_scroll.custom_minimum_size.y = 0.0
	_size_cards()


## With more than CARDS_VISIBLE cards every card is as wide as 1/CARDS_VISIBLE of the row, so exactly that many show and the rest
## is a swipe away (a peek of the next card is not wanted: the scroll bar under the row shows there is more). Fewer cards share the width.
func _size_cards() -> void:
	if _cards_row == null or _cards_scroll == null:
		return
	var n := _cards_row.get_child_count()
	var sep := float(_cards_row.get_theme_constant("separation"))
	var w := 0.0
	if n > CARDS_VISIBLE:
		w = maxf(0.0, (_cards_scroll.size.x - sep * float(CARDS_VISIBLE - 1)) / float(CARDS_VISIBLE))
	for ch in _cards_row.get_children():
		(ch as Control).custom_minimum_size.x = w


func _set_tab(id: String) -> void:
	_tab = id
	if _tab_buttons.has(id):
		(_tab_buttons[id] as Button).button_pressed = true
	_fill_cards()


func _fill_cards() -> void:
	for ch in _cards_row.get_children():
		_cards_row.remove_child(ch)
		ch.queue_free()
	var online := _tab == "online"
	_tab_note.text = "Online matches are not available yet. Everything under OFFLINE is fully playable." if online else "Choose how you want to play."
	for c in (_online_cards() if online else _offline_cards()):
		_cards_row.add_child(_make_card(c, online))
	if _cards_scroll != null:
		_cards_scroll.scroll_horizontal = 0
	_size_cards.call_deferred()


func _offline_cards() -> Array:
	return [
		{"id": "journey", "icon": "knight", "title": "JOURNEY", "sub": "Story  ·  1 vs 1",
			"desc": "Climb the trophy road in 1 vs 1 matches: wins earn trophies, defeats lose some. Trophies open new continents and their unit cards.",
			"chips": ["1 vs 1", "Trophy road"], "status": _journey_status()},
		{"id": "arena", "icon": "king", "title": "ARENA", "sub": "Free match",
			"desc": "Play a free match against AI on any continent, all open. Nothing to unlock (Kings and Pawns stay locked), just fight for the crown.",
			"chips": ["1 vs 1", "2 vs 2", "4 Player"], "status": "%d of %d continents open" % [_open_continent_count(), GameData.continents.size()]},
		{"id": "chaos", "icon": "bishop", "title": "CHAOS", "sub": "Free match  ·  40 tiles",
			"desc": "A short, frantic Arena match on a 40-tile board: 4 territories per region, and the Gate comes round again and again.",
			"chips": ["40 tiles", "1 vs 1", "2 vs 2", "4 Player"], "status": "Same rules as Arena"},
		{"id": "battle_chess", "icon": "rook", "title": "BATTLE CHESS", "sub": "8 x 8 auto battle",
			"desc": "Buy units, build a formation and watch the armies fight on the 8x8 board. No land, pure battle.",
			"chips": ["8 x 8", "Auto battle"],  # the status line below already says it earns Aether Coins; a third chip wrapped the row and pushed the hub past 720 px
			"status": "Win +%d to +%d  -  Loss +%d to +%d Aether Coins (by difficulty)" % [ShopSystem.PRACTICE_WIN_BY_DIFF["easy"], ShopSystem.PRACTICE_WIN_BY_DIFF["hard"], ShopSystem.PRACTICE_LOSS_BY_DIFF["easy"], ShopSystem.PRACTICE_LOSS_BY_DIFF["hard"]]},
		{"id": "tutorial", "icon": "pawn", "title": "TUTORIAL", "sub": "10 rounds  ·  1 vs 1",
			"desc": "A guided match against a normal AI that explains dice, land, tax and duels as you meet them.",
			"chips": ["Guided", "Normal AI"],
			"status": "Completed  -  replay anytime" if SaveManager.data["profile"].get("tutorial_done", false) else "Recommended for new players"},
	]


func _online_cards() -> Array:
	return [
		{"id": "classic", "icon": "king", "title": "CLASSIC", "sub": "Casual online",
			"desc": "Relaxed online matches against other players.",
			"chips": ["1 vs 1", "2 vs 2", "4 Player"], "status": "COMING SOON"},
		{"id": "ranked", "icon": "queen", "title": "RANKED", "sub": "Competitive ladder",
			"desc": "Climb the ranked ladder in 1 vs 1, 2 vs 2 or 4-player matches.",
			"chips": ["1 vs 1", "2 vs 2", "4 Player"], "status": "COMING SOON"},
		{"id": "online_chess", "icon": "rook", "title": "BATTLE CHESS", "sub": "Online 8 x 8",
			"desc": "Send your army into the 8x8 auto battle against a real opponent.",
			"chips": ["8 x 8", "PvP"], "status": "COMING SOON"},
	]


## Arena: every playable continent is open. Opening it for play does NOT unlock it (Journey does that), so its Kings and Pawns stay locked.
func _open_continent_count() -> int:
	return _open_continents().size()


func _journey_status() -> String:
	var next := SaveManager.next_continent_goal()
	if next == "":
		return "%d trophies  -  every continent open" % SaveManager.trophies()
	return "%d trophies  -  %s at %d" % [SaveManager.trophies(), String(GameData.get_continent(next)["name"]).capitalize(), SaveManager.continent_trophies(next)]


func _on_card(id: String) -> void:
	match id:
		"journey", "arena":
			GameSession.chaos_mode = false
			_show_setup(id)
		"chaos":
			GameSession.chaos_mode = true  # Chaos is an Arena match on the 40-tile board (same continents, wager and rewards)
			_show_setup("arena")
		"battle_chess":
			_ask_battle_wager()
		"tutorial":
			SaveManager.clear_match()  # the tutorial replaces the saved match, like START MATCH
			GameSession.start_tutorial()
			get_tree().change_scene_to_file(BOARD_SCENE)


## Battle Chess has no setup screen: a dialog asks for the difficulty and an optional wager, then the battle starts.
func _ask_battle_wager() -> void:
	GameSession.wager = 0
	GameSession.category = "battle_chess"
	# The map (continent: world bonuses, cards shown) is random each battle; the army always comes from the Deck saved in the Card Hub.
	GameSession.battle_deck_continent = SaveManager.last_deck_continent()
	var maps := _open_continents()
	if not maps.is_empty():
		GameSession.continent_id = String(maps[randi() % maps.size()])
	var panel := WagerPanel.new("battle_chess", true)
	var dlg := UiDialog.new()
	dlg.name = "BattleWagerDialog"
	dlg.title = "Battle Chess"
	dlg.tone = "warn"
	dlg.ok_button_text = "FIGHT"
	dlg.cancel_button_text = "Cancel"
	dlg.body_node = panel
	dlg.confirmed.connect(func():
		GameSession.wager_odds = panel.odds()
		if GameSession.wager > 0 and not SaveManager.place_wager(GameSession.wager):
			GameSession.wager = 0
		dlg.queue_free()
		get_tree().change_scene_to_file(BATTLE_SCENE))
	dlg.canceled.connect(func():
		GameSession.wager = 0
		dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(600, 0))


## One mode card: a flat Button (background, hover, press, disabled) with the content stacked on top of it.
func _make_card(c: Dictionary, disabled: bool) -> Control:
	var accent: Color = ACCENT[c["id"]]
	var card := PanelContainer.new()
	card.name = "Card_" + String(c["id"])
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var btn := Button.new()
	btn.name = "Tap"
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = disabled
	btn.add_theme_stylebox_override("normal", _card_box(accent, 0))
	btn.add_theme_stylebox_override("hover", _card_box(accent, 1))
	btn.add_theme_stylebox_override("pressed", _card_box(accent, 2))
	btn.add_theme_stylebox_override("disabled", _card_box(accent, -1))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if not disabled:
		btn.pressed.connect(Sfx.click)
		btn.pressed.connect(_on_card.bind(String(c["id"])))
	card.add_child(btn)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	card.add_child(pad)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pad.add_child(v)

	var icon := ModeIcon.new(String(c["icon"]), accent)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	v.add_child(_centered(UiTheme.make_label(String(c["title"]), 28, accent.lightened(0.3))))
	v.add_child(_centered(UiTheme.make_label(String(c["sub"]), 16, UiTheme.COL_MUTED)))
	var desc := _centered(UiTheme.make_label(String(c["desc"]), 17))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var chips := HFlowContainer.new()
	chips.alignment = FlowContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	for t in c["chips"]:
		chips.add_child(_chip(String(t), accent))
	v.add_child(chips)
	if String(c["status"]) != "":
		var st := _centered(UiTheme.make_label(String(c["status"]), 16, UiTheme.COL_GOLD if disabled else accent.lightened(0.2)))
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(st)
	_ignore_mouse(pad)  # only the Button underneath receives taps
	if disabled:
		card.modulate = Color(1, 1, 1, 0.62)
	return card


func _card_box(accent: Color, state: int) -> StyleBoxFlat:
	var bg := Color(accent.darkened(0.82), 0.96)
	var border := accent.darkened(0.45)
	var width := 2
	var shadow := 8
	match state:
		1:  # hover
			bg = Color(accent.darkened(0.72), 0.98)
			border = accent
			shadow = 12
		2:  # pressed
			bg = Color(accent.darkened(0.6), 1.0)
			border = accent.lightened(0.2)
			width = 3
			shadow = 0
		-1:  # disabled (online, coming soon)
			bg = Color(UiTheme.COL_PANEL, 0.85)
			border = Color("2e3350")
			shadow = 0
	return UiTheme.make_box(bg, border, width, 18, shadow)


func _chip(text: String, accent: Color) -> Control:
	var p := PanelContainer.new()
	var sb := UiTheme.make_box(Color(accent, 0.16), accent.darkened(0.25), 1, 10, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(UiTheme.make_label(text, 15, accent.lightened(0.35)))
	return p


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in n.get_children():
		_ignore_mouse(ch)


# ============================================================ SETUP (Journey / Arena)

func _show_setup(kind: String) -> void:
	_view = "setup"
	_kind = kind
	GameSession.category = kind
	GameSession.wager = mini(GameSession.wager, SaveManager.coins())  # Journey and Arena both take a wager
	if kind == "journey":  # Journey has no difficulty choice: it follows the trophies, and the player wagers instead
		if _arena_difficulty == "":
			_arena_difficulty = String(GameSession.difficulty)
		GameSession.difficulty = SaveManager.journey_difficulty()
	elif _arena_difficulty != "":
		GameSession.difficulty = _arena_difficulty
		_arena_difficulty = ""
	GameSession.faction_id = SaveManager.player_faction_id()  # from the Deck, never chosen here
	if kind == "journey":
		GameSession.mode = "custom_ai"  # Journey is always 1 vs 1
		GameSession.ai_count = 1
		GameSession.continent_id = SaveManager.journey_frontier()
	else:
		var known := false
		for m in ARENA_MODES:
			if GameSession.mode == m["mode"] and GameSession.ai_count == m["ai"]:
				known = true
		if not known:
			GameSession.mode = "ffa_ai"
			GameSession.ai_count = 3
		if not GameData.get_continent(GameSession.continent_id).get("playable", false):
			GameSession.continent_id = "aetherion"
	_reset_root()

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	_root.add_child(head)
	head.add_child(UiTheme.make_label("NEW MATCH", 40, UiTheme.COL_GOLD))
	var crumb_id := "chaos" if (kind == "arena" and GameSession.chaos_mode) else kind
	var crumb := UiTheme.make_label("   >   OFFLINE   >   %s" % crumb_id.to_upper(), 24, ACCENT[crumb_id].lightened(0.2))
	crumb.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(crumb)
	_root.add_child(UiTheme.make_divider())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(cols)
	_build_match_column(cols)
	_build_continent_column(cols)
	_build_champion_column(cols)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	_root.add_child(bottom)
	var back := UiTheme.make_button("Back", 60)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_stretch_ratio = 1.0
	back.pressed.connect(_show_hub)
	bottom.add_child(back)
	var start := UiTheme.make_primary("START MATCH", 60)
	start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start.size_flags_stretch_ratio = 2.0
	start.pressed.connect(_on_start)
	bottom.add_child(start)
	_start_btn = start

	_refresh_continent_info()
	_refresh_champion()
	_refresh_journey_hint()


func _on_start() -> void:
	if not _can_start():
		return
	if GameSession.wager > 0:  # Journey and Arena
		GameSession.wager_odds = _wager_panel.odds() if _wager_panel != null else 2.0
		if not SaveManager.place_wager(GameSession.wager):  # the stake is paid now; not enough coins -> no wager
			GameSession.wager = 0
			if _wager_panel != null:
				_wager_panel.refresh()
			return
	GameSession.random_bonus_active = false
	if _kind == "arena" and GameSession.continent_random and _open_continents().size() >= 2:
		var pool := _open_continents()
		GameSession.continent_id = String(pool[randi() % pool.size()])
		GameSession.random_bonus_active = true
	SaveManager.clear_match()  # a new match replaces the saved one
	GameSession.resume_match = false
	GameSession.category = _kind
	GameSession.faction_id = SaveManager.player_faction_id()
	if _kind == "journey":
		GameSession.mode = "custom_ai"
		GameSession.ai_count = 1
	get_tree().change_scene_to_file(BOARD_SCENE)


func _column(parent: Control, title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var scroll := UiTheme.make_scroll()
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	v.add_child(UiTheme.make_label(title, 24, UiTheme.COL_GOLD))
	return v


func _build_match_column(parent: Control) -> void:
	var c := _column(parent, "Match", 0.85)
	if _kind == "arena":
		var note_text := "Free match against AI. Wins here do not unlock continents."
		if GameSession.chaos_mode:
			note_text = "CHAOS: a free match on a 40-tile board, 5 territories per region (majority 3, Dominion 5) and no portals. You pass the Gate far more often. Wins here do not unlock continents."
		var note := UiTheme.make_label(note_text, 15, UiTheme.COL_MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(note)
		c.add_child(UiTheme.make_label("Players", 20, UiTheme.COL_TEXT))
		var group := ButtonGroup.new()
		for m in ARENA_MODES:
			var b := UiTheme.make_toggle("%s\n%s" % [m["label"], m["sub"]], group, 70)
			b.button_pressed = (GameSession.mode == m["mode"] and GameSession.ai_count == m["ai"])
			b.pressed.connect(func():
				GameSession.mode = m["mode"]
				GameSession.ai_count = m["ai"]
				if _wager_panel != null:
					_wager_panel.refresh())  # the odds depend on the mode
			UiTheme.scroll_passthrough(b)
			c.add_child(b)
	else:
		var note := UiTheme.make_label("Story path: master a continent to unlock another one.", 15, UiTheme.COL_MUTED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(note)
		c.add_child(UiTheme.make_label("Players", 20, UiTheme.COL_TEXT))
		var fmt := PanelContainer.new()
		var fsb := UiTheme.make_box(Color(ACCENT["journey"], 0.12), ACCENT["journey"].darkened(0.35), 2, 12, 0)
		fmt.add_theme_stylebox_override("panel", fsb)
		fmt.custom_minimum_size = Vector2(0, 70)
		var fv := VBoxContainer.new()
		fv.alignment = BoxContainer.ALIGNMENT_CENTER
		fv.add_child(_centered(UiTheme.make_label("1 vs 1", 22, ACCENT["journey"].lightened(0.3))))
		fv.add_child(_centered(UiTheme.make_label("You vs 1 AI", 17, UiTheme.COL_MUTED)))
		fmt.add_child(fv)
		_ignore_mouse(fmt)  # a pure info box: drags on it still scroll the column
		c.add_child(fmt)
		_journey_hint = UiTheme.make_label("", 16, UiTheme.COL_GOLD)
		_journey_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(_journey_hint)
	_wager_panel = null
	if _kind == "arena":
		c.add_child(UiTheme.make_label("Difficulty", 20, UiTheme.COL_TEXT))
		var drow := HBoxContainer.new()
		drow.add_theme_constant_override("separation", 8)
		c.add_child(drow)
		var dgroup := ButtonGroup.new()
		for d in ["easy", "normal", "hard"]:
			var b := UiTheme.make_toggle(d.capitalize(), dgroup, 52)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.button_pressed = (GameSession.difficulty == d)
			b.pressed.connect(func():
				GameSession.difficulty = d
				_refresh_difficulty_note()
				_refresh_trophy_note()
				_refresh_journey_hint()
				if _wager_panel != null:
					_wager_panel.refresh())  # the odds depend on the difficulty
			UiTheme.scroll_passthrough(b)
			drow.add_child(b)
	var life_note := UiTheme.make_label("", 15, UiTheme.COL_MUTED)
	life_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(life_note)
	_difficulty_note = life_note
	_refresh_difficulty_note()
	_wager_panel = WagerPanel.new(_kind, false)  # "arena" | "journey"
	c.add_child(UiTheme.make_divider())
	c.add_child(_wager_panel)


## "Easy 0+, Normal 400+, Hard 1100+": the trophy ladder of the Journey AI level.
func _difficulty_ladder() -> String:
	var table: Dictionary = GameData.b("journey_difficulty_by_trophies", {})
	var rows: Array = []
	for d in table:
		rows.append([int(table[d]), String(d).capitalize()])
	rows.sort_custom(func(x, y): return x[0] < y[0])
	var parts: Array[String] = []
	for r in rows:
		parts.append("%s %d+" % [r[1], r[0]])
	return ", ".join(parts)


## Life and coin reward of the chosen difficulty (easy 5 Life / normal 3 / hard 1).
func _refresh_difficulty_note() -> void:
	if _difficulty_note == null:
		return
	var d := String(GameSession.difficulty)
	if _kind == "journey":  # no difficulty to pick: just state the fixed rules
		_difficulty_note.text = "AI level: %s - it follows your trophies (%s).\nEveryone starts with %d Life (a lost duel or bankruptcy costs 1). Reward: win +%d, loss +%d Aether Coins." % [
			d.capitalize(), _difficulty_ladder(), GameData.life_for(d), ShopSystem.win_reward(d), ShopSystem.loss_reward(d)]
		return
	_difficulty_note.text = "%s: everyone starts with %d Life (a lost duel or bankruptcy costs 1).\nReward: win +%d, loss +%d Aether Coins." % [
		d.capitalize(), GameData.life_for(d), ShopSystem.win_reward(d), ShopSystem.loss_reward(d)]


func _refresh_trophy_note() -> void:
	if _trophy_note == null or _kind != "journey":
		return
	var d := String(GameSession.difficulty)
	_trophy_note.text = "Trophies: %d.  Win +%d / defeat %d (%s).  Continents open at their trophy count." % [
		SaveManager.trophies(), SaveManager.trophy_delta(true, d), SaveManager.trophy_delta(false, d), d.capitalize()]


func _build_continent_column(parent: Control) -> void:
	var c := _column(parent, "Journey Map" if _kind == "journey" else "Continent", 1.0)
	var cnote: Label
	if _kind == "arena":
		cnote = UiTheme.make_label("Every continent is open in Arena. Its King and Pawn cards stay locked until you open it in the Journey.", 15, UiTheme.COL_MUTED)
	else:
		cnote = UiTheme.make_label("Trophies: %d.  Win +%d / defeat %d (%s).  Continents open at their trophy count." % [
			SaveManager.trophies(), SaveManager.trophy_delta(true, String(GameSession.difficulty)), SaveManager.trophy_delta(false, String(GameSession.difficulty)),
			String(GameSession.difficulty).capitalize()], 15, UiTheme.COL_GOLD)
	_trophy_note = cnote
	cnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(cnote)
	var random_on := _kind == "arena" and GameSession.continent_random and _open_continents().size() >= 2
	if _kind == "arena":
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 8)
		c.add_child(mrow)
		var mgroup := ButtonGroup.new()
		var can_random := _open_continents().size() >= 2
		for spec in [[true, "Random map\nBonus in game + on a win"], [false, "Choose map\nPick it yourself"]]:
			var mb := UiTheme.make_toggle(spec[1], mgroup, 64)
			mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mb.button_pressed = (random_on == spec[0])
			mb.disabled = spec[0] and not can_random
			mb.pressed.connect(func():
				GameSession.continent_random = spec[0]
				_show_setup("arena"))  # rebuild: the continent list is dimmed in random mode
			UiTheme.scroll_passthrough(mb)
			mrow.add_child(mb)
		if not can_random:
			var hint := UiTheme.make_label("Random needs 2 or more open continents.", 15, UiTheme.COL_MUTED)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.add_child(hint)
		elif random_on:
			var hint2 := UiTheme.make_label("Drawn from the %d continents at the start. Each continent gives its own bonus in the game and on a win." % _open_continents().size(), 15, UiTheme.COL_GOLD)
			hint2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			c.add_child(hint2)
	var group := ButtonGroup.new()
	for i in range(GameData.continents.size()):
		var cont: Dictionary = GameData.continents[i]
		var id := String(cont["id"])
		var open: bool = _is_continent_open(cont)
		var state := _continent_state(id, open)
		if random_on and open:  # random mode: each open continent shows the bonus it would pay
			state = ShopSystem.random_bonus_lines(id)
		var b := UiTheme.make_toggle("%d.  %s\n%s" % [i + 1, cont["name"], state], group, 84 if (random_on and open) else 58)
		b.disabled = not open or random_on
		b.button_pressed = (GameSession.continent_id == id) and not random_on
		b.pressed.connect(func():
			GameSession.continent_id = id
			_refresh_continent_info()
			_refresh_journey_hint())
		UiTheme.scroll_passthrough(b)
		c.add_child(b)


## Open for the current setup: Journey needs the continent unlocked; Arena plays on every playable continent
## (it never unlocks anything, so the King and Pawn cards of a continent still locked in Journey stay locked).
func _is_continent_open(cont: Dictionary) -> bool:
	if not cont.get("playable", false):
		return false
	return _kind == "arena" or SaveManager.is_continent_unlocked(String(cont["id"]))


## Continents of the Arena random map pool: every playable one.
func _open_continents() -> Array:
	var out: Array = []
	for cont in GameData.continents:
		if cont.get("playable", false):
			out.append(String(cont["id"]))
	return out


func _continent_state(id: String, open: bool) -> String:
	if not open:
		return "Locked  -  %d trophies" % SaveManager.continent_trophies(id)
	if _kind != "journey":
		return "Open" if SaveManager.is_continent_unlocked(id) else "Open  -  King & Pawn stay locked"
	return "Open  -  from %d trophies" % SaveManager.continent_trophies(id)


## Read-only: the faction comes from the Deck. The button jumps to the Deck's faction list.
func _build_champion_column(parent: Control) -> void:
	var c := _column(parent, "Your Faction", 1.3)
	var note := UiTheme.make_label("Chosen in your Deck and used in every match.", 15, UiTheme.COL_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(note)
	var champ_row := HBoxContainer.new()
	champ_row.add_theme_constant_override("separation", 8)
	c.add_child(champ_row)
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
	var change := UiTheme.make_button("Change faction in Deck", 56)
	change.pressed.connect(_open_deck)
	UiTheme.scroll_passthrough(change)
	c.add_child(change)
	c.add_child(UiTheme.make_label("Continent", 20, UiTheme.COL_TEXT))
	_continent_text = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
	_continent_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(_continent_text)
	_home_note = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
	_home_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.add_child(_home_note)


func _open_deck() -> void:
	GameSession.setup_return = _kind  # Back in the Card Hub returns to this Journey / Arena setup
	GameSession.open_deck_tab = true
	GameSession.collection_return = "res://scenes/match_setup/match_setup.tscn"
	get_tree().change_scene_to_file("res://scenes/card_collection/card_collection.tscn")


func _continent_index(id: String) -> int:
	for i in range(GameData.continents.size()):
		if GameData.continents[i]["id"] == id:
			return i
	return 0


## Home-continent rule: the faction (and its bonuses) is at home only on its own continent.
## Journey requires a home faction; Arena allows any unlocked faction on any continent.
func _is_home() -> bool:
	return GameData.is_home_faction(SaveManager.player_faction_id(), GameSession.continent_id)


func _can_start() -> bool:
	return _kind != "journey" or _is_home()


func _refresh_home_note() -> void:
	if _start_btn != null:
		_start_btn.disabled = not _can_start()
	if _home_note == null:
		return
	var cname := String(GameData.get_continent(GameSession.continent_id).get("name", GameSession.continent_id))
	var fid := SaveManager.player_faction_id()
	var fname := String(GameData.find_faction(fid).get("name", fid.capitalize()))
	if _is_home():
		_home_note.text = "Home continent: %s bonuses (King Buff + unit buffs + Faction Synergy) are active on %s." % [fname, cname]
		_home_note.add_theme_color_override("font_color", UiTheme.COL_GOLD)
	elif _kind == "journey":
		_home_note.text = "Journey needs a faction of %s. Change faction in your Deck." % cname
		_home_note.add_theme_color_override("font_color", UiTheme.COL_MUTED)
	else:
		_home_note.text = "%s is foreign to %s: playable, but without its King Buff and unit buffs (the Battle Passive, Faction Tier and Grand Army (Faction) still work)." % [fname, cname]
		_home_note.add_theme_color_override("font_color", UiTheme.COL_MUTED)


func _refresh_journey_hint() -> void:
	_refresh_home_note()
	if _journey_hint == null:
		return
	var cid := GameSession.continent_id
	var cname := String(GameData.get_continent(cid).get("name", cid))
	var fid := SaveManager.player_faction_id()
	var fname := String(GameData.find_faction(fid).get("name", fid.capitalize()))
	var d := String(GameSession.difficulty)
	if GameData.get_faction(cid, fid).is_empty():
		_journey_hint.text = "%s is not a faction of %s: Journey only allows its own factions. Pick one in your Deck." % [fname, cname]
	else:
		_journey_hint.text = "Win with %s on %s: +%d trophies. A defeat: %d." % [fname, cname, SaveManager.trophy_delta(true, d), SaveManager.trophy_delta(false, d)]


func _refresh_continent_info() -> void:
	if _continent_text == null:
		return
	if _kind == "arena" and GameSession.continent_random and _open_continents().size() >= 2:
		_continent_text.text = "Random: the continent (and its modifier) is drawn when the match starts."
		_continent_text.tooltip_text = ""
		return
	var cont := GameData.get_continent(GameSession.continent_id)
	_continent_text.text = "%s: %s" % [cont["modifier"]["name"], cont["modifier"]["description"]]
	_continent_text.tooltip_text = String(cont.get("theme", ""))


func _king_buff_line(champion_id: String) -> String:
	var out := ""
	var kp: Dictionary = GameData.king_passives.get(champion_id, {})
	if not kp.is_empty():
		out += "\n[b]Battle Passive %s:[/b] %s" % [kp["name"], kp["desc"]]
	var kb := CardDatabase.king_buff(champion_id, false)
	if not kb.is_empty():
		out += "\n[b]King Buff %s:[/b] %s (%s)" % [kb["name"], kb["desc"], "active" if _is_home() else "home continent only"]
	return out


func _refresh_champion() -> void:
	var fid := SaveManager.player_faction_id()
	GameSession.faction_id = fid
	var fac := GameData.find_faction(fid)
	var ch := GameData.get_champion(String(fac.get("champion", "")))
	if ch.is_empty():
		_champion_text.text = ""
		_portrait.setup("")
		return
	_portrait.setup(String(fac.get("champion", "")))
	_champion_text.text = "[color=#d4af37][b]%s[/b][/color]\n[color=#d4af37]%s  -  %s King, Last Stand[/color]\nHP %d   ATK %d   Capacity %d\n[b]%s:[/b] %s\n[b]%s:[/b] %s%s" % [
		fac.get("name", fid.capitalize()), ch["name"], String(ch.get("rarity", "legendary")).capitalize(), ch["hp"], ch["atk"], ch["capacity"], ch["passive_name"], ch["passive_desc"], ch["active_name"], ch["active_desc"], _king_buff_line(String(fac.get("champion", "")))]
