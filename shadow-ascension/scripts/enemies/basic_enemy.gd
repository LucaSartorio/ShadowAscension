class_name BasicEnemy
extends RoomCombatant

## An enemy on the AI foundation (M12.1): the state machine every enemy
## archetype runs — the melee (M12.2), the ranged (M12.3), the tank (M12.4), the
## assassin (M12.5), the support (M12.6). Named BasicMeleeEnemy until M12.3, when
## it stopped being the melee's alone. Nothing here asks which archetype it is: an
## archetype is the parts its scene gives it (the `Attack` node: EnemyMeleeAttack,
## EnemyRangedAttack, EnemySupportAttack; a support's `Support` node) and the
## EnemyData that tunes it — `basic_melee_enemy.tres`, `basic_ranged_enemy.tres`.
##
## Its parts, each with one owner:
##
##     Data        EnemyData (`stats`): the archetype's numbers, copied into the
##                 runtime fields below once; the asset is never written.
##     Rank        `elite_profile` (M12.7): null for a normal enemy; an elite's
##                 EliteModifierData scales those numbers as they are copied —
##                 the same scene, script and AI, other values.
##     AI state    this script's state machine: `_state`, changed only through
##                 _change_state(), each state with its enter / update / exit.
##     Target      EnemyTargeting (child node): whom it fights, and when that ends.
##     Movement    this script's movement section: navigation, avoidance, the
##                 push, the one move_and_slide(). The states say where to go;
##                 the movement goes there.
##     Combat      EnemyAttack (child node `Attack`): the archetype's attacks and
##                 the attack under way — telegraph, active, recovery — and its
##                 cooldown. The state machine decides when to attack; the
##                 attack decides what the attack is.
##     Support     EnemySupport (child node `Support`, a support's only): the ally
##                 it supports and what it means to do for it (M12.6). Optional:
##                 without one, an enemy supports nobody.
##     Health      HealthComponent: the AI hears `damaged` and `died`, owns none.
##     Visual      the hit reactions' placeholder poses (the telegraph is the attack's).
##
## The distance it keeps is data, the same rule for every archetype: close in to
## the `preferred_combat_distance` ring and hold there; attack from anywhere
## between `minimum_combat_distance` and `attack_range`; nearer than the minimum,
## step back to the ring (REPOSITION). A melee's ring is 1.6 m, a ranged's 7 m.
## An archetype with a `disengage_distance` (the assassin, M12.5) keeps that wider
## ring instead while its attack cools down: it strikes, backs off, and comes
## back in when it may strike again.
##
## A support (M12.6) keeps its ring like a ranged, and while it has an ally to
## support it walks into reach and sight of that ally instead, and casts: the
## cast is an ATTACK like any other — the same states, no new one.
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
## What it is, as far as danger goes (M12.7): read from `elite_profile`, never
## stored beside it. No rarity ladder: normal, or elite.
enum Rank { NORMAL, ELITE }

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
## Makes this enemy an elite (M12.7): its archetype's numbers scaled by this
## profile as they are copied — set by whatever places it, like the fields above.
## Null: a normal enemy. Shared by every elite that uses it; never written.
@export var elite_profile: EliteModifierData = null

@export_group("DEBUG")
## DEBUG ONLY. Off by default. Prints every hit this enemy survives: its stagger
## power against the resistance, whether it staggered, and the push it took.
@export var debug_log_reactions: bool = false
## DEBUG ONLY. Off by default. Prints every state transition — and every one
## refused — with the target and its distance, and every change of target.
@export var debug_log_ai: bool = false
## DEBUG ONLY. Off by default. A label over the enemy: its state and attack phase
## (TELEGRAPH, ACTIVE, RECOVERY), its target and the distance to it, whether
## its navigation has somewhere to go, and for an elite its base and effective
## health and damage.
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
var line_of_sight_interval: float
var alert_duration: float

var attack_range: float
var preferred_combat_distance: float
var minimum_combat_distance: float
var enemy_spacing_radius: float
var disengage_distance: float

var max_attack_facing_angle: float

var stagger_resistance: float
var stagger_duration: float
var stagger_immunity_time: float
var knockback_multiplier: float
var knockback_deceleration: float

