class_name DungeonExit
extends Area3D

## Way out of a dungeon. Dead until the run is complete: no collision, no
## prompt, dimmed visual. The DungeonController switches it on.

signal exit_activated(target_scene: String)

@export_file("*.tscn") var target_scene: String = "res://scenes/core/test_world.tscn"
@export var prompt_text: String = "Esci dal Dungeon"
@export var interact_key_label: String = "E"
@export var disabled_color: Color = Color(0.2, 0.22, 0.25)
@export var enabled_color: Color = Color(0.3, 0.9, 0.55)
@export var enable_tween_duration: float = 0.5

@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var visual_root: Node3D = $VisualRoot
@onready var mesh_instance: MeshInstance3D = $VisualRoot/MeshInstance3D
@onready var prompt: Label3D = $Prompt

var _enabled: bool = false
var _used: bool = false
var _player_in_range: bool = false
var _material: StandardMaterial3D = null
var _transition: SceneTransition = null


func _ready() -> void:
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat != null:
		# Sub-resources are shared between instances of a PackedScene.
		_material = mat.duplicate() as StandardMaterial3D
		mesh_instance.set_surface_override_material(0, _material)
	if prompt != null:
		prompt.text = prompt_text
		prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_enabled(false, true)


func is_enabled() -> bool:
	return _enabled


func is_player_in_range() -> bool:
	return _player_in_range


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return
	_apply_enabled(value, false)


func _apply_enabled(value: bool, instant: bool) -> void:
	_enabled = value
	monitoring = value
	collision.set_deferred("disabled", not value)
	if not value:
		# A dead portal must never leave a prompt on screen.
		_player_in_range = false
		InteractionPrompt.clear(self, prompt)
	if _material != null:
		_material.albedo_color = enabled_color if value else disabled_color
		_material.emission_enabled = value
		_material.emission = enabled_color
	var target_scale: Vector3 = Vector3.ONE if value else Vector3(0.6, 0.35, 0.6)
	if instant:
		visual_root.scale = target_scale
		return
	var t: Tween = create_tween()
	t.tween_property(visual_root, "scale", target_scale, enable_tween_duration)


func _on_body_entered(body: Node3D) -> void:
	if not _enabled or not body.is_in_group("player"):
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


## Refuses unless the portal is live, the player is standing in it, it has not
## already been used, and no transition is running. Public so a future router
## can drive it.
func activate() -> bool:
	if not _enabled or not _player_in_range or _used:
		return false
	var transition: SceneTransition = _get_transition()
	if transition != null and transition.is_busy():
		return false
	_used = true
	InteractionPrompt.clear(self, prompt)
	exit_activated.emit(target_scene)
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
