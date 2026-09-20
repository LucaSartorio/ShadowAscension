class_name DungeonController
extends Node3D

## Orchestrates one dungeon run: it knows the room order, which room is current,
## and when the run is over. It owns no combat, no AI, no door mechanics — it
## only listens to the rooms under its Rooms container, in tree order.

signal dungeon_started
signal dungeon_completed

enum DungeonState { NOT_STARTED, IN_PROGRESS, COMPLETED }

@export var completion_message: String = "DUNGEON COMPLETE"

@onready var rooms_container: Node3D = $Rooms
@onready var completion_label: Label = $CompletionUI/CompletionLabel

var _state: DungeonState = DungeonState.NOT_STARTED
var _rooms: Array[RoomController] = []
var _current_index: int = 0


func _ready() -> void:
	_collect_rooms()
	for room in _rooms:
		room.room_started.connect(_on_room_started)
		room.room_cleared.connect(_on_room_cleared)
	if completion_label != null:
		completion_label.visible = false


## Room order is tree order under Rooms — no NodePath wiring to keep in sync.
func _collect_rooms() -> void:
	if rooms_container == null:
		return
	for child in rooms_container.get_children():
		var room: RoomController = child as RoomController
		if room != null:
			_rooms.append(room)


func get_state() -> DungeonState:
	return _state


func get_rooms() -> Array[RoomController]:
	return _rooms


func get_current_room_index() -> int:
	return _current_index


func _on_room_started(room: RoomController) -> void:
	_current_index = _rooms.find(room)
	if _state == DungeonState.NOT_STARTED:
		_state = DungeonState.IN_PROGRESS
		dungeon_started.emit()


func _on_room_cleared(room: RoomController) -> void:
	if _state == DungeonState.COMPLETED:
		return
	if room != _rooms.back():
		return
	_state = DungeonState.COMPLETED
	if completion_label != null:
		completion_label.text = completion_message
		completion_label.visible = true
	print("[Dungeon] " + completion_message)
	dungeon_completed.emit()
