class_name UpdateCheck
extends Node
## Checks the latest GitHub Release and tells the main menu when a newer APK exists.
## Android cannot install an APK silently: the game downloads it itself (UpdateInstaller) and opens the installer; the player confirms once.
## Release asset: MultiverseDominion.apk. Version = ProjectSettings application/config/version (set by CI).

signal update_available(version: String, apk_url: String, notes: String)
## Always fires once per check(): status = "available" | "current" | "error" (offline, rate limit, no release yet).
## Lets the caller retry later after an error (the menu) or tell the player what happened (Settings).
signal check_finished(status: String, info: Dictionary)

const REPO := "regi4nt/MultiverseDominion"
const API := "https://api.github.com/repos/%s/releases/latest"
const PAGE := "https://github.com/%s/releases/latest"
const APK_NAME := "MultiverseDominion.apk"
const NOTES_MAX := 360

var _http: HTTPRequest
var _done: bool = false


static func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## "v0.7.12" -> [0,7,12]; garbage -> [].
static func parse_version(v: String) -> Array:
	var s := v.strip_edges().trim_prefix("v").trim_prefix("V")
	var out := []
	for part in s.split("."):
		if not part.is_valid_int():
			return []
		out.append(int(part))
	return out


static func is_newer(remote: String, local: String) -> bool:
	var a := parse_version(remote)
	var b := parse_version(local)
	if a.is_empty() or b.is_empty():
		return false
	for i in range(maxi(a.size(), b.size())):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return x > y
	return false


## Picks the data we need out of a GitHub "latest release" JSON. Returns {} when there is no usable APK.
## Prefers the asset named exactly MultiverseDominion.apk (so a stray extra .apk can never be picked).
static func parse_release(rel: Variant) -> Dictionary:
	if not (rel is Dictionary):
		return {}
	var url := ""
	var fallback := ""
	for asset in rel.get("assets", []):
		if not (asset is Dictionary):
			continue
		var asset_name := str(asset.get("name", ""))
		if not asset_name.ends_with(".apk"):
			continue
		var u := str(asset.get("browser_download_url", ""))
		if u == "":
			continue
		if asset_name == APK_NAME:
			url = u
			break
		if fallback == "":
			fallback = u
	if url == "":
		url = fallback
	var tag = rel.get("tag_name", "")
	if url == "" or tag == null or str(tag) == "":
		return {}
	var body = rel.get("body", "")  # JSON null (a release without notes) must not become the text "<null>"
	var page = rel.get("html_url", "")
	return {
		"version": str(tag).trim_prefix("v"),
		"apk_url": url,
		"notes": "" if body == null else str(body),
		"page_url": (PAGE % REPO) if (page == null or str(page) == "") else str(page),
	}


## GitHub's auto-generated notes ("## What's Changed", "* Fix x by @user in https://...", "**Full Changelog**: ...")
## turned into a few readable lines, cut at a line boundary instead of in the middle of a word.
static func clean_notes(body: String, max_chars: int = NOTES_MAX) -> String:
	var lines: Array[String] = []
	for raw in body.replace("\r", "").split("\n"):
		var l := raw.strip_edges()
		if l == "" or l.begins_with("#") or l.to_lower().begins_with("**full changelog") or l.to_lower().begins_with("full changelog"):
			continue
		if l.begins_with("* ") or l.begins_with("- "):
			l = "- " + l.substr(2)
		var by := l.find(" by @")
		if by > 0:
			l = l.substr(0, by)
		lines.append(l)
	var out := ""
	for l in lines:
		var next: String = l if out == "" else out + "\n" + l
		if next.length() > max_chars:
			out += "\n..." if out != "" else l.left(max_chars) + "..."
			break
		out = next
	return out


## "Skip this version": remembered in the save so the automatic check stays quiet until a NEWER version appears.
static func is_skipped(version: String) -> bool:
	var sk = SaveManager.get_setting("skipped_update")
	return sk != null and str(sk) == version


