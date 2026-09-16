class_name Player
extends CharacterBody3D

enum AttackState { IDLE, STARTUP, ACTIVE, RECOVERY }

@export var movement_speed: float = 6.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 20.0

@export var combo_steps: Array[AttackStep] = []
@export var combo_reset_time: float = 0.8

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig: CameraRig = $CameraRig
@onready var attack_hitbox: Hitbox = $VisualRoot/AttackHitbox

var _attack_state: AttackState = AttackState.IDLE
var _attack_timer: float = 0.0
var _combo_index: int = 0
var _idle_since_step_ended: float = 0.0
var _queued_next: bool = false
var _current_step: AttackStep = null
var _visual_tween: Tween = null


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
	if combo_steps.is_empty():
		return
	if _attack_state == AttackState.IDLE:
		_fire_step(_combo_index)
	else:
		_queued_next = true


func _fire_step(index: int) -> void:
	if index < 0 or index >= combo_steps.size():
		index = 0
	var step: AttackStep = combo_steps[index]
	if step == null:
		return
	_current_step = step
	_combo_index = index + 1
	_idle_since_step_ended = 0.0
	_face_aim_direction()
	_do_visual_feedback(step)
	_attack_state = AttackState.STARTUP
	_attack_timer = step.startup


func _face_aim_direction() -> void:
	var cam_basis: Basis = camera_rig.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	if forward.length() < 0.0001:
		return
	forward = forward.normalized()
	visual_root.rotation.y = atan2(-forward.x, -forward.z)


func _do_visual_feedback(step: AttackStep) -> void:
	if _visual_tween != null and _visual_tween.is_running():
		_visual_tween.kill()
	var tilt: float = deg_to_rad(step.visual_tilt_degrees)
	var to_tilt_time: float = max(0.05, step.startup + step.active * 0.5)
	var to_zero_time: float = max(0.05, step.recovery)
	_visual_tween = create_tween()
	_visual_tween.tween_property(visual_root, "rotation:z", tilt, to_tilt_time)
	_visual_tween.tween_property(visual_root, "rotation:z", 0.0, to_zero_time)


func _update_attack(delta: float) -> void:
	if _attack_state == AttackState.IDLE:
		if _combo_index > 0 and _combo_index <= combo_steps.size():
			_idle_since_step_ended += delta
			if _idle_since_step_ended >= combo_reset_time:
				_combo_index = 0
				_idle_since_step_ended = 0.0
		return
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	match _attack_state:
		AttackState.STARTUP:
			_attack_state = AttackState.ACTIVE
			_attack_timer = _current_step.active
			attack_hitbox.damage = _current_step.damage
			attack_hitbox.set_debug_color(_current_step.debug_color)
			attack_hitbox.activate()
		AttackState.ACTIVE:
			attack_hitbox.deactivate()
			_attack_state = AttackState.RECOVERY
			_attack_timer = _current_step.recovery
		AttackState.RECOVERY:
			_attack_state = AttackState.IDLE
			_attack_timer = 0.0
			if _combo_index >= combo_steps.size():
				_combo_index = 0
				_queued_next = false
				_idle_since_step_ended = 0.0
			elif _queued_next:
				_queued_next = false
				_fire_step(_combo_index)
			else:
				_idle_since_step_ended = 0.0
