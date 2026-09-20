class_name DungeonObjectiveUI
extends CanvasLayer

## Shows the dungeon's current objective, top-left. Purely a display: the text is
## computed by DungeonController and arrives through `objective_changed`.
## Not a quest system, and it holds no gameplay logic of its own.

const GROUP: StringName = &"dungeon_objective_ui"

@onready var label: Label = $Root/ObjectiveLabel


func _ready() -> void:
	add_to_group(GROUP)
	var controller: DungeonController = _find_controller()
	if controller == null:
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
