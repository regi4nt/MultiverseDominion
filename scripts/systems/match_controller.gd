class_name MatchController
extends RefCounted
## Pure game logic of the Territory Board (no UI). The UI and the AI both drive it through
## the same public API:  roll_dice / reroll / confirm_move / decide / end_turn.
##
## Turn state machine:
##   AWAIT_ROLL -> ROLLED -> (AWAIT_DECISION)* -> TURN_DONE -> next player / bonus roll
##
## Territory Encounter (Phase 5): the owner chooses Tax or Duel; the visitor may accept or refuse
## (refusing = rent + configurable penalty). A duel is an 8x8 auto battle between the persistent armies.
## Attacker wins -> Conquest (take the land) or Victory Reward (gold). Owner wins (or draw) -> the
## attacker loses 1 Life. Life 0 = eliminated. Last player standing wins.

signal log_added(text: String)
signal state_changed()
signal dice_rolled(d1: int, d2: int)
signal player_moved(player_id: int, from_index: int, to_index: int, warped: bool)
signal tiles_changed()
signal players_changed()
signal game_over(winner_id: int)
signal monster_event(player_id: int, result: String, monster_id: String)  # result: "won" | "lost" | "fled"
signal deposit_event(player_id: int, kind: String, deposit_id: String)  # kind: "treasure" | "mine" (a hidden deposit was found)

const SAVE_FORMAT := 1

enum State { AWAIT_ROLL, ROLLED, AWAIT_DECISION, AWAIT_DUEL, TURN_DONE, GAME_OVER }

const PLAYER_COLORS: Array[Color] = [Color("3fa7d6"), Color("e5533d"), Color("59cd90"), Color("b266ff")]

var rng := RandomNumberGenerator.new()
var continent: Dictionary = {}
var tiles: Array[BoardTile] = []
var players: Array[PlayerState] = []
var current: int = 0
var round_number: int = 1
var state: State = State.AWAIT_ROLL
var pending: Dictionary = {}
var last_dice: Vector2i = Vector2i.ZERO
var winner_id: int = -1
var human_present: bool = true
var team_mode: bool = false  # 2vs2: seats 0 + 2 (Team A) against seats 1 + 3 (Team B)
var winner_team: int = -1
var wager: int = 0  # Arena wager: the stake was paid at the start; a human win pays stake x wager_odds (see SaveManager.settle_wager)
var wager_odds: float = 2.0
## Arena "Random map": the continent was drawn, so the human also gets its in-game bonus (data/continents.json random_bonus.ingame).
var random_map: bool = false
var wager_settled: bool = false
var journey: bool = false  # Journey match: a human win unlocks the next continent (Arena matches unlock nothing)
var tutorial: bool = false  # guided first match: contextual hints, scripted start, forced first duel
var round_limit: int = 30
var tutorial_seen: Array[String] = []
var recent_log: Array[String] = []  # last lines, shown again after resuming a saved match
## Counters (used by tests and the result screen).
var stats: Dictionary = {"tax": 0, "duels_offered": 0, "refused": 0, "duels": 0,
	"attacker_wins": 0, "defender_wins": 0, "conquests": 0, "rewards": 0, "bankrupt": 0, "heals": 0,
	"auctions": 0, "special_dice": 0, "upgrades": 0, "bank_deposits": 0, "bets": 0, "jackpots": 0,
	"monster_fights": 0, "monsters_won": 0, "treasures_found": 0, "mines_found": 0, "mine_income": 0}
## Stock market of the Bank tiles: last round's change of every portfolio (fraction, e.g. 0.12 = +12%).
var market_change: float = 0.0
## Hidden territory monsters (see MonsterSystem): [{"tile", "id", "taken"}]. Never shown on the map.
var monsters: Array = []
## Hidden territory treasures and mines (see DepositSystem): [{"tile", "id", "taken", "owner", "left", "paid"}]. Never shown on the map.
var deposits: Array = []
## Casino pot: grows with every bet placed, paid out (and reset) on a jackpot.
var casino_pot: int = 0

var _roll_was_double: bool = false
var _extra_roll: bool = false
var _bonus_rolls: int = 0
var _chain_depth: int = 0


# ------------------------------------------------------------------ setup

## cfg keys: continent_id, faction_id, difficulty, ai_count, seed, player_name, all_ai
func setup(cfg: Dictionary) -> void:
	if int(cfg.get("seed", 0)) != 0:
		rng.seed = int(cfg["seed"])
	else:
		rng.randomize()
	continent = GameData.get_continent(String(cfg.get("continent_id", "aetherion")))
	CardDatabase.set_continent(String(continent["id"]))
	WorldMods.apply(continent)
	GameData.apply_flavor(String(continent["id"]))  # themed event cards + Special Dice of this continent
	tiles = BoardBuilder.build(continent)
	PortalSystem.randomize_portals(tiles, rng)
	monsters = []
	if bool(cfg.get("monsters", true)) and not bool(cfg.get("tutorial", false)):  # the guided tutorial match has none
		monsters = MonsterSystem.place(tiles, String(continent["id"]), rng)
	deposits = []
	if bool(cfg.get("deposits", true)) and not bool(cfg.get("tutorial", false)):  # the guided tutorial match has none
		# Own generator derived from the match seed: the main rng stream (and so every other seeded behaviour) is untouched.
		var drng := RandomNumberGenerator.new()
		drng.seed = hash("deposits:" + str(rng.seed))
		deposits = DepositSystem.place(tiles, String(continent["id"]), drng, monsters.map(func(e): return int(e["tile"])))
	casino_pot = int(GameData.b("casino_pot_seed"))
	market_change = 0.0

	players.clear()
	human_present = not bool(cfg.get("all_ai", false))
	team_mode = bool(cfg.get("team_mode", false))
	journey = bool(cfg.get("journey", false))
	wager = maxi(int(cfg.get("wager", 0)), 0)
	wager_odds = float(cfg.get("wager_odds", 2.0))
	random_map = bool(cfg.get("random_map", false))
	var difficulty: String = cfg.get("difficulty", "normal")
	var faction_ids: Array = []
	for f in continent.get("factions", []):
		faction_ids.append(f["id"])
	var human_faction: String = cfg.get("faction_id", faction_ids[0])  # from the Deck: may belong to another continent
	if GameData.find_faction(human_faction).get("champion", "") == "":
		human_faction = faction_ids[0]
	var pool: Array = faction_ids.duplicate()
	pool.erase(human_faction)
	_shuffle(pool)
	var order: Array = [human_faction]
	order.append_array(pool)
	var ai_count: int = clampi(int(cfg.get("ai_count", 3)), 1, 3)
	if team_mode:
		ai_count = 3  # 2vs2 always seats four rulers

	for i in range(ai_count + 1):
		var is_ai := (i > 0) or not human_present
		var fac := GameData.get_faction(continent["id"], order[i])
		var tag := "AI"
		if team_mode and i == 2:
			tag = "Ally"  # seat 2 is the human's teammate
		var pname: String = String(cfg.get("player_name", "You")) if not is_ai else "%s (%s)" % [fac.get("name", "AI"), tag]
		var diffs: Array = cfg.get("difficulties", [])  # optional per-seat difficulty (balance tests)
		var seat_diff: String = String(diffs[i]) if i < diffs.size() else difficulty
		players.append(_make_player(i, order[i], is_ai, seat_diff, pname))
		if team_mode:
			players[i].team = i % 2  # turn order alternates: A, B, A, B

	current = 0
	round_number = 1
	state = State.AWAIT_ROLL
	pending = {}
	winner_id = -1
	winner_team = -1
	round_limit = int(cfg.get("round_limit", int(GameData.b("max_rounds"))))
	tutorial = bool(cfg.get("tutorial", false))
	if tutorial:
		# Scripted start: the AI already owns land right in front of the player, so the first
		# Territory Encounter (and the first duel) happens within a few turns.
		for i in [2, 4, 6, 8]:
			if tiles[i].type == BoardTile.Type.TERRITORY:
				tiles[i].owner_id = 1
	_log("Match start on %s. %d players. Good luck!" % [continent.get("name", "?"), players.size()])
	if team_mode:
		_log("2vs2: Team A (%s) against Team B (%s). Allies pay no rent to each other." % [_team_names(0), _team_names(1)])
	_apply_random_map(true)
	if WorldMods.modifier_name != "":
		_log("World modifier - %s: %s" % [WorldMods.modifier_name, continent["modifier"].get("description", "")])


## In-game bonus of the random map, for the human seat only (never the AI).
func random_ingame() -> Dictionary:
	if not random_map:
		return {}
	return ShopSystem.random_bonus(String(continent["id"])).get("ingame", {})


func _is_human(p: PlayerState) -> bool:
	return human_present and not p.is_ai


## `fresh` = a new match (one-time gifts like start tokens); a loaded match only re-applies the standing effects.
func _apply_random_map(fresh: bool) -> void:
	var b := random_ingame()
	if b.is_empty():
		return
	for p in players:
		if not _is_human(p):
			continue
		p.extra_price_mult = float(b.get("unit_price_mult", 1.0))
		if fresh and int(b.get("start_tokens", 0)) > 0:
			p.reroll_tokens += int(b["start_tokens"])
		if fresh:
			_log("Random map bonus - %s: %s" % [continent.get("name", "?"), ShopSystem.random_bonus(String(continent["id"])).get("ingame_text", "")])


