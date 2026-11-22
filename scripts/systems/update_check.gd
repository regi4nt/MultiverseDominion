class_name UpdateCheck
extends Node
## Checks the latest GitHub Release and tells the main menu when a newer APK exists.
## Android cannot install an APK silently, so "update" = open the APK download; the user taps the downloaded file.
## Release asset: MultiverseDominion.apk. Version = ProjectSettings application/config/version (set by CI).

signal update_available(version: String, apk_url: String, notes: String)

const REPO := "regi4nt/MultiverseDominion"
const API := "https://api.github.com/repos/%s/releases/latest"
const PAGE := "https://github.com/%s/releases/latest"

var _http: HTTPRequest


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
static func parse_release(rel: Variant) -> Dictionary:
	if not (rel is Dictionary):
		return {}
	var url := ""
	for asset in rel.get("assets", []):
		if asset is Dictionary and str(asset.get("name", "")).ends_with(".apk"):
			url = str(asset.get("browser_download_url", ""))
			break
	if url == "" or str(rel.get("tag_name", "")) == "":
		return {}
	return {"version": str(rel["tag_name"]).trim_prefix("v"), "apk_url": url, "notes": str(rel.get("body", ""))}


func check() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	if _http.request(API % REPO, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: MultiverseDominion"])) != OK:
		queue_free()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var j := JSON.new()
		if j.parse(body.get_string_from_utf8()) == OK:
			var rel := parse_release(j.data)
			if not rel.is_empty() and is_newer(rel["version"], current_version()):
				update_available.emit(rel["version"], rel["apk_url"], rel["notes"])
	queue_free()  # any failure (offline, rate limit, no release yet) is silent
