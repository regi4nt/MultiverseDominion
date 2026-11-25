class_name WagerPanel
extends VBoxContainer
## Wager picker for Journey, Arena and Battle Chess: choose a stake of Aether Coins (slider, multiples of 10) before the match.
## The stake is paid when the match starts; a win pays stake x odds (the stake included), a loss loses it,
## Battle Chess returns it on a draw. Odds depend on the mode and the difficulty (ShopSystem.wager_odds).
## Writes GameSession.wager; the host reads `odds()` when it starts the match.

signal changed

var kind: String = "arena"  # "journey" | "arena" | "battle_chess"
var with_difficulty: bool = false  # Battle Chess has no setup screen: the panel shows the difficulty too

var _slider: HSlider
var _minus: Button
var _plus: Button
var _value: Label
var _info: Label
var _balance: Label
var _series_info: Label


func _init(k: String = "arena", difficulty_row: bool = false) -> void:
	kind = k
	with_difficulty = difficulty_row
	add_theme_constant_override("separation", 6)


func _ready() -> void:
	if with_difficulty:
		add_child(UiTheme.make_label("Difficulty", 20, UiTheme.COL_TEXT))
		var drow := HBoxContainer.new()
		drow.add_theme_constant_override("separation", 8)
		add_child(drow)
		var dgroup := ButtonGroup.new()
		for d in ["easy", "normal", "hard"]:
			var b := UiTheme.make_toggle(String(d).capitalize(), dgroup, 48)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.button_pressed = (GameSession.difficulty == d)
			b.pressed.connect(func():
				GameSession.difficulty = d
				refresh())
			drow.add_child(b)
	if with_difficulty:  # Battle Chess: how long the run is (1 round / 10 rounds / until the first defeat)
		add_child(UiTheme.make_label("Length", 20, UiTheme.COL_TEXT))
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 8)
		add_child(lrow)
		var lgroup := ButtonGroup.new()
		for sid in ShopSystem.SERIES_IDS:
			var lb := UiTheme.make_toggle(ShopSystem.series_title(sid), lgroup, 48)
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lb.button_pressed = (GameSession.battle_series == sid)
			lb.pressed.connect(func():
				GameSession.battle_series = sid
				refresh())
			lrow.add_child(lb)
		_series_info = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
		_series_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_series_info)
	var head := HBoxContainer.new()
	add_child(head)
	var title := UiTheme.make_label("Wager", 20, UiTheme.COL_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_balance = UiTheme.make_label("", 16, UiTheme.COL_GOLD)
	head.add_child(_balance)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	add_child(line)
	_minus = UiTheme.make_button("-", 48)
	_minus.custom_minimum_size.x = 56
	_minus.pressed.connect(func(): _on_pick(GameSession.wager - ShopSystem.WAGER_STEP))
	line.add_child(_minus)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = ShopSystem.WAGER_MAX
	_slider.step = ShopSystem.WAGER_STEP
	_slider.rounded = true
	_slider.custom_minimum_size = Vector2(160, 40)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.scrollable = false  # the mouse wheel must scroll the page, not change the stake
	_slider.value_changed.connect(func(v: float): _on_pick(int(v)))
	line.add_child(_slider)
	_plus = UiTheme.make_button("+", 48)
	_plus.custom_minimum_size.x = 56
	_plus.pressed.connect(func(): _on_pick(GameSession.wager + ShopSystem.WAGER_STEP))
	line.add_child(_plus)
	_value = UiTheme.make_label("None", 18, UiTheme.COL_GOLD)
	_value.custom_minimum_size.x = 72
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(_value)
	_info = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	refresh()


func odds() -> float:
	return ShopSystem.wager_odds(kind, GameSession.mode, GameSession.ai_count, GameSession.difficulty, GameSession.chaos_mode)


## Highest stake the player can pay now: the balance rounded down to a multiple of WAGER_STEP, capped at WAGER_MAX.
func max_stake() -> int:
	return mini(SaveManager.coins() / ShopSystem.WAGER_STEP * ShopSystem.WAGER_STEP, ShopSystem.WAGER_MAX)


func _on_pick(amount: int) -> void:
	GameSession.wager = clampi(amount, 0, max_stake()) / ShopSystem.WAGER_STEP * ShopSystem.WAGER_STEP
	refresh()
	changed.emit()


## Syncs the slider (the balance and the odds can change) and the summary line.
func refresh() -> void:
	if _slider == null:
		return
	var coins := SaveManager.coins()
	var top := max_stake()
	GameSession.wager = clampi(GameSession.wager, 0, top) / ShopSystem.WAGER_STEP * ShopSystem.WAGER_STEP  # balance dropped / old value off the grid
	_slider.editable = top > 0
	_slider.set_value_no_signal(GameSession.wager)  # no signal: refresh must not re-enter _on_pick while dragging
	_minus.disabled = GameSession.wager <= 0
	_plus.disabled = GameSession.wager >= top
	_value.text = "None" if GameSession.wager == 0 else str(GameSession.wager)
	_balance.text = "You have %d coins" % coins
	if _series_info != null:
		_series_info.text = ShopSystem.series_desc(GameSession.battle_series)
	var stake := GameSession.wager
	if stake <= 0:
		_info.text = "No wager. Pick a stake to bet Aether Coins: win it back with a bonus, lose it if you lose."
	else:
		var o := odds()
		var tail := ""
		if kind == "battle_chess":
			match GameSession.battle_series:
				"ten":
					tail = "  Win = more rounds won than lost. Draw (equal): stake returned. Quitting early forfeits it."
				"survival":
					tail = "  Win = clear %d rounds before your first defeat." % ShopSystem.SERIES_SURVIVAL_TARGET
				_:
					tail = "  Draw: stake returned."
		_info.text = "Stake %d paid at the start.  Win: +%d coins back (x%s).  Lose: the stake is gone.%s" % [
			stake, ShopSystem.wager_payout(stake, o), _fmt(o), tail]


static func _fmt(o: float) -> String:
	return str(snappedf(o, 0.01))
