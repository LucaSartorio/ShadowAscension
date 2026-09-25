class_name EnemySupportAttack
extends EnemyRangedAttack

## The support archetype's attack (M12.6): its support actions and its offensive
## fallback, through one lifecycle — EnemyAttack's. A heal and a buff are
## AttackData like any attack: their windup is the cast, ACTIVE the moment the
## effect lands, their recovery the commitment after, then the attack cooldown.
##
##     | TELEGRAPH: the cast | effect | ACTIVE | RECOVERY | -> cooldown
##       turned to the ally    once     (EnemySupport.apply_cast())
##
## Which one runs is decided at the start: the action its EnemySupport can cast
## now, if any — else the offence, the ranged archetype's shot (M12.3), the same
## projectile, fired the same way. The support's parts decide what an action is
## for and what it does; this node only runs it:
##   - its telegraph takes the action's colour, and it turns to the ally;
##   - every tick, the cast is dropped — no cooldown, free to choose again — if
##     its ally dies or goes out of reach (EnemySupport.is_cast_valid());
##   - cut off before it lands (a stagger, a death) it is spent: the action waits
##     out its own cooldown (EnemySupport.end_cast()).
## After the effect, a stagger or a death changes nothing: it has landed.

## The support whose actions this runs — wired in the scene, like the ranged
## attack's projectile spawn.
@export var support: EnemySupport = null


## The action to cast now, if the support has one; the offence otherwise.
func select_attack() -> AttackData:
	if support != null:
		var action: AttackData = support.get_castable_action()
		if action != null:
			return action
	return super.select_attack()


func start(attack: AttackData, cooldown_variation: float = 0.0) -> bool:
	if not super.start(attack, cooldown_variation):
		return false
	if _is_casting():
		support.cast_started()
	return true


## A cast turns to its ally; the offence to the foe.
func get_facing_target() -> Node3D:
	if _is_casting():
		return support.get_support_target()
	return super.get_facing_target()


## A support action lands; the offence fires.
func _begin_active() -> bool:
	if support != null and support.is_support_action(_attack):
		return support.apply_cast()
	return super._begin_active()


func _cancel() -> void:
	super._cancel()
	if _is_casting():
		support.end_cast(true)


func _is_still_valid() -> bool:
	if not _is_casting() or support.is_cast_valid():
		return true
	support.end_cast(false)
	return false


func _telegraph_color() -> Color:
	if support != null and support.is_support_action(_attack):
		return support.get_action_color(_attack)
	return super._telegraph_color()


## A support action in its telegraph: cast, not landed yet.
func _is_casting() -> bool:
	return support != null and _phase == Phase.TELEGRAPH and support.is_support_action(_attack)
