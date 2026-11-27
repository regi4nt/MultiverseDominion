class_name ChessMove
extends RefCounted
## Real-chess MOVEMENT and chess-pattern ATTACKS on the 8x8 Battle Board (pure functions, shared by the engine and the UI).
## Attack = near (8 cells around) for every piece, plus far along the piece's chess pattern for Rook, Knight, Bishop and Queen (see capture_cells).
##   Rook    slides along rows / columns, any distance (SLIDE), stopped by the first unit or wall (it hits that unit if it is an enemy).
##   Bishop  slides along diagonals, same rule.
##   Queen   rook + bishop.
##   King    one cell in any direction (moves and hits).
##   Knight  L-jump (2+1), leaps over units and walls; moves to a free cell, hits an enemy on a jump cell.
##   Pawn    moves straight ahead (2 cells on its first move) ("ahead" = towards the enemy half); hits near only.
##           Only exception to chess, so two pawns facing each other never lock up: when the cell ahead is blocked (or the board ends)
##           a pawn may sidestep one cell sideways.
## `move` of move_cells is the number of cells of ONE slide; use steps_for() to get it for a piece.
const SLIDE := 7

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
		_:  # pawn (and anything unknown): straight ahead only; a sidestep when the way ahead is shut (never stuck, never locked head-on)
			var fwd := -1 if side == 0 else 1
			_slide(out, from, [Vector2i(0, fwd)], move, blocked)
			var ahead := from + Vector2i(0, fwd)
			if not in_bounds(ahead) or blocked.call(ahead):
				for dx in [-1, 1]:
					var c := from + Vector2i(dx, 0)
					if in_bounds(c) and not blocked.call(c):
						out.append(c)
	return out


## Cells of ONE slide / step for a piece: sliders go the whole board, a pawn 1 (2 on its first move), a knight / king as given.
static func steps_for(chess: String, move: int, moved: bool) -> int:
	match chess:
		"rook", "bishop", "queen":
			return SLIDE
		"king":
			return 1
		"knight":
			return maxi(move, 1)
		_:
			return maxi(move, 1) + (0 if moved else 1)


## Cells the piece hits from `from`. Every piece hits NEAR (the 8 cells around it); Rook, Knight, Bishop and Queen also hit FAR along their chess pattern:
##   Pawn, King            near only
##   Rook                  near + far along rows / columns (a slide stops at the first blocked cell, which is hit)
##   Bishop                near + far along diagonals (same rule)
##   Queen                 near + far along rows, columns and diagonals (same rule)
##   Knight                near + far on its L-jump cells (jumps over units)
## `blocked` = Callable(Vector2i) -> bool for units / walls (the engine ignores a wall as a target).
static func capture_cells(chess: String, from: Vector2i, _side: int, blocked: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in ORTHO + DIAG:  # near
		var n: Vector2i = from + d
		if in_bounds(n):
			out.append(n)
	match chess:
		"knight":
			for j in JUMPS:
				var c := from + j
				if in_bounds(c) and not out.has(c):
					out.append(c)
		"rook":
			_ray(out, from, ORTHO, blocked)
		"bishop":
			_ray(out, from, DIAG, blocked)
		"queen":
			_ray(out, from, ORTHO + DIAG, blocked)
	return out


static func can_capture(chess: String, from: Vector2i, to: Vector2i, side: int, blocked: Callable) -> bool:
	return capture_cells(chess, from, side, blocked).has(to)


## A ray: runs until the board ends or a blocked cell, which is the last cell of the ray (the one that is hit).
static func _ray(out: Array[Vector2i], from: Vector2i, dirs: Array, blocked: Callable) -> void:
	for d in dirs:
		var c: Vector2i = from
		for _i in range(SLIDE):
			c += d
			if not in_bounds(c):
				break
			if not out.has(c):
				out.append(c)
			if blocked.call(c):
				break


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
		"rook": return "Rook: slides along rows and columns. Hits near AND far (along its lines, to the first unit)"
		"bishop": return "Bishop: slides along diagonals. Hits near AND far (along its diagonals, to the first unit)"
		"queen": return "Queen: slides in any line. Hits near AND far (any line, to the first unit)"
		"king": return "King: 1 step any direction. Hits near only"
		"knight": return "Knight: L-jump, leaps over units. Hits near AND far (its jump cells)"
	return "Pawn: moves forward (2 on its first move), sidesteps when blocked. Hits near only"


## Very short form for cards: how the piece moves and hits.
static func tag(chess: String) -> String:
	match chess:
		"rook": return "Near + far (lines)"
		"bishop": return "Near + far (diagonals)"
		"queen": return "Near + far (any line)"
		"knight": return "Near + far (L-jump)"
		"king": return "Near only"
	return "Near only"