func _make_player(id: int, faction_id: String, is_ai: bool, difficulty: String, pname: String) -> PlayerState:
	var p := PlayerState.new()
	p.id = id
	p.display_name = pname
	p.is_ai = is_ai
	p.difficulty = difficulty
	p.faction_id = faction_id
	var fac := GameData.get_faction(continent["id"], faction_id)
	if fac.is_empty():
		fac = GameData.find_faction(faction_id)
	p.champion_id = fac.get("champion", "")
	var champ := GameData.get_champion(p.champion_id)
	p.passive = champ.get("passive", "")
	p.passive_value = float(champ.get("passive_value", 0.0))
	p.color = PLAYER_COLORS[id % PLAYER_COLORS.size()]
	p.gold = int(GameData.b("start_gold"))
	p.life = int(GameData.b("start_life"))
	p.level = int(GameData.b("start_level"))
	p.capacity = p.level * int(GameData.b("capacity_per_level"))
	if p.has_passive("fortune_weave"):
		p.reroll_tokens = int(p.passive_value)
	_init_army(p)
	return p


## Persistent army: own deck, draw pile and a few starter pawns.
func _init_army(p: PlayerState) -> void:
	if p.is_ai or not human_present:
		p.deck = Deck.create_default()
	else:
		p.deck = SaveManager.get_deck(String(continent["id"]))  # the player's own unit loadout of this continent
	p.deck.champion_id = p.champion_id
	p.battle_deck = BattleDeck.new(p.deck, rng)
	p.roster = UnitRoster.new()
	var pawns: Array[String] = []  # starter units: Pawns of the deck (any unit type if the deck has no Pawn)
	var deck_ids := p.deck.effective_unit_ids()
	for id in deck_ids:
		if String(CardDatabase.get_unit(id).get("chess", "")) == "pawn":
			pawns.append(id)
	if pawns.is_empty():
		pawns = deck_ids
	for i in range(int(GameData.b("starter_units"))):
		var id := pawns[rng.randi() % pawns.size()]
		if p.battle_deck.take_card(id):
			p.roster.add_copy(id)
	if p.has_passive("vanguard"):  # extra rare units
		var rares: Array[String] = []
		for id in deck_ids:
			if String(CardDatabase.get_unit(id).get("rarity", "")) == "rare":
				rares.append(id)
		if rares.is_empty():
			rares = deck_ids
		for i in range(int(p.passive_value)):
			var rid := rares[rng.randi() % rares.size()]
			if p.battle_deck.take_card(rid):
				p.roster.add_copy(rid)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ------------------------------------------------------------------ queries

func current_player() -> PlayerState:
	return players[current]


func alive_players() -> Array[PlayerState]:
	var out: Array[PlayerState] = []
	for p in players:
		if p.alive:
			out.append(p)
	return out


## 2vs2: true when both seats are on the same team (never in a free-for-all, never for the same seat).
func is_ally(a_id: int, b_id: int) -> bool:
	if not team_mode or a_id < 0 or b_id < 0 or a_id == b_id:
		return false
	return players[a_id].team == players[b_id].team


## "A" / "B" in 2vs2, "" otherwise.
func team_label(p: PlayerState) -> String:
	if not team_mode or p.team < 0:
		return ""
	return "A" if p.team == 0 else "B"


func _team_names(team: int) -> String:
	var names: Array[String] = []
	for p in players:
		if p.team == team:
			names.append(p.display_name)
	return " + ".join(names)


## Combined net worth of the living members of a team.
func team_networth(team: int) -> int:
	var total := 0
	for p in players:
		if p.alive and p.team == team:
			total += networth(p)
	return total


## True when the human's side won (their team in 2vs2, themselves otherwise).
func human_won() -> bool:
	if not human_present or winner_id < 0:
		return false
	if team_mode:
		return players[winner_id].team == players[0].team
	return winner_id == 0


func count_owned(player_id: int) -> int:
	var n := 0
	for t in tiles:
		if t.owner_id == player_id and t.type == BoardTile.Type.TERRITORY:
			n += 1
	return n


func networth(p: PlayerState) -> int:
	return EconomySystem.networth(tiles, p)


func ranking() -> Array[PlayerState]:
	var list: Array[PlayerState] = players.duplicate()
	list.sort_custom(func(a: PlayerState, b: PlayerState) -> bool: return networth(a) > networth(b))
	return list


func get_decision_options() -> Array:
	var out: Array = []
	var p := current_player()
	match String(pending.get("type", "")):
		"buy":
			var t: BoardTile = tiles[int(pending["tile"])]
			var price := int(pending["price"])
			out.append({"id": "buy", "label": "Buy %s (%d G)" % [t.name, price], "enabled": p.gold >= price})
			out.append({"id": "skip", "label": "Skip", "enabled": true})
		"upgrade":
			var ut: BoardTile = tiles[int(pending["tile"])]
			var ucost := int(pending["price"])
			var nxt := ut.level + 1
			var what := "Landmark" if nxt >= int(GameData.b("max_tile_level")) else "Level %d" % nxt
			out.append({"id": "upgrade", "label": "Upgrade to %s (%d G)" % [what, ucost], "enabled": p.gold >= ucost})
			out.append({"id": "skip", "label": "Not now", "enabled": true})
		"auction":
			var bidder := players[int(pending["actor"])]
			var nb := auction_next_bid()
			out.append({"id": "bid", "label": "Bid %d G" % nb, "enabled": bidder.gold >= nb})
			out.append({"id": "pass", "label": "Pass", "enabled": true})
		"portal":
			for idx in pending["options"]:
				var t: BoardTile = tiles[int(idx)]
				out.append({"id": int(idx), "label": "Warp: %s" % t.name, "enabled": true})
			out.append({"id": -1, "label": "Stay here", "enabled": true})
		"shop":
			var heal_price := heal_price_for(p)
			var reroll_price := token_price_for(p)
			out.append({"id": "heal", "label": "Restore Life (%d G)" % heal_price,
				"enabled": p.life < int(GameData.b("start_life")) and p.gold >= heal_price})
			out.append({"id": "reroll", "label": "Reroll Token (%d G)" % reroll_price, "enabled": p.gold >= reroll_price})
			out.append({"id": "special", "label": "Special Die (%d G)" % special_die_price(), "enabled": p.gold >= special_die_price() and p.special_dice.size() < int(GameData.b("max_special_dice"))})
			out.append({"id": "leave", "label": "Leave shop", "enabled": true})
		"bank":
			for amt in GameData.b("bank_invest_options"):
				out.append({"id": "invest_%d" % int(amt), "label": "Invest %d G" % int(amt), "enabled": p.gold >= int(amt)})
			out.append({"id": "withdraw", "label": "Sell all stocks (%d G)" % p.stock_value, "enabled": p.stock_value > 0})
			out.append({"id": "leave", "label": "Leave bank", "enabled": true})
		"casino":
			var tp := casino_bet_price()
			out.append({"id": "bet", "label": "Place bet (%d G)" % tp, "enabled": p.gold >= tp})
			out.append({"id": "skip", "label": "Pass", "enabled": true})
		"monster":
			out.append({"id": "fight", "label": "Fight the monster", "enabled": true})
			out.append({"id": "flee", "label": "Flee", "enabled": true})
		"encounter":
			out.append({"id": "tax", "label": "Collect Tax (%d G)" % int(pending["rent"]), "enabled": true})
			out.append({"id": "duel", "label": "Challenge to Duel", "enabled": true})
		"duel_response":
			var penalty := int(GameData.b("refuse_duel_penalty"))
			out.append({"id": "accept", "label": "Accept Duel", "enabled": true})
			out.append({"id": "refuse", "label": "Refuse (pay %d G)" % (int(pending["rent"]) + penalty), "enabled": true})
		"conquest":
			out.append({"id": "conquest", "label": "Conquest: take %s" % tiles[int(pending["tile"])].name, "enabled": true})
			out.append({"id": "reward", "label": "Victory Reward (+%d G)" % int(pending["reward"]), "enabled": true})
	return out


func describe_tile(idx: int) -> String:
	var t: BoardTile = tiles[idx]
	var s := "#%d  %s  [%s]" % [idx, t.name, t.type_name()]
	match t.type:
		BoardTile.Type.TERRITORY:
			var region_name: String = continent["regions"][t.region]["name"] if continent.has("regions") else str(t.region)
			s += "\nRegion: %s | Price: %d G" % [region_name, t.price]
			if t.level > 0:
				s += " | %s" % t.level_label()
			if t.owner_id >= 0:
				s += " | Rent: %d G\nOwner: %s" % [EconomySystem.rent_of(t, tiles), players[t.owner_id].display_name]
			else:
				s += " | Rent if owned: ~%d G\nOwner: none" % int(round(t.price * float(GameData.b("rent_rate"))))
		BoardTile.Type.PORTAL:
			s += "\nPortal socket: %s" % ("ACTIVE - may warp you to another active portal" if t.portal_active else "dormant")
		BoardTile.Type.SHOP:
			s += "\nBuy Reroll Tokens or restore Life."
		BoardTile.Type.EVENT:
			s += "\nDraws a random event card."
		BoardTile.Type.AUCTION:
			s += "\nA random free territory is offered at a discount."
		BoardTile.Type.TAX:
			s += "\nPay %d G to the bank." % int(GameData.b("tax_flat"))
		BoardTile.Type.SPECIAL:
			s += "\nRandom special effect (gift, teleport or tribute)."
		BoardTile.Type.BANK:
			s += "\nBank & Stocks: invest gold in the market (it moves every round: %d%% to +%d%%), or cash out." % [
				int(round(float(GameData.b("stock_change_min")) * 100.0)), int(round(float(GameData.b("stock_change_max")) * 100.0))]
		BoardTile.Type.CASINO:
			s += "\nCasino: a bet costs %d G. Pot: %d G (small prize x%d, big prize x%d, or the whole pot)." % [
				casino_bet_price(), casino_pot, int(GameData.b("casino_small_mult")), int(GameData.b("casino_big_mult"))]
		BoardTile.Type.CORNER:
			s += "\n" + _corner_text(t.corner_kind)
	return s


