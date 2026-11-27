extends Node
## Continent bonus on the corners (data/continents.json -> corner_bonus). Run: godot --headless --path . res://tests/corner_bonus_test.tscn

var failures := 0
const FACTION := {"aetherion": "solvaris", "arcanum": "astralis", "machina": "", "sylvaris": "", "drakmor": "", "thalassia": "", "eclipsia": ""}


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func new_match(cid: String, chaos: bool = false) -> MatchController:
	var cont: Dictionary = GameData.get_continent(cid)
	var fac := String(cont["factions"][0]["id"])
	var c := MatchController.new()
	c.setup({"continent_id": cid, "faction_id": fac, "difficulty": "normal", "ai_count": 3, "seed": 5, "all_ai": true, "chaos": chaos})
	return c


func corner(c: MatchController, kind: String) -> BoardTile:
	for t in c.tiles:
		if t.type == BoardTile.Type.CORNER and t.corner_kind == kind:
			return t
	return null


func land(c: MatchController, kind: String) -> PlayerState:
	var p := c.players[0]
	c.current = 0
	p.position = corner(c, kind).index
	c.state = MatchController.State.ROLLED
	c._resolve_landing(p)
	return p


func _ready() -> void:
	for cid in ["aetherion", "arcanum", "machina", "sylvaris", "drakmor", "thalassia", "eclipsia"]:
		var cont: Dictionary = GameData.get_continent(cid)
		var cb: Dictionary = cont.get("corner_bonus", {})
		check(cb.has("sanctuary") and cb.has("rift") and cb.has("crossroads"), "%s has a bonus for all three corners" % cid)
		for k in ["sanctuary", "rift", "crossroads"]:
			check(String(cb[k].get("text", "")) != "", "%s %s has tooltip text" % [cid, k])
	# Aetherion: +5 G per territory at the Sanctuary, Reroll Token at the Rift, warp to an owned territory at the Crossroads
	var c := new_match("aetherion")
	var owned := 0
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY and owned < 3:
			t.owner_id = 0
			owned += 1
	var g0 := c.players[0].gold
	land(c, "sanctuary")
	check(c.players[0].gold == g0 + int(GameData.b("sanctuary_bonus")) + 15, "Aetherion Sanctuary: base gold + 5 G per territory")
	var tk := c.players[0].reroll_tokens
	var p := land(c, "rift")
	check(p.reroll_tokens == tk + 1 and p.skip_turns == 1, "Aetherion Rift: still trapped, but +1 Reroll Token")
	p = land(c, "crossroads")
	check(c.tiles[p.position].type == BoardTile.Type.TERRITORY and c.tiles[p.position].owner_id == 0, "Aetherion Crossroads: warps to an owned territory")
	# Machina: Crossroads warps to a Shop
	c = new_match("machina")
	p = land(c, "crossroads")
	check(c.tiles[p.position].type == BoardTile.Type.SHOP, "Machina Crossroads: warps to a Shop")
	# Sylvaris: free upgrade at the Sanctuary-less Rift (needs an owned territory)
	c = new_match("sylvaris")
	var mine: BoardTile = null
	for t in c.tiles:
		if t.type == BoardTile.Type.TERRITORY:
			t.owner_id = 0
			t.level = 1
			mine = t
			break
	var gold_before := c.players[0].gold
	land(c, "rift")
	check(mine.level == 2 and c.players[0].gold == gold_before, "Sylvaris Rift: one territory upgraded for free")
	# Sylvaris Crossroads: free territory
	p = land(c, "crossroads")
	check(c.tiles[p.position].type == BoardTile.Type.TERRITORY and c.tiles[p.position].owner_id == -1 or c.pending.size() > 0, "Sylvaris Crossroads: warps to a free territory")
	# Eclipsia: the Rift skips no turn, Crossroads jumps 3 tiles
	c = new_match("eclipsia")
	p = land(c, "rift")
	check(p.skip_turns == 0, "Eclipsia Rift: no turn is skipped")
	var rift_idx := corner(c, "crossroads").index
	p = land(c, "crossroads")
	check(p.position != rift_idx, "Eclipsia Crossroads: the player moved away from the corner")
	# Thalassia: Crossroads lets the player choose a portal
	c = new_match("thalassia")
	p = land(c, "crossroads")
	check(String(c.pending.get("type", "")) == "portal" and (c.pending["options"] as Array).size() > 0, "Thalassia Crossroads: a portal choice is offered")
	c.decide(int(c.pending["options"][0]))
	check(c.tiles[c.players[0].position].type == BoardTile.Type.PORTAL, "Thalassia Crossroads: the chosen portal is reached")
	# Chaos (no portals): Thalassia falls back to a random warp, never a stuck pending choice
	c = new_match("thalassia", true)
	p = land(c, "crossroads")
	check(c.pending.is_empty() or String(c.pending.get("type", "")) != "portal", "Thalassia Crossroads in Chaos: no portal choice, random warp")
	# the tooltip shows the bonus
	c = new_match("arcanum")
	check(c._corner_text("sanctuary").contains("Continent bonus"), "corner tooltip names the continent bonus")
	print("CORNER BONUS TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
