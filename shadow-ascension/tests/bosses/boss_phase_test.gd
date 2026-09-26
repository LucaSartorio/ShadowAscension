extends Node3D

## M5.2 Boss Phase 2 and Encounter Polish — the phase state, the transition, the
## phase-2 rhythm, Double Strike and dying safely in either half.
## M5.1's activation, three attacks and completion flow stay in boss_test.

const DUNGEON: PackedScene = preload("res://scenes/dungeons/dungeon_test.tscn")

const ROOM1_TRIGGER: Vector3 = Vector3(0, 0.1, -13)
const ROOM2_TRIGGER: Vector3 = Vector3(0, 0.1, -33)
const BOSS_TRIGGER: Vector3 = Vector3(0, 0.1, -53)

## Indices into the boss's attacks, in the order its phases first list them.
const QUICK: int = 0
const SWEEP: int = 1
const SLAM: int = 2
const DOUBLE: int = 3

var _pass: int = 0
var _fail: int = 0

var _dungeon: DungeonController = null
var _player: Player = null
var _boss: DungeonBoss = null
var _bar: BossHealthBar = null
var _boss_room: RoomController = null


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(0.2)
	await _setup()
	await _arena_tests()
	await _phase_1_tests()
	await _transition_tests()
	await _phase_2_tests()
	await _double_strike_tests()
	await _decision_tests()
	await _death_tests()
	await _death_during_transition_tests()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


# --- helpers ------------------------------------------------------------------

## Brings a fresh dungeon up with the player standing in the boss room, both
## combat rooms cleared behind them, exactly as a real run arrives.
func _setup() -> void:
	_reset_session()
	if _dungeon != null:
		_dungeon.queue_free()
		await _wait(0.5)
	_dungeon = DUNGEON.instantiate() as DungeonController
	add_child(_dungeon)
	await _wait(0.8)
	_player = _dungeon.get_node("Player")
	_bar = _dungeon.get_node("BossHealthBar")
	_boss_room = _dungeon.get_rooms()[2]
	_boss = _boss_room.get_enemies()[0] as DungeonBoss
	for i in 2:
		_player.global_position = [ROOM1_TRIGGER, ROOM2_TRIGGER][i]
		await _wait(0.4)
		for enemy in _dungeon.get_rooms()[i].get_enemies():
			enemy.hurtbox.receive_hit(DamageInfo.new(10000.0, null))
		await _wait(0.5)
	_player.global_position = BOSS_TRIGGER
	await _wait(0.5)
	await _wait(_boss.intro_duration + 0.2)


func _place_player(distance: float) -> void:
	_player.global_position = _boss.global_position + Vector3(0, 0, -distance)
	_boss.visual_root.rotation.y = 0.0
	await get_tree().physics_frame


func _heal_player() -> void:
	_player.health_component.current_health = _player.health_component.max_health
	_player.health_component.is_dead = false
	_player.hurtbox.set_invulnerable(false)


## Leaves `index` as the only attack the decision layer may pick. Clears any
## swing still in flight first: a test that broke out mid-ACTIVE would otherwise
## leave the next one reading a stale attack phase.
func _only_attack(index: int) -> void:
	# interrupt() is what every real interruption runs: every hitbox shut and the
	# body put back at once, so the next attack is not read through this pose.
	_boss.combat.interrupt()
	var all: Array[BossAttack] = _boss.get_attacks()
	_boss.combat.clear_cooldowns()
	for i in all.size():
		_boss.combat.set_cooldown(all[i], 0.0 if i == index else 99.0)
	_boss._change_state(DungeonBoss.State.DECIDE)


func _attack(index: int) -> BossAttack:
	return _boss.get_attacks()[index]


func _any_hitbox_live() -> bool:
	for hitbox in _boss.combat.get_hitboxes():
		if hitbox.is_active():
			return true
	return false


## Blocks until the boss commits to an attack, so a caller measures a fresh one
## rather than whatever was already running.
func _await_attack_start(timeout: float = 3.0) -> bool:
	var elapsed: float = 0.0
	while elapsed < timeout:
		if _boss.get_state() == DungeonBoss.State.ATTACK:
			return true
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return false


