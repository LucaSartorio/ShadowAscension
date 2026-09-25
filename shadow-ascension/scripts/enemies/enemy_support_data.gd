class_name EnemySupportData
extends Resource

## CONFIGURATION of what a support archetype does for its allies (M12.6): whom it
## notices, how far it reaches, and its two support actions — the heal and the
## damage buff. Referenced from its EnemyData (`support`), so the archetype's
## numbers stay in one asset; null on every archetype that supports nobody.
## Read by EnemySupport, which copies it once; never written.
##
## Each action is an AttackData — its windup is the cast, its active the moment
## the effect lands, its recovery the commitment after — run through the same
## lifecycle as any enemy attack. What the effect *is* lives here.

@export_group("Allies")
## The physics layers its allies stand on — the enemies' bodies. Only an enemy on
## the AI foundation (one with an EnemyAttack) counts: the boss runs its own AI.
@export_flags_3d_physics var ally_mask: int = 4
## An ally is noticed, and may be chosen, within this distance, flat.
@export_range(0.0, 50.0, 0.5, "or_greater") var ally_detection_range: float = 14.0
## The furthest a support action reaches, flat: out of it — or out of sight — the
## support walks toward its ally before it casts.
@export_range(0.0, 50.0, 0.5, "or_greater") var support_range: float = 9.0
## A cast under way is dropped only when its ally gets this far beyond
## support_range: a step out of reach does not cancel it.
@export_range(0.0, 20.0, 0.1, "or_greater") var cast_break_margin: float = 3.0
## Seconds between two looks around for allies — a physics query, never a scan of
## the scene tree — and between two choices of whom to support.
@export_range(0.05, 5.0, 0.05, "or_greater") var ally_scan_interval: float = 0.5
## At most this many bodies are looked at in one look around.
@export_range(1, 64, 1, "or_greater") var max_allies: int = 16
## Seconds it may spend walking toward the ally it chose without being able to
## cast: past this it gives up on it, and that action waits out its cooldown.
@export_range(0.0, 20.0, 0.1, "or_greater") var approach_timeout: float = 4.0

@export_group("Heal")
## The heal's timing — the cast (windup), the effect (active), the recovery.
## Null: this archetype never heals.
@export var heal_action: AttackData = null
## An ally is healed only below this share of its maximum health.
@export_range(0.0, 1.0, 0.01) var heal_threshold: float = 0.7
## A heal restores this share of the healed ally's own maximum health — a tank's
## heal is bigger than an assassin's — never past its maximum.
@export_range(0.0, 1.0, 0.01) var heal_fraction: float = 0.25
## Seconds after a heal lands — or a cast of it is interrupted — before the next.
@export_range(0.0, 60.0, 0.1, "or_greater") var heal_cooldown: float = 6.0
## The cast's placeholder colour: the support's telegraph and the marker on its ally.
@export var heal_color: Color = Color(0.3, 1.0, 0.45)

@export_group("Buff")
## The buff's timing, as the heal's. Null: this archetype never buffs.
@export var buff_action: AttackData = null
## The ally's attack damage is raised by this share while the buff lasts: 0.2 is
## +20%. One buff at a time on an ally — a second is refused, never stacked.
@export_range(0.0, 2.0, 0.01, "or_greater") var buff_damage_bonus: float = 0.2
## Seconds the buff lasts; then the ally's damage is its own again.
@export_range(0.0, 60.0, 0.1, "or_greater") var buff_duration: float = 6.0
## Seconds after a buff lands — or a cast of it is interrupted — before the next.
@export_range(0.0, 60.0, 0.1, "or_greater") var buff_cooldown: float = 10.0
## The cast's placeholder colour, and the glow a buffed ally wears.
@export var buff_color: Color = Color(1.0, 0.55, 0.15)
