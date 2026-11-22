class_name AIController
extends RefCounted
## Rule-based AI for the Territory Board. One call to step() performs ONE action
## (the UI calls it on a timer so the player can follow what the AI does).
## Difficulty: easy / normal / hard.


static func step(c: MatchController) -> void:
	if c.state == MatchController.State.GAME_OVER:
		return
	var p: PlayerState = c.current_player()
	match c.state:
		MatchController.State.AWAIT_ROLL:
			if not _use_special_die(c, p):
				c.roll_dice()
		MatchController.State.ROLLED:
			if _should_reroll(c, p):
				c.reroll()
			else:
				c.confirm_move()
		MatchController.State.AWAIT_DECISION:
			_decide(c, c.decision_actor())
		MatchController.State.AWAIT_DUEL:
			c.auto_duel()  # AI-vs-AI duels run instantly; a human duel is fought in the Battle scene
		MatchController.State.TURN_DONE:
			c.end_turn()


static func _should_reroll(c: MatchController, p: PlayerState) -> bool:
	if p.reroll_tokens <= 0 or p.difficulty == "easy":
		return false
	var target: BoardTile = c.tiles[posmod(p.position + c.last_dice.x + c.last_dice.y, BoardBuilder.TILES_TOTAL)]
	if target.type == BoardTile.Type.CORNER and target.corner_kind == "rift":
		return true
	if target.type == BoardTile.Type.TERRITORY and target.owner_id >= 0 and target.owner_id != p.id:
		var limit := 0.5 if p.difficulty == "normal" else 0.3
		return float(EconomySystem.rent_of(target, c.tiles)) > float(p.gold) * limit
	return false


static func _decide(c: MatchController, p: PlayerState) -> void:
	var pend: Dictionary = c.pending
	match String(pend.get("type", "")):
		"buy":
			var t: BoardTile = c.tiles[int(pend["tile"])]
			c.decide("buy" if _wants_to_buy(c, p, t, int(pend["price"])) else "skip")
		"auction":
			c.decide(_auction_choice(c, p))
		"portal":
			c.decide(_choose_portal(c, p, pend["options"]))
		"shop":
			c.decide(_shop_choice(c, p))
		"encounter":
			c.decide(_owner_choice(c, p))
		"duel_response":
			c.decide(_visitor_choice(c, p))
		"conquest":
			# Short of gold -> take the Victory Reward; otherwise take the land.
			c.decide("reward" if p.gold < 150 and int(c.pending["reward"]) >= 60 else "conquest")
		_:
			c.decide("skip")


static func _wants_to_buy(c: MatchController, p: PlayerState, t: BoardTile, price: int) -> bool:
	if p.gold < price:
		return false
	var reserve := 200
	match p.difficulty:
		"easy":
			if c.rng.randf() < 0.35:
				return false
			reserve = 100
		"hard":
			reserve = 250
	if p.difficulty != "easy":
		# Regional priority: push for majority, and block rivals who are close to one.
		if EconomySystem.region_count(c.tiles, t.region, p.id) >= 3:
			reserve -= 120
		var rival_max := 0
		for o in c.players:
			if o.id != p.id:
				rival_max = maxi(rival_max, EconomySystem.region_count(c.tiles, t.region, o.id))
		if rival_max >= 5:
			reserve -= 80
	reserve = maxi(reserve, 30)
	return p.gold - price >= reserve


static func _choose_portal(c: MatchController, p: PlayerState, options: Array) -> int:
	if p.difficulty == "easy":
		if c.rng.randf() < 0.5:
			return -1
		return int(options[c.rng.randi() % options.size()])
	var best := -1
	var best_score := _landing_score(c, p, p.position)
	for idx in options:
		var s := _landing_score(c, p, int(idx))
		if s > best_score:
			best_score = s
			best = int(idx)
	return best


## Expected value of the next dice roll when standing on tile `from`.
static func _landing_score(c: MatchController, p: PlayerState, from: int) -> float:
	var weights: Array[int] = [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1]  # sums 2..12
	var total := 0.0
	for i in range(weights.size()):
		var t: BoardTile = c.tiles[posmod(from + 2 + i, BoardBuilder.TILES_TOTAL)]
		total += float(weights[i]) * _tile_value(c, p, t)
	return total / 36.0


