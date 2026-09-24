class_name CameraRig
extends Node3D

## The attack buttons, as intents. Here rather than on the player because a
## click while the cursor is free captures it instead of attacking.
signal attack_light_pressed
signal attack_heavy_pressed

@export var mouse_sensitivity: float = 0.005
@export var minimum_pitch: float = -1.2
@export var maximum_pitch: float = 1.2
@export var camera_distance: float = 4.0

@onready var pitch_pivot: Node3D = $PitchPivot
@onready var spring_arm: SpringArm3D = $PitchPivot/SpringArm3D


func _ready() -> void:
	spring_arm.spring_length = camera_distance
	var body: CollisionObject3D = get_parent() as CollisionObject3D
	if body != null:
		spring_arm.add_excluded_object(body.get_rid())
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion: InputEventMouseMotion = event
			rotation.y -= motion.relative.x * mouse_sensitivity
			pitch_pivot.rotation.x -= motion.relative.y * mouse_sensitivity
			pitch_pivot.rotation.x = clamp(pitch_pivot.rotation.x, minimum_pitch, maximum_pitch)
		return

	if event is InputEventKey:
		var key: InputEventKey = event
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if event.is_action_pressed("attack_light"):
		_attack_pressed(attack_light_pressed)
	elif event.is_action_pressed("attack_heavy"):
		_attack_pressed(attack_heavy_pressed)


func _attack_pressed(intent: Signal) -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		intent.emit()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_viewport().set_input_as_handled()
