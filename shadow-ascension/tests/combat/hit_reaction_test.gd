extends Node3D

## M11.6 — hit reactions, stagger and knockback, on real enemies and the boss.
##
##   godot --headless --path . res://tests/combat/hit_reaction_test.tscn
##
## The player's hits are its real attacks (PlayerCombat starting Light 1/2/3 or
## the heavy, aimed through the camera rig), landing through its real hitbox. A
## hit with values no attack of the player has (a push with no stagger, a
## stagger with no push) goes in the same one way, a DamageInfo to the enemy's
## hurtbox. Every hit the player lands is recorded as the enemy stood right
## after it; a watcher checks every physics frame that no enemy is ever in an
## impossible state.

const DT: float = 1.0 / 60.0
const FRAME_SLACK: int = 2
## Where the enemy under test stands, straight in front of the player at the origin.
const IN_FRONT: Vector3 = Vector3(0, 0.1, -1.5)
const PARKED: Array[Vector3] = [Vector3(-20, 0.1, 20), Vector3(-16, 0.1, 20), Vector3(-12, 0.1, 20)]
## The wall's near face (its centre is at z -12, 1 m thick).
const WALL_FACE_Z: float = -11.5
const ENEMY_BODY_RADIUS: float = 0.45

@onready var _player: Player = $Player
@onready var _a: BasicEnemy = $EnemyA
@onready var _b: BasicEnemy = $EnemyB
@onready var _c: BasicEnemy = $EnemyC
@onready var _boss: DungeonBoss = $Boss
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _combat: PlayerCombat = null
var _data: PlayerCombatData = null
var _light: Array[AttackData] = []
var _heavy: AttackData = null
## Every hit the player's hitbox landed: the target, what it carried, and how the
## target stood right after taking it.
var _hits: Array[Dictionary] = []
var _violations: Array[String] = []
var _watching: bool = false
## Game time: every physics tick's delta, summed. A hit stop (M11.9) holds the
## game, and the ticks it holds pass with no delta — a duration the game lives
## is measured on this, not by counting ticks.
var _clock: float = 0.0
var _pass: int = 0
var _fail: int = 0


## Criticals are random (M11.7) and this suite checks exact damage, so they are
## off for its whole run: every player here reads this one cached instance of
## the combat data. critical_hit_test and m11_critical_run test criticals.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_combat = _player.combat
	_data = _combat.data
	_light = _data.light_combo
	_heavy = _data.heavy_combo[0]
	_player.attack_hitbox.hit_landed.connect(_on_player_hit)
	_player.hurtbox.set_invulnerable(true)
	_run()


func _physics_process(delta: float) -> void:
	_clock += delta
	if _watching:
		_check_invariants()


