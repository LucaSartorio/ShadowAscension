extends Node3D

## M3.2 Enemy Combat Polish — avoidance, spacing, reposition, facing, telegraph,
## multi-enemy behavior. M3.1 regression lives in enemy_test.tscn.

@onready var _player: Player = $Player
@onready var _a: BasicMeleeEnemy = $EnemyA
@onready var _b: BasicMeleeEnemy = $EnemyB
@onready var _c: BasicMeleeEnemy = $EnemyC
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _los_wall: StaticBody3D = $NavigationRegion3D/LosWall

const PARK: Vector3 = Vector3(0, 0.1, 20)

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_nav_region.bake_navigation_mesh(false)
	_run_tests()


func _run_tests() -> void:
	await _wait(0.4)
	await _test_avoidance_configured()
	await _test_two_enemies_do_not_share_a_target()
	await _test_three_enemies_spread_around_player()
	await _test_too_close_enemy_repositions()
	await _test_reposition_never_gets_stuck()
	await _test_facing_gate_before_attack()
	await _test_startup_facing_correction_is_gradual()
	await _test_no_tracking_during_active()
	await _test_player_avoids_laterally()
	await _test_attack_range_matches_hitbox_reach()
	await _test_no_attack_through_wall()
	await _test_enemy_does_not_cross_wall()
	await _test_enemies_do_not_push_player()
	await _test_dead_enemy_leaves_avoidance()
	await _test_enemies_die_independently()
	await _test_attacks_are_not_synchronized()
	await _test_aggro_survives_brief_distance_spike()
	print("[SUMMARY] passed=%d failed=%d" % [_pass, _fail])
	get_tree().quit()


# --- helpers ------------------------------------------------------------------

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _record(passed: bool, description: String) -> void:
	if passed:
		_pass += 1
		print("[PASS] " + description)
	else:
		_fail += 1
		print("[FAIL] " + description)


func _reset_player(pos: Vector3 = Vector3(0, 0.1, 0)) -> void:
	if _player._visual_tween != null and _player._visual_tween.is_running():
		_player._visual_tween.kill()
	_player.global_position = pos
	_player.visual_root.rotation = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player._is_dodging = false
	_player._dodge_cooldown_remaining = 0.0
	_player._attack_state = Player.AttackState.IDLE
	_player._attack_timer = 0.0
	_player._combo_index = 0
	_player._queued_next = false
	_player._current_step = null
	if _player.hurtbox != null:
		_player.hurtbox.set_invulnerable(false)
	if _player.health_component != null:
		_player.health_component.current_health = _player.health_component.max_health
		_player.health_component.is_dead = false
	if _player.attack_hitbox != null and _player.attack_hitbox.is_active():
		_player.attack_hitbox.deactivate()


func _reset_enemy(
	e: BasicMeleeEnemy,
	pos: Vector3,
	angle_offset: float = 0.0,
	delay: float = 0.0,
	cooldown_variation: float = 0.0,
	face_player: bool = true
) -> void:
	e.global_position = pos
	e.velocity = Vector3.ZERO
	e.combat_angle_offset_degrees = angle_offset
	e.initial_attack_delay = delay
	e.attack_cooldown_variation = cooldown_variation
	e._state = BasicMeleeEnemy.State.IDLE
	e._attack_phase = BasicMeleeEnemy.AttackPhase.NONE
	e._phase_timer = 0.0
	e._cooldown_timer = 0.0
	e._attack_delay_timer = 0.0
	e._lose_target_timer = 0.0
	e._reposition_timer = 0.0
	e._reposition_block_timer = 0.0
	e._desired_horizontal = Vector3.ZERO
	e._reset_telegraph_instantly()
	e.visual_root.rotation = Vector3.ZERO
	if e.mesh_instance != null:
		e.mesh_instance.scale = Vector3.ONE
	if e.hitbox != null and e.hitbox.is_active():
		e.hitbox.deactivate()
	if e.health_component != null:
		e.health_component.current_health = e.health_component.max_health
		e.health_component.is_dead = false
		e._last_health = e.health_component.max_health
	if e.hurtbox != null:
		e.hurtbox.monitorable = true
	if e.hurtbox_collision != null:
		e.hurtbox_collision.disabled = false
	if e.body_collision != null:
		e.body_collision.disabled = false
	e.nav_agent.avoidance_enabled = true
	if face_player:
		_face(e, _player.global_position)


