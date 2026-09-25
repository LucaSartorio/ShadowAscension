class_name Hitbox
extends Area3D

## A hit landed on `target`, carrying exactly what was sent to its hurtbox —
## whether the hurtbox took it or refused it (i-frames), or it found the target
## already dead.
signal hit_landed(target: Node, hit: DamageInfo)
## The same hit, and it counted: the hurtbox took it and health went down, a
## killing blow included. Emitted right after hit_landed, and only then. Hit
## feedback listens to this one: a refused or pointless hit shows nothing.
signal hit_accepted(target: Node, hit: DamageInfo)

## Below this, a source and its target count as standing in the same place, and
## the hit is pushed the way the hitbox faces instead.
const MIN_DIRECTION_LENGTH_SQUARED: float = 0.0001
## Mixed into the critical generator's seed, apart from every other seeded roll.
const CRITICAL_SEED_SALT: int = 0xC217

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
## The swing's critical chance (0.0 to 1.0) and what a critical multiplies its
## damage by, set with `damage` by an attacker that has them. By default 0 and
## 1.0: an attacker that sets neither — an enemy, the boss, a shadow — never
## crits, and its damage reaches the target exactly as configured.
var critical_chance: float = 0.0
var critical_damage_multiplier: float = 1.0

var _active: bool = false
## Whom this activation has already hit. Per target, not per swing: one swing
## reaches every target in the volume once, and no target twice. Cleared by
## activate(), so each swing starts with nobody hit.
var _hit_targets: Array[Node] = []
var _debug_visual: MeshInstance3D = null
## Rolls this hitbox's criticals, one draw per hit. Seeded from its path, like
## loot drops and shadow extraction, so a run can be reproduced.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(String(get_path())) ^ CRITICAL_SEED_SALT
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


## Takes on `attack`'s hit: its damage — `base_damage` scaled by the attack's
## multiplier — its name and its impact. For an attacker that deals a whole
## AttackData at once: an enemy's swing, a projectile (M12.3).
func use_attack(attack: AttackData, base_damage: float) -> void:
	damage = DamageModel.attack_damage(base_damage, attack.damage_multiplier)
	attack_id = attack.id
	stagger_power = attack.stagger_power
	knockback_force = attack.knockback_force
	set_debug_color(attack.debug_color)


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
	# One roll per hit: every target of the swing rolls on its own.
	var critical: bool = DamageModel.roll_critical(critical_chance, _rng)
	var hit: DamageInfo = DamageInfo.new(
		DamageModel.final_damage(damage, critical, critical_damage_multiplier), source, attack_id)
	hit.is_critical = critical
	hit.stagger_power = stagger_power
	hit.knockback_force = knockback_force
	hit.direction = _direction_to(target_entity)
	var accepted: bool = hurtbox.receive_hit(hit)
	hit_landed.emit(target_entity, hit)
	if accepted:
		hit_accepted.emit(target_entity, hit)


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
