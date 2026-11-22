class_name PortraitView
extends Control
## Champion portrait: a heraldic shield in the faction colour with the continent emblem.

var champion_id: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(120, 140)


func setup(id: String) -> void:
	champion_id = id
	queue_redraw()


func _draw() -> void:
	var ch := GameData.get_champion(champion_id)
	if ch.is_empty():
		return
	var cont := GameData.get_continent(String(ch["continent"]))
	var fcol := Color("777788")
	for f in cont.get("factions", []):
		if f["id"] == ch["faction"]:
			fcol = Color(f["color"])
	var s := minf(size.x, size.y * 0.86)
	var origin := Vector2((size.x - s) * 0.5, 0.0)
	var box := Rect2(origin, Vector2(s, s * 1.16))
	var shield := PackedVector2Array()
	for p in [[0.06, 0.06], [0.94, 0.06], [0.94, 0.52], [0.5, 0.98], [0.06, 0.52]]:
		shield.append(box.position + Vector2(p[0] * box.size.x, p[1] * box.size.y))
	draw_colored_polygon(shield, fcol.darkened(0.55))
	var inner := PackedVector2Array()
	for p in [[0.14, 0.13], [0.86, 0.13], [0.86, 0.5], [0.5, 0.88], [0.14, 0.5]]:
		inner.append(box.position + Vector2(p[0] * box.size.x, p[1] * box.size.y))
	draw_colored_polygon(inner, fcol.darkened(0.25))
	var closed := shield.duplicate()
	closed.append(shield[0])
	draw_polyline(closed, UiTheme.COL_GOLD, 3.0)
	var em := Rect2(box.position + Vector2(box.size.x * 0.22, box.size.y * 0.16), Vector2(box.size.x * 0.56, box.size.x * 0.56))
	draw_emblem_safe(em, String(ch["continent"]), fcol.lightened(0.55), fcol.darkened(0.5))


func draw_emblem_safe(r: Rect2, continent: String, col: Color, detail: Color) -> void:
	Art.draw_emblem(self, continent, r, col, detail)
