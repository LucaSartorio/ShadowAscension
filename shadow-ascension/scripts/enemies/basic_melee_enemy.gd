class_name BasicMeleeEnemy
extends RoomCombatant

## Whether this enemy is currently fighting. The world-space health bar listens,
## so it can stay out of the way while the enemy is idle and undamaged.
signal engagement_changed(engaged: bool)

enum State { IDLE, CHASE, REPOSITION, ATTACK, DEAD }
enum AttackPhase { NONE, STARTUP, ACTIVE, RECOVERY }

## Archetype tuning. Copied into the runtime fields below on _ready(); this
## Resource is never written to at runtime.
@export var stats: EnemyStats

@export_group("Per-Instance")
## Bias of the approach bearing. Non-zero values make instances converge on
## different points around the player instead of the same one.
@export_range(-180.0, 180.0) var combat_angle_offset_degrees: float = 0.0
## Deterministic per-instance desync so a group does not swing in unison.
@export var initial_attack_delay: float = 0.0
@export var attack_cooldown_variation: float = 0.0

# Runtime tuning, seeded from `stats` in _apply_stats(). These are instance
# state: change them freely and the shared Resource stays untouched. The
# literals are only the fallback for an enemy with no stats assigned.
var max_health: float = 100.0

var movement_speed: float = 3.8
var acceleration: float = 12.0
var rotation_speed: float = 7.0
var gravity: float = 20.0

var detection_range: float = 10.0
var lose_target_range: float = 14.0
var lose_target_delay: float = 1.0
var eye_height: float = 1.2
var line_of_sight_mask: int = 1

var attack_range: float = 1.8
var preferred_combat_distance: float = 1.6
var minimum_combat_distance: float = 1.15
var enemy_spacing_radius: float = 0.8

var attack_damage: float = 15.0
var attack_startup: float = 0.35
var attack_active: float = 0.15
var attack_recovery: float = 0.65
var attack_cooldown: float = 0.4
var max_attack_facing_angle: float = 25.0
var attack_startup_turn_fraction: float = 0.3

var reposition_timeout: float = 1.5
var reposition_cooldown: float = 0.6
var reposition_speed_fraction: float = 0.8
var reposition_arrive_tolerance: float = 0.35

var telegraph_color: Color = Color(1.0, 0.85, 0.2)
var active_color: Color = Color(1.0, 0.25, 0.15)
var startup_scale: Vector3 = Vector3(0.88, 1.22, 0.88)
var active_scale: Vector3 = Vector3(1.18, 0.9, 1.18)

var target_update_interval: float = 0.2

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
var _engaged: bool = false
var _attack_phase: AttackPhase = AttackPhase.NONE
var _phase_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _attack_delay_timer: float = 0.0
var _lose_target_timer: float = 0.0
var _reposition_timer: float = 0.0
var _reposition_block_timer: float = 0.0
var _target_update_accum: float = 0.0
var _player: Player = null
var _telegraph_tween: Tween = null
var _last_health: float = 0.0

var _desired_horizontal: Vector3 = Vector3.ZERO
var _pending_delta: float = 0.0
var _moved_this_frame: bool = false
var _frames_without_avoidance: int = 0

var _body_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE

const AVOIDANCE_FALLBACK_FRAMES: int = 10


func _ready() -> void:
	_apply_stats()
	# reset_to rather than a bare write: this component filled itself from the
	# scene's placeholder in its own _ready(), before this one ran.
	health_component.reset_to(max_health)
	_last_health = max_health
	hitbox.damage = attack_damage
	hitbox.source = self
	health_component.health_changed.connect(_on_health_changed)
	health_component.died.connect(_on_died)
	_setup_navigation()
	_setup_material()


## Answered from the stats asset rather than copied into the inherited field on
## _ready(), so initialisation order never decides what a kill is worth.
func get_xp_reward() -> int:
	return stats.xp_reward if stats != null else xp_reward