func _corner_text(kind: String) -> String:
	match kind:
		"start": return "Pass or land: collect start bonus gold."
		"sanctuary": return "Rest: receive a small amount of gold."
		"rift": return "Trapped: skip your next turn."
		"crossroads": return "Free warp to a random active portal."
	return ""


# ------------------------------------------------------------------ turn API

func roll_dice() -> void:
	if state != State.AWAIT_ROLL:
		return
	last_dice = DiceSystem.roll(rng)
	state = State.ROLLED
	_log("%s rolled %d + %d = %d." % [current_player().display_name, last_dice.x, last_dice.y, last_dice.x + last_dice.y])
	dice_rolled.emit(last_dice.x, last_dice.y)
	state_changed.emit()


## Spend a Reroll Token to roll again before moving.
func reroll() -> void:
	var p := current_player()
	if state != State.ROLLED or p.reroll_tokens <= 0:
		return
	p.reroll_tokens -= 1
	last_dice = DiceSystem.roll(rng)
	_log("%s uses a Reroll Token: %d + %d = %d." % [p.display_name, last_dice.x, last_dice.y, last_dice.x + last_dice.y])
	dice_rolled.emit(last_dice.x, last_dice.y)
	players_changed.emit()
	state_changed.emit()


func confirm_move() -> void:
	if state != State.ROLLED:
		return
	var p := current_player()
	_roll_was_double = last_dice.x == last_dice.y
	_chain_depth = 0
	var steps := last_dice.x + last_dice.y + p.move_bonus
	p.move_bonus = 0
	_move_player(p, steps)
	_resolve_landing(p)
	_finish_landing()


## Answers the current pending decision. See get_decision_options().
func decide(choice: Variant) -> void:
	if state != State.AWAIT_DECISION:
		return
	var p := current_player()
	match String(pending.get("type", "")):
		"auction":
			_auction_answer(choice)
		"monster":
			_answer_monster(p, choice)
		"buy":
			if typeof(choice) == TYPE_STRING and choice == "buy":
				var price := int(pending["price"])
				if p.gold < price:
					return
				_do_buy(p, tiles[int(pending["tile"])], price)
			pending = {}
			_finish_landing()
		"upgrade":
			if typeof(choice) == TYPE_STRING and choice == "upgrade":
				var ut: BoardTile = tiles[int(pending["tile"])]
				var ucost := int(pending["price"])
				if p.gold < ucost:
					return
				_do_upgrade(p, ut, ucost)
			pending = {}
			_finish_landing()
		"portal":
			var dest := -1
			if typeof(choice) == TYPE_INT:
				dest = choice
			if dest >= 0 and (pending["options"] as Array).has(dest):
				_warp(p, dest, "Regional Warp")
			pending = {}
			_finish_landing()
		"shop":
			match String(choice):
				"heal":
					var price := heal_price_for(p)
					if p.life < int(GameData.b("start_life")) and p.gold >= price:
						p.gold -= price
						p.life += 1
						stats["heals"] += 1
						_log("%s restores 1 Life (%d G)." % [p.display_name, price])
				"reroll":
					var price := token_price_for(p)
					if p.gold >= price:
						p.gold -= price
						p.reroll_tokens += 1
						_log("%s buys a Reroll Token (%d G)." % [p.display_name, price])
				"special":
					var sp := special_die_price()
					if p.gold >= sp and p.special_dice.size() < int(GameData.b("max_special_dice")):
						p.gold -= sp
						_give_special_die(p)
				"leave":
					pending = {}
					_finish_landing()
					return
			players_changed.emit()
			state_changed.emit()
		"bank":
			var bc := String(choice)
			if bc.begins_with("invest_"):
				_bank_invest(p, int(bc.substr(7)))
				players_changed.emit()
				state_changed.emit()
			elif bc == "withdraw":
				_bank_withdraw(p)
				players_changed.emit()
				state_changed.emit()
			else:
				pending = {}
				_finish_landing()
		"casino":
			if String(choice) == "bet":
				_casino_draw(p)
			pending = {}
			_finish_landing()
		"encounter":
			var owner_id := int(pending["actor"])
			var t: BoardTile = tiles[int(pending["tile"])]
			if String(choice) == "duel":
				stats["duels_offered"] += 1
				_log("%s challenges %s to a DUEL for %s!" % [players[owner_id].display_name, p.display_name, t.name])
				pending = {"type": "duel_response", "actor": p.id, "tile": t.index, "rent": int(pending["rent"]), "owner": owner_id}
				state_changed.emit()
			else:
				stats["tax"] += 1
				var rent := int(pending["rent"])
				pending = {}
				_pay(p, rent, owner_id, "tax")
				_finish_landing()
		"duel_response":
			var tile_i := int(pending["tile"])
			var owner_id2 := int(pending["owner"])
			if String(choice) == "accept":
				_log("%s accepts the duel!" % p.display_name)
				pending = {"type": "duel_battle", "tile": tile_i, "attacker": p.id, "defender": owner_id2}
				state = State.AWAIT_DUEL
				state_changed.emit()
			else:
				stats["refused"] += 1
				var total := int(pending["rent"]) + int(GameData.b("refuse_duel_penalty"))
				pending = {}
				_log("%s refuses the duel: rent + %d G penalty." % [p.display_name, int(GameData.b("refuse_duel_penalty"))])
				_pay(p, total, owner_id2, "refused duel")
				_finish_landing()
		"conquest":
			var ct: BoardTile = tiles[int(pending["tile"])]
			if String(choice) == "conquest":
				stats["conquests"] += 1
				ct.owner_id = p.id
				_log("CONQUEST! %s takes %s." % [p.display_name, ct.name])
				_announce_region(p, ct)
			else:
				stats["rewards"] += 1
				var reward := int(pending["reward"])
				p.gold += reward
				_log("%s claims a Victory Reward of %d G (the land stays)." % [p.display_name, reward])
			pending = {}
			tiles_changed.emit()
			players_changed.emit()
			_finish_landing()
		_:
			pending = {}
			_finish_landing()


func end_turn() -> void:
	if state != State.TURN_DONE:
		return
	var p := current_player()
	var again := _roll_was_double or _extra_roll
	if p.alive and again and _bonus_rolls < int(GameData.b("max_bonus_rolls")) + WorldMods.bonus_rolls_extra:
		_bonus_rolls += 1
		_roll_was_double = false
		_extra_roll = false
		state = State.AWAIT_ROLL
		_log("%s rolls again!" % p.display_name)
		state_changed.emit()
		return
	_advance_turn()


# ------------------------------------------------------------------ internals

func _advance_turn() -> void:
	_bonus_rolls = 0
	_extra_roll = false
	_roll_was_double = false
	var n := players.size()
	var wrapped := false
	for i in range(n * 2):
		current += 1
		if current >= n:
			current = 0
			wrapped = true
		var np := players[current]
		if not np.alive:
			continue
		if np.skip_turns > 0:
			np.skip_turns -= 1
			_log("%s is trapped and skips this turn." % np.display_name)
			continue
		break
	if wrapped:
		_end_of_round()
		if state == State.GAME_OVER:
			return
	state = State.AWAIT_ROLL
	players_changed.emit()
	state_changed.emit()


func _end_of_round() -> void:
	round_number += 1
	PortalSystem.rotate_portals(tiles, rng)
	_log("--- Round %d. ---" % round_number)
	_update_market()
	_pay_mines()
	if WorldMods.harvest_per_land > 0:
		for hp in players:
			var lands := count_owned(hp.id)
			if hp.alive and lands > 0:
				hp.gold += lands * WorldMods.harvest_per_land
		_log("Bountiful Harvest: every territory yields %d G." % WorldMods.harvest_per_land)
	var hx := int(random_ingame().get("harvest_extra", 0))
	if hx > 0:
		for hp in players:
			if hp.alive and _is_human(hp):
				hp.gold += count_owned(hp.id) * hx
	players_changed.emit()
	tiles_changed.emit()
	if round_number > round_limit:
		_log("Round limit reached: the richest %s wins." % ("team" if team_mode else "ruler"))
		_end_game(_round_limit_winner())


func _move_player(p: PlayerState, steps: int) -> void:
	var from := p.position
	var raw := from + steps
	p.position = posmod(raw, BoardBuilder.TILES_TOTAL)
	player_moved.emit(p.id, from, p.position, false)
	if steps > 0 and raw >= BoardBuilder.TILES_TOTAL:
		_give_start_bonus(p)


func _warp(p: PlayerState, dest: int, label: String) -> void:
	var from := p.position
	p.position = dest
	_log("%s: %s warps to %s." % [label, p.display_name, tiles[dest].name])
	player_moved.emit(p.id, from, dest, true)


func _give_start_bonus(p: PlayerState) -> void:
	var bonus := int(GameData.b("start_bonus")) + WorldMods.start_bonus_extra
	if p.has_passive("royal_treasury"):
		bonus = int(bonus * (1.0 + p.passive_value))
	if _is_human(p):
		bonus += int(random_ingame().get("start_gold_extra", 0))
	p.gold += bonus
	_log("%s passes the Dominion Gate: +%d G." % [p.display_name, bonus])
	if _is_human(p) and int(random_ingame().get("pass_token", 0)) > 0:
		p.reroll_tokens += int(random_ingame()["pass_token"])
		_log("Random map bonus: %s gains %d Reroll Token." % [p.display_name, int(random_ingame()["pass_token"])])
	if WorldMods.start_token > 0:
		p.reroll_tokens += WorldMods.start_token
		_log("Time Fold: %s gains %d Reroll Token." % [p.display_name, WorldMods.start_token])
	players_changed.emit()


