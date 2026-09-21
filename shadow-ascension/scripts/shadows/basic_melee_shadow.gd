class_name BasicMeleeShadow
extends CharacterBody3D

## A summoned shadow: it follows the player, picks the nearest enemy within its
## detection area, walks over and hits it.
##
## Its own state logic, not the enemy's — it shares the components (health,
## hurtbox, hitbox, navigation) and none of the AI, the same split
## BasicMeleeEnemy and DungeonBoss already have.
##
## Health and damage come from the ShadowInstance's level, so a level-up changes
## what it does without any stat system of its own. It knows which instance it
## belongs to; the instance knows nothing about the scene.

signal shadow_died(shadow: BasicMeleeShadow)

enum State { FOLLOW, ACQUIRE_TARGET, CHASE_TARGET, ATTACK, RETURN_TO_PLAYER, DEAD }
enum AttackPhase { NONE, STARTUP, ACTIVE }

const GROUP: StringName = &"active_shadow"

@export var shadow_data: ShadowData

@export_group("Movement")
@export var movement_speed: float = 4.4
@export var acceleration: float = 14.0
@export var rotation_speed: float = 9.0
@export var gravity: float = 20.0
## Where it tries to stand when there is nothing to fight.
@export var follow_distance: float = 2.0
## Past this it stops loitering and walks back.
@export var max_follow_distance: float = 8.0
## Only used when it is hopelessly far or wedged — a last resort, not a
## movement strategy. Deliberately far beyond max_follow_distance.
@export var teleport_distance: float = 25.0
@export var teleport_stuck_time: float = 3.0
## A shadow this far below the player has left the level. Recovered at once
## rather than on the stuck timer: it is falling, and waiting only adds distance.
@export var fall_recovery_depth: float = 6.0
@export var target_update_interval: float = 0.2

@export_group("Combat")
@export var enemy_detection_range: float = 10.0
@export var attack_range: float = 1.6
@export var attack_startup: float = 0.25
@export var attack_active: float = 0.12
@export var attack_recovery: float = 0.45
@export var attack_cooldown: float = 0.5
@export var death_fade_duration: float = 0.7

@onready var visual_root: Node3D = $VisualRoot
@onready var mesh_instance: MeshInstance3D = $VisualRoot/MeshInstance3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hurtbox_collision: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var detection_area: Area3D = $DetectionArea
@onready var detection_shape: CollisionShape3D = $DetectionArea/CollisionShape3D
@onready var attack_hitbox: Hitbox = $VisualRoot/AttackOrigin/Hitbox

var instance: ShadowInstance = null

var _state: State = State.FOLLOW
var _attack_phase: AttackPhase = AttackPhase.NONE
var _phase_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _target_update_accum: float = 0.0
var _far_timer: float = 0.0

var _player: Player = null
var _target: RoomCombatant = null
var _desired_horizontal: Vector3 = Vector3.ZERO
var _material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(GROUP)
	attack_hitbox.source = self
	_setup_material()
	_apply_detection_range()
	nav_agent.max_speed = movement_speed
	health_component.died.connect(_on_died)


## Called by the summoner before the shadow enters the tree, so its very first
## frame already has the right health and damage for its level.
func bind(shadow_instance: ShadowInstance) -> void:
	instance = shadow_instance
	if instance != null and instance.shadow_data != null:
		shadow_data = instance.shadow_data
	apply_level()


## Recomputed from the instance's level rather than adjusted, so a level-up can
## never compound. Current health is kept: levelling raises the ceiling, it does
## not heal.
func apply_level() -> void:
	if instance == null:
		return
	var maximum: float = instance.get_max_health()
	if health_component == null:
		# Before _ready: the node is not resolved yet, so write the export the
		# health component will pick up when it readies.
		var component: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
		if component != null:
			component.max_health = maximum
		return
	if is_zero_approx(health_component.current_health):
		health_component.max_health = maximum
		health_component.current_health = maximum
	else:
		health_component.set_max_health(maximum)


func get_state() -> State:
	return _state


