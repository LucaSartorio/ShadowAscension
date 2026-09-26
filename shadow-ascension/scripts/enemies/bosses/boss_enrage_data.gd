class_name BossEnrageData
extends Resource

## A boss's enrage (M12.9): the last escalation of its fight — not a phase, not
## a second framework. A sub-resource of its BossData (`enrage`); null is a boss
## that never enrages.
##
## Once its health share has fallen to `health_threshold` — and only once every
## phase due has begun, so a blow through a phase's threshold and this one plays
## the phase's transition first — the boss plays a short beat and is enraged for
## the rest of its life: once, never undone, not by a heal, not by anything. A
## killing blow is a death, never an enrage.
##
## Pure configuration: whether the boss has enraged is its BossPhaseController's.

## The share of its maximum health at or below which the boss enrages
## (current / max). Below its last phase's threshold.
@export_range(0.0, 1.0, 0.01) var health_threshold: float = 0.25
## Seconds of the beat before the enrage takes hold — no attack, no movement, no
## stagger; still hittable.
@export_range(0.0, 10.0, 0.05, "or_greater") var transition_duration: float = 1.0

@export_group("Modifiers")
## Each scales on top of the phase's own (base -> phase -> enrage). Kept to the
## two that read as aggression: it moves a little faster and attacks a little
## more often — no damage spike, no shorter telegraph.
@export_range(0.1, 5.0, 0.01) var movement_speed_multiplier: float = 1.1
@export_range(0.1, 5.0, 0.01) var cooldown_multiplier: float = 0.85

@export_group("Look")
## PLACEHOLDER until M14: the body's resting colour once enraged, and the glow
## it keeps.
@export var body_color: Color = Color(0.95, 0.35, 0.1)
@export var emission_color: Color = Color(1.0, 0.3, 0.05)
@export_range(0.0, 8.0, 0.05) var emission_energy: float = 1.2


## What is wrong with this enrage, if anything.
func get_problems() -> PackedStringArray:
	var problems: PackedStringArray = []
	if health_threshold <= 0.0 or health_threshold >= 1.0:
		problems.append("the enrage threshold is not between 0 and 1")
	return problems
