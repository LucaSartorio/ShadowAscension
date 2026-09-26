class_name BossCombat
extends Node

## A boss's attacks (M12.8): which one it uses next, and the one under way — the
## single owner of both. The boss's state machine decides WHEN (its DECIDE state,
## and only there); this decides WHAT, and runs it:
##
##     NONE -> TELEGRAPH (windup) -> ACTIVE (hit window) -> RECOVERY -> NONE
##                                     | a multi-hit attack:
##                                     +-> BETWEEN_HITS -> ACTIVE (again) ...
##
## - The attack under way is `_attack`, and its place in it `_phase`: nothing
##   else records it — no name, no index, no flag beside them.
## - A choice is made among the attacks the phase offers that are valid: its
##   hitbox exists, its own cooldown is over, the target is within its range
##   band, and it has not already run max_consecutive_repeats times in a row.
##   Among those, weighted by BossAttack.weight, from a seeded generator, so a
##   run can be reproduced.
## - Each attack has its own cooldown, started when it starts; the phase's tempo
##   scales its windup, recovery and cooldown. All of it is this node's, one per
##   boss: the BossAttack and AttackData assets are only read.
## - Timed on delta alone — no Timer, no callback — so a cancelled attack leaves
##   nothing behind to fire later.
##
## Damage is the standard pipeline: each attack's hitbox takes its AttackData
## (Hitbox.use_attack() — the boss's base damage times the attack's multiplier,
## its stagger and push) and sends the same DamageInfo as any swing; the target's
## hurtbox decides, i-frames included.
##
## The wind-up's look is here too (PLACEHOLDER until M14): each telegraph shape
## deforms a different channel of the mesh, and the body takes the attack's
## colour.

## An attack began its telegraph.
signal attack_started(attack: BossAttack)
## The attack under way ended: `completed` after its recovery, false when it was
## cut off (a stagger, a transition, a death, the room parking the boss).
signal attack_ended(attack: BossAttack, completed: bool)

enum Phase { NONE, TELEGRAPH, ACTIVE, BETWEEN_HITS, RECOVERY }

## PLACEHOLDER looks: how far each telegraph shape deforms the mesh, and how
## quickly the body settles after an attack.
const LEAN_DEGREES: float = -22.0
const RECOIL_DEGREES: float = 14.0
const RECOIL_BACK: float = 0.45
const COMPRESS_SCALE: Vector3 = Vector3(1.35, 0.55, 1.35)
const RECOIL_SCALE: Vector3 = Vector3(0.78, 1.22, 0.78)
const REWIND_BACK: float = 0.5
const REWIND_SCALE: Vector3 = Vector3(0.7, 1.3, 0.7)
const REWIND_COLOR: Color = Color(1.0, 1.0, 0.85)
const SETTLE_TIME: float = 0.25

# Handed over by the boss in setup().
var _boss: CharacterBody3D = null
var _mesh_root: Node3D = null
var _body_material: StandardMaterial3D = null
var _max_repeats: int = 1
var _base_damage: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Per attack: its hitbox, and the seconds before it may be chosen again.
var _hitboxes: Dictionary = {}
var _cooldowns: Dictionary = {}

## The attack under way, or null; where it is.
var _attack: BossAttack = null
var _phase: Phase = Phase.NONE
var _phase_remaining: float = 0.0
var _hits_done: int = 0
## The tempo it started with: its phase's, fixed for the whole attack.
var _tempo: float = 1.0

# Repeat history.
var _last: BossAttack = null
var _consecutive: int = 0

## Reused, so a choice allocates nothing.
var _candidates: Array[BossAttack] = []
var _resting_color: Color = Color.WHITE
var _telegraph_tween: Tween = null
var _started: int = 0
## How many times the valid attacks have been gathered — once per decision.
var _evaluations: int = 0


## Called once by the boss with what its attacks work with: its body (the source
## of every hit), the node its hitboxes hang under, the mesh its telegraphs
## deform and the body material they tint, every attack any of its phases
## offers, its base damage, its repeat ceiling and the seed of its choices.
func setup(boss: CharacterBody3D, origins: Node3D, mesh_root: Node3D, body_material: StandardMaterial3D,
		all_attacks: Array[BossAttack], base_damage: float, max_repeats: int, decision_seed: int) -> void:
	_boss = boss
	_mesh_root = mesh_root
	_body_material = body_material
	_resting_color = body_material.albedo_color if body_material != null else Color.WHITE
	_max_repeats = maxi(1, max_repeats)
	_base_damage = base_damage
	_rng.seed = decision_seed
	_hitboxes.clear()
	_cooldowns.clear()
	for attack in all_attacks:
		if attack == null or _cooldowns.has(attack):
			continue
		var hitbox: Hitbox = origins.get_node_or_null(String(attack.hitbox_name)) as Hitbox if origins != null else null
		if hitbox == null:
			push_warning("%s: attack '%s' has no hitbox named %s; it will never be chosen." % [
				boss.name, attack.get_id(), attack.hitbox_name])
		else:
			hitbox.source = boss
			hitbox.use_attack(attack.attack, base_damage)
		_hitboxes[attack] = hitbox
		_cooldowns[attack] = 0.0


