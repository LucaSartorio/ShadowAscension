extends Node3D

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/basic_melee_enemy.tscn")

@onready var _player: Player = $Player
@onready var _enemy: BasicMeleeEnemy = $BasicMeleeEnemy
@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D

var _pass: int = 0
var _fail: int = 0


## Criticals are random (M11.7) and this suite checks exact damage, so they are
## off for its whole run: every player here reads this one cached instance of
## the combat data. critical_hit_test and m11_critical_run test criticals.
var _no_crits: PlayerCombatData = preload("res://resources/characters/player_combat.tres")


func _ready() -> void:
	_no_crits.critical_chance = 0.0
	_nav_region.bake_navigation_mesh(false)
	_run_tests()


func _run_tests() -> void:
	_reset_session()
	# wait for navigation server to register the baked map
	await _wait(0.4)
	await _test_idle_when_far()
	await _test_chase_on_detection()
	await _test_attack_at_range()
	await _test_attack_phases_and_hitbox_gating()
	await _test_enemy_damages_player_15()
	await _test_player_iframe_avoids_damage()
	await _test_attack_cooldown()
	await _test_return_to_idle_on_lose_target()
	await _test_player_attack_damages_enemy()
	await _test_full_combo_damages_enemy()
	await _test_enemy_dies_and_disables_everything()
	await _test_multi_enemy_operates_concurrently()
	await _test_navigation_around_obstacle()
	await _test_dodge_mistimed_takes_damage()
	await _test_player_avoids_by_moving_during_startup()
	await _test_recovery_commitment()
	await _test_returns_to_chase_when_player_leaves_range()
	await _test_single_hit_per_player_swing()
	await _test_hit_feedback()
	await _test_enemy_is_resource_driven()
	await _test_death_drop_hook()
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


func _reset_player() -> void:
	if _player._visual_tween != null and _player._visual_tween.is_running():
		_player._visual_tween.kill()
	_player.global_position = Vector3(0, 0.1, 0)
	_player.visual_root.rotation = Vector3.ZERO
	_player.camera_rig.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	_player.combat.reset()
	_player._dodge_direction = Vector3.ZERO
	if _player.hurtbox != null:
		_player.hurtbox.set_invulnerable(false)
	if _player.health_component != null:
		_player.health_component.current_health = _player.health_component.max_health
		_player.health_component.is_dead = false
	if _player.attack_hitbox != null and _player.attack_hitbox.is_active():
		_player.attack_hitbox.deactivate()


func _reset_enemy(pos: Vector3) -> void:
	_enemy.global_position = pos
	_enemy.visual_root.rotation = Vector3.ZERO
	_enemy.visual_root.scale = Vector3.ONE
	if _enemy.mesh_instance != null:
		_enemy.mesh_instance.scale = Vector3.ONE
	_enemy.velocity = Vector3.ZERO
	_enemy._state = BasicMeleeEnemy.State.IDLE
	_enemy._attack_phase = BasicMeleeEnemy.AttackPhase.NONE
	_enemy._phase_timer = 0.0
	_enemy._cooldown_timer = 0.0
	_enemy._attack_delay_timer = 0.0
	_enemy.targeting.release()
	_enemy._reposition_timer = 0.0
	_enemy._reposition_block_timer = 0.0
	_enemy._desired_horizontal = Vector3.ZERO
	_enemy._reset_telegraph_instantly()
	if _enemy.hitbox != null and _enemy.hitbox.is_active():
		_enemy.hitbox.deactivate()
	if _enemy.health_component != null:
		_enemy.health_component.current_health = _enemy.health_component.max_health
		_enemy.health_component.is_dead = false
		_enemy._clear_reactions()
	# This helper revives one instance, which nothing in the game ever does: a
	# real run rebuilds the scene. RoomCombatant latches "died once" and "XP
	# claimed once" for exactly that reason, so a revival has to clear them too.
	_enemy._died = false
	_enemy._xp_claimed = false
	if _enemy.hurtbox != null:
		_enemy.hurtbox.monitorable = true
	if _enemy.hurtbox_collision != null:
		_enemy.hurtbox_collision.disabled = false
	if _enemy.body_collision != null:
		_enemy.body_collision.disabled = false


