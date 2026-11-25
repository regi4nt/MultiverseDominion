class_name BoardBuilder
extends RefCounted
## Builds the perimeter board for a continent: 100 tiles (26x26 grid ring), or 40 tiles (11x11) in Chaos Mode.
## Per side (region): 24 non-corner tiles = 10 Territory, 1 Portal (the only teleport of the side),
## 2 Bank (gold investment / stock market), 1 Casino, 2 Shop, 3 Event, 1 Auction, 2 Tax, 2 Special.
## Plus 4 corners => 100 tiles.
## Totals: 40 Territory, 4 Portal, 8 Bank, 4 Casino, 8 Shop, 12 Event, 4 Auction, 8 Tax, 8 Special, 4 Corner.
## Chaos totals: 20 Territory, 0 Portal, 4 Event, 2 each of Bank / Tax / Special / Shop / Casino / Auction, 4 Corner.

##
## Chaos Mode: 40 tiles = 4 corners + 9 tiles per side, 5 Territories per region and NO Portal (see CHAOS_PATTERN_A / _B).
## The size lives in static vars so every script that walks the ring (BoardBuilder.tiles_total, .grid) follows the mode;
## MatchController sets it with configure() before it builds or loads a board.
const NORMAL_SIDE := 25
const CHAOS_SIDE := 10
const NORMAL_REGION_SIZE := 10
const CHAOS_REGION_SIZE := 5
static var chaos: bool = false
static var side_len: int = NORMAL_SIDE  # tiles from one corner to the next (the corner counts, so a side has side_len - 1 inner tiles)
static var tiles_total: int = NORMAL_SIDE * 4
static var grid: int = NORMAL_SIDE + 1  # tiles per row / column of the ring
static var region_size: int = NORMAL_REGION_SIZE  # territories per region (10 = Regional Dominion)
const SIDE_PATTERN: Array[String] = [
	"T", "T", "B", "T", "E", "T", "SH", "T", "X", "P", "T", "SP",
	"T", "E", "L", "T", "SH", "A", "T", "SP", "T", "X", "B", "E",
]
const CHAOS_PATTERN_A: Array[String] = ["T", "E", "T", "B", "T", "T", "T", "X", "SP"]
const CHAOS_PATTERN_B: Array[String] = ["T", "SH", "T", "L", "T", "T", "T", "A", "E"]
const CORNERS: Array[String] = ["start", "sanctuary", "rift", "crossroads"]
const CORNER_NAMES: Array[String] = ["Dominion Gate (START)", "Sanctuary", "The Rift", "Crossroads"]
const DEFAULT_REGION_NAMES: Array[String] = ["North", "East", "South", "West"]


## Switches the board size (Chaos Mode = 40 tiles). Call before build() / grid_pos() whenever a match is set up or loaded.
static func configure(is_chaos: bool) -> void:
	chaos = is_chaos
	side_len = CHAOS_SIDE if is_chaos else NORMAL_SIDE
	tiles_total = side_len * 4
	grid = side_len + 1
	region_size = CHAOS_REGION_SIZE if is_chaos else NORMAL_REGION_SIZE


## Territories of one region needed for the region's majority rent bonus (6 of 10; 3 of 5 in Chaos Mode).
static func majority_needed() -> int:
	var base := int(GameData.b("majority_threshold"))
	if region_size == NORMAL_REGION_SIZE:
		return base
	return clampi(ceili(float(base) / float(NORMAL_REGION_SIZE) * float(region_size)), 2, region_size)


static func side_pattern(side: int) -> Array[String]:
	if chaos:
		return CHAOS_PATTERN_A if side % 2 == 0 else CHAOS_PATTERN_B
	return SIDE_PATTERN


