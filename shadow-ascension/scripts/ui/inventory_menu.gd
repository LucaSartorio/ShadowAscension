class_name InventoryMenu
extends CanvasLayer

## What the player is carrying, listed. Opening it pauses the game, exactly like
## the character sheet.
##
## Display only: the rows come from PlayerInventory and are rebuilt on
## `inventory_changed`, never polled. No Equip button — equipping arrives in
## M7.2 and there is nothing here to press until then.
##
## Only one pause menu is ever open. Opening this one closes the other, so C and
## I always do what they say instead of stacking panels.

const GROUP: StringName = &"inventory_menu"
## Every menu that pauses the game joins this, so each can shut the others.
const PAUSE_MENU_GROUP: StringName = &"pause_menu"

@onready var panel_root: Control = $Root
@onready var hint: Control = $Hint
@onready var rows: VBoxContainer = $Root/Panel/Content/Rows
@onready var empty_label: Label = $Root/Panel/Content/EmptyLabel
@onready var detail_label: Label = $Root/Panel/Content/Detail

@export var empty_text: String = "Inventario vuoto"
@export var detail_placeholder: String = "Seleziona un oggetto per i dettagli."

var _inventory: PlayerInventory = null
var _open: bool = false
var _selected_id: StringName = &""
var last_mouse_mode_request: int = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(PAUSE_MENU_GROUP)
	panel_root.visible = false
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null or player.inventory == null:
		hint.visible = false
		return
	_inventory = player.inventory
	_inventory.inventory_changed.connect(_refresh)
	_refresh()


func is_open() -> bool:
	return _open


func get_row_count() -> int:
	return rows.get_child_count()


func is_empty_shown() -> bool:
	return empty_label.visible


func get_row_text(index: int) -> String:
	if index < 0 or index >= rows.get_child_count():
		return ""
	return (rows.get_child(index) as Button).text


func get_detail_text() -> String:
	return detail_label.text


## Public so a test can select without faking a click.
func select_row(index: int) -> void:
	if index < 0 or index >= rows.get_child_count():
		return
	(rows.get_child(index) as Button).pressed.emit()


# --- open / close -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
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
	if _open or _inventory == null:
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


## Whichever pause menu opens last wins, so pressing C with the inventory up
## swaps to the character sheet rather than stacking on top of it.
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


# --- content ------------------------------------------------------------------------

func _refresh() -> void:
	if _inventory == null:
		return
	for child in rows.get_children():
		child.queue_free()
		rows.remove_child(child)

	var entries: Array[Dictionary] = _inventory.get_entries()
	empty_label.visible = entries.is_empty()
	rows.visible = not entries.is_empty()
	if entries.is_empty():
		_selected_id = &""
		detail_label.text = detail_placeholder
		return

	var still_selected: bool = false
	for entry in entries:
		var item: ItemData = entry["item"]
		var button: Button = Button.new()
		button.text = "%-22s x%-4d %-11s %s" % [
			item.display_name, entry["quantity"], item.get_rarity_label(), item.get_type_label()]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_color_override("font_color", item.get_rarity_color())
		var id: StringName = entry["id"]
		button.pressed.connect(func() -> void: _select(id))
		rows.add_child(button)
		if id == _selected_id:
			still_selected = true

	if not still_selected:
		_selected_id = &""
	_update_detail()


func _select(id: StringName) -> void:
	_selected_id = id
	_update_detail()


func _update_detail() -> void:
	if _selected_id == &"" or not _inventory.has_item(_selected_id):
		detail_label.text = detail_placeholder
		return
	var item: ItemData = _inventory.get_item(_selected_id)
	detail_label.text = "\n".join([
		item.display_name,
		"%s · %s · x%d" % [
			item.get_rarity_label(), item.get_type_label(),
			_inventory.get_quantity(_selected_id)],
		"",
		item.description,
	])
