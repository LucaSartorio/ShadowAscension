extends Node3D

## M12.5 — the assassin archetype: fast, fragile and mobile, on the M12.1 state
## machine and the M12.2 melee attack. Its own loop — in fast, a short
## telegraph, a lunge, out to its disengage ring while its attack cools down, back
## in — against the player's whole M11 kit, beside the other three archetypes.
##
##   godot --headless --path . res://tests/enemies/assassin_archetype_test.tscn
##
## Every section spawns what it needs and frees it again. Every tick a watcher
## checks each enemy's attack against its state and its hitbox, and how far each
## assassin moved in the tick — no teleport.

const ASSASSIN_SCENE: PackedScene = preload("res://scenes/enemies/basic_assassin_enemy.tscn")
const MELEE_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const TANK_SCENE: PackedScene = preload("res://scenes/enemies/basic_tank_enemy.tscn")
const INDICATOR_SCENE: PackedScene = preload("res://scenes/ui/target_lock_indicator.tscn")
const ASSASSIN_DATA: EnemyData = preload("res://resources/enemies/basic_assassin_enemy.tres")
const MELEE_DATA: EnemyData = preload("res://resources/enemies/basic_melee_enemy.tres")
const TANK_DATA: EnemyData = preload("res://resources/enemies/basic_tank_enemy.tres")
const RANGED_DATA: EnemyData = preload("res://resources/enemies/basic_ranged_enemy.tres")
const SHADOW_DATA: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
const HOME: Vector3 = Vector3(0, 0.1, 0)
const IN_REACH: Vector3 = Vector3(0, 0.1, -2.1)
const PARK: Vector3 = Vector3(35, 0.1, 35)
## The back wall's face is at z -29.5.
const WALL_FACE_Z: float = -29.5
const DT: float = 1.0 / 60.0
const STRESS_COUNT: int = 12
## A physics tick must fit in one 60 Hz tick, or the game falls behind.
const PHYSICS_BUDGET: float = 1.0 / 60.0

@onready var _player: Player = $Player
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _strike: AttackData = null
var _spawned: Array = []
var _watched: Array = []
var _violations: Array[String] = []
## The furthest any assassin moved in one tick, in metres.
var _longest_step: float = 0.0
var _last_positions: Dictionary = {}
var _hits: Array[Dictionary] = []
var _transitions: Dictionary = {}
var _transition_times: Dictionary = {}
var _clock: float = 0.0
var _count: int = 0
var _pass: int = 0
var _fail: int = 0

var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_strike = ASSASSIN_DATA.attacks[0]
	_run()


func _physics_process(delta: float) -> void:
	_clock += delta
	for candidate in _watched:
		if not is_instance_valid(candidate) or not (candidate as Node).is_inside_tree():
			continue
		var e: BasicEnemy = candidate
		var phase: EnemyAttack.Phase = e.get_attack_phase()
		if (e.get_state() == BasicEnemy.State.ATTACK) != (phase != EnemyAttack.Phase.NONE):
			_violations.append("%s %s/%s" % [e.name, BasicEnemy.State.keys()[e.get_state()], EnemyAttack.Phase.keys()[phase]])
		var melee: EnemyMeleeAttack = e.attack as EnemyMeleeAttack
		if melee != null and melee.hitbox.is_active() != (phase == EnemyAttack.Phase.ACTIVE):
			_violations.append("%s hitbox in %s" % [e.name, EnemyAttack.Phase.keys()[phase]])
		if e.stats == ASSASSIN_DATA or e.stats.disengage_distance > 0.0:
			if _last_positions.has(e) and not e.is_knocked_back() and phase != EnemyAttack.Phase.ACTIVE:
				_longest_step = maxf(_longest_step, _flat(e.global_position - (_last_positions[e] as Vector3)).length())
			_last_positions[e] = e.global_position


