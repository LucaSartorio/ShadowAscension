class_name PlayerTargeting
extends Node

## The player's target lock (M11.8): which enemy the player is locked onto, if
## any — the one owner of that answer. Everything else asks: the player turns
## toward it and aims its attacks at it, the indicator shows it, nothing keeps
## a copy.
##
## Unlocked is `_target == null`, and nothing else: there is no flag beside the
## reference to disagree with it.
##
## What can be locked onto is a living RoomCombatant — an enemy or the boss —
## within acquisition_range, with the world not in the way. Shadows, the player
## and anything else on the enemy layer are not RoomCombatants and never count.
## Candidates are found by one physics query around the player, run only when
## the player locks on or switches; while a lock holds, only the held target is
## checked, once a physics tick, and its death arrives as a signal.
##
## The lock ends when the player lets go, the target dies or leaves the scene
## (both heard as signals, so it ends in the same call), it goes past
## lose_range, or the player dies. It never jumps to another target on its own.

## The locked target changed: a new one, or null when the lock ended.
signal target_changed(target: RoomCombatant)

## Directions for switch_target(), as the camera sees them.
const LEFT: int = -1
const RIGHT: int = 1
const MIN_DIRECTION_LENGTH_SQUARED: float = 0.0001
## Below this (radians), two targets stand on the same bearing and neither is
## to the other's left or right.
const MIN_SWITCH_ANGLE: float = 0.001

@export var data: PlayerTargetingData

@export_group("DEBUG")
## DEBUG ONLY. Off by default. Prints every lock, switch and release: the target,
## its distance and bearing, and how many candidates the search found.
@export var debug_log_enabled: bool = false

# Handed over by the player in setup().
var _player: Player = null
var _camera_rig: Node3D = null
var _health: HealthComponent = null

var _target: RoomCombatant = null
## Built once: the search around the player, moved to it each time it runs.
var _query: PhysicsShapeQueryParameters3D = null
## How many searches have run — a lock or a switch each, never a frame.
var _searches: int = 0


func _ready() -> void:
	if data == null:
		push_warning("%s has no PlayerTargetingData; using the class defaults." % name)
		data = PlayerTargetingData.new()
	set_physics_process(false)


## Called once by the player with the parts of itself this reads: its body, the
## camera that decides what is "in front", and its health, whose death ends a
## lock.
func setup(player: Player, camera_rig: Node3D, health: HealthComponent) -> void:
	_player = player
	_camera_rig = camera_rig
	_health = health
	var reach: SphereShape3D = SphereShape3D.new()
	reach.radius = data.acquisition_range
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = reach
	_query.collision_mask = data.target_body_mask
	_query.collide_with_areas = false
	_query.exclude = [player.get_rid()]
	if health != null:
		health.died.connect(unlock)


## Leaving the tree takes the lock with it, quietly: whatever listened to it is
## leaving with this scene too.
func _exit_tree() -> void:
	_release_target()
	_target = null


# --- intents ---------------------------------------------------------------------

## The lock button: lets go of a held target, or locks onto the best one. True
## when a target is held afterwards.
func toggle_lock() -> bool:
	if is_locked():
		unlock()
		return false
	return lock_on()


## Locks onto the best target in reach, if there is one; true when it did. A
## dead player locks onto nothing.
func lock_on() -> bool:
	if _health != null and _health.is_dead:
		return false
	var candidates: Array[RoomCombatant] = _find_candidates()
	var best: RoomCombatant = _best_of(candidates)
	if best == null:
		_log("nothing to lock onto")
		return false
	_set_target(best, "locked from %d candidates" % candidates.size())
	return true


func unlock() -> void:
	_set_target(null, "released")


## Moves the lock to the nearest target on the LEFT or RIGHT of the held one, as
## the camera sees them. With nothing on that side the lock stays where it is:
## no wrapping round. True when the lock moved.
func switch_target(direction: int) -> bool:
	if not is_locked():
		return false
	var candidates: Array[RoomCombatant] = _find_candidates()
	var next: RoomCombatant = _neighbour(direction, candidates)
	if next == null:
		_log("nothing to the %s" % ("right" if direction > 0 else "left"))
		return false
	_set_target(next, "switched %s" % ("right" if direction > 0 else "left"))
	return true


# --- queries ------------------------------------------------------------------------

func get_target() -> RoomCombatant:
	return _target


func is_locked() -> bool:
	return _target != null


## From the player to the target, flat and of length 1; zero while unlocked.
func direction_to_target() -> Vector3:
	if _target == null or _player == null:
		return Vector3.ZERO
	var to: Vector3 = _flat(_target.global_position - _player.global_position)
	if to.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return Vector3.ZERO
	return to.normalized()


## Whether `target` may be held from where the player stands: alive, in the
## scene, and no further than `within`, flat.
func is_valid_target(target: RoomCombatant, within: float) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if target.has_died() or _player == null:
		return false
	return _flat(target.global_position - _player.global_position).length() <= within


