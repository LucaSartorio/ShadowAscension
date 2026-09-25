extends Node3D

## M12.4 — the tank archetype: a melee specialised by data alone — heavier,
## slower, harder to stagger and to push, a slower and harder swing with a
## longer telegraph and a longer recovery — on the M12.1 state machine and the
## M12.2 melee attack, against the player's whole M11 kit, beside a melee and a
## ranged.
##
##   godot --headless --path . res://tests/enemies/tank_archetype_test.tscn
##
## Every section spawns what it needs and frees it again. Every tick a watcher
## checks each enemy's attack against its state and its hitbox, and every hit a
## tank's swing lands is recorded with the phase it landed in.

const TANK_SCENE: PackedScene = preload("res://scenes/enemies/basic_tank_enemy.tscn")
const MELEE_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://scenes/enemies/basic_ranged_enemy.tscn")
const INDICATOR_SCENE: PackedScene = preload("res://scenes/ui/target_lock_indicator.tscn")
const TANK_DATA: EnemyData = preload("res://resources/enemies/basic_tank_enemy.tres")
const MELEE_DATA: EnemyData = preload("res://resources/enemies/basic_melee_enemy.tres")
const SHADOW_DATA: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
const HOME: Vector3 = Vector3(0, 0.1, 0)
## In the tank's band — 1.4 to 2.3 m — and past the melee's 1.8 m reach.
const IN_REACH: Vector3 = Vector3(0, 0.1, -2.1)
const PARK: Vector3 = Vector3(35, 0.1, 35)
## The back wall's face is at z -29.5.
const WALL_FACE_Z: float = -29.5
const DT: float = 1.0 / 60.0
## A physics tick must fit in one 60 Hz tick, or the game falls behind.
const PHYSICS_BUDGET: float = 1.0 / 60.0

@onready var _player: Player = $Player
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _swing: AttackData = null
var _spawned: Array = []
var _watched: Array = []
var _violations: Array[String] = []
## Every hit a watched enemy's swing landed: {enemy, target, amount, attack_id, source, critical, phase, accepted}.
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
	_swing = TANK_DATA.attacks[0]
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
		if (e.get_state() == BasicEnemy.State.STAGGERED or e.get_state() == BasicEnemy.State.DEAD) \
				and phase != EnemyAttack.Phase.NONE:
			_violations.append("%s attacking while %s" % [e.name, BasicEnemy.State.keys()[e.get_state()]])


func _run() -> void:
	await _wait(0.4)
	await _config_tests()
	await _approach_tests()
	await _swing_tests()
	await _dodge_tests()
	await _punish_tests()
	await _stagger_tests()
	await _knockback_tests()
	await _critical_tests()
	await _death_tests()
	await _shadow_tests()
	await _multiple_tests()
	await _mixed_tests()
	await _hit_stop_tests()
	await _wait(0.3)
	_record(_violations.is_empty(),
		"IV1) every tick, on every enemy: an attack phase exactly in ATTACK, the hitbox open exactly in ACTIVE, nothing under way in STAGGERED or DEAD %s" % [
			_violations.slice(0, 4)])
	var tank_hits: Array[Dictionary] = _hits.filter(func(h: Dictionary) -> bool: return h["attack_id"] == &"tank_heavy_swing")
	_record(tank_hits.all(func(h: Dictionary) -> bool: return h["phase"] == EnemyAttack.Phase.ACTIVE),
		"IV2) every one of the %d hits a tank landed, landed in ACTIVE" % tank_hits.size())
	_record(TANK_DATA.max_health == 260.0 and TANK_DATA.stagger_resistance == 45.0 and _swing.windup == 0.8
			and MELEE_DATA.max_health == 100.0 and MELEE_DATA.attacks[0].windup == 0.35,
		"IV3) the shared EnemyData and AttackData — the tank's and the melee's — were never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration ------------------------------------------------------------------------------------

func _config_tests() -> void:
	var tank: BasicEnemy = await _spawn(TANK_SCENE, PARK)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, PARK + Vector3(4, 0, 0))
	var basic: AttackData = MELEE_DATA.attacks[0]
	_record(TANK_DATA.max_health == 260.0 and TANK_DATA.movement_speed == 2.4 and TANK_DATA.attack_range == 2.3
			and TANK_DATA.preferred_combat_distance == 2.0 and TANK_DATA.minimum_combat_distance == 1.4
			and TANK_DATA.stagger_resistance == 45.0 and TANK_DATA.knockback_multiplier == 0.35
			and TANK_DATA.attack_cooldown == 1.2 and TANK_DATA.attack_damage == 20.0 and TANK_DATA.xp_reward == 50
			and TANK_DATA.max_health > MELEE_DATA.max_health and TANK_DATA.movement_speed < MELEE_DATA.movement_speed
			and TANK_DATA.stagger_resistance > MELEE_DATA.stagger_resistance
			and TANK_DATA.knockback_multiplier < MELEE_DATA.knockback_multiplier,
		"CF1) the tank is data: 260 HP (melee 100), 2.4 m/s (3.8), reach 2.3 m, ring 2.0 m, minimum 1.4 m, stagger resistance 45 (25), knockback x0.35 (1.0), cooldown 1.2 s, 50 XP")
	_record(_swing.id == &"tank_heavy_swing" and _swing.windup == 0.8 and _swing.active == 0.2 and _swing.recovery == 1.1
			and _swing.damage_multiplier == 1.5 and _swing.windup > basic.windup and _swing.recovery > basic.recovery
			and tank.attack.hitbox.damage == 30.0,
		"CF2) its attack, `tank_heavy_swing`: telegraph 0.8 s (melee 0.35), active 0.2 s, recovery 1.1 s (0.65), x1.5 of its base 20 — 30 damage (15)")
	var box: BoxShape3D = tank.attack.hitbox.get_node("CollisionShape3D").shape as BoxShape3D
	var origin_z: float = absf((tank.attack.hitbox.get_parent() as Node3D).position.z)
	var near_edge: float = origin_z - box.size.z * 0.5
	var far_edge: float = origin_z + box.size.z * 0.5
	var anchor_higher: bool = tank.get_target_point().y - tank.global_position.y > melee.get_target_point().y - melee.global_position.y
	_record(tank.get_script() == melee.get_script() and tank.attack.get_script() == melee.attack.get_script()
			and tank.attack is EnemyMeleeAttack and far_edge >= tank.attack_range and near_edge <= tank.minimum_combat_distance
			and tank.nav_agent.radius == TANK_DATA.enemy_spacing_radius and anchor_higher,
		"CF3) the same state machine and the same melee attack as the melee — no tank script — with a bigger body: its hitbox reaches %.1f–%.1f m around its 1.4–2.3 m band, its avoidance radius 1.0 m, its lock anchor higher" % [
			near_edge, far_edge])
	_record(tank.get_state() == BasicEnemy.State.IDLE and tank.health_component.max_health == 260.0
			and tank.health_component.current_health == 260.0 and tank.movement_speed == 2.4 and tank.get_target() == null,
		"SP1) spawned: IDLE, 260 of 260 HP, moving at 2.4 m/s, no target")
	await _clear()