func _run() -> void:
	await _wait(0.4)
	await _config_tests()
	await _approach_tests()
	await _loop_tests()
	await _blocked_tests()
	await _dodge_tests()
	await _lunge_wall_tests()
	await _stagger_tests()
	await _knockback_tests()
	await _critical_and_hit_stop_tests()
	await _lock_tests()
	await _death_tests()
	await _shadow_tests()
	await _multiple_tests()
	await _mixed_tests()
	await _stress_tests()
	await _wait(0.3)
	_record(_violations.is_empty(),
		"IV1) every tick, on every enemy: an attack phase exactly in ATTACK, the hitbox open exactly in ACTIVE %s" % [
			_violations.slice(0, 4)])
	var strikes: Array[Dictionary] = _hits.filter(func(h: Dictionary) -> bool: return h["attack_id"] == &"assassin_quick_strike")
	_record(strikes.all(func(h: Dictionary) -> bool: return h["phase"] == EnemyAttack.Phase.ACTIVE)
			and _longest_step <= ASSASSIN_DATA.movement_speed * DT * 1.3,
		"IV2) all %d of the assassins' hits landed in ACTIVE; outside a push or a lunge no assassin ever moved more than %.3f m in a tick (%.3f at its top speed) — no teleport" % [
			strikes.size(), _longest_step, ASSASSIN_DATA.movement_speed * DT])
	_record(ASSASSIN_DATA.max_health == 60.0 and ASSASSIN_DATA.disengage_distance == 4.5 and _strike.windup == 0.28
			and MELEE_DATA.disengage_distance == 0.0 and MELEE_DATA.attacks[0].lunge_speed == 0.0,
		"IV3) the shared EnemyData and AttackData were never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration --------------------------------------------------------------------------------------

func _config_tests() -> void:
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, PARK)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, PARK + Vector3(4, 0, 0))
	var a: EnemyData = ASSASSIN_DATA
	_record(a.max_health == 60.0 and a.movement_speed == 5.6 and a.rotation_speed == 11.0 and a.attack_range == 2.3
			and a.preferred_combat_distance == 1.8 and a.minimum_combat_distance == 1.0 and a.disengage_distance == 4.5
			and a.stagger_resistance == 20.0 and a.knockback_multiplier == 1.2 and a.attack_cooldown == 1.3
			and a.attack_damage == 18.0 and a.xp_reward == 30
			and a.max_health < MELEE_DATA.max_health and a.movement_speed > MELEE_DATA.movement_speed
			and a.stagger_resistance < TANK_DATA.stagger_resistance and a.knockback_multiplier > TANK_DATA.knockback_multiplier
			and a.rotation_speed > TANK_DATA.rotation_speed,
		"CF1) the assassin is data: 60 HP (melee 100, tank 260), 5.6 m/s (3.8, 2.4), turns at 11 rad/s (tank 4), reach 2.3 m, ring 1.8 m, disengage 4.5 m, stagger resistance 20 (tank 45), knockback x1.2 (tank x0.35), 18 damage, cooldown 1.3 s")
	_record(_strike.id == &"assassin_quick_strike" and _strike.windup == 0.28 and _strike.active == 0.12
			and _strike.recovery == 0.35 and _strike.lunge_speed == 6.0 and _strike.windup < MELEE_DATA.attacks[0].windup
			and _strike.windup < TANK_DATA.attacks[0].windup and assassin.attack.hitbox.damage == 18.0,
		"CF2) its attack, `assassin_quick_strike`: telegraph 0.28 s (melee 0.35, tank 0.8), active 0.12 s with a 6 m/s lunge, recovery 0.35 s, 18 damage")
	var box: BoxShape3D = assassin.attack.hitbox.get_node("CollisionShape3D").shape as BoxShape3D
	var origin_z: float = absf((assassin.attack.hitbox.get_parent() as Node3D).position.z)
	var others_still: bool = [MELEE_DATA, RANGED_DATA, TANK_DATA].all(func(d: EnemyData) -> bool:
		return d.disengage_distance == 0.0 and d.attacks[0].lunge_speed == 0.0)
	_record(assassin.get_script() == melee.get_script() and assassin.attack.get_script() == melee.attack.get_script()
			and origin_z - box.size.z * 0.5 <= a.minimum_combat_distance and is_equal_approx(assassin.nav_agent.radius, 0.6) and others_still,
		"CF3) the same state machine and melee attack as the melee — no assassin script; the disengage ring and the lunge are data, 0 for the melee, the ranged and the tank")
	_record(assassin.get_state() == BasicEnemy.State.IDLE and assassin.health_component.max_health == 60.0
			and assassin.health_component.current_health == 60.0 and assassin.movement_speed == 5.6,
		"SP1) spawned: IDLE, 60 of 60 HP, moving at 5.6 m/s")
	await _clear()


# --- detection and approach -----------------------------------------------------------------------------

func _approach_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(-1.5, 0, -8))
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(1.5, 0, -8))
	assassin.set_combat_enabled(true)
	melee.set_combat_enabled(true)
	await _until(func() -> bool: return assassin.get_state() == BasicEnemy.State.CHASE, 60)
	var seen: Array = _transitions[assassin]
	var alert: float = _time_of(assassin, "ALERT>CHASE") - _time_of(assassin, "IDLE>ALERT")
	_record(seen.size() >= 2 and seen[0] == "IDLE>ALERT" and seen[1] == "ALERT>CHASE" and absf(alert - 0.15) <= 2.0 * DT,
		"DT1) the player 8 m away: IDLE -> ALERT, %.2f s, then CHASE" % alert)
	var arrived: Dictionary = {}
	var fastest: Array[float] = [0.0]
	var from: Array[float] = [-1.0]
	await _until(func() -> bool:
		if assassin.get_state() == BasicEnemy.State.CHASE:
			fastest[0] = maxf(fastest[0], _flat(assassin.velocity).length())
		for e in [assassin, melee]:
			var enemy: BasicEnemy = e
			if not arrived.has(enemy) and enemy.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH:
				arrived[enemy] = _clock
				if enemy == assassin:
					from[0] = assassin.targeting.get_distance()
		return arrived.size() == 2, 240)
	_record(arrived.has(assassin) and arrived.has(melee) and arrived[assassin] < arrived[melee] - 0.3 and fastest[0] <= 5.65,
		"AP1) side by side from 8 m: the assassin is on the player %.2f s before the melee, at up to %.2f m/s" % [
			arrived.get(melee, 0.0) - arrived.get(assassin, 0.0), fastest[0]])
	_record(from[0] > 0.0 and from[0] <= assassin.attack_range,
		"AR1) in range: CHASE -> ATTACK, its telegraph starting %.2f m out, within its 2.3 m" % from[0])
	await _clear()


# --- the loop: telegraph, strike, recovery, disengage, re-engage ---------------------------------------------

