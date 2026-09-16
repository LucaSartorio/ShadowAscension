class_name Player
extends CharacterBody3D

@export var movement_speed: float = 6.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 20.0

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig: Node3D = $CameraRig


func _physics_process(delta: float) -> void:
	var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	var cam_basis: Basis = camera_rig.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	if forward.length() > 0.0001:
		forward = forward.normalized()
	var right: Vector3 = cam_basis.x
	right.y = 0.0
	if right.length() > 0.0001:
		right = right.normalized()

	var desired_dir: Vector3 = forward * -input_vec.y + right * input_vec.x
	if desired_dir.length() > 1.0:
		desired_dir = desired_dir.normalized()

	var target_horiz: Vector3 = desired_dir * movement_speed
	var current_horiz: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var accel_rate: float = acceleration if desired_dir.length_squared() > 0.001 else deceleration
	current_horiz = current_horiz.move_toward(target_horiz, accel_rate * delta)
	velocity.x = current_horiz.x
	velocity.z = current_horiz.z

	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta

	move_and_slide()

	if desired_dir.length_squared() > 0.001:
		var target_yaw: float = atan2(-desired_dir.x, -desired_dir.z)
		var diff: float = wrapf(target_yaw - visual_root.rotation.y, -PI, PI)
		var max_step: float = rotation_speed * delta
		visual_root.rotation.y += clamp(diff, -max_step, max_step)