# --- detection, chase, range ----------------------------------------------------------------------------

func _approach_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(-1.5, 0, -8))
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(1.5, 0, -8))
	var tank_start: float = _flat(tank.global_position - _player.global_position).length()
	var melee_start: float = _flat(melee.global_position - _player.global_position).length()
	tank.set_combat_enabled(true)
	melee.set_combat_enabled(true)
	await _until(func() -> bool: return tank.get_state() == BasicEnemy.State.CHASE, 60)
	var seen: Array = _transitions[tank]
	var alert: float = _time_of(tank, "ALERT>CHASE") - _time_of(tank, "IDLE>ALERT")
	_record(seen.size() >= 2 and seen[0] == "IDLE>ALERT" and seen[1] == "ALERT>CHASE" and absf(alert - 0.4) <= 2.0 * DT,
		"DT1) the player 8 m away: IDLE -> ALERT, %.2f s squaring up to it, then CHASE" % alert)
	var fastest: Array[float] = [0.0]
	await _until(func() -> bool:
		fastest[0] = maxf(fastest[0], _flat(tank.velocity).length())
		return false, 72)
	var tank_closed: float = tank_start - tank.targeting.get_distance()
	var melee_closed: float = melee_start - melee.targeting.get_distance()
	_record(fastest[0] <= 2.45 and tank_closed > 1.0 and tank_closed < melee_closed * 0.75,
		"CH1) side by side, both chasing: the tank closes %.2f m to the melee's %.2f m, never faster than %.2f m/s" % [
			tank_closed, melee_closed, fastest[0]])
	melee.queue_free()
	var from: Array[float] = [-1.0]
	var reached: bool = await _until(func() -> bool:
		if tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH and from[0] < 0.0:
			from[0] = tank.targeting.get_distance()
		return from[0] > 0.0, 300)
	_record(reached and from[0] <= tank.attack_range and from[0] > MELEE_DATA.attack_range,
		"AR1) in range: CHASE -> ATTACK, its telegraph starting %.2f m out — within its 2.3 m reach, beyond a melee's 1.8 m" % from[0])
	await _clear()


# --- the swing -------------------------------------------------------------------------------------------------

