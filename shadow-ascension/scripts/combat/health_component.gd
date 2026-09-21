class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
signal died
## Same moment as `died`, but carrying whoever dealt the final blow. Separate
## rather than an argument on `died` so every existing listener keeps working.
signal died_from(source: Node)

@export var max_health: float = 100.0

var current_health: float = 0.0
var is_dead: bool = false
## Whoever dealt the last damage, or null. This component only records it — what
## a kill is worth, and who collects, is decided elsewhere. It knows nothing
## about XP.
var last_damage_source: Node = null


func _ready() -> void:
	current_health = max_health


func receive_damage(amount: float, source: Node = null) -> void:
	if is_dead:
		return
	if amount <= 0.0:
		return
	last_damage_source = source
	current_health = max(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		is_dead = true
		died.emit()
		died_from.emit(source)


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
