class_name PlayerStatsMenu
extends CanvasLayer

## Character sheet: the stats, what spending a point does, and the values those
## stats drive. Opening it pauses the game.
##
## Display and input only — every number shown is computed by PlayerProgression
## and every point spent goes through `allocate_stat()`. No stat logic lives
## here, and nothing is polled: the panel redraws on `stats_changed`.
##
## Runs with PROCESS_MODE_ALWAYS so it still answers input while the tree is
## paused, which is the whole point of pausing from here.

const GROUP: StringName = &"player_stats_menu"
## Every menu that pauses the game joins this, so each can shut the others.
const PAUSE_MENU_GROUP: StringName = &"pause_menu"

@onready var panel_root: Control = $Root
@onready var hint: Control = $Hint
@onready var level_label: Label = $Root/Panel/Content/LevelLabel
@onready var points_label: Label = $Root/Panel/Content/PointsLabel
@onready var derived_label: Label = $Root/Panel/Content/Derived
@onready var rows: VBoxContainer = $Root/Panel/Content/Rows

@export var points_format: String = "Punti disponibili: %d"
@export var level_format: String = "Livello %d"

var _progression: PlayerProgression = null
var _open: bool = false
## The mouse mode last asked for. A headless run silently refuses to capture the
## mouse, so this is what makes the open/close contract checkable there.
var last_mouse_mode_request: int = Input.MOUSE_MODE_CAPTURED
## Button per stat, so enabling and disabling never walks the tree.
var _buttons: Dictionary = {}
var _values: Dictionary = {}
var _splits: Dictionary = {}

const STAT_ROWS: Array = [
	{"key": "STR", "stat": PlayerProgression.Stat.STRENGTH},
	{"key": "AGI", "stat": PlayerProgression.Stat.AGILITY},
	{"key": "VIT", "stat": PlayerProgression.Stat.VITALITY},
	{"key": "INT", "stat": PlayerProgression.Stat.INTELLIGENCE},
]


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(PAUSE_MENU_GROUP)
	panel_root.visible = false
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null or player.progression == null:
		hint.visible = false
		return
	_progression = player.progression
	_build_rows()
	_progression.stats_changed.connect(_refresh)
	if player.equipment != null:
		player.equipment.equipment_changed.connect(_refresh)
	_progression.stat_points_changed.connect(func(_points: int) -> void: _refresh())
	_progression.level_changed.connect(func(_level: int) -> void: _refresh())
	_refresh()


func is_open() -> bool:
	return _open


func get_derived_text() -> String:
	return derived_label.text


func get_points_text() -> String:
	return points_label.text


func get_level_text() -> String:
	return level_label.text


func get_stat_value_text(key: String) -> String:
	return (_values[key] as Label).text if _values.has(key) else ""


func get_stat_split_text(key: String) -> String:
	return (_splits[key] as Label).text if _splits.has(key) else ""


func is_button_disabled(key: String) -> bool:
	return (_buttons[key] as Button).disabled if _buttons.has(key) else true


## Public so a test or a future pause menu can drive it without faking input.
func press_stat(key: String) -> void:
	for row in STAT_ROWS:
		if row["key"] == key:
			_on_plus_pressed(row["stat"])
			return


# --- open / close ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("character_stats"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	# ESC only closes the menu. Left alone while it is shut, so the existing
	# release-the-mouse behaviour is untouched.
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
	if _open or _progression == null:
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


## Whichever pause menu opens last wins, so pressing I with the sheet up swaps
## to the inventory rather than stacking on top of it.
func _close_other_menus() -> void:
	for node in get_tree().get_nodes_in_group(PAUSE_MENU_GROUP):
		if node != self and node.has_method("close"):
			node.close()


func _request_mouse_mode(mode: int) -> void:
	last_mouse_mode_request = mode
	Input.set_mouse_mode(mode)


func _exit_tree() -> void:
	# A scene change while the menu is up must not leave the game paused.
	if _open:
		get_tree().paused = false
		_request_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# --- rows -------------------------------------------------------------------------

func _build_rows() -> void:
	for row in STAT_ROWS:
		var key: String = row["key"]
		var line: HBoxContainer = HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)

		var name_label: Label = Label.new()
		name_label.text = key
		name_label.custom_minimum_size = Vector2(56, 0)
		name_label.add_theme_font_size_override("font_size", 16)
		line.add_child(name_label)

		var value: Label = Label.new()
		value.custom_minimum_size = Vector2(44, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 16)
		line.add_child(value)

		# The split sits beside the total, so a player can tell what they earned
		# from what they are wearing.
		var split: Label = Label.new()
		split.custom_minimum_size = Vector2(96, 0)
		split.add_theme_font_size_override("font_size", 11)
		split.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
		line.add_child(split)

		var spacer: Control = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(spacer)

		var button: Button = Button.new()
		button.text = "+"
		button.custom_minimum_size = Vector2(36, 26)
		button.focus_mode = Control.FOCUS_NONE
		var stat: PlayerProgression.Stat = row["stat"]
		button.pressed.connect(func() -> void: _on_plus_pressed(stat))
		line.add_child(button)

		rows.add_child(line)
		_values[key] = value
		_splits[key] = split
		_buttons[key] = button


## One click, one point. allocate_stat() refuses when there is nothing to spend,
## so a doubled press cannot charge twice or drive a stat negative.
func _on_plus_pressed(stat: PlayerProgression.Stat) -> void:
	if _progression == null:
		return
	_progression.allocate_stat(stat)


func _refresh() -> void:
	if _progression == null:
		return
	level_label.text = level_format % _progression.current_level
	points_label.text = points_format % _progression.available_stat_points
	var spendable: bool = _progression.available_stat_points > 0
	for row in STAT_ROWS:
		var key: String = row["key"]
		var stat: PlayerProgression.Stat = row["stat"]
		var allocated: int = _progression.get_stat(stat)
		var bonus: int = _progression.get_equipment_bonus(stat)
		(_values[key] as Label).text = str(allocated + bonus)
		(_splits[key] as Label).text = "" if bonus == 0 else "%d +%d Equip." % [allocated, bonus]
		(_buttons[key] as Button).disabled = not spendable
	derived_label.text = _derived_text()


## Read live off the player, so the panel shows what the game is actually using
## rather than a second copy of the formulas.
func _derived_text() -> String:
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	var move: float = player.effective_movement_speed if player != null else 0.0
	var dodge: float = player.effective_dodge_speed if player != null else 0.0
	var hp: float = player.health_component.max_health if player != null else 0.0
	return "\n".join([
		"Melee Attack Power  +%d" % roundi(_progression.get_melee_attack_power()),
		"Danno melee        x%.2f" % _progression.get_melee_damage_multiplier(),
		"Velocità           %.2f" % move,
		"Dodge Speed        %.2f" % dodge,
		"HP Massimi         %d" % int(hp),
		"Ability Power      x%.2f" % _progression.get_ability_power_multiplier(),
		"",
		"Ability Power agirà sulle abilità future.",
	])
