class_name DungeonBoss
extends RoomCombatant

## A boss, on the boss framework (M12.8). Every boss is a DungeonBoss scene with
## its own BossData: the same lifecycle, phases, attack choice and reactions,
## other numbers, phases and attacks — no boss-specific code path.
##
## It shares the room contract, the damage pipeline (Hitbox -> Hurtbox ->
## HealthComponent, DamageInfo), the hit-reaction rules (HitReaction), AttackData
## and the targeting (EnemyTargeting) with every enemy, and nothing of an
## archetype or of an elite: its own state machine, its own category.
##
## Its parts, each with one owner:
##
##     Configuration  BossData (`data`): copied into the runtime fields below once;
##                    the asset is never written.
##     Lifecycle      this script's state machine: `_state`, changed only through
##                    _change_state(), legal moves in TRANSITIONS.
##     Escalation     BossPhaseController: which phase, whether enraged, what is
##                    due next — forward only.
##     Attacks        BossCombat (child `BossCombat`): which attack next, the one
##                    under way, the cooldowns, the hitboxes, the telegraph's look.
##     Target         EnemyTargeting (child `EnemyTargeting`): whom it fights.
##     Movement       this script: navigation, facing, the one move_and_slide().
##     Health         HealthComponent: heard through its signals, owned by nobody here.
##     Completion     `enemy_died`, reported once: its room counts it, the dungeon
##                    completes on the room — nothing here knows either exists.
##
## The states, and what moves between them:
##
##     INACTIVE --start_encounter()--> INTRO --intro_duration--> DECIDE
##     DECIDE --> CHASE (far) / REPOSITION (too close, nothing valid, facing away)
##            --> ATTACK (an attack chosen) --its recovery over--> DECIDE
##     any fighting state --a hit that breaks through--> STAGGERED --over--> DECIDE
##     any living state --health reaches a later phase--> TRANSITION --beat over--> DECIDE
##     any living state --health reaches the enrage, no phase due--> ENRAGING --beat over--> DECIDE
##     any --died--> DEAD, which nothing leaves;  any living --parked--> INACTIVE
##
## Priority, by construction: DEAD over everything; the two beats — TRANSITION,
## then ENRAGING, which never run together — over STAGGERED (a stagger never
## starts in a beat, and a beat cuts one short); STAGGERED over ATTACK (the attack
## is cut off); ATTACK over movement.
##
## Every modifier is recomputed from the base (_apply_modifiers()):
##     base (BossData) -> x the phase's -> x the enrage's, once it has happened
## so nothing compounds, a phase entered never stacks on the one before, and the
## assets are never written.

## Carries what a health bar needs without the boss knowing a UI exists.
signal encounter_started(display_name: String, health: HealthComponent)
## The beat towards phase `to_index` began.
signal phase_transition_started(to_index: int)
## Phase `index` began — the first one when the encounter starts.
signal phase_changed(index: int)
## The enrage beat began.
signal enrage_started
## The boss is enraged, for the rest of its life: its modifiers are applied.
signal enraged
## The state changed; after the new state's enter logic has run.
signal state_changed(from: State, to: State)

enum State { INACTIVE, INTRO, DECIDE, CHASE, REPOSITION, ATTACK, STAGGERED, TRANSITION, ENRAGING, DEAD }

## The legal transitions, from each state. Anything missing is refused. The two
## beats lead only back to DECIDE, so one never runs inside the other.
const TRANSITIONS: Dictionary = {
	State.INACTIVE: [State.INTRO, State.DEAD],
	State.INTRO: [State.DECIDE, State.STAGGERED, State.TRANSITION, State.ENRAGING, State.INACTIVE, State.DEAD],
	State.DECIDE: [State.CHASE, State.REPOSITION, State.ATTACK, State.STAGGERED, State.TRANSITION,
		State.ENRAGING, State.INACTIVE, State.DEAD],
	State.CHASE: [State.DECIDE, State.STAGGERED, State.TRANSITION, State.ENRAGING, State.INACTIVE, State.DEAD],
	State.REPOSITION: [State.DECIDE, State.STAGGERED, State.TRANSITION, State.ENRAGING, State.INACTIVE,
		State.DEAD],
	State.ATTACK: [State.DECIDE, State.STAGGERED, State.TRANSITION, State.ENRAGING, State.INACTIVE, State.DEAD],
	State.STAGGERED: [State.DECIDE, State.TRANSITION, State.ENRAGING, State.INACTIVE, State.DEAD],
	State.TRANSITION: [State.DECIDE, State.INACTIVE, State.DEAD],
	State.ENRAGING: [State.DECIDE, State.INACTIVE, State.DEAD],
	State.DEAD: [],
}
## The states a hit may stagger it out of.
const STAGGERABLE: Array[State] = [State.INTRO, State.DECIDE, State.CHASE, State.REPOSITION, State.ATTACK]

