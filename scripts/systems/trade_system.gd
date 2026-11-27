class_name TradeSystem
extends RefCounted
## Shop > Trading: a live market paid in Chips. Seven continent assets move all the time; buy with Chips, sell later.
## The price is a pure function of the real clock (slow waves + noise), so it keeps moving while the game is closed and
## reopening the Shop cannot "re-roll" the market. Positions live in SaveManager.data["trading"]; Chips are the wallet "chips".
## Selling pays value x (1 - FEE). No rules live in the UI: TradeChart / the Shop panel only draw and call these functions.

const FEE := 0.02  # taken from the value when selling
const BUYS: Array[int] = [50, 100, 250, 500]
const BUY_MIN := 50  # the Trading slider runs BUY_MIN .. BUY_MAX chips in steps of BUY_STEP (buy() itself accepts any amount)
const BUY_MAX := 10000
const BUY_STEP := 50
const RANGES := [["1m", 60.0], ["5m", 300.0], ["30m", 1800.0]]  # chart windows (label, seconds)
const ASSETS := [
	{"id": "aeth", "tag": "AETH", "name": "Aetherion Crown", "base": 120.0, "vol": 1.0, "seed": 1101, "color": Color("d4af37")},
	{"id": "arcn", "tag": "ARCN", "name": "Arcanum Rune", "base": 64.0, "vol": 1.3, "seed": 2203, "color": Color("a98be0")},
	{"id": "mach", "tag": "MACH", "name": "Machina Gear", "base": 210.0, "vol": 0.9, "seed": 3307, "color": Color("b8c4d6")},
	{"id": "sylv", "tag": "SYLV", "name": "Sylvaris Grove", "base": 48.0, "vol": 0.7, "seed": 4409, "color": Color("59cd90")},
	{"id": "drak", "tag": "DRAK", "name": "Drakmor Ember", "base": 85.0, "vol": 1.6, "seed": 5521, "color": Color("ff7a45")},
	{"id": "thal", "tag": "THAL", "name": "Thalassia Tide", "base": 150.0, "vol": 1.1, "seed": 6637, "color": Color("7fd8ff")},
	{"id": "eclp", "tag": "ECLP", "name": "Eclipsia Void", "base": 32.0, "vol": 1.8, "seed": 7741, "color": Color("c46bff")},
]


static func now() -> float:
	return Time.get_unix_time_from_system()


static func asset(id: String) -> Dictionary:
	for a in ASSETS:
		if String(a["id"]) == id:
			return a
	return {}


## Deterministic value in [-1, 1] for (seed, n).
static func _hash11(seed_v: int, n: int) -> float:
	var x := ((n * 73856093) ^ (seed_v * 19349663)) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 1274126177) & 0xFFFFFFFF
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 32767.5 - 1.0


## Smooth value noise: random points every `step` seconds, eased between them.
static func _noise(seed_v: int, t: float, step: float) -> float:
	var f := t / step
	var n := int(floor(f))
	var u := f - float(n)
	u = u * u * (3.0 - 2.0 * u)
	return lerpf(_hash11(seed_v, n), _hash11(seed_v, n + 1), u)


## Price of an asset at unix time `t` (always > 0).
static func price(id: String, t: float) -> float:
	var a := asset(id)
	if a.is_empty():
		return 0.0
	var s := int(a["seed"])
	var r := 0.10 * sin(TAU * t / 2820.0 + float(s % 628) / 100.0) \
		+ 0.06 * sin(TAU * t / 780.0 + float((s * 3) % 628) / 100.0) \
		+ 0.035 * sin(TAU * t / 222.0 + float((s * 7) % 628) / 100.0) \
		+ 0.012 * _noise(s, t, 4.0) + 0.02 * _noise(s + 7, t, 37.0)
	return maxf(1.0, float(a["base"]) * exp(r * float(a["vol"])))


