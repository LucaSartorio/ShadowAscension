class_name BasicMeleeEnemy
extends CharacterBody3D

enum State { IDLE, CHASE, ATTACK, DEAD }
enum AttackPhase { NONE, STARTUP, ACTIVE, RECOVERY }

@export var max_health: float = 100.0

@export var movement_speed: float = 3.8
@export var acceleration: float = 12.0
@export var rotation_speed: float = 7.0
@export var gravity: float = 20.0

@export var detection_range: float = 10.0
@export var lose_target_range: float = 14.0
@export var attack_range: float = 1.8

@export var attack_damage: float = 15.0
@export var attack_startup: float = 0.35
@export var attack_active: float = 0.15
@export var attack_recovery: float = 0.65
@export var attack_cooldown: float = 0.4

@export var target_update_interval: float = 0.2

@onready var visual_root: Node3D = $VisualRoot
@onready var mesh_instance: MeshInstance3D = $VisualRoot/MeshInstance3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hurtbox_collision: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var attack_origin: Node3D = $VisualRoot/AttackOrigin
@onready var hitbox: Hitbox = $VisualRoot/AttackOrigin/Hitbox

var _state: State = State.IDLE
var _attack_phase: AttackPhase = AttackPhase.NONE
var _phase_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _target_update_accum: float = 0.0
var _player: Player = null
var _feedback_tween: Tween = null
var _last_health: float = 0.0


func _ready() -> void:
	health_component.max_health = max_health
	_last_health = max_health
	hitbox.damage = attack_damage
	hitbox.source = self
	health_component.health_changed.connect(_on_health_changed)
	health_component.died.connect(_on_died)


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	if _cooldown_timer > 0.0:
		_cooldown_timer = max(0.0, _cooldown_timer - delta)

	var player: Player = _get_player()
	if player == null:
		_apply_gravity_and_slide(delta)
		return

	var dist: float = global_position.distance_to(player.global_position)

	match _state:
		State.IDLE:
			_idle_step(delta, dist)
		State.CHASE:
			_chase_step(delta, dist, player)
		State.ATTACK:
			_attack_step(delta)


func _get_player() -> Player:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Player
	return _player


func _idle_step(delta: float, dist: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_slide(delta)
	if dist < detection_range:
		_enter_chase()


func _enter_chase() -> void:
	_state = State.CHASE
	_target_update_accum = target_update_interval  # force immediate update


func _chase_step(delta: float, dist: float, player: Player) -> void:
	if dist > lose_target_range:
		_enter_idle()
		return
	if dist < attack_range and _cooldown_timer <= 0.0:
		_enter_attack()
		return

	_target_update_accum += delta
	if _target_update_accum >= target_update_interval:
		_target_update_accum = 0.0
		nav_agent.target_position = player.global_position

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var to_next: Vector3 = next_pos - global_position
	to_next.y = 0.0
	var dir: Vector3 = Vector3.ZERO
	if to_next.length() > 0.0001:
		dir = to_next.normalized()

	var target_vel_x: float = dir.x * movement_speed
	var target_vel_z: float = dir.z * movement_speed
	velocity.x = move_toward(velocity.x, target_vel_x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_vel_z, acceleration * delta)

	_apply_gravity_and_slide(delta)

	if dir.length_squared() > 0.001:
		_rotate_visual_toward(dir, delta)


func _enter_idle() -> void:
	_state = State.IDLE


func _enter_attack() -> void:
	_state = State.ATTACK
	_attack_phase = AttackPhase.STARTUP
	_phase_timer = attack_startup
	velocity.x = 0.0
	velocity.z = 0.0
	_face_player_snapshot()
	_show_telegraph()


func _face_player_snapshot() -> void:
	var p: Player = _get_player()
	if p == null:
		return
	var to_p: Vector3 = p.global_position - global_position
	to_p.y = 0.0
	if to_p.length() < 0.0001:
		return
	visual_root.rotation.y = atan2(-to_p.x, -to_p.z)


func _show_telegraph() -> void:
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	var target_scale: Vector3 = Vector3(1.15, 1.15, 1.15)
	_feedback_tween.tween_property(visual_root, "scale", target_scale, max(0.05, attack_startup * 0.85))


func _hide_telegraph() -> void:
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(visual_root, "scale", Vector3.ONE, 0.08)


func _attack_step(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_and_slide(delta)
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return
	match _attack_phase:
		AttackPhase.STARTUP:
			_attack_phase = AttackPhase.ACTIVE
			_phase_timer = attack_active
			hitbox.damage = attack_damage
			hitbox.activate()
			_hide_telegraph()
		AttackPhase.ACTIVE:
			hitbox.deactivate()
			_attack_phase = AttackPhase.RECOVERY
			_phase_timer = attack_recovery
		AttackPhase.RECOVERY:
			_attack_phase = AttackPhase.NONE
			_phase_timer = 0.0
			_cooldown_timer = attack_cooldown
			_state = State.CHASE


func _rotate_visual_toward(world_dir: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-world_dir.x, -world_dir.z)
	var diff: float = wrapf(target_yaw - visual_root.rotation.y, -PI, PI)
	var step: float = rotation_speed * delta
	visual_root.rotation.y += clamp(diff, -step, step)


func _apply_gravity_and_slide(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


func _on_health_changed(current: float, _maximum: float) -> void:
	if current < _last_health:
		_hit_flash()
	_last_health = current


func _hit_flash() -> void:
	if mesh_instance == null:
		return
	var t: Tween = create_tween()
	t.tween_property(mesh_instance, "scale", Vector3(1.2, 0.85, 1.2), 0.05)
	t.tween_property(mesh_instance, "scale", Vector3.ONE, 0.12)


func _on_died() -> void:
	_state = State.DEAD
	_attack_phase = AttackPhase.NONE
	velocity = Vector3.ZERO
	if hitbox.is_active():
		hitbox.deactivate()
	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	body_collision.call_deferred("set_disabled", true)
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	var t: Tween = create_tween()
	t.tween_property(visual_root, "rotation:x", deg_to_rad(90.0), 0.4)