func _swing_tests() -> void:
	_home_player()
	var tank: BasicEnemy = await _spawn(TANK_SCENE, IN_REACH)
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	tank.set_combat_enabled(true)
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 60)
	var began: float = _clock
	var quiet: bool = true
	var reared: bool = false
	while tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH:
		quiet = quiet and not tank.attack.hitbox.is_active() and _player.health_component.current_health == hp
		reared = reared or (tank.visual_root.scale.y > 1.15 and _body_color(tank).r > 0.8 and _body_color(tank).b < 0.35)
		await get_tree().physics_frame
	var telegraph: float = _clock - began
	_record(quiet and reared and absf(telegraph - _swing.windup) <= 2.0 * DT,
		"TG1) the telegraph: %.2f s — more than twice the melee's — the hitbox shut, no damage, the body rearing high and turning orange" % telegraph)
	var active_began: float = _clock
	while tank.get_attack_phase() == EnemyAttack.Phase.ACTIVE:
		await get_tree().physics_frame
	var active: float = _clock - active_began
	var mine: Array[Dictionary] = _hits.slice(first)
	_record(mine.size() == 1 and mine[0]["target"] == _player and mine[0]["accepted"] and mine[0]["amount"] == 30.0
			and mine[0]["attack_id"] == &"tank_heavy_swing" and mine[0]["source"] == tank and not mine[0]["critical"]
			and hp - _player.health_component.current_health == 30.0 and absf(active - _swing.active) <= 2.0 * DT,
		"HT1) not avoided: one hit of 30 — the melee's is 15 — from the tank, named tank_heavy_swing, in a %.2f s window" % active)
	var recovery_began: float = _clock
	var shut: bool = true
	while tank.get_attack_phase() == EnemyAttack.Phase.RECOVERY:
		shut = shut and not tank.attack.hitbox.is_active() and tank.get_state() == BasicEnemy.State.ATTACK
		await get_tree().physics_frame
	var recovery: float = _clock - recovery_began
	var over: float = _clock
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 150)
	var cooldown: float = _clock - over
	_record(shut and absf(recovery - _swing.recovery) <= 2.0 * DT and absf(cooldown - 1.2) <= 3.0 * DT
			and _hits.size() - first == 1,
		"RC1) then %.2f s of recovery, committed, the hitbox shut — and %.2f s of cooldown before the next: never swing on swing" % [
			recovery, cooldown])
	await _clear()

	# Commitment: circled early, it barely follows; in the last 0.3 s it does not turn at all.
	_home_player()
	tank = await _spawn(TANK_SCENE, IN_REACH)
	tank.set_combat_enabled(true)
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 60)
	var yaw: float = tank.visual_root.rotation.y
	_player.global_position = IN_REACH + Vector3(2.1, 0, 0)
	await _until(func() -> bool: return tank.attack.get_turn_factor() == 0.0, 60)
	var tracked: float = rad_to_deg(absf(wrapf(tank.visual_root.rotation.y - yaw, -PI, PI)))
	var locked_yaw: float = tank.visual_root.rotation.y
	var still: bool = true
	while tank.get_state() == BasicEnemy.State.ATTACK:
		still = still and is_equal_approx(tank.visual_root.rotation.y, locked_yaw)
		await get_tree().physics_frame
	_record(tracked > 1.0 and tracked < 20.0 and still,
		"FC1) the player circles 90 deg as it winds up: it follows %.0f deg at 15%% of its turn speed; from 0.3 s before the blow, and through the blow and the recovery, it does not turn" % tracked)
	await _clear()


# --- the player's answers ---------------------------------------------------------------------------------------

func _dodge_tests() -> void:
	# Stepping out after the facing locks: no homing, a clean miss.
	_home_player()
	var tank: BasicEnemy = await _spawn(TANK_SCENE, IN_REACH)
	var hp: float = _player.health_component.current_health
	var first: int = _hits.size()
	tank.set_combat_enabled(true)
	await _until(func() -> bool:
		return (tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and tank.attack.get_phase_remaining() < TANK_DATA.telegraph_facing_lock), 90)
	_player.global_position = HOME + Vector3(3.2, 0, 0)
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 60)
	_record(_hits.size() == first and _player.health_component.current_health == hp,
		"MV1) the player steps 3 m aside in the last 0.3 s of the telegraph: the swing goes where it was aimed and misses")
	await _clear()

	# Dodging in place into the blow: the i-frames take it.
	_home_player()
	tank = await _spawn(TANK_SCENE, IN_REACH)
	hp = _player.health_component.current_health
	first = _hits.size()
	tank.set_combat_enabled(true)
	await _until(func() -> bool:
		return (tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and tank.attack.get_phase_remaining() <= 0.1), 90)
	var speed: float = _player.effective_dodge_speed
	_player.effective_dodge_speed = 0.0
	var stamina: float = _player.combat.get_stamina()
	_press(&"dodge")
	var paid: float = stamina - _player.combat.get_stamina()
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 60)
	_player.effective_dodge_speed = speed
	var reached: Array[Dictionary] = _hits.slice(first)
	var low: float = _player.combat.get_stamina()
	await _wait(1.6)
	_record(reached.size() == 1 and not reached[0]["accepted"] and _player.health_component.current_health == hp
			and paid == _player.combat.data.dodge_stamina_cost and _player.combat.get_stamina() > low,
		"IF1) dodging into the blow: it reaches the player inside the i-frames and is refused — no damage; the dodge cost %.0f stamina, and it comes back" % paid)
	await _clear()


