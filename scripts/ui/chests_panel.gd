class_name ChestsPanel
extends VBoxContainer
## Chests panel (tab "Chests" of the Events screen): the 4 reward-chest slots (see ChestSystem). A chest earned by winning an Arena match waits in a slot,
## is unlocked by a real-time timer (one at a time, it keeps running while the game is closed) and opened for coins,
## fragments, chips, tickets, crystals and XP. Crystals skip the timer.

var _cards: Array = []
var _info_label: Label
var _storage_title: Label
var _storage_list: VBoxContainer
var _storage_sig := ""
var _tick := 0.0
var _rng := RandomNumberGenerator.new()
var _dialog: UiDialog = null


## Drawn chest: body in the grade colour, lid, bands and a lock. `open` raises the lid with a glow; `empty` shows a dashed slot.
class ChestIcon extends Control:
	var grade: String = ""
	var open: bool = false
	var ready_glow: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(150, 110)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(g: String, is_open: bool) -> void:
		grade = g
		open = is_open
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var cx := w * 0.5
		if grade == "":  # empty slot: dashed outline
			var r := Rect2(cx - 50.0, h * 0.25, 100.0, 62.0)
			draw_rect(r, Color(UiTheme.COL_MUTED, 0.5), false, 2.0)
			draw_string(ThemeDB.fallback_font, Vector2(cx - 50.0, h * 0.25 + 40.0), "EMPTY", HORIZONTAL_ALIGNMENT_CENTER, 100.0, 18, Color(UiTheme.COL_MUTED, 0.7))
			return
		var c := ChestSystem.grade_color(grade)
		var body := Rect2(cx - 52.0, h * 0.42, 104.0, 56.0)
		if open:
			draw_circle(Vector2(cx, h * 0.42), 46.0, Color(c, 0.18))
			draw_circle(Vector2(cx, h * 0.42), 30.0, Color(1, 1, 0.8, 0.22))
		draw_rect(body, c.darkened(0.45))
		draw_rect(body, c, false, 3.0)
		draw_rect(Rect2(body.position.x + 14.0, body.position.y, 12.0, body.size.y), c.darkened(0.15))
		draw_rect(Rect2(body.end.x - 26.0, body.position.y, 12.0, body.size.y), c.darkened(0.15))
		if open:  # lid swung back
			var lid := PackedVector2Array([Vector2(body.position.x, body.position.y), Vector2(body.end.x, body.position.y),
				Vector2(body.end.x - 6.0, body.position.y - 34.0), Vector2(body.position.x + 6.0, body.position.y - 34.0)])
			draw_colored_polygon(lid, c.darkened(0.25))
			draw_polyline(PackedVector2Array([lid[0], lid[3], lid[2], lid[1]]), c, 3.0)
			draw_rect(Rect2(body.position.x + 6.0, body.position.y - 4.0, body.size.x - 12.0, 5.0), Color(1.0, 0.92, 0.55, 0.9))
		else:
			var lidr := Rect2(body.position.x - 3.0, body.position.y - 24.0, body.size.x + 6.0, 26.0)
			draw_rect(lidr, c.darkened(0.2))
			draw_rect(lidr, c, false, 3.0)
			draw_rect(Rect2(lidr.position.x + 17.0, lidr.position.y, 12.0, lidr.size.y), c.darkened(0.05))
			draw_rect(Rect2(lidr.end.x - 29.0, lidr.position.y, 12.0, lidr.size.y), c.darkened(0.05))
			var lock := Rect2(cx - 9.0, body.position.y - 8.0, 18.0, 20.0)  # lock plate
			draw_rect(lock, Color("2b2410"))
			draw_rect(lock, UiTheme.COL_GOLD, false, 2.0)
			draw_circle(lock.get_center(), 3.0, UiTheme.COL_GOLD)