func _face(e: BasicMeleeEnemy, target: Vector3) -> void:
	var to_t: Vector3 = target - e.global_position
	to_t.y = 0.0
	if to_t.length_squared() < 0.0001:
		return
	e.visual_root.rotation.y = atan2(-to_t.x, -to_t.z)


func _park_all() -> void:
	var i: int = 0
	for e in [_a, _b, _c]:
		_reset_enemy(e, PARK + Vector3(i * 3.0, 0, 0), 0.0, 0.0, 0.0, false)
		i += 1


func _flat_distance(u: Vector3, v: Vector3) -> float:
	return Vector2(u.x - v.x, u.z - v.z).length()


func _bearing_around(target: Vector3, point: Vector3) -> float:
	return atan2(point.x - target.x, point.z - target.z)


# --- tests --------------------------------------------------------------------

func _test_avoidance_configured() -> void:
	var n: NavigationAgent3D = _a.nav_agent
	var ok: bool = (
		n.avoidance_enabled
		and is_equal_approx(n.radius, _a.enemy_spacing_radius)
		and is_equal_approx(n.max_speed, _a.movement_speed)
		and n.neighbor_distance > 0.0
		and n.max_neighbors > 0
		and n.time_horizon_agents > 0.0
	)
	_record(ok, "1) avoidance configured (enabled=%s radius=%.2f neighbors=%d neighbor_dist=%.1f horizon=%.1f max_speed=%.2f)" % [
		n.avoidance_enabled, n.radius, n.max_neighbors, n.neighbor_distance, n.time_horizon_agents, n.max_speed])


func _test_two_enemies_do_not_share_a_target() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(-0.6, 0.1, 6.0), 0.0)
	_reset_enemy(_b, Vector3(0.6, 0.1, 6.5), 35.0)
	await _wait(2.0)
	var target_gap: float = _flat_distance(_a.nav_agent.target_position, _b.nav_agent.target_position)
	var body_gap: float = _flat_distance(_a.global_position, _b.global_position)
	var ok: bool = target_gap > 0.3 and body_gap > 0.8
	_record(ok, "2) two enemies keep separate targets (target_gap=%.2f body_gap=%.2f)" % [target_gap, body_gap])


func _test_three_enemies_spread_around_player() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(0.0, 0.1, 5.0), 0.0)
	_reset_enemy(_b, Vector3(1.2, 0.1, 5.2), 40.0)
	_reset_enemy(_c, Vector3(-1.2, 0.1, 5.2), -40.0)
	await _wait(3.0)
	var bearings: Array[float] = []
	var min_gap: float = 999.0
	for e in [_a, _b, _c]:
		bearings.append(_bearing_around(_player.global_position, e.global_position))
	for i in 3:
		for j in range(i + 1, 3):
			min_gap = minf(min_gap, _flat_distance(
				[_a, _b, _c][i].global_position, [_a, _b, _c][j].global_position))
	var spread: float = 0.0
	for i in 3:
		for j in range(i + 1, 3):
			spread = maxf(spread, absf(wrapf(bearings[i] - bearings[j], -PI, PI)))
	var ok: bool = min_gap > 0.8 and spread > deg_to_rad(30.0)
	_record(ok, "3) three enemies spread around player (min_gap=%.2f angular_spread=%.0f deg)" % [
		min_gap, rad_to_deg(spread)])


func _test_too_close_enemy_repositions() -> void:
	_park_all()
	_reset_player()
	# spawn well inside minimum_combat_distance (1.15)
	_reset_enemy(_a, Vector3(0, 0.1, 0.9))
	await _wait(0.2)
	var repositioning: bool = _a._state == BasicMeleeEnemy.State.REPOSITION
	await _wait(1.3)
	var dist: float = _flat_distance(_a.global_position, _player.global_position)
	var backed_off: bool = dist >= _a.minimum_combat_distance
	_record(repositioning and backed_off, "4) too-close enemy repositions and backs off (entered=%s dist=%.2f >= %.2f)" % [
		repositioning, dist, _a.minimum_combat_distance])
	await _wait(0.3)


