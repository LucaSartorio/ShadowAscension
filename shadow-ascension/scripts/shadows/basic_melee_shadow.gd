class_name BasicMeleeShadow
extends CharacterBody3D

## A summoned shadow: it follows the player, and fights what the player's orders
## — or its own command mode — put in front of it.
##
## Its own state logic, not the enemy's — it shares the components (health,
## hurtbox, hitbox, navigation) and none of the AI, the same split
## BasicEnemy and DungeonBoss already have.
##
## Health and damage come from the ShadowInstance's level, so a level-up changes
## what it does without any stat system of its own. It knows which instance it
## belongs to; the instance knows nothing about the scene.
##
## What it is TOLD to do lives here as state; who does the telling is
## PlayerShadowCommander. This node never reads input.
##
## Its body collides with the world only. Enemies already pass through it —
## their mask never had the shadow's layer in it — and making it solid to them
## in the one direction only meant an enemy walking at the player could pin the
## shadow against nothing. Who stands where in a fight is decided by attack
## ranges, not by bodies shoving each other.

signal shadow_died(shadow: BasicMeleeShadow)
signal command_mode_changed(mode: CommandMode)
## Emitted whenever the ordered target changes, including when the shadow drops
## it itself — a target that died or left the leash. The marker follows this
## rather than only the moment the player gave the order.
signal manual_target_changed(target: RoomCombatant)

enum State { FOLLOW, ACQUIRE_TARGET, CHASE_TARGET, ATTACK, RETURN_TO_PLAYER, DEAD }
enum AttackPhase { NONE, STARTUP, ACTIVE }
## FOLLOW never picks a fight by itself; AGGRESSIVE does. Both obey an order.
enum CommandMode { FOLLOW, AGGRESSIVE }

const GROUP: StringName = &"active_shadow"

@export var shadow_data: ShadowData

@export_group("Movement")
@export var movement_speed: float = 4.4
@export var acceleration: float = 14.0
@export var rotation_speed: float = 9.0
@export var gravity: float = 20.0
## Where it tries to stand when there is nothing to fight. Also where a return
## ends, so the two can never disagree about what "back with the player" means.
@export var follow_distance: float = 2.0
## Slack around `follow_distance`. It stops at the distance and only starts
## walking again once it is this much further out, which is what stops a shadow
## from shuffling back and forth on the spot.
@export var arrival_tolerance: float = 0.6
## Past this it stops loitering and walks back.
@export var max_follow_distance: float = 8.0
## A shadow this far below the player has left the level. Recovered at once
## rather than on the stuck timer: it is falling, and waiting only adds distance.
@export var fall_recovery_depth: float = 6.0
@export var target_update_interval: float = 0.2

@export_group("Combat")
@export var enemy_detection_range: float = 10.0
## How far from the PLAYER a fight may go. Not a distance from the shadow: the
## point is to keep the shadow near whoever it is guarding.
@export var max_combat_distance_from_player: float = 18.0
@export var attack_range: float = 1.6
@export var attack_startup: float = 0.25
@export var attack_active: float = 0.12
@export var attack_recovery: float = 0.45
@export var attack_cooldown: float = 0.5
## How long a quick recall keeps the shadow out of the fight after it is given.
## Without it, an AGGRESSIVE shadow recalled next to an enemy re-acquires the
## moment it gets home, and the order is undone within a second of being given —
## which is exactly when the player wanted it. It is a hold, not a mode change:
## the mode is the player's to set, and this expires on its own.
@export var recall_hold_duration: float = 3.0
@export var death_fade_duration: float = 0.7

@export_group("Stuck recovery")
## How long it may fail to make progress before anything is done about it.
@export var stuck_check_duration: float = 1.75
## Less ground than this covered over the window counts as no progress.
@export var stuck_progress_epsilon: float = 0.35
## Repathing is always tried first. Only a shadow that is still stuck AND this
## far from the player is repositioned — near the player it can be left to sort
## itself out, because the player can see it.
@export var hard_recovery_distance: float = 13.0
## Stops a repositioned shadow that is still stuck from teleporting on a loop.
@export var recovery_cooldown: float = 6.0

