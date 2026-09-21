class_name DungeonGate
extends Area3D

## Entry point into a dungeon. Shows a prompt while the player stands inside it
## and answers the `interact` action only then.
##
## Nothing about this scene is dungeon-specific: duplicate it and point
## `target_scene` somewhere else.

signal gate_activated(target_scene: String)

@export_file("*.tscn") var target_scene: String = "res://scenes/dungeons/dungeon_test.tscn"
@export var prompt_text: String = "Entra nel Gate"
@export var interact_key_label: String = "E"
## When false the gate only announces itself through gate_activated and leaves
## the scene change to whoever is listening.
@export var change_scene_on_activate: bool = true

@export_group("Presentation")
## The gate is the one thing in the hub the player must find, so it moves and
## breathes rather than sitting there as another coloured box.
@export var spin_speed_degrees: float = 26.0
@export var pulse_period: float = 2.4
@export var pulse_energy_low: float = 1.6
@export var pulse_energy_high: float = 3.2

@onready var prompt: Label3D = $Prompt
@onready var visual_root: Node3D = $VisualRoot
@onready var gate_light: OmniLight3D = $GateLight

var _player_in_range: bool = false
var _used: bool = false
var _transition: SceneTransition = null


func _ready() -> void:
	if prompt != null:
		prompt.text = prompt_text
		prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_start_idle_animation()


## A slow spin and a slow pulse, on tweens bound to this node so leaving the
## scene cannot strand them. Presentation only — nothing here is read back.
func _start_idle_animation() -> void:
	if gate_light != null:
		var pulse: Tween = create_tween()
		pulse.set_loops()
		pulse.tween_property(gate_light, "light_energy", pulse_energy_high,
			pulse_period * 0.5).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(gate_light, "light_energy", pulse_energy_low,
			pulse_period * 0.5).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if visual_root != null:
		visual_root.rotation.y += deg_to_rad(spin_speed_degrees) * delta


func is_player_in_range() -> bool:
	return _player_in_range


func _on_body_entered(body: Node3D) -> void:
	if _used or not body.is_in_group("player"):
		return
	_player_in_range = true
	InteractionPrompt.raise(self, interact_key_label, prompt_text, prompt)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	InteractionPrompt.clear(self, prompt)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	activate()


## Refuses unless the player is standing in the gate, it has not already been
## used, and no transition is running — so holding or spamming E cannot queue a
## second scene load. Public so tests and a future router can drive it.
func activate() -> bool:
	if _used or not _player_in_range:
		return false
	var transition: SceneTransition = _get_transition()
	if transition != null and transition.is_busy():
		return false
	_used = true
	InteractionPrompt.clear(self, prompt)
	gate_activated.emit(target_scene)
	if not change_scene_on_activate:
		return true
	if transition != null:
		transition.transition_to_scene(target_scene)
	else:
		get_tree().change_scene_to_file(target_scene)
	return true


func _get_transition() -> SceneTransition:
	if _transition != null and is_instance_valid(_transition):
		return _transition
	_transition = get_tree().get_first_node_in_group(SceneTransition.GROUP) as SceneTransition
	return _transition