func get_target() -> RoomCombatant:
	return _target


func get_attack_damage() -> float:
	return instance.get_damage() if instance != null else 0.0


func is_dead() -> bool:
	return _state == State.DEAD


func _setup_material() -> void:
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	# Sub-resources are shared between instances of a PackedScene.
	_material = mat.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _material)
	if shadow_data != null:
		_material.emission = shadow_data.accent_color


func _apply_detection_range() -> void:
	var shape: SphereShape3D = detection_shape.shape as SphereShape3D
	if shape != null:
		# The shape is shared between instances, so resize a copy.
		var own: SphereShape3D = shape.duplicate() as SphereShape3D
		own.radius = enemy_detection_range
		detection_shape.shape = own


# --- main loop -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)

	var player: Player = _get_player()
	if player == null:
		_apply_motion(Vector3.ZERO, delta)
		return

	_drop_invalid_target()
	var distance_to_player: float = global_position.distance_to(player.global_position)
	_tick_stuck(delta, distance_to_player, player)

	match _state:
		State.FOLLOW:
			_follow_step(delta, player, distance_to_player)
		State.ACQUIRE_TARGET:
			_acquire_step(delta, player)
		State.CHASE_TARGET:
			_chase_step(delta, player)
		State.ATTACK:
			_attack_step(delta)
		State.RETURN_TO_PLAYER:
			_return_step(delta, player, distance_to_player)


func _get_player() -> Player:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Player
	return _player


## A corpse is not a target. Checked every frame because an enemy can die to the
## player while this one is walking towards it.
func _drop_invalid_target() -> void:
	if _target == null:
		return
	if not is_instance_valid(_target) or _target.has_died():
		_target = null


## Last resort only: a shadow that has fallen out of the level, or that is
## absurdly far for long enough, is put back beside the player rather than left
## stranded behind geometry.
func _tick_stuck(delta: float, distance_to_player: float, player: Player) -> void:
	if player.global_position.y - global_position.y > fall_recovery_depth:
		_recover_to(player)
		return
	if distance_to_player < teleport_distance:
		_far_timer = 0.0
		return
	_far_timer += delta
	if _far_timer < teleport_stuck_time:
		return
	_recover_to(player)


func _recover_to(player: Player) -> void:
	_far_timer = 0.0
	global_position = player.global_position + _follow_offset(player)
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO


# --- states ------------------------------------------------------------------------

## Stands off the player's shoulder rather than inside them.
func _follow_offset(player: Player) -> Vector3:
	var behind: Vector3 = player.global_position - global_position
	behind.y = 0.0
	if behind.length_squared() < 0.0001:
		behind = Vector3.BACK
	return -behind.normalized() * follow_distance


func _follow_step(delta: float, player: Player, distance_to_player: float) -> void:
	if _find_target() != null:
		_state = State.ACQUIRE_TARGET
		return
	if distance_to_player > max_follow_distance:
		_state = State.RETURN_TO_PLAYER
		return
	if distance_to_player <= follow_distance + 0.4:
		# Close enough. Stand still rather than jitter around the player.
		_apply_motion(_accelerate_toward(Vector3.ZERO, delta), delta)
		_face(player.global_position - global_position, delta)
		return
	_walk_towards(player.global_position + _follow_offset(player), delta)


func _acquire_step(delta: float, player: Player) -> void:
	_target = _find_target()
	if _target == null:
		_state = State.FOLLOW
		_follow_step(delta, player, global_position.distance_to(player.global_position))
		return
	_state = State.CHASE_TARGET


func _chase_step(delta: float, player: Player) -> void:
	if _target == null:
		_state = State.FOLLOW
		return
	if global_position.distance_to(player.global_position) > max_follow_distance * 1.6:
		# Dragged too far from the player by a chase: the player comes first.
		_target = null
		_state = State.RETURN_TO_PLAYER
		return
	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= attack_range and _cooldown_timer <= 0.0:
		_begin_attack(to_target)
		return
	_walk_towards(_target.global_position, delta)


