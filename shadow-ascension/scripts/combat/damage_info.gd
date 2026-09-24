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
## field is added when a system needs one — a critical flag, a knockback
## direction, a damage type — rather than ahead of it.

## Health this hit removes, as the attacker resolved it.
var amount: float = 0.0
## Whoever dealt it, or null for damage with no attacker. Kill attribution
## reads it: the killing blow's source is who collects.
var source: Node = null
## The attack it came from (`AttackData.id`), or empty when the attacker has no
## named attacks.
var attack_id: StringName = &""


func _init(damage: float = 0.0, dealt_by: Node = null, attack: StringName = &"") -> void:
	amount = damage
	source = dealt_by
	attack_id = attack
