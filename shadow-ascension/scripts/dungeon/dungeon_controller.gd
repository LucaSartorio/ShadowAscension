class_name DungeonController
extends Node3D

## Orchestrates one dungeon run: room order, which room is current, when the run
## ends — by completion or by the player dying. It owns no combat, no AI, no door
## mechanics and no player movement; it only listens to the rooms under its Rooms
## container, in tree order.

signal dungeon_started
signal dungeon_completed
signal run_failed

enum DungeonState { NOT_STARTED, IN_PROGRESS, COMPLETED, FAILED }

@export var completion_message: String = "DUNGEON COMPLETE"
@export var death_message: String = "YOU DIED"
## How long the completion banner stays up. The exit portal stays live after it.
@export var completion_message_duration: float = 1.8
@export var death_restart_delay: float = 1.2

@onready var rooms_container: Node3D = $Rooms
@onready var status_label: Label = $DungeonUI/StatusLabel
@onready var exit_portal: DungeonExit = $DungeonExit

var _state: DungeonState = DungeonState.NOT_STARTED
var _rooms: Array[RoomController] = []
var _current_index: int = 0
## Latched the first time the run ends, either way. Everything that could fire a
## second completion or a second restart checks it.
var _run_ended: bool = false
var _player: Player = null
var _transition: SceneTransition = null
var _status_tween: Tween = null
var _restart_tween: Tween = null


func _ready() -> void:
	_collect_rooms()
	for room in _rooms:
		room.room_started.connect(_on_room_started)
		room.room_cleared.connect(_on_room_cleared)
	if status_label != null:
		status_label.visible = false
	if exit_portal != null:
		exit_portal.set_enabled(false)
	_connect_player()


## Room order is tree order under Rooms — no NodePath wiring to keep in sync.
func _collect_rooms() -> void:
	if rooms_container == null:
		return
	for child in rooms_container.get_children():
		var room: RoomController = child as RoomController
		if room != null:
			_rooms.append(room)


## One lookup at startup. The player adds itself to the group in its own _ready,
## which runs before this node's.
func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null or _player.health_component == null:
		return
	_player.health_component.died.connect(_on_player_died)


func get_state() -> DungeonState:
	return _state


func get_rooms() -> Array[RoomController]:
	return _rooms


func get_current_room_index() -> int:
	return _current_index


func is_run_over() -> bool:
	return _run_ended


func _on_room_started(room: RoomController) -> void:
	if _run_ended:
		return
	_current_index = _rooms.find(room)
	if _state == DungeonState.NOT_STARTED:
		_state = DungeonState.IN_PROGRESS
		dungeon_started.emit()


func _on_room_cleared(room: RoomController) -> void:
	if _run_ended or room != _rooms.back():
		return
	_run_ended = true
	_state = DungeonState.COMPLETED
	if exit_portal != null:
		exit_portal.set_enabled(true)
	print("[Dungeon] " + completion_message)
	dungeon_completed.emit()
	_show_status(completion_message, completion_message_duration)


func _on_player_died() -> void:
	if _run_ended:
		return
	_run_ended = true
	_state = DungeonState.FAILED
	# Stop the run before anything else can react: no room may arm or clear, and
	# the exit must not become usable on the way out.
	for room in _rooms:
		room.suspend()
	if exit_portal != null:
		exit_portal.set_enabled(false)
	print("[Dungeon] " + death_message)
	run_failed.emit()
	_show_status(death_message, 0.0)
	_restart_after_delay()


# Delays use node-bound tweens rather than awaited SceneTreeTimers: a tween dies
# with this node, so leaving the scene before it fires cannot strand a coroutine
# still holding a reference to the label (which leaked ObjectDB instances).
func _restart_after_delay() -> void:
	if _restart_tween != null and _restart_tween.is_running():
		return
	_restart_tween = create_tween()
	_restart_tween.tween_interval(death_restart_delay)
	_restart_tween.tween_callback(_do_restart)


func _do_restart() -> void:
	var transition: SceneTransition = _get_transition()
	if transition != null:
		transition.reload_current_scene()
	else:
		get_tree().reload_current_scene()


## `hold` of 0 keeps the message up until the scene goes away.
func _show_status(message: String, hold: float) -> void:
	if status_label == null:
		return
	if _status_tween != null and _status_tween.is_running():
		_status_tween.kill()
	status_label.text = message
	status_label.visible = true
	if hold <= 0.0:
		return
	_status_tween = create_tween()
	_status_tween.tween_interval(hold)
	_status_tween.tween_callback(_hide_status)


func _hide_status() -> void:
	if status_label != null:
		status_label.visible = false


func _get_transition() -> SceneTransition:
	if _transition != null and is_instance_valid(_transition):
		return _transition
	_transition = get_tree().get_first_node_in_group(SceneTransition.GROUP) as SceneTransition
	return _transition
