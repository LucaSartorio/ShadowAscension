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
## Progression survives a scene change: the first player of the session hands its
## starting values to the PlayerRuntimeState autoload, and every later player
## restores from it. That autoload stores data only — every formula, including
## the XP curve and each derived stat, stays here.

signal xp_changed(current_xp: int, required_xp: int)
signal level_changed(level: int)
signal stat_points_changed(points: int)
## Fired once per add_xp() that gained levels, carrying the level reached and
## every point awarded on the way — a single large reward reports one level-up
## of several levels rather than a burst the UI has to queue.
signal level_up(level: int, points_gained: int)
## Fired whenever a stat changes, so every system that derives a value from the
## stats recomputes once instead of polling. Carries nothing: listeners ask for
## the derived value they care about.
signal stats_changed
## A kill the summoned shadow finished. Carries both halves of the split so the
## HUD can say where the XP went without recomputing the share.
signal shadow_assisted_kill(shadow: ShadowInstance, shadow_xp: int, player_xp: int)

enum Stat { STRENGTH, AGILITY, VITALITY, INTELLIGENCE }

## The shadow's cut when it lands the killing blow. The player keeps the
## remainder rather than a second rounded share, so the two always add back up
## to the full reward.
const SHADOW_KILL_SHARE: float = 0.70

@export var stats: ProgressionStats
## The hitbox whose landed hits introduce combatants to this component. Left
## unset it is resolved from the player on _ready().
@export var attack_hitbox: Hitbox
## Set by the player. This node stays the stats layer: it owns every formula and
## combines the allocated stats with whatever equipment contributes, rather than
## letting each consumer add the two up itself.
var equipment: PlayerEquipment = null

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

## The single source of truth for the player's ALLOCATED stats. Equipment adds
## on top when an effective value is asked for; these are never written to, so
## taking a piece off can never leave a stat inflated.
var strength: int = 10
var agility: int = 10
var vitality: int = 10
var intelligence: int = 10

# Derived-stat tuning, seeded from `stats`.
var neutral_stat_value: int = 10
var melee_damage_per_point: float = 0.03
var movement_speed_per_point: float = 0.01
var dodge_speed_per_point: float = 0.005
var health_per_vitality_point: float = 8.0
var ability_power_per_point: float = 0.03

## Combatants already being watched, so one enemy is never subscribed twice.
var _tracked: Dictionary = {}
var _shadows: PlayerShadowCollection = null


func _ready() -> void:
	_apply_stats()
	_restore_or_capture()
	if attack_hitbox == null:
		# Resolved here rather than read off the player's own @onready var: this
		# node is a child, so its _ready() runs first and that var is still null.
		attack_hitbox = get_parent().get_node_or_null("VisualRoot/AttackHitbox") as Hitbox
	_shadows = get_parent().get_node_or_null("PlayerShadowCollection") as PlayerShadowCollection
	var summoner: PlayerShadowSummoner = get_parent().get_node_or_null(
		"PlayerShadowSummoner") as PlayerShadowSummoner
	if summoner != null:
		# The shadow's kills count too, so its hits introduce combatants the same
		# way the player's do. Nothing else about it is watched.
		summoner.shadow_summoned.connect(_on_shadow_summoned)
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
	neutral_stat_value = stats.neutral_stat_value
	melee_damage_per_point = stats.melee_damage_per_point
	movement_speed_per_point = stats.movement_speed_per_point
	dodge_speed_per_point = stats.dodge_speed_per_point
	health_per_vitality_point = stats.health_per_vitality_point
	ability_power_per_point = stats.ability_power_per_point


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

	_sync_to_runtime_state()
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


# --- session persistence ------------------------------------------------------

## The first player of a session defines the starting point; every player after
## it picks up where the last one left off. Only the raw values travel — derived
## stats are always recomputed here, never restored.
func _restore_or_capture() -> void:
	var state: Node = _runtime_state()
	if state == null:
		return
	if not state.initialized:
		state.capture_initial(current_level, current_xp, available_stat_points, _stat_dictionary())
		return
	current_level = state.current_level
	current_xp = state.current_xp
	available_stat_points = state.available_stat_points
	strength = state.strength
	agility = state.agility
	vitality = state.vitality
	intelligence = state.intelligence


## One place writes progress back, so a new field does not have to be remembered
## in every callback that can change it.
func _sync_to_runtime_state() -> void:
	var state: Node = _runtime_state()
	if state == null:
		return
	state.sync_progression(current_level, current_xp, available_stat_points, _stat_dictionary())


func _stat_dictionary() -> Dictionary:
	return {
		"strength": strength,
		"agility": agility,
		"vitality": vitality,
		"intelligence": intelligence,
	}


func _runtime_state() -> Node:
	return get_tree().root.get_node_or_null("PlayerRuntimeState")


# --- stats and derived values -------------------------------------------------

## Allocated plus whatever is worn. Every derived value below uses these, never
## the allocated numbers on their own.
func get_effective_strength() -> int:
	return strength + (equipment.get_bonus_strength() if equipment != null else 0)