func _run() -> void:
	await _wait(0.4)
	_watching = true
	_config_tests()
	await _light_and_heavy_tests()
	await _combo_tests()
	await _stagger_lifecycle_tests()
	await _independence_tests()
	await _interrupt_tests()
	await _ai_tests()
	await _direction_tests()
	await _obstacle_tests()
	await _multiple_target_tests()
	await _boss_tests()
	await _death_tests()
	_watching = false
	_record(_violations.is_empty(),
		"I1) every frame: a staggered enemy has no attack and no open hitbox, a dead one no push and no stagger, every push flat and no stronger than the heavy's (%d: %s)" % [
			_violations.size(), _violations.slice(0, 3)])
	var enemy_data: EnemyData = load("res://resources/enemies/basic_melee_enemy.tres") as EnemyData
	_record(enemy_data.stagger_resistance == 25.0 and enemy_data.knockback_multiplier == 1.0
			and _heavy.stagger_power == 60.0 and _light[0].knockback_force == 2.0,
		"I2) the shared enemy and attack assets were never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration ------------------------------------------------------------------------------

func _config_tests() -> void:
	var powers: Array[float] = []
	var forces: Array[float] = []
	for attack in _light:
		powers.append(attack.stagger_power)
		forces.append(attack.knockback_force)
	powers.append(_heavy.stagger_power)
	forces.append(_heavy.knockback_force)
	_record(powers == [10.0, 15.0, 30.0, 60.0] and forces == [2.0, 2.5, 4.5, 8.0],
		"CF1) stagger power L1/L2/L3/heavy %s, knockback %s m/s — rising through the combo, highest on the heavy" % [powers, forces])
	_record(_a.stagger_resistance == 25.0 and _a.stagger_duration == 0.5 and _a.stagger_immunity_time == 1.0
			and _a.knockback_multiplier == 1.0 and _a.knockback_deceleration == 30.0,
		"CF2) the basic enemy: resistance 25, stagger 0.5s, immunity 1.0s, knockback x1.0 dying at 30 m/s²")


# --- Light 1, 2, 3 and the heavy, one at a time --------------------------------------------------

func _light_and_heavy_tests() -> void:
	var cases: Array = [
		["L1", _light, 0, 20.0, false], ["L2", _light, 1, 25.0, false],
		["L3", _light, 2, 35.0, true], ["H", _data.heavy_combo, 0, 40.0, true],
	]
	var moved: Array[float] = []
	for case in cases:
		await _fresh(_a, IN_FRONT)
		var attack: AttackData = (case[1] as Array[AttackData])[case[2]]
		var start: Vector3 = _a.global_position
		var hp: float = _a.health_component.current_health
		var first: int = _hits.size()
		await _swing(case[1], case[2], _a)
		var hit: Dictionary = _hits[first] if _hits.size() > first else {}
		await _until(func() -> bool: return not _a.is_knocked_back())
		await _frames(2)
		var displacement: Vector3 = _flat(_a.global_position - start)
		var expected: float = attack.knockback_force * attack.knockback_force / (2.0 * _a.knockback_deceleration)
		moved.append(displacement.length())
		_record(_hits.size() == first + 1 and is_equal_approx(hp - _a.health_component.current_health, case[3])
				and hit.get("flinched", false) and hit.get("staggered", false) == case[4]
				and is_equal_approx(hit.get("push", -1.0), attack.knockback_force)
				and absf(displacement.length() - expected) <= attack.knockback_force * DT + 0.02
				and displacement.normalized().dot(Vector3.FORWARD) > 0.99,
			"%s1) %s: %.0f damage, a flinch, %s, pushed at %.1f m/s — %.2fm straight away from the player (%.2fm expected)" % [
				case[0], attack.id, case[3], "STAGGERED" if case[4] else "no stagger (%.0f < 25)" % attack.stagger_power,
				hit.get("push", -1.0), displacement.length(), expected])
	_record(moved[3] > moved[2] and moved[2] > moved[1] and moved[1] > moved[0],
		"H2) the heavy pushes furthest (%.2fm), then L3 (%.2fm), L2 (%.2fm), L1 (%.2fm)" % [moved[3], moved[2], moved[1], moved[0]])
	_record(_combat.get_stamina() == _combat.get_max_stamina(),
		"SM1) none of it touched the player's stamina: %.0f" % _combat.get_stamina())


# --- the combo and the heavy's single hit ---------------------------------------------------------

func _combo_tests() -> void:
	await _fresh(_a, IN_FRONT)
	_aim_at(_a)
	var first: int = _hits.size()
	var started: Array[StringName] = []
	var on_started: Callable = func(attack: AttackData) -> void: started.append(attack.id)
	_combat.attack_started.connect(on_started)
	_player.camera_rig.attack_light_pressed.emit()
	for i in 2:
		await _frames_until_state(PlayerCombat.State.RECOVERY)
		await _frames(3)
		_player.camera_rig.attack_light_pressed.emit()
		await _frames_until_state(PlayerCombat.State.WINDUP)
	await _frames_until_state(PlayerCombat.State.IDLE)
	_combat.attack_started.disconnect(on_started)
	var reactions: Array[String] = []
	for i in range(first, _hits.size()):
		reactions.append("%s:%.0f%s" % [_hits[i]["attack"], _hits[i]["amount"], "/stagger" if _hits[i]["staggered"] else "/flinch"])
	_record(started == [_light[0].id, _light[1].id, _light[2].id] and _hits.size() == first + 3
			and reactions == ["light_attack_1:20/flinch", "light_attack_2:25/flinch", "light_attack_3:35/stagger"],
		"LC1) Light 1 -> 2 -> 3 still chains and still lands, each hit reacting: %s" % [reactions])

	# One heavy, one hit, one push: however long the hit window stays open over the target.
	await _fresh(_a, IN_FRONT)
	first = _hits.size()
	var pushes: Array[float] = []
	_aim_at(_a)
	_combat.reset()
	_combat._start_attack(_data.heavy_combo, 0)
	var phases: Array[String] = []
	while _combat.get_state() != PlayerCombat.State.IDLE:
		var phase: String = PlayerCombat.State.keys()[_combat.get_state()]
		if phases.is_empty() or phases[-1] != phase:
			phases.append(phase)
		await get_tree().physics_frame
		if _a.is_knocked_back():
			pushes.append(_a.get_knockback_velocity().length())
	var decaying: bool = not pushes.is_empty()
	for i in range(1, pushes.size()):
		if pushes[i] > pushes[i - 1]:
			decaying = false
	_record(phases == ["WINDUP", "ACTIVE", "RECOVERY"] and _hits.size() == first + 1 and decaying,
		"HV1) the heavy runs windup -> active -> recovery, hits once, and its push only ever dies out (%d frames)" % pushes.size())


# --- stagger: duration, immunity, return -----------------------------------------------------------

func _stagger_lifecycle_tests() -> void:
	await _fresh(_a, IN_FRONT)
	await _swing(_light, 2, _a)
	var hit_clock: float = _hits[-1]["clock"]
	await _until(func() -> bool: return not _a.is_staggered())
	var total: float = _clock - hit_clock
	_record(absf(total - _a.stagger_duration) <= (FRAME_SLACK + 1) * DT and _a.is_stagger_immune()
			and _a._state == BasicEnemy.State.IDLE,
		"ST1) a stagger lasts %.2fs (%.2fs), then a parked enemy stands idle — and immune" % [_a.stagger_duration, total])

	var hp: float = _a.health_component.current_health
	var first: int = _hits.size()
	await _swing(_data.heavy_combo, 0, _a)
	var immune_hit: Dictionary = _hits[first] if _hits.size() > first else {}
	_record(not immune_hit.get("staggered", true) and hp - _a.health_component.current_health == 40.0
			and is_equal_approx(immune_hit.get("push", 0.0), _heavy.knockback_force),
		"ST2) a heavy inside the immunity: 40 damage and the full push, but no stagger")
	await _until(func() -> bool: return not _a.is_stagger_immune(), 90)
	_a.health_component.current_health = _a.health_component.max_health
	await _fresh(_a, IN_FRONT, false)
	first = _hits.size()
	await _swing(_data.heavy_combo, 0, _a)
	_record(_hits.size() > first and _hits[first]["staggered"],
		"ST3) once the immunity is over, the next heavy staggers again")

	# No lock: heavies back to back for four seconds.
	await _fresh(_a, IN_FRONT)
	var stagger_starts: Array[int] = []
	var staggered_frames: int = 0
	var frame: int = 0
	var was: bool = false
	while frame < 240:
		if _combat.get_state() == PlayerCombat.State.IDLE:
			_a.global_position = IN_FRONT
			_a.health_component.current_health = _a.health_component.max_health
			_aim_at(_a)
			_combat._start_attack(_data.heavy_combo, 0)
		await get_tree().physics_frame
		frame += 1
		if _a.is_staggered():
			staggered_frames += 1
			if not was:
				stagger_starts.append(frame)
		was = _a.is_staggered()
	var spaced: bool = stagger_starts.size() >= 2
	for i in range(1, stagger_starts.size()):
		if (stagger_starts[i] - stagger_starts[i - 1]) * DT < _a.stagger_duration + _a.stagger_immunity_time - DT:
			spaced = false
	_record(spaced and float(staggered_frames) / frame < 0.5,
		"ST4) heavies back to back for 4s: %d staggers, each at least %.1fs apart; staggered %d of %d frames — never locked" % [
			stagger_starts.size(), _a.stagger_duration + _a.stagger_immunity_time, staggered_frames, frame])


# --- stagger and knockback are independent --------------------------------------------------------

func _independence_tests() -> void:
	await _fresh(_a, IN_FRONT)
	var start: Vector3 = _a.global_position
	_a.hurtbox.receive_hit(_crafted_hit(5.0, 0.0, 6.0, Vector3.FORWARD))
	var push_only: bool = not _a.is_staggered() and _a.is_knocked_back()
	await _until(func() -> bool: return not _a.is_knocked_back())
	var pushed: float = _flat(_a.global_position - start).length()
	_record(push_only and pushed > 0.5, "KS1) a push with no stagger power: pushed %.2fm, not staggered" % pushed)

	await _fresh(_a, IN_FRONT)
	start = _a.global_position
	_a.hurtbox.receive_hit(_crafted_hit(5.0, 100.0, 0.0, Vector3.FORWARD))
	var stagger_only: bool = _a.is_staggered() and not _a.is_knocked_back()
	await _frames(20)
	_record(stagger_only and _flat(_a.global_position - start).length() < 0.01,
		"KS2) a stagger with no push: staggered, and not moved an inch")

	await _fresh(_a, IN_FRONT)
	start = _a.global_position
	_aim_at(_a)
	_combat._start_attack(_data.heavy_combo, 0)
	var both: bool = false
	var during: float = 0.0
	while _combat.get_state() != PlayerCombat.State.IDLE or _a.is_staggered():
		await get_tree().physics_frame
		if _a.is_staggered():
			both = both or _a.is_knocked_back()
			during = _flat(_a.global_position - start).length()
	var expected: float = _heavy.knockback_force * _heavy.knockback_force / (2.0 * _a.knockback_deceleration)
	_record(both and absf(during - expected) <= _heavy.knockback_force * DT + 0.02,
		"KS3) the heavy staggers and pushes at once: the stagger does not cancel the push (%.2fm, %.2fm expected)" % [during, expected])


# --- interrupting an attack -------------------------------------------------------------------------

func _interrupt_tests() -> void:
	# In its windup, by the player's Light 3.
	_player.hurtbox.set_invulnerable(false)
	_player.health_component.current_health = _player.health_component.max_health
	await _fresh(_a, IN_FRONT)
	_arm(_a)
	var began: bool = await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 240)
	var hp: float = _player.health_component.current_health
	var remaining: float = _a.attack.get_phase_remaining()
	var first: int = _hits.size()
	await _swing(_light, 2, _a, false)
	var hit: Dictionary = _hits[first] if _hits.size() > first else {}
	var untouched: bool = _player.health_component.current_health == hp
	await _until(func() -> bool: return not _a.is_staggered())
	_record(began and remaining >= _light[2].windup and hit.get("staggered", false)
			and hit.get("attack_phase", -1) == EnemyAttack.Phase.NONE and not hit.get("hitbox_open", true)
			and untouched,
		"IN1) an enemy winding up, hit by Light 3: STAGGERED, its attack gone, its hitbox shut, and the swing never lands on the player")
	_record(_a._state == BasicEnemy.State.CHASE or _a._state == BasicEnemy.State.ATTACK,
		"IN2) and after the stagger it is back under its AI (%s)" % BasicEnemy.State.keys()[_a._state])

	# With its hitbox open.
	_player.health_component.current_health = _player.health_component.max_health
	await _fresh(_a, IN_FRONT)
	_arm(_a)
	began = await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 240)
	_a.hurtbox.receive_hit(_crafted_hit(1.0, _heavy.stagger_power, 0.0, Vector3.FORWARD))
	var shut: bool = not _a.attack.hitbox.is_active() and _a.get_attack_phase() == EnemyAttack.Phase.NONE
	hp = _player.health_component.current_health
	await _wait(_a.attack.select_attack().active + 0.2)
	_record(began and shut and _a.is_staggered() and _player.health_component.current_health == hp,
		"IN3) staggered with its hitbox open: shut at once, and no damage lands from the cancelled swing")

	# Too weak to interrupt.
	_player.hurtbox.set_invulnerable(true)
	await _fresh(_a, IN_FRONT)
	_arm(_a)
	began = await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 240)
	_a.hurtbox.receive_hit(_crafted_hit(1.0, _light[0].stagger_power, 0.0, Vector3.FORWARD))
	var carried_on: bool = await _until(func() -> bool: return _a.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 60)
	_record(began and carried_on and not _a.is_staggered(),
		"IS1) a hit below the resistance (%.0f < 25) only flinches: the attack carries on into its swing" % _light[0].stagger_power)
	await _fresh(_a, IN_FRONT)


