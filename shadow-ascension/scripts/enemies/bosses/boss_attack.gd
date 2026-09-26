class_name BossAttack
extends Resource

## One boss attack (M12.8): an AttackData — the same resource as every other
## attack in the game, for its id, its damage multiplier, its windup / active /
## recovery and its stagger and push — composed with what only a boss needs:
## which of its hitboxes it swings, the reach it is chosen from, its own cooldown
## and pick weight, how many swings it makes, and how its wind-up reads. Nothing
## here repeats a field of AttackData.
##
## A phase lists the attacks it offers (BossPhaseData.attacks); the same asset
## may be in several phases. Pure configuration: never written; the cooldown
## left, the swing under way and the history are BossCombat's.

## How the wind-up reads without real animation. Each shape is a different
## channel, so attacks can be told apart at a glance. RAISE (M12.9): it rears
## up and towers — the heaviest blow's.
enum Telegraph { LEAN, SPIN, COMPRESS, RECOIL, RAISE }

## Its id, timings, damage multiplier and impact. The boss's damage is its
## BossData.attack_damage scaled by this attack's damage_multiplier.
@export var attack: AttackData = null
## Node name under the boss's AttackOrigins that this attack swings.
@export var hitbox_name: StringName = &""

@export_group("Choice")
## The boss chooses this attack only with its target in this band, flat.
@export_range(0.0, 50.0, 0.05, "or_greater") var min_range: float = 0.0
@export_range(0.0, 50.0, 0.05, "or_greater") var max_range: float = 2.6
## Seconds, from the start of the attack, before this attack may be chosen again
## — its own, not shared with the others. Scaled by the boss's pace: its phase's
## cooldown multiplier, and its enrage's.
@export_range(0.0, 60.0, 0.05, "or_greater") var cooldown: float = 1.0
## Relative pick weight among the attacks valid at the moment of choosing: lower
## is rarer, never impossible while above 0.
@export_range(0.0, 100.0, 0.05, "or_greater") var weight: float = 1.0

@export_group("Multi-hit")
## Swings in one attack. Each swing re-opens the hitbox, which forgets whom the
## last one hit: one landing per target per swing.
@export_range(1, 10, 1) var hit_count: int = 1
## Seconds between two swings: committed, harmless.
@export_range(0.0, 5.0, 0.01, "or_greater") var delay_between_hits: float = 0.0
## Share of the boss's rotation speed usable in that gap: a nudge, never a snap
## onto a player who has already left.
@export_range(0.0, 1.0) var between_hits_facing_fraction: float = 0.0

@export_group("Telegraph")
@export var telegraph: Telegraph = Telegraph.LEAN
@export var telegraph_color: Color = Color(1.0, 0.8, 0.25)
## Share of the boss's rotation speed usable during the wind-up. 0: the attack
## is committed to where it was aimed the moment it begins.
@export_range(0.0, 1.0) var facing_correction_fraction: float = 0.35
## Optional: a node under the boss's AttackOrigins shown for as long as this
## attack winds up — where it will land, drawn on the ground (PLACEHOLDER until
## M14). Empty: none.
@export var telegraph_marker_name: StringName = &""


## What names the attack wherever it is reported: its AttackData's id.
func get_id() -> StringName:
	return attack.id if attack != null else &""


## What is wrong with this attack, if anything: an empty list is a usable attack.
func get_problems() -> PackedStringArray:
	var problems: PackedStringArray = []
	if attack == null:
		problems.append("an attack with no AttackData")
		return problems
	if hitbox_name == &"":
		problems.append("attack '%s' names no hitbox" % attack.id)
	if max_range < min_range:
		problems.append("attack '%s' has max_range below min_range" % attack.id)
	return problems
