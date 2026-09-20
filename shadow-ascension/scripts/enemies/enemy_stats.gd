class_name EnemyStats
extends Resource

## Tuning definition for one enemy archetype. Instances live under
## `resources/enemies/` as `.tres`.
##
## This is a definition, not runtime state: the enemy copies these values into
## its own fields on `_ready()`, so per-instance changes (debug tweaks, future
## buffs) never write back into the shared asset.

@export_group("Health")
@export var max_health: float = 100.0

@export_group("Movement")
@export var movement_speed: float = 3.8
@export var acceleration: float = 12.0
@export var rotation_speed: float = 7.0
@export var gravity: float = 20.0

@export_group("Perception")
@export var detection_range: float = 10.0
@export var lose_target_range: float = 14.0
## Grace period before a target outside lose_target_range is dropped, so a
## momentary distance spike does not end the fight.
@export var lose_target_delay: float = 1.0
@export var eye_height: float = 1.2
## Physics layers that block line of sight (world geometry only).
@export_flags_3d_physics var line_of_sight_mask: int = 1

@export_group("Combat Spacing")
@export var attack_range: float = 1.8
@export var preferred_combat_distance: float = 1.6
@export var minimum_combat_distance: float = 1.15
## Drives NavigationAgent3D.radius — the personal space honored by avoidance.
@export var enemy_spacing_radius: float = 0.8

@export_group("Attack")
@export var attack_damage: float = 15.0
@export var attack_startup: float = 0.35
@export var attack_active: float = 0.15
@export var attack_recovery: float = 0.65
@export var attack_cooldown: float = 0.4
## An attack cannot start while the player is outside this cone.
@export var max_attack_facing_angle: float = 25.0
## Fraction of rotation_speed usable during STARTUP. Below 1.0 the swing can be
## sidestepped instead of tracking the player perfectly.
@export_range(0.0, 1.0) var attack_startup_turn_fraction: float = 0.3

@export_group("Reposition")
@export var reposition_timeout: float = 1.5
## Blocks re-entry to REPOSITION after a timeout, preventing CHASE/REPOSITION ping-pong.
@export var reposition_cooldown: float = 0.6
@export var reposition_speed_fraction: float = 0.8
@export var reposition_arrive_tolerance: float = 0.35

@export_group("Telegraph")
@export var telegraph_color: Color = Color(1.0, 0.85, 0.2)
@export var active_color: Color = Color(1.0, 0.25, 0.15)
@export var startup_scale: Vector3 = Vector3(0.88, 1.22, 0.88)
@export var active_scale: Vector3 = Vector3(1.18, 0.9, 1.18)

@export_group("Navigation")
@export var target_update_interval: float = 0.2
