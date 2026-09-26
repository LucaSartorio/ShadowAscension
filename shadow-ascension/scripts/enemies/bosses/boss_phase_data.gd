class_name BossPhaseData
extends Resource

## One phase of a boss fight (M12.8): when it begins, what the boss fights with
## in it, and how the fight changes gear. Listed in order in its BossData
## (`phases`); the first is where every encounter starts.
##
## Phases only ever advance: the boss enters a later phase once its health has
## fallen to that phase's threshold, and never goes back — not on a heal, not on
## anything. Pure configuration: which phase the boss is in is the boss's.

## Names the phase wherever it is reported — never an animation's name.
@export var id: StringName = &""
## The share of its maximum health at or below which the boss enters this phase
## (current / max). The first phase's is 1.0: it is where the fight starts.
@export_range(0.0, 1.0, 0.01) var health_threshold: float = 1.0
## Seconds of the beat before this phase begins — no attack, no movement, still
## hittable. 0 for the first phase.
@export_range(0.0, 10.0, 0.05, "or_greater") var transition_duration: float = 0.0
## What the boss chooses from in this phase. An attack may be in several phases.
@export var attacks: Array[BossAttack] = []

@export_group("Modifiers")
## Scales the boss's movement speed (and its navigation's) in this phase.
@export_range(0.1, 5.0, 0.01) var movement_speed_multiplier: float = 1.0
## Scales how long it may spend repositioning before it decides again: below 1
## it circles less.
@export_range(0.1, 5.0, 0.01) var reposition_timeout_multiplier: float = 1.0
## Scales every attack's windup, recovery and cooldown in this phase — the
## fight's rhythm — never its damage, its reach or its hit window. Below 1 is
## quicker: 0.8 is 20% quicker.
@export_range(0.1, 5.0, 0.01) var tempo_multiplier: float = 1.0

@export_group("Look")
## PLACEHOLDER: the body's resting colour in this phase. Fully transparent keeps
## the body's own.
@export var body_color: Color = Color(0, 0, 0, 0)


## What is wrong with this phase, if anything.
func get_problems() -> PackedStringArray:
	var problems: PackedStringArray = []
	if id == &"":
		problems.append("a phase with no id")
	if attacks.is_empty():
		problems.append("phase '%s' has no attacks" % id)
	for attack in attacks:
		if attack == null:
			problems.append("phase '%s' lists an empty attack" % id)
			continue
		problems.append_array(attack.get_problems())
	return problems
