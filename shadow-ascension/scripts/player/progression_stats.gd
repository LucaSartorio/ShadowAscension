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
## Data only in M6.1. What they actually do lands in M6.2.
@export var strength: int = 10
@export var agility: int = 10
@export var vitality: int = 10
@export var intelligence: int = 10
