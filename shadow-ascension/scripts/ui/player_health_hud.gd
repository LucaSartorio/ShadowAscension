class_name PlayerHealthHUD
extends CanvasLayer

## The player's health, top-left above the level and XP readout.
##
## Its own node rather than another block inside ProgressionHUD: health is not
## progression, and the two are driven by different components. Together they
## make the player status corner; neither knows about the other.
##
## Driven entirely by HealthComponent's `health_changed`, so it never reads
## health per frame. That signal also fires when the ceiling moves, which is how
## a point spent on VIT or a swapped chestpiece reaches the bar without this
## node knowing either system exists.

const GROUP: StringName = &"player_health_hud"

@onready var root: Control = $Root
@onready var bar: ProgressBar = $Root/HealthBar
@onready var label: Label = $Root/HealthLabel

@export var health_format: String = "%d / %d"
## Below this fraction the bar turns, so "nearly dead" reads without the numbers.
@export var low_health_ratio: float = 0.3
@export var healthy_color: Color = Color(0.35, 0.82, 0.38)
@export var low_color: Color = Color(0.9, 0.22, 0.2)

var _health: HealthComponent = null
var _fill: StyleBoxFlat = null


func _ready() -> void:
	add_to_group(GROUP)
	# The style box is shared between instances of a scene, so it is copied
	# before this node ever recolours it.
	var style: StyleBoxFlat = bar.get_theme_stylebox("fill") as StyleBoxFlat
	if style != null:
		_fill = style.duplicate() as StyleBoxFlat
		bar.add_theme_stylebox_override("fill", _fill)
	# One frame: the player comes up in the same scene and its components are
	# not resolved until its own _ready() has run.
	call_deferred("_subscribe")


func _subscribe() -> void:
	var player: Player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	if player == null or player.health_component == null:
		root.visible = false
		return
	_health = player.health_component
	_health.health_changed.connect(_on_health_changed)
	_on_health_changed(_health.current_health, _health.max_health)


func get_health_text() -> String:
	return label.text


func get_ratio() -> float:
	if bar.max_value <= 0.0:
		return 0.0
	return bar.value / bar.max_value


func is_showing() -> bool:
	return root.visible


func _on_health_changed(current: float, maximum: float) -> void:
	bar.max_value = maxf(maximum, 1.0)
	bar.value = clampf(current, 0.0, bar.max_value)
	label.text = health_format % [roundi(current), roundi(maximum)]
	if _fill != null:
		_fill.bg_color = low_color if get_ratio() <= low_health_ratio else healthy_color
