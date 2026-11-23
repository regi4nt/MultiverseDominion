class_name MapSkin
extends RefCounted
## Per-continent look of the Territory Board and the Battle Board (data/map_skins.json).
## A skin = palette + one procedural motif pattern (no image files, everything is drawn with _draw()):
##   marble (Aetherion) | runes (Arcanum) | gears (Machina) | leaves (Sylvaris) | embers (Drakmor) | waves (Thalassia) | stars (Eclipsia)
## Missing continents / keys fall back to the original look (DEFAULT_*), so nothing breaks without a skin.

const PATTERNS: Array[String] = ["marble", "runes", "gears", "leaves", "embers", "waves", "stars"]

const DEFAULT_TERRITORY := {
	"frame_bg": "0a0f21", "frame": "4a4126", "center_bg": "131a33", "center_border": "3d3822",
	"title": "d4af37", "title_dim": "8a7222", "tile": "1a2342", "tile_alt": "1a2342",
	"tint": "ffffff", "tint_amt": 0.0, "radius": 0.2, "pattern": "",
	"motif": "ffffff", "motif_a": 0.0, "emblem": "ffffff", "emblem_a": 0.0,
}
const DEFAULT_BATTLE := {
	"frame_bg": "090d1c", "frame": "4a4126", "mine_light": "1b2c52", "mine_dark": "182647",
	"foe_light": "3a2040", "foe_dark": "311a38", "radius": 0.12, "line": "c9a73a",
	"highland": "bfa65a", "highland_rim": "d9c27a", "wall": "5d6178", "wall_rim": "a9aec6", "pattern": "",
	"motif": "ffffff", "motif_a": 0.0, "emblem": "ffffff", "emblem_a": 0.0,
}
const DEFAULT_BACKDROP := {"top": "1a2350", "bottom": "060912"}

static var _cache: Dictionary = {}  # continent id -> resolved skin


## Resolved skin of a continent: {"territory": {...}, "battle": {...}, "backdrop": {...}}. Colours are Color objects,
## "radius" / "tint_amt" / "motif_a" / "emblem_a" are floats, "pattern" is a String.
static func get_skin(continent_id: String) -> Dictionary:
	if _cache.has(continent_id):
		return _cache[continent_id]
	var raw: Dictionary = GameData.get_map_skin(continent_id)
	var out := {
		"territory": _resolve(DEFAULT_TERRITORY, raw.get("territory", {})),
		"battle": _resolve(DEFAULT_BATTLE, raw.get("battle", {})),
		"backdrop": _resolve(DEFAULT_BACKDROP, raw.get("backdrop", {})),
	}
	_cache[continent_id] = out
	return out


## Forgets the resolved skins (tests that change the data).
static func clear_cache() -> void:
	_cache.clear()


static func _resolve(defaults: Dictionary, src: Dictionary) -> Dictionary:
	var out := {}
	for k in defaults:
		var d = defaults[k]
		var v = src.get(k, d)
		if k == "pattern":
			var pat := String(v)
			out[k] = pat if PATTERNS.has(pat) else ""
		elif typeof(d) == TYPE_STRING:
			out[k] = Color(String(v))
		else:
			out[k] = float(v)
	return out


## The motif colour of a section with its (low) alpha applied.
static func motif_color(section: Dictionary) -> Color:
	return Color(section["motif"], float(section["motif_a"]))


