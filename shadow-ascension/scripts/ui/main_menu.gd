class_name MainMenu
extends CanvasLayer

## The first thing the game shows. Two choices and a title — the vertical slice
## needs nothing else, and a settings screen with nothing to set would be a lie.
##
## It is a router, not a game scene: it holds no state, and everything it knows
## about the run is that the hub is where one starts.

signal play_requested
## Emitted before the application is asked to close, so a harness can watch the
## choice without the process going away underneath it.
signal quit_requested

const GROUP: StringName = &"main_menu"

@export_file("*.tscn") var hub_scene: String = "res://scenes/core/hub.tscn"
## Off in a test, where quitting would take the harness with it.
@export var quit_on_request: bool = true

@onready var play_button: Button = $Root/Panel/Content/PlayButton
@onready var quit_button: Button = $Root/Panel/Content/QuitButton

var _leaving: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	# The menu is played with a mouse; the hub takes the cursor back when the
	# camera rig comes up.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	play_button.pressed.connect(press_play)
	quit_button.pressed.connect(press_quit)
	play_button.grab_focus()


func get_title() -> String:
	return ($Root/Panel/Content/Title as Label).text


func press_play() -> void:
	if _leaving:
		return
	_leaving = true
	play_requested.emit()
	var transition: SceneTransition = SceneTransition.find_in(get_tree())
	if transition != null and transition.transition_to_scene(hub_scene):
		return
	# No transition in the scene: still go, just without the fade.
	get_tree().change_scene_to_file(hub_scene)


func press_quit() -> void:
	quit_requested.emit()
	if quit_on_request:
		get_tree().quit()
