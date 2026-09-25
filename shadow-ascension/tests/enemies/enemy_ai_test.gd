extends Node3D

## M12.1 — the enemy AI foundation: the state machine, the target, navigation,
## the attack, the reactions and death, on real enemies against a real player.
##
##   godot --headless --path . res://tests/enemies/enemy_ai_test.tscn
##
## The three scene enemies start parked; enemies that die are spawned for it,
## from the real scene, and freed afterwards. An every-tick watcher checks that
## the state is the one source of truth: a fighting state always has a target,
## IDLE and DEAD never do, ATTACK and an attack phase go together, the hitbox is
## only ever open in ACTIVE, DEAD and a dead health component go together.

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")
const ENEMY_DATA_PATH: String = "res://resources/enemies/basic_melee_enemy.tres"
const SHADOW_DATA: ShadowData = preload("res://resources/shadows/basic_melee_shadow.tres")
const PARKED: Array[Vector3] = [Vector3(-20, 0.1, 20), Vector3(-16, 0.1, 20), Vector3(-12, 0.1, 20)]
const HOME: Vector3 = Vector3(0, 0.1, 0)
## Past the detection range (14.4 m from HOME), clear of the scene's wall.
const FAR: Vector3 = Vector3(8, 0.1, -12)
const DT: float = 1.0 / 60.0
const STRESS_COUNT: int = 16
const STRESS_RADIUS: float = 6.0
## A physics tick must fit in one 60 Hz tick, or the game falls behind.
const PHYSICS_BUDGET: float = 1.0 / 60.0
## The same crowd measured on the pre-M12.1 enemy: about 9 ms a tick while it
## converges on the player, 2–4 ms once it has — the refactor costs nothing.
const STRESS_TICKS: int = 180

@onready var _player: Player = $Player
@onready var _a: BasicMeleeEnemy = $EnemyA
@onready var _b: BasicMeleeEnemy = $EnemyB
@onready var _c: BasicMeleeEnemy = $EnemyC
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _data: EnemyData = null
## Every enemy the watcher checks — the scene's and every one spawned. Untyped:
## a freed spawn must not break it.
var _watched: Array = []
## Every transition, as "Name:FROM>TO@frame".
var _transitions: Array[String] = []
var _violations: Array[String] = []
var _spawned: int = 0
var _pass: int = 0
var _fail: int = 0

## Criticals are random (M11.7) and this suite checks exact damage, so they are
## off for its whole run except where it turns one on.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_reset_session()
	_data = _a.stats
	for enemy in [_a, _b, _c]:
		_watch(enemy)
	_player.hurtbox.set_invulnerable(true)
	_run()


func _physics_process(_delta: float) -> void:
	for candidate in _watched:
		if not is_instance_valid(candidate) or not (candidate as Node).is_inside_tree():
			continue
		_check_invariants(candidate as BasicMeleeEnemy)


func _run() -> void:
	await _wait(0.4)
	_config_tests()
	await _idle_tests()
	await _detection_tests()
	await _chase_tests()
	await _attack_tests()
	await _target_lost_tests()
	await _stagger_tests()
	await _knockback_tests()
	await _death_tests()
	await _invalid_transition_tests()
	await _multi_enemy_tests()
	await _shadow_tests()
	await _dodge_tests()
	await _lock_tests()
	await _feedback_and_critical_tests()
	await _stress_tests()
	await _missing_navigation_tests()
	await _debug_tests()
	await _wait(0.3)
	_record(_violations.is_empty(),
		"IV1) every tick, on every enemy: a fighting state had a target, IDLE and DEAD none, ATTACK and an attack phase went together, the hitbox was open only in ACTIVE, DEAD matched the health %s" % [
			_violations.slice(0, 4)])
	_record(_data.alert_duration == 0.0 and _data.target_groups == [Player.GROUP] and _data.detection_range == 10.0
			and _data.attack_cooldown == 0.4 and _data.movement_speed == 3.8,
		"IV2) the shared EnemyData was never written")
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- configuration ---------------------------------------------------------------------------

func _config_tests() -> void:
	_record(_data.resource_path == ENEMY_DATA_PATH and _data.alert_duration == 0.0
			and _data.target_groups == [Player.GROUP] and _data.detection_range == 10.0
			and _data.lose_target_range == 14.0 and _data.lose_target_delay == 1.0 and _data.attack_range == 1.8
			and _data.attack_cooldown == 0.4 and _data.movement_speed == 3.8 and _data.max_health == 100.0
			and _data.attack_damage == 15.0 and _data.xp_reward == 25,
		"CF1) %s: target groups %s, ALERT 0 s; every M11 number unchanged (detection 10 m, lose 14 m / 1 s, range 1.8 m, cooldown 0.4 s, speed 3.8, 100 HP, 15 damage, 25 XP)" % [
			ENEMY_DATA_PATH.get_file(), _data.target_groups])
	var own: bool = _a.target_groups == _data.target_groups and not is_same(_a.target_groups, _data.target_groups) \
		and not is_same(_a.targeting, _b.targeting) and not is_same(_b.targeting, _c.targeting)
	_record(own and _a.get_state() == BasicMeleeEnemy.State.IDLE and _a.get_target() == null
			and _b.get_target() == null and _c.get_target() == null,
		"CF2) each enemy has its own targeting and its own copy of the data's groups; parked, all IDLE with no target")
	var quiet: bool = true
	for enemy in [_a, _b, _c]:
		var e: BasicMeleeEnemy = enemy
		quiet = quiet and not e.debug_log_ai and not e.debug_state_label and e._debug_label == null \
			and not e.is_processing()
	_record(quiet, "CF3) the AI debug — transition log and state label — is off by default, and costs nothing")


