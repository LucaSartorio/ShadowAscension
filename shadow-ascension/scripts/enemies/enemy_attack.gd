class_name EnemyAttack
extends Node

## An enemy archetype's attack (M12.2; the shared base since M12.3): what the
## enemy attacks with, and the attack under way — the one owner of both. The
## enemy's state machine decides WHEN to attack (ATTACK, from CHASE or
## REPOSITION); the attack decides WHAT the attack is and runs it:
##
##     | TELEGRAPH (AttackData.windup) | ACTIVE (.active) | RECOVERY (.recovery) | -> over
##       nothing can hit yet             the attack's effect   committed            cooldown starts
##       facing tracks, then locks       facing locked         facing locked
##
## What ACTIVE *is* belongs to the archetype, and is all a subclass writes: a
## melee opens the hitbox on its body for the window (EnemyMeleeAttack), a ranged
## fires a projectile as it begins (EnemyRangedAttack). The lifecycle, the
## cooldown, the desync, the facing rule and the telegraph's look are here, once.
##
## Recovery is the attack's own commitment, part of it; the cooldown is the gap
## after it before the next may start, and it runs whatever the enemy is doing.
## An attack is timed on delta alone — no clip, no callback — so it always ends;
## M14's clips will be timed to it, not the other way round.
##
## Attacks are AttackData, the same resource as the player's: `id`,
## `damage_multiplier` on the archetype's base damage, `windup` / `active` /
## `recovery`, `stagger_power` / `knockback_force`, `debug_color` — and, for a
## ranged attack, its projectile. The player-only fields — combo windows, dodge
## cancel, movement, hit feedback — are not read here.
##
## Shared configuration, never written: every enemy of an archetype reads the
## same EnemyData and AttackData. What an attack is doing — its phase, its clock,
## the cooldown left — is this node's, one per enemy.

enum Phase { NONE, TELEGRAPH, ACTIVE, RECOVERY }

# Configuration, copied from the archetype's EnemyData by configure().
## The archetype's attacks, the first its basic one.
var attacks: Array[AttackData] = []
## What every attack's damage_multiplier scales.
var attack_damage: float = 0.0
## Seconds after an attack before the next may start.
var attack_cooldown: float = 0.0
## Share of the enemy's rotation speed it may turn at during the telegraph.
var telegraph_turn_fraction: float = 0.0
## Seconds before ACTIVE when the facing locks: from there the attack goes where
## it was aimed.
var telegraph_facing_lock: float = 0.0
var telegraph_color: Color = Color.WHITE
var active_color: Color = Color.WHITE
var startup_scale: Vector3 = Vector3.ONE
var active_scale: Vector3 = Vector3.ONE

# Handed over by the enemy in setup().
## The enemy this attack belongs to: the source of its hits.
var _enemy: CharacterBody3D = null
var _targeting: EnemyTargeting = null
var _visual_root: Node3D = null
var _body_material: StandardMaterial3D = null
var _base_albedo: Color = Color.WHITE

var _phase: Phase = Phase.NONE
var _phase_remaining: float = 0.0
## The attack under way; null while none is.
var _attack: AttackData = null
## The cooldown after the attack under way, fixed when it starts.
var _cooldown_after: float = 0.0
var _cooldown_remaining: float = 0.0
## The desync a group starts with: no attack before this has run out.
var _hold_off_remaining: float = 0.0
var _telegraph_tween: Tween = null
var _started: int = 0
var _withheld: int = 0


## Copies what this archetype attacks with from its data. Called by the enemy
## while it seeds itself, so the attack and the enemy read the same asset once.
## A subclass copies its own fields too, after this.
func configure(source: EnemyData) -> void:
	attacks = source.attacks.duplicate()
	attack_damage = source.attack_damage
	attack_cooldown = source.attack_cooldown
	telegraph_turn_fraction = source.telegraph_turn_fraction
	telegraph_facing_lock = source.telegraph_facing_lock
	telegraph_color = source.telegraph_color
	active_color = source.active_color
	startup_scale = source.startup_scale
	active_scale = source.active_scale
	if attacks.is_empty() or attacks[0] == null:
		push_warning("%s: its EnemyData has no attacks; it will never attack." % get_parent().name)


## Called once by the enemy with what the attack works with: the enemy itself
## (the source of its hits), its target's owner, the visual root it scales for
## the telegraph and the mesh whose colour it tints. The mesh's material is
## duplicated here — a PackedScene shares it between instances, and without its
## own copy every enemy would telegraph at once. A subclass takes its own parts
## — wired in the scene — after this.
func setup(enemy: CharacterBody3D, targeting: EnemyTargeting, visual_root: Node3D, mesh: MeshInstance3D) -> void:
	_enemy = enemy
	_targeting = targeting
	_visual_root = visual_root
	if mesh == null:
		return
	var mat: StandardMaterial3D = mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	_body_material = mat.duplicate() as StandardMaterial3D
	mesh.set_surface_override_material(0, _body_material)
	_base_albedo = _body_material.albedo_color


# --- queries ------------------------------------------------------------------------

## The attack the next one will be. One attack for now, the archetype's first;
## choosing between several is where a heavier swing or a special will go.
func select_attack() -> AttackData:
	return attacks[0] if not attacks.is_empty() else null


func get_phase() -> Phase:
	return _phase


func is_attacking() -> bool:
	return _phase != Phase.NONE


## The attack under way, or null.
func get_current_attack() -> AttackData:
	return _attack


## Seconds left in the current phase; 0 while not attacking.
func get_phase_remaining() -> float:
	return _phase_remaining


