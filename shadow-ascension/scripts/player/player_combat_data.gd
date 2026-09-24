class_name PlayerCombatData
extends Resource

## The player's combat configuration: its base damage, its attacks, and the
## windows that decide what it may do and when. Shared and never written in
## play — how a fight is going (the state, the timers, the combo position) lives
## on PlayerCombat.
##
## How the dodge MOVES is not here: its speed scales with AGI beside the walking
## speed, and both belong to the player's movement.

## What an attack with a damage multiplier of 1.0 deals before STR and the
## weapon. Every attack scales it; none carries a damage number of its own.
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
