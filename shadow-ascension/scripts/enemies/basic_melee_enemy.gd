class_name BasicMeleeEnemy
extends RoomCombatant

## Whether this enemy is currently fighting. The world-space health bar listens,
## so it can stay out of the way while the enemy is idle and undamaged.
signal engagement_changed(engaged: bool)

## STAGGERED (M11.6) outranks every state but DEAD: it cuts an attack off, and
## nothing the AI decides runs until it is over.
enum State { IDLE, CHASE, REPOSITION, ATTACK, STAGGERED, DEAD }
enum AttackPhase { NONE, STARTUP, ACTIVE, RECOVERY }

## The archetype's configuration: the one place its numbers exist. Copied into
## the runtime fields below on _ready(); the asset itself is never written to,
## because every enemy of the archetype shares it.
@export var stats: EnemyData

@export_group("Per-Instance")
## Bias of the approach bearing. Non-zero values make instances converge on
## different points around the player instead of the same one.
@export_range(-180.0, 180.0) var combat_angle_offset_degrees: float = 0.0
## Deterministic per-instance desync so a group does not swing in unison.
@export var initial_attack_delay: float = 0.0
@export var attack_cooldown_variation: float = 0.0

@export_group("DEBUG")
## DEBUG ONLY. Off by default. Prints every hit this enemy survives: its stagger
## power against the resistance, whether it staggered, and the push it took.
@export var debug_log_reactions: bool = false

# RUNTIME tuning: this instance's own values, seeded from `stats` in
# _apply_stats() and read by the AI from then on. Instance state — change them
# freely and the shared asset stays untouched. They carry no values of their
# own: the archetype's numbers live in its EnemyData and nowhere in this script.
var max_health: float

var movement_speed: float
var acceleration: float
var rotation_speed: float
var gravity: float

var detection_range: float
var lose_target_range: float
var lose_target_delay: float
var eye_height: float
var line_of_sight_mask: int

var attack_range: float
var preferred_combat_distance: float
var minimum_combat_distance: float
var enemy_spacing_radius: float

var attack_damage: float
var attack_startup: float
var attack_active: float
var attack_recovery: float
var attack_cooldown: float
var max_attack_facing_angle: float
var attack_startup_turn_fraction: float

var stagger_resistance: float
var stagger_duration: float
var stagger_immunity_time: float
var knockback_multiplier: float
var knockback_deceleration: float

var reposition_timeout: float
var reposition_cooldown: float
var reposition_speed_fraction: float
var reposition_arrive_tolerance: float

var telegraph_color: Color
var active_color: Color
var startup_scale: Vector3
var active_scale: Vector3

var target_update_interval: float

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
## Hit reactions (M11.6), all runtime: what is left of a stagger, of the
## immunity after one, and of a push.
var _stagger_timer: float = 0.0
var _stagger_immunity_timer: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _flinch_tween: Tween = null
var _pose_tween: Tween = null
var _mesh_rest_quaternion: Quaternion = Quaternion.IDENTITY

var _desired_horizontal: Vector3 = Vector3.ZERO
var _pending_delta: float = 0.0
var _moved_this_frame: bool = false
var _frames_without_avoidance: int = 0

var _body_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE

const AVOIDANCE_FALLBACK_FRAMES: int = 10
## PLACEHOLDER hit reactions, until M14's clips: every hit that leaves the enemy
## standing squashes the body; a stagger also leans it away from the blow for as
## long as it lasts.
const FLINCH_SQUASH: Vector3 = Vector3(1.2, 0.85, 1.2)
const STAGGER_LEAN_DEGREES: float = 20.0
const STAGGER_LEAN_IN_TIME: float = 0.08
const STAGGER_LEAN_OUT_TIME: float = 0.15


func _ready() -> void:
	_apply_stats()
	# reset_to rather than a bare write: this component filled itself from the
	# scene's placeholder in its own _ready(), before this one ran.
	health_component.reset_to(max_health)
	hitbox.damage = attack_damage
	hitbox.source = self
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)
	_mesh_rest_quaternion = mesh_instance.quaternion
	_setup_navigation()
	_setup_material()


## Answered from the stats asset rather than copied into the inherited field on
## _ready(), so initialisation order never decides what a kill is worth.
func get_xp_reward() -> int:
	return stats.xp_reward if stats != null else xp_reward