# --- IDLE ------------------------------------------------------------------------------------

func _idle_tests() -> void:
	await _fresh(_a, FAR)
	var start: Vector3 = _a.global_position
	var reads: int = _a.targeting.get_refresh_count()
	var first: int = _transitions.size()
	_a.set_combat_enabled(true)
	var quiet: bool = true
	for i in 60:
		await get_tree().physics_frame
		quiet = quiet and _a._state == BasicMeleeEnemy.State.IDLE and _a.get_target() == null \
			and _a._attack_phase == BasicMeleeEnemy.AttackPhase.NONE and not _a.hitbox.is_active()
	var drift: float = _flat(_a.global_position - start).length()
	var group_reads: int = _a.targeting.get_refresh_count() - reads
	_record(quiet and drift < 0.05 and _transitions.size() == first and group_reads <= 2,
		"ID1) armed with the player 14 m away: IDLE for a second — no target, no step (%.3f m), no swing; the groups read %d times, not every tick" % [
			drift, group_reads])


# --- IDLE -> ALERT -> CHASE ---------------------------------------------------------------------

func _detection_tests() -> void:
	# The player walks in to 8 m.
	var first: int = _transitions.size()
	_player.global_position = HOME + Vector3(4, 0, -6)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE, 30)
	var seen: Array[String] = _sequence(_a, first)
	var same_tick: bool = _frames_of(_a, first).size() == 2 and _frames_of(_a, first)[0] == _frames_of(_a, first)[1]
	_record(seen == ["IDLE>ALERT", "ALERT>CHASE"] and same_tick and _a.get_target() == _player,
		"DT1) the player comes within 10 m: %s, both in the same tick (ALERT 0 s), and the player is its target" % [seen])
	_player.global_position = HOME

	# An archetype with a reaction: ALERT holds for its duration, turning, not walking.
	await _fresh(_a, HOME + Vector3(0, 0, -6), false)
	# Facing straight away from the player (who is behind it, at +z).
	_a.visual_root.rotation.y = 0.0
	_a.alert_duration = 0.5
	first = _transitions.size()
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.ALERT, 30)
	var alert_clock: int = Engine.get_physics_frames()
	var start: Vector3 = _a.global_position
	var error_start: float = _a._facing_error_to(_player)
	var stood: bool = true
	while _a._state == BasicMeleeEnemy.State.ALERT:
		await get_tree().physics_frame
		if _a._state == BasicMeleeEnemy.State.ALERT:
			stood = stood and _flat(_a.global_position - start).length() < 0.05 \
				and _a._attack_phase == BasicMeleeEnemy.AttackPhase.NONE
	var held: float = (Engine.get_physics_frames() - alert_clock) * DT
	var turned: bool = _a._facing_error_to(_player) < error_start
	_a.alert_duration = 0.0
	_record(absf(held - 0.5) <= 3.0 * DT and stood and turned and _a._state == BasicMeleeEnemy.State.CHASE,
		"DT2) with alert_duration 0.5 s: ALERT for %.2f s, standing, turning to face the target, then CHASE" % held)


# --- CHASE ---------------------------------------------------------------------------------------

func _chase_tests() -> void:
	await _fresh(_a, HOME + Vector3(0, 0, -7))
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE, 30)
	var start_distance: float = _a.targeting.get_distance()
	var paths: int = 0
	var last: Vector3 = _a.nav_agent.target_position
	var no_attack: bool = true
	for i in 60:
		await get_tree().physics_frame
		if _a.nav_agent.target_position != last:
			paths += 1
			last = _a.nav_agent.target_position
		if _a.targeting.get_distance() > _a.attack_range:
			no_attack = no_attack and _a._state != BasicMeleeEnemy.State.ATTACK
	var closed: float = start_distance - _a.targeting.get_distance()
	var slot_error: float = _flat(_a.nav_agent.target_position - _a._combat_slot_position()).length()
	_record(closed > 2.0 and no_attack and _a.get_target() == _player,
		"CH1) 7 m away it chases: %.2f m closed in a second, no swing while out of range" % closed)
	_record(paths <= 3 and slot_error < 0.5,
		"CH2) navigation aims at its slot beside the target (%.2f m off), and asks for a new path only when that point moves: %d paths in a second, not five" % [
			slot_error, paths])


# --- ATTACK --------------------------------------------------------------------------------------

