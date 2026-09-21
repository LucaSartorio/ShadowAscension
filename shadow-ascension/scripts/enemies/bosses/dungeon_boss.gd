class_name DungeonBoss
extends RoomCombatant

## The dungeon's boss. It shares the room contract, the damage pipeline and the
## navigation approach with BasicMeleeEnemy, but none of its AI: this is its own
## state logic with a three-attack decision layer.

## Carries what a health bar needs without the boss knowing a UI exists.
signal encounter_started(display_name: String, health: HealthComponent)
## Emitted on every phase change, including the transition itself. A UI listens;
## the boss still knows nothing about one.
signal phase_changed(phase: BossPhase)

enum State { INACTIVE, INTRO, DECIDE, CHASE, REPOSITION, ATTACK, TRANSITION, RECOVERY, DEAD }
## Which half of the fight this is. Distinct from State: the boss stays in
## PHASE_2 while it chases, attacks and recovers.
enum BossPhase { PHASE_1, TRANSITION, PHASE_2 }
enum AttackPhase { NONE, STARTUP, ACTIVE, BETWEEN_HITS }

const GROUP: StringName = &"boss"
## The body keeps this once phase 2 starts, so the boss reads as changed even
## when it is standing still.
const PHASE_2_COLOR: Color = Color(0.72, 0.12, 0.16)

@export var display_name: String = "Dungeon Boss"
## Body tuning. Copied into the runtime fields below on _ready().
@export var stats: BossStats
## The attack set, in no particular order — the decision layer picks per frame.
@export var attacks: Array[BossAttack] = []
## Fixed so a run is reproducible; the choice among valid attacks is random but
## seeded, not free-running.
@export var decision_seed: int = 20260920

# Runtime tuning, seeded from `stats`. Instance state — the Resource stays clean.
var max_health: float = 600.0
var movement_speed: float = 3.2
var acceleration: float = 10.0
var rotation_speed: float = 5.0
var gravity: float = 20.0
var preferred_combat_distance: float = 2.2
var minimum_combat_distance: float = 1.4
var chase_band: float = 1.0
var navigation_radius: float = 0.8
var max_attack_facing_angle: float = 30.0
var max_consecutive_repeats: int = 2
var reposition_timeout: float = 1.4
var reposition_speed_fraction: float = 0.85
var target_update_interval: float = 0.2
var intro_duration: float = 0.8
var death_topple_duration: float = 1.2
var phase_2_health_fraction: float = 0.5
var phase_transition_duration: float = 1.5
var phase_2_movement_speed: float = 3.8
var phase_2_reposition_timeout: float = 0.9
## Held so phase 2 can restore phase 1's values if the boss is ever reset.
var _phase_1_movement_speed: float = 3.2
var _phase_1_reposition_timeout: float = 1.4

@onready var visual_root: Node3D = $VisualRoot
## Telegraph animations live here, below the facing node, so a wind-up can lean
## or spin the body without moving the hitboxes or changing where the boss aims.
@onready var mesh_root: Node3D = $VisualRoot/MeshRoot
@onready var mesh_instance: MeshInstance3D = $VisualRoot/MeshRoot/MeshInstance3D
@onready var attack_origins: Node3D = $VisualRoot/AttackOrigins
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hurtbox_collision: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D

var _state: State = State.INACTIVE
var _phase: BossPhase = BossPhase.PHASE_1
## Latched the moment the transition starts, so it can never run twice — not on
## a second dip below the threshold, not on a heal and re-damage.
var _phase_transition_spent: bool = false
var _phase_timer_remaining: float = 0.0
var _attack_phase: AttackPhase = AttackPhase.NONE
## Swings already delivered by the attack in progress.
var _hits_done: int = 0
var _phase_timer: float = 0.0
var _intro_timer: float = 0.0
var _reposition_timer: float = 0.0
var _target_update_accum: float = 0.0