func _set_pending(d: Dictionary) -> void:
	pending = d
	state = State.AWAIT_DECISION
	state_changed.emit()


func _finish_landing() -> void:
	if state == State.GAME_OVER or not pending.is_empty():
		return
	state = State.TURN_DONE
	players_changed.emit()
	tiles_changed.emit()
	state_changed.emit()


func _nested_resolve(p: PlayerState) -> void:
	if _chain_depth >= 2 or not p.alive:
		return
	_chain_depth += 1
	_resolve_landing(p)
	_chain_depth -= 1


func _resolve_landing(p: PlayerState) -> void:
	var t: BoardTile = tiles[p.position]
	match t.type:
		BoardTile.Type.CORNER:
			_resolve_corner(p, t)
		BoardTile.Type.TERRITORY:
			_find_deposit(p, t)
			if not _meet_monster(p, t):
				_resolve_territory(p, t)
		BoardTile.Type.PORTAL:
			_resolve_portal(p, t)
		BoardTile.Type.SHOP:
			_log("%s enters the Territory Shop." % p.display_name)
			_set_pending({"type": "shop"})
		BoardTile.Type.EVENT:
			_resolve_event(p)
		BoardTile.Type.AUCTION:
			_resolve_auction(p)
		BoardTile.Type.TAX:
			_pay(p, _apply_tax_passive(p, int(int(GameData.b("tax_flat")) * WorldMods.tax_mult * (float(random_ingame().get("tax_mult", 1.0)) if _is_human(p) else 1.0))), -1, "tax")
		BoardTile.Type.SPECIAL:
			_resolve_special(p)
		BoardTile.Type.BANK:
			_log("%s enters the Bank (portfolio %d G)." % [p.display_name, p.stock_value])
			_set_pending({"type": "bank"})
		BoardTile.Type.CASINO:
			if p.gold < casino_bet_price():
				_log("%s cannot afford a Casino bet." % p.display_name)
			else:
				_set_pending({"type": "casino"})


func _resolve_corner(p: PlayerState, t: BoardTile) -> void:
	match t.corner_kind:
		"start":
			_log("%s stands at the Dominion Gate." % p.display_name)
		"sanctuary":
			var g := int(GameData.b("sanctuary_bonus"))
			p.gold += g
			_log("%s rests at the Sanctuary: +%d G." % [p.display_name, g])
		"rift":
			p.skip_turns += 1
			_log("%s is trapped in the Rift (skips next turn)." % p.display_name)
		"crossroads":
			var actives := PortalSystem.active_indices(tiles)
			if actives.is_empty():
				return
			_warp(p, actives[rng.randi() % actives.size()], "Crossroads")
	players_changed.emit()


func _price_for(p: PlayerState, t: BoardTile) -> int:
	var price := t.price
	if p.has_passive("landlord"):
		price = int(price * (1.0 - p.passive_value))
	return price


func _apply_tax_passive(p: PlayerState, amount: int) -> int:
	if p.has_passive("shadow_ledger"):
		return int(amount * (1.0 - p.passive_value))
	return amount


func _resolve_territory(p: PlayerState, t: BoardTile) -> void:
	if t.owner_id == -1:
		var price := _price_for(p, t)
		if p.gold >= price:
			_set_pending({"type": "buy", "tile": t.index, "price": price})
		else:
			_log("%s cannot afford %s (%d G)." % [p.display_name, t.name, price])
	elif t.owner_id == p.id:
		var ucost := EconomySystem.upgrade_cost(t)
		if ucost < 0:
			_log("%s visits their own Landmark %s." % [p.display_name, t.name])
		elif p.gold >= ucost:
			_set_pending({"type": "upgrade", "tile": t.index, "price": ucost})
		else:
			_log("%s visits their own land %s (upgrade costs %d G)." % [p.display_name, t.name, ucost])
	elif is_ally(t.owner_id, p.id):
		_log("%s visits the allied land %s: no rent, no duel." % [p.display_name, t.name])
	else:
		var owner_p := players[t.owner_id]
		var base_rent := EconomySystem.rent_of(t, tiles)
		if owner_p.has_passive("toll_keeper"):
			base_rent = int(base_rent * (1.0 + owner_p.passive_value))
		var rent := _apply_tax_passive(p, base_rent)
		_log("Territory Encounter at %s: %s must face the owner %s." % [t.name, p.display_name, owner_p.display_name])
		_set_pending({"type": "encounter", "actor": owner_p.id, "tile": t.index, "rent": rent, "attacker": p.id})


## A hidden treasure or mine lies on this territory: landing here finds it (automatic, never drawn on the map).
## A treasure pays once; a mine becomes the finder's and pays every round (see _pay_mines).
func _find_deposit(p: PlayerState, t: BoardTile) -> void:
	if not p.alive:
		return
	var e := DepositSystem.entry_at(deposits, t.index)
	if e.is_empty():
		return
	var d := GameData.get_deposit(String(e["id"]))
	if d.is_empty():
		return
	e["taken"] = true
	if String(d["kind"]) == "treasure":
		var parts: Array[String] = []
		var gold := int(d.get("gold", 0))
		p.gold += gold
		parts.append("%d G" % gold)
		var tk := int(d.get("tokens", 0))
		if tk > 0:
			p.reroll_tokens += tk
			parts.append("%d Reroll Token" % tk)
		if bool(d.get("die", false)) and p.special_dice.size() < int(GameData.b("max_special_dice")) and not GameData.special_dice.is_empty():
			_give_special_die(p)
			parts.append("a Special Die")
		stats["treasures_found"] += 1
		_log("Hidden treasure! %s unearths the %s on %s: %s." % [p.display_name, d["name"], t.name, " + ".join(parts)])
		deposit_event.emit(p.id, "treasure", String(d["id"]))
	else:
		e["owner"] = p.id
		e["left"] = int(d.get("rounds", 0))
		e["paid"] = 0
		stats["mines_found"] += 1
		_log("Hidden mine! %s strikes the %s on %s: %d G every round for %d rounds." % [p.display_name, d["name"], t.name, int(d.get("income", 0)), int(d.get("rounds", 0))])
		deposit_event.emit(p.id, "mine", String(d["id"]))
	players_changed.emit()
	tiles_changed.emit()


## End of a round: every active mine pays its finder (an eliminated ruler's mines pay nothing).
func _pay_mines() -> void:
	for e in deposits:
		if not bool(e["taken"]) or int(e["left"]) <= 0:
			continue
		var oid := int(e["owner"])
		if oid < 0 or oid >= players.size() or not players[oid].alive:
			continue
		var d := GameData.get_deposit(String(e["id"]))
		if String(d.get("kind", "")) != "mine":
			continue
		var mp: PlayerState = players[oid]
		var inc := int(d.get("income", 0))
		mp.gold += inc
		e["paid"] = int(e["paid"]) + 1
		e["left"] = int(e["left"]) - 1
		stats["mine_income"] += inc
		var line := "Mine: the %s yields %d G to %s" % [d["name"], inc, mp.display_name]
		var every := int(d.get("token_every", 0))
		if every > 0 and int(e["paid"]) % every == 0:
			mp.reroll_tokens += 1
			line += " and a Reroll Token"
		if int(e["left"]) <= 0:
			line += " (the mine is exhausted)"
		_log(line + ".")


## A hidden monster lurks on this territory: the player meets it only by landing here (it is never drawn on the map).
## A player who already owns a Monster card (max one per player) walks past it unaware. Returns true if a decision is pending.
func _meet_monster(p: PlayerState, t: BoardTile) -> bool:
	if p.monster_id != "" or not p.alive:
		return false
	var e := MonsterSystem.entry_at(monsters, t.index)
	if e.is_empty():
		return false
	var m := GameData.get_monster(String(e["id"]))
	_log("%s disturbs a hidden monster on %s: the %s attacks!" % [p.display_name, t.name, m.get("name", "monster")])
	_set_pending({"type": "monster", "tile": t.index, "monster": String(e["id"])})
	return true


## The player fights the monster (or flees); afterwards the landing continues as on any territory.
func _answer_monster(p: PlayerState, choice: Variant) -> void:
	var mid := String(pending["monster"])
	var t: BoardTile = tiles[int(pending["tile"])]
	var m := GameData.get_monster(mid)
	pending = {}
	if String(choice) == "fight":
		stats["monster_fights"] += 1
		var res := MonsterSystem.fight(p, mid, rng)
		if bool(res["won"]):
			var e := MonsterSystem.entry_at(monsters, t.index)
			if bool(GameData.b("monster_unique", true)) and not e.is_empty():
				e["taken"] = true  # this monster is gone for everyone
			p.monster_id = mid
			stats["monsters_won"] += 1
			_log("%s defeats the %s in %d ticks! Monster card won: it fights beside the King in Duels." % [p.display_name, m.get("name", "monster"), int(res["ticks"])])
			monster_event.emit(p.id, "won", mid)
		else:
			var fee := mini(int(GameData.b("monster_defeat_gold")), p.gold)
			p.gold -= fee
			_log("%s is beaten by the %s and loses %d G. The monster keeps its lair." % [p.display_name, m.get("name", "monster"), fee])
			monster_event.emit(p.id, "lost", mid)
	else:
		_log("%s flees from the %s." % [p.display_name, m.get("name", "monster")])
		monster_event.emit(p.id, "fled", mid)
	players_changed.emit()
	tiles_changed.emit()
	_resolve_territory(p, t)
	_finish_landing()


