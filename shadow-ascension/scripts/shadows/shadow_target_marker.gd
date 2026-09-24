class_name ShadowTargetMarker
extends Node3D

## The little diamond over whatever the player has ordered the shadow to attack.
##
## Feedback for one command, not a lock-on: it points at a target that has
## already been chosen, it never chooses one, and nothing reads it back.
##
## One marker exists and is moved, rather than one being parented to each target
## — a target that dies frees its children, and a marker is not something that
## should depend on its subject staying alive to be cleaned up.

## Clearance above a target that carries its own world-space health bar, so the
## marker sits over the bar instead of across it.
@export var clearance_above_bar: float = 0.75
## Used for a target with no world-space bar of its own, such as the boss.
@export var default_height: float = 3.3
@export var bob_height: float = 0.12
@export var bob_speed: float = 3.0
@export var spin_speed: float = 2.2

@onready var pivot: Node3D = $Pivot

var _target: Node3D = null
var _height: float = 0.0
var _elapsed: float = 0.0


func _ready() -> void:
	visible = false
	set_process(false)


func get_target() -> Node3D:
	return _target


func is_showing() -> bool:
	return visible


func follow(target: Node3D) -> void:
	if target == null:
		clear()
		return
	_target = target
	_height = _height_for(target)
	_elapsed = 0.0
	visible = true
	set_process(true)
	_place()


func clear() -> void:
	_target = null
	visible = false
	set_process(false)


## Above the health bar when there is one, otherwise at the default height. The
## bar declares its own offset, so a bar that moves takes the marker with it. It is
## recognised by type, not by the name it happens to have in the enemy's scene.
func _height_for(target: Node3D) -> float:
	for child in target.get_children():
		var bar: EnemyHealthBar3D = child as EnemyHealthBar3D
		if bar != null:
			return bar.health_bar_height_offset + clearance_above_bar
	return default_height


func _process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		clear()
		return
	_elapsed += delta
	pivot.rotation.y += spin_speed * delta
	_place()


func _place() -> void:
	global_position = _target.global_position \
		+ Vector3(0.0, _height + sin(_elapsed * bob_speed) * bob_height, 0.0)