# --- the AI does not steer a push ---------------------------------------------------------------------

func _ai_tests() -> void:
	await _fresh(_a, Vector3(0, 0.1, -6.0))
	_arm(_a)
	var chasing: bool = await _until(func() -> bool:
		return _a._state == BasicEnemy.State.CHASE and _a.velocity.z > 1.0, 180)
	var start: Vector3 = _a.global_position
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 0.0, _heavy.knockback_force, Vector3.FORWARD))
	await _frames(6)
	var away: float = start.z - _a.global_position.z
	await _until(func() -> bool: return not _a.is_knocked_back())
	var furthest: Vector3 = _a.global_position
	await _wait(0.8)
	var closed_in: bool = _flat(_player.global_position - _a.global_position).length() \
		< _flat(_player.global_position - furthest).length() - 0.3
	_record(chasing and away > 0.3 and not _a.is_staggered(),
		"AI1) an enemy running at the player, pushed with no stagger: it goes back %.2fm in 6 frames — the chase does not steer the push" % away)
	_record(closed_in, "AI2) and once the push is spent, it chases again")
	await _fresh(_a, IN_FRONT)


# --- which way -------------------------------------------------------------------------------------------

func _direction_tests() -> void:
	var centre: Vector3 = Vector3(6, 0.1, 6)
	var results: Array[String] = []
	for degrees in [0.0, 90.0, 200.0, 315.0]:
		var bearing: Vector3 = Vector3(sin(deg_to_rad(degrees)), 0, cos(deg_to_rad(degrees)))
		_player.global_position = centre + bearing * 1.5
		await _fresh(_a, centre, true, false)
		var first: int = _hits.size()
		await _swing(_light, 2, _a)
		await _until(func() -> bool: return not _a.is_knocked_back())
		var moved: Vector3 = _flat(_a.global_position - centre)
		var expected: Vector3 = -bearing
		var info: DamageInfo = _hits[first]["info"] if _hits.size() > first else null
		if info != null and moved.normalized().dot(expected) > 0.98 and info.direction.dot(expected) > 0.999:
			results.append("%.0f°" % degrees)
	_player.global_position = Vector3(0, 0.1, 0)
	_record(results.size() == 4,
		"DR1) hit from %s around it, the enemy is pushed straight away from the player each time" % [results])

	# Source and target in the same spot: the way the swing faces, not a world axis.
	_player.visual_root.rotation.y = deg_to_rad(40.0)
	var stand_in: Node3D = Node3D.new()
	add_child(stand_in)
	stand_in.global_position = _player.global_position
	var direction: Vector3 = _player.attack_hitbox._direction_to(stand_in)
	var facing: Vector3 = _flat(-_player.visual_root.global_basis.z).normalized()
	stand_in.queue_free()
	_player.visual_root.rotation.y = 0.0
	_record(direction.dot(facing) > 0.999 and is_equal_approx(direction.length(), 1.0),
		"DR2) attacker and target overlapping: pushed the way the swing faces %s" % [direction.snapped(Vector3.ONE * 0.01)])


