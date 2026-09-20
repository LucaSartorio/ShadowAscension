class_name RoomController
extends Node3D

## Lifecycle of a single room: arm on entry, hold the exit shut until every
## enemy that belongs to this room is dead, then open it and stay cleared.
##
## The room only ever looks at its own children. It never scans the tree for
## enemies, and it never talks to the dungeon — it reports through signals.

signal room_started(room: RoomController)
signal room_cleared(room: RoomController)

enum RoomState { IDLE, ACTIVE, CLEARED }

## A room with no enemies clears the moment it starts (start rooms, corridors).
@onready var enemy_container: Node3D = $Enemies
@onready var entry_trigger: Area3D = $EntryTrigger
@onready var exit_door: DungeonDoor = $ExitDoor
## Each room bakes its own island. Rooms are walled off from each other, so an
## enemy's path can never leave the room it belongs to.
@onready var navigation_region: NavigationRegion3D = $NavigationRegion3D

var _state: RoomState = RoomState.IDLE
var _enemies: Array[BasicMeleeEnemy] = []
var _alive: int = 0


func _ready() -> void:
	if navigation_region != null and navigation_region.navigation_mesh != null:
		# The NavigationMesh is a sub-resource of the room scene, so every instance
		# of that scene would share one object and the last bake would win. Give
		# this room its own copy before baking.
		navigation_region.navigation_mesh = navigation_region.navigation_mesh.duplicate()
		navigation_region.bake_navigation_mesh(false)
	_collect_enemies()
	# Parked until the player walks in. Done here rather than in the scene so a
	# room can never ship with live enemies by accident.
	for enemy in _enemies:
		enemy.set_combat_enabled(false)
		enemy.enemy_died.connect(_on_enemy_died)
	_alive = _enemies.size()
	exit_door.lock()
	entry_trigger.body_entered.connect(_on_entry_body_entered)


## One scan at startup, over this room's own subtree only.
func _collect_enemies() -> void:
	if enemy_container == null:
		return
	for child in enemy_container.get_children():
		var enemy: BasicMeleeEnemy = child as BasicMeleeEnemy
		if enemy != null:
			_enemies.append(enemy)


func get_state() -> RoomState:
	return _state


func is_cleared() -> bool:
	return _state == RoomState.CLEARED


func get_enemies() -> Array[BasicMeleeEnemy]:
	return _enemies


func _on_entry_body_entered(body: Node3D) -> void:
	# Only IDLE arms. A cleared room never fights again, an active one never
	# restarts, so backtracking is safe.
	if _state != RoomState.IDLE:
		return
	if not body.is_in_group("player"):
		return
	_start()


func _start() -> void:
	_state = RoomState.ACTIVE
	exit_door.lock()
	for enemy in _enemies:
		enemy.set_combat_enabled(true)
	room_started.emit(self)
	if _alive == 0:
		_clear()


func _on_enemy_died(_enemy: BasicMeleeEnemy) -> void:
	_alive = maxi(0, _alive - 1)
	if _state != RoomState.ACTIVE:
		return
	if _alive == 0:
		_clear()


func _clear() -> void:
	_state = RoomState.CLEARED
	exit_door.unlock()
	room_cleared.emit(self)