func _punish_tests() -> void:
	# A missed swing leaves it standing through a long recovery: the player walks
	# in and lands a combo before it can swing again.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _spawn(TANK_SCENE, IN_REACH)
	tank.set_combat_enabled(true)
	await _until(func() -> bool:
		return (tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and tank.attack.get_phase_remaining() < TANK_DATA.telegraph_facing_lock), 90)
	_player.global_position = HOME + Vector3(3.2, 0, 0)
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 60)
	_player.global_position = tank.global_position + Vector3(0, 0, 1.6)
	_player.camera_rig.rotation.y = 0.0
	var landed_in_recovery: Array[int] = [0]
	var on_damaged: Callable = func(_hit: DamageInfo) -> void:
		if tank.get_attack_phase() == EnemyAttack.Phase.RECOVERY:
			landed_in_recovery[0] += 1
	tank.health_component.damaged.connect(on_damaged)
	_player.combat.reset()
	_player.camera_rig.attack_light_pressed.emit()
	await _until(func() -> bool:
		if _player.combat.get_state() == PlayerCombat.State.RECOVERY and _player.combat.get_queued_attack() == null \
				and _player.combat.get_combo_index() < 1:
			_player.camera_rig.attack_light_pressed.emit()
		return _player.combat.get_combo_index() >= 1 and not _player.combat.is_attacking(), 120)
	tank.health_component.damaged.disconnect(on_damaged)
	_record(landed_in_recovery[0] >= 2,
		"PN1) the tank's swing misses: through its 1.1 s recovery the player walks in and lands Light 1 and Light 2 (%d hits) before it can swing again" % landed_in_recovery[0])
	await _clear()


# --- stagger -------------------------------------------------------------------------------------------------------