# --- queries ------------------------------------------------------------------------

func get_phase() -> Phase:
	return _phase


func is_attacking() -> bool:
	return _phase != Phase.NONE


## The attack under way, or null.
func get_current_attack() -> BossAttack:
	return _attack


func get_phase_remaining() -> float:
	return _phase_remaining


## Swings the attack under way has delivered.
func get_hits_done() -> int:
	return _hits_done


func get_cooldown(attack: BossAttack) -> float:
	return _cooldowns.get(attack, 0.0)


func get_hitbox(attack: BossAttack) -> Hitbox:
	return _hitboxes.get(attack, null)


## Every hitbox the boss's attacks swing.
func get_hitboxes() -> Array[Hitbox]:
	var out: Array[Hitbox] = []
	for hitbox in _hitboxes.values():
		if hitbox != null:
			out.append(hitbox)
	return out


func is_hit_window_open() -> bool:
	for hitbox in _hitboxes.values():
		if hitbox != null and (hitbox as Hitbox).is_active():
			return true
	return false


## Attacks started — telegraphs shown.
func get_started_count() -> int:
	return _started


## How many times a choice has been weighed. Only the boss's DECIDE asks, so
## this stands still through a telegraph, a swing, a recovery or a transition.
func get_evaluation_count() -> int:
	return _evaluations


## Share of the boss's rotation speed it may turn at now: the attack's facing
## correction in the telegraph, its between-hits fraction between two swings,
## nothing while a hit window is open or in recovery.
func get_turn_fraction() -> float:
	if _attack == null:
		return 0.0
	match _phase:
		Phase.TELEGRAPH:
			return _attack.facing_correction_fraction
		Phase.BETWEEN_HITS:
			return _attack.between_hits_facing_fraction
	return 0.0


# --- choosing ----------------------------------------------------------------------

## Whether any attack of `pool` could start at `distance` from the target.
func has_choice(pool: Array[BossAttack], distance: float) -> bool:
	_collect(pool, distance)
	return not _candidates.is_empty()


## The attack to use now, among the valid ones of `pool`, by weight — or null
## when none is valid. Draws from the generator only when there is a choice.
func choose(pool: Array[BossAttack], distance: float) -> BossAttack:
	_collect(pool, distance)
	if _candidates.is_empty():
		return null
	var total: float = 0.0
	for attack in _candidates:
		total += maxf(0.0, attack.weight)
	if total <= 0.0:
		return _candidates[_rng.randi_range(0, _candidates.size() - 1)]
	var roll: float = _rng.randf() * total
	for attack in _candidates:
		roll -= maxf(0.0, attack.weight)
		if roll <= 0.0:
			return attack
	return _candidates[_candidates.size() - 1]


func _collect(pool: Array[BossAttack], distance: float) -> void:
	_evaluations += 1
	_candidates.clear()
	for attack in pool:
		if attack == null or _hitboxes.get(attack, null) == null:
			continue
		if _cooldowns.get(attack, 0.0) > 0.0:
			continue
		if distance < attack.min_range or distance > attack.max_range:
			continue
		if attack == _last and _consecutive >= _max_repeats:
			continue
		_candidates.append(attack)


# --- the attack -----------------------------------------------------------------------

## Starts `attack` at `tempo` (its phase's): its telegraph, and its cooldown.
func start(attack: BossAttack, tempo: float) -> bool:
	if attack == null or _phase != Phase.NONE:
		return false
	_attack = attack
	_tempo = tempo
	_consecutive = _consecutive + 1 if attack == _last else 1
	_last = attack
	_cooldowns[attack] = attack.cooldown * tempo
	_hits_done = 0
	_started += 1
	_enter(Phase.TELEGRAPH, attack.attack.windup * tempo)
	_play_telegraph()
	attack_started.emit(attack)
	return true


## Runs the attack on; true on the tick it is over.
func advance(delta: float) -> bool:
	if _phase == Phase.NONE:
		return false
	_phase_remaining -= delta
	if _phase_remaining > 0.0:
		return false
	match _phase:
		Phase.TELEGRAPH:
			_open_swing()
		Phase.BETWEEN_HITS:
			_play_rewind()
			_open_swing()
		Phase.ACTIVE:
			_close_swing()
			_hits_done += 1
			if _hits_done < maxi(1, _attack.hit_count):
				# Another swing to come: committed, but harmless in the gap.
				_enter(Phase.BETWEEN_HITS, _attack.delay_between_hits)
				return false
			_enter(Phase.RECOVERY, _attack.attack.recovery * _tempo)
			settle_look(false)
		Phase.RECOVERY:
			var done: BossAttack = _attack
			_finish()
			attack_ended.emit(done, true)
			return true
	return false


