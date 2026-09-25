class_name DamageModel
extends RefCounted

## The damage model (M11.7): the rules every hit's damage follows, in one place
## and in this order.
##
##     raw    = base damage x attack multiplier        attack_damage(), once per swing,
##              then the attacker's own stats            by the attacker (the player's
##              (the player: weapon, STR, rounded;       weapon and STR: PlayerProgression;
##               an enemy: a support's buff)             an enemy's buff: buffed_damage())
##     crit   = roll_critical(chance)                  once per hit: each target of a
##                                                       swing rolls on its own
##     final  = raw, or round(raw x crit multiplier)   final_damage(), per hit
##     -- the target's own mitigation goes here, on the receiving side, when there is
##        one: Hurtbox.receive_hit(), after the i-frames and before
##        HealthComponent.take_damage(). There is none yet. --
##
## The attacker's side ends at `final`: a target never recomputes an attack
## multiplier or a critical. Stagger power and knockback are not damage and are
## never scaled here; a critical changes the damage and nothing else.
##
## Stateless: nothing here remembers a hit, and the random draws come from the
## caller's own generator.


## A swing's damage before the attacker's stats: its owner's base, scaled by
## the attack.
static func attack_damage(base_damage: float, attack_multiplier: float) -> float:
	return base_damage * attack_multiplier


## An enemy's base damage under a support's buff (M12.6): raised by `bonus`, a
## share — 0.2 is +20%. With no buff (0) it is the base, exactly: the buff never
## writes the base, so nothing of it outlives the buff.
static func buffed_damage(base_damage: float, bonus: float) -> float:
	return base_damage * (1.0 + maxf(bonus, 0.0))


## Whether one hit is critical. `chance` is 0.0 to 1.0 (0.1 = 10%), clamped: at
## 0 or below nothing is ever critical and at 1 or above everything is, without
## a draw, so both ends are exact.
static func roll_critical(chance: float, rng: RandomNumberGenerator) -> bool:
	if chance <= 0.0:
		return false
	if chance >= 1.0:
		return true
	return rng.randf() < chance


## What one hit takes: its raw damage, or for a critical the raw times the
## multiplier, rounded half away from zero — so every hit is a whole number, as
## a player swing has been since M6. A negative multiplier counts as 0.
static func final_damage(raw: float, critical: bool, critical_multiplier: float) -> float:
	if not critical:
		return raw
	return roundf(raw * maxf(critical_multiplier, 0.0))
