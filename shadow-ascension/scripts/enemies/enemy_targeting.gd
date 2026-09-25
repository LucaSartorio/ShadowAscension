class_name EnemyTargeting
extends Node

## An enemy's target (M12.1): whom it is fighting, if anyone — the one owner of
## that answer. The enemy's state machine, its navigation, its facing and its
## attack all read the target from here; nothing keeps a copy of it.
##
## Untargeted is `_target == null`, and nothing else: no flag beside the
## reference to disagree with it.
##
## Candidates are the living bodies in the enemy's target groups
## (`EnemyData.target_groups`) — a body that carries a `health_component` that is
## not dead. Which of them is chosen is the policy below; the groups are read on
## a cadence while searching, never every frame, and a held target is never
## searched for at all.
##
## Policy: the nearest living candidate within the detection range, flat. Once
## held, a target is kept — no candidate replaces it for being nearer — until it
## dies, leaves the scene, or stays past the lose range for the lose delay. The
## basic enemy's only group is the player's, so it fights the player and never
## a shadow (the behaviour since M4); a shadow group added to an archetype's data
## makes shadows candidates under the same rules.
##
## A target that dies or leaves the scene is let go in the same call — both are
## signals — so nothing ever holds a reference to something gone.

## The target changed: a new one, or null when it was let go.
signal target_changed(target: Node3D)

## Seconds between two readings of the target groups while searching. Between
## them the cached candidates are only measured, which costs no allocation.
const CANDIDATE_REFRESH_INTERVAL: float = 1.0
## The property through which a candidate exposes its health — Player and the
## shadow both do. Anything without one cannot be hurt, so it is no target.
const HEALTH_PROPERTY: StringName = &"health_component"

## Handed over by the enemy in setup().
var _body: Node3D = null
var _groups: Array[StringName] = []

var _target: Node3D = null
var _target_health: HealthComponent = null
## Untyped on purpose: a candidate freed between two refreshes must not break
## the cache; it is skipped by the validity check instead.
var _candidates: Array = []
var _refresh_remaining: float = 0.0
## Seconds the held target has spent past the lose range.
var _out_of_range_elapsed: float = 0.0
## How many times the groups have been read — a refresh each, never a frame.
var _refreshes: int = 0


## Called once by the enemy with its own body, and the groups its data names.
func setup(body: Node3D, groups: Array[StringName]) -> void:
	_body = body
	_groups = groups


## Leaving the tree takes the target with it, quietly: whatever listened to it
## is leaving with this enemy.
func _exit_tree() -> void:
	_disconnect_target()
	_target = null
	_target_health = null


# --- queries ---------------------------------------------------------------------

func get_target() -> Node3D:
	return _target


func has_target() -> bool:
	return _target != null


## Where the target stands; the body's own position while there is none.
func get_target_position() -> Vector3:
	if _target == null:
		return _body.global_position if _body != null else Vector3.ZERO
	return _target.global_position


## From the enemy to the target, flat; zero while there is none.
func get_flat_offset() -> Vector3:
	if _target == null or _body == null:
		return Vector3.ZERO
	var offset: Vector3 = _target.global_position - _body.global_position
	offset.y = 0.0
	return offset


func get_distance() -> float:
	return get_flat_offset().length()


## Whether `candidate` may be fought: a body in the scene, not the enemy itself,
## with a health component that is not dead.
func is_valid_target(candidate: Variant) -> bool:
	if not is_instance_valid(candidate):
		return false
	var body: Node3D = candidate as Node3D
	if body == null or not body.is_inside_tree():
		return false
	if is_same(body, _body):
		return false
	var health: HealthComponent = _health_of(body)
	return health != null and not health.is_dead


func get_refresh_count() -> int:
	return _refreshes


# --- intents ------------------------------------------------------------------------

## Looks for a target: the nearest valid candidate closer than `detection_range`,
## flat. Sets it, and says whether there is one. Called by the enemy while it
## has none; `delta` paces the reading of the groups.
func acquire(detection_range: float, delta: float) -> bool:
	_refresh_remaining -= delta
	if _refresh_remaining <= 0.0:
		_refresh_candidates()
	var best: Node3D = null
	var best_distance_squared: float = detection_range * detection_range
	for candidate in _candidates:
		if not is_valid_target(candidate):
			continue
		var offset: Vector3 = (candidate as Node3D).global_position - _body.global_position
		offset.y = 0.0
		var distance_squared: float = offset.length_squared()
		if distance_squared < best_distance_squared:
			best = candidate as Node3D
			best_distance_squared = distance_squared
	if best == null:
		return false
	_set_target(best)
	return true


## Lets the target go, announcing it if there was one.
func release() -> void:
	_set_target(null)


## False — letting it go first — when the held target is no longer valid: dead,
## freed, out of the scene. Cheap: no search.
func validate() -> bool:
	if _target == null:
		return false
	if is_valid_target(_target):
		return true
	release()
	return false


## Lets the target go once it has spent `lose_delay` seconds further than
## `lose_range`, flat — a grace period, so one step past the edge does not end a
## fight — and says whether it did.
func tick_lose(delta: float, lose_range: float, lose_delay: float) -> bool:
	if _target == null:
		return false
	if get_distance() <= lose_range:
		_out_of_range_elapsed = 0.0
		return false
	_out_of_range_elapsed += delta
	if _out_of_range_elapsed < lose_delay:
		return false
	release()
	return true


# --- the held target ---------------------------------------------------------------

func _set_target(target: Node3D) -> void:
	# By identity: a freed object compares equal to null.
	if is_same(target, _target):
		return
	_disconnect_target()
	_target = target
	_target_health = _health_of(target) if target != null else null
	_out_of_range_elapsed = 0.0
	if _target != null:
		_target.tree_exiting.connect(_on_target_gone)
		if _target_health != null:
			_target_health.died.connect(_on_target_gone)
	target_changed.emit(_target)


func _disconnect_target() -> void:
	if _target != null and is_instance_valid(_target) \
			and _target.tree_exiting.is_connected(_on_target_gone):
		_target.tree_exiting.disconnect(_on_target_gone)
	if _target_health != null and is_instance_valid(_target_health) \
			and _target_health.died.is_connected(_on_target_gone):
		_target_health.died.disconnect(_on_target_gone)


## Dead, or leaving the scene: let go while it is still a valid object.
func _on_target_gone() -> void:
	release()


func _refresh_candidates() -> void:
	_refresh_remaining = CANDIDATE_REFRESH_INTERVAL
	_refreshes += 1
	_candidates.clear()
	if not is_inside_tree():
		return
	for group in _groups:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D and not _candidates.has(node):
				_candidates.append(node)


func _health_of(body: Node3D) -> HealthComponent:
	if body == null or not is_instance_valid(body):
		return null
	return body.get(HEALTH_PROPERTY) as HealthComponent
