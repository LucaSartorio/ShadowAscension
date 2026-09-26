class_name EliteModifierData
extends Resource

## CONFIGURATION of what makes an enemy elite (M12.7): multipliers on its
## archetype's own numbers, and nothing else — no base value is repeated here, so
## an elite melee, an elite tank and an elite support are each their archetype,
## scaled. Assigned per enemy (`BasicEnemy.elite_profile`) by whatever places it;
## shared by every elite that uses it, and never written.
##
## Each effective value is derived here, once, by the getter below it — the one
## pipeline — when the enemy seeds its runtime copies on _ready():
##
##     base (EnemyData) -> x this profile -> the enemy's runtime copy
##                                         -> (damage only) a support's buff, at attack time
##
## The defaults are 1.0: a profile that changes nothing, which is what an enemy
## with no profile — a normal one — is scaled by. An elite profile's real numbers
## are the ones in its `.tres`.
##
## Out of scope on purpose: the telegraph, active and recovery of an attack (the
## archetype's readability is never shortened), the reach and the distances it
## keeps, the hitbox, its heal and buff if it is a support. Only what is listed.

## No multiplier goes below this or above MAX_MULTIPLIER, whatever a file says: a
## zero health or a negative damage multiplier would not make an elite.
const MIN_MULTIPLIER: float = 0.1
const MAX_MULTIPLIER: float = 10.0

@export_group("Body")
## Scales the archetype's max_health. Its health starts full at the result.
@export_range(0.1, 10.0, 0.01) var health_multiplier: float = 1.0
## Scales the archetype's movement_speed (and so its navigation's max speed).
## Keep it moderate: an elite assassin should not outrun the player.
@export_range(0.1, 10.0, 0.01) var move_speed_multiplier: float = 1.0

@export_group("Offence")
## Scales the archetype's attack_damage — the base every one of its attacks
## scales, so each attack, swing or shot, is raised by the same factor, once.
@export_range(0.1, 10.0, 0.01) var damage_multiplier: float = 1.0
## Scales the archetype's attack_cooldown, the gap between two attacks: below 1
## is shorter — 0.85 is 15% shorter. The attack itself is timed as ever.
@export_range(0.1, 10.0, 0.01) var cooldown_multiplier: float = 1.0

@export_group("Resistance")
## Scales the archetype's stagger_resistance: above 1, harder to interrupt.
@export_range(0.1, 10.0, 0.01) var stagger_resistance_multiplier: float = 1.0
## Scales the archetype's knockback_multiplier — the share of a push it takes:
## below 1 it is pushed less — 0.7 keeps 70% of it. Never 0 (immovable).
@export_range(0.1, 10.0, 0.01) var knockback_taken_multiplier: float = 1.0

@export_group("Reward")
## Scales the archetype's xp_reward, rounded to a whole number. Who collects it,
## and a shadow's 70/30 share of it, is PlayerProgression's, on this total.
@export_range(0.1, 10.0, 0.01) var xp_reward_multiplier: float = 1.0


## Whether every multiplier is a usable number: positive and finite. The getters
## clamp anyway; this is for saying so.
func is_valid() -> bool:
	for value in [health_multiplier, move_speed_multiplier, damage_multiplier, cooldown_multiplier,
			stagger_resistance_multiplier, knockback_taken_multiplier, xp_reward_multiplier]:
		var multiplier: float = value
		if not is_finite(multiplier) or multiplier <= 0.0:
			return false
	return true


func effective_max_health(base: float) -> float:
	return base * _clamped(health_multiplier)


func effective_movement_speed(base: float) -> float:
	return base * _clamped(move_speed_multiplier)


func effective_attack_damage(base: float) -> float:
	return base * _clamped(damage_multiplier)


func effective_attack_cooldown(base: float) -> float:
	return base * _clamped(cooldown_multiplier)


func effective_stagger_resistance(base: float) -> float:
	return base * _clamped(stagger_resistance_multiplier)


func effective_knockback_multiplier(base: float) -> float:
	return base * _clamped(knockback_taken_multiplier)


func effective_xp_reward(base: int) -> int:
	return roundi(base * _clamped(xp_reward_multiplier))


func _clamped(multiplier: float) -> float:
	if not is_finite(multiplier):
		return 1.0
	return clampf(multiplier, MIN_MULTIPLIER, MAX_MULTIPLIER)
