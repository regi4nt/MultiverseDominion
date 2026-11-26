class_name StoryPanel
extends Control
## Floating story card of the Journey: a prologue, 7 chapters (one per continent, 1st to 7th) and an epilogue.
## Simple layout: page tabs (P, 1-7, E; locked pages show a lock), title, scrolling text, Previous / Next / Close.
## Opens on `start_id` (see StorySystem). Emits `closed` when the player leaves it. Reading a page marks it as seen.

signal closed

const TAB_LABELS := {"prologue": "P", "epilogue": "E"}

var _pages: Array = []
var _id: String = ""
var _tabs: Dictionary = {}  # page id -> Button
var _kicker: Label
var _title: Label
var _body: RichTextLabel
var _goal: Label
var _prev: Button
var _next: Button
var _card: PanelContainer


func _init(start_id: String = "") -> void:
	_pages = StorySystem.page_ids()
	_id = start_id if _pages.has(start_id) and StorySystem.is_open(start_id) else StorySystem.PROLOGUE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the screen behind the card is blocked while it is open


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(680, 0)
	center.add_child(_card)
	var m := UiTheme.make_margin(20)
	_card.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	m.add_child(box)

	# page tabs
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	var grp := ButtonGroup.new()
	for id in _pages:
		var sid := String(id)
		var open := StorySystem.is_open(sid)
		var label: String = String(TAB_LABELS[sid]) if TAB_LABELS.has(sid) else str(StorySystem.chapter_number(sid))
		var b := UiTheme.make_toggle(label if open else "?", grp, 44)
		b.custom_minimum_size.x = 52
		b.disabled = not open
		b.tooltip_text = String(StorySystem.page(sid).get("title", "")) if open else "Locked: keep going on the Journey"
		b.pressed.connect(_show_page.bind(sid))
		tabs.add_child(b)
		_tabs[sid] = b

	_kicker = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_kicker)
	_title = UiTheme.make_label("", 30, UiTheme.COL_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	box.add_child(UiTheme.make_divider())

	var scroll := UiTheme.make_scroll()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 19)
	_body.add_theme_constant_override("line_separation", 4)
	scroll.add_child(_body)

	_goal = UiTheme.make_label("", 15, UiTheme.COL_GOLD)
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_goal)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	box.add_child(nav)
	_prev = UiTheme.make_button("< Previous", 48)
	_prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev.pressed.connect(_step.bind(-1))
	nav.add_child(_prev)
	var close := UiTheme.make_primary("Close", 48)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(close_panel)
	nav.add_child(close)
	_next = UiTheme.make_button("Next >", 48)
	_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next.pressed.connect(_step.bind(1))
	nav.add_child(_next)
	_show_page(_id)


## Android Back / Esc closes the card.
func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k != null and k.pressed and k.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func close_panel() -> void:
	closed.emit()
	queue_free()


## Moves to the previous / next page that is open (locked pages are skipped).
func _step(dir: int) -> void:
	var i := _pages.find(_id) + dir
	while i >= 0 and i < _pages.size():
		if StorySystem.is_open(String(_pages[i])):
			_show_page(String(_pages[i]))
			return
		i += dir


func _show_page(id: String) -> void:
	_id = id
	var p := StorySystem.page(id)
	match String(p.get("kind", "")):
		"chapter":
			var cont := GameData.get_continent(id)
			_kicker.text = "CHAPTER %d of %d  -  %s" % [int(p["number"]), StorySystem.chapters().size(), String(cont.get("name", id))]
			if cont.has("color"):
				_kicker.add_theme_color_override("font_color", Color(String(cont["color"])).lightened(0.2))
		"epilogue":
			_kicker.text = "EPILOGUE"
			_kicker.add_theme_color_override("font_color", UiTheme.COL_MUTED)
		_:
			_kicker.text = "PROLOGUE"
			_kicker.add_theme_color_override("font_color", UiTheme.COL_MUTED)
	_title.text = String(p.get("title", ""))
	var paragraphs: Array = p.get("lines", [])
	_body.text = "\n\n".join(PackedStringArray(paragraphs.map(func(s): return String(s))))
	var goal := String(p.get("goal", ""))
	_goal.text = ("Goal: " + goal) if goal != "" and id == StorySystem.current_id() else ""
	for k in _tabs:
		(_tabs[k] as Button).set_pressed_no_signal(k == id)
	_prev.disabled = not _has_open(-1)
	_next.disabled = not _has_open(1)
	StorySystem.mark_seen(id)


func _has_open(dir: int) -> bool:
	var i := _pages.find(_id) + dir
	while i >= 0 and i < _pages.size():
		if StorySystem.is_open(String(_pages[i])):
			return true
		i += dir
	return false