var _player: Player = null
var _hitboxes: Array[Hitbox] = []
var _cooldowns: Array[float] = []
var _active_attack: int = -1
var _last_attack: int = -1
var _consecutive: int = 0
## Reused so the per-frame decision allocates nothing.
var _candidates: Array[int] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _desired_horizontal: Vector3 = Vector3.ZERO
var _telegraph_tween: Tween = null
var _feedback_tween: Tween = null
var _body_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE
var _last_health: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	_apply_stats()
	_rng.seed = decision_seed
	health_component.max_health = max_health
	_last_health = max_health
	_phase_1_movement_speed = movement_speed
	_phase_1_reposition_timeout = reposition_timeout
	_setup_hitboxes()
	_setup_navigation()
	_setup_material()
	health_component.health_changed.connect(_on_health_changed)
	health_component.died.connect(_on_died)
	# A room parks the boss right after this, flipping it to INACTIVE. Without a
	# room — a test bench, a sandbox scene — it starts its own encounter.
	if combat_enabled:
		_state = State.INTRO
		_intro_timer = intro_duration


## Answered from the stats asset rather than copied into the inherited field on
## _ready(), so initialisation order never decides what a kill is worth.
func get_xp_reward() -> int:
	return stats.xp_reward if stats != null else xp_reward


func _apply_stats() -> void:
	if stats == null:
		push_warning("%s has no BossStats assigned; falling back to script defaults." % name)
		return
	max_health = stats.max_health
	movement_speed = stats.movement_speed
	acceleration = stats.acceleration
	rotation_speed = stats.rotation_speed
	gravity = stats.gravity
	preferred_combat_distance = stats.preferred_combat_distance
	minimum_combat_distance = stats.minimum_combat_distance
	chase_band = stats.chase_band
	navigation_radius = stats.navigation_radius
	max_attack_facing_angle = stats.max_attack_facing_angle
	max_consecutive_repeats = stats.max_consecutive_repeats
	reposition_timeout = stats.reposition_timeout
	phase_2_health_fraction = stats.phase_2_health_fraction
	phase_transition_duration = stats.phase_transition_duration
	phase_2_movement_speed = stats.phase_2_movement_speed
	phase_2_reposition_timeout = stats.phase_2_reposition_timeout
	reposition_speed_fraction = stats.reposition_speed_fraction
	target_update_interval = stats.target_update_interval
	intro_duration = stats.intro_duration
	death_topple_duration = stats.death_topple_duration


## Resolves each attack's hitbox once and wires its damage, so the per-frame path
## never looks a node up by name.
func _setup_hitboxes() -> void:
	_hitboxes.clear()
	_cooldowns.clear()
	for attack in attacks:
		var hitbox: Hitbox = attack_origins.get_node_or_null(String(attack.hitbox_name)) as Hitbox
		if hitbox == null:
			push_warning("%s: attack '%s' has no hitbox named %s" % [name, attack.attack_name, attack.hitbox_name])
		else:
			hitbox.damage = attack.damage
			hitbox.source = self
		_hitboxes.append(hitbox)
		_cooldowns.append(0.0)


func _setup_navigation() -> void:
	nav_agent.radius = navigation_radius
	nav_agent.max_speed = movement_speed
	# Only one boss in the room — RVO would cost without anything to avoid.
	nav_agent.avoidance_enabled = false


func _setup_material() -> void:
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	_body_material = mat.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _body_material)
	_base_albedo = _body_material.albedo_color


# --- room contract ------------------------------------------------------------

## The room wakes the boss when the player walks in; INTRO is a short beat, not
## a cutscene.
func set_combat_enabled(enabled: bool) -> void:
	if _state == State.DEAD:
		return
	var was_enabled: bool = combat_enabled
	super.set_combat_enabled(enabled)
	if not enabled:
		_state = State.INACTIVE
		_attack_phase = AttackPhase.NONE
		_deactivate_all_hitboxes()
		_reset_telegraph_instantly()
		velocity = Vector3.ZERO
		_desired_horizontal = Vector3.ZERO
		return
	if was_enabled:
		return
	_state = State.INTRO
	_intro_timer = intro_duration
	_play_intro_telegraph()
	encounter_started.emit(display_name, health_component)
	phase_changed.emit(_phase)