# --- walls and bodies ------------------------------------------------------------------------------------

func _obstacle_tests() -> void:
	_player.global_position = Vector3(0, 0.1, -9.4)
	await _fresh(_a, Vector3(0, 0.1, -10.9), true, false)
	var start: Vector3 = _a.global_position
	await _swing(_data.heavy_combo, 0, _a)
	await _until(func() -> bool: return not _a.is_knocked_back())
	await _frames(5)
	var stopped_at: float = _a.global_position.z
	_record(stopped_at < start.z - 0.05 and stopped_at >= WALL_FACE_Z + ENEMY_BODY_RADIUS - 0.03,
		"WL1) a heavy into a wall: pushed from z %.2f to %.2f and stopped by the wall (face at %.2f, body radius %.2f)" % [
			start.z, stopped_at, WALL_FACE_Z, ENEMY_BODY_RADIUS])

	# Into another enemy.
	_player.global_position = Vector3(0, 0.1, 0)
	await _fresh(_b, Vector3(0, 0.1, -2.6), false)
	await _fresh(_a, IN_FRONT, true, false)
	await _swing(_data.heavy_combo, 0, _a)
	await _until(func() -> bool: return not _a.is_knocked_back())
	await _frames(5)
	var gap: float = _flat(_b.global_position - _a.global_position).length()
	_record(gap >= 2.0 * ENEMY_BODY_RADIUS - 0.05,
		"WL2) a heavy into another enemy: the bodies stop against each other (%.2fm apart), no overlap" % gap)
	await _fresh(_b, PARKED[1], false)
	_player.global_position = Vector3(0, 0.1, 0)


