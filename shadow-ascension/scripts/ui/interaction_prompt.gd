class_name InteractionPrompt
extends CanvasLayer

## Contextual "press a key to do a thing" strip at the bottom of the screen.
## One per scene, found through the `interaction_prompt` group — it dies with the
## scene, so a prompt can never survive a transition.
##
## Ownership is explicit: whoever shows a prompt must be the one to hide it, so
## two overlapping interactables cannot clear each other's text.

const GROUP: StringName = &"interaction_prompt"

@onready var root: Control = $Root
@onready var key_label: Label = $Root/Panel/Row/KeyLabel
@onready var text_label: Label = $Root/Panel/Row/TextLabel

var _owner_node: Node = null


func _ready() -> void:
	add_to_group(GROUP)
	root.visible = false


func is_showing() -> bool:
	return root.visible


func get_text() -> String:
	return text_label.text


func show_prompt(owner_node: Node, action_key: String, text: String) -> void:
	_owner_node = owner_node
	key_label.text = "[%s]" % action_key
	text_label.text = text
	root.visible = true


## Only the node that raised the prompt may take it down.
func hide_prompt(owner_node: Node) -> void:
	if _owner_node != null and _owner_node != owner_node:
		return
	_owner_node = null
	root.visible = false


## Convenience for interactables: use the on-screen prompt when the scene has
## one, otherwise fall back to the object's own world label. Kept here so the
## rule lives in one place instead of in every interactable.
static func raise(source: Node, action_key: String, text: String, fallback: Label3D) -> void:
	var ui: InteractionPrompt = source.get_tree().get_first_node_in_group(GROUP) as InteractionPrompt
	if ui != null:
		ui.show_prompt(source, action_key, text)
	elif fallback != null:
		fallback.visible = true


static func clear(source: Node, fallback: Label3D) -> void:
	var ui: InteractionPrompt = source.get_tree().get_first_node_in_group(GROUP) as InteractionPrompt
	if ui != null:
		ui.hide_prompt(source)
	if fallback != null:
		fallback.visible = false