static func build(continent: Dictionary) -> Array[BoardTile]:
	var tiles: Array[BoardTile] = []
	var regions: Array = continent.get("regions", [])
	var prefixes: Array = continent.get("territory_prefixes", [])
	var order_counter: Array[int] = [0, 0, 0, 0]
	var portal_counter: Array[int] = [0, 0, 0, 0]

	for idx in range(tiles_total):
		var t := BoardTile.new()
		t.index = idx
		if idx % side_len == 0:
			var corner_i := int(idx / float(side_len))
			t.type = BoardTile.Type.CORNER
			t.corner_kind = CORNERS[corner_i]
			t.name = CORNER_NAMES[corner_i]
			tiles.append(t)
			continue

		var side := side_of(idx)
		var pos_in_side := (idx - 1) % side_len
		var region_name: String = DEFAULT_REGION_NAMES[side]
		var suffix: String = DEFAULT_REGION_NAMES[side]
		if side < regions.size():
			region_name = regions[side].get("name", region_name)
			suffix = regions[side].get("suffix", suffix)
		t.region = side

		match side_pattern(side)[pos_in_side]:
			"T":
				t.type = BoardTile.Type.TERRITORY
				var order := order_counter[side]
				order_counter[side] += 1
				t.region_order = order
				var prefix := "Lot"
				if prefixes.size() > 0:
					prefix = prefixes[order % prefixes.size()]
				t.name = "%s %s" % [prefix, suffix]
				t.price = int(GameData.b("territory_base_price")) + int(GameData.b("territory_price_step")) * order
				if chaos:  # 40 tiles: fewer, pricier lots so rent stays meaningful next to the Gate bonus
					t.price = int(round(float(t.price) * float(GameData.b("chaos_price_mult", 1.0))))
			"P":
				t.type = BoardTile.Type.PORTAL
				portal_counter[side] += 1
				t.name = "%s Portal %d" % [DEFAULT_REGION_NAMES[side], portal_counter[side]]
			"SH":
				t.type = BoardTile.Type.SHOP
				t.name = "Territory Shop (%s)" % region_name
			"E":
				t.type = BoardTile.Type.EVENT
				t.name = "Event (%s)" % region_name
			"A":
				t.type = BoardTile.Type.AUCTION
				t.name = "Auction House (%s)" % region_name
			"X":
				t.type = BoardTile.Type.TAX
				t.name = "Tax Collector (%s)" % region_name
			"SP":
				t.type = BoardTile.Type.SPECIAL
				t.name = "Special (%s)" % region_name
			"B":
				t.type = BoardTile.Type.BANK
				t.name = "Bank & Stocks (%s)" % region_name
			"L":
				t.type = BoardTile.Type.CASINO
				t.name = "Casino (%s)" % region_name
		tiles.append(t)
	return tiles


## Region index (0..3) of a non-corner tile.
static func side_of(idx: int) -> int:
	return int(floor(float(idx - 1) / float(side_len)))


## Position of a tile on the ring (grid x grid). Index 0 (START) = bottom-right corner, clockwise
## (the ring is laid out from the top-left, then rotated 180 degrees so the Dominion Gate sits bottom-right).
static func grid_pos(idx: int) -> Vector2i:
	var p := _ring_pos(idx)
	return Vector2i(side_len - p.x, side_len - p.y)


static func _ring_pos(idx: int) -> Vector2i:
	var n := side_len
	if idx <= n:
		return Vector2i(idx, 0)
	if idx <= n * 2:
		return Vector2i(n, idx - n)
	if idx <= n * 3:
		return Vector2i(n - (idx - n * 2), n)
	return Vector2i(0, n - (idx - n * 3))


static func count_types(tiles: Array[BoardTile]) -> Dictionary:
	var out := {}
	for t in tiles:
		var k := t.type_name()
		out[k] = int(out.get(k, 0)) + 1
	return out


static func region_color(continent: Dictionary, region: int) -> Color:
	var regions: Array = continent.get("regions", [])
	if region >= 0 and region < regions.size():
		return Color(regions[region].get("color", "#888888"))
	return Color("#888888")
