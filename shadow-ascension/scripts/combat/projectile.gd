class_name Projectile
extends Node3D

## A shot in flight (M12.3). Launched with a source, a direction and the attack
## it belongs to, it flies straight — never turning after anything — at the
## attack's speed until it hits something or its lifetime runs out, and then it
## is gone:
##
##     launch() -> flies (_physics_process) -> a hit that counts   -> gone
##                                          -> world geometry       -> gone
##                                          -> projectile_lifetime  -> gone
##
## Its hit is its Hitbox's, the same component a swing uses: the same DamageInfo
## through Hurtbox.receive_hit() — the receiver decides, i-frames included, and
## the projectile never asks — the same source filtering, the same one hit per
## target, criticals and all. It knows nothing of the player, the shadow, the HUD
## or the dungeon: what it may hit is its hitbox's collision mask.
##
## A hit the receiver refuses — a dodge's i-frames — does not end it: the body
## was not there to be hit, and the shot flies on through it (and cannot hit it
## again: the hitbox's registry). Anything else it touches on the world layer — a
## wall, the floor, a door — stops it.
##
## All of it is runtime and this node's own: where it is, where it goes, what is
## left of its life, whom it hit. The AttackData it was fired with is only read.
## It lives under the scene it was fired into, so a scene change takes it along.

## It is over: `reason` is &"hit" (a hit that counted), &"world" (it struck the
## world) or &"lifetime" (it flew out its life). Emitted once, just before it
## frees itself.
signal finished(reason: StringName)

const REASON_HIT: StringName = &"hit"
const REASON_WORLD: StringName = &"world"
const REASON_LIFETIME: StringName = &"lifetime"

@onready var hitbox: Hitbox = $Hitbox

var _direction: Vector3 = Vector3.ZERO
var _speed: float = 0.0
var _lifetime_remaining: float = 0.0
var _launched: bool = false
var _finished: bool = false


func _ready() -> void:
	hitbox.hit_accepted.connect(_on_hit_accepted)
	hitbox.body_entered.connect(_on_body_entered)


## Sends it off from where it stands: along `direction`, dealing `attack`'s hit
## with `base_damage` as its base, on behalf of `source`. Called once, right after
## it is added to the scene and placed.
func launch(source: Node, direction: Vector3, attack: AttackData, base_damage: float) -> void:
	if _launched:
		return
	_launched = true
	_direction = direction.normalized()
	_speed = attack.projectile_speed
	_lifetime_remaining = attack.projectile_lifetime
	hitbox.source = source
	hitbox.use_attack(attack, base_damage)
	# The shooter may die and be freed while this flies; the shot is its own by
	# then, and keeps no reference to something gone.
	if source != null:
		source.tree_exiting.connect(_on_source_gone, CONNECT_ONE_SHOT)
	hitbox.activate()


func get_direction() -> Vector3:
	return _direction


func get_speed() -> float:
	return _speed


func get_lifetime_remaining() -> float:
	return _lifetime_remaining


func is_finished() -> bool:
	return _finished


func _physics_process(delta: float) -> void:
	if not _launched or _finished:
		return
	global_position += _direction * (_speed * delta)
	_lifetime_remaining -= delta
	if _lifetime_remaining <= 0.0:
		_finish(REASON_LIFETIME)


func _on_hit_accepted(_target: Node, _hit: DamageInfo) -> void:
	_finish(REASON_HIT)


func _on_body_entered(_body: Node3D) -> void:
	_finish(REASON_WORLD)


func _on_source_gone() -> void:
	hitbox.source = null


func _finish(reason: StringName) -> void:
	if _finished:
		return
	_finished = true
	hitbox.deactivate()
	finished.emit(reason)
	queue_free()