func _loop_tests() -> void:
	_home_player()
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, IN_REACH)
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	assassin.set_combat_enabled(true)
	await _until(func() -> bool: return assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 60)
	var began: float = _clock
	var quiet: bool = true
	var crouched: bool = false
	while assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH:
		quiet = quiet and not assassin.attack.hitbox.is_active() and _player.health_component.current_health == hp
		crouched = crouched or (assassin.visual_root.scale.y < 0.9 and _body_color(assassin).g > 0.6)
		await get_tree().physics_frame
	var telegraph: float = _clock - began
	_record(quiet and crouched and absf(telegraph - _strike.windup) <= 2.0 * DT,
		"TG1) the telegraph: %.2f s — shorter than the melee's 0.35 — the hitbox shut, no damage, the body crouching and flashing teal" % telegraph)
	var yaw: float = assassin.visual_root.rotation.y
	var facing: Vector3 = -assassin.visual_root.global_basis.z
	var lunge_start: Vector3 = assassin.global_position
	var active_began: float = _clock
	var turned: bool = false
	while assassin.get_attack_phase() == EnemyAttack.Phase.ACTIVE:
		turned = turned or not is_equal_approx(assassin.visual_root.rotation.y, yaw)
		await get_tree().physics_frame
	var active: float = _clock - active_began
	var lunged: Vector3 = _flat(assassin.global_position - lunge_start)
	var mine: Array[Dictionary] = _hits.slice(first)
	_record(mine.size() == 1 and mine[0]["target"] == _player and mine[0]["accepted"] and mine[0]["amount"] == 18.0
			and mine[0]["attack_id"] == &"assassin_quick_strike" and mine[0]["source"] == assassin
			and hp - _player.health_component.current_health == 18.0 and absf(active - _strike.active) <= 2.0 * DT,
		"AT1) not avoided: one hit of 18 in a %.2f s window, from the assassin, named assassin_quick_strike" % active)
	_record(not turned and lunged.length() > 0.3 and rad_to_deg(lunged.angle_to(_flat(facing))) < 3.0,
		"LG1) the lunge: %.2f m forward during ACTIVE, along the facing it locked before (%.1f deg off it), not turning" % [
			lunged.length(), rad_to_deg(lunged.angle_to(_flat(facing)))])
	var recovery_began: float = _clock
	var shut: bool = true
	while assassin.get_attack_phase() == EnemyAttack.Phase.RECOVERY:
		shut = shut and not assassin.attack.hitbox.is_active()
		await get_tree().physics_frame
	var recovery: float = _clock - recovery_began
	var recovered_at: float = _clock
	_record(shut and absf(recovery - _strike.recovery) <= 2.0 * DT and _hits.size() - first == 1,
		"RC1) then %.2f s of recovery — short, but there — the hitbox shut, no second hit" % recovery)
	# Out to the disengage ring, and back in once the cooldown is over.
	var farthest: Array[float] = [0.0]
	var faced: Array[bool] = [true]
	var idle: Array[bool] = [false]
	var next_telegraph: bool = await _until(func() -> bool:
		farthest[0] = maxf(farthest[0], assassin.targeting.get_distance())
		if assassin.get_state() == BasicEnemy.State.REPOSITION and assassin.targeting.get_distance() > 2.5:
			faced[0] = faced[0] and assassin._facing_error_to(_player) < deg_to_rad(20.0)
		idle[0] = idle[0] or assassin.get_state() == BasicEnemy.State.IDLE
		return assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 240)
	var seen: Array = _transitions[assassin]
	var gap: float = _clock - recovered_at
	_record(seen.has("CHASE>REPOSITION") and farthest[0] >= 4.0 and farthest[0] <= 5.2 and faced[0],
		"DS1) after its strike it disengages: CHASE -> REPOSITION, backing out to %.2f m — its 4.5 m ring, not across the arena — on the navigation, facing the player" % farthest[0])
	_record(next_telegraph and not idle[0] and gap < 2.5 and seen.has("REPOSITION>CHASE"),
		"RE1) and re-engages once its cooldown is over: back in and winding up again %.2f s after the last recovery — never idle" % gap)
	await _clear()


func _blocked_tests() -> void:
	# Its back to a wall: it cannot back off, and falls back to fighting where it is.
	_home_player(Vector3(0, 0.1, WALL_FACE_Z + 2.8))
	_player.hurtbox.set_invulnerable(true)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, Vector3(0, 0.1, WALL_FACE_Z + 0.5))
	var first: int = assassin.attack.get_swing_count()
	assassin.set_combat_enabled(true)
	var deepest: Array[float] = [0.0]
	await _until(func() -> bool:
		deepest[0] = minf(deepest[0], assassin.global_position.z)
		return assassin.attack.get_swing_count() >= first + 2, 420)
	var seen: Array = _transitions[assassin]
	_record(assassin.attack.get_swing_count() >= first + 2 and seen.has("CHASE>REPOSITION") and seen.size() < 30
			and deepest[0] >= WALL_FACE_Z + 0.25,
		"BR1) its back to a wall: the disengage cannot go anywhere — it gives up on it and strikes again from where it is (%d transitions in two attacks, never through the wall)" % seen.size())
	await _clear()


# --- the player's answers ---------------------------------------------------------------------------------------

func _dodge_tests() -> void:
	# Dodging into the strike: the i-frames take it.
	_home_player()
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, IN_REACH)
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	assassin.set_combat_enabled(true)
	await _until(func() -> bool:
		return (assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and assassin.attack.get_phase_remaining() <= 0.08), 90)
	var speed: float = _player.effective_dodge_speed
	_player.effective_dodge_speed = 0.0
	var stamina: float = _player.combat.get_stamina()
	_press(&"dodge")
	var paid: float = stamina - _player.combat.get_stamina()
	await _until(func() -> bool: return assassin.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 60)
	_player.effective_dodge_speed = speed
	var reached: Array[Dictionary] = _hits.slice(first)
	_record(reached.size() == 1 and not reached[0]["accepted"] and _player.health_component.current_health == hp
			and paid == _player.combat.data.dodge_stamina_cost,
		"DG1) dodging into the strike: it reaches the player inside the i-frames and is refused — no damage; %.0f stamina" % paid)
	await _clear()

	# Stepping out after the facing locks: the lunge goes where it was aimed.
	_home_player()
	assassin = await _spawn(ASSASSIN_SCENE, IN_REACH)
	hp = _player.health_component.current_health
	first = _hits.size()
	assassin.set_combat_enabled(true)
	await _until(func() -> bool:
		return (assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and assassin.attack.get_phase_remaining() < ASSASSIN_DATA.telegraph_facing_lock), 90)
	var yaw: float = assassin.visual_root.rotation.y
	_player.global_position = HOME + Vector3(3.2, 0, 0)
	var still: bool = true
	while assassin.get_state() == BasicEnemy.State.ATTACK:
		still = still and is_equal_approx(assassin.visual_root.rotation.y, yaw)
		await get_tree().physics_frame
	_record(_hits.size() == first and _player.health_component.current_health == hp and still,
		"MV1) the player steps 3 m aside in the last 0.1 s of the telegraph: no turn, the lunge goes straight on — a clean miss")
	await _clear()