func _test_idle_when_far() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 20))  # > detection_range=10
	await _wait(0.3)
	var ok: bool = _enemy._state == BasicMeleeEnemy.State.IDLE
	_record(ok, "1) enemy IDLE when player far (state=%d)" % _enemy._state)


func _test_chase_on_detection() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 6))  # < detection_range
	await _wait(0.1)
	var ok: bool = _enemy._state == BasicMeleeEnemy.State.CHASE
	var dist_start: float = _enemy.global_position.distance_to(_player.global_position)
	await _wait(0.6)
	var dist_end: float = _enemy.global_position.distance_to(_player.global_position)
	var closed_in: bool = dist_start - dist_end > 0.5
	_record(ok and closed_in, "2) enemy CHASE and closes distance (state=%d %.2f -> %.2f)" % [_enemy._state, dist_start, dist_end])


func _test_attack_at_range() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))  # < attack_range=1.8
	await _wait(0.1)
	var ok: bool = _enemy._state == BasicMeleeEnemy.State.ATTACK
	_record(ok, "3) enemy ATTACK when player in attack range (state=%d)" % _enemy._state)
	# let this attack finish so following tests start clean
	await _wait(1.4)


func _test_attack_phases_and_hitbox_gating() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	await _wait(0.18)  # deep in STARTUP (0.35s)
	var startup_ok: bool = _enemy._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP and not _enemy.hitbox.is_active()
	var telegraph_ok: bool = _enemy.visual_root.scale.distance_to(Vector3.ONE) > 0.05
	# wait into ACTIVE window
	await _wait(0.25)
	var active_ok: bool = _enemy._attack_phase == BasicMeleeEnemy.AttackPhase.ACTIVE and _enemy.hitbox.is_active()
	# wait into RECOVERY
	await _wait(0.17)
	var recovery_ok: bool = _enemy._attack_phase == BasicMeleeEnemy.AttackPhase.RECOVERY and not _enemy.hitbox.is_active()
	_record(startup_ok and telegraph_ok and active_ok and recovery_ok, "4) attack phases: startup_off=%s telegraph=%s active_on=%s recovery_off=%s" % [startup_ok, telegraph_ok, active_ok, recovery_ok])
	await _wait(0.8)


func _test_enemy_damages_player_15() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	var hp_before: float = _player.health_component.current_health
	await _wait(0.6)  # into ACTIVE window (startup 0.35 + ~0.15 into active)
	var hp_mid: float = _player.health_component.current_health
	var damaged: bool = hp_before - hp_mid == 15.0
	_record(damaged, "5) enemy attack deals 15 dmg to player (%.0f -> %.0f delta=%.0f)" % [hp_before, hp_mid, hp_before - hp_mid])
	await _wait(0.9)


func _test_player_iframe_avoids_damage() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	# Enemy attack starts on frame 1. Startup 0.35, active 0.15. Damage lands during active [0.35, 0.5]
	# Time dodge to be in i-frame window during active. Dodge i-frames [0.06, 0.24]
	# Start dodge at t=~0.30 so i-frames cover [0.36, 0.54] — spans full active [0.35, 0.5].
	await _wait(0.30)
	_player._on_dodge_pressed()
	var hp_before: float = _player.health_component.current_health
	await _wait(0.4)  # past enemy active window
	var hp_after: float = _player.health_component.current_health
	_record(hp_before == hp_after, "6) player dodge i-frame avoids enemy damage (hp %.0f -> %.0f)" % [hp_before, hp_after])
	await _wait(0.9)


func _test_attack_cooldown() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	# Attack cycle: 0.35 + 0.15 + 0.65 = 1.15s + ~2 frames.
	await _wait(1.3)  # attack done, cooldown active
	var in_cooldown: bool = _enemy._cooldown_timer > 0.0
	var chase_state: bool = _enemy._state == BasicMeleeEnemy.State.CHASE
	await _wait(0.55)  # past cooldown (0.4s)
	var attacking_after_cd: bool = _enemy._state == BasicMeleeEnemy.State.ATTACK
	_record(in_cooldown and chase_state and attacking_after_cd, "7) attack cooldown respected (cd_active=%s chase=%s after_cd_attacking=%s)" % [in_cooldown, chase_state, attacking_after_cd])
	await _wait(1.4)