func _begin_attack(to_target: Vector3) -> void:
	_state = State.ATTACK
	_attack_phase = AttackPhase.STARTUP
	_phase_timer = attack_startup
	_desired_horizontal = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0
	if to_target.length_squared() > 0.0001:
		visual_root.rotation.y = atan2(-to_target.x, -to_target.z)


func _attack_step(delta: float) -> void:
	# Committed: no movement and no turning, so a target that steps aside is
	# genuinely missed.
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return
	match _attack_phase:
		AttackPhase.STARTUP:
			_attack_phase = AttackPhase.ACTIVE
			_phase_timer = attack_active
			attack_hitbox.damage = get_attack_damage()
			attack_hitbox.activate()
		AttackPhase.ACTIVE:
			if attack_hitbox.is_active():
				attack_hitbox.deactivate()
			_attack_phase = AttackPhase.NONE
			_phase_timer = attack_recovery
			_cooldown_timer = attack_cooldown + attack_recovery
			_state = State.CHASE_TARGET if _target != null else State.FOLLOW


func _return_step(delta: float, player: Player, distance_to_player: float) -> void:
	if distance_to_player <= follow_distance + 0.6:
		_state = State.FOLLOW
		return
	_walk_towards(player.global_position + _follow_offset(player), delta)


# --- movement ---------------------------------------------------------------------

func _walk_towards(point: Vector3, delta: float) -> void:
	_target_update_accum += delta
	if _target_update_accum >= target_update_interval:
		_target_update_accum = 0.0
		nav_agent.target_position = point
	var to_next: Vector3 = nav_agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length() < 0.0001:
		_apply_motion(_accelerate_toward(Vector3.ZERO, delta), delta)
		return
	var direction: Vector3 = to_next.normalized()
	_apply_motion(_accelerate_toward(direction * movement_speed, delta), delta)
	_face(direction, delta)


func _accelerate_toward(target_velocity: Vector3, delta: float) -> Vector3:
	var rate: float = acceleration * delta
	_desired_horizontal.x = move_toward(_desired_horizontal.x, target_velocity.x, rate)
	_desired_horizontal.z = move_toward(_desired_horizontal.z, target_velocity.z, rate)
	return _desired_horizontal


func _apply_motion(horizontal: Vector3, delta: float) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


func _face(direction: Vector3, delta: float) -> void:
	var flat: Vector3 = direction
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	var target_yaw: float = atan2(-flat.x, -flat.z)
	var diff: float = wrapf(target_yaw - visual_root.rotation.y, -PI, PI)
	var step: float = rotation_speed * delta
	visual_root.rotation.y += clampf(diff, -step, step)


# --- targeting ----------------------------------------------------------------------

## Nearest living enemy inside the detection area. The area does the work, so
## nothing scans the whole scene tree — and it is only consulted when the shadow
## actually needs a target.
func _find_target() -> RoomCombatant:
	var nearest: RoomCombatant = null
	var nearest_distance: float = INF
	for body in detection_area.get_overlapping_bodies():
		var combatant: RoomCombatant = body as RoomCombatant
		if combatant == null or combatant.has_died():
			continue
		var distance: float = global_position.distance_to(combatant.global_position)
		if distance < nearest_distance:
			nearest = combatant
			nearest_distance = distance
	return nearest


# --- death -------------------------------------------------------------------------

## The runtime entity dies; the ShadowInstance does not. It stays in the
## collection with its level and XP and can be summoned again.
func _on_died() -> void:
	_state = State.DEAD
	_attack_phase = AttackPhase.NONE
	_target = null
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	if attack_hitbox.is_active():
		attack_hitbox.deactivate()
	nav_agent.avoidance_enabled = false
	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	body_collision.call_deferred("set_disabled", true)
	detection_area.call_deferred("set_monitoring", false)
	shadow_died.emit(self)

	var t: Tween = create_tween()
	t.tween_property(visual_root, "scale", Vector3(0.1, 0.1, 0.1), death_fade_duration)
	t.tween_callback(queue_free)