# --- two targets in one swing -----------------------------------------------------------------------------

func _multiple_target_tests() -> void:
	await _fresh(_b, Vector3(0.55, 0.1, -1.5), false)
	await _fresh(_a, Vector3(-0.55, 0.1, -1.5), false)
	var start_a: Vector3 = _a.global_position
	var start_b: Vector3 = _b.global_position
	var first: int = _hits.size()
	_player.camera_rig.rotation.y = 0.0
	await _swing(_data.heavy_combo, 0, null)
	await _until(func() -> bool: return not _a.is_knocked_back() and not _b.is_knocked_back())
	var per_target: Dictionary = {}
	for i in range(first, _hits.size()):
		per_target[_hits[i]["target"]] = per_target.get(_hits[i]["target"], 0) + 1
	var moved_a: Vector3 = _flat(_a.global_position - start_a).normalized()
	var moved_b: Vector3 = _flat(_b.global_position - start_b).normalized()
	var own_a: Vector3 = _flat(start_a - _player.global_position).normalized()
	var own_b: Vector3 = _flat(start_b - _player.global_position).normalized()
	_record(per_target.get(_a, 0) == 1 and per_target.get(_b, 0) == 1
			and _hits[first]["staggered"] and _hits[first + 1]["staggered"]
			and moved_a.dot(own_a) > 0.98 and moved_b.dot(own_b) > 0.98 and moved_a.x < 0.0 and moved_b.x > 0.0,
		"ME1) one heavy through two enemies: each hit once, each staggered, each pushed its own way (%s, %s)" % [
			moved_a.snapped(Vector3.ONE * 0.01), moved_b.snapped(Vector3.ONE * 0.01)])
	await _fresh(_b, PARKED[1], false)