func _resolve_portal(p: PlayerState, t: BoardTile) -> void:
	if not t.portal_active:
		_log("%s stands on a dormant portal socket." % p.display_name)
		return
	var options: Array = []
	for idx in PortalSystem.active_indices(tiles):
		if idx != t.index:
			options.append(idx)
	if options.is_empty():
		return
	_log("%s stands on an ACTIVE portal!" % p.display_name)
	_set_pending({"type": "portal", "options": options})


## Auction House: a free territory is sold to the highest bidder. Every living ruler may bid, starting
## with the one who landed. A ruler who passes (or cannot afford the next bid) is out.
func _resolve_auction(p: PlayerState) -> void:
	var free: Array[BoardTile] = []
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY and t.owner_id == -1:
			free.append(t)
	if free.is_empty():
		_log("The Auction House has nothing to sell.")
		return
	var lot: BoardTile = free[rng.randi() % free.size()]
	var start := maxi(10, int(round(lot.price * float(GameData.b("auction_start_ratio")) / 5.0)) * 5)
	var inc := maxi(5, int(round(lot.price * float(GameData.b("auction_step_ratio")) / 5.0)) * 5)
	var order: Array = []
	for i in range(players.size()):
		var pid := (p.id + i) % players.size()
		if players[pid].alive:
			order.append(pid)
	_log("AUCTION: %s (list price %d G) opens at %d G. Every ruler may bid." % [lot.name, lot.price, start])
	_set_pending({"type": "auction", "actor": p.id, "tile": lot.index, "bid": start, "inc": inc, "leader": -1, "order": order, "passed": []})
	if p.gold < start:  # the lander cannot even open: moves on to the next bidder
		(pending["passed"] as Array).append(p.id)
		_auction_advance()


## Price the actor must pay to take the lead.
func auction_next_bid() -> int:
	if String(pending.get("type", "")) != "auction":
		return 0
	if int(pending["leader"]) < 0:
		return int(pending["bid"])
	return int(pending["bid"]) + int(pending["inc"])


func _auction_answer(choice: Variant) -> void:
	var actor := players[int(pending["actor"])]
	var lot_name := tiles[int(pending["tile"])].name
	if String(choice) == "bid":
		var nb := auction_next_bid()
		if actor.gold < nb:
			return
		pending["bid"] = nb
		pending["leader"] = actor.id
		_log("%s bids %d G for %s." % [actor.display_name, nb, lot_name])
	else:
		(pending["passed"] as Array).append(actor.id)
		_log("%s passes." % actor.display_name)
	_auction_advance()


func _auction_advance() -> void:
	var order: Array = pending["order"]
	var passed: Array = pending["passed"]
	var leader := int(pending["leader"])
	var actor_id := int(pending["actor"])
	for step in range(order.size()):
		actor_id = int(order[(order.find(actor_id) + 1) % order.size()])
		if passed.has(actor_id):
			continue
		if actor_id == leader:
			break  # every other ruler is out: the leader wins
		if players[actor_id].gold < auction_next_bid():
			passed.append(actor_id)  # cannot afford the next bid
			continue
		pending["actor"] = actor_id
		state_changed.emit()
		return
	_auction_end()


func _auction_end() -> void:
	var leader := int(pending["leader"])
	var t: BoardTile = tiles[int(pending["tile"])]
	var bid := int(pending["bid"])
	pending = {}
	if leader >= 0:
		var w := players[leader]
		w.gold -= bid
		t.owner_id = leader
		stats["auctions"] += 1
		_log("SOLD! %s wins %s for %d G." % [w.display_name, t.name, bid])
		_announce_region(w, t)
		tiles_changed.emit()
		players_changed.emit()
	else:
		_log("No bids: %s stays unsold." % t.name)
	_finish_landing()


func _resolve_event(p: PlayerState) -> void:
	if p.has_passive("treasure_hunter"):
		p.gold += int(p.passive_value)
		_log("%s's Treasure Hunter finds %d G." % [p.display_name, int(p.passive_value)])
	var ev := EventSystem.draw(rng)
	var value := int(ev.get("value", 0))
	_log("Event: %s - %s" % [ev.get("title", "?"), ev.get("description", "")])
	match String(ev.get("effect", "none")):
		"gain_gold":
			p.gold += value
		"lose_gold":
			_pay(p, value, -1, "event")
		"move_forward":
			_move_player(p, value)
			_nested_resolve(p)
		"move_back":
			_move_player(p, -value)
			_nested_resolve(p)
		"reroll_token":
			p.reroll_tokens += value
		"collect_from_all":
			_collect_from_rivals(p, value, "tribute")
		"extra_roll":
			_extra_roll = true
		"special_die":
			_give_special_die(p)
		"market_up":
			_shift_market(float(value) / 100.0)
		"market_down":
			_shift_market(-float(value) / 100.0)
		"free_bet":
			_casino_draw(p, true)
		"gain_per_land":  # continent cards: gold for every territory the player owns
			var n := _owned_land_count(p)
			p.gold += value * n
			_log("%s earns %d G from %d territories." % [p.display_name, value * n, n])
		"lose_per_land":  # a levy on every territory the player owns
			var nl := _owned_land_count(p)
			if nl > 0:
				_pay(p, value * nl, -1, "event")
		"steal_richest":  # take gold from the richest living rival (never a teammate)
			_special_steal(p, value)
		"warp_land":
			var lands: Array[BoardTile] = []
			for t in tiles:
				if t.type == BoardTile.Type.TERRITORY:
					lands.append(t)
			_warp(p, lands[rng.randi() % lands.size()].index, "Event")
			_nested_resolve(p)
		"heal":
			var max_life := int(GameData.b("start_life"))
			if p.life < max_life:
				p.life = mini(max_life, p.life + value)
				_log("%s recovers %d Life (now %d)." % [p.display_name, value, p.life])
			else:
				_log("%s is already at full Life." % p.display_name)
		"skip_turn":
			p.skip_turns += value
			_log("%s will skip the next turn." % p.display_name)
		"warp_portal":
			var act := PortalSystem.active_indices(tiles)
			act.erase(p.position)
			if not act.is_empty():
				_warp(p, act[rng.randi() % act.size()], "Event")
				_nested_resolve(p)
		"warp_start":
			_warp(p, 0, "Event")
			_give_start_bonus(p)
			_nested_resolve(p)
	players_changed.emit()


func _owned_land_count(p: PlayerState) -> int:
	var n := 0
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY and t.owner_id == p.id:
			n += 1
	return n


func _resolve_special(p: PlayerState) -> void:
	match rng.randi_range(0, 2):
		0:
			p.reroll_tokens += 1
			_log("Special: Cosmic Gift! %s gains a Reroll Token." % p.display_name)
		1:
			var lands: Array[BoardTile] = []
			for t in tiles:
				if t.type == BoardTile.Type.TERRITORY:
					lands.append(t)
			var dest: BoardTile = lands[rng.randi() % lands.size()]
			_warp(p, dest.index, "Special: Rift Surge")
			_nested_resolve(p)
		2:
			_log("Special: Tribute! %s collects 25 G from each rival." % p.display_name)
			_collect_from_rivals(p, 25, "tribute")
	players_changed.emit()


## Every living rival pays `amount` to p. Teammates (2vs2) are never charged.
func _collect_from_rivals(p: PlayerState, amount: int, reason: String) -> void:
	for o in players.duplicate():
		if o.alive and o.id != p.id and not is_ally(o.id, p.id) and state != State.GAME_OVER:
			_pay(o, amount, p.id, reason)


func _do_buy(p: PlayerState, t: BoardTile, price: int) -> void:
	p.gold -= price
	t.owner_id = p.id
	_log("%s buys %s for %d G." % [p.display_name, t.name, price])
	_announce_region(p, t)
	tiles_changed.emit()
	players_changed.emit()


## Commander missions: counts an event for the player's active mission and announces a new star.
func _mission_progress(p: PlayerState, metric: String, amount: int = 1) -> void:
	if CommanderSystem.add_progress(p, metric, amount):
		var cname := String(GameData.get_champion(p.champion_id).get("name", "Commander"))
		_log("COMMANDER UP! %s's %s reaches %d stars (mission complete)." % [p.display_name, cname, p.commander_star])
	players_changed.emit()


func _do_upgrade(p: PlayerState, t: BoardTile, cost: int) -> void:
	p.gold -= cost
	t.level += 1
	stats["upgrades"] = int(stats.get("upgrades", 0)) + 1
	if t.is_landmark():
		_log("%s raises a LANDMARK on %s (%d G). Rent is now %d G." % [p.display_name, t.name, cost, EconomySystem.rent_of(t, tiles)])
	else:
		_log("%s upgrades %s to Level %d (%d G). Rent is now %d G." % [p.display_name, t.name, t.level, cost, EconomySystem.rent_of(t, tiles)])
	tiles_changed.emit()
	players_changed.emit()
	if t.is_landmark():
		_mission_progress(p, "landmarks")


func _announce_region(p: PlayerState, t: BoardTile) -> void:
	var owned := EconomySystem.region_count(tiles, t.region, p.id)
	if owned == 10:
		_log("*** %s achieves REGIONAL DOMINION over %s! ***" % [p.display_name, _region_name(t.region)])
	elif owned == int(GameData.b("majority_threshold")):
		_log("%s now holds the majority of %s (rent bonus)." % [p.display_name, _region_name(t.region)])


func _region_name(region: int) -> String:
	var regions: Array = continent.get("regions", [])
	if region < regions.size():
		return regions[region]["name"]
	return BoardBuilder.DEFAULT_REGION_NAMES[region]


func _cheapest_owned(p: PlayerState) -> BoardTile:
	var best: BoardTile = null
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY and t.owner_id == p.id:
			if best == null or t.price < best.price:
				best = t
	return best