## Percent change over the last `seconds`.
static func change_pct(id: String, t: float, seconds: float = 60.0) -> float:
	var p0 := price(id, t - seconds)
	return (price(id, t) / p0 - 1.0) * 100.0 if p0 > 0.0 else 0.0


static func _store() -> Dictionary:
	var d: Dictionary = SaveManager.data
	if not d.has("trading") or not (d["trading"] is Dictionary):
		d["trading"] = {}
	var s: Dictionary = d["trading"]
	if not s.has("pos") or not (s["pos"] is Dictionary):
		s["pos"] = {}
	if not s.has("realized"):
		s["realized"] = 0
	return s


## Open position of an asset: {"units": float, "cost": int (Chips paid)} or {} when none.
static func position(id: String) -> Dictionary:
	return (_store()["pos"] as Dictionary).get(id, {})


static func position_value(id: String, t: float = -1.0) -> int:
	var p := position(id)
	if p.is_empty():
		return 0
	return int(floor(float(p["units"]) * price(id, now() if t < 0.0 else t)))


## Chips the open position would pay right now after the fee.
static func sell_value(id: String, t: float = -1.0, fraction: float = 1.0) -> int:
	var p := position(id)
	if p.is_empty():
		return 0
	return int(floor(float(p["units"]) * fraction * price(id, now() if t < 0.0 else t) * (1.0 - FEE)))


static func portfolio_value(t: float = -1.0) -> int:
	var n := 0
	for a in ASSETS:
		n += position_value(String(a["id"]), t)
	return n


static func realized() -> int:
	return int(_store()["realized"])


## Buys `chips` Chips of an asset at the current price. {"ok", "error", "price", "units"}; nothing is paid when ok is false.
static func buy(id: String, chips: int, t: float = -1.0) -> Dictionary:
	var res := {"ok": false, "error": "", "price": 0.0, "units": 0.0, "chips": chips}
	if asset(id).is_empty():
		res["error"] = "Unknown asset."
		return res
	if chips <= 0:
		res["error"] = "Pick an amount."
		return res
	if not SaveManager.spend_currency("chips", chips):
		res["error"] = "Not enough Chips."
		return res
	var pr := price(id, now() if t < 0.0 else t)
	var units := float(chips) / pr
	var pos: Dictionary = position(id)
	if pos.is_empty():
		pos = {"units": 0.0, "cost": 0}
	pos["units"] = float(pos["units"]) + units
	pos["cost"] = int(pos["cost"]) + chips
	(_store()["pos"] as Dictionary)[id] = pos
	SaveManager.save_game()
	res["ok"] = true
	res["price"] = pr
	res["units"] = units
	return res


## Sells `fraction` (0..1] of the position. {"ok", "error", "payout", "cost", "net", "price"}: net = payout - the cost share sold.
static func sell(id: String, fraction: float = 1.0, t: float = -1.0) -> Dictionary:
	var res := {"ok": false, "error": "", "payout": 0, "cost": 0, "net": 0, "price": 0.0}
	var pos := position(id)
	if pos.is_empty():
		res["error"] = "You hold nothing."
		return res
	fraction = clampf(fraction, 0.01, 1.0)
	var pr := price(id, now() if t < 0.0 else t)
	var payout := int(floor(float(pos["units"]) * fraction * pr * (1.0 - FEE)))
	var cost_part := int(pos["cost"]) if fraction >= 0.999 else int(round(float(pos["cost"]) * fraction))
	if fraction >= 0.999:
		(_store()["pos"] as Dictionary).erase(id)
	else:
		pos["units"] = float(pos["units"]) * (1.0 - fraction)
		pos["cost"] = int(pos["cost"]) - cost_part
	SaveManager.add_currency("chips", payout)
	var s := _store()
	s["realized"] = int(s["realized"]) + payout - cost_part
	SaveManager.save_game()
	res["ok"] = true
	res["payout"] = payout
	res["cost"] = cost_part
	res["net"] = payout - cost_part
	res["price"] = pr
	return res