func get_cooldown_remaining() -> float:
	return _cooldown_remaining


## Whether an attack may start as far as the attack is concerned: none under
## way, off cooldown, past the desync, and something to attack with. Range,
## facing and sight are the enemy's to judge.
func is_ready() -> bool:
	return _phase == Phase.NONE and _cooldown_remaining <= 0.0 and _hold_off_remaining <= 0.0 \
		and select_attack() != null


## How much of its rotation speed the enemy may turn at now: the fraction early
## in the telegraph, nothing in its last telegraph_facing_lock seconds, nor in
## ACTIVE or RECOVERY — the attack is committed where it was aimed.
func get_turn_factor() -> float:
	if _phase == Phase.TELEGRAPH and _phase_remaining > telegraph_facing_lock:
		return telegraph_turn_fraction
	return 0.0


## How many attacks this enemy has started — telegraphs shown.
func get_swing_count() -> int:
	return _started


## How many attacks ended at the end of their telegraph because ACTIVE could not
## begin (a ranged shot with nothing clear to fire at).
func get_withheld_count() -> int:
	return _withheld


# --- the attack -----------------------------------------------------------------------

## Starts `attack`: the telegraph. `cooldown_variation` is the instance's own
## desync of the cooldown after it.
func start(attack: AttackData, cooldown_variation: float = 0.0) -> bool:
	if attack == null or _phase != Phase.NONE:
		return false
	_attack = attack
	_cooldown_after = attack_cooldown + cooldown_variation
	_started += 1
	_enter_phase(Phase.TELEGRAPH, attack.windup)
	_telegraph_startup()
	return true


## Runs the attack on; true on the tick it is over — the phase dropped and, if
## it went through, the cooldown started.
func advance(delta: float) -> bool:
	if _phase == Phase.NONE:
		return false
	_phase_remaining -= delta
	if _phase_remaining > 0.0:
		return false
	match _phase:
		Phase.TELEGRAPH:
			if not _begin_active():
				# Nothing to do it at: the attack ends here, with no cooldown — the
				# enemy is free to put itself where it can.
				_withheld += 1
				_end_attack()
				return true
			_enter_phase(Phase.ACTIVE, _attack.active)
			_telegraph_active()
		Phase.ACTIVE:
			_end_active()
			_enter_phase(Phase.RECOVERY, _attack.recovery)
			_telegraph_recovery()
		Phase.RECOVERY:
			_enter_phase(Phase.NONE, 0.0)
			_attack = null
			_cooldown_remaining = _cooldown_after
			return true
	return false


## Cuts the attack off wherever it is: whatever ACTIVE had open is shut at once,
## the phase dropped, the telegraph undone. No cooldown: what cut it off (a
## stagger, a death, a lost target) is delay enough. What an attack already let
## loose — a projectile in flight — is not the attack's any more, and flies on.
func interrupt() -> void:
	_cancel()
	_end_attack()


## Runs down the cooldown and the desync. Called by the enemy's own tick, while
## it is awake.
func tick(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _hold_off_remaining > 0.0:
		_hold_off_remaining = maxf(0.0, _hold_off_remaining - delta)


## No attack before `seconds` have passed: a group's desync, set when a fight is
## picked up.
func hold_off(seconds: float) -> void:
	_hold_off_remaining = maxf(0.0, seconds)


## Nothing under way and nothing pending: no attack, no cooldown, no desync. For
## an enemy the room parks — or a test resetting one.
func reset() -> void:
	interrupt()
	_cooldown_remaining = 0.0
	_hold_off_remaining = 0.0


func _enter_phase(phase: Phase, duration: float) -> void:
	_phase = phase
	_phase_remaining = duration


func _end_attack() -> void:
	_enter_phase(Phase.NONE, 0.0)
	_attack = null
	_reset_telegraph_instantly()


# --- what ACTIVE is: the archetype's ------------------------------------------------------

## The telegraph is over: ACTIVE begins. False when it cannot — the attack is then
## withheld and ends without a cooldown.
func _begin_active() -> bool:
	return true


## ACTIVE is over, by its time.
func _end_active() -> void:
	pass


## The attack is cut off, in any phase: shut whatever ACTIVE opened.
func _cancel() -> void:
	pass


# --- the telegraph (PLACEHOLDER until M14's clips) --------------------------------------
#
# The body rears up and takes the telegraph's colour through the telegraph,
# lunges in the active colour, and settles back through the recovery. Only the
# look: every timing above is the attack's own.

func _kill_telegraph_tween() -> void:
	if _telegraph_tween != null and _telegraph_tween.is_running():
		_telegraph_tween.kill()


func _telegraph_startup() -> void:
	_tween_look(startup_scale, telegraph_color, maxf(0.05, _attack.windup * 0.85))


func _telegraph_active() -> void:
	_tween_look(active_scale, active_color, maxf(0.03, _attack.active * 0.5))


func _telegraph_recovery() -> void:
	_tween_look(Vector3.ONE, _base_albedo, maxf(0.08, _attack.recovery * 0.6))


func _tween_look(scale: Vector3, color: Color, duration: float) -> void:
	if _visual_root == null:
		return
	_kill_telegraph_tween()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(_visual_root, "scale", scale, duration)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", color, duration)


func _reset_telegraph_instantly() -> void:
	_kill_telegraph_tween()
	if _visual_root != null:
		_visual_root.scale = Vector3.ONE
	if _body_material != null:
		_body_material.albedo_color = _base_albedo