## Seeds this instance from its archetype. With no asset assigned it falls back
## to EnemyData's own defaults — the template a new asset starts from — so even
## the fallback keeps no copy of the numbers in this script.
func _apply_stats() -> void:
	var source: EnemyData = stats
	if source == null:
		push_warning("%s has no EnemyData assigned; falling back to EnemyData's defaults." % name)
		source = EnemyData.new()
	max_health = source.max_health

	movement_speed = source.movement_speed
	acceleration = source.acceleration
	rotation_speed = source.rotation_speed
	gravity = source.gravity

	detection_range = source.detection_range
	lose_target_range = source.lose_target_range
	lose_target_delay = source.lose_target_delay
	eye_height = source.eye_height
	line_of_sight_mask = source.line_of_sight_mask

	attack_range = source.attack_range
	preferred_combat_distance = source.preferred_combat_distance
	minimum_combat_distance = source.minimum_combat_distance
	enemy_spacing_radius = source.enemy_spacing_radius

	attack_damage = source.attack_damage
	attack_startup = source.attack_startup
	attack_active = source.attack_active
	attack_recovery = source.attack_recovery
	attack_cooldown = source.attack_cooldown
	max_attack_facing_angle = source.max_attack_facing_angle
	attack_startup_turn_fraction = source.attack_startup_turn_fraction

	stagger_resistance = source.stagger_resistance
	stagger_duration = source.stagger_duration
	stagger_immunity_time = source.stagger_immunity_time
	knockback_multiplier = source.knockback_multiplier
	knockback_deceleration = source.knockback_deceleration

	reposition_timeout = source.reposition_timeout
	reposition_cooldown = source.reposition_cooldown
	reposition_speed_fraction = source.reposition_speed_fraction
	reposition_arrive_tolerance = source.reposition_arrive_tolerance

	telegraph_color = source.telegraph_color
	active_color = source.active_color
	startup_scale = source.startup_scale
	active_scale = source.active_scale

	target_update_interval = source.target_update_interval


func _setup_navigation() -> void:
	# From the same runtime fields the AI reads, so the agent and the AI agree.
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
	_interrupt_attack()
	_clear_reactions()
	_enter_idle()
	_cooldown_timer = 0.0
	_attack_delay_timer = 0.0
	velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	# Cheap enough to check every frame, and the setter only emits on a real
	# change — far less error-prone than a call at each of the state's exits.
	_set_engaged(combat_enabled and _state != State.IDLE)

	_moved_this_frame = false
	# A stagger runs its course whether or not the AI is awake to follow it.
	_tick_reactions(delta)

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
		State.STAGGERED:
			_stagger_step(delta)


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
	# A push is not the AI's to steer: no avoidance pass may rewrite it.
	if not nav_agent.avoidance_enabled or is_knocked_back():
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


## The one place the body moves. A push in progress replaces whatever the AI
## wanted this frame, through move_and_slide() like any other motion — walls and
## other bodies stop it — and dies out at knockback_deceleration.
func _apply_motion(horizontal: Vector3, delta: float) -> void:
	if _moved_this_frame:
		return
	_moved_this_frame = true
	if is_knocked_back():
		horizontal = _knockback_velocity
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_deceleration * delta)
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


## Cuts off whatever attack is under way: the hit window shut at once — no hit can
## land through it any more — the phase dropped, the telegraph undone.
func _interrupt_attack() -> void:
	if hitbox.is_active():
		hitbox.deactivate()
	_attack_phase = AttackPhase.NONE
	_phase_timer = 0.0
	_reset_telegraph_instantly()


func _enter_stagger(hit: DamageInfo) -> void:
	_interrupt_attack()
	_state = State.STAGGERED
	_stagger_timer = stagger_duration
	# The AI's own speed goes; a push already under way stays — that is the
	# knockback's, and it plays out through the stagger.
	_desired_horizontal = Vector3.ZERO
	_play_stagger_pose(hit.direction)


## Nothing the AI decides runs while staggered: no turning, no pathing, no
## attack. The body only moves if something pushed it.
func _stagger_step(delta: float) -> void:
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)


func _tick_reactions(delta: float) -> void:
	if _stagger_immunity_timer > 0.0:
		_stagger_immunity_timer = maxf(0.0, _stagger_immunity_timer - delta)
	if _state != State.STAGGERED:
		return
	_stagger_timer -= delta
	if _stagger_timer <= 0.0:
		_end_stagger()


## Back under the AI's control, in the state it would pick up from: chasing the
## player it was fighting — CHASE decides again from there — or idle if the
## room has parked it.
func _end_stagger() -> void:
	_stagger_timer = 0.0
	_stagger_immunity_timer = stagger_immunity_time
	_release_stagger_pose()
	if combat_enabled:
		_enter_chase()
	else:
		_enter_idle()