func _test_reposition_never_gets_stuck() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(0, 0.1, 5.0))
	await _wait(0.2)
	# force the state and let the timeout fallback do its job
	_a._state = BasicMeleeEnemy.State.REPOSITION
	_a._reposition_timer = _a.reposition_timeout
	var elapsed: float = 0.0
	var limit: float = _a.reposition_timeout + 0.6
	while elapsed < limit and _a._state == BasicMeleeEnemy.State.REPOSITION:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	var escaped: bool = _a._state != BasicMeleeEnemy.State.REPOSITION
	_record(escaped, "5) reposition exits via timeout (escaped=%s after %.2fs, timeout=%.2f)" % [
		escaped, elapsed, _a.reposition_timeout])


func _test_facing_gate_before_attack() -> void:
	_park_all()
	_reset_player()
	# in attack range but looking the wrong way
	_reset_enemy(_a, Vector3(0, 0.1, 1.5), 0.0, 0.0, 0.0, false)
	_a.visual_root.rotation.y = PI
	await _wait(0.12)
	var blocked: bool = _a._state != BasicMeleeEnemy.State.ATTACK
	var error_then: float = _a._facing_error_to(_player)
	await _wait(1.2)
	var attacked: bool = _a._state == BasicMeleeEnemy.State.ATTACK or _a._attack_phase != BasicMeleeEnemy.AttackPhase.NONE
	_record(blocked and attacked, "6) attack gated until aligned (blocked_at %.0f deg=%s, attacked_after_turn=%s)" % [
		rad_to_deg(error_then), blocked, attacked])
	await _wait(1.3)


func _test_startup_facing_correction_is_gradual() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(0, 0.1, 1.5))
	await _wait(0.15)  # inside STARTUP
	var in_startup: bool = _a._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP
	var yaw_before: float = _a.visual_root.rotation.y
	# jump the player 90 degrees around the enemy
	_player.global_position = Vector3(1.5, 0.1, 1.5)
	await _wait(0.18)  # remainder of STARTUP
	var yaw_after: float = _a.visual_root.rotation.y
	var turned: float = absf(wrapf(yaw_after - yaw_before, -PI, PI))
	var residual: float = _a._facing_error_to(_player)
	# it corrects, but cannot snap: a large residual error must remain
	var ok: bool = in_startup and turned > 0.05 and residual > deg_to_rad(_a.max_attack_facing_angle)
	_record(ok, "7) startup facing correction is gradual (turned=%.0f deg, residual=%.0f deg > %.0f)" % [
		rad_to_deg(turned), rad_to_deg(residual), _a.max_attack_facing_angle])
	await _wait(1.2)


func _test_no_tracking_during_active() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(0, 0.1, 1.5))
	# startup 0.35 -> ACTIVE at ~0.36
	await _wait(0.40)
	var in_active: bool = _a._attack_phase == BasicMeleeEnemy.AttackPhase.ACTIVE
	var yaw_before: float = _a.visual_root.rotation.y
	_player.global_position = Vector3(1.5, 0.1, 1.5)
	await _wait(0.08)
	var yaw_after: float = _a.visual_root.rotation.y
	var locked: bool = is_equal_approx(yaw_before, yaw_after)
	_record(in_active and locked, "8) no facing tracking during ACTIVE (active=%s yaw %.4f -> %.4f)" % [
		in_active, yaw_before, yaw_after])
	await _wait(1.2)


func _test_player_avoids_laterally() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(0, 0.1, 1.5))
	await _wait(0.12)  # STARTUP, telegraph readable
	var hp_before: float = _player.health_component.current_health
	# sidestep out of the swing arc instead of retreating
	_player.global_position = Vector3(1.9, 0.1, 1.5)
	await _wait(0.6)  # through the whole ACTIVE window
	var hp_after: float = _player.health_component.current_health
	_record(hp_before == hp_after, "9) player sidesteps the swing (hp %.0f -> %.0f)" % [hp_before, hp_after])
	await _wait(1.2)