var reposition_timeout: float
var reposition_cooldown: float
var reposition_speed_fraction: float
var reposition_arrive_tolerance: float

var target_update_interval: float

@onready var visual_root: Node3D = $VisualRoot
@onready var mesh_instance: MeshInstance3D = $VisualRoot/MeshInstance3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hurtbox_collision: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var targeting: EnemyTargeting = $EnemyTargeting
@onready var attack: EnemyAttack = $Attack
## Optional: only a support's scene has one.
@onready var support: EnemySupport = get_node_or_null("Support") as EnemySupport

## The AI state: the one source of truth, written only by _change_state().
var _state: State = State.IDLE
var _engaged: bool = false

# The state machine's own clocks, each belonging to one state.
var _alert_timer: float = 0.0
var _reposition_timer: float = 0.0
var _reposition_block_timer: float = 0.0
var _stagger_timer: float = 0.0

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

# Perception: the last answer to "is the target in sight?", and how old it is.
# INF until the first ray, and again whenever the target changes.
var _in_sight: bool = false
var _sight_age: float = INF

var _debug_label: Label3D = null
## The neutral profile a normal enemy is scaled by — every multiplier 1.0 — made
## the first time it is needed; an elite uses its own.
var _neutral_rank: EliteModifierData = null


func _ready() -> void:
	_apply_stats()
	# reset_to rather than a bare write: this component filled itself from the
	# scene's placeholder in its own _ready(), before this one ran.
	health_component.reset_to(max_health)
	attack.setup(self, targeting, visual_root, mesh_instance)
	if support != null:
		support.setup(self, targeting, attack)
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)
	targeting.setup(self, target_groups)
	targeting.target_changed.connect(_on_target_changed)
	_mesh_rest_quaternion = mesh_instance.quaternion
	_setup_navigation()
	_setup_debug_label()


## Answered from the stats asset rather than copied into the inherited field on
## _ready(), so initialisation order never decides what a kill is worth — an
## elite's through its profile (M12.7), the total PlayerProgression then pays
## once and splits for a shadow's kill.
func get_xp_reward() -> int:
	return get_rank_profile().effective_xp_reward(stats.xp_reward) if stats != null else xp_reward


func get_rank() -> Rank:
	return Rank.ELITE if elite_profile != null else Rank.NORMAL


func is_elite() -> bool:
	return elite_profile != null


## The profile its numbers are scaled by: its elite profile, or the neutral one.
func get_rank_profile() -> EliteModifierData:
	if elite_profile != null:
		return elite_profile
	if _neutral_rank == null:
		_neutral_rank = EliteModifierData.new()
	return _neutral_rank


## Seeds this instance from its archetype. With no asset assigned it falls back
## to EnemyData's own defaults — the template a new asset starts from — so even
## the fallback keeps no copy of the numbers in this script.
##
## The rank (M12.7) is applied here, before anything is built on these values:
## base (EnemyData) -> its profile -> the runtime copy — max health (then filled
## to it by _ready()), speed, stagger resistance, knockback, and through the
## attack its damage and cooldown. Once, for its whole life: nothing here is
## recomputed per frame, and the shared assets are only read.
func _apply_stats() -> void:
	var source: EnemyData = stats
	if source == null:
		push_warning("%s has no EnemyData assigned; falling back to EnemyData's defaults." % name)
		source = EnemyData.new()
	var rank: EliteModifierData = get_rank_profile()
	if not rank.is_valid():
		push_warning("%s: its elite profile has a multiplier that is not a positive number; it is clamped." % name)
	max_health = rank.effective_max_health(source.max_health)

	movement_speed = rank.effective_movement_speed(source.movement_speed)
	acceleration = source.acceleration
	rotation_speed = source.rotation_speed
	gravity = source.gravity

	target_groups = source.target_groups.duplicate()
	detection_range = source.detection_range
	lose_target_range = source.lose_target_range
	lose_target_delay = source.lose_target_delay
	eye_height = source.eye_height
	line_of_sight_mask = source.line_of_sight_mask
	line_of_sight_interval = source.line_of_sight_interval
	alert_duration = source.alert_duration

	attack_range = source.attack_range
	preferred_combat_distance = source.preferred_combat_distance
	minimum_combat_distance = source.minimum_combat_distance
	enemy_spacing_radius = source.enemy_spacing_radius
	disengage_distance = source.disengage_distance

	max_attack_facing_angle = source.max_attack_facing_angle
	attack.configure(source, rank)
	# A support's heal and buff are not scaled by its rank: an elite support is a
	# tougher, harder-hitting healer, not a stronger heal.
	if support != null:
		support.configure(source)

	stagger_resistance = rank.effective_stagger_resistance(source.stagger_resistance)
	stagger_duration = source.stagger_duration
	stagger_immunity_time = source.stagger_immunity_time
	knockback_multiplier = rank.effective_knockback_multiplier(source.knockback_multiplier)
	knockback_deceleration = source.knockback_deceleration

	reposition_timeout = source.reposition_timeout
	reposition_cooldown = source.reposition_cooldown
	reposition_speed_fraction = source.reposition_speed_fraction
	reposition_arrive_tolerance = source.reposition_arrive_tolerance

	target_update_interval = source.target_update_interval


