class_name Hurtbox
extends Area3D

@export var health_component: HealthComponent
@export var owner_entity: Node


func _ready() -> void:
	monitoring = false
	monitorable = true
	if health_component == null:
		var sibling: Node = get_parent().get_node_or_null("HealthComponent")
		health_component = sibling as HealthComponent
	if owner_entity == null:
		owner_entity = get_parent()


func receive_hit(amount: float, _source: Node) -> void:
	if health_component == null:
		return
	health_component.receive_damage(amount)


func get_owner_entity() -> Node:
	return owner_entity