func _lunge_wall_tests() -> void:
	# A variant with a long lunge, aimed at a wall the player steps away from:
	# the physics stops it at the wall.
	var long: AttackData = _strike.duplicate() as AttackData
	long.lunge_speed = 25.0
	var data: EnemyData = ASSASSIN_DATA.duplicate() as EnemyData
	data.attacks = [long]
	_home_player(Vector3(0, 0.1, WALL_FACE_Z + 0.6))
	_player.hurtbox.set_invulnerable(true)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, Vector3(0, 0.1, WALL_FACE_Z + 2.7), data)
	assassin.set_combat_enabled(true)
	await _until(func() -> bool:
		return (assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and assassin.attack.get_phase_remaining() < ASSASSIN_DATA.telegraph_facing_lock), 90)
	_player.global_position = Vector3(3.5, 0.1, WALL_FACE_Z + 2.0)
	var deepest: Array[float] = [assassin.global_position.z]
	await _until(func() -> bool:
		deepest[0] = minf(deepest[0], assassin.global_position.z)
		return assassin.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 60)
	_record(deepest[0] >= WALL_FACE_Z + 0.25 and deepest[0] < WALL_FACE_Z + 1.0,
		"LG2) a 3 m lunge driven at a wall: the body stops at the wall (its centre %.2f m from the face) — no clipping through" % [
			deepest[0] - WALL_FACE_Z])
	await _clear()


# --- stagger -------------------------------------------------------------------------------------------------------

func _stagger_tests() -> void:
	var combo: Array = await _light_combo_against(ASSASSIN_SCENE)
	_record(combo[0] == [20.0, 25.0, 35.0] and combo[1] == [false, false, true],
		"ST1) the light combo on an assassin: %s — Light 1 (stagger 10) and Light 2 (15) flinch it, Light 3 (30) beats its 20 and staggers it %s" % [
			combo[0], combo[1]])
	# The heavy (60) — the strong answer.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(0, 0, -1.6))
	assassin.health_component.set_max_health(1000.0)
	assassin.health_component.current_health = 1000.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.heavy_combo, 0)
	var staggered: bool = await _until(func() -> bool: return assassin.is_staggered(), 60)
	var began: float = _clock
	await _until(func() -> bool: return not assassin.is_staggered(), 60)
	var stood: float = _clock - began
	_record(staggered and absf(stood - ASSASSIN_DATA.stagger_duration) <= 3.0 * DT,
		"ST2) the heavy (60) staggers it, for %.2f s — the short stagger of a light body" % stood)
	await _clear()

	# Staggered in the telegraph: no ACTIVE.
	_home_player()
	assassin = await _spawn(ASSASSIN_SCENE, IN_REACH)
	var hp: float = _player.health_component.current_health
	assassin.set_combat_enabled(true)
	await _until(func() -> bool: return assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 60)
	assassin.hurtbox.receive_hit(_crafted_hit(1.0, 30.0, 0.0))
	var cut: bool = assassin.is_staggered() and assassin.get_attack_phase() == EnemyAttack.Phase.NONE
	var never_opened: bool = true
	for i in 20:
		await get_tree().physics_frame
		never_opened = never_opened and not assassin.attack.hitbox.is_active()
	_record(cut and never_opened and _player.health_component.current_health == hp,
		"ST3) staggered in its telegraph: the strike is cancelled — no ACTIVE, no lunge, STAGGERED")
	await _clear()

	# Staggered while its hitbox is open: shut at once, no ghost hit.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	assassin = await _spawn(ASSASSIN_SCENE, IN_REACH)
	assassin.set_combat_enabled(true)
	await _until(func() -> bool: return assassin.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 60)
	_player.hurtbox.set_invulnerable(false)
	hp = _player.health_component.current_health
	assassin.hurtbox.receive_hit(_crafted_hit(1.0, 30.0, 0.0))
	var shut: bool = not assassin.attack.hitbox.is_active() and assassin.is_staggered()
	await _wait(0.4)
	_record(shut and _player.health_component.current_health == hp,
		"ST4) staggered mid-strike: the hitbox shut that moment and the lunge stopped — no ghost hit — STAGGERED")
	await _clear()

	# No stun-lock: light combos back to back stagger it once per window.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	assassin = await _spawn(ASSASSIN_SCENE, HOME + Vector3(0, 0, -1.6))
	assassin.health_component.set_max_health(5000.0)
	assassin.health_component.current_health = 5000.0
	var staggers: Array[int] = [0]
	assassin.state_changed.connect(func(_from: BasicEnemy.State, to: BasicEnemy.State) -> void:
		if to == BasicEnemy.State.STAGGERED:
			staggers[0] += 1)
	var hits: Array[int] = [0]
	assassin.health_component.damaged.connect(func(_hit: DamageInfo) -> void: hits[0] += 1)
	var staggered_ticks: Array[int] = [0]
	for i in 240:
		_player.global_position = assassin.global_position + _flat(_player.global_position - assassin.global_position).normalized() * 1.5
		if _player.combat.get_state() == PlayerCombat.State.IDLE:
			_player.combat.reset()
			_player.combat._start_attack(_player.combat.data.light_combo, 2)
		if assassin.is_staggered():
			staggered_ticks[0] += 1
		await get_tree().physics_frame
	_record(hits[0] >= 5 and staggers[0] <= 3 and staggered_ticks[0] < 120,
		"SL1) Light 3 after Light 3 for 4 s: %d hits, but only %d staggers — the stagger immunity every enemy has keeps it out of a stun-lock (%.1f s of 4 spent staggered)" % [
			hits[0], staggers[0], staggered_ticks[0] * DT])
	await _clear()


