class_name BossAttack
extends Resource

## One boss attack: its timings, its reach, its cooldown and how it telegraphs.
## Instances live under `resources/enemies/bosses/` as `.tres`.
##
## Pure data. The boss reads it; nothing here touches the scene tree.

## How the wind-up reads without real animation. Each shape is visually distinct
## so the three attacks can be told apart at a glance.
enum Telegraph { LEAN, SPIN, COMPRESS, RECOIL }

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

@export_group("Multi-hit")
## Swings in a single attack. Each swing re-activates the hitbox, which clears
## its hit registry, so one swing can land once and the next can land again.
@export var hit_count: int = 1
## Gap between swings. The boss is committed but harmless here.
@export var delay_between_hits: float = 0.0
## Fraction of rotation_speed usable in that gap. Small on purpose: the second
## swing may be nudged, never snapped onto a player who already left.
@export_range(0.0, 1.0) var between_hits_facing_fraction: float = 0.0

@export_group("Phase 2")
## Timings this attack switches to once the boss reaches phase 2. Damage and
## reach never change — phase 2 changes the rhythm, not the numbers.
@export var phase_2_startup: float = 0.2
@export var phase_2_recovery: float = 0.35
@export var phase_2_cooldown: float = 0.8
## False keeps the attack out of phase 1 entirely (Double Strike).
@export var available_in_phase_1: bool = true
## Relative pick weight among the attacks that are valid this frame. Lower means
## rarer without ever being impossible.
@export var weight_phase_1: float = 1.0
@export var weight_phase_2: float = 1.0

@export_group("Telegraph")
@export var telegraph: Telegraph = Telegraph.LEAN
@export var telegraph_color: Color = Color(1.0, 0.8, 0.25)
## Fraction of rotation_speed usable during STARTUP. 0 means fully committed the
## moment the wind-up begins.
@export_range(0.0, 1.0) var facing_correction_fraction: float = 0.35


# --- per-phase accessors ------------------------------------------------------
# The boss asks for a timing rather than branching on the phase itself, so the
# phase rules live here with the data instead of being spread through the AI.

func get_startup(in_phase_2: bool) -> float:
	return phase_2_startup if in_phase_2 else startup


func get_recovery(in_phase_2: bool) -> float:
	return phase_2_recovery if in_phase_2 else recovery


func get_cooldown(in_phase_2: bool) -> float:
	return phase_2_cooldown if in_phase_2 else cooldown


func get_weight(in_phase_2: bool) -> float:
	return weight_phase_2 if in_phase_2 else weight_phase_1


func is_available(in_phase_2: bool) -> bool:
	return in_phase_2 or available_in_phase_1