func _test_attack_range_matches_hitbox_reach() -> void:
	_park_all()
	_reset_player()
	var box: BoxShape3D = _a.hitbox.get_node("CollisionShape3D").shape as BoxShape3D
	var origin_z: float = absf(_a.attack_origin.position.z)
	var near_edge: float = origin_z - box.size.z * 0.5
	var far_edge: float = origin_z + box.size.z * 0.5
	# the decision distance must sit inside what the hitbox can physically cover
	var coherent: bool = _a.attack_range <= far_edge and _a.minimum_combat_distance >= near_edge
	var band_ok: bool = (
		_a.preferred_combat_distance >= _a.minimum_combat_distance
		and _a.preferred_combat_distance <= _a.attack_range
	)
	# empirical: an attack started at the very edge of attack_range still connects
	_reset_enemy(_a, Vector3(0, 0.1, _a.attack_range - 0.05))
	var hp_before: float = _player.health_component.current_health
	await _wait(0.65)
	var connected: bool = hp_before - _player.health_component.current_health == _a.attack_damage
	_record(coherent and band_ok and connected, "10) attack range coherent with hitbox (range=%.2f in [%.2f, %.2f], band_ok=%s, edge_hit=%s)" % [
		_a.attack_range, near_edge, far_edge, band_ok, connected])
	await _wait(1.0)


func _test_no_attack_through_wall() -> void:
	_park_all()
	# wall spans z in [-0.2, 0.2] at x = 12; both sides are inside attack_range
	_reset_player(Vector3(12, 0.1, 0.85))
	_reset_enemy(_a, Vector3(12, 0.1, -0.85))
	var dist: float = _flat_distance(_a.global_position, _player.global_position)
	var hp_before: float = _player.health_component.current_health
	await _wait(1.2)
	var never_attacked: bool = _a._attack_phase == BasicMeleeEnemy.AttackPhase.NONE
	var no_damage: bool = _player.health_component.current_health == hp_before
	_record(dist < _a.attack_range and never_attacked and no_damage, "11) no attack through wall (dist=%.2f < range=%.2f, phase_none=%s, dmg=%.0f)" % [
		dist, _a.attack_range, never_attacked, hp_before - _player.health_component.current_health])


func _test_enemy_does_not_cross_wall() -> void:
	# continues from the previous setup: enemy still trying to reach the player
	var wall_pos: Vector3 = _los_wall.global_position
	var breached: bool = false
	var elapsed: float = 0.0
	while elapsed < 1.5:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var d: Vector3 = _a.global_position - wall_pos
		# inside the wall volume (half extents 2.0 x 0.2) means it went through
		if absf(d.x) < 2.0 and absf(d.z) < 0.2:
			breached = true
			break
	_record(not breached, "12) enemy never enters the wall volume (breached=%s final_z=%.2f)" % [
		breached, _a.global_position.z])
	_park_all()
	await _wait(0.2)


func _test_enemies_do_not_push_player() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(0, 0.1, 2.6), 0.0)
	_reset_enemy(_b, Vector3(2.3, 0.1, -1.3), 30.0)
	_reset_enemy(_c, Vector3(-2.3, 0.1, -1.3), -30.0)
	await _wait(0.2)
	var start: Vector3 = _player.global_position
	await _wait(2.5)
	var drift: float = _flat_distance(_player.global_position, start)
	_record(drift < 0.5, "13) three converging enemies do not shove the player (drift=%.3f)" % drift)