func get_state() -> State:
	return _state


func get_phase() -> BossPhase:
	return _phase


func is_phase_2() -> bool:
	return _phase == BossPhase.PHASE_2


## True once the transition has run, whether or not the boss survived it.
func phase_transition_spent() -> bool:
	return _phase_transition_spent


func get_hits_done() -> int:
	return _hits_done


func get_attack_cooldown(index: int) -> float:
	if index < 0 or index >= _cooldowns.size():
		return 0.0
	return _cooldowns[index]


func get_active_attack_index() -> int:
	return _active_attack


func get_attack_phase() -> AttackPhase:
	return _attack_phase


# --- main loop ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return
	if not combat_enabled or _state == State.INACTIVE:
		# Dormant: gravity only. No perception, no navigation, no decisions.
		_apply_motion(Vector3.ZERO, delta)
		return

	_tick_cooldowns(delta)

	var player: Player = _get_player()
	if player == null:
		_apply_motion(Vector3.ZERO, delta)
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

	match _state:
		State.INTRO:
			_intro_step(delta)
		State.DECIDE:
			_decide_step(delta, dist, player)
		State.CHASE:
			_chase_step(delta, dist, player)
		State.REPOSITION:
			_reposition_step(delta, dist, player)
		State.ATTACK:
			_attack_step(delta, to_player)
		State.TRANSITION:
			_transition_step(delta)
		State.RECOVERY:
			_recovery_step(delta)


func _tick_cooldowns(delta: float) -> void:
	for i in _cooldowns.size():
		if _cooldowns[i] > 0.0:
			_cooldowns[i] = maxf(0.0, _cooldowns[i] - delta)


func _get_player() -> Player:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Player
	return _player


# --- states -------------------------------------------------------------------

func _intro_step(delta: float) -> void:
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)
	_intro_timer -= delta
	if _intro_timer <= 0.0:
		_reset_telegraph()
		_state = State.DECIDE


## The decision layer. It never picks an attack that is on cooldown, out of its
## range band, or the same one too many times running; and it will not commit
## while facing the wrong way.
func _decide_step(delta: float, dist: float, player: Player) -> void:
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)
	_rotate_toward_player(player, delta, rotation_speed)

	if dist > preferred_combat_distance + chase_band:
		_state = State.CHASE
		_target_update_accum = target_update_interval
		return
	if dist < minimum_combat_distance:
		# Too close to swing sensibly: back off before considering anything.
		_enter_reposition()
		return

	var p2: bool = is_phase_2()
	_candidates.clear()
	for i in attacks.size():
		var attack: BossAttack = attacks[i]
		if _hitboxes[i] == null or _cooldowns[i] > 0.0:
			continue
		if not attack.is_available(p2):
			continue
		if dist < attack.min_range or dist > attack.max_range:
			continue
		if i == _last_attack and _consecutive >= max_consecutive_repeats:
			continue
		_candidates.append(i)

	if _candidates.is_empty():
		_enter_reposition()
		return
	if _facing_error_to(player) > deg_to_rad(max_attack_facing_angle):
		# In range and off cooldown, but aimed wrong: turn before committing.
		_enter_reposition()
		return

	_begin_attack(_pick_weighted(p2))


## Picks among the valid candidates by their per-phase weight. Still random, but
## a heavy attack stays rarer than a jab instead of being equally likely.
func _pick_weighted(in_phase_2: bool) -> int:
	var total: float = 0.0
	for i in _candidates:
		total += maxf(0.0, attacks[i].get_weight(in_phase_2))
	if total <= 0.0:
		return _candidates[_rng.randi_range(0, _candidates.size() - 1)]
	var roll: float = _rng.randf() * total
	for i in _candidates:
		roll -= maxf(0.0, attacks[i].get_weight(in_phase_2))
		if roll <= 0.0:
			return i
	return _candidates[_candidates.size() - 1]


