extends Node3D

## Holds the bar's meshes and fades them together.
##
## It also gives every mesh under it its own material copy. Sub-resources are
## shared between instances of a PackedScene, so without this the whole room's
## bars would share one background and fade — and recolour — as one. Doing it
## here, in _ready(), means it has already happened by the time the bar above
## reads the fill material: a child is ready before its parent.

@onready var _label: Label3D = get_node_or_null("Label")


func _ready() -> void:
	_isolate_materials(self)


func modulate_alpha(alpha: float) -> void:
	_set_alpha(self, alpha)
	if _label != null:
		_label.modulate.a = alpha


func _isolate_materials(node: Node) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		var mat: Material = mesh.get_surface_override_material(0)
		if mat != null:
			mesh.set_surface_override_material(0, mat.duplicate())
	for child in node.get_children():
		_isolate_materials(child)


func _set_alpha(node: Node, alpha: float) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = alpha
	for child in node.get_children():
		_set_alpha(child, alpha)