## Small procedural motif inside `r` (a territory tile / a battle cell). `seed_i` varies it from cell to cell
## deterministically, so redraws never flicker. Costs 2-8 draw calls; skipped when the cell is tiny.
static func draw_motif(ci: CanvasItem, pattern: String, r: Rect2, col: Color, seed_i: int) -> void:
	if pattern == "" or col.a <= 0.0 or minf(r.size.x, r.size.y) < 6.0:
		return
	var s := minf(r.size.x, r.size.y)
	var c := r.get_center()
	var w := maxf(1.0, s * 0.045)
	var v := absi(seed_i) % 3
	match pattern:
		"marble":  # two pale veins through the stone
			ci.draw_line(r.position + Vector2(0.12, 0.88) * r.size, r.position + Vector2(0.58, 0.3) * r.size, col, w)
			ci.draw_line(r.position + Vector2(0.4, 0.96) * r.size, r.position + Vector2(0.9, 0.46) * r.size, col, w * 0.8)
			if v == 0:
				ci.draw_line(r.position + Vector2(0.3, 0.62) * r.size, r.position + Vector2(0.16, 0.4) * r.size, col, w * 0.7)
		"runes":  # a tiny glyph
			match v:
				0:
					ci.draw_arc(c, s * 0.24, 0.0, TAU, 16, col, w)
					ci.draw_line(c + Vector2(-0.24, 0.0) * s, c + Vector2(0.24, 0.0) * s, col, w)
					ci.draw_line(c + Vector2(0.0, -0.24) * s, c + Vector2(0.0, 0.24) * s, col, w)
				1:
					ci.draw_polyline(PackedVector2Array([c + Vector2(0.0, -0.26) * s, c + Vector2(0.22, 0.2) * s, c + Vector2(-0.22, 0.2) * s, c + Vector2(0.0, -0.26) * s]), col, w)
					ci.draw_circle(c + Vector2(0.0, 0.04) * s, s * 0.04, col)
				_:
					ci.draw_line(c + Vector2(0.0, -0.28) * s, c + Vector2(0.0, 0.28) * s, col, w)
					ci.draw_line(c + Vector2(-0.16, -0.12) * s, c + Vector2(0.16, -0.12) * s, col, w)
					ci.draw_line(c + Vector2(-0.16, 0.12) * s, c + Vector2(0.16, 0.12) * s, col, w)
		"gears":  # a cog
			ci.draw_arc(c, s * 0.22, 0.0, TAU, 14, col, w)
			for i in range(6):
				var d := Vector2(cos(TAU * i / 6.0 + v * 0.2), sin(TAU * i / 6.0 + v * 0.2))
				ci.draw_line(c + d * s * 0.22, c + d * s * 0.34, col, w * 1.6)
			ci.draw_circle(c, s * 0.07, col)
		"leaves":  # a leaf turned a different way in every cell
			var ang := float(absi(seed_i) % 4) * PI * 0.5 + 0.6
			var ax := Vector2(cos(ang), sin(ang))
			var nx := Vector2(-ax.y, ax.x)
			var up := PackedVector2Array()
			var down := PackedVector2Array()
			for i in range(6):
				var t := i / 5.0
				var along := (t - 0.5) * s * 0.7
				var wid := sin(PI * t) * s * 0.15
				up.append(c + ax * along + nx * wid)
				down.insert(0, c + ax * along - nx * wid)
			up.append_array(down)
			ci.draw_colored_polygon(up, col)
			ci.draw_line(c - ax * s * 0.35, c + ax * s * 0.35, Color(col, minf(1.0, col.a * 1.8)), w * 0.8)
		"embers":  # a crack in the stone and two sparks
			var o := r.position
			ci.draw_polyline(PackedVector2Array([o + Vector2(0.15, 0.2 + 0.1 * v) * r.size, o + Vector2(0.38, 0.42) * r.size, o + Vector2(0.3, 0.6) * r.size, o + Vector2(0.62, 0.76) * r.size, o + Vector2(0.84, 0.7 - 0.1 * v) * r.size]), col, w * 1.2)
			ci.draw_circle(o + Vector2(0.72, 0.28) * r.size, s * 0.045, col)
			ci.draw_circle(o + Vector2(0.24, 0.82) * r.size, s * 0.035, col)
		"waves":  # two wave lines
			for k in range(2):
				var pts := PackedVector2Array()
				for i in range(9):
					var x := 0.12 + 0.76 * i / 8.0
					pts.append(r.position + Vector2(x, 0.4 + 0.24 * k + sin(i / 8.0 * TAU + v) * 0.07) * r.size)
				ci.draw_polyline(pts, col, w)
		"stars":  # a four-point star and a speck
			var sc := c + Vector2(float(v - 1) * 0.1, -float(v % 2) * 0.06) * s
			var outer := s * 0.2
			var inner := s * 0.06
			var star := PackedVector2Array()
			for i in range(8):
				var a := TAU * i / 8.0 - PI * 0.5
				var rad := outer if i % 2 == 0 else inner
				star.append(sc + Vector2(cos(a), sin(a)) * rad)
			ci.draw_colored_polygon(star, col)
			ci.draw_circle(r.position + Vector2(0.8, 0.82) * r.size, s * 0.03, col)


## Big faint continent emblem (Art.draw_emblem) used as a watermark behind the centre plate / over the battle cells.
static func draw_watermark(ci: CanvasItem, continent_id: String, r: Rect2, section: Dictionary, plate: Color) -> void:
	var a := float(section["emblem_a"])
	if a <= 0.0:
		return
	Art.draw_emblem(ci, continent_id, r, Color(section["emblem"], a), Color(plate, minf(1.0, a * 3.0)))