func _attack_tests() -> void:
	await _fresh(_a, HOME + Vector3(0, 0, -1.5))
	var landed: Array[int] = [0]
	var on_landed: Callable = func(target: Node, _hit: DamageInfo) -> void:
		if target == _player:
			landed[0] += 1
	_a.hitbox.hit_landed.connect(on_landed)
	var first: int = _transitions.size()
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.ATTACK, 30)
	var phases: Array[String] = []
	var open_only_active: bool = true
	while _a._state == BasicMeleeEnemy.State.ATTACK:
		var phase: String = BasicMeleeEnemy.AttackPhase.keys()[_a._attack_phase]
		if phases.is_empty() or phases[-1] != phase:
			phases.append(phase)
		open_only_active = open_only_active and (_a.hitbox.is_active() == (_a._attack_phase == BasicMeleeEnemy.AttackPhase.ACTIVE))
		await get_tree().physics_frame
	var seen: Array[String] = _sequence(_a, first)
	var cooldown: float = _a._cooldown_timer
	_record(seen.slice(0, 3) == ["IDLE>ALERT", "ALERT>CHASE", "CHASE>ATTACK"] and seen[-1] == "ATTACK>CHASE"
			and phases == ["STARTUP", "ACTIVE", "RECOVERY"] and open_only_active and landed[0] == 1,
		"AT1) in range: CHASE -> ATTACK, one swing — %s, the hitbox open only in ACTIVE, one hit — then ATTACK -> CHASE" % [phases])
	# Still in range: the next swing waits for the cooldown.
	var waited: int = 0
	while _a._state != BasicMeleeEnemy.State.ATTACK and waited < 120:
		await get_tree().physics_frame
		waited += 1
	_record(absf(cooldown - _a.attack_cooldown) < 0.02 and absf(waited * DT - _a.attack_cooldown) <= 3.0 * DT,
		"AT2) the player still in range: the next swing starts once the %.2f s cooldown is over (%.2f s later)" % [
			_a.attack_cooldown, waited * DT])
	await _until(func() -> bool: return _a._state != BasicMeleeEnemy.State.ATTACK, 90)
	# The player walks off: back to chasing, and no swing out of range.
	_player.global_position = HOME + Vector3(0, 0, 4)
	var chased: bool = await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE and _a.velocity.z > 1.0, 60)
	var out_of_range_swing: bool = false
	for i in 30:
		await get_tree().physics_frame
		if _a.targeting.get_distance() > _a.attack_range + 0.3:
			out_of_range_swing = out_of_range_swing or _a._state == BasicMeleeEnemy.State.ATTACK
	_a.hitbox.hit_landed.disconnect(on_landed)
	_record(chased and not out_of_range_swing, "AT3) the player steps away: CHASE after it, and no swing at a target out of range")
	_player.global_position = HOME


# --- losing the target ----------------------------------------------------------------------------

func _target_lost_tests() -> void:
	# Out of range: kept for the grace period, then let go.
	await _fresh(_a, HOME + Vector3(0, 0, -6))
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE, 30)
	_player.global_position = HOME + Vector3(0, 0, 24)
	await _wait(0.5)
	var kept: bool = _a._state == BasicMeleeEnemy.State.CHASE and _a.get_target() == _player
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.IDLE, 90)
	_record(kept and _a._state == BasicMeleeEnemy.State.IDLE and _a.get_target() == null,
		"TL1) the target runs past 14 m: still chased half a second on (the 1 s grace), then let go — IDLE, no target")
	_player.global_position = HOME
	await _frames(3)

	# The target dies while chased: let go in the same call.
	await _fresh(_a, HOME + Vector3(0, 0, -6))
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE, 30)
	_kill_player()
	var same_call: bool = _a._state == BasicMeleeEnemy.State.IDLE and _a.get_target() == null
	for i in 20:
		await get_tree().physics_frame
	var stays: bool = _a._state == BasicMeleeEnemy.State.IDLE and _a.get_target() == null
	_record(same_call and stays, "TL2) the player dies while chased: let go in the same call — IDLE — and a dead player is never picked up again")
	_revive_player()

	# The target dies mid-swing: the swing is cut off safely.
	await _fresh(_a, HOME + Vector3(0, 0, -1.5))
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._attack_phase == BasicMeleeEnemy.AttackPhase.ACTIVE, 60)
	_kill_player()
	var cut: bool = _a._state == BasicMeleeEnemy.State.IDLE and _a._attack_phase == BasicMeleeEnemy.AttackPhase.NONE \
		and not _a.hitbox.is_active() and _a.visual_root.scale == Vector3.ONE
	_revive_player()
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE or _a._state == BasicMeleeEnemy.State.ATTACK, 30)
	_record(cut and _a.get_target() == _player,
		"TL3) the target dies mid-swing: the swing is cut off — hitbox shut, telegraph undone — IDLE; alive again, it is picked up again")


# --- STAGGERED --------------------------------------------------------------------------------------

func _stagger_tests() -> void:
	# From CHASE.
	await _fresh(_a, HOME + Vector3(0, 0, -6))
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE and _a.velocity.length() > 1.0, 60)
	var first: int = _transitions.size()
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	var start: Vector3 = _a.global_position
	var still: bool = true
	var clock: int = Engine.get_physics_frames()
	while _a._state == BasicMeleeEnemy.State.STAGGERED:
		await get_tree().physics_frame
		if _a._state == BasicMeleeEnemy.State.STAGGERED:
			still = still and _flat(_a.velocity).length() < 0.01 and _a.get_target() == _player
	var lasted: float = (Engine.get_physics_frames() - clock) * DT
	var drift: float = _flat(_a.global_position - start).length()
	_record(_sequence(_a, first) == ["CHASE>STAGGERED", "STAGGERED>CHASE"] and still and drift < 0.05
			and absf(lasted - _a.stagger_duration) <= 3.0 * DT and _a.is_stagger_immune(),
		"SG1) staggered mid-chase: no step for %.2f s — navigation does not drag it (%.3f m) — the target kept; then CHASE again, immune" % [
			lasted, drift])

	# From ATTACK: the swing is cut off, and nothing of it lands.
	await _fresh(_a, HOME + Vector3(0, 0, -1.5))
	var landed: Array[int] = [0]
	var on_landed: Callable = func(_t: Node, _h: DamageInfo) -> void: landed[0] += 1
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP, 60)
	_a.hitbox.hit_landed.connect(on_landed)
	first = _transitions.size()
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	var cut: bool = _a._state == BasicMeleeEnemy.State.STAGGERED and _a._attack_phase == BasicMeleeEnemy.AttackPhase.NONE \
		and not _a.hitbox.is_active()
	var refused: bool = not _a._change_state(BasicMeleeEnemy.State.ATTACK) and _a._state == BasicMeleeEnemy.State.STAGGERED
	await _until(func() -> bool: return _a._state != BasicMeleeEnemy.State.STAGGERED, 60)
	var ghost: int = landed[0]
	_a.hitbox.hit_landed.disconnect(on_landed)
	_record(cut and refused and ghost == 0 and _sequence(_a, first)[0] == "ATTACK>STAGGERED",
		"SG2) staggered in STARTUP: ATTACK -> STAGGERED, the swing cut off — no ghost hit — and no swing may start before it is over")