const GROUP: StringName = &"boss"
## REPOSITION stops within this much beyond the preferred distance: arrived.
const REPOSITION_ARRIVE_BAND: float = 0.3
## PLACEHOLDER looks: the intro's swell, the transition's pulse, the hit flash.
const INTRO_SCALE: Vector3 = Vector3(1.15, 1.2, 1.15)
const TRANSITION_PULSES: int = 3
const TRANSITION_SCALE_UP: Vector3 = Vector3(1.3, 1.3, 1.3)
const TRANSITION_SCALE_DOWN: Vector3 = Vector3(0.9, 0.9, 0.9)
const ENRAGE_PULSES: int = 2
const ENRAGE_SCALE_UP: Vector3 = Vector3(1.4, 1.15, 1.4)
const FLASH_COLOR: Color = Color(1.0, 1.0, 1.0)
const FLASH_IN: float = 0.04
const FLASH_OUT: float = 0.16
const DEBUG_LABEL_HEIGHT: float = 3.4

## The boss's configuration: the one place its numbers, phases and attacks exist.
@export var data: BossData
## Fixed so a run is reproducible: the choice among valid attacks is random but
## seeded.
@export var decision_seed: int = 20260920

@export_group("DEBUG")
## DEBUG ONLY. Off by default. A label over the boss: its state, phase, attack and
## where in it, target, cooldowns and health share.
@export var debug_state_label: bool = false
## DEBUG ONLY. Off by default. Prints each phase change (`PHASE phase_1 ->
## phase_2`) and the enrage (`ENRAGE in phase_2`).
@export var debug_log_phases: bool = false

# RUNTIME tuning: this boss's own values, seeded from `data` in _apply_data();
# the phase-dependent ones are recomputed when a phase begins. They carry no
# values of their own: the boss's numbers live in its BossData.
var max_health: float
var movement_speed: float
var acceleration: float
var rotation_speed: float
var gravity: float
var target_groups: Array[StringName] = []
var detection_range: float
var preferred_combat_distance: float
var minimum_combat_distance: float
var chase_band: float
var navigation_radius: float
var max_attack_facing_angle: float
var reposition_timeout: float
var reposition_speed_fraction: float
var target_update_interval: float
var stagger_resistance: float
var stagger_duration: float
var stagger_immunity_time: float
var knockback_multiplier: float
var knockback_deceleration: float
var intro_duration: float
var death_topple_duration: float

@onready var visual_root: Node3D = $VisualRoot
## Telegraphs deform this, below the facing node, so a wind-up can lean or spin
## the body without moving the hitboxes or changing where the boss aims.
@onready var mesh_root: Node3D = $VisualRoot/MeshRoot
## The PLACEHOLDER body the looks tint. Optional: a definitive model under
## MeshRoot without it keeps every rule of the fight and only loses the tints.
@onready var mesh_instance: MeshInstance3D = get_node_or_null(^"VisualRoot/MeshRoot/MeshInstance3D") as MeshInstance3D
@onready var attack_origins: Node3D = $VisualRoot/AttackOrigins
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hurtbox_collision: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var targeting: EnemyTargeting = $EnemyTargeting
@onready var combat: BossCombat = $BossCombat

## The lifecycle state: the one source of truth, written only by _change_state().
var _state: State = State.INACTIVE
var _phases: BossPhaseController = BossPhaseController.new()
## The data's problems, if any; a boss with any stays inert.
var _problems: PackedStringArray = []