static func _tile_value(c: MatchController, p: PlayerState, t: BoardTile) -> float:
	match t.type:
		BoardTile.Type.TERRITORY:
			if t.owner_id == -1:
				return float(t.price) * 0.4 if p.gold > t.price + 150 else 0.0
			if t.owner_id != p.id:
				return -float(EconomySystem.rent_of(t, c.tiles))
		BoardTile.Type.TAX:
			return -float(GameData.b("tax_flat"))
		BoardTile.Type.CORNER:
			if t.corner_kind == "rift":
				return -100.0
		BoardTile.Type.EVENT, BoardTile.Type.SHOP:
			return 5.0
	return 0.0


static func _shop_choice(c: MatchController, p: PlayerState) -> String:
	var heal_price := c.heal_price_for(p)
	var reroll_price := c.token_price_for(p)
	if p.life < int(GameData.b("start_life")) and p.gold >= heal_price + 150:
		return "heal"
	if p.difficulty != "easy" and p.special_dice.is_empty() and p.gold >= c.special_die_price() + 500:
		return "special"
	if p.difficulty != "easy" and p.reroll_tokens < 2 and p.gold >= reroll_price + 400:
		return "reroll"
	return "leave"


## Owner of the land: Tax or Duel?
static func _owner_choice(c: MatchController, owner_p: PlayerState) -> String:
	var visitor := c.current_player()
	if c.tutorial and int(c.stats["duels_offered"]) == 0:
		return "duel"  # tutorial: let the player experience a duel
	if owner_p.difficulty == "easy":
		return "duel" if c.rng.randf() < 0.3 else "tax"
	var po := BattleAI.army_power(owner_p)
	var pv := BattleAI.army_power(visitor)
	if po >= pv * float(GameData.b("ai_owner_duel_ratio")):
		return "duel"
	if visitor.life <= 1 and po >= pv * 0.8:
		return "duel"  # a loss would eliminate the visitor
	return "tax"


## Visitor challenged to a duel: accept or refuse (pay rent + penalty)?
static func _visitor_choice(c: MatchController, visitor: PlayerState) -> String:
	var owner_p: PlayerState = c.players[int(c.pending["owner"])]
	if visitor.difficulty == "easy":
		return "accept" if c.rng.randf() < 0.5 else "refuse"
	if visitor.life <= 1:
		return "refuse" if BattleAI.army_power(visitor) < BattleAI.army_power(owner_p) * 1.2 else "accept"
	return "accept" if BattleAI.army_power(visitor) >= BattleAI.army_power(owner_p) * float(GameData.b("ai_visitor_accept_ratio")) else "refuse"


## AI auction bid: values the lot by its price, the region it would complete and the difficulty.
static func _auction_choice(c: MatchController, p: PlayerState) -> String:
	var t: BoardTile = c.tiles[int(c.pending["tile"])]
	var next_bid := c.auction_next_bid()
	if p.gold < next_bid:
		return "pass"
	var mine := EconomySystem.region_count(c.tiles, t.region, p.id)
	var rival := 0
	for o in c.players:
		if o.id != p.id:
			rival = maxi(rival, EconomySystem.region_count(c.tiles, t.region, o.id))
	var value := float(t.price) * (0.85 + 0.12 * float(mine) + (0.15 if rival >= 5 else 0.0))
	var reserve := 150
	match p.difficulty:
		"easy":
			value *= 0.8
			reserve = 100
		"hard":
			value *= 1.1
			reserve = 200
	if mine >= 3:
		reserve -= 80
	return "bid" if float(next_bid) <= value and p.gold - next_bid >= reserve else "pass"


## Uses a Special Die when it helps. Returns true if one was used.
static func _use_special_die(c: MatchController, p: PlayerState) -> bool:
	for i in range(p.special_dice.size()):
		var id := p.special_dice[i]
		if id == "warp" and p.gold < 300:
			continue  # keep the Warp Die until there is gold to buy land
		return c.use_special_die(i) == ""
	return false
