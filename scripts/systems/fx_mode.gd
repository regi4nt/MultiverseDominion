class_name FxMode
extends RefCounted
## Visual-effects mode (Settings > Effects).
##   Pro  = every animation (default): dice tumble, pawn hops, camera glide, attack lunge, fall rings, card reveals, fades.
##   Lite = information stays, decoration goes: results appear instantly, nothing tweens. Lighter on weak phones / batteries.

const LITE := "lite"
const PRO := "pro"


static func mode() -> String:
	var m = SaveManager.get_setting("effects")
	return LITE if m == LITE else PRO


static func is_lite() -> bool:
	return mode() == LITE


static func is_pro() -> bool:
	return mode() == PRO
