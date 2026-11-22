class_name Art
extends RefCounted
## Procedural illustrations (no image files): chess-piece silhouettes, continent emblems,
## Support category icons. Everything is drawn into a SQUARE rect with simple polygons.


static func _p(ci: CanvasItem, pts: Array, r: Rect2, col: Color) -> void:
	var out := PackedVector2Array()
	for p in pts:
		out.append(r.position + Vector2(p[0] * r.size.x, p[1] * r.size.y))
	ci.draw_colored_polygon(out, col)


static func _r(ci: CanvasItem, x0: float, y0: float, x1: float, y1: float, r: Rect2, col: Color) -> void:
	ci.draw_rect(Rect2(r.position + Vector2(x0 * r.size.x, y0 * r.size.y), Vector2((x1 - x0) * r.size.x, (y1 - y0) * r.size.y)), col)


static func _c(ci: CanvasItem, cx: float, cy: float, rad: float, r: Rect2, col: Color) -> void:
	ci.draw_circle(r.position + Vector2(cx * r.size.x, cy * r.size.y), rad * minf(r.size.x, r.size.y), col)


static func _l(ci: CanvasItem, a: Vector2, b: Vector2, r: Rect2, col: Color, w: float) -> void:
	ci.draw_line(r.position + a * r.size, r.position + b * r.size, col, w)


## kind: pawn | rook | knight | bishop | queen | king
static func draw_piece(ci: CanvasItem, kind: String, r: Rect2, col: Color, detail: Color) -> void:
	match kind:
		"pawn":
			_c(ci, 0.5, 0.27, 0.14, r, col)
			_p(ci, [[0.42, 0.4], [0.58, 0.4], [0.68, 0.72], [0.32, 0.72]], r, col)
			_r(ci, 0.24, 0.72, 0.76, 0.84, r, col)
		"rook":
			_r(ci, 0.32, 0.38, 0.68, 0.76, r, col)
			_r(ci, 0.26, 0.3, 0.74, 0.4, r, col)
			for x in [0.26, 0.44, 0.62]:
				_r(ci, x, 0.16, x + 0.12, 0.3, r, col)
			_r(ci, 0.22, 0.76, 0.78, 0.86, r, col)
			_r(ci, 0.44, 0.5, 0.56, 0.64, r, detail)
		"knight":
			_p(ci, [[0.34, 0.86], [0.3, 0.6], [0.4, 0.4], [0.46, 0.2], [0.6, 0.26], [0.76, 0.5], [0.7, 0.58], [0.58, 0.52], [0.62, 0.7], [0.68, 0.86]], r, col)
			_p(ci, [[0.46, 0.2], [0.5, 0.08], [0.58, 0.24]], r, col)
			_c(ci, 0.56, 0.36, 0.035, r, detail)
			_r(ci, 0.26, 0.86, 0.74, 0.94, r, col)
		"bishop":
			_c(ci, 0.5, 0.12, 0.06, r, col)
			_p(ci, [[0.5, 0.16], [0.64, 0.3], [0.66, 0.5], [0.58, 0.66], [0.42, 0.66], [0.34, 0.5], [0.36, 0.3]], r, col)
			_l(ci, Vector2(0.48, 0.3), Vector2(0.56, 0.46), r, detail, maxf(2.0, r.size.x * 0.045))
			_r(ci, 0.34, 0.66, 0.66, 0.72, r, col)
			_p(ci, [[0.38, 0.72], [0.62, 0.72], [0.7, 0.86], [0.3, 0.86]], r, col)
		"queen":
			_p(ci, [[0.24, 0.64], [0.18, 0.3], [0.34, 0.46], [0.5, 0.2], [0.66, 0.46], [0.82, 0.3], [0.76, 0.64]], r, col)
			for pos in [Vector2(0.18, 0.26), Vector2(0.5, 0.16), Vector2(0.82, 0.26)]:
				_c(ci, pos.x, pos.y, 0.055, r, col)
			_r(ci, 0.3, 0.64, 0.7, 0.78, r, col)
			_r(ci, 0.24, 0.78, 0.76, 0.88, r, col)
		"king":
			_r(ci, 0.46, 0.05, 0.54, 0.27, r, col)
			_r(ci, 0.38, 0.12, 0.62, 0.19, r, col)
			_p(ci, [[0.34, 0.3], [0.66, 0.3], [0.74, 0.72], [0.26, 0.72]], r, col)
			_r(ci, 0.22, 0.72, 0.78, 0.86, r, col)
			_c(ci, 0.5, 0.5, 0.06, r, detail)