# The state machine's own clocks, each belonging to one state.
var _intro_timer: float = 0.0
var _reposition_timer: float = 0.0
var _stagger_timer: float = 0.0
var _transition_timer: float = 0.0
var _enrage_timer: float = 0.0
## The phase the running transition leads to.
var _transition_to: int = -1
## Every attack any phase offers, once each — gathered once, at _ready().
var _attacks: Array[BossAttack] = []
## The attack DECIDE chose, handed to ATTACK's enter.
var _pending_attack: BossAttack = null

# Reactions (M11.6's rules): the immunity after a stagger, and a push.
var _stagger_immunity_timer: float = 0.0
var _knockback_velocity: Vector3 = Vector3.ZERO

# The phase-independent bases the phase modifiers scale.
var _base_movement_speed: float = 0.0
var _base_reposition_timeout: float = 0.0

# Movement.
var _desired_horizontal: Vector3 = Vector3.ZERO
var _target_update_accum: float = 0.0

# Looks.
var _body_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE
var _look_tween: Tween = null
var _feedback_tween: Tween = null
var _debug_label: Label3D = null


func _ready() -> void:
	add_to_group(GROUP)
	_apply_data()
	# reset_to rather than a bare write: this component filled itself from the
	# scene's placeholder in its own _ready(), before this one ran.
	health_component.reset_to(max_health)
	_setup_material()
	_attacks = _gather_attacks()
	combat.setup(self, attack_origins, mesh_root, _body_material, _attacks,
		data.attack_damage if data != null else 0.0,
		data.max_consecutive_repeats if data != null else 1, decision_seed)
	targeting.setup(self, target_groups)
	_setup_navigation()
	health_component.health_changed.connect(_on_health_changed)
	health_component.damaged.connect(_on_damaged)
	health_component.died.connect(_on_died)
	_setup_debug_label()
	if not _problems.is_empty():
		push_error("%s: its boss data is not usable (%s); it stays inert." % [name, ", ".join(_problems)])
		return
	# A room parks the boss right after this; without a room — a test bench, a
	# sandbox — it starts its own encounter, once everything has readied.
	call_deferred("_start_if_awake")


## Answered from the data rather than copied into the inherited field on
## _ready(), so initialisation order never decides what a kill is worth.
func get_xp_reward() -> int:
	return data.xp_reward if data != null else xp_reward


func _apply_data() -> void:
	var source: BossData = data
	if source == null:
		_problems = ["no BossData assigned"]
		source = BossData.new()
	else:
		_problems = source.get_problems()
	max_health = source.max_health
	_base_movement_speed = source.movement_speed
	movement_speed = source.movement_speed
	acceleration = source.acceleration
	rotation_speed = source.rotation_speed
	gravity = source.gravity
	target_groups = source.target_groups.duplicate()
	detection_range = source.detection_range
	preferred_combat_distance = source.preferred_combat_distance
	minimum_combat_distance = source.minimum_combat_distance
	chase_band = source.chase_band
	navigation_radius = source.navigation_radius
	max_attack_facing_angle = source.max_attack_facing_angle
	_base_reposition_timeout = source.reposition_timeout
	reposition_timeout = source.reposition_timeout
	reposition_speed_fraction = source.reposition_speed_fraction
	target_update_interval = source.target_update_interval
	stagger_resistance = source.stagger_resistance
	stagger_duration = source.stagger_duration
	stagger_immunity_time = source.stagger_immunity_time
	knockback_multiplier = source.knockback_multiplier
	knockback_deceleration = source.knockback_deceleration
	intro_duration = source.intro_duration
	death_topple_duration = source.death_topple_duration
	_phases.configure(source.phases, source.enrage)


func _gather_attacks() -> Array[BossAttack]:
	var out: Array[BossAttack] = []
	if data == null:
		return out
	for phase in data.phases:
		if phase == null:
			continue
		for attack in phase.attacks:
			if attack != null and not out.has(attack):
				out.append(attack)
	return out


func _setup_navigation() -> void:
	nav_agent.radius = navigation_radius
	nav_agent.max_speed = movement_speed
	# Only one boss in the room — RVO would cost without anything to avoid.
	nav_agent.avoidance_enabled = false


func _setup_material() -> void:
	if mesh_instance == null:
		return
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	_body_material = mat.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _body_material)
	_base_albedo = _body_material.albedo_color