func _test_return_to_idle_on_lose_target() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 6))  # inside detection_range
	await _wait(0.1)
	var chased: bool = _enemy._state == BasicMeleeEnemy.State.CHASE
	# move the PLAYER out of range and let the enemy drop the target by itself
	_player.global_position = Vector3(0, 0.1, -30)
	await _wait(0.3)
	# lose_target_delay (1.0s) must still be holding the target here
	var still_engaged: bool = _enemy._state != BasicMeleeEnemy.State.IDLE
	await _wait(1.0)
	var idle_ok: bool = _enemy._state == BasicMeleeEnemy.State.IDLE
	_record(chased and still_engaged and idle_ok, "8) CHASE -> IDLE after lose_target_delay (chased=%s held=%s idle=%s)" % [chased, still_engaged, idle_ok])
	_reset_player()
	await _wait(0.2)


func _test_player_attack_damages_enemy() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, -1.5))  # in front of player facing -Z
	# suppress enemy attacks by keeping it far / re-positioning is not needed since attack test times briefly
	# Player fires attack
	var enemy_hp_before: float = _enemy.health_component.current_health
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.7)
	var enemy_hp_after: float = _enemy.health_component.current_health
	var delta: float = enemy_hp_before - enemy_hp_after
	_record(delta == 20.0, "9) player Attack 1 damages enemy 20 (%.0f -> %.0f)" % [enemy_hp_before, enemy_hp_after])
	await _wait(0.4)


func _test_full_combo_damages_enemy() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, -1.5))
	var enemy_hp_before: float = _enemy.health_component.current_health
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.2)
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.5)
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(1.4)
	var enemy_hp_after: float = _enemy.health_component.current_health
	var delta: float = enemy_hp_before - enemy_hp_after
	_record(delta == 80.0, "10) player full combo damages enemy 80 (%.0f -> %.0f delta=%.0f)" % [enemy_hp_before, enemy_hp_after, delta])
	await _wait(0.4)


func _test_enemy_dies_and_disables_everything() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, -1.5))
	# force lethal damage direct through hurtbox pipeline
	_enemy.hurtbox.receive_hit(DamageInfo.new(1000.0, self))
	await _wait(0.1)
	var dead_state: bool = _enemy._state == BasicMeleeEnemy.State.DEAD
	var hitbox_off: bool = not _enemy.hitbox.is_active()
	# check deferred disables after a frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var body_off: bool = _enemy.body_collision.disabled
	var hurtbox_off: bool = not _enemy.hurtbox.monitorable
	# no movement
	var no_motion: bool = _enemy.velocity == Vector3.ZERO
	_record(dead_state and hitbox_off and body_off and hurtbox_off and no_motion, "11) enemy dead: state=DEAD hitbox_off=%s body_off=%s hurtbox_off=%s no_motion=%s" % [hitbox_off, body_off, hurtbox_off, no_motion])
	# verify dead enemy takes no further damage / cannot attack
	_reset_player()
	_player.global_position = Vector3(0, 0.1, 0)
	_enemy.global_position = Vector3(0, 0.1, 1.0)  # in attack range
	var hp_before: float = _player.health_component.current_health
	await _wait(1.5)
	var no_damage: bool = _player.health_component.current_health == hp_before
	var stays_dead: bool = _enemy._state == BasicMeleeEnemy.State.DEAD
	_record(no_damage and stays_dead, "12) dead enemy doesn't attack (player_dmg=%.0f state=%d)" % [hp_before - _player.health_component.current_health, _enemy._state])


func _test_multi_enemy_operates_concurrently() -> void:
	# spawn 3 fresh enemies and verify all reach CHASE independently
	var extras: Array[BasicMeleeEnemy] = []
	for i in 3:
		var e: BasicMeleeEnemy = ENEMY_SCENE.instantiate() as BasicMeleeEnemy
		add_child(e)
		e.global_position = Vector3(-4 + i * 4, 0.1, 5)
		extras.append(e)
	_reset_player()
	await _wait(0.3)
	var all_chasing: bool = true
	for e in extras:
		if e._state != BasicMeleeEnemy.State.CHASE:
			all_chasing = false
			break
	_record(all_chasing, "13) 3 concurrent enemies all CHASE")
	for e in extras:
		e.queue_free()
	await _wait(0.2)


