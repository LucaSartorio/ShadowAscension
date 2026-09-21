class_name ShadowCollectionMenu
extends CanvasLayer

## The shadows the player has torn loose, listed. Opening it pauses the game,
## like the character sheet and the inventory, and closes whichever of those was
## up.
##
## Rows come from PlayerShadowCollection and are rebuilt on `collection_changed`,
## never polled. The one button summons the selected shadow, or takes it back if
## it is already out — the summoner decides what happens, this only labels it.

const GROUP: StringName = &"shadow_collection_menu"
const PAUSE_MENU_GROUP: StringName = &"pause_menu"

@onready var panel_root: Control = $Root
@onready var hint: Control = $Hint
@onready var total_label: Label = $Root/Panel/Content/TotalLabel
@onready var rows: VBoxContainer = $Root/Panel/Content/Rows
@onready var empty_label: Label = $Root/Panel/Content/EmptyLabel
@onready var detail_label: Label = $Root/Panel/Content/Detail
@onready var summon_button: Button = $Root/Panel/Content/SummonButton

@export var total_format: String = "Totale: %d"
@export var empty_text: String = "Nessuna Ombra estratta"
@export var detail_placeholder: String = "Seleziona un'Ombra per i dettagli."
@export var summon_text: String = "[Evoca]"
@export var recall_text: String = "[Richiama]"
## Marks the row that is currently in the world.
@export var active_marker: String = "ATTIVA"
@export var level_format: String = "Livello %d"
@export var xp_format: String = "XP: %d/%d"

var _collection: PlayerShadowCollection = null
var _summoner: PlayerShadowSummoner = null
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
	_summoner = player.shadow_summoner
	if _summoner != null:
		# One redraw per change of who is out, so the marker and the button
		# label follow a summon the player made from anywhere.
		_summoner.active_shadow_changed.connect(_on_active_changed)
	summon_button.pressed.connect(_on_summon_pressed)
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


func get_summon_button_text() -> String:
	return summon_button.text


func is_summon_button_visible() -> bool:
	return summon_button.visible


func press_summon() -> void:
	if summon_button.visible:
		summon_button.pressed.emit()


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
		summon_button.visible = false
		return

	var still_selected: bool = false
	for shadow in shadows:
		var button: Button = Button.new()
		var marker: String = "  %s" % active_marker if _is_active(shadow) else ""
		button.text = "%-10s %s  Lv.%d%s" % [
			shadow.get_short_id(), shadow.get_display_name(), shadow.level, marker]
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
		summon_button.visible = false
		return
	detail_label.text = "\n".join([
		shadow.get_display_name(),
		shadow.get_short_id(),
		level_format % shadow.level,
		xp_format % [shadow.current_xp, shadow.get_xp_to_next_level()],
		"",
		shadow.shadow_data.description if shadow.shadow_data != null else "",
	])
	summon_button.visible = _summoner != null
	summon_button.text = recall_text if _is_active(shadow) else summon_text


func _is_active(shadow: ShadowInstance) -> bool:
	return _summoner != null and _summoner.is_active(shadow.instance_id)


func _on_summon_pressed() -> void:
	if _summoner == null or _selected_id == &"":
		return
	_summoner.toggle(_selected_id)


## The marker lives on every row, so a change of who is out redraws the list
## rather than just the detail pane.
func _on_active_changed(_instance_id: StringName) -> void:
	_refresh()
