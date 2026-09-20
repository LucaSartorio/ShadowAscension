class_name BossStats
extends Resource

## Body tuning for a boss archetype. Instances live under
## `resources/enemies/bosses/` as `.tres`. The attack set is separate —
## see BossAttack.
##
## A definition, not runtime state: the boss copies these into its own fields on
## _ready(), so the shared asset is never written to.

@export_group("Rewards")
## XP granted for killing the boss.
@export var xp_reward: int = 200

@export_group("Health")
@export var max_health: float = 600.0

@export_group("Movement")
@export var movement_speed: float = 3.2
@export var acceleration: float = 10.0
@export var rotation_speed: float = 5.0
@export var gravity: float = 20.0

@export_group("Spacing")
## The distance the boss tries to hold when it is not committed to an attack.
@export var preferred_combat_distance: float = 2.2
@export var minimum_combat_distance: float = 1.4
## Beyond preferred + this, the boss closes in rather than repositioning.
@export var chase_band: float = 1.0
@export var navigation_radius: float = 0.8

@export_group("Decision")
## An attack cannot start while the player is outside this cone.
@export var max_attack_facing_angle: float = 30.0
## Hard ceiling on how often the same attack may run back to back.
@export var max_consecutive_repeats: int = 2
@export var reposition_timeout: float = 1.4
@export var reposition_speed_fraction: float = 0.85
@export var target_update_interval: float = 0.2

@export_group("Phase 2")
## The boss drops into its phase transition when health falls to this fraction
## of maximum. It happens once per life.
@export_range(0.0, 1.0) var phase_2_health_fraction: float = 0.5
## Harmless, committed beat between the two phases.
@export var phase_transition_duration: float = 1.5
@export var phase_2_movement_speed: float = 3.8
## Shorter than phase 1's, so the boss spends less time circling.
@export var phase_2_reposition_timeout: float = 0.9

@export_group("Encounter")
## Brief wind-up when the fight starts. No cutscene, just a readable beat.
@export var intro_duration: float = 0.8
@export var death_topple_duration: float = 1.2