func _stagger_tests() -> void:
	# Light 1 and Light 2 in its telegraph: damage, a flinch, and the swing goes on.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(0, 0, -1.6))
	tank._reposition_block_timer = 30.0
	tank.set_combat_enabled(true)
	var taken: Array[float] = []
	tank.health_component.damaged.connect(func(hit: DamageInfo) -> void: taken.append(hit.amount))
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return taken.size() >= 1, 30)
	var after_l1: bool = not tank.is_staggered()
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 1)
	await _until(func() -> bool: return taken.size() >= 2, 30)
	var after_l2: bool = not tank.is_staggered()
	var went_on: bool = await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.ACTIVE, 60)
	_record(taken == [20.0, 25.0] and after_l1 and after_l2 and went_on,
		"ST1) Light 1 (stagger 10) and Light 2 (15) in its telegraph: %s damage, flinches only — below its 45 — and the swing goes on to ACTIVE" % [taken])
	await _clear()

	# The whole light combo, against a tank and against a melee.
	var tank_combo: Array = await _light_combo_against(TANK_SCENE)
	var melee_combo: Array = await _light_combo_against(MELEE_SCENE)
	_record(tank_combo[0] == [20.0, 25.0, 35.0] and tank_combo[1] == [false, false, false]
			and melee_combo[1] == [false, false, true],
		"ST2) the light combo: Light 3's stagger 30 staggers a melee (25) but not the tank (45) — %s, staggered %s; the melee %s" % [
			tank_combo[0], tank_combo[1], melee_combo[1]])

	# The heavy (60) in its telegraph: cancelled.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	tank = await _spawn(TANK_SCENE, HOME + Vector3(0, 0, -1.6))
	tank._reposition_block_timer = 30.0
	tank.set_combat_enabled(true)
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.heavy_combo, 0)
	var staggered: bool = await _until(func() -> bool: return tank.is_staggered(), 60)
	var cancelled: bool = tank.get_attack_phase() == EnemyAttack.Phase.NONE and not tank.attack.hitbox.is_active()
	var stagger_began: float = _clock
	var never_opened: bool = true
	while tank.is_staggered():
		never_opened = never_opened and not tank.attack.hitbox.is_active()
		await get_tree().physics_frame
	var stood: float = _clock - stagger_began
	var back: bool = await _until(func() -> bool:
		return tank.get_state() == BasicEnemy.State.CHASE or tank.get_state() == BasicEnemy.State.ATTACK, 60)
	_record(staggered and cancelled and never_opened and absf(stood - TANK_DATA.stagger_duration) <= 3.0 * DT and back,
		"ST3) the heavy (stagger 60) in its telegraph beats its 45: the swing cancelled, no ACTIVE, STAGGERED %.2f s — shorter than a melee's — then back to the fight" % stood)
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
	# The same heavy against a melee and against a tank, both standing idle.
	var melee_push: Array = await _heavy_push(MELEE_SCENE, HOME + Vector3(0, 0, -1.6))
	var tank_push: Array = await _heavy_push(TANK_SCENE, HOME + Vector3(0, 0, -1.6))
	var ratio: float = tank_push[1] / maxf(melee_push[1], 0.001)
	_record(absf(melee_push[0] - 8.0) < 0.01 and absf(tank_push[0] - 8.0 * 0.35) < 0.01 and ratio < 0.25 and tank_push[1] > 0.02,
		"KB1) the same heavy: a melee is pushed at %.1f m/s, %.2f m; the tank at %.1f m/s, %.2f m — %.0f%% of the distance: moved a little, not thrown" % [
			melee_push[0], melee_push[1], tank_push[0], tank_push[1], ratio * 100.0])
	var melee_light: Array = await _push_by(MELEE_SCENE, HOME + Vector3(0, 0, -1.6), _player.combat.data.light_combo, 2)
	var tank_light: Array = await _push_by(TANK_SCENE, HOME + Vector3(0, 0, -1.6), _player.combat.data.light_combo, 2)
	_record(tank_light[1] < 0.1 and tank_light[1] < melee_light[1] * 0.25,
		"KB2) Light 3, the lights' hardest push (4.5 m/s): the tank gives %.3f m where a melee gives %.2f m — not dragged about by the combo" % [
			tank_light[1], melee_light[1]])

	# Against the wall: shoved into it, it stops at it, then fights on.
	_home_player(Vector3(0, 0.1, WALL_FACE_Z + 2.4))
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _spawn(TANK_SCENE, Vector3(0, 0.1, WALL_FACE_Z + 0.7))
	tank.set_combat_enabled(true)
	await _frames(3)
	_player.combat.reset()
	_player.camera_rig.rotation.y = 0.0
	_player.combat._start_attack(_player.combat.data.heavy_combo, 0)
	var pushed: bool = await _until(func() -> bool: return tank.is_knocked_back(), 60)
	var deepest: Array[float] = [tank.global_position.z]
	await _until(func() -> bool:
		deepest[0] = minf(deepest[0], tank.global_position.z)
		return not tank.is_knocked_back(), 60)
	var resumed: bool = await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 240)
	_record(pushed and deepest[0] >= WALL_FACE_Z + 0.55 and resumed,
		"WL1) shoved by a heavy against a wall: it stops at the wall (its back %.2f m from the face) — no clipping — and after the stagger fights on" % [
			deepest[0] - 0.6 - WALL_FACE_Z])
	await _clear()

	# Pushed mid-chase: the navigation does not cancel the push, and the chase resumes.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	tank = await _spawn(TANK_SCENE, HOME + Vector3(0, 0, -6))
	tank.set_combat_enabled(true)
	await _until(func() -> bool: return tank.get_state() == BasicEnemy.State.CHASE and _flat(tank.velocity).length() > 1.5, 120)
	var at: Vector3 = tank.global_position
	tank.hurtbox.receive_hit(_crafted_hit(1.0, 0.0, 12.0))
	await _until(func() -> bool: return not tank.is_knocked_back(), 60)
	var back: float = at.z - tank.global_position.z
	var chased: bool = await _until(func() -> bool: return tank.targeting.get_distance() <= tank.attack_range, 240)
	_record(back > 0.15 and chased,
		"KB3) pushed mid-chase (12 m/s): the push carries it %.2f m back against its own chase — the navigation does not cancel it — then it closes in again" % back)
	await _clear()


## Pushes a parked `scene` with one heavy; returns [push speed, distance moved].
func _heavy_push(scene: PackedScene, at: Vector3) -> Array:
	return await _push_by(scene, at, _player.combat.data.heavy_combo, 0)


func _push_by(scene: PackedScene, at: Vector3, chain: Array[AttackData], index: int) -> Array:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var enemy: BasicEnemy = await _spawn(scene, at)
	enemy.health_component.set_max_health(1000.0)
	enemy.health_component.current_health = 1000.0
	var start: Vector3 = enemy.global_position
	var speed: Array[float] = [0.0]
	enemy.health_component.damaged.connect(func(_hit: DamageInfo) -> void:
		speed[0] = enemy.get_knockback_velocity().length())
	_player.combat.reset()
	_player.combat._start_attack(chain, index)
	await _until(func() -> bool: return speed[0] > 0.0, 60)
	await _until(func() -> bool: return not enemy.is_knocked_back(), 90)
	var moved: float = _flat(enemy.global_position - start).length()
	await _clear()
	return [speed[0], moved]


# --- criticals -------------------------------------------------------------------------------------------------------