## The update dialog, shared by the main menu (automatic) and Settings (manual). `can_skip` adds "Skip this version".
static func show_dialog(parent: Node, info: Dictionary, can_skip: bool) -> void:
	var version := String(info.get("version", ""))
	var dlg := UiDialog.new()
	dlg.title = "Update available"
	var notes := clean_notes(String(info.get("notes", "")))
	var in_app := OS.get_name() == "Android"
	dlg.dialog_text = "Version %s is available (you have %s).%s\n\n%s" % [
		version, current_version(), ("\n\n" + notes) if notes != "" else "",
		"It downloads inside the game, then Android asks you to confirm the install.\nIf Android asks, allow installing from this app." if in_app else "Download it, then open the downloaded file to install."]
	dlg.ok_button_text = "Update now" if in_app else "Download"
	dlg.cancel_button_text = "Later"
	dlg.confirmed.connect(func():
		if in_app:
			start_in_app_update(parent, info)
		else:
			open_in_browser(info))
	if can_skip:
		dlg.add_button("Skip this version", false, "skip")
		dlg.custom_action.connect(func(action: StringName):
			if action == &"skip":
				SaveManager.set_setting("skipped_update", version)
				dlg.hide())
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.custom_action.connect(func(_a: StringName): dlg.queue_free())
	parent.add_child(dlg)
	dlg.popup_centered(Vector2i(600, 380))


## Fallback: the direct APK link first; if the phone cannot open it, the release page.
static func open_in_browser(info: Dictionary) -> void:
	if OS.shell_open(String(info.get("apk_url", ""))) != OK:
		OS.shell_open(String(info.get("page_url", PAGE % REPO)))


## In-game update: a progress dialog while the APK downloads, then Android's installer opens. Any failure
## (offline, refused install) offers the browser download instead, so the player is never stuck.
static func start_in_app_update(parent: Node, info: Dictionary) -> void:
	var inst := UpdateInstaller.new()
	parent.add_child(inst)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var lbl := UiTheme.make_label("Starting download...", 18)
	box.add_child(lbl)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 28)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	box.add_child(bar)
	var dlg := UiDialog.new()
	dlg.title = "Updating to %s" % String(info.get("version", ""))
	dlg.body_node = box
	dlg.ok_button_text = "Hide"  # the download keeps going in the background
	dlg.cancel_button_text = "Cancel"
	dlg.dismiss_on_backdrop = false
	dlg.show_cancel = true
	parent.add_child(dlg)
	dlg.popup_centered(Vector2i(600, 0))
	inst.progress.connect(func(done: int, total: int):
		if total > 0:
			bar.value = 100.0 * float(done) / float(total)
			lbl.text = "Downloading... %.1f / %.1f MB" % [done / 1048576.0, total / 1048576.0]
		else:
			lbl.text = "Downloading... %.1f MB" % (done / 1048576.0))
	dlg.canceled.connect(func():
		inst.cancel()
		inst.queue_free()
		dlg.queue_free())
	inst.finished.connect(func(ok: bool, error: String):
		if is_instance_valid(dlg):
			dlg.hide()
			dlg.queue_free()
		if ok and inst.install():
			inst.queue_free()
			return
		inst.queue_free()
		var fb := UiDialog.new()
		fb.title = "Could not update in the game"
		fb.tone = "warn"
		fb.dialog_text = "%s\n\nOpen the download in your browser instead?" % (error if not ok else "Android did not open the installer.")
		fb.ok_button_text = "Open browser"
		fb.cancel_button_text = "Later"
		fb.confirmed.connect(func(): open_in_browser(info))
		fb.confirmed.connect(fb.queue_free)
		fb.canceled.connect(fb.queue_free)
		parent.add_child(fb)
		fb.popup_centered(Vector2i(600, 0)))
	inst.start(String(info.get("apk_url", "")))


func check() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	if _http.request(API % REPO, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: MultiverseDominion"])) != OK:
		_finish("error", {})


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish("error", {})  # offline / timeout
		return
	if code == 404:
		_finish("current", {})  # no release published yet: nothing to update to
		return
	if code != 200:
		_finish("error", {})  # 403 / 429 rate limit, 5xx
		return
	var j := JSON.new()
	if j.parse(body.get_string_from_utf8()) != OK:
		_finish("error", {})
		return
	var rel := parse_release(j.data)
	if rel.is_empty():
		_finish("current", {})  # a release without an APK is not an update
	elif is_newer(rel["version"], current_version()):
		_finish("available", rel)
	else:
		_finish("current", rel)


func _finish(status: String, info: Dictionary) -> void:
	if _done:
		return
	_done = true
	if status == "available":
		update_available.emit(info["version"], info["apk_url"], info["notes"])
	check_finished.emit(status, info)
	queue_free()
