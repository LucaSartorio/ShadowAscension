class_name EnemySupport
extends Node

## A support archetype's support (M12.6): the allies it notices, the one it has
## chosen to support, and what it means to do for it. The one owner of that
## answer — the support target — kept apart from the hostile target, which stays
## EnemyTargeting's: the support fights the player and the shadows under the
## M12.1 policy like every enemy, and helps its allies besides.
##
##     look around (every ally_scan_interval: one physics query, never the tree)
##       -> choose: the ally with the lowest share of its health, under the heal
##          threshold, if the heal is ready; else, if the buff is ready, the
##          fighting ally nearest the foe that is not buffed yet; else nobody
##       -> the plan: that ally and that action, kept (not re-chosen every look)
##          until it is done, the ally dies, leaves, or no longer needs it
##       -> the enemy walks into reach and sight of it, and casts: the action runs
##          through its attack (EnemySupportAttack), windup / active / recovery
##       -> apply_cast() at ACTIVE: the heal through the ally's HealthComponent,
##          the buff through its EnemyAttack; that action's cooldown starts
##
## With nothing to do for anyone it holds no plan, and the enemy fights with its
## offensive fallback. Alone, its looks find nobody, and it simply fights.
##
## The action under way is its attack's (EnemyAttack's current attack and phase):
## get_current_action() only names it. Nothing here duplicates it — no flag says
## "casting" beside the attack's own phase. All of it is this node's, one per
## enemy: two supports sharing an EnemyData share no target, cast or cooldown.

## The ally it supports changed: a new one, or null when it let go.
signal support_target_changed(ally: RoomCombatant)
## A support action landed on `ally`: the health a heal restored, or the share a
## buff added (0 if the ally was buffed by someone else first).
signal support_applied(ally: RoomCombatant, action: AttackData, amount: float)

## What the enemy is doing, as far as support goes — a name for its attack's
## current attack, not a second record of it.
enum Action { NONE, HEAL, BUFF, OFFENSIVE }

## Two shares of health closer than this are a tie, and the nearer ally wins.
const HEALTH_SHARE_TIE: float = 0.001
## The properties through which an ally exposes its health and its attack — every
## enemy on the AI foundation does. Without an attack it is no ally (the boss).
const HEALTH_PROPERTY: StringName = &"health_component"
const ATTACK_PROPERTY: StringName = &"attack"
const TARGETING_PROPERTY: StringName = &"targeting"
## PLACEHOLDER: how the marker under the ally pulses when the action lands.
const MARKER_PULSE_SCALE: float = 1.8
const MARKER_PULSE_TIME: float = 0.3
const MARKER_LIFT: float = 0.06

## PLACEHOLDER: a ring laid under the ally while the cast is for it, in the
## action's colour. Wired in the scene; top-level, so it stays where it is put.
@export var cast_marker: MeshInstance3D = null

# Configuration, copied from the archetype's EnemyData (and its support data) by
# configure().
var ally_mask: int = 0
var ally_detection_range: float = 0.0
var support_range: float = 0.0
var cast_break_margin: float = 0.0
var ally_scan_interval: float = 0.0
var max_allies: int = 0
var approach_timeout: float = 0.0
var heal_action: AttackData = null
var heal_threshold: float = 0.0
var heal_fraction: float = 0.0
var heal_cooldown: float = 0.0
var heal_color: Color = Color.WHITE
var buff_action: AttackData = null
var buff_damage_bonus: float = 0.0
var buff_duration: float = 0.0
var buff_cooldown: float = 0.0
var buff_color: Color = Color.WHITE
var eye_height: float = 0.0
var line_of_sight_mask: int = 0
var line_of_sight_interval: float = 0.0

# Handed over by the enemy in setup().
var _body: CharacterBody3D = null
var _hostile: EnemyTargeting = null
var _attack: EnemyAttack = null

## The allies seen at the last look. Untyped on purpose: an ally freed between
## two looks must not break it; it is skipped by the validity check instead.
var _allies: Array = []
## The plan: whom it supports, and with what. Both null, or both set.
var _support_target: RoomCombatant = null
var _action: AttackData = null
var _heal_cooldown_remaining: float = 0.0
var _buff_cooldown_remaining: float = 0.0
var _scan_remaining: float = 0.0
## Seconds the plan has been out of reach or out of sight, in a row.
var _unreachable: float = 0.0
var _in_sight: bool = false
var _sight_age: float = INF
var _query: PhysicsShapeQueryParameters3D = null
var _marker_material: StandardMaterial3D = null
var _marker_tween: Tween = null

