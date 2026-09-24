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
## The light attack chain, in order.
@export var light_combo: Array[AttackData] = []
## How long an attack pressed while another is still running is remembered. It
## is spent when the next attack of the chain may start, and dropped if that
## does not happen in time — a press too early simply does nothing.
@export var input_buffer_time: float = 0.4

@export_group("Dodge")
@export var dodge_duration: float = 0.35
## The invulnerable part of a dodge, in seconds from its start.
@export var invulnerability_start: float = 0.06
@export var invulnerability_end: float = 0.24
## Seconds after a dodge ends before another may start.
@export var dodge_cooldown: float = 0.15
