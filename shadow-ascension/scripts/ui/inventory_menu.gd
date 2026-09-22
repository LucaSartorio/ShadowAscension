class_name InventoryMenu
extends CanvasLayer

## What the player is carrying, listed. Opening it pauses the game, exactly like
## the character sheet.
##
## Display and two actions: the rows come from PlayerInventory and the worn
## items from PlayerEquipment, both rebuilt on their own signals and never
## polled. Equipping and unequipping are the components' decisions; this panel
## only asks.
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
@onready var equip_button: Button = $Root/Panel/Content/Actions/EquipButton
@onready var unequip_button: Button = $Root/Panel/Content/Actions/UnequipButton
@onready var equipment_rows: VBoxContainer = $Root/Panel/Content/EquipmentRows

@export var empty_text: String = "Inventario vuoto"
@export var detail_placeholder: String = "Seleziona un oggetto per i dettagli."

var _inventory: PlayerInventory = null
var _equipment: PlayerEquipment = null
var _open: bool = false
var _selected_id: StringName = &""
## Which equipment slot the panel is focused on, or NONE. Selecting a bag row
## clears it and vice versa: one selection at a time, so the two buttons can
## never both be live.
var _selected_slot: ItemData.EquipmentSlot = ItemData.EquipmentSlot.NONE
var last_mouse_mode_request: int = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(PAUSE_MENU_GROUP)
	panel_root.visible = false
	var player: Player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null or player.inventory == null:
		hint.visible = false
		return
	_inventory = player.inventory
	_equipment = player.equipment
	_inventory.inventory_changed.connect(_refresh)
	if _equipment != null:
		_equipment.equipment_changed.connect(_refresh)
	equip_button.pressed.connect(_on_equip_pressed)
	unequip_button.pressed.connect(_on_unequip_pressed)
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


func is_equip_button_visible() -> bool:
	return equip_button.visible


func is_unequip_button_visible() -> bool:
	return unequip_button.visible


func get_equipment_row_text(slot: ItemData.EquipmentSlot) -> String:
	for row in equipment_rows.get_children():
		var button: Button = row as Button
		if button != null and button.text.begins_with(ItemData.slot_label(slot)):
			return button.text
	return ""


## Public so a test can focus a slot without faking a click.
func select_slot(slot: ItemData.EquipmentSlot) -> void:
	_select_slot(slot)


func press_equip() -> bool:
	return _on_equip_pressed()


func press_unequip() -> bool:
	return _on_unequip_pressed()


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
		_refresh_equipment()
		_update_detail()
		return

	_refresh_equipment()
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
	_selected_slot = ItemData.EquipmentSlot.NONE
	_update_detail()


func _select_slot(slot: ItemData.EquipmentSlot) -> void:
	_selected_slot = slot
	_selected_id = &""
	_update_detail()


## The bag row is the thing being equipped, so the item has to come from there.
func _on_equip_pressed() -> bool:
	if _equipment == null or _selected_id == &"":
		return false
	var item: ItemData = _inventory.get_item(_selected_id)
	if item == null or not item.is_equippable():
		return false
	var equipped: bool = _equipment.equip(item)
	if equipped:
		# It has left the bag; focus the slot it went into instead of a row that
		# may no longer exist.
		_select_slot(item.equipment_slot)
	return equipped


func _on_unequip_pressed() -> bool:
	if _equipment == null or _selected_slot == ItemData.EquipmentSlot.NONE:
		return false
	return _equipment.unequip_slot(_selected_slot)


## One row per slot, occupied or not, so an empty slot is still something the
## player can look at and understand.
func _refresh_equipment() -> void:
	for child in equipment_rows.get_children():
		child.queue_free()
		equipment_rows.remove_child(child)
	if _equipment == null:
		return
	for slot in [ItemData.EquipmentSlot.MAIN_HAND, ItemData.EquipmentSlot.CHEST]:
		var worn: ItemData = _equipment.get_equipped_item(slot)
		var button: Button = Button.new()
		button.text = "%-12s %s" % [
			ItemData.slot_label(slot), worn.display_name if worn != null else "Vuoto"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		if worn != null:
			button.add_theme_color_override("font_color", worn.get_rarity_color())
		var captured: ItemData.EquipmentSlot = slot
		button.pressed.connect(func() -> void: _select_slot(captured))
		equipment_rows.add_child(button)


func _update_detail() -> void:
	if _selected_slot != ItemData.EquipmentSlot.NONE:
		_show_slot_detail()
		return
	if _selected_id == &"" or not _inventory.has_item(_selected_id):
		detail_label.text = detail_placeholder
		equip_button.visible = false
		unequip_button.visible = false
		return
	var item: ItemData = _inventory.get_item(_selected_id)
	detail_label.text = _describe(item, _inventory.get_quantity(_selected_id))
	# Only something that can actually be worn offers the button.
	equip_button.visible = item.is_equippable()
	unequip_button.visible = false


func _show_slot_detail() -> void:
	var worn: ItemData = _equipment.get_equipped_item(_selected_slot)
	equip_button.visible = false
	unequip_button.visible = worn != null
	if worn == null:
		detail_label.text = "%s\n\nVuoto." % ItemData.slot_label(_selected_slot)
		return
	detail_label.text = _describe(worn, 1)


func _describe(item: ItemData, quantity: int) -> String:
	var lines: Array[String] = [
		item.display_name,
		"%s · %s · x%d" % [item.get_rarity_label(), item.get_type_label(), quantity],
	]
	if item.is_equippable():
		lines.append(item.get_slot_label())
	var bonuses: Array[String] = item.get_bonus_lines()
	if not bonuses.is_empty():
		lines.append("")
		lines.append_array(bonuses)
	lines.append("")
	lines.append(item.description)
	return "\n".join(lines)