func _apply_stats() -> void:
	if stats == null:
		push_warning("%s has no EnemyStats assigned; falling back to script defaults." % name)
		return
	max_health = stats.max_health

	movement_speed = stats.movement_speed
	acceleration = stats.acceleration
	rotation_speed = stats.rotation_speed
	gravity = stats.gravity

	detection_range = stats.detection_range
	lose_target_range = stats.lose_target_range
	lose_target_delay = stats.lose_target_delay
	eye_height = stats.eye_height
	line_of_sight_mask = stats.line_of_sight_mask

	attack_range = stats.attack_range
	preferred_combat_distance = stats.preferred_combat_distance
	minimum_combat_distance = stats.minimum_combat_distance
	enemy_spacing_radius = stats.enemy_spacing_radius

	attack_damage = stats.attack_damage
	attack_startup = stats.attack_startup
	attack_active = stats.attack_active
	attack_recovery = stats.attack_recovery
	attack_cooldown = stats.attack_cooldown
	max_attack_facing_angle = stats.max_attack_facing_angle
	attack_startup_turn_fraction = stats.attack_startup_turn_fraction

	reposition_timeout = stats.reposition_timeout
	reposition_cooldown = stats.reposition_cooldown
	reposition_speed_fraction = stats.reposition_speed_fraction
	reposition_arrive_tolerance = stats.reposition_arrive_tolerance

	telegraph_color = stats.telegraph_color
	active_color = stats.active_color
	startup_scale = stats.startup_scale
	active_scale = stats.active_scale

	target_update_interval = stats.target_update_interval


func _setup_navigation() -> void:
	# The exports stay the single source of truth for values the AI also reads.
	nav_agent.radius = enemy_spacing_radius
	nav_agent.max_speed = movement_speed
	nav_agent.avoidance_enabled = combat_enabled
	nav_agent.velocity_computed.connect(_on_velocity_computed)


func _setup_material() -> void:
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	# Sub-resources are shared across instances of a PackedScene — without this
	# duplicate every enemy would telegraph at the same time.
	_body_material = mat.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _body_material)
	_base_albedo = _body_material.albedo_color


## Wakes or parks the enemy. A dead enemy stays dead.
func set_combat_enabled(enabled: bool) -> void:
	if _state == State.DEAD:
		return
	super.set_combat_enabled(enabled)
	nav_agent.avoidance_enabled = enabled
	if enabled:
		return
	_enter_idle()
	_attack_phase = AttackPhase.NONE
	_phase_timer = 0.0
	_cooldown_timer = 0.0
	_attack_delay_timer = 0.0
	if hitbox.is_active():
		hitbox.deactivate()
	_reset_telegraph_instantly()
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	# Cheap enough to check every frame, and the setter only emits on a real
	# change — far less error-prone than a call at each of the state's exits.
	_set_engaged(combat_enabled and _state != State.IDLE)

	_moved_this_frame = false

	if not combat_enabled:
		# Dormant: no perception, no navigation, no timers. Gravity only, so the
		# body still rests on the floor.
		_desired_horizontal = Vector3.ZERO
		_apply_motion(Vector3.ZERO, delta)
		return

	_tick_timers(delta)

	var player: Player = _get_player()
	if player == null:
		_desired_horizontal = Vector3.ZERO
		_drive(Vector3.ZERO, delta)
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

	match _state:
		State.IDLE:
			_idle_step(delta, dist)
		State.CHASE:
			_chase_step(delta, dist, player)
		State.REPOSITION:
			_reposition_step(delta, dist, player)
		State.ATTACK:
			_attack_step(delta, to_player)


