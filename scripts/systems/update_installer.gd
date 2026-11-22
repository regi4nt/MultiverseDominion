class_name UpdateInstaller
extends Node
## Downloads the new APK inside the game (with progress) and then hands it to Android's installer,
## so the player never has to leave the app for a browser. Android always shows its own "Update?" confirmation
## before replacing an app; that last tap cannot be skipped.

signal progress(done: int, total: int)
## ok = the file is fully downloaded (then call install()); otherwise `error` says why and the caller falls back to the browser.
signal finished(ok: bool, error: String)

const MIN_APK_BYTES := 1_000_000  # an error page or a truncated file is never a real APK

var path := ""
var _http: HTTPRequest
var _active := false


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


func _on_done(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
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
		if size < MIN_APK_BYTES:
			_finish(false, "The downloaded file is incomplete.")
		else:
			_finish(true, "")


func _finish(ok: bool, error: String) -> void:
	_active = false
	set_process(false)
	finished.emit(ok, error)


## Opens the downloaded APK with Android's package installer. Returns false if the phone refused to open it.
func install() -> bool:
	return OS.shell_open("file://" + path) == OK