func _light_combo_against(scene: PackedScene) -> Array:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var enemy: BasicEnemy = await _spawn(scene, HOME + Vector3(0, 0, -1.6))
	enemy.health_component.set_max_health(1000.0)
	enemy.health_component.current_health = 1000.0
	var taken: Array[float] = []
	var staggered: Array[bool] = []
	enemy.health_component.damaged.connect(func(hit: DamageInfo) -> void:
		taken.append(hit.amount)
		staggered.append(enemy.is_staggered()))
	_player.combat.reset()
	_player.camera_rig.attack_light_pressed.emit()
	var frames: int = 0
	while _player.combat.is_attacking() and frames < 300:
		await get_tree().physics_frame
		frames += 1
		if _player.combat.get_state() == PlayerCombat.State.RECOVERY and _player.combat.get_queued_attack() == null \
				and _player.combat.get_combo_index() < 2:
			_player.camera_rig.attack_light_pressed.emit()
	await _clear()
	return [taken, staggered]


# --- knockback -------------------------------------------------------------------------------------------------------

func _knockback_tests() -> void:
	var tank_push: Array = await _heavy_push(TANK_SCENE)
	var assassin_push: Array = await _heavy_push(ASSASSIN_SCENE)
	_record(absf(assassin_push[0] - 8.0 * 1.2) < 0.01 and assassin_push[1] > tank_push[1] * 5.0 and assassin_push[1] > 1.0,
		"KB1) the same heavy: a tank moves %.2f m, an assassin %.2f m (pushed at %.1f m/s) — clearly thrown, not blown away" % [
			tank_push[1], assassin_push[1], assassin_push[0]])
	# Pushed mid-chase: the navigation does not cancel it, and it comes back in.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(0, 0, -7))
	assassin.set_combat_enabled(true)
	await _until(func() -> bool:
		return assassin.get_state() == BasicEnemy.State.CHASE and _flat(assassin.velocity).length() > 3.0, 120)
	var at: Vector3 = assassin.global_position
	assassin.hurtbox.receive_hit(_crafted_hit(1.0, 0.0, 8.0))
	await _until(func() -> bool: return not assassin.is_knocked_back(), 60)
	var back: float = at.z - assassin.global_position.z
	var resumed: bool = await _until(func() -> bool: return assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 180)
	_record(back > 0.8 and resumed,
		"KB2) pushed mid-chase: the push carries it %.2f m back against its own run — the navigation does not cancel it — then it closes in and strikes" % back)
	await _clear()


func _heavy_push(scene: PackedScene) -> Array:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var enemy: BasicEnemy = await _spawn(scene, HOME + Vector3(0, 0, -1.6))
	enemy.health_component.set_max_health(1000.0)
	enemy.health_component.current_health = 1000.0
	var start: Vector3 = enemy.global_position
	var speed: Array[float] = [0.0]
	enemy.health_component.damaged.connect(func(_hit: DamageInfo) -> void:
		speed[0] = enemy.get_knockback_velocity().length())
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.heavy_combo, 0)
	await _until(func() -> bool: return speed[0] > 0.0, 60)
	await _until(func() -> bool: return not enemy.is_knocked_back(), 90)
	var moved: float = _flat(enemy.global_position - start).length()
	await _clear()
	return [speed[0], moved]


# --- critical, hit stop -------------------------------------------------------------------------------------------------

func _critical_and_hit_stop_tests() -> void:
	# Struck (critically) in its telegraph: 30 damage, no stagger, the telegraph kept.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(0, 0, -1.6))
	assassin.health_component.set_max_health(1000.0)
	assassin.health_component.current_health = 1000.0
	assassin._reposition_block_timer = 30.0
	assassin.set_combat_enabled(true)
	await _until(func() -> bool: return assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 60)
	var began: float = _clock
	var tick: int = Engine.get_physics_frames()
	var taken: Array[DamageInfo] = []
	assassin.health_component.damaged.connect(func(hit: DamageInfo) -> void: taken.append(hit))
	var marks: int = _player.combat_feedback.get_critical_mark_count()
	var stops: int = _player.combat_feedback.get_hit_stop_count()
	_no_crits.critical_chance = 1.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return assassin.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH, 60)
	_no_crits.critical_chance = 0.0
	var game: float = _clock - began
	var wall: float = (Engine.get_physics_frames() - tick) * DT
	_record(taken.size() == 1 and taken[0].is_critical and taken[0].amount == 30.0 and not assassin.is_staggered()
			and _player.combat_feedback.get_critical_mark_count() > marks,
		"CR1) a critical Light 1 on it mid-telegraph: 30 damage (20 x1.5), its mark shown — and, a critical changing only the damage, no stagger")
	_record(_player.combat_feedback.get_hit_stop_count() > stops and absf(game - _strike.windup) <= 2.0 * DT
			and wall > game + DT and assassin.get_attack_phase() == EnemyAttack.Phase.ACTIVE,
		"HS1) through the hit stop that brought, the telegraph still lasts %.2f s of game time (%.2f s on the wall) and the strike goes on" % [
			game, wall])
	await _clear()


# --- the player's lock, on something that moves fast ----------------------------------------------------------------------

