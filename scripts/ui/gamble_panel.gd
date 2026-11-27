extends HBoxContainer
## Gamble panel: quick mini games (Coin Flip, Dice, Slots) with a drawn coin / dice / reels stage.
## Used by the Shop > Gamble tab (bets and winnings in Chips, the default) and by the Territory Casino (Dominion Gold).
## The panel only asks `play_fn` for a round and plays the result back; the money is moved by whoever owns the currency.
## Config keys (all optional): "unit" (name shown after amounts), "bets" (Array of ints: fixed stakes; without it the Shop slider runs GAMBLE_MIN..GAMBLE_MAX), "balance" (Callable -> int),
## "compact" (bool: simple floating card), "games" (Array of game ids that can be picked), "play" (Callable(game, choice, bet) -> round dictionary of ShopSystem.gamble), "hint" (text), "title" (header text).

const GambleStage := preload("res://scripts/ui/gamble_stage.gd")
const BetSlider := preload("res://scripts/ui/bet_slider.gd")

signal changed
signal round_done(result: Dictionary)

var rng: RandomNumberGenerator
var game: String = "coin"
var games: Array = []  # games that can be picked (all of them in the Shop, the one drawn in the Casino)
var choice: String = "heads"
var bet: int = 100
var game_row: HBoxContainer
var choice_row: HFlowContainer
var bet_slider: Control  # BetSlider: slide to set the stake
var rules: Label
var play_btn: Button
var stage: PanelContainer
var headline: Label
var detail: Label
var net_label: Label
var busy := false
var locked := false  # true = no more rounds (the Casino allows one round per visit)
var unit: String = "chips"  # currency name shown after amounts
var bets: Array = []
var _balance_fn: Callable
var _play_fn: Callable
var _hint: String = ""
var _title: String = "GAMBLE"
var gfx: Control  # GambleStage: the drawn coin / dice / reels
var compact := false  # true = the small floating card of the Territory Casino (one column, no side panel)
var footer: VBoxContainer  # compact only: the owner adds its own buttons here (e.g. Leave)
var bal_label: Label  # compact only: current balance
var _scroll: ScrollContainer  # compact only: the card content scrolls when the screen is too short to show it all
var _box: VBoxContainer  # compact only: the content of the card

const GAME_NAMES := {"coin": "Coin Flip", "dice": "Dice", "slots": "Slots"}
const CHOICES := {
	"coin": [["heads", "Heads"], ["tails", "Tails"]],
	"dice": [["low", "Low 2-6"], ["seven", "Seven"], ["high", "High 8-12"]],
	"slots": [],
}

func _init(r: RandomNumberGenerator, cfg: Dictionary = {}) -> void:
	rng = r
	unit = String(cfg.get("unit", "chips"))
	games = cfg.get("games", ShopSystem.GAMBLE_GAMES)
	game = String(games[0])
	bets = cfg.get("bets", [])  # empty = free slider range (Shop), otherwise only these stakes (Casino)
	bet = int(bets[0]) if not bets.is_empty() else ShopSystem.GAMBLE_BETS[0]
	_balance_fn = cfg.get("balance", func() -> int: return SaveManager.chips())
	_play_fn = cfg.get("play", func(g: String, c: String, b: int) -> Dictionary: return ShopSystem.gamble(g, c, b, rng))
	_hint = String(cfg.get("hint", "Fast money, real risk. Bets and winnings are Chips only: get Chips in the Exchange tab and turn winnings back into coins there."))
	_title = String(cfg.get("title", "GAMBLE"))
	compact = bool(cfg.get("compact", false))
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	if compact:
		_build_compact()
	else:
		_build()

