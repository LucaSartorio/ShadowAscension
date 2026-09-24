class_name Hitbox
extends Area3D

## A hit landed on `target`, carrying exactly what was sent to its hurtbox.
signal hit_landed(target: Node, hit: DamageInfo)

## Below this, a source and its target count as standing in the same place, and
## the hit is pushed the way the hitbox faces instead.
const MIN_DIRECTION_LENGTH_SQUARED: float = 0.0001

@export var damage: float = 25.0
@export var source: Node = null
## The attack this hitbox is dealing for, stamped on every hit it lands. Set by
## the attacker with `damage`, before activate(); empty for attackers with no
## named attacks.
var attack_id: StringName = &""
## What each hit of this swing carries into its target's reaction, set with
## `damage` by an attacker whose attacks have them; 0 — the default — for one
## whose attacks do not (enemies, the boss, shadows).
var stagger_power: float = 0.0
var knockback_force: float = 0.0

var _active: bool = false
## Whom this activation has already hit. Per target, not per swing: one swing
## reaches every target in the volume once, and no target twice. Cleared by
## activate(), so each swing starts with nobody hit.
var _hit_targets: Array[Node] = []
var _debug_visual: MeshInstance3D = null


func _ready() -> void:
	monitoring = false
	monitorable = true
	area_entered.connect(_on_area_entered)
	_debug_visual = get_node_or_null("DebugMesh") as MeshInstance3D
	if _debug_visual != null:
		_debug_visual.visible = false
		if _debug_visual.material_override != null:
			_debug_visual.material_override = _debug_visual.material_override.duplicate()


func set_debug_color(color: Color) -> void:
	if _debug_visual == null:
		return
	var mat: StandardMaterial3D = _debug_visual.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = color


func activate() -> void:
	if _active:
		return
	_active = true
	_hit_targets.clear()
	monitoring = true
	if _debug_visual != null:
		_debug_visual.visible = true


func deactivate() -> void:
	if not _active:
		return
	_active = false
	# Deferred because this can be reached from inside a physics signal: a hit
	# that kills the player runs area_entered -> receive_hit -> died -> the room
	# suspending its combatants, which deactivates whatever was mid-swing. Godot
	# blocks a direct write to `monitoring` there. `_active` is already false, and
	# _on_area_entered refuses on that, so nothing can land in the deferred frame.
	set_deferred("monitoring", false)
	if _debug_visual != null:
		_debug_visual.visible = false


func is_active() -> bool:
	return _active


func _on_area_entered(area: Area3D) -> void:
	if not _active:
		return
	var hurtbox: Hurtbox = area as Hurtbox
	if hurtbox == null:
		return
	var target_entity: Node = hurtbox.get_owner_entity()
	if target_entity == null:
		return
	if target_entity == source:
		return
	if target_entity in _hit_targets:
		return
	_hit_targets.append(target_entity)
	var hit: DamageInfo = DamageInfo.new(damage, source, attack_id)
	hit.stagger_power = stagger_power
	hit.knockback_force = knockback_force
	hit.direction = _direction_to(target_entity)
	hurtbox.receive_hit(hit)
	hit_landed.emit(target_entity, hit)


## From the attacker to the target, flat: the way a push goes. When the two
## overlap, the way this hitbox faces — the swing's own direction — rather than
## an arbitrary world axis.
func _direction_to(target: Node) -> Vector3:
	var target_3d: Node3D = target as Node3D
	if target_3d == null:
		return Vector3.ZERO
	var origin: Vector3 = global_position
	if source is Node3D and is_instance_valid(source):
		origin = (source as Node3D).global_position
	var away: Vector3 = target_3d.global_position - origin
	away.y = 0.0
	if away.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		away = -global_basis.z
		away.y = 0.0
	if away.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		return Vector3.ZERO
	return away.normalized()