## One slot: icon, title, timer + progress bar and its buttons. Built once, `refresh()` only changes texts and visibility.
class SlotCard extends PanelContainer:
	signal unlock_pressed(i: int)
	signal skip_pressed(i: int)
	signal open_pressed(i: int)

	var index: int = 0
	var icon: ChestIcon
	var title: Label
	var status: Label
	var bar: ProgressBar
	var unlock_btn: Button
	var skip_btn: Button
	var open_btn: Button

	func _init(i: int) -> void:
		index = i
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(190, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		add_child(v)
		v.add_child(UiTheme.make_label("SLOT %d" % (i + 1), 16, UiTheme.COL_MUTED))
		icon = ChestIcon.new()
		v.add_child(icon)
		title = UiTheme.make_label("", 24, UiTheme.COL_TEXT)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(title)
		status = UiTheme.make_label("", 18, UiTheme.COL_MUTED)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(status)
		bar = ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.max_value = 1.0
		bar.step = 0.0
		bar.add_theme_stylebox_override("background", UiTheme.make_box(Color("111629"), Color("2e3350"), 1, 6))
		v.add_child(bar)
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sp)
		unlock_btn = UiTheme.make_primary("Unlock", 56)
		unlock_btn.pressed.connect(func(): unlock_pressed.emit(index))
		v.add_child(unlock_btn)
		open_btn = UiTheme.make_primary("OPEN", 64)
		open_btn.pressed.connect(func(): open_pressed.emit(index))
		v.add_child(open_btn)
		skip_btn = UiTheme.make_button("", 52)
		skip_btn.pressed.connect(func(): skip_pressed.emit(index))
		v.add_child(skip_btn)

	func refresh() -> void:
		var st := ChestSystem.state(index)
		var g := ChestSystem.grade_at(index)
		var col := ChestSystem.grade_color(g) if g != "" else Color("2e3350")
		add_theme_stylebox_override("panel", UiTheme.make_box(Color(UiTheme.COL_PANEL, 0.94), col if st != "empty" else Color("2e3350"), 3 if st == "ready" else 2, 16, 10 if st == "ready" else 4))
		icon.set_state(g, st == "ready")
		unlock_btn.visible = st == "locked"
		open_btn.visible = st == "ready"
		skip_btn.visible = st == "locked" or st == "unlocking"
		bar.visible = st == "unlocking" or st == "ready"
		match st:
			"empty":
				title.text = "Empty"
				title.add_theme_color_override("font_color", UiTheme.COL_MUTED)
				status.text = "Win an Arena match to earn a chest."
			"locked":
				title.text = ChestSystem.grade_name(g)
				title.add_theme_color_override("font_color", col)
				status.text = "Unlock time: %s" % ChestSystem.duration_text(ChestSystem.grade_seconds(g))
				var busy := ChestSystem.unlocking_slot() >= 0
				unlock_btn.disabled = busy
				unlock_btn.text = "Waiting for the other chest" if busy else "Start unlocking"
			"unlocking":
				title.text = ChestSystem.grade_name(g)
				title.add_theme_color_override("font_color", col)
				status.text = ChestSystem.clock_text(ChestSystem.remaining(index))
				bar.value = 1.0 - float(ChestSystem.remaining(index)) / float(ChestSystem.grade_seconds(g))
				bar.add_theme_stylebox_override("fill", UiTheme.make_box(col, col, 0, 6))
			"ready":
				title.text = ChestSystem.grade_name(g)
				title.add_theme_color_override("font_color", col)
				status.text = "Ready!"
				bar.value = 1.0
				bar.add_theme_stylebox_override("fill", UiTheme.make_box(col, col, 0, 6))
		if skip_btn.visible:
			var cost := ChestSystem.skip_cost(index)
			skip_btn.text = "Open now  (%d Crystal%s)" % [cost, "" if cost == 1 else "s"]
			skip_btn.disabled = SaveManager.crystals() < cost


func _ready() -> void:
	_rng.randomize()
	add_theme_constant_override("separation", 10)

	_info_label = UiTheme.make_label("", 18, UiTheme.COL_MUTED)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info_label)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(row)
	main.add_child(_build_storage())
	for i in range(ChestSystem.SLOT_COUNT):
		var card := SlotCard.new(i)
		card.unlock_pressed.connect(_on_unlock)
		card.skip_pressed.connect(_on_skip)
		card.open_pressed.connect(_on_open)
		row.add_child(card)
		_cards.append(card)

	# What each grade holds.
	var scroll := UiTheme.make_scroll()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	scroll.add_child(info)
	for g in ChestSystem.GRADES:
		var l := UiTheme.make_label("%s  (%s):  %s" % [ChestSystem.grade_name(g), ChestSystem.duration_text(ChestSystem.grade_seconds(g)), ChestSystem.reward_summary(g)], 16, ChestSystem.grade_color(g).lightened(0.2))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(l)
	refresh()


## Storage beside the slots: unopened chests that did not fit in a slot. "To slot" moves one into the first free slot.
func _build_storage() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(290, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.make_box(Color(UiTheme.COL_PANEL, 0.94), Color("3b3a55"), 2, 16, 4))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_storage_title = UiTheme.make_label("", 22, UiTheme.COL_GOLD)
	v.add_child(_storage_title)
	var hint := UiTheme.make_label("Chests that do not fit in a slot wait here.", 15, UiTheme.COL_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var scroll := UiTheme.make_scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_storage_list = VBoxContainer.new()
	_storage_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_storage_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_storage_list)
	return panel