# --- the boss ---------------------------------------------------------------------------------------------

func _boss_tests() -> void:
	var spot: Vector3 = Vector3(12, 0.1, -4)
	_boss.global_position = spot
	_player.global_position = spot + Vector3(0, 0, 1.6)
	await _frames(4)
	var health: HealthComponent = _boss.health_component
	var hp: float = health.current_health
	var first: int = _hits.size()
	for i in 3:
		await _swing(_light, i, _boss)
	await _swing(_data.heavy_combo, 0, _boss)
	await _frames(20)
	var flashes: int = 0
	for i in range(first, _hits.size()):
		flashes += 1 if _hits[i].get("flashed", false) else 0
	var nudge: float = _flat(_boss.global_position - spot).length()
	_record(_hits.size() == first + 4 and flashes == 4 and hp - health.current_health == 120.0
			and nudge < 0.05 and _boss.get_state() == DungeonBoss.State.INACTIVE,
		"BO1) the boss takes Light 1/2/3 and the heavy — 120 damage, a flash each — barely nudged (%.3f m), and a parked boss is not staggered" % nudge)

	# M12.8: high resistance, not immunity. Below it, the attack goes on; at it,
	# the boss staggers and the attack is cut off.
	_player.hurtbox.set_invulnerable(true)
	_boss.set_combat_enabled(true)
	var winding: bool = await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 600)
	var at: Vector3 = _boss.global_position
	_boss.hurtbox.receive_hit(_crafted_hit(1.0, _boss.stagger_resistance - 1.0, 0.0, Vector3.FORWARD))
	var swung: bool = await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.ACTIVE, 120)
	_record(winding and swung and _flat(_boss.global_position - at).length() < 0.05,
		"BO2) hit mid-windup below its stagger resistance: the boss swings anyway, and stays where it stood")
	winding = await _until(func() -> bool: return _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH, 600)
	_boss.hurtbox.receive_hit(_crafted_hit(1.0, _boss.stagger_resistance, 0.0, Vector3.FORWARD))
	await _frames(1)
	_record(winding and _boss.is_staggered() and _boss.get_current_attack() == null
			and not _boss.combat.is_hit_window_open(),
		"BO3) a hit at its resistance (the heavy's %.0f) staggers it mid-windup and cuts the attack off" % _boss.stagger_resistance)
	_boss.set_combat_enabled(false)
	_boss.global_position = Vector3(20, 0.1, 20)
	_player.global_position = Vector3(0, 0.1, 0)