# --- the encounter ----------------------------------------------------------------

## The room wakes the boss when the player walks in, and parks it when the fight
## is suspended.
func set_combat_enabled(enabled: bool) -> void:
	if _state == State.DEAD:
		return
	var was_enabled: bool = combat_enabled
	super.set_combat_enabled(enabled)
	if not enabled:
		_change_state(State.INACTIVE)
		return
	if not was_enabled:
		start_encounter()


## The fight begins (or resumes after being parked): the first phase on the
## first start, with its numbers applied; cooldowns clean; a target taken; the
## intro beat; the encounter announced. A resumed fight keeps its phase — and a
## phase that fell due while it was parked begins now.
func start_encounter() -> void:
	# Only a boss waiting for its fight starts one: anything else is under way.
	if not _problems.is_empty() or _state != State.INACTIVE:
		return
	if not combat_enabled:
		super.set_combat_enabled(true)
	if not _phases.is_started():
		_phases.start()
		_apply_modifiers()
	combat.clear_cooldowns()
	targeting.acquire(detection_range, 0.0)
	_change_state(State.INTRO)
	encounter_started.emit(data.display_name, health_component)
	phase_changed.emit(_phases.get_index())
	_check_escalation()


func _start_if_awake() -> void:
	if combat_enabled and _state == State.INACTIVE and is_inside_tree():
		start_encounter()


# --- queries ------------------------------------------------------------------------

func get_state() -> State:
	return _state


## Every attack any of its phases offers, once each, in the order the phases
## first list them.
func get_attacks() -> Array[BossAttack]:
	return _attacks


## The phase the fight is in, or null before it starts.
func get_phase() -> BossPhaseData:
	return _phases.get_phase()


## -1 before the fight starts.
func get_phase_index() -> int:
	return _phases.get_index()


func get_phase_id() -> StringName:
	var phase: BossPhaseData = _phases.get_phase()
	return phase.id if phase != null else &""


func get_phase_count() -> int:
	return _phases.get_count()


func is_in_transition() -> bool:
	return _state == State.TRANSITION


## Enraged: for good, once its beat is over.
func is_enraged() -> bool:
	return _phases.is_enraged()


## In the enrage's beat.
func is_enraging() -> bool:
	return _state == State.ENRAGING


## The phase the running transition leads to; -1 outside one.
func get_transition_target() -> int:
	return _transition_to if _state == State.TRANSITION else -1


## Where the attack under way is — BossCombat's answer.
func get_attack_phase() -> BossCombat.Phase:
	return combat.get_phase()


## The attack under way, or null — BossCombat's answer.
func get_current_attack() -> BossAttack:
	return combat.get_current_attack()


## Whom it fights, or null — EnemyTargeting's answer.
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


## What is wrong with its data; empty for a usable boss.
func get_problems() -> PackedStringArray:
	return _problems


# --- the state machine ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if _stagger_immunity_timer > 0.0:
		_stagger_immunity_timer = maxf(0.0, _stagger_immunity_timer - delta)
	if not combat_enabled or _state == State.INACTIVE:
		# Dormant: gravity (and a push) only. No perception, no decisions.
		_apply_motion(Vector3.ZERO, delta)
		return
	combat.tick(delta)
	match _state:
		State.INTRO:
			_update_intro(delta)
		State.DECIDE:
			_update_decide(delta)
		State.CHASE:
			_update_chase(delta)
		State.REPOSITION:
			_update_reposition(delta)
		State.ATTACK:
			_update_attack(delta)
		State.STAGGERED:
			_update_staggered(delta)
		State.TRANSITION:
			_update_transition(delta)
		State.ENRAGING:
			_update_enraging(delta)


## The one way the state changes: the old state's exit, the new one's enter, the
## announcement. A transition TRANSITIONS does not list, and a state re-entering
## itself, are refused. True when the state changed.
func _change_state(to: State) -> bool:
	var from: State = _state
	if to == from or not (TRANSITIONS[from] as Array).has(to):
		return false
	_exit_state(from)
	_state = to
	_enter_state(to)
	state_changed.emit(from, to)
	return true