## What a lock or a switch would choose from right now. Runs the search, so it
## is for a lock, a switch or a test — never a frame.
func get_candidates() -> Array[RoomCombatant]:
	return _find_candidates()


func get_search_count() -> int:
	return _searches


# --- the held target ---------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if _target != null and not is_valid_target(_target, data.lose_range):
		_set_target(null, "lost: dead, gone or past %.0f m" % data.lose_range)


func _set_target(target: RoomCombatant, why: String) -> void:
	# By identity: a freed object compares equal to null, and a lock must never
	# mistake a target that is gone for "already unlocked" and skip the signal.
	if is_same(target, _target):
		return
	_release_target()
	_target = target
	if _target != null:
		_target.enemy_died.connect(_on_target_died)
		_target.tree_exiting.connect(_on_target_leaving)
	set_physics_process(_target != null)
	_log(why)
	target_changed.emit(_target)


func _release_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _target.enemy_died.is_connected(_on_target_died):
		_target.enemy_died.disconnect(_on_target_died)
	if _target.tree_exiting.is_connected(_on_target_leaving):
		_target.tree_exiting.disconnect(_on_target_leaving)


func _on_target_died(_combatant: RoomCombatant) -> void:
	_set_target(null, "target died")


## Freed or taken out of the scene: let go while it is still a valid object, so
## nothing is ever left holding a reference to something gone.
func _on_target_leaving() -> void:
	_set_target(null, "target left the scene")


# --- choosing ---------------------------------------------------------------------

## Every RoomCombatant around the player that may be locked onto: alive, within
## acquisition_range, and in view.
func _find_candidates() -> Array[RoomCombatant]:
	var found: Array[RoomCombatant] = []
	if _player == null or _query == null or not _player.is_inside_tree():
		return found
	_searches += 1
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	_query.transform = Transform3D(Basis.IDENTITY, _player.global_position)
	for hit in space.intersect_shape(_query, data.max_candidates):
		var candidate: RoomCombatant = hit.get("collider") as RoomCombatant
		if candidate == null or found.has(candidate):
			continue
		if is_valid_target(candidate, data.acquisition_range) and _in_view(space, candidate):
			found.append(candidate)
	return found


## Lowest score wins: degrees off the camera's view, plus distance_weight for
## every metre. What is in front of the camera comes first; distance breaks the
## tie, and a target behind is chosen only when nothing is in front.
func _best_of(candidates: Array[RoomCombatant]) -> RoomCombatant:
	var best: RoomCombatant = null
	var best_score: float = INF
	for candidate in candidates:
		var score: float = _score(candidate)
		if score < best_score:
			best = candidate
			best_score = score
	return best


func _score(target: RoomCombatant) -> float:
	var distance: float = _flat(target.global_position - _player.global_position).length()
	return rad_to_deg(absf(_bearing(target))) + distance * data.distance_weight


## The nearest target on the asked side of the held one, by bearing — the order
## the camera shows them in, not their order in any list.
func _neighbour(direction: int, candidates: Array[RoomCombatant]) -> RoomCombatant:
	var held: float = _bearing(_target)
	var best: RoomCombatant = null
	var best_gap: float = INF
	for candidate in candidates:
		if candidate == _target:
			continue
		var gap: float = wrapf(_bearing(candidate) - held, -PI, PI) * signf(direction)
		if gap > MIN_SWITCH_ANGLE and gap < best_gap:
			best = candidate
			best_gap = gap
	return best


## Where `target` stands off the camera's view, in radians, flat: 0 straight
## ahead, positive to the right, negative to the left, ±PI behind.
func _bearing(target: RoomCombatant) -> float:
	var forward: Vector3 = _camera_forward()
	var to: Vector3 = _flat(target.global_position - _player.global_position)
	if forward == Vector3.ZERO or to.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return 0.0
	return -forward.signed_angle_to(to.normalized(), Vector3.UP)


func _camera_forward() -> Vector3:
	if _camera_rig == null:
		return Vector3.ZERO
	var forward: Vector3 = _flat(-_camera_rig.global_basis.z)
	if forward.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return Vector3.ZERO
	return forward.normalized()


## Nothing of the world between the player's eyes and the target's anchor. Only
## asked when a target is chosen: a held target behind a pillar stays held.
func _in_view(space: PhysicsDirectSpaceState3D, target: RoomCombatant) -> bool:
	var from: Vector3 = _player.global_position + Vector3.UP * data.eye_height
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from, target.get_target_point(), data.line_of_sight_mask)
	ray.exclude = [_player.get_rid(), target.get_rid()]
	return space.intersect_ray(ray).is_empty()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _log(why: String) -> void:
	if not debug_log_enabled:
		return
	if _target == null or not is_instance_valid(_target):
		print("[PlayerTargeting] %s  unlocked" % why)
		return
	print("[PlayerTargeting] %s  target=%s  distance=%.1fm  bearing=%.0f deg" % [
		why, _target.name, _flat(_target.global_position - _player.global_position).length(),
		rad_to_deg(_bearing(_target))])