func _critical_tests() -> void:
	var plain: Array = await _one_hit(false)
	var crit: Array = await _one_hit(true)
	_record(plain[0] == 40.0 and crit[0] == 60.0 and plain[1] and crit[1] and absf(plain[2] - crit[2]) < 0.001,
		"CR1) a heavy on the tank: 40, or 60 when critical — the critical changes the damage only: both stagger it, both push it at %.1f m/s" % crit[2])
	var light_plain: Array = await _one_hit(false, true)
	var light_crit: Array = await _one_hit(true, true)
	_record(light_plain[0] == 20.0 and light_crit[0] == 30.0 and not light_plain[1] and not light_crit[1]
			and absf(light_plain[2] - light_crit[2]) < 0.001,
		"CR2) Light 1 on the tank: 20, or 30 critical — neither staggers it, both push it the same %.2f m/s" % light_crit[2])


## One player hit on a fresh tank; returns [damage, staggered, push speed].
func _one_hit(critical: bool, light: bool = false) -> Array:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(0, 0, -1.6))
	var result: Array = [0.0, false, 0.0]
	tank.health_component.damaged.connect(func(hit: DamageInfo) -> void:
		result[0] = hit.amount
		result[1] = tank.is_staggered()
		result[2] = tank.get_knockback_velocity().length())
	var marks: int = _player.combat_feedback.get_critical_mark_count()
	_no_crits.critical_chance = 1.0 if critical else 0.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo if light else _player.combat.data.heavy_combo, 0)
	await _until(func() -> bool: return result[0] > 0.0, 60)
	_no_crits.critical_chance = 0.0
	if critical and _player.combat_feedback.get_critical_mark_count() <= marks:
		result[0] = -1.0
	await _clear()
	return result


# --- death ---------------------------------------------------------------------------------------------------------------

func _death_tests() -> void:
	_home_player()
	var tank: BasicEnemy = await _spawn(TANK_SCENE, IN_REACH)
	var hp: float = _player.health_component.current_health
	tank.set_combat_enabled(true)
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 60)
	tank.hurtbox.receive_hit(_crafted_hit(1000.0, 0.0, 0.0))
	var dead: bool = tank.get_state() == BasicEnemy.State.DEAD
	var never_opened: bool = true
	for i in 60:
		await get_tree().physics_frame
		never_opened = never_opened and not tank.attack.hitbox.is_active()
	_record(dead and never_opened and _player.health_component.current_health == hp and tank.get_target() == null,
		"DE1) killed in its telegraph: DEAD at once, no ACTIVE, the hitbox never opens, no target")
	await _clear()

	# Killed by the player's strike while its hitbox is open: shut at once, paid once.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	tank = await _spawn(TANK_SCENE, HOME + Vector3(0, 0, -1.6))
	tank._reposition_block_timer = 30.0
	var deaths: Array[int] = [0]
	tank.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	var xp: int = _player.progression.get_total_xp()
	tank.set_combat_enabled(true)
	await _until(func() -> bool:
		return (tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH
			and tank.attack.get_phase_remaining() <= 0.1), 120)
	tank.health_component.current_health = 1.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	var in_active: Array[bool] = [false]
	tank.health_component.died.connect(func() -> void:
		in_active[0] = tank.get_attack_phase() == EnemyAttack.Phase.ACTIVE or tank.attack.hitbox.is_active())
	await _until(func() -> bool: return tank.get_state() == BasicEnemy.State.DEAD, 60)
	var shut: bool = not tank.attack.hitbox.is_active()
	await _frames(10)
	_record(tank.get_state() == BasicEnemy.State.DEAD and shut and deaths[0] == 1
			and _player.progression.get_total_xp() - xp == 50,
		"DE2) killed by the player's strike mid-swing%s: the hitbox shut at once, DEAD, 50 XP paid once" % [
			" (in ACTIVE)" if in_active[0] else ""])
	await _clear()


# --- shadows ---------------------------------------------------------------------------------------------------------------