## Emblem of a continent.
static func draw_emblem(ci: CanvasItem, continent_id: String, r: Rect2, col: Color, detail: Color) -> void:
	match continent_id:
		"aetherion":
			draw_piece(ci, "queen", r, col, detail)
		"arcanum":
			var pts: Array = []
			for i in range(16):
				var ang := TAU * i / 16.0 - PI / 2.0
				var rad := 0.44 if i % 2 == 0 else 0.17
				pts.append([0.5 + cos(ang) * rad, 0.5 + sin(ang) * rad])
			_p(ci, pts, r, col)
		"machina":
			_c(ci, 0.5, 0.5, 0.28, r, col)
			for i in range(8):
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				var c0 := Vector2(0.5, 0.5) + d * 0.26
				var c1 := Vector2(0.5, 0.5) + d * 0.43
				_p(ci, [[(c0 + n * 0.07).x, (c0 + n * 0.07).y], [(c1 + n * 0.06).x, (c1 + n * 0.06).y], [(c1 - n * 0.06).x, (c1 - n * 0.06).y], [(c0 - n * 0.07).x, (c0 - n * 0.07).y]], r, col)
			_c(ci, 0.5, 0.5, 0.11, r, detail)
		"sylvaris":
			var up: Array = []
			var down: Array = []
			var a0 := Vector2(0.18, 0.82)
			var a1 := Vector2(0.82, 0.18)
			var nrm := Vector2(0.707, 0.707)
			for i in range(0, 13):
				var t := i / 12.0
				var base := a0.lerp(a1, t)
				var off := sin(PI * t) * 0.2
				up.append([base.x + nrm.x * off, base.y + nrm.y * off])
				down.push_front([base.x - nrm.x * off, base.y - nrm.y * off])
			up.append_array(down)
			_p(ci, up, r, col)
			_l(ci, Vector2(0.2, 0.8), Vector2(0.8, 0.2), r, detail, maxf(2.0, r.size.x * 0.035))
		"drakmor":
			_p(ci, [[0.16, 0.16], [0.4, 0.2], [0.28, 0.86]], r, col)
			_p(ci, [[0.84, 0.16], [0.6, 0.2], [0.72, 0.86]], r, col)
			_p(ci, [[0.5, 0.3], [0.58, 0.5], [0.5, 0.72], [0.42, 0.5]], r, col)
		"thalassia":
			for k in range(3):
				var pts2 := PackedVector2Array()
				for i in range(0, 21):
					var x := 0.12 + 0.76 * i / 20.0
					pts2.append(r.position + Vector2(x, 0.3 + k * 0.2 + sin(i / 20.0 * TAU * 1.5) * 0.06) * r.size)
				ci.draw_polyline(pts2, col, maxf(2.5, r.size.x * 0.07))
			_c(ci, 0.78, 0.2, 0.06, r, col)
		"eclipsia":
			_c(ci, 0.5, 0.5, 0.33, r, col)
			_c(ci, 0.6, 0.43, 0.29, r, detail)
			ci.draw_arc(r.position + Vector2(0.5, 0.5) * r.size, 0.45 * r.size.x, 0.0, TAU, 40, col, maxf(2.0, r.size.x * 0.035))
		_:
			draw_piece(ci, "king", r, col, detail)


## Icon of a Support category.
static func draw_category(ci: CanvasItem, category: String, r: Rect2, col: Color, detail: Color) -> void:
	match category:
		"Creation":
			_r(ci, 0.42, 0.16, 0.58, 0.84, r, col)
			_r(ci, 0.16, 0.42, 0.84, 0.58, r, col)
			_c(ci, 0.5, 0.5, 0.07, r, detail)
		"Transformation":
			var c := r.position + Vector2(0.5, 0.5) * r.size
			ci.draw_arc(c, 0.3 * r.size.x, 0.5, PI - 0.3, 24, col, maxf(3.0, r.size.x * 0.08))
			ci.draw_arc(c, 0.3 * r.size.x, PI + 0.5, TAU - 0.3, 24, col, maxf(3.0, r.size.x * 0.08))
			_p(ci, [[0.12, 0.5], [0.3, 0.5], [0.21, 0.66]], r, col)
			_p(ci, [[0.88, 0.5], [0.7, 0.5], [0.79, 0.34]], r, col)
		"Magic":
			_p(ci, [[0.5, 0.08], [0.58, 0.42], [0.92, 0.5], [0.58, 0.58], [0.5, 0.92], [0.42, 0.58], [0.08, 0.5], [0.42, 0.42]], r, col)
		"Artifact":
			_p(ci, [[0.3, 0.3], [0.7, 0.3], [0.86, 0.46], [0.5, 0.88], [0.14, 0.46]], r, col)
			_l(ci, Vector2(0.14, 0.46), Vector2(0.86, 0.46), r, detail, maxf(2.0, r.size.x * 0.03))
			_l(ci, Vector2(0.38, 0.3), Vector2(0.5, 0.88), r, detail, maxf(2.0, r.size.x * 0.03))
			_l(ci, Vector2(0.62, 0.3), Vector2(0.5, 0.88), r, detail, maxf(2.0, r.size.x * 0.03))
		"Skill":
			_p(ci, [[0.56, 0.08], [0.28, 0.54], [0.46, 0.54], [0.4, 0.92], [0.74, 0.4], [0.54, 0.4]], r, col)
		"Blessing":
			_c(ci, 0.5, 0.5, 0.2, r, col)
			for i in range(8):
				var a := TAU * i / 8.0
				_l(ci, Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.29, Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * 0.44, r, col, maxf(3.0, r.size.x * 0.06))
		"Contract":
			_r(ci, 0.26, 0.18, 0.74, 0.82, r, col)
			for y in [0.34, 0.48, 0.62]:
				_l(ci, Vector2(0.34, y), Vector2(0.66, y), r, detail, maxf(2.0, r.size.x * 0.035))
			_c(ci, 0.26, 0.18, 0.06, r, col)
			_c(ci, 0.74, 0.82, 0.06, r, col)
		_:
			_c(ci, 0.5, 0.5, 0.3, r, col)