func _lock_tests() -> void:
	var indicator: TargetLockIndicator = INDICATOR_SCENE.instantiate() as TargetLockIndicator
	add_child(indicator)
	await _frames(3)
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(0, 0, -5))
	assassin.set_combat_enabled(true)
	await _frames(2)
	_press(&"target_lock")
	var locked: bool = _player.targeting.get_target() == assassin
	var held: Array[bool] = [true]
	var ringed: Array[bool] = [true]
	var states: Dictionary = {}
	var worst_facing: Array[float] = [0.0]
	await _until(func() -> bool:
		states[BasicEnemy.State.keys()[assassin.get_state()]] = true
		held[0] = held[0] and _player.targeting.get_target() == assassin
		ringed[0] = ringed[0] and indicator.is_showing() \
			and indicator.global_position.distance_to(assassin.get_target_point()) < 0.15
		if assassin.get_state() == BasicEnemy.State.REPOSITION:
			var to: Vector3 = _flat(assassin.global_position - _player.global_position).normalized()
			var facing: Vector3 = _flat(-_player.visual_root.global_basis.z).normalized()
			worst_facing[0] = maxf(worst_facing[0], rad_to_deg(facing.angle_to(to)))
		return states.has("REPOSITION") and assassin.attack.get_swing_count() >= 2 \
			and assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 360)
	assassin.hurtbox.receive_hit(_crafted_hit(1.0, 30.0, 0.0))
	await _frames(2)
	states[BasicEnemy.State.keys()[assassin.get_state()]] = true
	var still_locked: bool = _player.targeting.get_target() == assassin
	assassin.hurtbox.receive_hit(DamageInfo.new(1000.0, _player, &"test"))
	await _frames(3)
	_record(locked and held[0] and still_locked and ringed[0] and worst_facing[0] < 35.0
			and states.has("CHASE") and states.has("ATTACK") and states.has("REPOSITION") and states.has("STAGGERED")
			and not _player.targeting.is_locked() and not indicator.is_showing(),
		"LK1) locked on the assassin through %s, as it darts in and out: the lock held, the ring stayed on it, the player turned after it (%.0f deg behind at worst); dead, the lock and ring let go" % [
			states.keys(), worst_facing[0]])
	indicator.queue_free()
	await _clear()


# --- death ----------------------------------------------------------------------------------------------------------------------

func _death_tests() -> void:
	_home_player()
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, IN_REACH)
	var hp: float = _player.health_component.current_health
	assassin.set_combat_enabled(true)
	await _until(func() -> bool: return assassin.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 60)
	assassin.hurtbox.receive_hit(_crafted_hit(1000.0, 0.0, 0.0))
	var dead: bool = assassin.get_state() == BasicEnemy.State.DEAD
	var never_opened: bool = true
	for i in 40:
		await get_tree().physics_frame
		never_opened = never_opened and not assassin.attack.hitbox.is_active()
	_record(dead and never_opened and _player.health_component.current_health == hp,
		"DE1) killed in its telegraph: DEAD, no ACTIVE, no lunge, the hitbox never opens")
	await _clear()

	# Killed while it backs off: it stops there, and the kill is paid once.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	assassin = await _spawn(ASSASSIN_SCENE, HOME + Vector3(0, 0, -1.6))
	assassin.health_component.set_max_health(1000.0)
	assassin.health_component.current_health = 1000.0
	var deaths: Array[int] = [0]
	assassin.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	# One real hit first, so the player's progression is watching it.
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return not _player.combat.is_attacking(), 60)
	var xp: int = _player.progression.get_total_xp()
	assassin.set_combat_enabled(true)
	var backing: bool = await _until(func() -> bool:
		return assassin.get_state() == BasicEnemy.State.REPOSITION and assassin.is_disengaging(), 240)
	assassin.hurtbox.receive_hit(DamageInfo.new(5000.0, _player, &"test"))
	var at: Vector3 = assassin.global_position
	await _frames(30)
	_record(backing and assassin.get_state() == BasicEnemy.State.DEAD and _flat(assassin.global_position - at).length() < 0.05
			and deaths[0] == 1 and _player.progression.get_total_xp() - xp == 30 and assassin.get_target() == null,
		"DE2) killed while it backs off: DEAD where it stood — its disengage and its navigation over, nothing resumed — 30 XP paid once")
	await _clear()


# --- shadows ---------------------------------------------------------------------------------------------------------------------

func _shadow_tests() -> void:
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(0, 0, -2))
	shadow.set_physics_process(false)

	# The player and a shadow side by side in one strike: each hit once.
	_home_player()
	shadow.global_position = HOME + Vector3(0.8, 0, 0)
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(0.4, 0, -2.1))
	var hp: float = _player.health_component.current_health
	var shadow_hp: float = shadow.health_component.current_health
	var first: int = _hits.size()
	assassin.set_combat_enabled(true)
	await _until(func() -> bool: return assassin.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 90)
	var mine: Array[Dictionary] = _hits.slice(first)
	var on_player: int = mine.filter(func(h: Dictionary) -> bool: return h["target"] == _player).size()
	var on_shadow: int = mine.filter(func(h: Dictionary) -> bool: return h["target"] == shadow).size()
	_record(assassin.get_target() == _player and on_player == 1 and on_shadow == 1
			and hp - _player.health_component.current_health == 18.0 and shadow_hp - shadow.health_component.current_health == 18.0,
		"SH1) the player and a shadow in one strike: each hit once, 18 apiece — the hitbox decides, as for every melee")
	await _clear()

	# Hunting the shadow: the same loop — in, strike, out, back.
	var hunter_data: EnemyData = ASSASSIN_DATA.duplicate() as EnemyData
	hunter_data.target_groups = [Player.GROUP, BasicMeleeShadow.GROUP]
	_home_player(Vector3(-30, 0.1, 30))
	shadow.global_position = HOME + Vector3(0, 0, -1)
	shadow.health_component.current_health = shadow.health_component.max_health
	var hunter: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(0, 0, -7), hunter_data)
	first = _hits.size()
	hunter.set_combat_enabled(true)
	var farthest: Array[float] = [0.0]
	await _until(func() -> bool:
		if _hits.size() > first:
			farthest[0] = maxf(farthest[0], hunter.targeting.get_distance())
		return _hits.size() > first and hunter.get_state() == BasicEnemy.State.CHASE and farthest[0] >= 4.0, 360)
	var landed: Array[Dictionary] = _hits.slice(first)
	_record(hunter.get_target() == shadow and not landed.is_empty() and landed[0]["target"] == shadow
			and landed[0]["amount"] == 18.0 and farthest[0] >= 4.0,
		"SH2) an assassin whose data lists the shadow's group: in on the shadow, a strike of 18, then out to %.1f m — the same loop, M12.1's policy" % farthest[0])
	await _clear()
	shadow.set_physics_process(true)
	_player.shadow_summoner.recall()
	await _frames(3)