# --- knockback ----------------------------------------------------------------------------------------

func _knockback_tests() -> void:
	await _fresh(_a, HOME + Vector3(0, 0, -6))
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE and _a.velocity.z > 1.0, 60)
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 0.0, 8.0))
	var pushed_back: bool = true
	var frames: int = 0
	while _a.is_knocked_back() and frames < 60:
		await get_tree().physics_frame
		frames += 1
		if _a.is_knocked_back():
			# Pushed toward -z, away from the player: the AI's own step (+z) never wins.
			pushed_back = pushed_back and _a.velocity.z < 0.0
	var state_kept: bool = _a._state == BasicMeleeEnemy.State.CHASE
	var resumed: bool = await _until(func() -> bool: return _a.velocity.z > 1.0, 60)
	_record(pushed_back and frames > 2 and state_kept and resumed,
		"KB1) pushed mid-chase: for %d ticks the push is the velocity — the AI never steers over it — then the chase resumes, still CHASE" % frames)


# --- DEAD ---------------------------------------------------------------------------------------------

func _death_tests() -> void:
	var results: Dictionary = {}
	# From IDLE.
	await _park_all()
	var idle: BasicMeleeEnemy = await _spawn(FAR + Vector3(-16, 0, 0))
	idle.set_combat_enabled(true)
	await _frames(3)
	results["IDLE"] = await _kill_and_watch(idle)

	# From CHASE: navigation stops too.
	var chaser: BasicMeleeEnemy = await _spawn(HOME + Vector3(-5, 0, -6))
	chaser.set_combat_enabled(true)
	await _until(func() -> bool: return chaser._state == BasicMeleeEnemy.State.CHASE and chaser.velocity.length() > 1.0, 60)
	results["CHASE"] = await _kill_and_watch(chaser)
	var stopped: bool = not chaser.nav_agent.avoidance_enabled \
		and _flat(chaser.nav_agent.target_position - chaser.global_position).length() < 0.3

	# From ATTACK, killed by the player's own swing: the reward, once.
	var striker: BasicMeleeEnemy = await _spawn(HOME + Vector3(0, 0, -1.5))
	striker.health_component.current_health = 10.0
	striker.set_combat_enabled(true)
	await _until(func() -> bool: return striker._state == BasicMeleeEnemy.State.ATTACK, 60)
	var xp: int = _player.progression.get_total_xp()
	var deaths: Array[int] = [0]
	striker.enemy_died.connect(func(_dead: RoomCombatant) -> void: deaths[0] += 1)
	var first: int = _transitions.size()
	_player.camera_rig.rotation.y = 0.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.light_combo, 0)
	await _until(func() -> bool: return striker._state == BasicMeleeEnemy.State.DEAD, 60)
	var cut: bool = striker._attack_phase == BasicMeleeEnemy.AttackPhase.NONE and not striker.hitbox.is_active()
	await _frames(30)
	var attack_death: bool = _sequence(striker, first) == ["ATTACK>DEAD"] and cut and deaths[0] == 1 \
		and _player.progression.get_total_xp() - xp == striker.get_xp_reward() and striker.claim_xp() == 0

	# From STAGGERED: the stagger never resumes it.
	var staggered: BasicMeleeEnemy = await _spawn(HOME + Vector3(5, 0, -6))
	staggered.set_combat_enabled(true)
	await _until(func() -> bool: return staggered._state == BasicMeleeEnemy.State.CHASE, 30)
	staggered.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	results["STAGGERED"] = await _kill_and_watch(staggered, staggered.stagger_duration + 0.2)

	var all_clean: bool = true
	for from in results:
		all_clean = all_clean and results[from]
	_record(results.get("IDLE", false) and results.get("CHASE", false) and results.get("STAGGERED", false),
		"DE1) killed from IDLE, CHASE and STAGGERED: X -> DEAD and nothing after — no update, no resume, no target; DEAD refuses every transition and waking")
	_record(stopped, "DE2) killed mid-chase: its navigation stops — the path points where it lies, out of avoidance")
	_record(attack_death, "DE3) killed mid-swing by the player: ATTACK -> DEAD, the swing cut off, one death reported, %d XP paid once" % striker.get_xp_reward())
	for enemy in [idle, chaser, striker, staggered]:
		enemy.queue_free()
	await _frames(2)


## Kills `enemy` and watches it for `hold` seconds: DEAD, from whatever it was,
## and nothing after.
func _kill_and_watch(enemy: BasicMeleeEnemy, hold: float = 0.5) -> bool:
	var from: String = BasicMeleeEnemy.State.keys()[enemy._state]
	var first: int = _transitions.size()
	enemy.hurtbox.receive_hit(_crafted_hit(1000.0, 0.0, 0.0))
	var dead_now: bool = enemy._state == BasicMeleeEnemy.State.DEAD and enemy.get_target() == null
	await _wait(hold)
	var refuses: bool = not enemy._change_state(BasicMeleeEnemy.State.CHASE) \
		and not enemy._change_state(BasicMeleeEnemy.State.IDLE)
	enemy.set_combat_enabled(true)
	return dead_now and refuses and _sequence(enemy, first) == ["%s>DEAD" % from] \
		and enemy._state == BasicMeleeEnemy.State.DEAD and enemy.get_target() == null