func _shadow_tests() -> void:
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(0, 0, -2))
	shadow.set_physics_process(false)

	# The player and a shadow side by side in one swing: each hit once.
	_home_player()
	shadow.global_position = HOME + Vector3(0.9, 0, 0)
	var tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(0.45, 0, -2.1))
	var hp: float = _player.health_component.current_health
	var shadow_hp: float = shadow.health_component.current_health
	var first: int = _hits.size()
	tank.set_combat_enabled(true)
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.RECOVERY, 120)
	var mine: Array[Dictionary] = _hits.slice(first)
	var on_player: int = mine.filter(func(h: Dictionary) -> bool: return h["target"] == _player).size()
	var on_shadow: int = mine.filter(func(h: Dictionary) -> bool: return h["target"] == shadow).size()
	_record(tank.get_target() == _player and on_player == 1 and on_shadow == 1
			and hp - _player.health_component.current_health == 30.0 and shadow_hp - shadow.health_component.current_health == 30.0,
		"SH1) the player and a shadow in one swing: its target is the player, the hitbox decides — each hit once, 30 apiece")
	await _clear()

	# A tank whose data lists the shadow's group hunts the shadow.
	var hunter_data: EnemyData = TANK_DATA.duplicate() as EnemyData
	hunter_data.target_groups = [Player.GROUP, BasicMeleeShadow.GROUP]
	_home_player(Vector3(-30, 0.1, 30))
	shadow.global_position = HOME + Vector3(0, 0, -1)
	shadow_hp = shadow.health_component.current_health
	var hunter: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(0, 0, -6), hunter_data)
	first = _hits.size()
	var phases: Array[String] = []
	hunter.set_combat_enabled(true)
	var frames: int = 0
	while frames < 400 and _hits.size() == first:
		var phase: String = EnemyAttack.Phase.keys()[hunter.get_attack_phase()]
		if phases.is_empty() or phases[-1] != phase:
			phases.append(phase)
		await get_tree().physics_frame
		frames += 1
	var landed: Array[Dictionary] = _hits.slice(first)
	_record(hunter.get_target() == shadow and phases.has("TELEGRAPH") and landed.size() == 1 and landed[0]["target"] == shadow
			and shadow_hp - shadow.health_component.current_health == 30.0,
		"SH2) a tank whose data lists the shadow's group chases the shadow, telegraphs and hits it for 30 — M12.1's policy, nothing tank-specific")
	await _clear()
	shadow.set_physics_process(true)
	_player.shadow_summoner.recall()
	await _frames(3)


# --- several, and a mixed encounter ------------------------------------------------------------------------------------------