func _enter_state(state: State) -> void:
	match state:
		State.INACTIVE:
			combat.interrupt()
			targeting.release()
			_stagger_timer = 0.0
			velocity = Vector3.ZERO
			_desired_horizontal = Vector3.ZERO
		State.INTRO:
			_intro_timer = intro_duration
			_desired_horizontal = Vector3.ZERO
			_play_intro_look()
		State.CHASE:
			_target_update_accum = target_update_interval
		State.REPOSITION:
			_reposition_timer = reposition_timeout
			_target_update_accum = target_update_interval
		State.ATTACK:
			_desired_horizontal = Vector3.ZERO
			combat.start(_pending_attack)
			_pending_attack = null
		State.STAGGERED:
			_stagger_timer = stagger_duration
			_desired_horizontal = Vector3.ZERO
		State.TRANSITION:
			_enter_transition()
		State.ENRAGING:
			_enter_enraging()
		State.DEAD:
			_enter_dead()


func _exit_state(state: State) -> void:
	match state:
		State.ATTACK:
			# A finished attack has already ended; anything else is cut off here,
			# so no hit window outlives the state.
			if combat.is_attacking():
				combat.interrupt()
		State.STAGGERED:
			_stagger_timer = 0.0
			_stagger_immunity_timer = stagger_immunity_time
		State.TRANSITION:
			_transition_timer = 0.0
		State.ENRAGING:
			_enrage_timer = 0.0


func _update_intro(delta: float) -> void:
	_hold_position(delta)
	_intro_timer -= delta
	if _intro_timer <= 0.0:
		combat.settle_look(false)
		_change_state(State.DECIDE)


## The one decision point: where to be, and which attack — never during an
## attack, a stagger or a transition.
func _update_decide(delta: float) -> void:
	_hold_position(delta)
	var target: Node3D = _fight_target(delta)
	if target == null:
		return
	_rotate_toward(target.global_position, delta, rotation_speed)
	var dist: float = _flat_distance_to(target)
	if dist > preferred_combat_distance + chase_band:
		_change_state(State.CHASE)
		return
	if dist < minimum_combat_distance:
		# Too close to swing sensibly: back off before considering anything.
		_change_state(State.REPOSITION)
		return
	if _facing_error_to(target) > deg_to_rad(max_attack_facing_angle):
		# Aimed wrong: turn before committing to anything.
		_change_state(State.REPOSITION)
		return
	_pending_attack = combat.choose(_phases.get_phase().attacks, dist)
	if _pending_attack == null:
		# Nothing valid from here: move.
		_change_state(State.REPOSITION)
		return
	_change_state(State.ATTACK)


func _update_chase(delta: float) -> void:
	var target: Node3D = _fight_target(delta)
	if target == null:
		_change_state(State.DECIDE)
		return
	if _flat_distance_to(target) <= preferred_combat_distance:
		_change_state(State.DECIDE)
		return
	_update_nav_target(delta, target.global_position)
	var dir: Vector3 = _path_direction()
	_apply_motion(_accelerate_toward(dir * movement_speed, delta), delta)
	if dir.length_squared() > 0.001:
		_rotate_visual_toward(dir, delta, rotation_speed)


func _update_reposition(delta: float) -> void:
	var target: Node3D = _fight_target(delta)
	_reposition_timer -= delta
	if target == null or _reposition_timer <= 0.0:
		_change_state(State.DECIDE)
		return
	var dist: float = _flat_distance_to(target)
	_update_nav_target(delta, _combat_slot(target))
	var dir: Vector3 = _path_direction()
	var speed: float = movement_speed * reposition_speed_fraction
	if dist >= minimum_combat_distance and dist <= preferred_combat_distance + REPOSITION_ARRIVE_BAND:
		speed = 0.0
	_apply_motion(_accelerate_toward(dir * speed, delta), delta)
	# Reposition always turns to face the target, never the movement direction.
	_rotate_toward(target.global_position, delta, rotation_speed)


## One attack, start to end, standing still. It turns only as the attack allows:
## partly in the telegraph, a nudge between two swings, never in a hit window.
func _update_attack(delta: float) -> void:
	_hold_position(delta)
	var turn: float = combat.get_turn_fraction()
	var target: Node3D = targeting.get_target()
	if turn > 0.0 and target != null:
		_rotate_toward(target.global_position, delta, rotation_speed * turn)
	if combat.advance(delta):
		_change_state(State.DECIDE)


