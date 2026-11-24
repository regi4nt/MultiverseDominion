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
	# Hide must not cancel: the download belongs to the SceneTree root, not to the screen that started it.
	await get_tree().process_frame  # the root is still busy setting up children inside _ready
	var screen := Control.new()
	add_child(screen)
	UpdateCheck.start_in_app_update(screen, {"version": "9.9.9", "apk_url": "http://127.0.0.1:9/x.apk", "page_url": ""})
	var inst: UpdateInstaller = UpdateCheck._running
	check(inst != null and inst.get_parent() == get_tree().root, "downloader is a child of the root, not of the screen")
	var dlg: UiDialog = UpdateCheck._progress_dlg
	check(dlg.visible, "progress dialog is shown")
	dlg.confirmed.emit()  # the Hide button
	dlg.hide()
	check(UpdateCheck._pill != null and is_instance_valid(UpdateCheck._running), "Hide keeps the download and shows a pill")
	screen.queue_free()  # the player leaves the screen
	check(is_instance_valid(UpdateCheck._running) and is_instance_valid(inst), "leaving the screen does not kill the download")
	UpdateCheck.start_in_app_update(self, {})
	check(UpdateCheck._progress_dlg == dlg and dlg.visible and UpdateCheck._pill == null, "starting again just re-opens the progress dialog")
	dlg.canceled.emit()  # Android Back
	check(is_instance_valid(UpdateCheck._running) and UpdateCheck._pill != null, "Android Back hides instead of cancelling")
	dlg.custom_action.emit(&"cancel")  # Cancel download
	check(UpdateCheck._running == null and UpdateCheck._pill == null, "Cancel download stops it and removes the pill")
	await get_tree().process_frame

	# Installer: waits for the foreground, reports a refused launch.
	var ins := UpdateInstaller.new()
	add_child(ins)
	check(UpdateInstaller.can_install(), "install permission is not asked off Android")
	ins.path = "/nonexistent/x.apk"
	var reasons: Array[String] = []
	ins.install_failed.connect(func(r: String): reasons.append(r))
	ins.focused = false
	ins.install_when_possible()
	check(reasons.is_empty() and ins._pending, "in the background the install waits")
	ins._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(ins.focused and not ins._pending, "coming back to the foreground starts it once")
	ins.queue_free()

	print("UPDATE TEST RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(0 if failures == 0 else 1)
