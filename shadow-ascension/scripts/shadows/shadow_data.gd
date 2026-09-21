class_name ShadowData
extends Resource

## The definition of one kind of shadow. Instances live under `resources/shadows/`
## as `.tres`.
##
## Pure data and nothing else: a shadow type describes itself and how likely it is
## to be torn loose. No runtime state lives here — an extracted shadow is a
## ShadowInstance, and many instances can share one definition.

@export var id: StringName = &""
@export var display_name: String = "Shadow"
@export_multiline var description: String = ""
## Probability that one extraction attempt succeeds, 0..1. The only place this
## number exists — the extraction logic never hardcodes it.
@export_range(0.0, 1.0) var extraction_chance: float = 0.7
## Tint for the remnant and the collection list, so a type reads at a glance.
@export var accent_color: Color = Color(0.55, 0.35, 0.95)
## What this type summons as. Left unset the shadow cannot be summoned.
@export var summon_scene: PackedScene

@export_group("Combat")
## At level 1. Both scale with level — see the formulas below, which live here
## rather than in the runtime entity so a second shadow type can differ.
@export var base_health: float = 80.0
@export var health_per_level: float = 8.0
@export var base_damage: float = 12.0
@export var damage_per_level: float = 2.0

@export_group("Progression")
@export var base_xp_requirement: int = 50
@export var xp_growth_factor: float = 1.2


## Health at a given level. Level 1 is the base; nothing is granted below it.
func health_at_level(level: int) -> float:
	return base_health + maxi(0, level - 1) * health_per_level


func damage_at_level(level: int) -> float:
	return base_damage + maxi(0, level - 1) * damage_per_level


## XP needed to leave `level`. Computed, never a table — the same shape as the
## player's curve, with its own constants.
func xp_required_for_level(level: int) -> int:
	return int(round(base_xp_requirement * pow(xp_growth_factor, maxi(1, level) - 1)))
