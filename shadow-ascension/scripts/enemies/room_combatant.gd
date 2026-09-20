class_name RoomCombatant
extends CharacterBody3D

## The contract a RoomController drives: park it, wake it, hear about its death.
##
## Deliberately behaviourless. BasicMeleeEnemy and DungeonBoss implement their AI
## independently — this exists so a room can hold either without knowing which,
## and without one inheriting the other's logic.

## Drop hook, emitted once on death. Rooms count it; loot (M7), XP (M6) and
## shadow extraction (M8) will subscribe here too.
signal enemy_died(combatant: RoomCombatant)

## While false the combatant must not perceive, move, navigate or attack.
@export var combat_enabled: bool = true
## What killing this is worth, for a combatant with no stats Resource of its own.
## The combatant only declares the number — deciding whether to take it belongs to
## whoever is progressing (see PlayerProgression). Read through get_xp_reward().
@export var xp_reward: int = 0

var _died: bool = false
var _xp_claimed: bool = false


## Subclasses override to park or wake their own systems, then call super().
func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled


## Subclasses report death here rather than emitting enemy_died themselves, so
## "dies once" is guaranteed in one place no matter how the death was reached.
func report_death() -> void:
	if _died:
		return
	_died = true
	enemy_died.emit(self)


func has_died() -> bool:
	return _died


## What killing this is worth. Subclasses that carry a stats Resource override
## this and answer from it; the exported value is the fallback for anything
## placed in a scene without one.
func get_xp_reward() -> int:
	return xp_reward


## Hands the reward over exactly once. Every later call returns 0, so a duplicate
## signal, a room clearing, a boss phase transition or a dungeon completing
## cannot pay out a second time.
func claim_xp() -> int:
	if _xp_claimed:
		return 0
	_xp_claimed = true
	return get_xp_reward()
