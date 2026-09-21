class_name ProgressionHUD
extends CanvasLayer

## Level and XP readout, bottom-left, plus the level-up callout.
##
## Pure display, driven entirely by PlayerProgression's signals — it never polls
## and never reads progression state per frame. Deliberately not an HUD
## framework: M6.2 owns the real stat screen.

const GROUP: StringName = &"progression_hud"

@onready var root: Control = $Root
@onready var level_label: Label = $Root/LevelLabel
@onready var xp_bar: ProgressBar = $Root/XPBar
@onready var xp_label: Label = $Root/XPLabel
## Separate from the standing readout so a momentary callout and the permanent
## numbers never fight over one node.
@onready var banner: Label = $Banner

@export var banner_duration: float = 1.8
@export var level_format: String = "LV. %d"
@export var xp_format: String = "%d / %d"
@export var max_level_text: String = "MAX"
## Level reached, then the points it paid.
@export var level_up_format: String = "SALITO DI LIVELLO!\n\nLivello %d\n\n+%d Punti Statistica"

var _progression: PlayerProgression = null
var _banner_tween: Tween = null


func _ready() -> void:
	add_to_group(GROUP)
	banner.visible = false
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player == null or player.progression == null:
		root.visible = false
		return
	_progression = player.progression
	_progression.xp_changed.connect(_on_xp_changed)
	_progression.level_changed.connect(_on_level_changed)
	_progression.level_up.connect(_on_level_up)
	_refresh()


func get_level_text() -> String:
	return level_label.text


func get_xp_text() -> String:
	return xp_label.text


func get_xp_ratio() -> float:
	if xp_bar.max_value <= 0.0:
		return 1.0
	return xp_bar.value / xp_bar.max_value


func is_banner_showing() -> bool:
	return banner.visible


func get_banner_text() -> String:
	return banner.text


func _refresh() -> void:
	if _progression == null:
		return
	_on_level_changed(_progression.current_level)
	_on_xp_changed(_progression.current_xp, _progression.get_xp_to_next_level())


func _on_level_changed(level: int) -> void:
	level_label.text = level_format % level


## Called after every level-up too, so the bar shows the XP carried over rather
## than staying full.
func _on_xp_changed(current: int, required: int) -> void:
	if required <= 0:
		xp_bar.max_value = 1.0
		xp_bar.value = 1.0
		xp_label.text = max_level_text
		return
	xp_bar.max_value = required
	xp_bar.value = current
	xp_label.text = xp_format % [current, required]


func _on_level_up(level: int, points_gained: int) -> void:
	banner.text = level_up_format % [level, points_gained]
	if _banner_tween != null and _banner_tween.is_running():
		_banner_tween.kill()
	banner.visible = true
	banner.modulate.a = 1.0
	# Node-bound, so leaving the scene mid-callout cannot strand a coroutine.
	_banner_tween = create_tween()
	_banner_tween.tween_interval(banner_duration)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.35)
	_banner_tween.tween_callback(func() -> void: banner.visible = false)