## Drops the boss to a fraction of its health in one blow.
func _set_boss_health(fraction: float) -> void:
	var target: float = _boss.health_component.max_health * fraction
	var delta: float = _boss.health_component.current_health - target
	if delta > 0.0:
		_boss.hurtbox.receive_hit(DamageInfo.new(delta, null))


## Records every hit an attack's own hitbox lands, with the time it landed.
func _watch_hitbox(index: int) -> Array:
	var log: Array = []
	var hitbox: Hitbox = _boss.combat.get_hitbox(_attack(index))
	hitbox.hit_landed.connect(func(target: Node, hit: DamageInfo) -> void:
		log.append({"t": Time.get_ticks_msec(), "target": target, "damage": hit.amount}))
	return log


# --- arena ----------------------------------------------------------------------

## Functional checks only: room to dodge, corners the player can leave again, and
## a navmesh that actually covers the arena. Not art.
func _arena_tests() -> void:
	# The boss holds still while the player walks the room.
	_boss.set_physics_process(false)
	# The room's own origin, not the boss's — the boss stands 3 units south of
	# centre, so corners measured from it fall outside the walls.
	var centre: Vector3 = _boss_room.global_position
	var fight_spot: Vector3 = _boss.global_position

	# 1) a full dodge fits in every direction from where the fight happens
	var space: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state
	var reach: float = _player.dodge_speed * _player.combat.data.dodge_duration
	var clearances: Array[float] = []
	for dir in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var from: Vector3 = fight_spot + Vector3(0, 0.9, 0)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + dir * (reach + 1.0), 1)
		var hit: Dictionary = space.intersect_ray(query)
		clearances.append(reach + 1.0 if hit.is_empty() else from.distance_to(hit["position"]))
	var tightest: float = clearances.min()
	_record(tightest >= reach,
		"A1) a full dodge (%.1f) fits in every direction; tightest is %.1f" % [reach, tightest])

	# 2) every corner can be walked into and walked back out of
	var stuck: Array[String] = []
	# Walking back aims beside the boss, not into it: its own collider is not a
	# trapped corner.
	var open_floor: Vector3 = centre + Vector3(0, 0, 4.0)
	for corner in [Vector3(7.5, 0, 7.5), Vector3(-7.5, 0, 7.5), Vector3(7.5, 0, -7.5), Vector3(-7.5, 0, -7.5)]:
		var target: Vector3 = centre + corner
		_player.global_position = centre + corner * 0.55
		await get_tree().physics_frame
		var reached: bool = await _walk_player_to(target, 3.5)
		var escaped: bool = await _walk_player_to(open_floor, 5.0)
		if not escaped:
			stuck.append("%s (reached=%s)" % [corner, reached])
	_record(stuck.is_empty(), "A2) no corner traps the player: %s" % [
		"all four clear" if stuck.is_empty() else stuck])

	# 3) the navmesh covers the arena, so the boss can follow anywhere
	var unreachable: Array[String] = []
	for corner in [Vector3(7.0, 0, 7.0), Vector3(-7.0, 0, 7.0), Vector3(7.0, 0, -7.0), Vector3(-7.0, 0, -7.0)]:
		_boss.nav_agent.target_position = centre + corner
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not _boss.nav_agent.is_target_reachable():
			unreachable.append(str(corner))
	_record(unreachable.is_empty(), "A3) the boss can path to every corner: %s" % [
		"all four reachable" if unreachable.is_empty() else unreachable])

	_boss.nav_agent.target_position = _boss.global_position
	_boss.set_physics_process(true)
	_player.global_position = fight_spot + Vector3(0, 0, 2.5)
	await get_tree().physics_frame


