class_name DungeonGate
extends Area3D

## Entry point into a dungeon. Shows a prompt while the player stands inside it
## and answers the `interact` action only then.

signal gate_activated(target_scene: String)

@export_file("*.tscn") var target_scene: String = "res://scenes/dungeons/dungeon_test.tscn"
## When false the gate only announces itself through gate_activated and leaves
## the scene change to whoever is listening.
@export var change_scene_on_activate: bool = true

@onready var prompt: Label3D = $Prompt

var _player_in_range: bool = false


func _ready() -> void:
	if prompt != null:
		prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func is_player_in_range() -> bool:
	return _player_in_range


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if prompt != null:
		prompt.visible = true


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	if prompt != null:
		prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	activate()


## Public so tests and future scene routers can drive the gate directly.
func activate() -> bool:
	if not _player_in_range:
		return false
	gate_activated.emit(target_scene)
	if change_scene_on_activate:
		get_tree().change_scene_to_file(target_scene)
	return true
