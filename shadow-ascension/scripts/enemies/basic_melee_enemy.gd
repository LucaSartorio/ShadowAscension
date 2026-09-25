class_name BasicMeleeEnemy
extends RoomCombatant

## The basic melee enemy, on the enemy AI foundation (M12.1).
##
## Its parts, each with one owner:
##
##     Data        EnemyData (`stats`): the archetype's numbers, copied into the
##                 runtime fields below once; the asset is never written.
##     AI state    this script's state machine: `_state`, changed only through
##                 _change_state(), each state with its enter / update / exit.
##     Target      EnemyTargeting (child node): whom it fights, and when that ends.
##     Movement    this script's movement section: navigation, avoidance, the
##                 push, the one move_and_slide(). The states say where to go;
##                 the movement goes there.
##     Combat      this script's attack section: its phases, hitbox and cooldown.
##     Health      HealthComponent: the AI hears `damaged` and `died`, owns none.
##     Visual      the telegraph and the hit reactions' placeholder poses.
##
## The states, and what moves between them:
##
##     IDLE --target in detection range--> ALERT --alert_duration--> CHASE
##                                          (0 s: both in the same tick)
##     CHASE <--> REPOSITION   (too close, or in range but facing away)
##     CHASE / REPOSITION --attack possible--> ATTACK --recovery over--> CHASE
##     ALERT / CHASE / REPOSITION / ATTACK --target lost--> IDLE
##     any but DEAD --a hit strong enough--> STAGGERED --over--> CHASE, or IDLE
##     any --died--> DEAD, which nothing leaves
##
## Only the transitions in TRANSITIONS are legal, and a state that fights needs a
## target and combat on: anything else is refused. Death outranks everything,
## then the stagger, which nothing the AI decides can cut short.

## Whether this enemy is currently fighting. The world-space health bar listens,
## so it can stay out of the way while the enemy is idle and undamaged.
signal engagement_changed(engaged: bool)
## The AI state changed. Emitted after the new state's enter logic has run.
signal state_changed(from: State, to: State)

## REPOSITION is the chase's own manoeuvre (M5): the state machine keeps it
## because the behaviour needs it.
enum State { IDLE, ALERT, CHASE, REPOSITION, ATTACK, STAGGERED, DEAD }
enum AttackPhase { NONE, STARTUP, ACTIVE, RECOVERY }

## The legal transitions, from each state. Anything missing is refused.
const TRANSITIONS: Dictionary = {
	State.IDLE: [State.ALERT, State.STAGGERED, State.DEAD],
	State.ALERT: [State.IDLE, State.CHASE, State.STAGGERED, State.DEAD],
	State.CHASE: [State.IDLE, State.REPOSITION, State.ATTACK, State.STAGGERED, State.DEAD],
	State.REPOSITION: [State.IDLE, State.CHASE, State.ATTACK, State.STAGGERED, State.DEAD],
	State.ATTACK: [State.IDLE, State.CHASE, State.STAGGERED, State.DEAD],
	State.STAGGERED: [State.IDLE, State.CHASE, State.DEAD],
	State.DEAD: [],
}
## The states that fight: entering one needs a target and combat on, and each
## lets go to IDLE the moment the target is lost.
const FIGHTING_STATES: Array[State] = [State.ALERT, State.CHASE, State.REPOSITION, State.ATTACK]

const AVOIDANCE_FALLBACK_FRAMES: int = 10
## A new path is asked for only when the point to reach has moved at least this
## far (squared, m²) since the last one: a target standing still costs no query.
const NAV_TARGET_MIN_SHIFT_SQUARED: float = 0.01
## PLACEHOLDER hit reactions, until M14's clips: every hit that leaves the enemy
## standing squashes the body; a stagger also leans it away from the blow for as
## long as it lasts.
const FLINCH_SQUASH: Vector3 = Vector3(1.2, 0.85, 1.2)
const STAGGER_LEAN_DEGREES: float = 20.0
const STAGGER_LEAN_IN_TIME: float = 0.08
const STAGGER_LEAN_OUT_TIME: float = 0.15
## DEBUG ONLY: how high the state label floats above the feet.
const DEBUG_LABEL_HEIGHT: float = 2.4

