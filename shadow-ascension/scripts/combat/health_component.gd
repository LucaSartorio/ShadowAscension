class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
signal died

@export var max_health: float = 100.0

var current_health: float = 0.0
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health


func receive_damage(amount: float) -> void:
	if is_dead:
		return
	if amount <= 0.0:
		return
	current_health = max(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		is_dead = true
		died.emit()


## Changes the ceiling without healing: current health is only ever clamped down
## to the new maximum, never topped up. Generic on purpose — this component knows
## nothing about what raised the ceiling.
func set_max_health(value: float) -> void:
	if value <= 0.0 or is_equal_approx(value, max_health):
		return
	max_health = value
	current_health = minf(current_health, max_health)
	health_changed.emit(current_health, max_health)


func heal(amount: float) -> void:
	if is_dead:
		return
	if amount <= 0.0:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)