@onready var visual_root: Node3D = $VisualRoot
## The PLACEHOLDER body its accent tints. Optional: a definitive model without
## it keeps the shadow's behaviour whole (M13.7's shadow visual system replaces it).
@onready var mesh_instance: MeshInstance3D = get_node_or_null(^"VisualRoot/MeshInstance3D") as MeshInstance3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_component: HealthComponent = $HealthComponent
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hurtbox_collision: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var detection_area: Area3D = $DetectionArea
@onready var detection_shape: CollisionShape3D = $DetectionArea/CollisionShape3D
@onready var attack_hitbox: Hitbox = $VisualRoot/AttackOrigin/Hitbox

var instance: ShadowInstance = null
## Summoned ready to fight. The player switches it down, not up.
var command_mode: CommandMode = CommandMode.AGGRESSIVE

var _state: State = State.FOLLOW
var _attack_phase: AttackPhase = AttackPhase.NONE
var _phase_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _target_update_accum: float = 0.0

## The player this shadow belongs to, handed over by the summoner in bind().
## Never looked up: a shadow follows, defends and returns to its own summoner,
## not to whichever player a tree search happens to find first.
var _player: Player = null
## What the player pointed at. Outranks anything the shadow finds itself.
var _manual_target: RoomCombatant = null
## What the shadow found on its own, in AGGRESSIVE only.
var _auto_target: RoomCombatant = null
var _desired_horizontal: Vector3 = Vector3.ZERO
var _material: StandardMaterial3D = null

## Set when a recall arrives mid-swing: the active window finishes, then it goes.
var _recall_pending: bool = false
## Hysteresis for the stand-off, so it settles instead of oscillating.
var _settled: bool = false
## Counts down after a recall; while it runs the shadow will not pick its own
## fights. An order from the player clears it — asking for an attack outranks
## having asked to disengage.
var _recall_hold_left: float = 0.0

var _stuck_timer: float = 0.0
var _stuck_anchor: Vector3 = Vector3.ZERO
var _repath_tried: bool = false
var _recovery_cooldown_left: float = 0.0
## How many times it has been repositioned. Telemetry, and the thing to watch
## when asking whether recovery has turned into a way of getting around.
var recovery_count: int = 0


func _ready() -> void:
	add_to_group(GROUP)
	attack_hitbox.source = self
	_setup_material()
	_apply_detection_range()
	nav_agent.max_speed = movement_speed
	health_component.died.connect(_on_died)
	_stuck_anchor = global_position


## Called by the summoner before the shadow enters the tree, so its very first
## frame already has the right health and damage for its level, and already
## knows whose shadow it is. A shadow that was never bound has no owner and
## stands still.
func bind(shadow_instance: ShadowInstance, owner_player: Player = null) -> void:
	instance = shadow_instance
	_player = owner_player
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


# --- queries ---------------------------------------------------------------------

func get_state() -> State:
	return _state


## The target it is actually acting on: the order first, then what it found on
## its own, and nothing at all in FOLLOW without an order.
func get_target() -> RoomCombatant:
	if _manual_target != null:
		return _manual_target
	if command_mode == CommandMode.AGGRESSIVE:
		return _auto_target
	return null


func get_manual_target() -> RoomCombatant:
	return _manual_target


func get_auto_target() -> RoomCombatant:
	return _auto_target


func get_attack_damage() -> float:
	return instance.get_damage() if instance != null else 0.0


func is_dead() -> bool:
	return _state == State.DEAD


func is_returning() -> bool:
	return _state == State.RETURN_TO_PLAYER


## Whether the cheap answer to being stuck has already been tried on the current
## problem. Exposed so the escalation can be observed rather than inferred.
func has_tried_repath() -> bool:
	return _repath_tried


# --- orders -------------------------------------------------------------------------

func set_command_mode(mode: CommandMode) -> void:
	if _state == State.DEAD or mode == command_mode:
		return
	command_mode = mode
	if mode == CommandMode.FOLLOW:
		# It stops hunting at once. An order it is already carrying out stands —
		# switching to FOLLOW is "stop picking fights", not "stand down".
		_auto_target = null
		if _manual_target == null and _state in [State.ACQUIRE_TARGET, State.CHASE_TARGET]:
			_begin_return()
	command_mode_changed.emit(mode)