## Takes `amount` from p (selling land if needed). creditor_id -1 = bank.
func _pay(p: PlayerState, amount: int, creditor_id: int, reason: String) -> void:
	if amount <= 0:
		return
	if p.gold < amount and p.stock_value > 0:
		_log("%s cashes out the stock portfolio (%d G) to pay." % [p.display_name, p.stock_value])
		_bank_withdraw(p, true)
	while p.gold < amount:
		var t := _cheapest_owned(p)
		if t == null:
			break
		var refund := int((t.price + EconomySystem.upgrade_invested(t)) * float(GameData.b("sell_ratio")))
		t.owner_id = -1
		t.level = 0
		p.gold += refund
		_log("%s is forced to sell %s for %d G." % [p.display_name, t.name, refund])
		tiles_changed.emit()
	var paid := mini(p.gold, amount)
	p.gold -= paid
	if creditor_id >= 0:
		players[creditor_id].gold += paid
		_log("%s pays %d G (%s) to %s." % [p.display_name, paid, reason, players[creditor_id].display_name])
	else:
		_log("%s pays %d G (%s)." % [p.display_name, paid, reason])
	players_changed.emit()
	if paid < amount:
		_bankrupt(p)


func _bankrupt(p: PlayerState) -> void:
	stats["bankrupt"] += 1
	p.life -= 1
	_log("%s is BANKRUPT and loses 1 Life! (%d left)" % [p.display_name, p.life])
	if p.life <= 0:
		_eliminate(p)
	else:
		p.gold = int(GameData.b("bailout_gold"))
		_log("%s receives a bailout of %d G." % [p.display_name, p.gold])
		players_changed.emit()


func _eliminate(p: PlayerState) -> void:
	p.alive = false
	p.stock_value = 0
	p.stock_basis = 0
	for t in tiles:
		if t.owner_id == p.id:
			t.owner_id = -1
			t.level = 0
	_log("%s has been ELIMINATED." % p.display_name)
	if p.id == current:
		pending = {}
	tiles_changed.emit()
	players_changed.emit()
	_check_game_over()


func _check_game_over() -> void:
	if state == State.GAME_OVER:
		return
	var alive := alive_players()
	if team_mode:  # 2vs2: the match ends when only one team has rulers left
		var teams: Array[int] = []
		for q in alive:
			if not teams.has(q.team):
				teams.append(q.team)
		if teams.size() <= 1:
			_end_game(_richest(alive))
		return
	if human_present and not players[0].alive:
		_end_game(_richest(alive))
	elif alive.size() <= 1:
		_end_game(alive[0].id if alive.size() == 1 else -1)


## Round limit: the richest player in FFA; in 2vs2 the richest living member of the richest team.
func _round_limit_winner() -> int:
	if not team_mode:
		return _richest(alive_players())
	var best_team := -1
	var best_worth := -1
	for team in [0, 1]:
		var w := team_networth(team)
		if w > best_worth:
			best_worth = w
			best_team = team
	var members: Array[PlayerState] = []
	for p in alive_players():
		if p.team == best_team:
			members.append(p)
	return _richest(members)


func _richest(list: Array[PlayerState]) -> int:
	var best := -1
	var best_worth := -1
	for p in list:
		var w := networth(p)
		if w > best_worth:
			best_worth = w
			best = p.id
	return best


func _end_game(winner: int) -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	pending = {}
	winner_id = winner
	winner_team = players[winner].team if (team_mode and winner >= 0) else -1
	var who := "nobody"
	if winner >= 0:
		who = players[winner].display_name
		if team_mode:
			who = "Team %s (%s)" % [team_label(players[winner]), _team_names(players[winner].team)]
	_log("=== GAME OVER. Winner: %s ===" % who)
	players_changed.emit()
	state_changed.emit()
	game_over.emit(winner)


func _log(text: String) -> void:
	recent_log.append(text)
	if recent_log.size() > 60:
		recent_log.pop_front()
	log_added.emit(text)


# ------------------------------------------------------------------ Territory Encounter / Duel (Phase 5)

## The player who must answer the current decision (not always the current turn player:
## in an Encounter the OWNER chooses Tax or Duel).
func decision_actor() -> PlayerState:
	if state == State.AWAIT_DECISION and pending.has("actor"):
		return players[int(pending["actor"])]
	return current_player()


func get_decision_prompt() -> String:
	var p := current_player()
	match String(pending.get("type", "")):
		"monster":
			return "A hidden monster attacks! %s\nFight it with your army (if beaten you lose %d G) or flee?" % [
				MonsterSystem.summary(String(pending["monster"])), int(GameData.b("monster_defeat_gold"))]
		"encounter":
			return "%s landed on your %s (rent %d G). Collect Tax, or challenge to a Duel?" % [
				p.display_name, tiles[int(pending["tile"])].name, int(pending["rent"])]
		"duel_response":
			return "%s challenges you to a Duel for %s. Accept, or refuse and pay %d G (rent + penalty)?" % [
				players[int(pending["owner"])].display_name, tiles[int(pending["tile"])].name,
				int(pending["rent"]) + int(GameData.b("refuse_duel_penalty"))]
		"conquest":
			return "You won the Duel! Take %s (Conquest) or claim a Victory Reward?" % tiles[int(pending["tile"])].name
		"auction":
			var lot := tiles[int(pending["tile"])]
			var lead := int(pending["leader"])
			return "Auction: %s (list price %d G). %s Bid %d G or pass?" % [
				lot.name, lot.price,
				("Highest bid %d G by %s." % [int(pending["bid"]), players[lead].display_name]) if lead >= 0 else "No bids yet.",
				auction_next_bid()]
		"upgrade":
			var ut: BoardTile = tiles[int(pending["tile"])]
			return "Your land %s (rent %d G). Upgrade it for %d G to raise the rent?" % [ut.name, EconomySystem.rent_of(ut, tiles), int(pending["price"])]
		"portal":
			return "Active portal: choose a destination."
		"shop":
			return "Territory Shop."
		"bank":
			var bp := current_player()
			var pl := bp.stock_value - bp.stock_basis
			return "Bank & Stocks. Portfolio: %d G (%s%d G vs. invested). Last round: %+d%%." % [
				bp.stock_value, "+" if pl >= 0 else "", pl, int(round(market_change * 100.0))]
		"casino":
			return "Casino! Bet %d G. Pot: %d G." % [casino_bet_price(), casino_pot]
	return ""


func is_human_duel() -> bool:
	if state != State.AWAIT_DUEL:
		return false
	return not players[int(pending["attacker"])].is_ai or not players[int(pending["defender"])].is_ai


## For the UI: {"human": PlayerState, "opponent": PlayerState, "human_attacks": bool}
func duel_participants() -> Dictionary:
	var a := players[int(pending["attacker"])]
	var d := players[int(pending["defender"])]
	if not a.is_ai:
		return {"human": a, "opponent": d, "human_attacks": true}
	return {"human": d, "opponent": a, "human_attacks": false}


## Runs an AI-vs-AI duel instantly (no UI). Humans fight through the Battle scene instead.
func auto_duel() -> void:
	if state != State.AWAIT_DUEL or is_human_duel():
		return
	var a := players[int(pending["attacker"])]
	var d := players[int(pending["defender"])]
	var ground := Terrain.generate(rng)  # every duel is fought on new random ground
	var cfg_a := BattleAI.prepare_ai_army(a, rng, 0, ground)
	var cfg_d := BattleAI.prepare_ai_army(d, rng, 1, ground)
	var e := BattleEngine.new()
	e.setup({"seed": rng.randi(), "ai_supports": [true, true], "terrain": ground, "sides": [cfg_a, cfg_d]})
	var guard := 0
	while not e.finished and guard < BattleEngine.MAX_TICKS + 5:
		e.step()
		guard += 1
	a.consume_supports(e.used_supports[0])  # played Support cards are spent
	d.consume_supports(e.used_supports[1])
	var winner_pid := -1
	var bonus := 0
	if e.winner == 0:
		winner_pid = a.id
		bonus = int(e.bonus_gold[0])
	elif e.winner == 1:
		winner_pid = d.id
		bonus = int(e.bonus_gold[1])
	_log("Duel at %s: %s vs %s - %s after %d ticks." % [
		tiles[int(pending["tile"])].name, a.display_name, d.display_name,
		(players[winner_pid].display_name + " wins") if winner_pid >= 0 else "draw", e.tick])
	finish_duel({"winner": winner_pid, "bonus_gold": bonus,
		"gold_delta": {a.id: int(e.gold_delta[0]), d.id: int(e.gold_delta[1])}})


## result = {"winner": player_id or -1 (draw), "bonus_gold": int}. A draw goes to the defender.
func finish_duel(result: Dictionary) -> void:
	if state != State.AWAIT_DUEL:
		return
	var attacker := players[int(pending["attacker"])]
	var defender := players[int(pending["defender"])]
	var t: BoardTile = tiles[int(pending["tile"])]
	var bonus := int(result.get("bonus_gold", 0)) + WorldMods.duel_win_gold
	var deltas: Dictionary = result.get("gold_delta", {})
	for k in deltas:
		players[int(k)].gold = maxi(0, players[int(k)].gold + int(deltas[k]))
	stats["duels"] += 1
	var duel_winner := int(result.get("winner", -1))
	if duel_winner >= 0 and duel_winner < players.size():
		_mission_progress(players[duel_winner], "duel_wins")
	if duel_winner >= 0 and duel_winner < players.size() and _is_human(players[duel_winner]):
		bonus += int(random_ingame().get("duel_win_gold", 0))
	if int(result.get("winner", -1)) != attacker.id:
		stats["defender_wins"] += 1
		defender.gold += bonus + (int(defender.passive_value) if defender.has_passive("spoils") else 0)
		_log("DEFENDER WINS: %s keeps %s." % [defender.display_name, t.name])
		pending = {}
		_lose_life(attacker, "lost the duel")
		_finish_landing()
		return
	stats["attacker_wins"] += 1
	attacker.gold += bonus + (int(attacker.passive_value) if attacker.has_passive("spoils") else 0)
	_log("ATTACKER WINS: %s defeats %s!" % [attacker.display_name, defender.display_name])
	if bool(GameData.b("defender_loses_life")):
		_lose_life(defender, "lost the duel")
	if state == State.GAME_OVER:
		return
	var reward := int(t.price * float(GameData.b("duel_reward_ratio")))
	pending = {"type": "conquest", "actor": attacker.id, "tile": t.index, "reward": reward}
	state = State.AWAIT_DECISION
	players_changed.emit()
	state_changed.emit()