func _refresh_storage() -> void:
	var stock := ChestSystem.storage()
	_storage_title.text = "STORAGE  %d/%d" % [stock.size(), ChestSystem.STORAGE_CAPACITY]
	var can_move := ChestSystem.free_slots() > 0
	var sig := "%s|%s" % [",".join(PackedStringArray(stock)), can_move]
	if sig == _storage_sig:
		return
	_storage_sig = sig
	for c in _storage_list.get_children():
		_storage_list.remove_child(c)
		c.queue_free()
	if stock.is_empty():
		var e := UiTheme.make_label("Empty", 18, UiTheme.COL_MUTED)
		_storage_list.add_child(e)
		return
	for i in range(stock.size()):
		var g := String(stock[i])
		var col := ChestSystem.grade_color(g)
		var item := PanelContainer.new()
		item.add_theme_stylebox_override("panel", UiTheme.make_box(Color("111629"), col, 2, 10, 2))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		item.add_child(h)
		var lbl := UiTheme.make_label(ChestSystem.grade_name(g), 18, col)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(lbl)
		var b := UiTheme.make_button("To slot", 44)
		b.disabled = not can_move
		b.pressed.connect(_on_move.bind(i))
		h.add_child(b)
		_storage_list.add_child(item)


func _on_move(i: int) -> void:
	var err := ChestSystem.move_to_slot(i)
	if err != "":
		Sfx.play("error")
		_message("Cannot move", err)
	else:
		Sfx.play("magic")
	refresh()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_tick += delta
	if _tick >= 0.5:
		_tick = 0.0
		refresh()


func refresh() -> void:
	for c in _cards:
		(c as SlotCard).refresh()
	_refresh_storage()
	var ready := ChestSystem.ready_count()
	var wait := ChestSystem.limit_seconds_left()
	var drops := "Chest drops: %d/%d" % [ChestSystem.drops_used(), ChestSystem.DROP_LIMIT]
	if wait > 0:
		drops += "  (limit reached, refreshes in %s)" % ChestSystem.clock_text(wait)
	_info_label.text = "Win Arena matches to earn chests (a full set of slots sends them to the Storage). Only one chest unlocks at a time and the timer keeps running while the game is closed.   %s   Ready to open: %d   Free slots: %d   Storage: %d/%d" % [drops, ready, ChestSystem.free_slots(), ChestSystem.storage_count(), ChestSystem.STORAGE_CAPACITY]


func _on_unlock(i: int) -> void:
	var err := ChestSystem.start_unlock(i)
	if err != "":
		Sfx.play("error")
		_message("Cannot unlock", err)
	else:
		Sfx.play("magic")
	refresh()


func _on_skip(i: int) -> void:
	var cost := ChestSystem.skip_cost(i)
	var dlg := _new_dialog("Open now?")
	dlg.tone = "warn"
	dlg.dialog_text = "Spend %d Crystal%s to finish the timer of the %s?" % [cost, "" if cost == 1 else "s", ChestSystem.grade_name(ChestSystem.grade_at(i))]
	dlg.ok_button_text = "Spend"
	dlg.cancel_button_text = "Cancel"
	var slot := i
	dlg.confirmed.connect(func():
		var err := ChestSystem.skip(slot)
		if err != "":
			Sfx.play("error")
		refresh())
	dlg.popup_centered(Vector2i(520, 0))


func _on_open(i: int) -> void:
	var grade := ChestSystem.grade_at(i)
	var res := ChestSystem.open(i, _rng)
	refresh()
	if not res["ok"]:
		Sfx.play("error")
		_message("Cannot open", String(res["error"]))
		return
	Sfx.play("victory" if grade == "gold" else "coin")
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	var icon := ChestIcon.new()
	icon.set_state(grade, true)
	body.add_child(icon)
	for line in ChestSystem.reward_lines(res["rewards"]):
		var l := UiTheme.make_label(line, 26, UiTheme.COL_GOLD)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(l)
	if String(res["card"]) != "":
		var cl := UiTheme.make_label("New card unlocked: %s" % CardDatabase.get_support(String(res["card"]))["name"], 22, Color("a98be0"))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(cl)
	if int(res["level_up"]) > 0:
		var ll := UiTheme.make_label("LEVEL UP!  Lv %d - %s" % [int(res["level_up"]), XpSystem.title(int(res["level_up"]))], 22, UiTheme.COL_GOLD)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(ll)
		var lr := UiTheme.make_label(SaveManager.level_reward_line(), 20, UiTheme.COL_GOLD)
		lr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(lr)
	var dlg := _new_dialog(ChestSystem.grade_name(grade))
	dlg.body_node = body
	dlg.show_cancel = false
	dlg.ok_button_text = "Collect"
	dlg.popup_centered(Vector2i(520, 0))


func _message(title: String, text: String) -> void:
	var dlg := _new_dialog(title)
	dlg.tone = "warn"
	dlg.dialog_text = text
	dlg.show_cancel = false
	dlg.popup_centered(Vector2i(480, 0))


func _new_dialog(title: String) -> UiDialog:
	var dlg := UiDialog.new()
	dlg.title = title
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	return dlg
