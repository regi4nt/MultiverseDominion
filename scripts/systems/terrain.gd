class_name Terrain
extends RefCounted
## Battle Board terrain. A terrain map is a Dictionary {Vector2i: true} of HIGHLAND cells; every other cell is plains.
##   Plains    any unit (melee and ranged) can stand and walk there.
##   Highland  ranged units only (attack range >= MIN_RANGE). Ranged units standing there deal extra damage
##             (balance key highland_atk_bonus). Melee units can neither deploy on it, walk onto it nor be teleported onto it.
## The layout is drawn at random for every duel, mirrored top / bottom so both sides get the same ground.

const MIN_RANGE := 2
const PAIRS := 3  # mirrored pairs of highland cells (= 6 cells on the board)


## Random layout: PAIRS cells in the lower half (rows 4-6) plus their mirror image (rows 3-1). Rows 0 and 7 stay plains
## so the Champions always have somewhere to enter.
static func generate(rng: RandomNumberGenerator) -> Dictionary:
	var t := {}
	var guard := 0
	while t.size() < PAIRS * 2 and guard < 200:
		guard += 1
		var c := Vector2i(rng.randi_range(0, BattleEngine.COLS - 1), rng.randi_range(4, 6))
		if t.has(c):
			continue
		t[c] = true
		t[Vector2i(c.x, 7 - c.y)] = true
	return t


static func is_highland(terrain: Dictionary, cell: Vector2i) -> bool:
	return terrain.has(cell)


static func is_ranged(atk_range: int) -> bool:
	return atk_range >= MIN_RANGE


## Can a unit with this attack range stand on `cell`?
static func can_stand(terrain: Dictionary, atk_range: int, cell: Vector2i) -> bool:
	return not terrain.has(cell) or is_ranged(atk_range)