func _test_navigation_around_obstacle() -> void:
	# Enemy at z=14 behind big wall at z=8 from player at z=0. Widen detection so enemy engages.
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 14))
	var saved_detection: float = _enemy.detection_range
	var saved_lose: float = _enemy.lose_target_range
	_enemy.detection_range = 20.0
	_enemy.lose_target_range = 25.0
	await _wait(0.25)
	var start_pos: Vector3 = _enemy.global_position
	await _wait(3.0)
	var end_pos: Vector3 = _enemy.global_position
	var sideways: float = abs(end_pos.x - start_pos.x)
	# Success if enemy moved sideways to path around wall OR reached the player's side of the wall
	var not_stuck_against_wall: bool = sideways > 0.5 or end_pos.z < 8.0
	var moved: bool = start_pos.distance_to(end_pos) > 1.0
	_enemy.detection_range = saved_detection
	_enemy.lose_target_range = saved_lose
	_record(not_stuck_against_wall and moved, "14) enemy navigates around wall: sideways=%.2f z=%.2f start_z=%.2f moved=%s" % [sideways, end_pos.z, start_pos.z, moved])


func _test_dodge_mistimed_takes_damage() -> void:
	# A dodge started too early or too late must NOT save the player.
	# dodge_speed is zeroed so this measures the i-frame window only, not displacement.
	var saved_speed: float = _player.dodge_speed
	_player.dodge_speed = 0.0

	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	var early_before: float = _player.health_component.current_health
	await _wait(0.02)
	_player._on_dodge_pressed()  # i-frames [0.06, 0.24], enemy ACTIVE lands at ~0.36
	await _wait(0.75)
	var early_delta: float = early_before - _player.health_component.current_health
	await _wait(0.9)

	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	var late_before: float = _player.health_component.current_health
	await _wait(0.45)  # ACTIVE already connected at ~0.36
	_player._on_dodge_pressed()
	await _wait(0.4)
	var late_delta: float = late_before - _player.health_component.current_health

	_player.dodge_speed = saved_speed
	_record(early_delta == 15.0 and late_delta == 15.0, "15) mistimed dodge still takes damage (early=%.0f late=%.0f expect 15/15)" % [early_delta, late_delta])
	await _wait(0.9)


func _test_player_avoids_by_moving_during_startup() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	await _wait(0.15)  # inside STARTUP (0.35s)
	var startup_ok: bool = _enemy._attack_phase == BasicMeleeEnemy.AttackPhase.STARTUP
	_player.global_position = Vector3(0, 0.1, -8.0)  # step out of the telegraphed swing
	var hp_before: float = _player.health_component.current_health
	await _wait(0.6)  # through the whole ACTIVE window
	var hp_after: float = _player.health_component.current_health
	_record(startup_ok and hp_before == hp_after, "16) player escaping during startup takes no damage (startup=%s hp %.0f -> %.0f)" % [startup_ok, hp_before, hp_after])
	await _wait(0.8)
	_reset_player()


func _test_recovery_commitment() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	# startup 0.35 + active 0.15 -> RECOVERY spans ~[0.50, 1.15]
	await _wait(0.60)
	var early_ok: bool = _enemy._attack_phase == BasicMeleeEnemy.AttackPhase.RECOVERY and _enemy._state == BasicMeleeEnemy.State.ATTACK and not _enemy.hitbox.is_active()
	await _wait(0.45)  # still inside recovery (~1.05)
	var late_ok: bool = _enemy._attack_phase == BasicMeleeEnemy.AttackPhase.RECOVERY and _enemy._state == BasicMeleeEnemy.State.ATTACK and not _enemy.hitbox.is_active()
	await _wait(0.25)  # recovery finished (~1.30)
	var ended_ok: bool = _enemy._attack_phase == BasicMeleeEnemy.AttackPhase.NONE
	_record(early_ok and late_ok and ended_ok, "17) enemy stays committed for full recovery (early=%s late=%s ended=%s)" % [early_ok, late_ok, ended_ok])
	await _wait(1.3)