func toggle_command_mode() -> void:
	set_command_mode(CommandMode.AGGRESSIVE if command_mode == CommandMode.FOLLOW
		else CommandMode.FOLLOW)


## Returns false when the target is not one it can be sent at — dead, gone, or
## already outside the leash, in which case nothing about its behaviour changes.
func set_manual_target(target: RoomCombatant) -> bool:
	if _state == State.DEAD or not is_valid_target(target):
		return false
	_manual_target = target
	# An order replaces whatever it had picked for itself, and overrides a hold
	# still running from a recall.
	_auto_target = null
	_recall_pending = false
	_recall_hold_left = 0.0
	if _state in [State.FOLLOW, State.RETURN_TO_PLAYER]:
		_state = State.ACQUIRE_TARGET
	manual_target_changed.emit(target)
	return true


func clear_manual_target() -> void:
	if _manual_target == null:
		return
	_manual_target = null
	manual_target_changed.emit(null)


## "Come back to me" — a tactical order, not a despawn. The shadow stays in the
## collection and stays summoned; it just stops what it was doing.
func recall_to_player() -> void:
	if _state == State.DEAD:
		return
	clear_manual_target()
	_auto_target = null
	_recall_hold_left = recall_hold_duration
	# Mid-swing the active window is allowed to finish: cutting a hitbox off
	# inside its own frame is how you get a live hitbox on a walking shadow.
	if _state == State.ATTACK and _attack_phase == AttackPhase.ACTIVE:
		_recall_pending = true
		return
	_begin_return()


func _begin_return() -> void:
	_end_attack()
	_recall_pending = false
	_settled = false
	_state = State.RETURN_TO_PLAYER
	_reset_stuck()


## Leaves no live hitbox behind, whatever the swing was doing.
func _end_attack() -> void:
	if attack_hitbox.is_active():
		attack_hitbox.deactivate()
	_attack_phase = AttackPhase.NONE
	_phase_timer = 0.0


# --- target validation ----------------------------------------------------------------

## The single answer to "may the shadow act on this". Every state asks here
## rather than repeating the checks, so a rule added later lands in one place.
func is_valid_target(target: RoomCombatant) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.is_inside_tree() or target.has_died():
		return false
	var player: Player = _get_player()
	if player == null:
		return false
	# The leash is measured from the player, not from the shadow: the point is
	# to keep the fight near whoever is being guarded.
	return player.global_position.distance_to(target.global_position) \
		<= max_combat_distance_from_player


## Drops whatever is no longer actionable. Called once per frame, before any
## state looks at a target, so no state ever sees a corpse.
func _validate_targets() -> void:
	if _manual_target != null and not is_valid_target(_manual_target):
		clear_manual_target()
	if _auto_target != null and not is_valid_target(_auto_target):
		_auto_target = null


# --- setup ------------------------------------------------------------------------------

func _setup_material() -> void:
	if mesh_instance == null:
		return
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
	if _recovery_cooldown_left > 0.0:
		_recovery_cooldown_left = maxf(0.0, _recovery_cooldown_left - delta)
	if _recall_hold_left > 0.0:
		_recall_hold_left = maxf(0.0, _recall_hold_left - delta)

	var player: Player = _get_player()
	if player == null:
		_apply_motion(Vector3.ZERO, delta)
		return

	_validate_targets()
	var distance_to_player: float = global_position.distance_to(player.global_position)
	if _check_fall(player):
		return
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
	return _player if _player != null and is_instance_valid(_player) else null


# --- states ------------------------------------------------------------------------

## Stands off the player's shoulder rather than inside them.
func _follow_offset(player: Player) -> Vector3:
	var behind: Vector3 = player.global_position - global_position
	behind.y = 0.0
	if behind.length_squared() < 0.0001:
		behind = Vector3.BACK
	return -behind.normalized() * follow_distance


func _follow_step(delta: float, player: Player, distance_to_player: float) -> void:
	if _may_hunt():
		_auto_target = _find_target()
	if get_target() != null:
		_state = State.ACQUIRE_TARGET
		return
	if distance_to_player > max_follow_distance:
		_begin_return()
		return
	# Hysteresis: it stops AT the distance and only sets off again once it is a
	# tolerance further out.
	if _settled and distance_to_player <= follow_distance + arrival_tolerance:
		_apply_motion(_accelerate_toward(Vector3.ZERO, delta), delta)
		_face(player.global_position - global_position, delta)
		return
	if distance_to_player <= follow_distance:
		_settled = true
		_apply_motion(_accelerate_toward(Vector3.ZERO, delta), delta)
		_face(player.global_position - global_position, delta)
		return
	_settled = false
	_walk_towards(player.global_position + _follow_offset(player), delta)


