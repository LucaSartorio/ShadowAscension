class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
## A hit took health and left this alive: what a hit reaction listens to. Emitted
## after health_changed, and never with died — a killing blow is a death, not a
## hit to react to.
signal damaged(hit: DamageInfo)
## Who dealt the final blow is `last_damage_source`, read at this moment by the
## owner — a combatant passes it to RoomCombatant.report_death().
signal died

@export var max_health: float = 100.0

var current_health: float = 0.0
var is_dead: bool = false
## The last hit taken, or null. This component only records it — what a kill is
## worth, and who collects, is decided elsewhere. It knows nothing about XP.
var last_damage: DamageInfo = null
## Whoever dealt the last hit, or null: the part of it kill attribution reads.
var last_damage_source: Node:
	get:
		return last_damage.source if last_damage != null else null


func _ready() -> void:
	current_health = max_health


## The only place health goes down. Every hit arrives here the same way,
## whoever dealt it. True when it took health — a killing blow included — and
## false when there was nothing to take it from or nothing to take: dead
## already, no hit, no damage.
func take_damage(hit: DamageInfo) -> bool:
	if is_dead or hit == null:
		return false
	if hit.amount <= 0.0:
		return false
	last_damage = hit
	current_health = max(0.0, current_health - hit.amount)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		is_dead = true
		died.emit()
		return true
	damaged.emit(hit)
	return true


## Changes the ceiling without healing: current health is only ever clamped down
## to the new maximum, never topped up. Generic on purpose — this component knows
## nothing about what raised the ceiling.
func set_max_health(value: float) -> void:
	if value <= 0.0 or is_equal_approx(value, max_health):
		return
	max_health = value
	current_health = minf(current_health, max_health)
	health_changed.emit(current_health, max_health)


## Sets the ceiling and fills to it.
##
## For an entity that learns its maximum only after this component has already
## readied at whatever its scene happened to carry: this node fills to
## `max_health` in its own _ready(), which runs BEFORE its parent's, so a parent
## that later writes `max_health` alone leaves the thing standing at the old
## number. Raising a boss from 600 to 900 in its stats asset did exactly that —
## it started the fight at 600 of 900.
func reset_to(maximum: float) -> void:
	if maximum <= 0.0:
		return
	max_health = maximum
	current_health = maximum
	is_dead = false
	last_damage = null
	health_changed.emit(current_health, max_health)


func heal(amount: float) -> void:
	if is_dead:
		return
	if amount <= 0.0:
		return
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)
