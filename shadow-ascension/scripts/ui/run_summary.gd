class_name RunSummary
extends CanvasLayer

## What the run amounted to, shown once the dungeon is finished.
##
## Display only. Every number comes from DungeonRunStats, which counted them as
## they happened; this node computes nothing and keeps nothing.
##
## It pauses rather than changing scene: dismissing it leaves the player in the
## dungeon, free to walk to the exit portal in their own time.

const GROUP: StringName = &"run_summary"
const PAUSE_MENU_GROUP: StringName = &"pause_menu"

@onready var root: Control = $Root
@onready var title_label: Label = $Root/Panel/Content/Title
@onready var lines_label: Label = $Root/Panel/Content/Lines
@onready var continue_button: Button = $Root/Panel/Content/ContinueButton

@export var title_text: String = "DUNGEON COMPLETATO"
@export var enemies_format: String = "Nemici sconfitti: %d"
@export var bosses_format: String = "Boss sconfitti: %d"
@export var xp_format: String = "XP ottenuta: %d"
@export var items_format: String = "Oggetti raccolti: %d"
@export var shadows_format: String = "Ombre estratte: %d"

var _stats: DungeonRunStats = null
var _open: bool = false
var last_mouse_mode_request: int = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	add_to_group(GROUP)
	root.visible = false
	continue_button.pressed.connect(close)
	# The dungeon this UI was placed in is its owner — the root of the scene it
	# was saved into. No walk and no lookup; in the hub the owner is not a
	# dungeon, and this is null.
	var controller: DungeonController = owner as DungeonController
	if controller == null:
		return
	_stats = controller.get_run_stats()
	if _stats != null:
		# The kill that ends the run and the tally of it are two handlers on the
		# same signal, and nothing decides their order — so the panel follows the
		# tally rather than reading it once and hoping it was last.
		_stats.stats_changed.connect(_refresh)
	controller.dungeon_completed.connect(open)


func is_open() -> bool:
	return _open


func get_title() -> String:
	return title_label.text


func get_lines() -> String:
	return lines_label.text


func open() -> void:
	if _open:
		return
	_open = true
	_close_other_menus()
	_refresh()
	# Again next frame, once every other handler on the completing kill has run.
	call_deferred("_refresh")
	root.visible = true
	get_tree().paused = true
	_request_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	continue_button.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	root.visible = false
	get_tree().paused = false
	_request_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func press_continue() -> void:
	close()


## Dismisses whichever summary is up, if any, and says whether there was one.
## The dungeon is paused while it is open, so anything that drives the game
## without a player — a headless flow, a scripted demo — has to do what the
## player would do before it can carry on.
static func dismiss_open(tree: SceneTree) -> bool:
	for node in tree.get_nodes_in_group(GROUP):
		var summary: RunSummary = node as RunSummary
		if summary != null and summary.is_open():
			summary.press_continue()
			return true
	return false


func _input(event: InputEvent) -> void:
	if not _open:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo \
			and key.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if not is_inside_tree():
		return
	title_label.text = title_text
	if _stats == null:
		lines_label.text = ""
		return
	lines_label.text = "\n".join([
		enemies_format % _stats.enemies_defeated,
		bosses_format % _stats.bosses_defeated,
		"",
		xp_format % _stats.get_player_xp_earned(),
		items_format % _stats.items_picked_up,
		shadows_format % _stats.shadows_extracted,
	])


## Anything else that had the screen gives way: two panels over each other, one
## of them paused, is how a player ends up unable to dismiss either.
func _close_other_menus() -> void:
	for node in get_tree().get_nodes_in_group(PAUSE_MENU_GROUP):
		if node != self and node.has_method("close"):
			node.close()


func _request_mouse_mode(mode: int) -> void:
	last_mouse_mode_request = mode
	Input.set_mouse_mode(mode)


func _exit_tree() -> void:
	if _open:
		get_tree().paused = false
		_request_mouse_mode(Input.MOUSE_MODE_CAPTURED)

