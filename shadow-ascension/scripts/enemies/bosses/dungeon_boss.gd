class_name DungeonBoss
extends RoomCombatant

## The dungeon's boss. It shares the room contract, the damage pipeline and the
## navigation approach with BasicMeleeEnemy, but none of its AI: this is its own
## state logic with a three-attack decision layer.

## Carries what a health bar needs without the boss knowing a UI exists.
signal encounter_started(display_name: String, health: HealthComponent)

enum State { INACTIVE, INTRO, DECIDE, CHASE, REPOSITION, ATTACK, RECOVERY, DEAD }
enum AttackPhase { NONE, STARTUP, ACTIVE }

const GROUP: StringName = &"boss"

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
var _attack_phase: AttackPhase = AttackPhase.NONE
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


func get_state() -> State:
	return _state


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

	_candidates.clear()
	for i in attacks.size():
		var attack: BossAttack = attacks[i]
		if _hitboxes[i] == null or _cooldowns[i] > 0.0:
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

	_begin_attack(_candidates[_rng.randi_range(0, _candidates.size() - 1)])


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
	_cooldowns[index] = attack.cooldown
	_state = State.ATTACK
	_attack_phase = AttackPhase.STARTUP
	_phase_timer = attack.startup
	_desired_horizontal = Vector3.ZERO
	_play_telegraph(attack)


func _attack_step(delta: float, to_player: Vector3) -> void:
	_desired_horizontal = Vector3.ZERO
	_apply_motion(Vector3.ZERO, delta)
	var attack: BossAttack = attacks[_active_attack]

	# STARTUP may correct facing, and only partially. ACTIVE does not turn at
	# all, so a committed swing can be sidestepped.
	if _attack_phase == AttackPhase.STARTUP and to_player.length_squared() > 0.0001:
		var turn: float = rotation_speed * attack.facing_correction_fraction
		if turn > 0.0:
			_rotate_visual_toward(to_player.normalized(), delta, turn)

	_phase_timer -= delta
	if _phase_timer > 0.0:
		return

	match _attack_phase:
		AttackPhase.STARTUP:
			_attack_phase = AttackPhase.ACTIVE
			_phase_timer = attack.active
			var hitbox: Hitbox = _hitboxes[_active_attack]
			if hitbox != null:
				hitbox.damage = attack.damage
				hitbox.activate()
		AttackPhase.ACTIVE:
			_deactivate_all_hitboxes()
			_attack_phase = AttackPhase.NONE
			_state = State.RECOVERY
			_phase_timer = attack.recovery
			_reset_telegraph()


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
func _play_telegraph(attack: BossAttack) -> void:
	_kill_telegraph()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	var duration: float = maxf(0.05, attack.startup * 0.9)
	match attack.telegraph:
		BossAttack.Telegraph.LEAN:
			_telegraph_tween.tween_property(mesh_root, "rotation:x", deg_to_rad(-22.0), duration)
		BossAttack.Telegraph.SPIN:
			_telegraph_tween.tween_property(mesh_root, "rotation:y", -TAU, duration)
		BossAttack.Telegraph.COMPRESS:
			_telegraph_tween.tween_property(mesh_root, "scale", Vector3(1.35, 0.55, 1.35), duration)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", attack.telegraph_color, duration)


func _play_intro_telegraph() -> void:
	_kill_telegraph()
	_telegraph_tween = create_tween()
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3(1.15, 1.2, 1.15), maxf(0.05, intro_duration * 0.5))
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3.ONE, maxf(0.05, intro_duration * 0.5))


func _reset_telegraph() -> void:
	_kill_telegraph()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(mesh_root, "rotation", Vector3.ZERO, 0.25)
	_telegraph_tween.tween_property(mesh_root, "scale", Vector3.ONE, 0.25)
	_telegraph_tween.tween_property(mesh_root, "position:y", 0.0, 0.25)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", _base_albedo, 0.25)


func _reset_telegraph_instantly() -> void:
	_kill_telegraph()
	mesh_root.rotation = Vector3.ZERO
	mesh_root.scale = Vector3.ONE
	mesh_root.position.y = 0.0
	if _body_material != null:
		_body_material.albedo_color = _base_albedo


# --- damage / death -----------------------------------------------------------

func _deactivate_all_hitboxes() -> void:
	for hitbox in _hitboxes:
		if hitbox != null and hitbox.is_active():
			hitbox.deactivate()


## Deliberately lighter than the enemy's squash: a boss should not read as
## flinching. A brief tint pulse, no displacement, no stagger.
func _on_health_changed(current: float, _maximum: float) -> void:
	if current < _last_health:
		_hit_flash()
	_last_health = current


func _hit_flash() -> void:
	if _body_material == null:
		return
	if _feedback_tween != null and _feedback_tween.is_running():
		_feedback_tween.kill()
	var resting: Color = _body_material.albedo_color
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(_body_material, "albedo_color", Color(1.0, 1.0, 1.0), 0.04)
	_feedback_tween.tween_property(_body_material, "albedo_color", resting, 0.16)


func _on_died() -> void:
	_state = State.DEAD
	_attack_phase = AttackPhase.NONE
	_active_attack = -1
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
	enemy_died.emit(self)
