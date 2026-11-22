extends Node
## Autoload "AppNav": Android Back button (and Esc on desktop).
## A scene can implement `on_back_requested()`; otherwise Back returns to the Main Menu.
## project.godot sets application/config/quit_on_go_back=false so the app never closes by accident.

const MENU := "res://scenes/main_menu/main_menu.tscn"


func _ready() -> void:
	get_tree().root.go_back_requested.connect(go_back)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()


func go_back() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.has_method("on_back_requested"):
		scene.on_back_requested()
	elif scene.scene_file_path != MENU:
		get_tree().change_scene_to_file(MENU)