## No decision, no turning, no path: the body moves only if pushed.
func _update_staggered(delta: float) -> void:
	_hold_position(delta)
	_stagger_timer -= delta
	if _stagger_timer <= 0.0:
		_change_state(State.DECIDE)


## No decision, no navigation, no hitbox — the beat plays out, still hittable.
func _update_transition(delta: float) -> void:
	_hold_position(delta)
	_transition_timer -= delta
	if _transition_timer <= 0.0:
		_finish_transition()


## The enrage's beat: the same rules as a phase's.
func _update_enraging(delta: float) -> void:
	_hold_position(delta)
	_enrage_timer -= delta
	if _enrage_timer <= 0.0:
		_finish_enrage()


## The target it fights, taking the nearest candidate if it holds none; null
## while there is nobody.
func _fight_target(delta: float) -> Node3D:
	if targeting.validate():
		return targeting.get_target()
	if targeting.acquire(detection_range, delta):
		return targeting.get_target()
	return null


# --- phases and the enrage --------------------------------------------------------------

## Every modified number, recomputed from the bases:
##     base (BossData) -> x the phase's -> x the enrage's, once it has happened
## Idempotent — calling it twice changes nothing — so a phase never stacks on the
## one before and nothing compounds; the data is never written.
func _apply_modifiers() -> void:
	var phase: BossPhaseData = _phases.get_phase()
	if phase == null:
		return
	var speed: float = phase.movement_speed_multiplier
	var cooldown: float = phase.cooldown_multiplier
	var resting: Color = phase.body_color if phase.body_color.a > 0.0 else _base_albedo
	var enrage: BossEnrageData = _phases.get_enrage()
	if _phases.is_enraged() and enrage != null:
		speed *= enrage.movement_speed_multiplier
		cooldown *= enrage.cooldown_multiplier
		resting = enrage.body_color
	movement_speed = _base_movement_speed * speed
	reposition_timeout = _base_reposition_timeout * phase.reposition_timeout_multiplier
	nav_agent.max_speed = movement_speed
	combat.set_pace(phase.recovery_multiplier, cooldown)
	combat.set_resting_color(resting)


## Drops everything the boss was doing — the attack cut off, no hit window left,
## the path stopped — and hands it a harmless, committed beat.
func _enter_transition() -> void:
	combat.interrupt()
	_stagger_timer = 0.0
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	nav_agent.target_position = global_position
	var next: BossPhaseData = _phases.get_phase_at(_transition_to)
	_transition_timer = next.transition_duration if next != null else 0.0
	_play_transition_look(next)
	phase_transition_started.emit(_transition_to)


func _finish_transition() -> void:
	var from: StringName = get_phase_id()
	_phases.enter(_transition_to)
	var phase: BossPhaseData = _phases.get_phase()
	_apply_modifiers()
	# A new phase opens on a clean slate rather than inheriting cooldowns.
	combat.clear_cooldowns()
	combat.settle_look(false)
	if debug_log_phases:
		print("[%s] PHASE %s -> %s" % [name, from, phase.id])
	_change_state(State.DECIDE)
	_transition_to = -1
	phase_changed.emit(_phases.get_index())
	# The next step, if one is already due — the enrage a single blow also
	# reached plays now, after this beat, never inside it.
	_check_escalation()


## Like a phase's beat: the attack cut off, no hit window, the path stopped — a
## harmless, committed beat that no stagger breaks, still hittable.
func _enter_enraging() -> void:
	combat.interrupt()
	_stagger_timer = 0.0
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	nav_agent.target_position = global_position
	var enrage: BossEnrageData = _phases.get_enrage()
	_enrage_timer = enrage.transition_duration if enrage != null else 0.0
	_play_enrage_look(enrage)
	enrage_started.emit()


func _finish_enrage() -> void:
	_phases.enrage()
	_apply_modifiers()
	combat.settle_look(false)
	if debug_log_phases:
		print("[%s] ENRAGE in %s" % [name, get_phase_id()])
	_change_state(State.DECIDE)
	enraged.emit()


# --- movement -----------------------------------------------------------------------------