# --- death first ---------------------------------------------------------------------------------------------

func _death_tests() -> void:
	await _fresh(_c, IN_FRONT)
	_c.health_component.current_health = 30.0
	var damaged: Array[int] = [0]
	var deaths: Array[int] = [0]
	var on_damaged: Callable = func(_hit: DamageInfo) -> void: damaged[0] += 1
	var on_died: Callable = func(_enemy: RoomCombatant) -> void: deaths[0] += 1
	_c.health_component.damaged.connect(on_damaged)
	_c.enemy_died.connect(on_died)
	var xp: int = _player.progression.get_total_xp()
	await _swing(_data.heavy_combo, 0, _c)
	var at: Vector3 = _c.global_position
	await _frames(30)
	_c.health_component.damaged.disconnect(on_damaged)
	_c.enemy_died.disconnect(on_died)
	var paid: int = _player.progression.get_total_xp() - xp
	_record(_c._state == BasicEnemy.State.DEAD and not _c.is_staggered() and not _c.is_knocked_back()
			and damaged[0] == 0 and deaths[0] == 1 and _flat(_c.global_position - at).length() < 0.01
			and not (_c._flinch_tween != null and _c._flinch_tween.is_running()) and paid == _c.get_xp_reward(),
		"DE1) a killing heavy: DEAD at once — no stagger, no push, no flinch, no reaction signal — dies once, pays %d once" % paid)


# --- invariants ---------------------------------------------------------------------------------------------