var _scans: int = 0
var _heals: int = 0
var _buffs: int = 0
var _healed: float = 0.0
var _abandoned: int = 0


## Copies what this archetype does for its allies from its data. Called by the
## enemy while it seeds itself. Without support data it supports nobody.
func configure(source: EnemyData) -> void:
	eye_height = source.eye_height
	line_of_sight_mask = source.line_of_sight_mask
	line_of_sight_interval = source.line_of_sight_interval
	var data: EnemySupportData = source.support
	if data == null:
		push_warning("%s: its EnemyData has no support data; it will support nobody." % get_parent().name)
		return
	ally_mask = data.ally_mask
	ally_detection_range = data.ally_detection_range
	support_range = data.support_range
	cast_break_margin = data.cast_break_margin
	ally_scan_interval = data.ally_scan_interval
	max_allies = data.max_allies
	approach_timeout = data.approach_timeout
	heal_action = data.heal_action
	heal_threshold = data.heal_threshold
	heal_fraction = data.heal_fraction
	heal_cooldown = data.heal_cooldown
	heal_color = data.heal_color
	buff_action = data.buff_action
	buff_damage_bonus = data.buff_damage_bonus
	buff_duration = data.buff_duration
	buff_cooldown = data.buff_cooldown
	buff_color = data.buff_color


## Called once by the enemy with its body, its hostile targeting (whom it
## fights — the buff goes to the ally nearest that) and its attack (which runs
## the casts).
func setup(body: CharacterBody3D, hostile: EnemyTargeting, attack: EnemyAttack) -> void:
	_body = body
	_hostile = hostile
	_attack = attack
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = maxf(ally_detection_range, 0.01)
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = sphere
	_query.collision_mask = ally_mask
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.exclude = [body.get_rid()]
	if cast_marker != null:
		var mat: StandardMaterial3D = cast_marker.material_override as StandardMaterial3D
		if mat != null:
			_marker_material = mat.duplicate() as StandardMaterial3D
			cast_marker.material_override = _marker_material
		cast_marker.visible = false
	set_process(false)


func _exit_tree() -> void:
	_support_target = null
	_action = null
	_allies.clear()


# --- queries ---------------------------------------------------------------------

func get_support_target() -> RoomCombatant:
	return _support_target


## The action it means to cast on its support target — the heal or the buff — or
## null with no plan.
func get_planned_action() -> AttackData:
	return _action


func has_plan() -> bool:
	return _action != null


func is_support_action(action: AttackData) -> bool:
	return action != null and (action == heal_action or action == buff_action)


## What the enemy is doing now: the heal or the buff being cast (or landing, or
## recovering from), its offensive attack, or nothing.
func get_current_action() -> Action:
	var current: AttackData = _attack.get_current_attack() if _attack != null else null
	if current == null:
		return Action.NONE
	if current == heal_action:
		return Action.HEAL
	if current == buff_action:
		return Action.BUFF
	return Action.OFFENSIVE


## A support action is being cast: its attack is in the telegraph of the planned
## action — before it lands.
func is_casting() -> bool:
	return _action != null and _attack != null and _attack.get_current_attack() == _action \
		and _attack.get_phase() == EnemyAttack.Phase.TELEGRAPH


## Whether the planned action could be cast from here, now: the ally within
## support_range and in sight, and the action off its cooldown.
func can_cast() -> bool:
	if _action == null or is_casting() or not _is_ready(_action):
		return false
	if not _is_alive(_support_target) or _distance_to(_support_target) > support_range:
		return false
	return _ally_in_sight()


## The action to cast now, or null: what the attack picks before its offence.
func get_castable_action() -> AttackData:
	return _action if can_cast() else null


## Whether the cast under way still has an ally to land on: alive, and not more
## than cast_break_margin beyond support_range. Neither the player coming close
## nor the ally stepping out of sight cancels it — it is committed.
func is_cast_valid() -> bool:
	return _is_alive(_support_target) and _distance_to(_support_target) <= support_range + cast_break_margin