## Cuts the attack off wherever it is: every hit window shut at once, the look
## put back. Its cooldown stands — the attack was spent.
func interrupt() -> void:
	_close_swing()
	if _attack == null:
		return
	var cut: BossAttack = _attack
	_finish()
	settle_look(true)
	attack_ended.emit(cut, false)


## Runs the cooldowns down. Called by the boss's own tick, while it fights.
func tick(delta: float) -> void:
	for attack in _cooldowns:
		var left: float = _cooldowns[attack]
		if left > 0.0:
			_cooldowns[attack] = maxf(0.0, left - delta)


## Every cooldown over and no history: a new phase opens on a clean slate.
func clear_cooldowns() -> void:
	for attack in _cooldowns:
		_cooldowns[attack] = 0.0
	_last = null
	_consecutive = 0


## Sets one attack's cooldown — for whatever needs to hold one back.
func set_cooldown(attack: BossAttack, seconds: float) -> void:
	if _cooldowns.has(attack):
		_cooldowns[attack] = maxf(0.0, seconds)


func _enter(phase: Phase, duration: float) -> void:
	_phase = phase
	_phase_remaining = duration


func _finish() -> void:
	_enter(Phase.NONE, 0.0)
	_attack = null
	_hits_done = 0


## Opens one swing. activate() forgets whom the last swing hit, so each swing can
## land on each target once.
func _open_swing() -> void:
	_enter(Phase.ACTIVE, _attack.attack.active)
	var hitbox: Hitbox = _hitboxes.get(_attack, null)
	if hitbox != null:
		hitbox.use_attack(_attack.attack, _base_damage)
		hitbox.activate()


func _close_swing() -> void:
	for hitbox in _hitboxes.values():
		if hitbox != null and (hitbox as Hitbox).is_active():
			(hitbox as Hitbox).deactivate()


# --- the look (PLACEHOLDER until M14) ----------------------------------------------------

## The colour the body rests at — its phase's.
func set_resting_color(color: Color) -> void:
	_resting_color = color


## Puts the mesh back at rest in the resting colour: over SETTLE_TIME, or at once.
func settle_look(instant: bool) -> void:
	_kill_tween()
	if _mesh_root == null:
		return
	if instant:
		_mesh_root.rotation = Vector3.ZERO
		_mesh_root.scale = Vector3.ONE
		_mesh_root.position = Vector3.ZERO
		if _body_material != null:
			_body_material.albedo_color = _resting_color
		return
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(_mesh_root, "rotation", Vector3.ZERO, SETTLE_TIME)
	_telegraph_tween.tween_property(_mesh_root, "scale", Vector3.ONE, SETTLE_TIME)
	_telegraph_tween.tween_property(_mesh_root, "position", Vector3.ZERO, SETTLE_TIME)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", _resting_color, SETTLE_TIME)


func _kill_tween() -> void:
	if _telegraph_tween != null and _telegraph_tween.is_running():
		_telegraph_tween.kill()


## Each attack winds up with a different shape: a forward lean, a spin, a
## vertical compression, a recoil.
func _play_telegraph() -> void:
	if _mesh_root == null:
		return
	_kill_tween()
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	var duration: float = maxf(0.05, _phase_remaining * 0.9)
	match _attack.telegraph:
		BossAttack.Telegraph.LEAN:
			_telegraph_tween.tween_property(_mesh_root, "rotation:x", deg_to_rad(LEAN_DEGREES), duration)
		BossAttack.Telegraph.SPIN:
			_telegraph_tween.tween_property(_mesh_root, "rotation:y", -TAU, duration)
		BossAttack.Telegraph.COMPRESS:
			_telegraph_tween.tween_property(_mesh_root, "scale", COMPRESS_SCALE, duration)
		BossAttack.Telegraph.RECOIL:
			# Cocks backwards and narrows instead of leaning in: reads as a wind-up
			# with something held back, not as a single jab.
			_telegraph_tween.tween_property(_mesh_root, "position:z", RECOIL_BACK, duration)
			_telegraph_tween.tween_property(_mesh_root, "rotation:x", deg_to_rad(RECOIL_DEGREES), duration)
			_telegraph_tween.tween_property(_mesh_root, "scale", RECOIL_SCALE, duration)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", _attack.telegraph_color, duration)


## In the gap between two swings, so the next is announced rather than arriving
## out of a still body.
func _play_rewind() -> void:
	if _mesh_root == null or _attack.delay_between_hits <= 0.0:
		return
	_kill_tween()
	var half: float = maxf(0.03, _attack.delay_between_hits * 0.45)
	_telegraph_tween = create_tween()
	_telegraph_tween.set_parallel(true)
	_telegraph_tween.tween_property(_mesh_root, "position:z", REWIND_BACK, half)
	_telegraph_tween.tween_property(_mesh_root, "scale", REWIND_SCALE, half)
	if _body_material != null:
		_telegraph_tween.tween_property(_body_material, "albedo_color", REWIND_COLOR, half)