func _hold_position(delta: float) -> void:
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)


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


func _accelerate_toward(target_velocity: Vector3, delta: float) -> Vector3:
	var rate: float = acceleration * delta
	_desired_horizontal.x = move_toward(_desired_horizontal.x, target_velocity.x, rate)
	_desired_horizontal.z = move_toward(_desired_horizontal.z, target_velocity.z, rate)
	return _desired_horizontal


## The one place the body moves. A push in progress replaces whatever the AI
## wanted, through move_and_slide() like any motion, and dies out quickly.
func _apply_motion(horizontal: Vector3, delta: float) -> void:
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


## Holds the ring at preferred distance along the boss's current bearing.
func _combat_slot(target: Node3D) -> Vector3:
	var from_target: Vector3 = global_position - target.global_position
	from_target.y = 0.0
	if from_target.length_squared() < 0.0001:
		from_target = Vector3.BACK
	return target.global_position + from_target.normalized() * preferred_combat_distance


func _flat_distance_to(target: Node3D) -> float:
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	return offset.length()


# --- facing -----------------------------------------------------------------------------

func _rotate_visual_toward(world_dir: Vector3, delta: float, speed: float) -> void:
	var target_yaw: float = atan2(-world_dir.x, -world_dir.z)
	var diff: float = wrapf(target_yaw - visual_root.rotation.y, -PI, PI)
	var step: float = speed * delta
	visual_root.rotation.y += clampf(diff, -step, step)


func _rotate_toward(point: Vector3, delta: float, speed: float) -> void:
	var to_point: Vector3 = point - global_position
	to_point.y = 0.0
	if to_point.length_squared() < 0.0001:
		return
	_rotate_visual_toward(to_point.normalized(), delta, speed)


func _facing_error_to(target: Node3D) -> float:
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	var forward: Vector3 = -visual_root.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return PI
	return absf(forward.normalized().signed_angle_to(to_target.normalized(), Vector3.UP))


# --- damage, reactions, death --------------------------------------------------------------
#
# A hit arrives the one way every hit does. The health component has already
# taken the damage and said whether it killed: a killing blow is a death and
# nothing else — health_changed at 0 starts no phase, died ends everything.

func _on_health_changed(_current: float, _maximum: float) -> void:
	_check_escalation()


## What the health share makes due, one step at a time:
## - a later phase: its transition. During one, a deeper phase due (a blow
##   through two thresholds) becomes where it leads — deterministic, never back;
## - with no phase due, the enrage: its beat. Never during a beat — a blow that
##   reaches both plays the phase first, and the transition's end asks again.
## A killing blow reaches none of this (health 0), and a parked boss waits:
## start_encounter() asks again when the fight resumes.
func _check_escalation() -> void:
	var maximum: float = health_component.max_health
	var current: float = health_component.current_health
	if _state == State.DEAD or _state == State.INACTIVE or current <= 0.0 or maximum <= 0.0:
		return
	var share: float = current / maximum
	var due: int = _phases.due(share)
	if _state == State.TRANSITION:
		if due >= 0:
			_transition_to = maxi(_transition_to, due)
		return
	if _state == State.ENRAGING:
		return
	if due >= 0:
		_transition_to = due
		_change_state(State.TRANSITION)
	elif _phases.enrage_due(share):
		_change_state(State.ENRAGING)


## A hit that leaves it standing: a flash, a stagger if it breaks through (and
## the boss can be staggered now), a push by its knockback share.
func _on_damaged(hit: DamageInfo) -> void:
	if _state == State.DEAD:
		return
	_hit_flash()
	if _staggers(hit):
		_change_state(State.STAGGERED)
	var push: Vector3 = HitReaction.push_velocity(hit, knockback_multiplier)
	if push != Vector3.ZERO:
		_knockback_velocity = push
		_desired_horizontal = Vector3.ZERO


func _staggers(hit: DamageInfo) -> bool:
	return HitReaction.breaks_through(hit, stagger_resistance) and STAGGERABLE.has(_state) \
		and _stagger_immunity_timer <= 0.0


## Safe from every state, the transition and the gap between two swings
## included: the attack is torn down on the way out of its state, so no delayed
## hit window can open after death.
func _on_died() -> void:
	_change_state(State.DEAD)
	# The room counts this; nothing here knows about rooms or the dungeon.
	report_death(health_component.last_damage_source)


