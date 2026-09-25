class_name EnemyData
extends Resource

## CONFIGURATION for one enemy archetype: what that kind of enemy is, not how
## any one of them is doing. Instances live under `resources/enemies/` as `.tres`,
## one per archetype, and every enemy of that archetype shares the same asset.
##
## Configuration, never runtime state. BasicMeleeEnemy seeds its own fields from
## this on _ready() and works on those, so a per-instance change — a debug tweak,
## a test holding one enemy still, a future buff — never writes back into the
## asset its siblings are reading. Current health is the HealthComponent's, not
## this: `max_health` here is the archetype's ceiling and is never decremented.
##
## What does NOT belong here: current health or anything else that changes during
## a fight; AI state — the current state, the target, the cooldown and stagger
## left, the navigation — all of which is the enemy's own; placement (the
## approach angle and attack desync are set on each instance in its room); and
## what a kill drops or leaves behind, which the LootDropper and ShadowSource
## components on the enemy scene declare themselves.
##
## The defaults below are the template a new asset starts from in the editor, and
## what an enemy with no asset falls back to. An archetype's real numbers are the
## ones saved in its `.tres`.

@export_group("Rewards")
## XP granted for killing one of these. Who receives it, and how a shadow's kill
## is split, is PlayerProgression's decision rather than the enemy's.
@export_range(0, 10000, 1, "or_greater") var xp_reward: int = 25

@export_group("Health")
@export_range(1.0, 10000.0, 1.0, "or_greater") var max_health: float = 100.0

@export_group("Movement")
@export_range(0.0, 20.0, 0.1, "or_greater") var movement_speed: float = 3.8
@export_range(0.0, 100.0, 0.5, "or_greater") var acceleration: float = 12.0
@export_range(0.0, 30.0, 0.5, "or_greater") var rotation_speed: float = 7.0
@export var gravity: float = 20.0

@export_group("Perception")
## The groups whose members this archetype fights (M12.1). A candidate must also
## be alive (it carries a health component that is not dead). The basic enemy's
## is the player's alone: it has never fought a shadow.
@export var target_groups: Array[StringName] = [Player.GROUP]
## A target is acquired when it comes closer than this, flat.
@export_range(0.0, 50.0, 0.5, "or_greater") var detection_range: float = 10.0
@export_range(0.0, 50.0, 0.5, "or_greater") var lose_target_range: float = 14.0
## Grace period before a target outside lose_target_range is dropped, so a
## momentary distance spike does not end the fight.
@export_range(0.0, 10.0, 0.05, "or_greater") var lose_target_delay: float = 1.0
@export var eye_height: float = 1.2
## Physics layers that block line of sight (world geometry only).
@export_flags_3d_physics var line_of_sight_mask: int = 1
## Seconds between noticing a target and going after it (ALERT): the enemy
## stands and turns to face it. 0: noticed and chased in the same tick.
@export_range(0.0, 5.0, 0.05, "or_greater") var alert_duration: float = 0.0

@export_group("Combat Spacing")
@export_range(0.0, 10.0, 0.05, "or_greater") var attack_range: float = 1.8
@export_range(0.0, 10.0, 0.05, "or_greater") var preferred_combat_distance: float = 1.6
@export_range(0.0, 10.0, 0.05, "or_greater") var minimum_combat_distance: float = 1.15
## Drives NavigationAgent3D.radius — the personal space honored by avoidance.
@export_range(0.0, 5.0, 0.05, "or_greater") var enemy_spacing_radius: float = 0.8

@export_group("Attack")
@export_range(0.0, 1000.0, 0.5, "or_greater") var attack_damage: float = 15.0
@export_range(0.0, 5.0, 0.01, "or_greater") var attack_startup: float = 0.35
@export_range(0.0, 5.0, 0.01, "or_greater") var attack_active: float = 0.15
@export_range(0.0, 5.0, 0.01, "or_greater") var attack_recovery: float = 0.65
@export_range(0.0, 10.0, 0.01, "or_greater") var attack_cooldown: float = 0.4
## An attack cannot start while the player is outside this cone.
@export_range(0.0, 180.0, 1.0) var max_attack_facing_angle: float = 25.0
## Fraction of rotation_speed usable during STARTUP. Below 1.0 the swing can be
## sidestepped instead of tracking the player perfectly.
@export_range(0.0, 1.0) var attack_startup_turn_fraction: float = 0.3

@export_group("Hit Reactions")
## A hit whose stagger power is at least this staggers the enemy: its attack is
## cut off and it stands helpless for stagger_duration. Anything weaker is only
## a flinch. Per hit, not accumulated.
@export_range(0.0, 1000.0, 1.0, "or_greater") var stagger_resistance: float = 25.0
@export_range(0.0, 5.0, 0.01, "or_greater") var stagger_duration: float = 0.5
## After a stagger ends, no new one for this long — damage and knockback still
## land — so no chain of hits can hold the enemy helpless for ever.
@export_range(0.0, 10.0, 0.05, "or_greater") var stagger_immunity_time: float = 1.0
## Scales every push this enemy takes: 1.0 as the attack meant it, 0.0 immovable.
@export_range(0.0, 5.0, 0.05, "or_greater") var knockback_multiplier: float = 1.0
## How fast a push dies out, in m/s per second.
@export_range(0.1, 200.0, 0.5, "or_greater") var knockback_deceleration: float = 30.0

@export_group("Reposition")
@export_range(0.0, 10.0, 0.05, "or_greater") var reposition_timeout: float = 1.5
## Blocks re-entry to REPOSITION after a timeout, preventing CHASE/REPOSITION ping-pong.
@export_range(0.0, 10.0, 0.05, "or_greater") var reposition_cooldown: float = 0.6
@export_range(0.0, 1.0) var reposition_speed_fraction: float = 0.8
@export_range(0.0, 5.0, 0.05, "or_greater") var reposition_arrive_tolerance: float = 0.35

@export_group("Telegraph")
@export var telegraph_color: Color = Color(1.0, 0.85, 0.2)
@export var active_color: Color = Color(1.0, 0.25, 0.15)
@export var startup_scale: Vector3 = Vector3(0.88, 1.22, 0.88)
@export var active_scale: Vector3 = Vector3(1.18, 0.9, 1.18)

@export_group("Navigation")
@export_range(0.01, 2.0, 0.01, "or_greater") var target_update_interval: float = 0.2
