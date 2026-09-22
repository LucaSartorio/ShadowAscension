extends Node

## PERSISTENT PLAYER STATE. Player state that must outlive a scene change, and
## nothing else.
##
## A scene change destroys the player and builds a new one, so everything the
## player knew about itself died with it. This autoload holds the handful of
## values that belong to the session rather than to any one scene, and hands
## them back to the next player. It is the only autoload in the project, and the
## only place session-scoped player data lives.
##
## M10 separates state into categories. This node owns exactly one of them, and
## the others live with whoever their lifetime belongs to:
##
##   Persistent Player State  here                  level, XP, stats, health,
##                                                  inventory, equipment, shadows
##   Run State                DungeonRunStats       what one run amounted to;
##                                                  dies with the run
##   Dungeon State            DungeonController     rooms, current room, whether
##                            + RoomController      the run is over; dies with
##                                                  the dungeon scene
##   World State              nothing yet           no system needs it; do not
##                                                  invent one here
##   Settings                 nothing yet           belongs to a settings service
##                                                  (M19), never to this node
##   Save Data                nothing yet           M19; see below
##
## Nothing that belongs to one run, one dungeon or one scene may be added here,
## however convenient the global access is. The test for it is the lifetime: if
## a new dungeon should start it over, it is not persistent player state.
##
## Lifecycle. The data lives for the SESSION, which a New Game starts:
##
##   New Game       reset_runtime_state(), called from the main menu's GIOCA. The
##                  only place the session goes back to nothing.
##   first player   get_or_create_progression() builds the character from the
##                  player's ProgressionStats — the only first initialization.
##   scene change   the player and everything in the scene are freed and built
##                  again. Nothing here is touched: the new player attaches to
##                  the same progression object and the same shadow array.
##   death          reset_health_to_max(). Progress is untouched.
##
## It is NOT a save system: nothing here touches the disk, and closing the game
## starts a fresh session. Permanent saving is its own milestone.
##
## It is NOT a manager either. It stores and returns data. It owns no logic:
## PlayerProgression still computes XP, levels and every derived stat, and this
## node never duplicates one of those formulas.

## AGGRESSIVE, matching BasicMeleeShadow.CommandMode. A plain int so this
## autoload keeps no dependency on the shadow scene.
const DEFAULT_SHADOW_MODE: int = 1

## The character's level, XP, points and allocated stats. Null until the first
## player of the session asks for it, and null again after a New Game. Every
## PlayerProgression holds a reference to this object, never a copy of it.
var progression: PlayerProgressionData = null

## Current health only, carried so a scene change is not a free heal. The
## HealthComponent on the player owns current health while a scene runs; this is
## the value handed from one player to the next, written on every change.
## Max health is deliberately NOT stored: it is recomputed from the player's own
## base and VIT, so raising VIT and reloading can never desync the two. Negative
## means "start at full", which is both the fresh-session state and what a death
## leaves behind.
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

## Every extracted shadow: the ShadowInstance objects themselves, which carry
## each shadow's own level and XP. The collection on every player holds this same
## array rather than a copy, so a level a shadow earns is already here the moment
## it is earned, and a summoned shadow is only a view onto one of these.
var shadows: Array[ShadowInstance] = []
## The counter lives here too, because a new scene builds a new collection and
## would otherwise start numbering from one again and collide with what is
## already held.
var next_shadow_index: int = 1

## Which shadow was out when the scene changed, so the next one re-summons it.
## Empty means none — a shadow that died, or was recalled, stays recalled.
var active_shadow_instance_id: StringName = &""
## The command mode it was fighting in, as a plain int: this autoload stores and
## never interprets, so it does not know BasicMeleeShadow.CommandMode. Reset to
## the default whenever there is no active shadow, so a fresh summon starts from
## the default rather than from whatever the last one was doing.
var active_shadow_mode: int = DEFAULT_SHADOW_MODE


## The session's character, built from `stats` the first time any player asks
## and handed back unchanged to every player after that. This is the line between
## a first initialization and a scene merely coming up: `stats` is read once per
## session, and a player entering a scene can never re-apply its starting values.
func get_or_create_progression(stats: ProgressionStats) -> PlayerProgressionData:
	if progression == null:
		progression = PlayerProgressionData.from_stats(stats)
	return progression


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


## Stored rather than derived: a shadow that died is no longer active, and the
## collection alone cannot tell that apart from one that was never summoned.
func sync_active_shadow(instance_id: StringName) -> void:
	active_shadow_instance_id = instance_id
	if instance_id == &"":
		# No shadow out, nothing to remember. This is what makes the next summon
		# — after a recall, a shadow's death or the player's own — start from
		# the default mode instead of inheriting the last one.
		active_shadow_mode = DEFAULT_SHADOW_MODE


func sync_active_shadow_mode(mode: int) -> void:
	active_shadow_mode = mode


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


## A New Game: the one place the whole session goes back to nothing. The main
## menu calls it when a run is started, and tests call it to start clean. It is
## never part of a scene change.
##
## The progression and the shadow array are REPLACED rather than emptied. A
## scene still holding the old ones — a player on its way out — keeps writing to
## objects nobody reads any more, and can never leak into the new session.
func reset_runtime_state() -> void:
	progression = null
	current_health = -1.0
	inventory.clear()
	equipment.clear()
	var fresh_shadows: Array[ShadowInstance] = []
	shadows = fresh_shadows
	next_shadow_index = 1
	active_shadow_instance_id = &""
	active_shadow_mode = DEFAULT_SHADOW_MODE
