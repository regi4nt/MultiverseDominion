class_name PortalSystem
extends RefCounted
## Portal tiles: ONE per region (4 on the board) = the only teleports. With a single socket per
## region it is always active (rotation keeps it on), so the 4 portals link the 4 sides.
## Single Continent Match: portals never leave the board.


static func sockets_in_region(tiles: Array[BoardTile], region: int) -> Array[BoardTile]:
	var out: Array[BoardTile] = []
	for t in tiles:
		if t.type == BoardTile.Type.PORTAL and t.region == region:
			out.append(t)
	return out


static func randomize_portals(tiles: Array[BoardTile], rng: RandomNumberGenerator) -> void:
	for region in range(4):
		var sockets := sockets_in_region(tiles, region)
		for s in sockets:
			s.portal_active = false
		_activate(sockets, WorldMods.portals_per_region, rng)


static func rotate_portals(tiles: Array[BoardTile], rng: RandomNumberGenerator) -> void:
	for region in range(4):
		var sockets := sockets_in_region(tiles, region)
		var candidates: Array[BoardTile] = []
		for s in sockets:
			if not s.portal_active:
				candidates.append(s)
			s.portal_active = false
		if candidates.size() < WorldMods.portals_per_region:
			candidates = sockets
		_activate(candidates, WorldMods.portals_per_region, rng)


static func _activate(pool: Array[BoardTile], count: int, rng: RandomNumberGenerator) -> void:
	var left: Array[BoardTile] = pool.duplicate()
	for i in range(mini(count, left.size())):
		left.pop_at(rng.randi() % left.size()).portal_active = true


static func active_indices(tiles: Array[BoardTile]) -> Array[int]:
	var out: Array[int] = []
	for t in tiles:
		if t.type == BoardTile.Type.PORTAL and t.portal_active:
			out.append(t.index)
	return out