## Drops every reaction in progress: stagger, immunity, push and pose. For a
## death, a room parking the enemy, or a test reviving one.
func _clear_reactions() -> void:
	_stagger_timer = 0.0
	_stagger_immunity_timer = 0.0
	_knockback_velocity = Vector3.ZERO
	if _flinch_tween != null and _flinch_tween.is_running():
		_flinch_tween.kill()
	if _pose_tween != null and _pose_tween.is_running():
		_pose_tween.kill()
	mesh_instance.scale = Vector3.ONE
	mesh_instance.quaternion = _mesh_rest_quaternion
	if _state == State.STAGGERED:
		_state = State.IDLE


func is_staggered() -> bool:
	return _state == State.STAGGERED


func is_stagger_immune() -> bool:
	return _stagger_immunity_timer > 0.0


func is_knocked_back() -> bool:
	return _knockback_velocity != Vector3.ZERO


func get_knockback_velocity() -> Vector3:
	return _knockback_velocity


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
#
# A hit arrives the one way every hit does — Hitbox -> Hurtbox -> HealthComponent
# — and the health component has already taken the damage and decided whether
# it killed. A killing blow is a death (_on_died) and nothing else; a hit that
# leaves the enemy standing arrives here, and gets, in this order: a flinch, a
# stagger if it is strong enough, a push if it pushes.

func _on_damaged(hit: DamageInfo) -> void:
	if _state == State.DEAD:
		return
	_play_flinch()
	var staggers: bool = _staggers(hit)
	if staggers:
		_enter_stagger(hit)
	_apply_knockback(hit)
	if debug_log_reactions:
		print("[%s] hit %s: stagger %.0f vs %.0f%s -> %s, push %.2f m/s" % [
			name, hit.attack_id, hit.stagger_power, stagger_resistance,
			" (immune)" if is_stagger_immune() else "", "STAGGERED" if staggers else "flinch",
			_knockback_velocity.length()])


## One hit, judged alone: strong enough, and not inside a stagger or the
## immunity after one.
func _staggers(hit: DamageInfo) -> bool:
	if hit.stagger_power <= 0.0 or hit.stagger_power < stagger_resistance:
		return false
	return _state != State.STAGGERED and _stagger_immunity_timer <= 0.0


## A push replaces any push still dying out rather than adding to it, so a
## flurry of hits never builds into a launch.
func _apply_knockback(hit: DamageInfo) -> void:
	var speed: float = hit.knockback_force * knockback_multiplier
	if speed <= 0.0 or hit.direction == Vector3.ZERO:
		return
	_knockback_velocity = Vector3(hit.direction.x, 0.0, hit.direction.z).normalized() * speed
	_desired_horizontal = Vector3.ZERO


func _play_flinch() -> void:
	if _flinch_tween != null and _flinch_tween.is_running():
		_flinch_tween.kill()
	_flinch_tween = create_tween()
	_flinch_tween.tween_property(mesh_instance, "scale", FLINCH_SQUASH, 0.05)
	_flinch_tween.tween_property(mesh_instance, "scale", Vector3.ONE, 0.12)


## Leans the body away from the blow, and holds it until the stagger ends.
func _play_stagger_pose(direction: Vector3) -> void:
	var local: Vector3 = visual_root.global_basis.orthonormalized().inverse() * direction
	local.y = 0.0
	if local.length_squared() < 0.0001:
		local = Vector3.BACK
	var axis: Vector3 = Vector3.UP.cross(local.normalized()).normalized()
	var lean: Quaternion = _mesh_rest_quaternion * Quaternion(axis, deg_to_rad(STAGGER_LEAN_DEGREES))
	if _pose_tween != null and _pose_tween.is_running():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(mesh_instance, "quaternion", lean, STAGGER_LEAN_IN_TIME)


func _release_stagger_pose() -> void:
	if _pose_tween != null and _pose_tween.is_running():
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(mesh_instance, "quaternion", _mesh_rest_quaternion, STAGGER_LEAN_OUT_TIME)


## Emits only on a change, so nothing downstream sees a per-frame stream.
func _set_engaged(value: bool) -> void:
	if _engaged == value:
		return
	_engaged = value
	engagement_changed.emit(_engaged)


func is_engaged() -> bool:
	return _engaged


## Death outranks everything: whatever the enemy was doing — attacking, staggered,
## sliding from a push — stops here, and no reaction plays on the killing blow.
func _on_died() -> void:
	_set_engaged(false)
	_interrupt_attack()
	_clear_reactions()
	_state = State.DEAD
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO

	# Leave the avoidance simulation so the living stop steering around a corpse.
	nav_agent.avoidance_enabled = false

	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	body_collision.call_deferred("set_disabled", true)

	var t: Tween = create_tween()
	t.tween_property(visual_root, "rotation:x", deg_to_rad(90.0), 0.4)

	report_death(health_component.last_damage_source)
