class_name SceneTransition
extends CanvasLayer

## A per-scene fade curtain. Instance it once in any scene that needs to hand
## over to another one; it is deliberately NOT an autoload.
##
## Callers find it through the `scene_transition` group rather than a NodePath,
## so a scene can drop it in without rewiring anything.

signal transition_started(target_scene: String)
signal transition_finished(target_scene: String)

const GROUP: StringName = &"scene_transition"

@export var fade_duration: float = 0.35
## Fades up from black when the scene opens, so an incoming transition lands softly.
@export var fade_in_on_ready: bool = true
## Cleared by callers that want to observe a transition without actually
## swapping scenes (tests, previews). The fade still runs.
@export var perform_scene_change: bool = true

@onready var fade_rect: ColorRect = $FadeRect

var _busy: bool = false
var _tween: Tween = null


func _ready() -> void:
	add_to_group(GROUP)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if fade_in_on_ready:
		fade_rect.modulate.a = 1.0
		fade_rect.visible = true
		_fade_to(0.0)
	else:
		fade_rect.modulate.a = 0.0
		fade_rect.visible = false


## The transition belonging to `tree`, or null when the scene has none: a bare
## test bench, or a scene that hands over without a fade. The group name and the
## cast live here, with the class that owns them, instead of being copied into a
## private helper in every caller.
static func find_in(tree: SceneTree) -> SceneTransition:
	return tree.get_first_node_in_group(GROUP) as SceneTransition


## True while a fade is running. Callers must refuse to act while it is.
func is_busy() -> bool:
	return _busy


## Fades out and loads `scene_path`. Returns false if a transition is already
## running or the path is empty — the caller has not been queued, it was refused.
func transition_to_scene(scene_path: String) -> bool:
	if _busy or scene_path.is_empty():
		return false
	_run(scene_path, false)
	return true


## Same fade, but reloads whatever scene is current. Used by the death restart.
func reload_current_scene() -> bool:
	if _busy:
		return false
	_run("", true)
	return true


func _run(scene_path: String, reload: bool) -> void:
	_busy = true
	transition_started.emit(scene_path)
	fade_rect.visible = true
	await _fade_to(1.0)
	if perform_scene_change:
		if reload:
			get_tree().reload_current_scene()
		else:
			get_tree().change_scene_to_file(scene_path)
	transition_finished.emit(scene_path)
	# _busy stays true: this node dies with the outgoing scene, and while it is
	# still alive nothing else should be allowed to start another transition.


func _fade_to(alpha: float) -> Signal:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(fade_rect, "modulate:a", alpha, fade_duration)
	return _tween.finished