func _tick_timers(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	if _attack_delay_timer > 0.0:
		_attack_delay_timer = maxf(0.0, _attack_delay_timer - delta)
	if _reposition_block_timer > 0.0:
		_reposition_block_timer = maxf(0.0, _reposition_block_timer - delta)


func _get_player() -> Player:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	return _player


# --- movement -----------------------------------------------------------------

## Hands the desired velocity to NavigationAgent3D so RVO avoidance can adjust it.
## The actual move happens in _on_velocity_computed.
func _drive(desired_horizontal: Vector3, delta: float) -> void:
	_pending_delta = delta
	if not nav_agent.avoidance_enabled:
		_apply_motion(desired_horizontal, delta)
		return
	nav_agent.set_velocity(desired_horizontal)
	_frames_without_avoidance += 1
	if _frames_without_avoidance > AVOIDANCE_FALLBACK_FRAMES:
		# The agent never joined a navigation map; move anyway rather than freeze.
		_apply_motion(desired_horizontal, delta)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if _state == State.DEAD:
		return
	_frames_without_avoidance = 0
	_apply_motion(safe_velocity, _pending_delta)


func _apply_motion(horizontal: Vector3, delta: float) -> void:
	if _moved_this_frame:
		return
	_moved_this_frame = true
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


func _accelerate_toward(target_velocity: Vector3, delta: float) -> Vector3:
	var rate: float = acceleration * delta
	_desired_horizontal.x = move_toward(_desired_horizontal.x, target_velocity.x, rate)
	_desired_horizontal.z = move_toward(_desired_horizontal.z, target_velocity.z, rate)
	return _desired_horizontal


func _update_nav_target(delta: float, point: Vector3) -> void:
	_target_update_accum += delta
	if _target_update_accum >= target_update_interval:
		_target_update_accum = 0.0
		nav_agent.target_position = point


func _path_direction() -> Vector3:
	var to_next: Vector3 = nav_agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length() < 0.0001:
		return Vector3.ZERO
	return to_next.normalized()


## The point this instance wants to occupy: on the preferred-distance ring around
## the player, biased by combat_angle_offset_degrees so instances do not stack.
func _combat_slot_position(player: Player) -> Vector3:
	var from_player: Vector3 = global_position - player.global_position
	from_player.y = 0.0
	if from_player.length_squared() < 0.0001:
		from_player = Vector3.BACK
	var dir: Vector3 = from_player.normalized().rotated(Vector3.UP, deg_to_rad(combat_angle_offset_degrees))
	return player.global_position + dir * preferred_combat_distance


# --- facing -------------------------------------------------------------------

func _rotate_visual_toward(world_dir: Vector3, delta: float, speed: float) -> void:
	var target_yaw: float = atan2(-world_dir.x, -world_dir.z)
	var diff: float = wrapf(target_yaw - visual_root.rotation.y, -PI, PI)
	var step: float = speed * delta
	visual_root.rotation.y += clampf(diff, -step, step)


func _rotate_toward_player(player: Player, delta: float, speed: float) -> void:
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return
	_rotate_visual_toward(to_player.normalized(), delta, speed)


func _facing_error_to(player: Player) -> float:
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return 0.0
	var forward: Vector3 = -visual_root.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return PI
	return absf(forward.normalized().signed_angle_to(to_player.normalized(), Vector3.UP))


# --- perception ---------------------------------------------------------------

func _has_line_of_sight(player: Player) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from_point: Vector3 = global_position + Vector3.UP * eye_height
	var to_point: Vector3 = player.global_position + Vector3.UP * eye_height
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_point, to_point, line_of_sight_mask
	)
	query.exclude = [get_rid(), player.get_rid()]
	return space.intersect_ray(query).is_empty()


func _check_lose_target(delta: float, dist: float) -> bool:
	if dist <= lose_target_range:
		_lose_target_timer = 0.0
		return false
	_lose_target_timer += delta
	if _lose_target_timer < lose_target_delay:
		return false
	_enter_idle()
	return true


# --- states -------------------------------------------------------------------

func _enter_idle() -> void:
	_state = State.IDLE
	_lose_target_timer = 0.0
	_desired_horizontal = Vector3.ZERO


func _idle_step(delta: float, dist: float) -> void:
	_desired_horizontal = Vector3.ZERO
	_drive(Vector3.ZERO, delta)
	if dist < detection_range:
		_enter_chase(true)


func _enter_chase(acquiring_target: bool = false) -> void:
	_state = State.CHASE
	_lose_target_timer = 0.0
	_target_update_accum = target_update_interval
	if acquiring_target:
		_attack_delay_timer = initial_attack_delay


func _chase_step(delta: float, dist: float, player: Player) -> void:
	if _check_lose_target(delta, dist):
		return
	if _can_begin_attack(dist, player):
		_enter_attack()
		return
	if _reposition_block_timer <= 0.0 and _needs_reposition(dist, player):
		_enter_reposition()
		return

	_update_nav_target(delta, _combat_slot_position(player))
	var dir: Vector3 = _path_direction()
	# Spacing: once on the ring, hold position instead of grinding into the player.
	var speed: float = 0.0 if dist <= preferred_combat_distance else movement_speed
	_drive(_accelerate_toward(dir * speed, delta), delta)

	if speed > 0.0 and dir.length_squared() > 0.001:
		_rotate_visual_toward(dir, delta, rotation_speed)
	else:
		_rotate_toward_player(player, delta, rotation_speed)


func _needs_reposition(dist: float, player: Player) -> bool:
	if dist < minimum_combat_distance:
		return true
	if dist <= attack_range and _facing_error_to(player) > deg_to_rad(max_attack_facing_angle):
		return true
	return false


func _enter_reposition() -> void:
	_state = State.REPOSITION
	_reposition_timer = reposition_timeout
	_target_update_accum = target_update_interval