func _acquire_step(delta: float, player: Player) -> void:
	if _may_hunt():
		_auto_target = _find_target()
	if get_target() == null:
		_state = State.FOLLOW
		_follow_step(delta, player, global_position.distance_to(player.global_position))
		return
	_state = State.CHASE_TARGET


func _chase_step(delta: float, player: Player) -> void:
	var target: RoomCombatant = get_target()
	if target == null:
		# Nothing left to fight: AGGRESSIVE looks for the next one, FOLLOW does
		# not, and either way a shadow far from the player heads back.
		_after_target_lost(player)
		return
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() <= attack_range and _cooldown_timer <= 0.0:
		_begin_attack(to_target)
		return
	_walk_towards(target.global_position, delta)


## One place decides what happens when there is no longer anything to hit, so
## FOLLOW and AGGRESSIVE cannot drift apart.
func _after_target_lost(player: Player) -> void:
	if _may_hunt():
		_auto_target = _find_target()
		if _auto_target != null:
			_state = State.CHASE_TARGET
			return
	if global_position.distance_to(player.global_position) > follow_distance + arrival_tolerance:
		_begin_return()
		return
	_state = State.FOLLOW


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
			_end_attack()
			_phase_timer = attack_recovery
			_cooldown_timer = attack_cooldown + attack_recovery
			# A recall that arrived mid-swing is honoured here, with the hitbox
			# already down.
			if _recall_pending:
				_begin_return()
				return
			if get_target() != null:
				_state = State.CHASE_TARGET
			else:
				_after_target_lost(_get_player())


func _return_step(delta: float, player: Player, distance_to_player: float) -> void:
	# An order given while walking back takes over immediately.
	if _manual_target != null:
		_state = State.ACQUIRE_TARGET
		return
	if distance_to_player <= follow_distance + arrival_tolerance:
		_settled = true
		_state = State.FOLLOW
		return
	_walk_towards(player.global_position + _follow_offset(player), delta)


# --- movement ---------------------------------------------------------------------

func _walk_towards(point: Vector3, delta: float) -> void:
	_target_update_accum += delta
	if _target_update_accum >= target_update_interval:
		_target_update_accum = 0.0
		nav_agent.target_position = _navigable(point)
	var to_next: Vector3 = nav_agent.get_next_path_position() - global_position
	to_next.y = 0.0
	if to_next.length() < 0.0001:
		# No usable step from the agent. That is normal on the last stride, and
		# it also happens when the path has gone stale under a target that
		# moved — so steer straight at the point before giving up on moving at
		# all. move_and_slide still handles whatever is in the way.
		to_next = point - global_position
		to_next.y = 0.0
		if to_next.length() < 0.0001:
			_apply_motion(_accelerate_toward(Vector3.ZERO, delta), delta)
			return
	var direction: Vector3 = to_next.normalized()
	_apply_motion(_accelerate_toward(direction * movement_speed, delta), delta)
	_face(direction, delta)


## The nearest point on the navmesh. A moving target's exact centre is off the
## mesh more often than not — an enemy standing on the lip of a platform, a boss
## mid-stride — and an agent asked for an unreachable point returns no path at
## all, which reads as a shadow that simply stops.
func _navigable(point: Vector3) -> Vector3:
	var map: RID = nav_agent.get_navigation_map()
	if not map.is_valid():
		return point
	return NavigationServer3D.map_get_closest_point(map, point)


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

## May it pick a fight of its own right now. FOLLOW never does, a recall holds
## it off for a moment, and an order it already has comes first.
func _may_hunt() -> bool:
	return command_mode == CommandMode.AGGRESSIVE \
		and _recall_hold_left <= 0.0 \
		and get_target() == null