func _setup_navigation() -> void:
	# From the same runtime fields the AI reads, so the agent and the AI agree.
	nav_agent.radius = enemy_spacing_radius
	nav_agent.max_speed = movement_speed
	nav_agent.avoidance_enabled = combat_enabled
	nav_agent.velocity_computed.connect(_on_velocity_computed)


# --- queries ------------------------------------------------------------------------

func get_state() -> State:
	return _state


## Where the attack under way is — EnemyAttack's answer.
func get_attack_phase() -> EnemyAttack.Phase:
	return attack.get_phase()


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
	attack.reset()
	if support != null:
		support.reset()
	_sight_age = INF
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
			attack.hold_off(initial_attack_delay)
		State.CHASE:
			# Ask for a path on the first tick rather than one interval in.
			_target_update_accum = target_update_interval
			_last_nav_point = Vector3.INF
		State.REPOSITION:
			_reposition_timer = reposition_timeout
			_target_update_accum = target_update_interval
			_last_nav_point = Vector3.INF
		State.ATTACK:
			_desired_horizontal = Vector3.ZERO
			attack.start(attack.select_attack(), attack_cooldown_variation)
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
			# A finished attack has already ended; anything else is cut off here,
			# so no hit window outlives the state and no shot is fired after it.
			if attack.is_attacking():
				attack.interrupt()
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
	if _is_supporting():
		_move_to_support(delta)
		return

	# On the ring but unable to see the target — a wall between them — holding
	# there would wait for ever: it closes in on the target itself, down to the
	# minimum distance, until it sees it again.
	var ring: float = _ring_distance()
	var blind: bool = dist <= ring and not _target_in_sight()
	var point: Vector3 = targeting.get_target_position() if blind else _combat_slot_position()
	var stop_at: float = minimum_combat_distance if blind else ring
	_update_nav_target(delta, point)
	var dir: Vector3 = _path_direction()
	# Spacing: brake on the way in and hold on the ring, rather than grinding
	# into the target or sliding past the ring on the deceleration.
	var speed: float = _arrival_speed(dist - stop_at)
	_drive(_accelerate_toward(dir * speed, delta), delta)

	if speed > 0.0 and dir.length_squared() > 0.001:
		_rotate_visual_toward(dir, delta, rotation_speed)
	else:
		_rotate_toward_target(delta, rotation_speed)


## The speed from which `remaining` metres are just enough to stop at
## `acceleration`: the full movement speed far out, easing to nothing on arrival.
func _arrival_speed(remaining: float) -> float:
	if remaining <= 0.0:
		return 0.0
	return minf(movement_speed, sqrt(2.0 * acceleration * remaining))


## The ring it keeps now: its preferred distance — or, while it disengages, its
## disengage distance.
func _ring_distance() -> float:
	return disengage_distance if is_disengaging() else preferred_combat_distance


## Whether it is keeping its distance between two attacks (M12.5): an archetype
## that disengages, with its attack cooling down. The cooldown is the one record
## of "it has just attacked" — nothing else is kept for it.
func is_disengaging() -> bool:
	return disengage_distance > 0.0 and attack.get_cooldown_remaining() > 0.0