# --- illegal transitions --------------------------------------------------------------------------------

func _invalid_transition_tests() -> void:
	await _fresh(_a, FAR)
	_a.set_combat_enabled(true)
	await _frames(2)
	var first: int = _transitions.size()
	var from_idle: bool = not _a._change_state(BasicMeleeEnemy.State.ATTACK) \
		and not _a._change_state(BasicMeleeEnemy.State.CHASE) and not _a._change_state(BasicMeleeEnemy.State.ALERT)
	var parked: BasicMeleeEnemy = _b
	await _fresh(parked, HOME + Vector3(4, 0, -6))
	parked.targeting.acquire(parked.detection_range, 1.0)
	var parked_refuses: bool = parked.get_target() == _player and not parked._change_state(BasicMeleeEnemy.State.ALERT)
	parked.targeting.release()
	_record(from_idle and parked_refuses and _a._state == BasicMeleeEnemy.State.IDLE
			and _transitions.size() == first,
		"IT1) refused, and announced by nothing: IDLE -> ATTACK or CHASE (it goes through ALERT), ALERT with no target, ALERT while parked even with one")

	await _fresh(_a, HOME + Vector3(0, 0, -1.5))
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP, 60)
	var timer: float = _a._phase_timer
	var again: bool = not _a._change_state(BasicMeleeEnemy.State.ATTACK) and _a._phase_timer == timer \
		and _a._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP
	_record(again, "IT2) ATTACK -> ATTACK is refused: a swing under way is never restarted or doubled")
	await _until(func() -> bool: return _a._state != BasicMeleeEnemy.State.ATTACK, 90)


# --- more than one ------------------------------------------------------------------------------------------

func _multi_enemy_tests() -> void:
	await _fresh(_a, HOME + Vector3(0, 0, -1.5))
	await _fresh(_b, HOME + Vector3(5, 0, -5), false, true)
	await _fresh(_c, FAR, false, true)
	for enemy in [_a, _b, _c]:
		(enemy as BasicMeleeEnemy).set_combat_enabled(true)
	await _wait(0.2)
	var states: Array[String] = []
	for enemy in [_a, _b, _c]:
		states.append(BasicMeleeEnemy.State.keys()[(enemy as BasicMeleeEnemy)._state])
	var apart: bool = _a._state == BasicMeleeEnemy.State.ATTACK and _b._state == BasicMeleeEnemy.State.CHASE \
		and _c._state == BasicMeleeEnemy.State.IDLE and _a.get_target() == _player and _b.get_target() == _player \
		and _c.get_target() == null
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE, 90)
	var own_cooldown: bool = _a._cooldown_timer > 0.0 and _b._cooldown_timer == 0.0 and _c._cooldown_timer == 0.0
	_record(apart and own_cooldown,
		"ME1) three at once, each its own: %s — two targets on the player, one none; the attacker's cooldown is its alone" % [states])
	await _park_all()


# --- the player and a shadow --------------------------------------------------------------------------------

func _shadow_tests() -> void:
	var shadow: BasicMeleeShadow = await _summon(HOME + Vector3(0, 0, -5))
	_player.shadow_commander.set_mode(BasicMeleeShadow.CommandMode.FOLLOW)
	# The shipped policy: the player, never a shadow, even a nearer one.
	await _fresh(_a, HOME + Vector3(0, 0, -8), false)
	shadow.global_position = _a.global_position + Vector3(1.5, 0, 0)
	await _frames(2)
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a.get_target() != null, 30)
	_record(_a.get_target() == _player,
		"SH1) the policy as shipped: a shadow 1.5 m away and the player 8 m — it takes the player; a shadow is never its target")
	await _park_all()

	# An archetype whose groups include the shadow's: the nearest, then sticky.
	var hunter_data: EnemyData = _data.duplicate() as EnemyData
	hunter_data.target_groups = [Player.GROUP, BasicMeleeShadow.GROUP]
	_player.global_position = HOME
	var hunter: BasicMeleeEnemy = await _spawn(HOME + Vector3(0, 0, -8), hunter_data)
	shadow.global_position = hunter.global_position + Vector3(2.0, 0, 0)
	await _frames(2)
	var changes: Array[Node3D] = []
	hunter.targeting.target_changed.connect(func(t: Node3D) -> void: changes.append(t))
	hunter.set_combat_enabled(true)
	await _until(func() -> bool: return hunter.get_target() != null, 30)
	var took_shadow: bool = hunter.get_target() == shadow
	# The player now walks right up to it: nearer than the shadow, but no switch.
	_player.global_position = hunter.global_position + Vector3(0, 0, 1.4)
	for i in 60:
		await get_tree().physics_frame
	var sticky: bool = hunter.get_target() == shadow and changes.size() == 1
	_record(took_shadow and sticky,
		"SH2) with the shadow's group added to its data: it takes the nearest — the shadow — and keeps it when the player comes nearer (one change in a second, no flicker)")

	# The shadow is recalled: let go when it leaves, then the player.
	_player.shadow_summoner.recall()
	await get_tree().process_frame
	var released: bool = changes.size() >= 2 and changes[1] == null
	await _until(func() -> bool: return hunter.get_target() != null, 30)
	_record(released and hunter.get_target() == _player and is_instance_valid(hunter.get_target()),
		"SH3) the shadow recalled: let go as it left the scene — no reference to it kept — and the player taken instead")

	# Summoned again and killed while targeted.
	_player.global_position = HOME + Vector3(0, 0, 9)
	hunter.targeting.release()
	shadow = await _summon(hunter.global_position + Vector3(2.0, 0, 0))
	shadow.global_position = hunter.global_position + Vector3(2.0, 0, 0)
	await _until(func() -> bool: return hunter.get_target() == shadow, 90)
	var on_shadow: bool = hunter.get_target() == shadow
	# The player within reach, but the shadow is held: no switch.
	_player.global_position = hunter.global_position + Vector3(0, 0, 5)
	await _frames(10)
	on_shadow = on_shadow and hunter.get_target() == shadow
	var before: int = changes.size()
	shadow.health_component.take_damage(DamageInfo.new(100000.0, _b))
	var dropped: bool = changes.size() == before + 1 and changes[-1] == null
	await _until(func() -> bool: return hunter.get_target() != null, 60)
	_record(on_shadow and dropped and hunter.get_target() == _player,
		"SH4) the targeted shadow dies: let go in the same call, and the player — the one left — taken next")
	hunter.queue_free()
	_player.global_position = HOME
	await _frames(20)


