extends Node3D

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	if nav_region != null:
		nav_region.bake_navigation_mesh(false)
