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


## Subclasses override to park or wake their own systems, then call super().
func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
