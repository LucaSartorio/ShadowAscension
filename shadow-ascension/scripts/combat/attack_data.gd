class_name AttackData
extends Resource

## One attack as data: how long each phase lasts, how hard it hits relative to
## its owner's base damage, and when it lets the next attack or a dodge in.
##
##     | windup | active |      recovery       |
##              ^ hitbox opens                  ^ the attack is over: the queued
##                       ^ hitbox closes          next attack starts, or the chain ends
##                              [ combo window ]
##
## The combat controller runs this timeline. An animation only represents it:
## retiming one can never retune combat. Pure configuration, shared by every
## player: nothing here changes in play, and nothing of a running attack — its
## timers, its place in the chain, whom it hit — is kept here.

## Names the attack wherever it is reported: every hit it lands carries it.
@export var id: StringName = &""
## What the presentation shows for it, by name. Combat never reads it; the
## player resolves it — to a placeholder pose now, to a clip at M14 — so a new
## model or animation set never touches this data.
@export var animation: StringName = &""
## Scales the owner's base damage. The attack holds no damage of its own, so
## retuning the character's base moves every attack with it.
@export var damage_multiplier: float = 1.0

@export_group("Timing")
## Seconds before the hitbox opens.
@export var windup: float = 0.15
## Seconds the hitbox stays open.
@export var active: float = 0.15
## Seconds after it closes before the owner is free again.
@export var recovery: float = 0.25

@export_group("Windows")
## The combo window: the stretch of recovery, as fractions of it, in which a
## press queues the next attack of the chain. That attack starts when this one is
## over; with nothing queued by the end of the window, the chain ends with this
## attack. A press shortly before the window opens is held by the input buffer.
## Never read on the last attack of a chain, which has no next.
@export_range(0.0, 1.0) var combo_window_start: float = 0.0
@export_range(0.0, 1.0) var combo_window_end: float = 1.0
## How far into recovery a dodge may cancel what is left of it, as a fraction
## of it: 0.0 at once, 1.0 never before it ends. Windup and active always commit.
@export_range(0.0, 1.0) var dodge_cancel_recovery_fraction: float = 0.0
## Scales the owner's movement speed while this attack runs; 1.0 moves as freely
## as out of combat.
@export var movement_multiplier: float = 1.0

@export_group("Impact")
## How hard a hit of this attack tries to interrupt its target: it staggers a
## target whose resistance is no higher. Independent of the push below — either
## can be 0 without the other.
@export var stagger_power: float = 0.0
## How fast a hit of this attack pushes its target away, in m/s along the hit's
## direction, before the target's own multiplier.
@export var knockback_force: float = 0.0

@export_group("Feedback")
## What a hit of this attack feels like, when it counts — presentation only:
## none of it changes the damage, the critical, the stagger, the push or any
## timing. Played by PlayerCombatFeedback, which adds a critical's bonus, applies
## the accessibility scales and clamps every value; 0 plays nothing.
##
## Seconds the whole game holds on the hit (the hit stop). One per swing,
## however many targets it hits.
@export var hit_stop_duration: float = 0.0
## How far the camera is thrown on the hit, in metres, and how long the shake
## takes to settle, in seconds.
@export var camera_shake_strength: float = 0.0
@export var camera_shake_duration: float = 0.0

@export_group("Debug")
## Colour of the hitbox's debug mesh while it is open.
@export var debug_color: Color = Color(1, 0.3, 0.3, 0.35)