## The share of its maximum health `ally` has now; 0 for anything without health.
func health_share_of(ally: Node) -> float:
	var health: HealthComponent = _health_of(ally)
	if health == null or health.max_health <= 0.0:
		return 0.0
	return health.current_health / health.max_health


func get_action_color(action: AttackData) -> Color:
	return buff_color if action == buff_action and action != null else heal_color


func get_heal_cooldown_remaining() -> float:
	return _heal_cooldown_remaining


func get_buff_cooldown_remaining() -> float:
	return _buff_cooldown_remaining


func get_allies() -> Array:
	return _allies


func get_scan_count() -> int:
	return _scans


func get_heal_count() -> int:
	return _heals


func get_buff_count() -> int:
	return _buffs


## Health restored, in all, by this support's heals.
func get_healed_total() -> float:
	return _healed


## Plans given up because the ally could not be reached in approach_timeout.
func get_abandoned_count() -> int:
	return _abandoned


# --- the enemy's tick ----------------------------------------------------------------

## Runs the cooldowns and, while the enemy is fighting (`searching`), the plan:
## it is checked every tick — cheap, no search — and the allies are looked for,
## and an ally chosen, every ally_scan_interval. Not fighting — idle, staggered —
## it plans nothing, and lets go of a plan it had not started.
func tick(delta: float, searching: bool) -> void:
	if _heal_cooldown_remaining > 0.0:
		_heal_cooldown_remaining = maxf(0.0, _heal_cooldown_remaining - delta)
	if _buff_cooldown_remaining > 0.0:
		_buff_cooldown_remaining = maxf(0.0, _buff_cooldown_remaining - delta)
	_sight_age += delta
	if not searching:
		if _action != null and not is_casting():
			_set_plan(null, null)
		return
	_check_plan(delta)
	_scan_remaining -= delta
	if _scan_remaining <= 0.0:
		_scan_remaining = ally_scan_interval
		_look_around()
		_choose()


## The telegraph of the planned action has begun (EnemySupportAttack): the
## marker goes under the ally.
func cast_started() -> void:
	_unreachable = 0.0
	_show_marker(get_action_color(_action))


## The planned action lands on the ally — called at the start of ACTIVE. False,
## and nothing done, if the ally is no longer there to take it. The heal is the
## ally's own HealthComponent.heal(): it clamps to the ally's maximum — a heal
## that lands on a full ally (another support was faster) restores nothing —
## and never raises the dead. The action's cooldown starts, and the plan is done.
func apply_cast() -> bool:
	var ally: RoomCombatant = _support_target
	var action: AttackData = _action
	if action == null or not is_cast_valid():
		end_cast(false)
		return false
	var amount: float = 0.0
	if action == heal_action:
		var health: HealthComponent = _health_of(ally)
		amount = health.heal(health.max_health * heal_fraction)
		_heals += 1
		_healed += amount
		_heal_cooldown_remaining = heal_cooldown
	else:
		var ally_attack: EnemyAttack = _attack_of(ally)
		if ally_attack != null and ally_attack.apply_damage_buff(buff_damage_bonus, buff_duration, buff_color):
			amount = buff_damage_bonus
		_buffs += 1
		_buff_cooldown_remaining = buff_cooldown
	_pulse_marker()
	_set_plan(null, null)
	support_applied.emit(ally, action, amount)
	return true


## The cast ended before it landed. `spent`: it was cut off — a stagger, a death
## — and the action waits out its cooldown as if cast, so interrupting a support
## is worth it. Not spent: its ally went away, and it chooses again at once —
## on the next tick, not the next look around.
func end_cast(spent: bool) -> void:
	if _action == null:
		return
	if spent:
		_start_cooldown(_action)
	else:
		_scan_remaining = 0.0
	_hide_marker()
	_set_plan(null, null)


## Nothing planned, nothing cooling down, nobody seen. For an enemy the room
## parks — or a test resetting one.
func reset() -> void:
	_set_plan(null, null)
	_allies.clear()
	_heal_cooldown_remaining = 0.0
	_buff_cooldown_remaining = 0.0
	_scan_remaining = 0.0
	_hide_marker()


## Its enemy died: nobody supported, nobody watched, nothing shown.
func release() -> void:
	_set_plan(null, null)
	_allies.clear()
	_hide_marker()


# --- the plan ---------------------------------------------------------------------

