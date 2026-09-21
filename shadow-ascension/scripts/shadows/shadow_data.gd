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
