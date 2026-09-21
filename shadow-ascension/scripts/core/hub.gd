extends Node3D

## The hub: where a run starts and ends. Player spawn, the gate into the dungeon,
## and a training corner. It bakes its own navigation mesh so the enemies and a
## summoned shadow can path here as they do in the dungeon.

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	if nav_region != null:
		nav_region.bake_navigation_mesh(false)