## Keeps the plan honest every tick: a gone or dead ally is let go at once;
## before the cast, so is one that has wandered out of notice or no longer needs
## the action — healed by someone else, buffed by someone else. An ally it cannot
## reach or see for approach_timeout is given up, and the action waits out its
## cooldown, so an unreachable ally never stops it fighting.
func _check_plan(delta: float) -> void:
	if _action == null:
		return
	if not _is_alive(_support_target):
		if not is_casting():
			_set_plan(null, null)
		return
	if is_casting():
		return
	if _distance_to(_support_target) > ally_detection_range or not _still_needs(_support_target, _action):
		_set_plan(null, null)
		return
	if can_cast():
		_unreachable = 0.0
		return
	_unreachable += delta
	if approach_timeout > 0.0 and _unreachable >= approach_timeout:
		_abandoned += 1
		_start_cooldown(_action)
		_set_plan(null, null)


## Whom to support, and how: the heal first — the most hurt ally under the
## threshold — then the buff. A heal already planned is kept (stickiness: a
## slightly more hurt ally does not steal it); a planned buff gives way to a
## heal that has become needed; nothing is re-chosen during a cast.
func _choose() -> void:
	if is_casting():
		return
	if _action != null and _action == heal_action:
		return
	var ally: RoomCombatant = _most_hurt() if _is_ready(heal_action) else null
	if ally != null:
		_set_plan(ally, heal_action)
		return
	if _action != null:
		return
	ally = _buff_candidate() if _is_ready(buff_action) else null
	if ally != null:
		_set_plan(ally, buff_action)


## The ally with the lowest share of its health, under the heal threshold: a
## share, so a tank at 40% comes before a melee at 60% whatever their maximums.
## Ties go to the nearer.
func _most_hurt() -> RoomCombatant:
	var best: RoomCombatant = null
	var best_share: float = heal_threshold
	var best_distance: float = INF
	for candidate in _allies:
		if not _is_ally(candidate):
			continue
		var ally: RoomCombatant = candidate as RoomCombatant
		var share: float = health_share_of(ally)
		if share >= heal_threshold:
			continue
		var distance: float = _distance_to(ally)
		if share < best_share - HEALTH_SHARE_TIE \
				or (absf(share - best_share) <= HEALTH_SHARE_TIE and distance < best_distance):
			best = ally
			best_share = share
			best_distance = distance
	return best


## A fighting ally that is not buffed yet, the one nearest the foe — the one
## doing the fighting. None while the enemy fights nobody.
func _buff_candidate() -> RoomCombatant:
	if _hostile == null or not _hostile.has_target():
		return null
	var foe: Vector3 = _hostile.get_target_position()
	var best: RoomCombatant = null
	var best_distance: float = INF
	for candidate in _allies:
		if not _is_ally(candidate):
			continue
		var ally: RoomCombatant = candidate as RoomCombatant
		if not _still_needs(ally, buff_action) or not _is_fighting(ally):
			continue
		var offset: Vector3 = ally.global_position - foe
		offset.y = 0.0
		var distance: float = offset.length_squared()
		if distance < best_distance:
			best = ally
			best_distance = distance
	return best


func _still_needs(ally: RoomCombatant, action: AttackData) -> bool:
	if action == heal_action:
		return health_share_of(ally) < heal_threshold
	var ally_attack: EnemyAttack = _attack_of(ally)
	return ally_attack != null and not ally_attack.has_damage_buff()


func _set_plan(ally: RoomCombatant, action: AttackData) -> void:
	var changed: bool = not is_same(ally, _support_target)
	_support_target = ally
	_action = action if ally != null else null
	_unreachable = 0.0
	_sight_age = INF
	if changed:
		support_target_changed.emit(_support_target)


func _start_cooldown(action: AttackData) -> void:
	if action == heal_action:
		_heal_cooldown_remaining = heal_cooldown
	elif action == buff_action:
		_buff_cooldown_remaining = buff_cooldown


func _is_ready(action: AttackData) -> bool:
	if action == null:
		return false
	if action == heal_action:
		return _heal_cooldown_remaining <= 0.0
	return _buff_cooldown_remaining <= 0.0


# --- the allies ---------------------------------------------------------------------

