class_name Player
extends CharacterBody3D

enum AttackState { IDLE, STARTUP, ACTIVE, RECOVERY }

@export var movement_speed: float = 6.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 20.0

@export var attack_startup_time: float = 0.15
@export var attack_active_time: float = 0.15
@export var attack_recovery_time: float = 0.25

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig: CameraRig = $CameraRig
@onready var attack_hitbox: Hitbox = $VisualRoot/AttackHitbox

var _attack_state: AttackState = AttackState.IDLE
var _attack_timer: float = 0.0


func _ready() -> void:
	attack_hitbox.source = self
	camera_rig.attack_light_pressed.connect(_on_attack_light_pressed)


func _physics_process(delta: float) -> void:
	_update_attack(delta)

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

	if _attack_state == AttackState.IDLE and desired_dir.length_squared() > 0.001:
		var target_yaw: float = atan2(-desired_dir.x, -desired_dir.z)
		var diff: float = wrapf(target_yaw - visual_root.rotation.y, -PI, PI)
		var max_step: float = rotation_speed * delta
		visual_root.rotation.y += clamp(diff, -max_step, max_step)


func _on_attack_light_pressed() -> void:
	if _attack_state != AttackState.IDLE:
		return
	_face_aim_direction()
	_attack_state = AttackState.STARTUP
	_attack_timer = attack_startup_time


func _face_aim_direction() -> void:
	var cam_basis: Basis = camera_rig.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	if forward.length() < 0.0001:
		return
	forward = forward.normalized()
	visual_root.rotation.y = atan2(-forward.x, -forward.z)


func _update_attack(delta: float) -> void:
	if _attack_state == AttackState.IDLE:
		return
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	match _attack_state:
		AttackState.STARTUP:
			_attack_state = AttackState.ACTIVE
			_attack_timer = attack_active_time
			attack_hitbox.activate()
		AttackState.ACTIVE:
			attack_hitbox.deactivate()
			_attack_state = AttackState.RECOVERY
			_attack_timer = attack_recovery_time
		AttackState.RECOVERY:
			_attack_state = AttackState.IDLE
			_attack_timer = 0.0
