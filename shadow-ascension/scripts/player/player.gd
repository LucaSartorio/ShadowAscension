class_name Player
extends CharacterBody3D

enum AttackState { IDLE, STARTUP, ACTIVE, RECOVERY }

## Base values. AGI scales these into the `effective_*` fields below; the bases
## themselves are never written to, so a multiplier can never compound.
@export var movement_speed: float = 6.0
@export var acceleration: float = 40.0
@export var deceleration: float = 50.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 20.0

@export var combo_steps: Array[AttackStep] = []
@export var combo_reset_time: float = 0.8

@export var dodge_duration: float = 0.35
@export var dodge_speed: float = 11.5
@export var invulnerability_start: float = 0.06
@export var invulnerability_end: float = 0.24
@export var dodge_cooldown: float = 0.15
@export var dodge_visual_tilt_degrees: float = -15.0

@onready var visual_root: Node3D = $VisualRoot
@onready var camera_rig: CameraRig = $CameraRig
@onready var attack_hitbox: Hitbox = $VisualRoot/AttackHitbox
@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var progression: PlayerProgression = $PlayerProgression
@onready var inventory: PlayerInventory = $PlayerInventory
@onready var equipment: PlayerEquipment = $PlayerEquipment

## What the controller actually uses. Recomputed from the base values whenever
## the stats change — never from the previous effective value.
var effective_movement_speed: float = 6.0
var effective_dodge_speed: float = 11.5
## The player's own maximum, before VIT. Captured once so raising VIT adds to the
## original ceiling rather than to an already-raised one.
var base_max_health: float = 0.0

var _attack_state: AttackState = AttackState.IDLE
var _attack_timer: float = 0.0
var _recovery_elapsed: float = 0.0
var _combo_index: int = 0
var _idle_since_step_ended: float = 0.0
var _queued_next: bool = false
var _current_step: AttackStep = null
var _visual_tween: Tween = null

var _is_dodging: bool = false
var _dodge_elapsed: float = 0.0
var _dodge_cooldown_remaining: float = 0.0
var _dodge_direction: Vector3 = Vector3.ZERO
var _dodge_iframes_active: bool = false


func _ready() -> void:
	add_to_group("player")
	attack_hitbox.source = self
	camera_rig.attack_light_pressed.connect(_on_attack_light_pressed)
	base_max_health = health_component.max_health
	if progression != null:
		progression.equipment = equipment
		progression.stats_changed.connect(_apply_stat_effects)
	if equipment != null:
		# Taking a piece off changes max health, movement and damage, so the same
		# recompute runs for equipment as for a spent stat point.
		equipment.equipment_changed.connect(_apply_stat_effects)
	_apply_stat_effects()
	_restore_health()
	health_component.health_changed.connect(_on_health_changed)
	health_component.died.connect(_on_player_died)


## Health carries across a scene change, so walking through a gate is not a free
## heal. The ceiling is never restored — _apply_stat_effects() has already
## recomputed it from this player's own base plus VIT — only the wound is.
func _restore_health() -> void:
	var state: Node = _runtime_state()
	if state == null or not state.initialized:
		if state != null:
			state.sync_health(health_component.current_health)
		return
	if state.wants_full_health():
		health_component.current_health = health_component.max_health
		state.sync_health(health_component.current_health)
		return
	health_component.current_health = clampf(
		state.current_health, 0.0, health_component.max_health)
	# Written straight to the field, which emits nothing, so the session is told
	# explicitly. It matters when the clamp actually bit: without this the stored
	# value would stay above the ceiling it was just clamped to.
	state.sync_health(health_component.current_health)


func _on_health_changed(current: float, _maximum: float) -> void:
	var state: Node = _runtime_state()
	if state != null:
		state.sync_health(current)


## The run restarts, the character does not: the next player comes back at full
## health with its level, XP and stats untouched.
func _on_player_died() -> void:
	var state: Node = _runtime_state()
	if state != null:
		state.reset_health_to_max()


func _runtime_state() -> Node:
	return get_tree().root.get_node_or_null("PlayerRuntimeState")


## Recomputes every stat-driven value from its base. Called once at startup and
## again on each stat change — never incrementally, so nothing compounds.
func _apply_stat_effects() -> void:
	if progression == null:
		effective_movement_speed = movement_speed
		effective_dodge_speed = dodge_speed
		return
	effective_movement_speed = movement_speed * progression.get_movement_speed_multiplier()
	effective_dodge_speed = dodge_speed * progression.get_dodge_speed_multiplier()
	# Raises the ceiling without healing: HealthComponent only clamps downwards.
	health_component.set_max_health(base_max_health + progression.get_bonus_max_health())


## STR scaling for one swing. Kept here rather than written into the AttackStep,
## which stays the base damage for every attack.
func _effective_damage(base_damage: float) -> float:
	if progression == null:
		return base_damage
	return progression.get_effective_damage(base_damage)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dodge"):
		_on_dodge_pressed()


