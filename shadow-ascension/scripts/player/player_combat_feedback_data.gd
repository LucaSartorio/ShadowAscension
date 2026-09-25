class_name PlayerCombatFeedbackData
extends Resource

## How the player's hits are felt (M11.9): the rules around each attack's own
## hit stop and camera shake (AttackData, Feedback group) — what a critical adds,
## the ceilings nothing goes past, the critical's placeholder mark — and the two
## accessibility scales. Shared and never written in play: the scales in use
## live on PlayerCombatFeedback, copied from here.

@export_group("Hit stop")
## Engine.time_scale while a hit stop holds: 0 stops the game dead, 0.1 would
## slow it to a tenth instead.
@export_range(0.0, 1.0, 0.01) var hit_stop_time_scale: float = 0.0
## Seconds a critical adds to its attack's hit stop.
@export_range(0.0, 0.1, 0.001) var critical_hit_stop_bonus: float = 0.015
## No hit stop holds longer than this, whatever asked for it.
@export_range(0.0, 0.5, 0.005) var max_hit_stop_duration: float = 0.1

@export_group("Camera shake")
## What a critical multiplies its attack's shake strength by.
@export_range(1.0, 3.0, 0.05) var critical_shake_multiplier: float = 1.35
## No shake throws the camera further than this, in metres, or lasts longer
## than this, in seconds.
@export_range(0.0, 1.0, 0.01) var max_camera_shake_strength: float = 0.2
@export_range(0.0, 1.0, 0.01) var max_camera_shake_duration: float = 0.35

@export_group("Critical mark")
## PLACEHOLDER until damage numbers exist: a word that pops above a target a
## critical hit, rises and fades.
@export var critical_label_text: String = "CRITICO!"
@export var critical_label_color: Color = Color(1.0, 0.82, 0.25, 1.0)
## Metres above the target's aim point it appears, and how far it rises.
@export_range(0.0, 2.0, 0.05) var critical_label_height: float = 0.5
@export_range(0.0, 2.0, 0.05) var critical_label_rise: float = 0.6
## Seconds from appearing to gone.
@export_range(0.05, 2.0, 0.05) var critical_label_duration: float = 0.5
## The most marks on screen at once; a critical beyond them shows none.
@export_range(0, 16, 1) var max_critical_labels: int = 4

@export_group("Accessibility")
## Scale every camera shake and every hit stop, 1.0 as designed, 0.0 off. The
## defaults a settings screen will change when there is one — through
## PlayerCombatFeedback, never by writing here.
@export_range(0.0, 1.0, 0.05) var camera_shake_scale: float = 1.0
@export_range(0.0, 1.0, 0.05) var hit_stop_scale: float = 1.0
