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
## Progression survives a scene change because none of it lives here. The level,
## XP, points and stats are a PlayerProgressionData held by the PlayerRuntimeState
## autoload; this node attaches to that one object on _ready() and reads and
## writes it in place. A new player scene attaches to the same object again, so
## there is no restore step to forget and no copy to fall out of step.
##
## What does live here is everything that DOES something with those numbers: the
## XP curve, the level-up loop, the derived stats, and the signals the UI listens
## to. The data object is storage; this is its only writer.

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
## The hitbox whose landed hits introduce combatants to this component. Handed
## over by the player in setup().
var attack_hitbox: Hitbox = null
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

# Curve tuning, seeded from `stats` in _apply_tuning(). CONFIGURATION read into
# this node, not state: nothing changes them in play, and they carry no values
# of their own — the numbers live in ProgressionStats and nowhere in this script.
var max_level: int
var stat_points_per_level: int
var base_xp_requirement: int
var xp_growth_factor: float

## Where the character has got to. These are views onto the session's
## PlayerProgressionData, not copies of it: reading one reads the session, and
## writing one writes the session. Nothing needs syncing, and nothing is lost
## when this node is freed.
var current_level: int:
	get: return _data.current_level
	set(value): _data.current_level = value
var current_xp: int:
	get: return _data.current_xp
	set(value): _data.current_xp = value
var available_stat_points: int:
	get: return _data.available_stat_points
	set(value): _data.available_stat_points = value

## ALLOCATED stats. Equipment adds on top when an effective value is asked for;
## it never writes these, so taking a piece off can never leave a stat inflated.
var strength: int:
	get: return _data.strength
	set(value): _data.strength = value
var agility: int:
	get: return _data.agility
	set(value): _data.agility = value
var vitality: int:
	get: return _data.vitality
	set(value): _data.vitality = value
var intelligence: int:
	get: return _data.intelligence
	set(value): _data.intelligence = value

# Derived-stat tuning, seeded from `stats` the same way.
var neutral_stat_value: int
var melee_damage_per_point: float
var movement_speed_per_point: float
var dodge_speed_per_point: float
var health_per_vitality_point: float
var ability_power_per_point: float

## The session's character. A private stand-in until _ready() attaches to the
## real one, so nothing read before then can fail; a node with no session at all
## (a bare bench outside the project) keeps a private character of its own.
var _data: PlayerProgressionData = PlayerProgressionData.new()
## Combatants already being watched, so one enemy is never subscribed twice.
var _tracked: Dictionary = {}
var _shadows: PlayerShadowCollection = null


func _ready() -> void:
	_apply_tuning()
	_attach_to_session()


## Called once by the player with the siblings this needs. Nothing here looks
## anything up: the player knows its own layout, this only knows what it is given.
func setup(hitbox: Hitbox, player_equipment: PlayerEquipment,
		collection: PlayerShadowCollection, summoner: PlayerShadowSummoner) -> void:
	attack_hitbox = hitbox
	equipment = player_equipment
	_shadows = collection
	if summoner != null:
		# The shadow's kills count too, so its hits introduce combatants the same
		# way the player's do. Nothing else about it is watched.
		summoner.shadow_summoned.connect(_on_shadow_summoned)
	if attack_hitbox == null:
		push_warning("%s was given no attack hitbox; it will never receive XP." % name)
		return
	attack_hitbox.hit_landed.connect(_on_hit_landed)


## Tuning only: the curve, what a level pays, and the derived-stat rates. The
## starting level and stat block are NOT applied here — doing that on every
## _ready() is exactly how a scene change used to put a character back to level
## 1. They are applied once per session, by PlayerProgressionData.from_stats().
func _apply_tuning() -> void:
	var source: ProgressionStats = stats
	if source == null:
		push_warning("%s has no ProgressionStats assigned; falling back to ProgressionStats' defaults." % name)
		source = ProgressionStats.new()
	max_level = source.max_level
	stat_points_per_level = source.stat_points_per_level
	base_xp_requirement = source.base_xp_requirement
	xp_growth_factor = source.xp_growth_factor
	neutral_stat_value = source.neutral_stat_value
	melee_damage_per_point = source.melee_damage_per_point
	movement_speed_per_point = source.movement_speed_per_point
	dodge_speed_per_point = source.dodge_speed_per_point
	health_per_vitality_point = source.health_per_vitality_point
	ability_power_per_point = source.ability_power_per_point


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


## Every point of XP this character has ever earned, levels included. `current_xp`
## alone resets on each level-up, so it cannot be differenced across a stretch of
## play — this can, which is how a run reports what it was worth.
func get_total_xp() -> int:
	var total: int = current_xp
	for level in range(1, current_level):
		total += xp_required_for_level(level)
	return total


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


# --- session ------------------------------------------------------------------

## The first player of a session creates the character from `stats`; every player
## after it attaches to that same character. Derived stats are never stored, so
## there is nothing else to bring across: they are recomputed from the data.
func _attach_to_session() -> void:
	var state: Node = _runtime_state()
	if state == null:
		_data = PlayerProgressionData.from_stats(stats)
		return
	_data = state.get_or_create_progression(stats)


func _runtime_state() -> Node:
	return Player.session(self)


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
func _on_hit_landed(target: Node, _hit: DamageInfo) -> void:
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
