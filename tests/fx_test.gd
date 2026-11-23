extends Node
## Effects mode (Settings > Effects): default Pro, Lite switches animations off, setting persists in the save data.
## Run: godot --headless --path . res://tests/fx_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	check(SaveManager.default_data()["settings"]["effects"] == "pro", "default effects mode is Pro")
	SaveManager.set_setting("effects", "lite", false)
	check(FxMode.is_lite() and not FxMode.is_pro(), "Lite is active after choosing it")
	SaveManager.set_setting("effects", "pro", false)
	check(FxMode.is_pro() and not FxMode.is_lite(), "Pro is active after choosing it")
	SaveManager.set_setting("effects", "garbage", false)
	check(FxMode.mode() == FxMode.PRO, "an unknown value falls back to Pro")
	SaveManager.set_setting("effects", "pro", false)
	print("fx_test: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)