## Nearest living enemy inside the detection area. The area does the work, so
## nothing scans the whole scene tree — and it is only consulted when the shadow
## is allowed to pick a fight for itself.
func _find_target() -> RoomCombatant:
	var nearest: RoomCombatant = null
	var nearest_distance: float = INF
	for body in detection_area.get_overlapping_bodies():
		var combatant: RoomCombatant = body as RoomCombatant
		if combatant == null or not is_valid_target(combatant):
			continue
		var distance: float = global_position.distance_to(combatant.global_position)
		if distance < nearest_distance:
			nearest = combatant
			nearest_distance = distance
	return nearest


# --- stuck detection and recovery -------------------------------------------------------

## Falling out of the level is not a navigation problem and is not waited out.
func _check_fall(player: Player) -> bool:
	if player.global_position.y - global_position.y <= fall_recovery_depth:
		return false
	_reposition_beside(player)
	return true


## Progress, not position, is what says a shadow is stuck: one standing still
## because it has arrived is fine, one that should be walking and is not is not.
func _tick_stuck(delta: float, distance_to_player: float, player: Player) -> void:
	if not _should_be_moving():
		_reset_stuck()
		return
	_stuck_timer += delta
	if _stuck_timer < stuck_check_duration:
		return
	var covered: float = _stuck_anchor.distance_to(global_position)
	_stuck_timer = 0.0
	_stuck_anchor = global_position
	if covered >= stuck_progress_epsilon:
		# Moving. Whatever the last repath did, it worked.
		_repath_tried = false
		return
	if not _repath_tried:
		# Always the first answer: the path is stale far more often than the
		# shadow is genuinely trapped.
		_repath_tried = true
		_force_repath()
		return
	# Still stuck after a repath. Near the player it is left alone — the player
	# can see it and walk it out. Far away it is genuinely stranded.
	if distance_to_player < hard_recovery_distance or _recovery_cooldown_left > 0.0:
		return
	_reposition_beside(player)


## Walking is expected in exactly these cases. An attack is a commitment to
## standing still, and a settled shadow has nowhere to be.
func _should_be_moving() -> bool:
	if _state in [State.ATTACK, State.DEAD]:
		return false
	if _state == State.FOLLOW:
		return not _settled
	# Toe to toe with something and waiting out the cooldown. It is standing
	# still because it is fighting, which is the opposite of stuck — without
	# this, every drawn-out melee would look like a navigation failure.
	var target: RoomCombatant = get_target()
	if target != null and global_position.distance_to(target.global_position) <= attack_range:
		return false
	return true


func _force_repath() -> void:
	_target_update_accum = target_update_interval
	var target: RoomCombatant = get_target()
	var player: Player = _get_player()
	if target != null:
		nav_agent.target_position = _navigable(target.global_position)
	elif player != null:
		nav_agent.target_position = _navigable(player.global_position + _follow_offset(player))


func _reset_stuck() -> void:
	_stuck_timer = 0.0
	_stuck_anchor = global_position
	_repath_tried = false


## The last resort, and never a way of getting around. The destination is the
## follow offset beside the player, which is walkable by definition — the player
## is standing there — so this cannot put the shadow inside a wall or under the
## floor the way an arbitrary point could.
func _reposition_beside(player: Player) -> void:
	_end_attack()
	global_position = player.global_position + _follow_offset(player)
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	_recovery_cooldown_left = recovery_cooldown
	recovery_count += 1
	_reset_stuck()
	if _state == State.ATTACK:
		_state = State.CHASE_TARGET if get_target() != null else State.FOLLOW


# --- death -------------------------------------------------------------------------

## The runtime entity dies; the ShadowInstance does not. It stays in the
## collection with its level and XP and can be summoned again.
func _on_died() -> void:
	_state = State.DEAD
	_end_attack()
	clear_manual_target()
	_auto_target = null
	velocity = Vector3.ZERO
	_desired_horizontal = Vector3.ZERO
	nav_agent.avoidance_enabled = false
	hurtbox.call_deferred("set_monitorable", false)
	hurtbox_collision.call_deferred("set_disabled", true)
	body_collision.call_deferred("set_disabled", true)
	detection_area.call_deferred("set_monitoring", false)
	shadow_died.emit(self)

	var t: Tween = create_tween()
	t.tween_property(visual_root, "scale", Vector3(0.1, 0.1, 0.1), death_fade_duration)
	t.tween_callback(queue_free)
