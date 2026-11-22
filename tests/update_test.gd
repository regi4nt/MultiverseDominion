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
	# --- release picking / null-safety
	var r2 := UpdateCheck.parse_release({"tag_name": "v0.7.9", "body": null, "html_url": "https://x/rel", "assets": [
		{"name": "other.apk", "browser_download_url": "https://x/other.apk"},
		{"name": "MultiverseDominion.apk", "browser_download_url": "https://x/main.apk"}]})
	check(r2.get("apk_url", "") == "https://x/main.apk", "the asset named MultiverseDominion.apk wins over another .apk")
	check(r2.get("notes", "x") == "", "null release body becomes empty notes, not '<null>'")
	check(r2.get("page_url", "") == "https://x/rel", "release page url kept for the fallback")
	check(UpdateCheck.parse_release({"tag_name": null, "assets": [{"name": "a.apk", "browser_download_url": "https://x/a.apk"}]}).is_empty(), "null tag ignored")
	# --- notes cleanup
	var raw := "## What's Changed\n* Fix dice by @regi4nt in https://github.com/x/pull/3\n* Faster board by @bob in https://github.com/x/pull/4\n\n**Full Changelog**: https://github.com/x/compare/v1...v2"
	var cn := UpdateCheck.clean_notes(raw)
	check(cn == "- Fix dice\n- Faster board", "auto notes cleaned: '%s'" % cn.replace("\n", "|"))
	check(UpdateCheck.clean_notes("").is_empty(), "empty notes stay empty")
	var long_notes := ""
	for i in range(60):
		long_notes += "* change number %d\n" % i
	var ln := UpdateCheck.clean_notes(long_notes, 100)
	check(ln.length() <= 110 and ln.ends_with("..."), "long notes cut at a line boundary")
	print("UPDATE TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