func _test_dead_enemy_leaves_avoidance() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(0, 0.1, 3.0))
	await _wait(0.3)
	_a.hurtbox.receive_hit(1000.0, self)
	await _wait(0.1)
	var pos_at_death: Vector3 = _a.global_position
	await _wait(1.0)
	var left_avoidance: bool = not _a.nav_agent.avoidance_enabled
	var is_dead: bool = _a._state == BasicMeleeEnemy.State.DEAD
	var stayed_put: bool = _flat_distance(_a.global_position, pos_at_death) < 0.05
	var not_repositioning: bool = _a._state != BasicMeleeEnemy.State.REPOSITION
	_record(left_avoidance and is_dead and stayed_put and not_repositioning, "14) dead enemy leaves avoidance and stops moving (avoidance=%s dead=%s drift=%.3f)" % [
		_a.nav_agent.avoidance_enabled, is_dead, _flat_distance(_a.global_position, pos_at_death)])


func _test_enemies_die_independently() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(-1.8, 0.1, 4.0), -25.0)
	_reset_enemy(_b, Vector3(0.0, 0.1, 4.5), 0.0)
	_reset_enemy(_c, Vector3(1.8, 0.1, 4.0), 25.0)
	await _wait(0.4)
	_b.hurtbox.receive_hit(1000.0, self)
	await _wait(0.5)
	var b_dead: bool = _b._state == BasicMeleeEnemy.State.DEAD
	var a_alive: bool = _a._state != BasicMeleeEnemy.State.DEAD and not _a.health_component.is_dead
	var c_alive: bool = _c._state != BasicMeleeEnemy.State.DEAD and not _c.health_component.is_dead
	var others_engaged: bool = _a._state != BasicMeleeEnemy.State.IDLE and _c._state != BasicMeleeEnemy.State.IDLE
	_record(b_dead and a_alive and c_alive and others_engaged, "15) enemies die independently (b_dead=%s a_alive=%s c_alive=%s others_engaged=%s)" % [
		b_dead, a_alive, c_alive, others_engaged])
	await _wait(0.3)


func _test_attacks_are_not_synchronized() -> void:
	_park_all()
	_reset_player()
	# same distance, same facing, only the per-instance delay differs
	_reset_enemy(_a, Vector3(0.0, 0.1, 1.5), 0.0, 0.0, 0.0)
	_reset_enemy(_b, Vector3(1.3, 0.1, -0.75), 0.0, 0.3, 0.15)
	_reset_enemy(_c, Vector3(-1.3, 0.1, -0.75), 0.0, 0.6, 0.3)
	var first_active: Array[float] = [-1.0, -1.0, -1.0]
	var enemies: Array[BasicMeleeEnemy] = [_a, _b, _c]
	var elapsed: float = 0.0
	while elapsed < 3.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		for i in 3:
			if first_active[i] < 0.0 and enemies[i]._attack_phase == BasicMeleeEnemy.AttackPhase.ACTIVE:
				first_active[i] = elapsed
	var all_attacked: bool = first_active[0] >= 0.0 and first_active[1] >= 0.0 and first_active[2] >= 0.0
	var min_gap: float = 999.0
	if all_attacked:
		for i in 3:
			for j in range(i + 1, 3):
				min_gap = minf(min_gap, absf(first_active[i] - first_active[j]))
	_record(all_attacked and min_gap >= 0.15, "16) attacks are desynchronized (first ACTIVE at %.2f / %.2f / %.2f, min gap=%.2fs)" % [
		first_active[0], first_active[1], first_active[2], min_gap])
	await _wait(0.5)


func _test_aggro_survives_brief_distance_spike() -> void:
	_park_all()
	_reset_player()
	_reset_enemy(_a, Vector3(0, 0.1, 6.0))
	await _wait(0.3)
	var engaged: bool = _a._state == BasicMeleeEnemy.State.CHASE
	# blink the player far away for less than lose_target_delay, then back
	_player.global_position = Vector3(0, 0.1, -40)
	await _wait(0.4)
	var held: bool = _a._state != BasicMeleeEnemy.State.IDLE
	_reset_player()
	await _wait(0.3)
	var still_engaged: bool = _a._state != BasicMeleeEnemy.State.IDLE
	_record(engaged and held and still_engaged, "17) aggro survives a spike shorter than lose_target_delay (engaged=%s held=%s recovered=%s)" % [
		engaged, held, still_engaged])
