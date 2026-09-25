class_name TargetLockIndicator
extends Node3D

## What the target lock holds, shown: a ring on the locked target, turned to
## face the camera and drawn through whatever stands in front of it, plus the
## `[KEY] Action` hint for letting go and switching while a lock is on.
##
## A view of PlayerTargeting and nothing more: it hears target_changed, follows
## the target it was told about, and never chooses one. One ring exists and is
## moved, like the shadow's command marker — a ring parented to its target
## would depend on the target to be cleaned up.
##
## PLACEHOLDER look until the UI pass (M13-M15).

const GROUP: StringName = &"target_lock_indicator"

@export var hint_unlock: String = "Sblocca bersaglio"
@export var hint_switch: String = "Cambia bersaglio"

@onready var ring: MeshInstance3D = $Ring
@onready var hint_layer: CanvasLayer = $HintLayer
@onready var hint_label: Label = $HintLayer/Root/HintLabel

var _targeting: PlayerTargeting = null
var _target: RoomCombatant = null


func _ready() -> void:
	add_to_group(GROUP)
	hint_label.text = "[%s] %s\n[%s] [%s] %s" % [
		InteractionPrompt.key_for(&"target_lock"), hint_unlock,
		InteractionPrompt.key_for(&"target_switch_left"),
		InteractionPrompt.key_for(&"target_switch_right"), hint_switch]
	_show(null)
	# One frame: the player comes up in the same scene and its components are
	# not resolved until its own _ready() has run.
	call_deferred("_subscribe")


func _subscribe() -> void:
	var player: Player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null or player.targeting == null:
		return
	_targeting = player.targeting
	_targeting.target_changed.connect(_show)
	_show(_targeting.get_target())


func get_target() -> RoomCombatant:
	return _target


func is_showing() -> bool:
	return visible


func get_hint_text() -> String:
	return hint_label.text


func _show(target: RoomCombatant) -> void:
	_target = target
	visible = target != null
	hint_layer.visible = visible
	set_process(visible)
	if visible:
		_place()


## Only runs while a target is held.
func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		_show(null)
		return
	_place()


func _place() -> void:
	global_position = _target.get_target_point()
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(global_position) > 0.01:
		look_at(camera.global_position, Vector3.UP)