# --- several, the four archetypes, a crowd -----------------------------------------------------------------------------------

func _multiple_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var group: Array[BasicEnemy] = []
	var delays: Array[float] = [0.0, 0.4, 0.8]
	for i in 3:
		var angle: float = deg_to_rad(-60.0 + 60.0 * i)
		var enemy: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(sin(angle), 0, -cos(angle)) * 5.0)
		enemy.initial_attack_delay = delays[i]
		enemy.combat_angle_offset_degrees = -40.0 + 40.0 * i
		group.append(enemy)
	for enemy in group:
		enemy.set_combat_enabled(true)
	var disengaged: Dictionary = {}
	var apart: Array[bool] = [false]
	var cooling_apart: Array[bool] = [false]
	await _until(func() -> bool:
		for enemy in group:
			if enemy.get_state() == BasicEnemy.State.REPOSITION:
				disengaged[enemy] = true
		var phases: Array = group.map(func(e: BasicEnemy) -> int: return e.get_attack_phase())
		if phases[0] != phases[1] or phases[1] != phases[2]:
			apart[0] = true
		var cooling: Array = group.map(func(e: BasicEnemy) -> float: return e.attack.get_cooldown_remaining())
		if cooling.max() > 0.0 and not (cooling[0] == cooling[1] and cooling[1] == cooling[2]):
			cooling_apart[0] = true
		return disengaged.size() == 3 and group.all(func(e: BasicEnemy) -> bool: return e.attack.get_swing_count() >= 2), 480)
	_record(disengaged.size() == 3 and apart[0] and cooling_apart[0]
			and group.all(func(e: BasicEnemy) -> bool: return e.get_target() == _player and e.attack.get_swing_count() >= 2),
		"MU1) three assassins on the player: each strikes, disengages and comes back on its own clock — phases, disengages and cooldowns their own, one target each")
	await _clear()


func _mixed_tests() -> void:
	var indicator: TargetLockIndicator = INDICATOR_SCENE.instantiate() as TargetLockIndicator
	add_child(indicator)
	await _frames(3)
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(1.5, 0, 1))
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.AGGRESSIVE)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(-3, 0, -8))
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -10))
	var tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(3, 0, -8))
	var assassin: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(-6, 0, -8))
	var four: Array[BasicEnemy] = [melee, ranged, tank, assassin]
	for e in four:
		e.set_combat_enabled(true)
	var arrived: Dictionary = {}
	var closest_ranged: Array[float] = [100.0]
	var physics: Array[float] = [0.0]
	var ticks: Array[int] = [0]
	await _until(func() -> bool:
		ticks[0] += 1
		physics[0] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		if ranged.get_target() == _player:
			closest_ranged[0] = minf(closest_ranged[0], ranged.targeting.get_distance())
		for e in [melee, tank, assassin]:
			var enemy: BasicEnemy = e
			if not arrived.has(enemy) and enemy.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH:
				arrived[enemy] = _clock
		return arrived.size() == 3 or ticks[0] > 420, 480)
	_record(arrived.size() == 3 and arrived[assassin] < arrived[melee] and arrived[melee] < arrived[tank]
			and closest_ranged[0] >= ranged.minimum_combat_distance,
		"MX1) the four together: the assassin strikes first, then the melee, then the tank %.1f s after the assassin; the ranged keeps %.1f m at the nearest" % [
			arrived.get(tank, 0.0) - arrived.get(assassin, 0.0), closest_ranged[0]])
	# The player's kit against them: lock, switch across all four, strike, dodge.
	_player.global_position = HOME
	_player.camera_rig.rotation.y = 0.0
	_press(&"target_lock")
	var locked: Dictionary = {}
	for action in [&"target_switch_left", &"target_switch_left", &"target_switch_left", &"target_switch_right",
			&"target_switch_right", &"target_switch_right", &"target_switch_right"]:
		var target: RoomCombatant = _player.targeting.get_target()
		if target != null:
			locked[target] = true
		_press(action)
		await _frames(1)
	var stamina: float = _player.combat.get_stamina()
	_player.combat.reset()
	_player.camera_rig.attack_light_pressed.emit()
	await _until(func() -> bool: return not _player.combat.is_attacking(), 90)
	_no_crits.critical_chance = 1.0
	_player.camera_rig.attack_heavy_pressed.emit()
	await _until(func() -> bool: return not _player.combat.is_attacking(), 120)
	_no_crits.critical_chance = 0.0
	_press(&"dodge")
	var spent: bool = _player.combat.get_stamina() < stamina
	await _wait(2.0)
	var average: float = physics[0] / maxf(ticks[0], 1.0)
	var standing: bool = four.all(func(e: BasicEnemy) -> bool:
		return e.get_state() == BasicEnemy.State.DEAD or e.get_target() != null)
	_record(locked.size() == 4 and spent and _player.combat.get_stamina() > 0.0 and standing and _violations.is_empty()
			and average < PHYSICS_BUDGET and is_instance_valid(shadow),
		"MX2) with the shadow fighting too: the lock switched across all four archetypes, a light, a critical heavy and a dodge thrown in, stamina spent — every state machine consistent, %.2f ms of physics a tick" % [
			average * 1000.0])
	_player.targeting.unlock()
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	_player.shadow_summoner.recall()
	indicator.queue_free()
	await _clear()


