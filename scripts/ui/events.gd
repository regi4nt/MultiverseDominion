extends Control
## Events screen with three tabs: Mission (4 daily missions, reset at midnight), Achievement (permanent goals)
## and Chests (the 4 reward-chest slots, see ChestsPanel). Finished entries show a Claim button that pays the reward (see EventHub).

const TABS := [["mission", "Mission"], ["achievement", "Achievement"], ["chest", "Chests"]]

var _tab := "mission"
var _tab_buttons: Dictionary = {}
var _lists: Dictionary = {}  # tab id -> VBoxContainer (mission / achievement)
var _chest_panel: ChestsPanel
var _wallet_labels: Dictionary = {}
var _reset_label: Label
var _tick := 0.0
var _dialog_host: Node


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_child(UiTheme.make_background())
	var margin := UiTheme.make_margin(16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	root.add_child(head)
	head.add_child(UiTheme.make_label("EVENTS", 36, UiTheme.COL_GOLD))
	var wallet := HFlowContainer.new()
	wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wallet.alignment = FlowContainer.ALIGNMENT_END
	wallet.add_theme_constant_override("h_separation", 14)
	head.add_child(wallet)
	for spec in [["coins", Color("d4af37")], ["fragments", Color("a98be0")], ["tickets", Color("ff9f5a")], ["crystals", Color("7fd8ff")], ["chips", Color("59cd90")]]:
		var l := UiTheme.make_label("", 22, spec[1])
		wallet.add_child(l)
		_wallet_labels[spec[0]] = l
	var back := UiTheme.make_button("Back", 48)
	back.custom_minimum_size.x = 140
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn"))
	head.add_child(back)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	var group := ButtonGroup.new()
	for spec in TABS:
		var b := UiTheme.make_toggle(spec[1], group, 52)
		b.custom_minimum_size.x = 200
		b.button_pressed = (spec[0] == _tab)
		b.pressed.connect(_show_tab.bind(spec[0]))
		tabs.add_child(b)
		_tab_buttons[spec[0]] = b
	_reset_label = UiTheme.make_label("", 18, UiTheme.COL_MUTED)
	_reset_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reset_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs.add_child(_reset_label)

	for spec in TABS:
		if spec[0] == "chest":
			continue
		var scroll := UiTheme.make_scroll()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		root.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 8)
		scroll.add_child(list)
		_lists[spec[0]] = list
		scroll.set_meta("tab", spec[0])
	_chest_panel = ChestsPanel.new()
	_chest_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_chest_panel)
	_show_tab("mission")


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_header()
		if _tab == "mission" and EventHub.today() != String(_lists["mission"].get_meta("day", "")):
			_rebuild()  # midnight passed while the screen was open


func _show_tab(which: String) -> void:
	_tab = which
	for id in _lists:
		(_lists[id].get_parent() as Control).visible = (id == which)
	_chest_panel.visible = which == "chest"
	for id in _tab_buttons:
		(_tab_buttons[id] as Button).set_pressed_no_signal(id == which)
	_rebuild()


func _update_header() -> void:
	for k in _wallet_labels:
		(_wallet_labels[k] as Label).text = "%d %s" % [SaveManager.currency(String(k)), k]
	_reset_label.visible = _tab == "mission"
	_reset_label.text = "Resets in %s" % ChestSystem.clock_text(EventHub.seconds_to_reset())
	for spec in TABS:
		var id := String(spec[0])
		var n := ChestSystem.ready_count() if id == "chest" else EventHub.claimable_count_in(id == "mission")
		(_tab_buttons[id] as Button).text = "%s%s" % [String(spec[1]), "  (%d)" % n if n > 0 else ""]


func _rebuild() -> void:
	_update_header()
	if _tab == "chest":
		_chest_panel.refresh()
		return
	var daily := _tab == "mission"
	var list: VBoxContainer = _lists[_tab]
	for c in list.get_children():
		c.queue_free()
		list.remove_child(c)
	if daily:
		list.set_meta("day", EventHub.today())
	var defs: Array = EventHub.daily_missions() if daily else EventHub.ACHIEVEMENTS.duplicate()
	# Claimable first, then in progress, claimed last.
	var ordered: Array = []
	for pass_n in range(3):
		for d in defs:
			var st := 0 if EventHub.can_claim(d, daily) else (2 if EventHub.is_claimed(String(d["id"]), daily) else 1)
			if st == pass_n:
				ordered.append(d)
	for d in ordered:
		list.add_child(_make_row(d, daily))


func _make_row(d: Dictionary, daily: bool) -> Control:
	var claimed := EventHub.is_claimed(String(d["id"]), daily)
	var can := EventHub.can_claim(d, daily)
	var panel := PanelContainer.new()
	var border := UiTheme.COL_GOLD if can else (Color("2e3350") if claimed else Color("3b3a55"))
	panel.add_theme_stylebox_override("panel", UiTheme.make_box(Color(UiTheme.COL_PANEL, 0.94 if not claimed else 0.6), border, 3 if can else 2, 14, 4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	panel.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	v.add_child(UiTheme.make_label(String(d["name"]), 24, UiTheme.COL_GOLD if not claimed else UiTheme.COL_MUTED))
	var desc := UiTheme.make_label(String(d["desc"]), 17, UiTheme.COL_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)
	var cur := EventHub.progress(d, daily)
	var target := int(d["target"])
	var bar := ProgressBar.new()
	bar.max_value = target
	bar.value = cur
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.add_theme_stylebox_override("background", UiTheme.make_box(Color("111629"), Color("2e3350"), 1, 7))
	bar.add_theme_stylebox_override("fill", UiTheme.make_box(Color("59cd90"), Color("59cd90"), 0, 7))
	v.add_child(bar)
	v.add_child(UiTheme.make_label("%d / %d" % [cur, target], 16, UiTheme.COL_MUTED))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(230, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 6)
	h.add_child(right)
	var rl := UiTheme.make_label(", ".join(ChestSystem.reward_lines(d["reward"])).replace("+", ""), 16, Color("ffe08a"))
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(rl)
	var btn: Button = UiTheme.make_primary("Claim", 52) if can else UiTheme.make_button("Claimed" if claimed else "In progress", 52)
	btn.disabled = not can
	if can:
		btn.pressed.connect(_on_claim.bind(String(d["id"]), daily))
	right.add_child(btn)
	return panel


func _on_claim(id: String, daily: bool) -> void:
	var res := EventHub.claim(id, daily)
	if not res["ok"]:
		Sfx.play("error")
		return
	Sfx.play("coin")
	var dlg := UiDialog.new()
	dlg.title = "Reward claimed"
	dlg.dialog_text = "\n".join(ChestSystem.reward_lines(res["rewards"]))
	dlg.show_cancel = false
	dlg.ok_button_text = "OK"
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(420, 0))
	_rebuild()
