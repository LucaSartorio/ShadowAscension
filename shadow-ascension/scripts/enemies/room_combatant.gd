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
## Where a target lock points at this: its indicator sits here, and the view to
## it is checked to here. Optional — without one, the body's origin, at its feet.
@export var target_anchor: Node3D = null

var _died: bool = false
var _xp_claimed: bool = false
var _killer: Node = null


## Subclasses override to park or wake their own systems, then call super().
func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled


## Subclasses report death here rather than emitting enemy_died themselves, so
## "dies once" is guaranteed in one place no matter how the death was reached.
## `killer` is whoever dealt the final blow, taken from the health component.
## Carried on the combatant rather than on `enemy_died` so every existing
## listener keeps its signature; whoever cares asks for it.
func report_death(killer: Node = null) -> void:
	if _died:
		return
	_died = true
	_killer = killer
	enemy_died.emit(self)


## The point a target lock aims its indicator and its line of sight at.
func get_target_point() -> Vector3:
	if target_anchor != null and is_instance_valid(target_anchor):
		return target_anchor.global_position
	return global_position


func get_killer() -> Node:
	return _killer


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