func _lose_life(p: PlayerState, reason: String) -> void:
	p.life -= 1
	_log("%s %s and loses 1 Life (%d left)." % [p.display_name, reason, maxi(p.life, 0)])
	if p.life <= 0:
		_eliminate(p)
	else:
		players_changed.emit()


func heal_price_for(p: PlayerState) -> int:
	var price := float(GameData.b("heal_price"))
	if p.has_passive("mender"):
		price *= 1.0 - p.passive_value
	return int(round(price))


func token_price_for(_p: PlayerState) -> int:
	return WorldMods.token_price()


# ------------------------------------------------------------------ save / resume

func _player_to_dict(p: PlayerState) -> Dictionary:
	var units: Array = []
	for u in p.roster.units:
		units.append({"id": u.card_id, "stars": u.stars, "cell": [u.cell.x, u.cell.y]})
	return {
		"id": p.id, "name": p.display_name, "is_ai": p.is_ai, "difficulty": p.difficulty, "faction": p.faction_id,
		"champion": p.champion_id, "passive": p.passive, "passive_value": p.passive_value, "color": p.color.to_html(),
		"position": p.position, "gold": p.gold, "life": p.life, "level": p.level, "capacity": p.capacity,
		"tokens": p.reroll_tokens, "skip": p.skip_turns, "alive": p.alive, "team": p.team, "dice": p.special_dice.duplicate(), "move_bonus": p.move_bonus,
		"cstar": p.commander_star, "mprog": p.mission_progress, "stock": p.stock_value, "sbasis": p.stock_basis,
		"monster": p.monster_id, "deck": p.deck.to_dict(), "pile": p.battle_deck.pool.duplicate(), "spile": p.battle_deck.support_pool.duplicate(), "hand": p.hand.duplicate(), "units": units}


## Serialises the match. Only possible at a stable moment: start of a turn or end of a turn
## (no pending decision, no duel). Returns {} otherwise.
func to_dict() -> Dictionary:
	if (state != State.AWAIT_ROLL and state != State.TURN_DONE) or not pending.is_empty():
		return {}
	var plist: Array = []
	for p in players:
		plist.append(_player_to_dict(p))
	var tl: Array = []
	for t in tiles:
		tl.append([t.owner_id, t.portal_active, t.level])
	return {
		"version": SAVE_FORMAT, "continent_id": continent["id"], "round": round_number, "current": current,
		"state": int(state), "last_dice": [last_dice.x, last_dice.y], "winner_id": winner_id,
		"human_present": human_present, "team_mode": team_mode, "winner_team": winner_team, "roll_double": _roll_was_double, "extra_roll": _extra_roll, "bonus_rolls": _bonus_rolls,
		"tutorial": tutorial, "journey": journey, "wager": wager, "wager_odds": wager_odds, "random_map": random_map, "wager_settled": wager_settled, "round_limit": round_limit, "market": market_change, "pot": casino_pot, "tutorial_seen": tutorial_seen.duplicate(),
		"monsters": monsters.map(func(e): return [int(e["tile"]), String(e["id"]), bool(e["taken"])]),
		"deposits": deposits.map(func(e): return [int(e["tile"]), String(e["id"]), bool(e["taken"]), int(e["owner"]), int(e["left"]), int(e["paid"])]),
		"stats": stats.duplicate(), "players": plist, "tiles": tl, "log": recent_log.duplicate(),
		# 64-bit values are stored as text: JSON numbers are doubles and would lose precision.
		"rng_seed": str(rng.seed), "rng_state": str(rng.state)}


static func from_dict(d: Dictionary) -> MatchController:
	var c := MatchController.new()
	c.continent = GameData.get_continent(String(d["continent_id"]))
	CardDatabase.set_continent(String(c.continent["id"]))
	WorldMods.apply(c.continent)
	GameData.apply_flavor(String(c.continent["id"]))
	c.tiles = BoardBuilder.build(c.continent)
	var tl: Array = d["tiles"]
	for i in range(mini(tl.size(), c.tiles.size())):
		c.tiles[i].owner_id = int(tl[i][0])
		c.tiles[i].portal_active = bool(tl[i][1])
		if (tl[i] as Array).size() > 2:  # older saves have no upgrade level
			c.tiles[i].level = int(tl[i][2])
	for me in d.get("monsters", []):  # older saves have no monsters
		c.monsters.append({"tile": int(me[0]), "id": String(me[1]), "taken": bool(me[2])})
	for de in d.get("deposits", []):  # older saves have no deposits
		c.deposits.append({"tile": int(de[0]), "id": String(de[1]), "taken": bool(de[2]), "owner": int(de[3]), "left": int(de[4]), "paid": int(de[5])})
	c.human_present = bool(d["human_present"])
	c.team_mode = bool(d.get("team_mode", false))
	c.winner_team = int(d.get("winner_team", -1))
	for pd in d["players"]:
		var p := PlayerState.new()
		p.id = int(pd["id"])
		p.display_name = String(pd["name"])
		p.is_ai = bool(pd["is_ai"])
		p.difficulty = String(pd["difficulty"])
		p.faction_id = String(pd["faction"])
		p.champion_id = String(pd["champion"])
		p.passive = String(pd["passive"])
		p.passive_value = float(pd["passive_value"])
		p.color = Color(String(pd["color"]))
		p.position = int(pd["position"])
		p.gold = int(pd["gold"])
		p.life = int(pd["life"])
		p.level = int(pd["level"])
		p.capacity = int(pd["capacity"])
		p.reroll_tokens = int(pd["tokens"])
		p.skip_turns = int(pd["skip"])
		p.alive = bool(pd["alive"])
		p.team = int(pd.get("team", -1))
		for did in pd.get("dice", []):
			p.special_dice.append(String(did))
		p.move_bonus = int(pd.get("move_bonus", 0))
		p.commander_star = int(pd.get("cstar", 1))
		p.mission_progress = int(pd.get("mprog", 0))
		p.monster_id = String(pd.get("monster", ""))
		p.stock_value = int(pd.get("stock", 0))
		p.stock_basis = int(pd.get("sbasis", 0))
		p.deck = Deck.from_dict(pd["deck"])
		p.battle_deck = BattleDeck.new(p.deck, c.rng)
		p.battle_deck.pool.clear()
		for id in pd["pile"]:
			p.battle_deck.pool.append(String(id))
		if pd.has("spile"):  # older saves: every Support stays in the pile, empty hand
			p.battle_deck.support_pool.clear()
			for sid in pd["spile"]:
				p.battle_deck.support_pool.append(String(sid))
		for hid in pd.get("hand", []):
			p.hand.append(String(hid))
		p.roster = UnitRoster.new()
		for ud in pd["units"]:
			var u := UnitInstance.new(String(ud["id"]), int(ud["stars"]))
			u.cell = Vector2i(int(ud["cell"][0]), int(ud["cell"][1]))
			p.roster.units.append(u)
		c.players.append(p)
	c.tutorial = bool(d.get("tutorial", false))
	c.journey = bool(d.get("journey", false))
	c.wager = int(d.get("wager", 0))
	c.wager_odds = float(d.get("wager_odds", 2.0))
	c.random_map = bool(d.get("random_map", false))
	c._apply_random_map(false)  # standing effects (Battle Shop discount); one-time gifts were already paid
	c.wager_settled = bool(d.get("wager_settled", false))
	c.round_limit = int(d.get("round_limit", int(GameData.b("max_rounds"))))
	c.market_change = float(d.get("market", 0.0))
	c.casino_pot = int(d.get("pot", int(GameData.b("casino_pot_seed"))))
	for id in d.get("tutorial_seen", []):
		c.tutorial_seen.append(String(id))
	c.round_number = int(d["round"])
	c.current = int(d["current"])
	c.state = int(d["state"]) as State
	c.last_dice = Vector2i(int(d["last_dice"][0]), int(d["last_dice"][1]))
	c.winner_id = int(d["winner_id"])
	c._roll_was_double = bool(d["roll_double"])
	c._extra_roll = bool(d["extra_roll"])
	c._bonus_rolls = int(d["bonus_rolls"])
	for k in d["stats"]:
		c.stats[k] = int(d["stats"][k])
	for line in d.get("log", []):
		c.recent_log.append(String(line))
	# Restore the random generator LAST: building the piles above consumed random numbers.
	c.rng.seed = int(String(d["rng_seed"]))
	c.rng.state = int(String(d["rng_state"]))
	return c


# ------------------------------------------------------------------ Bank & Casino

func casino_bet_price() -> int:
	return int(GameData.b("casino_bet"))


