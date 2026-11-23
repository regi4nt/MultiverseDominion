class_name ChessMove
extends RefCounted
## Chess-style movement and attack areas on the 8x8 Battle Board (pure functions, shared by the engine and the UI).
##   Rook    slides along rows / columns, up to `move` cells, stopped by the first unit or wall.
##   Bishop  slides along diagonals, same rule.
##   Queen   rook + bishop.
##   King    one cell in any direction.
##   Knight  L-jump (2+1), leaps over units and walls, lands only on a free cell.
##   Pawn    straight ahead up to `move` cells, or one cell diagonally ahead / sideways ("ahead" = towards the enemy half).
## Attack area: every cell within `atk_range` (Chebyshev, the engine's range rule), without the unit's own cell.

const COLS := 8
const ROWS := 8
const ORTHO: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIAG: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const JUMPS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1),
	Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < COLS and c.y < ROWS


## Cells the piece can move to in ONE action. `blocked` is a Callable(Vector2i) -> bool (units / walls).
static func move_cells(chess: String, from: Vector2i, move: int, side: int, blocked: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match chess:
		"knight":
			for j in JUMPS:
				var c := from + j
				if in_bounds(c) and not blocked.call(c):
					out.append(c)
		"king":
			_slide(out, from, ORTHO + DIAG, 1, blocked)
		"rook":
			_slide(out, from, ORTHO, move, blocked)
		"bishop":
			_slide(out, from, DIAG, move, blocked)
		"queen":
			_slide(out, from, ORTHO + DIAG, move, blocked)
		_:  # pawn (and anything unknown)
			var fwd := -1 if side == 0 else 1
			_slide(out, from, [Vector2i(0, fwd)], move, blocked)
			for dx in [-1, 1]:
				for dy in [fwd, 0]:  # diagonal ahead, plus a sidestep so a pawn on the far row is never stuck
					var c := from + Vector2i(dx, dy)
					if in_bounds(c) and not blocked.call(c):
						out.append(c)
	return out


static func _slide(out: Array[Vector2i], from: Vector2i, dirs: Array, steps: int, blocked: Callable) -> void:
	for d in dirs:
		var c: Vector2i = from
		for _i in range(maxi(steps, 1)):
			c += d
			if not in_bounds(c) or blocked.call(c):
				break
			out.append(c)


## Cells the unit can hit from `from` (its own cell excluded).
static func attack_cells(from: Vector2i, atk_range: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(maxi(from.y - atk_range, 0), mini(from.y + atk_range, ROWS - 1) + 1):
		for x in range(maxi(from.x - atk_range, 0), mini(from.x + atk_range, COLS - 1) + 1):
			if Vector2i(x, y) != from:
				out.append(Vector2i(x, y))
	return out


## One-line description of how a piece moves (shown when a unit is selected).
static func describe(chess: String) -> String:
	match chess:
		"rook": return "Rook: slides in straight lines"
		"bishop": return "Bishop: slides diagonally"
		"queen": return "Queen: slides in any direction"
		"king": return "King: 1 step any direction"
		"knight": return "Knight: L-jump, leaps over units"
	return "Pawn: forward, or 1 step diagonal / sideways"
