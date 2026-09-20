class_name EnemyHealthBar3D
extends Node3D

## World-space health bar above an enemy. Two unshaded quads and a small label,
## turned to face the camera — no CanvasLayer and no viewport per enemy.
##
## It never reads health per frame: it redraws on `health_changed` and hides on
## `died`. The only per-frame work is facing the camera, and that stops whenever
## the bar is hidden.
##
## The boss deliberately does not use this. It has its own dedicated bar, and a
## second world-space one would only compete with it.

## Above this fraction, and out of combat, the bar stays out of the way.
const FULL_EPSILON: float = 0.001

@export var health_component: HealthComponent
## Anything that reports whether it is fighting, via `engagement_changed`.
## Resolved from the parent when left unset.
@export var combatant: Node
@export var health_bar_height_offset: float = 2.25
@export var bar_width: float = 1.1
@export var fade_duration: float = 0.18
@export var show_numbers: bool = true

@onready var pivot: Node3D = $Pivot
@onready var background: MeshInstance3D = $Pivot/Background
@onready var fill_pivot: Node3D = $Pivot/FillPivot
@onready var fill: MeshInstance3D = $Pivot/FillPivot/Fill
@onready var label: Label3D = $Pivot/Label

var _ratio: float = 1.0
var _engaged: bool = false
var _dead: bool = false
var _fill_material: StandardMaterial3D = null
var _fade_tween: Tween = null
var _camera: Camera3D = null


func _ready() -> void:
	position.y = health_bar_height_offset
	if health_component == null:
		health_component = get_parent().get_node_or_null("HealthComponent") as HealthComponent
	if combatant == null:
		combatant = get_parent()
	# The pivot already gave every mesh its own material copy in its own _ready,
	# which runs before this one.
	_fill_material = fill.get_surface_override_material(0) as StandardMaterial3D
	if health_component != null:
		health_component.health_changed.connect(_on_health_changed)
		health_component.died.connect(_on_died)
		_ratio = 1.0 if health_component.max_health <= 0.0 \
			else health_component.current_health / health_component.max_health
	if combatant != null and combatant.has_signal("engagement_changed"):
		combatant.engagement_changed.connect(_on_engagement_changed)
	_redraw()
	_apply_visibility(true)


func is_bar_visible() -> bool:
	return pivot.visible


func get_ratio() -> float:
	return _ratio


# --- data ------------------------------------------------------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	_ratio = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	if show_numbers:
		label.text = "%d / %d" % [roundi(current), roundi(maximum)]
	_redraw()
	_apply_visibility(false)


func _on_engagement_changed(engaged: bool) -> void:
	_engaged = engaged
	_apply_visibility(false)


func _on_died() -> void:
	_dead = true
	_apply_visibility(true)


func _redraw() -> void:
	# The quad is centred, so shrinking it also has to shift it left to stay
	# anchored: a bar that shrank towards its middle would read as two bars.
	fill_pivot.scale.x = maxf(_ratio, 0.0001)
	fill_pivot.position.x = -bar_width * (1.0 - _ratio) * 0.5
	if _fill_material != null:
		_fill_material.albedo_color = _colour_for(_ratio)


## Green through amber to red, so "nearly dead" reads at a glance across a room
## rather than needing the numbers.
func _colour_for(ratio: float) -> Color:
	if ratio > 0.5:
		return Color(0.35, 0.82, 0.38).lerp(Color(0.95, 0.78, 0.25), (1.0 - ratio) * 2.0)
	return Color(0.95, 0.78, 0.25).lerp(Color(0.9, 0.22, 0.2), (0.5 - ratio) * 2.0)


# --- visibility ------------------------------------------------------------------

## Hidden at full health out of combat, shown once the enemy is fighting or hurt,
## gone the moment it dies.
func _should_be_visible() -> bool:
	if _dead:
		return false
	return _engaged or _ratio < 1.0 - FULL_EPSILON


func _apply_visibility(instant: bool) -> void:
	var wanted: bool = _should_be_visible()
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	set_process(wanted)
	if instant or fade_duration <= 0.0:
		pivot.visible = wanted
		pivot.modulate_alpha(1.0 if wanted else 0.0)
		return
	if wanted:
		pivot.visible = true
		pivot.modulate_alpha(0.0)
		_fade_tween = create_tween()
		_fade_tween.tween_method(pivot.modulate_alpha, 0.0, 1.0, fade_duration)
		return
	_fade_tween = create_tween()
	_fade_tween.tween_method(pivot.modulate_alpha, 1.0, 0.0, fade_duration)
	_fade_tween.tween_callback(func() -> void: pivot.visible = false)


# --- facing ----------------------------------------------------------------------

## Only runs while the bar is on screen; set_process() is driven by visibility.
func _process(_delta: float) -> void:
	var camera: Camera3D = _get_camera()
	if camera == null:
		return
	var to_camera: Vector3 = camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.0001:
		return
	pivot.global_rotation.y = atan2(to_camera.x, to_camera.z)


func _get_camera() -> Camera3D:
	if _camera != null and is_instance_valid(_camera):
		return _camera
	_camera = get_viewport().get_camera_3d()
	return _camera
