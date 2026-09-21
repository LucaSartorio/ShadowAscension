extends Node

## Player state that must outlive a scene change, and nothing else.
##
## A scene change destroys the player and builds a new one, so everything the
## player knew about itself died with it. This autoload holds the handful of
## values that belong to the session rather than to any one scene, and hands
## them back to the next player.
##
## It is NOT a save system: nothing here touches the disk, and closing the game
## starts a fresh session. Permanent saving is its own milestone.
##
## It is NOT a manager either. It stores and returns data. It owns no logic:
## PlayerProgression still computes XP, levels and every derived stat, and this
## node never duplicates one of those formulas.

## Emitted when the session is wiped back to its starting values. Ordinary
## progress changes are already reported by PlayerProgression, and are not
## repeated here.
signal runtime_state_reset

const DEFAULT_LEVEL: int = 1
const DEFAULT_STAT: int = 10

## False until the first player of the session hands over its starting values.
var initialized: bool = false

var current_level: int = DEFAULT_LEVEL
var current_xp: int = 0
var available_stat_points: int = 0

var strength: int = DEFAULT_STAT
var agility: int = DEFAULT_STAT
var vitality: int = DEFAULT_STAT
var intelligence: int = DEFAULT_STAT

## Carried so a scene change is not a free heal. Max health is deliberately NOT
## stored: it is recomputed from the player's own base and VIT, so raising VIT
## and reloading can never desync the two. Negative means "start at full", which
## is both the fresh-session state and what a death leaves behind.
var current_health: float = -1.0

## What the player is carrying: id -> { "item": ItemData, "quantity": int }.
## Stored, never interpreted — stacking, caps and ordering all belong to
## PlayerInventory. The ItemData references are held directly because this is
## runtime only; nothing here is serialised.
var inventory: Dictionary = {}

## EquipmentSlot -> ItemData for whatever is worn. Bonuses and effective stats
## are deliberately absent: they are recomputed from this on every load, so the
## two can never drift apart.
var equipment: Dictionary = {}

## Extracted shadows, as [{ instance_id, shadow_data }]. Kept flat and dumb: the
## collection rebuilds its ShadowInstance objects from these. The counter lives
## here too, because a new scene builds a new collection and would otherwise
## start numbering from one again and collide with what is already held.
var shadows: Array[Dictionary] = []
var next_shadow_index: int = 1


## Called by the first player of the session, with the values its own resources
## gave it. Later players restore instead. Health is deliberately not a parameter:
## progression does not know it, and the player reports its own.
func capture_initial(level: int, xp: int, points: int, stats: Dictionary) -> void:
	if initialized:
		return
	current_level = level
	current_xp = xp
	available_stat_points = points
	strength = stats.get("strength", DEFAULT_STAT)
	agility = stats.get("agility", DEFAULT_STAT)
	vitality = stats.get("vitality", DEFAULT_STAT)
	intelligence = stats.get("intelligence", DEFAULT_STAT)
	initialized = true


## The one place progress is written back. PlayerProgression calls this whenever
## anything it owns changes, so no callback keeps its own copy of this list.
func sync_progression(level: int, xp: int, points: int, stats: Dictionary) -> void:
	current_level = level
	current_xp = xp
	available_stat_points = points
	strength = stats.get("strength", strength)
	agility = stats.get("agility", agility)
	vitality = stats.get("vitality", vitality)
	intelligence = stats.get("intelligence", intelligence)
	initialized = true


func sync_health(value: float) -> void:
	current_health = value


func sync_inventory(stacks: Dictionary) -> void:
	inventory = _copy_stacks(stacks)


## A copy, so the live inventory and the stored one cannot alias each other.
func get_inventory_copy() -> Dictionary:
	return _copy_stacks(inventory)


func sync_equipment(slots: Dictionary) -> void:
	equipment = slots.duplicate()


func get_equipment_copy() -> Dictionary:
	return equipment.duplicate()


func sync_shadows(rows: Array[Dictionary]) -> void:
	shadows = rows.duplicate()


## Hands out the next number and moves on, so no two extractions can share one.
func take_next_shadow_index() -> int:
	var index: int = next_shadow_index
	next_shadow_index += 1
	return index


func _copy_stacks(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in source:
		out[id] = {"item": source[id]["item"], "quantity": source[id]["quantity"]}
	return out


## Death is the one case that restores health without touching progress: the run
## restarts, the character does not.
func reset_health_to_max() -> void:
	# -1 means "whatever the next player computes as its maximum". The value
	# itself is not stored, because it depends on VIT and on the player's base.
	current_health = -1.0


func wants_full_health() -> bool:
	return current_health < 0.0


## A fresh session. Not part of any scene change — for debug, tests, and a
## future New Game.
func reset_runtime_state() -> void:
	initialized = false
	current_level = DEFAULT_LEVEL
	current_xp = 0
	available_stat_points = 0
	strength = DEFAULT_STAT
	agility = DEFAULT_STAT
	vitality = DEFAULT_STAT
	intelligence = DEFAULT_STAT
	current_health = -1.0
	inventory.clear()
	equipment.clear()
	shadows.clear()
	next_shadow_index = 1
	runtime_state_reset.emit()
