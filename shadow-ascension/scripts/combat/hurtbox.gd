class_name Hurtbox
extends Area3D

## Whatever does not name a reason of its own.
const DEFAULT_REASON: StringName = &"default"

@export var health_component: HealthComponent
@export var owner_entity: Node

## True while any reason to refuse hits holds. Read-only: set through
## set_invulnerable(), per reason.
var is_invulnerable: bool:
	get:
		return not _invulnerable_reasons.is_empty()

## Why this body is refusing hits right now: a set, so one system ending its own
## invulnerability — a dodge's i-frames running out — can never end another's.
var _invulnerable_reasons: Dictionary[StringName, bool] = {}


func _ready() -> void:
	monitoring = false
	monitorable = true
	if health_component == null:
		var sibling: Node = get_parent().get_node_or_null("HealthComponent")
		health_component = sibling as HealthComponent
	if owner_entity == null:
		owner_entity = get_parent()


func set_invulnerable(value: bool, reason: StringName = DEFAULT_REASON) -> void:
	if value:
		_invulnerable_reasons[reason] = true
	else:
		_invulnerable_reasons.erase(reason)


## The one way into this body's health, and the one place that decides whether a
## hit counts. Whoever sent it — player, shadow, enemy, boss — makes no
## difference here, and the attacker never asks: a refused hit is simply not
## applied, so health does not change and nothing downstream hears of it.
func receive_hit(hit: DamageInfo) -> void:
	if is_invulnerable:
		return
	if health_component == null:
		return
	health_component.take_damage(hit)


func get_owner_entity() -> Node:
	return owner_entity
