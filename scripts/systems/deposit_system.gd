class_name DepositSystem
extends RefCounted
## Hidden territory deposits: treasures and mines.
## Every continent has its OWN 2 treasures and 2 mines (data/deposits.json), each lying on a RANDOM territory tile of the
## whole board (never on a monster lair, never two on one tile). They are never drawn on the map: a player only finds one
## by landing on its tile (no decision, the find is automatic).
##  - Treasure: one-time reward (gold, Reroll Tokens, sometimes a Special Die). Gone for everyone once found.
##  - Mine: belongs to whoever found it and pays `income` gold at the end of every round for `rounds` rounds
##    (optionally a Reroll Token every `token_every` payouts). A mine of a ruler who is eliminated pays nothing.
## An entry is {"tile": territory index, "id": deposit id, "taken": found?, "owner": player id or -1, "left": payouts left, "paid": payouts made}.


## Places the deposits of a continent. Uses its OWN generator so the main match rng stream is not disturbed.
## `avoid` = tile indices that must stay free (monster lairs).
static func place(tiles: Array[BoardTile], continent_id: String, rng: RandomNumberGenerator, avoid: Array = []) -> Array:
	var out: Array = []
	var cands: Array[int] = []
	for t in tiles:
		if t.type == BoardTile.Type.TERRITORY and not avoid.has(t.index):
			cands.append(t.index)
	for d in GameData.get_deposits(continent_id):
		if cands.is_empty():
			break
		var i := rng.randi() % cands.size()
		out.append({"tile": cands[i], "id": String(d["id"]), "taken": false, "owner": -1, "left": 0, "paid": 0})
		cands.remove_at(i)
	return out


## The deposit waiting on `tile_index` (empty dictionary if none / already found).
static func entry_at(entries: Array, tile_index: int) -> Dictionary:
	for e in entries:
		if int(e["tile"]) == tile_index and not bool(e["taken"]):
			return e
	return {}


## Active mines (found, still paying) of one player.
static func mines_of(entries: Array, player_id: int) -> Array:
	var out: Array = []
	for e in entries:
		if bool(e["taken"]) and int(e["owner"]) == player_id and int(e["left"]) > 0:
			var d := GameData.get_deposit(String(e["id"]))
			if String(d.get("kind", "")) == "mine":
				out.append(e)
	return out


## Gold per round of all active mines of a player.
static func income_of(entries: Array, player_id: int) -> int:
	var sum := 0
	for e in mines_of(entries, player_id):
		sum += int(GameData.get_deposit(String(e["id"])).get("income", 0))
	return sum


## One-line description for logs / UI.
static func summary(deposit_id: String) -> String:
	var d := GameData.get_deposit(deposit_id)
	if d.is_empty():
		return ""
	if String(d["kind"]) == "treasure":
		var parts: Array[String] = ["%d G" % int(d.get("gold", 0))]
		if int(d.get("tokens", 0)) > 0:
			parts.append("%d Reroll Token" % int(d["tokens"]))
		if bool(d.get("die", false)):
			parts.append("a Special Die")
		return "%s: %s" % [d["name"], " + ".join(parts)]
	var s := "%s: %d G per round for %d rounds" % [d["name"], int(d.get("income", 0)), int(d.get("rounds", 0))]
	if int(d.get("token_every", 0)) > 0:
		s += ", a Reroll Token every %d rounds" % int(d["token_every"])
	return s