func _physics_process(delta: float) -> void:
	if _is_dodging:
		_tick_dodge(delta)
		return

	if _dodge_cooldown_remaining > 0.0:
		_dodge_cooldown_remaining = max(0.0, _dodge_cooldown_remaining - delta)

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

	var target_horiz: Vector3 = desired_dir * effective_movement_speed
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
	if _is_dodging:
		return
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
	_recovery_elapsed = 0.0
	_face_aim_direction()
	_do_attack_visual_feedback(step)
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


func _do_attack_visual_feedback(step: AttackStep) -> void:
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
	if _attack_state == AttackState.RECOVERY:
		_recovery_elapsed += delta
	if _attack_timer > 0.0:
		return
	match _attack_state:
		AttackState.STARTUP:
			_attack_state = AttackState.ACTIVE
			_attack_timer = _current_step.active
			# The step keeps its base damage; STR is applied here, once per swing.
			attack_hitbox.damage = _effective_damage(_current_step.damage)
			attack_hitbox.set_debug_color(_current_step.debug_color)
			attack_hitbox.activate()
		AttackState.ACTIVE:
			attack_hitbox.deactivate()
			_attack_state = AttackState.RECOVERY
			_attack_timer = _current_step.recovery
			_recovery_elapsed = 0.0
		AttackState.RECOVERY:
			_attack_state = AttackState.IDLE
			_attack_timer = 0.0
			_recovery_elapsed = 0.0
			if _combo_index >= combo_steps.size():
				_combo_index = 0
				_queued_next = false
				_idle_since_step_ended = 0.0
			elif _queued_next:
				_queued_next = false
				_fire_step(_combo_index)
			else:
				_idle_since_step_ended = 0.0


func _on_dodge_pressed() -> void:
	if _is_dodging:
		return
	if _dodge_cooldown_remaining > 0.0:
		return
	if _attack_state != AttackState.IDLE:
		if not _in_cancel_window():
			return
		_cancel_current_attack()
	var direction: Vector3 = _compute_dodge_direction()
	_start_dodge(direction)


func _in_cancel_window() -> bool:
	if _attack_state != AttackState.RECOVERY:
		return false
	if _current_step == null:
		return false
	var threshold: float = _current_step.recovery * _current_step.dodge_cancel_recovery_fraction
	return _recovery_elapsed >= threshold


func _cancel_current_attack() -> void:
	if attack_hitbox.is_active():
		attack_hitbox.deactivate()
	_attack_state = AttackState.IDLE
	_attack_timer = 0.0
	_recovery_elapsed = 0.0
	_combo_index = 0
	_queued_next = false
	_idle_since_step_ended = 0.0
	_current_step = null


func _compute_dodge_direction() -> Vector3:
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
	var dir: Vector3 = forward * -input_vec.y + right * input_vec.x
	if dir.length_squared() > 0.001:
		if dir.length() > 1.0:
			dir = dir.normalized()
		return dir.normalized()
	var facing_back: Vector3 = visual_root.global_transform.basis.z
	facing_back.y = 0.0
	if facing_back.length() < 0.0001:
		facing_back = Vector3(0, 0, 1)
	return facing_back.normalized()


func _start_dodge(direction: Vector3) -> void:
	_is_dodging = true
	_dodge_elapsed = 0.0
	_dodge_direction = direction
	_dodge_iframes_active = false
	_combo_index = 0
	_queued_next = false
	_idle_since_step_ended = 0.0
	if hurtbox != null:
		hurtbox.set_invulnerable(false)
	_do_dodge_visual_feedback()


func _do_dodge_visual_feedback() -> void:
	if _visual_tween != null and _visual_tween.is_running():
		_visual_tween.kill()
	var tilt: float = deg_to_rad(dodge_visual_tilt_degrees)
	var to_tilt_time: float = max(0.05, dodge_duration * 0.4)
	var to_zero_time: float = max(0.05, dodge_duration * 0.6)
	_visual_tween = create_tween()
	_visual_tween.tween_property(visual_root, "rotation:x", tilt, to_tilt_time)
	_visual_tween.tween_property(visual_root, "rotation:x", 0.0, to_zero_time)


func _tick_dodge(delta: float) -> void:
	_dodge_elapsed += delta
	var should_be_invulnerable: bool = _dodge_elapsed >= invulnerability_start and _dodge_elapsed < invulnerability_end
	if should_be_invulnerable != _dodge_iframes_active:
		_dodge_iframes_active = should_be_invulnerable
		if hurtbox != null:
			hurtbox.set_invulnerable(should_be_invulnerable)
	velocity.x = _dodge_direction.x * effective_dodge_speed
	velocity.z = _dodge_direction.z * effective_dodge_speed
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()
	if _dodge_elapsed >= dodge_duration:
		_end_dodge()


func _end_dodge() -> void:
	_is_dodging = false
	_dodge_direction = Vector3.ZERO
	_dodge_iframes_active = false
	if hurtbox != null:
		hurtbox.set_invulnerable(false)
	_dodge_cooldown_remaining = dodge_cooldown