func get_effective_agility() -> int:
	return agility + (equipment.get_bonus_agility() if equipment != null else 0)


func get_effective_vitality() -> int:
	return vitality + (equipment.get_bonus_vitality() if equipment != null else 0)


func get_effective_intelligence() -> int:
	return intelligence + (equipment.get_bonus_intelligence() if equipment != null else 0)


func get_effective_stat(stat: Stat) -> int:
	match stat:
		Stat.STRENGTH:
			return get_effective_strength()
		Stat.AGILITY:
			return get_effective_agility()
		Stat.VITALITY:
			return get_effective_vitality()
		Stat.INTELLIGENCE:
			return get_effective_intelligence()
	return 0


## What equipment alone contributes, for a UI that wants to show the split.
func get_equipment_bonus(stat: Stat) -> int:
	return get_effective_stat(stat) - get_stat(stat)


## Flat damage the main hand adds before the STR multiplier. 0 unarmed.
func get_melee_attack_power() -> float:
	return equipment.get_melee_attack_power() if equipment != null else 0.0


func get_stat(stat: Stat) -> int:
	match stat:
		Stat.STRENGTH:
			return strength
		Stat.AGILITY:
			return agility
		Stat.VITALITY:
			return vitality
		Stat.INTELLIGENCE:
			return intelligence
	return 0


## Spends one point. Refuses when there is nothing to spend, so a double click or
## a stale button press cannot go negative or charge twice.
func allocate_stat(stat: Stat) -> bool:
	if available_stat_points <= 0:
		return false
	match stat:
		Stat.STRENGTH:
			strength += 1
		Stat.AGILITY:
			agility += 1
		Stat.VITALITY:
			vitality += 1
		Stat.INTELLIGENCE:
			intelligence += 1
		_:
			return false
	available_stat_points -= 1
	_sync_to_runtime_state()
	stat_points_changed.emit(available_stat_points)
	stats_changed.emit()
	return true


## Points above the value at which a stat does nothing. Never negative: a low
## stat costs nothing, it simply grants nothing.
func _points_above_neutral(value: int) -> int:
	return maxi(0, value - neutral_stat_value)


func get_melee_damage_multiplier() -> float:
	return 1.0 + _points_above_neutral(get_effective_strength()) * melee_damage_per_point


func get_movement_speed_multiplier() -> float:
	return 1.0 + _points_above_neutral(get_effective_agility()) * movement_speed_per_point


func get_dodge_speed_multiplier() -> float:
	return 1.0 + _points_above_neutral(get_effective_agility()) * dodge_speed_per_point


## Flat health added on top of the player's own base maximum.
func get_bonus_max_health() -> float:
	return _points_above_neutral(get_effective_vitality()) * health_per_vitality_point


## Computed and shown, but nothing consumes it yet — the abilities it is meant
## for do not exist. It is here so the stat reads as doing something real rather
## than being invented later.
func get_ability_power_multiplier() -> float:
	return 1.0 + _points_above_neutral(get_effective_intelligence()) * ability_power_per_point


## Applied when a swing is prepared, never written back into the combo step, so
## neither the weapon nor the multiplier can stack across attacks.
##
##     round((base + weapon attack power) * STR multiplier)
func get_effective_damage(base_damage: float) -> float:
	return roundf((base_damage + get_melee_attack_power()) * get_melee_damage_multiplier())


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


func _on_shadow_summoned(_shadow: ShadowInstance, node: BasicMeleeShadow) -> void:
	if node == null or node.attack_hitbox == null:
		return
	node.attack_hitbox.hit_landed.connect(_on_hit_landed)


## claim_xp() hands its reward out once and returns 0 forever after, so a
## duplicate signal, a room clearing, a phase transition or a dungeon completing
## cannot pay twice.
##
## Who struck last decides the split: the player keeps the whole reward for its
## own kills, and shares it when the shadow finished the job.
func _collect(combatant: RoomCombatant) -> void:
	var total: int = combatant.claim_xp()
	if total <= 0:
		return
	var killer: ShadowInstance = _shadow_killer(combatant)
	if killer == null:
		add_xp(total)
		return
	var shadow_xp: int = int(round(total * SHADOW_KILL_SHARE))
	var player_xp: int = total - shadow_xp
	_shadows.award_xp(killer.instance_id, shadow_xp)
	add_xp(player_xp)
	shadow_assisted_kill.emit(killer, shadow_xp, player_xp)


## The shadow that landed the killing blow, or null when the player did. A
## shadow that is no longer in the collection counts as null — the kill still
## happened, but there is nothing left to pay.
func _shadow_killer(combatant: RoomCombatant) -> ShadowInstance:
	var node: BasicMeleeShadow = combatant.get_killer() as BasicMeleeShadow
	if node == null or node.instance == null or _shadows == null:
		return null
	if not _shadows.has_shadow(node.instance.instance_id):
		return null
	return node.instance