## The archetype's configuration: the one place its numbers exist. Copied into
## the runtime fields below on _ready(); the asset itself is never written to,
## because every enemy of the archetype shares it.
@export var stats: EnemyData

@export_group("Per-Instance")
## Bias of the approach bearing. Non-zero values make instances converge on
## different points around the target instead of the same one.
@export_range(-180.0, 180.0) var combat_angle_offset_degrees: float = 0.0
## Deterministic per-instance desync so a group does not swing in unison.
@export var initial_attack_delay: float = 0.0
@export var attack_cooldown_variation: float = 0.0

@export_group("DEBUG")
## DEBUG ONLY. Off by default. Prints every hit this enemy survives: its stagger
## power against the resistance, whether it staggered, and the push it took.
@export var debug_log_reactions: bool = false
## DEBUG ONLY. Off by default. Prints every state transition — and every one
## refused — with the target and its distance, and every change of target.
@export var debug_log_ai: bool = false
## DEBUG ONLY. Off by default. A label over the enemy: its state, its target and
## the distance to it, and whether its navigation has somewhere to go.
@export var debug_state_label: bool = false

# RUNTIME tuning: this instance's own values, seeded from `stats` in
# _apply_stats() and read by the AI from then on. Instance state — change them
# freely and the shared asset stays untouched. They carry no values of their
# own: the archetype's numbers live in its EnemyData and nowhere in this script.
var max_health: float

var movement_speed: float
var acceleration: float
var rotation_speed: float
var gravity: float

var target_groups: Array[StringName] = []
var detection_range: float
var lose_target_range: float
var lose_target_delay: float
var eye_height: float
var line_of_sight_mask: int
var alert_duration: float

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
@onready var targeting: EnemyTargeting = $EnemyTargeting

## The AI state: the one source of truth, written only by _change_state().
var _state: State = State.IDLE
var _engaged: bool = false

# The state machine's own clocks, each belonging to one state.
var _alert_timer: float = 0.0
var _reposition_timer: float = 0.0
var _reposition_block_timer: float = 0.0
var _stagger_timer: float = 0.0

# Combat — the attack and what gates the next one. The cooldown is the attack's,
# not a state's: it runs down whatever the enemy is doing.
var _attack_phase: AttackPhase = AttackPhase.NONE
var _phase_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _attack_delay_timer: float = 0.0
var _telegraph_tween: Tween = null

# Hit reactions (M11.6), all runtime: the immunity after a stagger and a push.
var _stagger_immunity_timer: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO
var _flinch_tween: Tween = null
var _pose_tween: Tween = null
var _mesh_rest_quaternion: Quaternion = Quaternion.IDENTITY

# Movement.
var _desired_horizontal: Vector3 = Vector3.ZERO
var _pending_delta: float = 0.0
var _moved_this_frame: bool = false
var _frames_without_avoidance: int = 0
var _target_update_accum: float = 0.0
## Where the last path was asked for; INF until the first, so it is always asked.
var _last_nav_point: Vector3 = Vector3.INF
## Checked once, the first time a path is needed: whether this enemy's
## navigation map has anything to walk on at all.
var _navigation_checked: bool = false
var _navigation_missing: bool = false

var _body_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE
var _debug_label: Label3D = null


func _ready() -> void:
	_apply_stats()
	# reset_to rather than a bare write: this component filled itself from the
	# scene's placeholder in its own _ready(), before this one ran.
	health_component.reset_to(max_health)
	hitbox.damage = attack_damage
	hitbox.source = self
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)
	targeting.setup(self, target_groups)
	targeting.target_changed.connect(_on_target_changed)
	_mesh_rest_quaternion = mesh_instance.quaternion
	_setup_navigation()
	_setup_material()
	_setup_debug_label()


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

	target_groups = source.target_groups.duplicate()
	detection_range = source.detection_range
	lose_target_range = source.lose_target_range
	lose_target_delay = source.lose_target_delay
	eye_height = source.eye_height
	line_of_sight_mask = source.line_of_sight_mask
	alert_duration = source.alert_duration

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


