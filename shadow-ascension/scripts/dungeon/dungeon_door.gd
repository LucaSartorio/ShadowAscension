class_name DungeonDoor
extends Node3D

## A doorway that can be closed or opened. It owns nothing but its own state —
## rooms call lock()/unlock(); the door never looks outward.

signal lock_state_changed(is_locked: bool)

@export var start_locked: bool = true
@export var open_height: float = 3.2
@export var move_duration: float = 0.45
@export var locked_color: Color = Color(0.75, 0.2, 0.2)
@export var unlocked_color: Color = Color(0.2, 0.7, 0.35)

@onready var blocker: StaticBody3D = $Blocker
@onready var blocker_collision: CollisionShape3D = $Blocker/CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot
@onready var mesh_instance: MeshInstance3D = $VisualRoot/MeshInstance3D

var _locked: bool = true
var _closed_y: float = 0.0
var _tween: Tween = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	_closed_y = visual_root.position.y
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat != null:
		# Sub-resources are shared between instances of a PackedScene.
		_material = mat.duplicate() as StandardMaterial3D
		mesh_instance.set_surface_override_material(0, _material)
	_apply_state(start_locked, true)


func lock() -> void:
	_apply_state(true, false)


func unlock() -> void:
	_apply_state(false, false)


func is_locked() -> bool:
	return _locked


func _apply_state(locked: bool, instant: bool) -> void:
	if _locked == locked and not instant:
		return
	_locked = locked
	blocker_collision.set_deferred("disabled", not locked)
	if _material != null:
		_material.albedo_color = locked_color if locked else unlocked_color

	var target_y: float = _closed_y if locked else _closed_y + open_height
	if _tween != null and _tween.is_running():
		_tween.kill()
	if instant:
		visual_root.position.y = target_y
	else:
		_tween = create_tween()
		_tween.tween_property(visual_root, "position:y", target_y, move_duration)

	lock_state_changed.emit(_locked)