func _multiple_tests() -> void:
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var a: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(-1.2, 0, -1.8))
	var b: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(1.2, 0, -1.8))
	b.initial_attack_delay = 0.5
	a.set_combat_enabled(true)
	b.set_combat_enabled(true)
	await _until(func() -> bool: return a.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	var apart: bool = b.get_attack_phase() == EnemyAttack.Phase.NONE
	a.hurtbox.receive_hit(_crafted_hit(50.0, 60.0, 0.0))
	var own_health: bool = a.health_component.current_health == 210.0 and b.health_component.current_health == 260.0
	var own_stagger: bool = a.is_staggered() and not b.is_staggered()
	await _until(func() -> bool: return b.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	var b_swings: bool = b.get_state() == BasicEnemy.State.ATTACK and a.get_state() != BasicEnemy.State.ATTACK
	await _until(func() -> bool: return b.attack.get_cooldown_remaining() > 0.0, 150)
	var own_cooldown: bool = absf(a.attack.get_cooldown_remaining() - b.attack.get_cooldown_remaining()) > 0.05
	_record(apart and own_health and own_stagger and b_swings and own_cooldown and a.get_target() == _player
			and b.get_target() == _player,
		"MU1) two tanks: one hit and staggered — its health and its stagger its own — while the other winds up and swings on its own clock, its cooldown its own")
	await _clear()


func _mixed_tests() -> void:
	var indicator: TargetLockIndicator = INDICATOR_SCENE.instantiate() as TargetLockIndicator
	add_child(indicator)
	await _frames(3)
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var melee: BasicEnemy = await _spawn(MELEE_SCENE, HOME + Vector3(-3, 0, -7))
	var ranged: BasicEnemy = await _spawn(RANGED_SCENE, HOME + Vector3(0, 0, -9))
	var tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(3, 0, -7))
	for e in [melee, ranged, tank]:
		(e as BasicEnemy).set_combat_enabled(true)
	var arrived: Dictionary = {}
	var closest_ranged: Array[float] = [100.0]
	var tank_fastest: Array[float] = [0.0]
	var physics: Array[float] = [0.0]
	var ticks: Array[int] = [0]
	await _until(func() -> bool:
		ticks[0] += 1
		physics[0] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		tank_fastest[0] = maxf(tank_fastest[0], _flat(tank.velocity).length())
		if ranged.get_target() != null:
			closest_ranged[0] = minf(closest_ranged[0], ranged.targeting.get_distance())
		for e in [melee, tank]:
			var enemy: BasicEnemy = e
			if not arrived.has(enemy) and enemy.get_target() != null and enemy.targeting.get_distance() <= enemy.attack_range:
				arrived[enemy] = _clock
		return arrived.size() == 2 or ticks[0] > 360, 400)
	_record(arrived.has(melee) and arrived.has(tank) and arrived[melee] < arrived[tank] - 0.5
			and closest_ranged[0] >= ranged.minimum_combat_distance and tank_fastest[0] <= 2.45
			and [melee, ranged, tank].all(func(e: BasicEnemy) -> bool: return e.get_target() == _player),
		"MX1) a melee, a ranged and a tank on the player: the melee arrives first, the tank %.1f s later at no more than %.2f m/s, the ranged keeps its distance (%.1f m at the nearest) — one target foundation, three roles" % [
			arrived.get(tank, 0.0) - arrived.get(melee, 0.0), tank_fastest[0], closest_ranged[0]])
	# The lock, switched through all three.
	_press(&"target_lock")
	var locked: Dictionary = {}
	var ringed: bool = true
	# Switching goes the way it is pressed and does not wrap: sweep left, then right.
	for action in [&"target_switch_left", &"target_switch_left", &"target_switch_right", &"target_switch_right",
			&"target_switch_right"]:
		var target: RoomCombatant = _player.targeting.get_target()
		if target != null:
			locked[target] = true
			await _frames(1)
			ringed = ringed and indicator.get_target() == target \
				and indicator.global_position.distance_to(target.get_target_point()) < 0.1
		_press(action)
	_record(locked.has(melee) and locked.has(ranged) and locked.has(tank) and ringed,
		"MX2) the lock switched through them: melee, ranged and tank each locked in turn, the ring on each — on the tank at its higher anchor")
	_player.targeting.unlock()
	await _wait(1.5)
	var average: float = physics[0] / maxf(ticks[0], 1.0)
	_record(average < PHYSICS_BUDGET and _violations.is_empty()
			and [melee, ranged, tank].all(func(e: BasicEnemy) -> bool: return e.get_target() == _player),
		"MX3) the three together: %.2f ms of physics a tick, every state machine consistent, every target held" % [average * 1000.0])
	indicator.queue_free()
	await _clear()


# --- the hit stop -------------------------------------------------------------------------------------------------------------

func _hit_stop_tests() -> void:
	# Struck in its telegraph: the telegraph keeps its game-time length.
	_home_player()
	_player.hurtbox.set_invulnerable(true)
	var tank: BasicEnemy = await _spawn(TANK_SCENE, HOME + Vector3(0, 0, -1.6))
	tank._reposition_block_timer = 30.0
	tank.set_combat_enabled(true)
	await _until(func() -> bool: return tank.get_attack_phase() == EnemyAttack.Phase.TELEGRAPH, 90)
	var began: float = _clock
	var tick: int = Engine.get_physics_frames()
	var stops: int = _player.combat_feedback.get_hit_stop_count()
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return tank.get_attack_phase() != EnemyAttack.Phase.TELEGRAPH, 90)
	var game: float = _clock - began
	var wall: float = (Engine.get_physics_frames() - tick) * DT
	_record(_player.combat_feedback.get_hit_stop_count() > stops and absf(game - _swing.windup) <= 2.0 * DT
			and wall > game + DT and tank.get_attack_phase() == EnemyAttack.Phase.ACTIVE,
		"HS1) struck in its telegraph, with the hit stop that brings: the telegraph still lasts %.2f s of game time (%.2f s on the wall) and the swing goes on" % [
			game, wall])
	await _until(func() -> bool: return tank.get_state() == BasicEnemy.State.CHASE, 120)
	# Staggered by a heavy: the stagger keeps its game-time length through the heavy's own hit stop.
	await _until(func() -> bool: return not tank.is_stagger_immune(), 120)
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.heavy_combo, 0)
	await _until(func() -> bool: return tank.is_staggered(), 60)
	var stood: float = await _time_staggered(tank)
	_record(absf(stood - TANK_DATA.stagger_duration) <= 3.0 * DT,
		"HS2) staggered by a heavy and its hit stop: the stagger still lasts %.2f s of game time" % stood)
	await _clear()


# --- helpers -----------------------------------------------------------------------------------------------------------------

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
		_hits.append({"enemy": enemy, "target": target, "amount": hit.amount, "attack_id": hit.attack_id,
			"source": hit.source, "critical": hit.is_critical, "phase": enemy.get_attack_phase(), "accepted": false}))
	melee.hitbox.hit_accepted.connect(func(_target: Node, _hit: DamageInfo) -> void:
		_hits[-1]["accepted"] = true)


## Game time from now until `enemy` is no longer staggered.
func _time_staggered(enemy: BasicEnemy) -> float:
	var began: float = _clock
	await _until(func() -> bool: return not enemy.is_staggered(), 120)
	return _clock - began


func _time_of(enemy: BasicEnemy, transition: String) -> float:
	var at: int = (_transitions[enemy] as Array).find(transition)
	return (_transition_times[enemy] as Array)[at] if at >= 0 else -1.0


func _body_color(enemy: BasicEnemy) -> Color:
	var mat: StandardMaterial3D = enemy.mesh_instance.get_surface_override_material(0) as StandardMaterial3D
	return mat.albedo_color if mat != null else Color.BLACK


func _clear() -> void:
	for enemy in _spawned:
		if is_instance_valid(enemy):
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