func _chase_step(delta: float, dist: float, player: Player) -> void:
	if dist <= preferred_combat_distance:
		_state = State.DECIDE
		return
	_update_nav_target(delta, player.global_position)
	var dir: Vector3 = _path_direction()
	_apply_motion(_accelerate_toward(dir * movement_speed, delta), delta)
	if dir.length_squared() > 0.001:
		_rotate_visual_toward(dir, delta, rotation_speed)


func _enter_reposition() -> void:
	_state = State.REPOSITION
	_reposition_timer = reposition_timeout
	_target_update_accum = target_update_interval


func _reposition_step(delta: float, dist: float, player: Player) -> void:
	_reposition_timer -= delta
	if _reposition_timer <= 0.0:
		_state = State.DECIDE
		return

	var slot: Vector3 = _combat_slot(player)
	_update_nav_target(delta, slot)
	var dir: Vector3 = _path_direction()
	var speed: float = movement_speed * reposition_speed_fraction
	if dist >= minimum_combat_distance and dist <= preferred_combat_distance + 0.3:
		speed = 0.0
	_apply_motion(_accelerate_toward(dir * speed, delta), delta)
	# Reposition always turns to face the player, never the movement direction.
	_rotate_toward_player(player, delta, rotation_speed)


## Holds the ring at preferred distance along the boss's current bearing.
func _combat_slot(player: Player) -> Vector3:
	var from_player: Vector3 = global_position - player.global_position
	from_player.y = 0.0
	if from_player.length_squared() < 0.0001:
		from_player = Vector3.BACK
	return player.global_position + from_player.normalized() * preferred_combat_distance


func _begin_attack(index: int) -> void:
	_active_attack = index
	_consecutive = 1 if index != _last_attack else _consecutive + 1
	_last_attack = index
	var attack: BossAttack = attacks[index]
	var p2: bool = is_phase_2()
	_cooldowns[index] = attack.get_cooldown(p2)
	_state = State.ATTACK
	_attack_phase = AttackPhase.STARTUP
	_phase_timer = attack.get_startup(p2)
	_hits_done = 0
	_desired_horizontal = Vector3.ZERO
	_play_telegraph(attack, p2)


func _attack_step(delta: float, to_player: Vector3) -> void:
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)
	var attack: BossAttack = attacks[_active_attack]

	# STARTUP may correct facing, and only partially. ACTIVE does not turn at
	# all, so a committed swing can be sidestepped. The gap between two swings of
	# a multi-hit allows a small nudge, never a snap onto a player who left.
	if to_player.length_squared() > 0.0001:
		var fraction: float = 0.0
		if _attack_phase == AttackPhase.STARTUP:
			fraction = attack.facing_correction_fraction
		elif _attack_phase == AttackPhase.BETWEEN_HITS:
			fraction = attack.between_hits_facing_fraction
		var turn: float = rotation_speed * fraction
		if turn > 0.0:
			_rotate_visual_toward(to_player.normalized(), delta, turn)

	_phase_timer -= delta
	if _phase_timer > 0.0:
		return

	match _attack_phase:
		AttackPhase.STARTUP:
			_start_hit_window(attack)
		AttackPhase.BETWEEN_HITS:
			_play_rewind_telegraph(attack)
			_start_hit_window(attack)
		AttackPhase.ACTIVE:
			_deactivate_all_hitboxes()
			_hits_done += 1
			if _hits_done < maxi(1, attack.hit_count):
				# Another swing to come: committed, but harmless in the gap.
				_attack_phase = AttackPhase.BETWEEN_HITS
				_phase_timer = attack.delay_between_hits
				return
			_attack_phase = AttackPhase.NONE
			_state = State.RECOVERY
			_phase_timer = attack.get_recovery(is_phase_2())
			_reset_telegraph()


