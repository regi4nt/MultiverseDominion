class_name UpdateInstaller
extends Node
## Downloads the new APK inside the game (with progress) and then hands it to Android's installer,
## so the player never has to leave the app for a browser. Android always shows its own "Update?" confirmation
## before replacing an app; that last tap cannot be skipped.

signal progress(done: int, total: int)
## ok = the file is fully downloaded (then call install()); otherwise `error` says why and the caller falls back to the browser.
signal finished(ok: bool, error: String)

## The install could not be started: reason "permission" (Install unknown apps is still off for this game) or "open" (Android refused the file).
signal install_failed(reason: String)

const MIN_APK_BYTES := 1_000_000  # an error page or a truncated file is never a real APK

var path := ""
var _http: HTTPRequest
var _active := false
var focused := true  # Android silently drops an installer launch from an app that is in the background
var _pending := false
var _asked := false


static func apk_path() -> String:
	return OS.get_user_data_dir().path_join("MultiverseDominion-update.apk")


func start(url: String) -> void:
	path = apk_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_http = HTTPRequest.new()
	_http.download_file = path
	_http.max_redirects = 10  # GitHub release assets redirect to a CDN
	_http.timeout = 0.0  # large file on a slow connection: no overall timeout, the Cancel button stops it
	add_child(_http)
	_http.request_completed.connect(_on_done)
	if _http.request(url, PackedStringArray(["User-Agent: MultiverseDominion"])) != OK:
		_finish(false, "Could not start the download.")
		return
	_active = true
	set_process(true)


func cancel() -> void:
	if _http != null:
		_http.cancel_request()
	_active = false
	set_process(false)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _process(_delta: float) -> void:
	if _active and _http != null:
		progress.emit(_http.get_downloaded_bytes(), _http.get_body_size())


## Content-Length of the response, or -1 when it is unknown or the body was sent compressed (the length would not match the file).
static func _expected_size(headers: PackedStringArray) -> int:
	var length := -1
	for h in headers:
		var low := h.to_lower()
		if low.begins_with("content-encoding:") and not low.contains("identity"):
			return -1
		if low.begins_with("content-length:"):
			length = int(low.substr(15).strip_edges())
	return length


func _on_done(result: int, code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish(false, "Download interrupted (check your connection).")
	elif code != 200:
		_finish(false, "The server answered %d." % code)
	else:
		var size := 0
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f != null:
				size = f.get_length()
		var expected := _expected_size(headers)
		if size < MIN_APK_BYTES or (expected > 0 and size != expected):  # a truncated download is never handed to the installer
			_finish(false, "The downloaded file is incomplete.")
		else:
			_finish(true, "")


func _finish(ok: bool, error: String) -> void:
	_active = false
	set_process(false)
	finished.emit(ok, error)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			focused = false
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED:
			focused = true
			_try_install()


## Android 8+: "Install unknown apps" must be allowed for this app (the same check StarrySound does). True when it cannot be asked.
static func can_install() -> bool:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return true
	var rt: Object = Engine.get_singleton("AndroidRuntime")
	var act: Object = rt.getActivity() if rt != null else null
	if act == null:
		return true
	var pm: Object = act.getPackageManager()
	if pm == null:
		return true
	return bool(pm.canRequestPackageInstalls())


## Starts the Android installer as soon as that can work: only while the game is in the foreground (a download that
## finishes while the player is in another app waits until they come back), and only once installs are allowed.
## If the permission is still missing after the player returns from Android's prompt, `install_failed("permission")` fires.
func install_when_possible() -> void:
	_pending = true
	_asked = false
	_try_install()


func _try_install() -> void:
	if not _pending or not focused or path == "":
		return
	if not can_install():
		if _asked:
			_pending = false
			install_failed.emit("permission")
			return
		_asked = true
		OS.shell_open("file://" + path)  # Android answers with its "allow installs from this app" screen
		return
	_pending = false
	if not install():
		install_failed.emit("open")


## Opens the downloaded APK with Android's package installer. Returns false if the phone refused to open it.
func install() -> bool:
	return OS.shell_open("file://" + path) == OK
