class_name InteractionPrompt
extends CanvasLayer

## Contextual "press a key to do a thing" strip at the bottom of the screen.
## One per scene, found through the `interaction_prompt` group — it dies with the
## scene, so a prompt can never survive a transition.
##
## It holds a small stack of everything currently in reach and shows one of them:
## the highest priority, most recently raised. That gives interactables a single
## shared answer to "who does E act on right now", which matters as soon as two
## of them overlap — a dropped item and a shadow remnant from the same corpse, for
## instance. Each one checks `is_current()` before acting, so one key press can
## only ever do one thing, and when the winner goes away the runner-up takes the
## prompt over instead of leaving the player staring at nothing.

const GROUP: StringName = &"interaction_prompt"
## Higher wins. A remnant sits above ordinary loot because it is the rarer, more
## deliberate action of the two.
const PRIORITY_DEFAULT: int = 0
const PRIORITY_SHADOW: int = 10

@onready var root: Control = $Root
@onready var key_label: Label = $Root/Panel/Row/KeyLabel
@onready var text_label: Label = $Root/Panel/Row/TextLabel

## [{ node, key, text, priority }], in the order they were raised.
var _requests: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(GROUP)
	root.visible = false


func is_showing() -> bool:
	return root.visible


func get_text() -> String:
	return text_label.text


## Whether E would act on this node right now. An interactable that is in range
## but not showing must not react.
func is_current(node: Node) -> bool:
	var winner: Dictionary = _winner()
	return not winner.is_empty() and winner["node"] == node


func get_current_owner() -> Node:
	var winner: Dictionary = _winner()
	return winner["node"] if not winner.is_empty() else null


func show_prompt(owner_node: Node, action_key: String, text: String,
		priority: int = PRIORITY_DEFAULT) -> void:
	for request in _requests:
		if request["node"] == owner_node:
			request["key"] = action_key
			request["text"] = text
			request["priority"] = priority
			_redraw()
			return
	_requests.append({
		"node": owner_node, "key": action_key, "text": text, "priority": priority,
	})
	_redraw()


## Takes this node's request out. Whatever else is still in reach takes over, so
## walking off one thing while standing on another does not blank the prompt.
func hide_prompt(owner_node: Node) -> void:
	for i in range(_requests.size() - 1, -1, -1):
		if _requests[i]["node"] == owner_node:
			_requests.remove_at(i)
	_redraw()


## Highest priority, and among equals the most recently raised. Freed nodes are
## dropped on the way, so a prompt cannot outlive the thing that asked for it.
func _winner() -> Dictionary:
	for i in range(_requests.size() - 1, -1, -1):
		if not is_instance_valid(_requests[i]["node"]):
			_requests.remove_at(i)
	var best: Dictionary = {}
	for request in _requests:
		if best.is_empty() or request["priority"] >= best["priority"]:
			best = request
	return best


func _redraw() -> void:
	var winner: Dictionary = _winner()
	if winner.is_empty():
		root.visible = false
		return
	key_label.text = "[%s]" % winner["key"]
	text_label.text = winner["text"]
	root.visible = true


## Convenience for interactables: use the on-screen prompt when the scene has
## one, otherwise fall back to the object's own world label. Kept here so the
## rule lives in one place instead of in every interactable.
static func raise(source: Node, action_key: String, text: String, fallback: Label3D,
		priority: int = PRIORITY_DEFAULT) -> void:
	var ui: InteractionPrompt = _find(source)
	if ui != null:
		ui.show_prompt(source, action_key, text, priority)
	elif fallback != null:
		fallback.visible = true


static func clear(source: Node, fallback: Label3D) -> void:
	var ui: InteractionPrompt = _find(source)
	if ui != null:
		ui.hide_prompt(source)
	if fallback != null:
		fallback.visible = false


## True when E should act on `source`. With no prompt in the scene — a bare test
## bench — everything in range is allowed, which is the old behaviour.
static func should_act(source: Node) -> bool:
	var ui: InteractionPrompt = _find(source)
	return ui == null or ui.is_current(source)


## The key an action is bound to, as the `[KEY] Action` format shows it: read
## from the real InputMap, so a hint cannot drift from the binding. Every hint
## that names a key asks here.
static func key_for(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		var key: InputEventKey = event as InputEventKey
		if key != null:
			return OS.get_keycode_string(
				key.physical_keycode if key.physical_keycode != 0 else key.keycode)
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button != null:
			match button.button_index:
				MOUSE_BUTTON_LEFT:
					return "LMB"
				MOUSE_BUTTON_RIGHT:
					return "RMB"
				MOUSE_BUTTON_MIDDLE:
					return "MMB"
				_:
					return "M%d" % button.button_index
	return "?"


static func _find(source: Node) -> InteractionPrompt:
	return source.get_tree().get_first_node_in_group(GROUP) as InteractionPrompt