## Opens one swing. activate() clears the hitbox's hit registry, so each swing
## can land on the player exactly once and the next swing starts fresh.
func _start_hit_window(attack: BossAttack) -> void:
	_attack_phase = AttackPhase.ACTIVE
	_phase_timer = attack.active
	var hitbox: Hitbox = _hitboxes[_active_attack]
	if hitbox != null:
		hitbox.damage = attack.damage
		hitbox.activate()


## Drops everything the boss was doing and hands it a harmless, committed beat.
## Safe from any state: mid-startup, mid-swing, between two hits of a Double
## Strike, mid-chase.
func _begin_phase_transition() -> void:
	_phase_transition_spent = true
	_phase = BossPhase.TRANSITION
	_state = State.TRANSITION
	_phase_timer_remaining = phase_transition_duration

	# Cancel the attack in flight rather than letting its windows keep firing.
	_deactivate_all_hitboxes()
	_attack_phase = AttackPhase.NONE
	_active_attack = -1
	_hits_done = 0
	_phase_timer = 0.0

	# Stop moving and stop pathing, so nothing carries over into the beat.
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	nav_agent.target_position = global_position
	_reposition_timer = 0.0

	_play_transition_telegraph()
	phase_changed.emit(_phase)


func _transition_step(delta: float) -> void:
	# No decisions, no navigation, no hitboxes — only gravity.
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)
	_phase_timer_remaining -= delta
	if _phase_timer_remaining > 0.0:
		return
	_enter_phase_2()


func _enter_phase_2() -> void:
	_phase = BossPhase.PHASE_2
	movement_speed = phase_2_movement_speed
	reposition_timeout = phase_2_reposition_timeout
	nav_agent.max_speed = movement_speed
	# Phase 2 opens with a clean slate rather than inheriting phase 1 cooldowns.
	for i in _cooldowns.size():
		_cooldowns[i] = 0.0
	_last_attack = -1
	_consecutive = 0
	_reset_telegraph()
	_state = State.DECIDE
	phase_changed.emit(_phase)


func _recovery_step(delta: float) -> void:
	# Committed: no movement, no turning, no new decision until it finishes.
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		_active_attack = -1
		_state = State.DECIDE


# --- movement -----------------------------------------------------------------

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


func _apply_motion(horizontal: Vector3, delta: float) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


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


# --- telegraph ----------------------------------------------------------------

func _kill_telegraph() -> void:
	if _telegraph_tween != null and _telegraph_tween.is_running():
		_telegraph_tween.kill()


## Each attack winds up with a different shape, so they stay distinguishable
## without animation: a forward lean, a wind-up spin, or a vertical compression.
func _play_telegraph(attack: BossAttack, in_phase_2: bool) -> void:
	_kill_telegraph()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	var duration: float = maxf(0.05, attack.get_startup(in_phase_2) * 0.9)
	match attack.telegraph:
		BossAttack.Telegraph.LEAN:
			_telegraph_tween.tween_property(mesh_root, "rotation:x", deg_to_rad(-22.0), duration)
		BossAttack.Telegraph.SPIN:
			_telegraph_tween.tween_property(mesh_root, "rotation:y", -TAU, duration)
		BossAttack.Telegraph.COMPRESS:
			_telegraph_tween.tween_property(mesh_root, "scale", Vector3(1.35, 0.55, 1.35), duration)
		BossAttack.Telegraph.RECOIL:
			# Cocks backwards and narrows instead of leaning in: reads as a
			# wind-up with something held back, not as a single jab.
			_telegraph_tween.tween_property(mesh_root, "position:z", 0.45, duration)
			_telegraph_tween.tween_property(mesh_root, "rotation:x", deg_to_rad(14.0), duration)
			_telegraph_tween.tween_property(mesh_root, "scale", Vector3(0.78, 1.22, 0.78), duration)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", attack.telegraph_color, duration)