# --- the player's dodge, stamina, lock ----------------------------------------------------------------------

func _dodge_tests() -> void:
	await _fresh(_a, HOME + Vector3(0, 0, -1.5))
	_player.hurtbox.set_invulnerable(false)
	_player.combat.restore_stamina(_player.combat.get_max_stamina())
	var hp: float = _player.health_component.current_health
	_a.set_combat_enabled(true)
	await _until(func() -> bool:
		return _a._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP and _a._phase_timer <= 0.12, 60)
	var speed: float = _player.effective_dodge_speed
	_player.effective_dodge_speed = 0.0
	var stamina: float = _player.combat.get_stamina()
	_press(&"dodge")
	var paid: float = stamina - _player.combat.get_stamina()
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE, 90)
	_player.effective_dodge_speed = speed
	_player.hurtbox.set_invulnerable(true)
	_record(_player.health_component.current_health == hp and paid == _player.combat.data.dodge_stamina_cost
			and _a._state == BasicMeleeEnemy.State.CHASE,
		"DG1) its swing met in the player's i-frames: no damage, the dodge paid its %.0f stamina, and the enemy — none the wiser — finishes it and chases on" % paid)
	await _park_all()


func _lock_tests() -> void:
	var states: Array[String] = []
	var held: bool = true
	await _fresh(_a, FAR + Vector3(0, 0, 3))
	_a.set_combat_enabled(true)
	await _frames(3)
	_press(&"target_lock")
	held = held and _player.targeting.get_target() == _a
	states.append(BasicMeleeEnemy.State.keys()[_a._state])
	_player.global_position = _a.global_position + Vector3(0, 0, 1.5)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.ATTACK, 180)
	held = held and _player.targeting.get_target() == _a
	states.append(BasicMeleeEnemy.State.keys()[_a._state])
	_a.hurtbox.receive_hit(_crafted_hit(1.0, 60.0, 0.0))
	held = held and _player.targeting.get_target() == _a
	states.append(BasicMeleeEnemy.State.keys()[_a._state])
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE, 60)
	held = held and _player.targeting.get_target() == _a
	states.append(BasicMeleeEnemy.State.keys()[_a._state])
	_a.hurtbox.receive_hit(_crafted_hit(1000.0, 0.0, 0.0))
	_record(held and states == ["IDLE", "ATTACK", "STAGGERED", "CHASE"] and not _player.targeting.is_locked(),
		"LK1) the player's lock holds through %s — the enemy never knows it is locked — and lets go at its death" % [states])
	# Let the topple finish before standing it back up.
	await _wait(0.6)
	_revive(_a)
	_player.global_position = HOME


func _feedback_and_critical_tests() -> void:
	# The player's heavy, critical, through a hit stop: 60 damage, a stagger, and
	# nothing of the enemy's clocks moves while the game is held.
	await _fresh(_a, HOME + Vector3(0, 0, -1.5))
	_no_crits.critical_chance = 1.0
	_a.set_combat_enabled(true)
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.ATTACK, 60)
	var hp: float = _a.health_component.current_health
	_player.camera_rig.rotation.y = 0.0
	_player.combat.reset()
	_player.combat._start_attack(_player.combat.data.heavy_combo, 0)
	await _until(func() -> bool: return _player.combat_feedback.is_hit_stop_active(), 60)
	await get_tree().physics_frame
	var held: Array[float] = [_a._stagger_timer, _a._cooldown_timer]
	var held_state: BasicMeleeEnemy.State = _a._state
	var frozen: bool = true
	while _player.combat_feedback.is_hit_stop_active():
		frozen = frozen and _a._stagger_timer == held[0] and _a._cooldown_timer == held[1] and _a._state == held_state
		await get_tree().physics_frame
	_no_crits.critical_chance = 0.0
	await _until(func() -> bool: return _a._state == BasicMeleeEnemy.State.CHASE, 60)
	_record(hp - _a.health_component.current_health == 60.0 and held_state == BasicMeleeEnemy.State.STAGGERED and frozen,
		"FB1) a critical heavy mid-swing: 60 damage, staggered like any hit, its stagger held still through the hit stop, then CHASE")
	await _park_all()