func _reposition_step(delta: float, dist: float, player: Player) -> void:
	if _check_lose_target(delta, dist):
		return

	_reposition_timer -= delta
	if _reposition_timer <= 0.0:
		# Fallback: never sit in REPOSITION forever. Hand back to CHASE and block
		# immediate re-entry so the two states cannot ping-pong.
		_reposition_block_timer = reposition_cooldown
		_enter_chase()
		return

	if _can_begin_attack(dist, player):
		_enter_attack()
		return

	var slot: Vector3 = _combat_slot_position(player)
	_update_nav_target(delta, slot)
	var dir: Vector3 = _path_direction()
	var speed: float = movement_speed * reposition_speed_fraction
	var in_band: bool = dist >= minimum_combat_distance and dist <= attack_range
	if in_band and global_position.distance_to(slot) < reposition_arrive_tolerance:
		speed = 0.0
	_drive(_accelerate_toward(dir * speed, delta), delta)

	# Reposition always turns to face the player, never the movement direction.
	_rotate_toward_player(player, delta, rotation_speed)


func _can_begin_attack(dist: float, player: Player) -> bool:
	if _cooldown_timer > 0.0 or _attack_delay_timer > 0.0:
		return false
	if dist > attack_range or dist < minimum_combat_distance:
		return false
	if _facing_error_to(player) > deg_to_rad(max_attack_facing_angle):
		return false
	return _has_line_of_sight(player)


func _enter_attack() -> void:
	_state = State.ATTACK
	_attack_phase = AttackPhase.STARTUP
	_phase_timer = attack_startup
	_desired_horizontal = Vector3.ZERO
	_telegraph_startup()


func _attack_step(delta: float, to_player: Vector3) -> void:
	_desired_horizontal = Vector3.ZERO
	_drive(Vector3.ZERO, delta)

	# STARTUP corrects facing slowly; ACTIVE and RECOVERY do not turn at all, so
	# the swing commits to where it was aimed and can be sidestepped.
	if _attack_phase == AttackPhase.STARTUP and to_player.length_squared() > 0.0001:
		_rotate_visual_toward(
			to_player.normalized(), delta, rotation_speed * attack_startup_turn_fraction
		)

	_phase_timer -= delta
	if _phase_timer > 0.0:
		return

	match _attack_phase:
		AttackPhase.STARTUP:
			_attack_phase = AttackPhase.ACTIVE
			_phase_timer = attack_active
			hitbox.damage = attack_damage
			hitbox.set_debug_color(active_color)
			hitbox.activate()
			_telegraph_active()
		AttackPhase.ACTIVE:
			hitbox.deactivate()
			_attack_phase = AttackPhase.RECOVERY
			_phase_timer = attack_recovery
			_telegraph_recovery()
		AttackPhase.RECOVERY:
			_attack_phase = AttackPhase.NONE
			_phase_timer = 0.0
			_cooldown_timer = attack_cooldown + attack_cooldown_variation
			_enter_chase()


# --- telegraph ----------------------------------------------------------------

func _kill_telegraph_tween() -> void:
	if _telegraph_tween != null and _telegraph_tween.is_running():
		_telegraph_tween.kill()


func _telegraph_startup() -> void:
	_kill_telegraph_tween()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	var duration: float = maxf(0.05, attack_startup * 0.85)
	_telegraph_tween.tween_property(visual_root, "scale", startup_scale, duration)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", telegraph_color, duration)


func _telegraph_active() -> void:
	_kill_telegraph_tween()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	var duration: float = maxf(0.03, attack_active * 0.5)
	_telegraph_tween.tween_property(visual_root, "scale", active_scale, duration)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", active_color, duration)


func _telegraph_recovery() -> void:
	_kill_telegraph_tween()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	var duration: float = maxf(0.08, attack_recovery * 0.6)
	_telegraph_tween.tween_property(visual_root, "scale", Vector3.ONE, duration)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", _base_albedo, duration)


func _reset_telegraph_instantly() -> void:
	_kill_telegraph_tween()
	visual_root.scale = Vector3.ONE
	if _body_material != null:
		_body_material.albedo_color = _base_albedo


# --- damage / death -----------------------------------------------------------

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


## Emits only on a change, so nothing downstream sees a per-frame stream.
func _set_engaged(value: bool) -> void:
	if _engaged == value:
		return
	_engaged = value
	engagement_changed.emit(_engaged)


func is_engaged() -> bool:
	return _engaged


func _on_died() -> void:
	_set_engaged(false)
	_state = State.DEAD
	_attack_phase = AttackPhase.NONE
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	if hitbox.is_active():
		hitbox.deactivate()

	# Leave the avoidance simulation so the living stop steering around a corpse.
	nav_agent.avoidance_enabled = false

	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	body_collision.call_deferred("set_disabled", true)

	_reset_telegraph_instantly()
	var t: Tween = create_tween()
	t.tween_property(visual_root, "rotation:x", deg_to_rad(90.0), 0.4)

	report_death(health_component.last_damage_source)