func _check_invariants() -> void:
	for enemy in [_a, _b, _c]:
		var e: BasicEnemy = enemy
		if e.is_staggered() and (e.get_attack_phase() != EnemyAttack.Phase.NONE or e.attack.hitbox.is_active()):
			_violations.append("%s staggered with an attack" % e.name)
		if e._state == BasicEnemy.State.DEAD and (e.is_knocked_back() or e._stagger_timer > 0.0):
			_violations.append("%s dead with a reaction" % e.name)
		var push: Vector3 = e.get_knockback_velocity()
		if push.y != 0.0 or push.length() > _heavy.knockback_force * e.knockback_multiplier + 0.001:
			_violations.append("%s pushed %s" % [e.name, push])


func _on_player_hit(target: Node, info: DamageInfo) -> void:
	var entry: Dictionary = {"target": target, "info": info, "attack": info.attack_id, "amount": info.amount,
		"clock": _clock}
	var enemy: BasicEnemy = target as BasicEnemy
	if enemy != null:
		entry["staggered"] = enemy.is_staggered()
		entry["push"] = enemy.get_knockback_velocity().length()
		entry["flinched"] = enemy._flinch_tween != null and enemy._flinch_tween.is_running()
		entry["attack_phase"] = enemy.get_attack_phase()
		entry["hitbox_open"] = enemy.attack.hitbox.is_active()
	var boss: DungeonBoss = target as DungeonBoss
	if boss != null:
		entry["flashed"] = boss.is_flashing()
	_hits.append(entry)


# --- helpers ---------------------------------------------------------------------------------------------

## Parks `enemy` at `at`, whole, facing the player, with nothing of a previous
## hit left: no stagger, no immunity, no push.
func _fresh(enemy: BasicEnemy, at: Vector3, reset_player: bool = true, player_home: bool = true) -> void:
	if reset_player:
		_combat.reset()
		_combat.restore_stamina(_combat.get_max_stamina())
		if player_home:
			_player.global_position = Vector3(0, 0.1, 0)
		_player.velocity = Vector3.ZERO
	enemy.set_combat_enabled(false)
	enemy.global_position = at
	enemy.velocity = Vector3.ZERO
	enemy.health_component.current_health = enemy.health_component.max_health
	enemy.attack.reset()
	_face(enemy, _player.global_position)
	await _frames(3)


## Wakes a parked enemy: with the player in its detection range it picks the
## fight up on its own — IDLE, ALERT, CHASE.
func _arm(enemy: BasicEnemy) -> void:
	enemy.set_combat_enabled(true)


## The player's own attack, aimed at `target` through the camera, run to its end.
func _swing(chain: Array[AttackData], index: int, target: Node3D, reset: bool = true) -> void:
	_aim_at(target)
	if reset:
		_combat.reset()
	_combat._start_attack(chain, index)
	await _frames_until_state(PlayerCombat.State.IDLE)


func _aim_at(target: Node3D) -> void:
	if target == null:
		return
	var to: Vector3 = _flat(target.global_position - _player.global_position)
	if to.length_squared() > 0.0001:
		_player.camera_rig.rotation.y = atan2(-to.x, -to.z)


func _face(enemy: BasicEnemy, point: Vector3) -> void:
	var to: Vector3 = _flat(point - enemy.global_position)
	if to.length_squared() > 0.0001:
		enemy.visual_root.rotation.y = atan2(-to.x, -to.z)


func _crafted_hit(amount: float, stagger: float, push: float, direction: Vector3) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new(amount, _player, &"test_hit")
	info.stagger_power = stagger
	info.knockback_force = push
	info.direction = direction
	return info


func _until(condition: Callable, budget: int = 120) -> bool:
	var n: int = 0
	while not condition.call():
		if n >= budget:
			return false
		await get_tree().physics_frame
		n += 1
	return true


func _frames_until_state(state: PlayerCombat.State, budget: int = 180) -> int:
	var n: int = 0
	while _combat.get_state() != state:
		if n >= budget:
			return -1
		await get_tree().physics_frame
		n += 1
	return n


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