# --- many at once --------------------------------------------------------------------------------------------

func _stress_tests() -> void:
	await _park_all()
	_player.global_position = HOME
	var crowd: Array[BasicMeleeEnemy] = []
	for i in STRESS_COUNT:
		var angle: float = TAU * float(i) / STRESS_COUNT
		var enemy: BasicMeleeEnemy = await _spawn(HOME + Vector3(cos(angle), 0, sin(angle)) * STRESS_RADIUS, null, false)
		enemy.combat_angle_offset_degrees = float(i * 23 % 90) - 45.0
		crowd.append(enemy)
	await _frames(2)
	for enemy in crowd:
		enemy.set_combat_enabled(true)
	var physics: float = 0.0
	var worst: float = 0.0
	var all_engaged: bool = false
	var engaged_by: int = -1
	var started: int = Time.get_ticks_usec()
	for tick in STRESS_TICKS:
		await get_tree().physics_frame
		var t: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		physics += t
		worst = maxf(worst, t)
		if not all_engaged:
			all_engaged = crowd.all(func(e: BasicMeleeEnemy) -> bool: return e.get_target() == _player)
			if all_engaged:
				engaged_by = tick
	var reads: int = 0
	var states: Dictionary = {}
	for enemy in crowd:
		reads += enemy.targeting.get_refresh_count()
		states[BasicMeleeEnemy.State.keys()[enemy._state]] = states.get(BasicMeleeEnemy.State.keys()[enemy._state], 0) + 1
	var average: float = physics / STRESS_TICKS
	var wall: float = float(Time.get_ticks_usec() - started) / 1000000.0
	_record(all_engaged and engaged_by <= 2 and reads <= STRESS_COUNT * 2 and average < PHYSICS_BUDGET
			and absf(wall - STRESS_TICKS * DT) < 0.3,
		"ST1) %d enemies around the player: all on it within %d ticks, the groups read %d times in all over 3 s; %d ticks in %.2f s — the rate kept — at %.2f ms of physics a tick (%.2f at worst), states %s" % [
			STRESS_COUNT, engaged_by + 1, reads, STRESS_TICKS, wall, average * 1000.0, worst * 1000.0, states])
	for enemy in crowd:
		enemy.queue_free()
	await _frames(3)
	_record(_living_spawns() == 0,
		"ST2) and freed again: nothing of the crowd left behind")


# --- no navigation ------------------------------------------------------------------------------------------

func _missing_navigation_tests() -> void:
	# A world of its own, with a floor and no NavigationRegion3D at all.
	var viewport: SubViewport = SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	viewport.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)
	var lost: BasicMeleeEnemy = ENEMY_SCENE.instantiate() as BasicMeleeEnemy
	lost.name = "NoNavigation"
	lost.combat_enabled = false
	viewport.add_child(lost)
	lost.global_position = HOME + Vector3(0, 0, -7)
	_watch(lost)
	await _frames(3)
	var start: float = _flat(lost.global_position - _player.global_position).length()
	lost.set_combat_enabled(true)
	await _wait(1.0)
	var closed: float = start - _flat(lost.global_position - _player.global_position).length()
	_record(lost._navigation_missing and lost._state == BasicMeleeEnemy.State.CHASE and closed > 1.5,
		"NV1) an enemy in a scene with no navigation says so once (a warning, not an error per tick) and steers straight at its target: %.2f m closed" % closed)
	viewport.queue_free()
	await _frames(2)


# --- debug -----------------------------------------------------------------------------------------------------

func _debug_tests() -> void:
	var shown: BasicMeleeEnemy = ENEMY_SCENE.instantiate() as BasicMeleeEnemy
	shown.name = "Labelled"
	shown.combat_enabled = false
	shown.debug_state_label = true
	add_child(shown)
	shown.global_position = HOME + Vector3(0, 0, -6)
	_watch(shown)
	await _frames(2)
	shown.set_combat_enabled(true)
	await _until(func() -> bool: return shown._state == BasicMeleeEnemy.State.CHASE, 30)
	await get_tree().process_frame
	await get_tree().process_frame
	var text: String = shown._debug_label.text if shown._debug_label != null else ""
	_record(shown.is_processing() and text.contains("CHASE") and text.contains("Player") and text.contains("m"),
		"DB1) with debug_state_label on: a label over it reads state, target and distance, and its navigation (\"%s\")" % text.replace("\n", " / "))
	shown.queue_free()
	await _frames(2)


# --- helpers -------------------------------------------------------------------------------------------------

func _watch(enemy: BasicMeleeEnemy) -> void:
	_watched.append(enemy)
	enemy.state_changed.connect(_on_state_changed.bind(enemy))


func _on_state_changed(from: BasicMeleeEnemy.State, to: BasicMeleeEnemy.State, enemy: BasicMeleeEnemy) -> void:
	_transitions.append("%s:%s>%s@%d" % [enemy.name, BasicMeleeEnemy.State.keys()[from],
		BasicMeleeEnemy.State.keys()[to], Engine.get_physics_frames()])


## `enemy`'s transitions since `first`, as "FROM>TO".
func _sequence(enemy: BasicMeleeEnemy, first: int) -> Array[String]:
	var out: Array[String] = []
	var prefix: String = "%s:" % enemy.name
	for i in range(first, _transitions.size()):
		if _transitions[i].begins_with(prefix):
			out.append(_transitions[i].trim_prefix(prefix).get_slice("@", 0))
	return out


