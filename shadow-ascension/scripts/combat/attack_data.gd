class_name AttackData
extends Resource

## One attack as data: how long each phase lasts, how hard it hits relative to
## its owner's base damage, and when it lets the next attack or a dodge in.
##
##     | windup | active | recovery |
##              ^ hitbox opens       ^ the attack is over
##                       ^ hitbox closes
##
## The combat controller runs this timeline. An animation only represents it:
## retiming one can never retune combat.

## Names the attack wherever it is reported: every hit it lands carries it, and
## it is what the presentation is asked to show.
@export var id: StringName = &""
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
## How far into recovery the next attack of the chain may begin, as a fraction
## of it: 1.0 only once this attack is over. A buffered press is spent the
## moment this opens, so a lower value cuts recovery short.
@export_range(0.0, 1.0) var combo_window_start: float = 1.0
## Seconds the chain keeps waiting after this attack is over. An attack started
## within them is the next of the combo; after them, the combo starts over. The
## last attack of a chain ends it, so there this is never read.
@export var combo_window_end: float = 0.8
## How far into recovery a dodge may cancel what is left of it, as a fraction
## of it: 0.0 at once, 1.0 never before it ends. Windup and active always commit.
@export_range(0.0, 1.0) var dodge_cancel_recovery_fraction: float = 0.0
## Scales the owner's movement speed while this attack runs; 1.0 moves as freely
## as out of combat.
@export var movement_multiplier: float = 1.0

@export_group("Placeholder presentation")
## How far the placeholder model rolls at the peak of the swing. Read by the
## presentation only — nothing that decides a hit — and replaced by a real
## animation at M14.
@export var visual_tilt_degrees: float = 8.0
## Colour of the hitbox's debug mesh while it is open.
@export var debug_color: Color = Color(1, 0.3, 0.3, 0.35)
