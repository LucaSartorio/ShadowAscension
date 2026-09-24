class_name PlayerCombatData
extends Resource

## The player's combat configuration: its base damage, its attacks, the windows
## that decide what it may do and when, and the stamina that pays for a dodge.
## Shared and never written in play — how a fight is going (the state, the
## timers, the combo position, the stamina left) lives on PlayerCombat.
##
## How the dodge MOVES is not here: its speed scales with AGI beside the walking
## speed, and both belong to the player's movement.

## What an attack with a damage multiplier of 1.0 deals before STR and the
## weapon. Every attack scales it; none carries a damage number of its own. The
## one source of the player's base damage.
@export var base_damage: float = 20.0
## The light combo, in order: Attack 1 -> Attack 2 -> Attack 3. Each is its own
## AttackData asset, so one can be retuned without touching the others or the
## controller. After the last, the chain is over.
@export var light_combo: Array[AttackData] = []
## The heavy attack: a chain of one — a single, slower, harder attack with no
## follow-up. A chain like the light combo, so the controller runs it the same
## way and a longer heavy chain would be data, not code.
@export var heavy_combo: Array[AttackData] = []
## How long a press made shortly before an attack's combo window opens is
## remembered. It queues the next attack if the window opens in time, and is
## dropped otherwise — a press made earlier than this simply does nothing.
@export var input_buffer_time: float = 0.15

@export_group("Critical")
## The chance, 0.0 to 1.0 (0.1 = 10%), that one of the player's hits is critical.
## Rolled for each hit on its own — each target of a swing, each attack of a
## combo — never once for a swing or a chain.
@export_range(0.0, 1.0, 0.01) var critical_chance: float = 0.1
## A critical hit's damage is its raw damage times this: 1.5 is 150%.
@export_range(0.0, 10.0, 0.05, "or_greater") var critical_damage_multiplier: float = 1.5

@export_group("Dodge")
## The whole dodge, in seconds: the player is committed to it, and moved by it,
## from start to end.
##
##     | STARTUP | INVULNERABLE | RECOVERY |  -> free; cooldown before the next
##     0    invulnerability_start   invulnerability_end   dodge_duration
@export var dodge_duration: float = 0.35
## The i-frames, in seconds from the start of the dodge. Before them the dodge is
## already moving but still vulnerable; after them, until dodge_duration, it is
## vulnerable again.
@export var invulnerability_start: float = 0.06
@export var invulnerability_end: float = 0.24
## Seconds after a dodge ends before another may start. Attacks and walking are
## free in it; only a second dodge waits.
@export var dodge_cooldown: float = 0.15
## Stamina a dodge costs, paid in full when it starts. With less than this left,
## no dodge starts — never a shorter or cheaper one.
@export var dodge_stamina_cost: float = 25.0

@export_group("Stamina")
## The most stamina the player holds, and what every player starts with.
@export var max_stamina: float = 100.0
## Stamina recovered per second while regenerating.
@export var stamina_regen_rate: float = 40.0
## Seconds without spending before stamina starts to come back, counted from the
## end of the action that spent it — a dodge's own length never counts.
@export var stamina_regen_delay: float = 0.8