func _enter_dead() -> void:
	combat.interrupt()
	targeting.release()
	_transition_to = -1
	_stagger_timer = 0.0
	_knockback_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	nav_agent.target_position = global_position
	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	body_collision.call_deferred("set_disabled", true)
	_kill_look()
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	var t: Tween = create_tween()
	t.tween_property(visual_root, "rotation:x", deg_to_rad(90.0), death_topple_duration)


# --- looks (PLACEHOLDER until M14) --------------------------------------------------------------

func _kill_look() -> void:
	if _look_tween != null and _look_tween.is_running():
		_look_tween.kill()


func _play_intro_look() -> void:
	_kill_look()
	var half: float = maxf(0.05, intro_duration * 0.5)
	_look_tween = create_tween()
	_look_tween.tween_property(mesh_root, "scale", INTRO_SCALE, half)
	_look_tween.tween_property(mesh_root, "scale", Vector3.ONE, half)


## The phase beat: a visible pulse, and the next phase's colour.
func _play_transition_look(next: BossPhaseData) -> void:
	_kill_look()
	mesh_root.rotation = Vector3.ZERO
	mesh_root.position = Vector3.ZERO
	var duration: float = next.transition_duration if next != null else 0.0
	var beat: float = maxf(0.1, duration / (TRANSITION_PULSES * 2.0))
	_look_tween = create_tween()
	_look_tween.set_loops(TRANSITION_PULSES)
	_look_tween.tween_property(mesh_root, "scale", TRANSITION_SCALE_UP, beat)
	_look_tween.tween_property(mesh_root, "scale", TRANSITION_SCALE_DOWN, beat)
	if _body_material != null and next != null and next.body_color.a > 0.0:
		_body_material.emission_enabled = true
		_body_material.emission = next.body_color
		_body_material.albedo_color = next.body_color


## The enrage beat: a heavier pulse, and the glow it keeps from then on.
func _play_enrage_look(enrage: BossEnrageData) -> void:
	_kill_look()
	mesh_root.rotation = Vector3.ZERO
	mesh_root.position = Vector3.ZERO
	var duration: float = enrage.transition_duration if enrage != null else 0.0
	var beat: float = maxf(0.1, duration / (ENRAGE_PULSES * 2.0))
	_look_tween = create_tween()
	_look_tween.set_loops(ENRAGE_PULSES)
	_look_tween.tween_property(mesh_root, "scale", ENRAGE_SCALE_UP, beat)
	_look_tween.tween_property(mesh_root, "scale", Vector3.ONE, beat)
	if _body_material != null and enrage != null:
		_body_material.emission_enabled = true
		_body_material.emission = enrage.emission_color
		_body_material.emission_energy_multiplier = enrage.emission_energy
		_body_material.albedo_color = enrage.body_color


## Deliberately light: a boss should not read as flinching. A brief tint pulse.
func _hit_flash() -> void:
	if _body_material == null:
		return
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	var resting: Color = _body_material.albedo_color
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(_body_material, "albedo_color", FLASH_COLOR, FLASH_IN)
	_feedback_tween.tween_property(_body_material, "albedo_color", resting, FLASH_OUT)


func is_flashing() -> bool:
	return _feedback_tween != null and _feedback_tween.is_running()


# --- debug ------------------------------------------------------------------------------------------

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
	var attack: BossAttack = combat.get_current_attack()
	var target: Node3D = targeting.get_target()
	var cooldowns: String = ""
	for a in _attacks:
		if combat.get_cooldown(a) > 0.0:
			cooldowns += " %s %.1f" % [a.get_id(), combat.get_cooldown(a)]
	_debug_label.text = "%s  %s%s\n%s %s\n%s  %.0f%%\n%s" % [State.keys()[_state], get_phase_id(),
		"  ENRAGED" if is_enraged() else "",
		String(attack.get_id()) if attack != null else "-", BossCombat.Phase.keys()[combat.get_phase()],
		String(target.name) if target != null else "no target",
		100.0 * health_component.current_health / maxf(health_component.max_health, 1.0), cooldowns]
