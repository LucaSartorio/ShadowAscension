class_name ProgressionStats
extends Resource

## Tuning definition for player progression: the XP curve, what a level awards,
## and the starting stat block. Instances live under `resources/characters/`.
##
## A definition, not runtime state: PlayerProgression copies these into its own
## fields on _ready(), so the shared asset is never written to.

@export_group("Level")
@export var starting_level: int = 1
## Technical ceiling only — not a game-design decision. It exists so the
## level-up loop is bounded and a huge reward cannot run away.
@export var max_level: int = 100
@export var stat_points_per_level: int = 5

@export_group("XP curve")
## XP needed for the first level. Every later level scales from this.
@export var base_xp_requirement: int = 100
@export var xp_growth_factor: float = 1.25

@export_group("Base stats")
@export var strength: int = 10
@export var agility: int = 10
@export var vitality: int = 10
@export var intelligence: int = 10

@export_group("Derived stats")
## The value at which a stat contributes nothing. Below it a stat never
## penalises; the formulas clamp at zero bonus.
@export var neutral_stat_value: int = 10
## Per point of STR above neutral.
@export var melee_damage_per_point: float = 0.03
## Per point of AGI above neutral.
@export var movement_speed_per_point: float = 0.01
@export var dodge_speed_per_point: float = 0.005
## Flat max health per point of VIT above neutral.
@export var health_per_vitality_point: float = 8.0
## Per point of INT above neutral. Computed and shown; no system consumes it yet.
@export var ability_power_per_point: float = 0.03