# --- queries ------------------------------------------------------------------------

func get_state() -> State:
	return _state


func get_attack_phase() -> AttackPhase:
	return _attack_phase


## Whom this enemy is fighting, or null. EnemyTargeting's answer.
func get_target() -> Node3D:
	return targeting.get_target()


func is_staggered() -> bool:
	return _state == State.STAGGERED


func is_stagger_immune() -> bool:
	return _stagger_immunity_timer > 0.0


func is_knocked_back() -> bool:
	return _knockback_velocity != Vector3.ZERO


func get_knockback_velocity() -> Vector3:
	return _knockback_velocity


func is_engaged() -> bool:
	return _engaged


## Wakes or parks the enemy. Parked, it holds no target and does nothing but
## stand; woken, it starts looking. A dead enemy stays dead.
func set_combat_enabled(enabled: bool) -> void:
	if _state == State.DEAD:
		return
	super.set_combat_enabled(enabled)
	nav_agent.avoidance_enabled = enabled
	if enabled:
		_refresh_engaged()
		return
	_change_state(State.IDLE)
	_clear_reactions()
	_cooldown_timer = 0.0
	_attack_delay_timer = 0.0
	velocity = Vector3.ZERO
	_refresh_engaged()


# --- the state machine ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	_moved_this_frame = false
	_tick_immunity(delta)

	if not combat_enabled:
		# Dormant: no perception, no navigation, no timers. A stagger still runs
		# its course and a push still plays out; otherwise gravity only, so the
		# body rests on the floor.
		if _state == State.STAGGERED:
			_update_staggered(delta)
		else:
			_desired_horizontal = Vector3.ZERO
			_apply_motion(Vector3.ZERO, delta)
		return

	_tick_timers(delta)
	# A fighting state with no valid target — dead, freed, gone — lets go first.
	if FIGHTING_STATES.has(_state) and not targeting.validate():
		_change_state(State.IDLE)
		return

	match _state:
		State.IDLE:
			_update_idle(delta)
		State.ALERT:
			_update_alert(delta)
		State.CHASE:
			_update_chase(delta)
		State.REPOSITION:
			_update_reposition(delta)
		State.ATTACK:
			_update_attack(delta)
		State.STAGGERED:
			_update_staggered(delta)


## The one way the state changes: the old state's exit, the new one's enter,
## then the announcement. A transition TRANSITIONS does not list, a fighting
## state without a target or with combat off, and a state re-entering itself are
## refused, and the state stays as it was. True when the state changed.
func _change_state(to: State) -> bool:
	var from: State = _state
	if to == from:
		return false
	if not _can_transition(from, to):
		_log_ai("refused %s -> %s" % [State.keys()[from], State.keys()[to]])
		return false
	_exit_state(from)
	_state = to
	_enter_state(to)
	_refresh_engaged()
	_log_ai("%s -> %s" % [State.keys()[from], State.keys()[to]])
	state_changed.emit(from, to)
	return true


func _can_transition(from: State, to: State) -> bool:
	if not (TRANSITIONS[from] as Array).has(to):
		return false
	if FIGHTING_STATES.has(to):
		return combat_enabled and targeting.has_target()
	return true


func _enter_state(state: State) -> void:
	match state:
		State.IDLE:
			_desired_horizontal = Vector3.ZERO
			targeting.release()
		State.ALERT:
			_desired_horizontal = Vector3.ZERO
			_alert_timer = alert_duration
			# The moment a fight is picked up is when a group's swings desync.
			_attack_delay_timer = initial_attack_delay
		State.CHASE:
			# Ask for a path on the first tick rather than one interval in.
			_target_update_accum = target_update_interval
			_last_nav_point = Vector3.INF
		State.REPOSITION:
			_reposition_timer = reposition_timeout
			_target_update_accum = target_update_interval
			_last_nav_point = Vector3.INF
		State.ATTACK:
			_start_attack()
		State.STAGGERED:
			_stagger_timer = stagger_duration
			# The AI's own speed goes; a push already under way stays — that is
			# the knockback's, and it plays out through the stagger.
			_desired_horizontal = Vector3.ZERO
		State.DEAD:
			_enter_dead()