## Played in the gap between two swings, so the second one is announced rather
## than arriving out of a still body.
func _play_rewind_telegraph(attack: BossAttack) -> void:
	if attack.delay_between_hits <= 0.0:
		return
	_kill_telegraph()
	var half: float = maxf(0.03, attack.delay_between_hits * 0.45)
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(mesh_root, "position:z", 0.5, half)
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3(0.7, 1.3, 0.7), half)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", Color(1.0, 1.0, 0.85), half)


## The phase beat: a visible pulse and a colour shift, no asset required.
func _play_transition_telegraph() -> void:
	_kill_telegraph()
	mesh_root.rotation = Vector3.ZERO
	mesh_root.position.z = 0.0
	var beat: float = maxf(0.1, phase_transition_duration / 6.0)
	_telegraph_tween = create_tween()
	_telegraph_tween.set_loops(3)
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3(1.3, 1.3, 1.3), beat)
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3(0.9, 0.9, 0.9), beat)
	if _body_material != null:
		_body_material.emission_enabled = true
		_body_material.emission = PHASE_2_COLOR
		_body_material.albedo_color = PHASE_2_COLOR


func _play_intro_telegraph() -> void:
	_kill_telegraph()
	_telegraph_tween = create_tween()
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3(1.15, 1.2, 1.15), maxf(0.05, intro_duration * 0.5))
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3.ONE, maxf(0.05, intro_duration * 0.5))


func _resting_albedo() -> Color:
	return PHASE_2_COLOR if _phase == BossPhase.PHASE_2 else _base_albedo


func _reset_telegraph() -> void:
	_kill_telegraph()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(mesh_root, "rotation", Vector3.ZERO, 0.25)
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3.ONE, 0.25)
	_telegraph_tween.tween_property(mesh_root, "position", Vector3.ZERO, 0.25)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", _resting_albedo(), 0.25)


func _reset_telegraph_instantly() -> void:
	_kill_telegraph()
	mesh_root.rotation = Vector3.ZERO
	mesh_root.scale = Vector3.ONE
	mesh_root.position = Vector3.ZERO
	if _body_material != null:
		_body_material.albedo_color = _resting_albedo()


# --- damage / death -----------------------------------------------------------

func _deactivate_all_hitboxes() -> void:
	for hitbox in _hitboxes:
		if hitbox != null and hitbox.is_active():
			hitbox.deactivate()


## Deliberately lighter than the enemy's squash: a boss should not read as
## flinching. A brief tint pulse, no displacement, no stagger.
func _on_health_changed(current: float, maximum: float) -> void:
	if current < _last_health:
		_hit_flash()
	_last_health = current
	# A blow that takes the boss to zero emits health_changed before died; there
	# is no phase left to enter, so let the death handler have it.
	if current <= 0.0 or _state == State.DEAD:
		return
	if _phase_transition_spent or not combat_enabled:
		return
	if current <= maximum * phase_2_health_fraction:
		_begin_phase_transition()


func _hit_flash() -> void:
	if _body_material == null:
		return
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	var resting: Color = _body_material.albedo_color
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(_body_material, "albedo_color", Color(1.0, 1.0, 1.0), 0.04)
	_feedback_tween.tween_property(_body_material, "albedo_color", resting, 0.16)


## Safe from every state, the phase transition and the gap between two swings of
## a Double Strike included: the attack machine is torn down here, so no delayed
## hit window can open after death.
func _on_died() -> void:
	_state = State.DEAD
	_attack_phase = AttackPhase.NONE
	_active_attack = -1
	_hits_done = 0
	_phase_timer = 0.0
	_phase_timer_remaining = 0.0
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	_deactivate_all_hitboxes()

	nav_agent.target_position = global_position

	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	body_collision.call_deferred("set_disabled", true)

	_reset_telegraph_instantly()
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	var t: Tween = create_tween()
	t.tween_property(visual_root, "rotation:x", deg_to_rad(90.0), death_topple_duration)

	# The room counts this; nothing here knows about rooms or the dungeon.
	report_death(health_component.last_damage_source)
