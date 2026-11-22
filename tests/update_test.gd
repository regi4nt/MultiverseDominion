extends Node
## Update checker: version comparison and release JSON parsing (no network).
## Run: godot --headless --path . res://tests/update_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok  - ", msg)


func _ready() -> void:
	check(UpdateCheck.is_newer("0.7.10", "0.7.9"), "0.7.10 > 0.7.9 (numeric, not text)")
	check(UpdateCheck.is_newer("v0.8.0", "0.7.99"), "v prefix and minor bump")
	check(not UpdateCheck.is_newer("0.7.9", "0.7.9"), "same version is not an update")
	check(not UpdateCheck.is_newer("0.7.1", "0.7.9"), "older is not an update")
	check(not UpdateCheck.is_newer("latest", "0.7.9"), "garbage version ignored")
	check(UpdateCheck.is_newer("1.0", "0.9.9"), "different length")
	check(UpdateCheck.current_version() != "", "app has a version: " + UpdateCheck.current_version())
	var rel := {"tag_name": "v0.7.5", "body": "notes", "assets": [
		{"name": "MultiverseDominion.aab", "browser_download_url": "https://x/a.aab"},
		{"name": "MultiverseDominion.apk", "browser_download_url": "https://x/a.apk"}]}
	var p := UpdateCheck.parse_release(rel)
	check(p.get("version", "") == "0.7.5" and p.get("apk_url", "") == "https://x/a.apk", "release parsed, APK picked over AAB")
	check(UpdateCheck.parse_release({"tag_name": "v1", "assets": []}).is_empty(), "release without APK ignored")
	check(UpdateCheck.parse_release("nope").is_empty(), "non-object ignored")
	print("UPDATE TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