func _stress_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var crowd: Array[BasicEnemy] = []
	for i in STRESS_COUNT:
		var angle: float = TAU * float(i) / STRESS_COUNT
		var enemy: BasicEnemy = await _spawn(ASSASSIN_SCENE, HOME + Vector3(cos(angle), 0, sin(angle)) * 7.0)
		enemy.combat_angle_offset_degrees = float(i * 23 % 90) - 45.0
		enemy.initial_attack_delay = 0.1 * (i % 5)
		crowd.append(enemy)
	for enemy in crowd:
		enemy.set_combat_enabled(true)
	await _frames(60)
	var physics: float = 0.0
	var worst: float = 0.0
	var reads: int = 0
	for enemy in crowd:
		reads -= enemy.targeting.get_refresh_count()
	var swings: int = 0
	for enemy in crowd:
		swings -= enemy.attack.get_swing_count()
	var disengages: Dictionary = {}
	for tick in 240:
		await get_tree().physics_frame
		var t: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics += t
		worst = maxf(worst, t)
		for enemy in crowd:
			if enemy.get_state() == BasicEnemy.State.REPOSITION and enemy.is_disengaging():
				disengages[enemy] = true
	for enemy in crowd:
		reads += enemy.targeting.get_refresh_count()
		swings += enemy.attack.get_swing_count()
	var average: float = physics / 240.0
	_record(average < PHYSICS_BUDGET and swings >= STRESS_COUNT and disengages.size() * 2 >= STRESS_COUNT and reads == 0
			and crowd.all(func(e: BasicEnemy) -> bool: return e.get_target() == _player),
		"PF1) %d assassins darting at the player for 4 s: %d strikes, %d of them disengaging, %.2f ms of physics a tick (%.2f at worst), no group read with targets held" % [
			STRESS_COUNT, swings, disengages.size(), average * 1000.0, worst * 1000.0])
	await _clear()
	_record(_spawned.is_empty() and get_children().filter(func(c: Node) -> bool: return c is BasicEnemy).is_empty(),
		"PF2) and freed again: nothing of the crowd left behind")


# --- helpers ----------------------------------------------------------------------------------------------------------------------

func _spawn(scene: PackedScene, at: Vector3, data: EnemyData = null) -> BasicEnemy:
	var enemy: BasicEnemy = scene.instantiate() as BasicEnemy
	_count += 1
	enemy.name = "%s%d" % [String(enemy.name).trim_prefix("Basic").trim_suffix("Enemy"), _count]
	enemy.combat_enabled = false
	if data != null:
		enemy.stats = data
	# Placed before it enters the tree: added first, it would stand at the origin
	# for a physics step and shove whatever is there.
	enemy.position = at
	add_child(enemy)
	_face(enemy, _player.global_position)
	_watch(enemy)
	_spawned.append(enemy)
	await _frames(3)
	return enemy


func _watch(enemy: BasicEnemy) -> void:
	_watched.append(enemy)
	_transitions[enemy] = []
	_transition_times[enemy] = []
	enemy.state_changed.connect(func(from: BasicEnemy.State, to: BasicEnemy.State) -> void:
		(_transitions[enemy] as Array).append("%s>%s" % [BasicEnemy.State.keys()[from], BasicEnemy.State.keys()[to]])
		(_transition_times[enemy] as Array).append(_clock))
	var melee: EnemyMeleeAttack = enemy.attack as EnemyMeleeAttack
	if melee == null:
		return
	melee.hitbox.hit_landed.connect(func(target: Node, hit: DamageInfo) -> void:
		_hits.append({"target": target, "amount": hit.amount, "attack_id": hit.attack_id, "source": hit.source,
			"phase": enemy.get_attack_phase(), "accepted": false}))
	melee.hitbox.hit_accepted.connect(func(_target: Node, _hit: DamageInfo) -> void:
		_hits[-1]["accepted"] = true)


func _time_of(enemy: BasicEnemy, transition: String) -> float:
	var at: int = (_transitions[enemy] as Array).find(transition)
	return (_transition_times[enemy] as Array)[at] if at >= 0 else -1.0


func _body_color(enemy: BasicEnemy) -> Color:
	var mat: StandardMaterial3D = enemy.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	return mat.albedo_color if mat != null else Color.BLACK


func _clear() -> void:
	for enemy in _spawned:
		if is_instance_valid(enemy):
			_last_positions.erase(enemy)
			(enemy as Node).queue_free()
	_spawned.clear()
	for child in get_children():
		if child is Projectile:
			child.queue_free()
	_player.targeting.unlock()
	_no_crits.critical_chance = 0.0
	await _frames(3)


func _summon(at: Vector3) -> BasicMeleeShadow:
	var shadow: ShadowInstance = _player.shadows.add_shadow(SHADOW_DATA)
	var node: BasicMeleeShadow = _player.shadow_summoner.summon(shadow.instance_id)
	await _frames(2)
	node.global_position = at
	node.hurtbox.set_invulnerable(false)
	await _frames(2)
	return node


func _home_player(at: Vector3 = HOME) -> void:
	_player.combat.reset()
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.health_component.current_health = _player.health_component.max_health
	_player.hurtbox.set_invulnerable(false)
	_player.combat.restore_stamina(_player.combat.get_max_stamina())


func _face(enemy: BasicEnemy, point: Vector3) -> void:
	var to: Vector3 = _flat(point - enemy.global_position)
	if to.length_squared() > 0.0001:
		enemy.visual_root.rotation.y = atan2(-to.x, -to.z)


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	_player._unhandled_input(event)


func _crafted_hit(amount: float, stagger_power: float, knockback: float) -> DamageInfo:
	var hit: DamageInfo = DamageInfo.new(amount, _player, &"test")
	hit.stagger_power = stagger_power
	hit.knockback_force = knockback
	hit.direction = Vector3.FORWARD
	return hit


func _until(condition: Callable, budget: int = 120) -> bool:
	var n: int = 0
	while not condition.call():
		if n >= budget:
			return false
		await get_tree().physics_frame
		n += 1
	return true


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
