class_name HitReaction
extends RefCounted

## The hit-reaction rules (M11.6), in one place for everything that reacts to a
## hit: an enemy (BasicEnemy) and a boss (DungeonBoss, M12.8). What a body does
## with the answer — a stagger state, a push it plays out — stays its own.
##
## Stateless, like DamageModel. Not damage: a critical never changes these.


## Whether `hit` breaks through a `resistance`: a stagger power, and at least as
## much as the resistance. Per hit, never accumulated. Whether the body may be
## staggered right now — already staggered, or in its immunity — is the body's.
static func breaks_through(hit: DamageInfo, resistance: float) -> bool:
	return hit.stagger_power > 0.0 and hit.stagger_power >= resistance


## The push `hit` gives a body that keeps `multiplier` of it: along the hit's
## flat direction, at its knockback force times the multiplier. Zero for no push,
## no direction, or a multiplier of 0 (immovable).
static func push_velocity(hit: DamageInfo, multiplier: float) -> Vector3:
	var speed: float = hit.knockback_force * multiplier
	if speed <= 0.0 or hit.direction == Vector3.ZERO:
		return Vector3.ZERO
	return Vector3(hit.direction.x, 0.0, hit.direction.z).normalized() * speed