## Drives the player's body the way its own controller does. Returns whether it
## got there.
func _walk_player_to(target: Vector3, budget: float) -> bool:
	_player.set_physics_process(false)
	var elapsed: float = 0.0
	while elapsed < budget:
		var to_target: Vector3 = target - _player.global_position
		to_target.y = 0.0
		if to_target.length() < 0.8:
			_player.set_physics_process(true)
			return true
		var dir: Vector3 = to_target.normalized()
		_player.velocity.x = dir.x * 6.0
		_player.velocity.z = dir.z * 6.0
		if _player.is_on_floor():
			if _player.velocity.y < 0.0:
				_player.velocity.y = 0.0
		else:
			_player.velocity.y -= 20.0 * get_physics_process_delta_time()
		_player.move_and_slide()
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_player.set_physics_process(true)
	return false


# --- phase 1 --------------------------------------------------------------------

func _phase_1_tests() -> void:
	_record(_boss.get_phase_index() == 0 and _boss.get_phase_id() == &"phase_1",
		"1) the boss starts in its first phase (%s)" % _boss.get_phase_id())
	_record(_bar.get_phase_text() == _bar.phase_text_format % 1,
		"1b) the UI reads '%s'" % _bar.get_phase_text())

	# 2) phase 1 offers exactly the three original attacks
	var p1: Array[StringName] = []
	var p2: Array[StringName] = []
	for attack in _boss.data.phases[0].attacks:
		p1.append(attack.get_id())
	for attack in _boss.data.phases[1].attacks:
		p2.append(attack.get_id())
	_record(p1.size() == 3 and not p1.has(&"boss_double_strike"),
		"2) phase 1 offers the three original attacks: %s" % [p1])
	_record(p2.size() == 4 and p2.has(&"boss_double_strike"),
		"2b) phase 2 adds Double Strike: %s" % [p2])

	# 3) above the threshold nothing happens
	await _place_player(2.0)
	_set_boss_health(0.6)
	await _wait(0.4)
	_record(_boss.get_phase_index() == 0 and not _boss.is_in_transition(),
		"3) at 60%% health the boss is still in phase 1 and has not transitioned")


# --- the transition ---------------------------------------------------------------

