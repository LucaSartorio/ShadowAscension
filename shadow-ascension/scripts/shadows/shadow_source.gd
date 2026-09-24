class_name ShadowSource
extends Node

## Declares that a combatant leaves a shadow behind, and drops the remnant when
## it dies. A component, like LootDropper — the combatant itself never learns
## what it is worth, and nothing anywhere branches on an enemy's class to decide
## which shadow it yields.
##
## RoomCombatant.report_death() fires its hook exactly once however the death was
## reached, and this node latches as well, so a duplicated signal, a room
## clearing, an XP award or a loot roll cannot spawn a second remnant.

@export var shadow_extractable: bool = true
@export var shadow_data: ShadowData
@export var remnant_scene: PackedScene
## Offset from the corpse. Deterministic and away from where LootDropper
## scatters, so the two do not land on top of each other.
@export var spawn_offset: Vector3 = Vector3(0.0, 0.1, -1.3)

var _spawned: bool = false
var _combatant: RoomCombatant = null


func _ready() -> void:
	_combatant = get_parent() as RoomCombatant
	if _combatant == null:
		push_warning("%s expects to be a child of a RoomCombatant." % name)
		return
	_combatant.enemy_died.connect(_on_died)


func has_spawned() -> bool:
	return _spawned


## Public so a test can spawn deterministically without killing anything.
func spawn_remnant() -> ShadowRemnant:
	if _spawned or not shadow_extractable:
		return null
	if shadow_data == null or remnant_scene == null or _combatant == null:
		return null
	var parent: Node = _combatant.get_parent()
	if parent == null:
		return null
	_spawned = true
	var remnant: ShadowRemnant = remnant_scene.instantiate() as ShadowRemnant
	remnant.configure(shadow_data)
	parent.add_child(remnant)
	# The corpse is standing on the floor, so its own Y is the floor.
	remnant.global_position = _combatant.global_position + spawn_offset
	return remnant


func _on_died(_dead: RoomCombatant) -> void:
	spawn_remnant()
