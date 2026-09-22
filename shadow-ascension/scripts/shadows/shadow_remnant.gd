class_name ShadowRemnant
extends Area3D

## What a fallen enemy leaves behind: one chance to tear its shadow loose.
##
## One attempt, ever. The roll happens once, the result is shown briefly, and the
## remnant goes — whether it worked or not. That is the whole point of it being a
## remnant rather than a pickup.
##
## It shares the scene's InteractionPrompt with dropped loot and outranks it, so
## a single press on a corpse that left both acts on exactly one of them.

signal extraction_started
signal extraction_finished(success: bool, shadow: ShadowInstance)

enum State { READY, EXTRACTING, SPENT }

@export var shadow_data: ShadowData
@export var interact_key_label: String = "E"
@export var prompt_text: String = "Estrai Ombra"
## How long the attempt reads as happening before the result lands.
@export var extraction_duration: float = 0.6
## How long the remnant lingers showing the outcome before it goes.
@export var result_duration: float = 1.2
@export var bob_height: float = 0.22
@export var bob_duration: float = 1.6
@export var spin_speed: float = 0.8

@onready var visual_root: Node3D = $VisualRoot
@onready var mesh_instance: MeshInstance3D = $VisualRoot/MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var _state: State = State.READY
var _player_in_range: bool = false
var _material: StandardMaterial3D = null
## Fixed so a run is reproducible; mixed with the remnant's own path so two
## remnants in one room do not share an outcome.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(String(get_path())) ^ 0x5EED
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_tint()
	_start_bob()


func configure(data: ShadowData) -> void:
	shadow_data = data


func get_state() -> State:
	return _state


func is_spent() -> bool:
	return _state == State.SPENT


func has_been_attempted() -> bool:
	return _state != State.READY


func is_player_in_range() -> bool:
	return _player_in_range


func get_prompt_text() -> String:
	return prompt_text


func _apply_tint() -> void:
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	# Sub-resources are shared between instances of a PackedScene.
	_material = mat.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _material)
	if shadow_data != null:
		_material.albedo_color = shadow_data.accent_color
		_material.emission = shadow_data.accent_color


func _start_bob() -> void:
	var base_y: float = visual_root.position.y
	var t: Tween = create_tween().set_loops()
	t.tween_property(visual_root, "position:y", base_y + bob_height, bob_duration * 0.5)
	t.tween_property(visual_root, "position:y", base_y, bob_duration * 0.5)


func _process(delta: float) -> void:
	visual_root.rotation.y += spin_speed * delta


# --- interaction ---------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if _state != State.READY or not body.is_in_group(Player.GROUP):
		return
	_player_in_range = true
	InteractionPrompt.raise(self, interact_key_label, prompt_text, null,
		InteractionPrompt.PRIORITY_SHADOW)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group(Player.GROUP):
		return
	_player_in_range = false
	InteractionPrompt.clear(self, null)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	# Consumed on success. Acting also releases the prompt, which the next
	# interactable in range would inherit within this same frame — so without
	# this one press would reach two of them.
	if attempt_extraction():
		get_viewport().set_input_as_handled()


## Public so tests and a future router can drive it. Refuses everything after the
## first call: the prompt comes down and the state leaves READY before the roll,
## so a second press during the attempt cannot start another.
func attempt_extraction() -> bool:
	if _state != State.READY or not _player_in_range or shadow_data == null:
		return false
	# Loot dropped by the same corpse may be underfoot; only the prompt's owner
	# acts, so one press does one thing.
	if not InteractionPrompt.should_act(self):
		return false

	_state = State.EXTRACTING
	_player_in_range = false
	InteractionPrompt.clear(self, null)
	collision.set_deferred("disabled", true)
	extraction_started.emit()
	_show_feedback_processing()

	# The roll happens once, here, and nothing re-enters this function.
	var success: bool = _rng.randf() < shadow_data.extraction_chance
	# A node-bound timer, so leaving the scene mid-attempt strands nothing.
	var t: Tween = create_tween()
	t.tween_interval(extraction_duration)
	t.tween_callback(func() -> void: _resolve(success))
	return true


func _resolve(success: bool) -> void:
	_state = State.SPENT
	var shadow: ShadowInstance = null
	if success:
		var collection: PlayerShadowCollection = _find_collection()
		if collection != null:
			shadow = collection.add_shadow(shadow_data)
	_show_feedback_result(success, shadow)
	extraction_finished.emit(success, shadow)

	if _material != null:
		_material.emission_energy_multiplier = 0.15
	var t: Tween = create_tween()
	t.tween_interval(result_duration)
	t.tween_callback(queue_free)


func _find_collection() -> PlayerShadowCollection:
	var player: Player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	return player.shadows if player != null else null


func _feedback() -> ExtractionFeedback:
	return get_tree().get_first_node_in_group(ExtractionFeedback.GROUP) as ExtractionFeedback


func _show_feedback_processing() -> void:
	var ui: ExtractionFeedback = _feedback()
	if ui != null:
		ui.show_processing()


func _show_feedback_result(success: bool, shadow: ShadowInstance) -> void:
	var ui: ExtractionFeedback = _feedback()
	if ui != null:
		ui.show_result(success, shadow, result_duration)
