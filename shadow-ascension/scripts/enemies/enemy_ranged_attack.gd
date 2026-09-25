class_name EnemyRangedAttack
extends EnemyAttack

## The ranged archetype's attack (M12.3): a telegraphed shot. The lifecycle is
## EnemyAttack's; what this adds is what ACTIVE is — the shot fired as it begins:
##
##     | TELEGRAPH (windup) | fire | ACTIVE (active: the release) | RECOVERY | -> cooldown
##       no projectile yet    once    the projectile flies on its own
##
## At the fire moment, and only then, the shot is decided:
##   - the target is the one the enemy holds (EnemyTargeting), still valid;
##   - it is aimed at the target's aim point *now* — the middle of its hurtbox —
##     with no prediction, and never more than the facing cone
##     (max_attack_facing_angle) off where the enemy faces: a target that has
##     got round it during the telegraph gets a shot along the edge of the cone;
##   - the line from the muzzle to that point is clear of the world (one ray):
##     a target gone behind a wall is not shot at;
##   - the point is within the projectile's reach (speed × lifetime).
## Any of those failing, nothing is fired: the attack is withheld — it ends
## there with no cooldown, and the enemy is free to move where it can shoot.
##
## Once fired, the projectile is the projectile's (Projectile): it flies straight,
## and nothing that happens to the enemy afterwards — a stagger, a death — calls
## it back. Before it is fired, anything that cuts the attack off (the enemy's
## ATTACK left for STAGGERED, DEAD or IDLE) means it never is: the state machine
## runs the attack only from ATTACK's update, so a stagger that lands first
## leaves no tick in which the telegraph could end in a shot.

## A projectile was fired, and is on its way.
signal fired(projectile: Projectile)

## Where the shot leaves from — a Marker3D under the enemy's VisualRoot, so it
## turns with its facing. Wired in the scene; M13 moves it to a hand, a staff or a
## bow without a line of code.
@export var projectile_spawn: Node3D = null

# Configuration, copied from the archetype's EnemyData by configure().
## What the fire-time ray checks against: the world.
var line_of_sight_mask: int = 0
## How far off the enemy's facing a shot may go, in degrees.
var max_aim_angle: float = 0.0

var _shots: int = 0


func configure(source: EnemyData) -> void:
	super.configure(source)
	line_of_sight_mask = source.line_of_sight_mask
	max_aim_angle = source.max_attack_facing_angle


func setup(enemy: CharacterBody3D, targeting: EnemyTargeting, visual_root: Node3D, mesh: MeshInstance3D) -> void:
	super.setup(enemy, targeting, visual_root, mesh)
	if projectile_spawn == null:
		push_warning("%s: its ranged attack has no projectile spawn point; it will never fire." % enemy.name)


## How many projectiles this enemy has fired.
func get_shot_count() -> int:
	return _shots


func _begin_active() -> bool:
	return _fire()


## Decides the shot and, if there is one, lets it loose: the projectile scene
## instanced into the scene the enemy stands in, placed at the muzzle and
## launched. True when a projectile was fired.
func _fire() -> bool:
	if projectile_spawn == null or _attack.projectile_scene == null or _targeting == null:
		return false
	var target: Node3D = _targeting.get_target()
	if not _targeting.is_valid_target(target):
		return false
	var origin: Vector3 = projectile_spawn.global_position
	var aim_point: Vector3 = _targeting.get_aim_point()
	if origin.distance_to(aim_point) > _attack.projectile_speed * _attack.projectile_lifetime:
		return false
	if not _is_clear(origin, aim_point, target):
		return false
	var world: Node = _enemy.get_parent()
	if world == null:
		return false
	var projectile: Projectile = _attack.projectile_scene.instantiate() as Projectile
	if projectile == null:
		push_warning("%s: %s's projectile scene is not a Projectile." % [_enemy.name, _attack.id])
		return false
	world.add_child(projectile)
	projectile.global_position = origin
	projectile.launch(_enemy, _aim_direction(origin, aim_point), _attack, attack_damage)
	_shots += 1
	fired.emit(projectile)
	return true


## Straight at `aim_point`, but no more than max_aim_angle off the facing,
## flat; the height of the aim kept.
func _aim_direction(origin: Vector3, aim_point: Vector3) -> Vector3:
	var to_aim: Vector3 = aim_point - origin
	var flat: Vector3 = Vector3(to_aim.x, 0.0, to_aim.z)
	var forward: Vector3 = -_visual_root.global_basis.z
	forward.y = 0.0
	if flat.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return to_aim.normalized() if to_aim.length_squared() > 0.0001 else forward.normalized()
	forward = forward.normalized()
	var angle: float = forward.signed_angle_to(flat.normalized(), Vector3.UP)
	var limit: float = deg_to_rad(max_aim_angle)
	if absf(angle) > limit:
		flat = forward.rotated(Vector3.UP, clampf(angle, -limit, limit)) * flat.length()
	return Vector3(flat.x, to_aim.y, flat.z).normalized()


## One ray, muzzle to aim point, against the world only: the shooter's and the
## target's own bodies are not walls.
func _is_clear(origin: Vector3, aim_point: Vector3, target: Node3D) -> bool:
	var space: PhysicsDirectSpaceState3D = _enemy.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		origin, aim_point, line_of_sight_mask)
	var exclude: Array[RID] = [_enemy.get_rid()]
	var target_body: CollisionObject3D = target as CollisionObject3D
	if target_body != null:
		exclude.append(target_body.get_rid())
	query.exclude = exclude
	return space.intersect_ray(query).is_empty()