func _needs_reposition(dist: float) -> bool:
	if dist < minimum_combat_distance:
		return true
	if is_disengaging() and dist < disengage_distance - reposition_arrive_tolerance:
		return true
	# Turned to an ally it is about to support, it is not facing away by mistake.
	if _is_supporting():
		return false
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
	var arrived: bool = global_position.distance_to(slot) < reposition_arrive_tolerance
	if arrived and is_disengaging():
		# Backed off to its disengage ring: CHASE holds it there until the
		# cooldown ends, then brings it back in.
		_change_state(State.CHASE)
		return
	_update_nav_target(delta, slot)
	var dir: Vector3 = _path_direction()
	var speed: float = movement_speed * reposition_speed_fraction
	var in_band: bool = dist >= minimum_combat_distance and dist <= attack_range
	if in_band and arrived:
		speed = 0.0
	_drive(_accelerate_toward(dir * speed, delta), delta)

	# Reposition always turns to face the target, never the movement direction.
	_rotate_toward_target(delta, rotation_speed)


## One attack, start to end, standing still — navigation does not pull it along.
## It turns only as the attack allows: slowly early in the telegraph, not at all
## from telegraph_facing_lock before ACTIVE, so the attack commits to where it
## was aimed. Over, it goes back to chasing, where the next one waits for the
## cooldown — or, if the attack was withheld, where it moves to be able to.
func _update_attack(delta: float) -> void:
	var lunge: float = attack.get_lunge_speed()
	if lunge > 0.0:
		# A lunge (M12.5): along the facing, locked since before ACTIVE, through
		# the physics — walls and bodies stop it — and past no avoidance pass that
		# could bend it after anyone.
		_desired_horizontal = _facing_direction() * lunge
		_apply_motion(_desired_horizontal, delta)
	else:
		_hold_position(delta)
	var turn: float = attack.get_turn_factor()
	var facing: Node3D = attack.get_facing_target()
	if turn > 0.0 and facing != null:
		_rotate_toward_point(facing.global_position, delta, rotation_speed * turn)
	if attack.advance(delta):
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
	attack.tick(delta)
	if support != null:
		support.tick(delta, FIGHTING_STATES.has(_state))
	_sight_age += delta
	if _reposition_block_timer > 0.0:
		_reposition_block_timer = maxf(0.0, _reposition_block_timer - delta)


## The target is gone — dead, freed, out of reach too long. A fighting state
## stops fighting; a stagger ends on its own time and finds nobody to chase.
func _on_target_changed(target: Node3D) -> void:
	_sight_age = INF
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
	# A push is not the AI's to steer: no avoidance pass may rewrite it. Nor is
	# the last stretch of a finished path: the agent calls it arrived
	# target_desired_distance short and stops passing velocities to avoidance,
	# whose answer is then zero — short of a slot on the preferred ring, that
	# froze an enemy just out of attack range, never to swing.
	if not nav_agent.avoidance_enabled or is_knocked_back() or nav_agent.is_navigation_finished():
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


## Whether it has an ally to support (M12.6): then it goes to that ally rather
## than to its ring, and fires nothing at the foe until it has cast.
func _is_supporting() -> bool:
	return support != null and support.has_plan()


## Toward the ally it supports, until it could cast on it — in reach and in
## sight — then holding there, turned to it, for its attack to be ready. Walking
## toward the ally is also how a wall between them is got round. The ring and the
## retreat still come first: CHASE checks the player pressing it before this.
func _move_to_support(delta: float) -> void:
	var ally: Node3D = support.get_support_target()
	if support.can_cast():
		_hold_position(delta)
		_rotate_toward_point(ally.global_position, delta, rotation_speed)
		return
	var to_ally: Vector3 = ally.global_position - global_position
	to_ally.y = 0.0
	_update_nav_target(delta, ally.global_position)
	var dir: Vector3 = _path_direction()
	# Two bodies' personal space short of it: never into it.
	var speed: float = _arrival_speed(to_ally.length() - enemy_spacing_radius * 2.0)
	_drive(_accelerate_toward(dir * speed, delta), delta)
	if speed > 0.0 and dir.length_squared() > 0.001:
		_rotate_visual_toward(dir, delta, rotation_speed)
	else:
		_rotate_toward_point(ally.global_position, delta, rotation_speed)