func _test_returns_to_chase_when_player_leaves_range() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 1.5))
	await _wait(0.15)
	var attacking: bool = _enemy._state == BasicMeleeEnemy.State.ATTACK
	_player.global_position = Vector3(0, 0.1, -6.0)  # out of attack_range, still inside detection_range
	await _wait(1.25)  # full attack cycle (1.15s) elapsed
	var chase_ok: bool = _enemy._state == BasicMeleeEnemy.State.CHASE
	_record(attacking and chase_ok, "18) enemy returns to CHASE when player leaves attack range (attacked=%s chase=%s)" % [attacking, chase_ok])
	_reset_player()
	await _wait(0.2)


func _test_single_hit_per_player_swing() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, -1.5))
	var hits: Array[float] = []
	var counter: Callable = func(current: float, _maximum: float) -> void:
		hits.append(current)
	_enemy.health_component.health_changed.connect(counter)
	var before: float = _enemy.health_component.current_health
	_player.camera_rig.attack_light_pressed.emit()
	await _wait(0.7)
	_enemy.health_component.health_changed.disconnect(counter)
	var delta: float = before - _enemy.health_component.current_health
	_record(hits.size() == 1 and delta == 20.0, "19) enemy takes exactly one hit per player swing (hits=%d dmg=%.0f)" % [hits.size(), delta])
	await _wait(0.5)


func _test_hit_feedback() -> void:
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, -1.5))
	_enemy.mesh_instance.scale = Vector3.ONE
	_enemy.hurtbox.receive_hit(DamageInfo.new(10.0, self))
	await _wait(0.04)  # inside the 0.05s squash tween
	var squashed: bool = _enemy.mesh_instance.scale.y < 0.98
	var squash_y: float = _enemy.mesh_instance.scale.y
	await _wait(0.35)  # tween returns to rest
	var restored: bool = absf(_enemy.mesh_instance.scale.y - 1.0) < 0.02
	_record(squashed and restored, "20) hit feedback plays and settles (squash_y=%.3f restored=%s)" % [squash_y, restored])
	await _wait(0.3)


func _test_enemy_is_resource_driven() -> void:
	# M3 exit criterion: the concrete variant is instantiated from a Resource asset,
	# not from values hardcoded on the node.
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 20))
	var st: EnemyData = _enemy.stats
	var has_resource: bool = st != null
	var from_asset: bool = has_resource and st.resource_path.begins_with("res://resources/enemies/")
	var seeded: bool = has_resource and is_equal_approx(_enemy.attack_damage, st.attack_damage) \
		and is_equal_approx(_enemy.detection_range, st.detection_range) \
		and is_equal_approx(_enemy.attack_range, st.attack_range) \
		and is_equal_approx(_enemy.health_component.max_health, st.max_health)
	# instance fields must not write back into the shared definition
	var before: float = st.detection_range if has_resource else 0.0
	_enemy.detection_range = 99.0
	var isolated: bool = has_resource and is_equal_approx(st.detection_range, before)
	_enemy.detection_range = before
	_record(has_resource and from_asset and seeded and isolated, "21) enemy is driven by an EnemyData asset (path=%s seeded=%s isolated=%s)" % [
		st.resource_path if has_resource else "<none>", seeded, isolated])


func _test_death_drop_hook() -> void:
	# Drop hook stub: loot / XP / shadow extraction will subscribe here later.
	_reset_player()
	_reset_enemy(Vector3(0, 0.1, 20))
	var payloads: Array[Node] = []
	var listener: Callable = func(enemy: BasicMeleeEnemy) -> void:
		payloads.append(enemy)
	_enemy.enemy_died.connect(listener)
	_enemy.hurtbox.receive_hit(DamageInfo.new(1000.0, self))
	await _wait(0.2)
	_enemy.enemy_died.disconnect(listener)
	var once: bool = payloads.size() == 1
	var correct_payload: bool = once and payloads[0] == _enemy
	_record(once and correct_payload, "22) death emits the drop hook once with itself (emissions=%d payload_ok=%s)" % [
		payloads.size(), correct_payload])


## Every suite starts from a clean session: PlayerRuntimeState now carries
## progression and health across scene changes, so without this a later test
## would inherit whatever an earlier one left behind.
func _reset_session() -> void:
	var state: Node = get_tree().root.get_node_or_null("PlayerRuntimeState")
	if state != null:
		state.reset_runtime_state()