func _frames_of(enemy: BasicMeleeEnemy, first: int) -> Array[int]:
	var out: Array[int] = []
	var prefix: String = "%s:" % enemy.name
	for i in range(first, _transitions.size()):
		if _transitions[i].begins_with(prefix):
			out.append(int(_transitions[i].trim_prefix(prefix).get_slice("@", 1)))
	return out


func _check_invariants(e: BasicMeleeEnemy) -> void:
	var s: BasicMeleeEnemy.State = e._state
	var name_of: String = "%s %s" % [e.name, BasicMeleeEnemy.State.keys()[s]]
	if BasicMeleeEnemy.FIGHTING_STATES.has(s) and not e.targeting.has_target():
		_violations.append("%s with no target" % name_of)
	if (s == BasicMeleeEnemy.State.IDLE or s == BasicMeleeEnemy.State.DEAD) and e.targeting.has_target():
		_violations.append("%s with a target" % name_of)
	if (s == BasicMeleeEnemy.State.ATTACK) != (e._attack_phase != BasicMeleeEnemy.AttackPhase.NONE):
		_violations.append("%s in attack phase %s" % [name_of, BasicMeleeEnemy.AttackPhase.keys()[e._attack_phase]])
	if e.hitbox.is_active() and e._attack_phase != BasicMeleeEnemy.AttackPhase.ACTIVE:
		_violations.append("%s with its hitbox open" % name_of)
	if (s == BasicMeleeEnemy.State.DEAD) != e.health_component.is_dead:
		_violations.append("%s, health dead %s" % [name_of, e.health_component.is_dead])


## A fresh, parked enemy from the real scene at `at`, on `data` if given, with a
## name of its own; settled for a few ticks unless `settle` is false.
func _spawn(at: Vector3, data: EnemyData = null, settle: bool = true) -> BasicMeleeEnemy:
	var enemy: BasicMeleeEnemy = ENEMY_SCENE.instantiate() as BasicMeleeEnemy
	_spawned += 1
	enemy.name = "Spawn%d" % _spawned
	enemy.combat_enabled = false
	if data != null:
		enemy.stats = data
	add_child(enemy)
	enemy.global_position = at
	_watch(enemy)
	if settle:
		await _frames(3)
	return enemy


func _living_spawns() -> int:
	var alive: int = 0
	for child in get_children():
		var enemy: BasicMeleeEnemy = child as BasicMeleeEnemy
		if enemy != null and not [_a, _b, _c].has(enemy) and not enemy.is_queued_for_deletion():
			alive += 1
	return alive


func _summon(at: Vector3) -> BasicMeleeShadow:
	var shadow: ShadowInstance = _player.shadows.add_shadow(SHADOW_DATA)
	var node: BasicMeleeShadow = _player.shadow_summoner.summon(shadow.instance_id)
	await _frames(2)
	node.global_position = at
	node.hurtbox.set_invulnerable(false)
	await _frames(2)
	return node


## Parks `enemy` at `at`, whole, with nothing of a previous fight left — and,
## unless `keep_others`, the other two back out of the way; the player home
## unless `reset_player` is false.
func _fresh(enemy: BasicMeleeEnemy, at: Vector3, reset_player: bool = true, keep_others: bool = false) -> void:
	if not keep_others:
		var enemies: Array[BasicMeleeEnemy] = [_a, _b, _c]
		for i in enemies.size():
			if enemies[i] != enemy:
				_park(enemies[i], PARKED[i])
	if reset_player:
		_player.combat.reset()
		_player.global_position = HOME
		_player.velocity = Vector3.ZERO
		_player.camera_rig.rotation.y = 0.0
	_park(enemy, at)
	_face(enemy, _player.global_position)
	await _frames(3)


func _park(enemy: BasicMeleeEnemy, at: Vector3) -> void:
	enemy.set_combat_enabled(false)
	enemy.global_position = at
	enemy.velocity = Vector3.ZERO
	enemy.health_component.current_health = enemy.health_component.max_health
	enemy._cooldown_timer = 0.0
	enemy._attack_delay_timer = 0.0
	enemy._reposition_block_timer = 0.0


func _park_all() -> void:
	var enemies: Array[BasicMeleeEnemy] = [_a, _b, _c]
	for i in enemies.size():
		_park(enemies[i], PARKED[i])
	await _frames(3)


## Brings a scene enemy back from the dead, which nothing in the game does: a
## real run rebuilds the scene.
func _revive(enemy: BasicMeleeEnemy) -> void:
	enemy.health_component.reset_to(enemy.health_component.max_health)
	enemy._state = BasicMeleeEnemy.State.IDLE
	enemy._died = false
	enemy._xp_claimed = false
	enemy.visual_root.rotation = Vector3.ZERO
	enemy.hurtbox.monitorable = true
	enemy.hurtbox_collision.disabled = false
	enemy.body_collision.disabled = false
	enemy.nav_agent.avoidance_enabled = false
	_park(enemy, PARKED[[_a, _b, _c].find(enemy)])


func _face(enemy: BasicMeleeEnemy, point: Vector3) -> void:
	var to: Vector3 = _flat(point - enemy.global_position)
	if to.length_squared() > 0.0001:
		enemy.visual_root.rotation.y = atan2(-to.x, -to.z)


func _kill_player() -> void:
	_player.hurtbox.set_invulnerable(false)
	_player.health_component.take_damage(DamageInfo.new(100000.0, _a))


func _revive_player() -> void:
	_player.health_component.reset_to(_player.health_component.max_health)
	_player.combat.reset()
	_player.hurtbox.set_invulnerable(true)


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