func _bank_invest(p: PlayerState, amount: int) -> void:
	var allowed := false
	for opt in GameData.b("bank_invest_options"):  # JSON numbers are floats: compare as ints
		if int(opt) == amount:
			allowed = true
	if amount <= 0 or p.gold < amount or not allowed:
		return
	p.gold -= amount
	p.stock_value += amount
	p.stock_basis += amount
	stats["bank_deposits"] = int(stats.get("bank_deposits", 0)) + 1
	_log("%s invests %d G in the stock market (portfolio %d G)." % [p.display_name, amount, p.stock_value])


## Sells the whole portfolio. `forced` = emergency sale to pay a debt (no extra log of the profit).
func _bank_withdraw(p: PlayerState, forced: bool = false) -> void:
	if p.stock_value <= 0:
		return
	var v := p.stock_value
	var pl := v - p.stock_basis
	p.gold += v
	p.stock_value = 0
	p.stock_basis = 0
	if not forced:
		_log("%s sells the portfolio for %d G (%s%d G)." % [p.display_name, v, "+" if pl >= 0 else "", pl])


## Every round the whole market moves by one random percentage, applied to every portfolio.
func _update_market() -> void:
	market_change = snappedf(rng.randf_range(float(GameData.b("stock_change_min")), float(GameData.b("stock_change_max"))) + WorldMods.stock_bias, 0.01)
	var any := false
	for p in players:
		if p.alive and p.stock_value > 0:
			p.stock_value = maxi(0, int(round(float(p.stock_value) * (1.0 + market_change))))
			any = true
	if any:
		_log("Stock market: %+d%% this round." % int(round(market_change * 100.0)))


## The die of destiny. Low faces hurt (1-2 lose gold, 3 sends you back), high faces reward (4-6).
## `forced_face` > 0: the Destiny Die (Special Die) rolled that face already.
func _resolve_fate(p: PlayerState, forced_face: int = 0, values: Array = []) -> void:
	var face := forced_face if forced_face > 0 else rng.randi_range(1, 6)
	var table: Array = values if values.size() == 6 else GameData.b("fate_values")
	var amount := int(table[face - 1])
	stats["fates"] = int(stats.get("fates", 0)) + 1
	match face:
		1:
			_log("FATE die: %d - Disaster! %s loses %d G." % [face, p.display_name, -amount])
			_pay(p, -amount, -1, "fate")
		2:
			_log("FATE die: %d - Bad luck. %s loses %d G." % [face, p.display_name, -amount])
			_pay(p, -amount, -1, "fate")
		3:
			var steps := int(GameData.b("fate_detour"))
			_log("FATE die: %d - A detour! %s goes back %d tiles." % [face, p.display_name, steps])
			_move_player(p, -steps)
			_nested_resolve(p)
		4, 5:
			p.gold += amount
			_log("FATE die: %d - %s! %s gains %d G." % [face, "Blessing" if face == 4 else "Fortune", p.display_name, amount])
		6:
			p.gold += amount
			p.reroll_tokens += 1
			_log("FATE die: %d - DIVINE FAVOR! %s gains %d G and a Reroll Token." % [face, p.display_name, amount])
	players_changed.emit()


## Event card: every portfolio moves at once by `change` (fraction).
func _shift_market(change: float) -> void:
	market_change = change
	var any := false
	for q in players:
		if q.alive and q.stock_value > 0:
			q.stock_value = maxi(0, int(round(float(q.stock_value) * (1.0 + change))))
			any = true
	_log("Stock market: every portfolio %+d%%%s." % [int(round(change * 100.0)), "" if any else " (nobody is invested)"])


## `free` = free chip from an Event card: costs nothing and adds nothing to the pot.
func _casino_draw(p: PlayerState, free: bool = false) -> void:
	var price := casino_bet_price()
	if not free:
		if p.gold < price:
			return
		p.gold -= price
		casino_pot += price
	stats["bets"] = int(stats.get("bets", 0)) + 1
	var r := rng.randf()
	var jack := float(GameData.b("casino_jackpot_chance"))
	var big := float(GameData.b("casino_big_chance"))
	var small := float(GameData.b("casino_small_chance"))
	if r < jack:
		var pot := casino_pot
		p.gold += pot
		casino_pot = int(GameData.b("casino_pot_seed"))
		stats["jackpots"] = int(stats.get("jackpots", 0)) + 1
		_log("CASINO JACKPOT! %s wins the whole pot: %d G!" % [p.display_name, pot])
	elif r < jack + big:
		var prize := price * int(GameData.b("casino_big_mult"))
		p.gold += prize
		_log("Casino: %s wins the big prize, %d G!" % [p.display_name, prize])
	elif r < jack + big + small:
		var prize2 := price * int(GameData.b("casino_small_mult"))
		p.gold += prize2
		_log("Casino: %s wins %d G." % [p.display_name, prize2])
	else:
		_log("Casino: %s %s - no luck." % [p.display_name, "plays a free chip" if free else "bets %d G" % price])
	players_changed.emit()


# ------------------------------------------------------------------ Special Dice

func special_die_price() -> int:
	return int(GameData.b("special_die_price"))


func _give_special_die(p: PlayerState) -> void:
	if p.special_dice.size() >= int(GameData.b("max_special_dice")):
		_log("%s cannot carry another Special Die." % p.display_name)
		return
	var def: Dictionary = GameData.special_dice[rng.randi() % GameData.special_dice.size()]
	p.special_dice.append(String(def["id"]))
	_log("%s receives a Special Die: %s." % [p.display_name, def["name"]])


## Uses one of the current player's Special Dice before rolling the normal dice.
## Swift: bonus to the next move. Thief: steal gold. Broker: moves the stock portfolio. Warp: teleport (replaces the roll). Order: bends the turn order.
## Destiny: the Fate die (lose / win gold, or a detour back 3 tiles).
## Returns "" on success or the reason it failed.
func use_special_die(index: int) -> String:
	if state != State.AWAIT_ROLL:
		return "Special Dice can only be used before rolling."
	var p := current_player()
	if index < 0 or index >= p.special_dice.size():
		return "No such die."
	var def := GameData.get_special_die(p.special_dice[index])
	p.special_dice.remove_at(index)
	var face = (def["faces"] as Array)[rng.randi() % 6]
	stats["special_dice"] += 1
	_log("%s rolls the %s: %s." % [p.display_name, def["name"], str(face)])
	match String(def["kind"]):
		"move":
			p.move_bonus = int(face)
		"steal":
			_special_steal(p, int(face))
		"land_gold":  # Sylvaris Harvest Die: face x owned territories
			var n := _owned_land_count(p)
			p.gold += int(face) * n
			_log("%s reaps %d G from %d territories." % [p.display_name, int(face) * n, n])
		"levy":  # Aetherion Decree / Drakmor Warlord Die: rivals pay the face; a negative face is a failure that costs the user
			if int(face) < 0:
				_log("The decree fails! %s pays %d G." % [p.display_name, -int(face)])
				_pay(p, -int(face), -1, "failed decree")
			elif int(face) > 0:
				_collect_from_rivals(p, int(face), "levy")
		"tokens":
			p.reroll_tokens += int(face)
		"gold":  # plain gold die: a negative face is paid
			if int(face) >= 0:
				p.gold += int(face)
			else:
				_pay(p, -int(face), -1, "die")
		"heal":
			var max_life := int(GameData.b("start_life"))
			if p.life < max_life:
				p.life = mini(max_life, p.life + int(face))
				_log("%s recovers %d Life (now %d)." % [p.display_name, int(face), p.life])
		"stock":
			if p.stock_value <= 0:
				p.stock_value = 100
				p.stock_basis = 100
				_log("%s receives a free 100 G stake in the market." % p.display_name)
			p.stock_value = maxi(0, int(round(float(p.stock_value) * (1.0 + float(int(face)) / 100.0))))
			_log("%s's portfolio moves %+d%% (now %d G)." % [p.display_name, int(face), p.stock_value])
		"order":
			match String(face):
				"extra_roll":
					_extra_roll = true
				"skip_next":
					var n := players.size()
					for i in range(1, n):
						var q := players[(current + i) % n]
						if q.alive and not is_ally(current, q.id):
							q.skip_turns += 1
							_log("%s will skip their next turn." % q.display_name)
							break
				"token":
					p.reroll_tokens += 1
				"gold":
					p.gold += 50
		"teleport":
			_special_teleport(p, String(face))
			return ""
		"fate":
			_resolve_fate(p, int(face), def.get("fate_values", []))
			if int(face) == 3:  # the detour moved the ruler: resolve like a teleport and end the roll
				_roll_was_double = false
				_finish_landing()
				return ""
	players_changed.emit()
	state_changed.emit()
	return ""


## Thief Die: takes gold from the richest living rival (never a teammate). A negative face = caught, pay a fine.
func _special_steal(p: PlayerState, face: int) -> void:
	if face < 0:
		_log("%s is caught red-handed!" % p.display_name)
		_pay(p, -face, -1, "fine")
		return
	var victim: PlayerState = null
	for q in players:
		if q.alive and q.id != p.id and not is_ally(q.id, p.id):
			if victim == null or q.gold > victim.gold:
				victim = q
	if victim == null:
		return
	_pay(victim, face, p.id, "theft")


func _special_teleport(p: PlayerState, face: String) -> void:
	var dest := -1
	var lands: Array[int] = []
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY:
			lands.append(t.index)
	match face:
		"portal":
			var act := PortalSystem.active_indices(tiles)
			act.erase(p.position)
			if not act.is_empty():
				dest = act[rng.randi() % act.size()]
		"start":
			dest = 0
	if dest < 0:
		dest = lands[rng.randi() % lands.size()]
	_warp(p, dest, "Warp Die")
	if dest == 0:
		_give_start_bonus(p)
	_roll_was_double = false
	_chain_depth = 0
	_resolve_landing(p)
	_finish_landing()