func _exit_state(state: State) -> void:
	match state:
		State.ATTACK:
			# Finished attacks have already ended their phase; anything else is
			# cut off here, so no hit window outlives the state.
			if _attack_phase != AttackPhase.NONE:
				_interrupt_attack()
		State.STAGGERED:
			_stagger_timer = 0.0
			_stagger_immunity_timer = stagger_immunity_time
			_release_stagger_pose()


func _update_idle(delta: float) -> void:
	_hold_position(delta)
	if targeting.acquire(detection_range, delta) and _change_state(State.ALERT):
		# An alert of no length is noticed and acted on in the same tick, so a
		# reaction of 0 s costs no time at all.
		if alert_duration <= 0.0:
			_update_alert(delta)


## Noticed, not yet after it: stands, turns to face the target, and goes after
## it once alert_duration is over.
func _update_alert(delta: float) -> void:
	_hold_position(delta)
	if targeting.tick_lose(delta, lose_target_range, lose_target_delay):
		return
	_rotate_toward_target(delta, rotation_speed)
	_alert_timer -= delta
	if _alert_timer <= 0.0:
		_change_state(State.CHASE)


func _update_chase(delta: float) -> void:
	if targeting.tick_lose(delta, lose_target_range, lose_target_delay):
		return
	var dist: float = targeting.get_distance()
	if _can_start_attack(dist):
		_change_state(State.ATTACK)
		return
	if _reposition_block_timer <= 0.0 and _needs_reposition(dist):
		_change_state(State.REPOSITION)
		return

	_update_nav_target(delta, _combat_slot_position())
	var dir: Vector3 = _path_direction()
	# Spacing: once on the ring, hold position instead of grinding into the target.
	var speed: float = 0.0 if dist <= preferred_combat_distance else movement_speed
	_drive(_accelerate_toward(dir * speed, delta), delta)

	if speed > 0.0 and dir.length_squared() > 0.001:
		_rotate_visual_toward(dir, delta, rotation_speed)
	else:
		_rotate_toward_target(delta, rotation_speed)


func _needs_reposition(dist: float) -> bool:
	if dist < minimum_combat_distance:
		return true
	if dist <= attack_range and _facing_error_to(targeting.get_target()) > deg_to_rad(max_attack_facing_angle):
		return true
	return false


func _update_reposition(delta: float) -> void:
	if targeting.tick_lose(delta, lose_target_range, lose_target_delay):
		return

	_reposition_timer -= delta
	if _reposition_timer <= 0.0:
		# Fallback: never sit in REPOSITION forever. Hand back to CHASE and block
		# immediate re-entry so the two states cannot ping-pong.
		_reposition_block_timer = reposition_cooldown
		_change_state(State.CHASE)
		return

	var dist: float = targeting.get_distance()
	if _can_start_attack(dist):
		_change_state(State.ATTACK)
		return

	var slot: Vector3 = _combat_slot_position()
	_update_nav_target(delta, slot)
	var dir: Vector3 = _path_direction()
	var speed: float = movement_speed * reposition_speed_fraction
	var in_band: bool = dist >= minimum_combat_distance and dist <= attack_range
	if in_band and global_position.distance_to(slot) < reposition_arrive_tolerance:
		speed = 0.0
	_drive(_accelerate_toward(dir * speed, delta), delta)

	# Reposition always turns to face the target, never the movement direction.
	_rotate_toward_target(delta, rotation_speed)


## One attack, start to end, standing still. STARTUP corrects facing slowly;
## ACTIVE and RECOVERY do not turn at all, so the swing commits to where it was
## aimed and can be sidestepped. Over, it goes back to chasing, where the next
## one waits for the cooldown.
func _update_attack(delta: float) -> void:
	_hold_position(delta)
	if _attack_phase == AttackPhase.STARTUP:
		_rotate_toward_target(delta, rotation_speed * attack_startup_turn_fraction)
	if _advance_attack(delta):
		_change_state(State.CHASE)


