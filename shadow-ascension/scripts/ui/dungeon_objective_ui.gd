class_name DungeonObjectiveUI
extends CanvasLayer

## Shows the current objective. Purely a display: inside a dungeon the text is
## computed by DungeonController and arrives through `objective_changed`.
## Not a quest system, and it holds no gameplay logic of its own.
##
## Outside a dungeon there is no controller to ask, so it shows `default_text` —
## which is how the hub says "go through the gate" without a second UI that does
## the same job in a different place.

const GROUP: StringName = &"dungeon_objective_ui"

## Shown when there is no DungeonController above this node. Empty means the UI
## simply stays hidden.
@export var default_text: String = ""

@onready var label: Label = $Root/ObjectiveLabel


func _ready() -> void:
	add_to_group(GROUP)
	var controller: DungeonController = _find_controller()
	if controller == null:
		set_objective(default_text)
		return
	controller.objective_changed.connect(set_objective)
	set_objective(controller.get_objective())


func get_objective() -> String:
	return label.text


func set_objective(text: String) -> void:
	label.text = text
	label.visible = not text.is_empty()


## The controller is this UI's scene root in practice; walk up rather than
## hard-coding a path, so the UI can sit anywhere under it.
func _find_controller() -> DungeonController:
	var node: Node = get_parent()
	while node != null:
		var controller: DungeonController = node as DungeonController
		if controller != null:
			return controller
		node = node.get_parent()
	return null
