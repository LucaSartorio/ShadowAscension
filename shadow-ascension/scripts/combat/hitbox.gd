class_name Hitbox
extends Area3D

signal hit_landed(target: Node, damage: float)

@export var damage: float = 25.0
@export var source: Node = null

var _active: bool = false
var _hit_targets: Array[Node] = []
var _debug_visual: MeshInstance3D = null


func _ready() -> void:
	monitoring = false
	monitorable = true
	area_entered.connect(_on_area_entered)
	_debug_visual = get_node_or_null("DebugMesh") as MeshInstance3D
	if _debug_visual != null:
		_debug_visual.visible = false
		if _debug_visual.material_override != null:
			_debug_visual.material_override = _debug_visual.material_override.duplicate()


func set_debug_color(color: Color) -> void:
	if _debug_visual == null:
		return
	var mat: StandardMaterial3D = _debug_visual.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = color


func activate() -> void:
	if _active:
		return
	_active = true
	_hit_targets.clear()
	monitoring = true
	if _debug_visual != null:
		_debug_visual.visible = true


func deactivate() -> void:
	if not _active:
		return
	_active = false
	monitoring = false
	if _debug_visual != null:
		_debug_visual.visible = false


func is_active() -> bool:
	return _active


func _on_area_entered(area: Area3D) -> void:
	if not _active:
		return
	var hurtbox: Hurtbox = area as Hurtbox
	if hurtbox == null:
		return
	var target_entity: Node = hurtbox.get_owner_entity()
	if target_entity == null:
		return
	if target_entity == source:
		return
	if target_entity in _hit_targets:
		return
	_hit_targets.append(target_entity)
	hurtbox.receive_hit(damage, source)
	hit_landed.emit(target_entity, damage)
