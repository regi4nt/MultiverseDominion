extends Node
## Autoload "AppNav": Android Back button (and Esc on desktop).
## A scene can implement `on_back_requested()`; otherwise Back returns to the previous scene (history), falling back to the Main Menu.
## project.godot sets application/config/quit_on_go_back=false so the app never closes by accident.

const MENU := "res://scenes/main_menu/main_menu.tscn"
const MAX_HISTORY := 20

var _history: Array = []  # scene paths visited before the current one (newest last)
var _last_scene: Node = null
var _last_path: String = ""
var _going_back := false


func _ready() -> void:
	get_tree().root.go_back_requested.connect(go_back)


func _process(_delta: float) -> void:
	var cur := get_tree().current_scene
	if cur == null or cur == _last_scene:
		return
	if _last_path != "" and not _going_back and _last_path != cur.scene_file_path:
		_history.append(_last_path)
		if _history.size() > MAX_HISTORY:
			_history.pop_front()
	_going_back = false
	_last_scene = cur
	_last_path = cur.scene_file_path


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()


func go_back() -> void:
	# An open dialog (UiDialog) takes Back first: it closes like its Cancel button instead of stacking another dialog.
	for d in get_tree().get_nodes_in_group("ui_dialog"):
		if d.visible:
			d.dismiss()
			return
	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.has_method("on_back_requested"):
		scene.on_back_requested()
	else:
		go_previous_scene()


## Leave the current scene for the one before it (falls back to the Main Menu). For scenes' own `on_back_requested` too.
func go_previous_scene() -> void:
	var cur := get_tree().current_scene
	var target := MENU
	while not _history.is_empty():
		var p: String = _history.pop_back()
		if p != "" and p != cur.scene_file_path and ResourceLoader.exists(p):
			target = p
			break
	if cur.scene_file_path == target:
		return
	_going_back = true
	get_tree().change_scene_to_file(target)
