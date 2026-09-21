class_name ShadowCollectionMenu
extends CanvasLayer

## The shadows the player has torn loose, listed. Opening it pauses the game,
## like the character sheet and the inventory, and closes whichever of those was
## up.
##
## Display only: rows come from PlayerShadowCollection and are rebuilt on
## `collection_changed`, never polled. There is no Summon button, because
## summoning does not exist yet and a dead control would be a lie.

const GROUP: StringName = &"shadow_collection_menu"
const PAUSE_MENU_GROUP: StringName = &"pause_menu"

@onready var panel_root: Control = $Root
@onready var hint: Control = $Hint
@onready var total_label: Label = $Root/Panel/Content/TotalLabel
@onready var rows: VBoxContainer = $Root/Panel/Content/Rows
@onready var empty_label: Label = $Root/Panel/Content/EmptyLabel
@onready var detail_label: Label = $Root/Panel/Content/Detail

@export var total_format: String = "Totale: %d"
@export var empty_text: String = "Nessuna Ombra estratta"
@export var detail_placeholder: String = "Seleziona un'Ombra per i dettagli."
## Shown under a selected shadow so the empty detail pane is not mistaken for a
## missing feature. No button, because there is nothing to press yet.
@export var summon_note: String = "Evocazione disponibile in una fase successiva."

var _collection: PlayerShadowCollection = null
var _open: bool = false
var _selected_id: StringName = &""
var last_mouse_mode_request: int = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(PAUSE_MENU_GROUP)
	panel_root.visible = false
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null or player.shadows == null:
		hint.visible = false
		return
	_collection = player.shadows
	_collection.collection_changed.connect(_refresh)
	_refresh()


func is_open() -> bool:
	return _open


func get_total_text() -> String:
	return total_label.text


func get_row_count() -> int:
	return rows.get_child_count()


func get_row_text(index: int) -> String:
	if index < 0 or index >= rows.get_child_count():
		return ""
	return (rows.get_child(index) as Button).text


func is_empty_shown() -> bool:
	return empty_label.visible


func get_detail_text() -> String:
	return detail_label.text


func select_row(index: int) -> void:
	if index < 0 or index >= rows.get_child_count():
		return
	(rows.get_child(index) as Button).pressed.emit()


# --- open / close -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shadow_collection"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open or _collection == null:
		return
	_close_other_menus()
	_open = true
	_refresh()
	panel_root.visible = true
	hint.visible = false
	get_tree().paused = true
	_request_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close() -> void:
	if not _open:
		return
	_open = false
	panel_root.visible = false
	hint.visible = true
	get_tree().paused = false
	_request_mouse_mode(Input.MOUSE_MODE_CAPTURED)


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


# --- content --------------------------------------------------------------------------

func _refresh() -> void:
	if _collection == null:
		return
	for child in rows.get_children():
		child.queue_free()
		rows.remove_child(child)

	var shadows: Array[ShadowInstance] = _collection.get_shadows()
	total_label.text = total_format % shadows.size()
	empty_label.visible = shadows.is_empty()
	rows.visible = not shadows.is_empty()
	if shadows.is_empty():
		_selected_id = &""
		detail_label.text = detail_placeholder
		return

	var still_selected: bool = false
	for shadow in shadows:
		var button: Button = Button.new()
		button.text = "%-10s %s" % [shadow.get_short_id(), shadow.get_display_name()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		if shadow.shadow_data != null:
			button.add_theme_color_override("font_color", shadow.shadow_data.accent_color)
		var id: StringName = shadow.instance_id
		button.pressed.connect(func() -> void: _select(id))
		rows.add_child(button)
		if id == _selected_id:
			still_selected = true

	if not still_selected:
		_selected_id = &""
	_update_detail()


func _select(instance_id: StringName) -> void:
	_selected_id = instance_id
	_update_detail()


func _update_detail() -> void:
	var shadow: ShadowInstance = _collection.get_shadow(_selected_id) \
		if _selected_id != &"" else null
	if shadow == null:
		detail_label.text = detail_placeholder
		return
	detail_label.text = "\n".join([
		shadow.get_display_name(),
		shadow.get_short_id(),
		"",
		shadow.shadow_data.description if shadow.shadow_data != null else "",
		"",
		summon_note,
	])