## Nothing the AI decides runs while staggered: no turning, no pathing, no
## attack. The body only moves if something pushed it.
func _update_staggered(delta: float) -> void:
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)
	_stagger_timer -= delta
	if _stagger_timer <= 0.0:
		_end_stagger()


## Back under the AI's control, in the state it would pick up from: chasing the
## target it was fighting — CHASE decides again from there — or idle if it has
## none, or the room has parked it.
func _end_stagger() -> void:
	if combat_enabled and targeting.validate():
		_change_state(State.CHASE)
	else:
		_change_state(State.IDLE)


func _tick_timers(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
	if _attack_delay_timer > 0.0:
		_attack_delay_timer = maxf(0.0, _attack_delay_timer - delta)
	if _reposition_block_timer > 0.0:
		_reposition_block_timer = maxf(0.0, _reposition_block_timer - delta)


## The target is gone — dead, freed, out of reach too long. A fighting state
## stops fighting; a stagger ends on its own time and finds nobody to chase.
func _on_target_changed(target: Node3D) -> void:
	if target != null:
		_log_ai("target %s at %.1f m" % [target.name, targeting.get_distance()])
		return
	_log_ai("target lost")
	if FIGHTING_STATES.has(_state):
		_change_state(State.IDLE)


# --- movement -------------------------------------------------------------------------
#
# What the states ask for: hold position, or go toward a point at a speed. How
# it happens — navigation, avoidance, a push overriding everything, gravity —
# is decided here, and nowhere in the states.

## Stands still, still inside the avoidance simulation.
func _hold_position(delta: float) -> void:
	_desired_horizontal = Vector3.ZERO
	_drive(Vector3.ZERO, delta)


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


## Every target_update_interval, and only when the point has really moved: a
## path is a query, and a target standing still needs no new one.
func _update_nav_target(delta: float, point: Vector3) -> void:
	_target_update_accum += delta
	if _target_update_accum < target_update_interval:
		return
	_target_update_accum = 0.0
	if point.distance_squared_to(_last_nav_point) >= NAV_TARGET_MIN_SHIFT_SQUARED:
		_last_nav_point = point
		nav_agent.target_position = point


func _path_direction() -> Vector3:
	var to_next: Vector3 = nav_agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length_squared() < 0.00000001:
		if not _has_navigation():
			# Nothing to walk on: steer straight at the point instead of freezing.
			to_next = nav_agent.target_position - global_position
			to_next.y = 0.0
		if to_next.length_squared() < 0.00000001:
			return Vector3.ZERO
	return to_next.normalized()


## Whether this enemy's navigation map has a region at all — asked once. A scene
## without one is a mistake worth saying out loud, once, rather than an enemy
## that silently stands still.
func _has_navigation() -> bool:
	if not _navigation_checked:
		_navigation_checked = true
		var map: RID = nav_agent.get_navigation_map()
		_navigation_missing = not map.is_valid() or NavigationServer3D.map_get_regions(map).is_empty()
		if _navigation_missing:
			push_warning("%s: its navigation map has no region — no baked NavigationRegion3D in this scene? It steers straight at its target instead." % name)
	return not _navigation_missing


## The point this instance wants to occupy: on the preferred-distance ring around
## the target, biased by combat_angle_offset_degrees so instances do not stack.
func _combat_slot_position() -> Vector3:
	var center: Vector3 = targeting.get_target_position()
	var from_target: Vector3 = global_position - center
	from_target.y = 0.0
	if from_target.length_squared() < 0.0001:
		from_target = Vector3.BACK
	var dir: Vector3 = from_target.normalized().rotated(Vector3.UP, deg_to_rad(combat_angle_offset_degrees))
	return center + dir * preferred_combat_distance


# --- facing ---------------------------------------------------------------------------

func _rotate_visual_toward(world_dir: Vector3, delta: float, speed: float) -> void:
	var target_yaw: float = atan2(-world_dir.x, -world_dir.z)
	var diff: float = wrapf(target_yaw - visual_root.rotation.y, -PI, PI)
	var step: float = speed * delta
	visual_root.rotation.y += clampf(diff, -step, step)


func _rotate_toward_target(delta: float, speed: float) -> void:
	var to_target: Vector3 = targeting.get_flat_offset()
	if to_target.length_squared() < 0.0001:
		return
	_rotate_visual_toward(to_target.normalized(), delta, speed)


## How far, in radians, the enemy's facing is off `target`, flat. 0 with no target.
func _facing_error_to(target: Node3D) -> float:
	if target == null:
		return 0.0
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	var forward: Vector3 = -visual_root.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return PI
	return absf(forward.normalized().signed_angle_to(to_target.normalized(), Vector3.UP))


# --- perception -----------------------------------------------------------------------

func _has_line_of_sight(target: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from_point: Vector3 = global_position + Vector3.UP * eye_height
	var to_point: Vector3 = target.global_position + Vector3.UP * eye_height
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_point, to_point, line_of_sight_mask
	)
	var target_body: CollisionObject3D = target as CollisionObject3D
	query.exclude = [get_rid(), target_body.get_rid()] if target_body != null else [get_rid()]
	return space.intersect_ray(query).is_empty()


# --- the attack -------------------------------------------------------------------------
#
# One melee swing: STARTUP (telegraphed, the hitbox shut) -> ACTIVE (the hitbox
# open) -> RECOVERY (shut again, committed) -> over, with the cooldown started.
# The state machine only asks whether one may start, starts it, advances it and,
# when the state is left early, has it cut off.

## Whether a swing may start now, `dist` away from the target: off cooldown and
## past the initial desync, inside the attack band, facing it, and seeing it.
func _can_start_attack(dist: float) -> bool:
	if _cooldown_timer > 0.0 or _attack_delay_timer > 0.0:
		return false
	if dist > attack_range or dist < minimum_combat_distance:
		return false
	var target: Node3D = targeting.get_target()
	if target == null or _facing_error_to(target) > deg_to_rad(max_attack_facing_angle):
		return false
	return _has_line_of_sight(target)


func _start_attack() -> void:
	_attack_phase = AttackPhase.STARTUP
	_phase_timer = attack_startup
	_desired_horizontal = Vector3.ZERO
	_telegraph_startup()


## Runs the swing on; true on the tick it is over — cooldown started, phase
## dropped. Timed on delta alone, so it always ends: no clip, no callback.
func _advance_attack(delta: float) -> bool:
	_phase_timer -= delta
	if _phase_timer > 0.0:
		return false
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
			return true
	return false


## Cuts off whatever attack is under way: the hit window shut at once — no hit can
## land through it any more — the phase dropped, the telegraph undone. No
## cooldown: what cut it off (a stagger, a death, a lost target) is delay enough.
func _interrupt_attack() -> void:
	if hitbox.is_active():
		hitbox.deactivate()
	_attack_phase = AttackPhase.NONE
	_phase_timer = 0.0
	_reset_telegraph_instantly()


# --- telegraph ---------------------------------------------------------------------------

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


# --- damage, reactions, death ------------------------------------------------------------
#
# A hit arrives the one way every hit does — Hitbox -> Hurtbox -> HealthComponent
# — and the health component has already taken the damage and decided whether
# it killed. A killing blow is a death (_on_died) and nothing else; a hit that
# leaves the enemy standing arrives here, and gets, in this order: a flinch, a
# stagger if it is strong enough, a push if it pushes. Whether it was critical
# changes none of it.

func _on_damaged(hit: DamageInfo) -> void:
	if _state == State.DEAD:
		return
	_play_flinch()
	var staggers: bool = _staggers(hit)
	if staggers:
		_enter_stagger(hit)
	_apply_knockback(hit)
	if debug_log_reactions:
		print("[%s] hit %s%s: stagger %.0f vs %.0f%s -> %s, push %.2f m/s" % [
			name, hit.attack_id, " (critical)" if hit.is_critical else "", hit.stagger_power, stagger_resistance,
			" (immune)" if is_stagger_immune() else "", "STAGGERED" if staggers else "flinch",
			_knockback_velocity.length()])


## One hit, judged alone: strong enough, and not inside a stagger or the
## immunity after one.
func _staggers(hit: DamageInfo) -> bool:
	if hit.stagger_power <= 0.0 or hit.stagger_power < stagger_resistance:
		return false
	return _state != State.STAGGERED and _stagger_immunity_timer <= 0.0


## Leaving ATTACK cuts the swing off (its exit), and the stagger begins.
func _enter_stagger(hit: DamageInfo) -> void:
	if _change_state(State.STAGGERED):
		_play_stagger_pose(hit.direction)


## A push replaces any push still dying out rather than adding to it, so a
## flurry of hits never builds into a launch.
func _apply_knockback(hit: DamageInfo) -> void:
	var speed: float = hit.knockback_force * knockback_multiplier
	if speed <= 0.0 or hit.direction == Vector3.ZERO:
		return
	_knockback_velocity = Vector3(hit.direction.x, 0.0, hit.direction.z).normalized() * speed
	_desired_horizontal = Vector3.ZERO


func _tick_immunity(delta: float) -> void:
	if _stagger_immunity_timer > 0.0:
		_stagger_immunity_timer = maxf(0.0, _stagger_immunity_timer - delta)


## Drops every reaction in progress: stagger, immunity, push and pose. For a
## death, a room parking the enemy, or a test reviving one.
func _clear_reactions() -> void:
	if _state == State.STAGGERED:
		_change_state(State.IDLE)
	_stagger_timer = 0.0
	_stagger_immunity_timer = 0.0
	_knockback_velocity = Vector3.ZERO
	if _flinch_tween != null and _flinch_tween.is_running():
		_flinch_tween.kill()
	if _pose_tween != null and _pose_tween.is_running():
		_pose_tween.kill()
	mesh_instance.scale = Vector3.ONE
	mesh_instance.quaternion = _mesh_rest_quaternion


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


## Fighting while combat is on and the state is anything but IDLE (or DEAD).
## Emits only on a change, so nothing downstream sees a per-frame stream.
func _refresh_engaged() -> void:
	var engaged: bool = combat_enabled and _state != State.IDLE and _state != State.DEAD
	if _engaged == engaged:
		return
	_engaged = engaged
	engagement_changed.emit(_engaged)


## Death outranks everything: whatever the enemy was doing — attacking, staggered,
## sliding from a push — stops here, and no reaction plays on the killing blow.
## The reward is not this script's: the death is reported, and PlayerProgression
## decides who collects (the player all of it, or a shadow 70% of its kill).
func _on_died() -> void:
	_change_state(State.DEAD)
	report_death(health_component.last_damage_source)


func _enter_dead() -> void:
	_clear_reactions()
	targeting.release()
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO

	# Stop navigating, and leave the avoidance simulation so the living stop
	# steering around a corpse.
	nav_agent.target_position = global_position
	nav_agent.avoidance_enabled = false

	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	body_collision.call_deferred("set_disabled", true)

	var t: Tween = create_tween()
	t.tween_property(visual_root, "rotation:x", deg_to_rad(90.0), 0.4)


# --- debug ----------------------------------------------------------------------------------

func _log_ai(what: String) -> void:
	if not debug_log_ai:
		return
	var target: Node3D = targeting.get_target() if targeting != null else null
	print("[%s] %s  target=%s  distance=%.1fm" % [name, what,
		String(target.name) if target != null else "-", targeting.get_distance() if target != null else 0.0])


## DEBUG ONLY: built only when asked for, and updated only while it exists.
func _setup_debug_label() -> void:
	if not debug_state_label:
		set_process(false)
		return
	_debug_label = Label3D.new()
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.position = Vector3.UP * DEBUG_LABEL_HEIGHT
	add_child(_debug_label)


func _process(_delta: float) -> void:
	if _debug_label == null:
		return
	var target: Node3D = targeting.get_target()
	var navigation: String = "no path" if nav_agent.is_navigation_finished() else "pathing"
	if _navigation_missing:
		navigation = "NO NAVIGATION"
	_debug_label.text = "%s%s\n%s %s" % [State.keys()[_state],
		" (%s)" % AttackPhase.keys()[_attack_phase] if _attack_phase != AttackPhase.NONE else "",
		"%s %.1fm" % [target.name, targeting.get_distance()] if target != null else "no target", navigation]
