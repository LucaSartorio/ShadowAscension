class_name EnemyMeleeAttack
extends EnemyAttack

## The melee archetype's attack (M12.2): a swing through the hitbox on the
## enemy's body. ACTIVE is the hit window — the hitbox open for AttackData.active
## — and the rest of the lifecycle is EnemyAttack's.
##
## Hits are the hitbox's: one hit per target per swing (its registry, cleared
## on activate()), any number of targets — the player and a shadow in the
## volume are both hit, once each. The enemy's target decides where it goes and
## whether it swings; who is actually hit is decided by the hitbox alone.

## The hit volume the swing opens, on the enemy's body — wired in the scene, so
## M13's model can carry it wherever the weapon is.
@export var hitbox: Hitbox = null


## The hitbox's source is the enemy, and it rests with the basic attack's numbers.
func setup(enemy: CharacterBody3D, targeting: EnemyTargeting, visual_root: Node3D, mesh: MeshInstance3D) -> void:
	super.setup(enemy, targeting, visual_root, mesh)
	if hitbox == null:
		push_warning("%s: its melee attack has no hitbox; its swings will hit nothing." % enemy.name)
		return
	hitbox.source = enemy
	var first: AttackData = select_attack()
	if first != null:
		hitbox.use_attack(first, attack_damage)


## The hit window: the hitbox takes this swing's damage, name and impact, and
## opens. activate() also forgets whom the last swing hit.
func _begin_active() -> bool:
	if hitbox != null:
		hitbox.use_attack(_attack, attack_damage)
		hitbox.activate()
	return true


func _end_active() -> void:
	_close_hit_window()


func _cancel() -> void:
	_close_hit_window()


func _close_hit_window() -> void:
	if hitbox != null and hitbox.is_active():
		hitbox.deactivate()