func _build() -> void:
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	add_child(left)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", 10)
	left.add_child(lbox)
	var scr := UiTheme.make_scroll()  # short screens scroll the settings; the Play button below stays in view
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbox.add_child(scr)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	scr.add_child(inner)
	inner.add_child(UiTheme.make_label(_title, 26, UiTheme.COL_GOLD))
	var hint := UiTheme.make_label(_hint, 15, UiTheme.COL_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(hint)
	inner.add_child(UiTheme.make_label("Game", 16, UiTheme.COL_MUTED))
	game_row = HBoxContainer.new()
	game_row.add_theme_constant_override("separation", 6)
	inner.add_child(game_row)
	var gg := ButtonGroup.new()
	for g in games:
		var b := UiTheme.make_toggle(String(GAME_NAMES[g]), gg, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = (g == game)
		b.pressed.connect(_pick_game.bind(String(g)))
		game_row.add_child(b)
	rules = UiTheme.make_label("", 15, UiTheme.COL_MUTED)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(rules)
	lbox.add_child(UiTheme.make_label("Your pick", 16, UiTheme.COL_MUTED))  # pick, stake and Play stay pinned below the scroll
	choice_row = HFlowContainer.new()
	choice_row.add_theme_constant_override("h_separation", 6)
	lbox.add_child(choice_row)
	lbox.add_child(UiTheme.make_label("Bet (%s)" % unit, 16, UiTheme.COL_MUTED))
	bet_slider = _make_bet_slider(34)
	lbox.add_child(bet_slider)
	play_btn = UiTheme.make_primary("Play", 72)
	play_btn.pressed.connect(_on_play)
	lbox.add_child(play_btn)

	stage = PanelContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_stage_color(UiTheme.COL_GOLD_DIM)
	add_child(stage)
	var sbox := VBoxContainer.new()
	sbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sbox.add_theme_constant_override("separation", 14)
	stage.add_child(sbox)
	headline = UiTheme.make_label("Place your bet", 40, UiTheme.COL_GOLD)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sbox.add_child(headline)
	gfx = GambleStage.new()
	gfx.sound.connect(func(n: String): Sfx.play(n))
	sbox.add_child(gfx)
	detail = UiTheme.make_label("", 22, UiTheme.COL_TEXT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sbox.add_child(detail)
	net_label = UiTheme.make_label("", 28, UiTheme.COL_MUTED)
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sbox.add_child(net_label)
	_pick_game(game)

## Simple floating card (Territory Casino): title + balance, the drawn game, result, pick, bet, Play. Nothing else.
func _build_compact() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stage = PanelContainer.new()
	stage.custom_minimum_size = Vector2(440, 0)
	stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_set_stage_color(UiTheme.COL_GOLD_DIM)
	add_child(stage)
	var m := UiTheme.make_margin(14)
	stage.add_child(m)
	_scroll = ScrollContainer.new()  # safety net: a short screen scrolls the card instead of cutting it off
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	m.add_child(_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	_scroll.add_child(box)
	_box = box
	# header: CASINO - Game ........ 1200 G
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := UiTheme.make_label("%s  -  %s" % [_title, String(GAME_NAMES[game])], 22, UiTheme.COL_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	bal_label = UiTheme.make_label("", 20, UiTheme.COL_TEXT)
	head.add_child(bal_label)
	# the drawn coin / dice / reels
	gfx = GambleStage.new()
	gfx.custom_minimum_size = Vector2(0, 120)
	gfx.sound.connect(func(n: String): Sfx.play(n))
	box.add_child(gfx)
	# result (one short block)
	headline = UiTheme.make_label("Place your bet", 28, UiTheme.COL_GOLD)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(headline)
	detail = UiTheme.make_label("", 18, UiTheme.COL_TEXT)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	net_label = UiTheme.make_label("", 22, UiTheme.COL_MUTED)
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(net_label)
	rules = UiTheme.make_label("", 13, UiTheme.COL_MUTED)
	rules.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(rules)
	# pick (hidden for Slots) and bet
	choice_row = HFlowContainer.new()
	choice_row.alignment = FlowContainer.ALIGNMENT_CENTER
	choice_row.add_theme_constant_override("h_separation", 6)
	box.add_child(choice_row)
	bet_slider = _make_bet_slider(26)
	box.add_child(bet_slider)
	game_row = HBoxContainer.new()  # kept so _set_busy works; the Casino has one game, so it is never shown
	game_row.visible = false
	box.add_child(game_row)
	play_btn = UiTheme.make_primary("Play", 48)
	play_btn.pressed.connect(_on_play)
	box.add_child(play_btn)
	footer = VBoxContainer.new()
	box.add_child(footer)
	_pick_game(game)
	tree_entered.connect(_fit_compact.call_deferred)
	resized.connect(_fit_compact.call_deferred)


## Compact card: the scroll area is as tall as its content, but never taller than the screen, so the card always fits
## (the Leave / Continue button stays reachable by scrolling on very short screens).
func _fit_compact() -> void:
	if _scroll == null or _box == null or not is_inside_tree():
		return
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_compact):
		vp.size_changed.connect(_fit_compact)
	var max_h := get_viewport_rect().size.y * 0.9 - 56.0  # card margins + stage border + a little air
	_scroll.custom_minimum_size.y = minf(_box.get_combined_minimum_size().y, maxf(max_h, 160.0))


## The stake slider. Shop: free range in Chips; Casino: only the fixed bets of the board (slider snaps between them).
func _make_bet_slider(font: int) -> Control:
	var cfg := {"unit": unit, "balance": _balance_fn, "start": bet, "font": font, "presets": not compact}
	if bets.is_empty():
		cfg["min"] = ShopSystem.GAMBLE_MIN
		cfg["max"] = ShopSystem.GAMBLE_MAX
		cfg["step"] = ShopSystem.GAMBLE_STEP
	else:
		cfg["values"] = bets
	var bs: Control = BetSlider.new(cfg)
	bet = bs.value
	bs.value_changed.connect(func(v: int):
		bet = v
		refresh())
	return bs


func _set_stage_color(c: Color) -> void:
	stage.add_theme_stylebox_override("panel", UiTheme.make_box(Color(c.darkened(0.8), 0.97), c, 2, 18, 18 if compact else 0))

func _pick_game(g: String) -> void:
	game = g
	var opts: Array = CHOICES[g]
	choice = String(opts[0][0]) if not opts.is_empty() else ""
	for c in choice_row.get_children():
		choice_row.remove_child(c)
		c.queue_free()
	var cg := ButtonGroup.new()
	for o in opts:
		var cb := UiTheme.make_toggle(String(o[1]), cg, 46)
		cb.custom_minimum_size.x = 110
		cb.button_pressed = (String(o[0]) == choice)
		cb.pressed.connect(func(): choice = String(o[0]))
		choice_row.add_child(cb)
	match g:
		"coin":
			rules.text = "Heads or tails. Win and you get double your bet (48% chance)."
		"dice":
			rules.text = "Two dice. Low (2-6) or High (8-12) pays x%.1f, exactly Seven pays x%.1f." % [ShopSystem.DICE_PAYOUT["low"], ShopSystem.DICE_PAYOUT["seven"]]
		"slots":
			rules.text = "Three reels. Three 7s pay x%d, any other three alike x%d, two alike x%.1f." % [int(ShopSystem.SLOT_JACKPOT), int(ShopSystem.SLOT_TRIPLE), ShopSystem.SLOT_PAIR]
	choice_row.visible = not opts.is_empty()
	gfx.set_idle(g)
	headline.text = "Place your bet"
	headline.add_theme_color_override("font_color", UiTheme.COL_GOLD)
	detail.text = ""
	net_label.text = ""
	_set_stage_color(UiTheme.COL_GOLD_DIM)
	refresh()

## Locks / unlocks the pickers while an animation plays.
func _set_busy(b: bool) -> void:
	busy = b
	bet_slider.set_locked(b or locked)
	for row in [game_row, choice_row]:
		for c in row.get_children():
			(c as Button).disabled = b or locked
	if b:
		play_btn.disabled = true
	else:
		refresh()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

## Suspense before the result: the graphic stage flips the coin, tumbles the dice or spins the reels. The outcome is already
## decided (ShopSystem.gamble); this only plays it back. Lite effects mode skips it.
func _animate(r: Dictionary) -> void:
	headline.text = {"coin": "Flipping...", "dice": "Rolling...", "slots": "Spinning..."}[game]
	headline.add_theme_color_override("font_color", UiTheme.COL_MUTED)
	net_label.text = ""
	detail.text = ""
	_set_stage_color(UiTheme.COL_GOLD_DIM)
	if game == "dice":
		Sfx.play("dice")
	await gfx.play(game, r["detail"])

## Pop for a win (bigger for a jackpot), shake for a loss.
func _celebrate(net: int, jackpot: bool) -> void:
	headline.pivot_offset = headline.size * 0.5
	var tw := create_tween()
	if net > 0:
		headline.scale = Vector2(0.6, 0.6)
		tw.tween_property(headline, "scale", Vector2(1.25 if jackpot else 1.12, 1.25 if jackpot else 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(headline, "scale", Vector2.ONE, 0.15)
		if jackpot:
			var fl := create_tween()
			fl.tween_property(stage, "modulate", Color(1.6, 1.5, 1.0), 0.12)
			fl.tween_property(stage, "modulate", Color.WHITE, 0.35)
	elif net < 0:
		for dx in [10.0, -10.0, 6.0, -6.0, 0.0]:
			tw.tween_property(headline, "position:x", dx, 0.04).as_relative()
		tw.tween_callback(func(): headline.scale = Vector2.ONE)

func _on_play() -> void:
	if busy:
		return
	var r: Dictionary = _play_fn.call(game, choice, bet)
	if not bool(r["ok"]):
		Sfx.play("error")
		headline.text = String(r["error"])
		headline.add_theme_color_override("font_color", UiTheme.COL_DANGER)
		return
	_set_busy(true)
	if not FxMode.is_lite():
		await _animate(r)
		if not is_inside_tree():
			return
	var d: Dictionary = r["detail"]
	match game:
		"coin":
			detail.text = "It landed on %s" % String(d["landed"]).to_upper()
		"dice":
			detail.text = "%d + %d = %d  (%s)" % [int(d["dice"][0]), int(d["dice"][1]), int(d["total"]), String(d["outcome"]).to_upper()]
		"slots":
			detail.text = "[ %s ]" % "  |  ".join(d["symbols"])
	var net := int(r["net"])
	var col: Color
	if net > 0:
		col = Color("59cd90")
		headline.text = "JACKPOT!" if String(d.get("kind", "")) == "jackpot" else "YOU WIN!"
		Sfx.play("victory" if String(d.get("kind", "")) == "jackpot" else "coin")
	elif net == 0:
		col = UiTheme.COL_GOLD
		headline.text = "PUSH"
	else:
		col = UiTheme.COL_DANGER
		headline.text = "YOU LOSE"
		Sfx.play("error")
	headline.add_theme_color_override("font_color", col)
	net_label.text = "%s%d %s" % ["+" if net > 0 else "", net, unit]
	net_label.add_theme_color_override("font_color", col)
	_set_stage_color(col)
	for l in [headline, detail, net_label]:
		if FxMode.is_lite():
			l.modulate.a = 1.0
			continue
		l.modulate.a = 0.0
		l.create_tween().tween_property(l, "modulate:a", 1.0, 0.25)
	if not FxMode.is_lite():
		_celebrate(net, String(d.get("kind", "")) == "jackpot")
		gfx.celebrate(net > 0, String(d.get("kind", "")) == "jackpot")
	if compact:
		_fit_compact.call_deferred()  # the result lines changed the content height
	_set_busy(false)
	round_done.emit(r)
	changed.emit()

## Ends the panel for good: nothing can be picked or played any more (the result stays on the stage).
func lock() -> void:
	locked = true
	_set_busy(busy)


func refresh() -> void:
	if compact:
		_fit_compact.call_deferred()
	if bet_slider != null and bet_slider.value != bet:
		bet_slider.set_value(bet)  # bet was set from outside (tests, balance change): the handle follows
	elif bet_slider != null:
		bet_slider.refresh()
	if bet_slider != null:
		bet = bet_slider.value
	play_btn.text = "Play  (%d %s)" % [bet, unit]
	if bal_label != null:
		bal_label.text = "%d %s" % [int(_balance_fn.call()), unit]
	play_btn.disabled = locked or int(_balance_fn.call()) < bet
