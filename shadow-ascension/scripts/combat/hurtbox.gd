class_name Hurtbox
extends Area3D

@export var health_component: HealthComponent
@export var owner_entity: Node

var is_invulnerable: bool = false


func _ready() -> void:
	monitoring = false
	monitorable = true
	if health_component == null:
		var sibling: Node = get_parent().get_node_or_null("HealthComponent")
		health_component = sibling as HealthComponent
	if owner_entity == null:
		owner_entity = get_parent()


func set_invulnerable(value: bool) -> void:
	is_invulnerable = value


## The one way into this body's health. Whoever sent the hit — player, shadow,
## enemy, boss — makes no difference here.
func receive_hit(hit: DamageInfo) -> void:
	if is_invulnerable:
		return
	if health_component == null:
		return
	health_component.take_damage(hit)


func get_owner_entity() -> Node:
	return owner_entity
