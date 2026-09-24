class_name DamageInfo
extends RefCounted

## One hit, as it travels from whoever dealt it to whatever took it:
##
##     Hitbox -> Hurtbox.receive_hit() -> HealthComponent.take_damage()
##
## The receiving side never asks who is hitting it. Player, shadow, enemy and
## boss all send this, and a health component reacts to it the same way.
##
## Deliberately small: it carries what something downstream reads today, and a
## field is added when a system needs one — a critical flag, a damage type —
## rather than ahead of it. M11.6 added the three a hit reaction reads: how hard
## the hit tries to interrupt its target, how hard it pushes, and which way.

## Health this hit removes, as the attacker resolved it.
var amount: float = 0.0
## Whoever dealt it, or null for damage with no attacker. Kill attribution
## reads it: the killing blow's source is who collects.
var source: Node = null
## The attack it came from (`AttackData.id`), or empty when the attacker has no
## named attacks.
var attack_id: StringName = &""
## How hard this hit tries to interrupt what its target is doing. The target
## compares it with its own resistance; 0 never staggers.
var stagger_power: float = 0.0
## How fast this hit pushes its target away, in m/s, before the target's own
## multiplier; 0 pushes nothing.
var knockback_force: float = 0.0
## Which way the hit travelled, flat on the ground and of length 1: from whoever
## dealt it to whatever it landed on, fixed at impact so nothing has to reach
## back to an attacker that may be gone by then. Zero when there is no telling.
var direction: Vector3 = Vector3.ZERO


func _init(damage: float = 0.0, dealt_by: Node = null, attack: StringName = &"") -> void:
	amount = damage
	source = dealt_by
	attack_id = attack
