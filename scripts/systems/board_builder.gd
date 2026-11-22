class_name BoardBuilder
extends RefCounted
## Builds the 100-tile perimeter board (26x26 grid ring) for a continent.
## Per side (region): 24 non-corner tiles = 10 Territory, 4 Portal Socket, 2 Shop,
## 3 Event, 1 Auction, 2 Tax, 2 Special. Plus 4 corners => 100 tiles.
## Totals: 40 Territory, 16 Portal Socket, 8 Shop, 12 Event, 4 Auction, 8 Tax, 8 Special, 4 Corner.

const TILES_TOTAL := 100
const GRID := 26
const SIDE_PATTERN: Array[String] = [
	"T", "T", "P", "T", "E", "T", "SH", "T", "X", "P", "T", "SP",
	"T", "E", "P", "T", "SH", "A", "T", "SP", "T", "X", "P", "E",
]
const CORNERS: Array[String] = ["start", "sanctuary", "rift", "crossroads"]
const CORNER_NAMES: Array[String] = ["Dominion Gate (START)", "Sanctuary", "The Rift", "Crossroads"]
const DEFAULT_REGION_NAMES: Array[String] = ["North", "East", "South", "West"]


static func build(continent: Dictionary) -> Array[BoardTile]:
	var tiles: Array[BoardTile] = []
	var regions: Array = continent.get("regions", [])
	var prefixes: Array = continent.get("territory_prefixes", [])
	var order_counter: Array[int] = [0, 0, 0, 0]
	var portal_counter: Array[int] = [0, 0, 0, 0]

	for idx in range(TILES_TOTAL):
		var t := BoardTile.new()
		t.index = idx
		if idx % 25 == 0:
			var corner_i := int(idx / 25.0)
			t.type = BoardTile.Type.CORNER
			t.corner_kind = CORNERS[corner_i]
			t.name = CORNER_NAMES[corner_i]
			tiles.append(t)
			continue

		var side := side_of(idx)
		var pos_in_side := (idx - 1) % 25
		var region_name: String = DEFAULT_REGION_NAMES[side]
		var suffix: String = DEFAULT_REGION_NAMES[side]
		if side < regions.size():
			region_name = regions[side].get("name", region_name)
			suffix = regions[side].get("suffix", suffix)
		t.region = side

		match SIDE_PATTERN[pos_in_side]:
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
		tiles.append(t)
	return tiles


## Region index (0..3) of a non-corner tile.
static func side_of(idx: int) -> int:
	return int(floor((idx - 1) / 25.0))


## Position of a tile on the 26x26 ring. Index 0 = top-left corner, clockwise.
static func grid_pos(idx: int) -> Vector2i:
	if idx <= 25:
		return Vector2i(idx, 0)
	if idx <= 50:
		return Vector2i(25, idx - 25)
	if idx <= 75:
		return Vector2i(25 - (idx - 50), 25)
	return Vector2i(0, 25 - (idx - 75))


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
