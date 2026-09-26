class_name BossData
extends Resource

## CONFIGURATION of one boss (M12.8, replacing M10's BossStats): what it is,
## how it moves and reacts, and its phases — each phase with the attacks it
## fights with. Instances live under `resources/enemies/bosses/` as `.tres`, and
## every boss of the kind shares one; the boss copies what it changes into its
## own fields on _ready(), so the asset is never written.
##
## Not an EnemyData, and not an elite: a boss is its own category, on its own
## state machine (DungeonBoss). It shares the parts every combatant shares — the
## health, the hit and its DamageInfo, the stagger and push rules (HitReaction),
## AttackData, the targeting (EnemyTargeting) — and nothing of an archetype.
##
## What does NOT belong here: its current health, phase, attack, cooldowns or
## target — all the boss's own, at runtime.

@export var id: StringName = &""
## Shown on its health bar.
@export var display_name: String = "Boss"

@export_group("Rewards")
## XP for killing it. Who collects, and a shadow's 70/30 share of a shadow's
## kill, is PlayerProgression's.
@export_range(0, 100000, 1, "or_greater") var xp_reward: int = 200

@export_group("Health")
## One pool for the whole fight: phases never refill or split it.
@export_range(1.0, 100000.0, 1.0, "or_greater") var max_health: float = 600.0

@export_group("Offence")
## The base every attack's damage_multiplier scales.
@export_range(0.0, 10000.0, 0.5, "or_greater") var attack_damage: float = 20.0

@export_group("Movement")
@export_range(0.0, 20.0, 0.1, "or_greater") var movement_speed: float = 3.2
@export_range(0.0, 100.0, 0.5, "or_greater") var acceleration: float = 10.0
@export_range(0.0, 30.0, 0.5, "or_greater") var rotation_speed: float = 5.0
@export var gravity: float = 20.0

@export_group("Perception")
## Whom it fights: the living members of these groups, the nearest within
## detection_range when the encounter starts — the player's, as before M12.8.
@export var target_groups: Array[StringName] = [Player.GROUP]
@export_range(0.0, 200.0, 0.5, "or_greater") var detection_range: float = 30.0

@export_group("Spacing")
## The distance it holds when not committed to an attack.
@export_range(0.0, 20.0, 0.05, "or_greater") var preferred_combat_distance: float = 2.2
@export_range(0.0, 20.0, 0.05, "or_greater") var minimum_combat_distance: float = 1.4
## Beyond preferred + this, it closes in rather than repositioning.
@export_range(0.0, 20.0, 0.05, "or_greater") var chase_band: float = 1.0
@export_range(0.0, 5.0, 0.05, "or_greater") var navigation_radius: float = 0.8

@export_group("Decision")
## An attack cannot start with the target outside this cone.
@export_range(0.0, 180.0, 1.0) var max_attack_facing_angle: float = 30.0
## The same attack at most this many times in a row.
@export_range(1, 10, 1, "or_greater") var max_consecutive_repeats: int = 2
@export_range(0.0, 10.0, 0.05, "or_greater") var reposition_timeout: float = 1.4
@export_range(0.0, 1.0) var reposition_speed_fraction: float = 0.85
@export_range(0.01, 2.0, 0.01, "or_greater") var target_update_interval: float = 0.2

@export_group("Hit Reactions")
## M11.6's rules, set high: a hit staggers the boss only with at least this much
## stagger power, and never again within stagger_immunity_time.
@export_range(0.0, 1000.0, 1.0, "or_greater") var stagger_resistance: float = 60.0
@export_range(0.0, 5.0, 0.01, "or_greater") var stagger_duration: float = 0.5
@export_range(0.0, 60.0, 0.05, "or_greater") var stagger_immunity_time: float = 5.0
## The share of a push it takes: small, so a heavy nudges it and never throws it
## across the arena.
@export_range(0.0, 5.0, 0.01, "or_greater") var knockback_multiplier: float = 0.1
@export_range(0.1, 200.0, 0.5, "or_greater") var knockback_deceleration: float = 60.0

@export_group("Phases")
## In order. The first is where the fight starts (threshold 1.0); each later one
## begins once health has fallen to its threshold — lower than the one before.
@export var phases: Array[BossPhaseData] = []

@export_group("Encounter")
## The readable beat when the fight starts. No cutscene.
@export_range(0.0, 10.0, 0.05, "or_greater") var intro_duration: float = 0.8
@export_range(0.0, 10.0, 0.05, "or_greater") var death_topple_duration: float = 1.2


## What is wrong with this boss's configuration, if anything: an empty list is a
## usable boss. The boss reports it as an error and stays inert rather than
## fighting half-configured.
func get_problems() -> PackedStringArray:
	var problems: PackedStringArray = []
	if max_health <= 0.0:
		problems.append("max_health is not positive")
	if phases.is_empty():
		problems.append("it has no phases")
		return problems
	var previous: float = 2.0
	for i in phases.size():
		var phase: BossPhaseData = phases[i]
		if phase == null:
			problems.append("phase %d is empty" % i)
			continue
		if i == 0 and phase.health_threshold < 1.0:
			problems.append("the first phase's threshold is not 1.0")
		if phase.health_threshold >= previous:
			problems.append("phase '%s' does not start below the one before it" % phase.id)
		previous = phase.health_threshold
		problems.append_array(phase.get_problems())
	return problems