## The point this instance wants to occupy: on its ring around the target (the
## preferred distance, or the disengage distance while it disengages), biased by
## combat_angle_offset_degrees so instances do not stack.
func _combat_slot_position() -> Vector3:
	var center: Vector3 = targeting.get_target_position()
	var from_target: Vector3 = global_position - center
	from_target.y = 0.0
	if from_target.length_squared() < 0.0001:
		from_target = Vector3.BACK
	var dir: Vector3 = from_target.normalized().rotated(Vector3.UP, deg_to_rad(combat_angle_offset_degrees))
	return center + dir * _ring_distance()


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


func _rotate_toward_point(point: Vector3, delta: float, speed: float) -> void:
	var to_point: Vector3 = point - global_position
	to_point.y = 0.0
	if to_point.length_squared() < 0.0001:
		return
	_rotate_visual_toward(to_point.normalized(), delta, speed)


## Where the enemy faces, flat and of length 1.
func _facing_direction() -> Vector3:
	var forward: Vector3 = -visual_root.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.ZERO


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

## Whether the target is in sight, from a ray at most line_of_sight_interval old:
## asked every tick, it costs one ray an interval, not one a tick.
func _target_in_sight() -> bool:
	if _sight_age >= line_of_sight_interval:
		_sight_age = 0.0
		var target: Node3D = targeting.get_target()
		_in_sight = target != null and _has_line_of_sight(target)
	return _in_sight


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


# --- when to attack -----------------------------------------------------------------------
#
# The attack itself is the archetype's (EnemyAttack); what the state machine
# judges is whether one may start from here.

## Whether an attack may start now, `dist` away from the target: the attack ready
## (none under way, off cooldown, past the desync), inside the attack band,
## facing the target, and seeing it. A support's cast (M12.6) needs none of the
## last three — its own reach and sight of the ally are the support's to judge —
## but not with the player inside its minimum distance: it steps back first. While
## it has an ally to support and cannot cast yet, it fires nothing at the foe.
##
## Nearer than the minimum is no place to attack from — the enemy steps back
## first (REPOSITION) — unless stepping back has just failed: a REPOSITION that
## timed out (a wall behind it, a target pressing it faster than it can back
## away) leaves it cornered for reposition_cooldown, and a cornered enemy fights
## from where it stands rather than trying the same retreat for ever.
func _can_start_attack(dist: float) -> bool:
	if not attack.is_ready():
		return false
	if dist < minimum_combat_distance and not is_cornered():
		return false
	if support != null and support.get_castable_action() != null:
		return true
	if _is_supporting():
		return false
	if dist > attack_range:
		return false
	var target: Node3D = targeting.get_target()
	if target == null or _facing_error_to(target) > deg_to_rad(max_attack_facing_angle):
		return false
	return _target_in_sight()


## A retreat has just timed out, and the next may not start yet.
func is_cornered() -> bool:
	return _reposition_block_timer > 0.0


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
	if not HitReaction.breaks_through(hit, stagger_resistance):
		return false
	return _state != State.STAGGERED and _stagger_immunity_timer <= 0.0


## Leaving ATTACK cuts the swing off (its exit), and the stagger begins.
func _enter_stagger(hit: DamageInfo) -> void:
	if _change_state(State.STAGGERED):
		_play_stagger_pose(hit.direction)


## A push replaces any push still dying out rather than adding to it, so a
## flurry of hits never builds into a launch.
func _apply_knockback(hit: DamageInfo) -> void:
	var push: Vector3 = HitReaction.push_velocity(hit, knockback_multiplier)
	if push == Vector3.ZERO:
		return
	_knockback_velocity = push
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
	attack.clear_damage_buff()
	if support != null:
		support.release()
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
	var phase: EnemyAttack.Phase = attack.get_phase()
	_debug_label.text = "%s%s\n%s %s" % [State.keys()[_state],
		" (%s)" % EnemyAttack.Phase.keys()[phase] if phase != EnemyAttack.Phase.NONE else "",
		"%s %.1fm" % [target.name, targeting.get_distance()] if target != null else "no target", navigation]
	if is_elite() and stats != null:
		_debug_label.text += "\nELITE  HP %.0f -> %.0f  damage %.1f -> %.1f" % [
			stats.max_health, max_health, stats.attack_damage, attack.attack_damage]