## One physics query for the bodies on the ally layers around it — never a walk
## of the scene tree. Whatever it finds is only a candidate; _is_ally() decides.
func _look_around() -> void:
	_allies.clear()
	if _body == null or _query == null or not _body.is_inside_tree():
		return
	_scans += 1
	_query.transform = Transform3D(Basis.IDENTITY, _body.global_position)
	for hit in _body.get_world_3d().direct_space_state.intersect_shape(_query, max_allies):
		var ally: RoomCombatant = hit.get("collider") as RoomCombatant
		if ally != null and not _allies.has(ally) and _is_ally(ally):
			_allies.append(ally)


## An ally: another enemy on the AI foundation — alive, in the fight, noticed.
func _is_ally(candidate: Variant) -> bool:
	if not _is_alive(candidate):
		return false
	var ally: RoomCombatant = candidate as RoomCombatant
	return ally.combat_enabled and _attack_of(ally) != null and _distance_to(ally) <= ally_detection_range


func _is_alive(candidate: Variant) -> bool:
	if not is_instance_valid(candidate):
		return false
	var ally: RoomCombatant = candidate as RoomCombatant
	if ally == null or not ally.is_inside_tree() or ally.has_died() or is_same(ally, _body):
		return false
	var health: HealthComponent = _health_of(ally)
	return health != null and not health.is_dead


## Fighting: its own targeting holds a target.
func _is_fighting(ally: RoomCombatant) -> bool:
	var targeting: EnemyTargeting = ally.get(TARGETING_PROPERTY) as EnemyTargeting
	return targeting != null and targeting.has_target()


func _health_of(ally: Node) -> HealthComponent:
	if ally == null or not is_instance_valid(ally):
		return null
	return ally.get(HEALTH_PROPERTY) as HealthComponent


func _attack_of(ally: Node) -> EnemyAttack:
	if ally == null or not is_instance_valid(ally):
		return null
	return ally.get(ATTACK_PROPERTY) as EnemyAttack


func _distance_to(ally: Node3D) -> float:
	if _body == null or ally == null:
		return INF
	var offset: Vector3 = ally.global_position - _body.global_position
	offset.y = 0.0
	return offset.length()


## Whether the support target is in sight, from a ray at most
## line_of_sight_interval old — nothing of the world between the two.
func _ally_in_sight() -> bool:
	if _sight_age >= line_of_sight_interval:
		_sight_age = 0.0
		_in_sight = _support_target != null and _has_line_of_sight(_support_target)
	return _in_sight


func _has_line_of_sight(ally: RoomCombatant) -> bool:
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		_body.global_position + Vector3.UP * eye_height, ally.global_position + Vector3.UP * eye_height,
		line_of_sight_mask)
	query.exclude = [_body.get_rid(), ally.get_rid()]
	return space.intersect_ray(query).is_empty()


# --- the marker (PLACEHOLDER until M14) ----------------------------------------------------

func _process(_delta: float) -> void:
	if cast_marker == null or not cast_marker.visible:
		set_process(false)
		return
	if is_casting() and is_instance_valid(_support_target):
		cast_marker.global_position = _support_target.global_position + Vector3.UP * MARKER_LIFT


func _show_marker(color: Color) -> void:
	if cast_marker == null or not is_instance_valid(_support_target):
		return
	_kill_marker_tween()
	if _marker_material != null:
		_marker_material.albedo_color = color
	cast_marker.scale = Vector3.ONE
	cast_marker.global_position = _support_target.global_position + Vector3.UP * MARKER_LIFT
	cast_marker.visible = true
	set_process(true)


## The action landed: the ring flares out and is gone.
func _pulse_marker() -> void:
	if cast_marker == null or not cast_marker.visible:
		return
	_kill_marker_tween()
	_marker_tween = create_tween()
	_marker_tween.tween_property(cast_marker, "scale", Vector3.ONE * MARKER_PULSE_SCALE, MARKER_PULSE_TIME)
	_marker_tween.tween_callback(_put_marker_away)


func _hide_marker() -> void:
	_kill_marker_tween()
	_put_marker_away()


func _put_marker_away() -> void:
	_marker_tween = null
	if cast_marker == null:
		return
	cast_marker.visible = false
	cast_marker.scale = Vector3.ONE
	set_process(false)


func _kill_marker_tween() -> void:
	if _marker_tween != null and _marker_tween.is_running():
		_marker_tween.kill()
	_marker_tween = null
