class_name WorldItem
extends Area3D

## A dropped item lying on the floor, waiting to be picked up.
##
## Interaction reuses the existing InteractionPrompt — there is no second
## interaction system. The pickup itself is the inventory's decision: this node
## offers, the inventory accepts what it can, and the drop only disappears once
## nothing is left.

signal picked_up(item: ItemData, quantity: int)

@export var item: ItemData
@export var quantity: int = 1
@export var interact_key_label: String = "E"
## "[E] Raccogli Monster Fragment x3"
@export var prompt_format: String = "Raccogli %s"
@export var prompt_stack_format: String = "Raccogli %s x%d"
@export var bob_height: float = 0.18
@export var bob_duration: float = 1.1
@export var spin_speed: float = 1.2

@onready var visual_root: Node3D = $VisualRoot
@onready var mesh_instance: MeshInstance3D = $VisualRoot/MeshInstance3D
@onready var collision: CollisionShape3D = $CollisionShape3D

var _player_in_range: bool = false
var _claimed: bool = false
var _material: StandardMaterial3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_rarity()
	_start_bob()


## Called right after instancing, before the node is added to the tree, so the
## visual is correct on its very first frame.
func configure(source: ItemData, amount: int) -> void:
	item = source
	quantity = maxi(1, amount)


func get_prompt_text() -> String:
	if item == null:
		return ""
	if quantity > 1:
		return prompt_stack_format % [item.display_name, quantity]
	return prompt_format % item.display_name


func is_player_in_range() -> bool:
	return _player_in_range


func _apply_rarity() -> void:
	if item == null:
		return
	var mat: StandardMaterial3D = mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	# Sub-resources are shared between instances of a PackedScene.
	_material = mat.duplicate() as StandardMaterial3D
	mesh_instance.set_surface_override_material(0, _material)
	var colour: Color = item.get_rarity_color()
	_material.albedo_color = colour
	_material.emission_enabled = true
	_material.emission = colour


## Bob and spin so a drop is findable on a grey floor. Node-bound tweens, so
## leaving the scene mid-bob cannot strand anything.
func _start_bob() -> void:
	var base_y: float = visual_root.position.y
	var t: Tween = create_tween().set_loops()
	t.tween_property(visual_root, "position:y", base_y + bob_height, bob_duration * 0.5)
	t.tween_property(visual_root, "position:y", base_y, bob_duration * 0.5)


func _process(delta: float) -> void:
	visual_root.rotation.y += spin_speed * delta


func _on_body_entered(body: Node3D) -> void:
	if _claimed or not body.is_in_group("player"):
		return
	_player_in_range = true
	InteractionPrompt.raise(self, interact_key_label, get_prompt_text(), null)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	InteractionPrompt.clear(self, null)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	# Consumed on success, so one press cannot also reach whatever inherits the
	# prompt when this item releases it.
	if pick_up():
		get_viewport().set_input_as_handled()


## Public so tests and a future router can drive it. Takes only what the
## inventory accepts: a full stack leaves the remainder on the floor rather than
## quietly destroying it.
func pick_up() -> bool:
	if _claimed or not _player_in_range or item == null:
		return false
	# Another interactable may be overlapping this one — a shadow remnant from
	# the same corpse, typically. Only whoever holds the prompt acts.
	if not InteractionPrompt.should_act(self):
		return false
	var inventory: PlayerInventory = _find_inventory()
	if inventory == null:
		return false
	var accepted: int = inventory.add_item(item, quantity)
	if accepted <= 0:
		return false
	quantity -= accepted
	picked_up.emit(item, accepted)
	if quantity > 0:
		# Partially taken: the prompt has to show what is still down there.
		InteractionPrompt.raise(self, interact_key_label, get_prompt_text(), null)
		return true
	_claimed = true
	_player_in_range = false
	InteractionPrompt.clear(self, null)
	collision.set_deferred("disabled", true)
	queue_free()
	return true


func _find_inventory() -> PlayerInventory:
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	return player.inventory if player != null else null
