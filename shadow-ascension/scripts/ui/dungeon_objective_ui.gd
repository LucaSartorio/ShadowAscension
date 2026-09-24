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
	# The dungeon this UI was placed in is its owner — the root of the scene it
	# was saved into. No walk and no lookup; in the hub the owner is not a
	# dungeon, and this is null.
	var controller: DungeonController = owner as DungeonController
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

