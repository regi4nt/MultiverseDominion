class_name WagerPanel
extends VBoxContainer
## Wager picker for Arena and Battle Chess: choose a stake of Aether Coins before the match.
## The stake is paid when the match starts; a win pays stake x odds (the stake included), a loss loses it,
## Battle Chess returns it on a draw. Odds depend on the mode and the difficulty (ShopSystem.wager_odds).
## Writes GameSession.wager; the host reads `odds()` when it starts the match.

signal changed

var kind: String = "arena"  # "arena" | "battle_chess"
var with_difficulty: bool = false  # Battle Chess has no setup screen: the panel shows the difficulty too

var _chips: HFlowContainer
var _info: Label
var _balance: Label


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
	var head := HBoxContainer.new()
	add_child(head)
	var title := UiTheme.make_label("Wager", 20, UiTheme.COL_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_balance = UiTheme.make_label("", 16, UiTheme.COL_GOLD)
	head.add_child(_balance)
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 6)
	_chips.add_theme_constant_override("v_separation", 6)
	add_child(_chips)
	_info = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	refresh()


func odds() -> float:
	return ShopSystem.wager_odds(kind, GameSession.mode, GameSession.ai_count, GameSession.difficulty)


func _on_pick(amount: int) -> void:
	GameSession.wager = amount
	refresh()
	changed.emit()


## Rebuilds the chips (the balance and the odds can change) and the summary line.
func refresh() -> void:
	if _chips == null:
		return
	var coins := SaveManager.coins()
	if GameSession.wager > coins:
		GameSession.wager = 0
	for c in _chips.get_children():
		_chips.remove_child(c)
		c.queue_free()
	var group := ButtonGroup.new()
	var steps: Array = [0] + ShopSystem.WAGER_STEPS
	for amount in steps:
		var b := UiTheme.make_toggle("None" if amount == 0 else str(amount), group, 48)
		b.custom_minimum_size.x = 84
		b.button_pressed = (GameSession.wager == amount)
		b.disabled = amount > coins
		b.pressed.connect(_on_pick.bind(int(amount)))
		UiTheme.scroll_passthrough(b)
		_chips.add_child(b)
	_balance.text = "You have %d coins" % coins
	var stake := GameSession.wager
	if stake <= 0:
		_info.text = "No wager. Pick a stake to bet Aether Coins: win it back with a bonus, lose it if you lose."
	else:
		var o := odds()
		_info.text = "Stake %d paid at the start.  Win: +%d coins back (x%s).  Lose: the stake is gone.%s" % [
			stake, ShopSystem.wager_payout(stake, o), _fmt(o), "  Draw: stake returned." if kind == "battle_chess" else ""]


static func _fmt(o: float) -> String:
	return str(snappedf(o, 0.01))