func _transition_tests() -> void:
	# Catch it mid-attack, so the interruption is real rather than convenient.
	_heal_player()
	await _place_player(1.8)
	_only_attack(SLAM)
	var waited: float = 0.0
	while waited < 3.0 and _boss.get_state() != DungeonBoss.State.ATTACK:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	var was_attacking: bool = _boss.get_state() == DungeonBoss.State.ATTACK

	var hp_at_cut: float = _player.health_component.current_health
	_set_boss_health(0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_record(was_attacking and _boss.get_state() == DungeonBoss.State.TRANSITION,
		"4/5) crossing 50%% interrupts the attack in flight and enters TRANSITION (was attacking=%s)" % was_attacking)
	_record(_boss.get_phase_index() == 0 and _boss.get_transition_target() == 1,
		"4b) the transition leads to phase 2, which has not begun yet")
	_record(_boss.get_current_attack() == null
			and _boss.get_attack_phase() == BossCombat.Phase.NONE,
		"5b) the queued attack is cancelled, not left half-run")

	_record(not _any_hitbox_live(), "6) every attack hitbox is off during the transition")
	_record(_bar.is_banner_showing() and _bar.get_phase_text() == _bar.phase_text_format % 2,
		"7/10) the UI flashes the phase callout and reads '%s'" % _bar.get_phase_text())

	# 8) harmless and still for the whole beat
	var pos: Vector3 = _boss.global_position
	var moved: float = 0.0
	var elapsed: float = 0.0
	var attacked: bool = false
	while elapsed < _boss.data.phases[1].transition_duration - 0.2:
		if _boss.get_state() == DungeonBoss.State.ATTACK:
			attacked = true
		moved = maxf(moved, _boss.global_position.distance_to(pos))
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_record(not attacked and _player.health_component.current_health == hp_at_cut,
		"8) the boss neither attacks nor damages the player during the transition")
	_record(moved < 0.2, "8b) it does not chase or reposition either (drift=%.3f)" % moved)

	await _wait(0.6)
	_record(_boss.get_phase_index() == 1 and _boss.get_phase_id() == &"phase_2",
		"9) the transition ends in phase 2 (%s)" % _boss.get_phase_id())
	_record(_boss.get_state() != DungeonBoss.State.TRANSITION,
		"9b) and the boss resumes acting (state=%d)" % _boss.get_state())

	# 4) it can never run twice
	_set_boss_health(0.3)
	await _wait(0.3)
	_record(_boss.get_phase_index() == 1
			and _boss.get_state() != DungeonBoss.State.TRANSITION,
		"4c) dropping further does not re-run the transition")


# --- phase 2 ----------------------------------------------------------------------

func _phase_2_tests() -> void:
	var phase_2: BossPhaseData = _boss.data.phases[1]
	var tempo: float = phase_2.tempo_multiplier
	var speed: float = _boss.data.movement_speed * phase_2.movement_speed_multiplier
	_record(is_equal_approx(_boss.movement_speed, speed) and _boss.movement_speed > _boss.data.movement_speed
			and is_equal_approx(_boss.nav_agent.max_speed, speed),
		"11) phase 2 raises movement speed to %.2f" % _boss.movement_speed)

	var quick: BossAttack = _attack(QUICK)
	var sweep: BossAttack = _attack(SWEEP)
	var slam: BossAttack = _attack(SLAM)
	_record(tempo < 1.0,
		"12/13/14) phase 2 quickens every wind-up and recovery (tempo %.2f): quick %.2f/%.2f, sweep %.2f/%.2f, slam %.2f/%.2f" % [
			tempo, quick.attack.windup * tempo, quick.attack.recovery * tempo,
			sweep.attack.windup * tempo, sweep.attack.recovery * tempo,
			slam.attack.windup * tempo, slam.attack.recovery * tempo])
	_record(_boss.combat.get_hitbox(quick).damage == 20.0 and _boss.combat.get_hitbox(sweep).damage == 30.0
			and _boss.combat.get_hitbox(slam).damage == 40.0,
		"14b) phase 2 changes the rhythm, not the damage (%.0f/%.0f/%.0f)" % [
			_boss.combat.get_hitbox(quick).damage, _boss.combat.get_hitbox(sweep).damage,
			_boss.combat.get_hitbox(slam).damage])

	# 12b) the telegraph still takes up most of the wind-up, so it stays readable
	_heal_player()
	await _place_player(2.0)
	_only_attack(QUICK)
	var startup_seen: float = 0.0
	var elapsed: float = 0.0
	while elapsed < 2.5:
		if _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH:
			startup_seen += get_physics_process_delta_time()
		if _boss.get_attack_phase() == BossCombat.Phase.ACTIVE:
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_record(startup_seen >= 0.15 and startup_seen <= quick.attack.windup * tempo + 0.05,
		"12b) the phase 2 Quick Strike shows its quickened wind-up before it lands (%.2fs of %.2f)" % [
			startup_seen, quick.attack.windup * tempo])

	# 28) cooldowns drop but still exist
	_record(is_equal_approx(quick.cooldown * tempo, 0.8)
			and is_equal_approx(sweep.cooldown * tempo, 1.6)
			and is_equal_approx(slam.cooldown * tempo, 2.8),
		"28) phase 2 cooldowns: %.1f / %.1f / %.1f" % [
			quick.cooldown * tempo, sweep.cooldown * tempo, slam.cooldown * tempo])
	_heal_player()
	await _place_player(2.0)
	_only_attack(QUICK)
	var saw: bool = await _await_attack_start()
	_record(saw and _boss.combat.get_cooldown(quick) > 0.0
			and _boss.combat.get_cooldown(quick) <= 0.8,
		"28b) using it starts its phase 2 cooldown (%.2f of 0.8)" % _boss.combat.get_cooldown(quick))


# --- Double Strike ---------------------------------------------------------------

func _double_strike_tests() -> void:
	var attack: BossAttack = _attack(DOUBLE)
	var double_damage: float = _boss.combat.get_hitbox(attack).damage
	_record(attack.hit_count == 2 and double_damage == 18.0
			and is_equal_approx(attack.delay_between_hits, 0.22),
		"16/17/18) Double Strike is %d hits of %.0f, %.2fs apart" % [
			attack.hit_count, double_damage, attack.delay_between_hits])

	# 15/16) two separate hit windows, one hitbox, opened twice
	_heal_player()
	await _place_player(1.8)
	var log: Array = _watch_hitbox(DOUBLE)
	_only_attack(DOUBLE)
	var used: bool = await _await_attack_start()
	used = used and _boss.get_current_attack() == attack
	# Count only this one attack: the 2.2s cooldown would let a second start
	# inside a fixed window, which is the decision layer working, not a defect.
	var windows: int = 0
	var was_active: bool = false
	var elapsed: float = 0.0
	while elapsed < 3.0 and _boss.get_state() == DungeonBoss.State.ATTACK:
		var active: bool = _boss.get_attack_phase() == BossCombat.Phase.ACTIVE
		if active and not was_active:
			windows += 1
		was_active = active
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_record(used, "15) the decision layer uses Double Strike in phase 2")
	_record(windows == 2, "16b) it opens exactly two hit windows (%d)" % windows)
	_record(log.size() == 2 and log[0]["damage"] == 18.0 and log[1]["damage"] == 18.0,
		"17/18b) both swings land for 18 (%d hits: %s)" % [log.size(),
			[log[0]["damage"], log[1]["damage"]] if log.size() == 2 else []])
	_record(_player.health_component.max_health - _player.health_component.current_health == 36.0,
		"19/20) each swing hits once and the second still lands (total %.0f)" % [
			_player.health_component.max_health - _player.health_component.current_health])

	# 21) step out during the wind-up and neither swing connects
	_heal_player()
	await _place_player(1.8)
	_only_attack(DOUBLE)
	elapsed = 0.0
	while elapsed < 3.0:
		if _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH:
			_player.global_position = _boss.global_position + Vector3(7.0, 0, 0)
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	await _wait(1.6)
	_record(_player.health_component.current_health == _player.health_component.max_health,
		"21/23a) leaving during the wind-up avoids both swings (hp %.0f)" % _player.health_component.current_health)

	# 22/23) eat the first, leave before the second
	_heal_player()
	await _place_player(1.8)
	_only_attack(DOUBLE)
	var hp_after_first: float = -1.0
	elapsed = 0.0
	while elapsed < 3.0:
		if _player.health_component.current_health < _player.health_component.max_health:
			hp_after_first = _player.health_component.current_health
			_player.global_position = _boss.global_position + Vector3(7.0, 0, 0)
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	await _wait(1.2)
	_record(hp_after_first > 0.0
			and _player.health_component.current_health == hp_after_first,
		"22/23b) hit by the first, clear of the second (hp %.0f, took %.0f)" % [
			_player.health_component.current_health,
			_player.health_component.max_health - _player.health_component.current_health])

	# 24) i-frames cover a Double Strike swing like any other
	_heal_player()
	await _place_player(1.6)
	_only_attack(DOUBLE)
	var dodged: bool = false
	elapsed = 0.0
	while elapsed < 3.0:
		if _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH and not dodged:
			_player.hurtbox.set_invulnerable(true)
			dodged = true
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_record(dodged and _player.health_component.current_health == _player.health_component.max_health,
		"24) i-frames shrug off Double Strike (hp %.0f)" % _player.health_component.current_health)
	_player.hurtbox.set_invulnerable(false)

	# 25) the gap nudges the aim, it does not snap onto a player who moved
	_heal_player()
	await _place_player(1.8)
	_only_attack(DOUBLE)
	var yaw_at_gap: float = 0.0
	var yaw_at_hit2: float = 0.0
	var seen_gap: bool = false
	elapsed = 0.0
	while elapsed < 3.0:
		if _boss.get_attack_phase() == BossCombat.Phase.BETWEEN_HITS and not seen_gap:
			seen_gap = true
			yaw_at_gap = _boss.visual_root.rotation.y
			_player.global_position = _boss.global_position + Vector3(4.0, 0, 0)
		if seen_gap and _boss.get_attack_phase() == BossCombat.Phase.ACTIVE:
			yaw_at_hit2 = _boss.visual_root.rotation.y
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	var swing: float = absf(wrapf(yaw_at_hit2 - yaw_at_gap, -PI, PI))
	_record(seen_gap and swing < deg_to_rad(35.0),
		"25) the second swing is nudged, not snapped onto the player (turned %.1f deg)" % rad_to_deg(swing))

	# The spec asks specifically that Double Strike not look like Quick Strike.
	# Read it off the body, not the resource: a telegraph that is configured but
	# never animated must not count as readable.
	var quick_peak: Dictionary = await _telegraph_peak(QUICK)
	var double_peak: Dictionary = await _telegraph_peak(DOUBLE)
	_record(_shape_of(quick_peak) == "lean" and _shape_of(double_peak) == "recoil",
		"D1) Double Strike's wind-up reads apart from Quick Strike's: %s vs %s" % [
			_shape_of(quick_peak), _shape_of(double_peak)])
	_record(double_peak["pz"] > 0.1 and quick_peak["pz"] < 0.05,
		"D2) it cocks backwards (%.2f) where Quick Strike does not (%.2f)" % [
			double_peak["pz"], quick_peak["pz"]])


## Forces one attack and returns how far the body actually moved during its
## wind-up.
func _telegraph_peak(index: int) -> Dictionary:
	_heal_player()
	await _place_player(1.8)
	_only_attack(index)
	var peak: Dictionary = {"pz": 0.0, "rx": 0.0, "ry": 0.0, "sy": 1.0}
	var elapsed: float = 0.0
	while elapsed < 3.5:
		if _boss.get_current_attack() == _attack(index) \
				and _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH:
			var root: Node3D = _boss.mesh_root
			peak["pz"] = maxf(peak["pz"], absf(root.position.z))
			peak["rx"] = maxf(peak["rx"], absf(root.rotation.x))
			peak["ry"] = maxf(peak["ry"], absf(root.rotation.y))
			peak["sy"] = minf(peak["sy"], root.scale.y)
		if _boss.get_attack_phase() == BossCombat.Phase.ACTIVE:
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	return peak


func _shape_of(peak: Dictionary) -> String:
	if peak["ry"] > 0.5:
		return "spin"
	if peak["sy"] < 0.8:
		return "compress"
	if peak["pz"] > 0.1:
		return "recoil"
	if peak["rx"] > 0.1:
		return "lean"
	return "none"


# --- decision logic ----------------------------------------------------------------

func _decision_tests() -> void:
	# Free fight in phase 2: watch what it actually chooses.
	_heal_player()
	await _place_player(2.0)
	_boss.combat.clear_cooldowns()
	_boss._change_state(DungeonBoss.State.DECIDE)
	var all: Array[BossAttack] = _boss.get_attacks()

	var sequence: Array[int] = []
	var last: int = -1
	var idle: float = 0.0
	var elapsed: float = 0.0
	while elapsed < 24.0:
		_player.health_component.current_health = _player.health_component.max_health
		_player.health_component.is_dead = false
		_boss.health_component.current_health = _boss.health_component.max_health * 0.3
		var index: int = all.find(_boss.get_current_attack())
		if index >= 0 and index != last:
			sequence.append(index)
		last = index
		if _boss.get_state() == DungeonBoss.State.DECIDE \
				or _boss.get_state() == DungeonBoss.State.REPOSITION:
			idle += get_physics_process_delta_time()
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()

	var counts: Array[int] = [0, 0, 0, 0]
	var max_run: int = 0
	var run: int = 0
	var previous: int = -1
	for index in sequence:
		counts[index] += 1
		run = run + 1 if index == previous else 1
		max_run = maxi(max_run, run)
		previous = index

	_record(sequence.size() >= 8 and max_run <= _boss.data.max_consecutive_repeats,
		"26a/27a) no attack repeats more than %d in a row (longest=%d over %d attacks)" % [
			_boss.data.max_consecutive_repeats, max_run, sequence.size()])
	_record(counts[DOUBLE] >= 1 and counts[DOUBLE] <= sequence.size() / 2,
		"26b) Double Strike is used but not spammed (%d of %d)" % [counts[DOUBLE], sequence.size()])
	_record(counts[SLAM] < counts[QUICK] + counts[SWEEP] + counts[DOUBLE],
		"27b) Ground Slam stays rarer than the standard melee (%d slam vs %d melee)" % [
			counts[SLAM], counts[QUICK] + counts[SWEEP] + counts[DOUBLE]])
	_record(idle / elapsed < 0.6,
		"26c) phase 2 spends most of its time committed, not idling (%.0f%% idle)" % [
			100.0 * idle / elapsed])
	_record(counts[QUICK] > 0 and counts[SWEEP] > 0 and counts[SLAM] > 0 and counts[DOUBLE] > 0,
		"26d) all four phase 2 attacks appear: %s" % [counts])


# --- death -------------------------------------------------------------------------

func _death_tests() -> void:
	_heal_player()
	await _place_player(2.0)
	# Kill it mid-attack, so the teardown has something in flight to tear down.
	_only_attack(DOUBLE)
	var elapsed: float = 0.0
	while elapsed < 3.0:
		if _boss.get_attack_phase() == BossCombat.Phase.TELEGRAPH:
			break
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	var killed_mid_attack: bool = _boss.get_state() == DungeonBoss.State.ATTACK
	_boss.hurtbox.receive_hit(DamageInfo.new(10000.0, null))
	await get_tree().physics_frame

	_record(killed_mid_attack and _boss.get_state() == DungeonBoss.State.DEAD
			and _boss.get_phase_index() == 1,
		"29) the boss dies during a phase 2 attack (state=%d phase=%d)" % [
			_boss.get_state(), _boss.get_phase_index()])

	# 31) the second swing must not arrive from beyond the grave
	var hp: float = _player.health_component.current_health
	var any_live: bool = false
	elapsed = 0.0
	while elapsed < 1.5:
		any_live = any_live or _any_hitbox_live()
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	_record(not any_live and _player.health_component.current_health == hp,
		"31) no delayed hit window opens after death")
	_record(not _bar.is_showing() and not _bar.is_banner_showing(),
		"31b) the boss UI and its phase callout both go away")

	await _wait(0.6)
	_record(_boss_room.is_cleared(), "32) the boss room clears")
	_record(_dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"33) the dungeon completes")
	_record(_dungeon.exit_portal.is_enabled(), "34) the exit portal goes live")


# --- dying inside the transition ------------------------------------------------

func _death_during_transition_tests() -> void:
	await _setup()
	await _place_player(2.0)
	_set_boss_health(0.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var in_transition: bool = _boss.get_state() == DungeonBoss.State.TRANSITION

	_boss.hurtbox.receive_hit(DamageInfo.new(10000.0, null))
	await get_tree().physics_frame
	_record(in_transition and _boss.get_state() == DungeonBoss.State.DEAD,
		"30) the boss can be killed during the transition (state=%d)" % _boss.get_state())

	var pos: Vector3 = _boss.global_position
	var hp: float = _player.health_component.current_health
	await _wait(1.8)
	var any_live: bool = _any_hitbox_live()
	_record(_boss.get_state() == DungeonBoss.State.DEAD
			and not any_live
			and _boss.global_position.distance_to(pos) < 0.05
			and _player.health_component.current_health == hp,
		"30b) it stays dead past the transition's end — no phase 2, no hitbox, no drift")
	_record(_boss_room.is_cleared() and _dungeon.get_state() == DungeonController.DungeonState.COMPLETED,
		"30c) the room still clears exactly once and the dungeon completes")


## Every suite starts from a clean session: PlayerRuntimeState now carries
## progression and health across scene changes, so without this a later test
## would inherit whatever an earlier one left behind.
func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
