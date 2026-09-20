class_name BossAttack
extends Resource

## One boss attack: its timings, its reach, its cooldown and how it telegraphs.
## Instances live under `resources/enemies/bosses/` as `.tres`.
##
## Pure data. The boss reads it; nothing here touches the scene tree.

## How the wind-up reads without real animation. Each shape is visually distinct
## so the three attacks can be told apart at a glance.
enum Telegraph { LEAN, SPIN, COMPRESS }

@export var attack_name: String = "Attack"
## Node name under the boss's AttackOrigins that this attack activates.
@export var hitbox_name: StringName = &"QuickStrikeHitbox"

@export_group("Damage and timing")
@export var damage: float = 20.0
@export var startup: float = 0.25
@export var active: float = 0.12
@export var recovery: float = 0.45
@export var cooldown: float = 1.0

@export_group("Range")
## The boss will not choose this attack outside this band.
@export var min_range: float = 0.0
@export var max_range: float = 2.6

@export_group("Telegraph")
@export var telegraph: Telegraph = Telegraph.LEAN
@export var telegraph_color: Color = Color(1.0, 0.8, 0.25)
## Fraction of rotation_speed usable during STARTUP. 0 means fully committed the
## moment the wind-up begins.
@export_range(0.0, 1.0) var facing_correction_fraction: float = 0.35
