class_name PlayerProgression
extends Node

## Player XP and levels. A component on the player, not part of its controller:
## movement, combat and progression stay separate concerns.
##
## It is the active receiver of XP. A combatant only declares what it is worth
## (`RoomCombatant.xp_reward`); this node decides whether to take it. It learns
## about combatants through the player's own attack hitbox — the only enemies it
## ever hears about are the ones the player actually hit — so nothing here
## searches the tree and no controller has to wire enemies to the player.
##
## NOTE: progression does not survive a scene reload. Dying in a dungeon
## reloads it and builds a fresh player, which starts at level 1. Persisting
## progression across scene changes needs a save/session layer and is deliberately
## out of scope here; it belongs to its own milestone.

signal xp_changed(current_xp: int, required_xp: int)
signal level_changed(level: int)
signal stat_points_changed(points: int)
## Fired once per add_xp() that gained levels, carrying the level reached and
## every point awarded on the way — a single large reward reports one level-up
## of several levels rather than a burst the UI has to queue.
signal level_up(level: int, points_gained: int)

@export var stats: ProgressionStats
## The hitbox whose landed hits introduce combatants to this component. Left
## unset it is resolved from the player on _ready().
@export var attack_hitbox: Hitbox

@export_group("DEBUG")
## DEBUG ONLY. Off by default; the game never needs it. While true, pressing
## `debug_xp_key` grants `debug_xp_amount`. It reads raw key events rather than
## an input action, so it cannot collide with gameplay bindings.
@export var debug_progression_enabled: bool = false
@export var debug_xp_key: Key = KEY_F10
@export var debug_xp_amount: int = 50

# Runtime tuning, seeded from `stats`.
var max_level: int = 100
var stat_points_per_level: int = 5
var base_xp_requirement: int = 100
var xp_growth_factor: float = 1.25

var current_level: int = 1
var current_xp: int = 0
var available_stat_points: int = 0

## M6.1 holds these as data only. M6.2 gives them effects.
var strength: int = 10
var agility: int = 10
var vitality: int = 10
var intelligence: int = 10

## Combatants already being watched, so one enemy is never subscribed twice.
var _tracked: Dictionary = {}


func _ready() -> void:
	_apply_stats()
	if attack_hitbox == null:
		# Resolved here rather than read off the player's own @onready var: this
		# node is a child, so its _ready() runs first and that var is still null.
		attack_hitbox = get_parent().get_node_or_null("VisualRoot/AttackHitbox") as Hitbox
	if attack_hitbox == null:
		push_warning("%s found no attack hitbox; it will never receive XP." % name)
		return
	attack_hitbox.hit_landed.connect(_on_hit_landed)


func _apply_stats() -> void:
	if stats == null:
		push_warning("%s has no ProgressionStats assigned; falling back to script defaults." % name)
		return
	current_level = stats.starting_level
	max_level = stats.max_level
	stat_points_per_level = stats.stat_points_per_level
	base_xp_requirement = stats.base_xp_requirement
	xp_growth_factor = stats.xp_growth_factor
	strength = stats.strength
	agility = stats.agility
	vitality = stats.vitality
	intelligence = stats.intelligence


# --- XP curve -----------------------------------------------------------------

## XP needed to leave `level`. Computed, never a hand-written table.
func xp_required_for_level(level: int) -> int:
	if level < 1:
		level = 1
	return int(round(base_xp_requirement * pow(xp_growth_factor, level - 1)))


func get_xp_to_next_level() -> int:
	if is_max_level():
		return 0
	return xp_required_for_level(current_level)


func is_max_level() -> bool:
	return current_level >= max_level


func get_xp_ratio() -> float:
	var required: int = get_xp_to_next_level()
	if required <= 0:
		return 1.0
	return clampf(float(current_xp) / float(required), 0.0, 1.0)


# --- earning ------------------------------------------------------------------

## Adds XP and levels up as many times as the amount allows. The loop is bounded
## by max_level, so no reward can spin it.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	if is_max_level():
		return

	current_xp += amount
	var levels_gained: int = 0
	var points_gained: int = 0
	while not is_max_level() and current_xp >= get_xp_to_next_level():
		current_xp -= get_xp_to_next_level()
		current_level += 1
		available_stat_points += stat_points_per_level
		levels_gained += 1
		points_gained += stat_points_per_level
	if is_max_level():
		# Nothing left to earn towards, so the bar reads full rather than drifting.
		current_xp = 0

	xp_changed.emit(current_xp, get_xp_to_next_level())
	if levels_gained > 0:
		level_changed.emit(current_level)
		stat_points_changed.emit(available_stat_points)
		level_up.emit(current_level, points_gained)


## DEBUG ONLY.
func debug_add_xp(amount: int) -> void:
	add_xp(amount)


func _unhandled_input(event: InputEvent) -> void:
	if not debug_progression_enabled:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == debug_xp_key:
		debug_add_xp(debug_xp_amount)


# --- receiving from combat ----------------------------------------------------

## The player landed a hit. Watch that combatant so its death can be collected;
## nothing else in the world is ever subscribed to.
func _on_hit_landed(target: Node, _damage: float) -> void:
	var combatant: RoomCombatant = target as RoomCombatant
	if combatant == null or _tracked.has(combatant):
		return
	_tracked[combatant] = true
	# A first hit that kills reports the death before Hitbox emits hit_landed,
	# so the signal we would connect to has already fired. Collect it now.
	if combatant.has_died():
		_collect(combatant)
		return
	combatant.enemy_died.connect(_collect)


## claim_xp() hands its reward out once and returns 0 forever after, so a
## duplicate signal, a room clearing, a phase transition or a dungeon completing
## cannot pay twice.
func _collect(combatant: RoomCombatant) -> void:
	add_xp(combatant.claim_xp())
